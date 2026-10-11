// mobile-qa gap-closure (salon-cover work, 2026-08-29) — `salon_cover_widgets.dart`
// had zero dedicated test file despite being SHARED render code consumed by
// both `PublicSalonProfileScreen` and `SalonManagementProfileScreen` (see
// `mobile-build-verifier`'s finding: no golden or widget test anywhere
// exercises `CoverIconButton`, `SalonCover`, or either cover-consuming
// screen — 280 golden tests passed unchanged through a new icon appearing
// on the cover AND a pill being deleted from it).
//
// This file covers the ONE new API surface that shipped here:
// `CoverIconButton.icon`/`svgIcon` — relaxed from a required `IconData` to
// two mutually-exclusive optional fields, guarded by
// `assert((icon == null) != (svgIcon == null))`. Without a test, that
// invariant is decoration — nothing proves the assert actually fires, and
// nothing proves each valid branch renders the widget type it claims to.

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_cover_widgets.dart';
import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/fake_media_cache.dart';
import '../../../../helpers/pump_app.dart';

void main() {
  group('CoverIconButton icon/svgIcon invariant', () {
    test('throws AssertionError when NEITHER icon nor svgIcon is provided', () {
      expect(
        () => CoverIconButton(
          onTap: () {},
          semanticLabel: 'x',
          // icon and svgIcon both default to null — assertion fires here.
        ),
        throwsAssertionError,
      );
    });

    test('throws AssertionError when BOTH icon and svgIcon are provided', () {
      expect(
        () => CoverIconButton(
          icon: Icons.tune_rounded,
          svgIcon: BeauticaAssetIcons.notificationUnread,
          onTap: () {},
          semanticLabel: 'x',
        ),
        throwsAssertionError,
      );
    });

    testWidgets('icon-only renders a Material Icon, never AppIcon', (
      tester,
    ) async {
      await tester.pumpApp(
        CoverIconButton(
          key: const Key('under-test'),
          icon: Icons.tune_rounded,
          onTap: () {},
          semanticLabel: 'x',
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('under-test')),
          matching: find.byType(Icon),
        ),
        findsOneWidget,
        reason: 'the icon-only branch must render Material\'s Icon',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('under-test')),
          matching: find.byType(AppIcon),
        ),
        findsNothing,
        reason: 'the icon-only branch must NOT also render AppIcon',
      );
    });

    testWidgets('svgIcon-only renders AppIcon, never a Material Icon', (
      tester,
    ) async {
      await tester.pumpApp(
        CoverIconButton(
          key: const Key('under-test'),
          svgIcon: BeauticaAssetIcons.notificationUnread,
          onTap: () {},
          semanticLabel: 'x',
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('under-test')),
          matching: find.byType(AppIcon),
        ),
        findsOneWidget,
        reason:
            'the svgIcon-only branch must render AppIcon, matching '
            'the notification bell\'s multicolour asset',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('under-test')),
          matching: find.byType(Icon),
        ),
        findsNothing,
        reason:
            'the svgIcon-only branch must NOT also render a Material '
            'Icon',
      );
    });
  });

  // ── Phase 369 — SalonLogo / SalonCover render the uploaded photo ─────────
  group('Phase 369 photo rendering', () {
    late FakeMediaCacheManager cache;
    setUp(() {
      MediaConfig.debugAllowedHosts = <String>{'media.test'};
      cache = FakeMediaCacheManager(mediaLoadingForever);
      debugMediaCacheManager = cache;
    });
    tearDown(() {
      debugMediaCacheManager = null;
      MediaConfig.debugAllowedHosts = null;
    });

    const String allowed = 'https://media.test/salons/1/x.jpg';
    const String evil = 'https://evil.test/x.jpg';

    Widget cover(String? url) => Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 360,
        child: SalonCover(height: 232, topInset: 0, imageUrl: url),
      ),
    );

    testWidgets('SalonLogo: null → the monogram, no image, no fetch', (
      tester,
    ) async {
      await tester.pumpApp(const SalonLogo(diameter: 68, monogram: 'В'));
      // i18n-finder-ok: the salon-name initial is fixture data, not UI copy.
      expect(find.text('В'), findsOneWidget);
      expect(find.byType(RemoteImage), findsNothing);
      expect(cache.getFileStreamCalls, 0);
    });

    testWidgets('SalonLogo: an allowed URL renders the circle-clipped photo '
        'at the inner (inside-the-ring) size', (tester) async {
      await tester.pumpApp(
        const SalonLogo(diameter: 68, monogram: 'В', imageUrl: allowed),
      );
      final RemoteImage img = tester.widget<RemoteImage>(
        find.byType(RemoteImage),
      );
      expect(img.url, allowed);
      expect(img.shape, RemoteImageShape.circle);
      expect((img.width, img.height), (64.0, 64.0));
      expect(find.byType(Image), findsOneWidget);
      expect(cache.getFileStreamCalls, 1);
    });

    testWidgets('SalonLogo: a disallowed host keeps the monogram and never '
        'fetches', (tester) async {
      await tester.pumpApp(
        const SalonLogo(diameter: 68, monogram: 'В', imageUrl: evil),
      );
      // i18n-finder-ok: the salon-name initial is fixture data, not UI copy.
      expect(find.text('В'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(cache.getFileStreamCalls, 0);
    });

    testWidgets('SalonLogo: a failed fetch falls back to the monogram', (
      tester,
    ) async {
      cache.responder = mediaFetchError;
      // A URL of its own: the image cache keeps the earlier tests' pending
      // (loading-forever) stream for `allowed`.
      await tester.pumpApp(
        const SalonLogo(
          diameter: 68,
          monogram: 'В',
          imageUrl: 'https://media.test/salons/1/broken.jpg',
        ),
      );
      for (int i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      // i18n-finder-ok: the salon-name initial is fixture data, not UI copy.
      expect(find.text('В'), findsOneWidget);
    });

    testWidgets('SalonCover: null → the gradient placeholder (glyph), no '
        'image', (tester) async {
      await tester.pumpApp(cover(null));
      expect(find.byIcon(Icons.photo_camera_back_outlined), findsOneWidget);
      expect(find.byType(RemoteImage), findsNothing);
      expect(cache.getFileStreamCalls, 0);
    });

    testWidgets('SalonCover: an allowed URL renders the photo full-bleed, '
        'BoxFit.cover, under the legibility veil', (tester) async {
      await tester.pumpApp(cover(allowed));
      final RemoteImage img = tester.widget<RemoteImage>(
        find.byType(RemoteImage),
      );
      expect(img.url, allowed);
      expect(img.fit, BoxFit.cover);
      expect((img.width, img.height), (360.0, 232.0));
      expect(cache.getFileStreamCalls, 1);
      expect(
        find.byIcon(Icons.photo_camera_back_outlined),
        findsNothing,
        reason: 'the placeholder glyph is only the fallback now',
      );
    });

    testWidgets('SalonCover: a disallowed host renders exactly the '
        'placeholder and never fetches', (tester) async {
      await tester.pumpApp(cover(evil));
      expect(find.byType(RemoteImage), findsNothing);
      expect(find.byIcon(Icons.photo_camera_back_outlined), findsOneWidget);
      expect(cache.getFileStreamCalls, 0);
    });

    testWidgets('read-only marks carry no edit badge', (tester) async {
      await tester.pumpApp(
        const SalonLogo(diameter: 68, monogram: 'В', imageUrl: allowed),
      );
      expect(find.byType(PhotoEditBadge), findsNothing);
    });
  });
}
