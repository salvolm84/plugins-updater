# SLM Plugins Updater

A small native macOS app (Apple Silicon) that keeps the SLM audio plug-ins up to date.

It looks at the GitHub releases of every plug-in repo under [github.com/salvolm84](https://github.com/salvolm84), compares them with what is installed on your Mac, and installs updates — or new plug-ins you don't have yet — after showing you what changed.

## Features

- **Finds plug-ins automatically.** Every repo with a macOS plug-in release shows up. No setup on a fresh Mac.
- **Three groups at launch:** *Updates available*, *New — not installed on this Mac*, and *Up to date*.
- **Changelog before you confirm.** Notes from every release between your version and the latest are combined. Boilerplate sections (Install, Requirements, …) are removed. Tick *Show full release notes* to see the originals.
- **Installs VST3, Audio Unit and CLAP** bundles to `~/Library/Audio/Plug-Ins/…`. Standalone apps go to `/Applications`; this format is off by default and can be turned on in Settings. Existing copies are replaced where they are (including `/Library`), and old versions go to the Trash.
- **Gets past Gatekeeper.** After installing, it runs `sudo xattr -rd com.apple.quarantine` on every new bundle, with one administrator password prompt per batch, so macOS doesn't block the unsigned plug-ins.
- Warns you if a DAW is running, and refreshes the Audio Unit cache after installing AUs.

## Install

1. Download `SLM-Plugins-Updater-<version>-macOS-arm64.zip` from [Releases](https://github.com/salvolm84/plugins-updater/releases/latest) and unzip it.
2. Move **SLM Plugins Updater.app** to `/Applications`.
3. The app is unsigned, so clear its quarantine flag once:

   ```sh
   sudo xattr -rd com.apple.quarantine "/Applications/SLM Plugins Updater.app"
   ```

   Or right-click the app → **Open**, then confirm.

Requires macOS 14 Sonoma or later on Apple Silicon.

## Usage

Open the app. It checks GitHub at launch (you can turn this off in Settings).

- Click **Update** or **Install** on a row, or **Update All** / **Install All** on a section.
- Read the changelog and click **Update** / **Install** to confirm.
- Enter your password when macOS asks. This runs the `xattr` step.
- Rescan plug-ins in your DAW.

**Settings** (⌘,) lets you pick formats, turn off the quarantine step, include pre-releases, or point the app at another GitHub owner.

## How detection works

- Bundles are found in `~/Library/Audio/Plug-Ins/{VST3,Components,CLAP}`, `/Library/Audio/Plug-Ins/…`, `/Applications` and `~/Applications`, and matched by bundle identifier.
- [`catalog.json`](catalog.json) maps each repo to its bundle IDs and display name. The app downloads it from this repo at every check, so you can add a plug-in or fix a mapping without a new build. A built-in copy is used when offline.
- Repos missing from the catalog still appear if a release asset name mentions `vst3`/`au`/`component`/`clap`/`plugin`, or the repo has a topic like `audio-plugin` or `vst3`. Their bundle IDs are recorded on first install.
- The app records which release tag it installed (in `~/Library/Application Support/SLM Plugins Updater/installed.json`). That keeps versions right even when a bundle's `Info.plist` version wasn't bumped. If the bundle changes outside the app, the `Info.plist` version is used instead.

### Release conventions for plug-in repos

To be picked up, a release should:

- be a published (non-draft) GitHub release with a version tag such as `v1.2.0`;
- attach a `.zip` whose name includes `macOS` (and ideally the format, e.g. `MyPlugin-1.2.0-macOS-arm64-VST3.zip`);
- contain `.vst3`, `.component`, `.clap` and/or `.app` bundles at any folder depth.

Assets for Windows, Linux or Intel-only builds are ignored.

## Build from source

```sh
swift build                                    # debug build
.build/debug/SLMPluginsUpdater --list          # print what would be updated, then quit
scripts/build-app.sh 1.0.0                     # dist/SLM Plugins Updater.app + release zip
```

Needs Xcode 16 or later (Swift 6 toolchain). No dependencies.
