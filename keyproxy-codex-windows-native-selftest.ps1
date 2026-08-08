#requires -Version 5.1
<#
Executa testes nativos e isolados do instalador KeyProxy para Windows.
Não usa Codex real, não acessa rede e restaura KEYPROXY_API_KEY em finally.
Execute uma vez com Windows PowerShell 5.1 e, se disponível, outra com PowerShell 7.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallerPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw ('{0} (esperado={1}, obtido={2})' -f $Message, $Expected, $Actual)
    }
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $encoding = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Content, $encoding)
}

function New-FakeCodex {
    param([string]$Path)
    $batch = @'
@echo off
setlocal
>>"%TEST_CODEX_LOG%" echo %*
if "%~1"=="--version" (
  echo codex-cli windows-native-selftest
  exit /b 0
)
if "%~1"=="--strict-config" (
  if /I "%TEST_STRICT_FAIL%"=="true" exit /b 41
  echo codex-cli windows-native-selftest
  exit /b 0
)
if "%~1"=="doctor" (
  if /I "%TEST_DOCTOR_FAIL%"=="true" exit /b 51
  echo {"checks":{"config.load":{"details":{"model":"gpt-5.6-sol","model provider":"keyproxy"}}}}
  exit /b 0
)
if "%~1"=="mcp" (
  if /I "%TEST_MCP_FAIL%"=="true" exit /b 52
  echo keyproxy
  exit /b 0
)
if "%~1"=="logout" (
  >>"%TEST_EVENT_LOG%" echo logout
  exit /b 0
)
if "%~1"=="exec" (
  >>"%TEST_EVENT_LOG%" echo exec
  if /I "%TEST_EXEC_MODE%"=="api-fail" (
    echo model: gpt-5.6-sol
    echo provider: keyproxy
    echo ERROR HTTP 403
    exit /b 53
  )
  if /I "%TEST_EXEC_MODE%"=="mcp-fail" (
    echo model: gpt-5.6-sol
    echo provider: keyproxy
    echo MCP server keyproxy failed: HTTP 401 Unauthorized
    echo KEYPROXY_OK
    exit /b 0
  )
  if /I "%TEST_EXEC_MODE%"=="timeout" (
    timeout /t 3 /nobreak >nul
  )
  echo model: gpt-5.6-sol
  echo provider: keyproxy
  echo KEYPROXY_OK
  exit /b 0
)
exit /b 90
'@
    [IO.File]::WriteAllText($Path, $batch, [Text.Encoding]::ASCII)
}

function New-TestCase {
    param([string]$Root, [string]$Name)
    $caseRoot = Join-Path $Root $Name
    $codexHome = Join-Path $caseRoot 'codex home á'
    $bin = Join-Path $caseRoot 'bin'
    [IO.Directory]::CreateDirectory($codexHome) | Out-Null
    [IO.Directory]::CreateDirectory($bin) | Out-Null
    $codex = Join-Path $bin 'codex.cmd'
    New-FakeCodex -Path $codex
    $codexLog = Join-Path $caseRoot 'codex.log'
    $eventLog = Join-Path $caseRoot 'events.log'
    [IO.File]::WriteAllText($codexLog, '')
    [IO.File]::WriteAllText($eventLog, '')
    return [PSCustomObject]@{
        Root = $caseRoot
        CodexHome = $codexHome
        Config = Join-Path $codexHome 'config.toml'
        Codex = $codex
        CodexLog = $codexLog
        EventLog = $eventLog
        Stdout = Join-Path $caseRoot 'stdout.log'
        Stderr = Join-Path $caseRoot 'stderr.log'
    }
}

