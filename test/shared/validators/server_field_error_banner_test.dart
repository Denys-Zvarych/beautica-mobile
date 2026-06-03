// Unit tests for buildFieldErrorBanner() + localizedFieldName().
//
// These pure functions back the multi-field error banner surfaced on screens
// where the failing field is NOT rendered (verification post-OTP save, register
// step 3 submit). The banner maps each backend field key to a localized display
// name and joins "<name>: <server message>" lines with '\n'.
//
// Covered scenarios:
//   localizedFieldName:
//     1. known key (firstName)      → localized label (Ім'я)
//     2. known alias (businessName) → salon-name label (collapses aliases)
//     3. phone alias (contactPhone) → phone label
//     4. unknown key (foo.bar)      → raw key passed through (never dropped)
//   buildFieldErrorBanner:
//     5. empty map                  → null (caller falls back to serverMessage)
//     6. single known field         → one "<label>: <msg>" line
//     7. multiple fields            → newline-joined, every entry present
//     8. unknown key                → raw key surfaced inline (contract drift)
//
// A real (uk) AppLocalizations is loaded off-tree via lookupAppLocalizations so
// the assertions exercise the actual l10n template, not a fake.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/validators/server_field_error_banner.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final AppLocalizations l10n = lookupAppLocalizations(const Locale('uk'));

  group('localizedFieldName', () {
    test('known key firstName → localized Ім\'я label', () {
      expect(
        localizedFieldName('firstName', l10n),
        equals(l10n.fieldNameFirstName),
      );
    });

    test('alias businessName collapses to the salon-name label', () {
      expect(
        localizedFieldName('businessName', l10n),
        equals(l10n.fieldNameSalonName),
      );
      // `name` and `salonName` alias the same label.
      expect(localizedFieldName('name', l10n), equals(l10n.fieldNameSalonName));
      expect(
        localizedFieldName('salonName', l10n),
        equals(l10n.fieldNameSalonName),
      );
    });

    test('phone aliases (phoneNumber / contactPhone) → phone label', () {
      expect(localizedFieldName('phone', l10n), equals(l10n.fieldNamePhone));
      expect(
        localizedFieldName('phoneNumber', l10n),
        equals(l10n.fieldNamePhone),
      );
      expect(
        localizedFieldName('contactPhone', l10n),
        equals(l10n.fieldNamePhone),
      );
    });

    test('unknown key falls back to the raw key (never silently dropped)', () {
      expect(localizedFieldName('foo.bar', l10n), equals('foo.bar'));
    });
  });

  group('buildFieldErrorBanner', () {
    test('empty map → null (caller falls back to serverMessage)', () {
      expect(buildFieldErrorBanner(const <String, String>{}, l10n), isNull);
    });

    test('single known field → one "<label>: <message>" line', () {
      final banner = buildFieldErrorBanner(const <String, String>{
        'street': 'Required',
      }, l10n);
      expect(
        banner,
        equals(l10n.validationFieldErrorLine(l10n.fieldNameStreet, 'Required')),
      );
      // No spurious newline for a single entry.
      expect(banner!.contains('\n'), isFalse);
    });

    test('multiple fields → newline-joined, every entry present', () {
      final banner = buildFieldErrorBanner(const <String, String>{
        'firstName': 'Too short',
        'phone': 'Invalid',
      }, l10n);
      expect(banner, isNotNull);
      // Two lines joined with '\n'.
      expect(banner!.split('\n'), hasLength(2));
      expect(
        banner,
        contains(
          l10n.validationFieldErrorLine(l10n.fieldNameFirstName, 'Too short'),
        ),
      );
      expect(
        banner,
        contains(l10n.validationFieldErrorLine(l10n.fieldNamePhone, 'Invalid')),
      );
    });

    test(
      'unknown key is surfaced inline using the raw key (contract drift)',
      () {
        final banner = buildFieldErrorBanner(const <String, String>{
          'mysteryField': 'boom',
        }, l10n);
        expect(
          banner,
          equals(l10n.validationFieldErrorLine('mysteryField', 'boom')),
        );
      },
    );
  });
}
