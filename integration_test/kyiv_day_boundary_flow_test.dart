// mobile-qa (2026-08-02, backlog :226 audit) — Step 2.7 Rule 3b integration
// coverage for the Kyiv-day-authority track.
//
// WHY THIS FILE EXISTS
// ---------------------
// The Kyiv-day-authority migration (`lib/shared/time/kyiv_day.dart`, 11
// production call sites) is proven at the unit/widget tier — most
// thoroughly for `bookedDaysProvider` (`booked_days_notifier_test.dart`) and
// `HttpWorkingHoursRepository._todayKyiv` (`working_hours_repository_test
// .dart`), which both pin a device instant where the Kyiv calendar day
// disagrees with a UTC/host-local one. Neither of those is an integration
// test: they mock the repository / the Dio client respectively, so neither
// proves the WIRING — that a Kyiv-anchored "today" computed deep in a
// provider actually reaches the real HTTP request, through the real screen,
// through the real router, against a REAL (fake-backed) HTTP boundary. Per
// Step 2.7 Rule 3b, a change that reaches provider/repository wiring and the
// API-contract surface (which day the booked-days dots cover — literally the
// example Rule 3b names) requires fake-backed `integration_test/` coverage,
// not just a unit/widget pin.
//
// This flow boots the harness with the injected clock (`AppHarness.boot`'s
// new `clock:` param, added by this audit) pinned to 2026-08-01T22:30Z: the
// UTC calendar day is still the 1st, but Kyiv (EEST, +3) has already rolled
// over to the 2nd (01:30 local) — the identical fixture
// `kyiv_day_test.dart` pins for `kyivDayOf` itself. `kFixedNow` (noon UTC)
// cannot serve this role: it sits deliberately far from either day boundary
// (see its own doc comment), so it never discriminates Kyiv-vs-UTC.
//
// REPO TRAP: `integration_test/` runs ONE file per invocation
// (`flutter test integration_test/kyiv_day_boundary_flow_test.dart
// -d flutter-tester`) — batching two files together kills the second with a
// bogus "log reader failed" (see `docs/mobile-phases/mobile-backlog.md`).
// This does NOT apply to `all_tests_part1.dart`/`all_tests_part2.dart`
// themselves (each is still exactly one `flutter test` invocation; the trap
// is about invoking two SEPARATE files in one command, not about how many
// flows one aggregator groups). Wired into `all_tests_part2.dart` (2026-08-02,
// mobile-dev), beside `master_bookings_flow`, whose screen this flow drives —
// see that file for the CI aggregation this now participates in.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart'
    show kBookedDaysSpanDays;
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// 2026-08-01T22:30Z — UTC calendar day = Aug 1; Kyiv calendar day (EEST,
/// +3) = Aug 2 (01:30 local, already rolled over). Mirrors the fixture
/// `kyiv_day_test.dart`, `booked_days_notifier_test.dart` and
/// `working_hours_repository_test.dart` all use for the identical case.
final DateTime _kKyivBoundaryInstant = DateTime.utc(2026, 8, 1, 22, 30);

/// The CORRECT Kyiv day for [_kKyivBoundaryInstant] — what every Kyiv-
/// anchored "today" in the app must resolve to.
final DateTime _kKyivToday = kyivDayOf(_kKyivBoundaryInstant);

/// The WRONG day a reverted device/UTC-day derivation would compute instead
/// — asserted as a negative-space check throughout, the same pattern
/// `booked_days_notifier_test.dart`'s Kyiv-anchored group uses.
final DateTime _kUtcDeviceDay = DateTime(2026, 8, 1);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'INDEPENDENT_MASTER opens «Мої записи» at the Kyiv day boundary: both '
    'the day-scoped landing fetch AND the booked-days rail window are '
    'anchored to the KYIV day, never the UTC/device one that is still "the '
    '1st" at this exact instant',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        clock: () => _kKyivBoundaryInstant,
      );

      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      expect(AppHarness.location(router), startsWith(RouteNames.masterProfile));

      // «Мої записи» (nav tile 1) — pushes /master/bookings.
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterBookings),
      );
      expect(find.byType(MasterBookingsScreen), findsOneWidget);

      // ── 1. The day-scoped LANDING fetch (`GET /bookings/me?from=&to=`,
      //        from == to, Phase 7.9) lands on Aug 2 — the KYIV day — never
      //        Aug 1, even though Aug 1 is still "today" in UTC. ───────────
      final Map<String, dynamic>? landingQuery = fb.lastMyBookingsQuery;
      expect(
        landingQuery,
        isNotNull,
        reason: 'the landing fetch must have reached the fake backend',
      );
      expect(
        landingQuery!['from'],
        landingQuery['to'],
        reason: 'the landing fetch is a single Kyiv calendar day (from==to)',
      );
      expect(
        landingQuery['from'],
        toApiDate(_kKyivToday),
        reason:
            'BookingsDiscoveryView must open on the KYIV day (Aug 2), not '
            'the UTC/device day (Aug 1) this instant still reads as',
      );
      expect(
        landingQuery['from'],
        isNot(toApiDate(_kUtcDeviceDay)),
        reason:
            'the exact wrong value a device/UTC-day `_today` regression '
            'would send on the wire',
      );

      // ── 2. The SEPARATE booked-days rail window (`GET /bookings/me/
      //        booked-days?from=&to=`, ±kBookedDaysSpanDays,
      //        `booked_days_notifier.dart`) is likewise Kyiv-anchored. ─────
      final Map<String, dynamic>? railQuery = fb.lastBookedDaysQuery;
      expect(
        railQuery,
        isNotNull,
        reason: 'the rail must be fed by GET /bookings/me/booked-days',
      );
      final DateTime expectedFrom = DateTime(
        _kKyivToday.year,
        _kKyivToday.month,
        _kKyivToday.day - kBookedDaysSpanDays,
      );
      final DateTime expectedTo = DateTime(
        _kKyivToday.year,
        _kKyivToday.month,
        _kKyivToday.day + kBookedDaysSpanDays,
      );
      expect(
        railQuery!['from'],
        toApiDate(expectedFrom),
        reason:
            'the ±$kBookedDaysSpanDays-day rail window must be anchored on '
            'the KYIV today (Aug 2), not the UTC/device day (Aug 1)',
      );
      expect(railQuery['to'], toApiDate(expectedTo));
      // Negative-space: the window a device/UTC-day `today` would produce
      // instead — one calendar day off across the WHOLE span.
      final DateTime wrongFrom = DateTime(
        _kUtcDeviceDay.year,
        _kUtcDeviceDay.month,
        _kUtcDeviceDay.day - kBookedDaysSpanDays,
      );
      expect(railQuery['from'], isNot(toApiDate(wrongFrom)));
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
