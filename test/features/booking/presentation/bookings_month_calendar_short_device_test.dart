// Варіант D port — gap 2 (mobile-qa audit, 2026-08-13): realistic short-device
// coverage for `BookingsMonthCalendarPanel`'s EXPANDED state.
//
// WHY THIS FILE EXISTS
// ---------------------
// `bookings_day_rebuild_isolation_test.dart`'s "month step (Варіант D
// calendar)" group pumps its screen at `height: 2400` — logical pixels no
// real phone in this app's target range gets anywhere close to (the tallest
// current flagship runs ~930dp logical; 2400 is roughly a 3× multiple of
// that). That file's own comment on the knob is explicit that this was NEVER
// RE-BENCHMARKED against the mobile-perf Stack/Positioned overlay fix that
// decoupled the expanding panel from the timeline's layout — it is inherited,
// unverified headroom. This file supplies the missing verification.
//
// THE GEOMETRY, PROBED EMPIRICALLY (360dp wide, varying total height `h`):
//   h=480 → CLIPPED  (panel bottom 496 > scaffold bottom 402)
//   h=520 → CLIPPED  (496 > 442)
//   h=560 → CLIPPED  (496 > 482, 14dp of the calendar's bottom row cut off)
//   h=600 → fits, 26dp margin  (522 > 496)
//   h=640 → fits, 66dp margin  (562 > 496)
//   h=667 → fits, 93dp margin  (589 > 496)
//   h=700 → fits, 126dp margin (622 > 496)
//   h=780 → fits, 206dp margin (702 > 496)
//
// Two things fall out of this that are worth stating plainly:
//
//   1. The EXPANDED panel's rendered bottom edge sits at a FIXED ~496dp from
//      the screen top (116dp header/top-row + kMonthCalendarExpandedHeight's
//      380dp), independent of viewport height. `BookingsMonthCalendarPanel`
//      is a `Positioned(top, left, right)` with no `bottom`/`height` inside
//      the host's `Stack` (`bookings_discovery_view.dart`'s build()) — that
//      shrink-wraps to the child's OWN intrinsic size, so it can never throw
//      the "RenderFlex overflowed" error `installOverflowGuard` listens for,
//      no matter how short the screen is. There is no overflow EXCEPTION to
//      catch here at any height, which is exactly why a bare
//      `tester.takeException()` check (or the guard alone) proves nothing for
//      this widget — see point 2.
//   2. What DOES happen on a too-short screen is silent CLIPPING: `Stack`'s
//      default `clipBehavior` (`Clip.hardEdge`) simply cuts off whatever
//      paints past its own bounds — no error, no warning, just an invisible,
//      unreachable bottom half of the calendar. The only way to catch that is
//      a GEOMETRIC assertion (compare the panel's rendered `Rect` against its
//      containing scaffold's), which is what this file does.
//
// The clip boundary sits around 580–600dp total viewport height. Every real
// phone this app targets is comfortably above that: iPhone SE (2nd/3rd gen)
// is the shortest iOS device Beautica ships on at 667dp logical height, and
// the smallest common Android baselines (e.g. a compact 5" 1:2 aspect device)
// run 640dp+. This file pins the two realistic low ends actually in that
// range — 640dp and 667dp — plus the mid-range 780dp point as a third
// witness, so a future viewport-affecting change (a taller header, a second
// toolbar row) that eats into that margin has something to trip.
//
// VERDICT for the `height: 2400` knob (see that file's own stale-rationale
// comment): NOT required any more. Every realistic phone height fits with
// 66dp+ of margin to spare; 2400 was carrying ~230dp of margin per the
// pre-Stack-fix `Column`+`Expanded` era and is now pure unverified padding.
// mobile-qa has reduced it to 700dp in that file (see the accompanying diff)
// — inside the realistic range, with headroom, rather than an arbitrary
// multiple of the smallest tablet.

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

