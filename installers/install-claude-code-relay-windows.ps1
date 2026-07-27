<#
.SYNOPSIS
Configure Claude Code CLI and the VS Code Claude Code extension to use a
Claude/Anthropic Messages-compatible relay.

.DESCRIPTION
This script writes relay settings to ~/.claude/settings.json. Claude Code CLI
and the VS Code Claude Code extension share this file. The relay API key is
stored under the env object as ANTHROPIC_AUTH_TOKEN, and a timestamped backup is
created before changes.
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Uninstall,
    [switch]$Restore,
    [switch]$Doctor,
    [switch]$TestConnection,
    [switch]$ListModels,
    [switch]$NoModelPicker,
    [switch]$SkipClaudeCheck,
    [string]$BaseUrl,
    [string]$Model,
    [int]$RequestTimeoutSec = 30
)

$ErrorActionPreference = "Stop"

$DefaultBaseUrl = "https://litellm.blackwhitedeer.studio"
$DefaultModel = "gpt-5.5"
$ManagedEnvKeys = @(
    "ANTHROPIC_BASE_URL",
    "ANTHROPIC_AUTH_TOKEN",
    "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY",
    "ANTHROPIC_MODEL",
    "ANTHROPIC_DEFAULT_SONNET_MODEL",
    "ANTHROPIC_DEFAULT_OPUS_MODEL",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL"
)

function Write-Step {
    param([string]$Message)
    Write-Host "[claude-relay] $Message"
}

function Write-Warn {
    param([string]$Message)
    Write-Warning "[claude-relay] $Message"
}

function Get-ScriptPathForHelp {
    if ($PSCommandPath) {
        return $PSCommandPath
    }
    if ($MyInvocation.MyCommand.Path) {
        return $MyInvocation.MyCommand.Path
    }
    return "C:\path\to\install-claude-code-relay-windows.ps1"
}

function Write-ReRunHints {
    $scriptPath = Get-ScriptPathForHelp
    Write-Step "Use the full installer path for future local runs:"
    Write-Step "  powershell -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Doctor"
    Write-Step "  powershell -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -TestConnection"
    Write-Step "  powershell -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Uninstall"
}

function Get-ClaudeHome {
    return (Join-Path $HOME ".claude")
}

function Get-SettingsPath {
    return (Join-Path (Get-ClaudeHome) "settings.json")
}

function Normalize-ClaudeBaseUrl {
    param([string]$Value)

    $resolved = if ($Value -and $Value.Trim()) { $Value.Trim() } else { $DefaultBaseUrl }
    $resolved = $resolved.TrimEnd("/")
    if ($resolved -match "/v1/messages$") {
        $resolved = $resolved.Substring(0, $resolved.Length - "/v1/messages".Length)
    }
    elseif ($resolved -match "/messages$") {
        $resolved = $resolved.Substring(0, $resolved.Length - "/messages".Length)
    }
    elseif ($resolved -match "/v1$") {
        $resolved = $resolved.Substring(0, $resolved.Length - "/v1".Length)
    }
    return $resolved.TrimEnd("/")
}

function Join-ClaudeUrl {
    param(
        [string]$BaseUrl,
        [string]$Path
    )

    $base = Normalize-ClaudeBaseUrl $BaseUrl
    $cleanPath = $Path.TrimStart("/")
    return "$base/v1/$cleanPath"
}

function ConvertTo-PlainText {
    param([SecureString]$SecureValue)

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Read-ApiKey {
    while ($true) {
        $secure = Read-Host "Paste your Claude relay API key" -AsSecureString
        $plain = ConvertTo-PlainText $secure
        if ($plain -and $plain.Trim()) {
            return $plain.Trim()
        }
        Write-Warn "API key cannot be empty."
    }
}

function Read-RequiredValue {
    param(
        [string]$Prompt,
        [string]$CurrentValue
    )

    if ($CurrentValue) {
        return $CurrentValue.Trim()
    }

    while ($true) {
        $value = Read-Host $Prompt
        if ($value -and $value.Trim()) {
            return $value.Trim()
        }
        Write-Warn "Value cannot be empty."
    }
}

function Get-SettingsObject {
    $path = Get-SettingsPath
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{}
    }

    $content = Get-Content -LiteralPath $path -Raw
    if (-not $content.Trim()) {
        return [pscustomobject]@{}
    }
    return $content | ConvertFrom-Json
}

