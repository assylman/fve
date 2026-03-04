import 'dart:convert';

import 'package:test/test.dart';

import '../helpers/fve_process.dart';

/// Parses [text] as JSON, returning null if parsing fails.
Object? tryParseJson(String text) {
  try {
    return jsonDecode(text.trim());
  } catch (_) {
    return null;
  }
}

void main() {
  late FveTestEnv env;

  setUp(() => env = FveTestEnv.create());
  tearDown(() => env.dispose());

  // ── api context ───────────────────────────────────────────────────────────

  group('fve api context — no version set', () {
    test('exits 0', () async {
      expect((await env.run(['api', 'context'])).exitCode, 0);
    });

    test('outputs valid JSON', () async {
      final r = await env.run(['api', 'context']);
      expect(tryParseJson(r.stdout), isNotNull);
    });

    test('active is null when no version is set', () async {
      final r = await env.run(['api', 'context']);
      final json = jsonDecode(r.stdout.trim()) as Map<String, dynamic>;
      expect(json['active'], isNull);
    });

    test('project is null when no .fverc exists', () async {
      final r = await env.run(['api', 'context']);
      final json = jsonDecode(r.stdout.trim()) as Map<String, dynamic>;
      expect(json['project'], isNull);
    });

    test('global is null when no global version is set', () async {
      final r = await env.run(['api', 'context']);
      final json = jsonDecode(r.stdout.trim()) as Map<String, dynamic>;
      expect(json['global'], isNull);
    });
  });

  group('fve api context — project version set', () {
    late String projPath;

    setUp(() {
      env.installVersion('3.22.2');
      final dir = env.createProjectDir(pinnedVersion: '3.22.2');
      projPath = dir.path;
    });

    test('project.version matches .fverc', () async {
      final r = await env.run(['api', 'context'], workingDir: projPath);
      final json = jsonDecode(r.stdout.trim()) as Map<String, dynamic>;
      final project = json['project'] as Map<String, dynamic>;
      expect(project['version'], '3.22.2');
    });

    test('active equals the project version', () async {
      final r = await env.run(['api', 'context'], workingDir: projPath);
      final json = jsonDecode(r.stdout.trim()) as Map<String, dynamic>;
      expect(json['active'], '3.22.2');
    });

    test('activeSource is "project"', () async {
      final r = await env.run(['api', 'context'], workingDir: projPath);
      final json = jsonDecode(r.stdout.trim()) as Map<String, dynamic>;
      expect(json['activeSource'], 'project');
    });
  });

  group('fve api context — global version set', () {
    setUp(() {
      env.installVersion('3.22.2');
      env.setGlobal('3.22.2');
    });

    test('global.version matches the symlink', () async {
      final r = await env.run(['api', 'context']);
      final json = jsonDecode(r.stdout.trim()) as Map<String, dynamic>;
      final global = json['global'] as Map<String, dynamic>;
      expect(global['version'], '3.22.2');
    });

    test('activeSource is "global"', () async {
      final r = await env.run(['api', 'context']);
      final json = jsonDecode(r.stdout.trim()) as Map<String, dynamic>;
      expect(json['activeSource'], 'global');
    });
  });

  group('fve api context — both project and global', () {
    late String projPath;

    setUp(() {
      env.installVersion('3.22.2');
      env.installVersion('3.19.0');
      env.setGlobal('3.19.0');
      final dir = env.createProjectDir(pinnedVersion: '3.22.2');
      projPath = dir.path;
    });

    test('active is the project version (takes precedence)', () async {
      final r = await env.run(['api', 'context'], workingDir: projPath);
      final json = jsonDecode(r.stdout.trim()) as Map<String, dynamic>;
      expect(json['active'], '3.22.2');
      expect(json['activeSource'], 'project');
    });
  });

  // ── api list ──────────────────────────────────────────────────────────────

  group('fve api list — nothing installed', () {
    test('exits 0', () async {
      expect((await env.run(['api', 'list'])).exitCode, 0);
    });

    test('outputs a JSON array', () async {
      final r = await env.run(['api', 'list']);
      final json = tryParseJson(r.stdout);
      expect(json, isList);
      expect((json as List), isEmpty);
    });
  });

  group('fve api list — versions installed', () {
    setUp(() {
      env.installVersion('3.22.2');
      env.installVersion('3.19.0');
    });

    test('outputs a JSON array with both versions', () async {
      final r = await env.run(['api', 'list']);
      final json = jsonDecode(r.stdout.trim()) as List<dynamic>;
      final versions = json.map((e) => (e as Map)['version']).toList();
      expect(versions, contains('3.22.2'));
      expect(versions, contains('3.19.0'));
    });

    test('each item has the required fields', () async {
      final r = await env.run(['api', 'list']);
      final json = jsonDecode(r.stdout.trim()) as List<dynamic>;
      final item = json.first as Map<String, dynamic>;
      expect(item.containsKey('version'), isTrue);
      expect(item.containsKey('sdkPath'), isTrue);
      expect(item.containsKey('dartBin'), isTrue);
      expect(item.containsKey('flutterBin'), isTrue);
      expect(item.containsKey('isGlobal'), isTrue);
      expect(item.containsKey('isProject'), isTrue);
    });

    test('isGlobal is true for the global version', () async {
      env.setGlobal('3.22.2');
      final r = await env.run(['api', 'list']);
      final json = jsonDecode(r.stdout.trim()) as List<dynamic>;
      final entry = json.firstWhere(
        (e) => (e as Map)['version'] == '3.22.2',
      ) as Map<String, dynamic>;
      expect(entry['isGlobal'], isTrue);
    });
  });

  // ── api project ───────────────────────────────────────────────────────────

  group('fve api project — no .fverc', () {
    test('outputs null', () async {
      final r = await env.run(['api', 'project']);
      expect(r.stdout.trim(), 'null');
    });
  });

  group('fve api project — .fverc present', () {
    late String projPath;

    setUp(() {
      env.installVersion('3.22.2');
      final dir = env.createProjectDir(pinnedVersion: '3.22.2');
      projPath = dir.path;
    });

    test('returns flutterVersion from .fverc', () async {
      final r = await env.run(['api', 'project'], workingDir: projPath);
      final json = jsonDecode(r.stdout.trim()) as Map<String, dynamic>;
      expect(json['flutterVersion'], '3.22.2');
    });

    test('includes sdkPath', () async {
      final r = await env.run(['api', 'project'], workingDir: projPath);
      final json = jsonDecode(r.stdout.trim()) as Map<String, dynamic>;
      expect(json['sdkPath'], isNotNull);
      expect(json['sdkPath'], contains('3.22.2'));
    });

    test('isInstalled is true when version is cached', () async {
      final r = await env.run(['api', 'project'], workingDir: projPath);
      final json = jsonDecode(r.stdout.trim()) as Map<String, dynamic>;
      expect(json['isInstalled'], isTrue);
    });

    test('isInstalled is false when version is not cached', () async {
      final dir = env.createProjectDir(pinnedVersion: '9.9.9');
      final r = await env.run(['api', 'project'], workingDir: dir.path);
      final json = jsonDecode(r.stdout.trim()) as Map<String, dynamic>;
      expect(json['isInstalled'], isFalse);
    });
  });

  // ── api — help ────────────────────────────────────────────────────────────

  group('fve api --help', () {
    test('exits 0', () async {
      expect((await env.run(['api', '--help'])).exitCode, 0);
    });
  });
}
