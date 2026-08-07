# Instaladores KeyProxy Hub para Codex CLI

Este pacote instala ou verifica primeiro o **Codex CLI oficial** e, somente depois, configura o KeyProxy Hub:

- modelo: `gpt-5.6-sol`;
- provider: `keyproxy`;
- API: `https://api.keyproxyhub.store/v1`;
- MCP: `https://api.keyproxyhub.store/mcp`;
- credencial: variável `KEYPROXY_API_KEY`;
- OAuth e apps oficiais desativados para uso exclusivo do KeyProxy.

## Arquivos

| Plataforma | Instalador | Checksum |
|---|---|---|
| macOS e Linux | `keyproxy-codex-install.sh` | `keyproxy-codex-install.sh.sha256` |
| Windows nativo | `keyproxy-codex-install-windows.ps1` | `keyproxy-codex-install-windows.ps1.sha256` |

`keyproxy-codex-windows-native-selftest.ps1` é o harness de validação para Windows PowerShell 5.1 e PowerShell 7. Ele usa chave e Codex fictícios; não é necessário para o cliente final.

## Comportamento do bootstrap

Em todas as plataformas, o instalador segue esta ordem:

1. procura o comando `codex`;
2. executa `codex --version` para comprovar que a instalação encontrada funciona;
3. se estiver ausente ou inválida, baixa o instalador oficial do Codex para um arquivo temporário;
4. valida a sintaxe do instalador oficial antes de executá-lo;
5. executa o instalador oficial sem `curl | sh` nem `irm | iex`;
6. atualiza o `PATH` da sessão e exige que `codex --version` funcione;
7. somente então solicita a API key e aplica a configuração KeyProxy.

Se o Codex não puder ser instalado ou validado, o KeyProxy não é aplicado.

## macOS e Linux

Baixe os arquivos, trocando `URL_BASE` pela URL de publicação:

```bash
URL_BASE="https://SEU-DOMINIO/caminho"
curl -fL "$URL_BASE/keyproxy-codex-install.sh" -o keyproxy-codex-install.sh
curl -fL "$URL_BASE/keyproxy-codex-install.sh.sha256" -o keyproxy-codex-install.sh.sha256
```

Verifique e execute:

```bash
shasum -a 256 -c keyproxy-codex-install.sh.sha256 2>/dev/null || sha256sum -c keyproxy-codex-install.sh.sha256
chmod 700 keyproxy-codex-install.sh
./keyproxy-codex-install.sh
```

O script aceita Bash ou Zsh como shell do usuário. Não execute com `sudo` ou como `root`.

## Windows nativo

Baixe os arquivos, trocando as URLs:

```powershell
Invoke-WebRequest `
  -Uri 'https://SEU-DOMINIO/caminho/keyproxy-codex-install-windows.ps1' `
  -OutFile '.\keyproxy-codex-install-windows.ps1'

Invoke-WebRequest `
  -Uri 'https://SEU-DOMINIO/caminho/keyproxy-codex-install-windows.ps1.sha256' `
  -OutFile '.\keyproxy-codex-install-windows.ps1.sha256'
```

Verifique o SHA-256:

```powershell
$Expected = (Get-Content '.\keyproxy-codex-install-windows.ps1.sha256' -Raw).Split()[0].ToLowerInvariant()
$Actual = (Get-FileHash '.\keyproxy-codex-install-windows.ps1' -Algorithm SHA256).Hash.ToLowerInvariant()
if ($Actual -ne $Expected) { throw "SHA-256 divergente. Esperado: $Expected; obtido: $Actual" }
Write-Host "SHA-256 confirmado: $Actual"
```

Execute no Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File '.\keyproxy-codex-install-windows.ps1'
```

Ou no PowerShell 7:

```powershell
pwsh.exe -NoProfile -File '.\keyproxy-codex-install-windows.ps1'
```

Não execute como Administrador. Dentro do WSL, use o instalador Bash, não o instalador PowerShell nativo.

## Segurança

- Nunca publique uma API key dentro dos scripts ou da documentação.
- Nunca recomende `curl URL | sh`, `wget URL | sh` ou `irm URL | iex`.
- O cliente deve baixar, inspecionar, verificar o SHA-256 e somente depois executar.
- A chave é solicitada sem eco e não é escrita no `config.toml`.
