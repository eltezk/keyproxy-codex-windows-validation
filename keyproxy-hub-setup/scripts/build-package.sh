#!/usr/bin/env bash
# Gera um ZIP autocontido depois de validar conteúdo, sintaxe e checksums.

set -Eeuo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT/dist}"
[[ "$OUTPUT_DIR" = /* ]] || OUTPUT_DIR="$ROOT/$OUTPUT_DIR"
PACKAGE_NAME='keyproxy-hub-setup'
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/keyproxy-hub-build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

for required in \
  keyproxy-hub.sh keyproxy-hub.ps1 README.md SHA256SUMS \
  claude/install.sh claude/install.ps1 claude/lib/keyproxy_claude_config.py \
  codex/keyproxy-codex-install.sh codex/keyproxy-codex-install-windows.ps1 \
  tests/unix-selftest.sh tests/windows-selftest.ps1; do
  [[ -f "$ROOT/$required" ]] || { printf 'Arquivo obrigatório ausente: %s\n' "$required" >&2; exit 1; }
done

bash -n "$ROOT/keyproxy-hub.sh" "$ROOT/tests/unix-selftest.sh" "$ROOT/claude/install.sh" "$ROOT/codex/keyproxy-codex-install.sh"
python3 -m py_compile "$ROOT/claude/lib/keyproxy_claude_config.py" "$ROOT/claude/bin/keyproxy-claude"
(cd "$ROOT" && shasum -a 256 -c SHA256SUMS)

cp -R "$ROOT"/. "$STAGING/$PACKAGE_NAME"
rm -rf "$STAGING/$PACKAGE_NAME/dist" "$STAGING/$PACKAGE_NAME/.DS_Store" "$STAGING/$PACKAGE_NAME/.git"
find "$STAGING/$PACKAGE_NAME" -type f \( -name '*.log' -o -name '.env' -o -name '.env.*' \) -print -quit | grep -q . && {
  printf 'O pacote contém arquivo proibido.\n' >&2; exit 1;
}

mkdir -p "$OUTPUT_DIR"
ZIP_PATH="$OUTPUT_DIR/$PACKAGE_NAME.zip"
rm -f "$ZIP_PATH"
(
  cd "$STAGING"
  zip -qr "$ZIP_PATH" "$PACKAGE_NAME"
)
shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"
printf 'package=%s\n' "$ZIP_PATH"
printf 'checksum=%s.sha256\n' "$ZIP_PATH"
