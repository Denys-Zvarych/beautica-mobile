// SUP-34 / SUP-68 — the app's legal versions must equal the `updated:` date
// of the website legal docs. The website is a sibling, private repo that the
// mobile CI does NOT check out, so this only runs on a dev machine with both
// repos side by side. When the sibling is absent the tests are SKIPPED with a
// loud reason (never a silent pass); set BEAUTICA_REQUIRE_WEBSITE_PARITY=1 to
// turn the absence into a failure.

import 'dart:io';

import 'package:beautica_mobile/shared/utils/legal_versions.dart';
import 'package:flutter_test/flutter_test.dart';

const String _legalDir = '../beautica-website/src/content/legal/uk';

/// The `updated:` frontmatter date of [file], or null when the file is absent.
String? _updated(String file) {
  final File f = File('$_legalDir/$file');
  if (!f.existsSync()) return null;
  final Match? m = RegExp(
    r'^updated:\s*(\d{4}-\d{2}-\d{2})\s*$',
    multiLine: true,
  ).firstMatch(f.readAsStringSync());
  return m?.group(1);
}

void main() {
  final bool require =
      Platform.environment['BEAUTICA_REQUIRE_WEBSITE_PARITY'] == '1';
  final bool present = Directory(_legalDir).existsSync();
  final String? skip = present
      ? null
      : 'SKIPPED: sibling repo not found at $_legalDir (expected on CI) — '
            'legal-version parity NOT verified in this run';

  if (!present) {
    // ignore: avoid_print
    print('WARNING $skip');
  }

  if (!present && require) {
    test('website legal docs are available', () {
      fail('BEAUTICA_REQUIRE_WEBSITE_PARITY=1 but $_legalDir is missing');
    });
    return;
  }

  test('kTermsVersion equals terms.md updated: date', () {
    expect(_updated('terms.md'), isNotNull, reason: 'no updated: in terms.md');
    expect(kTermsVersion, _updated('terms.md'));
  }, skip: skip);

  test('kPrivacyPolicyVersion equals privacy.md updated: date', () {
    expect(
      _updated('privacy.md'),
      isNotNull,
      reason: 'no updated: in privacy.md',
    );
    expect(kPrivacyPolicyVersion, _updated('privacy.md'));
  }, skip: skip);
}
