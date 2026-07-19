// Phase 7.12 — DayTimeWindow (domain) + its wiring into BookingsDiscoveryView.
//
// Every test here is mutation-verified — evidence is reported per test in the
// hand-off, not repeated inline (matching the convention of
// `master_bookings_filter_wiring_test.dart`, which records mutations only for
// the ones that are non-obvious).
//
// ZERO-NETWORK PROOF TECHNIQUE: [_fetchLog] records one entry per
// `BookingRepository.getMyBookings` invocation, mirroring
// `master_bookings_filter_wiring_test.dart`'s `_Call`/`calls` pattern. Since
// EVERY `bookingsDayProvider` family member's `build()` calls
// `getMyBookings` exactly once (see `bookings_day_notifier.dart`), an
// unchanged fetch count after a window edit is not merely correlated with
// "no new family member was minted" — it is the same fact observed from the
// one point that actually matters (the wire), and it is the single
// observation the phase doc itself calls for ("assert on the mock").

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/domain/day_time_window.dart';
import 'package:beautica_mobile/features/booking/presentation/bookings_discovery_view.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/day_time_window_sheet.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_hour_ruler.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';

import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

/// 2026-07-20 is Kyiv summer time (UTC+3) — matches the rest of this
/// feature's fixtures (`bookings_timeline_grid_test.dart`,
/// `master_bookings_filter_wiring_test.dart`). Used ONLY by the pure-domain
/// and direct-`BookingsTimelineGrid` groups below, which take `day` as an
/// explicit parameter and never touch `BookingsDiscoveryView`'s own day
/// derivation.
final DateTime _day = DateTime(2026, 7, 20);

/// Kyiv "today" — a GETTER, not a cached `final`, mirroring
/// `master_bookings_filter_wiring_test.dart`'s `_kyivToday`. Every
/// `BookingsDiscoveryView`-level test below MUST anchor its fixtures to this
/// (never to [_day]): the view deliberately does NOT read its initial day
/// selection from the `query` it is constructed with — it derives Kyiv
/// "today" itself from the live clock (`bookings_discovery_view.dart`'s "The
/// day is NOT read from query" header section) — so a booking fixture pinned
/// to a hard-coded 2026-07-20 would silently land on the WRONG day (and
/// therefore never appear, or appear at a nonsensical offset) on any test run
/// where real "today" isn't that exact date.
DateTime get _viewDay => dateOnly(toBeauticaTime(DateTime.now()));

/// A UTC instant for the given Kyiv wall-clock [hour]:[minute] on
/// [kyivDay] — DST-correct (unlike a fixed UTC-offset literal), so fixtures
/// built from this are valid regardless of which calendar date `_viewDay`
/// happens to resolve to on any given test run.
DateTime _kyivInstant(DateTime kyivDay, int hour, int minute) => tz.TZDateTime(
  beauticaZone,
  kyivDay.year,
  kyivDay.month,
  kyivDay.day,
  hour,
  minute,
).toUtc();

Booking _booking({
  required String id,
  required DateTime startAtUtc,
  int durationMinutes = 30,
}) => Booking(
  id: id,
  masterId: 'master-1',
  masterFirstName: 'Оля',
  masterLastName: 'Коваль',
  masterType: 'INDEPENDENT_MASTER',
  clientFirstName: 'Марія',
  clientLastName: 'Іванюк',
  serviceId: 'service-1',
  serviceName: 'Манікюр',
  durationMinutes: durationMinutes,
  price: 500,
  startAt: startAtUtc,
  endAt: startAtUtc.add(Duration(minutes: durationMinutes)),
  status: BookingStatus.confirmed,
  canReview: false,
);

