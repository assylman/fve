import 'package:fve/src/models/podfile_lock.dart';
import 'package:test/test.dart';

const _sample = '''
PODS:
  - Firebase/Core (10.0.0):
    - Firebase/CoreOnly (= 10.0.0)
  - Firebase/CoreOnly (10.0.0)
  - Flutter (1.0.0)
  - SDWebImage (5.15.5)

DEPENDENCIES:
  - Firebase/Core
  - Flutter (from `Flutter`)

SPEC CHECKSUMS:
  Firebase: abcdef123456

COCOAPODS: 1.14.3
''';

void main() {
  group('PodfileLock.parse', () {
    test('extracts top-level pod versions', () {
      final lock = PodfileLock.parse(_sample);
      expect(lock.pods['Firebase/Core'], '10.0.0');
      expect(lock.pods['Flutter'], '1.0.0');
      expect(lock.pods['SDWebImage'], '5.15.5');
    });

    test('ignores constraint sub-dependency lines', () {
      final lock = PodfileLock.parse(_sample);
      // The `- Firebase/CoreOnly (= 10.0.0)` constraint line (4-space indent)
      // must not be captured; only the concrete `(10.0.0)` entry counts.
      expect(lock.pods['Firebase/CoreOnly'], '10.0.0');
      expect(lock.pods.values, isNot(contains('= 10.0.0')));
    });

    test('reads the COCOAPODS version trailer', () {
      expect(PodfileLock.parse(_sample).cocoaPodsVersion, '1.14.3');
    });

    test('stops collecting pods at the DEPENDENCIES section', () {
      final lock = PodfileLock.parse(_sample);
      // "Flutter (from `Flutter`)" lives under DEPENDENCIES and must not
      // overwrite the PODS entry.
      expect(lock.pods['Flutter'], '1.0.0');
    });

    test('handles an empty / lockless input', () {
      final lock = PodfileLock.parse('');
      expect(lock.pods, isEmpty);
      expect(lock.cocoaPodsVersion, isNull);
    });
  });

  group('diffPodfileLocks', () {
    PodfileLock lk(Map<String, String> pods) => PodfileLock(pods: pods);

    test('detects added, removed and changed pods, sorted by name', () {
      final before = lk({'A': '1.0.0', 'B': '2.0.0', 'C': '3.0.0'});
      final after = lk({'A': '1.0.0', 'B': '2.1.0', 'D': '4.0.0'});

      final changes = diffPodfileLocks(before, after);
      expect(changes.map((c) => c.name), ['B', 'C', 'D']);

      final byName = {for (final c in changes) c.name: c};
      expect(byName['B']!.kind, PodChangeKind.changed);
      expect(byName['B']!.from, '2.0.0');
      expect(byName['B']!.to, '2.1.0');
      expect(byName['C']!.kind, PodChangeKind.removed);
      expect(byName['C']!.from, '3.0.0');
      expect(byName['D']!.kind, PodChangeKind.added);
      expect(byName['D']!.to, '4.0.0');
    });

    test('identical locks produce no changes', () {
      final same = lk({'A': '1.0.0', 'B': '2.0.0'});
      expect(diffPodfileLocks(same, lk({'A': '1.0.0', 'B': '2.0.0'})), isEmpty);
    });
  });

  group('cocoaPodsDrift', () {
    test('identical versions → none', () {
      expect(cocoaPodsDrift('1.16.2', '1.16.2'), CocoaPodsDrift.none);
    });

    test('missing patch component compares equal (1.16 == 1.16.0) → none', () {
      expect(cocoaPodsDrift('1.16', '1.16.0'), CocoaPodsDrift.none);
      expect(cocoaPodsDrift('1.16.0', '1.16'), CocoaPodsDrift.none);
    });

    test('patch-only difference → patch', () {
      expect(cocoaPodsDrift('1.16.1', '1.16.2'), CocoaPodsDrift.patch);
      expect(cocoaPodsDrift('1.16.2', '1.16.0'), CocoaPodsDrift.patch);
    });

    test('minor difference → significant', () {
      expect(cocoaPodsDrift('1.15.0', '1.16.2'), CocoaPodsDrift.significant);
    });

    test('major difference → significant', () {
      expect(cocoaPodsDrift('1.16.2', '2.0.0'), CocoaPodsDrift.significant);
    });

    test('unparseable / pre-release suffix is tolerated', () {
      // Trailing non-numeric components are ignored (treated as 0).
      expect(cocoaPodsDrift('1.16.2.beta', '1.16.2'), CocoaPodsDrift.none);
      expect(cocoaPodsDrift('1.16.2', '1.16.2-rc1'), CocoaPodsDrift.none);
      // Garbage major falls back to 0, so a real version is significant drift.
      expect(cocoaPodsDrift('garbage', '1.16.2'), CocoaPodsDrift.significant);
    });
  });
}
