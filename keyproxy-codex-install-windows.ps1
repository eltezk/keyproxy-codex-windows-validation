#requires -Version 5.1
<#
.SYNOPSIS
Configura o KeyProxy Hub no Codex CLI nativo para Windows.

.DESCRIPTION
Instala ou detecta o Codex CLI, solicita a API key sem eco, configura o
provider KeyProxy, o modelo gpt-5.6-sol e o MCP HTTP. Preserva as demais
preferências do config.toml e cria backup antes da substituição.

Este instalador é para PowerShell nativo no Windows. Em WSL, use o instalador
Bash para macOS/Linux dentro da distribuição Linux.

.PARAMETER SkipApiTest
Não executa a chamada real KEYPROXY_OK ao final.

.PARAMETER SkipCodexInstall
Falha se o Codex CLI não estiver instalado.

.PARAMETER Help
Mostra ajuda resumida.

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\keyproxy-codex-install-windows.ps1

.EXAMPLE
pwsh.exe -NoProfile -File .\keyproxy-codex-install-windows.ps1 -SkipApiTest

.NOTES
Rotação: execute novamente e informe a nova API key.
Rollback: restaure o backup config.toml.DATA.PID.bak informado no resumo.
Desinstalação manual: restaure o config.toml, remova as seções KeyProxy e
execute [Environment]::SetEnvironmentVariable('KEYPROXY_API_KEY', $null, 'User').
Abra um novo terminal para outros processos herdarem a variável atualizada.
#>
[CmdletBinding()]
param(
    [switch]$SkipApiTest,
    [switch]$SkipCodexInstall,
    [switch]$Help,

    [Parameter(DontShow = $true)]
    [switch]$TestMode,

    [Parameter(DontShow = $true)]
    [string]$TestCodexPath,

    [Parameter(DontShow = $true)]
    [string]$TestApiKey,

    [Parameter(DontShow = $true)]
    [string]$TestUserEnvironmentFile,

    [Parameter(DontShow = $true)]
    [string]$TestInstallerPath,

    [Parameter(DontShow = $true)]
    [switch]$TestEnvironmentNotification
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:InvocationParameters = @{}
foreach ($parameterName in $PSBoundParameters.Keys) {
    $script:InvocationParameters[$parameterName] = $PSBoundParameters[$parameterName]
}

$script:KeyProxyBaseUrl = 'https://api.keyproxyhub.store/v1'
$script:KeyProxyMcpUrl = 'https://api.keyproxyhub.store/mcp'
$script:KeyProxyModel = 'gpt-5.6-sol'
$script:CodexInstallerUrl = 'https://chatgpt.com/codex/install.ps1'
$script:CodexExecutable = $null
$script:ConfigHome = $null
$script:ConfigFile = $null
$script:TemporaryRoot = $null
$script:BackupFile = $null
$script:StateFile = $null
$script:StateCreated = $false
$script:ConfigExisted = $false
$script:ConfigInstalled = $false
$script:PreviousUserApiKey = $null
$script:UserEnvironmentChanged = $false
$script:RollbackArmed = $false
$script:ExitCode = 0
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-KeyProxyInfo {
    param([Parameter(Mandatory = $true)][string]$Message)
    [Console]::Out.WriteLine('[KeyProxy] {0}', $Message)
}

function Write-KeyProxyWarning {
    param([Parameter(Mandatory = $true)][string]$Message)
    [Console]::Error.WriteLine('[KeyProxy] AVISO: {0}', $Message)
}

function Write-KeyProxyStep {
    param(
        [Parameter(Mandatory = $true)][int]$Number,
        [Parameter(Mandatory = $true)][string]$Message
    )
    [Console]::Out.WriteLine()
    [Console]::Out.WriteLine('[KeyProxy] Etapa {0}/5 — {1}', $Number, $Message)
}

function Show-KeyProxyBanner {
    [Console]::Out.WriteLine()
    [Console]::Out.WriteLine('===============================================')
    [Console]::Out.WriteLine(' KeyProxy Hub + Codex CLI — Windows')
    [Console]::Out.WriteLine('===============================================')
    [Console]::Out.WriteLine('O instalador verificará o Codex, pedirá sua API key')
    [Console]::Out.WriteLine('e configurará modelo, API e MCP automaticamente.')
}

function Stop-KeyProxyInstall {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [int]$Code = 1
    )
    $script:ExitCode = $Code
    throw $Message
}

function Show-KeyProxyHelp {
    @'
Instala o KeyProxy Hub no Codex CLI nativo para Windows.

Uso:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\keyproxy-codex-install-windows.ps1
  pwsh.exe -NoProfile -File .\keyproxy-codex-install-windows.ps1

Opções:
  -SkipApiTest       Não executa a chamada real KEYPROXY_OK ao final.
  -SkipCodexInstall  Falha se o Codex CLI não estiver instalado.
  -Help              Mostra esta ajuda.

O instalador:
  1. verifica ou instala o Codex CLI pelo instalador oficial;
  2. solicita a API key sem exibi-la;
  3. persiste KEYPROXY_API_KEY no ambiente do usuário Windows;
  4. mescla provider, modelo e MCP no config.toml ativo;
  5. cria backup e manifesto local de recuperação do KeyProxy;
  6. testa modelo, provider, MCP e uma resposta real com prazo limitado;
  7. executa codex logout somente após a validação de conexão.

Com -SkipApiTest, o login OAuth oficial é preservado. Falhas de API, MCP ou
prazo também preservam o login OAuth oficial.

Configuração ativa:
  %CODEX_HOME%\config.toml, quando CODEX_HOME estiver definido;
  %USERPROFILE%\.codex\config.toml, caso contrário.

Rotação:
  Execute este instalador novamente e informe a nova API key.

Rollback:
  Confira o manifesto restrito %CODEX_HOME%\keyproxy-codex-state.json e
  restaure manualmente apenas o backup indicado no campo configBackup.

Desinstalação manual:
  1. restaure o backup indicado pelo manifesto KeyProxy ou remova as seções;
  2. remova a variável do usuário:
     [Environment]::SetEnvironmentVariable('KEYPROXY_API_KEY', $null, 'User')

Este arquivo é para PowerShell nativo. Dentro do WSL, use o instalador Bash.
Abra um novo terminal para outros processos herdarem a variável atualizada.
'@ | ForEach-Object { [Console]::Out.WriteLine($_) }
}

