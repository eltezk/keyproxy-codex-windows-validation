#!/usr/bin/env bash
# Orquestrador seguro do KeyProxy Hub para Claude Code e Codex CLI.

set -Eeuo pipefail
umask 077

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${KEYPROXY_HUB_CLAUDE_DIR:-$ROOT/claude}"
CODEX_DIR="${KEYPROXY_HUB_CODEX_DIR:-$ROOT/codex}"

COLOR=false
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
  COLOR=true
fi
if [[ "$COLOR" == true ]]; then
  C_RESET=$'\033[0m'; C_ACCENT=$'\033[38;5;208m'; C_DIM=$'\033[2m'; C_OK=$'\033[38;5;114m'; C_WARN=$'\033[38;5;220m'; C_ERR=$'\033[38;5;203m'
else
  C_RESET=''; C_ACCENT=''; C_DIM=''; C_OK=''; C_WARN=''; C_ERR=''
fi

usage() {
  cat <<'EOF'
KeyProxy Hub Setup

Uso: bash keyproxy-hub.sh [comando] [opções do módulo]

Comandos:
  install-claude       Configura ou atualiza o KeyProxy no Claude Code
  open-claude          Abre o seletor de modelos do Claude Code
  install-codex        Configura ou atualiza o KeyProxy no Codex CLI
  status               Mostra apenas estado local sanitizado
  validate             Valida a integridade e a sintaxe dos módulos do pacote
  revert-claude --yes  Restaura o snapshot anterior do Claude Code
  reset-claude --yes   Remove somente a configuração KeyProxy do Claude Code
  revert-codex --yes   Restaura somente a configuração Codex registrada pelo KeyProxy
  codex-recovery       Mostra backup e instruções manuais seguras do Codex
  help                 Exibe esta ajuda

As operações de reversão exigem --yes fora do menu. A reversão Codex só usa
um manifesto e backup criados pelo KeyProxy; credenciais e o Codex CLI são preservados.
EOF
}

line() { printf '%s%s%s\n' "$C_DIM" '────────────────────────────────────────────────────────' "$C_RESET"; }
card() { printf '%s%s%s\n' "$C_ACCENT" "$1" "$C_RESET"; }
ok() { printf '%s[ok]%s %s\n' "$C_OK" "$C_RESET" "$1"; }
warn() { printf '%s[aviso]%s %s\n' "$C_WARN" "$C_RESET" "$1" >&2; }
die() { printf '%s[erro]%s %s\n' "$C_ERR" "$C_RESET" "$1" >&2; exit 1; }

banner() {
  printf '\n'
  printf '%s  ██╗  ██╗██████╗ %s\n' "$C_ACCENT" "$C_RESET"
  printf '%s  ██║ ██╔╝██╔══██╗%s\n' "$C_ACCENT" "$C_RESET"
  printf '%s  █████╔╝ ██████╔╝%s\n' "$C_ACCENT" "$C_RESET"
  printf '%s  ██╔═██╗ ██╔═══╝ %s\n' "$C_ACCENT" "$C_RESET"
  printf '%s  ██║  ██╗██║     %s\n' "$C_ACCENT" "$C_RESET"
  printf '%s  KeyProxy Hub Setup · Claude Code + Codex CLI%s\n' "$C_DIM" "$C_RESET"
  line
}

require_module() {
  local file="$1"
  [[ -f "$file" ]] || die "Módulo obrigatório ausente: $file"
}

run_claude() {
  local action="$1"; shift
  require_module "$CLAUDE_DIR/keyproxy-claude.sh"
  case "$action" in
    install|open|list|status|revert|reset) bash "$CLAUDE_DIR/keyproxy-claude.sh" "$action" "$@" ;;
    *) die "Ação Claude inválida: $action" ;;
  esac
}

run_codex_install() {
  require_module "$CODEX_DIR/keyproxy-codex-install.sh"
  bash "$CODEX_DIR/keyproxy-codex-install.sh" "$@"
}

codex_home() { printf '%s\n' "${CODEX_HOME:-$HOME/.codex}"; }

