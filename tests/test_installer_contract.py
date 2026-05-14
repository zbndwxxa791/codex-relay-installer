from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read_text(name: str) -> str:
    return (ROOT / name).read_text(encoding="utf-8")


def test_windows_installer_contract():
    text = read_text("install for Windows.ps1")

    assert "param(" in text
    assert "[switch]$DryRun" in text
    assert "[switch]$Uninstall" in text
    assert "[switch]$Restore" in text
    assert "[switch]$Doctor" in text
    assert "[switch]$TestConnection" in text
    assert "[switch]$ListModels" in text
    assert "[switch]$NoModelPicker" in text
    assert "CODEX_RELAY_API_KEY" in text
    assert "wire_api = \"responses\"" in text
    assert "model_provider = \"$ProviderId\"" in text
    assert "[Environment]::SetEnvironmentVariable" in text
    assert "Invoke-RestMethod" in text
    assert "responses" in text
    assert "models" in text
    assert ".backup-" in text
    assert "BEGIN CODEX RELAY INSTALLER MANAGED BLOCK" in text
    assert "END CODEX RELAY INSTALLER MANAGED BLOCK" in text
    assert "experimental_bearer_token" not in text


def test_unix_installer_contract():
    text = read_text("install for Linux&macOS.sh")

    assert "set -euo pipefail" in text
    assert "--dry-run" in text
    assert "--uninstall" in text
    assert "--restore" in text
    assert "--doctor" in text
    assert "--test" in text
    assert "--list-models" in text
    assert "--no-model-picker" in text
    assert "CODEX_RELAY_API_KEY" in text
    assert 'wire_api = "responses"' in text
    assert 'model_provider = "$PROVIDER_ID"' in text
    assert "curl" in text
    assert "responses" in text
    assert "models" in text
    assert ".backup-" in text
    assert "BEGIN CODEX RELAY INSTALLER MANAGED BLOCK" in text
    assert "END CODEX RELAY INSTALLER MANAGED BLOCK" in text
    assert "experimental_bearer_token" not in text


def test_readme_contains_public_distribution_commands():
    text = read_text("README.md")

    assert "install for Windows.ps1" in text
    assert "install for Linux&macOS.sh" in text
    assert "Responses API" in text
    assert "CODEX_RELAY_API_KEY" in text
    assert "--dry-run" in text
    assert "--doctor" in text
    assert "--test" in text
    assert "--list-models" in text
    assert "模型选择" in text
    assert "--restore" in text
    assert "--uninstall" in text
