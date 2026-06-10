import 'dart:io';

import 'package:fve/src/services/cache_service.dart';
import 'package:fve/src/services/lock_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fve_lock_');
    CacheService.fveHomeOverride = tmp.path;
  });

  tearDown(() {
    CacheService.fveHomeOverride = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('acquire succeeds and writes this process PID', () {
    expect(LockService.acquire(), isTrue);
    final f = File(LockService.lockFile);
    expect(f.existsSync(), isTrue);
    expect(f.readAsStringSync().trim(), '$pid');
    LockService.release();
  });

  test('a second acquire fails while a live process holds the lock', () {
    expect(LockService.acquire(), isTrue);
    // The lock file holds our own (live) PID, so re-acquiring must fail.
    expect(LockService.acquire(), isFalse);
    LockService.release();
  });

  test('release removes the lock only when this process holds it', () {
    LockService.acquire();
    LockService.release();
    expect(File(LockService.lockFile).existsSync(), isFalse);

    // A lock held by a different PID is not released by us.
    File(LockService.lockFile).writeAsStringSync('424242\n');
    LockService.release();
    expect(File(LockService.lockFile).existsSync(), isTrue);
  });

  test('a stale lock from a dead PID is cleared and re-acquired', () {
    // PID 999999 is (essentially) never a running process.
    File(LockService.lockFile)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('999999\n');
    expect(LockService.acquire(), isTrue);
    expect(File(LockService.lockFile).readAsStringSync().trim(), '$pid');
    LockService.release();
  });

  test('a garbage (non-numeric) lock is treated as stale', () {
    File(LockService.lockFile)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('not-a-pid\n');
    expect(LockService.acquire(), isTrue);
    LockService.release();
  });

  // ── Keyed (scoped) locks ───────────────────────────────────────────────────

  group('keyed lock (path:)', () {
    String lockA() => p.join(tmp.path, 'pods', '3.22.2.lock');
    String lockB() => p.join(tmp.path, 'pods', '3.19.0.lock');

    test('acquires at a custom path and writes this PID', () {
      expect(LockService.acquire(path: lockA()), isTrue);
      expect(File(lockA()).readAsStringSync().trim(), '$pid');
      LockService.release(path: lockA());
      expect(File(lockA()).existsSync(), isFalse);
    });

    test('a second acquire of the SAME key fails while held', () {
      expect(LockService.acquire(path: lockA()), isTrue);
      expect(LockService.acquire(path: lockA()), isFalse);
      LockService.release(path: lockA());
    });

    test('different keys are independent (concurrent versions allowed)', () {
      expect(LockService.acquire(path: lockA()), isTrue);
      expect(LockService.acquire(path: lockB()), isTrue);
      LockService.release(path: lockA());
      LockService.release(path: lockB());
    });

    test('the keyed lock does not touch the global lock', () {
      expect(LockService.acquire(path: lockA()), isTrue);
      expect(File(LockService.lockFile).existsSync(), isFalse);
      LockService.release(path: lockA());
    });
  });
}
