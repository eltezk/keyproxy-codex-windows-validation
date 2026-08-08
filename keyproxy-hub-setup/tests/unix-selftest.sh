#!/usr/bin/env bash
# Testa somente o roteamento do launcher unificado em diretório temporário.

set -Eeuo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAKE_CLAUDE="$TMP/claude"
FAKE_CODEX="$TMP/codex"
mkdir -p "$FAKE_CLAUDE" "$FAKE_CODEX" "$TMP/home/.codex"

cat > "$FAKE_CLAUDE/keyproxy-claude.sh" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'claude-action=%s\n' "${1:-}"
case "${1:-}" in
  status) printf '%s\n' 'Configuração: KeyProxy ativa' 'Credencial: configurada e ocultada' ;;
  revert|reset|install|open) : ;;
  *) exit 23 ;;
esac
SH
chmod 700 "$FAKE_CLAUDE/keyproxy-claude.sh"

cat > "$FAKE_CODEX/keyproxy-codex-install.sh" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'codex-action=install args=%s\n' "$*"
SH
chmod 700 "$FAKE_CODEX/keyproxy-codex-install.sh"

export HOME="$TMP/home"
export CODEX_HOME="$HOME/.codex"
export KEYPROXY_HUB_CLAUDE_DIR="$FAKE_CLAUDE"
export KEYPROXY_HUB_CODEX_DIR="$FAKE_CODEX"

install_output="$(NO_COLOR=1 bash "$ROOT/keyproxy-hub.sh" install-claude)"
grep -Fqx 'claude-action=install' <<<"$install_output"

codex_output="$(NO_COLOR=1 bash "$ROOT/keyproxy-hub.sh" install-codex --skip-api-test)"
grep -Fqx 'codex-action=install args=--skip-api-test' <<<"$codex_output"

status_output="$(NO_COLOR=1 bash "$ROOT/keyproxy-hub.sh" status 2>&1)"
grep -Fq 'Claude Code' <<<"$status_output"
grep -Fq 'claude-action=status' <<<"$status_output"
grep -Fq 'Codex CLI' <<<"$status_output"
grep -Fq 'KeyProxy Codex: não configurado' <<<"$status_output"
! printf '%s' "$status_output" | LC_ALL=C grep -q "$(printf '\033')\["

if NO_COLOR=1 bash "$ROOT/keyproxy-hub.sh" revert-claude >/dev/null 2>&1; then
  printf 'FALHA: revert sem --yes foi aceito\n' >&2
  exit 1
fi
revert_output="$(NO_COLOR=1 bash "$ROOT/keyproxy-hub.sh" revert-claude --yes)"
grep -Fqx 'claude-action=revert' <<<"$revert_output"

if NO_COLOR=1 bash "$ROOT/keyproxy-hub.sh" reset-claude >/dev/null 2>&1; then
  printf 'FALHA: reset sem --yes foi aceito\n' >&2
  exit 1
fi
reset_output="$(NO_COLOR=1 bash "$ROOT/keyproxy-hub.sh" reset-claude --yes)"
grep -Fqx 'claude-action=reset' <<<"$reset_output"

recovery_output="$(NO_COLOR=1 bash "$ROOT/keyproxy-hub.sh" codex-recovery 2>&1)"
grep -Fq 'Nenhum backup comprovável foi encontrado' <<<"$recovery_output"

printf 'hub-unix-selftest=ok\n'
