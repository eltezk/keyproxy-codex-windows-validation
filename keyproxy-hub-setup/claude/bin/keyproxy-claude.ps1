[CmdletBinding()]
param(
    [string]$Model,
    [switch]$List,
    [string]$ConfigDir = $(if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }),
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$ClaudeArgs
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$SettingsPath = Join-Path $ConfigDir 'settings.json'
$CachePath = Join-Path $ConfigDir 'cache\keyproxy-models.json'
$Fallback = @('auto','gpt-5.6-sol','gpt-5.6-terra','gpt-5.6-luna','gpt-5.5','gpt-5.4','gpt-5.4-mini','gpt-5.3-codex','gpt-5.3-codex-xhigh','gpt-5.3-codex-high','gpt-5.3-codex-low','gpt-5.3-codex-none','gpt-5.3-codex-spark')
$Validated = @('gpt-5.6-sol','gpt-5.6-terra','gpt-5.6-luna','gpt-5.5','gpt-5.4','gpt-5.4-mini','gpt-5.3-codex-spark')
$settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
$baseUrl = [string]$settings.env.ANTHROPIC_BASE_URL
$modelsUrl = if ($settings.env.PSObject.Properties['KEYPROXY_MODELS_URL']) { [string]$settings.env.KEYPROXY_MODELS_URL } else { 'https://painel.keyproxyhub.store/v1/models' }
$token = if ($env:KEYPROXY_API_KEY) { $env:KEYPROXY_API_KEY } elseif ($settings.env.PSObject.Properties['KEYPROXY_API_KEY']) { [string]$settings.env.KEYPROXY_API_KEY } else { [string]$settings.env.ANTHROPIC_AUTH_TOKEN }
$allowed = @($settings.availableModels | Where-Object { $Fallback -contains $_ })
if ($baseUrl -ne 'https://api.keyproxyhub.store/v1' -or -not $modelsUrl.StartsWith('https://') -or [string]::IsNullOrWhiteSpace($token)) { throw 'KeyProxy não está configurado.' }
$url = if ($modelsUrl.Contains('?')) { $modelsUrl } else { $modelsUrl + '?limit=1000' }
$models = @()
try {
    $headers = @{ Authorization = 'Bearer ' + $token; Accept = 'application/json' }
    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 3 -MaximumRedirection 0
    foreach ($row in @($response.data)) {
        $id = [string]$row.id
        $toolCapable = -not $row.PSObject.Properties['capabilities'] -or $row.capabilities.toolCalling -eq $true
        if ($id -and $id -ne 'auto' -and $toolCapable -and $allowed -contains $id -and $models -notcontains $id) { $models += $id }
    }
    if ($models.Count -eq 0) { throw 'A API não retornou modelos autorizados.' }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $CachePath) | Out-Null
    [IO.File]::WriteAllText($CachePath, ((@{models=$models} | ConvertTo-Json -Compress) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
} catch {
    Write-Warning 'Descoberta indisponível; usando lista local ou cache.'
    if (Test-Path -LiteralPath $CachePath) { try { $models = @((Get-Content $CachePath -Raw | ConvertFrom-Json).models | Where-Object { $allowed -contains $_ }) } catch { $models = @() } }
    if ($models.Count -eq 0) { $models = @($Fallback | Where-Object { $_ -ne 'auto' -and $allowed -contains $_ }) }
}
if ($List) { $models; exit 0 }
if ([string]::IsNullOrWhiteSpace($Model)) {
    Write-Host 'Modelos disponíveis no KeyProxy'
    Write-Host '  [validado] = testado no fluxo completo do Claude Code'
    Write-Host '  [gateway]  = anunciado, mas atualmente incompatível nesse fluxo'
    for ($i=0; $i -lt $models.Count; $i++) {
        $status = if ($Validated -contains $models[$i]) { 'validado' } else { 'gateway' }
        $suffix = if ($models[$i] -eq 'gpt-5.6-sol') { ', padrão' } else { '' }
        Write-Host ('  {0,2}. {1} [{2}{3}]' -f ($i+1), $models[$i], $status, $suffix)
    }
    do { $answer = Read-Host 'Selecione o número do modelo'; $number = 0; $valid = [int]::TryParse($answer,[ref]$number) -and $number -ge 1 -and $number -le $models.Count } until ($valid)
    $Model = $models[$number-1]
}
if ($models -notcontains $Model) { throw "Modelo não autorizado ou indisponível: $Model" }
$originalKey = $env:KEYPROXY_API_KEY
$keyWasDefined = Test-Path Env:KEYPROXY_API_KEY
try {
    $env:KEYPROXY_API_KEY = $token
    & claude --model $Model @ClaudeArgs
    $status = $LASTEXITCODE
} finally {
    if ($keyWasDefined) { $env:KEYPROXY_API_KEY = $originalKey }
    else { Remove-Item Env:KEYPROXY_API_KEY -ErrorAction SilentlyContinue }
    $originalKey = $null
    $token = $null
}
exit $status
