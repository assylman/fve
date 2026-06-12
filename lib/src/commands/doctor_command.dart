import 'dart:io';

import 'package:path/path.dart' as p;


import '../models/podfile_lock.dart';
import '../models/project_config.dart';
import '../services/cache_service.dart';
import '../services/pod_service.dart';
import '../utils/logger.dart';
import 'base_command.dart';

class DoctorCommand extends FveCommand {
  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check your fve environment for problems and print setup instructions.';

  var _criticalError = false;

  @override
  Future<void> run() async {
    Logger.bold('\nfve doctor');
    Logger.plain('');

    final cache = CacheService();
    final cwd = Directory.current.path;

    // ── 1. fve home ──────────────────────────────────────────────────────
    _section('fve home');
    final home = CacheService.fveHome;
    _check('fve home exists', Directory(home).existsSync(), home);
    _check(
      'versions dir exists',
      Directory(CacheService.versionsDir).existsSync(),
      CacheService.versionsDir,
    );

    // ── 2. Installed versions ────────────────────────────────────────────
    _section('Installed versions');
    final versions = cache.installedVersions();
    if (versions.isEmpty) {
      Logger.warning('  No versions installed. Run: fve install <version>');
      _criticalError = true;
    } else {
      for (final v in versions) {
        Logger.success('  $v');
      }
    }

    // ── 3. Global version ────────────────────────────────────────────────
    _section('Global version');
    final globalVersion = cache.currentGlobalVersion();
    if (globalVersion != null) {
      _check('Global version set', true, globalVersion);
      _check(
        'Symlink target exists',
        Directory(cache.versionDir(globalVersion)).existsSync(),
        CacheService.currentLink,
      );
    } else {
      Logger.warning('  No global version. Run: fve global <version>');
    }

    // ── 4. PATH check ─────────────────────────────────────────────────────
    _section('PATH');
    final pathEnv = Platform.environment['PATH'] ?? '';
    final fveBinInPath =
        pathEnv.contains(p.join(home, 'current', 'bin'));
    if (fveBinInPath) {
      Logger.success('  fve current/bin is in PATH');
    } else {
      Logger.warning(
        '  fve current/bin is not in PATH\n'
        '    Add to your shell rc:\n'
        '    export PATH="\$HOME/.fve/current/bin:\$PATH"',
      );
    }

    // ── 5. Project config ────────────────────────────────────────────────
    _section('Project (current directory)');
    final projectConfig = ProjectConfig.findForDirectory('.');
    if (projectConfig != null) {
      final v = projectConfig.flutterVersion;
      final installed = cache.isInstalled(v);
      _check('Project version set', true, v);
      _check(
        'Project version installed',
        installed,
        installed ? null : 'Run: fve install $v',
        critical: true,
      );
      final configPath = ProjectConfig.configPathForDirectory('.');
      Logger.dim('  config: $configPath');
    } else {
      Logger.dim('  No .fverc found. Run: fve use <version>');
    }

    // ── 6. iOS / CocoaPods ───────────────────────────────────────────────────
    final pod = PodService();
    if (pod.hasPodfile(cwd)) {
      _section('iOS / CocoaPods');
      if (projectConfig != null) {
        final version = projectConfig.flutterVersion;
        final injectedVersion = pod.podfileInjectionVersion(cwd);
        if (injectedVersion == version) {
          _check('Podfile injection', true, 'CP_HOME_DIR → ${pod.podCacheDir(version)}');
        } else if (injectedVersion != null) {
          _check(
            'Podfile injection',
            false,
            'injected for $injectedVersion, but .fverc pins $version\n'
            '    Fix: fve use $version',
            critical: true,
          );
        } else {
          _check(
            'Podfile injection',
            false,
            'fve block missing\n    Fix: fve use $version',
            critical: true,
          );
        }
        final podCacheExists = Directory(pod.podCacheDir(version)).existsSync();
        _check(
          'Pod cache for $version',
          podCacheExists,
          podCacheExists
              ? pod.podCacheDir(version)
              : 'Run: fve pod install',
        );
        _checkCocoaPodsDrift(cwd);
      } else {
        Logger.dim('  ios/Podfile found. Pin a version first: fve use <version>');
      }
    }

    // ── 7. Project structure ─────────────────────────────────────────────
    if (projectConfig != null) {
      _section('Project structure');
      _checkProjectStructure(cwd);
    }

    // ── 8. System tools ──────────────────────────────────────────────────
    _section('System tools');
    _checkTool('git', ['--version']);
    _checkTool('unzip', ['-v']);
    if (Platform.isMacOS) {
      _checkTool('pod', ['--version']);
      _checkTool('xcode-select', ['--print-path']);
      _checkXcodeVersion();
      _checkRubyVersion();
    }
    if (!Platform.isMacOS) {
      // Linux Flutter archives are `.tar.xz`; extraction needs the xz binary.
      _checkTool('xz', ['--version'],
          hint: 'Install xz-utils — needed to extract Flutter .tar.xz '
              'archives (fve install --no-git).');
      _checkAndroidSdk();
      _checkJavaVersion();
    }

    Logger.plain('');
    if (_criticalError) exit(1);
  }

