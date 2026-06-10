<#
.SYNOPSIS
Refresh the relay model list and switch the active model for Codex CLI
and/or Claude Code on Windows.

.DESCRIPTION
Reads the existing managed configuration written by the relay installers:

  - Codex     : $CODEX_HOME/config.toml or ~/.codex/config.toml
  - Claude Code: ~/.claude/settings.json

Re-fetches /v1/models from the relay with the saved API key, lets you
pick a new model, and rewrites only the model fields. Base URLs, API
keys, and unrelated settings are left as-is. A timestamped backup is
created before each file is changed.

Use this whenever your relay platform exposes new models and you want
to switch without re-running the full installer.

By default the script auto-detects which tools are configured. If both
~/.codex/config.toml and ~/.claude/settings.json exist, you are asked
which one(s) to update. Pass -Tool codex|claude|both to skip the
prompt.

.EXAMPLE
PS> .\update-relay-model-windows.ps1

.EXAMPLE
PS> .\update-relay-model-windows.ps1 -Tool both -ListModels

.EXAMPLE
PS> .\update-relay-model-windows.ps1 -Tool claude -Model gpt-5.5 -DryRun
#>

[CmdletBinding()]
param(
    [ValidateSet("auto", "codex", "claude", "both")]
    [string]$Tool = "auto",
    [switch]$DryRun,
    [switch]$ListModels,
    [switch]$NoModelPicker,
    [string]$Model,
    [string]$BaseUrl,
    [string]$ApiKey,
    [string]$ProviderId,
    [int]$RequestTimeoutSec = 30
)

if ($PSVersionTable.PSVersion.Major -lt 6) {
    $pwsh = Get-Command "pwsh" -ErrorAction SilentlyContinue
    if ($pwsh) {
        $forwardArgs = New-Object System.Collections.Generic.List[string]
        foreach ($entry in $MyInvocation.BoundParameters.GetEnumerator()) {
            $forwardArgs.Add("-$($entry.Key)")
            if ($entry.Value -is [System.Management.Automation.SwitchParameter]) {
                if (-not $entry.Value.IsPresent) {
                    $forwardArgs.RemoveAt($forwardArgs.Count - 1)
                }
                continue
            }
            $forwardArgs.Add([string]$entry.Value)
        }
        foreach ($arg in $args) {
            $forwardArgs.Add([string]$arg)
        }

        Write-Host "[relay] Windows PowerShell $($PSVersionTable.PSVersion) detected; re-running with PowerShell 7: $($pwsh.Source)"
        & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @forwardArgs
        exit $LASTEXITCODE
    }

    Write-Warning "[relay] Windows PowerShell $($PSVersionTable.PSVersion) can fail to parse large Claude settings.json files. Install PowerShell 7 and run this script with pwsh."
}

$ErrorActionPreference = "Stop"

# Codex constants
$CodexBeginMarker = "# BEGIN CODEX RELAY INSTALLER MANAGED BLOCK"
$CodexEndMarker = "# END CODEX RELAY INSTALLER MANAGED BLOCK"
$CodexDefaultBaseUrl = "https://litellm.blackwhitedeer.studio/v1"
$CodexDefaultProviderId = "custom-relay"

# Claude constants
$ClaudeDefaultBaseUrl = "https://litellm.blackwhitedeer.studio"
$ClaudeModelEnvKeys = @(
    "ANTHROPIC_MODEL",
    "ANTHROPIC_DEFAULT_SONNET_MODEL",
    "ANTHROPIC_DEFAULT_OPUS_MODEL",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL"
)
$ClaudeFamilyModelEnvKeys = [ordered]@{
    ANTHROPIC_DEFAULT_SONNET_MODEL = "sonnet"
    ANTHROPIC_DEFAULT_OPUS_MODEL = "opus"
    ANTHROPIC_DEFAULT_HAIKU_MODEL = "haiku"
}
$ClaudeModelDiscoveryEnvKey = "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY"

# Shared
$FallbackModel = "gpt-5.5"

#------------------------------------------------------------------
# Logging
#------------------------------------------------------------------
function Write-Step {
    param([string]$Message, [string]$Tag = "relay")
    Write-Host "[$Tag] $Message"
}

function Write-Warn {
    param([string]$Message, [string]$Tag = "relay")
    Write-Warning "[$Tag] $Message"
}

#------------------------------------------------------------------
# Shared helpers
#------------------------------------------------------------------
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

function Read-ApiKeyInteractive {
    param([string]$Tag = "relay")
    while ($true) {
        $secure = Read-Host "Paste your relay API key" -AsSecureString
        $plain = ConvertTo-PlainText $secure
        if ($plain -and $plain.Trim()) {
            return $plain.Trim()
        }
        Write-Warn -Tag $Tag "API key cannot be empty."
    }
}

function Show-ModelChoices {
    param([string[]]$Models, [string]$Tag = "relay")

    $width = [Math]::Max(3, ([string]$Models.Count).Length)
    $format = "  {0,$width}. {1}"
    for ($i = 0; $i -lt $Models.Count; $i++) {
        Write-Host ($format -f ($i + 1), $Models[$i])
    }
}

