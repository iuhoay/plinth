#!/bin/bash
# Write build/appcast.xml, the feed that tells Plinth a new version is out,
# for a notarized disk image made by make_dmg.sh:
#
#   ./scripts/make_appcast.sh build/Plinth-1.4.0.dmg [whats-new.md]
#
# The optional Markdown file is shown in the update window, so keep it to
# what changed. The image is signed with the EdDSA key saved in your login
# keychain under the account "plinth" (docs/RELEASING.md), or with the key in
# PLINTH_SPARKLE_KEY when that is set.
#
# Publish the image and build/appcast.xml in the same release. The app reads
# the feed from the latest release, so every release needs one. Don't rebuild
# or re-sign the image afterwards: the feed carries its signature.
set -euo pipefail
cd "$(dirname "$0")/.."

DMG=${1:?usage: make_appcast.sh build/Plinth-<version>.dmg [whats-new.md]}
NOTES=${2:-}
NAME=$(basename "$DMG" .dmg)
VERSION=${NAME#Plinth-}
REPO=https://github.com/rubycatco/plinth

xcrun stapler validate -q "$DMG" ||
  { echo "error: $DMG isn't notarized; make it with make_dmg.sh and the notarization variables" >&2; exit 1; }

swift package resolve >/dev/null
TOOLS=.build/artifacts/sparkle/Sparkle/bin

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp "$DMG" "$STAGE/"
if [ -n "$NOTES" ]; then cp "$NOTES" "$STAGE/$NAME.md"; fi

ARGS=(--download-url-prefix "$REPO/releases/download/v$VERSION/"
      --full-release-notes-url "$REPO/releases/tag/v$VERSION"
      --link "$REPO" --maximum-deltas 0 --embed-release-notes)
if [ -n "${PLINTH_SPARKLE_KEY:-}" ]; then
  printf '%s\n' "$PLINTH_SPARKLE_KEY" | "$TOOLS/generate_appcast" --ed-key-file - "${ARGS[@]}" "$STAGE"
else
  "$TOOLS/generate_appcast" --account plinth "${ARGS[@]}" "$STAGE"
fi
cp "$STAGE/appcast.xml" build/appcast.xml
echo "Made build/appcast.xml for $NAME.dmg"
