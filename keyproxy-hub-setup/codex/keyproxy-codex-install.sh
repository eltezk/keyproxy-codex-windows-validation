#!/usr/bin/env bash
# Instalador do KeyProxy Hub para o Codex CLI em macOS e Linux.
# Não contém nem transmite uma API key embutida.

set -Eeuo pipefail

readonly KEYPROXY_BASE_URL="https://api.keyproxyhub.store/v1"
readonly KEYPROXY_MCP_URL="https://api.keyproxyhub.store/mcp"
readonly KEYPROXY_MODEL="gpt-5.6-sol"
readonly CODEX_INSTALLER_URL="https://chatgpt.com/codex/install.sh"
readonly PROFILE_BEGIN="# >>> KeyProxy Hub para Codex CLI >>>"
readonly PROFILE_END="# <<< KeyProxy Hub para Codex CLI <<<"

SKIP_API_TEST=false
SKIP_CODEX_INSTALL=false
API_KEY_STDIN=false
TMP_ROOT=""
BACKUP_FILE=""
PROFILE_BACKUP=""
ENV_BACKUP=""
STATE_FILE=""
STATE_CREATED=false
API_TEST_PID=""
ROLLBACK_ARMED=false
CONFIG_EXISTED=false
CONFIG_INSTALLED=false
PROFILE_EXISTED=false
PROFILE_CHANGED=false
ENV_EXISTED=false
ENV_CHANGED=false

info() { printf '[KeyProxy] %s\n' "$*"; }
step() { printf '\n[KeyProxy] Etapa %s/5 — %s\n' "$1" "$2"; }
warn() { printf '[KeyProxy] AVISO: %s\n' "$*" >&2; }
die() { printf '[KeyProxy] ERRO: %s\n' "$*" >&2; exit 1; }

show_banner() {
  printf '\n'
  printf '===============================================\n'
  printf ' KeyProxy Hub + Codex CLI — macOS/Linux\n'
  printf '===============================================\n'
  printf 'O instalador verificará o Codex, pedirá sua API key\n'
  printf 'e configurará modelo, API e MCP automaticamente.\n'
}

usage() {
  cat <<'HELP'
Instala o KeyProxy Hub no Codex CLI em macOS ou Linux.

Uso:
  ./keyproxy-codex-install.sh [opções]

Opções:
  --skip-api-test       Não executa a chamada real KEYPROXY_OK ao final.
  --skip-codex-install  Falha se o Codex CLI não estiver instalado.
  --api-key-stdin       Lê a API key de uma única linha da entrada padrão.
  -h, --help            Mostra esta ajuda.

O instalador:
  1. verifica ou instala o Codex CLI pelo instalador oficial;
  2. solicita a API key sem exibi-la;
  3. salva a chave em ~/.config/keyproxy/env com permissão 600;
  4. mescla o provider e o MCP no config.toml ativo, preservando o restante;
  5. cria backups e um manifesto local de recuperação do KeyProxy;
  6. valida modelo, provider, MCP e uma resposta real com prazo limitado;
  7. remove o login OAuth oficial somente após a validação de conexão.

Com --skip-api-test, o login OAuth oficial é preservado. Falhas de API, MCP
ou prazo também preservam o login OAuth oficial.

Configuração ativa:
  $CODEX_HOME/config.toml, quando CODEX_HOME estiver definido;
  ~/.codex/config.toml, caso contrário.

Rotação da chave:
  Execute este instalador novamente e informe a nova chave.

Rollback do TOML:
  cp "/caminho/config.toml.DATA.bak" "${CODEX_HOME:-$HOME/.codex}/config.toml"

Desinstalação manual:
  1. confira o manifesto restrito em
     ${CODEX_HOME:-$HOME/.codex}/keyproxy-codex-state;
  2. restaure manualmente apenas o backup indicado no campo config_backup;
  3. remova do perfil o bloco entre os marcadores "KeyProxy Hub para Codex CLI";
  4. remova ~/.config/keyproxy/env quando não precisar mais da credencial.

O script não usa OPENAI_BASE_URL, OPENAI_API_BASE ou chave literal no TOML.
HELP
}

