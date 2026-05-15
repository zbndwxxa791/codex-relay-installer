<#
.SYNOPSIS
Configure Codex CLI, Codex Desktop, and the VS Code Codex extension to use an
OpenAI Responses-compatible relay.

.DESCRIPTION
This script writes a managed provider block to $CODEX_HOME/config.toml or
~/.codex/config.toml, stores the relay API key in the current user's environment
as CODEX_RELAY_API_KEY, and creates a timestamped config backup before changes.
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Uninstall,
    [switch]$Restore,
    [switch]$Doctor,
    [switch]$TestConnection,
    [switch]$Benchmark,
    [switch]$ListModels,
    [switch]$NoModelPicker,
    [switch]$SkipCodexCheck,
    [string]$ProviderId = "custom-relay",
    [string]$EnvVarName = "CODEX_RELAY_API_KEY",
    [string]$BaseUrl,
    [string]$Model,
    [int]$RequestTimeoutSec = 30
)

$ErrorActionPreference = "Stop"

$BeginMarker = "# BEGIN CODEX RELAY INSTALLER MANAGED BLOCK"
$EndMarker = "# END CODEX RELAY INSTALLER MANAGED BLOCK"
$DefaultBaseUrl = "https://litellm.blackwhitedeer.studio/v1"

function Write-Step {
    param([string]$Message)
    Write-Host "[codex-relay] $Message"
}

function Write-Warn {
    param([string]$Message)
    Write-Warning "[codex-relay] $Message"
}

function Get-ScriptPathForHelp {
    if ($PSCommandPath) {
        return $PSCommandPath
    }
    if ($MyInvocation.MyCommand.Path) {
        return $MyInvocation.MyCommand.Path
    }
    return "C:\path\to\install for Windows.ps1"
}

function Write-ReRunHints {
    $scriptPath = Get-ScriptPathForHelp
    Write-Step "Use the full installer path for future local runs:"
    Write-Step "  powershell -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Doctor"
    Write-Step "  powershell -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Uninstall"
}

function Get-CodexHome {
    if ($env:CODEX_HOME) {
        return $env:CODEX_HOME
    }
    return (Join-Path $HOME ".codex")
}

function Get-ConfigPath {
    return (Join-Path (Get-CodexHome) "config.toml")
}

function Join-ApiUrl {
    param(
        [string]$BaseUrl,
        [string]$Path
    )

    $base = (Normalize-BaseUrl $BaseUrl)
    $cleanPath = $Path.TrimStart("/")
    return "$base/$cleanPath"
}

function Assert-ProviderId {
    param([string]$Value)
    if ($Value -notmatch '^[A-Za-z0-9_-]+$') {
        throw "ProviderId may only contain letters, numbers, underscore, and dash."
    }
}

function Assert-EnvVarName {
    param([string]$Value)
    if ($Value -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        throw "EnvVarName must be a valid environment variable name."
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
        $secure = Read-Host "Paste your relay API key" -AsSecureString
        $plain = ConvertTo-PlainText $secure
        if ($plain -and $plain.Trim()) {
            return $plain.Trim()
        }
        Write-Warn "API key cannot be empty."
    }
}

function Escape-TomlString {
    param([string]$Value)

    return $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '').Replace("`n", '')
}

function Normalize-BaseUrl {
    param([string]$Value)

    $trimmed = $Value.Trim()
    while ($trimmed.EndsWith('/')) {
        $trimmed = $trimmed.Substring(0, $trimmed.Length - 1)
    }
    if ($trimmed -notmatch '^https?://') {
        Write-Warn "Base URL does not start with http:// or https://. Keeping it exactly as entered."
    }
    return $trimmed
}

function Resolve-BaseUrl {
    param([string]$Value)

    if ($Value -and $Value.Trim()) {
        return Normalize-BaseUrl $Value
    }
    return Normalize-BaseUrl $DefaultBaseUrl
}

function Get-RelayRootUrl {
    param([string]$BaseUrl)

    $normalized = Normalize-BaseUrl $BaseUrl
    if ($normalized -match '/v1$') {
        return $normalized.Substring(0, $normalized.Length - 3)
    }
    return $normalized
}

