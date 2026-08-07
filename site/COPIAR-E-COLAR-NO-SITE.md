## Instalar Codex CLI com KeyProxy Hub

O instalador verifica primeiro se o **Codex CLI** está funcionando. Se necessário, ele instala ou repara o Codex automaticamente. Depois, configura o modelo `gpt-5.6-sol`, a API e o MCP do KeyProxy Hub.

Tenha sua **API key do KeyProxy** em mãos. Quando o instalador pedir a chave, cole-a e pressione Enter. A chave não será exibida na tela.

### macOS ou Linux

Abra o **Terminal** como usuário normal — não use `sudo` nem `root` —, copie o bloco inteiro abaixo e pressione Enter:

```bash
set -e
DIR="$HOME/Downloads/keyproxy-codex"
BASE="https://keyproxyhub.store/downloads/codex"
mkdir -p "$DIR"
cd "$DIR"
curl -fL "$BASE/keyproxy-codex-install.sh" -o keyproxy-codex-install.sh
curl -fL "$BASE/keyproxy-codex-install.sh.sha256" -o keyproxy-codex-install.sh.sha256
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 -c keyproxy-codex-install.sh.sha256
else
  sha256sum -c keyproxy-codex-install.sh.sha256
fi
chmod 700 keyproxy-codex-install.sh
./keyproxy-codex-install.sh
```

Ao terminar, abra um novo Terminal e execute:

```bash
codex
```

### Windows

Abra o **Windows PowerShell** ou **PowerShell 7** como usuário normal. Não use **Executar como administrador**. Copie o bloco inteiro abaixo e pressione Enter:

```powershell
$ErrorActionPreference = 'Stop'
$Dir = Join-Path $HOME 'Downloads\keyproxy-codex'
$Base = 'https://keyproxyhub.store/downloads/codex'
New-Item -ItemType Directory -Path $Dir -Force | Out-Null
Set-Location $Dir
$Script = Join-Path $Dir 'keyproxy-codex-install-windows.ps1'
$Checksum = "$Script.sha256"
Invoke-WebRequest -Uri "$Base/keyproxy-codex-install-windows.ps1" -OutFile $Script
Invoke-WebRequest -Uri "$Base/keyproxy-codex-install-windows.ps1.sha256" -OutFile $Checksum
$Expected = (Get-Content $Checksum -Raw).Split()[0].ToLowerInvariant()
$Actual = (Get-FileHash $Script -Algorithm SHA256).Hash.ToLowerInvariant()
if ($Actual -ne $Expected) { throw "Falha de segurança: SHA-256 divergente. Não execute o instalador." }
Write-Host "Arquivo verificado: $Actual"
if ($PSVersionTable.PSEdition -eq 'Core') {
    & pwsh.exe -NoProfile -File $Script
} else {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script
}
if ($LASTEXITCODE -ne 0) { throw "O instalador terminou com código $LASTEXITCODE." }
```

Ao terminar, abra um novo PowerShell e execute:

```powershell
codex
```

> **Usa WSL?** Execute o procedimento de macOS/Linux dentro da distribuição Linux. Não use o instalador PowerShell dentro do WSL.

### Precisa de ajuda?

- Para trocar a API key, execute novamente o mesmo instalador.
- Se a validação SHA-256 falhar, não execute o arquivo e contate o suporte.
- Nunca envie sua API key em tickets, mensagens ou capturas de tela.
