import 'dart:io';

import 'package:fve/src/utils/platform_utils.dart';
import 'package:test/test.dart';

void main() {
  group('currentPlatform', () {
    test('returns FvePlatform.macOS when running on macOS', () {
      if (Platform.isMacOS) {
        expect(currentPlatform, FvePlatform.macOS);
      }
    });

    test('returns FvePlatform.linux when running on Linux', () {
      if (Platform.isLinux) {
        expect(currentPlatform, FvePlatform.linux);
      }
    });

    test('does not throw on the current platform', () {
      expect(() => currentPlatform, returnsNormally);
    });
  });

  group('currentArch', () {
    test('returns a valid FveArch value without throwing', () {
      expect(() => currentArch, returnsNormally);
      expect(FveArch.values, contains(currentArch));
    });

    test('returns x64 or arm64', () {
      expect([FveArch.x64, FveArch.arm64], contains(currentArch));
    });
  });

  group('platformKey', () {
    test('returns "macos" on macOS', () {
      if (Platform.isMacOS) expect(platformKey, 'macos');
    });

    test('returns "linux" on Linux', () {
      if (Platform.isLinux) expect(platformKey, 'linux');
    });

    test('returns "windows" on Windows', () {
      if (Platform.isWindows) expect(platformKey, 'windows');
    });

    test('is a non-empty lowercase string', () {
      expect(platformKey, isNotEmpty);
      expect(platformKey, equals(platformKey.toLowerCase()));
    });
  });

  group('releasesJsonUrl', () {
    test('is a valid HTTPS URL', () {
      expect(releasesJsonUrl, startsWith('https://'));
    });

    test('contains the platform key', () {
      expect(releasesJsonUrl, contains(platformKey));
    });

    test('ends with .json', () {
      expect(releasesJsonUrl, endsWith('.json'));
    });

    test('points to the official Flutter releases storage bucket', () {
      expect(
        releasesJsonUrl,
        contains('storage.googleapis.com/flutter_infra_release'),
      );
    });
  });

  group('flutterBinaryName', () {
    test('returns "flutter" on non-Windows', () {
      if (!Platform.isWindows) {
        expect(flutterBinaryName, 'flutter');
      }
    });

    test('returns "flutter.bat" on Windows', () {
      if (Platform.isWindows) {
        expect(flutterBinaryName, 'flutter.bat');
      }
    });
  });

  group('dartBinaryName', () {
    test('returns "dart" on non-Windows', () {
      if (!Platform.isWindows) {
        expect(dartBinaryName, 'dart');
      }
    });

    test('returns "dart.bat" on Windows', () {
      if (Platform.isWindows) {
        expect(dartBinaryName, 'dart.bat');
      }
    });
  });
}
