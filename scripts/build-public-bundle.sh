#!/usr/bin/env bash
# Monta uma entrega autoexplicativa para o proprietário publicar no portal.

set -Eeuo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DELIVERY="${1:-$ROOT/dist/keyproxy-codex-site}"
if [[ "$DELIVERY" != /* ]]; then
  DELIVERY="$ROOT/$DELIVERY"
fi
UPLOAD_DIR="$DELIVERY/UPLOAD-NO-SITE"

readonly SOURCE_UNIX="keyproxy-codex-install.sh"
readonly SOURCE_WINDOWS="keyproxy-codex-install-windows.ps1"
readonly PUBLIC_FILES=(
  install.sh
  install.sh.sha256
  install.ps1
  install.ps1.sha256
)
readonly GUIDE_FILES=(
  LEIA-ME-PRIMEIRO.txt
  COPIAR-E-COLAR-NO-SITE.html
  COPIAR-E-COLAR-NO-SITE.md
)

rm -rf "$DELIVERY"
mkdir -p "$UPLOAD_DIR"

for file in "$SOURCE_UNIX" "$SOURCE_WINDOWS"; do
  [[ -f "$ROOT/$file" ]] || {
    printf 'Arquivo obrigatório ausente: %s\n' "$file" >&2
    exit 1
  }
done

cp "$ROOT/$SOURCE_UNIX" "$UPLOAD_DIR/install.sh"
cp "$ROOT/$SOURCE_WINDOWS" "$UPLOAD_DIR/install.ps1"
(
  cd "$UPLOAD_DIR"
  shasum -a 256 install.sh > install.sh.sha256
  shasum -a 256 install.ps1 > install.ps1.sha256
  shasum -a 256 -c install.sh.sha256
  shasum -a 256 -c install.ps1.sha256
)

for file in "${GUIDE_FILES[@]}"; do
  [[ -f "$ROOT/site/$file" ]] || {
    printf 'Guia obrigatório ausente: site/%s\n' "$file" >&2
    exit 1
  }
  cp "$ROOT/site/$file" "$DELIVERY/$file"
done

actual_count="$(find "$UPLOAD_DIR" -maxdepth 1 -type f | wc -l | tr -d ' ')"
[[ "$actual_count" == "${#PUBLIC_FILES[@]}" ]] || {
  printf 'UPLOAD-NO-SITE deve conter exatamente %s arquivos; encontrou %s.\n' \
    "${#PUBLIC_FILES[@]}" "$actual_count" >&2
  exit 1
}

for file in "${PUBLIC_FILES[@]}"; do
  [[ -f "$UPLOAD_DIR/$file" ]] || {
    printf 'Arquivo público esperado ausente: %s\n' "$file" >&2
    exit 1
  }
done

for forbidden in \
  '*selftest*' \
  '.github' \
  '.git' \
  '*.log' \
  '.env*' \
  'keyproxy-codex-install*'; do
  if find "$UPLOAD_DIR" -name "$forbidden" -print -quit | grep -q .; then
    printf 'UPLOAD-NO-SITE contém um caminho proibido: %s\n' "$forbidden" >&2
    exit 1
  fi
done

for guide in \
  "$DELIVERY/COPIAR-E-COLAR-NO-SITE.html" \
  "$DELIVERY/COPIAR-E-COLAR-NO-SITE.md"; do
  for required in \
    'https://keyproxyhub.store/downloads/codex/install.sh' \
    'https://keyproxyhub.store/downloads/codex/install.sh.sha256' \
    'https://keyproxyhub.store/downloads/codex/install.ps1' \
    'https://keyproxyhub.store/downloads/codex/install.ps1.sha256' \
    'Quero verificar o SHA-256 antes' \
    'ExecutionPolicy Bypass'; do
    grep -Fq "$required" "$guide" || {
      printf 'O guia não contém o item obrigatório "%s": %s\n' "$required" "$guide" >&2
      exit 1
    }
  done

  if grep -Eiq 'raw\.githubusercontent\.com|github\.com/eltezk|SEU-DOMINIO' "$guide"; then
    printf 'O guia contém URL privada ou placeholder: %s\n' "$guide" >&2
    exit 1
  fi
  if grep -Eiq 'curl[^\n|]*\|[[:space:]]*(ba)?sh|wget[^\n|]*\|[[:space:]]*(ba)?sh|irm[^\n|]*\|[[:space:]]*iex|Invoke-RestMethod[^\n|]*\|[[:space:]]*Invoke-Expression' "$guide"; then
    printf 'O guia contém execução direta de download por pipe: %s\n' "$guide" >&2
    exit 1
  fi
  if grep -Eiq 'script (é|esta|está) (digitalmente )?assinado|assinatura (digital )?verificada|authenticode verificado' "$guide"; then
    printf 'O guia alega uma assinatura que o release não comprova: %s\n' "$guide" >&2
    exit 1
  fi
done

zip_path="${DELIVERY%/}.zip"
rm -f "$zip_path"
if command -v zip >/dev/null 2>&1; then
  (
    cd "$(dirname "$DELIVERY")"
    zip -qr "$zip_path" "$(basename "$DELIVERY")"
  )
  printf '%s\n' "$zip_path"
fi

find "$DELIVERY" -type f -print | LC_ALL=C sort
printf 'site-delivery=ok\n'
