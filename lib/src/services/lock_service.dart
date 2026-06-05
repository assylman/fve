import 'dart:io';

import 'package:path/path.dart' as p;

import 'cache_service.dart';

/// Provides an advisory file lock at `~/.fve/lock` to prevent concurrent
/// fve operations from corrupting shared state.
///
/// The lock file contains the PID of the process that holds it. When a second
/// process tries to acquire the lock it checks whether the recorded PID is
/// still running; if not, the stale lock is cleared automatically.
class LockService {
  static String get lockFile => p.join(CacheService.fveHome, 'lock');

  /// Acquires the lock. Returns true on success, false if another fve process
  /// is already running. Clears stale locks from dead processes automatically.
  static bool acquire() {
    final file = File(lockFile);
    file.parent.createSync(recursive: true);

    if (file.existsSync()) {
      final contents = file.readAsStringSync().trim();
      final stalePid = int.tryParse(contents);
      if (stalePid != null && _isProcessRunning(stalePid)) {
        return false; // another live fve process holds the lock
      }
      // Stale lock — clear it.
      file.deleteSync();
    }

    file.writeAsStringSync('$pid\n');
    return true;
  }

  /// Releases the lock if this process holds it.
  static void release() {
    final file = File(lockFile);
    if (!file.existsSync()) return;
    final contents = file.readAsStringSync().trim();
    if (contents == '$pid') {
      file.deleteSync();
    }
  }

  /// Returns true when [targetPid] is a live process.
  static bool _isProcessRunning(int targetPid) {
    if (Platform.isWindows) {
      final r = Process.runSync('tasklist', ['/FI', 'PID eq $targetPid', '/NH']);
      return (r.stdout as String).contains('$targetPid');
    }
    // POSIX: kill -0 sends no signal but checks whether the process exists.
    final r = Process.runSync('kill', ['-0', '$targetPid']);
    return r.exitCode == 0;
  }
}
