import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INSTALLERS = ROOT / "installers"
DEFAULT_CODEX_BASE_URL = "https://litellm.blackwhitedeer.studio/v1"
DEFAULT_CLAUDE_BASE_URL = "https://litellm.blackwhitedeer.studio"

CODEX_INSTALLERS = {
    "windows": "installers/install-codex-relay-windows.ps1",
    "macos": "installers/install-codex-relay-macos.sh",
    "linux": "installers/install-codex-relay-linux.sh",
}
CLAUDE_INSTALLERS = {
    "windows": "installers/install-claude-code-relay-windows.ps1",
    "macos": "installers/install-claude-code-relay-macos.sh",
    "linux": "installers/install-claude-code-relay-linux.sh",
}
ALL_INSTALLERS = {**CODEX_INSTALLERS, **{f"claude-{k}": v for k, v in CLAUDE_INSTALLERS.items()}}
CODEX_MODEL_UPDATERS = {
    "windows": "installers/update-codex-relay-windows.ps1",
    "macos": "installers/update-codex-relay-macos.sh",
    "linux": "installers/update-codex-relay-linux.sh",
}
CLAUDE_MODEL_UPDATERS = {
    "windows": "installers/update-claude-code-relay-windows.ps1",
    "macos": "installers/update-claude-code-relay-macos.sh",
    "linux": "installers/update-claude-code-relay-linux.sh",
}
ALL_MODEL_UPDATERS = {
    **CODEX_MODEL_UPDATERS,
    **{f"claude-{k}": v for k, v in CLAUDE_MODEL_UPDATERS.items()},
}


def read_text(name: str) -> str:
    return (ROOT / name).read_text(encoding="utf-8")


def test_six_platform_installers_exist_under_installers_directory():
    expected = sorted([*CODEX_INSTALLERS.values(), *CLAUDE_INSTALLERS.values()])
    actual = sorted(
        str(path.relative_to(ROOT)).replace("\\", "/")
        for path in INSTALLERS.iterdir()
        if path.name.startswith("install-")
    )

    assert actual == expected
    assert (INSTALLERS / "README.md").is_file()

def test_six_platform_model_updaters_exist_under_installers_directory():
    expected = sorted([*CODEX_MODEL_UPDATERS.values(), *CLAUDE_MODEL_UPDATERS.values()])
    actual = sorted(
        str(path.relative_to(ROOT)).replace("\\", "/")
        for path in INSTALLERS.iterdir()
        if path.name.startswith("update-")
    )

    assert actual == expected
    assert not (ROOT / "update-relay-model-windows.ps1").exists()
    assert not (ROOT / "update-relay-model-linux-macos.sh").exists()

def test_root_scripts_are_compatibility_wrappers():
    wrappers = {
        "install-codex-relay-windows.ps1": "installers\\install-codex-relay-windows.ps1",
        "install-claude-code-relay-windows.ps1": "installers\\install-claude-code-relay-windows.ps1",
        "install-codex-relay-linux-macos.sh": "installers/install-codex-relay-",
        "install-claude-code-relay-linux-macos.sh": "installers/install-claude-code-relay-",
    }

    for wrapper, target_fragment in wrappers.items():
        text = read_text(wrapper)
        assert target_fragment in text
        assert "installers" in text

    assert "@args" in read_text("install-codex-relay-windows.ps1")
    assert '"$@"' in read_text("install-codex-relay-linux-macos.sh")


def test_codex_installers_use_responses_protocol_and_official_cli_commands():
    for os_name, script in CODEX_INSTALLERS.items():
        text = read_text(script)
        assert DEFAULT_CODEX_BASE_URL in text
        assert 'wire_api = "responses"' in text
        assert "experimental_bearer_token" in text
        assert "ANTHROPIC_BASE_URL" not in text
        assert "ANTHROPIC_AUTH_TOKEN" not in text
        assert "CODEX_RELAY_API_KEY" not in text
        assert "env_key =" not in text
        assert "env_key_instructions" not in text
        assert "npm install -g @openai/codex" not in text
        assert "@openai/codex" not in text

        if os_name == "windows":
            assert "irm https://chatgpt.com/codex/install.ps1 | iex" in text
            assert "Ensure-NpmAvailable" in text
            assert "OpenJS.NodeJS.LTS" in text
            assert re.search(r"Install-RelayConfig \{\n\s+Assert-ProviderId.*\n\n\s+Ensure-NpmAvailable\n\s+Ensure-GitAvailable\n\s+Ensure-CodexCli", text)
        else:
            assert "curl -fsSL https://chatgpt.com/codex/install.sh | sh" in text
            assert "ensure_npm_available" in text
            assert re.search(r"install_relay_config\(\) \{\n\s+assert_provider_id\n\n\s+ensure_npm_available\n\s+ensure_git_available\n\s+ensure_codex_cli", text)


