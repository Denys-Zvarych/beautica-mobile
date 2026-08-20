// mobile-qa (Phase 225 fix pass, mobile-perf MEDIUM #4) — direct unit
// coverage for `invalidateBookingViewsAfterExternalDecline`
// (`booking_calendar_invalidation.dart:83`), specifically its NEWEST fan-out
// target: `nextAppointmentProvider` (added at line 96 for Phase 225's Home
// Hub «Найближчий запис» card).
//
// The function's other four targets — `bookingDetailProvider(id)` (one per
// declined id), `bookingsDayProvider(day)` (one per affected date), and BOTH
// `myBookingsProvider` tabs (upcoming/cancelled) — are already asserted
// end-to-end via the REAL `DayHoursSheet` UI flow in
// `test/features/schedule/presentation/day_hours_sheet_test.dart`'s
// "booking-calendar invalidation is asserted directly" group. Only
// `nextAppointmentProvider` was left uncovered when it was added to the
// fan-out, so this file adds ONLY that assertion — at the cheapest tier that
// proves it directly: a bare `Consumer` button that calls the function with a
// real `WidgetRef` (mirrors `reschedule_navigation_test.dart`'s `_NavProbe`
// pattern), not a full `DayHoursSheet`/`OverridesNotifier` drive.
//
// TRAP AVOIDED: `ref.invalidate` on an already-loaded provider performs a
// SEAMLESS reload — the previous `.value` is retained while the new fetch is
// in flight (Riverpod 3.x). A null-then-value assertion would therefore never
// fire; the refetch COUNT (via a counting provider override, not a
// null-then-value comparison) is the only reliable signal — same technique
// `day_hours_sheet_test.dart`'s own invalidation group already uses.

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_calendar_invalidation.dart';
import 'package:beautica_mobile/features/booking/application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_state.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

/// Minimal authenticated identity — `BookingsDayNotifier.build` watches
/// `authProvider.select(...)`, so an unauthenticated container would rebuild it
/// mid-flight and inflate the fetch count this file asserts on.
class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(
      id: 'master-1',
      email: 'master1@beautica.ua',
      role: UserRole.independentMaster,
      firstName: 'Оля',
      lastName: 'Коваль',
    ),
    accessToken: 'token-1',
  );
}

/// Counts `getMyBookings` calls per DISTINCT status set, so the two day-list
/// family members can be told apart by what they actually put on the wire.
class _CountingBookingRepository implements BookingRepository {
  final List<Set<BookingStatus>> statusCalls = <Set<BookingStatus>>[];

