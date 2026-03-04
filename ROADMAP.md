# fve — Flutter Version & Environment Manager: Roadmap

---

## Phase 1: Foundation & CLI Setup

**Goal:** Working CLI skeleton with project structure

- [ ] Choose tech stack (recommend **Dart** or **Go** for easy binary distribution)
- [ ] Set up project structure and dependency management
- [ ] Implement CLI argument parsing framework
- [ ] Define configuration file schema (`.fverc` or `fve_config.json`)
- [ ] Set up logging and error handling
- [ ] Define storage paths (`~/.fve/versions/`, `~/.fve/cache/`, `~/.fve/pods/`)

---

## Phase 2: Flutter Version Management (FVM parity)

**Goal:** Full Flutter SDK version lifecycle management

- [ ] **`fve releases`** — Fetch available Flutter versions from Flutter releases API
- [ ] **`fve install <version>`** — Download and cache a specific Flutter SDK version
- [ ] **`fve use <version>`** — Set global or project-local Flutter version
- [ ] **`fve list`** — List installed versions
- [ ] **`fve remove <version>`** — Remove a cached SDK version
- [ ] **`fve current`** — Show active Flutter version
- [ ] **`fve exec <cmd>`** — Run a command with a specific Flutter version
- [ ] Symlink management for `flutter` and `dart` binaries
- [ ] Project-level config (reads `.fverc` from project root)
- [ ] Shell shim setup (`PATH` injection)

---

## Phase 3: Pod Cache Management (Core Innovation)

**Goal:** Isolate CocoaPods cache per Flutter version to eliminate conflicts

### The Problem

When switching Flutter versions, the iOS pod dependencies (`Flutter.framework`, engine artifacts, plugin versions) change — causing `pod install` failures or stale caches.

### Pod Cache Isolation Strategy

```
~/.fve/
  versions/
    3.19.0/   ← Flutter SDK
    3.22.1/   ← Flutter SDK
  pods/
    3.19.0/   ← CP_HOME_DIR for this version
      cache/
      repos/
    3.22.1/   ← CP_HOME_DIR for this version
```

When `fve use 3.22.1` is run in an iOS project, `fve` sets `CP_HOME_DIR=~/.fve/pods/3.22.1` before any pod commands, ensuring complete isolation.

### Tasks

- [ ] Understand the pod-flutter relationship:
  - Flutter engine artifacts (`Flutter.xcframework`) version-lock pod specs
  - Plugin pods depend on Flutter engine API compatibility
  - `Podfile.lock` becomes stale across Flutter versions
- [ ] Override `CP_HOME_DIR` env variable per version context
- [ ] Store `Podfile.lock` snapshots per version
- [ ] **`fve pod install`** — Run `pod install` in version-aware context
- [ ] **`fve pod cache list`** — List cached pod state per Flutter version
- [ ] **`fve pod cache clear <version>`** — Clear pod cache for a specific Flutter version
- [ ] **`fve pod restore`** — Restore pod cache when switching Flutter versions
- [ ] Auto-detect iOS projects and trigger pod cache switch on `fve use`
- [ ] Warn user if `Podfile.lock` is incompatible with current Flutter version

---

## Phase 4: Project Integration & DX

**Goal:** Seamless developer experience in real projects

- [ ] **`fve init`** — Initialize fve config in a Flutter project
- [ ] **`fve doctor`** — Diagnose version conflicts, missing pods, env issues
- [ ] **`fve spawn`** — Open a shell with the correct Flutter + pod env
- [ ] `.fverc` config file auto-detection (walk up directory tree)
- [ ] IDE integration hints (VS Code settings, Android Studio instructions)
- [ ] Git-friendly: `.fverc` committed, pod caches gitignored

---

## Phase 5: Advanced Features

- [ ] **Channel support** — `stable`, `beta`, `dev`, `master`
- [ ] **`fve global <version>`** — Set system-wide default
- [ ] **Pod lockfile diffing** — Show what pod versions changed between Flutter versions
- [ ] **Auto-switch** — Detect `.fverc` on `cd` via shell hook
- [ ] **`fve update`** — Self-update mechanism
- [ ] Support for **Melos** (monorepo) integration

---

## Phase 6: Distribution & Docs

- [ ] Homebrew formula (macOS)
- [ ] Install script (`curl | sh`)
- [ ] GitHub Releases with pre-built binaries
- [ ] README, CLI `--help` text, man page

---

## Known Problems & Challenges

A realistic look at what will be hard to build correctly.

---

### 1. Shell Environment Isolation (Hardest Problem)

`CP_HOME_DIR` and `PATH` are **process-level environment variables**. Setting them in one terminal does not affect another terminal. This means:

- Developer opens ProjectA in Terminal 1 (`fve use 3.18.0`) → env set correctly
- Developer opens ProjectB in Terminal 2 (`fve use 3.38.0`) → env set correctly
- **Both work fine in parallel because each shell process has its own env**

However, the problem appears when:
- The developer runs `pod install` directly **without going through `fve`** — the env is not set and falls back to the global `~/.cocoapods` cache, breaking isolation silently
- Xcode's build system runs `pod install` internally and does **not inherit the shell env** — so Xcode-triggered pod installs bypass `fve` entirely

**Solution:** Either provide a `fve pod install` wrapper that must be used instead of raw `pod install`, or inject `CP_HOME_DIR` into the Podfile itself via `fve init`.

---

### 2. `flutter clean` Destroys Pod State

`flutter clean` deletes:
- `ios/Pods/`
- `ios/.symlinks/`
- `ios/Flutter/`

