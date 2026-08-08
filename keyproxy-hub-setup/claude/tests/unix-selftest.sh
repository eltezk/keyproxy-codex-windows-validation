#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export CLAUDE_CONFIG_DIR="$HOME/.claude"
export KEYPROXY_INSTALL_BIN="$HOME/.local/bin"
export KEYPROXY_SHELL_PROFILE="$HOME/.profile"
export KEYPROXY_CLAUDE_JSON="$HOME/.claude.json"
mkdir -p "$CLAUDE_CONFIG_DIR" "$TMP/fake-bin"
printf '{"language":"Portugues, Brasil","env":{"KEEP_ME":"yes"}}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
printf '{"keep":"yes","mcpServers":{"other":{"type":"http","url":"https://example.invalid/mcp"}}}\n' > "$KEYPROXY_CLAUDE_JSON"
cp "$CLAUDE_CONFIG_DIR/settings.json" "$TMP/original.json"
cp "$KEYPROXY_CLAUDE_JSON" "$TMP/original-claude.json"
cat > "$TMP/fake-bin/claude" <<'SH'
#!/usr/bin/env bash
[[ "${1:-}" == "--version" ]] && { echo "2.1.224"; exit 0; }
printf 'fake-claude:%s\n' "$*"
SH
chmod +x "$TMP/fake-bin/claude"
export PATH="$TMP/fake-bin:$PATH"
export KEYPROXY_API_KEY='kp_test_not_real'

# A falha de rede é intencional; o seletor deve usar a lista local.
bash "$ROOT/keyproxy-claude.sh" install > "$TMP/install.log" 2>&1
! grep -Fq "$KEYPROXY_API_KEY" "$TMP/install.log"
python3 "$ROOT/lib/keyproxy_claude_config.py" validate \
  --settings "$CLAUDE_CONFIG_DIR/settings.json" --claude-config "$KEYPROXY_CLAUDE_JSON" \
  --state "$CLAUDE_CONFIG_DIR/keyproxy-claude/state.json"
python3 - "$CLAUDE_CONFIG_DIR/settings.json" "$KEYPROXY_CLAUDE_JSON" <<'PY'
import json,sys
settings=json.load(open(sys.argv[1],encoding='utf-8'))
claude=json.load(open(sys.argv[2],encoding='utf-8'))
assert settings['env']['KEYPROXY_API_KEY']=='kp_test_not_real'
assert settings['env']['KEYPROXY_MODELS_URL']=='https://painel.keyproxyhub.store/v1/models'
assert settings['env']['ANTHROPIC_DEFAULT_OPUS_MODEL']=='gpt-5.6-sol'
assert settings['env']['ANTHROPIC_DEFAULT_FABLE_MODEL']=='gpt-5.6-sol'
assert settings['env']['ANTHROPIC_DEFAULT_SONNET_MODEL']=='gpt-5.6-terra'
assert settings['env']['ANTHROPIC_DEFAULT_HAIKU_MODEL']=='gpt-5.6-luna'
assert settings['env']['ANTHROPIC_CUSTOM_MODEL_OPTION']=='gpt-5.5'
assert settings['env']['CLAUDE_CODE_SUBAGENT_MODEL']=='inherit'
assert claude['keep']=='yes' and 'other' in claude['mcpServers']
assert claude['mcpServers']['keyproxy']=={'type':'http','url':'https://api.keyproxyhub.store/mcp','headers':{'Authorization':'Bearer ${KEYPROXY_API_KEY}'}}
assert 'kp_test_not_real' not in open(sys.argv[2],encoding='utf-8').read()
PY
count="$(bash "$ROOT/keyproxy-claude.sh" list 2>/dev/null | wc -l | tr -d ' ')"
[[ "$count" == 12 ]]
status="$(bash "$ROOT/keyproxy-claude.sh" status 2>/dev/null)"
grep -Fq 'Configuração: KeyProxy ativa' <<<"$status"
grep -Fq 'Credencial: configurada e ocultada' <<<"$status"
! grep -Fq "$KEYPROXY_API_KEY" <<<"$status"
"$KEYPROXY_INSTALL_BIN/keyproxy-claude" --model gpt-5.4 -- --print teste | grep -Fq 'fake-claude:--model gpt-5.4 --print teste'
if "$KEYPROXY_INSTALL_BIN/keyproxy-claude" --model invalid-model -- --print teste >/dev/null 2>&1; then
  printf 'Modelo inválido foi aceito.\n' >&2; exit 1
fi

