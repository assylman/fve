import 'dart:convert';
import 'dart:io';

import 'package:fve/src/services/compat_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Builds a pub.dev `/api/packages/<name>` response body whose latest version
/// declares the given Flutter SDK [flutterConstraint] (or none when null).
String _pubResponse({String? flutterConstraint}) {
  return jsonEncode({
    'latest': {
      'pubspec': {
        'environment': {
          if (flutterConstraint != null) 'flutter': flutterConstraint,
        },
      },
    },
  });
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('fve_compat_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String writePubspec(String body) {
    File(p.join(tmp.path, 'pubspec.yaml')).writeAsStringSync(body);
    return tmp.path;
  }

  /// A MockClient that maps package name → flutter constraint (or status), and
  /// records every package name requested.
  ({http.Client client, Set<String> requested}) mockPub(
    Map<String, String?> constraints, {
    Set<String> notFound = const {},
    Set<String> serverError = const {},
  }) {
    final requested = <String>{};
    final client = MockClient((req) async {
      final name = req.url.pathSegments.last; // /api/packages/<name>
      requested.add(name);
      if (notFound.contains(name)) return http.Response('{}', 404);
      if (serverError.contains(name)) return http.Response('{}', 500);
      return http.Response(
        _pubResponse(flutterConstraint: constraints[name]),
        200,
      );
    });
    return (client: client, requested: requested);
  }

  group('CompatService.check — constraint matching', () {
    test('flags a package whose Flutter constraint excludes the version',
        () async {
      final m = mockPub({'go_router': '>=2.0.0 <3.0.0'});
      final dir = writePubspec('''
name: app
dependencies:
  go_router: ^1.0.0
''');
      final results =
          await CompatService(client: m.client).check(dir, '3.22.0');

      expect(results, hasLength(1));
      expect(results.single.package, 'go_router');
      expect(results.single.compatible, isFalse);
      expect(results.single.reason, contains('3.22.0'));
    });

    test('accepts a package whose constraint allows the version', () async {
      final m = mockPub({'go_router': '>=3.0.0'});
      final dir = writePubspec('''
name: app
dependencies:
  go_router: ^13.0.0
''');
      final results =
          await CompatService(client: m.client).check(dir, '3.24.0');
      expect(results, isEmpty);
    });

    test('handles caret Flutter constraints', () async {
      // ^3.0.0 means >=3.0.0 <4.0.0 — 3.24.0 is allowed, 4.0.0 is not.
      final mOk = mockPub({'pkg': '^3.0.0'});
      final dirOk = writePubspec('name: app\ndependencies:\n  pkg: ^1.0.0\n');
      expect(await CompatService(client: mOk.client).check(dirOk, '3.24.0'),
          isEmpty);

      final mBad = mockPub({'pkg': '^3.0.0'});
      expect(
        (await CompatService(client: mBad.client).check(dirOk, '4.0.0')).single
            .package,
        'pkg',
      );
    });

    test('treats an unparseable target version (channel) as compatible',
        () async {
      final m = mockPub({'pkg': '>=3.0.0 <4.0.0'});
      final dir = writePubspec('name: app\ndependencies:\n  pkg: ^1.0.0\n');
      expect(await CompatService(client: m.client).check(dir, 'stable'),
          isEmpty);
    });
  });

  group('CompatService.check — pub.dev responses', () {
    test('package with no Flutter constraint is treated as unknown (skipped)',
        () async {
      final m = mockPub({'pkg': null});
      final dir = writePubspec('name: app\ndependencies:\n  pkg: ^1.0.0\n');
      expect(await CompatService(client: m.client).check(dir, '3.0.0'),
          isEmpty);
    });

    test('404 marks the package as not found / incompatible', () async {
      final m = mockPub({}, notFound: {'ghost'});
      final dir = writePubspec('name: app\ndependencies:\n  ghost: ^1.0.0\n');
      final results = await CompatService(client: m.client).check(dir, '3.0.0');
      expect(results.single.package, 'ghost');
      expect(results.single.reason, contains('not found'));
    });

    test('server error is treated as unknown (skipped)', () async {
      final m = mockPub({}, serverError: {'pkg'});
      final dir = writePubspec('name: app\ndependencies:\n  pkg: ^1.0.0\n');
      expect(await CompatService(client: m.client).check(dir, '3.0.0'),
          isEmpty);
    });
  });

  group('CompatService.check — dependency parsing', () {
    test('checks both dependencies and dev_dependencies', () async {
      final m = mockPub({'a': '>=9.0.0', 'b': '>=9.0.0'});
      final dir = writePubspec('''
name: app
dependencies:
  a: ^1.0.0
dev_dependencies:
  b: ^1.0.0
''');
      final results = await CompatService(client: m.client).check(dir, '3.0.0');
      expect(results.map((r) => r.package), containsAll(['a', 'b']));
    });

    test('skips the flutter SDK pseudo-dependencies', () async {
      final m = mockPub({});
      final dir = writePubspec('''
name: app
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  flutter_test:
    sdk: flutter
''');
      await CompatService(client: m.client).check(dir, '3.0.0');
      expect(m.requested, isEmpty);
    });

    test('skips git/path map-form dependencies', () async {
      final m = mockPub({});
      final dir = writePubspec('''
name: app
dependencies:
  from_git:
    git: https://example.com/x.git
  from_path:
    path: ../local
''');
      await CompatService(client: m.client).check(dir, '3.0.0');
      expect(m.requested, isEmpty);
    });

    test('handles a bare dependency (no version) as "any"', () async {
      final m = mockPub({'pkg': '>=9.0.0'});
      final dir = writePubspec('name: app\ndependencies:\n  pkg:\n');
      // pkg is still version-checked against its Flutter constraint.
      final results = await CompatService(client: m.client).check(dir, '3.0.0');
      expect(results.single.package, 'pkg');
    });
  });

  group('CompatService.check — guards', () {
    test('returns empty when force is true (no requests made)', () async {
      final m = mockPub({'pkg': '>=9.0.0'});
      final dir = writePubspec('name: app\ndependencies:\n  pkg: ^1.0.0\n');
      expect(
          await CompatService(client: m.client)
              .check(dir, '3.0.0', force: true),
          isEmpty);
      expect(m.requested, isEmpty);
    });

    test('returns empty when there is no pubspec.yaml', () async {
      final m = mockPub({});
      expect(await CompatService(client: m.client).check(tmp.path, '3.0.0'),
          isEmpty);
    });
  });
}