This wipes the project-level pod install, forcing a full `pod install` again. Since `ios/Pods/` is gitignored by default, there is no recovery from the `fve` side.

**Impact:** The promise of "no reinstalling from scratch" partially breaks if the user or a CI script runs `flutter clean`.

**Solution:** Provide `fve clean` as a replacement that preserves `ios/Pods/` and warns the user. Document this clearly.

---

### 3. Podfile.lock Conflicts

`Podfile.lock` records exact pod versions and is committed to git. When switching Flutter versions:
- The locked pod versions may be incompatible with the new Flutter engine
- `pod install` will either fail or silently use wrong versions
- The developer may commit a `Podfile.lock` that works for their version but breaks teammates on a different version

**Solution:** `fve` must snapshot `Podfile.lock` per Flutter version and restore the correct one when switching. This is non-trivial — it means `fve` needs to manage a file that is traditionally owned by git.

---

### 4. First-Time Pod Install is Always Slow

The first `pod install` for each Flutter version must:
- Sync the CocoaPods spec repo (can be 500MB+)
- Download all pod source tarballs
- Compile native code

This takes 5–20 minutes depending on network and machine speed. There is no way around this for the first run. Users may think `fve` is broken.

**Solution:** Show clear progress output, explain what is happening, and store a flag indicating the cache is "warm" for that version so future runs are instant.

---

### 5. Flutter SDK Download Size & Reliability

Each Flutter SDK is 500MB–1GB+ compressed. Problems:
- Partial downloads leave corrupted caches
- Download URLs and archive formats change between Flutter versions (`.tar.xz`, `.zip`)
- The Flutter releases API structure has changed historically and can change again
- ARM64 (Apple Silicon) vs x86_64 binaries require different download URLs

**Solution:** Checksum verification after every download, atomic extraction (extract to temp dir then move), and architecture detection at install time.

---

### 6. CocoaPods Version Incompatibility

`CP_HOME_DIR` behavior and the pod cache directory structure have changed across CocoaPods versions. A cache built with CocoaPods 1.11 may not be fully compatible with CocoaPods 1.14.

**Solution:** Store the CocoaPods version alongside the pod cache metadata. Warn or re-initialize the cache if the CocoaPods version changes.

---

### 7. Xcode Does Not Inherit Shell Environment

When building from Xcode (not terminal), Xcode launches its own process tree that does not read `.zshrc` or `.bashrc`. This means:
- `CP_HOME_DIR` set by `fve` in your shell is invisible to Xcode
- Xcode-triggered `pod install` (via build phases) uses the default `~/.cocoapods`

**Solution:** The most reliable fix is writing `CP_HOME_DIR` directly into the project's `Podfile` during `fve use` or `fve init`, so it is hardcoded at the file level rather than depending on shell env.

```ruby
# Written by fve — do not edit manually
ENV['CP_HOME_DIR'] = File.expand_path('~/.fve/pods/3.38.0')
```

---

### 8. Auto-Switch on `cd` is Shell-Specific

Automatically switching Flutter version when entering a project directory (reading `.fverc`) requires hooking into the shell's `cd` command. This is different for every shell:
- `zsh` — `chpwd` hook
- `bash` — `PROMPT_COMMAND`
- `fish` — `--on-variable PWD`

Each shell needs its own integration code, tested separately. If the user uses a non-standard shell or a multiplexer like `tmux`, hooks may not fire correctly.

---

### 9. Concurrent Terminal Sessions with Different Versions

If the developer runs `pod install` in two terminals simultaneously — one for each project — both will try to write to their respective `CP_HOME_DIR` caches at the same time. CocoaPods does not use lock files for cache access.

**Risk:** Corrupted cache if the same pod happens to be downloaded in both sessions simultaneously (rare but possible).

**Solution:** Implement a file-based lock per `CP_HOME_DIR` before running pod commands.

---

### 10. Flutter Channel Versions vs Release Versions

Flutter versions can be:
- Exact releases: `3.19.0`, `3.38.0`
- Channel tips: `stable`, `beta`, `master`

Channel tips are moving targets — `stable` today is a different commit than `stable` tomorrow. Caching pod state against a channel name (not a commit hash) can silently become stale.

**Solution:** Resolve channel names to their current commit hash at install time and use the hash as the cache key, not the channel name.

---

### 11. Swift Package Manager Migration

Flutter is actively migrating from CocoaPods to **Swift Package Manager (SPM)**. Some plugins already support SPM only. In 1–2 years, CocoaPods may be fully deprecated in Flutter.

**Impact:** The pod cache isolation feature — the core innovation of `fve` — becomes less relevant over time.

**Solution:** Design the pod cache layer as a pluggable module. Plan for an `fve spm cache` equivalent using `SWIFTPM_CACHE_DIR` or similar, so the tool stays relevant after the CocoaPods era ends.

---

### 12. fve Itself Updating Can Break Existing Caches

When `fve` updates and changes its internal cache directory structure (e.g., renaming `~/.fve/pods/` to `~/.fve/pod-cache/`), all existing caches become orphaned and the user has to reinstall everything.

**Solution:** Store a `schema_version` in `~/.fve/meta.json` and run migration scripts on startup when the version changes. Never break existing cache layouts silently.

---

## Recommended Tech Stack

| Concern | Recommendation |
|---|---|
| Language | **Dart** (native, no runtime dep) or **Go** |
| CLI framework | `args` (Dart) or `cobra` (Go) |
| HTTP client | `http` (Dart) / `net/http` (Go) |
| Config format | JSON or TOML |
| Pod isolation | `CP_HOME_DIR` env var override |
