import 'dart:io';

import 'package:fve/src/services/cache_service.dart';
import 'package:fve/src/services/snapshot_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory fveHome;
  late Directory project;
  final svc = SnapshotService();

  setUp(() {
    fveHome = Directory.systemTemp.createTempSync('fve_snap_home_');
    CacheService.fveHomeOverride = fveHome.path;
    project = Directory.systemTemp.createTempSync('fve_snap_proj_');
  });

  tearDown(() {
    CacheService.fveHomeOverride = null;
    for (final d in [fveHome, project]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  void writeLock(String content) =>
      File(p.join(project.path, 'pubspec.lock')).writeAsStringSync(content);

  void writePodLock(String content) {
    final ios = Directory(p.join(project.path, 'ios'))..createSync();
    File(p.join(ios.path, 'Podfile.lock')).writeAsStringSync(content);
  }

  String readPodLock() =>
      File(p.join(project.path, 'ios', 'Podfile.lock')).readAsStringSync();

  group('save', () {
    test('snapshots an existing pubspec.lock', () {
      writeLock('# lock 3.22.2\n');
      svc.save(project.path, '3.22.2');
      expect(svc.hasSnapshot(project.path, '3.22.2'), isTrue);
    });

    test('is a no-op when there is no pubspec.lock', () {
      svc.save(project.path, '3.22.2');
      expect(svc.hasSnapshot(project.path, '3.22.2'), isFalse);
    });

    test('a later save overwrites the snapshot for the same version', () {
      writeLock('v1\n');
      svc.save(project.path, '3.22.2');
      writeLock('v2\n');
      svc.save(project.path, '3.22.2');

      writeLock('current\n');
      svc.restore(project.path, '3.22.2');
      expect(File(p.join(project.path, 'pubspec.lock')).readAsStringSync(),
          'v2\n');
    });
  });

  group('restore', () {
    test('restores a saved snapshot and returns true', () {
      writeLock('snapshot-body\n');
      svc.save(project.path, '3.22.2');

      // Mutate the working lock, then restore.
      writeLock('changed\n');
      expect(svc.restore(project.path, '3.22.2'), isTrue);
      expect(File(p.join(project.path, 'pubspec.lock')).readAsStringSync(),
          'snapshot-body\n');
    });

    test('returns false when no snapshot exists', () {
      expect(svc.restore(project.path, '9.9.9'), isFalse);
    });
  });

  group('listSnapshots', () {
    test('lists snapshotted versions sorted', () {
      for (final v in ['3.24.0', '3.22.2', '3.19.0']) {
        writeLock('lock $v\n');
        svc.save(project.path, v);
      }
      final versions =
          svc.listSnapshots(project.path).map((s) => s.version).toList();
      expect(versions, ['3.19.0', '3.22.2', '3.24.0']);
    });

    test('is empty for a project with no snapshots', () {
      expect(svc.listSnapshots(project.path), isEmpty);
    });

    test('matches snapshots when listed via a non-normalized path (. segment)',
        () {
      // Regression: `fve use` saves with the absolute cwd while `fve snapshots`
      // listed with '.', producing `/proj/.` — a different project id — so the
      // listing always came up empty. The id must be path-normalized.
      writeLock('lock 3.22.2\n');
      svc.save(project.path, '3.22.2');

      final dottedPath = p.join(project.path, '.'); // e.g. /tmp/proj/.
      final versions =
          svc.listSnapshots(dottedPath).map((s) => s.version).toList();
      expect(versions, contains('3.22.2'));
    });
  });

  group('removeVersionSnapshots', () {
    test('removes the given version across projects, leaving others', () {
      writeLock('keep\n');
      svc.save(project.path, '3.22.2');
      svc.save(project.path, '3.24.0');

      svc.removeVersionSnapshots('3.24.0');

      expect(svc.hasSnapshot(project.path, '3.22.2'), isTrue);
      expect(svc.hasSnapshot(project.path, '3.24.0'), isFalse);
    });
  });

  group('Podfile.lock (LockKind.podfile)', () {
    test('saves and restores ios/Podfile.lock independently of pubspec.lock',
        () {
      writePodLock('PODS: AppMetrica 5.16.1\n');
      svc.save(project.path, '3.22.2', kind: LockKind.podfile);
      expect(svc.hasSnapshot(project.path, '3.22.2', kind: LockKind.podfile),
          isTrue);
      // pubspec snapshot does NOT exist (we only saved the podfile kind).
      expect(svc.hasSnapshot(project.path, '3.22.2'), isFalse);

      writePodLock('PODS: changed\n');
      expect(svc.restore(project.path, '3.22.2', kind: LockKind.podfile),
          isTrue);
      expect(readPodLock(), 'PODS: AppMetrica 5.16.1\n');
    });

    test('save is a no-op when ios/Podfile.lock is absent', () {
      svc.save(project.path, '3.22.2', kind: LockKind.podfile);
      expect(svc.hasSnapshot(project.path, '3.22.2', kind: LockKind.podfile),
          isFalse);
    });

    test('restore returns false when no podfile snapshot exists', () {
      expect(svc.restore(project.path, '9.9.9', kind: LockKind.podfile),
          isFalse);
    });

    test('both lockfiles coexist in the same version snapshot', () {
      writeLock('# pub 3.22.2\n');
      writePodLock('# pods 3.22.2\n');
      svc.save(project.path, '3.22.2');
      svc.save(project.path, '3.22.2', kind: LockKind.podfile);

      expect(svc.hasSnapshot(project.path, '3.22.2'), isTrue);
      expect(svc.hasSnapshot(project.path, '3.22.2', kind: LockKind.podfile),
          isTrue);

      final entry =
          svc.listSnapshots(project.path).firstWhere((s) => s.version == '3.22.2');
      expect(entry.locks, containsAll(['pubspec.lock', 'Podfile.lock']));
    });

    test('listSnapshots includes a version with only a Podfile.lock', () {
      writePodLock('# pods only\n');
      svc.save(project.path, '3.30.0', kind: LockKind.podfile);
      final versions =
          svc.listSnapshots(project.path).map((s) => s.version).toList();
      expect(versions, contains('3.30.0'));
    });

    test('readSnapshot returns the stored content without restoring', () {
      writePodLock('PODS:\n  - Foo (1.0.0)\n');
      svc.save(project.path, '3.22.2', kind: LockKind.podfile);
      // Mutate the working copy; readSnapshot must NOT touch it.
      writePodLock('changed\n');

      final content =
          svc.readSnapshot(project.path, '3.22.2', kind: LockKind.podfile);
      expect(content, 'PODS:\n  - Foo (1.0.0)\n');
      expect(readPodLock(), 'changed\n'); // working copy untouched
    });

    test('readSnapshot returns null when no snapshot exists', () {
      expect(
        svc.readSnapshot(project.path, '9.9.9', kind: LockKind.podfile),
        isNull,
      );
    });
  });

  group('project isolation', () {
    test('snapshots for different projects do not collide', () {
      final other = Directory.systemTemp.createTempSync('fve_snap_other_');
      addTearDown(() => other.deleteSync(recursive: true));

      writeLock('proj-A\n');
      svc.save(project.path, '3.22.2');
      File(p.join(other.path, 'pubspec.lock')).writeAsStringSync('proj-B\n');
      svc.save(other.path, '3.22.2');

      svc.restore(project.path, '3.22.2');
      expect(File(p.join(project.path, 'pubspec.lock')).readAsStringSync(),
          'proj-A\n');
      svc.restore(other.path, '3.22.2');
      expect(File(p.join(other.path, 'pubspec.lock')).readAsStringSync(),
          'proj-B\n');
    });
  });
}