def test_claude_installers_use_anthropic_messages_gateway_and_official_cli_commands():
    for os_name, script in CLAUDE_INSTALLERS.items():
        text = read_text(script)
        assert DEFAULT_CLAUDE_BASE_URL in text
        assert f'DEFAULT_BASE_URL="{DEFAULT_CLAUDE_BASE_URL}"' in text or f'$DefaultBaseUrl = "{DEFAULT_CLAUDE_BASE_URL}"' in text
        assert 'https://litellm.blackwhitedeer.studio/v1"' not in text
        assert "ANTHROPIC_BASE_URL" in text
        assert "ANTHROPIC_AUTH_TOKEN" in text
        assert "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY" in text
        assert "ANTHROPIC_DEFAULT_SONNET_MODEL" in text
        assert "anthropic-version" in text
        assert "messages" in text
        assert "wire_api" not in text
        assert "experimental_bearer_token" not in text
        assert "npm install -g @anthropic-ai/claude-code" not in text
        assert "@anthropic-ai/claude-code" not in text

        if os_name == "windows":
            assert "irm https://claude.ai/install.ps1 | iex" in text
            assert "Ensure-NpmAvailable" in text
            assert re.search(r"Invoke-Install \{\n\s+Ensure-NpmAvailable\n\s+Ensure-ClaudeCli", text)
        else:
            assert "curl -fsSL https://claude.ai/install.sh | bash" in text
            assert "require_json_editor" in text
            assert re.search(r"invoke_install\(\) \{\n\s+local base api_key model path\n\s+require_json_editor\n\s+ensure_claude_cli", text)


def test_platform_scripts_use_native_node_install_paths():
    assert "winget" in read_text(CODEX_INSTALLERS["windows"])
    assert "OpenJS.NodeJS.LTS" in read_text(CODEX_INSTALLERS["windows"])
    assert "nodejs.org/dist/index.tab" in read_text(CODEX_INSTALLERS["macos"])
    assert "sudo installer -pkg" in read_text(CODEX_INSTALLERS["macos"])
    assert "deb.nodesource.com/setup_lts.x" in read_text(CODEX_INSTALLERS["linux"])
    assert "rpm.nodesource.com/setup_lts.x" in read_text(CODEX_INSTALLERS["linux"])

    assert "winget" in read_text(CLAUDE_INSTALLERS["windows"])
    assert "OpenJS.NodeJS.LTS" in read_text(CLAUDE_INSTALLERS["windows"])
    assert "nodejs.org/dist/index.tab" in read_text(CLAUDE_INSTALLERS["macos"])
    assert "sudo installer -pkg" in read_text(CLAUDE_INSTALLERS["macos"])
    assert "deb.nodesource.com/setup_lts.x" in read_text(CLAUDE_INSTALLERS["linux"])
    assert "rpm.nodesource.com/setup_lts.x" in read_text(CLAUDE_INSTALLERS["linux"])


def test_platform_scripts_guard_against_wrong_os():
    assert 'TARGET_OS="Darwin"' in read_text(CODEX_INSTALLERS["macos"])
    assert 'TARGET_OS="Linux"' in read_text(CODEX_INSTALLERS["linux"])
    assert 'TARGET_OS="Darwin"' in read_text(CLAUDE_INSTALLERS["macos"])
    assert 'TARGET_OS="Linux"' in read_text(CLAUDE_INSTALLERS["linux"])

    assert "ensure_target_os" in read_text(CODEX_INSTALLERS["macos"])
    assert "ensure_target_os" in read_text(CODEX_INSTALLERS["linux"])
    assert "ensure_target_os" in read_text(CLAUDE_INSTALLERS["macos"])
    assert "ensure_target_os" in read_text(CLAUDE_INSTALLERS["linux"])


