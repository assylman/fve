import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;

  setUp(() => env = FveTestEnv.create());
  tearDown(() => env.dispose());

  group('fve migrate', () {
    test('exits 64 when no target version is given', () async {
      final proj = env.createFlutterProjectDir();
      final r = await env.run(['migrate'], workingDir: proj.path);
      expect(r.exitCode, 64);
      expect(r.output.toLowerCase(), contains('version'));
    });

    test('exits 1 with a clear error when there is no pubspec.yaml', () async {
      final proj = env.createProjectDir(); // no pubspec.yaml
      final r = await env.run(['migrate', '3.24.0'], workingDir: proj.path);
      expect(r.exitCode, 1);
      expect(r.output.toLowerCase(), contains('pubspec.yaml'));
    });

    test('--help exits 0', () async {
      final r = await env.run(['migrate', '--help']);
      expect(r.exitCode, 0);
      expect(r.output.toLowerCase(), contains('compatible'));
    });
  });
}
