import 'dart:io';

import 'package:path/path.dart' as p;

import '../help.dart';
import '../models/flutter_release.dart';
import '../services/cache_service.dart';
import '../services/download_service.dart';
import '../services/releases_service.dart';
import '../utils/logger.dart';
import '../utils/tui.dart';
import 'base_command.dart';

class InstallCommand extends FveCommand {
  @override
  String get name => 'install';

  @override
  String get description => 'Download and cache a Flutter SDK version.';

  @override
  String get argSyntax => '<version>';

  @override
  List<HelpArg> get helpArguments => const [
        HelpArg(
          '<version>',
          'Version number (e.g. 3.22.2) or channel name (stable, beta, dev)',
        ),
      ];

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('install 3.22.2', 'Install a specific version (git clone, ~200 MB)'),
        HelpExample('install stable', 'Install the latest stable release'),
        HelpExample('install beta', 'Install the latest beta release'),
        HelpExample('install 3.22.2 --force', 'Force re-install if already cached'),
        HelpExample('install 3.22.2 --no-git', 'Force archive download (~1 GB) instead of git'),
      ];

  InstallCommand() {
    argParser
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Re-install even if the version is already cached.',
        negatable: false,
      )
      ..addFlag(
        'no-git',
        help: 'Download the pre-built archive instead of using git clone.\n'
            'Use this when git is unavailable, a version has no git tag,\n'
            'or you need a byte-identical binary to the official release.',
        negatable: false,
      );
  }

  @override
  Future<void> run() async {
    if (argResults!.rest.isEmpty) {
      usageException(
        'Please provide a version number or channel name.\n'
        'Example: fve install 3.22.2',
      );
    }

    final versionArg = argResults!.rest.first;
    final force = argResults!['force'] as bool;
    final noGit = argResults!['no-git'] as bool;
    final cache = CacheService()..ensureDirectoriesExist();

    // Resolve the actual release metadata (also validates the version exists).
    final resolveSpinner = Spinner('Resolving "$versionArg"');
    resolveSpinner.start();
    final release = await ReleasesService().findRelease(versionArg);
    resolveSpinner.stop();

    if (release == null) {
      Logger.error('No release found for "$versionArg".');
      Logger.dim('Run `fve releases` to see available versions.');
      return;
    }

    final version = release.version;
    final destDir = cache.versionDir(version);

    // ── Guard: already fully installed ──────────────────────────────────────
    if (!force && cache.isInstalled(version)) {
      Logger.success('Flutter $version is already installed.');
      Logger.dim('Use --force to re-install.');
      return;
    }

    // ── Guard: incomplete installation (interrupted previous attempt) ────────
    // The directory exists but the flutter binary is missing, meaning a
    // previous clone or extraction was interrupted. For git-based installs,
    // installViaGit() handles the resume internally. For archive installs,
    // clean up so extractSdk() gets a clean target directory.
    if (cache.isVersionDirPresent(version) && !cache.isInstalled(version)) {
      if (noGit) {
        Logger.warning('Incomplete installation found — cleaning up…');
        cache.deleteVersion(version);
      }
      // Git path: installViaGit() detects and resumes from the partial .git
      // directory automatically — no manual cleanup needed here.
    }

    // ── Guard: force re-install of a complete installation ───────────────────
    if (force && cache.isInstalled(version)) {
      Logger.dim('  Removing existing installation…');
      cache.deleteVersion(version);
    }

    Logger.bold('\nInstalling Flutter $version…');
    Logger.dim('  channel : ${release.channel}');
    Logger.dim('  arch    : ${release.dartSdkArch}');
    Logger.dim('  dart    : ${release.dartSdkVersion}');
    print('');

    final downloader = DownloadService();

    if (!noGit && await DownloadService.gitAvailable()) {
      await _installViaGit(downloader, version, destDir);
    } else {
      if (!noGit) {
        // git was requested but is not available on this machine.
        Logger.warning('git not found — falling back to pre-built archive (≈1 GB).');
        Logger.dim('  Tip: install git for ~200 MB installs (brew install git).');
        print('');
      }
      await _installViaArchive(downloader, release, destDir);
    }
  }

  // ── Git install ──────────────────────────────────────────────────────────

  Future<void> _installViaGit(
    DownloadService downloader,
    String version,
    String destDir,
  ) async {
    await downloader.installViaGit(version, destDir);

    Logger.success('Flutter $version installed at $destDir');
    print('');
    Logger.dim(
      '  The first `fve flutter` / `fve dart` invocation will fetch',
    );
    Logger.dim(
      '  engine binaries (~400 MB). This is a one-time download per version.',
    );
    Logger.warning(
      '  Do NOT run `flutter upgrade` inside a managed version —\n'
      '  use `fve install <new-version>` instead.',
    );
    print('');
    _printNextSteps(version);
  }

  // ── Archive install ──────────────────────────────────────────────────────

  Future<void> _installViaArchive(
    DownloadService downloader,
    FlutterRelease release,
    String destDir,
  ) async {
    final archiveName = p.basename(release.archive);
    final tempDir = Directory.systemTemp.createTempSync('fve_');
    final archivePath = p.join(tempDir.path, archiveName);
    final url =
        'https://storage.googleapis.com/flutter_infra_release/releases/${release.archive}';

    try {
      await downloader.download(url, archivePath);

      final checksumSpinner = Spinner('Verifying checksum');
      checksumSpinner.start();
      await downloader.verifySha256(archivePath, release.sha256);
      checksumSpinner.stop(done: 'Checksum OK');

      final extractSpinner = Spinner('Extracting SDK');
      extractSpinner.start();
      await downloader.extractSdk(archivePath, destDir);
      extractSpinner.stop(done: 'Flutter ${release.version} installed at $destDir');
      print('');
      _printNextSteps(release.version);
    } finally {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    }
  }

  // ── Shared ───────────────────────────────────────────────────────────────

  void _printNextSteps(String version) {
    Logger.dim('Set as project version : fve use $version');
    Logger.dim('Set as global default  : fve global $version');
  }
}
