# Releasing

Plinth ships as a disk image signed with a Developer ID certificate and notarized by Apple, so it opens on any Mac without Gatekeeper warnings.

Plinth updates itself with [Sparkle](https://sparkle-project.org). Once a day it reads `appcast.xml` from the latest GitHub release, at `https://github.com/rubycatco/plinth/releases/latest/download/appcast.xml`, and offers the disk image the feed points to. The feed carries an EdDSA signature of that image, made with the key under [Update signing key](#update-signing-key), and the app installs only an image that matches. **Every release must include `appcast.xml`.** A release without one leaves every installed copy unable to find updates until a release with a feed is published.

## Cut a release

Tag the commit on `main` and push the tag:

```sh
git tag v1.2.0
git push origin v1.2.0
```

What happens next depends on whether the repository has the signing secrets listed under [One-time setup](#one-time-setup). `gh secret list` shows them.

- **With the secrets**, the [Release workflow](../.github/workflows/release.yml) builds `Plinth-1.2.0.dmg` (the tag sets the version), signs and notarizes it, staples the ticket, writes the update feed, and publishes both as a GitHub release with generated notes.
- **Without them**, the workflow builds an ad hoc signed image, keeps it in the run's artifacts, and publishes nothing. The run still succeeds, with a warning. Build the signed image on your Mac and publish it by hand, as below.

Running the workflow by hand from the Actions tab only builds the disk image and keeps it in the run's artifacts.

### Publishing by hand

With your certificate and notarization profile set up as in [Building a signed image locally](#building-a-signed-image-locally), build from the tagged commit:

```sh
git switch --detach v1.2.0
PLINTH_VERSION=1.2.0 \
PLINTH_BUILD=$(git rev-list --count HEAD) \
PLINTH_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
PLINTH_NOTARY_PROFILE=plinth-notary \
./scripts/make_dmg.sh
```

Set `PLINTH_VERSION` and `PLINTH_BUILD` as shown. Without them the app keeps the version in `App/Info.plist`, and the image is named after it. `PLINTH_BUILD` matches what the workflow uses: the number of commits up to the tag.

Write the update feed for it. The optional Markdown file is shown in the app's update window, so keep it to what changed, without install steps:

```sh
./scripts/make_appcast.sh build/Plinth-1.2.0.dmg whats-new.md
```

The script signs the image with the key in your keychain. The first time, macOS asks whether `generate_appcast` may use the key; choose Always Allow. Don't rebuild or re-sign the image after this: the feed holds its signature.

Check the image, then publish it and the feed with your notes and the image's SHA-256:

```sh
spctl -a -vv -t open --context context:primary-signature build/Plinth-1.2.0.dmg
shasum -a 256 build/Plinth-1.2.0.dmg
gh release create v1.2.0 build/Plinth-1.2.0.dmg build/appcast.xml --title "Plinth 1.2.0" --notes-file notes.md
```

Earlier releases have notes in English and Simplified Chinese, with install steps and the image's SHA-256. Use them as a template.

## One-time setup

This needs a paid Apple Developer Program membership.

1. **Developer ID certificate.** In Xcode, open Settings → Accounts, select the team, choose Manage Certificates, click +, and pick Developer ID Application. Only the team's Account Holder can create one.
2. **Export it for CI.** In Keychain Access, under My Certificates, right-click "Developer ID Application: …", choose Export, and save a `.p12` file with a password.
3. **Notarization key.** In App Store Connect, go to Users and Access → Integrations → App Store Connect API → Team Keys and generate a key with Developer access. Download the `.p8` file (it can only be downloaded once) and note its Key ID and the Issuer ID shown above the list.
4. **Repository secrets.** From the repository folder:

   ```sh
   base64 -i DeveloperID.p12 | gh secret set MACOS_CERTIFICATE_P12
   gh secret set MACOS_CERTIFICATE_PASSWORD          # paste the .p12 password
   gh secret set NOTARY_API_KEY_P8 < AuthKey_XXXXXXXXXX.p8
   gh secret set NOTARY_API_KEY_ID --body XXXXXXXXXX
   gh secret set NOTARY_API_ISSUER_ID --body 00000000-0000-0000-0000-000000000000
   ```

   Then delete the exported `.p12`.
5. **Update signing key** for the workflow, from [Update signing key](#update-signing-key):

   ```sh
   gh secret set SPARKLE_ED_PRIVATE_KEY < plinth-update-key.txt
   ```

   Without it the workflow publishes nothing, even with the other secrets, since a release without a feed would stop updates.

## Update signing key

The key that signs updates lives in the login keychain of the Mac that made it, under the account `plinth`. Its public half is `SUPublicEDKey` in [`App/Info.plist`](../App/Info.plist). Sparkle's tools come with the package:

```sh
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account plinth -p   # print the public key
```

**Back it up.** Without it, the only way to ship an update that installed copies accept is Sparkle's [key rotation](https://sparkle-project.org/documentation/#rotating-signing-keys): a release signed with the same Developer ID certificate that carries a new public key. Lose the certificate as well and every user has to download the next version by hand. Export the key, keep the file in a password manager, and delete it:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account plinth -x plinth-update-key.txt
```

On another Mac, `generate_keys --account plinth -f plinth-update-key.txt` imports it. Never commit it. If it leaks, rotate it the same way.

## Mac App Store build

`PLINTH_APPSTORE=1` builds the app for the Mac App Store: it runs in the App Sandbox with [`App/Plinth.entitlements`](../App/Plinth.entitlements), leaves out Sparkle, and has no update feed or update menu item, since the App Store updates it. Without a certificate it is signed ad hoc, which is enough to try the sandboxed app on your own Mac:

```sh
PLINTH_APPSTORE=1 ./scripts/build_app.sh
```

To upload, you need the app's Mac App Store provisioning profile and two certificates, "Apple Distribution" and "3rd Party Mac Developer Installer" (create them in Xcode under Settings → Accounts → Manage Certificates):

```sh
PLINTH_APPSTORE=1 \
PLINTH_VERSION=1.2.0 \
PLINTH_BUILD=$(git rev-list --count HEAD) \
PLINTH_SIGN_IDENTITY="Apple Distribution: Your Name (TEAMID)" \
PLINTH_PROVISIONING_PROFILE=Plinth_Mac_App_Store.provisionprofile \
PLINTH_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Your Name (TEAMID)" \
./scripts/build_app.sh
```

The script embeds the profile, signs the app with the sandbox entitlements plus the app and team identifiers from the profile, and writes `build/Plinth.pkg`. Upload it with Transporter or `xcrun altool --upload-package`. Every upload needs a higher `PLINTH_BUILD` than the last.

## Building a signed image locally

Save the notarization key in your keychain once, then point the script at your certificate:

```sh
xcrun notarytool store-credentials plinth-notary \
  --key AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer 00000000-0000-0000-0000-000000000000

PLINTH_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
PLINTH_NOTARY_PROFILE=plinth-notary \
./scripts/make_dmg.sh
```

Without those variables, `./scripts/make_dmg.sh` makes an ad hoc signed image, which opens on your own Mac but not on others.

The script lays out the image's window with [dmgbuild](https://github.com/dmgbuild/dmgbuild), which it installs from PyPI into a temporary virtual environment, so it needs network access and a `python3` of 3.10 or later (the one that ships with macOS is 3.9). The packages are pinned by hash in `scripts/dmgbuild-requirements.txt`.
