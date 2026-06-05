import 'dart:io';

import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;

  setUp(() => env = FveTestEnv.create());
  tearDown(() => env.dispose());

  group('fve uninstall', () {
    test('exits 0 with --force', () async {
      final r = await env.run(['uninstall', '--force']);
      expect(r.exitCode, 0);
    });

    test('removes the ~/.fve directory', () async {
      env.installVersion('3.22.2');
      expect(Directory(env.fveHome).existsSync(), isTrue);

      await env.run(['uninstall', '--force']);

      expect(Directory(env.fveHome).existsSync(), isFalse);
    });

    test(
        'does NOT delete the running executable when invoked via the Dart '
        'launcher (resolvedExecutable is not the fve binary)', () async {
      // Regression guard: a destructive uninstall must never delete
      // Platform.resolvedExecutable when fve runs via `dart run` — that path
      // is the Dart/Flutter SDK launcher, and deleting it breaks the toolchain.
      final r = await env.run(['uninstall', '--force']);
      expect(r.exitCode, 0);
      expect(r.output.toLowerCase(), contains('skipping binary removal'));
      // The launcher that ran this subprocess must still exist.
      expect(File(dartLauncherPath).existsSync(), isTrue);
    });

    test('aborts when confirmation is not "yes"', () async {
      env.installVersion('3.22.2');
      final r = await env.run(['uninstall'], stdin: 'no');
      expect(r.output.toLowerCase(), contains('aborted'));
      expect(Directory(env.fveHome).existsSync(), isTrue);
    });
  });
}
