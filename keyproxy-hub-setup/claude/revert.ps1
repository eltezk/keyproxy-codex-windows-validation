[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$ConfigDir = $(if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }),
    [string]$ClaudeJson = $(if ($env:KEYPROXY_CLAUDE_JSON) { $env:KEYPROXY_CLAUDE_JSON } else { Join-Path $HOME '.claude.json' })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$SettingsPath = Join-Path $ConfigDir 'settings.json'
$StatePath = Join-Path (Join-Path $ConfigDir 'keyproxy-claude') 'state.json'
$ManagedTop = @('model','availableModels','enforceAvailableModels','teammateDefaultModel','advisorModel')
$ManagedEnv = @('ANTHROPIC_BASE_URL','ANTHROPIC_AUTH_TOKEN','ANTHROPIC_DEFAULT_OPUS_MODEL','ANTHROPIC_DEFAULT_OPUS_MODEL_NAME','ANTHROPIC_DEFAULT_OPUS_MODEL_DESCRIPTION','ANTHROPIC_DEFAULT_FABLE_MODEL','ANTHROPIC_DEFAULT_FABLE_MODEL_NAME','ANTHROPIC_DEFAULT_FABLE_MODEL_DESCRIPTION','ANTHROPIC_DEFAULT_SONNET_MODEL','ANTHROPIC_DEFAULT_SONNET_MODEL_NAME','ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION','ANTHROPIC_DEFAULT_HAIKU_MODEL','ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME','ANTHROPIC_DEFAULT_HAIKU_MODEL_DESCRIPTION','ANTHROPIC_CUSTOM_MODEL_OPTION','ANTHROPIC_CUSTOM_MODEL_OPTION_NAME','ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION','CLAUDE_CODE_SUBAGENT_MODEL','KEYPROXY_API_KEY','KEYPROXY_MODELS_URL','ANTHROPIC_SMALL_FAST_MODEL','CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY')

function Has-Property($Object, [string]$Name) { return $null -ne $Object.PSObject.Properties[$Name] }
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
    foreach ($section in @(@('top',$ManagedTop),@('env',$ManagedEnv))) {
        $values = $State.($section[0])
        if (-not $values -or @($values.PSObject.Properties).Count -ne $section[1].Count) { return $false }
        foreach ($name in $section[1]) {
            if (-not (Has-Property $values $name)) { return $false }
            $item = $values.$name
            if (-not (Has-Property $item 'present') -or $item.present -isnot [bool]) { return $false }
        }
    }
    return (Has-Property $State 'mcp') -and (Has-Property $State.mcp 'present') -and $State.mcp.present -is [bool]
}
function Write-JsonAtomic($Object, [string]$Path) {
    $directory = Split-Path -Parent $Path
    $temp = Join-Path $directory ('.' + [IO.Path]::GetRandomFileName())
    try {
        $json = $Object | ConvertTo-Json -Depth 100
        [IO.File]::WriteAllText($temp, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
        $null = Get-Content -LiteralPath $temp -Raw | ConvertFrom-Json
        Move-Item -LiteralPath $temp -Destination $Path -Force
        Protect-UserFile $Path
    } finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

if (-not (Test-Path -LiteralPath $StatePath)) { throw "Estado anterior não encontrado: $StatePath" }
$settings = if (Test-Path -LiteralPath $SettingsPath) { Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
$state = Upgrade-State (Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json)
if (-not (Test-State $state)) { throw 'Estado KeyProxy inválido ou incompatível.' }
$claudeConfig = if (Test-Path -LiteralPath $ClaudeJson) { Get-Content -LiteralPath $ClaudeJson -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
if (-not $claudeConfig.PSObject.Properties['mcpServers']) { $claudeConfig | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{}) }
elseif ($claudeConfig.mcpServers -isnot [pscustomobject]) { throw '~/.claude.json.mcpServers precisa conter um objeto JSON.' }
if (-not $settings.PSObject.Properties['env']) { $settings | Add-Member -NotePropertyName env -NotePropertyValue ([pscustomobject]@{}) }
elseif ($settings.env -isnot [pscustomobject]) { throw 'settings.env precisa conter um objeto JSON.' }

foreach ($name in $ManagedTop) {
    $item = $state.top.$name
    if ($item.present) {
        if ($settings.PSObject.Properties[$name]) { $settings.$name = $item.value }
        else { $settings | Add-Member -NotePropertyName $name -NotePropertyValue $item.value }
    } elseif ($settings.PSObject.Properties[$name]) { $settings.PSObject.Properties.Remove($name) }
}
foreach ($name in $ManagedEnv) {
    $item = $state.env.$name
    if ($item.present) {
        if ($settings.env.PSObject.Properties[$name]) { $settings.env.$name = $item.value }
        else { $settings.env | Add-Member -NotePropertyName $name -NotePropertyValue $item.value }
    } elseif ($settings.env.PSObject.Properties[$name]) { $settings.env.PSObject.Properties.Remove($name) }
}
if (@($settings.env.PSObject.Properties).Count -eq 0) { $settings.PSObject.Properties.Remove('env') }
if ($state.mcp.present) {
    if ($claudeConfig.mcpServers.PSObject.Properties['keyproxy']) { $claudeConfig.mcpServers.keyproxy = $state.mcp.value }
    else { $claudeConfig.mcpServers | Add-Member -NotePropertyName keyproxy -NotePropertyValue $state.mcp.value }
} elseif ($claudeConfig.mcpServers.PSObject.Properties['keyproxy']) { $claudeConfig.mcpServers.PSObject.Properties.Remove('keyproxy') }
if (@($claudeConfig.mcpServers.PSObject.Properties).Count -eq 0) { $claudeConfig.PSObject.Properties.Remove('mcpServers') }

if ($DryRun) { Write-Output 'dry-run=ok'; exit 0 }
Write-JsonAtomic $settings $SettingsPath
Write-JsonAtomic $claudeConfig $ClaudeJson
Write-Output 'revert=ok'
Write-Output 'Nenhum processo ou sessão foi encerrado. Abra uma nova sessão para aplicar.'
