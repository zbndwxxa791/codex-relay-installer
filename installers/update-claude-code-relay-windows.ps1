<#
.SYNOPSIS
Refresh the custom relay model list for Claude Code on Windows.

.DESCRIPTION
Fetches an OpenAI-compatible /v1/models response or accepts a manual model
list, enables Claude Code gateway model discovery, and maintains the legacy
~/.claude/cache/gateway-models.json compatibility cache. Refresh never changes
the current default model.
#>

[CmdletBinding()]
param(
    [ValidateSet("refresh", "list", "switch")]
    [string]$Mode = "refresh",
    [string]$Model,
    [string[]]$Models,
    [string]$ModelsFile,
    [switch]$Manual,
    [string]$BaseUrl,
    [string]$ApiKey,
    [string]$ModelsUrl,
    [ValidateSet("auto", "bearer", "x-api-key")]
    [string]$AuthMode = "auto",
    [string]$UserAgent,
    [ValidateRange(1, 600)]
    [int]$RequestTimeoutSec = 15,
    [switch]$DryRun,
    [switch]$ListModels,
    [switch]$NoModelPicker
)

$ErrorActionPreference = "Stop"
$DefaultBaseUrl = "https://litellm.blackwhitedeer.studio"
$DiscoveryKey = "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY"

function Write-Step([string]$Message) { Write-Host "[claude-models] $Message" }
function Write-Warn([string]$Message) { Write-Warning "[claude-models] $Message" }

function Get-ClaudeHomePath {
    if ($env:CLAUDE_CONFIG_DIR -and $env:CLAUDE_CONFIG_DIR.Trim()) { return $env:CLAUDE_CONFIG_DIR.Trim() }
    return (Join-Path $env:USERPROFILE ".claude")
}

function Get-ClaudeSettingsPath { return (Join-Path (Get-ClaudeHomePath) "settings.json") }
function Get-ClaudeCachePath { return (Join-Path (Get-ClaudeHomePath) "cache\gateway-models.json") }

function ConvertTo-PlainText([Security.SecureString]$SecureValue) {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function Read-ApiKeyInteractive {
    if ([Console]::IsInputRedirected) { throw "No API key was found and stdin is redirected. Pass -ApiKey." }
    $secureValue = Read-Host "Paste relay API key" -AsSecureString
    $plainValue = ConvertTo-PlainText $secureValue
    if (-not $plainValue -or -not $plainValue.Trim()) { throw "API key cannot be empty." }
    return $plainValue.Trim()
}

function Assert-ModelId([string]$Id) {
    if (-not $Id -or -not $Id.Trim()) { throw "Model ID cannot be empty." }
    if ($Id -match '[\x00-\x1F\x7F]') { throw "Model ID contains a control character." }
    return $Id.Trim()
}

function ConvertTo-ModelRecords([object[]]$Items) {
    $recordsById = [ordered]@{}
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        if ($item -is [string]) {
            $modelId = Assert-ModelId ([string]$item)
            $record = [pscustomobject]@{ id = $modelId; display_name = $modelId; owned_by = $null; context_window = $null }
        }
        else {
            $modelId = Assert-ModelId ([string]$item.id)
            $displayName = if ($item.display_name) { [string]$item.display_name } elseif ($item.displayName) { [string]$item.displayName } else { $modelId }
            $contextWindow = $null
            if ($item.context_window) { $contextWindow = [int64]$item.context_window }
            elseif ($item.contextWindow) { $contextWindow = [int64]$item.contextWindow }
            if ($contextWindow -and $contextWindow -lt 1) { throw "context_window for '$modelId' must be positive." }
            $record = [pscustomobject]@{
                id = $modelId
                display_name = $displayName
                owned_by = if ($item.owned_by) { [string]$item.owned_by } else { $null }
                context_window = $contextWindow
            }
        }
        if (-not $recordsById.Contains($modelId)) { $recordsById[$modelId] = $record }
    }
    $result = @($recordsById.Values | Sort-Object -Property id)
    if ($result.Count -eq 0) { throw "No valid models were supplied." }
    return $result
}

function Read-ModelsFromFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Models file not found: $Path" }
    $content = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path))
    if (-not $content.Trim()) { throw "Models file is empty: $Path" }
    $trimmed = $content.TrimStart()
    if ($trimmed.StartsWith("[") -or $trimmed.StartsWith("{")) {
        try { $parsed = $content | ConvertFrom-Json }
        catch { throw "Models file is not valid JSON: $($_.Exception.Message)" }
        if ($null -ne $parsed.data) { return ConvertTo-ModelRecords @($parsed.data) }
        if ($null -ne $parsed.models) { return ConvertTo-ModelRecords @($parsed.models) }
        return ConvertTo-ModelRecords @($parsed)
    }
    $items = @()
    foreach ($line in ($content -split "\r?\n")) {
        $value = $line.Trim()
        if ($value -and -not $value.StartsWith("#")) { $items += $value }
    }
    return ConvertTo-ModelRecords $items
}

