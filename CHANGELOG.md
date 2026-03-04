# Changelog

All notable changes to fve are documented here.
Versioning follows [Semantic Versioning](https://semver.org/).

---

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

[0.1.0]: https://github.com/assylman/fve/releases/tag/v0.1.0