function Select-Model {
    param(
        [string[]]$Models,
        [string]$CurrentModel,
        [string]$Tag = "relay"
    )

    if ($Models.Count -eq 0) {
        throw "Relay returned no models. Cannot pick a new model."
    }

    $defaultModel = if ($CurrentModel -and ($Models -contains $CurrentModel)) {
        $CurrentModel
    }
    elseif ($Models -contains $FallbackModel) {
        $FallbackModel
    }
    else {
        $Models[0]
    }

    Write-Step -Tag $Tag "Available models from relay ($($Models.Count) total):"
    Show-ModelChoices -Models $Models -Tag $Tag
    if ($CurrentModel) {
        Write-Step -Tag $Tag "Current model: $CurrentModel"
    }

    while ($true) {
        $answer = Read-Host "Choose default model number/name, or press Enter for $defaultModel"
        if (-not $answer) { return $defaultModel }
        if ($answer -match '^\d+$') {
            $index = [int]$answer - 1
            if ($index -ge 0 -and $index -lt $Models.Count) {
                return $Models[$index]
            }
            Write-Warn -Tag $Tag "Model number out of range. Try again."
            continue
        }
        return $answer.Trim()
    }
}

function Write-HttpStatusHint {
    param(
        [object]$Status,
        [string]$FallbackMessage = "Request failed.",
        [string]$Tag = "relay"
    )

    switch ($Status) {
        400 { Write-Warn -Tag $Tag "HTTP 400: request was rejected. Check API compatibility." }
        401 { Write-Warn -Tag $Tag "HTTP 401: API key is missing or invalid." }
        402 { Write-Warn -Tag $Tag "HTTP 402: quota, balance, or payment limit may be exhausted." }
        403 { Write-Warn -Tag $Tag "HTTP 403: API key is valid but not allowed to use this resource." }
        404 { Write-Warn -Tag $Tag "HTTP 404: endpoint not found. Confirm the base URL." }
        429 { Write-Warn -Tag $Tag "HTTP 429: upstream rate limit or quota was reached." }
        { $_ -ge 500 } { Write-Warn -Tag $Tag "HTTP ${Status}: relay or upstream server error." }
        default { Write-Warn -Tag $Tag $FallbackMessage }
    }
}

function Write-HttpFailureHint {
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$Tag = "relay"
    )

    $status = $null
    if ($ErrorRecord.Exception.Response) {
        try { $status = [int]$ErrorRecord.Exception.Response.StatusCode } catch { $status = $null }
    }
    Write-HttpStatusHint -Status $status -FallbackMessage $ErrorRecord.Exception.Message -Tag $Tag
}

function Invoke-CurlJsonRequest {
    param(
        [string]$Method,
        [string]$Url,
        [hashtable]$Headers
    )

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) { throw "curl.exe was not found." }

    $stderrPath = [System.IO.Path]::GetTempFileName()
    try {
        $arguments = @(
            "--silent", "--show-error", "--fail",
            "--ssl-no-revoke", "--tlsv1.2", "--http1.1",
            "--max-time", [string]$RequestTimeoutSec,
            "-X", $Method.ToUpperInvariant()
        )
        foreach ($key in $Headers.Keys) {
            $arguments += @("-H", ("{0}: {1}" -f $key, $Headers[$key]))
        }
        $arguments += $Url

        $output = & $curl.Source @arguments 2> $stderrPath
        $exitCode = $LASTEXITCODE
        $stderr = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
        $responseText = ($output -join [Environment]::NewLine)
        if ($exitCode -ne 0) {
            $details = if ($stderr -and $stderr.Trim()) { $stderr.Trim() } elseif ($responseText) { $responseText.Trim() } else { "curl.exe exited with code $exitCode." }
            throw "curl.exe request failed: $details"
        }
        if (-not $responseText.Trim()) {
            throw "curl.exe returned an empty response."
        }
        return $responseText | ConvertFrom-Json
    }
    finally {
        Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-RelayJson {
    param(
        [string]$Method,
        [string]$Url,
        [hashtable]$Headers
    )

    try {
        return Invoke-RestMethod -Method $Method -Uri $Url -Headers $Headers -TimeoutSec $RequestTimeoutSec
    }
    catch {
        $primary = $_.Exception.Message
        if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw }
        Write-Warn "PowerShell request failed; retrying with curl.exe. $primary"
        try {
            return Invoke-CurlJsonRequest -Method $Method -Url $Url -Headers $Headers
        }
        catch {
            throw "PowerShell request failed: $primary; curl.exe fallback failed: $($_.Exception.Message)"
        }
    }
}

function Update-QueryParameter {
    param(
        [string]$Url,
        [string]$Name,
        [string]$Value
    )

    $escapedValue = [Uri]::EscapeDataString($Value)
    if ($Url -match "(?i)([?&]$([regex]::Escape($Name))=)[^&]*") {
        return [regex]::Replace($Url, "(?i)([?&]$([regex]::Escape($Name))=)[^&]*", "`$1$escapedValue", 1)
    }
    if ($Url -match "\?") {
        return "${Url}&${Name}=${escapedValue}"
    }
    return "${Url}?${Name}=${escapedValue}"
}

function Resolve-NextModelsUrl {
    param(
        [object]$Response,
        [string]$CurrentUrl
    )

    if (-not $Response) { return $null }
    $props = $Response.PSObject.Properties.Name

    if ($props -contains "next") {
        $next = [string]$Response.next
        if ($next -and $next.Trim()) {
            try {
                $baseUri = [System.Uri]$CurrentUrl
                $resolved = [System.Uri]::new($baseUri, $next)
                return $resolved.AbsoluteUri
            }
            catch {
                return $null
            }
        }
    }

    if ($props -contains "next_page" -and $Response.next_page) {
        return Update-QueryParameter -Url $CurrentUrl -Name "page" -Value ([string]$Response.next_page)
    }

    if ($props -contains "next_cursor" -and $Response.next_cursor) {
        return Update-QueryParameter -Url $CurrentUrl -Name "cursor" -Value ([string]$Response.next_cursor)
    }

    if ($props -contains "has_more") {
        $hasMore = $false
        try {
            if ($Response.has_more -is [bool]) {
                $hasMore = [bool]$Response.has_more
            }
            elseif ($Response.has_more -is [string]) {
                $hasMore = [string]::Equals([string]$Response.has_more, "true", "InvariantCultureIgnoreCase")
            }
        }
        catch { }

        if ($hasMore) {
            if ($props -contains "page") {
                try {
                    $nextPage = [int]$Response.page + 1
                    return Update-QueryParameter -Url $CurrentUrl -Name "page" -Value ([string]$nextPage)
                }
                catch {
                    return $null
                }
            }
            if ($props -contains "offset" -and $props -contains "limit") {
                try {
                    $nextOffset = [int]$Response.offset + [int]$Response.limit
                    return Update-QueryParameter -Url $CurrentUrl -Name "offset" -Value ([string]$nextOffset)
                }
                catch {
                    return $null
                }
            }
        }
    }

    return $null
}

