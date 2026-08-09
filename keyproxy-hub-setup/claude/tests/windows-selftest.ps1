$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = Split-Path -Parent $PSScriptRoot
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('keyproxy-claude-' + [guid]::NewGuid())
$OriginalPath = $env:PATH
$OriginalConfig = $env:CLAUDE_CONFIG_DIR
$OriginalKey = $env:KEYPROXY_API_KEY
$ConfigWasDefined = Test-Path Env:CLAUDE_CONFIG_DIR
$KeyWasDefined = Test-Path Env:KEYPROXY_API_KEY
try {
    $HomeDir = Join-Path $Temp 'home'
    $Config = Join-Path $HomeDir '.claude'
    $ClaudeJson = Join-Path $HomeDir '.claude.json'
    $Bin = Join-Path $HomeDir 'bin'
    $Fake = Join-Path $Temp 'fake'
    New-Item -ItemType Directory -Force -Path $Config,$Bin,$Fake | Out-Null
    $original = '{"language":"Portugues, Brasil","env":{"KEEP_ME":"yes"}}' + [Environment]::NewLine
    [IO.File]::WriteAllText((Join-Path $Config 'settings.json'),$original,(New-Object Text.UTF8Encoding($false)))
    $originalClaude = '{"keep":"yes","mcpServers":{"other":{"type":"http","url":"https://example.invalid/mcp"}}}' + [Environment]::NewLine
    [IO.File]::WriteAllText($ClaudeJson,$originalClaude,(New-Object Text.UTF8Encoding($false)))
    $fakeClaude = "@echo off`r`nif `"%1`"==`"--version`" (echo 2.1.224& exit /b 0)`r`necho fake-claude:%*`r`n"
    [IO.File]::WriteAllText((Join-Path $Fake 'claude.cmd'),$fakeClaude,(New-Object Text.ASCIIEncoding))
    $env:PATH = $Fake + [IO.Path]::PathSeparator + $env:PATH
    $env:CLAUDE_CONFIG_DIR = $Config
    $env:KEYPROXY_API_KEY = 'kp_test_not_real'

    & (Join-Path $Root 'keyproxy-claude.ps1') install -ConfigDir $Config -InstallBin $Bin -ClaudeJson $ClaudeJson | Out-Null
    $settings = Get-Content (Join-Path $Config 'settings.json') -Raw | ConvertFrom-Json
    if ($settings.language -ne 'Portugues, Brasil' -or $settings.env.KEEP_ME -ne 'yes' -or $settings.availableModels.Count -ne 12) { throw 'Falha no merge' }
    if ($settings.env.KEYPROXY_API_KEY -ne 'kp_test_not_real' -or $settings.env.ANTHROPIC_AUTH_TOKEN -ne 'kp_test_not_real') { throw 'Credenciais gerenciadas divergentes' }
    if ($settings.env.KEYPROXY_MODELS_URL -ne 'https://painel.keyproxyhub.store/v1/models') { throw 'Endpoint de catálogo incorreto' }
    if ($settings.env.CLAUDE_CODE_SUBAGENT_MODEL -ne 'inherit') { throw 'Subagentes não herdam a sessão' }
    if ($settings.env.ANTHROPIC_DEFAULT_OPUS_MODEL -ne 'gpt-5.6-sol' -or $settings.env.ANTHROPIC_DEFAULT_FABLE_MODEL -ne 'gpt-5.6-sol') { throw 'Aliases Opus/Fable incorretos' }
    if ($settings.env.ANTHROPIC_DEFAULT_SONNET_MODEL -ne 'gpt-5.6-terra') { throw 'Alias Sonnet incorreto' }
    if ($settings.env.ANTHROPIC_DEFAULT_HAIKU_MODEL -ne 'gpt-5.6-luna') { throw 'Alias Haiku incorreto' }
    if ($settings.env.ANTHROPIC_CUSTOM_MODEL_OPTION -ne 'gpt-5.5') { throw 'Alias Custom incorreto' }
    $claudeConfig = Get-Content $ClaudeJson -Raw | ConvertFrom-Json
    if ($claudeConfig.keep -ne 'yes' -or -not $claudeConfig.mcpServers.PSObject.Properties['other']) { throw 'Merge do MCP removeu configuração alheia' }
    $mcp = $claudeConfig.mcpServers.keyproxy
    if ($mcp.type -ne 'http' -or $mcp.url -ne 'https://api.keyproxyhub.store/mcp' -or $mcp.headers.Authorization -ne 'Bearer ${KEYPROXY_API_KEY}') { throw 'Configuração MCP incorreta' }
    if ((Get-Content $ClaudeJson -Raw).Contains('kp_test_not_real')) { throw 'Segredo foi gravado no JSON do MCP' }
    $statePath = Join-Path (Join-Path $Config 'keyproxy-claude') 'state.json'
    $stateBefore = [Convert]::ToBase64String([IO.File]::ReadAllBytes($statePath))
    $savedState = [IO.File]::ReadAllBytes($statePath)
    Remove-Item -LiteralPath $statePath -Force
    try {
        & (Join-Path $Root 'keyproxy-claude.ps1') install -ConfigDir $Config -InstallBin $Bin -ClaudeJson $ClaudeJson | Out-Null
        throw 'A reinstalação aceitou configuração ativa sem snapshot'
    } catch {
        if ($_.Exception.Message -eq 'A reinstalação aceitou configuração ativa sem snapshot') { throw }
    } finally {
        [IO.File]::WriteAllBytes($statePath, $savedState)
    }
    $env:KEYPROXY_API_KEY = 'kp_test_not_real'
    & (Join-Path $Root 'keyproxy-claude.ps1') install -ConfigDir $Config -InstallBin $Bin -ClaudeJson $ClaudeJson | Out-Null
    $stateAfter = [Convert]::ToBase64String([IO.File]::ReadAllBytes($statePath))
    if ($stateBefore -ne $stateAfter) { throw 'A reinstalação sobrescreveu o snapshot original' }

    $status = @(& (Join-Path $Root 'keyproxy-claude.ps1') status -ConfigDir $Config -InstallBin $Bin -ClaudeJson $ClaudeJson 3>$null) -join "`n"
    if ($status -notmatch 'Configuração: KeyProxy ativa' -or $status -notmatch 'MCP KeyProxy: configurado' -or $status -match 'kp_test_not_real') { throw 'Status inválido ou expôs segredo' }
    $env:CLAUDE_CONFIG_DIR = Join-Path $Temp 'config-incorreta'
    $listed = @(& (Join-Path $Root 'keyproxy-claude.ps1') list -ConfigDir $Config -InstallBin $Bin 3>$null)
    if ($listed.Count -ne 11) { throw 'O launcher ignorou ConfigDir explícito' }
    $modelSources = @(
        (Join-Path $Config 'settings.json'),
        (Join-Path $Bin 'keyproxy-claude.ps1'),
        (Join-Path $Root 'lib\keyproxy_claude_config.py'),
        (Join-Path $Root 'bin\keyproxy-claude'),
        (Join-Path $Root 'bin\keyproxy-claude.ps1'),
        (Join-Path $Root 'install.ps1')
    )
    if (@($modelSources | Where-Object { (Get-Content -LiteralPath $_ -Raw) -match 'codex-spark' }).Count -ne 0) { throw 'Identificador de modelo proibido encontrado' }
    $env:CLAUDE_CONFIG_DIR = $Config
    & (Join-Path $Root 'revert.ps1') -DryRun -ConfigDir $Config -ClaudeJson $ClaudeJson | Out-Null
    & (Join-Path $Root 'keyproxy-claude.ps1') revert -ConfigDir $Config -InstallBin $Bin -ClaudeJson $ClaudeJson | Out-Null
    $restored = Get-Content (Join-Path $Config 'settings.json') -Raw | ConvertFrom-Json
    if ($restored.language -ne 'Portugues, Brasil' -or $restored.env.KEEP_ME -ne 'yes' -or $restored.PSObject.Properties['model']) { throw 'Falha no revert idempotente' }
    $restoredClaude = Get-Content $ClaudeJson -Raw | ConvertFrom-Json
    if ($restoredClaude.keep -ne 'yes' -or -not $restoredClaude.mcpServers.PSObject.Properties['other'] -or $restoredClaude.mcpServers.PSObject.Properties['keyproxy']) { throw 'Revert não restaurou o MCP original' }

    # Falha injetada restaura settings, state, helper e PATH.
    $env:KEYPROXY_API_KEY = 'kp_test_not_real'
    $beforeFailureSettings = [IO.File]::ReadAllBytes((Join-Path $Config 'settings.json'))
    $beforeFailureClaude = [IO.File]::ReadAllBytes($ClaudeJson)
    $beforeFailureState = [IO.File]::ReadAllBytes($statePath)
    $beforeFailureHelper = [IO.File]::ReadAllBytes((Join-Path $Bin 'keyproxy-claude.ps1'))
    $beforeFailureUserPath = [Environment]::GetEnvironmentVariable('Path','User')
    $beforeFailureProcessPath = $env:PATH
    $env:KEYPROXY_TEST_FAIL_AFTER_HELPER = '1'
    try {
        & (Join-Path $Root 'install.ps1') -ConfigDir $Config -InstallBin $Bin -ClaudeJson $ClaudeJson | Out-Null
        throw 'A falha injetada não ocorreu'
    } catch {
        if ($_.Exception.Message -eq 'A falha injetada não ocorreu') { throw }
    } finally {
        $env:KEYPROXY_TEST_FAIL_AFTER_HELPER = $null
    }
    if ([Convert]::ToBase64String($beforeFailureSettings) -ne [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $Config 'settings.json')))) { throw 'Rollback de settings falhou' }
    if ([Convert]::ToBase64String($beforeFailureClaude) -ne [Convert]::ToBase64String([IO.File]::ReadAllBytes($ClaudeJson))) { throw 'Rollback do MCP global falhou' }
    if ([Convert]::ToBase64String($beforeFailureState) -ne [Convert]::ToBase64String([IO.File]::ReadAllBytes($statePath))) { throw 'Rollback de state falhou' }
    if ([Convert]::ToBase64String($beforeFailureHelper) -ne [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $Bin 'keyproxy-claude.ps1')))) { throw 'Rollback de helper falhou' }
    if ([Environment]::GetEnvironmentVariable('Path','User') -ne $beforeFailureUserPath -or $env:PATH -ne $beforeFailureProcessPath) { throw 'Rollback de PATH falhou' }

    $env:KEYPROXY_API_KEY = 'kp_test_not_real'
    & (Join-Path $Root 'install.ps1') -ConfigDir $Config -InstallBin $Bin -ClaudeJson $ClaudeJson | Out-Null
    & (Join-Path $Root 'reset-claude-default.ps1') -DryRun -ConfigDir $Config -InstallBin $Bin -ClaudeJson $ClaudeJson | Out-Null

    # Falha injetada no reset restaura settings, state, helper e PATH.
    $beforeResetSettings = [IO.File]::ReadAllBytes((Join-Path $Config 'settings.json'))
    $beforeResetClaude = [IO.File]::ReadAllBytes($ClaudeJson)
    $beforeResetState = [IO.File]::ReadAllBytes($statePath)
    $helperPath = Join-Path $Bin 'keyproxy-claude.ps1'
    $beforeResetHelper = [IO.File]::ReadAllBytes($helperPath)
    $beforeResetUserPath = [Environment]::GetEnvironmentVariable('Path','User')
    $beforeResetProcessPath = $env:PATH
    $env:KEYPROXY_TEST_FAIL_AFTER_RESET_FILES = '1'
    try {
        & (Join-Path $Root 'reset-claude-default.ps1') -ConfigDir $Config -InstallBin $Bin -ClaudeJson $ClaudeJson | Out-Null
        throw 'A falha injetada no reset não ocorreu'
    } catch {
        if ($_.Exception.Message -eq 'A falha injetada no reset não ocorreu') { throw }
    } finally {
        $env:KEYPROXY_TEST_FAIL_AFTER_RESET_FILES = $null
    }
    if ([Convert]::ToBase64String($beforeResetSettings) -ne [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $Config 'settings.json')))) { throw 'Rollback de settings no reset falhou' }
    if ([Convert]::ToBase64String($beforeResetClaude) -ne [Convert]::ToBase64String([IO.File]::ReadAllBytes($ClaudeJson))) { throw 'Rollback do MCP no reset falhou' }
    if ([Convert]::ToBase64String($beforeResetState) -ne [Convert]::ToBase64String([IO.File]::ReadAllBytes($statePath))) { throw 'Rollback de state no reset falhou' }
    if ([Convert]::ToBase64String($beforeResetHelper) -ne [Convert]::ToBase64String([IO.File]::ReadAllBytes($helperPath))) { throw 'Rollback de helper no reset falhou' }
    if ([Environment]::GetEnvironmentVariable('Path','User') -ne $beforeResetUserPath -or $env:PATH -ne $beforeResetProcessPath) { throw 'Rollback de PATH no reset falhou' }

    & (Join-Path $Root 'keyproxy-claude.ps1') reset -ConfigDir $Config -InstallBin $Bin -ClaudeJson $ClaudeJson | Out-Null
    $settings = Get-Content (Join-Path $Config 'settings.json') -Raw | ConvertFrom-Json
    if ($settings.env.KEEP_ME -ne 'yes' -or $settings.PSObject.Properties['model']) { throw 'Falha no reset' }
    $resetClaude = Get-Content $ClaudeJson -Raw | ConvertFrom-Json
    if ($resetClaude.keep -ne 'yes' -or -not $resetClaude.mcpServers.PSObject.Properties['other'] -or $resetClaude.mcpServers.PSObject.Properties['keyproxy']) { throw 'Reset removeu MCP alheio ou manteve MCP KeyProxy' }
    if (Test-Path -LiteralPath $statePath) { throw 'Reset manteve snapshot com segredo' }
    if (Test-Path -LiteralPath $helperPath) { throw 'Reset manteve o helper instalado' }

    # Um servidor keyproxy divergente nunca deve ser sobrescrito ou exposto.
    $conflict = '{"mcpServers":{"keyproxy":{"type":"http","url":"https://different.invalid/mcp"}}}' + [Environment]::NewLine
    [IO.File]::WriteAllText($ClaudeJson,$conflict,(New-Object Text.UTF8Encoding($false)))
    $beforeConflictSettings = [IO.File]::ReadAllBytes((Join-Path $Config 'settings.json'))
    $conflictOutput = ''
    try {
        $conflictOutput = @(& (Join-Path $Root 'keyproxy-claude.ps1') install -ConfigDir $Config -InstallBin $Bin -ClaudeJson $ClaudeJson 2>&1) -join "`n"
        throw 'A instalação sobrescreveu um MCP divergente'
    } catch {
        $conflictOutput += "`n" + $_.Exception.Message
        if ($_.Exception.Message -eq 'A instalação sobrescreveu um MCP divergente') { throw }
    }
    if ([Convert]::ToBase64String($beforeConflictSettings) -ne [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $Config 'settings.json')))) { throw 'Conflito MCP alterou settings' }
    if ((Get-Content $ClaudeJson -Raw) -ne $conflict) { throw 'Conflito MCP alterou a configuração global' }
    if ($conflictOutput -match 'kp_test_not_real') { throw 'Conflito MCP expôs segredo' }
    $resetConflictOutput = ''
    try {
        $resetConflictOutput = @(& (Join-Path $Root 'keyproxy-claude.ps1') reset -ConfigDir $Config -InstallBin $Bin -ClaudeJson $ClaudeJson 2>&1) -join "`n"
        throw 'O reset aceitou um MCP divergente'
    } catch {
        $resetConflictOutput += "`n" + $_.Exception.Message
        if ($_.Exception.Message -eq 'O reset aceitou um MCP divergente') { throw }
    }
    if ((Get-Content $ClaudeJson -Raw) -ne $conflict) { throw 'Reset alterou MCP divergente' }
    if ($resetConflictOutput -match 'kp_test_not_real') { throw 'Reset com conflito expôs segredo' }
    Write-Output 'windows-selftest=ok'
} finally {
    $env:KEYPROXY_TEST_FAIL_AFTER_HELPER = $null
    $env:KEYPROXY_TEST_FAIL_AFTER_RESET_FILES = $null
    $env:PATH = $OriginalPath
    if ($ConfigWasDefined) { $env:CLAUDE_CONFIG_DIR = $OriginalConfig } else { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue }
    if ($KeyWasDefined) { $env:KEYPROXY_API_KEY = $OriginalKey } else { Remove-Item Env:KEYPROXY_API_KEY -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
}
