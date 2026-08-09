#!/usr/bin/env bash
# Configura Claude Code para KeyProxy sem encerrar sessões ou processos.

set -Eeuo pipefail
umask 077

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CONFIG_DIR/settings.json"
CLAUDE_JSON="${KEYPROXY_CLAUDE_JSON:-$HOME/.claude.json}"
STATE="$CONFIG_DIR/keyproxy-claude/state.json"
INSTALL_BIN="${KEYPROXY_INSTALL_BIN:-$HOME/.local/bin}"
HELPER="$INSTALL_BIN/keyproxy-claude"
PROFILE="${KEYPROXY_SHELL_PROFILE:-}"
MARKER_BEGIN='# >>> keyproxy-claude-code >>>'
MARKER_END='# <<< keyproxy-claude-code <<<'

rollback_needed=false
transaction_dir=''
settings_backup=''
claude_backup=''
state_backup=''
helper_backup=''
profile_backup=''
settings_existed=false
claude_existed=false
state_existed=false
helper_existed=false
profile_existed=false

cleanup() {
  if [[ -n "$transaction_dir" ]]; then rm -rf "$transaction_dir"; fi
  return 0
}

fail() {
  printf 'Erro: %s\n' "$*" >&2
  exit 1
}

rollback() {
  local status=$?
  trap - ERR INT TERM
  if [[ "$rollback_needed" == true ]]; then
    if [[ "$settings_existed" == true && -f "$settings_backup" ]]; then cp -p "$settings_backup" "$SETTINGS"; else rm -f "$SETTINGS"; fi
    if [[ "$claude_existed" == true && -f "$claude_backup" ]]; then cp -p "$claude_backup" "$CLAUDE_JSON"; else rm -f "$CLAUDE_JSON"; fi
    if [[ "$state_existed" == true && -f "$state_backup" ]]; then cp -p "$state_backup" "$STATE"; else rm -f "$STATE"; fi
    if [[ "$helper_existed" == true && -f "$helper_backup" ]]; then cp -p "$helper_backup" "$HELPER"; else rm -f "$HELPER"; fi
    if [[ "$profile_existed" == true && -f "$profile_backup" ]]; then cp -p "$profile_backup" "$PROFILE"; else rm -f "$PROFILE"; fi
  fi
  cleanup
  exit "$status"
}
trap rollback ERR INT TERM
trap cleanup EXIT

command -v python3 >/dev/null 2>&1 || fail 'Python 3 é obrigatório.'
command -v claude >/dev/null 2>&1 || fail 'Claude Code não foi encontrado no PATH. Instale-o pelo canal oficial.'
claude --version >/dev/null 2>&1 || fail 'O comando claude existe, mas claude --version falhou.'
[[ -f "$ROOT/lib/keyproxy_claude_config.py" ]] || fail 'Biblioteca de configuração ausente.'
[[ -f "$ROOT/bin/keyproxy-claude" ]] || fail 'Seletor de modelos ausente.'

mkdir -p "$CONFIG_DIR" "$INSTALL_BIN" "$(dirname "$STATE")"
chmod 700 "$CONFIG_DIR" "$(dirname "$STATE")" 2>/dev/null || true

if [[ -z "$PROFILE" ]]; then
  case "$(basename "${SHELL:-/bin/sh}")" in
    zsh) PROFILE="$HOME/.zshrc" ;;
    bash) PROFILE="$HOME/.bashrc" ;;
    *) PROFILE="$HOME/.profile" ;;
  esac
fi

if [[ -n "${KEYPROXY_API_KEY:-}" ]]; then
  api_key=$KEYPROXY_API_KEY
elif [[ -t 0 ]]; then
  IFS= read -r -s -p 'Cole sua API key do KeyProxy: ' api_key
  printf '\n'
else
  fail 'Defina KEYPROXY_API_KEY em execução não interativa.'
fi
[[ -n "$api_key" ]] || fail 'A API key não pode estar vazia.'

transaction_dir="$(mktemp -d)"
if [[ -f "$SETTINGS" ]]; then
  settings_existed=true
  settings_backup="$transaction_dir/settings"
  cp -p "$SETTINGS" "$settings_backup"
fi
if [[ -f "$CLAUDE_JSON" ]]; then
  claude_existed=true
  claude_backup="$transaction_dir/claude.json"
  cp -p "$CLAUDE_JSON" "$claude_backup"
fi
if [[ -f "$STATE" ]]; then
  state_existed=true
  state_backup="$transaction_dir/state"
  cp -p "$STATE" "$state_backup"
fi
if [[ -e "$HELPER" ]]; then
  helper_existed=true
  helper_backup="$transaction_dir/helper"
  cp -p "$HELPER" "$helper_backup"
fi
if [[ -f "$PROFILE" ]]; then
  profile_existed=true
  profile_backup="$transaction_dir/profile"
  cp -p "$PROFILE" "$profile_backup"
fi
rollback_needed=true
path_added=false
[[ ":$PATH:" != *":$INSTALL_BIN:"* ]] && path_added=true

printf '%s' "$api_key" | python3 "$ROOT/lib/keyproxy_claude_config.py" install \
  --settings "$SETTINGS" --claude-config "$CLAUDE_JSON" \
  --state "$STATE" --token-stdin --path-added "$path_added" >/dev/null
unset api_key KEYPROXY_API_KEY

install -m 700 "$ROOT/bin/keyproxy-claude" "$HELPER"

if [[ ":$PATH:" != *":$INSTALL_BIN:"* ]]; then
  touch "$PROFILE"
  python3 - "$PROFILE" "$MARKER_BEGIN" "$MARKER_END" "$INSTALL_BIN" <<'PY'
import os, sys, tempfile
from pathlib import Path
path=Path(sys.argv[1]); begin=sys.argv[2]; end=sys.argv[3]; bindir=sys.argv[4]
text=path.read_text(encoding='utf-8') if path.exists() else ''
start=text.find(begin); finish=text.find(end)
if start >= 0 and finish >= start:
    finish += len(end)
    text=text[:start].rstrip()+text[finish:].lstrip('\n')
block=f'{begin}\nexport PATH="{bindir}:$PATH"\n{end}\n'
text=text.rstrip()+('\n\n' if text.strip() else '')+block
fd,name=tempfile.mkstemp(prefix=f'.{path.name}.',dir=str(path.parent))
with os.fdopen(fd,'w',encoding='utf-8') as f: f.write(text)
os.replace(name,path)
PY
fi

python3 "$ROOT/lib/keyproxy_claude_config.py" validate \
  --settings "$SETTINGS" --claude-config "$CLAUDE_JSON" --state "$STATE" >/dev/null
"$HELPER" --list >/dev/null
rollback_needed=false
trap - ERR INT TERM
cleanup
transaction_dir=''

printf 'Instalação concluída.\n'
printf 'Abra um novo terminal e execute: keyproxy-claude\n'
printf 'Dentro do Claude Code, também é possível usar: /model gpt-5.5\n'
printf 'Nenhum processo ou sessão existente foi encerrado.\n'