function Get-RelayModels {
    param(
        [string]$Url,
        [string]$ApiKey,
        [string]$Tag = "relay"
    )

    $headers = @{ Authorization = "Bearer $ApiKey" }
    $seenPages = @{}
    $seen = @{}
    $models = New-Object System.Collections.Generic.List[string]
    $baseUrl = $Url
    $retriesWithoutLimit = $false
    if ($Url -match "(?i)([\?&]limit=)") {
        $nextUrl = $Url
    }
    else {
        $nextUrl = Update-QueryParameter -Url $Url -Name "limit" -Value "200"
    }
    $maxPages = 50

    for ($page = 0; $page -lt $maxPages -and $nextUrl; $page++) {
        if ($seenPages.ContainsKey($nextUrl)) {
            Write-Warn -Tag $Tag "Detected paging loop at $nextUrl. Stopping."
            break
        }
        $seenPages[$nextUrl] = $true

        Write-Step -Tag $Tag "Fetching model list from: $nextUrl"
        try {
            $response = Invoke-RelayJson -Method Get -Url $nextUrl -Headers $headers
        }
        catch {
            if (-not $retriesWithoutLimit -and $nextUrl -ne $baseUrl) {
                Write-Warn -Tag $Tag "Request with limit failed; retrying without limit."
                $nextUrl = $baseUrl
                $retriesWithoutLimit = $true
                $page--
                continue
            }
            throw
        }
        if (-not $response) { break }

        $responseData = if ($response.data) {
            $response.data
        }
        elseif ($response.models) {
            $response.models
        }
        else {
            @()
        }

        foreach ($item in $responseData) {
            if (-not $item.id) { continue }
            $id = [string]$item.id
            if (-not $seen.ContainsKey($id)) {
                $seen[$id] = $true
                $models.Add($id)
            }
        }

        $nextUrl = Resolve-NextModelsUrl -Response $response -CurrentUrl $nextUrl
        if (-not $nextUrl) {
            break
        }
    }
    return @($models)
}

#------------------------------------------------------------------
# Codex helpers
#------------------------------------------------------------------
function Get-CodexHome {
    if ($env:CODEX_HOME) { return $env:CODEX_HOME }
    return (Join-Path $HOME ".codex")
}

function Get-CodexConfigPath {
    return (Join-Path (Get-CodexHome) "config.toml")
}

function Get-CodexModelCachePath {
    return (Join-Path (Get-CodexHome) "models_cache.json")
}

function Normalize-CodexBaseUrl {
    param([string]$Value)

    $trimmed = $Value.Trim()
    while ($trimmed.EndsWith('/')) { $trimmed = $trimmed.Substring(0, $trimmed.Length - 1) }
    return $trimmed
}

function Join-CodexUrl {
    param([string]$BaseUrl, [string]$Path)
    $base = Normalize-CodexBaseUrl $BaseUrl
    $cleanPath = $Path.TrimStart("/")
    return "$base/$cleanPath"
}

function Escape-TomlString {
    param([string]$Value)
    return $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '').Replace("`n", '')
}