function Invoke-InstallerTest {
    param(
        $Case,
        [string]$ApiKey,
        [switch]$SkipApi,
        [string]$DoctorFail = '',
        [string]$McpFail = '',
        [string]$ExecMode = '',
        [string]$ApiTimeoutSeconds = '',
        [string]$InstallerPayload = '',
        [switch]$TestNotification
    )

    $saved = @{}
    foreach ($name in @('CODEX_HOME', 'KEYPROXY_INSTALLER_TEST_MODE', 'KEYPROXY_TEST_DIRECT_CODEX', 'TEST_CODEX_LOG',
            'TEST_EVENT_LOG', 'TEST_DOCTOR_FAIL', 'TEST_MCP_FAIL', 'TEST_EXEC_MODE', 'KEYPROXY_CODEX_API_TIMEOUT_SECONDS')) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    try {
        $env:CODEX_HOME = $Case.CodexHome
        $env:KEYPROXY_INSTALLER_TEST_MODE = '1'
        $env:TEST_CODEX_LOG = $Case.CodexLog
        $env:TEST_EVENT_LOG = $Case.EventLog
        $env:TEST_DOCTOR_FAIL = $DoctorFail
        $env:TEST_MCP_FAIL = $McpFail
        $env:TEST_EXEC_MODE = $ExecMode
        $env:KEYPROXY_CODEX_API_TIMEOUT_SECONDS = $ApiTimeoutSeconds
        if ($ExecMode -eq 'timeout') {
            Remove-Item Env:KEYPROXY_TEST_DIRECT_CODEX -ErrorAction SilentlyContinue
        }
        else {
            $env:KEYPROXY_TEST_DIRECT_CODEX = '1'
        }

        $engine = (Get-Process -Id $PID).Path
        $arguments = @(
            '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-File', $InstallerPath,
            '-TestMode', '-TestCodexPath', $Case.Codex, '-TestApiKey', $ApiKey
        )
        if ($SkipApi) { $arguments += '-SkipApiTest' }
        if (-not [string]::IsNullOrWhiteSpace($InstallerPayload)) {
            $arguments += @('-TestInstallerPath', $InstallerPayload)
        }
        if ($TestNotification) { $arguments += '-TestEnvironmentNotification' }
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & $engine @arguments 1> $Case.Stdout 2> $Case.Stderr
            return $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousPreference
        }
    }
    finally {
        foreach ($name in $saved.Keys) {
            if ($null -eq $saved[$name]) {
                Remove-Item ("Env:{0}" -f $name) -ErrorAction SilentlyContinue
            }
            else {
                [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process')
            }
        }
    }
}

if ($env:OS -ne 'Windows_NT') {
    throw 'Este self-test deve ser executado no Windows nativo.'
}
if (-not [Environment]::Is64BitProcess) {
    throw 'Execute o self-test em PowerShell x64.'
}
$InstallerPath = (Resolve-Path -LiteralPath $InstallerPath).Path
$root = Join-Path ([IO.Path]::GetTempPath()) ('keyproxy-native-selftest-{0}' -f [Guid]::NewGuid().ToString('N'))
$previousUserKey = [Environment]::GetEnvironmentVariable('KEYPROXY_API_KEY', 'User')
$testSecret = "kp_selftest_' espaço_á"