function Read-ModelsInteractive {
    if ([Console]::IsInputRedirected) { throw "-Manual requires an interactive terminal." }
    Write-Step "Enter one model ID per line. Submit an empty line to finish."
    $items = @()
    while ($true) {
        $value = Read-Host "Model ID"
        if (-not $value) { break }
        $items += $value
    }
    return ConvertTo-ModelRecords $items
}

function Read-ModelsArgument([string[]]$Values) {
    $items = @()
    foreach ($value in @($Values)) {
        foreach ($part in ([string]$value -split ',')) {
            if ($part.Trim()) { $items += $part.Trim() }
        }
    }
    return ConvertTo-ModelRecords $items
}

function Add-EndpointCandidate([Collections.Generic.List[string]]$List, [Collections.Generic.HashSet[string]]$Seen, [string]$Value) {
    if ($Value -and $List.Count -lt 3 -and $Seen.Add($Value)) { $List.Add($Value) }
}

function Get-ModelsEndpointCandidates([string]$RelayBaseUrl, [string]$OverrideUrl) {
    $list = New-Object 'Collections.Generic.List[string]'
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    if ($OverrideUrl -and $OverrideUrl.Trim()) {
        Add-EndpointCandidate $list $seen $OverrideUrl.Trim()
        return $list.ToArray()
    }
    $normalized = $RelayBaseUrl.Trim().TrimEnd('/')
    if (-not $normalized) { throw "Base URL cannot be empty." }
    if ($normalized -match '/v([0-9]+)$') {
        Add-EndpointCandidate $list $seen "$normalized/models"
        if ($Matches[1] -ne "1") { Add-EndpointCandidate $list $seen "$normalized/v1/models" }
    }
    else { Add-EndpointCandidate $list $seen "$normalized/v1/models" }

    $suffixes = @('/api/claudecode','/api/anthropic','/apps/anthropic','/api/coding','/claudecode','/anthropic','/step_plan','/coding','/claude')
    foreach ($suffix in $suffixes) {
        if ($normalized.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase)) {
            $root = $normalized.Substring(0, $normalized.Length - $suffix.Length).TrimEnd('/')
            Add-EndpointCandidate $list $seen "$root/v1/models"
            Add-EndpointCandidate $list $seen "$root/models"
            break
        }
    }
    return $list.ToArray()
}

function Get-StatusCodeFromError([Management.Automation.ErrorRecord]$ErrorRecord) {
    try { return [int]$ErrorRecord.Exception.Response.StatusCode }
    catch { return 0 }
}

function Invoke-ModelsRequest([string]$Url, [string]$ResolvedApiKey, [string]$ResolvedAuthMode) {
    $requestHeaders = @{ Accept = "application/json" }
    if ($UserAgent) { $requestHeaders["User-Agent"] = $UserAgent }
    if ($ResolvedApiKey) {
        if ($ResolvedAuthMode -eq "x-api-key") { $requestHeaders["x-api-key"] = $ResolvedApiKey }
        else { $requestHeaders["Authorization"] = "Bearer $ResolvedApiKey" }
    }
    try {
        $response = Invoke-WebRequest -Uri $Url -Headers $requestHeaders -Method Get -UseBasicParsing -TimeoutSec $RequestTimeoutSec
        return [pscustomobject]@{ Status = [int]$response.StatusCode; Content = [string]$response.Content }
    }
    catch { return [pscustomobject]@{ Status = (Get-StatusCodeFromError $_); Content = $null } }
}

