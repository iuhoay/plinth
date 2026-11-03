#!/bin/bash
# Build build/Plinth.app (universal). Needs macOS 14+ and Xcode.
#
# Signed ad hoc by default, which is fine on your own Mac. To sign for
# distribution, set PLINTH_SIGN_IDENTITY to a Developer ID Application
# certificate in your keychain, e.g. "Developer ID Application: Name (TEAMID)";
# the app then gets the hardened runtime and secure timestamp that
# notarization requires. PLINTH_VERSION and PLINTH_BUILD override the
# version (e.g. 1.2.0) and build number in Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Plinth

APP=build/Plinth.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Plinth"
cp -R App/Resources/* "$APP/Contents/Resources/"
cp App/Info.plist "$APP/Contents/Info.plist"
if [ -n "${PLINTH_VERSION:-}" ]; then
  plutil -replace CFBundleShortVersionString -string "$PLINTH_VERSION" "$APP/Contents/Info.plist"
fi
if [ -n "${PLINTH_BUILD:-}" ]; then
  plutil -replace CFBundleVersion -string "$PLINTH_BUILD" "$APP/Contents/Info.plist"
fi

ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s App/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) App/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="${PLINTH_SIGN_IDENTITY:-}"
if [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  SIGNER="$IDENTITY"
else
  codesign --force --sign - "$APP"
  SIGNER="ad hoc"
fi
codesign --verify --strict "$APP"
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
echo "Built $APP $VERSION, signed $SIGNER"