while (($#)); do
  case "$1" in
    --skip-api-test) SKIP_API_TEST=true ;;
    --skip-codex-install) SKIP_CODEX_INSTALL=true ;;
    --api-key-stdin) API_KEY_STDIN=true ;;
    -h|--help) usage; exit 0 ;;
    *) die "Opção desconhecida: $1. Use --help." ;;
  esac
  shift
done

rollback_local_changes() {
  warn "Falha antes da validação local; restaurando arquivos anteriores."

  if [[ "$CONFIG_INSTALLED" == true ]]; then
    if [[ "$CONFIG_EXISTED" == true && -n "$BACKUP_FILE" && -f "$BACKUP_FILE" ]]; then
      cp -p "$BACKUP_FILE" "$CONFIG_FILE" || true
    else
      rm -f "$CONFIG_FILE" || true
    fi
  fi

  if [[ "$PROFILE_CHANGED" == true ]]; then
    if [[ "$PROFILE_EXISTED" == true && -n "$PROFILE_BACKUP" && -f "$PROFILE_BACKUP" ]]; then
      cp -p "$PROFILE_BACKUP" "$SHELL_PROFILE" || true
    else
      rm -f "$SHELL_PROFILE" || true
    fi
  fi

  if [[ "$ENV_CHANGED" == true ]]; then
    if [[ "$ENV_EXISTED" == true && -n "$ENV_BACKUP" && -f "$ENV_BACKUP" ]]; then
      cp -p "$ENV_BACKUP" "$ENV_FILE" || true
    else
      rm -f "$ENV_FILE" || true
    fi
  fi

  if [[ "$STATE_CREATED" == true && -n "$STATE_FILE" ]]; then
    rm -f "$STATE_FILE" || true
  fi
}

cleanup() {
  local exit_code=$?
  trap - EXIT

  if [[ -n "$API_TEST_PID" ]]; then
    kill "$API_TEST_PID" >/dev/null 2>&1 || true
    wait "$API_TEST_PID" >/dev/null 2>&1 || true
  fi

  if [[ "$ROLLBACK_ARMED" == true && "$exit_code" -ne 0 ]]; then
    rollback_local_changes
  fi

  if [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]]; then
    rm -rf "$TMP_ROOT"
  fi

  exit "$exit_code"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Dependência obrigatória ausente: $1"
}

