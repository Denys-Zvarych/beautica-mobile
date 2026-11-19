// M515 (AUTH-46 / AUTH-D15) — login identifier classifier + Ukrainian-mobile
// rule: email / `0…` / `380…` / `+380…` / UA landline / non-UA / junk.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/validators/identifier_classifier.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final AppLocalizations l10n = lookupAppLocalizations(const Locale('uk'));

  group('normalizeUaMobile', () {
    test('accepts 0…, 380…, +380… with spaces / dashes / brackets', () {
      for (final String raw in <String>[
        '0671234567',
        '067 123 45 67',
        '380671234567',
        '+380671234567',
        '+380 (67) 123-45-67',
      ]) {
        expect(normalizeUaMobile(raw), '+380671234567', reason: raw);
      }
    });

    test('accepts every listed mobile operator code', () {
      for (final String code in kUaMobileOperatorCodes) {
        expect(normalizeUaMobile('0${code}1234567'), '+380${code}1234567');
      }
    });

    test('refuses a UA landline (Kyiv 044)', () {
      expect(normalizeUaMobile('0441234567'), isNull);
      expect(normalizeUaMobile('+380441234567'), isNull);
    });

    test('refuses non-UA numbers, wrong lengths and junk', () {
      for (final String raw in <String>[
        '+48512345678',
        '+1 202 555 0123',
        '06712345',
        '067123456789',
        'abc',
        '',
      ]) {
        expect(normalizeUaMobile(raw), isNull, reason: raw);
      }
    });
  });

  group('validateIdentifier', () {
    test('empty → «Введіть телефон або email»', () {
      expect(validateIdentifier('  ', l10n), l10n.errIdentifierRequired);
    });

    test('«@» → email rules', () {
      expect(validateIdentifier('anna@beautica.ua', l10n), isNull);
      expect(validateIdentifier('anna@', l10n), l10n.errEmailInvalid);
    });

    test('no «@» → Ukrainian mobile rule', () {
      expect(validateIdentifier('067 123 45 67', l10n), isNull);
      expect(
        validateIdentifier('+48 512 345 678', l10n),
        'Потрібен український мобільний номер',
      );
      expect(validateIdentifier('0441234567', l10n), l10n.errPhoneNotUaMobile);
    });
  });

  group('normalizeIdentifier', () {
    test('email is trimmed, unchanged otherwise', () {
      expect(normalizeIdentifier(' anna@beautica.ua '), 'anna@beautica.ua');
    });

    test('phone is normalised to +380', () {
      expect(normalizeIdentifier('067 123 45 67'), '+380671234567');
    });
  });
}
