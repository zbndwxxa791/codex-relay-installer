from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BASE_URL = "https://litellm.blackwhitedeer.studio/v1"


def read_text(name: str) -> str:
    return (ROOT / name).read_text(encoding="utf-8")


def test_windows_installer_contract():
    text = read_text("install for Windows.ps1")

    assert "param(" in text
    assert f'$DefaultBaseUrl = "{DEFAULT_BASE_URL}"' in text
    assert "[switch]$DryRun" in text
    assert "[switch]$Uninstall" in text
    assert "[switch]$Restore" in text
    assert "[switch]$Doctor" in text
    assert "[switch]$TestConnection" in text
    assert "[switch]$Benchmark" in text
    assert "[switch]$ListModels" in text
    assert "[switch]$NoModelPicker" in text
    assert "EnvVarName" not in text
    assert "wire_api = \"responses\"" in text
    assert "model_provider = \"$ProviderId\"" in text
    assert "experimental_bearer_token" in text
    assert "env_key =" not in text
    assert "env_key_instructions" not in text
    assert "[Environment]::SetEnvironmentVariable" not in text
    assert "Invoke-RestMethod" in text
    assert "Invoke-WebRequest" in text
    assert "Find-NpmCommand" in text
    assert "Ensure-NpmAvailable" in text
    assert "OpenJS.NodeJS.LTS" in text
    assert "winget" in text
    assert "Measure-RelayRequest" in text
    assert "Invoke-Benchmark" in text
    assert "Get-ScriptPathForHelp" in text
    assert "Write-ReRunHints" in text
    assert "Ensure-WindowsSandboxConfig" in text
    assert "Remove-RelayProviderConfig" in text
    assert 'sandbox = "elevated"' in text
    assert "spend/keys" in text
    assert "responses" in text
    assert "models" in text
    assert ".backup-" in text
    assert "BEGIN CODEX RELAY INSTALLER MANAGED BLOCK" in text
    assert "END CODEX RELAY INSTALLER MANAGED BLOCK" in text


def test_unix_installer_contract():
    text = read_text("install for Linux&macOS.sh")

    assert "set -euo pipefail" in text
    assert f'DEFAULT_BASE_URL="{DEFAULT_BASE_URL}"' in text
    assert "--dry-run" in text
    assert "--uninstall" in text
    assert "--restore" in text
    assert "--doctor" in text
    assert "--test" in text
    assert "--benchmark" in text
    assert "--list-models" in text
    assert "--no-model-picker" in text
    assert "--env-var-name" not in text
    assert "CODEX_RELAY_API_KEY" not in text
    assert 'wire_api = "responses"' in text
    assert 'model_provider = "$PROVIDER_ID"' in text
    assert "experimental_bearer_token" in text
    assert "env_key =" not in text
    assert "env_key_instructions" not in text
    assert "set_persistent_env" not in text
    assert "curl" in text
    assert "load_nvm_if_available" in text
    assert "ensure_npm_available" in text
    assert "nvm install --lts" in text
    assert "NodeSource" in text
    assert "timed_curl_json" in text
    assert "invoke_benchmark" in text
    assert "script_path_for_help" in text
    assert "print_rerun_hints" in text
    assert "ensure_windows_sandbox_config" in text
    assert "remove_relay_provider_config" in text
    assert 'sandbox = "elevated"' in text
    assert "spend/keys" in text
    assert "responses" in text
    assert "models" in text
    assert ".backup-" in text
    assert "BEGIN CODEX RELAY INSTALLER MANAGED BLOCK" in text
    assert "END CODEX RELAY INSTALLER MANAGED BLOCK" in text


def test_readme_contains_public_distribution_commands():
    text = read_text("README.md")

    assert DEFAULT_BASE_URL in text
    assert "https://relay.example.com/v1" not in text
    assert "install for Windows.ps1" in text
    assert "install for Linux&macOS.sh" in text
    assert "Responses API" in text
    assert "experimental_bearer_token" in text
    assert "CODEX_RELAY_API_KEY" not in text
    assert "--dry-run" in text
    assert "Node.js LTS" in text
    assert "npm" in text
    assert "winget" in text
    assert "nvm" in text
    assert "--doctor" in text
    assert "--test" in text
    assert "--benchmark" in text
    assert "--list-models" in text
    assert "模型选择" in text
    assert "--restore" in text
    assert "--uninstall" in text


def test_readme_uses_full_local_script_paths():
    text = read_text("README.md")

    assert '$installer = "C:\\path\\to\\install for Windows.ps1"' in text
    assert 'installer="/path/to/install for Linux&macOS.sh"' in text
    assert "C:\\Users\\wjj20" not in text
    assert "/c/Users/wjj20" not in text
    assert '-File ".\\install for Windows.ps1"' not in text
    assert 'bash "install for Linux&macOS.sh"' not in text
