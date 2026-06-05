import 'dart:io';

import 'package:path/path.dart' as p;

import '../help.dart';
import '../services/cache_service.dart';
import '../utils/logger.dart';
import 'base_command.dart';

class UninstallCommand extends FveCommand {
  @override
  String get name => 'uninstall';

  @override
  String get description =>
      'Completely remove fve from this machine (binary, SDKs, caches, PATH entry).';

  @override
  List<HelpExample> get usageExamples => const [
        HelpExample('uninstall', 'Remove everything fve installed (with confirmation)'),
        HelpExample('uninstall --force', 'Skip the confirmation prompt'),
      ];

  UninstallCommand() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Skip the confirmation prompt.',
      negatable: false,
    );
  }

  @override
  Future<void> run() async {
    final force = argResults!['force'] as bool;

    final binaryPath = Platform.resolvedExecutable;
    final fveHome = CacheService.fveHome;
    final versions = CacheService().installedVersions();
    final shell = _detectShell();
    final rcFile = _rcFile(shell);
    final rcHasFve = _rcHasFve(rcFile);

    Logger.bold('\nfve uninstall');
    Logger.plain('');
    Logger.plain('  The following will be permanently removed:');
    Logger.plain('');
    Logger.plain('    Binary    : $binaryPath');
    Logger.plain('    Cache dir : $fveHome');
    if (versions.isNotEmpty) {
      Logger.dim(
          '              (${versions.length} Flutter SDK version(s): ${versions.join(', ')})');
    }
    if (rcHasFve) {
      Logger.plain('    PATH entry: $rcFile');
    }
    Logger.plain('');

    if (!force) {
      stdout.write('Type "yes" to confirm: ');
      final input = stdin.readLineSync()?.trim().toLowerCase();
      if (input != 'yes') {
        Logger.plain('Aborted.');
        return;
      }
    }

    // 1. Remove ~/.fve/
    final cacheDir = Directory(fveHome);
    if (cacheDir.existsSync()) {
      cacheDir.deleteSync(recursive: true);
      Logger.success('Removed $fveHome');
    }

    // 2. Remove PATH entry from shell rc
    if (rcHasFve) {
      _removeFromRc(rcFile);
    }

    // 3. Remove the fve binary last (we are still running from it).
    //
    // Guard: only delete it when we are genuinely running from the compiled
    // `fve` binary. When fve is run via `dart run bin/fve.dart` (development,
    // tests), Platform.resolvedExecutable points at the Dart launcher itself —
    // deleting that would wipe the user's Dart/Flutter SDK. Skip in that case.
    final binaryName = p.basename(binaryPath);
    if (binaryName != 'fve') {
      Logger.dim(
        'Skipping binary removal — fve is running via "$binaryName", not the '
        'installed fve binary. Remove it manually if needed.',
      );
    } else {
      final binary = File(binaryPath);
      if (binary.existsSync()) {
        try {
          binary.deleteSync();
          Logger.success('Removed $binaryPath');
        } catch (_) {
          // Likely needs elevated permissions.
          Logger.warning('Could not remove $binaryPath — try:');
          Logger.dim('  sudo rm "$binaryPath"');
        }
      }
    }

    Logger.plain('');
    Logger.plain('fve has been uninstalled.');
    if (rcHasFve) {
      Logger.dim('Restart your terminal to clear the PATH entry.');
    }
  }

  // ── Shell helpers (mirrors SetupCommand logic) ───────────────────────────

  String _detectShell() {
    final shellEnv = Platform.environment['SHELL'] ?? '';
    if (shellEnv.contains('zsh')) return 'zsh';
    if (shellEnv.contains('bash')) return 'bash';
    if (shellEnv.contains('fish')) return 'fish';
    return 'sh';
  }

  String _rcFile(String shell) {
    final home = Platform.environment['HOME'] ?? '~';
    return switch (shell) {
      'zsh' => p.join(home, '.zshrc'),
      'bash' => p.join(home, '.bashrc'),
      'fish' => p.join(home, '.config', 'fish', 'config.fish'),
      _ => p.join(home, '.profile'),
    };
  }

  bool _rcHasFve(String rcFile) {
    final file = File(rcFile);
    if (!file.existsSync()) return false;
    return file.readAsStringSync().contains('.fve/current/bin');
  }

  void _removeFromRc(String rcFile) {
    final file = File(rcFile);
    final original = file.readAsStringSync();
    final cleaned = original
        .replaceAll(
          RegExp(
            r'\n# fve — Flutter Version & Environment Manager\n[^\n]+\n',
          ),
          '',
        )
        .replaceAll(
          RegExp(r'\n?export PATH="\$HOME/\.fve/current/bin:\$PATH"\n?'),
          '\n',
        )
        .replaceAll(
          RegExp(r'\n?fish_add_path \$HOME/\.fve/current/bin\n?'),
          '\n',
        );

    if (cleaned != original) {
      file.writeAsStringSync(cleaned);
      Logger.success('Removed fve PATH entry from $rcFile');
    }
  }
}
