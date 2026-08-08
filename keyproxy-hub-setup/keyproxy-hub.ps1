#requires -Version 5.1
<#
.SYNOPSIS
Orquestra com segurança os módulos KeyProxy para Claude Code e Codex CLI.
#>
[CmdletBinding()]
param(
    [Parameter(Position=0)][ValidateSet('install-claude','open-claude','install-codex','status','validate','revert-claude','reset-claude','revert-codex','codex-recovery','help')][string]$Command,
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$RemainingArgs,
    [switch]$Yes,
    [string]$ClaudeDir = $(Join-Path $PSScriptRoot 'claude'),
    [string]$CodexDir = $(Join-Path $PSScriptRoot 'codex')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:UseColor = -not $env:NO_COLOR -and -not [Console]::IsOutputRedirected
$script:Reset = if ($script:UseColor) { "`e[0m" } else { '' }
$script:Accent = if ($script:UseColor) { "`e[38;5;208m" } else { '' }
$script:Dim = if ($script:UseColor) { "`e[2m" } else { '' }
$script:Ok = if ($script:UseColor) { "`e[38;5;114m" } else { '' }
$script:Warn = if ($script:UseColor) { "`e[38;5;220m" } else { '' }
$script:ErrorColor = if ($script:UseColor) { "`e[38;5;203m" } else { '' }

function Write-Line { Write-Output ($script:Dim + ('─' * 56) + $script:Reset) }
function Write-Card([string]$Text) { Write-Output ($script:Accent + $Text + $script:Reset) }
function Write-Ok([string]$Text) { Write-Output ($script:Ok + '[ok]' + $script:Reset + ' ' + $Text) }
function Write-HubWarning([string]$Text) { [Console]::Error.WriteLine($script:Warn + '[aviso]' + $script:Reset + ' ' + $Text) }
function Stop-Hub([string]$Text) { throw ($script:ErrorColor + '[erro]' + $script:Reset + ' ' + $Text) }

function Show-Banner {
    Write-Output ''
    Write-Output ($script:Accent + '  ██╗  ██╗██████╗ ' + $script:Reset)
    Write-Output ($script:Accent + '  ██║ ██╔╝██╔══██╗' + $script:Reset)
    Write-Output ($script:Accent + '  █████╔╝ ██████╔╝' + $script:Reset)
    Write-Output ($script:Accent + '  ██╔═██╗ ██╔═══╝ ' + $script:Reset)
    Write-Output ($script:Accent + '  ██║  ██╗██║     ' + $script:Reset)
    Write-Output ($script:Dim + '  KeyProxy Hub Setup · Claude Code + Codex CLI' + $script:Reset)
    Write-Line
}

function Show-Usage {
@'
KeyProxy Hub Setup

Uso: .\keyproxy-hub.ps1 [comando] [opções do módulo]

Comandos:
  install-claude       Configura ou atualiza o KeyProxy no Claude Code
  open-claude          Abre o seletor de modelos do Claude Code
  install-codex        Configura ou atualiza o KeyProxy no Codex CLI
  status               Mostra apenas estado local sanitizado
  validate             Valida a integridade e a sintaxe dos módulos do pacote
  revert-claude -Yes   Restaura o snapshot anterior do Claude Code
  reset-claude -Yes    Remove somente a configuração KeyProxy do Claude Code
  revert-codex -Yes    Restaura somente a configuração Codex registrada pelo KeyProxy
  codex-recovery       Mostra backup e instruções manuais seguras do Codex
  help                 Exibe esta ajuda

As operações de reversão exigem -Yes fora do menu. A reversão Codex só usa
um manifesto e backup criados pelo KeyProxy; credenciais e o Codex CLI são preservados.
'@ | Write-Output
}

function Assert-Module([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Stop-Hub "Módulo obrigatório ausente: $Path" }
}

function Invoke-ClaudeAction([string]$Action, [string[]]$Arguments) {
    $launcher = Join-Path $ClaudeDir 'keyproxy-claude.ps1'
    Assert-Module $launcher
    if (@($Arguments).Count -gt 0) { & $launcher $Action @Arguments } else { & $launcher $Action }
    $exitCode = Get-Variable -Name LASTEXITCODE -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $exitCode -and $exitCode -ne 0) { exit $exitCode }
}