function Get-SafeUrlForLog([string]$Url, [string]$Secret) {
    try {
        $builder = New-Object UriBuilder($Url)
        $builder.UserName = ""
        $builder.Password = ""
        $builder.Query = ""
        $builder.Fragment = ""
        $safeUrl = $builder.Uri.AbsoluteUri
        if ($Secret) { $safeUrl = $safeUrl.Replace($Secret, "<redacted>") }
        return $safeUrl
    }
    catch { return "<invalid URL>" }
}
function Get-RemoteModelRecords([string]$RelayBaseUrl, [string]$ResolvedApiKey, [string]$ResolvedAuthMode) {
    $lastFailure = "No endpoint was attempted."
    foreach ($endpoint in (Get-ModelsEndpointCandidates $RelayBaseUrl $ModelsUrl)) {
        $safeEndpoint = Get-SafeUrlForLog $endpoint $ResolvedApiKey
        Write-Step "Fetching model list: $safeEndpoint"
        $result = Invoke-ModelsRequest $endpoint $ResolvedApiKey $ResolvedAuthMode
        if ($result.Status -eq 200) {
            try { $payload = $result.Content | ConvertFrom-Json }
            catch { throw "Model endpoint returned invalid JSON." }
            $trimmedResponse = $result.Content.TrimStart()
            if ($trimmedResponse.StartsWith("[")) { $items = @($payload) }
            elseif ($trimmedResponse.StartsWith("{") -and $payload.PSObject.Properties.Name -contains "data" -and $payload.data -is [Array]) { $items = @($payload.data) }
            elseif ($trimmedResponse.StartsWith("{") -and $payload.PSObject.Properties.Name -contains "models" -and $payload.models -is [Array]) { $items = @($payload.models) }
            else { throw "Model endpoint JSON must be an array or contain a data/models array." }
            return ConvertTo-ModelRecords $items
        }
        if ($result.Status -eq 404 -or $result.Status -eq 405) {
            $lastFailure = "HTTP $($result.Status) from $safeEndpoint"
            continue
        }
        if ($result.Status) { throw "Model endpoint returned HTTP $($result.Status)." }
        throw "Model endpoint request failed. Check connectivity, Base URL, and authentication."
    }
    throw "$lastFailure. Pass -Models, -ModelsFile, or -Manual to update without the network."
}

function Ensure-ObjectProperty([object]$Object, [string]$Name, [object]$Value) {
    if ($Object.PSObject.Properties.Name -contains $Name) { $Object.$Name = $Value }
    else { $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value }
}

function Read-ClaudeSettings {
    $settingsPath = Get-ClaudeSettingsPath
    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        try { $settings = [IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json }
        catch { throw "Claude settings are not valid JSON: $settingsPath" }
    }
    else { $settings = [pscustomobject]@{} }
    if (-not ($settings.PSObject.Properties.Name -contains "env") -or $null -eq $settings.env) {
        Ensure-ObjectProperty $settings "env" ([pscustomobject]@{})
    }
    $resolvedBaseUrl = if ($BaseUrl) { $BaseUrl.Trim() } elseif ($settings.env.ANTHROPIC_BASE_URL) { [string]$settings.env.ANTHROPIC_BASE_URL } else { $DefaultBaseUrl }
    $resolvedApiKey = $null
    $detectedAuthMode = "bearer"
    if ($ApiKey) { $resolvedApiKey = $ApiKey.Trim() }
    elseif ($settings.env.ANTHROPIC_AUTH_TOKEN) { $resolvedApiKey = [string]$settings.env.ANTHROPIC_AUTH_TOKEN; $detectedAuthMode = "bearer" }
    elseif ($settings.env.ANTHROPIC_API_KEY) { $resolvedApiKey = [string]$settings.env.ANTHROPIC_API_KEY; $detectedAuthMode = "x-api-key" }
    return [pscustomobject]@{
        Path = $settingsPath
        Settings = $settings
        BaseUrl = $resolvedBaseUrl.TrimEnd('/')
        ApiKey = $resolvedApiKey
        AuthMode = if ($AuthMode -eq "auto") { $detectedAuthMode } else { $AuthMode }
        CurrentModel = [string]$settings.env.ANTHROPIC_MODEL
    }
}

function Backup-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmssfff"
    $backupPath = "$Path.backup-$stamp"
    Copy-Item -LiteralPath $Path -Destination $backupPath
    return $backupPath
}