  int callsWithStatuses(Set<BookingStatus> wanted) => statusCalls
      .where(
        (Set<BookingStatus> s) =>
            s.length == wanted.length && s.containsAll(wanted),
      )
      .length;

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required Iterable<BookingStatus> statuses,
    required int page,
    int size = 100,
    BookingSort? sort,
    Iterable<String>? serviceIds,
    DateTime? from,
    DateTime? to,
    Object? partition,
    Object? cancelToken,
  }) async {
    statusCalls.add(statuses.toSet());
    return const PageResponse<Booking>(
      items: <Booking>[],
      page: 0,
      totalPages: 1,
      totalElements: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  testWidgets('invalidateBookingViewsAfterExternalDecline invalidates '
      'nextAppointmentProvider — a declined booking may have been the '
      "client's soonest upcoming appointment", (tester) async {
    int nextApptFetches = 0;

    await tester.pumpApp(
      Scaffold(
        body: Consumer(
          builder: (BuildContext context, WidgetRef ref, _) => TextButton(
            key: const Key('invalidate'),
            onPressed: () => invalidateBookingViewsAfterExternalDecline(
              ref,
              const <String>['booking-1'],
              // future-date-ok: arbitrary bookingsDayProvider invalidation target, never read through BookingDisplayX.isPast — the test only counts nextAppointmentProvider refetches, so this date's value is inconsequential.
              affectedDates: <DateTime>[DateTime.utc(2026, 7, 20)],
            ),
            child: const Text('invalidate'),
          ),
        ),
      ),
      overrides: <Object>[
        nextAppointmentProvider.overrideWith((ref) async {
          nextApptFetches++;
          return null;
        }),
      ],
    );

    // Hold a LIVE subscription so the invalidate triggers a genuine
    // refetch instead of Riverpod simply dropping an unwatched autoDispose
    // member.
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('invalidate'))),
      listen: false,
    );
    final ProviderSubscription<AsyncValue<Booking?>> sub = container.listen(
      nextAppointmentProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    await container.read(nextAppointmentProvider.future);
    expect(
      nextApptFetches,
      1,
      reason: 'sanity: the provider must have fetched once before any tap',
    );

    await tester.tap(find.byKey(const Key('invalidate')));
    await tester.pumpAndSettle();

    await container.read(nextAppointmentProvider.future);
    expect(
      nextApptFetches,
      2,
      reason:
          'invalidateBookingViewsAfterExternalDecline must invalidate '
          'nextAppointmentProvider — this is the specific line the Phase '
          '225 fan-out added, and only a refetch proves it actually fires',
    );
  });

  // REGRESSION GUARD (mobile-perf HIGH, 2026-08-13) — the `bookingsDayProvider`
  // half of the fan-out must reach the member the master's own «Мої записи»
  // ACTUALLY WATCHES.
  //
  // The existing end-to-end coverage in
  // `test/features/schedule/presentation/day_hours_sheet_test.dart` subscribes
  // to `BookingsDayQuery.of(day:)` — the EMPTY-status member. Since
  // CANCELLED/DECLINED became hidden by default (locked 2026-08-13),
  // `BookingsDiscoveryView` watches `BookingsDayQuery.dayList(day:)` instead
  // (`{CONFIRMED, COMPLETED, NOT_COMPLETED}` on the wire) — a DIFFERENT family
  // key. So this function could stay green there while invalidating nothing the
  // screen reads, and `bookings_day_notifier.dart`'s ≤3-day keepAlive LRU pins
  // that stale member ACROSS screen disposal: decline through `DayHoursSheet` →
  // back to «Мої записи» → the declined booking still renders CONFIRMED until a
  // manual pull-to-refresh.
  //
  // Asserted by the STATUS SET each refetch puts on the wire, not by query
  // identity, so a future re-spelling of the default set that changed what the
  // server sees would still fail here.
  //
  // MUTATION: dropped the `BookingsDayQuery.dayList(day:)` invalidation from
  // `invalidateBookingViewsAfterExternalDecline` → this test failed (1 call,
  // not 2). Restored.
  testWidgets('invalidateBookingViewsAfterExternalDecline invalidates the '
      'DEFAULT day-list member the master\'s own screen watches, not only '
      'the plain empty-status one', (tester) async {
    // future-date-ok: an arbitrary calendar-day family key; never read through
    // BookingDisplayX.isPast — the test counts refetches per status set.
    final DateTime affected = DateTime(2026, 7, 20);
    final _CountingBookingRepository repo = _CountingBookingRepository();

    await tester.pumpApp(
      Scaffold(
        body: Consumer(
          builder: (BuildContext context, WidgetRef ref, _) => TextButton(
            key: const Key('invalidate'),
            onPressed: () => invalidateBookingViewsAfterExternalDecline(
              ref,
              const <String>['booking-1'],
              affectedDates: <DateTime>[affected],
            ),
            child: const Text('invalidate'),
          ),
        ),
      ),
      overrides: <Object>[
        bookingRepositoryProvider.overrideWithValue(repo),
        authProvider.overrideWith(_StubAuthNotifier.new),
        nextAppointmentProvider.overrideWith((ref) async => null),
      ],
    );

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('invalidate'))),
      listen: false,
    );
    await container.read(authProvider.future);

    // Built through the SHARED factory with an empty (untouched) selection —
    // exactly as `BookingsDiscoveryView._rebuildQuery` builds it. A
    // hand-written `{confirmed, completed, notCompleted}` literal here would
    // re-create the very drift this guard exists to catch.
    final BookingsDayQuery dayListQuery = BookingsDayQuery.dayList(
      day: affected,
    );
    expect(
      dayListQuery,
      isNot(BookingsDayQuery.of(day: affected)),
      reason:
          'the default day-list member must be a DIFFERENT family key from '
          'the plain empty-status one — if these collapse to one key this '
          'guard silently stops testing anything',
    );

    // A LIVE subscription, or Riverpod just drops the unwatched autoDispose
    // member instead of refetching (which would make the count assertion
    // vacuous).
    final ProviderSubscription<AsyncValue<BookingsDayState>> sub = container
        .listen(
          bookingsDayProvider(dayListQuery),
          (_, _) {},
          fireImmediately: true,
        );
    addTearDown(sub.close);
    await container.read(bookingsDayProvider(dayListQuery).future);
    expect(
      repo.callsWithStatuses(BookingStatus.visibleInDayListByDefault),
      1,
      reason: 'sanity: the default day-list member fetched once before the tap',
    );

    await tester.tap(find.byKey(const Key('invalidate')));
    await tester.pumpAndSettle();
    await container.read(bookingsDayProvider(dayListQuery).future);

    expect(
      repo.callsWithStatuses(BookingStatus.visibleInDayListByDefault),
      2,
      reason:
          'the external decline must invalidate BookingsDayQuery.dayList(day:) '
          '— invalidating only BookingsDayQuery.of(day:) leaves the kept-alive '
          'default member serving the declined booking as CONFIRMED',
    );
  });

  // ══════════════════════════════════════════════════════════════════════
  // THE DELIBERATE NO-OP (audit cycle 2, 2026-08-20 — LOW gap)
  // ══════════════════════════════════════════════════════════════════════
  //
  // ⚠ READ THIS BEFORE "FIXING" THE TEST BELOW BY DELETING IT. ⚠
  //
  // `invalidateBookingViewsAfterProviderClose` serves BOTH provider-initiated
  // closes — DECLINE (CONFIRMED → DECLINED) and COMPLETE (CONFIRMED →
  // COMPLETED) — and invalidates `bookedDaysProvider` on both. On the COMPLETE
  // arm that invalidation is **mathematically redundant, and deliberately kept
  // anyway**:
  //
  //   The day-rail / month-grid dot set comes from
  //   `BookingRepository#findBookedDatesByMasterId`
  //   (`beautica-backend/.../BookingRepository.java:185-195`), whose query
  //   ALLOW-LISTS `CONFIRMED / COMPLETED / NOT_COMPLETED`. A complete moves a
  //   booking from one allow-listed status to another, so the day's dot
  //   membership cannot change. Only DECLINE crosses the boundary.
  //
  // So this test is asserting a refetch that changes nothing on screen. That
  // is the POINT, and it is why the assertion needs its own explanation: the
  // reason the redundant call stays is that this file's entire purpose is that
  // "which caches does a status close drop?" has ONE answer per helper.
  // Re-splitting it per transition — the plausible "optimisation" — is exactly
  // the hand-rolled-fan-out drift that produced the 2026-08-16 archive
  // staleness bug, where two independent fan-outs implementing the same
  // contract silently disagreed about one target. The cost being optimised
  // away is ONE refetch of a singleton, only while «Мої записи» is mounted, on
  // a user-initiated confirm-dialog tap.
  //
  // Removing this assertion therefore removes the only thing standing between
  // that documented decision and a future split. If it ever fails, the
  // question to answer is "did someone split the helper per transition?", not
  // "is this refetch necessary?" — it never was.
  //
  // Counterpart at the CALL SITE: `booking_detail_provider_footer_test.dart`'s
  // "bookedDaysProvider invalidation on COMPLETE" group drives the real
  // «Завершити» confirm dialog, which is what pins that the complete path
  // routes through THIS helper rather than a per-transition replacement.
  //
  // Asserted by refetch COUNT, never by value: `ref.invalidate` reloads
  // seamlessly and RETAINS the previous `.value` (Riverpod 3.x), so a
  // value-shape assertion here could never fail.
  //
  // MUTATION: deleted `ref.invalidate(bookedDaysProvider);` from
  // `invalidateBookingViewsAfterProviderClose`
  // (`booking_calendar_invalidation.dart:242`) → this test failed (1 fetch,
  // not 2). Restored.
  testWidgets('invalidateBookingViewsAfterProviderClose drops '
      'bookedDaysProvider — redundant on the COMPLETE arm BY DESIGN, and '
      'kept so the helper is never split per transition', (tester) async {
    int bookedDaysFetches = 0;

    await tester.pumpApp(
      Scaffold(
        body: Consumer(
          builder: (BuildContext context, WidgetRef ref, _) => TextButton(
            key: const Key('close'),
            // The id is inconsequential: `bookingDetailProvider('booking-1')`
            // has no listener here, so that arm of the fan-out is a documented
            // no-op, as are the two bare families (`bookingsDayProvider`,
            // `masterArchiveProvider`) with nothing watching them.
            onPressed: () =>
                invalidateBookingViewsAfterProviderClose(ref, 'booking-1'),
            child: const Text('close'),
          ),
        ),
      ),
      overrides: <Object>[
        // Overridden rather than left real: the production provider parks a
        // 30-minute keepAlive `Timer` that `flutter_test` would fail on at
        // teardown.
        bookedDaysProvider.overrideWith((ref) async {
          bookedDaysFetches++;
          return <DateTime>{};
        }),
      ],
    );

    // A LIVE subscription — mirrors «Мої записи» sitting warm underneath the
    // pushed detail screen. Without it Riverpod simply drops the invalidated
    // provider instead of refetching, and the count assertion goes vacuous.
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('close'))),
      listen: false,
    );
    final ProviderSubscription<AsyncValue<Set<DateTime>>> sub = container
        .listen(bookedDaysProvider, (_, _) {}, fireImmediately: true);
    addTearDown(sub.close);
    await container.read(bookedDaysProvider.future);
    expect(
      bookedDaysFetches,
      1,
      reason: 'sanity: fetched once for the live watcher before any tap',
    );

    await tester.tap(find.byKey(const Key('close')));
    await tester.pumpAndSettle();

    await container.read(bookedDaysProvider.future);
    expect(
      bookedDaysFetches,
      2,
      reason:
          'the ONE shared provider-close fan-out must drop the dot-set '
          'singleton — see the block comment above for why this stays on the '
          'COMPLETE arm even though a complete cannot change dot membership',
    );
  });
}