function Ensure-ObjectProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Value
    )

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    }
    else {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Remove-ObjectProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.PSObject.Properties.Remove($Name)
    }
}

function Backup-Settings {
    $path = Get-SettingsPath
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }

    $backup = "$path.backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item -LiteralPath $path -Destination $backup -Force
    return $backup
}

function Write-SettingsObject {
    param([object]$Settings)

    $path = Get-SettingsPath
    $settingsDir = Split-Path -Parent $path
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    $json = $Settings | ConvertTo-Json -Depth 20
    Set-Content -LiteralPath $path -Value ($json + [Environment]::NewLine) -Encoding UTF8
}

function Get-ClaudeRelayConfig {
    $settings = Get-SettingsObject
    $envObject = $settings.env
    if (-not $envObject) {
        return [pscustomobject]@{
            Exists = (Test-Path -LiteralPath (Get-SettingsPath))
            BaseUrl = $null
            ApiKey = $null
            Model = $null
        }
    }

    return [pscustomobject]@{
        Exists = (Test-Path -LiteralPath (Get-SettingsPath))
        BaseUrl = $envObject.ANTHROPIC_BASE_URL
        ApiKey = $envObject.ANTHROPIC_AUTH_TOKEN
        Model = $envObject.ANTHROPIC_MODEL
    }
}

function Write-HttpStatusHint {
    param(
        [object]$Status,
        [string]$FallbackMessage = "Request failed."
    )

    switch ($Status) {
        400 { Write-Warn "HTTP 400: request was rejected. The model name or Anthropic Messages payload may be wrong." }
        401 { Write-Warn "HTTP 401: API key is missing, invalid, or not enabled for this endpoint." }
        402 { Write-Warn "HTTP 402: quota, balance, or payment limit may be exhausted." }
        403 { Write-Warn "HTTP 403: API key is valid but not allowed to use this resource." }
        404 { Write-Warn "HTTP 404: endpoint not found. For Claude Code, use the relay root, not a duplicated /v1 path." }
        429 { Write-Warn "HTTP 429: upstream rate limit or quota was reached." }
        { $_ -ge 500 } { Write-Warn "HTTP ${Status}: relay or upstream server error." }
        default { Write-Warn $FallbackMessage }
    }
}

function Write-HttpFailureHint {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    $status = $null
    if ($ErrorRecord.Exception.Response) {
        try {
            $status = [int]$ErrorRecord.Exception.Response.StatusCode
        }
        catch {
            $status = $null
        }
    }

    Write-HttpStatusHint -Status $status -FallbackMessage $ErrorRecord.Exception.Message
}