assert_path_has_no_symlink() {
  local path="$1" label="$2" parent
  [[ "$path" == /* ]] || die "$label precisa usar um caminho absoluto."

  while true; do
    [[ ! -L "$path" ]] || die "$label contém link simbólico: $path. Use um caminho físico para não alterar outro destino."
    [[ "$path" == "$HOME" || "$path" != "$HOME"/* ]] && return
    parent="$(dirname "$path")"
    [[ "$parent" != "$path" ]] || return
    path="$parent"
  done
}

is_keyproxy_config() {
  local file="$1"
  [[ -f "$file" ]] \
    && grep -Eq '^model[[:space:]]*=[[:space:]]*"gpt-5\.6-sol"[[:space:]]*$' "$file" \
    && grep -Eq '^model_provider[[:space:]]*=[[:space:]]*"keyproxy"[[:space:]]*$' "$file" \
    && grep -Fqx '[model_providers.keyproxy]' "$file" \
    && grep -Fqx '[mcp_servers.keyproxy]' "$file"
}

validate_recovery_state() {
  local recorded_version recorded_creator recorded_path recorded_existed recorded_backup
  if [[ ! -e "$STATE_FILE" ]]; then
    if is_keyproxy_config "$CONFIG_FILE"; then
      die 'A configuração KeyProxy ativa não tem manifesto de recuperação confiável; nenhum arquivo será sobrescrito.'
    fi
    return
  fi
  [[ ! -L "$STATE_FILE" ]] || die 'O manifesto de recuperação contém link simbólico; nenhum arquivo será seguido.'
  [[ -f "$STATE_FILE" ]] || die 'O manifesto de recuperação não é um arquivo regular.'

  recorded_version="$(grep -E '^version=' "$STATE_FILE" | cut -d= -f2-)"
  recorded_creator="$(grep -E '^created_by=' "$STATE_FILE" | cut -d= -f2-)"
  recorded_path="$(grep -E '^config_path=' "$STATE_FILE" | cut -d= -f2-)"
  recorded_existed="$(grep -E '^config_existed=' "$STATE_FILE" | cut -d= -f2-)"
  recorded_backup="$(grep -E '^config_backup=' "$STATE_FILE" | cut -d= -f2-)"
  [[ "$recorded_version" == 1 && "$recorded_creator" == keyproxy-codex-install \
    && "$recorded_path" == "$CONFIG_FILE" && ( "$recorded_existed" == true || "$recorded_existed" == false ) ]] || die \
    'O manifesto de recuperação é inválido para este CODEX_HOME; nenhum arquivo será sobrescrito.'
  if [[ "$recorded_existed" == true ]]; then
    [[ "$recorded_backup" == "$CONFIG_FILE".*.bak && -f "$recorded_backup" && ! -L "$recorded_backup" ]] || die \
      'O backup registrado pelo KeyProxy não está disponível ou não é seguro; nenhum arquivo será sobrescrito.'
  else
    [[ -z "$recorded_backup" ]] || die 'O manifesto de recuperação contém backup inesperado; nenhum arquivo será sobrescrito.'
  fi
}

write_recovery_state() {
  local state_dir staged
  [[ ! -e "$STATE_FILE" ]] || return
  state_dir="$(dirname "$STATE_FILE")"
  mkdir -p "$state_dir"
  chmod 700 "$state_dir"
  staged="$state_dir/.codex-state.$$"
  {
    printf 'version=1\n'
    printf 'config_path=%s\n' "$CONFIG_FILE"
    printf 'config_existed=%s\n' "$CONFIG_EXISTED"
    printf 'config_backup=%s\n' "$BACKUP_FILE"
    printf 'created_by=keyproxy-codex-install\n'
  } > "$staged"
  chmod 600 "$staged"
  mv "$staged" "$STATE_FILE"
  STATE_CREATED=true
}

is_allowed_installer_url() {
  local url="$1"
  [[ "$url" =~ ^https://(chatgpt\.com|releases\.openai\.com)(:[0-9]+)?(/|$) ]]
}

validate_existing_config() {
  [[ -f "$CONFIG_FILE" ]] || return 0

  info "Validando a configuração existente antes da mesclagem."
  codex --strict-config --version >/dev/null 2>&1 || die \
    "O config.toml existente já é inválido; nenhum arquivo foi alterado."

  if grep -Eq "=[[:space:]]*('''|\"\"\")" "$CONFIG_FILE"; then
    die "O config.toml usa strings TOML multilinha; use a configuração manual para preservar esse formato."
  fi

  if awk '
    function has_unclosed_collection(line,    i, ch, quote, escaped, equal_at, value, first, balance) {
      quote = ""
      escaped = 0
      equal_at = 0
      for (i = 1; i <= length(line); i++) {
        ch = substr(line, i, 1)
        if (quote == "\"") {
          if (escaped) escaped = 0
          else if (ch == "\\") escaped = 1
          else if (ch == "\"") quote = ""
          continue
        }
        if (quote == "\047") {
          if (ch == "\047") quote = ""
          continue
        }
        if (ch == "#") break
        if (ch == "\"" || ch == "\047") {
          quote = ch
          continue
        }
        if (ch == "=") {
          equal_at = i
          break
        }
      }
      if (!equal_at) return 0

      value = substr(line, equal_at + 1)
      sub(/^[[:space:]]+/, "", value)
      first = substr(value, 1, 1)
      if (first != "[" && first != "{") return 0

      quote = ""
      escaped = 0
      balance = 0
      for (i = 1; i <= length(value); i++) {
        ch = substr(value, i, 1)
        if (quote == "\"") {
          if (escaped) escaped = 0
          else if (ch == "\\") escaped = 1
          else if (ch == "\"") quote = ""
          continue
        }
        if (quote == "\047") {
          if (ch == "\047") quote = ""
          continue
        }
        if (ch == "#") break
        if (ch == "\"" || ch == "\047") {
          quote = ch
          continue
        }
        if (ch == "[" || ch == "{") balance++
        else if (ch == "]" || ch == "}") balance--
      }
      return balance != 0
    }
    has_unclosed_collection($0) { invalid = 1 }
    END { exit(invalid ? 0 : 1) }
  ' "$CONFIG_FILE"; then
    die "O config.toml usa array/tabela multilinha; use a configuração manual para preservar esse formato."
  fi
}

validate_existing_profile() {
  local marker_status
  [[ -f "$SHELL_PROFILE" ]] || return 0

  marker_status="$(awk -v begin="$PROFILE_BEGIN" -v end="$PROFILE_END" '
    $0 == begin {
      begin_count++
      if (opened) invalid = 1
      opened = 1
    }
    $0 == end {
      end_count++
      if (!opened) invalid = 1
      opened = 0
    }
    END {
      if (opened || invalid || begin_count != end_count || begin_count > 1) print "invalid"
      else print "ok"
    }
  ' "$SHELL_PROFILE")"

  [[ "$marker_status" == "ok" ]] || die \
    "O perfil $SHELL_PROFILE contém marcadores KeyProxy incompletos ou duplicados; nenhum arquivo foi alterado."
}

download_file() {
  local url="$1" destination="$2" final_url
  is_allowed_installer_url "$url" || die "A URL do instalador oficial não pertence a um host aprovado."

  command -v curl >/dev/null 2>&1 || die \
    "curl é obrigatório para baixar o Codex CLI com validação do redirecionamento final."
  final_url="$(curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --output "$destination" --write-out '%{url_effective}' "$url")" || return

  is_allowed_installer_url "$final_url" || die "Redirecionamento não autorizado do instalador oficial: $final_url"
}

install_codex_if_needed() {
  if command -v codex >/dev/null 2>&1; then
    if codex --version >/dev/null 2>&1; then
      info "Codex CLI já está instalado e funcional."
      return
    fi
    warn "O comando codex existe, mas codex --version falhou; o instalador oficial será executado para reparar a instalação."
  fi

  if [[ "$SKIP_CODEX_INSTALL" == true ]]; then
    die "Codex CLI ausente ou inválido e --skip-codex-install foi informado."
  fi

  info "Codex CLI não encontrado ou inválido; baixando o instalador oficial."
  local installer="$TMP_ROOT/codex-install.sh"
  download_file "$CODEX_INSTALLER_URL" "$installer"
  [[ -s "$installer" ]] || die "O instalador oficial do Codex foi baixado vazio."
  /bin/sh -n "$installer" || die "O instalador oficial baixado não contém shell válido."
  chmod 700 "$installer"
  CODEX_NON_INTERACTIVE=1 /bin/sh "$installer"

  export PATH="$HOME/.local/bin:$PATH"
  hash -r 2>/dev/null || true
  command -v codex >/dev/null 2>&1 || die \
    "Codex foi instalado, mas não foi encontrado no PATH. Abra um novo terminal e execute novamente."
  codex --version >/dev/null 2>&1 || die \
    "O instalador oficial terminou, mas codex --version ainda falha. Corrija a instalação do Codex e execute novamente."
}

assert_codex_available() {
  command -v codex >/dev/null 2>&1 || die "Codex CLI não foi localizado após a verificação/instalação."
  local version
  version="$(codex --version 2>/dev/null)" || die "codex --version falhou após a verificação/instalação."
  [[ -n "$version" ]] || die "codex --version não retornou uma versão."
  info "Codex detectado: $version"
}

detect_platform_and_profile() {
  case "$(uname -s)" in
    Darwin) PLATFORM="macOS" ;;
    Linux) PLATFORM="Linux" ;;
    *) die "Sistema não suportado. Use macOS ou Linux." ;;
  esac

  local shell_name="${SHELL:-}"
  shell_name="${shell_name##*/}"
  case "$shell_name" in
    zsh) SHELL_PROFILE="$HOME/.zshrc" ;;
    bash)
      if [[ "$PLATFORM" == "macOS" ]]; then
        SHELL_PROFILE="$HOME/.bash_profile"
      else
        SHELL_PROFILE="$HOME/.bashrc"
      fi
      ;;
    *) die "Shell não suportado: ${SHELL:-desconhecido}. Use Bash ou Zsh." ;;
  esac
}

