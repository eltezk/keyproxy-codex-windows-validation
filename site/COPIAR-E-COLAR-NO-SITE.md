## Codex CLI com KeyProxy Hub

**Hospedado com HTTPS em `keyproxyhub.store`**

O instalador faz somente o necessário: verifica ou instala o Codex CLI oficial, solicita sua API key sem exibi-la e configura o modelo `gpt-5.6-sol`, a API e o MCP do KeyProxy Hub. Você pode visualizar o código antes de executar.

### macOS ou Linux

Abra o Terminal como usuário normal — sem `sudo` — e execute:

```bash
curl -fLO https://keyproxyhub.store/downloads/codex/install.sh && bash install.sh
```

[Ver script](https://keyproxyhub.store/downloads/codex/install.sh) · [Ver SHA-256](https://keyproxyhub.store/downloads/codex/install.sh.sha256)

<details>
<summary>Quero verificar o SHA-256 antes</summary>

```bash
curl -fLO https://keyproxyhub.store/downloads/codex/install.sh
curl -fLO https://keyproxyhub.store/downloads/codex/install.sh.sha256
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 -c install.sh.sha256
else
  sha256sum -c install.sh.sha256
fi
bash install.sh
```

</details>

### Windows

Abra o PowerShell como usuário normal — sem **Executar como administrador** — e execute:

```powershell
Invoke-WebRequest https://keyproxyhub.store/downloads/codex/install.ps1 -OutFile install.ps1; powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

[Ver script](https://keyproxyhub.store/downloads/codex/install.ps1) · [Ver SHA-256](https://keyproxyhub.store/downloads/codex/install.ps1.sha256)

`ExecutionPolicy Bypass` vale somente para esse processo do instalador. Ele não altera permanentemente a política do Windows. O arquivo é salvo no computador antes de ser executado e pode ser inspecionado.

<details>
<summary>Quero verificar o SHA-256 antes</summary>

```powershell
Invoke-WebRequest https://keyproxyhub.store/downloads/codex/install.ps1 -OutFile install.ps1
Invoke-WebRequest https://keyproxyhub.store/downloads/codex/install.ps1.sha256 -OutFile install.ps1.sha256
$Expected = (Get-Content .\install.ps1.sha256 -Raw).Split()[0].ToLowerInvariant()
$Actual = (Get-FileHash .\install.ps1 -Algorithm SHA256).Hash.ToLowerInvariant()
if ($Actual -ne $Expected) { throw 'SHA-256 divergente. Não execute o instalador.' }
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

</details>

Quando o instalador solicitar, cole sua API key e pressione Enter. A chave não aparecerá na tela. Ao concluir, abra um novo terminal e execute `codex`.

> **Usa WSL?** Execute o procedimento macOS/Linux dentro da distribuição Linux.

### Transparência e segurança

- Os scripts são hospedados no domínio oficial do KeyProxy e podem ser lidos antes da execução.
- Nenhum comando baixa conteúdo diretamente para um pipe de execução.
- O instalador cria backup da configuração existente e realiza rollback se a validação local falhar.
- Nunca envie sua API key em tickets, mensagens ou capturas de tela.