function Test-IsWindows {
    if (Get-Variable -Name IsWindows -Scope Global -ErrorAction SilentlyContinue) {
        return [bool]$global:IsWindows
    }
    return $env:OS -eq 'Windows_NT'
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Preflight {
    if ($PSVersionTable.PSVersion -lt [Version]'5.1') {
        Stop-KeyProxyInstall 'PowerShell 5.1 ou superior é obrigatório.'
    }

    $hiddenParameters = @(
        'TestCodexPath', 'TestApiKey', 'TestUserEnvironmentFile',
        'TestInstallerPath', 'TestEnvironmentNotification'
    )
    $hiddenParameterWasUsed = $false
    foreach ($parameterName in $hiddenParameters) {
        if ($script:InvocationParameters.ContainsKey($parameterName)) {
            $hiddenParameterWasUsed = $true
            break
        }
    }
    if (-not $TestMode -and $hiddenParameterWasUsed) {
        Stop-KeyProxyInstall 'Parâmetros internos de teste exigem -TestMode.'
    }
    if ($TestMode -and $env:KEYPROXY_INSTALLER_TEST_MODE -ne '1') {
        Stop-KeyProxyInstall 'TestMode é restrito ao harness automatizado do instalador.'
    }

    if (-not $TestMode) {
        if (-not (Test-IsWindows)) {
            Stop-KeyProxyInstall 'Este instalador é exclusivo para Windows nativo. Em macOS, Linux ou WSL, use o instalador Bash.'
        }
        if (-not [Environment]::Is64BitOperatingSystem) {
            Stop-KeyProxyInstall 'Windows 64 bits é obrigatório para o Codex CLI nativo.'
        }
        if (-not [Environment]::Is64BitProcess) {
            Stop-KeyProxyInstall 'Abra o PowerShell x64; processos PowerShell de 32 bits não são suportados.'
        }
        if (Test-IsAdministrator) {
            Stop-KeyProxyInstall 'Não execute como Administrador; o instalador configura somente o usuário atual.'
        }

        $build = [Environment]::OSVersion.Version.Build
        if ($build -lt 17763) {
            Stop-KeyProxyInstall 'Use Windows 10 build 17763 ou superior. Windows 11 é recomendado.'
        }
        if ($build -lt 22000) {
            Write-KeyProxyWarning 'Windows 10 possui suporte best effort. Windows 11 é recomendado.'
        }
    }
}

function Get-CodexExecutable {
    if (-not [string]::IsNullOrWhiteSpace($TestCodexPath)) {
        if (-not (Test-Path -LiteralPath $TestCodexPath -PathType Leaf)) {
            return $null
        }
        return (Get-Item -LiteralPath $TestCodexPath).FullName
    }

    $command = Get-Command codex.exe, codex -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) {
        return $null
    }
    if (-not [string]::IsNullOrWhiteSpace($command.Path)) {
        return $command.Path
    }
    return $command.Source
}

function Invoke-Codex {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [int]$TimeoutSeconds = 0
    )

    if ([string]::IsNullOrWhiteSpace($script:CodexExecutable)) {
        Stop-KeyProxyInstall 'Executável Codex não foi inicializado.'
    }

    if ($TimeoutSeconds -eq 0 -or ($TestMode -and $env:KEYPROXY_TEST_DIRECT_CODEX -eq '1')) {
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $output = @(& $script:CodexExecutable @Arguments 2>&1 | ForEach-Object { $_.ToString() })
            $exitCode = $LASTEXITCODE
            if ($null -eq $exitCode) { $exitCode = 0 }
            return [PSCustomObject]@{
                ExitCode = [int]$exitCode
                TimedOut = $false
                Output = [string[]]$output
                Text = [string]::Join([Environment]::NewLine, [string[]]$output)
            }
        }
        finally {
            $ErrorActionPreference = $previousPreference
        }
    }

    $outputFile = Join-Path $script:TemporaryRoot ('codex-output.{0}.log' -f [Guid]::NewGuid().ToString('N'))
    $encodedArguments = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($Arguments | ConvertTo-Json -Compress)))
    $runner = @'
$ErrorActionPreference = 'Continue'
$arguments = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($env:KEYPROXY_CODEX_ARGUMENTS)) | ConvertFrom-Json
& $env:KEYPROXY_CODEX_EXECUTABLE @([string[]]$arguments) 2>&1 | ForEach-Object { $_.ToString() }
exit $LASTEXITCODE
'@
    $runnerFile = Join-Path $script:TemporaryRoot ('codex-runner.{0}.ps1' -f [Guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($runnerFile, $runner, $script:Utf8NoBom)
    $previousExecutable = $env:KEYPROXY_CODEX_EXECUTABLE
    $previousArguments = $env:KEYPROXY_CODEX_ARGUMENTS
    try {
        $env:KEYPROXY_CODEX_EXECUTABLE = $script:CodexExecutable
        $env:KEYPROXY_CODEX_ARGUMENTS = $encodedArguments
        $engine = (Get-Process -Id $PID).Path
        $quotedRunnerFile = '"{0}"' -f $runnerFile
        $process = Start-Process -FilePath $engine -ArgumentList @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $quotedRunnerFile) -RedirectStandardOutput $outputFile -Wait:$false -PassThru
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            # O runner e o Codex abaixo dele foram iniciados por esta chamada; encerre só essa árvore.
            $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
            if (Test-Path -LiteralPath $taskkill -PathType Leaf) {
                & $taskkill /PID $process.Id /T /F 2>$null | Out-Null
            }
            if (-not $process.HasExited) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                [void]$process.WaitForExit(5000)
            }
            return [PSCustomObject]@{ ExitCode = 124; TimedOut = $true; Output = @(); Text = '' }
        }
        $text = if (Test-Path -LiteralPath $outputFile) { [IO.File]::ReadAllText($outputFile) } else { '' }
        $lines = @($text -split "`r?`n" | Where-Object { $_ -ne '' })
        return [PSCustomObject]@{
            ExitCode = [int]$process.ExitCode
            TimedOut = $false
            Output = [string[]]$lines
            Text = $text
        }
    }
    finally {
        if ($null -eq $previousExecutable) { Remove-Item Env:KEYPROXY_CODEX_EXECUTABLE -ErrorAction SilentlyContinue } else { $env:KEYPROXY_CODEX_EXECUTABLE = $previousExecutable }
        if ($null -eq $previousArguments) { Remove-Item Env:KEYPROXY_CODEX_ARGUMENTS -ErrorAction SilentlyContinue } else { $env:KEYPROXY_CODEX_ARGUMENTS = $previousArguments }
        Remove-Item -LiteralPath $runnerFile,$outputFile -Force -ErrorAction SilentlyContinue
    }
}

