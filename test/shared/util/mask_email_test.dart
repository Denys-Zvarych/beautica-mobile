// Unit tests for maskEmail() — shared between VerificationScreen and
// AuthNotifier debug logs (Phase 2.11 backlog row 160).

import 'package:beautica_mobile/shared/util/mask_email.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('maskEmail', () {
    test('redacts a typical email to first-letter + *** + domain', () {
      expect(maskEmail('anya@example.com'), equals('a***@example.com'));
    });

    test('redacts a single-character local part the same way', () {
      expect(maskEmail('a@example.com'), equals('a***@example.com'));
    });

    test('returns input unchanged when no @ is present', () {
      expect(maskEmail('not-an-email'), equals('not-an-email'));
    });

    test('returns input unchanged when @ is the first character', () {
      expect(maskEmail('@example.com'), equals('@example.com'));
    });

    test('returns empty string unchanged', () {
      expect(maskEmail(''), equals(''));
    });

    test('handles multi-character local part correctly', () {
      expect(maskEmail('master@beautica.test'), equals('m***@beautica.test'));
    });
  });
}
