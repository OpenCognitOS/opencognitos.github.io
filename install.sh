#!/bin/sh
# OpenCognit installer for macOS (Apple Silicon)
# Usage: curl -fsSL https://opencognit.com/install.sh | sh
#
# Downloads the latest release from GitHub, checks its SHA-512 against the release's latest-mac.yml,
# and puts OpenCognit.app into /Applications (or ~/Applications). Run it again to update.
# Linux and Windows: installers at https://opencognit.com/#pricing
set -eu

REPO="OpenCognitOS/opencognit-releases"
BASE="https://github.com/$REPO/releases"
APP="OpenCognit.app"

say() { printf '  %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "This installer is for macOS. Linux and Windows: https://opencognit.com/#pricing"
[ "$(uname -m)" = "arm64" ] || fail "OpenCognit for Mac needs Apple Silicon (M1 or newer) for now."
for tool in curl ditto shasum base64 xxd; do
  command -v "$tool" >/dev/null 2>&1 || fail "Missing tool: $tool"
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

printf '\n  OpenCognit for macOS\n\n'

# Version and checksum of the zip from the version file
curl -fsSL "$BASE/latest/download/latest-mac.yml" -o "$tmp/latest-mac.yml" || fail "Could not reach GitHub."
version=$(sed -n 's/^version: *//p' "$tmp/latest-mac.yml" | head -n 1)
zip=$(sed -n 's/^ *- url: *\(.*\.zip\) *$/\1/p' "$tmp/latest-mac.yml" | head -n 1)
[ -n "$version" ] && [ -n "$zip" ] || fail "No macOS build in the latest release."
want=$(awk -v z="$zip" '$0 ~ "url: *"z"$" { getline; sub(/^ *sha512: */, ""); print; exit }' "$tmp/latest-mac.yml")
[ -n "$want" ] || fail "No checksum for $zip."

say "Downloading OpenCognit $version …"
curl -fL --progress-bar "$BASE/download/v$version/$zip" -o "$tmp/app.zip" || fail "Download failed."

got=$(shasum -a 512 "$tmp/app.zip" | cut -d ' ' -f 1 | xxd -r -p | base64 | tr -d '\n')
[ "$got" = "$want" ] || fail "Checksum does not match — the download is damaged or was changed. Nothing was installed."
say "Checksum OK"

ditto -x -k "$tmp/app.zip" "$tmp/x"
[ -d "$tmp/x/$APP" ] || fail "$APP not found in the download."

dest="/Applications"
[ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }

# Quit a running copy first (updating)
if pgrep -x OpenCognit >/dev/null; then
  say "Closing the running OpenCognit …"
  osascript -e 'quit app "OpenCognit"' >/dev/null 2>&1 || true
  i=0
  while pgrep -x OpenCognit >/dev/null && [ $i -lt 40 ]; do sleep 0.5; i=$((i + 1)); done
  pgrep -x OpenCognit >/dev/null && fail "OpenCognit is still running (agents busy?). Quit it, then run this again."
fi

rm -rf "$dest/$APP"
mv "$tmp/x/$APP" "$dest/$APP"
# Not notarized by Apple (no paid developer account) — curl downloads carry no quarantine flag anyway
xattr -dr com.apple.quarantine "$dest/$APP" 2>/dev/null || true

say "✓ Installed to $dest/$APP"
open "$dest/$APP"
printf '\n  To update later, run the same command again.\n\n'
