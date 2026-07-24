// The FULL body's row-1 client mark — `_ClientAvatarMark` (2026-07-24).
//
// The backend ships `clientAvatarUrl` on `BookingDetailResponse`, so the slot
// that used to be an unconditional `person_outlined` glyph renders the booking
// client's real photo when there is one and keeps the glyph as its fallback.
//
// ## WHAT THIS FILE IS ACTUALLY GUARDING — the 16dp footprint, not the pixels
//
// `MasterBookingCard.fullLayoutNaturalHeight` is 118dp against
// `BookingsTimelineGrid._kHourH`'s 120dp/hour, so a 59-minute booking's floor
// is EXACTLY 118 (zero clearance) and an hour-long one's is 120 (2dp). Row 1's
// height IS this mark's height — 16dp beats
// `VelvetText.masterCardClientNameFull`'s 15dp line box at textScaler 1.0,
// which is the entire reason the constant is 118 rather than 117. So one dp of
// growth in ANY of the mark's four states silently demotes hour-long bookings
// — the bulk of a real working day — to the compact layout, with no test
// failure and no visual error anywhere near the change.
//
// `master_booking_card_test.dart` already pins that 43.5dp interior headroom
// (`border 1.5 + _fullPadding 16 + row 1 (16) + 10`), but only for a fixture
// with NO avatar URL, i.e. for the fallback state. Every state this file adds
// is a state that pin cannot see. Hence the same two measurements repeated
// across all four: the interior headroom (catches shrinkage AND growth) and the
// outer box (which the floor pads from below, so it catches growth only).
//
// ## MECHANISM — the shared media loader, injected (2026-07-24)
//
// The mark's provider moved from a bare `NetworkImage` to the shared
// disk-cached `beauticaMediaProvider` (core/media/beautica_image.dart). That
// provider's real `CacheManager` needs path_provider + sqflite and cannot run
// under `flutter test` at all, so the three network-dependent states are driven
// by injecting a [FakeMediaCacheManager] via `debugMediaCacheManager`:
//   • loading → a stream that never resolves;
//   • loaded  → a stream carrying a real (in-memory) PNG, decoded under
//     `tester.runAsync`;
//   • error   → a stream that errors immediately.
// The host allowlist is opened to the fixture host via
// `MediaConfig.debugAllowedHosts` — without it every https URL is rejected by
// [isAllowedMediaUrl] and would fall straight to the glyph, so the allowlist
// override is what makes the "photo" states reachable at all.
//
// NOT ASSERTED HERE, deliberately: what the photo looks like. The ring, the
// clip and the fit are design choices with no correctness contract; the
// footprint is the contract.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';

import '../../../helpers/fake_media_cache.dart';
import '../../../helpers/pump_app.dart';

/// The fixture host, added to the media allowlist in [setUp]. A publicly-shaped
/// https avatar URL on this host is what the "photo" states require.
const String _kHost = 'cdn.example.com';
const String _kHttpsAvatar = 'https://$_kHost/avatars/client-1.png';

/// The same URL downgraded — the case [isAllowedMediaUrl] must refuse on
/// scheme, before the host allowlist is even consulted.
const String _kHttpAvatar = 'http://$_kHost/avatars/client-1.png';

/// A DISTINCT https URL for the error case, so a cached frame from the loaded
/// case can never serve it (the test binding clears the image cache between
/// tests, but distinct keys keep the intent explicit).
const String _kDeadAvatar = 'https://$_kHost/avatars/deleted-404.png';

/// The card's OWN key, derived from the fixture's booking id inside
/// [MasterBookingCard] — never passed in from here, or the finder matches both
/// the widget and its internal `GestureDetector`.
const Key _kCard = Key('master-booking-card-avatar-fixture');
const Key _kDivider = Key('master-booking-card-divider-avatar-fixture');