is_keyproxy_codex_config() {
  local config="$1"
  [[ -f "$config" ]] \
    && grep -Eq '^model[[:space:]]*=[[:space:]]*"gpt-5\.6-sol"[[:space:]]*$' "$config" \
    && grep -Eq '^model_provider[[:space:]]*=[[:space:]]*"keyproxy"[[:space:]]*$' "$config" \
    && grep -Fqx '[model_providers.keyproxy]' "$config" \
    && grep -Fqx '[mcp_servers.keyproxy]' "$config"
}

is_keyproxy_codex_backup() {
  local config="$1" backup="$2"
  [[ "$backup" == "$config".*.bak && -f "$backup" && ! -L "$backup" ]]
}

read_codex_recovery_state() {
  local state="$1" config="$2"
  RECOVERY_VERSION="$(grep -E '^version=' "$state" | cut -d= -f2-)"
  RECOVERY_CREATED_BY="$(grep -E '^created_by=' "$state" | cut -d= -f2-)"
  RECOVERY_PATH="$(grep -E '^config_path=' "$state" | cut -d= -f2-)"
  RECOVERY_EXISTED="$(grep -E '^config_existed=' "$state" | cut -d= -f2-)"
  RECOVERY_BACKUP="$(grep -E '^config_backup=' "$state" | cut -d= -f2-)"
  [[ "$RECOVERY_VERSION" == 1 && "$RECOVERY_CREATED_BY" == keyproxy-codex-install \
    && "$RECOVERY_PATH" == "$config" && ( "$RECOVERY_EXISTED" == true || "$RECOVERY_EXISTED" == false ) ]]
}

show_codex_status() {
  local home config backup_count=0
  home="$(codex_home)"; config="$home/config.toml"
  printf 'Codex CLI: '
  if command -v codex >/dev/null 2>&1 && codex --version 2>/dev/null; then :; else printf 'não encontrado ou inválido\n'; fi
  printf 'Configuração Codex: %s\n' "$config"
  if [[ -L "$home" || -L "$config" ]]; then
    warn 'O caminho de configuração Codex contém link simbólico; nenhum arquivo será seguido pelo status.'
    return 1
  fi
  if [[ ! -f "$config" ]]; then
    printf 'KeyProxy Codex: não configurado\n'
  elif grep -Eq '^model[[:space:]]*=[[:space:]]*"gpt-5\.6-sol"[[:space:]]*$' "$config" \
    && grep -Eq '^model_provider[[:space:]]*=[[:space:]]*"keyproxy"[[:space:]]*$' "$config" \
    && grep -Fq '[mcp_servers.keyproxy]' "$config"; then
    printf 'KeyProxy Codex: configuração local ativa\n'
  else
    printf 'KeyProxy Codex: inativo ou divergente\n'
  fi
  if [[ -f "$home/keyproxy-codex-state" && ! -L "$home/keyproxy-codex-state" ]]; then
    backup_count=1
  fi
  printf 'Recuperação Codex: %s\n' "$(if ((backup_count == 1)); then printf 'manifesto KeyProxy presente'; else printf 'não disponível'; fi)"
  printf 'Credencial Codex: %s\n' "$(if [[ -f "$HOME/.config/keyproxy/env" ]]; then printf 'arquivo local presente e ocultado'; else printf 'não detectada'; fi)"
}

show_status() {
  banner
  card 'Claude Code'
  run_claude status || warn 'O status Claude retornou falha.'
  printf '\n'
  card 'Codex CLI'
  show_codex_status || true
}

validate_modules() {
  local failure=0
  banner
  card 'Validação local do pacote (sem alterar configurações)'
  for file in \
    "$ROOT/keyproxy-hub.sh" \
    "$CLAUDE_DIR/keyproxy-claude.sh" "$CLAUDE_DIR/install.sh" "$CLAUDE_DIR/revert.sh" "$CLAUDE_DIR/reset-claude-default.sh" \
    "$CODEX_DIR/keyproxy-codex-install.sh"; do
    if bash -n "$file"; then ok "Sintaxe Bash: ${file#$ROOT/}"; else failure=1; fi
  done
  if command -v python3 >/dev/null 2>&1 && python3 -m py_compile "$CLAUDE_DIR/lib/keyproxy_claude_config.py" "$CLAUDE_DIR/bin/keyproxy-claude"; then
    ok 'Sintaxe Python do módulo Claude'
  else
    warn 'Falha na validação Python do módulo Claude'; failure=1
  fi
  if command -v shasum >/dev/null 2>&1 && [[ -f "$ROOT/SHA256SUMS" ]]; then
    if (cd "$ROOT" && shasum -a 256 -c SHA256SUMS >/dev/null); then ok 'Checksums do pacote'; else warn 'Checksums divergentes'; failure=1; fi
  else
    warn 'SHA256SUMS ausente ou shasum indisponível'; failure=1
  fi
  ((failure == 0)) || return 1
  ok 'Validação local concluída'
}

