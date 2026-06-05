/// Validates Flutter version identifiers before they are used as filesystem
/// path segments (`~/.fve/versions/<version>`, `~/.fve/pods/<version>`,
/// snapshot dirs) or interpolated into generated Podfile Ruby.
///
/// Without validation, an attacker-controlled `.fverc`, `FVE_FLUTTER_VERSION`,
/// or CLI argument could supply a value such as `../../etc` (path traversal)
/// or `'); system('rm -rf /` (Ruby code injection in the Podfile block).
class VersionValidator {
  /// Channel names accepted by the Flutter tool.
  static const channels = {'stable', 'beta', 'dev', 'master', 'main'};

  /// Semantic version with optional pre-release / build metadata, e.g.
  /// `3.24.0`, `3.24.0-1.0.pre`, `2.0.1+hotfix.1`.
  static final _semver = RegExp(r'^\d+\.\d+\.\d+([-+][0-9A-Za-z.+-]+)?$');

  /// Returns true when [version] is a recognised channel or semantic version.
  static bool isValid(String version) =>
      channels.contains(version) || _semver.hasMatch(version);

  /// Returns [version] unchanged when valid, otherwise throws a
  /// [FormatException] with a remediation hint.
  static String check(String version) {
    if (!isValid(version)) {
      throw FormatException(
        'Invalid Flutter version "$version". Expected a semantic version '
        '(e.g. 3.24.0) or a channel (${channels.join(', ')}).',
      );
    }
    return version;
  }
}
