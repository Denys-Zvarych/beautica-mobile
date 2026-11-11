// Phase 443 — legal document version constants: format + not-in-the-future
// (mirrors the backend 442 `@Pattern` + `@PolicyVersionDate` checks).

import 'package:beautica_mobile/shared/utils/legal_versions.dart';
import 'package:flutter_test/flutter_test.dart';

final RegExp _format = RegExp(r'^\d{4}-\d{2}-\d{2}(\.\d{1,3})?$');

DateTime _datePart(String version) {
  final String date = version.split('.').first;
  final DateTime parsed = DateTime.parse(date);
  // Reject roll-over dates such as 2026-02-30 (DateTime.parse normalises).
  final String roundTrip =
      '${parsed.year.toString().padLeft(4, '0')}-'
      '${parsed.month.toString().padLeft(2, '0')}-'
      '${parsed.day.toString().padLeft(2, '0')}';
  expect(roundTrip, date, reason: '$version is not a real calendar date');
  return parsed;
}

void main() {
  for (final (String name, String value) in <(String, String)>[
    ('kTermsVersion', kTermsVersion),
    ('kPrivacyPolicyVersion', kPrivacyPolicyVersion),
  ]) {
    test('$name matches the backend version format', () {
      expect(_format.hasMatch(value), isTrue, reason: value);
    });

    test('$name is a real date that is not in the future', () {
      final DateTime date = _datePart(value);
      // Compared against UTC "tomorrow" so a Kyiv-vs-UTC day boundary can
      // never flake this test; the backend allows today.
      // instant-ok: test-only bound
      final DateTime nowUtc = DateTime.now().toUtc();
      final DateTime tomorrow = DateTime.utc(
        nowUtc.year,
        nowUtc.month,
        nowUtc.day + 1,
      );
      expect(
        DateTime.utc(date.year, date.month, date.day).isBefore(tomorrow),
        isTrue,
        reason: '$name=$value is in the future',
      );
    });
  }

  test('current versions equal the website legal docs (phase 443 D5)', () {
    expect(kTermsVersion, '2026-10-29');
    expect(kPrivacyPolicyVersion, '2026-11-07');
  });
}
