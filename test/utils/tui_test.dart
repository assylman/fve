import 'package:fve/src/utils/tui.dart';
import 'package:test/test.dart';

// Tests run with stdout redirected (not a TTY), so _ansi returns false and
// all rendering is a no-op.  We verify public API contracts: no throws,
// correct behaviour at boundary values, and spinner timer lifecycle.

void main() {
  // ── ProgressBar ────────────────────────────────────────────────────────────

  group('ProgressBar', () {
    test('instantiates with a known total', () {
      expect(
        () => ProgressBar(total: 1000, label: 'flutter.zip'),
        returnsNormally,
      );
    });

    test('instantiates with unknown total (total = 0)', () {
      expect(
        () => ProgressBar(total: 0, label: 'flutter.zip'),
        returnsNormally,
      );
    });

    test('update() does not throw', () {
      final bar = ProgressBar(total: 1000, label: 'flutter.zip');
      expect(() => bar.update(500), returnsNormally);
    });

    test('complete() does not throw', () {
      final bar = ProgressBar(total: 1000, label: 'flutter.zip');
      bar.update(500);
      expect(() => bar.complete(), returnsNormally);
    });

    test('complete() without prior update() does not throw', () {
      final bar = ProgressBar(total: 500, label: 'flutter.zip');
      expect(() => bar.complete(), returnsNormally);
    });

    test('update() with received > total does not throw', () {
      final bar = ProgressBar(total: 100, label: 'flutter.zip');
      expect(() => bar.update(200), returnsNormally);
    });

    test('update() with zero total (unknown size) does not throw', () {
      final bar = ProgressBar(total: 0, label: 'flutter.zip');
      expect(() => bar.update(1024 * 1024), returnsNormally);
    });

    test('multiple sequential update() calls do not throw', () {
      final bar = ProgressBar(total: 1000, label: 'flutter.zip');
      for (var i = 0; i <= 1000; i += 100) {
        bar.update(i);
      }
      expect(() => bar.complete(), returnsNormally);
    });

    test('update() at exact total followed by complete() does not throw', () {
      final bar = ProgressBar(total: 512, label: 'flutter.zip');
      bar.update(512);
      expect(() => bar.complete(), returnsNormally);
    });

    test('handles a label longer than 32 characters without throwing', () {
      final bar = ProgressBar(
        total: 1000,
        label: 'flutter_linux_x64_3.22.2-stable_archive.tar.xz',
      );
      expect(() => bar.update(400), returnsNormally);
    });

    test('handles empty label without throwing', () {
      final bar = ProgressBar(total: 100, label: '');
      expect(() => bar.update(50), returnsNormally);
    });
  });

  // ── Spinner ────────────────────────────────────────────────────────────────

  group('Spinner', () {
    test('instantiates', () {
      expect(() => Spinner('Extracting SDK'), returnsNormally);
    });

    test('start() does not throw', () {
      final s = Spinner('Test');
      expect(() => s.start(), returnsNormally);
      s.stop();
    });

    test('stop() after start() does not throw', () async {
      final s = Spinner('Test');
      s.start();
      await Future.delayed(const Duration(milliseconds: 100));
      expect(() => s.stop(), returnsNormally);
    });

    test('stop() with done message does not throw', () {
      final s = Spinner('Checking');
      s.start();
      expect(() => s.stop(done: 'All good'), returnsNormally);
    });

    test('stop() without calling start() does not throw', () {
      final s = Spinner('Orphan');
      expect(() => s.stop(), returnsNormally);
    });

    test('stop() can be called multiple times without throwing', () {
      final s = Spinner('Multi-stop');
      s.start();
      s.stop();
      expect(() => s.stop(), returnsNormally);
    });

    test('calling start() then stop() then start() again does not throw', () {
      final s = Spinner('Restart');
      s.start();
      s.stop();
      s.start();
      expect(() => s.stop(), returnsNormally);
    });
  });
}
