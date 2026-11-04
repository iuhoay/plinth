#!/bin/bash
# Build Plinth and package it as build/Plinth-<version>.dmg.
#
# Without credentials you get an ad hoc signed image, fine for your own Mac;
# on other Macs Gatekeeper will block it. For one that opens anywhere:
#
#   PLINTH_SIGN_IDENTITY   a Developer ID Application certificate in your
#                          keychain; signs the app and the image
#
# plus notarization credentials, either a profile saved with
# `xcrun notarytool store-credentials`:
#
#   PLINTH_NOTARY_PROFILE  the profile's name
#
# or an App Store Connect API key:
#
#   PLINTH_NOTARY_KEY      path to the AuthKey_XXXXXXXXXX.p8 file
#   PLINTH_NOTARY_KEY_ID   its key ID
#   PLINTH_NOTARY_ISSUER   the issuer ID
#
# The image is then notarized by Apple and the ticket stapled to it.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build_app.sh
APP=build/Plinth.app
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
DMG="build/Plinth-$VERSION.dmg"
IDENTITY="${PLINTH_SIGN_IDENTITY:-}"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
# dmgbuild lays out the window (background, icon positions) by writing its
# .DS_Store directly, so it needs no Finder or AppleScript, even on CI.
python3 -m venv "$STAGE/venv"
"$STAGE/venv/bin/pip" install --quiet --disable-pip-version-check "dmgbuild==1.6.7"
# One TIFF holding the 1x and @2x backgrounds, so Retina screens get the sharp one.
tiffutil -cathidpicheck App/DMGBackground.png App/DMGBackground@2x.png -out "$STAGE/background.tiff" 2>/dev/null
rm -f "$DMG"
# hdiutil now and then fails with "Resource busy", especially on CI.
for attempt in 1 2 3; do
  if "$STAGE/venv/bin/dmgbuild" -s scripts/dmg_settings.py -D app="$APP" -D background="$STAGE/background.tiff" \
      Plinth "$DMG" >/dev/null; then
    break
  fi
  if [ "$attempt" = 3 ]; then
    echo "error: dmgbuild could not create $DMG" >&2
    exit 1
  fi
  sleep 5
done

if [ -z "$IDENTITY" ]; then
  echo "Made $DMG (ad hoc signed: opens on this Mac, Gatekeeper blocks it elsewhere)"
  exit 0
fi

codesign --force --timestamp --sign "$IDENTITY" "$DMG"

NOTARY=()
if [ -n "${PLINTH_NOTARY_PROFILE:-}" ]; then
  NOTARY=(--keychain-profile "$PLINTH_NOTARY_PROFILE")
elif [ -n "${PLINTH_NOTARY_KEY:-}" ]; then
  NOTARY=(--key "$PLINTH_NOTARY_KEY" --key-id "$PLINTH_NOTARY_KEY_ID" --issuer "$PLINTH_NOTARY_ISSUER")
fi
if [ ${#NOTARY[@]} -eq 0 ]; then
  echo "Made $DMG (signed, not notarized: Gatekeeper will still warn on other Macs)"
  exit 0
fi

echo "Notarizing $DMG (this usually takes a few minutes)..."
RESULT=$(xcrun notarytool submit "$DMG" "${NOTARY[@]}" --wait --output-format json)
STATUS=$(plutil -extract status raw - <<<"$RESULT")
if [ "$STATUS" != "Accepted" ]; then
  echo "error: notarization finished with status $STATUS" >&2
  ID=$(plutil -extract id raw - <<<"$RESULT" 2>/dev/null || true)
  [ -n "$ID" ] && xcrun notarytool log "$ID" "${NOTARY[@]}" >&2 || true
  exit 1
fi
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "Made $DMG (signed, notarized and stapled)"
