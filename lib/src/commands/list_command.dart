import 'dart:io';

import '../help.dart';
import '../models/flutter_release.dart';
import '../models/project_config.dart';
import '../services/cache_service.dart';
import '../services/releases_service.dart';
import '../utils/logger.dart';
import 'base_command.dart';

// Minimum width reserved for the version + tag column before the size column.
const _minTagWidth = 28;

/// Shows all locally installed Flutter SDK versions and marks which one is
/// active globally and/or pinned in the current project.
class ListCommand extends FveCommand {
  @override
  String get name => 'list';

  @override
  String get description => 'Show locally installed Flutter SDK versions.';

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('list', 'Show all installed versions with global / project markers'),
        HelpExample('list --remote', 'Show all versions available for download'),
        HelpExample('releases', 'Browse all versions available for download (interactive)'),
      ];

  ListCommand() {
    argParser
      ..addFlag(
        'remote',
        abbr: 'r',
        help: 'Show all Flutter versions available for download from storage.googleapis.com.',
        negatable: false,
      )
      ..addOption(
        'channel',
        abbr: 'c',
        help: 'Filter remote versions by channel (used with --remote).',
        allowed: ['stable', 'beta', 'dev', 'any'],
        defaultsTo: 'stable',
      );
  }

  @override
  Future<void> run() async {
    final remote = argResults!['remote'] as bool;
    if (remote) {
      await _listRemote();
      return;
    }
    await _listLocal();
  }

  // ── Remote listing ─────────────────────────────────────────────────────────

  Future<void> _listRemote() async {
    final channel = argResults!['channel'] as String;
    Logger.info('Fetching Flutter releases…');

    late FlutterReleasesResponse resp;
    try {
      resp = await ReleasesService().fetchReleases();
    } catch (e) {
      Logger.error('Could not fetch releases: $e');
      Logger.dim('Check your network connection and try again.');
      exit(1);
    }

    final seen = <String>{};
    final releases = resp.releases
        .where((r) => channel == 'any' || r.channel == channel)
        .where((r) => seen.add(r.version))
        .toList();

    if (releases.isEmpty) {
      Logger.warning('No releases found for channel "$channel".');
      return;
    }

    final installed = Set<String>.from(CacheService().installedVersions());

    Logger.header('Flutter releases (channel: $channel · ${releases.length} total)');
    for (final r in releases) {
      final date = r.releaseDate.toLocal().toString().substring(0, 10);
      final dart = 'dart ${r.dartSdkVersion}';
      final mark = installed.contains(r.version) ? '●' : ' ';
      Logger.plain('  $mark ${r.version.padRight(12)} $dart  $date');
    }
    Logger.plain('');
    Logger.dim('${releases.length} version(s) available. Install with: fve install <version>');
    Logger.dim('Use --channel beta/dev/any to see more versions.');
  }

  // ── Local listing ──────────────────────────────────────────────────────────

  Future<void> _listLocal() async {
    final cache = CacheService();
    final versions = cache.installedVersions();

    if (versions.isEmpty) {
      Logger.warning('No Flutter versions installed.');
      Logger.dim('Install one  : fve install <version>');
      Logger.dim('Browse all   : fve releases');
      return;
    }

    final globalVersion = cache.currentGlobalVersion();
    final projectVersion = ProjectConfig.findForDirectory('.')?.flutterVersion;
    final sizes = cache.versionSizesKb(versions);

    Logger.header('Installed Flutter versions');

    // Pre-compute tag labels to align size column.
    final labels = <String, String>{};
    for (final v in versions) {
      final isGlobal = v == globalVersion;
      final isProject = v == projectVersion;
      final tags = [
        if (isGlobal) 'global',
        if (isProject) 'project',
      ].join(', ');
      labels[v] = tags.isNotEmpty ? '  ← $tags' : '';
    }

    final colWidth = versions
        .map((v) => ('  ● $v${labels[v]}').length)
        .fold(_minTagWidth, (a, b) => a > b ? a : b);

    for (final v in versions) {
      final isGlobal = v == globalVersion;
      final isProject = v == projectVersion;
      final marker = (isProject || isGlobal) ? '●' : ' ';
      final left = '  $marker $v${labels[v]}';
      final kb = sizes[v];
      final sizeLabel = kb != null ? formatSizeKb(kb) : '';
      final line = sizeLabel.isNotEmpty
          ? '${left.padRight(colWidth)}  $sizeLabel'
          : left;
      Logger.plain(line);
    }

    final totalKb = sizes.values.fold(0, (a, b) => a + b);
    final totalLabel = totalKb > 0 ? ' · ${formatSizeKb(totalKb)} total' : '';
    Logger.plain('');
    Logger.dim('${versions.length} version(s) installed$totalLabel.');
    Logger.dim('Browse available versions: fve releases');
  }
}
