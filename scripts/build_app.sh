#!/bin/bash
# Build build/Plinth.app (universal). Needs macOS 14+ and Xcode 16.3+.
#
# Signed ad hoc by default, which is fine on your own Mac. To sign for
# distribution, set PLINTH_SIGN_IDENTITY to a Developer ID Application
# certificate in your keychain, e.g. "Developer ID Application: Name (TEAMID)";
# the app then gets the hardened runtime and secure timestamp that
# notarization requires, and keeps its update feed (an ad hoc build doesn't
# update itself). PLINTH_VERSION and PLINTH_BUILD override the version
# (e.g. 1.2.0) and build number in Info.plist.
#
# PLINTH_APPSTORE=1 builds for the Mac App Store instead: sandboxed, without
# Sparkle or an update feed. Ad hoc signed, it runs sandboxed on your own Mac.
# With PLINTH_SIGN_IDENTITY set to an "Apple Distribution: Name (TEAMID)"
# certificate, it also needs PLINTH_PROVISIONING_PROFILE, the app's Mac App
# Store provisioning profile, and PLINTH_INSTALLER_IDENTITY, a "3rd Party Mac
# Developer Installer: Name (TEAMID)" certificate, and writes build/Plinth.pkg
# to upload.
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
APPSTORE=${PLINTH_APPSTORE:-}
if [ "$APPSTORE" != 1 ]; then
  mkdir -p "$APP/Contents/Frameworks"
  # ditto keeps the framework's relative symlinks.
  ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
fi

# Shortcuts finds the Knock action through App Intents metadata. Xcode
# extracts it when it builds an app; SwiftPM doesn't, so extract it here from
# the constant values the compiler wrote.
SCRATCH=$(mktemp -d)
ls "$PWD"/Sources/Plinth/*.swift > "$SCRATCH/sources"
find "$PWD/.build" -name '*.swiftconstvalues' -path '*/Release/*/arm64/*' > "$SCRATCH/constvalues"
xcrun appintentsmetadataprocessor --quiet-warnings \
  --output "$APP/Contents/Resources" --binary-file "$APP/Contents/MacOS/Plinth" \
  --toolchain-dir "$(dirname "$(xcrun -f swiftc)")/../.." \
  --sdk-root "$(xcrun --show-sdk-path --sdk macosx)" \
  --xcode-version "$(xcodebuild -version | awk '/Build version/ { print $3 }')" \
  --module-name Plinth --platform-family macOS --deployment-target 14.0 \
  --target-triple arm64-apple-macos14.0 \
  --source-file-list "$SCRATCH/sources" --swift-const-vals-list "$SCRATCH/constvalues" >/dev/null 2>&1
test -f "$APP/Contents/Resources/Metadata.appintents/extract.actionsdata" ||
  { echo "Couldn't extract the App Intents metadata for Shortcuts; it needs Xcode 16.3 or later" >&2; exit 1; }
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

# Sign from the inside out, never with --deep.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
IDENTITY="${PLINTH_SIGN_IDENTITY:-}"
PKG=""
if [ "$APPSTORE" = 1 ]; then
  # The App Store updates the app itself.
  for key in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks; do
    plutil -remove "$key" "$APP/Contents/Info.plist"
  done
  # Bring the skins of an earlier Plinth into the sandbox on first launch.
  cp App/container-migration.plist "$APP/Contents/Resources/"
  if [ -n "$IDENTITY" ]; then
    PROFILE="${PLINTH_PROVISIONING_PROFILE:?Set PLINTH_PROVISIONING_PROFILE to the Mac App Store provisioning profile}"
    INSTALLER="${PLINTH_INSTALLER_IDENTITY:?Set PLINTH_INSTALLER_IDENTITY to a 3rd Party Mac Developer Installer certificate}"
    cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
    # The signature must also carry the app and team identifiers the profile grants.
    SCRATCH=$(mktemp -d)
    security cms -D -i "$PROFILE" > "$SCRATCH/profile.plist"
    cp App/Plinth.entitlements "$SCRATCH/Plinth.entitlements"
    for key in com.apple.application-identifier com.apple.developer.team-identifier; do
      value=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:$key" "$SCRATCH/profile.plist")
      /usr/libexec/PlistBuddy -c "Add :$key string $value" "$SCRATCH/Plinth.entitlements"
    done
    codesign --force --options runtime --timestamp --sign "$IDENTITY" \
      --entitlements "$SCRATCH/Plinth.entitlements" "$APP"
    PKG=build/Plinth.pkg
    productbuild --component "$APP" /Applications --sign "$INSTALLER" "$PKG"
    SIGNER="$IDENTITY"
  else
    codesign --force --sign - --entitlements App/Plinth.entitlements "$APP"
    SIGNER="ad hoc, sandboxed"
  fi
elif [ -n "$IDENTITY" ]; then
  SIGN=(codesign --force --options runtime --timestamp --sign "$IDENTITY")
  "${SIGN[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
  "${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
  "${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
  "${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
  "${SIGN[@]}" "$SPARKLE"
  "${SIGN[@]}" "$APP"
  SIGNER="$IDENTITY"
else
  # Updates come signed with our Developer ID, so a build of your own gets
  # no feed and never offers to replace itself with ours. Ad hoc code also
  # can't take the hardened runtime: library validation would refuse
  # Sparkle, which has no team ID either.
  plutil -remove SUFeedURL "$APP/Contents/Info.plist"
  codesign --force --sign - "$SPARKLE"
  codesign --force --sign - "$APP"
  SIGNER="ad hoc"
fi
codesign --verify --deep --strict "$APP"
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
echo "Built $APP $VERSION, signed $SIGNER"
if [ -n "$PKG" ]; then echo "Built $PKG to upload to App Store Connect"; fi