  // ── Project structure checks ─────────────────────────────────────────────

  void _checkProjectStructure(String cwd) {
    // 4.1.9 pubspec.yaml missing — reported but not critical. A directory can
    // legitimately pin a Flutter version via .fverc without being a Flutter
    // project root, so doctor should surface this without exiting non-zero.
    final hasPubspec = File(p.join(cwd, 'pubspec.yaml')).existsSync();
    _check('pubspec.yaml', hasPubspec, hasPubspec ? null : 'Not a Flutter project');

    if (!hasPubspec) return;

    // 4.1.4 .env missing but .env.example exists
    final hasEnv = File(p.join(cwd, '.env')).existsSync();
    final hasEnvExample = File(p.join(cwd, '.env.example')).existsSync();
    if (!hasEnv && hasEnvExample) {
      Logger.warning('  .env missing but .env.example exists');
      Logger.dim('    Fix: cp .env.example .env');
    } else if (hasEnv) {
      Logger.success('  .env file present');
    }

    // 4.1.3 build_runner: detect stale generated files
    final hasBuildYaml = File(p.join(cwd, 'build.yaml')).existsSync();
    if (hasBuildYaml) {
      Logger.dim('  build.yaml found (code generation project)');
      _checkBuildRunnerStaleness(cwd);
    }

    // 4.1.8 Platform folders
    _checkPlatformFolders(cwd);

    // 4.1.10 Monorepo / melos
    final hasMelos = File(p.join(cwd, 'melos.yaml')).existsSync();
    if (hasMelos) {
      Logger.dim('  melos.yaml found (monorepo)');
      _checkMelosPackages(cwd);
    }
  }

  void _checkBuildRunnerStaleness(String cwd) {
    // Heuristic: look for .g.dart files older than their sources.
    try {
      final libDir = Directory(p.join(cwd, 'lib'));
      if (!libDir.existsSync()) return;
      var staleFound = false;
      for (final f in libDir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.g.dart') && !f.path.endsWith('.freezed.dart')) continue;
        final base = f.path.replaceAll(RegExp(r'\.(g|freezed)\.dart$'), '.dart');
        final source = File(base);
        if (source.existsSync() && source.lastModifiedSync().isAfter(f.lastModifiedSync())) {
          staleFound = true;
          break;
        }
      }
      if (staleFound) {
        Logger.warning('  Stale generated files detected');
        Logger.dim('    Fix: dart run build_runner build');
      } else {
        Logger.success('  Generated files appear up to date');
      }
    } catch (_) {}
  }

  void _checkPlatformFolders(String cwd) {
    final platforms = {
      'android': 'Android',
      'ios': 'iOS',
      'web': 'Web',
      'linux': 'Linux desktop',
      'macos': 'macOS desktop',
      'windows': 'Windows desktop',
    };
    final present = <String>[];
    final missing = <String>[];
    for (final entry in platforms.entries) {
      if (Directory(p.join(cwd, entry.key)).existsSync()) {
        present.add(entry.value);
      } else {
        missing.add(entry.value);
      }
    }
    if (present.isNotEmpty) {
      Logger.success('  Platforms enabled: ${present.join(', ')}');
    }
    if (missing.isNotEmpty) {
      Logger.dim('  Platforms not added: ${missing.join(', ')}');
    }
  }

  void _checkMelosPackages(String cwd) {
    try {
      final result = Process.runSync('melos', ['list', '--json'], workingDirectory: cwd);
      if (result.exitCode == 0) {
        Logger.success('  melos found packages');
      } else {
        Logger.dim('  Run melos bootstrap to initialise the monorepo');
      }
    } catch (_) {
      Logger.dim('  melos not installed: dart pub global activate melos');
    }
  }

  // ── Platform tool checks ─────────────────────────────────────────────────

  void _checkXcodeVersion() {
    try {
      final r = Process.runSync('xcodebuild', ['-version']);
      if (r.exitCode == 0) {
        final first = (r.stdout as String).trim().split('\n').first;
        final match = RegExp(r'Xcode (\d+)').firstMatch(first);
        final major = int.tryParse(match?.group(1) ?? '') ?? 0;
        if (major >= 14) {
          Logger.success('  Xcode version: $first');
        } else {
          Logger.warning('  Xcode $major may be too old for recent Flutter versions');
          Logger.dim('    Recommended: Xcode 14+');
        }
      }
    } catch (_) {}
  }