function Get-TomlValue {
    param([string]$Content, [string]$Key)
    $match = [regex]::Match($Content, "(?m)^\s*$([regex]::Escape($Key))\s*=\s*`"([^`"]+)`"")
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

function Get-CodexProviderBlockValue {
    param([string]$Content, [string]$ProviderId, [string]$Key)
    $escapedProviderId = [regex]::Escape($ProviderId)
    $providerPattern = "\[model_providers\.(?:`"$escapedProviderId`"|$escapedProviderId)\]"
    $blockMatch = [regex]::Match($Content, "(?ms)^\s*$providerPattern\s*`$([\s\S]*?)(?=^\s*\[|\z)")
    if (-not $blockMatch.Success) { return $null }
    return Get-TomlValue -Content $blockMatch.Groups[1].Value -Key $Key
}

function Get-EnvironmentVariableValue {
    param([string]$Name)

    if (-not $Name) { return $null }
    $trimmed = $Name.Trim()
    if (-not $trimmed) { return $null }

    foreach ($target in @("Process", "User", "Machine")) {
        $value = [Environment]::GetEnvironmentVariable($trimmed, $target)
        if ($value) { return $value }
    }
    return $null
}

function Resolve-CodexProviderApiKey {
    param([string]$Content, [string]$ProviderId)

    $directApiKey = Get-CodexProviderBlockValue -Content $Content -ProviderId $ProviderId -Key "experimental_bearer_token"
    if ($directApiKey) {
        return [pscustomobject]@{
            ApiKey = $directApiKey
            Source = "experimental_bearer_token"
            ProviderId = $ProviderId
            EnvKey = $null
        }
    }

    $envKey = Get-CodexProviderBlockValue -Content $Content -ProviderId $ProviderId -Key "env_key"
    $envApiKey = Get-EnvironmentVariableValue -Name $envKey
    if ($envApiKey) {
        return [pscustomobject]@{
            ApiKey = $envApiKey
            Source = "env_key"
            ProviderId = $ProviderId
            EnvKey = $envKey
        }
    }

    return [pscustomobject]@{
        ApiKey = $null
        Source = $null
        ProviderId = $ProviderId
        EnvKey = $envKey
    }
}

function Copy-ShallowObject {
    param([object]$InputObject)

    $copy = [ordered]@{}
    if ($InputObject -and $InputObject.PSObject.Properties) {
        foreach ($property in $InputObject.PSObject.Properties) {
            $copy[$property.Name] = $property.Value
        }
    }
    return $copy
}

function Read-CodexModelCache {
    $cachePath = Get-CodexModelCachePath
    if (-not (Test-Path -LiteralPath $cachePath)) {
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $cachePath -Raw
        if (-not $raw.Trim()) {
            return $null
        }
        return $raw | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Read-CodexRelay {
    $configPath = Get-CodexConfigPath
    if (-not (Test-Path -LiteralPath $configPath)) {
        return [pscustomobject]@{
            ConfigPath = $configPath; Exists = $false; Content = $null
            Model = $null; ProviderId = $null; BaseUrl = $null; ApiKey = $null
            ApiKeySource = $null; ApiKeySourceProviderId = $null; ApiKeyEnvKey = $null
            HasManagedBlock = $false
        }
    }

    $content = Get-Content -LiteralPath $configPath -Raw
    $configuredProviderId = Get-TomlValue -Content $content -Key "model_provider"
    if (-not $configuredProviderId) { $configuredProviderId = $CodexDefaultProviderId }
    $apiKeyInfo = Resolve-CodexProviderApiKey -Content $content -ProviderId $configuredProviderId
    if (-not $apiKeyInfo.ApiKey -and $configuredProviderId -ne $CodexDefaultProviderId) {
        $fallbackApiKeyInfo = Resolve-CodexProviderApiKey -Content $content -ProviderId $CodexDefaultProviderId
        if ($fallbackApiKeyInfo.ApiKey) {
            $apiKeyInfo = $fallbackApiKeyInfo
        }
    }

    return [pscustomobject]@{
        ConfigPath = $configPath
        Exists = $true
        Content = $content
        Model = Get-TomlValue -Content $content -Key "model"
        ProviderId = $configuredProviderId
        BaseUrl = Get-CodexProviderBlockValue -Content $content -ProviderId $configuredProviderId -Key "base_url"
        ApiKey = $apiKeyInfo.ApiKey
        ApiKeySource = $apiKeyInfo.Source
        ApiKeySourceProviderId = $apiKeyInfo.ProviderId
        ApiKeyEnvKey = $apiKeyInfo.EnvKey
        HasManagedBlock = ([regex]::Match($content, "(?ms)^\s*$([regex]::Escape($CodexBeginMarker))[\s\S]*?$([regex]::Escape($CodexEndMarker))").Success)
    }
}

function Update-CodexManagedModelLine {
    param([string]$Content, [string]$Model)

    if (-not $Content) { return $null }
    $beginEscaped = [regex]::Escape($CodexBeginMarker)
    $endEscaped = [regex]::Escape($CodexEndMarker)
    $blockMatch = [regex]::Match($Content, "(?ms)^$beginEscaped\s*`$([\s\S]*?)^$endEscaped\s*`$")
    if (-not $blockMatch.Success) { return $null }

    $blockBody = $blockMatch.Groups[1].Value
    $escapedModel = Escape-TomlString $Model
    $replacementBody = [regex]::Replace($blockBody, '(?m)^(\s*model\s*=\s*)"[^"]*"', "`$1`"$escapedModel`"")
    if ($replacementBody -eq $blockBody) {
        $replacementBody = "`r`nmodel = `"$escapedModel`"" + $blockBody
    }

    $replacementBlock = "$CodexBeginMarker$replacementBody$CodexEndMarker"
    $startIndex = $blockMatch.Index
    $blockLength = $blockMatch.Length
    return $Content.Substring(0, $startIndex) + $replacementBlock + $Content.Substring($startIndex + $blockLength)
}

function New-CodexCacheEntry {
    param([string]$Model, [hashtable]$Template)

    $entry = if ($Template) { Copy-ShallowObject -InputObject $Template } else { [ordered]@{} }
    $entry["slug"] = $Model
    $entry["display_name"] = $Model
    if (-not $entry.Contains("id")) {
        $entry["id"] = ""
    }
    if (-not $entry.Contains("visibility") -or -not $entry["visibility"]) {
        $entry["visibility"] = "list"
    }
    if (-not $entry.Contains("supported_in_api")) {
        $entry["supported_in_api"] = $true
    }
    return [pscustomobject]$entry
}

function Write-CodexModelCache {
    param(
        [string[]]$Models,
        [string]$Tag = "codex-relay"
    )

    if (-not $Models -or $Models.Count -eq 0) { return }

    $cachePath = Get-CodexModelCachePath
    $cacheDir = Split-Path -Parent $cachePath
    $cache = Read-CodexModelCache
    $existingByModel = @{}
    $template = $null

    if ($cache -and $cache.models -is [array] -and $cache.models.Count -gt 0) {
        foreach ($model in $cache.models) {
            $slug = if ($model -and $model.slug) { [string]$model.slug } else { $null }
            if ($slug -and -not $existingByModel.ContainsKey($slug)) {
                $existingByModel[$slug] = Copy-ShallowObject -InputObject $model
            }
        }
        $template = Copy-ShallowObject -InputObject $cache.models[0]
    }

    $seen = @{}
    $cacheEntries = New-Object System.Collections.Generic.List[object]
    foreach ($model in $Models) {
        $modelId = [string]$model
        if (-not $modelId -or $seen.ContainsKey($modelId)) {
            continue
        }
        $seen[$modelId] = $true

        if ($existingByModel.ContainsKey($modelId)) {
            $cacheEntries.Add([pscustomobject]$existingByModel[$modelId])
            continue
        }

        $cacheEntries.Add((New-CodexCacheEntry -Model $modelId -Template $template))
    }

    $payload = [ordered]@{
        fetched_at = (Get-Date).ToUniversalTime().ToString("o")
        etag = if ($cache -and $cache.etag) { $cache.etag } else { $null }
        client_version = if ($cache -and $cache.client_version) { $cache.client_version } else { $null }
        models = @($cacheEntries)
    }

    try {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        $json = $payload | ConvertTo-Json -Depth 20
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($cachePath, $json + [Environment]::NewLine, $utf8NoBom)
        Write-Step -Tag $Tag "Model cache refreshed: $cachePath"
    }
    catch {
        Write-Warn -Tag $Tag "Failed to refresh model cache at ${cachePath}: $($_.Exception.Message)"
    }
}

function Update-CodexModelLine {
    param([string]$Content, [string]$Model)

    $updatedByManagedBlock = Update-CodexManagedModelLine -Content $Content -Model $Model
    if ($updatedByManagedBlock) {
        return $updatedByManagedBlock
    }

    $escapedModel = Escape-TomlString $Model
    $updatedRootLine = [regex]::Replace($Content, '(?m)^model\s*=\s*"[^"]*"', "model = `"$escapedModel`"", 1)
    if ($updatedRootLine -ne $Content) {
        return $updatedRootLine
    }

    if (-not $Content) { return "model = `"$escapedModel`"" }
    return "model = `"$escapedModel`"`r`n$Content"
}

function Update-CodexProviderApiKey {
    param([string]$Content, [string]$ProviderId, [string]$BaseUrl, [string]$ApiKey)

    $escapedApiKey = Escape-TomlString $ApiKey
    $tokenLine = "experimental_bearer_token = `"$escapedApiKey`""
    $escapedProviderId = [regex]::Escape($ProviderId)
    $providerPattern = "\[model_providers\.(?:`"$escapedProviderId`"|$escapedProviderId)\]"
    $blockMatch = [regex]::Match($Content, "(?ms)^\s*$providerPattern\s*`$([\s\S]*?)(?=^\s*\[|\z)")

    if ($blockMatch.Success) {
        $block = $blockMatch.Value
        $updatedBlock = [regex]::Replace($block, '(?m)^(\s*experimental_bearer_token\s*=\s*)"[^"]*"', "`$1`"$escapedApiKey`"")

        if ($updatedBlock -eq $block) {
            foreach ($anchor in @("wire_api", "base_url", "name")) {
                $anchorPattern = "(?m)^(\s*$anchor\s*=\s*`"[^`"]*`"\s*)$"
                $candidate = [regex]::Replace($block, $anchorPattern, "`$1`r`n$tokenLine")
                if ($candidate -ne $block) {
                    $updatedBlock = $candidate
                    break
                }
            }
        }

        if ($updatedBlock -eq $block) {
            $updatedBlock = $block.TrimEnd() + "`r`n$tokenLine`r`n"
        }

        return $Content.Substring(0, $blockMatch.Index) + $updatedBlock + $Content.Substring($blockMatch.Index + $blockMatch.Length)
    }

    $escapedProviderName = Escape-TomlString $ProviderId
    $escapedBaseUrl = Escape-TomlString $BaseUrl
    $newBlock = @"
[model_providers."$escapedProviderName"]
name = "$escapedProviderName"
base_url = "$escapedBaseUrl"
wire_api = "responses"
$tokenLine
"@
    if (-not $Content) { return $newBlock.TrimEnd() }
    return $Content.TrimEnd() + "`r`n`r`n" + $newBlock.TrimEnd()
}

function Backup-File {
    param([string]$Path)
    $backup = "$Path.backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item -LiteralPath $Path -Destination $backup -Force
    return $backup
}

function Save-TextFile {
    param([string]$Path, [string]$Content)
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content.TrimEnd() + "`r`n", $utf8NoBom)
}

function Invoke-CodexUpdate {
    $tag = "codex-relay"
    $relay = Read-CodexRelay
    if (-not $relay.Exists) {
        Write-Warn -Tag $tag "Codex relay config not found at $($relay.ConfigPath). Skipping."
        return
    }

    $resolvedProviderId = if ($ProviderId) { $ProviderId.Trim() } else { $relay.ProviderId }
    if (-not $resolvedProviderId) { $resolvedProviderId = $CodexDefaultProviderId }

    $resolvedBaseUrl = if ($BaseUrl) { Normalize-CodexBaseUrl $BaseUrl } else { $relay.BaseUrl }
    if (-not $resolvedBaseUrl) { $resolvedBaseUrl = $CodexDefaultBaseUrl }

    $shouldPersistApiKey = $false
    if ($ApiKey) {
        $resolvedApiKey = $ApiKey.Trim()
    }
    elseif ($relay.ApiKey) {
        $resolvedApiKey = $relay.ApiKey
        if ($relay.ApiKeySource -eq "env_key") {
            Write-Step -Tag $tag "Using relay API key from environment variable: $($relay.ApiKeyEnvKey)"
        }
        elseif ($relay.ApiKeySourceProviderId -and $relay.ApiKeySourceProviderId -ne $resolvedProviderId) {
            Write-Step -Tag $tag "Using relay API key from provider: $($relay.ApiKeySourceProviderId)"
        }
    }
    else {
        Write-Warn -Tag $tag "No relay API key found in $($relay.ConfigPath). You will be prompted."
        $resolvedApiKey = Read-ApiKeyInteractive -Tag $tag
        $shouldPersistApiKey = $true
    }

    Write-Step -Tag $tag "Config: $($relay.ConfigPath)"
    Write-Step -Tag $tag "Provider: $resolvedProviderId"
    Write-Step -Tag $tag "Base URL: $resolvedBaseUrl"
    if ($relay.Model) { Write-Step -Tag $tag "Currently configured model: $($relay.Model)" }

    $url = Join-CodexUrl -BaseUrl $resolvedBaseUrl -Path "models"
    try {
        $models = @(Get-RelayModels -Url $url -ApiKey $resolvedApiKey -Tag $tag)
    }
    catch {
        Write-HttpFailureHint -ErrorRecord $_ -Tag $tag
        Write-Warn -Tag $tag "Failed to fetch /models. Skipping Codex update."
        return
    }
    Write-CodexModelCache -Models $models -Tag $tag

    if ($ListModels) {
        if ($models.Count -eq 0) { Write-Warn -Tag $tag "Relay returned no models."; return }
        Write-Step -Tag $tag "Models from relay: $($models.Count)"
        Show-ModelChoices -Models $models -Tag $tag
        return
    }

    if ($Model) {
        $resolvedModel = $Model.Trim()
        if ($models.Count -gt 0 -and -not ($models -contains $resolvedModel)) {
            Write-Warn -Tag $tag "Model '$resolvedModel' is not in the relay /models response. Writing it anyway."
        }
    }
    elseif ($NoModelPicker) {
        $resolvedModel = if ($relay.Model) { $relay.Model } else { $FallbackModel }
        Write-Step -Tag $tag "Skipping interactive picker. Keeping model: $resolvedModel"
    }
    else {
        $resolvedModel = Select-Model -Models $models -CurrentModel $relay.Model -Tag $tag
    }

    $modelChanged = ($resolvedModel -ne $relay.Model)
    if (-not $modelChanged -and -not $shouldPersistApiKey) {
        Write-Step -Tag $tag "Selected model matches the current model ($resolvedModel). Nothing to update."
        return
    }

    $updatedContent = $relay.Content
    if ($modelChanged) {
        $updatedContent = Update-CodexModelLine -Content $updatedContent -Model $resolvedModel
    }
    if ($shouldPersistApiKey) {
        $updatedContent = Update-CodexProviderApiKey -Content $updatedContent -ProviderId $resolvedProviderId -BaseUrl $resolvedBaseUrl -ApiKey $resolvedApiKey
    }

    if ($DryRun) {
        if ($modelChanged) {
            Write-Step -Tag $tag "Dry run: would update model -> $resolvedModel in $($relay.ConfigPath)"
        }
        if ($shouldPersistApiKey) {
            Write-Step -Tag $tag "Dry run: would save relay API key in provider '$resolvedProviderId'"
        }
        return
    }

    $backup = Backup-File -Path $relay.ConfigPath
    Write-Step -Tag $tag "Backup written: $backup"
    Save-TextFile -Path $relay.ConfigPath -Content $updatedContent
    if ($modelChanged) {
        Write-Step -Tag $tag "Model updated to: $resolvedModel"
    }
    if ($shouldPersistApiKey) {
        Write-Step -Tag $tag "Relay API key saved in provider: $resolvedProviderId"
    }
}

#------------------------------------------------------------------
# Claude helpers
#------------------------------------------------------------------
function Get-ClaudeHome {
    return (Join-Path $HOME ".claude")
}

function Get-ClaudeSettingsPath {
    return (Join-Path (Get-ClaudeHome) "settings.json")
}

function Normalize-ClaudeBaseUrl {
    param([string]$Value)

    $resolved = if ($Value -and $Value.Trim()) { $Value.Trim() } else { $ClaudeDefaultBaseUrl }
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
    param([string]$BaseUrl, [string]$Path)
    $base = Normalize-ClaudeBaseUrl $BaseUrl
    $cleanPath = $Path.TrimStart("/")
    return "$base/v1/$cleanPath"
}

function Get-ClaudeSettingsObject {
    $path = Get-ClaudeSettingsPath
    if (-not (Test-Path -LiteralPath $path)) { return [pscustomobject]@{} }
    $content = Get-Content -LiteralPath $path -Raw
    if (-not $content.Trim()) { return [pscustomobject]@{} }
    return $content | ConvertFrom-Json
}

function Ensure-ObjectProperty {
    param([object]$Object, [string]$Name, [object]$Value)
    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    }
    else {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Read-ClaudeRelay {
    $settings = Get-ClaudeSettingsObject
    $path = Get-ClaudeSettingsPath
    $envObject = $settings.env
    if (-not $envObject) {
        return [pscustomobject]@{
            SettingsPath = $path; Exists = (Test-Path -LiteralPath $path); Settings = $settings
            BaseUrl = $null; ApiKey = $null; Model = $null; ModelDiscovery = $null
            SonnetModel = $null; OpusModel = $null; HaikuModel = $null
        }
    }
    return [pscustomobject]@{
        SettingsPath = $path
        Exists = (Test-Path -LiteralPath $path)
        Settings = $settings
        BaseUrl = $envObject.ANTHROPIC_BASE_URL
        ApiKey = $envObject.ANTHROPIC_AUTH_TOKEN
        Model = $envObject.ANTHROPIC_MODEL
        ModelDiscovery = $envObject.CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY
        SonnetModel = $envObject.ANTHROPIC_DEFAULT_SONNET_MODEL
        OpusModel = $envObject.ANTHROPIC_DEFAULT_OPUS_MODEL
        HaikuModel = $envObject.ANTHROPIC_DEFAULT_HAIKU_MODEL
    }
}

function Select-ClaudeFamilyModel {
    param(
        [string[]]$Models,
        [string]$Family,
        [string]$CurrentModel,
        [string]$FallbackModel
    )

    if ($CurrentModel -and ($Models -contains $CurrentModel) -and ($CurrentModel -match [regex]::Escape($Family))) {
        return $CurrentModel
    }

    $match = @($Models | Where-Object { $_ -match [regex]::Escape($Family) } | Select-Object -First 1)
    if ($match.Count -gt 0) { return $match[0] }
    return $FallbackModel
}

function Resolve-ClaudeFamilyModels {
    param([string[]]$Models, [object]$Relay, [string]$DefaultModel)

    return [ordered]@{
        ANTHROPIC_DEFAULT_SONNET_MODEL = Select-ClaudeFamilyModel -Models $Models -Family "sonnet" -CurrentModel $Relay.SonnetModel -FallbackModel $DefaultModel
        ANTHROPIC_DEFAULT_OPUS_MODEL = Select-ClaudeFamilyModel -Models $Models -Family "opus" -CurrentModel $Relay.OpusModel -FallbackModel $DefaultModel
        ANTHROPIC_DEFAULT_HAIKU_MODEL = Select-ClaudeFamilyModel -Models $Models -Family "haiku" -CurrentModel $Relay.HaikuModel -FallbackModel $DefaultModel
    }
}

function Test-ClaudeFamilyModelsMatch {
    param([object]$Relay, [hashtable]$FamilyModels)

    return (
        $Relay.SonnetModel -eq $FamilyModels.ANTHROPIC_DEFAULT_SONNET_MODEL -and
        $Relay.OpusModel -eq $FamilyModels.ANTHROPIC_DEFAULT_OPUS_MODEL -and
        $Relay.HaikuModel -eq $FamilyModels.ANTHROPIC_DEFAULT_HAIKU_MODEL
    )
}

function Save-ClaudeSettings {
    param([string]$Path, [object]$Settings)
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $json = $Settings | ConvertTo-Json -Depth 20
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, $utf8NoBom)
}

function Get-ClaudeGatewayCachePath {
    return (Join-Path (Get-ClaudeHome) "cache" "gateway-models.json")
}

function Write-ClaudeGatewayCache {
    param(
        [string[]]$Models,
        [string]$BaseUrl,
        [string]$Tag = "claude-relay"
    )

    if (-not $BaseUrl -or $Models.Count -eq 0) {
        return
    }

    $cachePath = Get-ClaudeGatewayCachePath
    try {
        $cacheDir = Split-Path -Parent $cachePath
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

        $payload = [ordered]@{
            baseUrl = $BaseUrl
            fetchedAt = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
            models = @()
        }
        foreach ($model in $Models) {
            $payload.models += [ordered]@{ id = $model }
        }

        $json = $payload | ConvertTo-Json -Depth 20
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($cachePath, $json + [Environment]::NewLine, $utf8NoBom)
        Write-Step -Tag $Tag "Gateway cache refreshed: ${cachePath}"
    }
    catch {
        Write-Warn -Tag $Tag "Failed to refresh gateway cache at ${cachePath}: $($_.Exception.Message)"
    }
}

function Invoke-ClaudeUpdate {
    $tag = "claude-relay"
    $relay = Read-ClaudeRelay
    if (-not $relay.Exists) {
        Write-Warn -Tag $tag "Claude Code relay config not found at $($relay.SettingsPath). Skipping."
        return
    }

    $resolvedBaseUrl = if ($BaseUrl) { Normalize-ClaudeBaseUrl $BaseUrl } else { Normalize-ClaudeBaseUrl $relay.BaseUrl }
    if (-not $resolvedBaseUrl) { $resolvedBaseUrl = $ClaudeDefaultBaseUrl }

    $resolvedApiKey = if ($ApiKey) {
        $ApiKey.Trim()
    }
    elseif ($relay.ApiKey) {
        $relay.ApiKey
    }
    else {
        Write-Warn -Tag $tag "No relay API key found in $($relay.SettingsPath). You will be prompted."
        Read-ApiKeyInteractive -Tag $tag
    }

    Write-Step -Tag $tag "Settings: $($relay.SettingsPath)"
    Write-Step -Tag $tag "Base URL: $resolvedBaseUrl"
    if ($relay.Model) { Write-Step -Tag $tag "Currently configured model: $($relay.Model)" }

    $url = Join-ClaudeUrl -BaseUrl $resolvedBaseUrl -Path "models"
    try {
        $models = @(Get-RelayModels -Url $url -ApiKey $resolvedApiKey -Tag $tag)
    }
    catch {
        Write-HttpFailureHint -ErrorRecord $_ -Tag $tag
        Write-Warn -Tag $tag "Failed to fetch /v1/models. Skipping Claude update."
        return
    }

    if ($ListModels) {
        if ($models.Count -eq 0) { Write-Warn -Tag $tag "Relay returned no models."; return }
        Write-ClaudeGatewayCache -Models $models -BaseUrl $resolvedBaseUrl -Tag $tag
        Show-ModelChoices -Models $models -Tag $tag
        return
    }

    if ($Model) {
        $resolvedModel = $Model.Trim()
        if ($models.Count -gt 0 -and -not ($models -contains $resolvedModel)) {
            Write-Warn -Tag $tag "Model '$resolvedModel' is not in the relay /v1/models response. Writing it anyway."
        }
    }
    elseif ($NoModelPicker) {
        $resolvedModel = if ($relay.Model) { $relay.Model } else { $FallbackModel }
        Write-Step -Tag $tag "Skipping interactive picker. Keeping model: $resolvedModel"
    }
    else {
        $resolvedModel = Select-Model -Models $models -CurrentModel $relay.Model -Tag $tag
    }

    $familyModels = Resolve-ClaudeFamilyModels -Models $models -Relay $relay -DefaultModel $resolvedModel
    Write-Step -Tag $tag "Resolved Claude default family models:"
    foreach ($entry in $familyModels.GetEnumerator()) {
        Write-Step -Tag $tag "  $($entry.Key) = $($entry.Value)"
    }
    Write-ClaudeGatewayCache -Models $models -BaseUrl $resolvedBaseUrl -Tag $tag

    $modelDiscoveryAlreadyEnabled = ([string]$relay.ModelDiscovery) -eq "1"
    $familyModelsAlreadyMatch = Test-ClaudeFamilyModelsMatch -Relay $relay -FamilyModels $familyModels
    if (($resolvedModel -eq $relay.Model) -and $modelDiscoveryAlreadyEnabled -and $familyModelsAlreadyMatch) {
        Write-Step -Tag $tag "Selected model matches the current model ($resolvedModel). Nothing to update."
        return
    }

    $settings = $relay.Settings
    if (-not ($settings.PSObject.Properties.Name -contains "env") -or -not $settings.env) {
        Ensure-ObjectProperty -Object $settings -Name "env" -Value ([pscustomobject]@{})
    }
    Ensure-ObjectProperty -Object $settings.env -Name $ClaudeModelDiscoveryEnvKey -Value "1"
    Ensure-ObjectProperty -Object $settings.env -Name "ANTHROPIC_MODEL" -Value $resolvedModel
    foreach ($entry in $familyModels.GetEnumerator()) {
        Ensure-ObjectProperty -Object $settings.env -Name $entry.Key -Value $entry.Value
    }

    if ($DryRun) {
        Write-Step -Tag $tag "Dry run: would enable model discovery and update Claude Code default/family models in $($relay.SettingsPath)"
        return
    }

    $backup = Backup-File -Path $relay.SettingsPath
    Write-Step -Tag $tag "Backup written: $backup"
    Save-ClaudeSettings -Path $relay.SettingsPath -Settings $settings
    Write-Step -Tag $tag "Refreshing gateway model cache: $(Get-ClaudeGatewayCachePath)"
    Write-ClaudeGatewayCache -Models $models -BaseUrl $resolvedBaseUrl -Tag $tag
    Write-Step -Tag $tag "Default model updated to: $resolvedModel"
    Write-Step -Tag $tag "Model discovery enabled: $ClaudeModelDiscoveryEnvKey=1"
    Write-Step -Tag $tag "Updated default/family model env keys: $($ClaudeModelEnvKeys -join ', ')"
}

#------------------------------------------------------------------
# Tool selection
#------------------------------------------------------------------
function Resolve-ToolSelection {
    $codexExists = Test-Path -LiteralPath (Get-CodexConfigPath)
    $claudeExists = Test-Path -LiteralPath (Get-ClaudeSettingsPath)

    if ($Tool -ne "auto") {
        if ($Tool -eq "codex" -and -not $codexExists) {
            Write-Warn "Codex config not found at $(Get-CodexConfigPath). Run install-codex-relay-windows.ps1 first."
        }
        if ($Tool -eq "claude" -and -not $claudeExists) {
            Write-Warn "Claude config not found at $(Get-ClaudeSettingsPath). Run install-claude-code-relay-windows.ps1 first."
        }
        if ($Tool -eq "both") {
            if (-not $codexExists) {
                Write-Warn "Codex config not found at $(Get-CodexConfigPath). It will be skipped."
            }
            if (-not $claudeExists) {
                Write-Warn "Claude config not found at $(Get-ClaudeSettingsPath). It will be skipped."
            }
        }
        return $Tool
    }

    if ($codexExists -and $claudeExists) {
        Write-Step "Detected both Codex ($(Get-CodexConfigPath)) and Claude Code ($(Get-ClaudeSettingsPath))."
        while ($true) {
            $answer = Read-Host "Update which tool? [1] Codex  [2] Claude Code  [3] both (default 3)"
            if (-not $answer) { return "both" }
            switch ($answer.Trim()) {
                "1" { return "codex" }
                "2" { return "claude" }
                "3" { return "both" }
                "codex" { return "codex" }
                "claude" { return "claude" }
                "both" { return "both" }
                default { Write-Warn "Pick 1, 2, or 3." }
            }
        }
    }
    if ($codexExists) {
        Write-Step "Auto-detected Codex relay config."
        return "codex"
    }
    if ($claudeExists) {
        Write-Step "Auto-detected Claude Code relay config."
        return "claude"
    }
    throw "Neither $(Get-CodexConfigPath) nor $(Get-ClaudeSettingsPath) was found. Run one of the install scripts first."
}

$resolvedTool = Resolve-ToolSelection
switch ($resolvedTool) {
    "codex"  { Invoke-CodexUpdate }
    "claude" { Invoke-ClaudeUpdate }
    "both"   { Invoke-CodexUpdate; Invoke-ClaudeUpdate }
}