function Invoke-CurlJsonRequest {
    param(
        [string]$Method,
        [string]$Url,
        [hashtable]$Headers,
        [string]$Body,
        [string]$ContentType = "application/json"
    )

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) {
        throw "curl.exe was not found."
    }

    $stderrPath = [System.IO.Path]::GetTempFileName()
    $bodyPath = $null
    try {
        $arguments = @(
            "--silent",
            "--show-error",
            "--fail",
            "--ssl-no-revoke",
            "--tlsv1.2",
            "--http1.1",
            "--max-time",
            [string]$RequestTimeoutSec,
            "-X",
            $Method.ToUpperInvariant()
        )

        foreach ($key in $Headers.Keys) {
            $arguments += @("-H", ("{0}: {1}" -f $key, $Headers[$key]))
        }
        if ($ContentType) {
            $arguments += @("-H", "Content-Type: $ContentType")
        }
        if ($Body) {
            $bodyPath = [System.IO.Path]::GetTempFileName()
            Set-Content -LiteralPath $bodyPath -Value $Body -Encoding UTF8
            $arguments += @("--data-binary", "@$bodyPath")
        }
        $arguments += $Url

        $output = & $curl.Source @arguments 2> $stderrPath
        $exitCode = $LASTEXITCODE
        $stderr = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
        $responseText = ($output -join [Environment]::NewLine)
        if ($exitCode -ne 0) {
            $details = if ($stderr -and $stderr.Trim()) { $stderr.Trim() } elseif ($responseText -and $responseText.Trim()) { $responseText.Trim() } else { "curl.exe exited with code $exitCode." }
            throw "curl.exe request failed: $details"
        }
        if (-not $responseText.Trim()) {
            throw "curl.exe returned an empty response."
        }
        return $responseText | ConvertFrom-Json
    }
    finally {
        Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
        if ($bodyPath) {
            Remove-Item -LiteralPath $bodyPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-ClaudeRelayJson {
    param(
        [string]$Method,
        [string]$Url,
        [hashtable]$Headers,
        [string]$Body,
        [string]$ContentType = "application/json"
    )

    $parameters = @{
        Method = $Method
        Uri = $Url
        Headers = $Headers
        TimeoutSec = $RequestTimeoutSec
    }
    if ($Body) {
        $parameters.Body = $Body
        $parameters.ContentType = $ContentType
    }

    try {
        return Invoke-RestMethod @parameters
    }
    catch {
        $primaryMessage = $_.Exception.Message
        if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
            throw
        }

        Write-Warn "PowerShell request failed; retrying with curl.exe. $primaryMessage"
        try {
            return Invoke-CurlJsonRequest -Method $Method -Url $Url -Headers $Headers -Body $Body -ContentType $ContentType
        }
        catch {
            throw "PowerShell request failed: $primaryMessage; curl.exe fallback failed: $($_.Exception.Message)"
        }
    }
}

function Get-ClaudeModels {
    param(
        [string]$BaseUrl,
        [string]$ApiKey
    )

    $headers = @{
        Authorization = "Bearer $ApiKey"
    }
    $url = Join-ClaudeUrl -BaseUrl $BaseUrl -Path "models"
    $response = Invoke-ClaudeRelayJson -Method Get -Url $url -Headers $headers
    if (-not $response.data) {
        return @()
    }
    return @($response.data | Where-Object { $_.id } | ForEach-Object { [string]$_.id } | Sort-Object -Unique)
}

function Show-ModelChoices {
    param([string[]]$Models)

    $limit = [Math]::Min($Models.Count, 30)
    for ($i = 0; $i -lt $limit; $i++) {
        Write-Host ("  {0,2}. {1}" -f ($i + 1), $Models[$i])
    }
    if ($Models.Count -gt $limit) {
        Write-Step "Showing first $limit of $($Models.Count) models."
    }
}

function Select-ClaudeModel {
    param(
        [string]$BaseUrl,
        [string]$ApiKey,
        [string]$RequestedModel
    )

    if ($RequestedModel) {
        return $RequestedModel.Trim()
    }
    if ($DryRun -or $NoModelPicker) {
        return $DefaultModel
    }

    try {
        $models = @(Get-ClaudeModels -BaseUrl $BaseUrl -ApiKey $ApiKey)
        if ($models.Count -gt 0) {
            $default = if ($models -contains $DefaultModel) { $DefaultModel } else { $models[0] }
            Write-Step "Available models from relay:"
            Show-ModelChoices -Models $models
            $answer = Read-Host "Choose model number/name, or press Enter for $default"
            if (-not $answer) {
                return $default
            }
            if ($answer -match '^\d+$') {
                $index = [int]$answer - 1
                if ($index -ge 0 -and $index -lt $models.Count) {
                    return $models[$index]
                }
                Write-Warn "Model number out of range. Using $default."
                return $default
            }
            return $answer.Trim()
        }
    }
    catch {
        Write-Warn "Could not fetch model list. Falling back to manual model input."
        Write-HttpFailureHint $_
    }

    $manual = Read-Host "Default model [$DefaultModel]"
    if ($manual) {
        return $manual.Trim()
    }
    return $DefaultModel
}

function Test-ClaudeMessagesConnection {
    param(
        [string]$BaseUrl,
        [string]$ApiKey,
        [string]$Model
    )

    $headers = @{
        Authorization = "Bearer $ApiKey"
        "anthropic-version" = "2023-06-01"
    }
    $body = @{
        model = $Model
        max_tokens = 16
        messages = @(
            @{
                role = "user"
                content = "Reply with OK only."
            }
        )
    } | ConvertTo-Json -Depth 6
    $url = Join-ClaudeUrl -BaseUrl $BaseUrl -Path "messages"
    $response = Invoke-ClaudeRelayJson -Method Post -Url $url -Headers $headers -Body $body -ContentType "application/json"
    if ($response.type -ne "message" -or -not $response.content) {
        throw "Relay returned a response, but it did not look like an Anthropic Messages response."
    }
    Write-Step "Anthropic Messages test succeeded for model: $Model"
}

function Find-NpmCommand {
    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($npm) {
        return $npm
    }

    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if ($npm) {
        return $npm
    }

    $candidateDirs = @()
    if ($env:ProgramFiles) {
        $candidateDirs += (Join-Path $env:ProgramFiles "nodejs")
    }
    ${env:ProgramFiles(x86)} | ForEach-Object {
        if ($_) {
            $candidateDirs += (Join-Path $_ "nodejs")
        }
    }

    foreach ($dir in $candidateDirs) {
        $candidate = Join-Path $dir "npm.cmd"
        if (Test-Path -LiteralPath $candidate) {
            if ($env:PATH -notlike "*$dir*") {
                $env:PATH = "$dir;$env:PATH"
            }
            return Get-Command $candidate -ErrorAction SilentlyContinue
        }
    }

    return $null
}

function Find-WingetCommand {
    return (Get-Command winget -ErrorAction SilentlyContinue)
}

function Install-NodeRuntime {
    if ($DryRun) {
        Write-Step "Would install Node.js LTS with winget package OpenJS.NodeJS.LTS if npm is missing."
        return
    }

    $winget = Find-WingetCommand
    if (-not $winget) {
        throw "npm was not found and winget is unavailable. Install Node.js LTS from https://nodejs.org/, restart PowerShell, then rerun this installer."
    }

    $answer = Read-Host "npm was not found. Install Node.js LTS now with winget (OpenJS.NodeJS.LTS)? [y/N]"
    if ($answer -notmatch '^(y|yes)$') {
        throw "Node.js and npm are required to install Claude Code CLI. Install Node.js LTS, restart PowerShell, then rerun this installer."
    }

    & $winget.Source install -e --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "winget failed to install Node.js LTS. Install Node.js LTS from https://nodejs.org/, restart PowerShell, then rerun this installer."
    }
}