  /// Warns when `ios/Podfile.lock` was generated with a different CocoaPods
  /// version than the one currently installed (ROADMAP Risk #6 — cache/lock
  /// built with one CocoaPods can behave differently with another).
  void _checkCocoaPodsDrift(String cwd) {
    final lock = File(p.join(cwd, 'ios', 'Podfile.lock'));
    if (!lock.existsSync()) return;
    final lockCp = PodfileLock.parse(lock.readAsStringSync()).cocoaPodsVersion;
    if (lockCp == null) return;

    final installed = _installedCocoaPodsVersion();
    if (installed == null) return; // pod not found — reported elsewhere

    final detail =
        'Podfile.lock built with CocoaPods $lockCp, installed is $installed\n'
        '    Re-run: fve pod install  (regenerates the lock)';

    switch (cocoaPodsDrift(lockCp, installed)) {
      case CocoaPodsDrift.none:
        _check('CocoaPods version', true, 'Podfile.lock and pod both $lockCp');
      case CocoaPodsDrift.patch:
        // Patch-only drift is almost always benign — warn, but don't fail the
        // doctor run, so a routine CocoaPods patch release doesn't break CI.
        Logger.warning('  CocoaPods version (patch drift)');
        Logger.dim('    $detail');
      case CocoaPodsDrift.significant:
        // Major/minor drift can change resolution or the generated Pods
        // project — surface as a critical failure (exit 1).
        _check('CocoaPods version', false, detail, critical: true);
    }
  }

  String? _installedCocoaPodsVersion() {
    // Test seam: force the "installed" version deterministically (the drift
    // check otherwise depends on whatever `pod` is on the host).
    final override = Platform.environment['FVE_FAKE_POD_VERSION'];
    if (override != null && override.isNotEmpty) return override;
    try {
      final r = Process.runSync('pod', ['--version']);
      if (r.exitCode != 0) return null;
      return (r.stdout as String).trim().split('\n').first.trim();
    } catch (_) {
      return null;
    }
  }

  void _checkRubyVersion() {
    try {
      final r = Process.runSync('ruby', ['--version']);
      if (r.exitCode == 0) {
        final ver = (r.stdout as String).trim().split('\n').first;
        final match = RegExp(r'ruby (\d+)\.(\d+)').firstMatch(ver);
        final major = int.tryParse(match?.group(1) ?? '') ?? 0;
        final minor = int.tryParse(match?.group(2) ?? '') ?? 0;
        if (major > 2 || (major == 2 && minor >= 6)) {
          Logger.success('  Ruby: $ver');
        } else {
          Logger.warning('  Ruby version may be too old for CocoaPods');
          Logger.dim('    Recommended: Ruby 2.6+');
        }
      }
    } catch (_) {}
  }

  void _checkAndroidSdk() {
    final androidHome =
        Platform.environment['ANDROID_HOME'] ??
        Platform.environment['ANDROID_SDK_ROOT'];
    if (androidHome != null && Directory(androidHome).existsSync()) {
      Logger.success('  ANDROID_HOME: $androidHome');
    } else {
      Logger.warning('  ANDROID_HOME not set or directory not found');
      Logger.dim('    Set ANDROID_HOME to your Android SDK path.');
    }
  }

  void _checkJavaVersion() {
    try {
      final r = Process.runSync('java', ['-version']);
      // java prints version to stderr
      final ver = (r.stderr as String).trim().split('\n').first;
      Logger.success('  Java: $ver');
    } catch (_) {
      Logger.warning('  Java not found — needed for Android builds');
      Logger.dim('    Install JDK 17 or later.');
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _section(String title) {
    Logger.header(title);
  }

  void _check(String label, bool ok, String? detail, {bool critical = false}) {
    if (ok) {
      Logger.success('  $label${detail != null ? ': $detail' : ''}');
    } else {
      Logger.error('  $label${detail != null ? '\n    $detail' : ''}');
      if (critical) _criticalError = true;
    }
  }

  void _checkTool(String tool, List<String> args, {String? hint}) {
    try {
      final result = Process.runSync(tool, args);
      final ok = result.exitCode == 0;
      final version = result.stdout.toString().trim().split('\n').first;
      _check(tool, ok, ok ? version : null);
      if (!ok && hint != null) Logger.dim('    $hint');
    } catch (_) {
      Logger.error('  $tool: not found');
      if (hint != null) Logger.dim('    $hint');
    }
  }
}
