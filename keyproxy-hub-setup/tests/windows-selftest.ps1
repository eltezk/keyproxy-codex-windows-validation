$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('keyproxy-hub-' + [guid]::NewGuid())
$OriginalCodexHome = $env:CODEX_HOME
$CodexHomeWasDefined = Test-Path Env:CODEX_HOME
$OriginalApiKey = $env:KEYPROXY_API_KEY
$ApiKeyWasDefined = Test-Path Env:KEYPROXY_API_KEY
$Utf8NoBom = New-Object Text.UTF8Encoding($false)
try {
    $ClaudeDir = Join-Path $Temp 'claude'
    $CodexDir = Join-Path $Temp 'codex'
    $HomeDir = Join-Path $Temp 'home'
    New-Item -ItemType Directory -Force -Path $ClaudeDir,$CodexDir,(Join-Path $HomeDir '.codex') | Out-Null
    $env:CODEX_HOME = Join-Path $HomeDir '.codex'
    $env:KEYPROXY_API_KEY = 'kp_test_not_real'

    @'
param([Parameter(Position=0)][string]$Action)
Write-Output ('claude-action=' + $Action)
if ($Action -eq 'status') { Write-Output 'Configuração: KeyProxy ativa'; Write-Output 'Credencial: configurada e ocultada' }
'@ | Set-Content -LiteralPath (Join-Path $ClaudeDir 'keyproxy-claude.ps1') -Encoding UTF8

    @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
Write-Output ('codex-action=install args=' + ($Arguments -join ' '))
'@ | Set-Content -LiteralPath (Join-Path $CodexDir 'keyproxy-codex-install-windows.ps1') -Encoding UTF8

    $Hub = Join-Path $Root 'keyproxy-hub.ps1'
    $install = @(& $Hub install-claude -ClaudeDir $ClaudeDir -CodexDir $CodexDir 3>$null) -join "`n"
    if ($install -notmatch '(?m)^claude-action=install$') { throw 'Instalação Claude não foi roteada' }

    $codex = @(& $Hub install-codex -ClaudeDir $ClaudeDir -CodexDir $CodexDir -SkipApiTest 3>$null) -join "`n"
    if ($codex -notmatch 'codex-action=install args=-SkipApiTest') { throw 'Instalação Codex não foi roteada' }

    $status = @(& $Hub status -ClaudeDir $ClaudeDir -CodexDir $CodexDir 3>$null) -join "`n"
    if ($status -notmatch 'Claude Code' -or $status -notmatch 'claude-action=status' -or $status -notmatch 'Codex CLI' -or $status -notmatch 'KeyProxy Codex: não configurado') { throw 'Status unificado inválido' }
    if ($status -match 'kp_test_not_real') { throw 'Status expôs segredo' }

    try { & $Hub revert-claude -ClaudeDir $ClaudeDir -CodexDir $CodexDir 3>$null; throw 'Revert sem -Yes foi aceito' }
    catch { if ($_.Exception.Message -match 'Revert sem -Yes foi aceito') { throw } }
    $revert = @(& $Hub revert-claude -Yes -ClaudeDir $ClaudeDir -CodexDir $CodexDir 3>$null) -join "`n"
    if ($revert -notmatch '(?m)^claude-action=revert$') { throw 'Revert confirmado não foi roteado' }

    try { & $Hub reset-claude -ClaudeDir $ClaudeDir -CodexDir $CodexDir 3>$null; throw 'Reset sem -Yes foi aceito' }
    catch { if ($_.Exception.Message -match 'Reset sem -Yes foi aceito') { throw } }
    $reset = @(& $Hub reset-claude -Yes -ClaudeDir $ClaudeDir -CodexDir $CodexDir 3>$null) -join "`n"
    if ($reset -notmatch '(?m)^claude-action=reset$') { throw 'Reset confirmado não foi roteado' }

    $beforeRecovery = @((Get-ChildItem -LiteralPath $env:CODEX_HOME -Force | Select-Object -ExpandProperty Name)) -join "`n"
    & $Hub codex-recovery -ClaudeDir $ClaudeDir -CodexDir $CodexDir 3>$null | Out-Null
    $afterRecovery = @((Get-ChildItem -LiteralPath $env:CODEX_HOME -Force | Select-Object -ExpandProperty Name)) -join "`n"
    if ($beforeRecovery -ne $afterRecovery) { throw 'Recuperação Codex alterou arquivos' }

    $config = Join-Path $env:CODEX_HOME 'config.toml'
    $backup = Join-Path $env:CODEX_HOME 'config.toml.before-keyproxy.bak'
    $state = Join-Path $env:CODEX_HOME 'keyproxy-codex-state.json'
    [IO.File]::WriteAllText($backup, "model = `"original`"`n", $Utf8NoBom)
    $keyProxyConfig = @'
model = "gpt-5.6-sol"
model_provider = "keyproxy"

[model_providers.keyproxy]
name = "KeyProxy Hub"

[mcp_servers.keyproxy]
enabled = true
'@
    [IO.File]::WriteAllText($config, $keyProxyConfig, $Utf8NoBom)
    [IO.File]::WriteAllText($state, (@{ version = 1; configPath = $config; configExisted = $true; configBackup = $backup; createdBy = 'keyproxy-codex-install' } | ConvertTo-Json -Compress), $Utf8NoBom)

    try { & $Hub revert-codex -ClaudeDir $ClaudeDir -CodexDir $CodexDir 3>$null; throw 'Reversão Codex sem -Yes foi aceita' }
    catch { if ($_.Exception.Message -match 'Reversão Codex sem -Yes foi aceita') { throw } }
    $restored = @(& $Hub revert-codex -Yes -ClaudeDir $ClaudeDir -CodexDir $CodexDir 3>$null) -join "`n"
    if ($restored -notmatch 'Configuração Codex restaurada' -or (Get-Content -LiteralPath $config -Raw) -ne (Get-Content -LiteralPath $backup -Raw)) { throw 'Backup Codex não foi restaurado' }
    if (Test-Path -LiteralPath $state) { throw 'Manifesto Codex não foi removido após restauração' }
    if ($env:KEYPROXY_API_KEY -ne 'kp_test_not_real') { throw 'Reversão Codex alterou credencial' }

    [IO.File]::WriteAllText($config, $keyProxyConfig, $Utf8NoBom)
    [IO.File]::WriteAllText($state, (@{ version = 1; configPath = $config; configExisted = $false; configBackup = ''; createdBy = 'keyproxy-codex-install' } | ConvertTo-Json -Compress), $Utf8NoBom)
    & $Hub revert-codex -Yes -ClaudeDir $ClaudeDir -CodexDir $CodexDir 3>$null | Out-Null
    if (Test-Path -LiteralPath $config) { throw 'Configuração Codex criada pelo KeyProxy não foi removida' }
    if (Test-Path -LiteralPath $state) { throw 'Manifesto Codex não foi removido após exclusão' }
    if ($env:KEYPROXY_API_KEY -ne 'kp_test_not_real') { throw 'Reversão Codex alterou credencial na exclusão' }

    [IO.File]::WriteAllText($config, "model = `"user-choice`"`n", $Utf8NoBom)
    [IO.File]::WriteAllText($state, (@{ version = 1; configPath = $config; configExisted = $false; configBackup = ''; createdBy = 'keyproxy-codex-install' } | ConvertTo-Json -Compress), $Utf8NoBom)
    try { & $Hub revert-codex -Yes -ClaudeDir $ClaudeDir -CodexDir $CodexDir 3>$null; throw 'Reversão Codex sobrescreveu configuração divergente' }
    catch { if ($_.Exception.Message -match 'Reversão Codex sobrescreveu configuração divergente') { throw } }
    if ((Get-Content -LiteralPath $config -Raw) -notmatch 'user-choice' -or -not (Test-Path -LiteralPath $state)) { throw 'Reversão Codex alterou configuração divergente' }

    [IO.File]::WriteAllText($config, $keyProxyConfig, $Utf8NoBom)
    $externalBackup = Join-Path $Temp 'backup-terceiro.bak'
    [IO.File]::WriteAllText($externalBackup, "model = `"third-party`"`n", $Utf8NoBom)
    [IO.File]::WriteAllText($state, (@{ version = 1; configPath = $config; configExisted = $true; configBackup = $externalBackup; createdBy = 'keyproxy-codex-install' } | ConvertTo-Json -Compress), $Utf8NoBom)
    try { & $Hub revert-codex -Yes -ClaudeDir $ClaudeDir -CodexDir $CodexDir 3>$null; throw 'Reversão Codex aceitou backup externo' }
    catch { if ($_.Exception.Message -match 'Reversão Codex aceitou backup externo') { throw } }
    if ((Get-Content -LiteralPath $config -Raw) -notmatch 'gpt-5.6-sol' -or -not (Test-Path -LiteralPath $state)) { throw 'Reversão Codex alterou estado com backup externo' }

    [IO.File]::WriteAllText($config, $keyProxyConfig, $Utf8NoBom)
    [IO.File]::WriteAllText($state, (@{ version = 1; configPath = $config; configExisted = $false; configBackup = ''; createdBy = 'terceiro' } | ConvertTo-Json -Compress), $Utf8NoBom)
    try { & $Hub revert-codex -Yes -ClaudeDir $ClaudeDir -CodexDir $CodexDir 3>$null; throw 'Reversão Codex aceitou manifesto forjado' }
    catch { if ($_.Exception.Message -match 'Reversão Codex aceitou manifesto forjado') { throw } }
    if ((Get-Content -LiteralPath $config -Raw) -notmatch 'gpt-5.6-sol' -or -not (Test-Path -LiteralPath $state)) { throw 'Reversão Codex alterou estado com manifesto forjado' }

    Write-Output 'hub-windows-selftest=ok'
} finally {
    if ($CodexHomeWasDefined) { $env:CODEX_HOME = $OriginalCodexHome } else { Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue }
    if ($ApiKeyWasDefined) { $env:KEYPROXY_API_KEY = $OriginalApiKey } else { Remove-Item Env:KEYPROXY_API_KEY -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
}