function Ensure-NpmAvailable {
    $npm = Find-NpmCommand
    if ($npm) {
        return $npm
    }

    Write-Warn "npm was not found. Node.js LTS is required before Claude Code CLI can be installed."
    Install-NodeRuntime

    $npm = Find-NpmCommand
    if ($npm) {
        return $npm
    }

    throw "Node.js LTS installation finished, but npm is not available in this PowerShell session. Open a new PowerShell window and rerun this installer."
}

function Ensure-ClaudeCli {
    if ($SkipClaudeCheck) {
        return
    }

    $claude = Get-Command claude -ErrorAction SilentlyContinue
    if ($claude) {
        Write-Step "Found Claude CLI: $($claude.Source)"
        try {
            $version = & $claude.Source --version
            if ($version) {
                Write-Step "Claude CLI version: $version"
            }
        }
        catch {
            Write-Warn "Claude CLI was found, but version check failed."
        }
        return
    }

    Write-Warn "Claude CLI was not found on PATH."
    $answer = Read-Host "Install Claude Code CLI now with the official Windows command (irm https://claude.ai/install.ps1 | iex)? [y/N]"
    if ($answer -notmatch '^(y|yes)$') {
        Write-Warn "Skipping Claude Code CLI install. Install it later with: powershell -ExecutionPolicy Bypass -Command `"irm https://claude.ai/install.ps1 | iex`""
        return
    }

    if ($DryRun) {
        Write-Step "Would run: powershell -ExecutionPolicy Bypass -Command `"irm https://claude.ai/install.ps1 | iex`""
        return
    }

    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://claude.ai/install.ps1 | iex"
    if ($LASTEXITCODE -ne 0) {
        throw "Official Claude Code installer failed. Rerun the official command or check network access to https://claude.ai/install.ps1."
    }
}

