<#
.SYNOPSIS
Refresh the custom relay model list for Codex on Windows.

.DESCRIPTION
Fetches an OpenAI-compatible /v1/models response or accepts a manual model
list, writes ~/.codex/cc-switch-model-catalog.json, and points config.toml at
that catalog. Refresh is the default and never changes the current model.
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
    [string]$ProviderId,
    [ValidateSet("auto", "bearer", "x-api-key")]
    [string]$AuthMode = "auto",
    [string]$UserAgent,
    [ValidateRange(1, 600)]
    [int]$RequestTimeoutSec = 15,
    [switch]$DryRun,
    [switch]$ListModels,
    [switch]$NoModelPicker,
    [switch]$ReplaceCustomCatalog
)

$ErrorActionPreference = "Stop"
$DefaultBaseUrl = "https://litellm.blackwhitedeer.studio/v1"
$DefaultProviderId = "custom-relay"
$CatalogFileName = "cc-switch-model-catalog.json"
$DefaultContextWindow = 128000

function Write-Step([string]$Message) { Write-Host "[codex-models] $Message" }
function Write-Warn([string]$Message) { Write-Warning "[codex-models] $Message" }

function Get-CodexHomePath {
    if ($env:CODEX_HOME -and $env:CODEX_HOME.Trim()) { return $env:CODEX_HOME.Trim() }
    return (Join-Path $env:USERPROFILE ".codex")
}

function Get-CodexConfigPath { return (Join-Path (Get-CodexHomePath) "config.toml") }
function Get-CodexCachePath { return (Join-Path (Get-CodexHomePath) "models_cache.json") }
function Get-CodexCatalogPath { return (Join-Path (Get-CodexHomePath) $CatalogFileName) }

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
            $record = [pscustomobject]@{ id = $modelId; display_name = $modelId; display_name_explicit = $false; owned_by = $null; context_window = $null }
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
                display_name_explicit = [bool]($item.display_name -or $item.displayName)
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
        if ($Matches[1] -ne "1") {
            Add-EndpointCandidate $list $seen "$normalized/v1/models"
        }
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
        return [pscustomobject]@{ Status = [int]$response.StatusCode; Content = [string]$response.Content; Error = $null }
    }
    catch {
        return [pscustomobject]@{ Status = (Get-StatusCodeFromError $_); Content = $null; Error = $_.Exception.Message }
    }
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

