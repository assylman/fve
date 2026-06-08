import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../help.dart';
import '../runner.dart';
import '../utils/logger.dart';
import 'base_command.dart';

/// Self-updates fve by downloading the latest binary from GitHub Releases.
///
/// SDKs, caches, and config files are never touched during upgrade (12.2, 12.3).
class UpgradeCommand extends FveCommand {
  final http.Client _client;

  UpgradeCommand({http.Client? client}) : _client = client ?? http.Client() {
    argParser.addFlag(
      'check',
      help: 'Only check for updates; do not install.',
      negatable: false,
    );
  }

  @override
  String get name => 'upgrade';

  @override
  String get description => 'Upgrade fve to the latest version.';

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('upgrade', 'Download and install the latest fve release'),
        HelpExample('upgrade --check', 'Check if a newer version is available without installing'),
      ];

  static const _githubApiUrl =
      'https://api.github.com/repos/assylman/fve/releases/latest';

  @override
  Future<void> run() async {
    final checkOnly = argResults!['check'] as bool;

    Logger.bold('\nfve upgrade');
    Logger.plain('');
    Logger.dim('  Current version: $kFveVersion');

    // ── Fetch latest release info ────────────────────────────────────────────
    late Map<String, dynamic> releaseJson;
    try {
      final response = await _client.get(
        Uri.parse(_githubApiUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      );
      if (response.statusCode == 404) {
        Logger.warning('No releases found on GitHub yet.');
        return;
      }
      if (response.statusCode != 200) {
        Logger.error('GitHub API error (HTTP ${response.statusCode}).');
        exit(1);
      }
      releaseJson = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      Logger.error('Could not reach GitHub: $e');
      Logger.dim('Check your network connection and try again.');
      exit(1);
    }

    final latestTag = (releaseJson['tag_name'] as String?)?.replaceFirst('v', '') ?? '';
    Logger.dim('  Latest  version: $latestTag');
    Logger.plain('');

    if (latestTag.isEmpty) {
      Logger.warning('Could not determine latest version.');
      return;
    }

    if (latestTag == kFveVersion) {
      Logger.success('fve is already up to date ($kFveVersion).');
      return;
    }

    if (checkOnly) {
      Logger.info('A new version is available: $latestTag');
      Logger.dim('  Run `fve upgrade` to install it.');
      return;
    }

    // ── Find the right asset for this platform ───────────────────────────────
    final assets = (releaseJson['assets'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    final platformSuffix = _platformSuffix();
    final asset = assets.firstWhere(
      (a) => (a['name'] as String).contains(platformSuffix),
      orElse: () => <String, dynamic>{},
    );

    if (asset.isEmpty) {
      Logger.warning(
        'No pre-built binary found for this platform ($platformSuffix).\n'
        '  Install manually from: https://github.com/assylman/fve/releases',
      );
      return;
    }

    final downloadUrl = asset['browser_download_url'] as String;
    final binaryPath = Platform.resolvedExecutable;

    // Guard: only replace the binary when we are genuinely running from the
    // compiled `fve` executable. Under `dart run bin/fve.dart` (development,
    // tests) Platform.resolvedExecutable is the Dart launcher — overwriting it
    // would corrupt the user's Dart/Flutter SDK.
    if (p.basename(binaryPath) != 'fve') {
      Logger.warning(
        'Refusing to self-upgrade: fve is running via '
        '"${p.basename(binaryPath)}", not the installed fve binary.',
      );
      Logger.dim('  A new version ($latestTag) is available. Install it from:');
      Logger.dim('  https://github.com/assylman/fve/releases');
      return;
    }

    Logger.info('Downloading fve $latestTag…');

    final tempFile = File('${binaryPath}_fve_upgrade_tmp');
    try {
      final response = await _client.get(Uri.parse(downloadUrl));
      if (response.statusCode != 200) {
        Logger.error('Download failed (HTTP ${response.statusCode}).');
        exit(1);
      }
      tempFile.writeAsBytesSync(response.bodyBytes);

      // Make executable and replace in-place.
      if (!Platform.isWindows) {
        Process.runSync('chmod', ['+x', tempFile.path]);
      }
      tempFile.renameSync(binaryPath);

      Logger.success('fve upgraded to $latestTag');
      Logger.dim('  Binary: $binaryPath');
      Logger.plain('');
      Logger.dim('  Your Flutter SDKs, caches, and config are unchanged.');
    } catch (e) {
      if (tempFile.existsSync()) tempFile.deleteSync();
      Logger.error('Upgrade failed: $e');
      Logger.dim('  Try manually: https://github.com/assylman/fve/releases');
      exit(1);
    }
  }

  static String _platformSuffix() {
    if (Platform.isMacOS) {
      // Check for Apple Silicon.
      final r = Process.runSync('uname', ['-m']);
      final arch = (r.stdout as String).trim();
      return arch == 'arm64' ? 'macos-arm64' : 'macos-x64';
    }
    if (Platform.isLinux) return 'linux-x64';
    if (Platform.isWindows) return 'windows-x64';
    return 'unknown';
  }
}
