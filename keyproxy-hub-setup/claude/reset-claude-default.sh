#!/usr/bin/env bash
# Remove somente a configuração KeyProxy e retorna ao provider oficial do Claude.

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
PATH_ADDED=false
if [[ -f "$STATE" ]]; then
  PATH_ADDED="$(python3 - "$STATE" <<'PY'
import json,sys
try:
 data=json.load(open(sys.argv[1],encoding='utf-8'))
 print('true' if data.get('pathAdded') is True else 'false')
except Exception:
 print('false')
PY
)"
fi
DRY=false
[[ "${1:-}" == '--dry-run' ]] && DRY=true
command -v python3 >/dev/null 2>&1 || { printf 'Python 3 é obrigatório.\n' >&2; exit 1; }
if [[ -z "$PROFILE" ]]; then
  case "$(basename "${SHELL:-/bin/sh}")" in zsh) PROFILE="$HOME/.zshrc";; bash) PROFILE="$HOME/.bashrc";; *) PROFILE="$HOME/.profile";; esac
fi
if $DRY; then
  python3 "$ROOT/lib/keyproxy_claude_config.py" reset \
    --settings "$SETTINGS" --claude-config "$CLAUDE_JSON" --state "$STATE" --dry-run
  printf 'Configuração oficial restaurada (simulação). O próximo uso pode solicitar login.\n'
  printf 'Nenhum processo ou sessão foi encerrado.\n'
  exit 0
fi

TMP="$(mktemp -d)"
settings_existed=false; claude_existed=false; state_existed=false; helper_existed=false; profile_existed=false
[[ -f "$SETTINGS" ]] && { settings_existed=true; cp -p "$SETTINGS" "$TMP/settings"; }
[[ -f "$CLAUDE_JSON" ]] && { claude_existed=true; cp -p "$CLAUDE_JSON" "$TMP/claude.json"; }
[[ -f "$STATE" ]] && { state_existed=true; cp -p "$STATE" "$TMP/state"; }
[[ -e "$HELPER" ]] && { helper_existed=true; cp -p "$HELPER" "$TMP/helper"; }
[[ -f "$PROFILE" ]] && { profile_existed=true; cp -p "$PROFILE" "$TMP/profile"; }
rollback_needed=true
rollback() {
  local status=$?
  if [[ "$rollback_needed" == true ]]; then
    if [[ "$settings_existed" == true ]]; then cp -p "$TMP/settings" "$SETTINGS"; else rm -f "$SETTINGS"; fi
    if [[ "$claude_existed" == true ]]; then cp -p "$TMP/claude.json" "$CLAUDE_JSON"; else rm -f "$CLAUDE_JSON"; fi
    if [[ "$state_existed" == true ]]; then mkdir -p "$(dirname "$STATE")"; cp -p "$TMP/state" "$STATE"; else rm -f "$STATE"; fi
    if [[ "$helper_existed" == true ]]; then mkdir -p "$INSTALL_BIN"; cp -p "$TMP/helper" "$HELPER"; else rm -f "$HELPER"; fi
    if [[ "$profile_existed" == true ]]; then cp -p "$TMP/profile" "$PROFILE"; else rm -f "$PROFILE"; fi
  fi
  rm -rf "$TMP"
  exit "$status"
}
trap rollback ERR INT TERM

python3 "$ROOT/lib/keyproxy_claude_config.py" reset \
  --settings "$SETTINGS" --claude-config "$CLAUDE_JSON" --state "$STATE"
rm -f "$HELPER" "$STATE"
if [[ "$PATH_ADDED" == true && -f "$PROFILE" ]]; then
  python3 - "$PROFILE" <<'PY'
import os,sys,tempfile
from pathlib import Path
p=Path(sys.argv[1]); text=p.read_text(encoding='utf-8')
b='# >>> keyproxy-claude-code >>>'; e='# <<< keyproxy-claude-code <<<'
s=text.find(b); f=text.find(e)
if s>=0 and f>=s:
 f+=len(e); text=(text[:s].rstrip()+"\n"+text[f:].lstrip("\n"))
 fd,n=tempfile.mkstemp(prefix=f'.{p.name}.',dir=str(p.parent))
 with os.fdopen(fd,'w',encoding='utf-8') as h:h.write(text)
 os.replace(n,p)
PY
fi
rollback_needed=false
trap - ERR INT TERM
rm -rf "$TMP"
printf 'Configuração oficial restaurada. O próximo uso pode solicitar login.\n'
printf 'Nenhum processo ou sessão foi encerrado.\n'
