#!/usr/bin/env bash
# Monta uma entrega autoexplicativa para o proprietário publicar no portal.

set -Eeuo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DELIVERY="${1:-$ROOT/dist/keyproxy-codex-site}"
if [[ "$DELIVERY" != /* ]]; then
  DELIVERY="$ROOT/$DELIVERY"
fi
UPLOAD_DIR="$DELIVERY/UPLOAD-NO-SITE"

readonly PUBLIC_FILES=(
  keyproxy-codex-install.sh
  keyproxy-codex-install.sh.sha256
  keyproxy-codex-install-windows.ps1
  keyproxy-codex-install-windows.ps1.sha256
)
readonly GUIDE_FILES=(
  LEIA-ME-PRIMEIRO.txt
  COPIAR-E-COLAR-NO-SITE.html
  COPIAR-E-COLAR-NO-SITE.md
)

rm -rf "$DELIVERY"
mkdir -p "$UPLOAD_DIR"

for file in "${PUBLIC_FILES[@]}"; do
  [[ -f "$ROOT/$file" ]] || {
    printf 'Arquivo obrigatório ausente: %s\n' "$file" >&2
    exit 1
  }
  cp "$ROOT/$file" "$UPLOAD_DIR/$file"
done

for file in "${GUIDE_FILES[@]}"; do
  [[ -f "$ROOT/site/$file" ]] || {
    printf 'Guia obrigatório ausente: site/%s\n' "$file" >&2
    exit 1
  }
  cp "$ROOT/site/$file" "$DELIVERY/$file"
done

(
  cd "$UPLOAD_DIR"
  shasum -a 256 -c keyproxy-codex-install.sh.sha256
  expected="$(awk 'NR == 1 { print tolower($1) }' keyproxy-codex-install-windows.ps1.sha256)"
  actual="$(shasum -a 256 keyproxy-codex-install-windows.ps1 | awk '{ print tolower($1) }')"
  [[ "$actual" == "$expected" ]] || {
    printf 'SHA-256 divergente para o instalador Windows.\n' >&2
    exit 1
  }
)

actual_count="$(find "$UPLOAD_DIR" -maxdepth 1 -type f | wc -l | tr -d ' ')"
[[ "$actual_count" == "${#PUBLIC_FILES[@]}" ]] || {
  printf 'UPLOAD-NO-SITE deve conter exatamente %s arquivos; encontrou %s.\n' \
    "${#PUBLIC_FILES[@]}" "$actual_count" >&2
  exit 1
}

for forbidden in \
  '*selftest*' \
  '.github' \
  '.git' \
  '*.log' \
  '.env*'; do
  if find "$UPLOAD_DIR" -name "$forbidden" -print -quit | grep -q .; then
    printf 'UPLOAD-NO-SITE contém um caminho proibido: %s\n' "$forbidden" >&2
    exit 1
  fi
done

for guide in \
  "$DELIVERY/COPIAR-E-COLAR-NO-SITE.html" \
  "$DELIVERY/COPIAR-E-COLAR-NO-SITE.md"; do
  grep -Fq 'https://keyproxyhub.store/downloads/codex' "$guide" || {
    printf 'O guia não contém a URL pública do KeyProxy: %s\n' "$guide" >&2
    exit 1
  }
  if grep -Eiq 'raw\.githubusercontent\.com|github\.com/eltezk|SEU-DOMINIO' "$guide"; then
    printf 'O guia contém URL privada ou placeholder: %s\n' "$guide" >&2
    exit 1
  fi
  if grep -Eiq 'curl[^\n|]*\|[[:space:]]*(ba)?sh|wget[^\n|]*\|[[:space:]]*(ba)?sh|irm[^\n|]*\|[[:space:]]*iex|Invoke-RestMethod[^\n|]*\|[[:space:]]*Invoke-Expression' "$guide"; then
    printf 'O guia contém execução direta de download por pipe: %s\n' "$guide" >&2
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
