$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('keyproxy-hub-' + [guid]::NewGuid())
$OriginalCodexHome = $env:CODEX_HOME
$CodexHomeWasDefined = Test-Path Env:CODEX_HOME
try {
    $ClaudeDir = Join-Path $Temp 'claude'
    $CodexDir = Join-Path $Temp 'codex'
    $HomeDir = Join-Path $Temp 'home'
    New-Item -ItemType Directory -Force -Path $ClaudeDir,$CodexDir,(Join-Path $HomeDir '.codex') | Out-Null
    $env:CODEX_HOME = Join-Path $HomeDir '.codex'

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
    & $Hub codex-recovery -ClaudeDir $ClaudeDir -CodexDir $CodexDir 3>$null
    $afterRecovery = @((Get-ChildItem -LiteralPath $env:CODEX_HOME -Force | Select-Object -ExpandProperty Name)) -join "`n"
    if ($beforeRecovery -ne $afterRecovery) { throw 'Recuperação Codex alterou arquivos' }

    Write-Output 'hub-windows-selftest=ok'
} finally {
    if ($CodexHomeWasDefined) { $env:CODEX_HOME = $OriginalCodexHome } else { Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
}
