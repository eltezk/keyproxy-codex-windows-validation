[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$ConfigDir = $(if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }),
    [string]$InstallBin = $(Join-Path (Join-Path $HOME '.local') 'bin'),
    [string]$ClaudeJson = $(if ($env:KEYPROXY_CLAUDE_JSON) { $env:KEYPROXY_CLAUDE_JSON } else { Join-Path $HOME '.claude.json' })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$SettingsPath = Join-Path $ConfigDir 'settings.json'
$StatePath = Join-Path (Join-Path $ConfigDir 'keyproxy-claude') 'state.json'
$HelperPath = Join-Path $InstallBin 'keyproxy-claude.ps1'
$EnvKeys = @('ANTHROPIC_BASE_URL','ANTHROPIC_AUTH_TOKEN','ANTHROPIC_DEFAULT_OPUS_MODEL','ANTHROPIC_DEFAULT_OPUS_MODEL_NAME','ANTHROPIC_DEFAULT_OPUS_MODEL_DESCRIPTION','ANTHROPIC_DEFAULT_FABLE_MODEL','ANTHROPIC_DEFAULT_FABLE_MODEL_NAME','ANTHROPIC_DEFAULT_FABLE_MODEL_DESCRIPTION','ANTHROPIC_DEFAULT_SONNET_MODEL','ANTHROPIC_DEFAULT_SONNET_MODEL_NAME','ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION','ANTHROPIC_DEFAULT_HAIKU_MODEL','ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME','ANTHROPIC_DEFAULT_HAIKU_MODEL_DESCRIPTION','ANTHROPIC_CUSTOM_MODEL_OPTION','ANTHROPIC_CUSTOM_MODEL_OPTION_NAME','ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION','CLAUDE_CODE_SUBAGENT_MODEL','KEYPROXY_API_KEY','KEYPROXY_MODELS_URL','ANTHROPIC_SMALL_FAST_MODEL','CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY')
$TopKeys = @('model','availableModels','enforceAvailableModels','teammateDefaultModel','advisorModel')

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
    $temp = Join-Path $directory ('.' + [IO.Path]::GetRandomFileName())
    try {
        $json = $Object | ConvertTo-Json -Depth 100
        [IO.File]::WriteAllText($temp, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
        $null = Get-Content -LiteralPath $temp -Raw | ConvertFrom-Json
        Move-Item -LiteralPath $temp -Destination $Path -Force
        Protect-UserFile $Path
    } finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}
function Restore-File([string]$Path, [bool]$Existed, [byte[]]$Bytes) {
    if ($Existed) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
        [IO.File]::WriteAllBytes($Path, $Bytes)
    } else { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
}

$settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
if (-not $settings.PSObject.Properties['env']) { $settings | Add-Member -NotePropertyName env -NotePropertyValue ([pscustomobject]@{}) }
elseif ($settings.env -isnot [pscustomobject]) { throw 'settings.env precisa conter um objeto JSON.' }
foreach ($key in $EnvKeys) { if ($settings.env.PSObject.Properties[$key]) { $settings.env.PSObject.Properties.Remove($key) } }
foreach ($key in $TopKeys) { if ($settings.PSObject.Properties[$key]) { $settings.PSObject.Properties.Remove($key) } }
if (@($settings.env.PSObject.Properties).Count -eq 0) { $settings.PSObject.Properties.Remove('env') }
$claudeConfig = if (Test-Path -LiteralPath $ClaudeJson) { Get-Content -LiteralPath $ClaudeJson -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
if ($claudeConfig.PSObject.Properties['mcpServers']) {
    if ($claudeConfig.mcpServers -isnot [pscustomobject]) { throw '~/.claude.json.mcpServers precisa conter um objeto JSON.' }
    if ($claudeConfig.mcpServers.PSObject.Properties['keyproxy']) {
        $server = $claudeConfig.mcpServers.keyproxy
        $isManagedMcp = $server -is [pscustomobject] -and
            @($server.PSObject.Properties).Count -eq 3 -and
            $server.PSObject.Properties['type'] -and $server.type -eq 'http' -and
            $server.PSObject.Properties['url'] -and $server.url -eq 'https://api.keyproxyhub.store/mcp' -and
            $server.PSObject.Properties['headers'] -and $server.headers -is [pscustomobject] -and
            @($server.headers.PSObject.Properties).Count -eq 1 -and
            $server.headers.PSObject.Properties['Authorization'] -and
            $server.headers.Authorization -eq 'Bearer ${KEYPROXY_API_KEY}'
        if ($isManagedMcp) { $claudeConfig.mcpServers.PSObject.Properties.Remove('keyproxy') }
        else { throw "O servidor MCP 'keyproxy' está divergente; reset recusado para não remover configuração não gerenciada." }
    }
    if (@($claudeConfig.mcpServers.PSObject.Properties).Count -eq 0) { $claudeConfig.PSObject.Properties.Remove('mcpServers') }
}
if ($DryRun) { Write-Output 'dry-run=ok'; exit 0 }

$SettingsBytes = [IO.File]::ReadAllBytes($SettingsPath)
$ClaudeJsonExisted = Test-Path -LiteralPath $ClaudeJson
$ClaudeJsonBytes = if ($ClaudeJsonExisted) { [IO.File]::ReadAllBytes($ClaudeJson) } else { $null }
$StateExisted = Test-Path -LiteralPath $StatePath
$StateBytes = if ($StateExisted) { [IO.File]::ReadAllBytes($StatePath) } else { $null }
$PathAdded = $false
if ($StateExisted) {
    try {
        $savedState = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
        if ($savedState.PSObject.Properties['pathAdded'] -and $savedState.pathAdded -is [bool]) { $PathAdded = $savedState.pathAdded }
    } catch { $PathAdded = $false }
}
$HelperExisted = Test-Path -LiteralPath $HelperPath
$HelperBytes = if ($HelperExisted) { [IO.File]::ReadAllBytes($HelperPath) } else { $null }
$OriginalUserPath = [Environment]::GetEnvironmentVariable('Path','User')
$OriginalProcessPath = $env:PATH
try {
    Write-JsonAtomic $settings $SettingsPath
    Write-JsonAtomic $claudeConfig $ClaudeJson
    if (Test-Path -LiteralPath $HelperPath) { Remove-Item -LiteralPath $HelperPath -Force -ErrorAction Stop }
    if (Test-Path -LiteralPath $StatePath) { Remove-Item -LiteralPath $StatePath -Force -ErrorAction Stop }
    if ((Test-Path -LiteralPath $HelperPath) -or (Test-Path -LiteralPath $StatePath)) { throw 'Não foi possível remover todos os artefatos do KeyProxy.' }
    if ($env:KEYPROXY_TEST_FAIL_AFTER_RESET_FILES -eq '1') { throw 'Falha de teste após remover artefatos do reset.' }
    if ($PathAdded) {
        $parts = @($OriginalUserPath -split [IO.Path]::PathSeparator | Where-Object { $_ -and $_ -ne $InstallBin })
        [Environment]::SetEnvironmentVariable('Path', ($parts -join [IO.Path]::PathSeparator), 'User')
        $env:PATH = (@($OriginalProcessPath -split [IO.Path]::PathSeparator | Where-Object { $_ -and $_ -ne $InstallBin }) -join [IO.Path]::PathSeparator)
    }
} catch {
    Restore-File $SettingsPath $true $SettingsBytes
    Restore-File $ClaudeJson $ClaudeJsonExisted $ClaudeJsonBytes
    Restore-File $StatePath $StateExisted $StateBytes
    Restore-File $HelperPath $HelperExisted $HelperBytes
    [Environment]::SetEnvironmentVariable('Path', $OriginalUserPath, 'User')
    $env:PATH = $OriginalProcessPath
    throw
}
Write-Output 'reset=ok'
Write-Output 'O próximo uso pode solicitar login oficial. Nenhum processo foi encerrado.'
