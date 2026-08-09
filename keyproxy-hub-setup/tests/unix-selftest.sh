#!/usr/bin/env bash
# Testa o roteamento e as reversões seguras do launcher unificado em diretório temporário.

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
mkdir -p "$HOME/.config/keyproxy"
printf 'export KEYPROXY_API_KEY=%q\n' 'kp_test_not_real' > "$HOME/.config/keyproxy/env"
cp "$HOME/.config/keyproxy/env" "$TMP/env-before"

write_keyproxy_config() {
  cat > "$CODEX_HOME/config.toml" <<'TOML'
model = "gpt-5.6-sol"
model_provider = "keyproxy"

[model_providers.keyproxy]
name = "KeyProxy Hub"

[mcp_servers.keyproxy]
enabled = true
TOML
}

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
grep -Fq 'Não há manifesto KeyProxy seguro' <<<"$recovery_output"

# A reversão exige confirmação e restaura apenas o backup apontado pelo manifesto.
printf 'model = "original"\n' > "$CODEX_HOME/config.toml.before-keyproxy.bak"
write_keyproxy_config
cat > "$CODEX_HOME/keyproxy-codex-state" <<EOF
version=1
config_path=$CODEX_HOME/config.toml
config_existed=true
config_backup=$CODEX_HOME/config.toml.before-keyproxy.bak
created_by=keyproxy-codex-install
EOF
cat > "$HOME/.zshrc" <<'PROFILE'
export KEEP_ME=1
# >>> KeyProxy Hub para Codex CLI >>>
[[ -f "$HOME/.config/keyproxy/env" ]] && source "$HOME/.config/keyproxy/env"
# <<< KeyProxy Hub para Codex CLI <<<
PROFILE
if NO_COLOR=1 bash "$ROOT/keyproxy-hub.sh" revert-codex >/dev/null 2>&1; then
  printf 'FALHA: reversão Codex sem --yes foi aceita\n' >&2
  exit 1
fi
revert_codex_output="$(NO_COLOR=1 bash "$ROOT/keyproxy-hub.sh" revert-codex --yes)"
grep -Fq 'Configuração Codex restaurada' <<<"$revert_codex_output"
cmp -s "$CODEX_HOME/config.toml" "$CODEX_HOME/config.toml.before-keyproxy.bak"
[[ ! -e "$CODEX_HOME/keyproxy-codex-state" ]]
[[ "$(cat "$HOME/.zshrc")" == 'export KEEP_ME=1' ]]
cmp -s "$HOME/.config/keyproxy/env" "$TMP/env-before"

# Quando o KeyProxy criou o config.toml, somente esse arquivo e o manifesto são removidos.
write_keyproxy_config
cat > "$CODEX_HOME/keyproxy-codex-state" <<EOF
version=1
config_path=$CODEX_HOME/config.toml
config_existed=false
config_backup=
created_by=keyproxy-codex-install
EOF
NO_COLOR=1 bash "$ROOT/keyproxy-hub.sh" revert-codex --yes >/dev/null
[[ ! -e "$CODEX_HOME/config.toml" ]]
[[ ! -e "$CODEX_HOME/keyproxy-codex-state" ]]
cmp -s "$HOME/.config/keyproxy/env" "$TMP/env-before"

# Uma configuração posterior do usuário nunca é sobrescrita.
printf 'model = "user-choice"\n' > "$CODEX_HOME/config.toml"
cat > "$CODEX_HOME/keyproxy-codex-state" <<EOF
version=1
config_path=$CODEX_HOME/config.toml
config_existed=false
config_backup=
created_by=keyproxy-codex-install
EOF
if NO_COLOR=1 bash "$ROOT/keyproxy-hub.sh" revert-codex --yes >"$TMP/divergent.log" 2>&1; then
  printf 'FALHA: reversão Codex sobrescreveu configuração divergente\n' >&2
  exit 1
fi
grep -Fq 'não pertence ao KeyProxy' "$TMP/divergent.log"
grep -Fq 'user-choice' "$CODEX_HOME/config.toml"
[[ -f "$CODEX_HOME/keyproxy-codex-state" ]]

# Um manifesto que aponta para backup fora do padrão criado pelo instalador é recusado.
write_keyproxy_config
printf 'model = "third-party"\n' > "$TMP/backup-terceiro.bak"
cat > "$CODEX_HOME/keyproxy-codex-state" <<EOF
version=1
config_path=$CODEX_HOME/config.toml
config_existed=true
config_backup=$TMP/backup-terceiro.bak
created_by=keyproxy-codex-install
EOF
if NO_COLOR=1 bash "$ROOT/keyproxy-hub.sh" revert-codex --yes >"$TMP/external-backup.log" 2>&1; then
  printf 'FALHA: reversão Codex aceitou backup externo\n' >&2
  exit 1
fi
grep -Fq 'não está disponível ou não é seguro' "$TMP/external-backup.log"
grep -Fq 'gpt-5.6-sol' "$CODEX_HOME/config.toml"
[[ -f "$CODEX_HOME/keyproxy-codex-state" ]]

# Um manifesto sem a origem esperada não pode restaurar ou remover arquivos.
write_keyproxy_config
cat > "$CODEX_HOME/keyproxy-codex-state" <<EOF
version=1
config_path=$CODEX_HOME/config.toml
config_existed=false
config_backup=
created_by=terceiro
EOF
if NO_COLOR=1 bash "$ROOT/keyproxy-hub.sh" revert-codex --yes >"$TMP/forged-state.log" 2>&1; then
  printf 'FALHA: reversão Codex aceitou manifesto forjado\n' >&2
  exit 1
fi
grep -Fq 'manifesto KeyProxy é inválido' "$TMP/forged-state.log"
grep -Fq 'gpt-5.6-sol' "$CODEX_HOME/config.toml"
[[ -f "$CODEX_HOME/keyproxy-codex-state" ]]

printf 'hub-unix-selftest=ok\n'
