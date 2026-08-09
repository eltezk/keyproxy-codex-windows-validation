#!/usr/bin/env bash
# Menu principal do KeyProxy Hub para Claude Code no macOS e Linux.

set -Eeuo pipefail
umask 077
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CONFIG_DIR/settings.json"
CLAUDE_JSON="${KEYPROXY_CLAUDE_JSON:-$HOME/.claude.json}"
STATE="$CONFIG_DIR/keyproxy-claude/state.json"
INSTALL_BIN="${KEYPROXY_INSTALL_BIN:-$HOME/.local/bin}"
HELPER="$INSTALL_BIN/keyproxy-claude"

usage() {
  cat <<'EOF'
KeyProxy Hub para Claude Code

Uso: bash keyproxy-claude.sh [comando]

Comandos:
  install  Instala ou atualiza a configuração KeyProxy
  open     Abre o seletor e inicia o Claude Code
  list     Lista os modelos anunciados/autorizados
  status   Mostra configuração e testa a descoberta
  revert   Restaura o estado anterior à primeira instalação ativa
  reset    Volta ao Claude oficial
  help     Exibe esta ajuda
EOF
}

require_configured() {
  [[ -x "$HELPER" ]] || { printf 'Seletor não instalado. Use a opção de instalação primeiro.\n' >&2; return 1; }
}

show_status() {
  command -v python3 >/dev/null 2>&1 || { printf 'Python 3: não encontrado\n'; return 1; }
  printf 'Claude Code: '
  if command -v claude >/dev/null 2>&1 && version="$(claude --version 2>/dev/null)"; then printf '%s\n' "$version"; else printf 'não encontrado ou inválido\n'; fi
  python3 - "$SETTINGS" "$CLAUDE_JSON" "$STATE" "$HELPER" <<'PY'
import json,sys
from pathlib import Path
settings,claude_config,state,helper=map(Path,sys.argv[1:])
try:
    data=json.loads(settings.read_text(encoding='utf-8'))
except (OSError,ValueError):
    print('Configuração: ausente ou inválida')
    raise SystemExit(1)
env=data.get('env') if isinstance(data.get('env'),dict) else {}
endpoint=env.get('ANTHROPIC_BASE_URL')
token=env.get('ANTHROPIC_AUTH_TOKEN')
print('Configuração: ' + ('KeyProxy ativa' if endpoint=='https://api.keyproxyhub.store/v1' and isinstance(token,str) and bool(token) else 'KeyProxy inativa ou divergente'))
print('Endpoint: ' + (endpoint if isinstance(endpoint,str) else 'não configurado'))
print('Modelo principal: ' + str(data.get('model','não configurado')))
print('Aliases: opus={0}; fable={1}; sonnet={2}; haiku={3}'.format(env.get('ANTHROPIC_DEFAULT_OPUS_MODEL','-'),env.get('ANTHROPIC_DEFAULT_FABLE_MODEL','-'),env.get('ANTHROPIC_DEFAULT_SONNET_MODEL','-'),env.get('ANTHROPIC_DEFAULT_HAIKU_MODEL','-')))
models=data.get('availableModels')
print('Allowlist: {0} modelo(s)'.format(len(models) if isinstance(models,list) else 0))
print('Snapshot: ' + ('presente' if state.is_file() else 'ausente'))
try:
    global_data=json.loads(claude_config.read_text(encoding='utf-8'))
except (OSError,ValueError):
    global_data={}
server=(global_data.get('mcpServers') or {}).get('keyproxy') if isinstance(global_data,dict) and isinstance(global_data.get('mcpServers',{}),dict) else None
expected={'type':'http','url':'https://api.keyproxyhub.store/mcp','headers':{'Authorization':'Bearer ${KEYPROXY_API_KEY}'}}
print('MCP KeyProxy: ' + ('configurado' if server==expected else ('ausente' if server is None else 'divergente')))
print('Seletor: ' + ('instalado' if helper.is_file() else 'ausente'))
PY
  if [[ -x "$HELPER" ]]; then
    local output count
    if output="$($HELPER --list 2>/dev/null)"; then
      count="$(printf '%s\n' "$output" | grep -c . || true)"
      printf 'Descoberta executável: %s modelo(s) concreto(s)\n' "$count"
    else
      printf 'Descoberta executável: falhou\n'
      return 1
    fi
  fi
  printf 'Credencial: configurada e ocultada\n'
}

confirm() {
  local prompt=$1 answer
  [[ -t 0 ]] || return 1
  IFS= read -r -p "$prompt [s/N]: " answer
  [[ "$answer" == 's' || "$answer" == 'S' ]]
}

run_command() {
  local command=${1:-help}
  shift || true
  case "$command" in
    install) bash "$ROOT/install.sh" "$@" ;;
    open) require_configured && "$HELPER" "$@" ;;
    list) require_configured && "$HELPER" --list ;;
    status) show_status ;;
    revert) bash "$ROOT/revert.sh" "$@" ;;
    reset) bash "$ROOT/reset-claude-default.sh" "$@" ;;
    help|-h|--help) usage ;;
    *) printf 'Comando inválido: %s\n\n' "$command" >&2; usage >&2; return 2 ;;
  esac
}

menu() {
  while true; do
    cat <<'EOF'

KeyProxy Hub para Claude Code

  1. Instalar ou atualizar KeyProxy
  2. Abrir Claude Code e escolher modelo
  3. Listar modelos disponíveis
  4. Verificar status e conexão
  5. Restaurar configuração anterior
  6. Voltar ao Claude oficial
  7. Sair
EOF
    IFS= read -r -p 'Escolha uma opção: ' option
    case "$option" in
      1) run_command install ;;
      2) run_command open ;;
      3) run_command list ;;
      4) run_command status ;;
      5) if confirm 'Restaurar a configuração anterior à instalação?'; then run_command revert; else printf 'Operação cancelada.\n'; fi ;;
      6) if confirm 'Remover o KeyProxy e voltar ao Claude oficial?'; then run_command reset; else printf 'Operação cancelada.\n'; fi ;;
      7) return 0 ;;
      *) printf 'Opção inválida.\n' >&2 ;;
    esac
  done
}

if [[ $# -gt 0 ]]; then run_command "$@"; else menu; fi
