[CmdletBinding()]
param(
    [Parameter(Position=0)][ValidateSet('install','open','list','status','revert','reset','help')][string]$Command,
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$RemainingArgs,
    [string]$ConfigDir = $(if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }),
    [string]$InstallBin = $(Join-Path (Join-Path $HOME '.local') 'bin'),
    [string]$ClaudeJson = $(if ($env:KEYPROXY_CLAUDE_JSON) { $env:KEYPROXY_CLAUDE_JSON } else { Join-Path $HOME '.claude.json' })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$SettingsPath = Join-Path $ConfigDir 'settings.json'
$StatePath = Join-Path (Join-Path $ConfigDir 'keyproxy-claude') 'state.json'
$HelperPath = Join-Path $InstallBin 'keyproxy-claude.ps1'

function Show-Usage {
@'
KeyProxy Hub para Claude Code

Uso: .\keyproxy-claude.ps1 [comando]

Comandos:
  install  Instala ou atualiza a configuração KeyProxy
  open     Abre o seletor e inicia o Claude Code
  list     Lista os modelos anunciados/autorizados
  status   Mostra configuração e testa a descoberta
  revert   Restaura o estado anterior à primeira instalação ativa
  reset    Volta ao Claude oficial
  help     Exibe esta ajuda
'@ | Write-Output
}

function Assert-Configured {
    if (-not (Test-Path -LiteralPath $HelperPath)) { throw 'Seletor não instalado. Use a opção de instalação primeiro.' }
}

function Show-Status {
    Write-Host -NoNewline 'Claude Code: '
    try {
        $version = & claude --version 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'falha' }
        Write-Host ($version -join ' ')
    } catch { Write-Host 'não encontrado ou inválido' }

    if (-not (Test-Path -LiteralPath $SettingsPath)) { Write-Output 'Configuração: ausente'; return }
    try { $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json } catch { Write-Output 'Configuração: inválida'; return }
    $envSettings = if ($settings.PSObject.Properties['env'] -and $settings.env) { $settings.env } else { [pscustomobject]@{} }
    $endpoint = if ($envSettings.PSObject.Properties['ANTHROPIC_BASE_URL']) { [string]$envSettings.ANTHROPIC_BASE_URL } else { 'não configurado' }
    $hasToken = $envSettings.PSObject.Properties['ANTHROPIC_AUTH_TOKEN'] -and -not [string]::IsNullOrWhiteSpace([string]$envSettings.ANTHROPIC_AUTH_TOKEN)
    $active = $endpoint -eq 'https://api.keyproxyhub.store/v1' -and $hasToken
    Write-Output ('Configuração: ' + $(if ($active) { 'KeyProxy ativa' } else { 'KeyProxy inativa ou divergente' }))
    Write-Output ('Endpoint: ' + $endpoint)
    Write-Output ('Modelo principal: ' + $(if ($settings.PSObject.Properties['model']) { [string]$settings.model } else { 'não configurado' }))
    $alias = { param($name) if ($envSettings.PSObject.Properties[$name]) { [string]$envSettings.$name } else { '-' } }
    Write-Output ('Aliases: opus={0}; fable={1}; sonnet={2}; haiku={3}' -f (&$alias 'ANTHROPIC_DEFAULT_OPUS_MODEL'),(&$alias 'ANTHROPIC_DEFAULT_FABLE_MODEL'),(&$alias 'ANTHROPIC_DEFAULT_SONNET_MODEL'),(&$alias 'ANTHROPIC_DEFAULT_HAIKU_MODEL'))
    $count = if ($settings.PSObject.Properties['availableModels']) { @($settings.availableModels).Count } else { 0 }
    Write-Output ('Allowlist: {0} modelo(s)' -f $count)
    Write-Output ('Snapshot: ' + $(if (Test-Path -LiteralPath $StatePath) { 'presente' } else { 'ausente' }))
    $mcpStatus = 'ausente'
    if (Test-Path -LiteralPath $ClaudeJson) {
        try {
            $globalConfig = Get-Content -LiteralPath $ClaudeJson -Raw | ConvertFrom-Json
            if ($globalConfig.PSObject.Properties['mcpServers'] -and $globalConfig.mcpServers.PSObject.Properties['keyproxy']) {
                $server = $globalConfig.mcpServers.keyproxy
                $isManagedMcp = $server -is [pscustomobject] -and
                    @($server.PSObject.Properties).Count -eq 3 -and
                    $server.PSObject.Properties['type'] -and $server.type -eq 'http' -and
                    $server.PSObject.Properties['url'] -and $server.url -eq 'https://api.keyproxyhub.store/mcp' -and
                    $server.PSObject.Properties['headers'] -and $server.headers -is [pscustomobject] -and
                    @($server.headers.PSObject.Properties).Count -eq 1 -and
                    $server.headers.PSObject.Properties['Authorization'] -and
                    $server.headers.Authorization -eq 'Bearer ${KEYPROXY_API_KEY}'
                $mcpStatus = if ($isManagedMcp) { 'configurado' } else { 'divergente' }
            }
        } catch { $mcpStatus = 'divergente' }
    }
    Write-Output ('MCP KeyProxy: ' + $mcpStatus)
    Write-Output ('Seletor: ' + $(if (Test-Path -LiteralPath $HelperPath) { 'instalado' } else { 'ausente' }))
    if (Test-Path -LiteralPath $HelperPath) {
        try {
            $models = @(& $HelperPath -List -ConfigDir $ConfigDir -ErrorAction Stop 3>$null)
            Write-Output ('Descoberta executável: {0} modelo(s) concreto(s)' -f $models.Count)
        } catch { Write-Output 'Descoberta executável: falhou'; throw }
    }
    Write-Output 'Credencial: configurada e ocultada'
}