validate_codex_shell_integration() {
  local profile marker_status
  for profile in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    [[ -e "$profile" ]] || continue
    [[ ! -L "$profile" && -f "$profile" ]] || die \
      "O perfil $profile não é um arquivo regular seguro; nenhum arquivo foi alterado."
    marker_status="$(awk '
      $0 == "# >>> KeyProxy Hub para Codex CLI >>>" { begin_count++; opened = 1 }
      $0 == "# <<< KeyProxy Hub para Codex CLI <<<" { end_count++; if (!opened) invalid = 1; opened = 0 }
      END { if (opened || invalid || begin_count != end_count || begin_count > 1) print "invalid" }
    ' "$profile")"
    [[ "$marker_status" != invalid ]] || die \
      "O perfil $profile contém marcadores KeyProxy incompletos ou duplicados; nenhum arquivo foi alterado."
  done
}

remove_codex_shell_integration() {
  local profile staged
  for profile in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    [[ -f "$profile" && ! -L "$profile" ]] || continue
    grep -Fqx '# >>> KeyProxy Hub para Codex CLI >>>' "$profile" || continue
    staged="$profile.keyproxy-remove.$$"
    awk '
      $0 == "# >>> KeyProxy Hub para Codex CLI >>>" { skipping = 1; next }
      $0 == "# <<< KeyProxy Hub para Codex CLI <<<" { skipping = 0; next }
      !skipping { print }
    ' "$profile" > "$staged"
    chmod 600 "$staged"
    mv "$staged" "$profile"
  done
}

revert_codex() {
  local home config state backup staged env_file
  home="$(codex_home)"; config="$home/config.toml"; state="$home/keyproxy-codex-state"
  [[ ! -L "$home" && ! -L "$config" && ! -L "$state" && -f "$state" ]] || die \
    'Não há manifesto KeyProxy seguro para este CODEX_HOME; nenhum arquivo foi alterado.'
  read_codex_recovery_state "$state" "$config" || die \
    'O manifesto KeyProxy é inválido para este CODEX_HOME; nenhum arquivo será alterado.'
  is_keyproxy_codex_config "$config" || die \
    'A configuração ativa do Codex não pertence ao KeyProxy; nenhum arquivo será sobrescrito.'
  validate_codex_shell_integration

  if [[ "$RECOVERY_EXISTED" == true ]]; then
    is_keyproxy_codex_backup "$config" "$RECOVERY_BACKUP" || die \
      'O backup registrado pelo KeyProxy não está disponível ou não é seguro; nenhum arquivo será sobrescrito.'
    backup="$RECOVERY_BACKUP"
    staged="$home/.config.toml.restore-keyproxy.$$"
    cp -p "$backup" "$staged"
    chmod 600 "$staged"
    mv "$staged" "$config"
    printf '[ok] Configuração Codex restaurada a partir do backup registrado pelo KeyProxy.
'
  else
    [[ -z "$RECOVERY_BACKUP" ]] || die 'O manifesto de recuperação contém backup inesperado; nenhum arquivo será alterado.'
    rm -f "$config"
    printf '[ok] Configuração Codex criada pelo KeyProxy foi removida.
'
  fi

  remove_codex_shell_integration
  rm -f "$state"
  env_file="$HOME/.config/keyproxy/env"
  printf 'A integração KeyProxy do shell foi removida. O Codex CLI e a credencial foram preservados.
'
  printf 'Para remover a credencial manualmente, exclua: %s
' "$env_file"
}

