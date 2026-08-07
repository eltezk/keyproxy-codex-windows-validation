#!/usr/bin/env bash
# Monta o pacote público do portal sem expor arquivos internos do repositório privado.

set -Eeuo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${1:-$ROOT/dist/public}"

readonly PUBLIC_FILES=(
  keyproxy-codex-install.sh
  keyproxy-codex-install.sh.sha256
  keyproxy-codex-install-windows.ps1
  keyproxy-codex-install-windows.ps1.sha256
)

rm -rf "$DESTINATION"
mkdir -p "$DESTINATION"

for file in "${PUBLIC_FILES[@]}"; do
  [[ -f "$ROOT/$file" ]] || {
    printf 'Arquivo obrigatório ausente: %s\n' "$file" >&2
    exit 1
  }
  cp "$ROOT/$file" "$DESTINATION/$file"
done

(
  cd "$DESTINATION"
  shasum -a 256 -c keyproxy-codex-install.sh.sha256
  expected="$(awk 'NR == 1 { print tolower($1) }' keyproxy-codex-install-windows.ps1.sha256)"
  actual="$(shasum -a 256 keyproxy-codex-install-windows.ps1 | awk '{ print tolower($1) }')"
  [[ "$actual" == "$expected" ]] || {
    printf 'SHA-256 divergente para o instalador Windows.\n' >&2
    exit 1
  }
)

for forbidden in \
  '*selftest*' \
  '.github' \
  '.git' \
  '*.log' \
  '.env*'; do
  if find "$DESTINATION" -name "$forbidden" -print -quit | grep -q .; then
    printf 'O bundle contém um caminho não publicável: %s\n' "$forbidden" >&2
    exit 1
  fi
done

find "$DESTINATION" -type f -maxdepth 1 -print | LC_ALL=C sort
printf 'public-bundle=ok\n'
