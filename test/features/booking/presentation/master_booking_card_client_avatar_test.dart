// The FULL body's row-1 client mark — `_ClientAvatarMark` (2026-07-24).
//
// The backend now ships `clientAvatarUrl` on `BookingDetailResponse`, so the
// slot that used to be an unconditional `person_outlined` glyph renders the
// booking client's real photo when there is one and keeps the glyph as its
// fallback.
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
// (`border 1.5 + _fullPadding 16 + row 1 (16) + 10`), and a `minHeight` floor
// cannot pad an interior distance — but it pins it for a fixture with NO
// avatar URL, i.e. for the fallback state only. Every state this file adds is
// a state that pin cannot see. Hence the same two measurements repeated across
// all four: the interior headroom (catches shrinkage AND growth) and the outer
// box (which the floor pads from below, so it catches growth only).
//
// NOT ASSERTED HERE, deliberately: what the photo looks like. The ring, the
// clip and the fit are design choices with no correctness contract; the
// footprint is the contract.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';

import '../../../helpers/pump_app.dart';

/// A publicly-shaped https avatar URL. Never fetched for real: the tests that
/// expect a decoded frame run inside `mockNetworkImagesFor`, and the ones that
/// expect the error path deliberately run outside it, where `flutter_test`'s
/// default `HttpClient` answers 400.
const String _kHttpsAvatar = 'https://cdn.example.com/avatars/client-1.png';

/// The same URL downgraded — the case the https guard must refuse to request
/// at all (`Image.network` uses its own `HttpClient`, not the pinned Dio).
const String _kHttpAvatar = 'http://cdn.example.com/avatars/client-1.png';

/// A DISTINCT https URL for the error case. Deliberately not [_kHttpsAvatar]:
/// Flutter's `ImageCache` keys on the provider, so reusing the URL the
/// "loaded" case already decoded would serve that cached bitmap instead of
/// exercising the failure path at all.
const String _kDeadAvatar = 'https://cdn.example.com/avatars/deleted-404.png';

/// An `HttpClient` that fails whatever is asked of it — how the error state is
/// provoked deterministically.
///
/// ## WHY NOT JUST SKIP `mockNetworkImagesFor` AND LET THE DEFAULT 400 FIRE
///
/// Because it silently stops working the moment any OTHER test in this file
/// loads an image first. `NetworkImage._sharedHttpClient`
/// (`painting/_network_image_io.dart`) is a `static final` — one instance per
/// TEST PROCESS, built lazily from whatever `HttpOverrides` happened to be
/// installed at the first image load anywhere in the file. `mockNetworkImagesFor`
/// is a properly scoped `HttpOverrides.runZoned`, but the client it hands out
/// on that first load is captured in that static forever, so a later
/// un-mocked test keeps getting the MOCK — and a "dead" URL loads a perfectly
/// good transparent pixel. That is not a hypothetical: it is what this test
/// did before this class existed, and it failed by finding the photo where it
/// expected the fallback.
///
/// `debugNetworkImageHttpClientProvider` is the supported way out: it is
/// consulted on EVERY load, ahead of that static, so it works whatever ran
/// first and leaves the other tests in this file order-independent.
class _FailingHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw const SocketException('avatar host unreachable (test fixture)');
}

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
      _expectFootprintUnmoved(tester, 'null URL');
    });

    testWidgets('loading — the fallback glyph holds the slot, not a hole', (
      WidgetTester tester,
    ) async {
      await mockNetworkImagesFor(() async {
        await _pumpFullCard(tester, avatarUrl: _kHttpsAvatar);
        // No `runAsync`, so no frame has decoded yet: this IS the loading
        // state, and `frameBuilder` must be showing the glyph.
        expect(
          find.byType(Image),
          findsOneWidget,
          reason: 'an https URL must reach Image.network',
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
    });

    testWidgets('loaded — the photo replaces the glyph in the same box', (
      WidgetTester tester,
    ) async {
      await mockNetworkImagesFor(() async {
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
    });

    testWidgets('error — a dead URL falls back, never a broken-image box', (
      WidgetTester tester,
    ) async {
      // Every fetch fails while this is installed — see [_FailingHttpClient]
      // for why the ambient default cannot be relied on here.
      // Cleared inline at the end of the body, NOT via `addTearDown`: the
      // framework's `debugAssertAllPaintingVarsUnset` invariant runs before
      // tear-downs and fails the test on a still-set painting debug variable.
      //
      // `finally`, not a bare trailing assignment: an assertion failure below
      // is an exception, and a plain trailing reset is skipped on that path —
      // leaving the override installed and failing EVERY LATER TEST IN THIS
      // FILE on the same painting-vars invariant. One real failure would then
      // arrive as four, three of them in tests that are fine. Verified by
      // mutation (QA, 2026-07-24): breaking `errorBuilder` alone turned this
      // file red 4 times, not once.
      debugNetworkImageHttpClientProvider = () => _FailingHttpClient();
      try {
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
      } finally {
        debugNetworkImageHttpClientProvider = null;
      }
    });
  });

  group('the https-only guard, mirrored from ResultThumbnail/_MasterPhoto', () {
    testWidgets('an http:// URL is never requested — it falls to the glyph', (
      WidgetTester tester,
    ) async {
      await mockNetworkImagesFor(() async {
        await _pumpFullCard(tester, avatarUrl: _kHttpAvatar);
        expect(
          find.byType(Image),
          findsNothing,
          reason:
              'Image.network uses its own HttpClient, not the pinned Dio, so a '
              'cleartext URL must not be fetched at all — it must not merely '
              'fail and fall back',
        );
        expect(find.byIcon(Icons.person_outlined), findsOneWidget);
        _expectFootprintUnmoved(tester, 'http:// blocked');
      });
    });

    testWidgets('an empty-string URL is treated as no photo', (
      WidgetTester tester,
    ) async {
      await mockNetworkImagesFor(() async {
        await _pumpFullCard(tester, avatarUrl: '');
        expect(find.byType(Image), findsNothing);
        expect(find.byIcon(Icons.person_outlined), findsOneWidget);
      });
    });
  });

  group('the photo is decorative — it must not enter the a11y tree', () {
    testWidgets('no second announcement, and no URL leak', (
      WidgetTester tester,
    ) async {
      // Disposed inline rather than via `addTearDown`: the framework's
      // "a SemanticsHandle was active at the end of the test" verification
      // runs BEFORE tear-downs. In a `finally` for the same reason the error
      // case above is — a failed expectation must not leak the handle into
      // whatever runs next.
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await mockNetworkImagesFor(() async {
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
          // rendered-tree consequence — no `image`-flagged node anywhere
          // inside the card, whatever route one might arrive by.
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
            find.bySemanticsLabel(RegExp('cdn.example.com')),
            findsNothing,
            reason: 'the object URL must never reach the semantics tree',
          );
        });
      } finally {
        handle.dispose();
      }
    });
  });
}
