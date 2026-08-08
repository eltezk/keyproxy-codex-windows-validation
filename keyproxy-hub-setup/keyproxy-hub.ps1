#requires -Version 5.1
<#
.SYNOPSIS
Orquestra com segurança os módulos KeyProxy para Claude Code e Codex CLI.
#>
[CmdletBinding()]
param(
    [Parameter(Position=0)][ValidateSet('install-claude','open-claude','install-codex','status','validate','revert-claude','reset-claude','codex-recovery','help')][string]$Command,
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
  codex-recovery       Mostra backups e instruções manuais seguras do Codex
  help                 Exibe esta ajuda

As operações de reversão exigem -Yes fora do menu. O pacote não executa
reversão automática do Codex: somente informa backups comprováveis.
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
    $backups = @(if (Test-Path -LiteralPath $codexHome -PathType Container) { Get-ChildItem -LiteralPath $codexHome -File -Filter 'config.toml.*.bak' -ErrorAction SilentlyContinue })
    Write-Output ('Backups Codex: {0}' -f $backups.Count)
    $credential = Join-Path (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config') 'keyproxy\env'
    Write-Output ('Credencial Codex: ' + $(if (Test-Path -LiteralPath $credential -PathType Leaf) { 'arquivo local presente e ocultado' } else { 'não detectada' }))
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

function Show-CodexRecovery {
    $codexHome = Get-CodexHome
    $config = Join-Path $codexHome 'config.toml'
    Show-Banner
    Write-Card 'Recuperação manual segura do Codex CLI'
    Write-Output ('Configuração ativa esperada: ' + $config)
    $backups = @(if ((Test-Path -LiteralPath $codexHome -PathType Container) -and -not ((Get-Item -LiteralPath $codexHome -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { Get-ChildItem -LiteralPath $codexHome -File -Filter 'config.toml.*.bak' -ErrorAction SilentlyContinue | Sort-Object FullName })
    if ($backups.Count -eq 0) {
        Write-HubWarning 'Nenhum backup comprovável foi encontrado; não há reversão automática disponível.'
        return
    }
    foreach ($backup in $backups) { Write-Output ('Backup encontrado: ' + $backup.FullName) }
    Write-Output ''
    Write-Output 'Antes de restaurar manualmente: confira o backup e mantenha uma cópia do config.toml atual.'
    Write-Output 'Exemplo (substitua <BACKUP> por um caminho listado acima):'
    Write-Output ('  Copy-Item -LiteralPath "<BACKUP>" -Destination "' + $config + '" -Force')
    Write-Output ('Depois, se não precisar mais da credencial KeyProxy, remova manualmente: ' + (Join-Path (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config') 'keyproxy\env'))
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
  8. Mostrar recuperação manual segura do Codex CLI
  9. Sair
'@ | Write-Output
        switch (Read-Host 'Escolha uma opção') {
            '1' { Invoke-ClaudeAction 'install' @() }
            '2' { Invoke-ClaudeAction 'open' @() }
            '3' { Invoke-CodexInstall @() }
            '4' { Show-Status }
            '5' { Invoke-Validation }
            '6' { if (Confirm-Action 'Restaurar o snapshot anterior do Claude Code?') { Invoke-ClaudeAction 'revert' @() } else { Write-HubWarning 'Operação cancelada.' } }
            '7' { if (Confirm-Action 'Remover KeyProxy do Claude Code e voltar ao provider oficial?') { Invoke-ClaudeAction 'reset' @() } else { Write-HubWarning 'Operação cancelada.' } }
            '8' { Show-CodexRecovery }
            '9' { return }
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
    'revert-claude' { if (-not $Yes) { Stop-Hub 'revert-claude exige -Yes fora do menu.' }; Invoke-ClaudeAction -Action 'revert' -Arguments @($RemainingArgs | Where-Object { $null -ne $_ }) }
    'reset-claude' { if (-not $Yes) { Stop-Hub 'reset-claude exige -Yes fora do menu.' }; Invoke-ClaudeAction -Action 'reset' -Arguments @($RemainingArgs | Where-Object { $null -ne $_ }) }
    'help' { Show-Usage }
}
