import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/fve_process.dart';

void main() {
  late FveTestEnv env;
  late Directory project;

  setUp(() {
    env = FveTestEnv.create();
    project = env.createProjectDir();
  });
  tearDown(() => env.dispose());

  // Creates a directory with one file so we can assert on its removal.
  void mkdir(String rel) {
    final d = Directory(p.join(project.path, p.joinAll(rel.split('/'))))
      ..createSync(recursive: true);
    File(p.join(d.path, 'x')).writeAsStringSync('x');
  }

  bool exists(String rel) =>
      Directory(p.join(project.path, p.joinAll(rel.split('/')))).existsSync();

  group('fve clean --help', () {
    test('exits 0', () async {
      final r = await env.run(['clean', '--help']);
      expect(r.exitCode, 0);
    });
  });

  group('fve clean', () {
    test('removes build artifacts but preserves ios/Pods', () async {
      mkdir('build');
      mkdir('.dart_tool');
      mkdir('ios/Pods');
      mkdir('ios/.symlinks');

      final r = await env.run(['clean'], workingDir: project.path);

      expect(r.exitCode, 0, reason: r.toString());
      expect(exists('build'), isFalse);
      expect(exists('.dart_tool'), isFalse);
      expect(exists('ios/Pods'), isTrue); // preserved
      expect(exists('ios/.symlinks'), isTrue); // preserved
      expect(r.output.toLowerCase(), contains('preserved'));
    });

    test('--pods also removes ios/Pods and ios/.symlinks', () async {
      mkdir('build');
      mkdir('ios/Pods');
      mkdir('ios/.symlinks');

      final r = await env.run(['clean', '--pods'], workingDir: project.path);

      expect(r.exitCode, 0, reason: r.toString());
      expect(exists('build'), isFalse);
      expect(exists('ios/Pods'), isFalse);
      expect(exists('ios/.symlinks'), isFalse);
    });

    test('says nothing to clean on an empty project', () async {
      final r = await env.run(['clean'], workingDir: project.path);
      expect(r.exitCode, 0);
      expect(r.output.toLowerCase(), contains('nothing to clean'));
    });
  });
}
