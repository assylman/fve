import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fve/src/services/download_service.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// A fake [http.Client] for the streaming download path. The first
/// [failTimes] `send` calls return a body that drops mid-stream (simulating a
/// connection reset); subsequent calls stream [payload] in full.
class _FlakyClient extends http.BaseClient {
  _FlakyClient({required this.payload, required this.failTimes});

  final List<int> payload;
  final int failTimes;
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final attempt = calls++;
    if (attempt < failTimes) {
      // Emit a couple of bytes, then error out like a dropped connection.
      final broken = Stream<List<int>>.fromIterable([payload.take(2).toList()])
          .asyncExpand((chunk) async* {
        yield chunk;
        throw http.ClientException('Connection closed while receiving data');
      });
      return http.StreamedResponse(broken, 200, contentLength: payload.length);
    }
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([payload]),
      200,
      contentLength: payload.length,
    );
  }
}

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

  // ── HTTP download retry ─────────────────────────────────────────────────────

  group('DownloadService.download — HTTP streaming retry', () {
    final payload = utf8.encode('flutter sdk archive payload bytes');

    test('retries a dropped connection and ultimately writes the full file',
        () async {
      final client = _FlakyClient(payload: payload, failTimes: 1);
      final service = DownloadService(client: client, aria2Enabled: false);
      final dest = '${tempDir.path}/sdk.tar.xz';

      await service.download('https://example.test/sdk.tar.xz', dest);

      expect(client.calls, 2, reason: 'one failure + one success');
      expect(File(dest).readAsBytesSync(), equals(payload));
    });

    test('gives up after the max attempts with an actionable error', () async {
      final client = _FlakyClient(payload: payload, failTimes: 99);
      final service = DownloadService(client: client, aria2Enabled: false);
      final dest = '${tempDir.path}/sdk.tar.xz';

      try {
        await service.download('https://example.test/sdk.tar.xz', dest);
        fail('Expected the download to fail after retries.');
      } catch (e) {
        expect(e.toString(), contains('Download failed after'));
        expect(e.toString(), contains('aria2c'));
      }
      // Partial file must not be left behind on hard failure.
      expect(File(dest).existsSync(), isFalse);
    });
  });
}