function Invoke-Doctor {
    $settingsPath = Get-SettingsPath
    $relay = Get-ClaudeRelayConfig
    $effectiveBaseUrl = if ($BaseUrl) { Normalize-ClaudeBaseUrl $BaseUrl } elseif ($relay.BaseUrl) { Normalize-ClaudeBaseUrl $relay.BaseUrl } else { $DefaultBaseUrl }
    $apiKey = $relay.ApiKey
    $model = if ($Model) { $Model } elseif ($relay.Model) { $relay.Model } else { $DefaultModel }

    Write-Step "Claude home: $(Get-ClaudeHome)"
    Write-Step "Settings path: $settingsPath"
    Write-Step "Settings exists: $(Test-Path -LiteralPath $settingsPath)"
    Write-Step "Configured base URL: $effectiveBaseUrl"
    Write-Step "API key stored in settings: $([bool]$apiKey)"
    Write-Step "Configured model: $model"
    Ensure-ClaudeCli

    if ($apiKey) {
        try {
            $models = @(Get-ClaudeModels -BaseUrl $effectiveBaseUrl -ApiKey $apiKey)
            Write-Step "Model endpoint reachable. Model count: $($models.Count)"
        }
        catch {
            Write-Warn "Model endpoint check failed."
            Write-HttpFailureHint $_
        }
    }
    else {
        Write-Warn "No API key found in settings; skipping authenticated relay check."
    }
}

function Invoke-ListModels {
    $resolvedBaseUrl = Normalize-ClaudeBaseUrl (Read-RequiredValue -Prompt "Claude relay base URL" -CurrentValue $BaseUrl)
    $apiKey = if ($DryRun) { "__dry_run_api_key_not_written__" } else { Read-ApiKey }
    if ($DryRun) {
        Write-Step "Would request: $(Join-ClaudeUrl -BaseUrl $resolvedBaseUrl -Path "models")"
        return
    }

    $models = @(Get-ClaudeModels -BaseUrl $resolvedBaseUrl -ApiKey $apiKey)
    if ($models.Count -eq 0) {
        Write-Warn "No models returned."
        return
    }
    Show-ModelChoices -Models $models
}

function Invoke-TestConnection {
    $resolvedBaseUrl = Normalize-ClaudeBaseUrl (Read-RequiredValue -Prompt "Claude relay base URL" -CurrentValue $BaseUrl)
    $apiKey = if ($DryRun) { "__dry_run_api_key_not_written__" } else { Read-ApiKey }
    $resolvedModel = Select-ClaudeModel -BaseUrl $resolvedBaseUrl -ApiKey $apiKey -RequestedModel $Model
    if ($DryRun) {
        Write-Step "Would request: $(Join-ClaudeUrl -BaseUrl $resolvedBaseUrl -Path "models")"
        Write-Step "Would request: $(Join-ClaudeUrl -BaseUrl $resolvedBaseUrl -Path "messages")"
        Write-Step "Would test model: $resolvedModel"
        return
    }

    $null = Get-ClaudeModels -BaseUrl $resolvedBaseUrl -ApiKey $apiKey
    Test-ClaudeMessagesConnection -BaseUrl $resolvedBaseUrl -ApiKey $apiKey -Model $resolvedModel
}

function Invoke-Restore {
    $settingsPath = Get-SettingsPath
    $backup = Get-ChildItem -LiteralPath (Split-Path -Parent $settingsPath) -Filter "settings.json.backup-*" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $backup) {
        Write-Warn "No backup found."
        return
    }

    if ($DryRun) {
        Write-Step "Would restore: $($backup.FullName) -> $settingsPath"
        return
    }

    Copy-Item -LiteralPath $backup.FullName -Destination $settingsPath -Force
    Write-Step "Restored latest backup: $($backup.FullName)"
}