def test_installers_do_not_write_proxy_or_use_acceleration_mirrors():
    banned = [
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "ghproxy",
        "gh.llkk.cc",
        "hub.gitmirror",
        "registry.npmmirror.com",
    ]

    for script in [*CODEX_INSTALLERS.values(), *CLAUDE_INSTALLERS.values()]:
        text = read_text(script)
        for token in banned:
            assert token not in text, f"{script} unexpectedly contains {token}"


def test_readme_documents_six_public_commands_and_protocols():
    text = read_text("README.md")

    for script in [*CODEX_INSTALLERS.values(), *CLAUDE_INSTALLERS.values()]:
        assert script in text
        assert f"https://your-domain.example/{script}" in text
        assert f"https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/{script}" in text

    assert "OpenAI Responses API" in text
    assert "Anthropic Messages" in text
    assert 'wire_api = "responses"' in text
    assert "ANTHROPIC_BASE_URL" in text
    assert "ANTHROPIC_AUTH_TOKEN" in text
    assert "experimental_bearer_token" in text
    assert "脚本不会内置客户 API key" in text
    assert "终端里按提示输入" in text
    assert "不写代理环境变量" in text
    assert "npm 包安装" not in text


def test_installers_readme_is_customer_facing():
    text = read_text("installers/README.md")

    for script in [*CODEX_INSTALLERS.values(), *CLAUDE_INSTALLERS.values()]:
        assert Path(script).name in text

    assert "面向正在安装 Codex 或 Claude Code 中转配置的用户" in text
    assert "准备好你的 relay API key" in text
    assert "请从下载页复制与你系统和工具匹配的命令" in text
    assert "Node.js、CLI 安装、模型选择和配置写入都会由脚本自动完成" in text
    assert "<脚本下载地址>" in text
    assert "curl -fsSL \"<脚本下载地址>\" | bash" in text
    assert "Invoke-RestMethod '<脚本下载地址>'" in text
    assert "~/.codex/config.toml" in text
    assert "~/.claude/settings.json" in text
    assert "Remote SSH" in text
    assert "your-domain.example" not in text
    assert "GitHub raw" not in text
    assert "你自己网站" not in text
    assert "你的安装脚本" not in text
    assert ' -o "${TMPDIR' not in text
    for heading in [
        "## Windows Codex 手动配置",
        "## macOS Codex 手动配置",
        "## Linux Codex 手动配置",
        "## Windows Claude Code 手动配置",
        "## macOS Claude Code 手动配置",
        "## Linux Claude Code 手动配置",
    ]:
        assert heading in text

    assert r"C:\Users\<你的用户名>\.codex\config.toml" in text
    assert "/Users/<你的用户名>/.codex/config.toml" in text
    assert "/home/<你的用户名>/.codex/config.toml" in text
    assert r"C:\Users\<你的用户名>\.claude\settings.json" in text
    assert "/Users/<你的用户名>/.claude/settings.json" in text
    assert "/home/<你的用户名>/.claude/settings.json" in text
    assert text.count('wire_api = "responses"') == 3
    assert text.count('experimental_bearer_token = "替换成你的 relay API key"') == 3
    assert text.count('"ANTHROPIC_BASE_URL": "https://litellm.blackwhitedeer.studio"') >= 3
    assert text.count('"ANTHROPIC_AUTH_TOKEN": "替换成你的 relay API key"') >= 3
    assert text.count('"CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1"') >= 3
    assert 'sandbox = "elevated"' in text
    assert "把下面内容粘到 `config.toml`" in text
    assert "把下面内容粘到 `settings.json`" in text


