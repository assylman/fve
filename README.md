# fve — Flutter Version & Environment Manager

> Install, switch, and manage multiple Flutter SDK versions with per-project pinning.
> No symlink juggling. No broken teammates. No stale CocoaPods caches. *(coming soon)*

---

## Table of Contents

- [Why fve?](#why-fve)
- [Features](#features)
- [Platform Support](#platform-support)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
  - [Version Resolution](#version-resolution)
  - [The `.fverc` File](#the-fverc-file)
  - [Storage Layout](#storage-layout)
- [Command Reference](#command-reference)
  - [fve install](#fve-install)
  - [fve use](#fve-use)
  - [fve global](#fve-global)
  - [fve list](#fve-list)
  - [fve releases](#fve-releases)
  - [fve current](#fve-current)
  - [fve remove](#fve-remove)
  - [fve flutter](#fve-flutter)
  - [fve dart](#fve-dart)
  - [fve exec](#fve-exec)
  - [fve doctor](#fve-doctor)
- [Shell Integration](#shell-integration)
- [Team Workflows](#team-workflows)
- [CI/CD Integration](#cicd-integration)
- [Configuration Reference](#configuration-reference)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## Why fve?

Flutter projects tend to drift across SDK versions. One project uses `3.19.0`; another targets `3.22.2`; a third is pinned to a beta build for a specific engine fix. Without tooling, the only option is to manually reinstall Flutter or maintain multiple SDK directories and update `PATH` by hand.

**fve** solves this with a small, fast Dart binary that:

- Caches each SDK version once in `~/.fve/versions/` and never downloads it again.
- Reads a `.fverc` file in your project root to automatically pick the right version when you run `fve flutter` or `fve dart`.
- Leaves your system Flutter installation untouched.

The planned Phase 3 feature — **per-version CocoaPods cache isolation** — goes further: it sets `CP_HOME_DIR` to a version-specific directory before any pod command, eliminating the cache corruption that happens when you switch Flutter versions in an iOS project.

---

## Features

- **Multi-version management** — install and keep as many Flutter SDK versions as you need, side by side.
- **Per-project pinning** — a single `.fverc` file in your repo root locks the project to a specific version.
- **Channel support** — install by channel name (`stable`, `beta`, `dev`) in addition to exact version numbers.
- **Automatic architecture detection** — downloads the correct binary for Apple Silicon (arm64) or Intel (x64).
- **SHA-256 checksum verification** — every download is verified before extraction.
- **Global default** — one version can be set as the system-wide fallback via `~/.fve/current`.
- **Pass-through proxies** — `fve flutter` and `fve dart` forward all arguments to the pinned binary unchanged.
- **Environment injection** — `fve exec` prepends the correct `bin/` to `PATH` before running any command.
- **Diagnostics** — `fve doctor` checks your installation, symlinks, PATH, and system tools.
- **CocoaPods cache isolation** *(coming in Phase 3)* — per-version `CP_HOME_DIR` isolation for iOS projects.

---

## Platform Support

| Platform | Status |
|---|---|
| macOS (Apple Silicon) | Supported |
| macOS (Intel) | Supported |
| Linux (x64) | Supported |
| Linux (arm64) | Supported |
| Windows | Planned |

**Prerequisites:** Dart SDK 3.0 or later, `git`, `unzip` (or `tar` for `.tar.xz` archives on Linux).

---

## Installation

### Via pub global (recommended)

```sh
dart pub global activate fve
```

Ensure Dart's global bin directory is in your `PATH`. If `dart pub global activate` warns you about it, add this to your shell rc:

```sh
export PATH="$HOME/.pub-cache/bin:$PATH"
```

### From source

```sh
git clone https://github.com/yourname/fve.git
cd fve
dart pub get
dart compile exe bin/fve.dart -o fve
sudo mv fve /usr/local/bin/fve
```

### Shell integration

After installing `fve`, set up your global `flutter` and `dart` shims by adding the following to your `~/.zshrc`, `~/.bashrc`, or equivalent:

```sh
# fve — Flutter Version & Environment Manager
export PATH="$HOME/.fve/current/bin:$PATH"
```

Reload your shell:

```sh
source ~/.zshrc  # or ~/.bashrc
```

`$HOME/.fve/current` is a symlink that points to whichever Flutter SDK you have set as your global default. Run `fve global <version>` to update it.

---

## Quick Start

```sh
# 1. See which Flutter versions are available
fve releases

# 2. Install a version
fve install 3.22.2

# 3. Set it as your system-wide default
fve global 3.22.2

# 4. Navigate to your project and pin the version
cd ~/projects/my_app
fve use 3.22.2

# 5. Run Flutter commands — fve picks the right SDK automatically
fve flutter pub get
fve flutter run
fve flutter build apk --release
```

Commit the generated `.fverc` so your whole team uses the same version automatically.

---

## Core Concepts

### Version Resolution

Every `fve flutter`, `fve dart`, and `fve exec` command resolves the active Flutter version using the following priority order:

```
1. .fverc in the current directory (or any ancestor directory)
2. Global default  (~/.fve/config.json  →  ~/.fve/current symlink)
3. Error — no version configured
```

fve walks up the directory tree from the current working directory looking for a `.fverc` file. This means you can have a root `.fverc` for a monorepo and override it in any subdirectory.

### The `.fverc` File

`.fverc` is a JSON file placed in your project root. It contains one field:

```json
{
  "flutter_version": "3.22.2"
}
```

**Commit `.fverc` to version control.** It is small, human-readable, and should be treated the same as `.tool-versions` or `.nvmrc` files in other ecosystems. Add `.fverc` to your project's `.gitignore` template exclusion list (i.e., do *not* ignore it).

To create or update `.fverc`, use [`fve use`](#fve-use):

```sh
fve use 3.22.2
```

### Storage Layout

fve keeps everything inside `~/.fve/`:

```
~/.fve/
├── versions/
│   ├── 3.19.0/          ← Full Flutter SDK (extracted archive)
│   │   ├── bin/
│   │   │   ├── flutter
│   │   │   └── dart
│   │   └── ...
│   └── 3.22.2/          ← Full Flutter SDK
│       ├── bin/
│       └── ...
├── current -> versions/3.22.2   ← Symlink to the global default
└── config.json          ← Global configuration (default version, etc.)
```

Each version directory is a self-contained Flutter SDK. fve never modifies your system Flutter installation.

---

## Command Reference

### `fve install`

Downloads and caches a Flutter SDK version.

```
fve install <version> [options]
```

**Arguments**

| Argument | Description |
|---|---|
| `<version>` | Exact version number (e.g. `3.22.2`) or channel name (`stable`, `beta`, `dev`) |

**Options**

| Option | Description |
|---|---|
| `-f`, `--force` | Re-download even if the version is already cached |

**Examples**

```sh
# Install a specific version
fve install 3.22.2

# Install the latest stable release
fve install stable

# Install the latest beta release
fve install beta

# Force re-download of an existing version (e.g. after a corrupted download)
fve install 3.22.2 --force
```

When you install by channel name (`stable`, `beta`, `dev`), fve resolves the channel to its current commit hash and installs that exact release. The cached copy is stored under the resolved version number (e.g. `3.22.2`), not the channel name, so the cache remains stable even as the channel advances.

fve verifies the SHA-256 checksum of every downloaded archive before extracting it. If verification fails, the partial download is deleted and an error is reported.

---

### `fve use`

Pins a Flutter version for the current project by writing a `.fverc` file.

```
fve use <version> [options]
```

**Arguments**

| Argument | Description |
|---|---|
| `<version>` | Installed Flutter version to pin (must already be installed unless `--skip-install` is passed) |

**Options**

| Option | Description |
|---|---|
| `-g`, `--global` | Also update the system-wide global default |
| `--skip-install` | Write `.fverc` even if the version is not yet installed locally |

**Examples**

```sh
# Pin the current project to 3.22.2
fve use 3.22.2

# Pin and also update the global default in one step
fve use 3.22.2 --global

# Write .fverc before installing (useful in setup scripts)
fve use 3.22.2 --skip-install
```

`fve use` writes (or overwrites) a `.fverc` file in the **current directory**. It does not modify any parent directory.

---

### `fve global`

Sets the system-wide default Flutter version by updating the `~/.fve/current` symlink.

```
fve global <version> [options]
```

**Arguments**

| Argument | Description |
|---|---|
| `<version>` | Installed Flutter version to set as the global default |

**Examples**

```sh
fve global 3.22.2
```

After running this command, `flutter` and `dart` (via the `$HOME/.fve/current/bin` PATH entry) resolve to the specified version. Projects with a `.fverc` are unaffected — they always use their pinned version regardless of the global default.

---

### `fve list`

Browses available Flutter SDK versions fetched from the Flutter releases API, with installed versions highlighted.

```
fve list [options]
```

**Options**

| Option | Default | Description |
|---|---|---|
| `-i`, `--installed` | — | Show only locally installed versions |
| `-c`, `--channel` | `stable` | Filter by channel (`stable`, `beta`, `dev`, `any`) |
| `-n`, `--page-size` | `20` | Number of versions to show per page |

**Examples**

```sh
# Paginated view of stable releases (installed ones are highlighted)
fve list

# Show only what you have installed locally
fve list --installed

# Browse beta channel versions
fve list --channel beta

# Browse across all channels
fve list --channel any
```

In interactive terminals, use **Enter** or **Space** to advance pages and **q** to quit. When output is piped, all results are printed at once.

---

### `fve releases`

Fetches the Flutter release list from the official Flutter releases API and prints a compact summary.

```
fve releases [options]
```

**Options**

| Option | Default | Description |
|---|---|---|
| `-c`, `--channel` | `stable` | Filter by channel (`stable`, `beta`, `dev`, `any`) |
| `-n`, `--limit` | `20` | Maximum number of releases to show |

**Examples**

```sh
# Show the latest 20 stable releases
fve releases

# Show beta releases
fve releases --channel beta

# Show 50 releases across all channels
fve releases --channel any --limit 50
```

Output columns: version · architecture · Dart SDK version · release date.

---

### `fve current`

Shows the active Flutter version for the current directory.

```
fve current
```

Prints three lines:

- **project** — the version from `.fverc` (walked up from `$PWD`), or "none".
- **global** — the version linked at `~/.fve/current`, or "none".
- **active** — whichever of the above takes precedence (project wins).

A warning is shown if the pinned version is not installed.

---

### `fve remove`

Removes a cached Flutter SDK version from `~/.fve/versions/`.

```
fve remove <version> [options]
```

**Arguments**

| Argument | Description |
|---|---|
| `<version>` | Installed Flutter version to remove |

**Options**

| Option | Description |
|---|---|
| `-f`, `--force` | Skip the confirmation prompt |

**Aliases:** `uninstall`, `rm`

**Examples**

```sh
# Remove with a confirmation prompt
fve remove 3.19.0

# Skip the prompt (useful in scripts)
fve remove 3.19.0 --force
```

`fve remove` refuses to delete the version that is currently set as the global default. Set another version as global first:

```sh
fve global 3.22.2
fve remove 3.19.0
```

---

### `fve flutter`

Runs the `flutter` binary from the project-pinned (or global) version, forwarding all arguments unchanged.

```
fve flutter [flutter-arguments...]
```

All arguments are passed directly to `flutter`. fve does not parse or inspect them.

**Examples**

```sh
fve flutter run
fve flutter build apk --release
fve flutter pub get
fve flutter test --coverage
fve flutter --version
```

> **Tip:** `fve flutter --help` shows fve's own help page for this wrapper command.
> To see Flutter's native `--help` output, use `fve exec -- flutter --help`.

---

### `fve dart`

Runs the `dart` binary from the project-pinned (or global) version, forwarding all arguments unchanged.

```
fve dart [dart-arguments...]
```

**Examples**

```sh
fve dart pub get
fve dart run bin/main.dart
fve dart compile exe bin/main.dart
fve dart analyze
fve dart format .
```

> **Tip:** `fve dart --help` shows fve's help page for this wrapper. Use `fve exec -- dart --help` to see Dart's native output.

---

### `fve exec`

Runs any command inside the Flutter version environment. The resolved version's `bin/` directory is prepended to `PATH`, and `FVE_VERSION` is set in the environment.

```
fve exec [options] -- <command> [arguments...]
```

Use `--` to separate fve options from the command being executed.

**Options**

| Option | Description |
|---|---|
| `-v`, `--version` | Override the Flutter version for this invocation |

**Examples**

```sh
# Run pod install with the correct Flutter engine in the environment
fve exec -- pod install

# Get Flutter's native --help output
fve exec -- flutter --help

# Run flutter doctor with an explicit version override
fve exec --version 3.19.0 -- flutter doctor

# Run a custom script that calls flutter internally
fve exec -- ./scripts/build.sh
```

`fve exec` is the escape hatch for any tool that needs to call `flutter` or `dart` directly (scripts, Makefiles, build systems) without going through `fve flutter`.

---

### `fve doctor`

Checks your fve installation for common problems and prints actionable remedies.

```
fve doctor
```

Checks performed:

| Check | What it verifies |
|---|---|
| fve home exists | `~/.fve/` is present |
| versions dir exists | `~/.fve/versions/` is present |
| Installed versions | Lists all locally cached SDKs |
| Global version set | `~/.fve/current` symlink exists and is valid |
| PATH | `$HOME/.fve/current/bin` is in `PATH` |
| Project version | `.fverc` in directory tree, version is installed |
| System tools | `git`, `unzip` (and `pod`, `xcode-select` on macOS) |

---

## Shell Integration

### Global shim (recommended)

Add this to your `~/.zshrc` or `~/.bashrc`:

```sh
export PATH="$HOME/.fve/current/bin:$PATH"
```

After running `fve global <version>`, the system `flutter` and `dart` commands resolve to that version. When you need a project-specific version, use `fve flutter` / `fve dart` instead — they read `.fverc` regardless of `PATH`.

### Per-project shim (alternative)

If you prefer not to modify `PATH`, omit the export and always invoke Flutter through `fve`:

```sh
# Instead of:  flutter run
fve flutter run

# Instead of:  dart pub get
fve dart pub get
```

This is more explicit and works without any shell configuration.

---

## Team Workflows

### New project setup

```sh
# One developer installs the SDK and pins the version
fve install 3.22.2
fve use 3.22.2
git add .fverc
git commit -m "chore: pin Flutter 3.22.2 via fve"
```

### Teammate onboarding

```sh
# After cloning the repo:
fve install   # reads .fverc automatically — coming in a future release
# or:
fve install 3.22.2   # version shown in .fverc
fve flutter pub get
fve flutter run
```

### Upgrading the project Flutter version

```sh
# 1. Install the new version
fve install 3.24.0

# 2. Update .fverc
fve use 3.24.0

# 3. Verify everything builds
fve flutter pub get
fve flutter build apk

# 4. Commit
git add .fverc
git commit -m "chore: upgrade Flutter to 3.24.0"
```

---

## CI/CD Integration

Install fve and the required Flutter version in your CI pipeline before running build steps.

### GitHub Actions

```yaml
- name: Install fve
  run: dart pub global activate fve

- name: Install Flutter (version from .fverc)
  run: |
    VERSION=$(jq -r .flutter_version .fverc)
    fve install "$VERSION"
    echo "$HOME/.fve/versions/$VERSION/bin" >> $GITHUB_PATH

- name: Build
  run: flutter build apk --release
```

### Generic shell script

```sh
#!/usr/bin/env sh
set -e

VERSION=$(jq -r .flutter_version .fverc)
dart pub global activate fve
fve install "$VERSION"
export PATH="$HOME/.fve/versions/$VERSION/bin:$PATH"

flutter pub get
flutter test
flutter build apk --release
```

> **Note:** In CI it is often simpler to add the SDK's `bin/` directory directly to `PATH` (as shown above) rather than using `fve flutter`, since CI machines typically run a single version.

---

## Configuration Reference

### `.fverc` — project configuration

| Field | Type | Required | Description |
|---|---|---|---|
| `flutter_version` | string | yes | Flutter version pinned for this project |

**Full example:**

```json
{
  "flutter_version": "3.22.2"
}
```

fve locates `.fverc` by walking up the directory tree from `$PWD`. The first file found wins. This means a monorepo can have a root-level `.fverc` that is automatically overridden by a package-level `.fverc` in any subdirectory.

**Recommended `.gitignore` entries** — `.fverc` should be committed. Do **not** add it to `.gitignore`. You may want to ignore fve's internal data directory:

```gitignore
# fve stores Flutter SDKs here — no need to commit
# (this is in your HOME dir, not your repo, so no action needed)
```

---

### `~/.fve/config.json` — global configuration

Managed by fve. Do not edit manually.

| Field | Type | Description |
|---|---|---|
| `default_version` | string | Version set by `fve global` |

---

## Troubleshooting

### `fve: command not found`

Dart's global bin directory is not in your `PATH`. Add it:

```sh
export PATH="$HOME/.pub-cache/bin:$PATH"
```

### `flutter: command not found` after `fve global`

The fve shim directory is not in your `PATH`. Add it:

```sh
export PATH="$HOME/.fve/current/bin:$PATH"
```

Then reload your shell (`source ~/.zshrc`).

### `Flutter X.Y.Z (from .fverc) is not installed`

The version recorded in `.fverc` has not been downloaded yet on this machine:

```sh
fve install 3.22.2   # use the version shown in the error
```

### Version shown by `flutter --version` doesn't match `.fverc`

You are running the system `flutter`, not `fve flutter`. Use `fve flutter --version` or ensure `$HOME/.fve/current/bin` appears before other Flutter installations in `PATH`.

### Checksum verification failed

The downloaded archive is corrupt. Delete it and retry:

```sh
fve install 3.22.2 --force
```

### `No release found for "X.Y.Z"`

The version does not exist in the Flutter releases API for your platform and architecture. Run `fve releases` to see available versions.

### `fve doctor` reports missing `pod`

CocoaPods is not installed. Install it:

```sh
sudo gem install cocoapods
```

---

## Contributing

Contributions are welcome. Please open an issue before submitting a pull request for significant changes so the approach can be discussed first.

**Development setup:**

```sh
git clone https://github.com/yourname/fve.git
cd fve
dart pub get
dart run bin/fve.dart --help
```

**Running the analyzer:**

```sh
dart analyze
```

**Running tests:**

```sh
dart test
```

**Project layout:**

```
bin/fve.dart                 Entry point
lib/
  fve.dart                   Library root (re-exports runner)
  src/
    runner.dart              CommandRunner setup
    help.dart                Help formatter (HelpFormatter, HelpArg, HelpExample)
    commands/
      base_command.dart      FveCommand base class
      install_command.dart
      use_command.dart
      global_command.dart
      list_command.dart
      releases_command.dart
      remove_command.dart
      current_command.dart
      flutter_command.dart
      dart_command.dart
      exec_command.dart
      doctor_command.dart
    models/
      flutter_release.dart   API response models
      project_config.dart    .fverc model
    services/
      cache_service.dart     ~/.fve/ directory management
      config_service.dart    Global config (config.json)
      download_service.dart  HTTP download, checksum, extraction
      releases_service.dart  Flutter releases API client
    utils/
      logger.dart            ANSI terminal output
      platform_utils.dart    Platform / architecture detection
```

---

## License

```
MIT License

Copyright (c) 2024 fve contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