function Confirm-Action([string]$Prompt) {
    $answer = Read-Host ($Prompt + ' [s/N]')
    return $answer -eq 's' -or $answer -eq 'S'
}

function Invoke-CommandAction([string]$Action, [string[]]$Arguments) {
    switch ($Action) {
        'install' { & (Join-Path $Root 'install.ps1') -ConfigDir $ConfigDir -InstallBin $InstallBin -ClaudeJson $ClaudeJson }
        'open' {
            Assert-Configured
            if ($Arguments) { & $HelperPath -ConfigDir $ConfigDir @Arguments } else { & $HelperPath -ConfigDir $ConfigDir }
            if ($LASTEXITCODE) { exit $LASTEXITCODE }
        }
        'list' { Assert-Configured; & $HelperPath -List -ConfigDir $ConfigDir }
        'status' { Show-Status }
        'revert' {
            if ($Arguments) { & (Join-Path $Root 'revert.ps1') -ConfigDir $ConfigDir -ClaudeJson $ClaudeJson @Arguments }
            else { & (Join-Path $Root 'revert.ps1') -ConfigDir $ConfigDir -ClaudeJson $ClaudeJson }
        }
        'reset' {
            if ($Arguments) { & (Join-Path $Root 'reset-claude-default.ps1') -ConfigDir $ConfigDir -InstallBin $InstallBin -ClaudeJson $ClaudeJson @Arguments }
            else { & (Join-Path $Root 'reset-claude-default.ps1') -ConfigDir $ConfigDir -InstallBin $InstallBin -ClaudeJson $ClaudeJson }
        }
        'help' { Show-Usage }
    }
}

function Show-Menu {
    while ($true) {
@'

KeyProxy Hub para Claude Code

  1. Instalar ou atualizar KeyProxy
  2. Abrir Claude Code e escolher modelo
  3. Listar modelos disponíveis
  4. Verificar status e conexão
  5. Restaurar configuração anterior
  6. Voltar ao Claude oficial
  7. Sair
'@ | Write-Host
        $option = Read-Host 'Escolha uma opção'
        switch ($option) {
            '1' { Invoke-CommandAction 'install' @() }
            '2' { Invoke-CommandAction 'open' @() }
            '3' { Invoke-CommandAction 'list' @() }
            '4' { Invoke-CommandAction 'status' @() }
            '5' { if (Confirm-Action 'Restaurar a configuração anterior à instalação?') { Invoke-CommandAction 'revert' @() } else { Write-Output 'Operação cancelada.' } }
            '6' { if (Confirm-Action 'Remover o KeyProxy e voltar ao Claude oficial?') { Invoke-CommandAction 'reset' @() } else { Write-Output 'Operação cancelada.' } }
            '7' { return }
            default { Write-Warning 'Opção inválida.' }
        }
    }
}

if ($Command) { Invoke-CommandAction $Command $RemainingArgs } else { Show-Menu }