function Assert-CodexAvailable {
    $result = Invoke-Codex -Arguments @('--version')
    if ($result.ExitCode -ne 0) {
        Stop-KeyProxyInstall 'codex --version falhou.'
    }
    Write-KeyProxyInfo ('Codex detectado: {0}' -f (($result.Output | Select-Object -First 1) -as [string]))
}

function Refresh-ProcessPath {
    if ($TestMode) {
        return
    }
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $allEntries = New-Object 'Collections.Generic.List[string]'
    foreach ($pathValue in @($env:Path, $machinePath, $userPath)) {
        if ([string]::IsNullOrWhiteSpace($pathValue)) { continue }
        foreach ($entry in $pathValue.Split(';')) {
            if ([string]::IsNullOrWhiteSpace($entry)) { continue }
            if (-not $allEntries.Contains($entry)) { $allEntries.Add($entry) }
        }
    }
    $env:Path = [string]::Join(';', $allEntries)
}

function Install-CodexIfNeeded {
    $script:CodexExecutable = Get-CodexExecutable
    if (-not [string]::IsNullOrWhiteSpace($script:CodexExecutable)) {
        $versionResult = Invoke-Codex -Arguments @('--version')
        if ($versionResult.ExitCode -eq 0 -and $versionResult.Output.Count -gt 0) {
            Write-KeyProxyInfo ('Codex CLI já está instalado e funcional: {0}' -f $versionResult.Output[0])
            return
        }
        Write-KeyProxyWarning 'O comando codex existe, mas codex --version falhou; o instalador oficial será executado para reparar a instalação.'
    }

    if ($SkipCodexInstall) {
        Stop-KeyProxyInstall 'Codex CLI ausente ou inválido e -SkipCodexInstall foi informado.'
    }

    Write-KeyProxyInfo 'Codex CLI não encontrado ou inválido; baixando o instalador oficial.'
    $installer = Join-Path $script:TemporaryRoot 'codex-install.ps1'

    if ($TestMode -and -not [string]::IsNullOrWhiteSpace($TestInstallerPath)) {
        Copy-Item -LiteralPath $TestInstallerPath -Destination $installer
    }
    else {
        $sourceUri = [Uri]$script:CodexInstallerUrl
        if ($sourceUri.Scheme -ne 'https') {
            Stop-KeyProxyInstall 'O instalador oficial deve usar HTTPS.'
        }

        $previousSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
        try {
            [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            $response = Invoke-WebRequest -Uri $sourceUri -OutFile $installer -PassThru -UseBasicParsing
        }
        finally {
            [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol
        }
        $finalUri = $null
        if ($null -ne $response.BaseResponse) {
            if ($response.BaseResponse.PSObject.Properties.Name -contains 'ResponseUri') {
                $finalUri = $response.BaseResponse.ResponseUri
            }
            elseif ($null -ne $response.BaseResponse.RequestMessage) {
                $finalUri = $response.BaseResponse.RequestMessage.RequestUri
            }
        }
        if ($null -eq $finalUri) {
            Stop-KeyProxyInstall 'Não foi possível confirmar o destino final do instalador oficial.'
        }
        $allowedHosts = @('chatgpt.com', 'releases.openai.com')
        if ($finalUri.Scheme -ne 'https' -or $allowedHosts -notcontains $finalUri.Host.ToLowerInvariant()) {
            Stop-KeyProxyInstall ("Redirecionamento não autorizado do instalador oficial: {0}" -f $finalUri.AbsoluteUri)
        }
    }

    if (-not (Test-Path -LiteralPath $installer -PathType Leaf) -or (Get-Item -LiteralPath $installer).Length -eq 0) {
        Stop-KeyProxyInstall 'O instalador oficial foi baixado vazio.'
    }

    $installerText = [IO.File]::ReadAllText($installer)
    try {
        [void][ScriptBlock]::Create($installerText)
    }
    catch {
        Stop-KeyProxyInstall 'O instalador oficial baixado não contém PowerShell válido.'
    }

    if ($TestMode) {
        $LASTEXITCODE = 0
        & $installer
        if ($LASTEXITCODE -ne 0) {
            Stop-KeyProxyInstall 'O instalador Codex de teste falhou.'
        }
    }
    else {
        $powerShellExecutable = (Get-Process -Id $PID).Path
        $previousNonInteractive = $env:CODEX_NON_INTERACTIVE
        try {
            $env:CODEX_NON_INTERACTIVE = '1'
            & $powerShellExecutable -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installer
            if ($LASTEXITCODE -ne 0) {
                Stop-KeyProxyInstall ("O instalador oficial do Codex falhou com código {0}." -f $LASTEXITCODE)
            }
        }
        finally {
            if ($null -eq $previousNonInteractive) {
                Remove-Item Env:CODEX_NON_INTERACTIVE -ErrorAction SilentlyContinue
            }
            else {
                $env:CODEX_NON_INTERACTIVE = $previousNonInteractive
            }
        }
    }

    Refresh-ProcessPath
    $script:CodexExecutable = Get-CodexExecutable
    if ([string]::IsNullOrWhiteSpace($script:CodexExecutable)) {
        Stop-KeyProxyInstall 'Codex foi instalado, mas não foi encontrado no PATH. Abra um novo terminal e execute novamente.'
    }
    Assert-CodexAvailable
}

function Test-ReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    $item = Get-Item -LiteralPath $Path -Force
    return ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
}

function Assert-NoReparsePointInPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $current = [IO.Path]::GetFullPath($Path)
    while ($true) {
        if (Test-ReparsePoint -Path $current) {
            Stop-KeyProxyInstall ("{0} contém link ou reparse point: {1}. Use configuração manual para não alterar outro destino." -f $Label, $current)
        }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
            return
        }
        $current = $parent
    }
}

