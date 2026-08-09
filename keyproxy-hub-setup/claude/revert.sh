#!/usr/bin/env bash
# Restaura os valores anteriores salvos pelo instalador KeyProxy.

set -Eeuo pipefail
umask 077
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CONFIG_DIR/settings.json"
CLAUDE_JSON="${KEYPROXY_CLAUDE_JSON:-$HOME/.claude.json}"
STATE="$CONFIG_DIR/keyproxy-claude/state.json"
DRY=false
[[ "${1:-}" == '--dry-run' ]] && DRY=true
command -v python3 >/dev/null 2>&1 || { printf 'Python 3 é obrigatório.\n' >&2; exit 1; }
[[ -f "$STATE" ]] || { printf 'Estado anterior não encontrado: %s\n' "$STATE" >&2; exit 1; }
if $DRY; then
  python3 "$ROOT/lib/keyproxy_claude_config.py" revert \
    --settings "$SETTINGS" --claude-config "$CLAUDE_JSON" --state "$STATE" --dry-run
else
  python3 "$ROOT/lib/keyproxy_claude_config.py" revert \
    --settings "$SETTINGS" --claude-config "$CLAUDE_JSON" --state "$STATE"
fi
printf 'Nenhum processo ou sessão foi encerrado. Abra uma nova sessão para aplicar.\n'
