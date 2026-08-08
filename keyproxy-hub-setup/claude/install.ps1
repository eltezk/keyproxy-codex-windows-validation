[CmdletBinding()]
param(
    [string]$ConfigDir = $(if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }),
    [string]$InstallBin = $(Join-Path (Join-Path $HOME '.local') 'bin'),
    [string]$ClaudeJson = $(if ($env:KEYPROXY_CLAUDE_JSON) { $env:KEYPROXY_CLAUDE_JSON } else { Join-Path $HOME '.claude.json' })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$BaseUrl = 'https://api.keyproxyhub.store/v1'
$ModelsUrl = 'https://painel.keyproxyhub.store/v1/models'
$McpServer = [pscustomobject]@{ type = 'http'; url = 'https://api.keyproxyhub.store/mcp'; headers = [pscustomobject]@{ Authorization = 'Bearer ${KEYPROXY_API_KEY}' } }
$Models = @('auto','gpt-5.6-sol','gpt-5.6-terra','gpt-5.6-luna','gpt-5.5','gpt-5.4','gpt-5.4-mini','gpt-5.3-codex','gpt-5.3-codex-xhigh','gpt-5.3-codex-high','gpt-5.3-codex-low','gpt-5.3-codex-none','gpt-5.3-codex-spark')
$SettingsPath = Join-Path $ConfigDir 'settings.json'
$StateDir = Join-Path $ConfigDir 'keyproxy-claude'
$StatePath = Join-Path $StateDir 'state.json'
$HelperSource = Join-Path (Join-Path $PSScriptRoot 'bin') 'keyproxy-claude.ps1'
$HelperTarget = Join-Path $InstallBin 'keyproxy-claude.ps1'
$ManagedTop = @('model','availableModels','enforceAvailableModels','teammateDefaultModel','advisorModel')
$ManagedEnv = @('ANTHROPIC_BASE_URL','ANTHROPIC_AUTH_TOKEN','ANTHROPIC_DEFAULT_OPUS_MODEL','ANTHROPIC_DEFAULT_OPUS_MODEL_NAME','ANTHROPIC_DEFAULT_OPUS_MODEL_DESCRIPTION','ANTHROPIC_DEFAULT_FABLE_MODEL','ANTHROPIC_DEFAULT_FABLE_MODEL_NAME','ANTHROPIC_DEFAULT_FABLE_MODEL_DESCRIPTION','ANTHROPIC_DEFAULT_SONNET_MODEL','ANTHROPIC_DEFAULT_SONNET_MODEL_NAME','ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION','ANTHROPIC_DEFAULT_HAIKU_MODEL','ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME','ANTHROPIC_DEFAULT_HAIKU_MODEL_DESCRIPTION','ANTHROPIC_CUSTOM_MODEL_OPTION','ANTHROPIC_CUSTOM_MODEL_OPTION_NAME','ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION','CLAUDE_CODE_SUBAGENT_MODEL','KEYPROXY_API_KEY','KEYPROXY_MODELS_URL','ANTHROPIC_SMALL_FAST_MODEL','CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY')

function Read-JsonObject([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{} }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]@{} }
    return $raw | ConvertFrom-Json
}
function Has-Property($Object, [string]$Name) { return $null -ne $Object.PSObject.Properties[$Name] }
function Set-Property($Object, [string]$Name, $Value) {
    if (Has-Property $Object $Name) { $Object.$Name = $Value } else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}
