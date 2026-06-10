# fve — Flutter Version & Environment Manager

> Install, switch, and manage multiple Flutter SDK versions with per-project pinning and isolated CocoaPods caches.

**[Full documentation →](https://assylman.github.io/fve)**

---

## Why fve?

Flutter teams constantly juggle SDK versions. One project runs `3.19.0`, another needs `3.24.0`, a third is pinned to a beta build for a specific engine fix. Without tooling this means manually reinstalling Flutter, updating `PATH` by hand, or silently breaking a teammate's environment with a global upgrade.

**On iOS it gets significantly worse.** Every time you switch Flutter versions, CocoaPods detects a different Flutter engine and invalidates its cache. The only fix is:

```sh
pod cache clean --all   # wipes everything
pod install             # rebuilds from scratch — can take 10–30+ minutes
```

This happens on every context-switch between Flutter versions. On large projects with many native dependencies that rebuild alone costs half an hour of lost time, per developer, per switch.

**fve solves both problems:**

- **Per-project version pinning** — a `.fverc` file in your repo pins every developer and CI machine to the exact same Flutter version automatically. No manual PATH changes. No "works on my machine."
- **Isolated CocoaPods caches** — each Flutter version gets its own pod cache (`~/.fve/pods/<version>/`). Switching versions reuses the existing cache for that version instantly. No clean, no rebuild.
- **Self-healing spec index** — when `pod install` fails because the CocoaPods spec index is out of date (`could not find compatible versions for pod …`), fve detects it and automatically retries once with `--repo-update`. Only the missing/changed pods are fetched; cached pods are reused. Force it up front with `fve pod install --repo-update`.
- **Per-version lockfile snapshots** — `fve use` snapshots both `pubspec.lock` and `ios/Podfile.lock` per Flutter version and restores them on switch, so each version keeps its own working dependency resolution. `fve pod restore` re-applies the pinned version's `Podfile.lock` and reinstalls. `fve pod diff <a> <b>` shows which pods changed between two versions.
- **Pod-preserving clean** — `fve clean` removes build artifacts but keeps `ios/Pods` (no full `pod install` next build); `fve clean --pods` removes those too.
- **Zero global side effects** — your system Flutter installation is never touched. All SDKs live in `~/.fve/versions/` and activate per-directory.

---

## Install

```sh
curl -sSL https://assylman.github.io/fve/install.sh | sh
```

Then add to your `~/.zshrc` or `~/.bashrc`:

```sh
export PATH="$HOME/.fve/current/bin:$PATH"
```

## Quick Start

```sh
fve releases          # browse available Flutter versions
fve install 3.22.2    # download and cache a version
fve use 3.22.2        # pin your project + run pub get
fve flutter run       # run Flutter via the pinned version
```

## Commands

| Command | Description |
|---|---|
| `fve install <version>` | Download and cache a Flutter SDK |
| `fve use <version>` | Pin the current project to a version |
| `fve global <version>` | Set the system-wide default |
| `fve list` | Show installed versions |
| `fve releases` | Browse available versions |
| `fve current` | Show active version |
| `fve remove <version>` | Delete a cached SDK |
| `fve flutter [args]` | Run flutter with the pinned version |
| `fve dart [args]` | Run dart with the pinned version |
| `fve exec -- <cmd>` | Run any command in the version environment |
| `fve pod install\|update` | CocoaPods with isolated cache |
| `fve doctor` | Check your setup |
| `fve setup` | Configure shell PATH |

## How it works

- Each SDK is cached once in `~/.fve/versions/<version>/`
- A `.fverc` file in your project root pins the version — commit it
- `fve use` also injects a CI-safe pod cache block into `ios/Podfile`
- `~/.fve/current` symlink points to the global default

## Platform Support

macOS (Apple Silicon / Intel) · Linux (x64 / arm64)

## License

MIT
