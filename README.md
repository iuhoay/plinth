# Plinth

A tiny wooden fish that lives on your Mac's desktop. Click it to knock and hear a soft *tok*. That's all. You earn no merit (功德) for it.

The wooden fish (*muyu*) is a hollow temple block that Buddhist monks strike to keep time while chanting. Old monastic rules say it is shaped like a fish because a fish never closes its eyes, so its knock keeps the drowsy awake. Plinth puts one on a small neon pedestal next to your windows.

Many wooden-fish apps float "功德 +1" ("merit +1") over every knock and keep a running score. Plinth doesn't. When Emperor Wu listed the temples he had built and asked Bodhidharma how much merit he had earned, the answer was 「并无功德」: none at all. Your first knock gets the same answer, and no score is ever kept.

## Features

- **Knock it.** Click the fish. A mallet swings, the wood gives a little, and it sounds. The longer the quiet before a knock, the more it rings.
- **Auto-knock.** Let it keep a steady rhythm (every 0.5 to 4 seconds), with an option to stop after 108 knocks, one full turn of a mala.
- **Knock as you type.** Optional: each key you press, in any app, knocks once. Pause to think, and the next key rings. It needs no special permission: Plinth only notices *when* a key goes down, never which key.
- **A few words.** The fish has a few things to say, and says each of them once.
- **Stays out of the way.** No Dock icon. Float it above your windows or sink it onto the desktop. Drag it anywhere.
- **Skins.** Seven ship with the app, each with its own mallet and most with their own burst: the wooden fish, a jade fish, a red lacquer fish, a singing bowl, a pixel-art fish, a cartoon fish, and an ink-wash fish. Or swap in anything: a folder of sprite frames, or a single image.

What little the fish says is in the original Chinese, as you would hear it in a temple. Menus and settings are in English.

Right-click the fish, or use the fish icon in the menu bar, for every option.

## Download

Get `Plinth-x.y.z.dmg` from [Releases](https://github.com/rubycatco/plinth/releases), open it, and drag Plinth into Applications. It runs on macOS 14 Sonoma or later. Or build it yourself, as below.

## Requirements

- macOS 14 Sonoma or later
- Xcode 15 or later (to build from source)

## Build

```sh
git clone https://github.com/rubycatco/plinth.git
cd plinth
./scripts/build_app.sh
open build/Plinth.app
```

The script builds a universal binary (Apple silicon and Intel), assembles `build/Plinth.app`, and signs it ad hoc. To keep it, drag `build/Plinth.app` into `/Applications`. `./scripts/make_dmg.sh` packages it as a disk image; [docs/RELEASING.md](docs/RELEASING.md) covers signing, notarization, and releases.

For a quick run during development, `swift run` works too, but the fish won't find its images and sounds outside the app bundle, so use the script to see the real thing.

## Skins

Plinth looks for skins in:

```
~/Library/Application Support/Plinth/Skins/
```

Open it from **Skin → Open Skins Folder**, or add skins with **Skin → Add Skins…**. Changes are picked up while the app runs.

A skin is either a single image (PNG, JPEG, …) or a folder like this:

```
my-skin/
├── idle.png    resting pose (required)
├── blink.png   shown for a moment every few seconds (optional)
├── hit.png     shown right after the mallet lands (optional)
├── mallet.png  the skin's own mallet (optional)
├── impact.png  the skin's own burst where the mallet lands (optional)
└── skin.json   its name, and where the mallet lands (optional)
```

Blink and hit can also be short sequences: `blink-1.png`, `blink-2.png`, … A blink plays toward its last frame (eyes shut) and back; a hit plays toward its last frame, holds, and settles. Each step cross-fades at the display's frame rate, so even two or three frames move smoothly.

Frames should be square with a transparent background. 512 × 512 works well. A skin's `mallet.png` replaces the shared [`mallet.png`](App/Resources/mallet.png) and should be laid out the same way: horizontal, head on the left, grip at the right edge. Its `impact.png` replaces the shared neon burst and is drawn as is, so it can be dark, like an ink splash. `skin.json` gives the point where the mallet's head lands, as fractions of the frame width and height, measured from the top-left corner:

```json
{ "name": "My Skin", "strike": [0.6, 0.3] }
```

A figure without a hit frame gives a little under the mallet instead. The built-in skins live in [`App/Resources/Skins`](App/Resources/Skins). The fishes have no blink or hit frame, on purpose: a fish never closes its eyes, not even when struck.

## Project layout

```
Sources/Plinth/     SwiftUI + AppKit source
App/                Info.plist, app icon, and bundled resources
scripts/            build and disk-image scripts
docs/               how releases are signed and published
.github/workflows/  the release workflow
tools/              synthesizer for the knock and its hall (Python, NumPy, SciPy)
```

## License

Code: [MIT](LICENSE). Art and sounds: CC0. See [CREDITS.md](CREDITS.md).
