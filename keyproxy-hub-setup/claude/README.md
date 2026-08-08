# KeyProxy Hub para Claude Code

Pacote independente para configurar o **Claude Code** com o KeyProxy, escolher modelos e voltar com segurança à configuração anterior ou ao provider oficial.

Ele altera somente arquivos do usuário em `~/.claude`, registra o MCP de escopo de usuário em `~/.claude.json` (equivalentes no `%USERPROFILE%` no Windows) e instala o seletor no perfil do usuário. Quando `CLAUDE_CONFIG_DIR` é customizado, use também `KEYPROXY_CLAUDE_JSON="$CLAUDE_CONFIG_DIR/.claude.json"` para manter o arquivo global no mesmo diretório que o próprio Claude Code consulta. Não encerra Claude Code, Orca nem outros processos.

## Uso simples

Baixe e extraia o pacote antes de executar. Não use download por pipe para o shell.

### macOS, Linux e Ubuntu

Pré-requisitos: Claude Code funcional, Python 3 e Bash.

```bash
cd keyproxy-claude-code-setup
bash keyproxy-claude.sh
```

### Windows

Abra PowerShell como usuário normal. Não é necessário executar como administrador.

```powershell
Set-Location .\keyproxy-claude-code-setup
.\keyproxy-claude.ps1
```

O menu oferece:

1. instalar ou atualizar KeyProxy;
2. abrir Claude Code e escolher modelo;
3. listar modelos disponíveis;
4. verificar status e conexão;
5. restaurar a configuração anterior;
6. voltar ao Claude oficial;
7. sair.

O instalador solicita a API key sem exibi-la. Nenhuma chave está incluída no pacote.

## Uso por comando

macOS/Linux:

```bash
bash keyproxy-claude.sh install
bash keyproxy-claude.sh open
bash keyproxy-claude.sh list
bash keyproxy-claude.sh status
bash keyproxy-claude.sh revert
bash keyproxy-claude.sh reset
```

Windows:

```powershell
.\keyproxy-claude.ps1 install
.\keyproxy-claude.ps1 open
.\keyproxy-claude.ps1 list
.\keyproxy-claude.ps1 status
.\keyproxy-claude.ps1 revert
.\keyproxy-claude.ps1 reset
```

`revert` restaura as chaves existentes antes da primeira instalação ativa. `reset` remove somente as chaves gerenciadas pelo KeyProxy, elimina o snapshot que pode conter credenciais anteriores e retorna ao Claude oficial; o próximo uso pode solicitar login. Se uma configuração KeyProxy estiver ativa, mas seu snapshot estiver ausente ou inválido, a reinstalação falhará de forma segura em vez de substituir a referência original.

## Configuração aplicada

- API: `https://api.keyproxyhub.store/v1`;
- principal: `gpt-5.6-sol`;
- allowlist com os 13 IDs anunciados pelo KeyProxy;
- aliases internos do Claude Code apontando somente para IDs KeyProxy;
- subagentes, agent teams e workflows herdando o modelo da sessão;
- catálogo autenticado: `https://painel.keyproxyhub.store/v1/models`;
- MCP HTTP: `https://api.keyproxyhub.store/mcp`;
- seletor dinâmico que consulta o catálogo e filtra a resposta pela allowlist local.

| Alias interno | Modelo KeyProxy |
|---|---|
| Default / Opus / Fable | `gpt-5.6-sol` |
| Sonnet | `gpt-5.6-terra` |
| Haiku | `gpt-5.6-luna` |
| Custom | `gpt-5.5` |

### MCP público

A instalação mescla, sem apagar outros servidores, esta definição em `~/.claude.json` ou `%USERPROFILE%\.claude.json`:

```json
{
  "mcpServers": {
    "keyproxy": {
      "type": "http",
      "url": "https://api.keyproxyhub.store/mcp",
      "headers": {
        "Authorization": "Bearer ${KEYPROXY_API_KEY}"
      }
    }
  }
}
```

O arquivo global contém apenas o placeholder `${KEYPROXY_API_KEY}`. O Claude Code expande essa variável a partir do ambiente gerenciado em `settings.json`; o valor da chave não é duplicado no JSON do MCP. Se já existir um servidor chamado `keyproxy` com outra definição, `install` e `reset` recusam a operação em vez de sobrescrever ou remover configuração alheia.

O comando `status` distingue configuração local de conectividade: `MCP KeyProxy: configurado` confirma que o registro está correto, não que uma chamada de ferramenta acabou de ocorrer. A validação de release executa separadamente `initialize`, `tools/list` e uma chamada real de ferramenta.

Dentro de uma sessão existente também é possível usar o ID exato:

```text
/model gpt-5.5
```

## Situação real dos modelos

A API anuncia 13 IDs. O seletor não oferece `auto` como escolha concreta.

**Validados no protocolo completo do Claude Code:**

- `gpt-5.6-sol`;
- `gpt-5.6-terra`;
- `gpt-5.6-luna`;
- `gpt-5.5`;
- `gpt-5.4`;
- `gpt-5.4-mini`;
- `gpt-5.3-codex-spark`.

`gpt-5.3-codex-spark` permanece como opção manual validada, mas não é usado por nenhum alias automático. Em sessões onde ele apresentou chamadas de ferramenta inválidas ou indisponibilidade, selecione outro modelo permitido com o seletor ou `/model`.

**Anunciados pelo gateway, mas atualmente incompatíveis nesse fluxo:**