/// Pumps `MasterBookingsScreen` at a fixed [width]×[height] viewport, expands
/// the Варіант D calendar, and returns:
///   * the expanded panel's rendered [Rect] (key `bookings-month-calendar` —
///     the ClipRect'd `SizedBox` `BookingsMonthCalendarPanel` animates)
///   * the containing (inner) Scaffold's rendered [Rect] (key
///     `master-bookings-screen`), which is what the host `Stack` actually
///     clips against.
Future<(Rect panel, Rect scaffold)> _pumpExpandedAt(
  WidgetTester tester, {
  required double width,
  required double height,
}) async {
  final _MockBookingRepository repo = _MockBookingRepository();
  when(
    () => repo.getMyBookings(
      statuses: any(named: 'statuses'),
      serviceIds: any(named: 'serviceIds'),
      from: any(named: 'from'),
      to: any(named: 'to'),
      sort: any(named: 'sort'),
      page: any(named: 'page'),
      size: any(named: 'size'),
      cancelToken: any(named: 'cancelToken'),
    ),
  ).thenAnswer(
    (_) async => const PageResponse<Booking>(
      items: <Booking>[],
      page: 0,
      totalPages: 1,
      totalElements: 0,
    ),
  );

  await tester.pumpApp(
    const MasterBookingsScreen(),
    width: width,
    height: height,
    overrides: <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingRepositoryProvider.overrideWithValue(repo),
      bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
    ],
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('bookings-month-calendar-toggle')));
  await tester.pumpAndSettle();

  final Rect panel = tester.getRect(
    find.byKey(const Key('bookings-month-calendar')),
  );
  final Rect scaffold = tester.getRect(
    find.byKey(const Key('master-bookings-screen')),
  );
  return (panel, scaffold);
}

void main() {
  setUpAll(() {
    registerFallbackValue(<BookingStatus>{});
  });

  group('BookingsMonthCalendarPanel fits on realistic short devices', () {
    testWidgets(
      'fits at 360×640 (a common small-Android baseline) — the expanded '
      'grid is not clipped by the host Stack',
      (tester) async {
        final (Rect panel, Rect scaffold) = await _pumpExpandedAt(
          tester,
          width: 360,
          height: 640,
        );

        expect(
          scaffold.bottom,
          greaterThanOrEqualTo(panel.bottom),
          reason:
              'the expanded calendar\'s rendered bottom edge (${panel.bottom}) '
              'falls past the scaffold\'s own bottom edge '
              '(${scaffold.bottom}) — the host Stack\'s default '
              'Clip.hardEdge would silently cut off the calendar\'s bottom '
              'row(s) on a 360×640 device, which is smaller than nothing '
              'this app actually ships on',
        );
      },
    );

    testWidgets('fits at 375×667 (iPhone SE — the shortest iOS device this app '
        'ships on)', (tester) async {
      final (Rect panel, Rect scaffold) = await _pumpExpandedAt(
        tester,
        width: 375,
        height: 667,
      );

      expect(scaffold.bottom, greaterThanOrEqualTo(panel.bottom));
    });

    testWidgets(
      'fits at 360×780 (a mid-range Android height) with room to spare',
      (tester) async {
        final (Rect panel, Rect scaffold) = await _pumpExpandedAt(
          tester,
          width: 360,
          height: 780,
        );

        expect(scaffold.bottom, greaterThanOrEqualTo(panel.bottom));
        // A distinctive margin, not just "fits by 1px" — mobile-qa fixture
        // guard: a REGRESSION that ate into the margin should show up here
        // long before it starts clipping at the two tighter heights above.
        expect(scaffold.bottom - panel.bottom, greaterThan(150));
      },
    );
  });

  group('BookingsMonthCalendarPanel — the clip IS real below the realistic '
      'range (documents the boundary, not a bug to fix)', () {
    testWidgets(
      'at 360×480 the calendar genuinely clips — proves the assertion '
      'above is not vacuous',
      (tester) async {
        final (Rect panel, Rect scaffold) = await _pumpExpandedAt(
          tester,
          width: 360,
          height: 480,
        );

        expect(
          scaffold.bottom,
          lessThan(panel.bottom),
          reason:
              'fixture guard: if this ever passes (i.e. stops clipping), '
              'the "fits" assertions above are not proving anything — a '
              'geometric check that can never fail either way is worthless. '
              '360×480 is far below any device this app targets; this case '
              'exists ONLY to keep the other three honest.',
        );
      },
    );
  });
}
