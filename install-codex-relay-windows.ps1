<#
Compatibility wrapper. The maintained Windows installer lives under installers/.
#>
$ErrorActionPreference = "Stop"
$target = Join-Path $PSScriptRoot "installers\install-codex-relay-windows.ps1"
if (-not (Test-Path -LiteralPath $target)) {
    throw "Installer not found: $target"
}
& powershell -NoProfile -ExecutionPolicy Bypass -File $target @args
exit $LASTEXITCODE