write_merger() {
  cat > "$TMP_ROOT/merge.awk" <<'AWK'
function trim(value) {
  sub(/^[[:space:]]+/, "", value)
  sub(/[[:space:]]+$/, "", value)
  return value
}
function emit_top_level_missing() {
  if (!model_seen) print "model = \"gpt-5.6-sol\""
  if (!provider_seen) print "model_provider = \"keyproxy\""
  model_seen = provider_seen = 1
}
function emit_provider() {
  print "[model_providers.keyproxy]"
  print "name = \"KeyProxy Hub\""
  print "base_url = \"https://api.keyproxyhub.store/v1\""
  print "env_key = \"KEYPROXY_API_KEY\""
  print "wire_api = \"responses\""
  print "requires_openai_auth = false"
  provider_section_emitted = 1
}
function emit_mcp() {
  print "[mcp_servers.keyproxy]"
  print "url = \"https://api.keyproxyhub.store/mcp\""
  print "bearer_token_env_var = \"KEYPROXY_API_KEY\""
  print "enabled = true"
  mcp_section_emitted = 1
}
function finish_features() {
  if (section == "features" && !apps_seen) print "apps = false"
}
BEGIN {
  section = "top"
  skipping = 0
  first_section_seen = 0
  model_seen = provider_seen = 0
  provider_section_emitted = mcp_section_emitted = 0
  features_seen = apps_seen = 0
}
{
  line = $0
  normalized = trim(line)

  if (normalized ~ /^\[.*\]([[:space:]]*#.*)?$/) {
    finish_features()
    if (!first_section_seen) {
      emit_top_level_missing()
      if (NR > 1) print ""
      first_section_seen = 1
    }

    if (normalized ~ /^\[model_providers\.keyproxy\]([[:space:]]*#.*)?$/) {
      if (!provider_section_emitted) emit_provider()
      section = "provider"
      skipping = 1
      next
    }
    if (normalized ~ /^\[mcp_servers\.keyproxy\]([[:space:]]*#.*)?$/) {
      if (!mcp_section_emitted) emit_mcp()
      section = "mcp"
      skipping = 1
      next
    }

    skipping = 0
    if (normalized ~ /^\[features\]([[:space:]]*#.*)?$/) {
      section = "features"
      features_seen = 1
      apps_seen = 0
    } else {
      section = "other"
    }
    print line
    next
  }

  if (skipping) next

  if (section == "top") {
    if (line ~ /^[[:space:]]*model[[:space:]]*=/) {
      if (!model_seen) print "model = \"gpt-5.6-sol\""
      model_seen = 1
      next
    }
    if (line ~ /^[[:space:]]*model_provider[[:space:]]*=/) {
      if (!provider_seen) print "model_provider = \"keyproxy\""
      provider_seen = 1
      next
    }
    if (line ~ /^[[:space:]]*(api_key|base_url)[[:space:]]*=/) next
  }

  if (section == "features" && line ~ /^[[:space:]]*apps[[:space:]]*=/) {
    if (!apps_seen) print "apps = false"
    apps_seen = 1
    next
  }

  print line
}
END {
  finish_features()
  if (!first_section_seen) emit_top_level_missing()
  if (!provider_section_emitted) {
    print ""
    emit_provider()
  }
  if (!features_seen) {
    print ""
    print "[features]"
    print "apps = false"
  }
  if (!mcp_section_emitted) {
    print ""
    emit_mcp()
  }
}
AWK
}

merge_config() {
  local config_dir
  config_dir="$(dirname "$CONFIG_FILE")"
  if [[ ! -d "$config_dir" ]]; then
    umask 077
    mkdir -p "$config_dir"
    chmod 700 "$config_dir"
  fi

  local source_file="$CONFIG_FILE"
  if [[ ! -f "$source_file" ]]; then
    CONFIG_EXISTED=false
    source_file="$TMP_ROOT/empty.toml"
    : > "$source_file"
  else
    CONFIG_EXISTED=true
    BACKUP_FILE="$CONFIG_FILE.$(date +%Y%m%d-%H%M%S).$$.bak"
    cp -p "$CONFIG_FILE" "$BACKUP_FILE"
    chmod 600 "$BACKUP_FILE"
    info "Backup do Codex criado: $BACKUP_FILE"
  fi

  write_merger
  awk -f "$TMP_ROOT/merge.awk" "$source_file" > "$TMP_ROOT/config.toml"
  chmod 600 "$TMP_ROOT/config.toml"

  local validation_home="$TMP_ROOT/validation-codex-home"
  mkdir -p "$validation_home"
  cp "$TMP_ROOT/config.toml" "$validation_home/config.toml"
  chmod 600 "$validation_home/config.toml"

  if ! CODEX_HOME="$validation_home" codex --strict-config --version >/dev/null 2>&1; then
    die "A configuração mesclada não passou no parser estrito do Codex; nenhum config.toml foi alterado."
  fi

  local staged="$config_dir/.config.toml.keyproxy.$$"
  cp "$TMP_ROOT/config.toml" "$staged"
  chmod 600 "$staged"
  CONFIG_INSTALLED=true
  mv "$staged" "$CONFIG_FILE"

  codex --strict-config --version >/dev/null 2>&1 || die \
    "O Codex rejeitou a configuração ativa."
}

shell_quote() {
  local value="$1"
  value=${value//\'/\'\\\'\'}
  printf "'%s'" "$value"
}

store_api_key() {
  local api_key env_dir
  if [[ "$API_KEY_STDIN" == true ]]; then
    IFS= read -r api_key || true
  else
    [[ -t 0 ]] || die "Execução não interativa exige --api-key-stdin; nunca informe a chave como argumento."
    printf 'Cole sua API key do KeyProxy Hub e pressione Enter.\n'
    printf 'A chave não aparecerá na tela. Pressione Ctrl+C para cancelar.\n'
    printf 'API key: '
    IFS= read -r -s api_key
    printf '\n'
  fi
  [[ -n "$api_key" ]] || die "Nenhuma API key foi informada. Obtenha uma chave no portal KeyProxy e execute novamente."

  env_dir="$(dirname "$ENV_FILE")"
  if [[ ! -d "$env_dir" ]]; then
    umask 077
    mkdir -p "$env_dir"
    chmod 700 "$env_dir"
  elif [[ "$env_dir" == "$KEYPROXY_DIR" ]]; then
    chmod 700 "$env_dir"
  fi
  umask 077

  if [[ -f "$ENV_FILE" ]]; then
    ENV_EXISTED=true
    ENV_BACKUP="$TMP_ROOT/keyproxy-env.backup"
    cp -p "$ENV_FILE" "$ENV_BACKUP"
  else
    ENV_EXISTED=false
  fi

  local staged="$env_dir/.env.keyproxy.$$"
  printf 'export KEYPROXY_API_KEY=%s\n' "$(shell_quote "$api_key")" > "$staged"
  chmod 600 "$staged"
  ENV_CHANGED=true
  mv "$staged" "$ENV_FILE"
  export KEYPROXY_API_KEY="$api_key"
  unset api_key
}

update_shell_profile() {
  local profile_dir
  profile_dir="$(dirname "$SHELL_PROFILE")"
  mkdir -p "$profile_dir"

  if [[ -f "$SHELL_PROFILE" ]]; then
    PROFILE_EXISTED=true
    PROFILE_BACKUP="$SHELL_PROFILE.keyproxy.$(date +%Y%m%d-%H%M%S).$$.bak"
    cp -p "$SHELL_PROFILE" "$PROFILE_BACKUP"
  else
    PROFILE_EXISTED=false
  fi

  if [[ "$PROFILE_EXISTED" == true ]]; then
    awk -v begin="$PROFILE_BEGIN" -v end="$PROFILE_END" '
      $0 == begin { skipping = 1; next }
      $0 == end { skipping = 0; next }
      !skipping { print }
    ' "$SHELL_PROFILE" > "$TMP_ROOT/shell-profile"
  else
    : > "$TMP_ROOT/shell-profile"
  fi

  cat >> "$TMP_ROOT/shell-profile" <<EOF

$PROFILE_BEGIN
[[ -f "\$HOME/.config/keyproxy/env" ]] && source "\$HOME/.config/keyproxy/env"
$PROFILE_END
EOF

  local staged_profile="$SHELL_PROFILE.keyproxy.$$"
  if [[ "$PROFILE_EXISTED" == true ]]; then
    cp -p "$SHELL_PROFILE" "$staged_profile"
    cat "$TMP_ROOT/shell-profile" > "$staged_profile"
  else
    umask 077
    cat "$TMP_ROOT/shell-profile" > "$staged_profile"
    chmod 600 "$staged_profile"
  fi
  PROFILE_CHANGED=true
  mv "$staged_profile" "$SHELL_PROFILE"
}

validate_local_configuration() {
  info "Validando configuração, provider e MCP."
  codex --strict-config --version

  local doctor_output="$TMP_ROOT/doctor.json"
  if ! codex doctor --json > "$doctor_output"; then
    die "codex doctor não conseguiu concluir. Execute manualmente: codex doctor --json"
  fi

  grep -Eq '"model"[[:space:]]*:[[:space:]]*"gpt-5\.6-sol"' "$doctor_output" || die \
    "O diagnóstico não confirmou o modelo gpt-5.6-sol."
  grep -Eq '"model provider"[[:space:]]*:[[:space:]]*"keyproxy"' "$doctor_output" || die \
    "O diagnóstico não confirmou o provider keyproxy."

  codex mcp get keyproxy >/dev/null || die "O MCP keyproxy não foi encontrado."
}

validate_api() {
  if [[ "$SKIP_API_TEST" == true ]]; then
    warn "Teste real da API ignorado por --skip-api-test."
    return
  fi

  info "Executando uma chamada real com $KEYPROXY_MODEL."
  info "Se a rede ficar presa, pressione Ctrl+C; o script não encerra processos externos."
  local output="$TMP_ROOT/api-test.log"
  local api_status=0
  local timeout_seconds="${KEYPROXY_CODEX_API_TIMEOUT_SECONDS:-90}"
  [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] || die \
    'KEYPROXY_CODEX_API_TIMEOUT_SECONDS precisa ser um inteiro positivo.'

  codex exec --sandbox read-only --skip-git-repo-check \
    'Responda somente com: KEYPROXY_OK' > "$output" 2>&1 &
  API_TEST_PID=$!
  local elapsed=0
  while kill -0 "$API_TEST_PID" >/dev/null 2>&1; do
    if ((elapsed >= timeout_seconds)); then
      kill "$API_TEST_PID" >/dev/null 2>&1 || true
      wait "$API_TEST_PID" >/dev/null 2>&1 || true
      API_TEST_PID=""
      warn "A chamada real excedeu o prazo de ${timeout_seconds}s; o login OAuth oficial foi preservado."
      exit 2
    fi
    sleep 1
    ((elapsed+=1))
  done
  wait "$API_TEST_PID" || api_status=$?
  API_TEST_PID=""
  if ((api_status != 0)); then
    warn "A configuração local passou, mas a chamada real falhou (código $api_status)."
    warn "Confira sua chave, rede, cota e o endpoint do KeyProxy Hub."
    grep -E '^(ERROR|error:|model:|provider:)|401|403|429|KEYPROXY_OK' "$output" >&2 || true
    exit 2
  fi

  grep -Fq 'model: gpt-5.6-sol' "$output" || die \
    "A chamada não confirmou o modelo gpt-5.6-sol."
  grep -Fq 'provider: keyproxy' "$output" || die \
    "A chamada não confirmou o provider keyproxy."
  grep -Eq '^KEYPROXY_OK$' "$output" || die \
    "A chamada terminou, mas não retornou KEYPROXY_OK."

  if awk '
    {
      line = tolower($0)
      if (line ~ /keyproxy/ && line ~ /mcp/ && \
          line ~ /(failed|failure|error|unable|falhou|falha|erro|401|403|unauthorized|não autorizad[oa])/) {
        found = 1
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$output"; then
    warn "A resposta do modelo funcionou, mas o MCP keyproxy falhou ao iniciar."
    grep -Ei 'keyproxy.*mcp|mcp.*keyproxy' "$output" >&2 || true
    exit 2
  fi
}

main() {
  [[ "$(id -u)" != "0" ]] || die \
    "Não execute como root/sudo; o instalador configura o usuário atual."

  for command_name in uname id awk grep sed date mktemp cp mv rm chmod mkdir dirname cat cut; do
    require_command "$command_name"
  done

  detect_platform_and_profile
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/keyproxy-codex.XXXXXX")"
  chmod 700 "$TMP_ROOT"

  CODEX_CONFIG_HOME="${CODEX_HOME:-$HOME/.codex}"
  CONFIG_FILE="$CODEX_CONFIG_HOME/config.toml"
  KEYPROXY_DIR="$HOME/.config/keyproxy"
  ENV_FILE="$KEYPROXY_DIR/env"
  STATE_FILE="$CODEX_CONFIG_HOME/keyproxy-codex-state"
  assert_path_has_no_symlink "$CODEX_CONFIG_HOME" 'CODEX_HOME'
  assert_path_has_no_symlink "$CONFIG_FILE" 'config.toml'
  assert_path_has_no_symlink "$SHELL_PROFILE" 'perfil do shell'
  assert_path_has_no_symlink "$KEYPROXY_DIR" 'diretório de credencial KeyProxy'
  assert_path_has_no_symlink "$ENV_FILE" 'arquivo de credencial KeyProxy'
  assert_path_has_no_symlink "$STATE_FILE" 'manifesto de recuperação KeyProxy'
  validate_recovery_state

  show_banner
  info "Sistema detectado: $PLATFORM"
  info "Configuração Codex: $CONFIG_FILE"

  step 1 "verificando o Codex CLI"
  install_codex_if_needed
  assert_codex_available

  step 2 "conferindo a configuração existente"
  validate_existing_config
  validate_existing_profile

  ROLLBACK_ARMED=true
  step 3 "salvando sua API key com segurança"
  store_api_key

  step 4 "configurando modelo, API e MCP"
  merge_config
  update_shell_profile
  validate_local_configuration
  write_recovery_state
  ROLLBACK_ARMED=false

  step 5 "testando a conexão com o KeyProxy Hub"
  validate_api

  if [[ "$SKIP_API_TEST" == true ]]; then
    warn "Login OAuth oficial preservado porque o teste real da API foi ignorado."
  else
    info "Removendo o login OAuth oficial do Codex para uso exclusivo do KeyProxy."
    codex logout >/dev/null 2>&1 || warn "Não havia login oficial ativo ou o logout não foi necessário."
  fi

  printf '\n'
  printf '===============================================\n'
  printf ' Instalação concluída com sucesso\n'
  printf '===============================================\n'
  info "Modelo: $KEYPROXY_MODEL"
  info "Provider: keyproxy"
  info "API: $KEYPROXY_BASE_URL"
  info "MCP: $KEYPROXY_MCP_URL"
  info "Configuração: $CONFIG_FILE"
  info "Credencial: $ENV_FILE (permissão 600)"
  [[ -n "$BACKUP_FILE" ]] && info "Backup: $BACKUP_FILE"
  info "Próximo passo: abra um novo Terminal e execute: codex"
  info "Para usar neste Terminal agora: source $SHELL_PROFILE"
}

main
