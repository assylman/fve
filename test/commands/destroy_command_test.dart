import 'dart:io';

import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;

  setUp(() => env = FveTestEnv.create());
  tearDown(() {
    // Dispose handles cleanup; if the test destroyed the fve home, that's fine.
    env.dispose();
  });

  // ── No fve home directory ─────────────────────────────────────────────────

  group('fve destroy — fve home does not exist', () {
    test('exits 0', () async {
      final r = await env.run(['destroy']);
      expect(r.exitCode, 0);
    });

    test('prints a warning that the cache does not exist', () async {
      final r = await env.run(['destroy']);
      expect(r.output.toLowerCase(), contains('does not exist'));
    });
  });

  // ── Force destroy ─────────────────────────────────────────────────────────

  group('fve destroy --force', () {
    setUp(() {
      // Create the fve home with an installed version.
      env.installVersion('3.22.2');
    });

    test('exits 0', () async {
      final r = await env.run(['destroy', '--force']);
      expect(r.exitCode, 0);
    });

    test('removes the entire ~/.fve directory', () async {
      await env.run(['destroy', '--force']);
      expect(Directory(env.fveHome).existsSync(), isFalse);
    });

    test('reports success', () async {
      final r = await env.run(['destroy', '--force']);
      expect(r.output.toLowerCase(), contains('destroyed'));
    });

    test('-f is an alias for --force', () async {
      final r = await env.run(['destroy', '-f']);
      expect(r.exitCode, 0);
      expect(Directory(env.fveHome).existsSync(), isFalse);
    });
  });

  // ── Interactive confirmation ───────────────────────────────────────────────

  group('fve destroy — interactive confirmation', () {
    setUp(() => env.installVersion('3.22.2'));

    test('destroys when user types "yes"', () async {
      final r = await env.run(['destroy'], stdin: 'yes');
      expect(r.exitCode, 0);
      expect(Directory(env.fveHome).existsSync(), isFalse);
    });

    test('aborts when user types anything other than "yes"', () async {
      final r = await env.run(['destroy'], stdin: 'no');
      expect(r.exitCode, 0);
      expect(r.output.toLowerCase(), contains('aborted'));
      expect(Directory(env.fveHome).existsSync(), isTrue);
    });

    test('aborts when user types "y" (partial match not accepted)', () async {
      final r = await env.run(['destroy'], stdin: 'y');
      expect(r.output.toLowerCase(), contains('aborted'));
      expect(Directory(env.fveHome).existsSync(), isTrue);
    });

    test('aborts on empty input', () async {
      final r = await env.run(['destroy'], stdin: '');
      expect(r.output.toLowerCase(), contains('aborted'));
      expect(Directory(env.fveHome).existsSync(), isTrue);
    });
  });

  // ── Lists versions before confirming ──────────────────────────────────────

  group('fve destroy — summary before confirmation', () {
    setUp(() {
      env.installVersion('3.22.2');
      env.installVersion('3.19.0');
    });

    test('prints the number of installed versions', () async {
      final r = await env.run(['destroy'], stdin: 'no');
      expect(r.output, contains('2'));
    });

    test('prints the installed version numbers', () async {
      final r = await env.run(['destroy'], stdin: 'no');
      expect(r.output, contains('3.22.2'));
    });
  });

  // ── Help ──────────────────────────────────────────────────────────────────

  group('fve destroy --help', () {
    test('exits 0', () async {
      expect((await env.run(['destroy', '--help'])).exitCode, 0);
    });
  });
}