void main() {
  // Called DIRECTLY (not only via `setUpAll`, which merely registers a
  // deferred callback): the `fixedBookings` fixture below is a top-level
  // `final` inside `main()`'s own synchronous body, built via `_kyivInstant`
  // → `beauticaZone`, which throws if read before the tz database is loaded.
  // `setUpAll`'s callback would only run once the framework starts executing
  // tests — AFTER `main()` has already finished building the whole tree — so
  // relying on it alone here would throw before a single test runs.
  // Idempotent, so this and the `setUpAll` below are both safe to keep.
  initBeauticaTimeZones();
  setUpAll(initBeauticaTimeZones);

  // ===========================================================================
  // DayTimeWindow — pure Dart, no widget pump.
  // ===========================================================================
  group('DayTimeWindow construction', () {
    // MUTATION: changed the guard to `endMinute < startMinute` (allowing
    // endMinute == startMinute through) → this test failed (no throw for the
    // equal case). Restored to `<=`.
    test('rejects endMinute <= startMinute', () {
      expect(
        () => DayTimeWindow(startMinute: 540, endMinute: 540),
        throwsArgumentError,
        reason: 'an equal end must be rejected — a zero-width window',
      );
      expect(
        () => DayTimeWindow(startMinute: 540, endMinute: 480),
        throwsArgumentError,
        reason: 'an inverted end must be rejected',
      );
    });

    // MUTATION: swapped the constructor's field assignment (`startMinute =
    // endMinute, endMinute = startMinute`) → this test failed (480/720
    // read back as 720/480). Restored.
    test('accepts a valid window', () {
      final DayTimeWindow w = DayTimeWindow(startMinute: 480, endMinute: 720);
      expect(w.startMinute, 480);
      expect(w.endMinute, 720);
    });
  });

  group('DayTimeWindow.== is structural', () {
    // MUTATION: changed `operator ==` to `identical(this, other)` only (drops
    // BOTH field comparisons) → this test failed (two separately-constructed
    // equal windows compared unequal). Restored.
    test(
      'two separately-constructed windows with the same bounds are equal',
      () {
        final DayTimeWindow a = DayTimeWindow(startMinute: 480, endMinute: 720);
        final DayTimeWindow b = DayTimeWindow(startMinute: 480, endMinute: 720);
        expect(a, equals(b));
        expect(a.hashCode, b.hashCode);
      },
    );

    // MUTATION: dropped the `endMinute` comparison from `operator ==` (kept
    // only `startMinute == startMinute`) → this test failed (a and c, which
    // differ only in endMinute, compared equal). Restored.
    test('windows with different bounds are not equal', () {
      final DayTimeWindow a = DayTimeWindow(startMinute: 480, endMinute: 720);
      final DayTimeWindow c = DayTimeWindow(startMinute: 480, endMinute: 600);
      expect(a, isNot(equals(c)));
    });
  });

  // ===========================================================================
  // DayTimeWindow.contains — Kyiv-time correctness + the start-inside rule.
  // ===========================================================================
  group('DayTimeWindow.contains', () {
    // MUTATION: changed `contains` to read `booking.startAt.hour * 60 +
    // booking.startAt.minute` directly (raw UTC, no `toBeauticaTime`
    // conversion) instead of going through `_minutesSinceDayStart` → this
    // test failed (09:00 Kyiv, which is 06:00 UTC, computed as minute 360
    // instead of 540, landing OUTSIDE the 480–720 window under test).
    // Restored.
    test('is measured in Kyiv wall-clock time, not raw UTC', () {
      // 09:00 Kyiv == 06:00 UTC (Kyiv is UTC+3 in July).
      final Booking b = _booking(
        id: 'kyiv-0900',
        startAtUtc: DateTime.utc(2026, 7, 20, 6),
      );
      final DayTimeWindow window = DayTimeWindow(
        startMinute: 480, // 08:00 Kyiv
        endMinute: 720, // 12:00 Kyiv
      );

      expect(
        window.contains(b, _day),
        isTrue,
        reason:
            '09:00 Kyiv (06:00 UTC) falls inside 08:00–12:00 Kyiv. A '
            'UTC-naive implementation would place raw 06:00 outside this '
            'window and fail here — the test runner\'s own process zone is '
            'irrelevant either way (this file never reads TZ), so pinning '
            'to Europe/Kyiv is the only thing that can pass this.',
      );
    });

    // MUTATION: changed the membership check from `start >= startMinute &&
    // start < endMinute` to full containment (`start >= startMinute && start
    // + booking-duration <= endMinute`, requiring the caller to pass a
    // duration) — pins the exact rule the phase doc's Step 1 forbids
    // "fixing". Verified by hand: a straddling booking must stay INSIDE.
    test(
      'a booking starting inside but ending outside the window IS included',
      () {
        // 13:30 Kyiv start (10:30 UTC), 60-minute service → ends 14:30 Kyiv.
        final Booking straddling = _booking(
          id: 'straddling',
          startAtUtc: DateTime.utc(2026, 7, 20, 10, 30),
          durationMinutes: 60,
        );
        final DayTimeWindow window = DayTimeWindow(
          startMinute: 480, // 08:00 Kyiv
          endMinute: 840, // 14:00 Kyiv — the booking's END (14:30) is past this
        );

        expect(
          window.contains(straddling, _day),
          isTrue,
          reason:
              'the booking STARTS at 13:30, inside [08:00, 14:00) — it must '
              'count even though it runs past the window\'s 14:00 edge. '
              'Start-inside is the rule, not full containment (Step 1).',
        );
      },
    );

    // MUTATION (both tests below): dropped the upper-bound half of
    // `contains` entirely (`return start >= startMinute;`) → BOTH tests
    // failed — the 20:00 booking (well past the window) and the
    // exactly-at-endMinute booking were both wrongly included. Restored.
    test('a booking starting outside the window is excluded', () {
      final Booking outside = _booking(
        id: 'outside',
        startAtUtc: DateTime.utc(2026, 7, 20, 17), // 20:00 Kyiv
      );
      final DayTimeWindow window = DayTimeWindow(
        startMinute: 480,
        endMinute: 720,
      );
      expect(window.contains(outside, _day), isFalse);
    });

    test(
      'a booking starting exactly at endMinute is excluded (exclusive upper bound)',
      () {
        // 12:00 Kyiv == 09:00 UTC, exactly the window's endMinute.
        final Booking atEdge = _booking(
          id: 'at-edge',
          startAtUtc: DateTime.utc(2026, 7, 20, 9),
        );
        final DayTimeWindow window = DayTimeWindow(
          startMinute: 480,
          endMinute: 720,
        );
        expect(window.contains(atEdge, _day), isFalse);
      },
    );
  });

  // ===========================================================================
  // BookingsTimelineGrid — the R1 clamp under a narrow/degenerate window.
  // ===========================================================================
  group('R1 clamp under a narrow window', () {
    // MUTATION: removed the `math.max(lastMinuteCandidate, firstMinute +
    // 60)` floor in `bookings_timeline_grid.dart` (used `lastMinuteCandidate`
    // directly) → this test failed: the rendered SizedBox height dropped to
    // 1 minute's worth (1.2px) instead of the 60-minute floor (72px), and
    // the `gridHeight > 0` assert in the grid still technically held but the
    // ACTUAL floor value asserted below did not. Restored.
    testWidgets(
      'a 1-minute window still yields the 60-minute floor height, never throws',
      (tester) async {
        final Booking b = _booking(
          id: 'narrow',
          startAtUtc: DateTime.utc(2026, 7, 20, 6), // 09:00 Kyiv
        );

        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[b],
            day: _day,
            windowStartMinute: 540, // 09:00
            windowEndMinute: 541, // 09:01 — a 1-minute window
            onBookingTap: (_) {},
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);

        final SizedBox stackSizedBox = tester.widget<SizedBox>(
          find.ancestor(
            of: find.byKey(const ValueKey<String>('timeline-lane-stack')),
            matching: find.byType(SizedBox),
          ),
        );
        expect(
          stackSizedBox.height,
          72.0, // 60 minutes * 72px/hour / 60
          reason:
              'the R1 floor must clamp a 1-minute window up to a full '
              'hour of rendered space, not a sliver.',
        );
      },
    );
  });

  // ===========================================================================
  // DayTimeWindowSheet — _pickStart/_pickEnd FIELD WIRING.
  //
  // Every other test in this file applies the sheet's seeded 09:00–18:00
  // default without ever opening a wheel, so the `setState(() => _draftStart
  // = picked)` / `_draftEnd = picked` seam in `day_time_window_sheet.dart`
  // was never exercised (flagged by mobile-build-verifier). The wheel-DRAG
  // mechanics themselves are already covered by
  // `velvet_time_picker_test.dart`'s "scrolling wheel then confirming"
  // group; this group only proves the SHEET wires each picker's result into
  // the correct draft field — a swapped assignment (`_draftStart = picked`
  // under `_pickEnd`, or vice versa) or a dropped `mounted` guard would pass
  // every other test in this file.
  // ===========================================================================
  group('DayTimeWindowSheet — _pickStart/_pickEnd field wiring', () {
    const Key openKey = Key('open-day-time-window-sheet-under-test');
    const Key confirmKey = Key('btn-velvet-time-picker-confirm');

    /// Pumps a minimal host that opens [DayTimeWindowSheet] on tap, seeded
    /// from [initial], capturing whatever it resolves with into [onResult].
    /// Mirrors `velvet_time_picker_test.dart`'s `_pumpPicker` harness.
    // `DayTimeWindowSheet._apply`/`_clear` resolve via `context.pop` — the
    // go_router extension, which throws "No GoRouter found in context"
    // under a bare `MaterialApp`. Routed, mirroring every other widget-level
    // test in this file (`pump`'s own `GoRouter` host below).
    Future<void> pumpSheetHost(
      WidgetTester tester, {
      DayTimeWindow? initial,
      required ValueChanged<DayTimeWindowPickResult?> onResult,
    }) async {
      await tester.pumpRoutedApp(
        GoRouter(
          initialLocation: '/',
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              builder: (BuildContext context, GoRouterState state) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    key: openKey,
                    onPressed: () async {
                      final DayTimeWindowPickResult? result =
                          await DayTimeWindowSheet.show(
                            context,
                            initial: initial,
                          );
                      onResult(result);
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      await tester.tap(find.byKey(openKey));
      await tester.pumpAndSettle();
    }

    // MUTATION: swapped `_pickStart`'s `setState(() => _draftStart = picked)`
    // for `setState(() => _draftEnd = picked)` (and the mirror swap in
    // `_pickEnd`) → this test failed: the start row kept showing "09:00"
    // after driving its own wheel, while the END row jumped to "11:00"
    // instead — the exact field-swap bug this test exists to catch. Restored.
    testWidgets(
      'driving the START wheel updates ONLY the start row, and the applied '
      'window carries the new start with the end untouched',
      (tester) async {
        DayTimeWindowPickResult? result;
        await pumpSheetHost(tester, onResult: (r) => result = r);

        // Defaults: start row "09:00", end row "18:00" (no `initial`).
        expect(find.text('09:00'), findsOneWidget);
        expect(find.text('18:00'), findsOneWidget);

        // Open the START wheel via the sheet's own row — never the end row.
        await tester.tap(find.byKey(const Key('day-time-window-start')));
        await tester.pumpAndSettle();

        // Drag the HOURS wheel up by 2 item-extents (46px each): 09 → 11.
        // Mirrors `velvet_time_picker_test.dart`'s scrolling group verbatim.
        final Finder hoursWheel = find.byType(ListWheelScrollView).first;
        await tester.drag(hoursWheel, const Offset(0, -92));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(confirmKey));
        await tester.pumpAndSettle();

        // Back on the sheet: the START row changed, the END row did NOT.
        expect(
          find.text('11:00'),
          findsOneWidget,
          reason:
              'the picker opened from the START row must write its result '
              'into _draftStart, not _draftEnd',
        );
        expect(
          find.text('09:00'),
          findsNothing,
          reason: 'the stale start value must not survive the pick',
        );
        expect(
          find.text('18:00'),
          findsOneWidget,
          reason:
              'the END row must be completely unaffected by a START-wheel '
              'pick — a swapped assignment would move this instead',
        );

        await tester.tap(find.byKey(const Key('day-time-window-apply')));
        await tester.pumpAndSettle();

        expect(result, isA<DayTimeWindowApplied>());
        final DayTimeWindow applied = (result! as DayTimeWindowApplied).window;
        expect(
          applied.startMinute,
          11 * 60,
          reason: 'the applied window must carry the WHEEL-PICKED start',
        );
        expect(
          applied.endMinute,
          18 * 60,
          reason: 'the end must still be the untouched seeded default',
        );
      },
    );

    // MUTATION (mirror of the above, END side): same swap, opposite
    // direction — this test failed under the identical mutation because the
    // END row stayed "18:00" while the START row jumped instead. Restored.
    // Together the two tests pin BOTH assignment directions — a one-sided
    // swap fix (only `_pickStart` corrected) would still fail this one.
    testWidgets(
      'driving the END wheel updates ONLY the end row, and the applied '
      'window carries the new end with the start untouched',
      (tester) async {
        DayTimeWindowPickResult? result;
        await pumpSheetHost(tester, onResult: (r) => result = r);

        await tester.tap(find.byKey(const Key('day-time-window-end')));
        await tester.pumpAndSettle();

        // 18 → 20: drag the hours wheel up by 2 item-extents.
        final Finder hoursWheel = find.byType(ListWheelScrollView).first;
        await tester.drag(hoursWheel, const Offset(0, -92));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(confirmKey));
        await tester.pumpAndSettle();

        expect(
          find.text('20:00'),
          findsOneWidget,
          reason:
              'the picker opened from the END row must write its result '
              'into _draftEnd, not _draftStart',
        );
        expect(find.text('18:00'), findsNothing);
        expect(
          find.text('09:00'),
          findsOneWidget,
          reason: 'the START row must be unaffected by an END-wheel pick',
        );

        await tester.tap(find.byKey(const Key('day-time-window-apply')));
        await tester.pumpAndSettle();

        expect(result, isA<DayTimeWindowApplied>());
        final DayTimeWindow applied = (result! as DayTimeWindowApplied).window;
        expect(applied.startMinute, 9 * 60);
        expect(
          applied.endMinute,
          20 * 60,
          reason: 'the applied window must carry the WHEEL-PICKED end',
        );
      },
    );

    // Phase 7.12 Step 2: "Guard end > start in the UI — disable «Застосувати»
    // rather than surfacing a thrown ArgumentError." Uncovered before this
    // audit — every other test in this file only ever confirms a VALID
    // draft. This pins the disabled-button contract directly, not just the
    // downstream `DayTimeWindow` constructor throw it exists to prevent the
    // user from ever reaching.
    //
    // MUTATION: two guards duplicate this invariant — the button's own
    // `onTap: _canApply ? _apply : null` AND `_apply`'s own internal `if
    // (!_canApply) return;` — so dropping only ONE leaves the other as a
    // silent, unreachable-but-still-safe no-op (verified by hand: mutating
    // either alone left every assertion below GREEN, because the surviving
    // guard still blocks the call before the constructor is ever reached).
    // The REALISTIC failure is a single refactor that deletes "the" guard
    // and forgets it was duplicated: changed the `onTap` ternary to a bare
    // `onTap: _apply` AND removed `_apply`'s internal early-return together
    // → this test failed at `expect(tester.takeException(), isNull)`: the
    // tap now reached `DayTimeWindow`'s constructor with the equal-bound
    // draft (1080 == 1080) and its `ArgumentError` surfaced UNCAUGHT to the
    // test framework instead of being silently blocked. Both guards
    // restored.
    testWidgets('«Застосувати» is disabled (and inert) when the draft start is '
        'dragged onto/past the draft end, and re-enables once fixed', (
      tester,
    ) async {
      DayTimeWindowPickResult? result;
      await pumpSheetHost(tester, onResult: (r) => result = r);

      // Drag the START hours wheel up by 9 item-extents: 09 → 18 — lands
      // exactly ON the untouched default end (18:00), an invalid
      // zero-width draft ([DayTimeWindow.new]'s own `endMinute <=
      // startMinute` rejects an EQUAL bound too — see the construction
      // group above).
      await tester.tap(find.byKey(const Key('day-time-window-start')));
      await tester.pumpAndSettle();
      final Finder hoursWheel = find.byType(ListWheelScrollView).first;
      await tester.drag(hoursWheel, const Offset(0, -46.0 * 9));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(confirmKey));
      await tester.pumpAndSettle();

      expect(find.text('18:00'), findsNWidgets(2));

      final Semantics applySemantics = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byKey(const Key('day-time-window-apply')),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(
        applySemantics.properties.enabled,
        isFalse,
        reason:
            'the phase doc requires a DISABLED affordance, not a live '
            'ArgumentError, for an invalid draft',
      );

      // Tapping it anyway must be a no-op — no crash, no resolution.
      await tester.tap(
        find.byKey(const Key('day-time-window-apply')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(
        result,
        isNull,
        reason: 'a disabled «Застосувати» must not resolve the sheet',
      );
      expect(
        tester.takeException(),
        isNull,
        reason:
            'must never surface the DayTimeWindow constructor\'s '
            'ArgumentError to the UI layer',
      );

      // Fix it: push the END wheel past the new 18:00 start.
      await tester.tap(find.byKey(const Key('day-time-window-end')));
      await tester.pumpAndSettle();
      await tester.drag(hoursWheel, const Offset(0, -46.0 * 3)); // 18 → 21
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(confirmKey));
      await tester.pumpAndSettle();

      final Semantics reEnabled = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byKey(const Key('day-time-window-apply')),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(reEnabled.properties.enabled, isTrue);

      await tester.tap(find.byKey(const Key('day-time-window-apply')));
      await tester.pumpAndSettle();

      expect(result, isA<DayTimeWindowApplied>());
      final DayTimeWindow applied = (result! as DayTimeWindowApplied).window;
      expect(applied.startMinute, 18 * 60);
      expect(applied.endMinute, 21 * 60);
    });
  });

  // ===========================================================================
  // BookingsDiscoveryView wiring — zero network, no-results, header
  // affordance, day-change clearing.
  // ===========================================================================

  late _MockBookingRepository repo;
  late int fetchCount;
  late List<Booking> currentBookings;

  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(<BookingStatus>[]);
  });

  /// Three bookings — 05:00, 12:00, and 20:00 Kyiv — every wiring test below
  /// that does not pass its own `bookings:` reuses this fixed set. Anchored
  /// to [_viewDay] (real Kyiv "today"), NOT [_day] — see [_viewDay]'s doc.
  ///
  /// Deliberately shaped around the sheet's default 09:00–18:00 draft:
  /// 'midday' sits INSIDE it (so applying the default window still leaves
  /// something for the grid to render — an all-outside fixture makes
  /// `_Loaded` fall through to the no-results state and `TimelineHourRuler`
  /// never mounts at all), while 'early'/'late' sit OUTSIDE it on OPPOSITE
  /// sides. The two-booking version of this fixture (one at exactly 09:00,
  /// the window's own start) let a `windowStartMinute: null` mutation pass
  /// VACUOUSLY — the data-derived and window-derived `firstMinute` were
  /// numerically identical, so `ruler.firstHour` read `9` either way and the
  /// ruler-extent test proved nothing about whether the override was wired
  /// up at all. Caught by hand while mutation-verifying that test; fixed by
  /// widening the fixture to three bookings so the data's true extent
  /// genuinely differs from the window's on BOTH bounds while the window
  /// still has something to render.
  final List<Booking> fixedBookings = <Booking>[
    _booking(id: 'early', startAtUtc: _kyivInstant(_viewDay, 5, 0)),
    _booking(id: 'midday', startAtUtc: _kyivInstant(_viewDay, 12, 0)),
    _booking(id: 'late', startAtUtc: _kyivInstant(_viewDay, 20, 0)),
  ];

  setUp(() {
    fetchCount = 0;
    currentBookings = fixedBookings;
    repo = _MockBookingRepository();
    when(
      () => repo.getMyBookings(
        statuses: any(named: 'statuses'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
        serviceIds: any(named: 'serviceIds'),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer((_) async {
      fetchCount++;
      return PageResponse<Booking>(
        items: currentBookings,
        page: 0,
        totalPages: 1,
        totalElements: currentBookings.length,
      );
    });
  });

  Future<void> pump(WidgetTester tester, {List<Booking>? bookings}) async {
    if (bookings != null) currentBookings = bookings;
    await tester.pumpRoutedApp(
      GoRouter(
        initialLocation: '/',
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (BuildContext context, GoRouterState state) =>
                BookingsDiscoveryView(
                  // Discarded by the view (it derives its own initial day —
                  // see [_viewDay]'s doc) — value here is irrelevant, only a
                  // valid `BookingsDayQuery` is required.
                  query: BookingsDayQuery.of(day: _viewDay),
                  title: 'Мої записи',
                  onBookingTap: (Booking _) {},
                ),
          ),
        ],
      ),
      overrides: <Object>[
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        bookingRepositoryProvider.overrideWithValue(repo),
        bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
        masterServiceCatalogProvider.overrideWith((ref) async => const []),
      ],
    );
    await tester.pumpAndSettle();
  }

  Future<void> openWindowSheet(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const Key('master-bookings-time-window-button')),
    );
    await tester.pumpAndSettle();
  }

  /// Applies the sheet's DEFAULT draft (09:00–18:00) — wide enough to keep
  /// BOTH fixture bookings visible, used by tests that only care about the
  /// zero-network property.
  Future<void> applyDefaultWindow(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('day-time-window-apply')));
    await tester.pumpAndSettle();
  }

  Future<void> removeWindow(WidgetTester tester) async {
    await openWindowSheet(tester);
    await tester.tap(find.byKey(const Key('day-time-window-reset')));
    await tester.pumpAndSettle();
  }

  group('zero network traffic', () {
    // MUTATION, two rounds (recorded because the first round is a genuinely
    // useful negative result, not just noise):
    //
    //   Round 1 — reintroduced a bare `_rebuildQuery()` call inside
    //   `_openWindowSheet`'s `setState` (the naive "folded the window into
    //   the query" mistake). ALL THREE tests in this group stayed GREEN.
    //   Why: `_rebuildQuery()` alone rebuilds `_liveQuery` from `_day`/
    //   `_statuses`/`_serviceIds` — none of which the window touches — so it
    //   reconstructs a `BookingsDayQuery` that is STRUCTURALLY `==` to the
    //   one already in use (`@freezed` equality), and Riverpod's family
    //   caching treats `bookingsDayProvider(equalQuery)` as the SAME
    //   element. A bare `_rebuildQuery()` call is therefore not by itself
    //   sufficient to detect (or cause) a family leak.
    //
    //   Round 2 — the FAITHFUL mutation: kept Round 1's `_rebuildQuery()`
    //   call AND made `_rebuildQuery()` itself window-sensitive (folded a
    //   marker into `serviceIds` whenever `_window != null`) — i.e. actually
    //   reproduced "the window leaked into the family key". All three tests
    //   failed: fetchCount went 1 → 2 on setting/changing/clearing the
    //   window. Both changes reverted.
    testWidgets('setting a window issues zero additional requests', (
      tester,
    ) async {
      await pump(tester);
      expect(fetchCount, 1, reason: 'the initial landing fetch');

      await openWindowSheet(tester);
      await applyDefaultWindow(tester);

      expect(
        fetchCount,
        1,
        reason:
            'setting the window must not mint a new bookingsDayProvider '
            'family member — every member build() calls getMyBookings '
            'exactly once, so a second call here would mean a new member '
            'was created.',
      );
    });

    testWidgets(
      'changing the window (open again, apply again) issues zero additional requests',
      (tester) async {
        await pump(tester);
        await openWindowSheet(tester);
        await applyDefaultWindow(tester);
        expect(fetchCount, 1);

        // Change it again — pick the end row and confirm without altering
        // the wheel (still resolves a DIFFERENT DayTimeWindow instance, same
        // bounds is fine; the point is a SECOND sheet round trip).
        await openWindowSheet(tester);
        await applyDefaultWindow(tester);

        expect(
          fetchCount,
          1,
          reason: 'a second window edit, still zero new fetches',
        );
      },
    );

    testWidgets('clearing the window issues zero additional requests', (
      tester,
    ) async {
      await pump(tester);
      await openWindowSheet(tester);
      await applyDefaultWindow(tester);
      expect(fetchCount, 1);

      await removeWindow(tester);

      expect(
        fetchCount,
        1,
        reason: 'clearing the window must not refetch either',
      );
    });
  });

  group('header affordance', () {
    // MUTATION: changed `_TimeWindowButton`'s `if (rangeLabel != null)`
    // guard to `if (true)` (with `Text(rangeLabel ?? '', ...)` to keep it
    // compiling) → this test failed (the label key rendered — empty text,
    // but present — before any window was set). The sibling "active" test
    // stayed green under this mutation (harmless when the label SHOULD show
    // anyway), so it took a SECOND mutation to pin that direction — see
    // below. Restored.
    testWidgets('no chip label before a window is set', (tester) async {
      await pump(tester);
      expect(
        find.byKey(const Key('master-bookings-time-window-label')),
        findsNothing,
      );
    });

    // MUTATION: changed the same guard to `if (false)` → this test failed
    // (the label never rendered even with an active window). Restored.
    testWidgets('an active window renders a visible HH:MM–HH:MM chip', (
      tester,
    ) async {
      await pump(tester);
      await openWindowSheet(tester);
      await applyDefaultWindow(tester);

      expect(
        find.byKey(const Key('master-bookings-time-window-label')),
        findsOneWidget,
      );
      expect(find.text('09:00–18:00'), findsOneWidget);
    });
  });

  group('the ruler spans the window, not the data', () {
    // MUTATION, three rounds — the first two exposed real gaps in this
    // test's own fixture/reasoning, kept as history rather than erased.
    //
    //   Round 1 — set `windowStartMinute: null` in `_Loaded`'s
    //   `BookingsTimelineGrid(...)` call. STAYED GREEN with the original
    //   two-booking fixture (one booking exactly at 09:00, the window's own
    //   start): the data-derived and window-derived `firstMinute` were
    //   numerically identical, so `ruler.firstHour` read `9` either way.
    //   Fixed by widening the fixture to three bookings ('early' 05:00,
    //   'midday' 12:00, 'late' 20:00) — see `fixedBookings`'s doc.
    //
    //   Round 2 — re-ran `windowStartMinute: null` against the widened
    //   fixture: RED, but `ruler.firstHour` read `12`, not the naively-
    //   expected `5`. Reason (not a bug, a fact about this file's OWN
    //   design): `_Loaded` passes the grid an ALREADY window-filtered
    //   `items` list (Step 3's "filter through `_window.contains` before
    //   handing them to the grid" — see `bookings_discovery_view.dart`).
    //   With `windowStartMinute` null, the grid's OWN data-extent fallback
    //   reduces over THAT filtered set — only 'midday' (12:00) survives
    //   filtering — never over the full unfiltered fixture. So the failure
    //   mode this mutation actually demonstrates is subtly different from
    //   "shows the true full-day extent": it silently narrows the ruler to
    //   wherever the surviving cards happen to sit, dropping the requested
    //   09:00–12:00 dead space at the start. Still a real, user-visible
    //   defect (the ruler no longer matches what the user asked to see),
    //   just not the exact number a first guess would predict — corrected
    //   the assertion's expected value and reasoning to match.
    //
    //   Round 3 — `windowEndMinute: null` instead (start restored): RED,
    //   `ruler.lastHour` read `13` (`ceil(('midday' start + its 30-minute
    //   duration) / 60)`), for the identical reason. All mutations reverted.
    testWidgets(
      'window 09:00–18:00 (the sheet default) makes the ruler span exactly '
      'that, not wherever the surviving cards happen to sit',
      (tester) async {
        await pump(tester);
        await openWindowSheet(tester);
        await applyDefaultWindow(tester);

        final TimelineHourRuler ruler = tester.widget<TimelineHourRuler>(
          find.byType(TimelineHourRuler),
        );

        expect(
          ruler.firstHour,
          9,
          reason:
              'the ruler must start at the WINDOW\'s start (09:00) — if the '
              '`windowStartMinute` override were dropped, the grid would '
              'derive the extent from only the SURVIVING (already '
              'window-filtered) cards and read 12 instead (Round 2)',
        );
        expect(
          ruler.lastHour,
          18,
          reason:
              'the ruler must stop at the WINDOW\'s end (18:00) — D8, locked '
              '— not wherever the surviving cards alone would derive to '
              '(13, if `windowEndMinute` were dropped; Round 3)',
        );
        // Fixture guard, BOTH directions: `fixedBookings` genuinely has a
        // booking on each side of [09:00, 18:00) — precondition for the
        // failure mode above to be reachable at all (a fixture entirely
        // inside the window could never expose a dropped override, since
        // there would be no "outside" case to filter away in the first
        // place).
        expect(
          fixedBookings.any((Booking b) => toBeauticaTime(b.startAt).hour < 9),
          isTrue,
          reason:
              'fixture guard: without a booking before 09:00 Kyiv, '
              'ruler.firstHour would read 9 whether or not the window '
              'override is wired up',
        );
        expect(
          fixedBookings.any(
            (Booking b) => toBeauticaTime(b.startAt).hour >= 19,
          ),
          isTrue,
          reason:
              'fixture guard: without a booking past 18:00 Kyiv, '
              'ruler.lastHour would read 18 whether or not the window '
              'override is wired up',
        );
      },
    );
  });

  group('a window matching nothing renders no-results, never true-empty', () {
    // Both fixture bookings sit OUTSIDE the sheet's default 09:00–18:00
    // draft (05:00 and 22:00 Kyiv) — applying the default (no wheel-scroll
    // needed; `velvet_time_picker_test.dart` already pins that confirming
    // without scrolling returns the seeded value verbatim) matches neither.
    final List<Booking> earlyAndLateBookings = <Booking>[
      _booking(id: 'too-early', startAtUtc: _kyivInstant(_viewDay, 5, 0)),
      _booking(id: 'too-late', startAtUtc: _kyivInstant(_viewDay, 22, 0)),
    ];

    // MUTATION 1 (the no-results-vs-true-empty distinction): changed
    // `hasFilters: _liveQuery.hasFilters || _window != null` to
    // `hasFilters: _liveQuery.hasFilters` (dropping the window OR) → the
    // first `expect` below failed: `master-bookings-no-results` was NOT
    // found at all — the view rendered the unrecoverable TRUE-empty state
    // instead (exactly the Do-NOT-list regression this test exists to
    // catch). Restored.
    //
    // MUTATION 2 (the reset-clears-window requirement): removed `_window =
    // null;` from `_clearAllFilters` → the LAST two `expect`s below failed:
    // `master-bookings-no-results` was still present after tapping «Скинути
    // фільтри» (window still active, still filtering everything out) and
    // the chip label was still rendered. Restored.
    testWidgets(
      'the default 09:00–18:00 window (matches neither fixture booking) '
      'shows no-results with a working «Скинути фільтри»',
      (tester) async {
        await pump(tester, bookings: earlyAndLateBookings);
        // Precondition: the unfiltered day actually has bookings — the
        // fixture guard for this whole test.
        expect(find.byKey(const Key('master-bookings-empty')), findsNothing);
        expect(
          find.byKey(const Key('master-bookings-no-results')),
          findsNothing,
        );
        // At least one — the timeline's hour ruler AND the booking card
        // itself both render a "05:00"-containing label pre-window.
        expect(find.textContaining('05:00'), findsWidgets);

        await openWindowSheet(tester);
        await applyDefaultWindow(tester);

        expect(
          find.byKey(const Key('master-bookings-no-results')),
          findsOneWidget,
          reason:
              'the day HAS bookings — a window that filters all of them out '
              'must render the recoverable no-results state, never the '
              'true-empty one',
        );
        expect(find.byKey(const Key('master-bookings-empty')), findsNothing);
        expect(
          find.byKey(const Key('master-bookings-clear-filters')),
          findsOneWidget,
        );

        // «Скинути фільтри» must clear the window too.
        await tester.tap(
          find.byKey(const Key('master-bookings-clear-filters')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('master-bookings-no-results')),
          findsNothing,
          reason: 'resetting must bring the bookings back into view',
        );
        expect(
          find.byKey(const Key('master-bookings-time-window-label')),
          findsNothing,
          reason:
              '«Скинути фільтри» must clear the window, not just the '
              'status/service filters',
        );
      },
    );
  });

  group('changing the selected day clears the window', () {
    // MUTATION: removed `_window = null;` from `_selectDay`'s debounced
    // `setState` (kept `_rebuildQuery()`) → this test failed: the chip
    // label was still present after tapping tomorrow's day cell. Restored.
    testWidgets('the header chip disappears after a day-rail tap', (
      tester,
    ) async {
      await pump(tester);
      await openWindowSheet(tester);
      await applyDefaultWindow(tester);
      expect(
        find.byKey(const Key('master-bookings-time-window-label')),
        findsOneWidget,
        reason: 'precondition: the window is active',
      );

      // `DateTime(y, m, d + 1)`, NEVER `.add(Duration(days: 1))` — the
      // latter is an INSTANT shift and can skew across a Europe/Kyiv DST
      // transition; `_viewDay` is already date-only, so incrementing `.day`
      // and letting `DateTime`'s own overflow normalisation handle month/
      // year rollover is the DST-safe pattern this codebase uses throughout
      // (`bookings_day_rail.dart`'s `railDayAt`, this feature's own
      // convention).
      final DateTime tomorrow = DateTime(
        _viewDay.year,
        _viewDay.month,
        _viewDay.day + 1,
      );
      await tester.tap(find.byKey(dayChipKey(tomorrow)));
      // The rail tap goes through a 220ms debounce
      // (`_BookingsDiscoveryViewState._dayDebounce`) before `_selectDay`
      // actually mutates state. A bare tap schedules no animation frame of
      // its own, so `pumpAndSettle`'s "stop once nothing is scheduled"
      // heuristic can exit after its first ~100ms step, well before the
      // debounce fires — an explicit fixed wait past 220ms is required to
      // actually cross it.
      // A bare `Timer`, not tied to a frame or an awaitable Future — there is
      // no pumpable condition to wait ON, so a fixed wait past its known
      // 220ms delay is the correct tool here.
      // fixed-wait-ok: cross _BookingsDiscoveryViewState._dayDebounce's fixed 220ms delay
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('master-bookings-time-window-label')),
        findsNothing,
        reason:
            'a window is scoped to the day it was set on — it must not '
            'survive a day change',
      );
    });
  });
}
