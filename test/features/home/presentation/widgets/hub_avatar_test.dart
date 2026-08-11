// Phase F — [HubAvatar]'s additive `imageUrl` / `fallbackIcon` parameters.
//
// [HubAvatar] predates a photo path entirely — every call site until Phase F
// (the wish-list's SALON-row avatar) passed only `initials`/`size`. That path
// MUST stay byte-for-byte unchanged: this file pins that the null-`imageUrl`
// branch renders the exact gradient disc it always has (no `RemoteImage` in
// the tree at all), and separately pins the fallback branch — [fallbackIcon]
// drawn inside the SAME disc when a network photo is absent or disallowed —
// and (mobile-qa, closing a gap the original cut of this file left open) the
// LOADED-photo branch itself, via the same `debugMediaCacheManager` +
// `MediaConfig.debugAllowedHosts` seam `master_booking_card_client_avatar_test
// .dart` already uses. `flutter test` has no real network, but that seam
// makes the loaded case reachable anyway — a real decoded frame, not merely
// its absence.
//
// Layer: Widget. [HubAvatar] is a `StatelessWidget`, no providers needed.

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/hub_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/fake_media_cache.dart';
import '../../../../helpers/pump_app.dart';

void main() {
  group('should_renderInitialsDisc_when_imageUrlIsAbsent', () {
    testWidgets('the pre-Phase-F call shape renders exactly as before', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        const Center(child: HubAvatar(initials: 'ОК', size: 38)),
      );

      // i18n-finder-ok: 'ОК' is test-authored fixture data, not UI copy.
      expect(find.text('ОК'), findsOneWidget);
      expect(
        find.byType(RemoteImage),
        findsNothing,
        reason:
            'a null imageUrl must not even construct a RemoteImage — every '
            'existing caller keeps its exact original widget tree',
      );
    });

    testWidgets(
      'a fallbackIcon with no imageUrl still draws — the disc still falls back',
      (WidgetTester tester) async {
        // No pre-Phase-F caller passes fallbackIcon (it is a new, additive
        // parameter), so this path never fires for any of them — but by
        // design it does NOT require imageUrl to be set: [HubAvatar]'s own
        // doc says the disc falls back "either because imageUrl is null, or
        // because it failed to resolve", drawing fallbackIcon either way.
        await tester.pumpApp(
          const Center(
            child: HubAvatar(
              initials: 'ОК',
              size: 38,
              fallbackIcon: Icons.storefront_rounded,
            ),
          ),
        );

        expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
        // i18n-finder-ok: 'ОК' is test-authored fixture data, not UI copy.
        expect(find.text('ОК'), findsNothing);
      },
    );
  });

  group('should_fallBackToTheGradientDisc_when_imageUrlIsNotAllowed', () {
    testWidgets('a non-https imageUrl falls back to fallbackIcon', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        const Center(
          child: HubAvatar(
            initials: 'ОК',
            size: 38,
            imageUrl: 'http://not-https.example/x.png',
            fallbackIcon: Icons.storefront_rounded,
          ),
        ),
      );

      expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
      expect(
        // i18n-finder-ok: 'ОК' is test-authored fixture data, not UI copy.
        find.text('ОК'),
        findsNothing,
        reason: 'fallbackIcon takes over from initials once imageUrl is set',
      );
    });

    testWidgets(
      'a non-https imageUrl with NO fallbackIcon falls back to initials',
      (WidgetTester tester) async {
        await tester.pumpApp(
          const Center(
            child: HubAvatar(
              initials: 'ОК',
              size: 38,
              imageUrl: 'http://not-https.example/x.png',
            ),
          ),
        );

        // i18n-finder-ok: 'ОК' is test-authored fixture data, not UI copy.
        expect(find.text('ОК'), findsOneWidget);
      },
    );

    testWidgets('a disallowed host also falls back — the same guard', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        const Center(
          child: HubAvatar(
            initials: '',
            size: 38,
            imageUrl: 'https://evil.example/x.png',
            fallbackIcon: Icons.storefront_rounded,
          ),
        ),
      );

      expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
    });
  });

  group('should_renderLoadedPhoto_when_imageUrlResolves', () {
    const String kHost = 'cdn.example.com';
    const String kHttpsAvatar = 'https://$kHost/avatars/salon.png';

    late FakeMediaCacheManager fake;

    setUp(() {
      MediaConfig.debugAllowedHosts = <String>{kHost};
      fake = FakeMediaCacheManager(mediaLoaded);
      debugMediaCacheManager = fake;
    });

    tearDown(() {
      debugMediaCacheManager = null;
      MediaConfig.debugAllowedHosts = null;
      // A stuck completer from an earlier test resolving the SAME URL would
      // be handed back here instead of a fresh one — see
      // `master_booking_card_client_avatar_test.dart`'s identical teardown.
      imageCache.clear();
      imageCache.clearLiveImages();
    });

    testWidgets(
      'a resolvable https avatar replaces BOTH initials and fallbackIcon',
      (WidgetTester tester) async {
        await tester.pumpApp(
          const Center(
            child: HubAvatar(
              initials: 'ОК',
              size: 38,
              imageUrl: kHttpsAvatar,
              fallbackIcon: Icons.storefront_rounded,
            ),
          ),
        );
        // Image decoding is genuinely async (`instantiateImageCodec`) — it
        // does not advance under `pump`/`pumpAndSettle` alone.
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pumpAndSettle();

        expect(
          find.byType(RemoteImage),
          findsOneWidget,
          reason: 'an allowed https URL must reach the disc\'s RemoteImage',
        );
        expect(
          find.byIcon(Icons.storefront_rounded),
          findsNothing,
          reason: 'once decoded, the photo takes over from fallbackIcon',
        );
        // i18n-finder-ok: 'ОК' is test-authored fixture data, not UI copy.
        expect(find.text('ОК'), findsNothing);
        expect(
          fake.getFileStreamCalls,
          1,
          reason: 'the allowed URL must genuinely reach the cache manager',
        );
      },
    );

    testWidgets('the loaded photo is clipped to a circle of exactly [size]', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        const Center(
          child: HubAvatar(initials: 'ОК', size: 38, imageUrl: kHttpsAvatar),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(find.byType(ClipOval), findsOneWidget);
      expect(tester.getSize(find.byType(ClipOval)), const Size(38, 38));
    });
  });
}
