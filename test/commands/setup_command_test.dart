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

    test('mentions --write flag', () async {
      final r = await env.run(['setup', '--help']);
      expect(r.output, contains('write'));
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
      // Should mention some kind of rc file path.
      expect(
        r.output,
        anyOf(contains('zshrc'), contains('bashrc'), contains('profile'),
            contains('config.fish')),
      );
    });

    test('does not modify any files without --write', () async {
      final zshrc = File(p.join(env.homePath, '.zshrc'));
      final bashrc = File(p.join(env.homePath, '.bashrc'));
      await env.run(['setup']);
      expect(zshrc.existsSync(), isFalse);
      expect(bashrc.existsSync(), isFalse);
    });
  });

  // ── --write: appends to shell rc ──────────────────────────────────────────

  group('fve setup --write', () {
    test('exits 0', () async {
      final r = await env.run(['setup', '--write']);
      expect(r.exitCode, 0);
    });

    test('creates the shell rc file', () async {
      await env.run(['setup', '--write']);
      // At least one rc file should now exist in the home dir.
      final rcFiles = ['.zshrc', '.bashrc', '.profile']
          .map((f) => File(p.join(env.homePath, f)))
          .toList();
      expect(rcFiles.any((f) => f.existsSync()), isTrue);
    });

    test('written rc contains .fve/current/bin', () async {
      await env.run(['setup', '--write']);
      final rcFiles = ['.zshrc', '.bashrc', '.profile']
          .map((f) => File(p.join(env.homePath, f)))
          .where((f) => f.existsSync())
          .toList();
      expect(rcFiles, isNotEmpty);
      final content = rcFiles.first.readAsStringSync();
      expect(content, contains('.fve/current/bin'));
    });

    test('running --write twice does not duplicate the entry', () async {
      await env.run(['setup', '--write']);
      await env.run(['setup', '--write']);
      final rcFiles = ['.zshrc', '.bashrc', '.profile']
          .map((f) => File(p.join(env.homePath, f)))
          .where((f) => f.existsSync())
          .toList();
      final content = rcFiles.first.readAsStringSync();
      // Should only contain one PATH line, not two.
      expect('.fve/current/bin'.allMatches(content).length, 1);
    });

    test('prints success message', () async {
      final r = await env.run(['setup', '--write']);
      expect(r.output.toLowerCase(), contains('written'));
    });
  });
}
