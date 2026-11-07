// Phase 438 D5 — the store-URL sanitizer and the market:// → https order.

import 'package:beautica_mobile/core/app_version/store_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  final Uri fallback = Uri.parse(kPlayStoreFallbackUrl);

  group('sanitizedStoreUri', () {
    test('an https play.google.com URL is kept verbatim', () {
      const String url =
          'https://play.google.com/store/apps/details?id=com.beautica.app';
      expect(sanitizedStoreUri(url), Uri.parse(url));
    });

    test('extra harmless query params (hl) on the allowed listing are kept', () {
      const String url =
          'https://play.google.com/store/apps/details?id=com.beautica.app&hl=uk';
      expect(sanitizedStoreUri(url), Uri.parse(url));
    });

    final Map<String, String?> rejected = <String, String?>{
      'null': null,
      'empty': '',
      'http (not https)': 'http://play.google.com/store/apps/details?id=x',
      'another host': 'https://evil.example/store/apps/details?id=x',
      'look-alike host': 'https://play.google.com.evil.example/x',
      'subdomain': 'https://www.play.google.com/x',
      'user-info trick': 'https://play.google.com@evil.example/x',
      'explicit port': 'https://play.google.com:8443/x',
      'intent scheme': 'intent://details?id=x#Intent;scheme=market;end',
      'javascript': 'javascript:alert(1)',
      'relative': '/store/apps/details?id=x',
      'garbage': '::::',
      'Play host, other path': 'https://play.google.com/x',
      'Play host, developer page':
          'https://play.google.com/store/apps/dev?id=com.beautica.app',
      'Play host, path suffix':
          'https://play.google.com/store/apps/details/x?id=com.beautica.app',
      'Play host, redirect-ish path':
          'https://play.google.com/url?q=https://evil.example',
      'listing, no id': 'https://play.google.com/store/apps/details',
      'listing, empty id': 'https://play.google.com/store/apps/details?id=',
      'listing, other app id':
          'https://play.google.com/store/apps/details?id=com.evil.app',
      'listing, staging id':
          'https://play.google.com/store/apps/details?id=com.beautica.app.staging',
      'listing, duplicate id':
          'https://play.google.com/store/apps/details'
          '?id=com.beautica.app&id=com.evil.app',
      'listing, case-variant id':
          'https://play.google.com/store/apps/details?id=COM.BEAUTICA.APP',
      'listing, fragment':
          'https://play.google.com/store/apps/details?id=com.beautica.app#x',
    };
    for (final MapEntry<String, String?> e in rejected.entries) {
      test('${e.key} → the hard-coded prod Play URL', () {
        expect(sanitizedStoreUri(e.value), fallback);
      });
    }
  });

  test('marketUriFor builds market://details?id=<package>', () {
    expect(
      marketUriFor('com.beautica.app').toString(),
      'market://details?id=com.beautica.app',
    );
  });

  group('openStoreListing', () {
    late List<(Uri, LaunchMode)> calls;

    StoreUrlLauncher launcher(List<Object> results) {
      int i = 0;
      return (Uri uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
        calls.add((uri, mode));
        final Object r = results[i++];
        if (r is Exception) throw r;
        return r as bool;
      };
    }

    setUp(() => calls = <(Uri, LaunchMode)>[]);

    test('market:// first; stops when it launches', () async {
      final bool ok = await openStoreListing(
        storeUrl: kPlayStoreFallbackUrl,
        launcher: launcher(<Object>[true]),
      );
      expect(ok, isTrue);
      expect(calls.single.$1.scheme, 'market');
      expect(calls.single.$2, LaunchMode.externalApplication);
    });

    test('market:// fails → the validated storeUrl', () async {
      const String store =
          'https://play.google.com/store/apps/details?id=com.beautica.app&hl=uk';
      final bool ok = await openStoreListing(
        storeUrl: store,
        launcher: launcher(<Object>[false, true]),
      );
      expect(ok, isTrue);
      expect(calls.map(((Uri, LaunchMode) c) => c.$1.toString()), <String>[
        'market://details?id=com.beautica.app',
        store,
      ]);
    });

    test('a non-Play storeUrl is NEVER launched', () async {
      await openStoreListing(
        storeUrl: 'https://evil.example/apk',
        launcher: launcher(<Object>[false, false]),
      );
      expect(
        calls.map(((Uri, LaunchMode) c) => c.$1.host),
        isNot(contains('evil.example')),
      );
      expect(calls.last.$1, fallback);
    });

    test('market:// targets the sanitized listing id — never a tampered '
        'id', () async {
      await openStoreListing(
        storeUrl: 'https://play.google.com/store/apps/details?id=com.evil.app',
        launcher: launcher(<Object>[false, false]),
      );
      expect(calls.map(((Uri, LaunchMode) c) => c.$1.toString()), <String>[
        'market://details?id=com.beautica.app',
        kPlayStoreFallbackUrl,
      ]);
    });

    test('a throwing launch falls through; both failing → false', () async {
      final bool ok = await openStoreListing(
        storeUrl: kPlayStoreFallbackUrl,
        launcher: launcher(<Object>[Exception('no activity'), false]),
      );
      expect(ok, isFalse);
      expect(calls, hasLength(2));
    });
  });
}