function Save-Utf8Atomic([string]$Path, [string]$Content) {
    $directory = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporaryPath = "$Path.tmp.$([Guid]::NewGuid().ToString('N'))"
    $utf8NoBom = New-Object Text.UTF8Encoding($false)
    try {
        [IO.File]::WriteAllText($temporaryPath, $Content, $utf8NoBom)
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
}

function Show-Models([object[]]$ModelRecords) {
    for ($index = 0; $index -lt $ModelRecords.Count; $index++) { Write-Host ("{0,4}. {1}" -f ($index + 1), $ModelRecords[$index].id) }
}

function Select-ModelId([object[]]$ModelRecords, [string]$CurrentModel) {
    if ($Model) {
        $selected = Assert-ModelId $Model
        if (-not ($ModelRecords.id -contains $selected)) { Write-Warn "Model '$selected' is not in the supplied list; writing it anyway." }
        return $selected
    }
    if ($NoModelPicker) {
        if ($CurrentModel) { return $CurrentModel }
        return $ModelRecords[0].id
    }
    if ([Console]::IsInputRedirected) { throw "switch mode requires -Model or -NoModelPicker when stdin is redirected." }
    Show-Models $ModelRecords
    $defaultModel = if ($CurrentModel -and ($ModelRecords.id -contains $CurrentModel)) { $CurrentModel } else { $ModelRecords[0].id }
    $answer = Read-Host "Choose model number/name, or press Enter for $defaultModel"
    if (-not $answer) { return $defaultModel }
    if ($answer -match '^\d+$') {
        $position = [int]$answer - 1
        if ($position -lt 0 -or $position -ge $ModelRecords.Count) { throw "Model number is out of range." }
        return $ModelRecords[$position].id
    }
    return (Assert-ModelId $answer)
}

$modelsProvided = $PSBoundParameters.ContainsKey("Models")
$modelsFileProvided = $PSBoundParameters.ContainsKey("ModelsFile")
$manualSourceCount = 0
if ($modelsProvided) { $manualSourceCount++ }
if ($modelsFileProvided) { $manualSourceCount++ }
if ($Manual) { $manualSourceCount++ }
if ($manualSourceCount -gt 1) { throw "Use only one manual source: -Models, -ModelsFile, or -Manual." }

$runMode = if ($ListModels) { "list" } elseif ($Model) { "switch" } else { $Mode }
$relay = Read-ClaudeSettings
if ($modelsProvided) { $modelRecords = @(Read-ModelsArgument $Models) }
elseif ($modelsFileProvided) { $modelRecords = @(Read-ModelsFromFile $ModelsFile) }
elseif ($Manual) { $modelRecords = @(Read-ModelsInteractive) }
else {
    $resolvedApiKey = $relay.ApiKey
    if (-not $resolvedApiKey) { $resolvedApiKey = Read-ApiKeyInteractive }
    $modelRecords = @(Get-RemoteModelRecords $relay.BaseUrl $resolvedApiKey $relay.AuthMode)
}

Write-Step "Resolved $($modelRecords.Count) model(s)."
if ($runMode -eq "list") { Show-Models $modelRecords; exit 0 }

$settings = $relay.Settings
Ensure-ObjectProperty $settings.env $DiscoveryKey "1"
$selectedModel = $null
if ($runMode -eq "switch") {
    $selectedModel = Select-ModelId $modelRecords $relay.CurrentModel
    Ensure-ObjectProperty $settings.env "ANTHROPIC_MODEL" $selectedModel
    $familyAliases = [ordered]@{
        sonnet = "ANTHROPIC_DEFAULT_SONNET_MODEL"
        opus = "ANTHROPIC_DEFAULT_OPUS_MODEL"
        haiku = "ANTHROPIC_DEFAULT_HAIKU_MODEL"
    }
    $selectedFamily = @($familyAliases.Keys) | Where-Object { $selectedModel.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0 } | Select-Object -First 1
    if ($selectedFamily) { Ensure-ObjectProperty $settings.env $familyAliases[$selectedFamily] $selectedModel }
}

$settingsJson = ($settings | ConvertTo-Json -Depth 100) + [Environment]::NewLine
$cacheModels = @()
foreach ($record in $modelRecords) {
    $cacheEntry = [ordered]@{ id = $record.id; display_name = $record.display_name }
    if ($record.owned_by) { $cacheEntry.owned_by = $record.owned_by }
    if ($record.context_window) { $cacheEntry.context_window = $record.context_window }
    $cacheModels += $cacheEntry
}
$cachePayload = [ordered]@{
    baseUrl = $relay.BaseUrl
    fetchedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    models = $cacheModels
}
$cacheJson = ($cachePayload | ConvertTo-Json -Depth 100) + [Environment]::NewLine

if ($DryRun) {
    Write-Step "Dry run: would update $($relay.Path) and $(Get-ClaudeCachePath)."
    if ($selectedModel) { Write-Step "Dry run: would switch default model to $selectedModel." }
    exit 0
}

$settingsBackup = Backup-File $relay.Path
$cacheBackup = Backup-File (Get-ClaudeCachePath)
if ($settingsBackup) { Write-Step "Settings backup: $settingsBackup" }
if ($cacheBackup) { Write-Step "Cache backup: $cacheBackup" }
Save-Utf8Atomic $relay.Path $settingsJson
Save-Utf8Atomic (Get-ClaudeCachePath) $cacheJson
Write-Step "Gateway discovery enabled: $DiscoveryKey=1"
Write-Step "Compatibility cache updated: $(Get-ClaudeCachePath)"
if ($selectedModel) { Write-Step "Default model updated to: $selectedModel" }
else { Write-Step "Current default model unchanged: $($relay.CurrentModel)" }
Write-Step "Restart Claude Code or the VS Code Claude Code extension to reload the model list."
