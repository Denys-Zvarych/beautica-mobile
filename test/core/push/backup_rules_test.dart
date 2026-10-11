import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Phase 066 audit M1: Firebase registration state must be excluded from every
// backup / transfer section. Android path matching is exact (no prefix/glob),
// so only the fixed-name sharedpref store is assertable.
const String _appId =
    '<exclude domain="sharedpref" path="com.google.android.gms.appid.xml"/>';

String _stripComments(String xml) =>
    xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

String _section(String xml, String tag) {
  final m = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(xml);
  expect(m, isNotNull, reason: 'missing <$tag> section');
  return m!.group(1)!;
}

void main() {
  const String base = 'android/app/src/main/res/xml';
  final String full = _stripComments(
    File('$base/backup_rules.xml').readAsStringSync(),
  );
  final String ext = _stripComments(
    File('$base/data_extraction_rules.xml').readAsStringSync(),
  );

  test(
    'backup_rules.xml (full-backup) excludes Firebase appid + keeps others',
    () {
      final s = _section(full, 'full-backup-content');
      expect(s, contains(_appId));
      expect(s, contains('path="FlutterSecureStorage"'));
      expect(s, contains('path="beauticaImages.db"'));
    },
  );

  for (final tag in ['cloud-backup', 'device-transfer']) {
    test(
      'data_extraction_rules.xml <$tag> excludes Firebase appid + keeps others',
      () {
        final s = _section(ext, tag);
        expect(s, contains(_appId));
        expect(s, contains('path="FlutterSecureStorage"'));
        expect(s, contains('path=".flutter_secure_storage"'));
        expect(s, contains('path="beauticaImages.db"'));
      },
    );
  }
}