function Invoke-CodexInstall([string[]]$Arguments) {
    $installer = Join-Path $CodexDir 'keyproxy-codex-install-windows.ps1'
    Assert-Module $installer
    if (@($Arguments).Count -gt 0) { & $installer @Arguments } else { & $installer }
    $exitCode = Get-Variable -Name LASTEXITCODE -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $exitCode -and $exitCode -ne 0) { exit $exitCode }
}

function Get-CodexHome {
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { return [IO.Path]::GetFullPath($env:CODEX_HOME) }
    return (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex')
}

function Test-KeyProxyCodexConfig([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $content = Get-Content -LiteralPath $Path -Raw
    return $content -match '(?m)^model\s*=\s*"gpt-5\.6-sol"\s*$' -and
        $content -match '(?m)^model_provider\s*=\s*"keyproxy"\s*$' -and
        $content -match '(?m)^\[model_providers\.keyproxy\]\s*$' -and
        $content -match '(?m)^\[mcp_servers\.keyproxy\]\s*$'
}

function Test-KeyProxyCodexBackup([string]$Config, [string]$Backup) {
    if ([string]::IsNullOrWhiteSpace($Backup) -or -not (Test-Path -LiteralPath $Backup -PathType Leaf)) { return $false }
    $configPath = [IO.Path]::GetFullPath($Config)
    $backupItem = Get-Item -LiteralPath $Backup -Force -ErrorAction SilentlyContinue
    if (-not $backupItem -or ($backupItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
    $backupPath = $backupItem.FullName
    return $backupPath.StartsWith($configPath + '.', [StringComparison]::Ordinal) -and
        $backupPath.EndsWith('.bak', [StringComparison]::OrdinalIgnoreCase)
}

function Test-KeyProxyCodexState([object]$State, [string]$Config) {
    return $State.version -eq 1 -and $State.createdBy -eq 'keyproxy-codex-install' -and
        $State.configPath -eq $Config -and $State.configExisted -is [bool]
}

function Show-CodexStatus {
    $codexHome = Get-CodexHome
    $config = Join-Path $codexHome 'config.toml'
    Write-Host -NoNewline 'Codex CLI: '
    try {
        $version = & codex --version 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'falha' }
        Write-Output ($version -join ' ')
    } catch { Write-Output 'não encontrado ou inválido' }
    Write-Output ('Configuração Codex: ' + $config)
    $homeItem = Get-Item -LiteralPath $codexHome -Force -ErrorAction SilentlyContinue
    $configItem = Get-Item -LiteralPath $config -Force -ErrorAction SilentlyContinue
    if (($homeItem -and ($homeItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) -or ($configItem -and ($configItem.Attributes -band [IO.FileAttributes]::ReparsePoint))) {
        Write-HubWarning 'O caminho de configuração Codex contém reparse point; nenhum arquivo será seguido pelo status.'
        return
    }
    if (-not (Test-Path -LiteralPath $config -PathType Leaf)) {
        Write-Output 'KeyProxy Codex: não configurado'
    } else {
        $content = Get-Content -LiteralPath $config -Raw
        $configured = $content -match '(?m)^model\s*=\s*"gpt-5\.6-sol"\s*$' -and
            $content -match '(?m)^model_provider\s*=\s*"keyproxy"\s*$' -and
            $content.Contains('[mcp_servers.keyproxy]')
        Write-Output ('KeyProxy Codex: ' + $(if ($configured) { 'configuração local ativa' } else { 'inativo ou divergente' }))
    }
    $state = Join-Path $codexHome 'keyproxy-codex-state.json'
    $stateItem = Get-Item -LiteralPath $state -Force -ErrorAction SilentlyContinue
    $statePresent = $stateItem -and -not ($stateItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $stateItem.PSIsContainer -eq $false
    Write-Output ('Recuperação Codex: ' + $(if ($statePresent) { 'manifesto KeyProxy presente' } else { 'não disponível' }))
    $credential = [Environment]::GetEnvironmentVariable('KEYPROXY_API_KEY', 'User')
    Write-Output ('Credencial Codex: ' + $(if ([string]::IsNullOrWhiteSpace($credential)) { 'não detectada' } else { 'variável do usuário presente e ocultada' }))
}

function Show-Status {
    Show-Banner
    Write-Card 'Claude Code'
    try { Invoke-ClaudeAction 'status' @() } catch { Write-HubWarning 'O status Claude retornou falha.' }
    Write-Output ''
    Write-Card 'Codex CLI'
    Show-CodexStatus
}

function Test-PowerShellSyntax([string]$Path) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    return @($errors).Count -eq 0
}

function Invoke-Validation {
    $failed = $false
    Show-Banner
    Write-Card 'Validação local do pacote (sem alterar configurações)'
    $files = @(
        (Join-Path $PSScriptRoot 'keyproxy-hub.ps1'),
        (Join-Path $ClaudeDir 'keyproxy-claude.ps1'),
        (Join-Path $ClaudeDir 'install.ps1'),
        (Join-Path $ClaudeDir 'revert.ps1'),
        (Join-Path $ClaudeDir 'reset-claude-default.ps1'),
        (Join-Path $CodexDir 'keyproxy-codex-install-windows.ps1')
    )
    foreach ($file in $files) {
        if ((Test-Path -LiteralPath $file -PathType Leaf) -and (Test-PowerShellSyntax $file)) { Write-Ok ('Sintaxe PowerShell: ' + $file.Substring($PSScriptRoot.Length + 1)) }
        else { Write-HubWarning ('Falha de sintaxe ou módulo ausente: ' + $file); $failed = $true }
    }
    $manifest = Join-Path $PSScriptRoot 'SHA256SUMS'
    if (Test-Path -LiteralPath $manifest -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $manifest) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -notmatch '^([0-9a-fA-F]{64})  (.+)$') { Write-HubWarning 'SHA256SUMS contém formato inválido.'; $failed = $true; continue }
            $expected = $Matches[1].ToLowerInvariant(); $relative = $Matches[2]
            if ($relative.StartsWith('./') -or $relative.StartsWith('.\\')) { $relative = $relative.Substring(2) }
            $path = Join-Path $PSScriptRoot $relative
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Write-HubWarning ('Arquivo do checksum ausente: ' + $relative); $failed = $true; continue }
            $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -ne $expected) { Write-HubWarning ('Checksum divergente: ' + $relative); $failed = $true }
        }
        if (-not $failed) { Write-Ok 'Checksums do pacote' }
    } else { Write-HubWarning 'SHA256SUMS ausente.'; $failed = $true }
    if ($failed) { exit 1 }
    Write-Ok 'Validação local concluída'
}