function Invoke-Uninstall {
    $settingsPath = Get-SettingsPath
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        Write-Step "Settings file does not exist; nothing to uninstall."
        return
    }

    $settings = Get-SettingsObject
    if (-not $settings.env) {
        Write-Step "Settings file has no env block; nothing to uninstall."
        return
    }

    if ($DryRun) {
        Write-Step "Would remove Claude relay env keys from: $settingsPath"
        return
    }

    $backup = Backup-Settings
    foreach ($key in $ManagedEnvKeys) {
        Remove-ObjectProperty -Object $settings.env -Name $key
    }
    Write-SettingsObject -Settings $settings
    if ($backup) {
        Write-Step "Backup created: $backup"
    }
    Write-Step "Removed Claude relay env keys from settings.json."
}

function Invoke-Install {
    Ensure-NpmAvailable
    Ensure-ClaudeCli

    $resolvedBaseUrl = Normalize-ClaudeBaseUrl (Read-RequiredValue -Prompt "Claude relay base URL [$DefaultBaseUrl]" -CurrentValue $BaseUrl)
    $apiKey = if ($DryRun) { "__dry_run_api_key_not_written__" } else { Read-ApiKey }
    $resolvedModel = Select-ClaudeModel -BaseUrl $resolvedBaseUrl -ApiKey $apiKey -RequestedModel $Model

    if (-not $DryRun) {
        Test-ClaudeMessagesConnection -BaseUrl $resolvedBaseUrl -ApiKey $apiKey -Model $resolvedModel
    }

    $settingsPath = Get-SettingsPath
    if ($DryRun) {
        Write-Step "Would write Claude Code settings to: $settingsPath"
        Write-Step "Base URL: $resolvedBaseUrl"
        Write-Step "Model: $resolvedModel"
        Write-Step "API key would be stored as ANTHROPIC_AUTH_TOKEN."
        return
    }

    $backup = Backup-Settings
    $settings = Get-SettingsObject
    if (-not $settings.env) {
        Ensure-ObjectProperty -Object $settings -Name "env" -Value ([pscustomobject]@{})
    }

    Ensure-ObjectProperty -Object $settings.env -Name "ANTHROPIC_BASE_URL" -Value $resolvedBaseUrl
    Ensure-ObjectProperty -Object $settings.env -Name "ANTHROPIC_AUTH_TOKEN" -Value $apiKey
    Ensure-ObjectProperty -Object $settings.env -Name "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY" -Value "1"
    Ensure-ObjectProperty -Object $settings.env -Name "ANTHROPIC_MODEL" -Value $resolvedModel
    Ensure-ObjectProperty -Object $settings.env -Name "ANTHROPIC_DEFAULT_SONNET_MODEL" -Value $resolvedModel
    Ensure-ObjectProperty -Object $settings.env -Name "ANTHROPIC_DEFAULT_OPUS_MODEL" -Value $resolvedModel
    Ensure-ObjectProperty -Object $settings.env -Name "ANTHROPIC_DEFAULT_HAIKU_MODEL" -Value $resolvedModel

    Write-SettingsObject -Settings $settings
    if ($backup) {
        Write-Step "Backup created: $backup"
    }
    Write-Step "Wrote Claude Code settings: $settingsPath"
    Write-Step "Base URL: $resolvedBaseUrl"
    Write-Step "Model: $resolvedModel"
    Write-Step "Restart VS Code and Claude Code so they reload ~/.claude/settings.json."
    Write-Step "Try: claude --version ; claude"
    Write-ReRunHints
}

if ($Restore) {
    Invoke-Restore
    return
}
if ($Uninstall) {
    Invoke-Uninstall
    return
}
if ($Doctor) {
    Invoke-Doctor
    return
}
if ($ListModels) {
    Invoke-ListModels
    return
}
if ($TestConnection) {
    Invoke-TestConnection
    return
}

Invoke-Install
