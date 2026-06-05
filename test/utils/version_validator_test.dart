import 'package:fve/src/utils/version_validator.dart';
import 'package:test/test.dart';

void main() {
  group('VersionValidator', () {
    test('accepts semantic versions', () {
      expect(VersionValidator.isValid('3.24.0'), isTrue);
      expect(VersionValidator.isValid('2.0.1'), isTrue);
      expect(VersionValidator.isValid('3.24.0-1.0.pre'), isTrue);
      expect(VersionValidator.isValid('1.17.0+hotfix.5'), isTrue);
    });

    test('accepts known channels', () {
      for (final channel in VersionValidator.channels) {
        expect(VersionValidator.isValid(channel), isTrue, reason: channel);
      }
    });

    test('rejects path traversal', () {
      expect(VersionValidator.isValid('../../etc'), isFalse);
      expect(VersionValidator.isValid('..'), isFalse);
      expect(VersionValidator.isValid('foo/bar'), isFalse);
      expect(VersionValidator.isValid('/absolute'), isFalse);
    });

    test('rejects ruby/shell injection payloads', () {
      expect(VersionValidator.isValid("'); system('rm -rf /"), isFalse);
      expect(VersionValidator.isValid('3.0.0\nmalicious'), isFalse);
      expect(VersionValidator.isValid('3.0.0; rm -rf /'), isFalse);
    });

    test('rejects empty and garbage input', () {
      expect(VersionValidator.isValid(''), isFalse);
      expect(VersionValidator.isValid('latest'), isFalse);
      expect(VersionValidator.isValid('v3.24.0'), isFalse);
    });

    test('check() returns valid input and throws on invalid', () {
      expect(VersionValidator.check('3.24.0'), '3.24.0');
      expect(
        () => VersionValidator.check('../../etc'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
