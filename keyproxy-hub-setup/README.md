# KeyProxy Hub Setup

Pacote autocontido para macOS, Linux e Windows que centraliza os módulos auditados do **Claude Code** e do **Codex CLI**. Ele oferece um menu único, mas mantém as operações sensíveis dentro de cada módulo especializado: não reimplementa merge de JSON/TOML, não lê a API key e não encerra processos.

## Antes de usar

1. Baixe e extraia o pacote. **Não execute downloads diretamente por pipe**.
2. Confira o checksum do ZIP recebido e, dentro da pasta extraída, valide os arquivos:

```bash
bash keyproxy-hub.sh validate
```

```powershell
.\keyproxy-hub.ps1 validate
```

A validação local não consulta a API nem altera configurações. Ela checa sintaxe e hashes do pacote.

## Menu único

### macOS e Linux

```bash
cd keyproxy-hub-setup
bash keyproxy-hub.sh
```

### Windows PowerShell 5.1 ou PowerShell 7

Abra o PowerShell como usuário normal — sem Administrador:

```powershell
Set-Location .\keyproxy-hub-setup
.\keyproxy-hub.ps1
```

O terminal usa uma paleta escura/laranja quando a saída é interativa. Em CI, SSH com saída redirecionada ou com `NO_COLOR=1`, a saída é textual e sem ANSI.

## Ações disponíveis

1. Configurar ou atualizar KeyProxy no Claude Code.
2. Abrir o seletor de modelos do Claude Code.
3. Configurar ou atualizar KeyProxy no Codex CLI.
4. Mostrar status sanitizado dos dois módulos.
5. Validar módulos e checksums do pacote.
6. Restaurar o snapshot anterior do Claude Code.
7. Voltar o Claude Code ao provider oficial.
8. Listar backups do Codex e mostrar instruções de restauração manual.

As ações 6 e 7 pedem confirmação no menu. Em automação, elas exigem confirmação explícita:

```bash
bash keyproxy-hub.sh revert-claude --yes
bash keyproxy-hub.sh reset-claude --yes
```

```powershell
.\keyproxy-hub.ps1 revert-claude -Yes
.\keyproxy-hub.ps1 reset-claude -Yes
```

## Comandos não interativos

| Objetivo | macOS/Linux | Windows |
|---|---|---|
| Instalar Claude | `bash keyproxy-hub.sh install-claude` | `.\keyproxy-hub.ps1 install-claude` |
| Abrir seletor Claude | `bash keyproxy-hub.sh open-claude` | `.\keyproxy-hub.ps1 open-claude` |
| Instalar Codex | `bash keyproxy-hub.sh install-codex` | `.\keyproxy-hub.ps1 install-codex` |
| Status sanitizado | `bash keyproxy-hub.sh status` | `.\keyproxy-hub.ps1 status` |
| Recuperação Codex | `bash keyproxy-hub.sh codex-recovery` | `.\keyproxy-hub.ps1 codex-recovery` |

Argumentos adicionais de instalação são encaminhados ao módulo correspondente. Por exemplo, para instalar Codex sem a chamada real de API (preservando OAuth oficial):

```bash
bash keyproxy-hub.sh install-codex --skip-api-test
```

```powershell
.\keyproxy-hub.ps1 install-codex -SkipApiTest
```

O uso de `--skip-api-test` / `-SkipApiTest` reduz a validação e deve ser reservado a diagnóstico controlado. Quando usado, os instaladores Codex preservam o login OAuth oficial.

## Recuperação do Codex CLI

O pacote **não executa reversão automática do Codex**. O instalador Codex cria backups de `config.toml` quando substitui uma configuração existente, mas o launcher não pode garantir que cada backup pertence ao KeyProxy ou que ele é o estado desejado. A opção `codex-recovery` apenas lista arquivos `config.toml.*.bak` no `CODEX_HOME` e imprime um comando de restauração para você revisar e executar manualmente.

Se nenhum backup comprovável existir, a ferramenta informa isso e não altera nada.

## Curadoria de modelos Claude Code

O módulo Claude instala a seguinte curadoria:

| Alias | Modelo KeyProxy |
|---|---|
| Default / Opus / Fable | `gpt-5.6-sol` |
| Sonnet | `gpt-5.6-terra` |
| Haiku | `gpt-5.6-luna` |
| Custom | `gpt-5.5` |

Também define `CLAUDE_CODE_SUBAGENT_MODEL=inherit`. Assim, subagentes, teams e workflows sem override herdam o modelo ativo da sessão. `gpt-5.3-codex-spark` permanece uma opção manual na allowlist, mas não é selecionado automaticamente por aliases rápidos.

## Segurança

- Nunca informe API key como argumento de linha de comando.
- Não há API key, token ou credencial embutida no pacote.
- O menu não lê, registra nem imprime segredos.
- Não use `curl | sh`, `wget | sh` ou `irm | iex`.
- O módulo Codex valida HTTPS e redirecionamento do bootstrap oficial antes de executá-lo.
- O módulo Claude usa escrita atômica, snapshot e rollback transacional.
- O módulo Codex recusa symlinks/reparse points em caminhos controlados e preserva OAuth quando o teste real é ignorado ou falha.
- O status não mostra valores de credenciais.
- Nenhum script encerra Claude Code, Codex, Orca ou outros processos.

## Testes de desenvolvimento

```bash
bash -n keyproxy-hub.sh tests/unix-selftest.sh scripts/build-package.sh
bash tests/unix-selftest.sh
bash claude/tests/unix-selftest.sh
bash codex/keyproxy-codex-unix-selftest.sh codex/keyproxy-codex-install.sh
bash scripts/build-package.sh
```

```powershell
.\tests\windows-selftest.ps1
.\claude\tests\windows-selftest.ps1
.\codex\keyproxy-codex-windows-native-selftest.ps1 -InstallerPath .\codex\keyproxy-codex-install-windows.ps1
```

A validação Windows nativa deve ser executada tanto em Windows PowerShell 5.1 quanto em PowerShell 7 antes de distribuir a clientes.
