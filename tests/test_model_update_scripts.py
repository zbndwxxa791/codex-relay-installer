import json
import os
import shlex
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = Path(os.environ.get("WINDIR", r"C:\Windows")) / "System32" / "WindowsPowerShell" / "v1.0" / "powershell.exe"
CODEX_SCRIPT = ROOT / "installers" / "update-codex-relay-windows.ps1"
CLAUDE_SCRIPT = ROOT / "installers" / "update-claude-code-relay-windows.ps1"
SECRET = "TEST_SECRET_MUST_NOT_APPEAR"


def run_script(script: Path, args: list[str], env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    command = [
        str(POWERSHELL),
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(script),
        *args,
    ]
    return subprocess.run(
        command,
        cwd=ROOT,
        env={**os.environ, **env},
        capture_output=True,
        text=True,
        errors="replace",
        timeout=30,
        check=False,
    )


def write_codex_config(codex_home: Path, model: str = "keep-model") -> Path:
    codex_home.mkdir(parents=True)
    path = codex_home / "config.toml"
    path.write_text(
        f'''model = "{model}"
model_provider = "custom-relay"

[model_providers.custom-relay]
base_url = "https://127.0.0.1:9/v1"
experimental_bearer_token = "{SECRET}"
wire_api = "responses"
''',
        encoding="utf-8",
    )
    return path


def write_claude_settings(claude_home: Path, model: str = "keep-model") -> Path:
    claude_home.mkdir(parents=True)
    path = claude_home / "settings.json"
    path.write_text(
        json.dumps(
            {
                "env": {
                    "ANTHROPIC_BASE_URL": "https://127.0.0.1:9",
                    "ANTHROPIC_AUTH_TOKEN": SECRET,
                    "ANTHROPIC_MODEL": model,
                    "ANTHROPIC_DEFAULT_SONNET_MODEL": "keep-sonnet",
                    "ANTHROPIC_DEFAULT_OPUS_MODEL": "keep-opus",
                    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "keep-haiku",
                },
                "permissions": {"allow": ["Read"]},
            }
        ),
        encoding="utf-8",
    )
    return path


def combined_output(result: subprocess.CompletedProcess[str]) -> str:
    return result.stdout + result.stderr


def test_codex_manual_refresh_deduplicates_and_keeps_default(tmp_path: Path):
    codex_home = tmp_path / "codex"
    config_path = write_codex_config(codex_home)
    (codex_home / "cc-switch-model-catalog.json").write_text(
        json.dumps({"models": [{"slug": "alpha", "display_name": "Friendly Alpha", "context_window": 64000}, {"slug": "old-template", "display_name": "Old", "context_window": 32000}]}),
        encoding="utf-8",
    )

    result = run_script(
        CODEX_SCRIPT,
        ["-Mode", "refresh", "-Models", "zeta,alpha,alpha"],
        {"CODEX_HOME": str(codex_home)},
    )

    assert result.returncode == 0, combined_output(result)
    assert SECRET not in combined_output(result)
    updated_config = config_path.read_text(encoding="utf-8")
    assert 'model = "keep-model"' in updated_config
    assert 'model_catalog_json = "cc-switch-model-catalog.json"' in updated_config
    catalog = json.loads((codex_home / "cc-switch-model-catalog.json").read_text(encoding="utf-8"))
    assert [item["slug"] for item in catalog["models"]] == ["alpha", "zeta"]
    assert catalog["models"][0]["display_name"] == "Friendly Alpha"
    assert catalog["models"][0]["context_window"] == 64000
    assert catalog["models"][1]["context_window"] == 128000
    assert all(item["base_instructions"] for item in catalog["models"])
    assert all(item["supports_reasoning_summaries"] is True for item in catalog["models"])


def test_claude_json_refresh_preserves_defaults_and_metadata(tmp_path: Path):
    claude_home = tmp_path / "claude"
    settings_path = write_claude_settings(claude_home)
    models_path = tmp_path / "models.json"
    models_path.write_text(
        json.dumps(
            {
                "data": [
                    {"id": "zeta", "owned_by": "relay"},
                    {"id": "alpha", "display_name": "Alpha", "context_window": 64000},
                    {"id": "alpha"},
                ]
            }
        ),
        encoding="utf-8",
    )

    result = run_script(
        CLAUDE_SCRIPT,
        ["-Mode", "refresh", "-ModelsFile", str(models_path)],
        {"CLAUDE_CONFIG_DIR": str(claude_home)},
    )

    assert result.returncode == 0, combined_output(result)
    assert SECRET not in combined_output(result)
    settings = json.loads(settings_path.read_text(encoding="utf-8"))
    assert settings["env"]["ANTHROPIC_MODEL"] == "keep-model"
    assert settings["env"]["ANTHROPIC_DEFAULT_SONNET_MODEL"] == "keep-sonnet"
    assert settings["env"]["CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY"] == "1"
    assert settings["permissions"] == {"allow": ["Read"]}
    cache = json.loads((claude_home / "cache" / "gateway-models.json").read_text(encoding="utf-8"))
    assert [item["id"] for item in cache["models"]] == ["alpha", "zeta"]
    assert cache["models"][0]["display_name"] == "Alpha"
    assert cache["models"][0]["context_window"] == 64000
    assert cache["models"][1]["owned_by"] == "relay"


def test_text_and_models_json_import_formats(tmp_path: Path):
    codex_home = tmp_path / "codex"
    write_codex_config(codex_home)
    text_models = tmp_path / "models.txt"
    text_models.write_text("# comment\nzeta\n\nalpha\n", encoding="utf-8")
    codex_result = run_script(
        CODEX_SCRIPT,
        ["-ModelsFile", str(text_models)],
        {"CODEX_HOME": str(codex_home)},
    )
    assert codex_result.returncode == 0, combined_output(codex_result)
    catalog = json.loads((codex_home / "cc-switch-model-catalog.json").read_text(encoding="utf-8"))
    assert [item["slug"] for item in catalog["models"]] == ["alpha", "zeta"]

    claude_home = tmp_path / "claude"
    write_claude_settings(claude_home)
    json_models = tmp_path / "models.json"
    json_models.write_text(
        json.dumps({"models": ["zeta", {"id": "alpha", "display_name": "Alpha"}]}),
        encoding="utf-8",
    )
    claude_result = run_script(
        CLAUDE_SCRIPT,
        ["-ModelsFile", str(json_models)],
        {"CLAUDE_CONFIG_DIR": str(claude_home)},
    )
    assert claude_result.returncode == 0, combined_output(claude_result)
    cache = json.loads((claude_home / "cache" / "gateway-models.json").read_text(encoding="utf-8"))
    assert [item["id"] for item in cache["models"]] == ["alpha", "zeta"]
    assert cache["models"][0]["display_name"] == "Alpha"

def test_manual_source_conflict_and_empty_file_do_not_write(tmp_path: Path):
    codex_home = tmp_path / "codex"
    config_path = write_codex_config(codex_home)
    original = config_path.read_bytes()
    models_path = tmp_path / "models.txt"
    models_path.write_text("alpha\n", encoding="utf-8")

    explicit_empty = run_script(
        CODEX_SCRIPT,
        ["-Models", ""],
        {"CODEX_HOME": str(codex_home)},
    )
    assert explicit_empty.returncode != 0
    assert "Fetching model list" not in combined_output(explicit_empty)
    assert config_path.read_bytes() == original

    explicit_empty_file = run_script(
        CODEX_SCRIPT,
        ["-ModelsFile", ""],
        {"CODEX_HOME": str(codex_home)},
    )
    assert explicit_empty_file.returncode != 0
    assert "Fetching model list" not in combined_output(explicit_empty_file)
    assert config_path.read_bytes() == original

    no_tty = run_script(
        CODEX_SCRIPT,
        ["-Manual"],
        {"CODEX_HOME": str(codex_home)},
    )
    assert no_tty.returncode != 0
    assert "interactive terminal" in combined_output(no_tty)
    assert config_path.read_bytes() == original

    conflict = run_script(
        CODEX_SCRIPT,
        ["-Models", "alpha", "-ModelsFile", str(models_path)],
        {"CODEX_HOME": str(codex_home)},
    )
    assert conflict.returncode != 0
    assert config_path.read_bytes() == original
    assert not (codex_home / "cc-switch-model-catalog.json").exists()

    models_path.write_text("# no models\n\n", encoding="utf-8")
    empty = run_script(
        CODEX_SCRIPT,
        ["-ModelsFile", str(models_path)],
        {"CODEX_HOME": str(codex_home)},
    )
    assert empty.returncode != 0
    assert config_path.read_bytes() == original
    assert not (codex_home / "cc-switch-model-catalog.json").exists()

    custom_config = config_path.read_text(encoding="utf-8").replace('\n[model_providers', "\nmodel_catalog_json = 'nested/cc-switch-model-catalog.json'\n\n[model_providers")
    config_path.write_text(custom_config, encoding="utf-8")
    protected = run_script(
        CODEX_SCRIPT,
        ["-Models", "alpha"],
        {"CODEX_HOME": str(codex_home)},
    )
    assert protected.returncode != 0
    assert config_path.read_text(encoding="utf-8") == custom_config
    assert not (codex_home / "cc-switch-model-catalog.json").exists()

    forced = run_script(
        CODEX_SCRIPT,
        ["-Models", "alpha", "-ReplaceCustomCatalog"],
        {"CODEX_HOME": str(codex_home)},
    )
    assert forced.returncode == 0, combined_output(forced)
    assert 'model_catalog_json = "cc-switch-model-catalog.json"' in config_path.read_text(encoding="utf-8")
    assert (codex_home / "cc-switch-model-catalog.json").exists()


def test_codex_switch_only_reads_and_writes_top_level_toml(tmp_path: Path):
    codex_home = tmp_path / "codex"
    codex_home.mkdir(parents=True)
    config_path = codex_home / "config.toml"
    config_path.write_text(
        f'''model_provider = "custom-relay"

[model_providers.custom-relay]
name = "relay"
base_url = "https://127.0.0.1:9/v1"
experimental_bearer_token = "{SECRET}"

[profiles.work]
model = "profile-model"
model_catalog_json = "profile-catalog.json"
''',
        encoding="utf-8",
    )

    result = run_script(
        CODEX_SCRIPT,
        ["-Mode", "switch", "-Model", "alpha", "-Models", "alpha"],
        {"CODEX_HOME": str(codex_home)},
    )

    assert result.returncode == 0, combined_output(result)
    updated = config_path.read_text(encoding="utf-8")
    top_level = updated.split("[model_providers", 1)[0]
    assert 'model = "alpha"' in top_level
    assert 'model_catalog_json = "cc-switch-model-catalog.json"' in top_level
    assert '[profiles.work]\nmodel = "profile-model"\nmodel_catalog_json = "profile-catalog.json"' in updated

def test_dry_run_is_read_only_and_switch_is_explicit(tmp_path: Path):
    claude_home = tmp_path / "claude"
    settings_path = write_claude_settings(claude_home)
    original = settings_path.read_bytes()

    dry_run = run_script(
        CLAUDE_SCRIPT,
        ["-Mode", "refresh", "-Models", "sonnet-new,opus-new,haiku-new", "-DryRun"],
        {"CLAUDE_CONFIG_DIR": str(claude_home)},
    )
    assert dry_run.returncode == 0, combined_output(dry_run)
    assert settings_path.read_bytes() == original
    assert not (claude_home / "cache" / "gateway-models.json").exists()

    switched = run_script(
        CLAUDE_SCRIPT,
        [
            "-Mode",
            "switch",
            "-Model",
            "sonnet-new",
            "-Models",
            "sonnet-new,opus-new,haiku-new",
        ],
        {"CLAUDE_CONFIG_DIR": str(claude_home)},
    )
    assert switched.returncode == 0, combined_output(switched)
    settings = json.loads(settings_path.read_text(encoding="utf-8"))
    assert settings["env"]["ANTHROPIC_MODEL"] == "sonnet-new"
    assert settings["env"]["ANTHROPIC_DEFAULT_SONNET_MODEL"] == "sonnet-new"
    assert settings["env"]["ANTHROPIC_DEFAULT_OPUS_MODEL"] == "keep-opus"
    assert settings["env"]["ANTHROPIC_DEFAULT_HAIKU_MODEL"] == "keep-haiku"


def test_automatic_fetch_uses_404_fallback_and_bearer_without_leaking_key(tmp_path: Path):
    requests: list[tuple[str, str | None]] = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append((self.path, self.headers.get("Authorization")))
            if self.path == "/api/claude/v1/models":
                self.send_response(404)
                self.end_headers()
                return
            if self.path == "/api/v1/models":
                payload = json.dumps({"data": [{"id": "network-zeta"}, {"id": "network-alpha"}]}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return
            self.send_response(405)
            self.end_headers()

        def log_message(self, _format, *_args):
            return

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        claude_home = tmp_path / "claude"
        settings_path = write_claude_settings(claude_home)
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
        settings["env"]["ANTHROPIC_BASE_URL"] = f"http://127.0.0.1:{server.server_port}/api/claude"
        settings_path.write_text(json.dumps(settings), encoding="utf-8")

        result = run_script(
            CLAUDE_SCRIPT,
            ["-Mode", "refresh", "-NoModelPicker"],
            {"CLAUDE_CONFIG_DIR": str(claude_home)},
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)

    assert result.returncode == 0, combined_output(result)
    assert SECRET not in combined_output(result)
    assert requests[:2] == [
        ("/api/claude/v1/models", f"Bearer {SECRET}"),
        ("/api/v1/models", f"Bearer {SECRET}"),
    ]
    cache = json.loads((claude_home / "cache" / "gateway-models.json").read_text(encoding="utf-8"))
    assert [item["id"] for item in cache["models"]] == ["network-alpha", "network-zeta"]
    updated = json.loads(settings_path.read_text(encoding="utf-8"))
    assert updated["env"]["ANTHROPIC_MODEL"] == "keep-model"


def test_v4_405_fallback_uses_x_api_key(tmp_path: Path):
    requests: list[tuple[str, str | None]] = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append((self.path, self.headers.get("x-api-key")))
            if self.path == "/api/coding/paas/v4/models":
                self.send_response(405)
                self.end_headers()
                return
            if self.path == "/api/coding/paas/v4/v1/models":
                payload = json.dumps({"models": ["v4-model"]}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return
            self.send_response(404)
            self.end_headers()

        def log_message(self, _format, *_args):
            return

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        claude_home = tmp_path / "claude"
        settings_path = write_claude_settings(claude_home)
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
        settings["env"].pop("ANTHROPIC_AUTH_TOKEN")
        settings["env"]["ANTHROPIC_API_KEY"] = SECRET
        settings["env"]["ANTHROPIC_BASE_URL"] = f"http://127.0.0.1:{server.server_port}/api/coding/paas/v4"
        settings_path.write_text(json.dumps(settings), encoding="utf-8")
        result = run_script(
            CLAUDE_SCRIPT,
            ["-Mode", "refresh", "-NoModelPicker"],
            {"CLAUDE_CONFIG_DIR": str(claude_home)},
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)

    assert result.returncode == 0, combined_output(result)
    assert SECRET not in combined_output(result)
    assert requests[:2] == [
        ("/api/coding/paas/v4/models", SECRET),
        ("/api/coding/paas/v4/v1/models", SECRET),
    ]
    cache = json.loads((claude_home / "cache" / "gateway-models.json").read_text(encoding="utf-8"))
    assert [item["id"] for item in cache["models"]] == ["v4-model"]


def test_posix_codex_runtime_parses_multiline_provider_and_v4_fallback(tmp_path: Path):
    bash = Path(r"C:\Program Files\Git\bin\bash.exe")
    if not bash.exists():
        return

    actual_os = subprocess.run(
        [str(bash), "-lc", "uname -s"], capture_output=True, text=True, check=True
    ).stdout.strip()
    source = (ROOT / "installers" / "update-codex-relay-linux.sh").read_text(encoding="utf-8")
    script = tmp_path / "update-codex-test.sh"
    script.write_text(source.replace('TARGET_OS="Linux"', f'TARGET_OS="{actual_os}"'), encoding="utf-8", newline="\n")

    requests: list[str] = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            if self.path == "/api/coding/paas/v4/models":
                self.send_response(405)
                self.end_headers()
                return
            if self.path == "/api/coding/paas/v4/v1/models":
                payload = json.dumps({"data": [{"id": "posix-model"}]}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return
            self.send_response(404)
            self.end_headers()

        def log_message(self, _format, *_args):
            return

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        codex_home = tmp_path / "codex"
        codex_home.mkdir()
        (codex_home / "config.toml").write_text(
            f'''model = "keep-posix"
model_provider = "custom-relay"

[model_providers.custom-relay]
name = "relay"
wire_api = "responses"
base_url = 'http://127.0.0.1:{server.server_port}/api/coding/paas/v4'
env_key = 'RELAY_API_KEY'
''',
            encoding="utf-8",
        )

        def msys_path(path: Path) -> str:
            value = path.resolve().as_posix()
            return f"/{value[0].lower()}{value[2:]}"

        command = " ".join(
            [
                f"export CODEX_HOME={shlex.quote(msys_path(codex_home))};",
                f"export RELAY_API_KEY={shlex.quote(SECRET)};",
                "bash",
                shlex.quote(msys_path(script)),
                "--mode refresh --no-picker",
            ]
        )
        result = subprocess.run(
            [str(bash), "-lc", command],
            cwd=ROOT,
            capture_output=True,
            text=True,
            errors="replace",
            timeout=30,
            check=False,
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)

    assert result.returncode == 0, combined_output(result)
    assert SECRET not in combined_output(result)
    assert requests[:2] == [
        "/api/coding/paas/v4/models",
        "/api/coding/paas/v4/v1/models",
    ]
    catalog = json.loads((codex_home / "cc-switch-model-catalog.json").read_text(encoding="utf-8"))
    assert [item["slug"] for item in catalog["models"]] == ["posix-model"]
    assert 'model = "keep-posix"' in (codex_home / "config.toml").read_text(encoding="utf-8")


def test_all_four_posix_scripts_run_with_manual_source(tmp_path: Path):
    bash = Path(r"C:\Program Files\Git\bin\bash.exe")
    if not bash.exists():
        return
    actual_os = subprocess.run(
        [str(bash), "-lc", "uname -s"], capture_output=True, text=True, check=True
    ).stdout.strip()

    def msys_path(path: Path) -> str:
        value = path.resolve().as_posix()
        return f"/{value[0].lower()}{value[2:]}"

    scripts = [
        "update-codex-relay-macos.sh",
        "update-codex-relay-linux.sh",
        "update-claude-code-relay-macos.sh",
        "update-claude-code-relay-linux.sh",
    ]
    for script_name in scripts:
        source = (ROOT / "installers" / script_name).read_text(encoding="utf-8")
        source = source.replace('TARGET_OS="Darwin"', f'TARGET_OS="{actual_os}"')
        source = source.replace('TARGET_OS="Linux"', f'TARGET_OS="{actual_os}"')
        script = tmp_path / f"test-{script_name}"
        script.write_text(source, encoding="utf-8", newline="\n")
        home = tmp_path / script_name
        home.mkdir()

        if "codex" in script_name and "claude-code" not in script_name:
            (home / "config.toml").write_text(
                '''model = "keep-posix"
model_provider = "custom-relay"

[model_providers.custom-relay]
base_url = "https://127.0.0.1:9/v1"
experimental_bearer_token = "TEST_SECRET_MUST_NOT_APPEAR"
''',
                encoding="utf-8",
            )
            env_export = f"export CODEX_HOME={shlex.quote(msys_path(home))};"
        else:
            (home / "settings.json").write_text(
                json.dumps(
                    {
                        "env": {
                            "ANTHROPIC_BASE_URL": "https://127.0.0.1:9",
                            "ANTHROPIC_AUTH_TOKEN": SECRET,
                            "ANTHROPIC_MODEL": "keep-posix",
                        }
                    }
                ),
                encoding="utf-8",
            )
            env_export = f"export CLAUDE_CONFIG_DIR={shlex.quote(msys_path(home))};"

        command = " ".join(
            [
                env_export,
                "bash",
                shlex.quote(msys_path(script)),
                '--models "zeta,alpha" --no-picker',
            ]
        )
        result = subprocess.run(
            [str(bash), "-lc", command],
            cwd=ROOT,
            capture_output=True,
            text=True,
            errors="replace",
            timeout=30,
            check=False,
        )
        assert result.returncode == 0, f"{script_name}: {combined_output(result)}"
        assert SECRET not in combined_output(result)
        if "codex" in script_name and "claude-code" not in script_name:
            catalog = json.loads((home / "cc-switch-model-catalog.json").read_text(encoding="utf-8"))
            assert [item["slug"] for item in catalog["models"]] == ["alpha", "zeta"]
        else:
            settings = json.loads((home / "settings.json").read_text(encoding="utf-8"))
            assert settings["env"]["ANTHROPIC_MODEL"] == "keep-posix"
            assert settings["env"]["CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY"] == "1"
            cache = json.loads((home / "cache" / "gateway-models.json").read_text(encoding="utf-8"))
            assert [item["id"] for item in cache["models"]] == ["alpha", "zeta"]


def test_windows_rejects_json_scalar_from_network(tmp_path: Path):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            payload = json.dumps("maintenance").encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, _format, *_args):
            return

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        claude_home = tmp_path / "claude"
        settings_path = write_claude_settings(claude_home)
        original = settings_path.read_bytes()
        result = run_script(
            CLAUDE_SCRIPT,
            ["-ModelsUrl", f"http://127.0.0.1:{server.server_port}/v1/models", "-NoModelPicker"],
            {"CLAUDE_CONFIG_DIR": str(claude_home)},
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)

    assert result.returncode != 0
    assert "array or contain a data/models array" in combined_output(result)
    assert settings_path.read_bytes() == original
    assert not (claude_home / "cache" / "gateway-models.json").exists()
