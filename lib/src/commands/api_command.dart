import 'dart:convert';
import 'dart:io';

import '../help.dart';
import '../models/flutter_release.dart';
import '../models/project_config.dart';
import '../services/cache_service.dart';
import '../services/releases_service.dart';
import 'base_command.dart';

// ── Root api command ──────────────────────────────────────────────────────────

class ApiCommand extends FveCommand {
  @override
  String get name => 'api';

  @override
  String get description =>
      'Output machine-readable JSON for IDE plugin and script integration.';

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('api context', 'Active version info as JSON'),
        HelpExample('api list', 'Installed versions as JSON'),
        HelpExample('api project', 'Current project .fverc as JSON'),
        HelpExample('api releases', 'Available releases from the Flutter API as JSON'),
      ];

  ApiCommand() {
    addSubcommand(_ApiContextCommand());
    addSubcommand(_ApiListCommand());
    addSubcommand(_ApiProjectCommand());
    addSubcommand(_ApiReleasesCommand());
  }
}

// ── api context ───────────────────────────────────────────────────────────────

class _ApiContextCommand extends FveCommand {
  @override
  String get name => 'context';

  @override
  String get description =>
      'Print the active Flutter version context as JSON.';

  @override
  Future<void> run() async {
    final cache = CacheService();

    final projectConfig = ProjectConfig.findForDirectory('.');
    final projectVersion = projectConfig?.flutterVersion;
    final configPath = ProjectConfig.configPathForDirectory('.');
    final globalVersion = cache.currentGlobalVersion();
    final activeVersion = projectVersion ?? globalVersion;
    final activeSource = projectVersion != null
        ? 'project'
        : (globalVersion != null ? 'global' : null);

    _printJson({
      'project': projectVersion != null
          ? {'version': projectVersion, 'configPath': configPath}
          : null,
      'global': globalVersion != null
          ? {
              'version': globalVersion,
              'sdkPath': cache.versionDir(globalVersion),
            }
          : null,
      'active': activeVersion,
      'activeSource': activeSource,
    });
  }
}

// ── api list ──────────────────────────────────────────────────────────────────

class _ApiListCommand extends FveCommand {
  @override
  String get name => 'list';

  @override
  String get description => 'Print all locally installed Flutter versions as JSON.';

  @override
  Future<void> run() async {
    final cache = CacheService();
    final versions = cache.installedVersions();
    final globalVersion = cache.currentGlobalVersion();
    final projectVersion =
        ProjectConfig.findForDirectory('.')?.flutterVersion;

    _printJson(
      versions
          .map(
            (v) => {
              'version': v,
              'sdkPath': cache.versionDir(v),
              'dartBin': cache.dartBin(v),
              'flutterBin': cache.flutterBin(v),
              'isGlobal': v == globalVersion,
              'isProject': v == projectVersion,
            },
          )
          .toList(),
    );
  }
}

// ── api project ───────────────────────────────────────────────────────────────

class _ApiProjectCommand extends FveCommand {
  @override
  String get name => 'project';

  @override
  String get description =>
      'Print the nearest .fverc project configuration as JSON, or null if not found.';

  @override
  Future<void> run() async {
    final config = ProjectConfig.findForDirectory('.');
    final configPath = ProjectConfig.configPathForDirectory('.');

    if (config == null) {
      _printJson(null);
      return;
    }

    final cache = CacheService();
    final version = config.flutterVersion;

    _printJson({
      'flutterVersion': version,
      'configPath': configPath,
      'sdkPath': cache.versionDir(version),
      'isInstalled': cache.isInstalled(version),
    });
  }
}

// ── api releases ──────────────────────────────────────────────────────────────

class _ApiReleasesCommand extends FveCommand {
  @override
  String get name => 'releases';

  @override
  String get description =>
      'Print available Flutter releases from the releases API as JSON.';

  _ApiReleasesCommand() {
    argParser
      ..addOption(
        'channel',
        abbr: 'c',
        help: 'Filter by channel.',
        allowed: ['stable', 'beta', 'dev', 'any'],
        defaultsTo: 'stable',
      )
      ..addOption(
        'limit',
        abbr: 'n',
        help: 'Maximum number of releases to return.',
        defaultsTo: '20',
      );
  }

  @override
  Future<void> run() async {
    final channel = argResults!['channel'] as String;
    final limit = int.tryParse(argResults!['limit'] as String) ?? 20;

    late FlutterReleasesResponse resp;
    try {
      resp = await ReleasesService().fetchReleases();
    } catch (e) {
      stderr.writeln(jsonEncode({'error': e.toString()}));
      exit(1);
    }

    final seen = <String>{};
    final releases = resp.releases
        .where((r) => channel == 'any' || r.channel == channel)
        .where((r) => seen.add(r.version))
        .take(limit)
        .map(
          (r) => {
            'version': r.version,
            'channel': r.channel,
            'dartSdkVersion': r.dartSdkVersion,
            'dartSdkArch': r.dartSdkArch,
            'releaseDate': r.releaseDate.toIso8601String(),
            'hash': r.hash,
          },
        )
        .toList();

    _printJson({
      'channel': channel,
      'limit': limit,
      'count': releases.length,
      'releases': releases,
    });
  }
}

// ── Shared helper ─────────────────────────────────────────────────────────────

void _printJson(Object? value) {
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(value));
}
