# Changelog

## 0.1.0

- Initial release
- `fve releases` — list available Flutter SDK versions
- `fve install <version>` — download and cache a Flutter SDK
- `fve use <version>` — set project-local Flutter version via `.fverc`
- `fve global <version>` — set system-wide default Flutter version
- `fve list` — list installed versions
- `fve remove <version>` — remove a cached version
- `fve current` — show active Flutter version (project + global)
- `fve flutter <args>` — run flutter with the project version
- `fve dart <args>` — run dart with the project version
- `fve exec -- <command>` — run any command inside the version environment
- `fve doctor` — diagnose environment issues