# Reinstalar preserva o primeiro snapshot e restaura o JSON original.
state_hash_before="$(shasum -a 256 "$CLAUDE_CONFIG_DIR/keyproxy-claude/state.json" | cut -d ' ' -f 1)"
# Se o snapshot for perdido durante uma configuração ativa, a reinstalação falha
# em vez de salvar a própria configuração KeyProxy como estado original.
cp "$CLAUDE_CONFIG_DIR/keyproxy-claude/state.json" "$TMP/state.saved"
rm "$CLAUDE_CONFIG_DIR/keyproxy-claude/state.json"
if bash "$ROOT/keyproxy-claude.sh" install > "$TMP/missing-state.log" 2>&1; then
  printf 'Reinstalação aceitou configuração ativa sem snapshot.\n' >&2; exit 1
fi
! grep -Fq "$KEYPROXY_API_KEY" "$TMP/missing-state.log"
cp "$TMP/state.saved" "$CLAUDE_CONFIG_DIR/keyproxy-claude/state.json"
export KEYPROXY_API_KEY='kp_test_not_real'
bash "$ROOT/keyproxy-claude.sh" install >/dev/null 2>&1
state_hash_after="$(shasum -a 256 "$CLAUDE_CONFIG_DIR/keyproxy-claude/state.json" | cut -d ' ' -f 1)"
[[ "$state_hash_before" == "$state_hash_after" ]]
python3 - <<'PY'
import json,os
p=os.path.join(os.environ['CLAUDE_CONFIG_DIR'],'settings.json')
d=json.load(open(p)); assert d['language']=='Portugues, Brasil'; assert d['env']['KEEP_ME']=='yes'; assert len(d['availableModels'])==13
PY
bash "$ROOT/revert.sh" --dry-run > "$TMP/revert-dry.log"
grep -Fq 'dry-run=ok' "$TMP/revert-dry.log"
bash "$ROOT/keyproxy-claude.sh" revert >/dev/null
python3 - "$CLAUDE_CONFIG_DIR/settings.json" "$TMP/original.json" "$KEYPROXY_CLAUDE_JSON" "$TMP/original-claude.json" <<'PY'
import json,sys
with open(sys.argv[1],encoding='utf-8') as current, open(sys.argv[2],encoding='utf-8') as original:
    assert json.load(current) == json.load(original)
with open(sys.argv[3],encoding='utf-8') as current, open(sys.argv[4],encoding='utf-8') as original:
    assert json.load(current) == json.load(original)
PY

# Reset remove somente a configuração gerenciada.
export KEYPROXY_API_KEY='kp_test_not_real'
bash "$ROOT/keyproxy-claude.sh" install >/dev/null 2>&1
bash "$ROOT/reset-claude-default.sh" --dry-run > "$TMP/reset-dry.log"
grep -Fq 'dry-run=ok' "$TMP/reset-dry.log"
bash "$ROOT/keyproxy-claude.sh" reset >/dev/null
python3 - <<'PY'
import json,os
p=os.path.join(os.environ['CLAUDE_CONFIG_DIR'],'settings.json'); d=json.load(open(p)); assert d['language']=='Portugues, Brasil'; assert d['env']=={'KEEP_ME':'yes'}; assert 'model' not in d; assert 'availableModels' not in d
c=json.load(open(os.environ['KEYPROXY_CLAUDE_JSON'])); assert c['keep']=='yes'; assert list(c['mcpServers'])==['other']
PY
[[ ! -e "$KEYPROXY_INSTALL_BIN/keyproxy-claude" ]]
[[ ! -e "$CLAUDE_CONFIG_DIR/keyproxy-claude/state.json" ]]

# Configuração MCP divergente é recusada sem alterar arquivos.
printf '{"mcpServers":{"keyproxy":{"type":"http","url":"https://different.invalid/mcp"}}}\n' > "$KEYPROXY_CLAUDE_JSON"
cp "$CLAUDE_CONFIG_DIR/settings.json" "$TMP/before-conflict-settings"
if bash "$ROOT/keyproxy-claude.sh" install > "$TMP/conflict.log" 2>&1; then
  printf 'Instalação sobrescreveu MCP divergente.\n' >&2; exit 1
fi
cmp -s "$CLAUDE_CONFIG_DIR/settings.json" "$TMP/before-conflict-settings"
! grep -Fq "$KEYPROXY_API_KEY" "$TMP/conflict.log"
if bash "$ROOT/keyproxy-claude.sh" reset > "$TMP/conflict-reset.log" 2>&1; then
  printf 'Reset aceitou MCP divergente.\n' >&2; exit 1
fi
grep -Fq 'https://different.invalid/mcp' "$KEYPROXY_CLAUDE_JSON"
! grep -Fq "$KEYPROXY_API_KEY" "$TMP/conflict-reset.log"

# Nenhum caminho de código aceita token em argv.
! grep -RE -- '--token([ =]|$)' "$ROOT/install.sh" "$ROOT/lib/keyproxy_claude_config.py" >/dev/null
printf 'unix-selftest=ok\n'