try {
    [IO.Directory]::CreateDirectory($root) | Out-Null

    # Instalação existente, File.Replace, Registry, user32, preservação e idempotência.
    $case = New-TestCase -Root $root -Name 'existing'
    $existing = @'
# configuração nativa existente
model = "antigo"
model_provider = "openai"
model_reasoning_effort = "xhigh"
lista = ["a", "b"]

[features]
memories = true
apps = true

[windows]
sandbox = "elevated"

[[custom_agents]]
name = "preservado"

[model_providers.keyproxy]
name = "Antigo"
base_url = "https://antigo.invalid/v1"

[mcp_servers.keyproxy]
url = "https://antigo.invalid/mcp"
'@
    Write-Utf8NoBom -Path $case.Config -Content $existing
    $first = Invoke-InstallerTest -Case $case -ApiKey $testSecret -SkipApi -TestNotification
    Assert-Equal $first 0 'primeira instalação existente falhou'
    $firstErrors = [IO.File]::ReadAllText($case.Stderr)
    Assert-True (-not $firstErrors.Contains('notificação ao Windows falhou')) 'WM_SETTINGCHANGE/user32 falhou'
    $second = Invoke-InstallerTest -Case $case -ApiKey $testSecret -SkipApi
    Assert-Equal $second 0 'idempotência falhou'
    $config = [IO.File]::ReadAllText($case.Config)
    Assert-Equal ([regex]::Matches($config, '(?m)^model = "gpt-5\.6-sol"\r?$').Count) 1 'modelo duplicado'
    Assert-Equal ([regex]::Matches($config, '(?m)^\[model_providers\.keyproxy\]\r?$').Count) 1 'provider duplicado'
    Assert-Equal ([regex]::Matches($config, '(?m)^\[mcp_servers\.keyproxy\]\r?$').Count) 1 'MCP duplicado'
    Assert-True ($config.Contains('model_reasoning_effort = "xhigh"')) 'reasoning não preservado'
    Assert-True ($config.Contains('[windows]')) 'configuração Windows não preservada'
    Assert-True ($config.Contains('[[custom_agents]]')) 'array de tabelas não preservado'
    Assert-True (-not $config.Contains($testSecret)) 'segredo apareceu no TOML'
    Assert-Equal ([Environment]::GetEnvironmentVariable('KEYPROXY_API_KEY', 'User')) $testSecret 'Registry de ambiente não atualizado'
    Assert-Equal (@(Get-ChildItem -LiteralPath $case.CodexHome -Filter 'config.toml.*.bak').Count) 2 'backups esperados ausentes'
    $configBytes = [IO.File]::ReadAllBytes($case.Config)
    Assert-True ($configBytes.Length -lt 3 -or -not ($configBytes[0] -eq 0xEF -and $configBytes[1] -eq 0xBB -and $configBytes[2] -eq 0xBF)) 'config.toml contém BOM UTF-8'
    Assert-True (-not ($config -match "(?<!`r)`n")) 'config.toml contém LF sem CR no Windows'
    Assert-True ([string]::IsNullOrWhiteSpace([IO.File]::ReadAllText($case.EventLog))) 'logout ocorreu apesar de -SkipApiTest'
    $skipApiStderr = [IO.File]::ReadAllText($case.Stderr)
    Assert-True ($skipApiStderr.Contains('Login OAuth oficial preservado')) 'preservação do OAuth não foi informada com -SkipApiTest'
    [Console]::Out.WriteLine('native-skip-api-preserves-oauth=ok')
    [Console]::Out.WriteLine('native-existing-idempotent=ok')
    [Console]::Out.WriteLine('native-user32-notification=ok')

    # Instalação nova e chamada API simulada.
    $case = New-TestCase -Root $root -Name 'fresh-api'
    $rc = Invoke-InstallerTest -Case $case -ApiKey $testSecret
    Assert-Equal $rc 0 'instalação nova/API simulada falhou'
    Assert-True (Test-Path -LiteralPath $case.Config) 'config novo ausente'
    $statePath = Join-Path $case.CodexHome 'keyproxy-codex-state.json'
    Assert-True (Test-Path -LiteralPath $statePath -PathType Leaf) 'manifesto KeyProxy ausente'
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    Assert-True ($state.version -eq 1 -and $state.createdBy -eq 'keyproxy-codex-install' -and $state.configPath -eq $case.Config -and -not $state.configExisted) 'manifesto KeyProxy inválido'
    $successEvents = @([IO.File]::ReadAllText($case.EventLog) -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    Assert-Equal ([string]::Join(',', $successEvents)) 'exec,logout' 'logout não ocorreu após a chamada real'
    [Console]::Out.WriteLine('native-api-before-logout=ok')
    [Console]::Out.WriteLine('native-fresh-api=ok')

    # Falha de API não remove OAuth previamente ativo.
    $case = New-TestCase -Root $root -Name 'api-failure'
    $rc = Invoke-InstallerTest -Case $case -ApiKey $testSecret -ExecMode 'api-fail'
    Assert-Equal $rc 2 'falha API deveria retornar 2'
    $apiFailureEvents = @([IO.File]::ReadAllText($case.EventLog) -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    Assert-Equal ([string]::Join(',', $apiFailureEvents)) 'exec' 'logout ocorreu após falha da API'
    Assert-True (Test-Path -LiteralPath $case.Config) 'falha API removeu config local válida'
    [Console]::Out.WriteLine('native-api-failure-preserves-oauth=ok')

    # Timeout usa o subprocesso de produção mesmo no harness; OAuth permanece intacto.
    $case = New-TestCase -Root $root -Name 'api-timeout'
    $rc = Invoke-InstallerTest -Case $case -ApiKey $testSecret -ExecMode 'timeout' -ApiTimeoutSeconds '1'
    Assert-Equal $rc 2 'timeout da API deveria retornar 2'
    $timeoutEvents = @([IO.File]::ReadAllText($case.EventLog) -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    Assert-Equal ([string]::Join(',', $timeoutEvents)) 'exec' 'logout ocorreu após timeout da API'
    $timeoutStderr = [IO.File]::ReadAllText($case.Stderr)
    Assert-True ($timeoutStderr.Contains('excedeu o prazo')) 'timeout da API não foi diagnosticado'
    [Console]::Out.WriteLine('native-api-timeout-preserves-oauth=ok')

    # Codex ausente: bootstrap oficial simulado deve ocorrer antes do KeyProxy.
    $case = New-TestCase -Root $root -Name 'bootstrap-missing'
    Remove-Item -LiteralPath $case.Codex -Force
    $escapedCodexPath = $case.Codex.Replace("'", "''")
    $bootstrapPayload = Join-Path $case.Root 'official-installer.ps1'
    $bootstrapText = @"
`$batch = @'
@echo off
setlocal
>>"%TEST_CODEX_LOG%" echo %*
if "%~1"=="--version" (echo codex-cli bootstrap-native& exit /b 0)
if "%~1"=="--strict-config" (echo codex-cli bootstrap-native& exit /b 0)
if "%~1"=="doctor" (echo {"checks":{"config.load":{"details":{"model":"gpt-5.6-sol","model provider":"keyproxy"}}}}& exit /b 0)
if "%~1"=="mcp" (echo keyproxy& exit /b 0)
if "%~1"=="logout" (>>"%TEST_EVENT_LOG%" echo logout& exit /b 0)
if "%~1"=="exec" (>>"%TEST_EVENT_LOG%" echo exec& echo model: gpt-5.6-sol& echo provider: keyproxy& echo KEYPROXY_OK& exit /b 0)
exit /b 90
'@
[IO.File]::WriteAllText('$escapedCodexPath', `$batch, [Text.Encoding]::ASCII)
"@
    Write-Utf8NoBom -Path $bootstrapPayload -Content $bootstrapText
    $rc = Invoke-InstallerTest -Case $case -ApiKey $testSecret -SkipApi -InstallerPayload $bootstrapPayload
    if ($rc -ne 0) {
        $bootstrapStdout = [IO.File]::ReadAllText($case.Stdout)
        $bootstrapStderr = [IO.File]::ReadAllText($case.Stderr)
        throw ("bootstrap nativo com Codex ausente falhou (código={0})`nSTDOUT:`n{1}`nSTDERR:`n{2}" -f $rc, $bootstrapStdout, $bootstrapStderr)
    }
    Assert-True (Test-Path -LiteralPath $case.Codex -PathType Leaf) 'bootstrap não instalou Codex falso'
    Assert-True (Test-Path -LiteralPath $case.Config -PathType Leaf) 'KeyProxy não foi aplicado depois do bootstrap'
    $bootstrapLog = [IO.File]::ReadAllText($case.CodexLog)
    Assert-True ($bootstrapLog.Contains('--version')) 'Codex instalado não foi validado com --version'
    [Console]::Out.WriteLine('native-codex-bootstrap=ok')

    # Rollback de config e Registry antes da validação local.
    $case = New-TestCase -Root $root -Name 'rollback'
    Write-Utf8NoBom -Path $case.Config -Content "model_reasoning_effort = `"medium`"`r`n"
    [Environment]::SetEnvironmentVariable('KEYPROXY_API_KEY', 'valor-anterior-selftest', 'User')
    $before = [IO.File]::ReadAllText($case.Config)
    $rc = Invoke-InstallerTest -Case $case -ApiKey 'valor-novo-selftest' -DoctorFail 'true'
    Assert-Equal $rc 1 'falha doctor deveria retornar 1'
    Assert-Equal ([IO.File]::ReadAllText($case.Config)) $before 'rollback nativo do config falhou'
    Assert-Equal ([Environment]::GetEnvironmentVariable('KEYPROXY_API_KEY', 'User')) 'valor-anterior-selftest' 'rollback nativo do Registry falhou'
    Assert-True ([string]::IsNullOrWhiteSpace([IO.File]::ReadAllText($case.EventLog))) 'logout ocorreu antes da validação local'
    [Console]::Out.WriteLine('native-coordinated-rollback=ok')

    # Falha MCP paralela mantém configuração local e usa código 2.
    $case = New-TestCase -Root $root -Name 'mcp-failure'
    $rc = Invoke-InstallerTest -Case $case -ApiKey $testSecret -ExecMode 'mcp-fail'
    Assert-Equal $rc 2 'falha MCP deveria retornar 2'
    Assert-True (Test-Path -LiteralPath $case.Config) 'falha MCP removeu config local válida'
    [Console]::Out.WriteLine('native-mcp-failure=ok')

    # CODEX_HOME como junction/reparse point deve ser recusado antes da chave.
    $caseRoot = Join-Path $root 'junction-case'
    $target = Join-Path $caseRoot 'target'
    $junction = Join-Path $caseRoot 'codex-junction'
    $bin = Join-Path $caseRoot 'bin'
    [IO.Directory]::CreateDirectory($target) | Out-Null
    [IO.Directory]::CreateDirectory($bin) | Out-Null
    New-Item -ItemType Junction -Path $junction -Target $target | Out-Null
    $fake = Join-Path $bin 'codex.cmd'
    New-FakeCodex -Path $fake
    $junctionCase = [PSCustomObject]@{
        Root = $caseRoot
        CodexHome = $junction
        Config = Join-Path $junction 'config.toml'
        Codex = $fake
        CodexLog = Join-Path $caseRoot 'codex.log'
        EventLog = Join-Path $caseRoot 'events.log'
        Stdout = Join-Path $caseRoot 'stdout.log'
        Stderr = Join-Path $caseRoot 'stderr.log'
    }
    [IO.File]::WriteAllText($junctionCase.CodexLog, '')
    [IO.File]::WriteAllText($junctionCase.EventLog, '')
    [Environment]::SetEnvironmentVariable('KEYPROXY_API_KEY', 'antes-junction', 'User')
    $rc = Invoke-InstallerTest -Case $junctionCase -ApiKey 'não-deve-gravar' -SkipApi
    Assert-Equal $rc 1 'junction deveria ser recusada'
    Assert-Equal ([Environment]::GetEnvironmentVariable('KEYPROXY_API_KEY', 'User')) 'antes-junction' 'junction alterou Registry antes da recusa'
    Assert-True (-not (Test-Path -LiteralPath $junctionCase.Config)) 'junction recebeu config'
    [Console]::Out.WriteLine('native-reparse-refusal=ok')

    # Nenhum segredo fictício deve aparecer nos logs do instalador.
    $logFiles = @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Name -in @('stdout.log', 'stderr.log', 'codex.log', 'events.log', 'config.toml') })
    foreach ($file in $logFiles) {
        $text = [IO.File]::ReadAllText($file.FullName)
        Assert-True (-not $text.Contains($testSecret)) ("segredo apareceu em {0}" -f $file.FullName)
    }

    [Console]::Out.WriteLine('windows-native-selftest=ok')
    [Console]::Out.WriteLine(('engine={0} {1}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion))
    [Console]::Out.WriteLine(('windows={0}' -f [Environment]::OSVersion.VersionString))
}
finally {
    [Environment]::SetEnvironmentVariable('KEYPROXY_API_KEY', $previousUserKey, 'User')
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

exit 0
