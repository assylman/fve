import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fve/src/services/download_service.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fve_download_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // ── verifySha256 ──────────────────────────────────────────────────────────

  group('DownloadService.verifySha256', () {
    late DownloadService service;

    setUp(() => service = DownloadService());

    String sha256Of(List<int> bytes) => sha256.convert(bytes).toString();

    test('passes when the file matches the expected checksum', () async {
      final content = utf8.encode('flutter sdk archive content');
      final file = File('${tempDir.path}/archive.zip')
        ..writeAsBytesSync(content);

      expect(
        () => service.verifySha256(file.path, sha256Of(content)),
        returnsNormally,
      );
    });

    test('throws when the checksum does not match', () async {
      final file = File('${tempDir.path}/archive.zip')
        ..writeAsStringSync('corrupted data');

      expect(
        () => service.verifySha256(file.path, 'a' * 64),
        throwsException,
      );
    });

    test('skips verification when expectedSha256 is an empty string', () async {
      // An empty sha256 means "no checksum provided" — must not throw.
      final file = File('${tempDir.path}/archive.zip')
        ..writeAsStringSync('any content');

      expect(
        () => service.verifySha256(file.path, ''),
        returnsNormally,
      );
    });

    test('error message includes the expected and actual checksums', () async {
      final file = File('${tempDir.path}/archive.zip')
        ..writeAsStringSync('real content');

      final wrongHash = 'f' * 64;

      try {
        await service.verifySha256(file.path, wrongHash);
        fail('Expected an exception to be thrown.');
      } catch (e) {
        expect(e.toString(), contains(wrongHash));
        expect(e.toString(), contains(sha256Of(utf8.encode('real content'))));
      }
    });

    test('validates against the actual sha256 of binary content', () async {
      // Use a known 8-byte payload to make the expected hash deterministic.
      final bytes = [0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE];
      final file = File('${tempDir.path}/binary.zip')
        ..writeAsBytesSync(bytes);
      final expected = sha256Of(bytes);

      expect(
        () => service.verifySha256(file.path, expected),
        returnsNormally,
      );
    });
  });
}
