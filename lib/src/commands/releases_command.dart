import 'dart:io' show exit, stdin, stdout;

import '../help.dart';
import '../models/flutter_release.dart';
import '../services/cache_service.dart';
import '../services/releases_service.dart';
import '../utils/logger.dart';
import 'base_command.dart';

enum _NavKey { right, left, quit, other }

/// Browses Flutter SDK versions available for download with interactive
/// left/right arrow-key pagination.
class ReleasesCommand extends FveCommand {
  @override
  String get name => 'releases';

  @override
  String get description =>
      'Browse Flutter SDK versions available for download (← → to page).';

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('releases', 'Browse stable releases 20 at a time'),
        HelpExample('releases --channel beta', 'Browse beta channel'),
        HelpExample('releases --channel any', 'Browse all channels'),
        HelpExample('releases -n 10', 'Show 10 versions per page'),
      ];

  ReleasesCommand() {
    argParser
      ..addOption(
        'channel',
        abbr: 'c',
        help: 'Filter by channel.',
        allowed: ['stable', 'beta', 'dev', 'any'],
        defaultsTo: 'stable',
      )
      ..addOption(
        'page-size',
        abbr: 'n',
        help: 'Number of versions to display per page.',
        defaultsTo: '20',
      );
  }

  @override
  Future<void> run() async {
    final channel = argResults!['channel'] as String;
    final pageSize = int.tryParse(argResults!['page-size'] as String) ?? 20;

    Logger.info('Fetching Flutter releases…');

    late FlutterReleasesResponse resp;
    try {
      resp = await ReleasesService().fetchReleases();
    } catch (e) {
      Logger.error('Could not fetch releases: $e');
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
    final totalPages = (releases.length / pageSize).ceil();

    // Static header — printed once, never cleared during navigation.
    Logger.header(
      'Flutter releases  (channel: $channel · ${releases.length} total)',
    );

    final isInteractive = stdout.hasTerminal && stdout.supportsAnsiEscapes;

    if (!isInteractive || totalPages == 1) {
      // Non-interactive (piped output or single page): just print and exit.
      _printPage(releases, installed, 0, pageSize, totalPages,
          interactive: false);
      return;
    }

    // ── Interactive arrow-key pagination ─────────────────────────────────────

    stdin.echoMode = false;
    stdin.lineMode = false;

    var page = 0;
    var linesDrawn = 0;

    try {
      linesDrawn = _printPage(releases, installed, page, pageSize, totalPages,
          interactive: true);

      while (true) {
        final key = _readKey();

        if (key == _NavKey.quit) break;

        final newPage = switch (key) {
          _NavKey.right => (page + 1).clamp(0, totalPages - 1),
          _NavKey.left => (page - 1).clamp(0, totalPages - 1),
          _ => page,
        };

        if (newPage == page) continue; // already at first/last page

        _clearLines(linesDrawn);
        page = newPage;
        linesDrawn = _printPage(releases, installed, page, pageSize, totalPages,
            interactive: true);
      }
    } finally {
      stdin.echoMode = true;
      stdin.lineMode = true;
    }
  }

  // ── Page rendering ────────────────────────────────────────────────────────

  /// Prints one page of releases and returns the exact number of lines written.
  /// The return value is used by [_clearLines] to erase the page on navigation.
  int _printPage(
    List<FlutterRelease> releases,
    Set<String> installed,
    int page,
    int pageSize,
    int totalPages, {
    required bool interactive,
  }) {
    final start = page * pageSize;
    final end = (start + pageSize).clamp(0, releases.length);
    final slice = releases.sublist(start, end);

    var lines = 0;

    for (final r in slice) {
      _printRelease(r, installed.contains(r.version));
      lines++;
    }

    // Blank separator line.
    stdout.writeln();
    lines++;

    if (interactive) {
      // Navigation bar: ← grayed-out on first page, → grayed-out on last page.
      final atFirst = page == 0;
      final atLast = page == totalPages - 1;

      final leftArrow = atFirst ? _dim('←') : _bright('←');
      final rightArrow = atLast ? _dim('→') : _bright('→');
      final pageLabel = _dim('page ${page + 1} / $totalPages');
      final qHint = _dim('[q] quit');

      stdout.writeln(
        '  $leftArrow   $pageLabel   $rightArrow      $qHint',
      );
      lines++;
    } else {
      Logger.dim('  Showing ${slice.length} of ${releases.length} versions.');
      Logger.dim('  Install with: fve install <version>');
    }

    return lines;
  }

  void _printRelease(FlutterRelease r, bool isInstalled) {
    final arch = r.isArm64 ? 'arm64' : 'x64 ';
    final date = r.releaseDate.toLocal().toString().substring(0, 10);
    final dart = 'dart ${r.dartSdkVersion}'.padRight(16);

    if (isInstalled) {
      stdout.writeln(
        _bold(_green('  ● ${r.version.padRight(12)} $arch  $dart  $date  ← installed')),
      );
    } else {
      stdout.writeln(
        _dim('    ${r.version.padRight(12)} $arch  $dart  $date'),
      );
    }
  }

  // ── Terminal control ──────────────────────────────────────────────────────

  /// Moves the cursor up [n] lines and erases everything below it, effectively
  /// wiping the page content so it can be redrawn in place.
  void _clearLines(int n) {
    if (n <= 0) return;
    stdout.write('\x1B[${n}A\x1B[J');
  }

  /// Reads a keypress in raw mode and returns the navigation intent.
  ///
  /// Arrow keys send a 3-byte CSI escape sequence: ESC `[` C/D.
  /// After receiving ESC (27) we read 2 more bytes to complete the sequence.
  _NavKey _readKey() {
    final byte = stdin.readByteSync();

    // Quit keys: q, Q, Ctrl-C.
    if (byte == 113 || byte == 81 || byte == 3) return _NavKey.quit;

    if (byte == 27) {
      // Start of a CSI escape sequence — read the '[' introducer.
      final bracket = stdin.readByteSync();
      if (bracket == 91) {
        // Read the final byte to identify which arrow key.
        final letter = stdin.readByteSync();
        if (letter == 67) return _NavKey.right; // →  ESC [ C
        if (letter == 68) return _NavKey.left; //  ←  ESC [ D
      }
      // Unknown escape sequence — treat as quit.
      return _NavKey.quit;
    }

    return _NavKey.other;
  }

  // ── ANSI helpers ──────────────────────────────────────────────────────────

  static const _reset = '\x1B[0m';
  static const _boldCode = '\x1B[1m';
  static const _greenCode = '\x1B[32m';
  static const _grayCode = '\x1B[90m';
  static const _whiteCode = '\x1B[97m';

  static bool get _colors => stdout.hasTerminal && stdout.supportsAnsiEscapes;

  String _bold(String s) => _colors ? '$_boldCode$s$_reset' : s;
  String _green(String s) => _colors ? '$_greenCode$s$_reset' : s;
  String _dim(String s) => _colors ? '$_grayCode$s$_reset' : s;
  String _bright(String s) => _colors ? '$_whiteCode$s$_reset' : s;
}