- `gpt-5.3-codex`;
- `gpt-5.3-codex-xhigh`;
- `gpt-5.3-codex-high`;
- `gpt-5.3-codex-low`;
- `gpt-5.3-codex-none`.

`auto` respondeu `No tool-capable model is available for this API key`. As cinco variantes acima retornaram `400 Bad request`, apesar de `/v1/models` indicar `toolCalling: true`.

O seletor identifica opções validadas e opções apenas anunciadas. Se uma opção incompatível for escolhida, o ID exato será enviado; nunca ocorre troca silenciosa por outro modelo.

## Subagentes, agent teams e workflows

A instalação define `CLAUDE_CODE_SUBAGENT_MODEL=inherit`. Assim, subagentes, agent teams e workflows sem override explícito herdam o modelo da sessão, cujo padrão é `gpt-5.6-sol`. Os aliases internos usados por tarefas rápidas apontam somente para modelos KeyProxy:

- `opus` → `gpt-5.6-sol`;
- `fable` → `gpt-5.6-sol`;
- `sonnet` → `gpt-5.6-terra`;
- `haiku` → `gpt-5.6-luna`;
- `custom` → `gpt-5.5`.

A allowlist de 13 IDs e `enforceAvailableModels=true` evitam a seleção normal de modelos fora do KeyProxy. Um custom agent ou workflow escrito manualmente com um ID oficial fixo não é traduzido silenciosamente: ele deve ser recusado pela allowlist. Para herança garantida, omita `model` ou use `model: inherit` nas definições customizadas.

A validação controlada do pacote confirmou uma sessão `gpt-5.6-sol`, chamada MCP e criação de subagente via `Agent`. O runtime informa o modelo da sessão; não fornece, em todos os formatos de evento, um comprovante separado do identificador interno de cada chamada do subagente. Por isso a garantia é baseada em `inherit`, aliases KeyProxy e allowlist, não em uma alegação de telemetria inexistente.

## Limitação do picker nativo

No Claude Code 2.1.224, a descoberta de gateway mantém somente IDs contendo `claude` ou `anthropic`. Como os IDs KeyProxy começam com `gpt-`, os 13 não aparecem automaticamente como linhas separadas no `/model`. `ANTHROPIC_CUSTOM_MODEL_OPTION` também permite somente uma entrada adicional.

Por isso o pacote combina aliases distintos no picker nativo com o seletor externo `keyproxy-claude`.

Uma melhoria futura no gateway é anunciar aliases como `keyproxy/claude/gpt-5.6-sol` e aceitar esses mesmos aliases na rota `/v1/messages`, traduzindo-os internamente para os IDs reais.

## Scripts avançados

As operações internas continuam disponíveis separadamente:

| Operação | macOS/Linux | Windows |
|---|---|---|
| Instalar | `bash install.sh` | `.\install.ps1` |
| Restaurar snapshot | `bash revert.sh` | `.\revert.ps1` |
| Voltar ao oficial | `bash reset-claude-default.sh` | `.\reset-claude-default.ps1` |
| Selecionar modelo | `keyproxy-claude` | `keyproxy-claude.ps1` |

Simulação sem alteração:

```bash
bash revert.sh --dry-run
bash reset-claude-default.sh --dry-run
```

```powershell
.\revert.ps1 -DryRun
.\reset-claude-default.ps1 -DryRun
```

## Segurança

- A API key não é embutida ou impressa.
- No Unix, a chave é entregue ao merge por stdin e não aparece nos argumentos do processo.
- No Windows, o prompt usa `SecureString`; evite fornecer segredo em linha de comando.
- `settings.json`, `~/.claude.json`, estado e cache usam permissões restritas; cópias transacionais são temporárias e removidas ao final.
- O seletor bloqueia redirects na descoberta Unix e usa `MaximumRedirection 0` no PowerShell.
- A resposta da API é filtrada pela allowlist local.
- Instalações repetidas preservam o primeiro snapshot enquanto o KeyProxy estiver ativo.
- Os instaladores e o reset restauram settings, state, helper, perfil/PATH quando uma etapa intermediária falha.
- Nenhum script encerra processos ou executa um download diretamente por pipe.

O Claude Code precisa armazenar `ANTHROPIC_AUTH_TOKEN` e `KEYPROXY_API_KEY` em `settings.json`: a primeira autentica a API de mensagens e a segunda expande o header do MCP. Para que `revert` possa restaurar exatamente uma configuração anterior, o snapshot restrito também pode conter um token anterior que já existia; `reset` apaga esse snapshot. Proteja sua conta do sistema operacional e rotacione qualquer chave exposta.

## Testes

macOS/Linux:

```bash
bash -n keyproxy-claude.sh install.sh revert.sh reset-claude-default.sh tests/unix-selftest.sh
python3 -m py_compile lib/keyproxy_claude_config.py bin/keyproxy-claude
bash tests/unix-selftest.sh
```

Windows PowerShell:

```powershell
.\tests\windows-selftest.ps1
```

A suíte foi executada com PowerShell 7. A sintaxe foi analisada pelo parser compatível, mas PowerShell 5.1 ainda exige validação final em um Windows real ou runner Windows antes de ser declarado certificado.

## Arquivos

```text
README.md
SHA256SUMS
keyproxy-claude.sh
keyproxy-claude.ps1
install.sh
install.ps1
revert.sh
revert.ps1
reset-claude-default.sh
reset-claude-default.ps1
bin/keyproxy-claude
bin/keyproxy-claude.ps1
lib/keyproxy_claude_config.py
tests/unix-selftest.sh
tests/windows-selftest.ps1
```