show_codex_recovery() {
  local home config state recorded_path recorded_existed backup
  home="$(codex_home)"; config="$home/config.toml"; state="$home/keyproxy-codex-state"
  banner
  card 'Recuperação manual segura do Codex CLI'
  printf 'Configuração ativa esperada: %s\n' "$config"
  if [[ -L "$home" || -L "$state" || ! -f "$state" ]]; then
    warn 'Não há manifesto KeyProxy seguro para este CODEX_HOME; nenhum arquivo será alterado.'
    return 0
  fi
  if ! read_codex_recovery_state "$state" "$config"; then
    warn 'O manifesto KeyProxy é inválido para este CODEX_HOME; nenhum arquivo será alterado.'
    return 0
  fi
  if [[ "$RECOVERY_EXISTED" == false ]]; then
    printf 'O KeyProxy criou o config.toml originalmente; não há backup anterior a restaurar.\n'
  elif is_keyproxy_codex_backup "$config" "$RECOVERY_BACKUP"; then
    printf 'Backup KeyProxy registrado: %s\n' "$RECOVERY_BACKUP"
    printf '\nAntes de restaurar manualmente: confira o backup e mantenha uma cópia do config.toml atual.\n'
    printf 'Comando revisável: cp -- "%s" "%s"\n' "$RECOVERY_BACKUP" "$config"
  else
    warn 'O backup registrado pelo KeyProxy não está disponível ou não é seguro; nenhum arquivo será alterado.'
    return 0
  fi
  printf 'Depois, se não precisar mais da credencial KeyProxy, remova manualmente: %s\n' "$HOME/.config/keyproxy/env"
  printf 'Nenhum arquivo foi alterado por esta opção.\n'
}

confirm() {
  local prompt="$1" answer
  [[ -t 0 ]] || return 1
  IFS= read -r -p "$prompt [s/N]: " answer
  [[ "$answer" == s || "$answer" == S ]]
}

menu() {
  local option
  while true; do
    banner
    cat <<'EOF'
  1. Configurar ou atualizar KeyProxy no Claude Code
  2. Abrir seletor de modelos do Claude Code
  3. Configurar ou atualizar KeyProxy no Codex CLI
  4. Mostrar status sanitizado
  5. Validar módulos do pacote
  6. Restaurar configuração anterior do Claude Code
  7. Voltar Claude Code ao provider oficial
  8. Restaurar ou remover com segurança a configuração KeyProxy do Codex CLI
  9. Mostrar informações de recuperação do Codex CLI
 10. Sair
EOF
    IFS= read -r -p 'Escolha uma opção: ' option
    case "$option" in
      1) run_claude install ;;
      2) run_claude open ;;
      3) run_codex_install ;;
      4) show_status ;;
      5) validate_modules ;;
      6) if confirm 'Restaurar o snapshot anterior do Claude Code?'; then run_claude revert; else warn 'Operação cancelada.'; fi ;;
      7) if confirm 'Remover KeyProxy do Claude Code e voltar ao provider oficial?'; then run_claude reset; else warn 'Operação cancelada.'; fi ;;
      8) if confirm 'Restaurar ou remover somente a configuração KeyProxy do Codex CLI?'; then revert_codex; else warn 'Operação cancelada.'; fi ;;
      9) show_codex_recovery ;;
      10) return 0 ;;
      *) warn 'Opção inválida.' ;;
    esac
    printf '\n'; [[ -t 0 ]] && read -r -p 'Pressione Enter para voltar ao menu...' || true
  done
}

dispatch() {
  local command="${1:-}"; shift || true
  case "$command" in
    '') menu ;;
    install-claude) run_claude install "$@" ;;
    open-claude) run_claude open "$@" ;;
    install-codex) run_codex_install "$@" ;;
    status) show_status ;;
    validate) validate_modules ;;
    codex-recovery) show_codex_recovery ;;
    revert-claude)
      [[ "${1:-}" == '--yes' ]] || die 'revert-claude exige --yes fora do menu.'
      shift; run_claude revert "$@" ;;
    reset-claude)
      [[ "${1:-}" == '--yes' ]] || die 'reset-claude exige --yes fora do menu.'
      shift; run_claude reset "$@" ;;
    revert-codex)
      [[ "${1:-}" == '--yes' ]] || die 'revert-codex exige --yes fora do menu.'
      shift; revert_codex ;;
    help|-h|--help) usage ;;
    *) die "Comando inválido: $command. Use help." ;;
  esac
}

dispatch "$@"
