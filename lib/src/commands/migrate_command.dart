import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../help.dart';
import '../services/compat_service.dart';
import '../utils/logger.dart';
import 'base_command.dart';

/// Suggests dependency version bumps needed to be compatible with a target
/// Flutter version (3.2.x).
class MigrateCommand extends FveCommand {
  @override
  String get name => 'migrate';

  @override
  String get description =>
      'Show package version bumps needed to be compatible with a Flutter version.';

  @override
  String get argSyntax => '<flutter-version>';

  @override
  List<HelpArg> get helpArguments => const [
        HelpArg('<flutter-version>', 'Target Flutter version to migrate towards'),
      ];

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('migrate 3.24.0', 'Show upgrades needed for Flutter 3.24.0'),
      ];

  @override
  Future<void> run() async {
    if (argResults!.rest.isEmpty) {
      usageException('Please provide a Flutter version.\nExample: fve migrate 3.24.0');
    }

    final targetVersion = argResults!.rest.first;
    final cwd = Directory.current.path;

    final pubspec = File(p.join(cwd, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      Logger.error('No pubspec.yaml found. Run from a Flutter project root.');
      exit(1);
    }

    Logger.info('Checking compatibility with Flutter $targetVersion…');

    final incompatible =
        await CompatService().check(cwd, targetVersion, force: false);

    if (incompatible.isEmpty) {
      Logger.success('All dependencies are compatible with Flutter $targetVersion.');
      return;
    }

    Logger.header('Migration suggestions → Flutter $targetVersion');

    for (final r in incompatible) {
      Logger.plain('  ✗ ${r.package}');
      Logger.dim('    Current constraint : ${r.constraint}');
      Logger.dim('    Issue              : ${r.reason}');

      // Fetch latest version from pub.dev as a migration target.
      final latestVersion = await _fetchLatestVersion(r.package);
      if (latestVersion != null) {
        Logger.plain('    Suggested upgrade  : ^$latestVersion');
      } else {
        Logger.dim('    (could not fetch latest version from pub.dev)');
      }
      Logger.plain('');
    }

    Logger.dim('Apply: update pubspec.yaml then run flutter pub get');
  }

  Future<String?> _fetchLatestVersion(String package) async {
    try {
      final response = await http
          .get(Uri.parse('https://pub.dev/api/packages/$package'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return (json['latest'] as Map<String, dynamic>?)?['version'] as String?;
    } catch (_) {
      return null;
    }
  }
}
