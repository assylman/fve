import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;

  setUp(() => env = FveTestEnv.create());
  tearDown(() => env.dispose());

  // ── Help ──────────────────────────────────────────────────────────────────

  group('fve setup --help', () {
    test('exits 0', () async {
      final r = await env.run(['setup', '--help']);
      expect(r.exitCode, 0);
    });

    test('mentions --remove flag', () async {
      final r = await env.run(['setup', '--help']);
      expect(r.output, contains('remove'));
    });

    test('does not mention --write flag', () async {
      final r = await env.run(['setup', '--help']);
      expect(r.output, isNot(contains('--write')));
    });
  });

  // ── No flags: shows PATH line ─────────────────────────────────────────────

  group('fve setup — no flags', () {
    test('exits 0', () async {
      final r = await env.run(['setup']);
      expect(r.exitCode, 0);
    });

    test('shows .fve/current/bin in output', () async {
      final r = await env.run(['setup']);
      expect(r.output, contains('.fve/current/bin'));
    });

    test('mentions the shell rc file', () async {
      final r = await env.run(['setup']);
      expect(
        r.output,
        anyOf(contains('zshrc'), contains('bashrc'), contains('profile'),
            contains('config.fish')),
      );
    });

    test('does not modify any files', () async {
      final zshrc = File(p.join(env.homePath, '.zshrc'));
      final bashrc = File(p.join(env.homePath, '.bashrc'));
      await env.run(['setup']);
      expect(zshrc.existsSync(), isFalse);
      expect(bashrc.existsSync(), isFalse);
    });
  });

  // ── --remove: strips PATH entry from rc ──────────────────────────────────

  group('fve setup --remove', () {
    test('exits 0 when no rc file exists', () async {
      final r = await env.run(['setup', '--remove']);
      expect(r.exitCode, 0);
    });

    test('removes fve block from rc file', () async {
      // Manually write an rc file with a fve block.
      final zshrc = File(p.join(env.homePath, '.zshrc'))
        ..writeAsStringSync(
          'export FOO=bar\n'
          '\n# fve — Flutter Version & Environment Manager\n'
          r'export PATH="$HOME/.fve/current/bin:$PATH"'
          '\n',
        );

      await env.run(['setup', '--remove'],
          extraEnv: {'SHELL': '/bin/zsh'});

      final content = zshrc.readAsStringSync();
      expect(content, isNot(contains('.fve/current/bin')));
      expect(content, contains('export FOO=bar'));
    });

    test('warns when no fve entry found in rc', () async {
      File(p.join(env.homePath, '.zshrc'))
          .writeAsStringSync('export FOO=bar\n');

      final r = await env.run(['setup', '--remove'],
          extraEnv: {'SHELL': '/bin/zsh'});
      expect(r.output.toLowerCase(), contains('no fve'));
    });
  });
}