function Test-KeyProxyConfig {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $content = [IO.File]::ReadAllText($Path)
    return $content -match '(?m)^model = "gpt-5\.6-sol"\r?$' -and
        $content -match '(?m)^model_provider = "keyproxy"\r?$' -and
        $content -match '(?m)^\[model_providers\.keyproxy\]\r?$' -and
        $content -match '(?m)^\[mcp_servers\.keyproxy\]\r?$'
}

function Assert-ValidRecoveryState {
    if (-not (Test-Path -LiteralPath $script:StateFile)) {
        if (Test-KeyProxyConfig -Path $script:ConfigFile) {
            Stop-KeyProxyInstall 'A configuração KeyProxy ativa não tem manifesto de recuperação confiável; nenhum arquivo será sobrescrito.'
        }
        return
    }
    Assert-NoReparsePointInPath -Path $script:StateFile -Label 'manifesto de recuperação KeyProxy'
    if (-not (Test-Path -LiteralPath $script:StateFile -PathType Leaf)) {
        Stop-KeyProxyInstall 'O manifesto de recuperação não é um arquivo regular.'
    }
    try {
        $state = Get-Content -LiteralPath $script:StateFile -Raw | ConvertFrom-Json
    }
    catch {
        Stop-KeyProxyInstall 'O manifesto de recuperação não contém JSON válido.'
    }
    if ($state.version -ne 1 -or $state.createdBy -ne 'keyproxy-codex-install' -or
        $state.configPath -ne $script:ConfigFile -or $state.configExisted -isnot [bool]) {
        Stop-KeyProxyInstall 'O manifesto de recuperação é inválido para este CODEX_HOME; nenhum arquivo será sobrescrito.'
    }
    if ($state.configExisted) {
        $backupPath = if ([string]::IsNullOrWhiteSpace([string]$state.configBackup)) { '' } else { [IO.Path]::GetFullPath([string]$state.configBackup) }
        $configPath = [IO.Path]::GetFullPath($script:ConfigFile)
        if ([string]::IsNullOrWhiteSpace($backupPath) -or
            -not $backupPath.StartsWith($configPath + '.', [StringComparison]::Ordinal) -or
            -not $backupPath.EndsWith('.bak', [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $backupPath -PathType Leaf) -or
            (Test-ReparsePoint -Path $backupPath)) {
            Stop-KeyProxyInstall 'O backup registrado pelo KeyProxy não está disponível ou não é seguro; nenhum arquivo será sobrescrito.'
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($state.configBackup)) {
        Stop-KeyProxyInstall 'O manifesto de recuperação contém backup inesperado; nenhum arquivo será sobrescrito.'
    }
}

function Write-RecoveryState {
    if (Test-Path -LiteralPath $script:StateFile) { return }
    $state = [ordered]@{
        version = 1
        configPath = $script:ConfigFile
        configExisted = [bool]$script:ConfigExisted
        configBackup = [string]$script:BackupFile
        createdBy = 'keyproxy-codex-install'
    }
    $staging = Join-Path $script:ConfigHome ('.keyproxy-codex-state.{0}' -f $PID)
    [IO.File]::WriteAllText($staging, ($state | ConvertTo-Json -Compress), $script:Utf8NoBom)
    Move-Item -LiteralPath $staging -Destination $script:StateFile
    $script:StateCreated = $true
}

function Get-UserApiKey {
    if ($TestMode -and -not [string]::IsNullOrWhiteSpace($TestUserEnvironmentFile)) {
        if (Test-Path -LiteralPath $TestUserEnvironmentFile -PathType Leaf) {
            return [IO.File]::ReadAllText($TestUserEnvironmentFile)
        }
        return $null
    }
    return [Environment]::GetEnvironmentVariable('KEYPROXY_API_KEY', 'User')
}

function Send-EnvironmentChangedNotification {
    if ($TestMode -and -not $TestEnvironmentNotification) {
        return
    }
    try {
        if (-not ('KeyProxy.NativeMethods' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace KeyProxy {
    public static class NativeMethods {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
            uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
    }
}
'@
        }
        $result = [UIntPtr]::Zero
        [void][KeyProxy.NativeMethods]::SendMessageTimeout(
            [IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, 'Environment',
            0x0002, 5000, [ref]$result)
    }
    catch {
        Write-KeyProxyWarning 'A variável foi gravada, mas a notificação ao Windows falhou. Abra um novo terminal.'
    }
}

function Set-UserApiKey {
    param([AllowNull()]$Value)

    if ($TestMode -and -not [string]::IsNullOrWhiteSpace($TestUserEnvironmentFile)) {
        $directory = Split-Path -Parent $TestUserEnvironmentFile
        if (-not [string]::IsNullOrWhiteSpace($directory)) {
            [IO.Directory]::CreateDirectory($directory) | Out-Null
        }
        if ($null -eq $Value) {
            Remove-Item -LiteralPath $TestUserEnvironmentFile -Force -ErrorAction SilentlyContinue
        }
        else {
            [IO.File]::WriteAllText($TestUserEnvironmentFile, $Value, $script:Utf8NoBom)
        }
    }
    else {
        [Environment]::SetEnvironmentVariable('KEYPROXY_API_KEY', $Value, 'User')
    }

    if ($null -eq $Value) {
        Remove-Item Env:KEYPROXY_API_KEY -ErrorAction SilentlyContinue
    }
    else {
        $env:KEYPROXY_API_KEY = $Value
    }
    Send-EnvironmentChangedNotification
}

function Read-AndStoreApiKey {
    $script:PreviousUserApiKey = Get-UserApiKey
    $plainText = $null
    $bstr = [IntPtr]::Zero
    try {
        if ($TestMode) {
            $plainText = $TestApiKey
        }
        else {
            [Console]::Out.WriteLine('Cole sua API key do KeyProxy Hub e pressione Enter.')
            [Console]::Out.WriteLine('A chave não aparecerá na tela. Pressione Ctrl+C para cancelar.')
            $secureValue = Read-Host 'API key' -AsSecureString
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
            $plainText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }

        if ([string]::IsNullOrWhiteSpace($plainText)) {
            Stop-KeyProxyInstall 'Nenhuma API key foi informada. Obtenha uma chave no portal KeyProxy e execute novamente.'
        }

        Set-UserApiKey -Value $plainText
        $script:UserEnvironmentChanged = $true
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
        $plainText = $null
    }
}

function Invoke-WithCodexHome {
    param(
        [AllowNull()][string]$CodexHome,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )
    $previous = $env:CODEX_HOME
    try {
        if ($null -eq $CodexHome) {
            Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
        }
        else {
            $env:CODEX_HOME = $CodexHome
        }
        & $Action
    }
    finally {
        if ($null -eq $previous) {
            Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
        }
        else {
            $env:CODEX_HOME = $previous
        }
    }
}

function Test-UnclosedTomlCollection {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Line)

    $quote = [char]0
    $escaped = $false
    $equalAt = -1
    for ($index = 0; $index -lt $Line.Length; $index++) {
        $character = $Line[$index]
        if ($quote -eq '"') {
            if ($escaped) { $escaped = $false }
            elseif ($character -eq '\') { $escaped = $true }
            elseif ($character -eq '"') { $quote = [char]0 }
            continue
        }
        if ($quote -eq "'") {
            if ($character -eq "'") { $quote = [char]0 }
            continue
        }
        if ($character -eq '#') { break }
        if ($character -eq '"' -or $character -eq "'") {
            $quote = $character
            continue
        }
        if ($character -eq '=') {
            $equalAt = $index
            break
        }
    }
    if ($equalAt -lt 0) { return $false }

    $value = $Line.Substring($equalAt + 1).TrimStart()
    if ($value.Length -eq 0 -or ($value[0] -ne '[' -and $value[0] -ne '{')) {
        return $false
    }

    $quote = [char]0
    $escaped = $false
    $balance = 0
    for ($index = 0; $index -lt $value.Length; $index++) {
        $character = $value[$index]
        if ($quote -eq '"') {
            if ($escaped) { $escaped = $false }
            elseif ($character -eq '\') { $escaped = $true }
            elseif ($character -eq '"') { $quote = [char]0 }
            continue
        }
        if ($quote -eq "'") {
            if ($character -eq "'") { $quote = [char]0 }
            continue
        }
        if ($character -eq '#') { break }
        if ($character -eq '"' -or $character -eq "'") {
            $quote = $character
            continue
        }
        if ($character -eq '[' -or $character -eq '{') { $balance++ }
        elseif ($character -eq ']' -or $character -eq '}') { $balance-- }
    }
    return $balance -ne 0
}

function Assert-SupportedExistingConfig {
    Assert-NoReparsePointInPath -Path $script:ConfigHome -Label 'CODEX_HOME'
    Assert-NoReparsePointInPath -Path $script:ConfigFile -Label 'config.toml'
    if (-not (Test-Path -LiteralPath $script:ConfigFile -PathType Leaf)) {
        return
    }
    if (Test-ReparsePoint -Path $script:ConfigFile) {
        Stop-KeyProxyInstall 'O config.toml é um link ou reparse point; use configuração manual para não substituir o link.'
    }

    Write-KeyProxyInfo 'Validando a configuração existente antes da mesclagem.'
    $strictResult = Invoke-Codex -Arguments @('--strict-config', '--version')
    if ($strictResult.ExitCode -ne 0) {
        Stop-KeyProxyInstall 'O config.toml existente já é inválido; nenhum arquivo foi alterado.'
    }

    $content = [IO.File]::ReadAllText($script:ConfigFile)
    if ($content -match '(?m)^[^#\r\n]*=\s*(?:''' + "'" + '|""")') {
        Stop-KeyProxyInstall 'O config.toml usa strings TOML multilinha; use a configuração manual para preservar esse formato.'
    }

    $normalized = $content.Replace("`r`n", "`n").Replace("`r", "`n")
    foreach ($line in $normalized.Split("`n")) {
        if (Test-UnclosedTomlCollection -Line $line) {
            Stop-KeyProxyInstall 'O config.toml usa array/tabela multilinha; use a configuração manual para preservar esse formato.'
        }
    }
}

function Add-CanonicalProvider {
    param([AllowEmptyCollection()][Collections.Generic.List[string]]$Lines)
    $Lines.Add('[model_providers.keyproxy]')
    $Lines.Add('name = "KeyProxy Hub"')
    $Lines.Add('base_url = "https://api.keyproxyhub.store/v1"')
    $Lines.Add('env_key = "KEYPROXY_API_KEY"')
    $Lines.Add('wire_api = "responses"')
    $Lines.Add('requires_openai_auth = false')
}

function Add-CanonicalMcp {
    param([AllowEmptyCollection()][Collections.Generic.List[string]]$Lines)
    $Lines.Add('[mcp_servers.keyproxy]')
    $Lines.Add('url = "https://api.keyproxyhub.store/mcp"')
    $Lines.Add('bearer_token_env_var = "KEYPROXY_API_KEY"')
    $Lines.Add('enabled = true')
}

function Merge-KeyProxyConfig {
    param([AllowEmptyString()][string]$Content)

    $source = $Content.Replace("`r`n", "`n").Replace("`r", "`n")
    if ($source.Length -eq 0) {
        $sourceLines = [string[]]@()
    }
    else {
        $sourceLines = [string[]]$source.Split("`n")
    }
    $output = New-Object 'Collections.Generic.List[string]'
    $section = 'top'
    $skipping = $false
    $firstSectionSeen = $false
    $modelSeen = $false
    $providerSeen = $false
    $providerSectionEmitted = $false
    $mcpSectionEmitted = $false
    $featuresSeen = $false
    $appsSeen = $false

    foreach ($line in $sourceLines) {
        $normalized = $line.Trim()
        $sectionMatch = [regex]::Match($normalized, '^\[{1,2}([^\]]+)\]{1,2}(?:\s*#.*)?$')
        if ($sectionMatch.Success) {
            if ($section -eq 'features' -and -not $appsSeen) {
                $output.Add('apps = false')
            }
            if (-not $firstSectionSeen) {
                if (-not $modelSeen) { $output.Add('model = "gpt-5.6-sol"') }
                if (-not $providerSeen) { $output.Add('model_provider = "keyproxy"') }
                $modelSeen = $true
                $providerSeen = $true
                if ($output.Count -gt 0 -and $output[$output.Count - 1] -ne '') { $output.Add('') }
                $firstSectionSeen = $true
            }

            $sectionName = $sectionMatch.Groups[1].Value
            if ($sectionName -eq 'model_providers.keyproxy') {
                if (-not $providerSectionEmitted) {
                    Add-CanonicalProvider -Lines $output
                    $providerSectionEmitted = $true
                }
                $section = 'provider'
                $skipping = $true
                continue
            }
            if ($sectionName -eq 'mcp_servers.keyproxy') {
                if (-not $mcpSectionEmitted) {
                    Add-CanonicalMcp -Lines $output
                    $mcpSectionEmitted = $true
                }
                $section = 'mcp'
                $skipping = $true
                continue
            }

            $skipping = $false
            if ($sectionName -eq 'features') {
                $section = 'features'
                $featuresSeen = $true
                $appsSeen = $false
            }
            else {
                $section = 'other'
            }
            $output.Add($line)
            continue
        }

        if ($skipping) { continue }

        if ($section -eq 'top') {
            if ($line -match '^\s*model\s*=') {
                if (-not $modelSeen) { $output.Add('model = "gpt-5.6-sol"') }
                $modelSeen = $true
                continue
            }
            if ($line -match '^\s*model_provider\s*=') {
                if (-not $providerSeen) { $output.Add('model_provider = "keyproxy"') }
                $providerSeen = $true
                continue
            }
            if ($line -match '^\s*(?:api_key|base_url)\s*=') {
                continue
            }
        }

        if ($section -eq 'features' -and $line -match '^\s*apps\s*=') {
            if (-not $appsSeen) { $output.Add('apps = false') }
            $appsSeen = $true
            continue
        }

        $output.Add($line)
    }

    if ($section -eq 'features' -and -not $appsSeen) {
        $output.Add('apps = false')
    }
    if (-not $firstSectionSeen) {
        if (-not $modelSeen) { $output.Add('model = "gpt-5.6-sol"') }
        if (-not $providerSeen) { $output.Add('model_provider = "keyproxy"') }
    }
    if (-not $providerSectionEmitted) {
        if ($output.Count -gt 0 -and $output[$output.Count - 1] -ne '') { $output.Add('') }
        Add-CanonicalProvider -Lines $output
    }
    if (-not $featuresSeen) {
        if ($output.Count -gt 0 -and $output[$output.Count - 1] -ne '') { $output.Add('') }
        $output.Add('[features]')
        $output.Add('apps = false')
    }
    if (-not $mcpSectionEmitted) {
        if ($output.Count -gt 0 -and $output[$output.Count - 1] -ne '') { $output.Add('') }
        Add-CanonicalMcp -Lines $output
    }

    while ($output.Count -gt 0 -and $output[$output.Count - 1] -eq '') {
        $output.RemoveAt($output.Count - 1)
    }
    return ([string]::Join("`r`n", $output) + "`r`n")
}

function Install-MergedConfig {
    if (-not (Test-Path -LiteralPath $script:ConfigHome -PathType Container)) {
        [IO.Directory]::CreateDirectory($script:ConfigHome) | Out-Null
    }

    $existingContent = ''
    if (Test-Path -LiteralPath $script:ConfigFile -PathType Leaf) {
        $script:ConfigExisted = $true
        $existingContent = [IO.File]::ReadAllText($script:ConfigFile)
    }
    else {
        $script:ConfigExisted = $false
    }

    $merged = Merge-KeyProxyConfig -Content $existingContent
    $candidate = Join-Path $script:TemporaryRoot 'config.toml'
    [IO.File]::WriteAllText($candidate, $merged, $script:Utf8NoBom)

    $validationHome = Join-Path $script:TemporaryRoot 'validation-codex-home'
    [IO.Directory]::CreateDirectory($validationHome) | Out-Null
    Copy-Item -LiteralPath $candidate -Destination (Join-Path $validationHome 'config.toml')
    $validationResult = Invoke-WithCodexHome -CodexHome $validationHome -Action {
        Invoke-Codex -Arguments @('--strict-config', '--version')
    }
    if ($validationResult.ExitCode -ne 0) {
        Stop-KeyProxyInstall 'A configuração mesclada não passou no parser estrito do Codex; nenhum config.toml foi alterado.'
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    if ($script:ConfigExisted) {
        $script:BackupFile = '{0}.{1}.{2}.bak' -f $script:ConfigFile, $timestamp, $PID
        Copy-Item -LiteralPath $script:ConfigFile -Destination $script:BackupFile
        Write-KeyProxyInfo ("Backup do Codex criado: {0}" -f $script:BackupFile)
    }

    $staging = Join-Path $script:ConfigHome ('.config.toml.keyproxy.{0}' -f $PID)
    [IO.File]::WriteAllText($staging, $merged, $script:Utf8NoBom)
    $script:ConfigInstalled = $true
    if ($script:ConfigExisted) {
        try {
            [IO.File]::Replace($staging, $script:ConfigFile, $null)
        }
        catch {
            Write-KeyProxyWarning 'File.Replace não está disponível neste volume; usando substituição no mesmo diretório.'
            Move-Item -LiteralPath $staging -Destination $script:ConfigFile -Force
        }
    }
    else {
        Move-Item -LiteralPath $staging -Destination $script:ConfigFile
    }

    $activeResult = Invoke-Codex -Arguments @('--strict-config', '--version')
    if ($activeResult.ExitCode -ne 0) {
        Stop-KeyProxyInstall 'O Codex rejeitou a configuração ativa.'
    }
}

function Find-JsonPropertyValue {
    param(
        [AllowNull()]$Node,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ($null -eq $Node) { return $null }
    if ($Node -is [string] -or $Node -is [ValueType]) { return $null }

    if ($Node -is [Collections.IDictionary]) {
        foreach ($key in $Node.Keys) {
            if ([string]$key -eq $Name) { return $Node[$key] }
            $nested = Find-JsonPropertyValue -Node $Node[$key] -Name $Name
            if ($null -ne $nested) { return $nested }
        }
        return $null
    }

    if ($Node -is [Collections.IEnumerable]) {
        foreach ($item in $Node) {
            $nested = Find-JsonPropertyValue -Node $item -Name $Name
            if ($null -ne $nested) { return $nested }
        }
        return $null
    }

    foreach ($property in $Node.PSObject.Properties) {
        if ($property.Name -eq $Name) { return $property.Value }
        $nested = Find-JsonPropertyValue -Node $property.Value -Name $Name
        if ($null -ne $nested) { return $nested }
    }
    return $null
}

function Validate-LocalConfiguration {
    Write-KeyProxyInfo 'Validando configuração, provider e MCP.'
    $strict = Invoke-Codex -Arguments @('--strict-config', '--version')
    if ($strict.ExitCode -ne 0) {
        Stop-KeyProxyInstall 'O Codex rejeitou a configuração ativa.'
    }

    $doctor = Invoke-Codex -Arguments @('doctor', '--json')
    if ($doctor.ExitCode -ne 0) {
        Stop-KeyProxyInstall 'codex doctor não conseguiu concluir.'
    }
    try {
        $diagnostic = $doctor.Text | ConvertFrom-Json
    }
    catch {
        Stop-KeyProxyInstall 'codex doctor não retornou JSON válido.'
    }
    $model = Find-JsonPropertyValue -Node $diagnostic -Name 'model'
    $provider = Find-JsonPropertyValue -Node $diagnostic -Name 'model provider'
    if ([string]$model -ne $script:KeyProxyModel) {
        Stop-KeyProxyInstall 'O diagnóstico não confirmou o modelo gpt-5.6-sol.'
    }
    if ([string]$provider -ne 'keyproxy') {
        Stop-KeyProxyInstall 'O diagnóstico não confirmou o provider keyproxy.'
    }

    $mcp = Invoke-Codex -Arguments @('mcp', 'get', 'keyproxy')
    if ($mcp.ExitCode -ne 0) {
        Stop-KeyProxyInstall 'O MCP keyproxy não foi encontrado.'
    }
}

function Test-KeyProxyMcpFailure {
    param([Parameter(Mandatory = $true)][string[]]$Lines)
    foreach ($line in $Lines) {
        $lower = $line.ToLowerInvariant()
        if ($lower -match 'keyproxy' -and $lower -match 'mcp' -and
            $lower -match '(failed|failure|error|unable|falhou|falha|erro|401|403|unauthorized|não autorizad[oa])') {
            return $true
        }
    }
    return $false
}

function Validate-Api {
    if ($SkipApiTest) {
        Write-KeyProxyWarning 'Teste real da API ignorado por -SkipApiTest.'
        return
    }

    $timeoutValue = if ([string]::IsNullOrWhiteSpace($env:KEYPROXY_CODEX_API_TIMEOUT_SECONDS)) { 90 } else { $env:KEYPROXY_CODEX_API_TIMEOUT_SECONDS }
    $timeoutSeconds = 0
    if (-not [int]::TryParse($timeoutValue, [ref]$timeoutSeconds) -or $timeoutSeconds -lt 1 -or $timeoutSeconds -gt 3600) {
        Stop-KeyProxyInstall 'KEYPROXY_CODEX_API_TIMEOUT_SECONDS precisa ser um inteiro entre 1 e 3600.'
    }
    Write-KeyProxyInfo ("Executando uma chamada real com {0} (prazo: {1}s)." -f $script:KeyProxyModel, $timeoutSeconds)
    $result = Invoke-Codex -Arguments @(
        'exec', '--sandbox', 'read-only', '--skip-git-repo-check',
        'Responda somente com: KEYPROXY_OK'
    ) -TimeoutSeconds $timeoutSeconds
    if ($result.TimedOut) {
        Write-KeyProxyWarning ("A chamada real excedeu o prazo de {0}s; o login OAuth oficial foi preservado." -f $timeoutSeconds)
        Stop-KeyProxyInstall 'Prazo excedido na chamada real do KeyProxy Hub.' 2
    }
    if ($result.ExitCode -ne 0) {
        Write-KeyProxyWarning ("A configuração local passou, mas a chamada real falhou (código {0})." -f $result.ExitCode)
        Write-KeyProxyWarning 'Confira sua chave, rede, cota e o endpoint do KeyProxy Hub.'
        foreach ($line in $result.Output) {
            if ($line -match '^(ERROR|error:|model:|provider:)|401|403|429|KEYPROXY_OK') {
                [Console]::Error.WriteLine($line)
            }
        }
        Stop-KeyProxyInstall 'Falha na chamada real do KeyProxy Hub.' 2
    }

    if ($result.Output -notcontains 'model: gpt-5.6-sol') {
        Stop-KeyProxyInstall 'A chamada não confirmou o modelo gpt-5.6-sol.'
    }
    if ($result.Output -notcontains 'provider: keyproxy') {
        Stop-KeyProxyInstall 'A chamada não confirmou o provider keyproxy.'
    }
    if ($result.Output -notcontains 'KEYPROXY_OK') {
        Stop-KeyProxyInstall 'A chamada terminou, mas não retornou KEYPROXY_OK.'
    }
    if (Test-KeyProxyMcpFailure -Lines $result.Output) {
        Write-KeyProxyWarning 'A resposta do modelo funcionou, mas o MCP keyproxy falhou ao iniciar.'
        foreach ($line in $result.Output) {
            if (($line -match 'keyproxy.*mcp') -or ($line -match 'mcp.*keyproxy')) {
                [Console]::Error.WriteLine($line)
            }
        }
        Stop-KeyProxyInstall 'Falha na inicialização do MCP keyproxy.' 2
    }
}

function Restore-LocalChanges {
    Write-KeyProxyWarning 'Falha antes da validação local; restaurando configuração e variável anteriores.'

    if ($script:ConfigInstalled) {
        try {
            if ($script:ConfigExisted -and -not [string]::IsNullOrWhiteSpace($script:BackupFile) -and
                (Test-Path -LiteralPath $script:BackupFile -PathType Leaf)) {
                Copy-Item -LiteralPath $script:BackupFile -Destination $script:ConfigFile -Force
            }
            else {
                Remove-Item -LiteralPath $script:ConfigFile -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-KeyProxyWarning ("Rollback do config.toml falhou: {0}" -f $_.Exception.Message)
        }
    }

    if ($script:UserEnvironmentChanged) {
        try {
            Set-UserApiKey -Value $script:PreviousUserApiKey
        }
        catch {
            Write-KeyProxyWarning ("Rollback da variável KEYPROXY_API_KEY falhou: {0}" -f $_.Exception.Message)
        }
    }

    if ($script:StateCreated -and -not [string]::IsNullOrWhiteSpace($script:StateFile)) {
        Remove-Item -LiteralPath $script:StateFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-KeyProxyMain {
    if ($Help) {
        Show-KeyProxyHelp
        return
    }

    Invoke-Preflight
    $script:TemporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('keyproxy-codex-{0}' -f [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($script:TemporaryRoot) | Out-Null

    $configuredHome = $env:CODEX_HOME
    if ([string]::IsNullOrWhiteSpace($configuredHome)) {
        $configuredHome = Join-Path $HOME '.codex'
    }
    $script:ConfigHome = [IO.Path]::GetFullPath($configuredHome)
    $script:ConfigFile = Join-Path $script:ConfigHome 'config.toml'
    $script:StateFile = Join-Path $script:ConfigHome 'keyproxy-codex-state.json'
    Assert-NoReparsePointInPath -Path $script:ConfigHome -Label 'CODEX_HOME'
    Assert-NoReparsePointInPath -Path $script:ConfigFile -Label 'config.toml'
    Assert-NoReparsePointInPath -Path $script:StateFile -Label 'manifesto de recuperação KeyProxy'
    Assert-ValidRecoveryState

    Show-KeyProxyBanner
    Write-KeyProxyInfo 'Sistema detectado: Windows nativo'
    Write-KeyProxyInfo ("Configuração Codex: {0}" -f $script:ConfigFile)

    Write-KeyProxyStep -Number 1 -Message 'verificando o Codex CLI'
    Install-CodexIfNeeded

    Write-KeyProxyStep -Number 2 -Message 'conferindo a configuração existente'
    Assert-SupportedExistingConfig

    $script:RollbackArmed = $true
    Write-KeyProxyStep -Number 3 -Message 'salvando sua API key com segurança'
    Read-AndStoreApiKey

    Write-KeyProxyStep -Number 4 -Message 'configurando modelo, API e MCP'
    Install-MergedConfig
    Validate-LocalConfiguration
    Write-RecoveryState
    $script:RollbackArmed = $false

    Write-KeyProxyStep -Number 5 -Message 'testando a conexão com o KeyProxy Hub'
    Validate-Api

    if ($SkipApiTest) {
        Write-KeyProxyWarning 'Login OAuth oficial preservado porque o teste real da API foi ignorado.'
    }
    else {
        Write-KeyProxyInfo 'Removendo o login OAuth oficial do Codex para uso exclusivo do KeyProxy.'
        $logout = Invoke-Codex -Arguments @('logout')
        if ($logout.ExitCode -ne 0) {
            Write-KeyProxyWarning 'Não havia login oficial ativo ou o logout não foi necessário.'
        }
    }

    [Console]::Out.WriteLine()
    [Console]::Out.WriteLine('===============================================')
    [Console]::Out.WriteLine(' Instalação concluída com sucesso')
    [Console]::Out.WriteLine('===============================================')
    Write-KeyProxyInfo ("Modelo: {0}" -f $script:KeyProxyModel)
    Write-KeyProxyInfo 'Provider: keyproxy'
    Write-KeyProxyInfo ("API: {0}" -f $script:KeyProxyBaseUrl)
    Write-KeyProxyInfo ("MCP: {0}" -f $script:KeyProxyMcpUrl)
    Write-KeyProxyInfo ("Configuração: {0}" -f $script:ConfigFile)
    Write-KeyProxyInfo 'Credencial: variável KEYPROXY_API_KEY do usuário Windows'
    if (-not [string]::IsNullOrWhiteSpace($script:BackupFile)) {
        Write-KeyProxyInfo ("Backup: {0}" -f $script:BackupFile)
    }
    Write-KeyProxyInfo 'Abra um novo terminal e execute: codex'
}

try {
    Invoke-KeyProxyMain
}
catch {
    if ($script:RollbackArmed) {
        Restore-LocalChanges
    }
    if ($script:ExitCode -eq 0) {
        $script:ExitCode = 1
    }
    [Console]::Error.WriteLine('[KeyProxy] ERRO: {0}', $_.Exception.Message)
}
finally {
    if (-not [string]::IsNullOrWhiteSpace($script:TemporaryRoot) -and
        (Test-Path -LiteralPath $script:TemporaryRoot -PathType Container)) {
        Remove-Item -LiteralPath $script:TemporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit $script:ExitCode