def test_docs_reference_split_platform_scripts():
    docs = {
        "claude-code-relay-installation.md": read_text("claude-code-relay-installation.md"),
        "claude-code-server-debug.md": read_text("claude-code-server-debug.md"),
        "codex-server-debug.md": read_text("codex-server-debug.md"),
    }

    assert "installers/install-claude-code-relay-linux.sh" in docs["claude-code-relay-installation.md"]
    assert "installers/install-claude-code-relay-macos.sh" in docs["claude-code-relay-installation.md"]
    assert "installers/install-claude-code-relay-linux.sh" in docs["claude-code-server-debug.md"]
    assert "installers/install-claude-code-relay-macos.sh" in docs["claude-code-server-debug.md"]
    assert "installers/install-codex-relay-linux.sh" in docs["codex-server-debug.md"]
    assert "install-codex-relay-linux-macos.sh" not in "\n".join(docs.values())
    assert "install-claude-code-relay-linux-macos.sh" not in "\n".join(docs.values())


def test_windows_installers_do_not_assign_reserved_powershell_variables():
    reserved_names = "home|host|pid|pshome|pwd"
    assignment_pattern = re.compile(rf"^\s*\$({reserved_names})\s*=", re.IGNORECASE | re.MULTILINE)

    for script_name in [CODEX_INSTALLERS["windows"], CLAUDE_INSTALLERS["windows"]]:
        text = read_text(script_name)
        match = assignment_pattern.search(text)
        assert match is None, f"{script_name} assigns reserved PowerShell variable ${match.group(1)}"


def test_model_update_scripts_expose_manual_and_safe_update_contracts():
    reserved_names = "home|host|pid|pshome|pwd"
    assignment_pattern = re.compile(rf"^\s*\$({reserved_names})\s*=", re.IGNORECASE | re.MULTILINE)
    for os_name, script_name in ALL_MODEL_UPDATERS.items():
        text = read_text(script_name)
        assert "refresh" in text
        assert "list" in text
        assert "switch" in text
        assert "models-file" in text.lower() or "ModelsFile" in text
        assert "manual" in text.lower()
        assert "dry-run" in text.lower() or "DryRun" in text
        assert "/v1/models" in text
        assert "404" in text
        assert "405" in text

        if os_name.endswith("windows") or os_name == "windows":
            assert "ModelsFile" in text
            assert "ReplaceCustomCatalog" in text or "claude-" in script_name
            match = assignment_pattern.search(text)
            assert match is None, f"{script_name} assigns reserved PowerShell variable ${match.group(1)}"
        else:
            assert "--models-file" in text
            assert "--manual" in text
            assert "--dry-run" in text

    for script_name in CODEX_MODEL_UPDATERS.values():
        text = read_text(script_name)
        assert "cc-switch-model-catalog.json" in text
        assert "model_catalog_json" in text
        assert "models_cache.json" in text
        assert "base_instructions" in text
        assert "supports_reasoning_summaries" in text
        assert "128000" in text

    for script_name in CLAUDE_MODEL_UPDATERS.values():
        text = read_text(script_name)
        assert "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY" in text
        assert "gateway-models.json" in text
        assert "ANTHROPIC_MODEL" in text
        assert "ANTHROPIC_DEFAULT_SONNET_MODEL" in text
        assert "ANTHROPIC_DEFAULT_OPUS_MODEL" in text
        assert "ANTHROPIC_DEFAULT_HAIKU_MODEL" in text


def test_model_update_scripts_are_platform_specific():
    assert 'TARGET_OS="Darwin"' in read_text(CODEX_MODEL_UPDATERS["macos"])
    assert 'TARGET_OS="Linux"' in read_text(CODEX_MODEL_UPDATERS["linux"])
    assert 'TARGET_OS="Darwin"' in read_text(CLAUDE_MODEL_UPDATERS["macos"])
    assert 'TARGET_OS="Linux"' in read_text(CLAUDE_MODEL_UPDATERS["linux"])


def test_readmes_document_six_model_updaters_and_manual_sources():
    root_readme = read_text("README.md")
    customer_readme = read_text("installers/README.md")

    for script_name in ALL_MODEL_UPDATERS.values():
        assert script_name in root_readme
        assert Path(script_name).name in customer_readme

    for text in (root_readme, customer_readme):
        assert "cc-switch-model-catalog.json" in text
        assert "gateway-models.json" in text
        assert "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY" in text
        assert "--models-file" in text
        assert "--manual" in text
        assert "ModelsFile" in text
        assert "Manual" in text
