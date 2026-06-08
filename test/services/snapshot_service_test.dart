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
