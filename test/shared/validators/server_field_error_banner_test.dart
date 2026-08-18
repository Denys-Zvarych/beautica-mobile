// Unit tests for buildFieldErrorBanner() + localizedFieldName().
//
// These pure functions back the multi-field error banner surfaced on screens
// where the failing field is NOT rendered (verification post-OTP save, register
// step 3 submit). The banner maps each backend field key to a localized display
// name and joins "<name>: <fieldErrorGeneric>" lines with '\n' — the backend's
// raw per-field VALUE is never included (mobile-security, 2026-08): this banner
// routes to a live-narrated generic surface (VelvetSnack / AuthBanner), so
// untranslated/technical server text must not reach it.
//
// Covered scenarios:
//   localizedFieldName:
//     1. known key (firstName)      → localized label (Ім'я)
//     2. known alias (businessName) → salon-name label (collapses aliases)
//     3. phone alias (contactPhone) → phone label
//     4. unknown key (foo.bar)      → raw key passed through (never dropped)
//   buildFieldErrorBanner:
//     5. empty map                  → null (caller falls back to userMessage)
//     6. single known field         → one "<label>: <fieldErrorGeneric>" line,
//        and the raw server-supplied value is NOT present anywhere in it
//     7. multiple fields            → newline-joined, every field NAME present,
//        every raw server VALUE absent
//     8. unknown key                → raw key surfaced inline (contract drift),
//        raw server value still dropped
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

    // mobile-security, 2026-08: `ErrorMapperInterceptor._extractFieldErrors`
    // caps the backend `errors` map's VALUES at 200 chars but never caps the
    // KEYS at all. An unrecognized key falls through to this raw-key path and
    // is rendered inside a `Semantics(liveRegion: true)` VelvetSnack/AuthBanner
    // — narrated to screen readers verbatim. An oversized or control-char
    // laden key must NOT reach that surface; it must fall back to the
    // localized generic field-name label instead.
    test('unknown key LONGER than the field-name cap falls back to the '
        'localized generic label, not the raw key', () {
      final String longKey = 'x' * 41;
      expect(
        localizedFieldName(longKey, l10n),
        equals(l10n.fieldNameUnknown),
        reason:
            'an oversized raw JSON key must never reach a live-narrated '
            'liveRegion surface verbatim',
      );
    });

    test('unknown key carrying a control character falls back to the '
        'localized generic label, not the raw key', () {
      // U+202E is RIGHT-TO-LEFT OVERRIDE — written as an escape, not a
      // literal, so the hostile code point is visible on review (see
      // server_field_message_test.dart's header for why).
      const String hostileKey = 'ab\u202Ecd';
      expect(
        localizedFieldName(hostileKey, l10n),
        equals(l10n.fieldNameUnknown),
        reason:
            'a bidi-override / control character in a raw JSON key must '
            'never reach a live-narrated liveRegion surface verbatim',
      );
    });

    test('unknown key AT the field-name cap is still shown verbatim '
        '(cap is inclusive, mirrors serverFieldMessageOr)', () {
      final String atCapKey = 'x' * 40;
      expect(localizedFieldName(atCapKey, l10n), equals(atCapKey));
    });
  });

  group('buildFieldErrorBanner', () {
    test('empty map → null (caller falls back to Failure.userMessage)', () {
      expect(buildFieldErrorBanner(const <String, String>{}, l10n), isNull);
    });

    test('single known field → one "<label>: <fieldErrorGeneric>" line, raw '
        'server value dropped', () {
      final banner = buildFieldErrorBanner(const <String, String>{
        'street': 'Required',
      }, l10n);
      expect(
        banner,
        equals(
          l10n.validationFieldErrorLine(
            l10n.fieldNameStreet,
            l10n.fieldErrorGeneric,
          ),
        ),
      );
      // No spurious newline for a single entry.
      expect(banner!.contains('\n'), isFalse);
      // The raw backend value must never leak into this live-narrated
      // surface (mobile-security, 2026-08).
      expect(banner, isNot(contains('Required')));
    });

    test('multiple fields → newline-joined, every field name present, every '
        'raw server value dropped', () {
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
          l10n.validationFieldErrorLine(
            l10n.fieldNameFirstName,
            l10n.fieldErrorGeneric,
          ),
        ),
      );
      expect(
        banner,
        contains(
          l10n.validationFieldErrorLine(
            l10n.fieldNamePhone,
            l10n.fieldErrorGeneric,
          ),
        ),
      );
      // Neither raw backend value leaked through.
      expect(banner, isNot(contains('Too short')));
      expect(banner, isNot(contains('Invalid')));
    });

    test('unknown key is surfaced inline using the raw key (contract drift), '
        'raw server value still dropped', () {
      final banner = buildFieldErrorBanner(const <String, String>{
        'mysteryField': 'boom',
      }, l10n);
      expect(
        banner,
        equals(
          l10n.validationFieldErrorLine('mysteryField', l10n.fieldErrorGeneric),
        ),
      );
      expect(banner, isNot(contains('boom')));
    });
  });
}
