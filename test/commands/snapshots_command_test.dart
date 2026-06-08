import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;

  setUp(() => env = FveTestEnv.create());
  tearDown(() => env.dispose());

  group('fve snapshots', () {
    test('exits 0 with a hint when the project has no snapshots', () async {
      final proj = env.createProjectDir();
      final r = await env.run(['snapshots'], workingDir: proj.path);
      expect(r.exitCode, 0);
      expect(r.output.toLowerCase(), contains('no snapshots'));
    });

    test('--all exits 0 with a message when nothing is snapshotted', () async {
      final r = await env.run(['snapshots', '--all']);
      expect(r.exitCode, 0);
      expect(r.output.toLowerCase(), contains('no snapshots'));
    });

    test('-a is an alias for --all', () async {
      final r = await env.run(['snapshots', '-a']);
      expect(r.exitCode, 0);
    });

    test('--help exits 0', () async {
      final r = await env.run(['snapshots', '--help']);
      expect(r.exitCode, 0);
      expect(r.output.toLowerCase(), contains('snapshot'));
    });
  });
}
