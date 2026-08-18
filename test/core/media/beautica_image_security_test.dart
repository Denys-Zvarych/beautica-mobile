// Security contract of the shared media loader — the regression tests that
// encode the ADR in core/media/beautica_image.dart.
//
// Covers, in one place:
//   • [isAllowedMediaUrl] — the https-only + exact-host-allowlist guard
//     (control #3): accepts a listed https host, rejects http / look-alike /
//     unknown / null / empty, and rejects EVERYTHING when the allowlist is
//     empty (the fail-closed default).
//   • The injected `dart:io` HttpClient (control #2): system trust context,
//     bounded per-host concurrency, connection + idle timeouts.
//   • [RemoteImage]: renders the fallback for a disallowed URL WITHOUT any
//     network attempt, and carries `TickerMode(enabled: false)` +
//     `excludeFromSemantics` on the allowed path.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';

import '../../helpers/fake_media_cache.dart';
import '../../helpers/pump_app.dart';

const String _kHost = 'pub-abc.r2.dev';

void main() {
  group('isAllowedMediaUrl — https-only + exact host allowlist', () {
    setUp(() => MediaConfig.debugAllowedHosts = <String>{_kHost});
    tearDown(() => MediaConfig.debugAllowedHosts = null);

    test('accepts an https URL on the configured host', () {
      expect(isAllowedMediaUrl('https://$_kHost/avatars/u/1.png'), isTrue);
    });

    test('rejects http (cleartext) on the configured host', () {
      expect(isAllowedMediaUrl('http://$_kHost/avatars/u/1.png'), isFalse);
    });

    test('rejects a look-alike host (suffix attack)', () {
      expect(
        isAllowedMediaUrl('https://$_kHost.evil.example/avatars/u/1.png'),
        isFalse,
      );
    });

    test('rejects a subdomain that is not the exact host', () {
      expect(isAllowedMediaUrl('https://cdn.$_kHost/x.png'), isFalse);
    });

    test('rejects an entirely unknown host', () {
      expect(isAllowedMediaUrl('https://other.r2.dev/x.png'), isFalse);
    });

    test('rejects null and empty', () {
      expect(isAllowedMediaUrl(null), isFalse);
      expect(isAllowedMediaUrl(''), isFalse);
    });

    test('rejects an unparseable / schemeless string', () {
      expect(isAllowedMediaUrl('not a url'), isFalse);
      expect(isAllowedMediaUrl('$_kHost/x.png'), isFalse);
    });
  });

  test('with an EMPTY allowlist, even a valid https URL is rejected '
      '(fail-closed default)', () {
    MediaConfig.debugAllowedHosts = <String>{};
    addTearDown(() => MediaConfig.debugAllowedHosts = null);
    expect(isAllowedMediaUrl('https://$_kHost/x.png'), isFalse);
  });

  group('the injected media HttpClient — ADR control #2', () {
    test('uses the SYSTEM trust store, NOT the pinned dio context', () {
      // The pinned API path builds its own SecurityContext(withTrustedRoots:
      // false); the media path must use the shared system-default singleton.
      // `identical` is exact — this is the regression pin that stops anyone
      // "fixing the asymmetry" by pointing media at the pinned context.
      expect(
        identical(mediaTrustContext, SecurityContext.defaultContext),
        isTrue,
      );
    });

    test('bounds per-host concurrency and sets both timeouts', () {
      // flutter_test_config.dart installs a global HttpOverrides that throws on
      // HttpClient construction (no un-mocked network in tests). We only need
      // to CONSTRUCT the client to read its config — no socket is opened — so
      // clear the override for the construction, then restore it immediately.
      // `global` is setter-only in this SDK; read the active override via
      // `current` (no zone override is installed, so it is the global one).
      final HttpOverrides? saved = HttpOverrides.current;
      HttpOverrides.global = null;
      final HttpClient client;
      try {
        client = buildMediaHttpClient();
      } finally {
        HttpOverrides.global = saved;
      }
      try {
        expect(client.maxConnectionsPerHost, kMediaMaxConnectionsPerHost);
        expect(client.maxConnectionsPerHost, 6);
        expect(client.connectionTimeout, kMediaConnectionTimeout);
        expect(client.connectionTimeout, const Duration(seconds: 10));
        expect(client.idleTimeout, kMediaIdleTimeout);
      } finally {
        client.close(force: true);
      }
    });
  });

  group('RemoteImage — guard renders fallback with no network attempt', () {
    late FakeMediaCacheManager fake;

    setUp(() {
      MediaConfig.debugAllowedHosts = <String>{_kHost};
      fake = FakeMediaCacheManager(mediaLoadingForever);
      debugMediaCacheManager = fake;
    });

    tearDown(() {
      debugMediaCacheManager = null;
      MediaConfig.debugAllowedHosts = null;
    });

    Widget remote(String? url, {bool excludeSemantics = true}) => RemoteImage(
      url: url,
      width: 52,
      height: 52,
      shape: RemoteImageShape.circle,
      excludeFromSemantics: excludeSemantics,
      fallback: const ColoredBox(key: Key('fb'), color: Color(0xFF000000)),
    );

    testWidgets('a disallowed http URL renders the fallback and fetches '
        'nothing', (WidgetTester tester) async {
      await tester.pumpApp(remote('http://$_kHost/x.png'));
      expect(find.byKey(const Key('fb')), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(
        fake.getFileStreamCalls,
        0,
        reason: 'a rejected URL must never reach the cache manager',
      );
    });

    testWidgets('a null URL renders the fallback and fetches nothing', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(remote(null));
      expect(find.byKey(const Key('fb')), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(fake.getFileStreamCalls, 0);
    });

    testWidgets('an allowed https URL builds the Image, pinned to frame 0 and '
        'excluded from semantics', (WidgetTester tester) async {
      await tester.pumpApp(remote('https://$_kHost/x.png'));

      expect(find.byType(Image), findsOneWidget);
      expect(
        fake.getFileStreamCalls,
        1,
        reason:
            'an allowed URL DOES reach the cache manager (positive control)',
      );
      expect(
        tester.widget<Image>(find.byType(Image)).excludeFromSemantics,
        isTrue,
        reason: 'avatar variants must not add a decorative image a11y node',
      );
      expect(
        TickerMode.valuesOf(tester.element(find.byType(Image))).enabled,
        isFalse,
        reason:
            'the effective ticker mode at the Image must be false — an animated '
            'WebP (served un-transcoded) must be pinned to frame 0',
      );
    });
  });
}