function Remove-Property($Object, [string]$Name) { if (Has-Property $Object $Name) { $Object.PSObject.Properties.Remove($Name) } }
function Test-McpServer($Server) {
    if ($null -eq $Server -or $Server -isnot [pscustomobject]) { return $false }
    if (@($Server.PSObject.Properties).Count -ne 3) { return $false }
    if (-not (Has-Property $Server 'type') -or $Server.type -ne 'http') { return $false }
    if (-not (Has-Property $Server 'url') -or $Server.url -ne 'https://api.keyproxyhub.store/mcp') { return $false }
    if (-not (Has-Property $Server 'headers') -or $Server.headers -isnot [pscustomobject]) { return $false }
    if (@($Server.headers.PSObject.Properties).Count -ne 1 -or -not (Has-Property $Server.headers 'Authorization')) { return $false }
    return $Server.headers.Authorization -eq 'Bearer ${KEYPROXY_API_KEY}'
}
function Protect-UserFile([string]$Path) {
    if ($env:OS -ne 'Windows_NT' -or -not (Test-Path -LiteralPath $Path)) { return }
    $acl = Get-Acl -LiteralPath $Path
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) { $null = $acl.RemoveAccessRuleAll($rule) }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'Allow')
    $acl.SetAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl
}
function Write-JsonAtomic($Object, [string]$Path) {
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $temp = Join-Path $directory ('.' + [IO.Path]::GetRandomFileName())
    try {
        $json = $Object | ConvertTo-Json -Depth 100
        [IO.File]::WriteAllText($temp, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
        $null = Get-Content -LiteralPath $temp -Raw | ConvertFrom-Json
        Move-Item -LiteralPath $temp -Destination $Path -Force
        Protect-UserFile $Path
    } finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}
function Convert-SecureStringToText([Security.SecureString]$Secure) {
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
function Upgrade-State($State) {
    if (-not $State -or -not (Has-Property $State 'version')) { return $null }
    if ($State.version -eq 1) {
        foreach ($name in @('KEYPROXY_API_KEY','KEYPROXY_MODELS_URL')) {
            if (-not (Has-Property $State.env $name)) { $State.env | Add-Member -NotePropertyName $name -NotePropertyValue ([pscustomobject]@{ present = $false; value = $null }) }
        }
        $State.version = 2
        $State | Add-Member -NotePropertyName mcp -NotePropertyValue ([pscustomobject]@{ present = $false; value = $null })
    }
    return $State
}
function Test-State($State) {
    $State = Upgrade-State $State
    if (-not $State -or $State.version -ne 2) { return $false }
    if ((Has-Property $State 'pathAdded') -and $State.pathAdded -isnot [bool]) { return $false }
    foreach ($section in @(@('top',$ManagedTop),@('env',$ManagedEnv))) {
        $sectionName = $section[0]
        $keys = $section[1]
        if (-not (Has-Property $State $sectionName)) { return $false }
        $values = $State.$sectionName
        if (@($values.PSObject.Properties).Count -ne $keys.Count) { return $false }
        foreach ($name in $keys) {
            if (-not (Has-Property $values $name)) { return $false }
            $item = $values.$name
            if (-not (Has-Property $item 'present') -or $item.present -isnot [bool]) { return $false }
        }
    }
    return (Has-Property $State 'mcp') -and (Has-Property $State.mcp 'present') -and $State.mcp.present -is [bool]
}
function Test-Managed($Settings) {
    if (-not (Has-Property $Settings 'env') -or -not $Settings.env) { return $false }
    if (-not (Has-Property $Settings.env 'ANTHROPIC_BASE_URL') -or $Settings.env.ANTHROPIC_BASE_URL -ne $BaseUrl) { return $false }
    if (-not (Has-Property $Settings.env 'ANTHROPIC_AUTH_TOKEN') -or [string]::IsNullOrWhiteSpace([string]$Settings.env.ANTHROPIC_AUTH_TOKEN)) { return $false }
    if (-not (Has-Property $Settings 'model') -or $Settings.model -ne 'gpt-5.6-sol') { return $false }
    if (-not (Has-Property $Settings 'availableModels') -or @($Settings.availableModels).Count -ne $Models.Count) { return $false }
    for ($index = 0; $index -lt $Models.Count; $index++) { if ($Settings.availableModels[$index] -ne $Models[$index]) { return $false } }
    return (Has-Property $Settings 'enforceAvailableModels') -and $Settings.enforceAvailableModels -eq $true
}
function Restore-File([string]$Path, [bool]$Existed, [byte[]]$Bytes) {
    if ($Existed) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
        [IO.File]::WriteAllBytes($Path, $Bytes)
    } else {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
}

& claude --version *> $null
if ($LASTEXITCODE -ne 0) { throw 'Claude Code não foi encontrado ou claude --version falhou.' }
if (-not (Test-Path -LiteralPath $HelperSource)) { throw "Seletor ausente: $HelperSource" }

$OriginalApiKey = $env:KEYPROXY_API_KEY
$ApiKeyWasDefined = Test-Path Env:KEYPROXY_API_KEY
$ApiKey = $env:KEYPROXY_API_KEY
if ([string]::IsNullOrWhiteSpace($ApiKey)) { $ApiKey = Convert-SecureStringToText (Read-Host 'Cole sua API key do KeyProxy' -AsSecureString) }
if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw 'A API key não pode estar vazia.' }

$SettingsExisted = Test-Path -LiteralPath $SettingsPath
$ClaudeJsonExisted = Test-Path -LiteralPath $ClaudeJson
$StateExisted = Test-Path -LiteralPath $StatePath
$HelperExisted = Test-Path -LiteralPath $HelperTarget
$SettingsBytes = if ($SettingsExisted) { [IO.File]::ReadAllBytes($SettingsPath) } else { $null }
$ClaudeJsonBytes = if ($ClaudeJsonExisted) { [IO.File]::ReadAllBytes($ClaudeJson) } else { $null }
$StateBytes = if ($StateExisted) { [IO.File]::ReadAllBytes($StatePath) } else { $null }
$HelperBytes = if ($HelperExisted) { [IO.File]::ReadAllBytes($HelperTarget) } else { $null }
$OriginalUserPath = [Environment]::GetEnvironmentVariable('Path','User')
$OriginalProcessPath = $env:PATH
$TransactionStarted = $false

try {
    New-Item -ItemType Directory -Force -Path $ConfigDir,$StateDir,$InstallBin | Out-Null
    $settings = Read-JsonObject $SettingsPath
    $claudeConfig = Read-JsonObject $ClaudeJson
    if ((Has-Property $claudeConfig 'mcpServers') -and $claudeConfig.mcpServers -isnot [pscustomobject]) { throw '~/.claude.json.mcpServers precisa conter um objeto JSON.' }
    $mcpServers = if (Has-Property $claudeConfig 'mcpServers') { $claudeConfig.mcpServers } else { [pscustomobject]@{} }
    if ((Has-Property $mcpServers 'keyproxy') -and -not (Test-McpServer $mcpServers.keyproxy)) { throw "Já existe um servidor MCP 'keyproxy' divergente." }
    $preserveState = $false
    if (Test-Managed $settings) {
        if (-not $StateExisted) { throw 'A configuração KeyProxy está ativa, mas o snapshot original está ausente.' }
        $existingState = Upgrade-State (Read-JsonObject $StatePath)
        if (-not (Test-State $existingState)) { throw 'O estado KeyProxy existente é inválido.' }
        $preserveState = $true
    }

    if (-not $preserveState) {
        $existingPathParts = @($OriginalUserPath -split [IO.Path]::PathSeparator | Where-Object { $_ })
        $existingMcp = Has-Property $mcpServers 'keyproxy'
        $state = [pscustomobject]@{ version = 2; pathAdded = ($existingPathParts -notcontains $InstallBin); top = [pscustomobject]@{}; env = [pscustomobject]@{}; mcp = [pscustomobject]@{ present = $existingMcp; value = $(if ($existingMcp) { $mcpServers.keyproxy } else { $null }) } }
        if ((Has-Property $settings 'env') -and $settings.env -isnot [pscustomobject]) { throw 'settings.env precisa conter um objeto JSON.' }
        $snapshotEnv = if (Has-Property $settings 'env') { $settings.env } else { [pscustomobject]@{} }
        foreach ($name in $ManagedTop) {
            $present = Has-Property $settings $name
            $item = [pscustomobject]@{ present = $present; value = $(if ($present) { $settings.$name } else { $null }) }
            $state.top | Add-Member -NotePropertyName $name -NotePropertyValue $item
        }
        foreach ($name in $ManagedEnv) {
            $present = Has-Property $snapshotEnv $name
            $item = [pscustomobject]@{ present = $present; value = $(if ($present) { $snapshotEnv.$name } else { $null }) }
            $state.env | Add-Member -NotePropertyName $name -NotePropertyValue $item
        }
    }

    $TransactionStarted = $true
    if (-not $preserveState) { Write-JsonAtomic $state $StatePath }

    $oldEnv = if (Has-Property $settings 'env') { $settings.env } else { [pscustomobject]@{} }
    Set-Property $settings 'env' $oldEnv
    $values = [ordered]@{
        ANTHROPIC_BASE_URL=$BaseUrl; ANTHROPIC_AUTH_TOKEN=$ApiKey; ANTHROPIC_DEFAULT_OPUS_MODEL='gpt-5.6-sol';
        ANTHROPIC_DEFAULT_OPUS_MODEL_NAME='gpt-5.6-sol'; ANTHROPIC_DEFAULT_OPUS_MODEL_DESCRIPTION='KeyProxy - máxima capacidade';
        ANTHROPIC_DEFAULT_FABLE_MODEL='gpt-5.6-sol'; ANTHROPIC_DEFAULT_FABLE_MODEL_NAME='gpt-5.6-sol'; ANTHROPIC_DEFAULT_FABLE_MODEL_DESCRIPTION='KeyProxy - máxima capacidade';
        ANTHROPIC_DEFAULT_SONNET_MODEL='gpt-5.6-terra'; ANTHROPIC_DEFAULT_SONNET_MODEL_NAME='gpt-5.6-terra'; ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION='KeyProxy - equilíbrio entre capacidade e custo';
        ANTHROPIC_DEFAULT_HAIKU_MODEL='gpt-5.6-luna'; ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME='gpt-5.6-luna'; ANTHROPIC_DEFAULT_HAIKU_MODEL_DESCRIPTION='KeyProxy - execução rápida e eficiente com ferramentas';
        ANTHROPIC_CUSTOM_MODEL_OPTION='gpt-5.5'; ANTHROPIC_CUSTOM_MODEL_OPTION_NAME='gpt-5.5'; ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION='KeyProxy - opção premium alternativa';
        CLAUDE_CODE_SUBAGENT_MODEL='inherit'; KEYPROXY_API_KEY=$ApiKey; KEYPROXY_MODELS_URL=$ModelsUrl
    }
    foreach ($entry in $values.GetEnumerator()) { Set-Property $oldEnv $entry.Key $entry.Value }
    Remove-Property $oldEnv 'ANTHROPIC_SMALL_FAST_MODEL'
    Remove-Property $oldEnv 'CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY'
    Set-Property $settings 'model' 'gpt-5.6-sol'
    Set-Property $settings 'availableModels' $Models
    Set-Property $settings 'enforceAvailableModels' $true
    Remove-Property $settings 'teammateDefaultModel'
    Remove-Property $settings 'advisorModel'
    Write-JsonAtomic $settings $SettingsPath
    Set-Property $claudeConfig 'mcpServers' $mcpServers
    Set-Property $mcpServers 'keyproxy' $McpServer
    Write-JsonAtomic $claudeConfig $ClaudeJson
    if ($env:KEYPROXY_TEST_FAIL_AFTER_SETTINGS -eq '1') { throw 'Falha de teste após settings.' }

    Copy-Item -LiteralPath $HelperSource -Destination $HelperTarget -Force
    if ($env:KEYPROXY_TEST_FAIL_AFTER_HELPER -eq '1') { throw 'Falha de teste após helper.' }
    $pathParts = @($OriginalUserPath -split [IO.Path]::PathSeparator | Where-Object { $_ })
    if ($pathParts -notcontains $InstallBin) { [Environment]::SetEnvironmentVariable('Path', (($pathParts + $InstallBin) -join [IO.Path]::PathSeparator), 'User') }
    $processPathParts = @($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ })
    if ($processPathParts -notcontains $InstallBin) { $env:PATH = $InstallBin + [IO.Path]::PathSeparator + $env:PATH }
    $TransactionStarted = $false
} catch {
    if ($TransactionStarted) {
        Restore-File $SettingsPath $SettingsExisted $SettingsBytes
        Restore-File $ClaudeJson $ClaudeJsonExisted $ClaudeJsonBytes
        Restore-File $StatePath $StateExisted $StateBytes
        Restore-File $HelperTarget $HelperExisted $HelperBytes
        [Environment]::SetEnvironmentVariable('Path', $OriginalUserPath, 'User')
        $env:PATH = $OriginalProcessPath
    }
    throw
} finally {
    $ApiKey = $null
    if ($ApiKeyWasDefined) { $env:KEYPROXY_API_KEY = $OriginalApiKey }
    else { Remove-Item Env:KEYPROXY_API_KEY -ErrorAction SilentlyContinue }
    $OriginalApiKey = $null
}

Write-Output 'Instalação concluída. Abra um novo PowerShell e execute:'
Write-Output '  keyproxy-claude.ps1'
Write-Output 'Nenhum processo ou sessão existente foi encerrado.'