function Get-ConfigValue {
    param(
        [string]$Content,
        [string]$Key
    )

    $match = [regex]::Match($Content, "(?m)^\s*$([regex]::Escape($Key))\s*=\s*`"([^`"]+)`"")
    if ($match.Success) {
        return $match.Groups[1].Value
    }
    return $null
}

function Get-ProviderBlockValue {
    param(
        [string]$Content,
        [string]$ProviderId,
        [string]$Key
    )

    $providerPattern = [regex]::Escape("[model_providers.$ProviderId]")
    $blockMatch = [regex]::Match($Content, "(?ms)^\s*$providerPattern\s*`$([\s\S]*?)(?=^\s*\[|\z)")
    if (-not $blockMatch.Success) {
        return $null
    }

    return Get-ConfigValue -Content $blockMatch.Groups[1].Value -Key $Key
}

function Get-ConfiguredRelay {
    $configPath = Get-ConfigPath
    if (-not (Test-Path -LiteralPath $configPath)) {
        return [pscustomobject]@{
            ConfigPath = $configPath
            Exists = $false
            Model = $null
            ProviderId = $ProviderId
            BaseUrl = $null
            EnvVarName = $EnvVarName
        }
    }

    $content = Get-Content -LiteralPath $configPath -Raw
    $configuredProviderId = Get-ConfigValue -Content $content -Key "model_provider"
    if (-not $configuredProviderId) {
        $configuredProviderId = $ProviderId
    }

    $configuredEnvVar = Get-ProviderBlockValue -Content $content -ProviderId $configuredProviderId -Key "env_key"
    if (-not $configuredEnvVar) {
        $configuredEnvVar = $EnvVarName
    }

    return [pscustomobject]@{
        ConfigPath = $configPath
        Exists = $true
        Model = Get-ConfigValue -Content $content -Key "model"
        ProviderId = $configuredProviderId
        BaseUrl = Get-ProviderBlockValue -Content $content -ProviderId $configuredProviderId -Key "base_url"
        EnvVarName = $configuredEnvVar
    }
}

function Get-EffectiveEnvValue {
    param([string]$Name)

    $processValue = [Environment]::GetEnvironmentVariable($Name, "Process")
    if ($processValue) {
        return $processValue
    }
    $userValue = [Environment]::GetEnvironmentVariable($Name, "User")
    if ($userValue) {
        return $userValue
    }
    return [Environment]::GetEnvironmentVariable($Name, "Machine")
}

function Get-RelayModels {
    param(
        [string]$BaseUrl,
        [string]$ApiKey
    )

    $headers = @{
        Authorization = "Bearer $ApiKey"
    }
    $url = Join-ApiUrl -BaseUrl $BaseUrl -Path "models"
    $response = Invoke-RestMethod -Method Get -Uri $url -Headers $headers -TimeoutSec $RequestTimeoutSec
    if (-not $response.data) {
        return @()
    }
    return @($response.data | Where-Object { $_.id } | ForEach-Object { [string]$_.id } | Sort-Object -Unique)
}

function Write-HttpStatusHint {
    param(
        [object]$Status,
        [string]$FallbackMessage = "Request failed."
    )

    switch ($status) {
        400 { Write-Warn "HTTP 400: request was rejected. The model name or Responses API compatibility may be wrong." }
        401 { Write-Warn "HTTP 401: API key is missing or invalid." }
        402 { Write-Warn "HTTP 402: quota, balance, or payment limit may be exhausted." }
        403 { Write-Warn "HTTP 403: API key is valid but not allowed to use this resource." }
        404 { Write-Warn "HTTP 404: endpoint not found. Check base URL and make sure it includes the correct /v1 path." }
        429 { Write-Warn "HTTP 429: upstream rate limit or quota was reached." }
        { $_ -ge 500 } { Write-Warn "HTTP ${status}: relay or upstream server error." }
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

function Select-Model {
    param(
        [string]$BaseUrl,
        [string]$ApiKey,
        [string]$RequestedModel
    )

    if ($RequestedModel) {
        return $RequestedModel.Trim()
    }
    if ($DryRun -or $NoModelPicker) {
        return "gpt-5.5"
    }

    try {
        $models = @(Get-RelayModels -BaseUrl $BaseUrl -ApiKey $ApiKey)
        if ($models.Count -gt 0) {
            $defaultModel = if ($models -contains "gpt-5.5") { "gpt-5.5" } else { $models[0] }
            Write-Step "Available models from relay:"
            Show-ModelChoices -Models $models
            $answer = Read-Host "Choose model number/name, or press Enter for $defaultModel"
            if (-not $answer) {
                return $defaultModel
            }
            if ($answer -match '^\d+$') {
                $index = [int]$answer - 1
                if ($index -ge 0 -and $index -lt $models.Count) {
                    return $models[$index]
                }
                Write-Warn "Model number out of range. Using $defaultModel."
                return $defaultModel
            }
            return $answer.Trim()
        }
    }
    catch {
        Write-Warn "Could not fetch model list. Falling back to manual model input."
        Write-HttpFailureHint $_
    }

    $manual = Read-Host "Default model [gpt-5.5]"
    if ($manual) {
        return $manual.Trim()
    }
    return "gpt-5.5"
}

function Test-ResponsesConnection {
    param(
        [string]$BaseUrl,
        [string]$ApiKey,
        [string]$Model
    )

    $headers = @{
        Authorization = "Bearer $ApiKey"
        "Content-Type" = "application/json"
    }
    $body = @{
        model = $Model
        instructions = "Reply with OK only."
        input = "Connectivity test."
        stream = $false
    } | ConvertTo-Json -Depth 4
    $url = Join-ApiUrl -BaseUrl $BaseUrl -Path "responses"
    $null = Invoke-RestMethod -Method Post -Uri $url -Headers $headers -Body $body -TimeoutSec $RequestTimeoutSec
    Write-Step "Responses API test succeeded for model: $Model"
}

function Measure-RelayRequest {
    param(
        [string]$Name,
        [string]$Method,
        [string]$Url,
        [hashtable]$Headers,
        [string]$Body
    )

    $parameters = @{
        Method = $Method
        Uri = $Url
        Headers = $Headers
        TimeoutSec = $RequestTimeoutSec
        UseBasicParsing = $true
    }
    if ($Body) {
        $parameters.Body = $Body
        $parameters.ContentType = "application/json"
    }

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $response = Invoke-WebRequest @parameters
        $timer.Stop()
        return [pscustomobject]@{
            Name = $Name
            Url = $Url
            StatusCode = [int]$response.StatusCode
            ElapsedMs = [Math]::Round($timer.Elapsed.TotalMilliseconds)
            Succeeded = $true
            ErrorMessage = $null
        }
    }
    catch {
        $timer.Stop()
        $status = $null
        if ($_.Exception.Response) {
            try {
                $status = [int]$_.Exception.Response.StatusCode
            }
            catch {
                $status = $null
            }
        }
        return [pscustomobject]@{
            Name = $Name
            Url = $Url
            StatusCode = $status
            ElapsedMs = [Math]::Round($timer.Elapsed.TotalMilliseconds)
            Succeeded = $false
            ErrorMessage = $_.Exception.Message
        }
    }
}

function Write-BenchmarkResult {
    param([pscustomobject]$Result)

    $statusText = if ($null -ne $Result.StatusCode) { $Result.StatusCode } else { "no HTTP status" }
    if ($Result.Succeeded) {
        Write-Step "$($Result.Name): HTTP $statusText in $($Result.ElapsedMs) ms"
    }
    else {
        Write-Warn "$($Result.Name): HTTP $statusText after $($Result.ElapsedMs) ms"
    }
}

function Invoke-Benchmark {
    $resolvedBaseUrl = Resolve-BaseUrl $script:BaseUrl
    $apiKey = if ($DryRun) { "__dry_run_api_key_not_written__" } else { Read-ApiKey }
    $resolvedModel = Select-Model -BaseUrl $resolvedBaseUrl -ApiKey $apiKey -RequestedModel $script:Model

    $modelsUrl = Join-ApiUrl -BaseUrl $resolvedBaseUrl -Path "models"
    $responsesUrl = Join-ApiUrl -BaseUrl $resolvedBaseUrl -Path "responses"
    $spendUrl = "$(Get-RelayRootUrl $resolvedBaseUrl)/global/spend/keys?limit=1"

    if ($DryRun) {
        Write-Step "Would benchmark: $modelsUrl"
        Write-Step "Would benchmark: $responsesUrl"
        Write-Step "Would probe quota/spend endpoint: $spendUrl"
        Write-Step "Would test model: $resolvedModel"
        return
    }

    $headers = @{
        Authorization = "Bearer $apiKey"
        "Content-Type" = "application/json"
    }
    $body = @{
        model = $resolvedModel
        instructions = "Reply with OK only."
        input = "One-time speed and quota probe."
        stream = $false
    } | ConvertTo-Json -Depth 4

    Write-Step "Benchmark base URL: $resolvedBaseUrl"
    Write-Step "Benchmark model: $resolvedModel"

    $modelsResult = Measure-RelayRequest -Name "GET /models speed" -Method "GET" -Url $modelsUrl -Headers $headers
    Write-BenchmarkResult $modelsResult
    if (-not $modelsResult.Succeeded) {
        Write-HttpStatusHint -Status $modelsResult.StatusCode -FallbackMessage $modelsResult.ErrorMessage
    }

    $responsesResult = Measure-RelayRequest -Name "POST /responses speed and quota status" -Method "POST" -Url $responsesUrl -Headers $headers -Body $body
    Write-BenchmarkResult $responsesResult
    if ($responsesResult.Succeeded) {
        Write-Step "Quota status: one minimal Responses request was accepted."
    }
    else {
        Write-HttpStatusHint -Status $responsesResult.StatusCode -FallbackMessage $responsesResult.ErrorMessage
    }

    $spendResult = Measure-RelayRequest -Name "GET /global/spend/keys quota metadata probe" -Method "GET" -Url $spendUrl -Headers $headers
    Write-BenchmarkResult $spendResult
    if ($spendResult.Succeeded) {
        Write-Step "Quota metadata endpoint is reachable for this key."
    }
    else {
        Write-Warn "Quota metadata endpoint is not readable with this key. This is normal for user keys; HTTP 401/403/404 here does not mean the relay request quota failed."
        Write-HttpStatusHint -Status $spendResult.StatusCode -FallbackMessage $spendResult.ErrorMessage
    }

    if (-not $modelsResult.Succeeded -or -not $responsesResult.Succeeded) {
        throw "Benchmark failed for one or more required relay checks."
    }
}

function Invoke-Doctor {
    $relay = Get-ConfiguredRelay
    Write-Step "Codex home: $(Get-CodexHome)"
    Write-Step "Config path: $($relay.ConfigPath)"
    Write-Step "Config exists: $($relay.Exists)"

    $codex = Get-Command codex -ErrorAction SilentlyContinue
    if ($codex) {
        Write-Step "Codex CLI: $($codex.Source)"
        try {
            $version = & $codex.Source --version
            Write-Step "Codex version: $version"
        }
        catch {
            Write-Warn "Codex exists but version check failed."
        }
    }
    else {
        Write-Warn "Codex CLI not found on PATH."
    }

    $effectiveBaseUrl = if ($BaseUrl) { Normalize-BaseUrl $BaseUrl } elseif ($relay.BaseUrl) { $relay.BaseUrl } else { $DefaultBaseUrl }
    $effectiveEnvVar = if ($relay.EnvVarName) { $relay.EnvVarName } else { $EnvVarName }
    $apiKey = Get-EffectiveEnvValue $effectiveEnvVar

    Write-Step "Configured provider: $($relay.ProviderId)"
    Write-Step "Configured model: $($relay.Model)"
    Write-Step "Configured base URL: $effectiveBaseUrl"
    Write-Step "API key env var: $effectiveEnvVar"
    Write-Step "API key visible to this process/user: $([bool]$apiKey)"

    if ($effectiveBaseUrl -and $apiKey) {
        try {
            $models = @(Get-RelayModels -BaseUrl $effectiveBaseUrl -ApiKey $apiKey)
            Write-Step "Models endpoint reachable. Models returned: $($models.Count)"
        }
        catch {
            Write-Warn "Models endpoint check failed."
            Write-HttpFailureHint $_
        }
    }
    else {
        Write-Warn "Skipping network checks because base URL or API key is missing."
    }
}

function Invoke-ListModels {
    $resolvedBaseUrl = Resolve-BaseUrl $script:BaseUrl
    $apiKey = if ($DryRun) { "__dry_run_api_key_not_written__" } else { Read-ApiKey }
    if ($DryRun) {
        Write-Step "Would request: $(Join-ApiUrl -BaseUrl $resolvedBaseUrl -Path "models")"
        return
    }
    $models = @(Get-RelayModels -BaseUrl $resolvedBaseUrl -ApiKey $apiKey)
    if ($models.Count -eq 0) {
        Write-Warn "Models endpoint returned no model IDs."
        return
    }
    Show-ModelChoices -Models $models
}

function Invoke-TestConnection {
    $resolvedBaseUrl = Resolve-BaseUrl $script:BaseUrl
    $apiKey = if ($DryRun) { "__dry_run_api_key_not_written__" } else { Read-ApiKey }
    $resolvedModel = Select-Model -BaseUrl $resolvedBaseUrl -ApiKey $apiKey -RequestedModel $script:Model
    if ($DryRun) {
        Write-Step "Would request: $(Join-ApiUrl -BaseUrl $resolvedBaseUrl -Path "responses")"
        Write-Step "Would test model: $resolvedModel"
        return
    }
    try {
        Test-ResponsesConnection -BaseUrl $resolvedBaseUrl -ApiKey $apiKey -Model $resolvedModel
    }
    catch {
        Write-Warn "Responses API test failed."
        Write-HttpFailureHint $_
        throw
    }
}

function Remove-ManagedConfig {
    param(
        [string]$Content,
        [switch]$RemoveTopLevelDefaults
    )

    if (-not $Content) {
        return ""
    }

    $lines = $Content -split "`r?`n"
    $output = New-Object System.Collections.Generic.List[string]
    $insideManagedBlock = $false
    $insideAnyTable = $false

    foreach ($line in $lines) {
        if ($line -eq $BeginMarker) {
            $insideManagedBlock = $true
            continue
        }
        if ($line -eq $EndMarker) {
            $insideManagedBlock = $false
            continue
        }
        if ($insideManagedBlock) {
            continue
        }

        if ($RemoveTopLevelDefaults -and -not $insideAnyTable -and $line -match '^\s*(model|model_provider)\s*=') {
            continue
        }

        if ($line -match '^\s*\[') {
            $insideAnyTable = $true
        }

        $output.Add($line)
    }

    return (($output -join "`r`n").TrimEnd())
}

function Remove-RelayProviderConfig {
    param(
        [string]$Content,
        [string]$ProviderId
    )

    if (-not $Content) {
        return ""
    }

    $escapedProviderId = [regex]::Escape($ProviderId)
    $providerHeaderPattern = "^\s*\[model_providers\.(?:`"$escapedProviderId`"|$escapedProviderId)\]\s*$"
    $lines = $Content -split "`r?`n"
    $output = New-Object System.Collections.Generic.List[string]
    $insideTargetProvider = $false

    foreach ($line in $lines) {
        if ($line -match '^\s*\[') {
            if ($line -match $providerHeaderPattern) {
                $insideTargetProvider = $true
                continue
            }
            $insideTargetProvider = $false
        }

        if ($insideTargetProvider) {
            continue
        }

        $output.Add($line)
    }

    return (($output -join "`r`n").TrimEnd())
}

function New-ManagedRootBlock {
    param(
        [string]$ProviderId,
        [string]$Model
    )

    $escapedModel = Escape-TomlString $Model

    return @"
$BeginMarker
model = "$escapedModel"
model_provider = "$ProviderId"
$EndMarker
"@
}

function New-ManagedProviderBlock {
    param(
        [string]$ProviderId,
        [string]$EnvVarName,
        [string]$BaseUrl
    )

    $escapedProviderName = Escape-TomlString $ProviderId
    $escapedBaseUrl = Escape-TomlString $BaseUrl
    $escapedEnvVarName = Escape-TomlString $EnvVarName

    return @"
$BeginMarker
[model_providers.$ProviderId]
name = "$escapedProviderName"
base_url = "$escapedBaseUrl"
wire_api = "responses"
env_key = "$escapedEnvVarName"
env_key_instructions = "Set $escapedEnvVarName in your user environment."
$EndMarker
"@
}

function Split-ConfigAtFirstTable {
    param([string]$Content)

    if (-not $Content) {
        return [pscustomobject]@{ Root = ""; Tables = "" }
    }

    $lines = $Content -split "`r?`n"
    $tableIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[') {
            $tableIndex = $i
            break
        }
    }

    if ($tableIndex -lt 0) {
        return [pscustomobject]@{ Root = ($lines -join "`r`n").TrimEnd(); Tables = "" }
    }

    $rootLines = if ($tableIndex -eq 0) { @() } else { $lines[0..($tableIndex - 1)] }
    $tableLines = $lines[$tableIndex..($lines.Count - 1)]

    return [pscustomobject]@{
        Root = ($rootLines -join "`r`n").TrimEnd()
        Tables = ($tableLines -join "`r`n").TrimEnd()
    }
}

function Ensure-WindowsSandboxConfig {
    param([string]$Content)

    $lines = if ($Content) { $Content -split "`r?`n" } else { @() }
    $output = New-Object System.Collections.Generic.List[string]
    $currentTable = ""
    $foundWindowsTable = $false

    foreach ($line in $lines) {
        if ($line -match '^\s*\[([^\]]+)\]\s*$') {
            $currentTable = $matches[1].Trim()
            $output.Add($line)
            if ($currentTable -eq "windows") {
                $foundWindowsTable = $true
                $output.Add('sandbox = "elevated"')
            }
            continue
        }

        if ($line -match '^\s*sandbox\s*=') {
            continue
        }

        $output.Add($line)
    }

    if (-not $foundWindowsTable) {
        if ($output.Count -gt 0 -and $output[$output.Count - 1].Trim()) {
            $output.Add("")
        }
        $output.Add("[windows]")
        $output.Add('sandbox = "elevated"')
    }

    return (($output -join "`r`n").TrimEnd())
}

function Join-ConfigSections {
    param([string[]]$Sections)

    $cleanSections = @()
    foreach ($section in $Sections) {
        if ($section -and $section.Trim()) {
            $cleanSections += $section.Trim()
        }
    }
    return (($cleanSections -join "`r`n`r`n") + "`r`n")
}

function Backup-Config {
    param([string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return $null
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$ConfigPath.backup-$stamp"
    if (-not $DryRun) {
        Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -Force
    }
    return $backupPath
}

function Get-LatestBackup {
    param([string]$ConfigPath)

    $dir = Split-Path -Parent $ConfigPath
    $leaf = Split-Path -Leaf $ConfigPath
    if (-not (Test-Path -LiteralPath $dir)) {
        return $null
    }
    return Get-ChildItem -LiteralPath $dir -Filter "$leaf.backup-*" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Restore-Config {
    param([string]$ConfigPath)

    $backup = Get-LatestBackup $ConfigPath
    if (-not $backup) {
        throw "No backup found for $ConfigPath"
    }

    if ($DryRun) {
        Write-Step "Would restore $ConfigPath from $($backup.FullName)"
        return
    }

    $configDir = Split-Path -Parent $ConfigPath
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    Copy-Item -LiteralPath $backup.FullName -Destination $ConfigPath -Force
    Write-Step "Restored config from $($backup.FullName)"
}

function Ensure-CodexCli {
    if ($SkipCodexCheck) {
        return
    }

    $codex = Get-Command codex -ErrorAction SilentlyContinue
    if ($codex) {
        Write-Step "Found Codex CLI: $($codex.Source)"
        return
    }

    Write-Warn "Codex CLI was not found on PATH."
    $answer = Read-Host "Install Codex CLI now with npm i -g @openai/codex? [y/N]"
    if ($answer -notmatch '^(y|yes)$') {
        Write-Warn "Skipping Codex CLI install. Install it later with: npm i -g @openai/codex"
        return
    }

    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $npm) {
        $npm = Get-Command npm -ErrorAction SilentlyContinue
    }
    if (-not $npm) {
        throw "npm was not found. Install Node.js first, then run: npm i -g @openai/codex"
    }

    if ($DryRun) {
        Write-Step "Would run: npm i -g @openai/codex"
        return
    }

    & $npm.Source i -g "@openai/codex"
}

function Install-RelayConfig {
    Assert-ProviderId $ProviderId
    Assert-EnvVarName $EnvVarName

    $resolvedBaseUrl = Resolve-BaseUrl $script:BaseUrl
    $apiKey = if ($DryRun) { "__dry_run_api_key_not_written__" } else { Read-ApiKey }
    $resolvedModel = Select-Model -BaseUrl $resolvedBaseUrl -ApiKey $apiKey -RequestedModel $script:Model

    Ensure-CodexCli

    $codexHome = Get-CodexHome
    $configPath = Get-ConfigPath

    $existing = if (Test-Path -LiteralPath $configPath) {
        Get-Content -LiteralPath $configPath -Raw
    } else {
        ""
    }

    $clean = Remove-ManagedConfig -Content $existing -RemoveTopLevelDefaults
    $clean = Remove-RelayProviderConfig -Content $clean -ProviderId $ProviderId
    $clean = Ensure-WindowsSandboxConfig $clean
    $split = Split-ConfigAtFirstTable -Content $clean
    $rootBlock = New-ManagedRootBlock -ProviderId $ProviderId -Model $resolvedModel
    $providerBlock = New-ManagedProviderBlock -ProviderId $ProviderId -EnvVarName $EnvVarName -BaseUrl $resolvedBaseUrl
    $nextContent = Join-ConfigSections -Sections @($rootBlock, $split.Root, $split.Tables, $providerBlock)

    if ($DryRun) {
        Write-Step "Would write config to $configPath"
        Write-Host ""
        Write-Host $nextContent
        Write-Step "Would set user environment variable $EnvVarName"
        Write-ReRunHints
        return
    }

    New-Item -ItemType Directory -Path $codexHome -Force | Out-Null
    $backupPath = Backup-Config $configPath
    if ($backupPath) {
        Write-Step "Backed up config to $backupPath"
    }

    Set-Content -LiteralPath $configPath -Value $nextContent -Encoding UTF8 -NoNewline
    [Environment]::SetEnvironmentVariable($EnvVarName, $apiKey, "User")
    Set-Item -Path "Env:$EnvVarName" -Value $apiKey

    Write-Step "Wrote Codex config: $configPath"
    Write-Step "Set user environment variable: $EnvVarName"
    Write-Step "Restart PowerShell, VS Code, and Codex Desktop so they inherit the new environment."
    Write-Step "Try: codex --version ; codex"
    Write-ReRunHints
}

function Uninstall-RelayConfig {
    Assert-EnvVarName $EnvVarName
    $configPath = Get-ConfigPath

    $backup = Get-LatestBackup $configPath
    if ($backup) {
        if ($DryRun) {
            Write-Step "Would restore $configPath from $($backup.FullName)"
        } else {
            Restore-Config $configPath
        }
    }
    elseif (Test-Path -LiteralPath $configPath) {
        $existing = Get-Content -LiteralPath $configPath -Raw
        $clean = Remove-ManagedConfig -Content $existing
        if ($DryRun) {
            Write-Step "Would remove managed block from $configPath"
        } else {
            Set-Content -LiteralPath $configPath -Value "$clean`r`n" -Encoding UTF8 -NoNewline
            Write-Step "Removed managed config block from $configPath"
        }
    }
    else {
        Write-Warn "No config file found at $configPath"
    }

    if ($DryRun) {
        Write-Step "Would clear user environment variable $EnvVarName"
    } else {
        [Environment]::SetEnvironmentVariable($EnvVarName, $null, "User")
        Remove-Item "Env:$EnvVarName" -ErrorAction SilentlyContinue
        Write-Step "Cleared user environment variable: $EnvVarName"
    }
}

$exclusiveModeCount = (@($Restore, $Uninstall, $Doctor, $TestConnection, $Benchmark, $ListModels) | Where-Object { $_ }).Count
if ($exclusiveModeCount -gt 1) {
    throw "Use only one mode at a time: -Restore, -Uninstall, -Doctor, -TestConnection, -Benchmark, or -ListModels."
}

if ($Doctor) {
    Invoke-Doctor
}
elseif ($TestConnection) {
    Invoke-TestConnection
}
elseif ($Benchmark) {
    Invoke-Benchmark
}
elseif ($ListModels) {
    Invoke-ListModels
}
elseif ($Restore) {
    Restore-Config (Get-ConfigPath)
}
elseif ($Uninstall) {
    Uninstall-RelayConfig
}
else {
    Install-RelayConfig
}
