#!/usr/bin/env bash
# Self-test isolado do bootstrap Codex + KeyProxy para macOS e Linux.

set -Eeuo pipefail

INSTALLER="${1:-}"
[[ -n "$INSTALLER" && -f "$INSTALLER" ]] || {
  printf 'Uso: %s /caminho/keyproxy-codex-install.sh\n' "$0" >&2
  exit 1
}
INSTALLER="$(cd -P "$(dirname "$INSTALLER")" && pwd)/$(basename "$INSTALLER")"

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/keyproxy-unix-selftest.XXXXXX")"
cleanup() { rm -rf "$ROOT"; }
trap cleanup EXIT

assert_file_contains() {
  local file="$1" text="$2" message="$3"
  grep -Fq -- "$text" "$file" || {
    printf 'FALHA: %s\n' "$message" >&2
    exit 1
  }
}

write_valid_codex() {
  local destination="$1"
  cat > "$destination" <<'CODEX'
#!/bin/sh
printf '%s\n' "$*" >> "${TEST_CODEX_LOG:?}"
case "$1" in
  --version|--strict-config) printf '%s\n' 'codex-cli unix-selftest' ;;
  doctor) printf '%s\n' '{"checks":{"config.load":{"details":{"model":"gpt-5.6-sol","model provider":"keyproxy"}}}}' ;;
  mcp) printf '%s\n' 'keyproxy' ;;
  logout) printf '%s\n' 'logout' >> "${TEST_EVENT_LOG:?}" ;;
  exec) printf '%s\n' 'model: gpt-5.6-sol' 'provider: keyproxy' 'KEYPROXY_OK' ;;
  *) exit 90 ;;
esac
CODEX
  chmod 755 "$destination"
}

write_fake_downloader() {
  local destination="$1"
  cat > "$destination" <<'DOWNLOADER'
#!/bin/sh
output=''
printf '%s\n' "$*" >> "${TEST_DOWNLOAD_LOG:?}"
while [ "$#" -gt 0 ]; do
  if [ "$1" = '--output' ] || [ "$1" = '--output-document' ]; then
    shift
    output=$1
  fi
  shift
done
[ -n "$output" ] || exit 91
cat > "$output" <<'OFFICIAL'
#!/bin/sh
[ "${CODEX_NON_INTERACTIVE:-}" = '1' ] || exit 92
printf '%s\n' 'noninteractive=ok' >> "${TEST_INSTALL_LOG:?}"
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/codex" <<'CODEX'
#!/bin/sh
printf '%s\n' "$*" >> "${TEST_CODEX_LOG:?}"
case "$1" in
  --version|--strict-config) printf '%s\n' 'codex-cli unix-selftest' ;;
  doctor) printf '%s\n' '{"checks":{"config.load":{"details":{"model":"gpt-5.6-sol","model provider":"keyproxy"}}}}' ;;
  mcp) printf '%s\n' 'keyproxy' ;;
  logout) printf '%s\n' 'logout' >> "${TEST_EVENT_LOG:?}" ;;
  exec) printf '%s\n' 'model: gpt-5.6-sol' 'provider: keyproxy' 'KEYPROXY_OK' ;;
  *) exit 90 ;;
esac
CODEX
chmod 755 "$HOME/.local/bin/codex"
OFFICIAL
chmod 700 "$output"
DOWNLOADER
  chmod 755 "$destination"
}

new_case() {
  local name="$1"
  CASE_ROOT="$ROOT/$name"
  CASE_HOME="$CASE_ROOT/home com espaço á"
  CASE_BIN="$CASE_ROOT/bin"
  mkdir -p "$CASE_HOME" "$CASE_BIN"
  printf '# perfil existente\n' > "$CASE_HOME/.bashrc"
  printf '# perfil existente\n' > "$CASE_HOME/.zshrc"
  : > "$CASE_ROOT/codex.log"
  : > "$CASE_ROOT/events.log"
  : > "$CASE_ROOT/download.log"
  : > "$CASE_ROOT/install.log"
}

run_case() {
  local shell_path="$1"
  printf '%s\n' "kp_selftest_' espaço_á" | env -i \
    HOME="$CASE_HOME" \
    SHELL="$shell_path" \
    PATH="$CASE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    TEST_CODEX_LOG="$CASE_ROOT/codex.log" \
    TEST_EVENT_LOG="$CASE_ROOT/events.log" \
    TEST_DOWNLOAD_LOG="$CASE_ROOT/download.log" \
    TEST_INSTALL_LOG="$CASE_ROOT/install.log" \
    /bin/bash "$INSTALLER" --skip-api-test \
    > "$CASE_ROOT/stdout.log" 2> "$CASE_ROOT/stderr.log"
}

SHELL_PATH="${TEST_LOGIN_SHELL:-/bin/bash}"

# Codex ausente: instala, valida e somente depois aplica KeyProxy.
new_case missing
write_fake_downloader "$CASE_BIN/curl"
run_case "$SHELL_PATH"
assert_file_contains "$CASE_ROOT/install.log" 'noninteractive=ok' 'bootstrap não foi não interativo'
assert_file_contains "$CASE_ROOT/codex.log" '--version' 'codex --version não foi executado após o bootstrap'
assert_file_contains "$CASE_HOME/.codex/config.toml" 'model = "gpt-5.6-sol"' 'modelo KeyProxy ausente'
assert_file_contains "$CASE_HOME/.codex/config.toml" 'model_provider = "keyproxy"' 'provider KeyProxy ausente'
assert_file_contains "$CASE_HOME/.codex/config.toml" '[mcp_servers.keyproxy]' 'MCP KeyProxy ausente'
if grep -R -Fq "kp_selftest_' espaço_á" "$CASE_HOME/.codex"; then
  printf 'FALHA: segredo apareceu no CODEX_HOME\n' >&2
  exit 1
fi
printf 'unix-codex-bootstrap=ok\n'

# Codex válido: não baixa nem reinstala.
new_case existing
write_valid_codex "$CASE_BIN/codex"
cat > "$CASE_BIN/curl" <<'FAILCURL'
#!/bin/sh
printf '%s\n' called >> "${TEST_DOWNLOAD_LOG:?}"
exit 99
FAILCURL
chmod 755 "$CASE_BIN/curl"
run_case "$SHELL_PATH"
[[ ! -s "$CASE_ROOT/download.log" ]] || {
  printf 'FALHA: Codex válido foi reinstalado\n' >&2
  exit 1
}
assert_file_contains "$CASE_ROOT/stdout.log" 'Codex CLI já está instalado e funcional.' 'Codex válido não foi reconhecido'
printf 'unix-existing-codex=ok\n'

# Comando Codex inválido: executa bootstrap de reparo e prossegue.
new_case repair
cat > "$CASE_BIN/codex" <<'BROKEN'
#!/bin/sh
exit 44
BROKEN
chmod 755 "$CASE_BIN/codex"
write_fake_downloader "$CASE_BIN/curl"
run_case "$SHELL_PATH"
assert_file_contains "$CASE_ROOT/stderr.log" 'codex --version falhou' 'Codex inválido não foi detectado'
assert_file_contains "$CASE_ROOT/install.log" 'noninteractive=ok' 'reparo do Codex não executou o bootstrap'
assert_file_contains "$CASE_ROOT/stdout.log" 'Codex detectado: codex-cli unix-selftest' 'Codex reparado não foi validado'
printf 'unix-invalid-codex-repair=ok\n'

printf 'unix-selftest=ok\n'
printf 'system=%s shell=%s\n' "$(uname -s)" "$SHELL_PATH"
