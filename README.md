# Plinth

A tiny wooden fish that lives on your Mac's desktop. Click it to knock, hear a soft *tok*, and earn one point of merit (功德).

The wooden fish (*muyu*) is a hollow temple block that Buddhist monks strike to keep time while chanting. Old monastic rules say it is shaped like a fish because a fish never closes its eyes, so its knock keeps the drowsy awake. Plinth puts one on a small neon pedestal next to your windows.

## Features

- **Knock it.** Click the fish. A mallet swings, the fish reacts, and 功德 +1 ("merit +1") drifts up, or a single Zen character like 静 or 空.
- **Auto-knock.** Let it keep a steady rhythm (every 0.5 to 4 seconds), with an option to stop after 108 knocks, one full turn of a mala.
- **A teaching every 108 knocks.** Every 108 merit points, the fish offers a line from the Zen classics, in the original Chinese.
- **Stays out of the way.** No Dock icon. Float it above your windows or sink it onto the desktop. Drag it anywhere.
- **Skins.** Swap the fish for anything: a folder of sprite frames, or a single image.
- **Let go.** Reset your merit to zero. The count was never the point.

Everything on the fish itself (the merit count, the floating characters, the teachings) is in Chinese, as it would be in a temple. Menus and settings are in English.

Right-click the fish, or use the fish icon in the menu bar, for every option.

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

The script builds a universal binary (Apple silicon and Intel), assembles `build/Plinth.app`, and signs it ad hoc. To keep it, drag `build/Plinth.app` into `/Applications`.

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
└── skin.json   where the mallet lands (optional)
```

Frames should be square with a transparent background. 512 × 512 works well. `skin.json` gives the point where the mallet's head lands, as fractions of the frame width and height, measured from the top-left corner:

```json
{ "strike": [0.6, 0.3] }
```

The built-in wooden fish in [`App/Resources/Skins/wooden-fish`](App/Resources/Skins/wooden-fish) is a complete example.

## Project layout

```
Sources/Plinth/     SwiftUI + AppKit source
App/                Info.plist, app icon, and bundled resources
scripts/            build script
tools/              knock-sound synthesizer (Python, NumPy, SciPy)
```

## License

Code: [MIT](LICENSE). Art and sounds: CC0. See [CREDITS.md](CREDITS.md).
