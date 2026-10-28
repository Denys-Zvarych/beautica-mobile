// Branch fix/login-unverified-403 QA — [PublicWebLinks] are the only legal
// URLs the app opens (registration step 1 + Account «Правова інформація»).
// They must stay on the single allow-listed website origin.

import 'package:beautica_mobile/core/config/app_config.dart';
import 'package:beautica_mobile/shared/utils/public_web_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PublicWebLinks', () {
    test('terms is exactly https://beautica.app/terms', () {
      expect(PublicWebLinks.terms.toString(), 'https://beautica.app/terms');
    });

    test('privacy is exactly https://beautica.app/privacy', () {
      expect(PublicWebLinks.privacy.toString(), 'https://beautica.app/privacy');
    });

    for (final (String name, Uri uri, String path) in <(String, Uri, String)>[
      ('terms', PublicWebLinks.terms, '/terms'),
      ('privacy', PublicWebLinks.privacy, '/privacy'),
    ]) {
      test('$name is built from AppConfig.publicWebOrigin: https, the '
          'allow-listed host, no port/userinfo/query/fragment', () {
        expect(uri.toString(), '${AppConfig.publicWebOrigin}$path');
        expect(uri.scheme, 'https');
        expect(uri.host, AppConfig.publicWebHost);
        expect(uri.hasPort, isFalse);
        expect(uri.userInfo, isEmpty);
        expect(uri.path, path);
        expect(uri.hasQuery, isFalse);
        expect(uri.hasFragment, isFalse);
      });
    }
  });
}
