# Changelog

All notable changes to fve are documented here.
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [0.2.0] — 2026-06-10

### CocoaPods / iOS isolation

- `fve pod install`/`update` now **self-heal a stale spec index**. CocoaPods can fail when the local spec index is older than the versions pinned in `Podfile.lock` (e.g. `could not find compatible versions for pod "X"` / `specs repository is too out-of-date`). fve detects this from the pod output and automatically retries once with `--repo-update`, after printing a warning. `--repo-update` only refreshes the spec index — pods already in the version-isolated cache are reused, nothing is re-downloaded wholesale.
- First-time pod cache creation for a version now runs the initial `pod install` with `--repo-update`, so a fresh cache never starts with an empty/missing spec index.
- New `fve pod install --repo-update` flag to force a spec-index refresh up front (escape hatch).
- Pod output is now tee'd (still live in the terminal, and captured for stale-index detection) instead of inherited directly.
- **`ios/Podfile.lock` snapshots per Flutter version.** `Podfile.lock` is committed and version-locked to the Flutter engine, so a lockfile that works on one version silently breaks teammates on another. `fve use` now snapshots the outgoing version's `Podfile.lock` and restores the incoming version's (the same save-on-leave / restore-on-enter mechanism already used for `pubspec.lock`).
- New **`fve pod restore`** — restores the pinned version's `Podfile.lock` snapshot, then runs `pod install`. (Resolves the previously-documented-but-unimplemented command.)
- `fve snapshots` now reports every tracked lockfile (`pubspec.lock` and `Podfile.lock`) per version.
- **Per-version pod cache lock.** `pod install`/`update`/`restore` now take an advisory lock keyed on the version's pod cache, so two simultaneous runs for the *same* Flutter version can't corrupt the shared cache (CocoaPods doesn't lock it itself). Different versions still run concurrently; stale locks from dead processes are reclaimed automatically.
- **Opt-in auto `pod install` on `fve use`.** Enable with `fve config --auto-pod-install`; when on, `fve use` runs `pod install` for iOS projects after switching (reusing stale-index auto-heal). Off by default; failures are non-fatal to `use`.
- New **`fve pod diff <version-a> <version-b>`** — compares the `Podfile.lock` snapshots of two Flutter versions and shows which pods were added/removed/changed.
- New **`fve clean`** — a pod-preserving project clean: removes build artifacts (`build/`, `.dart_tool/`, `.flutter-plugins*`) but keeps `ios/Pods` and `ios/.symlinks` so the next build skips a full `pod install`. `fve clean --pods` removes those too.
- `fve doctor` now warns when `ios/Podfile.lock` was generated with a different CocoaPods version than the one currently installed.

## [0.1.0] — 2026-03-04

Initial public release.

### Version management

- `fve releases` — browse Flutter SDK versions with interactive arrow-key pagination; filters by channel (stable/beta/dev/any)
- `fve install <version>` — install a Flutter SDK via shallow git clone (~200 MB) or archive fallback (`--no-git`); `fve install` (no args) reads `.fverc`
- `fve use <version>` — pin a version in the current project (`.fverc`), auto-runs `flutter pub get`, auto-updates `.vscode/settings.json`
- `fve global <version>` — set the global Flutter version (symlink at `~/.fve/current`); `--unlink` removes the symlink
- `fve list` — show all locally installed Flutter versions with install date and size
- `fve remove <version>` — delete a cached Flutter SDK; `--all` removes every version
- `fve current` — print the active Flutter version for the current directory
- `fve spawn <version> -- <command>` — run any command with a specific Flutter version without changing the project pin

### Pass-through commands

- `fve flutter <args>` — run `flutter` with the project-pinned (or global) version
- `fve dart <args>` — run `dart` with the project-pinned (or global) version
- `fve exec -- <command>` — run any arbitrary command with fve-managed Flutter on PATH

### CocoaPods / iOS isolation

- `fve pod install` — run `pod install` with `CP_HOME_DIR` set to `~/.fve/pods/<version>/`
- `fve pod cache list` — list pod caches per Flutter version
- `fve pod cache clear [version]` — remove cached pods for a version (or all versions)
- `fve pod restore` — re-run `pod install` after switching Flutter versions
- `fve use` automatically injects the fve block into `ios/Podfile` to set `CP_HOME_DIR` at CocoaPods runtime

### Tooling

- `fve doctor` — full environment health check; exits 1 when critical issues are found (PATH not set, version not installed, Podfile injection mismatch)
- `fve setup` — show or auto-write the PATH export for your shell (`--write` flag)
- `fve config` — get/set fve preferences (`vscode_integration`, `auto_pub_get`)
- `fve api` — JSON output for scripting: `context`, `list`, `project`, `releases`

### Distribution

- Pre-built binaries for macOS arm64, macOS x64, Linux x64 (via GitHub Actions)
- One-line install: `curl -fsSL https://assylman.github.io/fve/install.sh | bash`
- GitHub Actions release workflow: builds and publishes binaries on `v*` tag push

[0.2.0]: https://github.com/assylman/fve/releases/tag/v0.2.0
[0.1.0]: https://github.com/assylman/fve/releases/tag/v0.1.0
