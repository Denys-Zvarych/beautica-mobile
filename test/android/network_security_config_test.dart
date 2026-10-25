import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// File-scan guard for the phase 408 per-flavor TLS / App-Link / applicationId
/// wiring. Reads raw Android sources relative to the package root.
const String _res = 'android/app/src';
const String _stagingHost = 'beautica-backend-staging.up.railway.app';
const String _prodHost = 'api.beautica.app';

String _read(String p) {
  final File f = File(p);
  if (!f.existsSync()) throw StateError('missing $p');
  return f.readAsStringSync();
}

/// `<domain ...>HOST</domain>` values inside non-comment XML.
List<String> _domains(String xml) {
  final String noComments = xml.replaceAll(
    RegExp(r'<!--.*?-->', dotAll: true),
    '',
  );
  return RegExp(
    r'<domain\b[^>]*>([^<]+)</domain>',
  ).allMatches(noComments).map((RegExpMatch m) => m.group(1)!.trim()).toList();
}

void main() {
  final String main = _read('$_res/main/res/xml/network_security_config.xml');
  final String staging = _read(
    '$_res/staging/res/xml/network_security_config.xml',
  );
  final String prod = _read('$_res/prod/res/xml/network_security_config.xml');
  final String gradle = _read('android/app/build.gradle.kts');
  final String manifest = _read('$_res/main/AndroidManifest.xml');

  test('src/main has no <domain> pin but keeps a HTTPS-only base-config', () {
    expect(_domains(main), isEmpty);
    expect(main, contains('<base-config cleartextTrafficPermitted="false">'));
  });

  test('src/staging pins only the staging API host, with both ISRG roots', () {
    expect(_domains(staging), <String>[_stagingHost]);
    expect(staging, contains('@raw/isrg_root_x1'));
    expect(staging, contains('@raw/isrg_root_x2'));
  });

  test('src/prod pins only the prod API host, with both ISRG roots', () {
    expect(_domains(prod), <String>[_prodHost]);
    expect(prod, contains('@raw/isrg_root_x1'));
    expect(prod, contains('@raw/isrg_root_x2'));
  });

  test('media hosts are NOT pinned anywhere (system trust store)', () {
    for (final String xml in <String>[main, staging, prod]) {
      for (final String d in _domains(xml)) {
        expect(d, isNot(contains('media.beautica.app')));
        expect(d, isNot(contains('r2.dev')));
        expect(d, isNot(contains('cloudflare')));
      }
    }
  });

  test('flavor configs carry no cleartext permission', () {
    expect(staging, isNot(contains('cleartextTrafficPermitted="true"')));
    expect(prod, isNot(contains('cleartextTrafficPermitted="true"')));
  });

  test('no Android source mentions the dead production Railway host', () {
    final List<File> files = Directory('android')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (File f) =>
              !f.path.contains('/build/') &&
              !f.path.contains('/.gradle/') &&
              (f.path.endsWith('.xml') ||
                  f.path.endsWith('.kts') ||
                  f.path.endsWith('.kt') ||
                  f.path.endsWith('.java') ||
                  f.path.endsWith('.gradle')),
        )
        .toList();
    expect(files, isNotEmpty);
    for (final File f in files) {
      expect(
        utf8.decode(f.readAsBytesSync(), allowMalformed: true),
        isNot(contains('beautica-backend-production.up.railway.app')),
        reason: f.path,
      );
    }
  });

  group('build.gradle.kts flavors', () {
    test('base applicationId is com.beautica.app; namespace unchanged', () {
      expect(gradle, contains('val prodApplicationId = "com.beautica.app"'));
      expect(gradle, contains('applicationId = prodApplicationId'));
      expect(gradle, contains('namespace = "com.beautica.beautica_mobile"'));
    });

    test('staging adds the .staging suffix; prod adds none', () {
      final RegExpMatch? stagingBlock = RegExp(
        r'create\("staging"\)\s*\{(.*?)\n        \}',
        dotAll: true,
      ).firstMatch(gradle);
      final RegExpMatch? prodBlock = RegExp(
        r'create\("prod"\)\s*\{(.*?)\n        \}',
        dotAll: true,
      ).firstMatch(gradle);
      expect(stagingBlock, isNotNull);
      expect(prodBlock, isNotNull);
      expect(
        stagingBlock!.group(1),
        contains('applicationIdSuffix = ".staging"'),
      );
      expect(stagingBlock.group(1), contains('Beautica β'));
      expect(prodBlock!.group(1), isNot(contains('applicationIdSuffix')));
      expect(prodBlock.group(1), contains('"app_name", "Beautica")'));
    });

    test('appLinkHost placeholders: prod beautica.app, staging unverified', () {
      expect(
        gradle,
        contains('manifestPlaceholders["appLinkHost"] = "beautica.app"'),
      );
      expect(
        gradle,
        contains(
          'manifestPlaceholders["appLinkHost"] = "staging.beautica.app"',
        ),
      );
    });

    test('single env dimension with exactly the two flavors', () {
      expect(gradle, contains('flavorDimensions += "env"'));
      expect(
        RegExp(
          r'create\("(\w+)"\)\s*\{\s*\n\s*dimension',
        ).allMatches(gradle).map((RegExpMatch m) => m.group(1)).toSet(),
        <String?>{'staging', 'prod'},
      );
    });
  });

  test('manifest uses the flavor placeholders for host and label', () {
    expect(manifest, contains('android:host="\${appLinkHost}"'));
    expect(manifest, contains('android:label="@string/app_name"'));
    expect(manifest, contains('android:pathPrefix="/invite/accept"'));
  });

  test('staging launcher icon override exists at every density', () {
    for (final String d in <String>[
      'mdpi',
      'hdpi',
      'xhdpi',
      'xxhdpi',
      'xxxhdpi',
    ]) {
      expect(
        File('$_res/staging/res/mipmap-$d/launcher_icon.png').existsSync(),
        isTrue,
        reason: d,
      );
      expect(
        File(
          '$_res/staging/res/drawable-$d/ic_launcher_foreground.png',
        ).existsSync(),
        isTrue,
        reason: d,
      );
    }
  });
}