/// A 60-minute booking — the duration whose 120dp floor clears the 118dp full
/// layout by only 2dp, i.e. the one this file exists to protect.
Booking _booking({String? avatarUrl}) {
  // future-date-ok: pinned wall-clock fixture; nothing here reads "now".
  final DateTime startAt = DateTime.utc(2026, 7, 20, 6); // 09:00 Kyiv
  return Booking(
    id: 'avatar-fixture',
    masterId: 'master-1',
    masterFirstName: 'Olha',
    masterLastName: 'Koval',
    masterType: 'INDEPENDENT_MASTER',
    clientFirstName: 'Mariia',
    clientLastName: 'Ivaniuk',
    clientAvatarUrl: avatarUrl,
    serviceId: 'service-1',
    serviceName: 'Haircut',
    durationMinutes: 60,
    price: 450,
    startAt: startAt,
    endAt: startAt.add(const Duration(minutes: 60)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

Future<void> _pumpFullCard(WidgetTester tester, {String? avatarUrl}) async {
  await tester.pumpApp(
    Center(
      child: SizedBox(
        width: 226,
        child: MasterBookingCard(
          booking: _booking(avatarUrl: avatarUrl),
          onTap: () {},
          // At or above this, `build` selects the FULL body — the only one
          // with a row-1 mark at all.
          minHeight: MasterBookingCard.fullLayoutMinHeight,
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The two measurements, together, for whichever state the caller has pumped.
void _expectFootprintUnmoved(WidgetTester tester, String state) {
  final Finder card = find.byKey(_kCard);
  final Finder divider = find.byKey(_kDivider);
  expect(
    divider,
    findsOneWidget,
    reason: 'precondition ($state): this must be the FULL layout',
  );

  final double headroom =
      tester.getRect(divider).top - tester.getRect(card).top;
  expect(
    headroom,
    closeTo(43.5, 0.01),
    reason:
        'in the "$state" state the card\'s top edge sits ${headroom}dp above '
        'the hairline, against the 43.5dp the full body derives (1.5 border + '
        '16 padding + a 16dp row 1 + 10). The row-1 mark must measure exactly '
        '16dp in EVERY state — this is an interior distance, so the minHeight '
        'floor cannot pad it back.',
  );

  expect(
    tester.getSize(card).height,
    closeTo(MasterBookingCard.fullLayoutNaturalHeight, 0.01),
    reason:
        'in the "$state" state the full body grew past its 118dp natural. A '
        '59-minute booking has ZERO clearance over that number and an '
        'hour-long one has 2dp, so this demotes most of a working day to the '
        'compact layout.',
  );
}

void main() {
  late FakeMediaCacheManager fake;

  setUp(() {
    // Open the allowlist to the fixture host, and route every media fetch
    // through an injected fake so no real network / disk cache is touched.
    // Default responder is "loading forever"; individual tests swap it.
    MediaConfig.debugAllowedHosts = <String>{_kHost};
    fake = FakeMediaCacheManager(mediaLoadingForever);
    debugMediaCacheManager = fake;
  });

  tearDown(() {
    debugMediaCacheManager = null;
    MediaConfig.debugAllowedHosts = null;
    // A `mediaLoadingForever` fetch leaves a never-completing ImageStream
    // completer in the global image cache keyed by the avatar URL. Without
    // clearing it, a later test resolving the SAME URL is handed that stuck
    // completer instead of building a fresh one — which is why the "loaded"
    // state (same URL as "loading") never decoded when the suite ran in order.
    imageCache.clear();
    imageCache.clearLiveImages();
  });

  group('the row-1 client mark keeps its 16dp footprint in all four states', () {
    testWidgets('null URL — a guest booking, or a client with no photo', (
      WidgetTester tester,
    ) async {
      await _pumpFullCard(tester);
      expect(
        find.byIcon(Icons.person_outlined),
        findsOneWidget,
        reason: 'no URL must render the fallback glyph',
      );
      expect(
        find.byType(Image),
        findsNothing,
        reason: 'a null URL must not build a network image at all',
      );
      expect(
        fake.getFileStreamCalls,
        0,
        reason: 'a null URL must not reach the cache manager',
      );
      _expectFootprintUnmoved(tester, 'null URL');
    });

    testWidgets('loading — the fallback glyph holds the slot, not a hole', (
      WidgetTester tester,
    ) async {
      fake.responder = mediaLoadingForever;
      await _pumpFullCard(tester, avatarUrl: _kHttpsAvatar);
      // The fetch never resolves, so no frame has decoded: this IS the loading
      // state, and `frameBuilder` must be showing the glyph.
      expect(
        find.byType(Image),
        findsOneWidget,
        reason: 'an allowed https URL must reach the mark\'s Image',
      );
      expect(
        find.byIcon(Icons.person_outlined),
        findsOneWidget,
        reason:
            'while the photo is in flight the slot must hold the fallback '
            'glyph — a blank box would break row 1/row 2\'s shared left rail',
      );
      _expectFootprintUnmoved(tester, 'loading');
    });

    testWidgets('loaded — the photo replaces the glyph in the same box', (
      WidgetTester tester,
    ) async {
      fake.responder = mediaLoaded;
      await _pumpFullCard(tester, avatarUrl: _kHttpsAvatar);
      // Image decoding is genuinely async (`instantiateImageCodec`), so it
      // does not advance under `pump`/`pumpAndSettle` alone.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(
        find.byIcon(Icons.person_outlined),
        findsNothing,
        reason: 'once decoded, the photo must take the glyph\'s place',
      );
      expect(
        tester.getSize(find.byType(ClipOval)),
        const Size(16, 16),
        reason: 'the photo is clipped to exactly the glyph\'s footprint',
      );
      _expectFootprintUnmoved(tester, 'loaded');
    });

    testWidgets('error — a dead URL falls back, never a broken-image box', (
      WidgetTester tester,
    ) async {
      fake.responder = mediaFetchError;
      await _pumpFullCard(tester, avatarUrl: _kDeadAvatar);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(
        find.byIcon(Icons.person_outlined),
        findsOneWidget,
        reason: 'a failed fetch must land back on the glyph',
      );
      _expectFootprintUnmoved(tester, 'error');
    });
  });

  group('the https + allowlist guard, funnelled through isAllowedMediaUrl', () {
    testWidgets('an http:// URL is never requested — it falls to the glyph', (
      WidgetTester tester,
    ) async {
      await _pumpFullCard(tester, avatarUrl: _kHttpAvatar);
      expect(
        find.byType(Image),
        findsNothing,
        reason:
            'a cleartext URL is rejected on scheme before any fetch — it must '
            'not merely fail and fall back',
      );
      expect(
        fake.getFileStreamCalls,
        0,
        reason: 'a rejected URL must never reach the cache manager',
      );
      expect(find.byIcon(Icons.person_outlined), findsOneWidget);
      _expectFootprintUnmoved(tester, 'http:// blocked');
    });

    testWidgets('an https URL on an UNLISTED host is never requested', (
      WidgetTester tester,
    ) async {
      await _pumpFullCard(
        tester,
        avatarUrl: 'https://evil.example.net/avatars/client-1.png',
      );
      expect(
        find.byType(Image),
        findsNothing,
        reason:
            'the host is not in the allowlist, so the guard must reject it '
            'without a fetch — the real closable trust boundary',
      );
      expect(fake.getFileStreamCalls, 0);
      expect(find.byIcon(Icons.person_outlined), findsOneWidget);
    });

    testWidgets('an empty-string URL is treated as no photo', (
      WidgetTester tester,
    ) async {
      await _pumpFullCard(tester, avatarUrl: '');
      expect(find.byType(Image), findsNothing);
      expect(fake.getFileStreamCalls, 0);
      expect(find.byIcon(Icons.person_outlined), findsOneWidget);
    });
  });

  group('the photo is decorative — it must not enter the a11y tree', () {
    testWidgets('no second announcement, and no URL leak', (
      WidgetTester tester,
    ) async {
      // Disposed inline rather than via `addTearDown`: the framework's
      // "a SemanticsHandle was active at the end of the test" verification
      // runs BEFORE tear-downs.
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        fake.responder = mediaLoadingForever;
        await _pumpFullCard(tester, avatarUrl: _kHttpsAvatar);

        expect(
          tester.widget<Image>(find.byType(Image)).excludeFromSemantics,
          isTrue,
          reason:
              'the client\'s name is already announced by the card\'s own '
              'Semantics(label:); an Image node would add an empty, '
              'image-flagged second node inside that button',
        );
        // The property assertion above is the direct pin; this is the
        // rendered-tree consequence — no `image`-flagged node anywhere inside
        // the card, whatever route one might arrive by.
        expect(
          find.byWidgetPredicate(
            (Widget w) => w is Semantics && (w.properties.image ?? false),
          ),
          findsNothing,
          reason:
              'no image-flagged semantics node may exist in the card\'s '
              'subtree — the card is a single button announcing one person',
        );
        expect(
          find.bySemanticsLabel(RegExp(_kHost)),
          findsNothing,
          reason: 'the object URL must never reach the semantics tree',
        );
      } finally {
        handle.dispose();
      }
    });
  });
}