function Restore-KeyProxyCodex {
    $codexHome = Get-CodexHome
    $config = Join-Path $codexHome 'config.toml'
    $statePath = Join-Path $codexHome 'keyproxy-codex-state.json'
    $homeItem = Get-Item -LiteralPath $codexHome -Force -ErrorAction SilentlyContinue
    $configItem = Get-Item -LiteralPath $config -Force -ErrorAction SilentlyContinue
    $stateItem = Get-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    if (($homeItem -and ($homeItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) -or
        ($configItem -and ($configItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) -or
        -not $stateItem -or ($stateItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $stateItem.PSIsContainer) {
        Stop-Hub 'Não há manifesto KeyProxy seguro para este CODEX_HOME; nenhum arquivo foi alterado.'
    }
    try { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json }
    catch { Stop-Hub 'O manifesto KeyProxy é inválido; nenhum arquivo foi alterado.' }
    if (-not (Test-KeyProxyCodexState -State $state -Config $config)) {
        Stop-Hub 'O manifesto KeyProxy é inválido para este CODEX_HOME; nenhum arquivo foi alterado.'
    }
    if (-not (Test-KeyProxyCodexConfig -Path $config)) {
        Stop-Hub 'A configuração ativa do Codex não pertence ao KeyProxy; nenhum arquivo será sobrescrito.'
    }
    if ($state.configExisted) {
        $backupItem = Get-Item -LiteralPath $state.configBackup -Force -ErrorAction SilentlyContinue
        if (-not $backupItem -or $backupItem.PSIsContainer -or -not (Test-KeyProxyCodexBackup -Config $config -Backup $backupItem.FullName)) {
            Stop-Hub 'O backup registrado pelo KeyProxy não está disponível ou não é seguro; nenhum arquivo foi alterado.'
        }
        $staged = Join-Path $codexHome ('.config.toml.restore-keyproxy.{0}' -f $PID)
        Copy-Item -LiteralPath $backupItem.FullName -Destination $staged
        Move-Item -LiteralPath $staged -Destination $config -Force
        Write-Ok 'Configuração Codex restaurada a partir do backup registrado pelo KeyProxy.'
    }
    else {
        if (-not [string]::IsNullOrWhiteSpace([string]$state.configBackup)) {
            Stop-Hub 'O manifesto de recuperação contém backup inesperado; nenhum arquivo foi alterado.'
        }
        Remove-Item -LiteralPath $config -Force -ErrorAction SilentlyContinue
        Write-Ok 'Configuração Codex criada pelo KeyProxy foi removida.'
    }
    Remove-Item -LiteralPath $statePath -Force
    Write-Output 'A credencial KEYPROXY_API_KEY e o Codex CLI foram preservados. Remova a credencial manualmente somente se desejar.'
}

function Show-CodexRecovery {
    $codexHome = Get-CodexHome
    $config = Join-Path $codexHome 'config.toml'
    $statePath = Join-Path $codexHome 'keyproxy-codex-state.json'
    Show-Banner
    Write-Card 'Recuperação manual segura do Codex CLI'
    Write-Output ('Configuração ativa esperada: ' + $config)
    $homeItem = Get-Item -LiteralPath $codexHome -Force -ErrorAction SilentlyContinue
    $stateItem = Get-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    if (($homeItem -and ($homeItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) -or
        -not $stateItem -or ($stateItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $stateItem.PSIsContainer) {
        Write-HubWarning 'Não há manifesto KeyProxy seguro para este CODEX_HOME; nenhum arquivo será alterado.'
        return
    }
    try { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json }
    catch { Write-HubWarning 'O manifesto KeyProxy é inválido; nenhum arquivo será alterado.'; return }
    if (-not (Test-KeyProxyCodexState -State $state -Config $config)) {
        Write-HubWarning 'O manifesto KeyProxy é inválido para este CODEX_HOME; nenhum arquivo será alterado.'
        return
    }
    if (-not $state.configExisted) {
        Write-Output 'O KeyProxy criou o config.toml originalmente; não há backup anterior a restaurar.'
    }
    else {
        $backupItem = Get-Item -LiteralPath $state.configBackup -Force -ErrorAction SilentlyContinue
        if (-not $backupItem -or $backupItem.PSIsContainer -or -not (Test-KeyProxyCodexBackup -Config $config -Backup $backupItem.FullName)) {
            Write-HubWarning 'O backup registrado pelo KeyProxy não está disponível ou não é seguro; nenhum arquivo será alterado.'
            return
        }
        Write-Output ('Backup KeyProxy registrado: ' + $backupItem.FullName)
        Write-Output ''
        Write-Output 'Antes de restaurar manualmente: confira o backup e mantenha uma cópia do config.toml atual.'
        Write-Output ('Comando revisável: Copy-Item -LiteralPath "' + $backupItem.FullName + '" -Destination "' + $config + '" -Force')
    }
    Write-Output "Depois, se não precisar mais da credencial KeyProxy, remova manualmente: [Environment]::SetEnvironmentVariable('KEYPROXY_API_KEY', `$null, 'User')"
    Write-Output 'Nenhum arquivo foi alterado por esta opção.'
}

function Confirm-Action([string]$Prompt) {
    return (Read-Host ($Prompt + ' [s/N]')) -match '^[sS]$'
}

function Show-Menu {
    while ($true) {
        Show-Banner
@'
  1. Configurar ou atualizar KeyProxy no Claude Code
  2. Abrir seletor de modelos do Claude Code
  3. Configurar ou atualizar KeyProxy no Codex CLI
  4. Mostrar status sanitizado
  5. Validar módulos do pacote
  6. Restaurar configuração anterior do Claude Code
  7. Voltar Claude Code ao provider oficial
  8. Restaurar ou remover com segurança a configuração KeyProxy do Codex CLI
  9. Mostrar informações de recuperação do Codex CLI
 10. Sair
'@ | Write-Output
        switch (Read-Host 'Escolha uma opção') {
            '1' { Invoke-ClaudeAction 'install' @() }
            '2' { Invoke-ClaudeAction 'open' @() }
            '3' { Invoke-CodexInstall @() }
            '4' { Show-Status }
            '5' { Invoke-Validation }
            '6' { if (Confirm-Action 'Restaurar o snapshot anterior do Claude Code?') { Invoke-ClaudeAction 'revert' @() } else { Write-HubWarning 'Operação cancelada.' } }
            '7' { if (Confirm-Action 'Remover KeyProxy do Claude Code e voltar ao provider oficial?') { Invoke-ClaudeAction 'reset' @() } else { Write-HubWarning 'Operação cancelada.' } }
            '8' { if (Confirm-Action 'Restaurar ou remover somente a configuração KeyProxy do Codex CLI?') { Restore-KeyProxyCodex } else { Write-HubWarning 'Operação cancelada.' } }
            '9' { Show-CodexRecovery }
            '10' { return }
            default { Write-HubWarning 'Opção inválida.' }
        }
        [void](Read-Host 'Pressione Enter para voltar ao menu')
    }
}

if (-not $Command) { Show-Menu; exit 0 }
switch ($Command) {
    'install-claude' { Invoke-ClaudeAction -Action 'install' -Arguments @($RemainingArgs | Where-Object { $null -ne $_ }) }
    'open-claude' { Invoke-ClaudeAction -Action 'open' -Arguments @($RemainingArgs | Where-Object { $null -ne $_ }) }
    'install-codex' { Invoke-CodexInstall -Arguments @($RemainingArgs | Where-Object { $null -ne $_ }) }
    'status' { Show-Status }
    'validate' { Invoke-Validation }
    'codex-recovery' { Show-CodexRecovery }
    'revert-codex' { if (-not $Yes) { Stop-Hub 'revert-codex exige -Yes fora do menu.' }; Restore-KeyProxyCodex }
    'revert-claude' { if (-not $Yes) { Stop-Hub 'revert-claude exige -Yes fora do menu.' }; Invoke-ClaudeAction -Action 'revert' -Arguments @($RemainingArgs | Where-Object { $null -ne $_ }) }
    'reset-claude' { if (-not $Yes) { Stop-Hub 'reset-claude exige -Yes fora do menu.' }; Invoke-ClaudeAction -Action 'reset' -Arguments @($RemainingArgs | Where-Object { $null -ne $_ }) }
    'help' { Show-Usage }
}