function Get-TomlTopLevelValue([string]$Content, [string]$Key) {
    $section = [regex]::Match($Content, "(?m)^\s*\[")
    $topLevel = if ($section.Success) { $Content.Substring(0, $section.Index) } else { $Content }
    $pattern = '(?m)^\s*' + [regex]::Escape($Key) + '\s*=\s*(?<quote>["''])(?<value>(?:\\.|[^"''])*)\k<quote>\s*$'
    $match = [regex]::Match($topLevel, $pattern)
    if ($match.Success) { return $match.Groups['value'].Value -replace '\\"','"' -replace '\\\\','\' }
    return $null
}
function Get-CodexProviderValue([string]$Content, [string]$ResolvedProviderId, [string]$Key) {
    $escapedProvider = [regex]::Escape($ResolvedProviderId)
    $sectionPattern = '(?ms)^\s*\[model_providers\.(?:"' + $escapedProvider + '"|' + $escapedProvider + ')\]\s*\r?\n(?<body>.*?)(?=^\s*\[|\z)'; $section = [regex]::Match($Content, $sectionPattern)
    if (-not $section.Success) { return $null }
    $valuePattern = '(?m)^\s*' + [regex]::Escape($Key) + '\s*=\s*(?<quote>["''])(?<value>(?:\\.|[^"''])*)\k<quote>\s*$'
    $value = [regex]::Match($section.Groups['body'].Value, $valuePattern)
    if ($value.Success) { return $value.Groups['value'].Value -replace '\\"','"' -replace '\\\\','\' }
    return $null
}

function Read-CodexConfig {
    $configPath = Get-CodexConfigPath
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw "Codex config not found: $configPath" }
    $content = [IO.File]::ReadAllText($configPath)
    $resolvedProviderId = if ($ProviderId) { $ProviderId.Trim() } else { Get-TomlTopLevelValue $content "model_provider" }
    if (-not $resolvedProviderId) { $resolvedProviderId = $DefaultProviderId }
    $resolvedBaseUrl = if ($BaseUrl) { $BaseUrl.Trim() } else { Get-CodexProviderValue $content $resolvedProviderId "base_url" }
    if (-not $resolvedBaseUrl) { $resolvedBaseUrl = $DefaultBaseUrl }
    $resolvedApiKey = if ($ApiKey) { $ApiKey.Trim() } else { Get-CodexProviderValue $content $resolvedProviderId "experimental_bearer_token" }
    if (-not $resolvedApiKey) {
        $envKeyName = Get-CodexProviderValue $content $resolvedProviderId "env_key"
        if ($envKeyName) { $resolvedApiKey = [Environment]::GetEnvironmentVariable($envKeyName) }
    }
    return [pscustomobject]@{
        Path = $configPath
        Content = $content
        ProviderId = $resolvedProviderId
        BaseUrl = $resolvedBaseUrl.TrimEnd('/')
        ApiKey = $resolvedApiKey
        CurrentModel = Get-TomlTopLevelValue $content "model"
        CatalogReference = Get-TomlTopLevelValue $content "model_catalog_json"
    }
}

function Copy-JsonObject([object]$Value) {
    if ($null -eq $Value) { return $null }
    return (($Value | ConvertTo-Json -Depth 100) | ConvertFrom-Json)
}

function Ensure-ObjectProperty([object]$Object, [string]$Name, [object]$Value) {
    if ($Object.PSObject.Properties.Name -contains $Name) {
        if ($null -eq $Object.$Name) { $Object.$Name = $Value }
    }
    else { $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value }
}

function New-FallbackCatalogEntry {
    return [pscustomobject][ordered]@{
        slug = "relay-model"
        display_name = "relay-model"
        description = "Custom relay model"
        default_reasoning_level = "medium"
        supported_reasoning_levels = @(
            [ordered]@{ effort = "low"; description = "Fast responses with lighter reasoning" },
            [ordered]@{ effort = "medium"; description = "Balanced reasoning" },
            [ordered]@{ effort = "high"; description = "Greater reasoning depth" },
            [ordered]@{ effort = "xhigh"; description = "Extra high reasoning depth" }
        )
        shell_type = "shell_command"
        visibility = "list"
        supported_in_api = $true
        priority = 0
        additional_speed_tiers = @()
        service_tiers = @()
        availability_nux = $null
        upgrade = $null
        base_instructions = "You are Codex, a coding agent."
        model_messages = $null
        include_skills_usage_instructions = $true
        supports_reasoning_summaries = $true
        default_reasoning_summary = "auto"
        support_verbosity = $true
        default_verbosity = "medium"
        apply_patch_tool_type = "freeform"
        web_search_tool_type = "text_and_image"
        truncation_policy = [ordered]@{ mode = "tokens"; limit = 10000 }
        supports_parallel_tool_calls = $true
        supports_image_detail_original = $true
        context_window = $DefaultContextWindow
        max_context_window = $DefaultContextWindow
        effective_context_window_percent = 95
        experimental_supported_tools = @()
        input_modalities = @("text", "image")
        supports_search_tool = $true
        use_responses_lite = $false
    }
}

function Read-JsonModels([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    try {
        $payload = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
        if ($null -ne $payload.models) { return @($payload.models) }
    }
    catch { Write-Warn "Ignoring unreadable model metadata file: $Path" }
    return @()
}

function New-CodexCatalog([object[]]$ModelRecords) {
    $existingModels = @(Read-JsonModels (Get-CodexCatalogPath))
    $cachedModels = @(Read-JsonModels (Get-CodexCachePath))
    $templates = @{}
    foreach ($entry in @($cachedModels + $existingModels)) {
        $entryId = if ($entry.slug) { [string]$entry.slug } elseif ($entry.id) { [string]$entry.id } else { $null }
        if ($entryId -and -not $templates.ContainsKey($entryId)) { $templates[$entryId] = $entry }
    }
    $fallbackTemplate = New-FallbackCatalogEntry
    $catalogModels = @()
    foreach ($record in $ModelRecords) {
        $hasExistingTemplate = $templates.ContainsKey($record.id)
        $entry = Copy-JsonObject $fallbackTemplate
        if ($hasExistingTemplate) {
            foreach ($property in $templates[$record.id].PSObject.Properties) {
                Ensure-ObjectProperty $entry $property.Name $property.Value
                $entry.($property.Name) = $property.Value
            }
        }

        Ensure-ObjectProperty $entry "slug" $record.id
        $entry.slug = $record.id
        if ($record.display_name_explicit -or -not $hasExistingTemplate) {
            Ensure-ObjectProperty $entry "display_name" $record.display_name
            $entry.display_name = $record.display_name

        }

        Ensure-ObjectProperty $entry "description" $record.display_name
        if (-not $entry.description) { $entry.description = $record.display_name }
        $contextWindow = if ($record.context_window) { [int64]$record.context_window } elseif ($entry.context_window) { [int64]$entry.context_window } else { $DefaultContextWindow }
        Ensure-ObjectProperty $entry "context_window" $contextWindow
        Ensure-ObjectProperty $entry "max_context_window" $contextWindow
        $entry.context_window = $contextWindow
        $entry.max_context_window = $contextWindow
        Ensure-ObjectProperty $entry "base_instructions" "You are Codex, a coding agent."
        if (-not $entry.base_instructions) { $entry.base_instructions = "You are Codex, a coding agent." }
        Ensure-ObjectProperty $entry "supports_reasoning_summaries" $true
        Ensure-ObjectProperty $entry "supported_reasoning_levels" @()
        Ensure-ObjectProperty $entry "shell_type" "shell_command"
        Ensure-ObjectProperty $entry "visibility" "list"
        Ensure-ObjectProperty $entry "supported_in_api" $true
        Ensure-ObjectProperty $entry "priority" 0
        Ensure-ObjectProperty $entry "input_modalities" @("text", "image")
        Ensure-ObjectProperty $entry "supports_parallel_tool_calls" $true
        $catalogModels += $entry
    }
    return [ordered]@{ models = $catalogModels }
}

function Set-TomlTopLevelString([string]$Content, [string]$Key, [string]$Value) {
    $escaped = $Value.Replace('\','\\').Replace('"','\"')
    $line = "$Key = `"$escaped`""
    $pattern = "(?m)^\s*" + [regex]::Escape($Key) + "\s*=.*$"
    $section = [regex]::Match($Content, "(?m)^\s*\[")
    $prefix = if ($section.Success) { $Content.Substring(0, $section.Index) } else { $Content }
    $remainder = if ($section.Success) { $Content.Substring($section.Index) } else { "" }
    if ([regex]::IsMatch($prefix, $pattern)) { return [regex]::Replace($prefix, $pattern, $line, 1) + $remainder }
    if ($section.Success) { return $prefix + $line + [Environment]::NewLine + [Environment]::NewLine + $remainder }
    return $Content.TrimEnd() + [Environment]::NewLine + $line + [Environment]::NewLine
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
    for ($index = 0; $index -lt $ModelRecords.Count; $index++) {
        Write-Host ("{0,4}. {1}" -f ($index + 1), $ModelRecords[$index].id)
    }
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
$config = Read-CodexConfig
if ($config.CatalogReference -and $runMode -ne "list") {
    $catalogReference = $config.CatalogReference.Replace("\", "/").Trim()
    if (@($CatalogFileName, "./$CatalogFileName") -notcontains $catalogReference -and -not $ReplaceCustomCatalog) {
        throw "config.toml points to custom catalog '$($config.CatalogReference)'. Re-run with -ReplaceCustomCatalog to replace it."
    }
}

if ($modelsProvided) { $modelRecords = @(Read-ModelsArgument $Models) }
elseif ($modelsFileProvided) { $modelRecords = @(Read-ModelsFromFile $ModelsFile) }
elseif ($Manual) { $modelRecords = @(Read-ModelsInteractive) }
else {
    $resolvedApiKey = $config.ApiKey
    if (-not $resolvedApiKey) { $resolvedApiKey = Read-ApiKeyInteractive }
    $resolvedAuthMode = if ($AuthMode -eq "auto") { "bearer" } else { $AuthMode }
    $modelRecords = @(Get-RemoteModelRecords $config.BaseUrl $resolvedApiKey $resolvedAuthMode)
}

Write-Step "Resolved $($modelRecords.Count) model(s)."
if ($runMode -eq "list") { Show-Models $modelRecords; exit 0 }

$selectedModel = $null
if ($runMode -eq "switch") { $selectedModel = Select-ModelId $modelRecords $config.CurrentModel }
$catalogPayload = New-CodexCatalog $modelRecords
$catalogJson = ($catalogPayload | ConvertTo-Json -Depth 100) + [Environment]::NewLine
$updatedConfig = Set-TomlTopLevelString $config.Content "model_catalog_json" $CatalogFileName
if ($runMode -eq "switch") { $updatedConfig = Set-TomlTopLevelString $updatedConfig "model" $selectedModel }

if ($DryRun) {
    Write-Step "Dry run: would write $(Get-CodexCatalogPath) and update $($config.Path)."
    if ($selectedModel) { Write-Step "Dry run: would switch default model to $selectedModel." }
    exit 0
}

$catalogBackup = Backup-File (Get-CodexCatalogPath)
$configBackup = Backup-File $config.Path
if ($catalogBackup) { Write-Step "Catalog backup: $catalogBackup" }
if ($configBackup) { Write-Step "Config backup: $configBackup" }
Save-Utf8Atomic (Get-CodexCatalogPath) $catalogJson
Save-Utf8Atomic $config.Path $updatedConfig
Write-Step "Model catalog updated: $(Get-CodexCatalogPath)"
if ($selectedModel) { Write-Step "Default model updated to: $selectedModel" }
else { Write-Step "Current default model unchanged: $($config.CurrentModel)" }
Write-Step "Restart Codex, Codex Desktop, or the VS Code Codex extension to reload the catalog."
