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
import 'package:beautica_mobile/features/booking/domain/booking_partition.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_state.dart';
import 'package:beautica_mobile/features/booking/application/salon_board_refresh_gate.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_shell_provider.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart'
    show kSalonBookingsNavTab;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

/// Mocktail double for the `getMyBookings` call-count assertions below — a
/// DIFFERENT technique from `_CountingBookingRepository` above (which predates
/// this group): mocktail's `verify(...).called(n)` is what
/// `booking_detail_provider_footer_test.dart`'s own "day-list invalidation on
/// success" group already uses for the SAME call, so this mirrors that
/// existing convention rather than inventing a third counting mechanism.
class _MockBookingRepository extends Mock implements BookingRepository {}

/// Stubs `getMyBookings` (whatever the exact args) to return an empty page —
/// only the invocation COUNT matters to the tests below, read back via
/// `verify(...).called(n)` on the mock itself.
void _stubGetMyBookings(_MockBookingRepository repo) {
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
}

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

  /// Phase 382 — the `asMaster` flag of each call, index-aligned with
  /// [statusCalls], so an owner-master (`asOwnerMaster: true`) member can be
  /// told apart from the default `/bookings/me` member with the same statuses.
  final List<bool> asMasterCalls = <bool>[];

  int callsWithStatusesAndScope(
    Set<BookingStatus> wanted, {
    required bool asMaster,
  }) {
    int n = 0;
    for (int i = 0; i < statusCalls.length; i++) {
      final Set<BookingStatus> s = statusCalls[i];
      if (asMasterCalls[i] == asMaster &&
          s.length == wanted.length &&
          s.containsAll(wanted)) {
        n++;
      }
    }
    return n;
  }

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
    bool asMaster = false,
  }) async {
    statusCalls.add(statuses.toSet());
    asMasterCalls.add(asMaster);
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

/// Counts `getSalonBookings` calls per (salonId, masterId, day) — the three
/// fields that actually reach the salon WIRE — for the salon day-LIST group at
/// the bottom of this file.
///
/// A separate double from [_CountingBookingRepository] above because the two
/// count DIFFERENT endpoints: that one tells the master day-list's two members
/// apart by their status sets, this one tells salon BOARD members apart by the
/// `masterId` a «Майстер» filter puts on the path — which is precisely the
/// field a hand-built `masterId: null` invalidation key gets wrong.
///
/// [serverItems] is mutable so a test can move a booking the way the backend
/// write under test just did, making a refetch's VALUE observable and not only
/// its count.
class _SalonCountingRepository implements BookingRepository {
  /// `day` is nullable because phase 342 relaxed `getSalonBookings`' bounds to
  /// optional — the salon ARCHIVE passes neither. Every caller this double
  /// serves is the salon BOARD, which always passes a day, so a `null` here
  /// means a genuinely unbounded read slipped into the board's path and must
  /// NOT silently match a dated [callsFor] probe.
  final List<({String salonId, String? masterId, DateTime? day})> salonCalls =
      <({String salonId, String? masterId, DateTime? day})>[];

  List<Booking> serverItems = const <Booking>[];

  int callsFor({
    required String salonId,
    required DateTime day,
    String? masterId,
  }) => salonCalls
      .where(
        (({String salonId, String? masterId, DateTime? day}) c) =>
            c.salonId == salonId && c.masterId == masterId && c.day == day,
      )
      .length;

  @override
  Future<PageResponse<Booking>> getSalonBookings({
    required String salonId,
    DateTime? from,
    DateTime? to,
    String? masterId,
    Iterable<BookingStatus>? statuses,
    BookingPartition? partition,
    required int page,
    int size = 100,
    BookingSort? sort,
    Object? cancelToken,
  }) async {
    salonCalls.add((salonId: salonId, masterId: masterId, day: from));
    final List<Booking> items = serverItems;
    return PageResponse<Booking>(
      items: items,
      page: 0,
      totalPages: 1,
      totalElements: items.length,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// One CONFIRMED salon booking at [start] — the only field any assertion below
/// reads, so everything else is fixed filler.
Booking _salonBooking({required DateTime start, String id = 'booking-1'}) =>
    Booking(
      id: id,
      masterId: 'master-7',
      masterFirstName: 'Оля',
      masterLastName: 'Коваль',
      masterType: 'SALON_MASTER',
      clientFirstName: 'Марія',
      clientLastName: 'Іванюк',
      serviceId: 'service-1',
      serviceName: 'Манікюр',
      durationMinutes: 60,
      price: 500,
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
      status: BookingStatus.confirmed,
      canReview: false,
    );

/// Captures a real `Ref` (NOT a `WidgetRef`) so the KEYED group at the bottom
/// of this file can invoke the literal production
/// [invalidateBookingViewsAfterBookingCreated] — that helper's only call site
/// is `MasterCreateBookingNotifier.submit`, so unlike its three siblings it is
/// typed on `Ref`. Same technique as
/// `master_create_booking_pin_race_test.dart:176`.
final Provider<void Function(String?)> _createdFanOutProvider =
    Provider<void Function(String?)>(
      (Ref ref) =>
          (String? salonId) =>
              invalidateBookingViewsAfterBookingCreated(ref, salonId: salonId),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(<BookingStatus>{});
    registerFallbackValue(BookingSort.oldest);
  });

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
            // no-op, as is `masterArchiveProvider` (bare family, nothing
            // watching it) and the per-date `bookingsDayProvider` members
            // (nothing built this session for this date, so
            // `DayKeepAliveLru.contains` is false and no eager read fires).
            onPressed: () => invalidateBookingViewsAfterProviderClose(
              ref,
              'booking-1',
              // arbitrary bookingsDayProvider invalidation target, never read
              // through BookingDisplayX.isPast — this test only counts
              // bookedDaysProvider refetches.
              // future-date-ok: see comment block above
              affectedDate: DateTime.utc(2026, 7, 20),
            ),
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

  // ══════════════════════════════════════════════════════════════════════
  // mobile-debugger fix (this track) — `invalidateBookingsDayAfterAppointmentItemReschedule`
  // was missing the `bookedDaysProvider` drop its three siblings
  // (`invalidateBookingViewsAfterExternalDecline`,
  // `invalidateBookingViewsAfterProviderClose`,
  // `invalidateBookingViewsAfterBookingCreated`) all carry.
  // ══════════════════════════════════════════════════════════════════════
  //
  // User-reported symptom this closes: "in the date rail there is no dot
  // under the date number in case the day has only 1 booking and it's a
  // manual booking" — every walk-in reschedule takes this helper's ONLY call
  // site (`booking_confirm_screen.dart`'s `rescheduleAppointmentId != null`
  // branch), and without this invalidation the day-rail/month-panel dot set
  // (a filter-independent `keepAlive()` singleton with a 30-minute TTL) kept
  // serving its stale pre-reschedule membership.
  //
  // Same technique as the `invalidateBookingViewsAfterProviderClose` group
  // above: refetch COUNT via a counting override, never a value assertion
  // (`ref.invalidate` reloads seamlessly and retains the previous `.value`,
  // Riverpod 3.x), with a LIVE subscription held so Riverpod actually
  // refetches instead of just dropping the unwatched provider.
  //
  // MUTATION: deleted `ref.invalidate(bookedDaysProvider);` from
  // `invalidateBookingsDayAfterAppointmentItemReschedule`
  // (`booking_calendar_invalidation.dart:503`) → this test failed (1 fetch,
  // not 2, matching the debugger's throwaway probe exactly). Restored.
  group('invalidateBookingsDayAfterAppointmentItemReschedule drops '
      'bookedDaysProvider', () {
    testWidgets('a per-item VISIT reschedule refetches the day-rail dot set', (
      tester,
    ) async {
      int bookedDaysFetches = 0;

      await tester.pumpApp(
        Scaffold(
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) => TextButton(
              key: const Key('reschedule'),
              // The date is inconsequential: `bookingsDayProvider` has no
              // listener here, so that half of the fan-out is a documented
              // no-op (DayKeepAliveLru.contains is false, no eager read
              // fires) — this test only counts bookedDaysProvider
              // refetches.
              onPressed: () =>
                  invalidateBookingsDayAfterAppointmentItemReschedule(
                    ref,
                    // future-date-ok: see comment above
                    affectedDays: <DateTime>{DateTime.utc(2026, 7, 20)},
                  ),
              child: const Text('reschedule'),
            ),
          ),
        ),
        overrides: <Object>[
          // Overridden rather than left real: the production provider
          // parks a 30-minute keepAlive `Timer` that `flutter_test` would
          // fail on at teardown.
          bookedDaysProvider.overrideWith((ref) async {
            bookedDaysFetches++;
            return <DateTime>{};
          }),
        ],
      );

      // A LIVE subscription — mirrors «Мої записи» sitting warm underneath
      // the reschedule flow. Without it Riverpod simply drops the
      // invalidated provider instead of refetching, and the count
      // assertion goes vacuous.
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('reschedule'))),
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

      await tester.tap(find.byKey(const Key('reschedule')));
      await tester.pumpAndSettle();

      await container.read(bookedDaysProvider.future);
      expect(
        bookedDaysFetches,
        2,
        reason:
            'a per-item VISIT reschedule must drop the dot-set singleton '
            '— a day whose ONLY booking just moved on/off it must not keep '
            'showing its stale dot state',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // ITEM 6 (this track) — pin the wasPinned GATE's invocation count.
  // ══════════════════════════════════════════════════════════════════════
  //
  // Every test above proves the FIX exists (a decline/complete/reschedule
  // drops the right caches). None of them distinguish "the eager read fired
  // because the query was genuinely pinned" from "the eager read fires
  // unconditionally" — a bare `ref.invalidate` + a bare `ref.read` right
  // after it would ALSO make every test above pass, since `ref.read` on a
  // family member CREATES it if absent. If a future edit drops the
  // `if (wasPinned)` guard in `invalidateBookingViewsAfterProviderClose` or
  // `invalidateBookingsDayAfterAppointmentItemReschedule`, every call —
  // including one for a date NOBODY is viewing — silently starts an
  // unconditional `getMyBookings` round trip (mobile-perf's own "≤4 eager
  // GETs per reschedule, typically 1–2" ceases to be a ceiling at all), with
  // nothing above going red: those tests only ever exercise the PINNED path.
  //
  // These two groups exercise BOTH branches of the gate directly, via
  // mocktail `verify(...).called(n)` — the UNPINNED case asserting exactly
  // ZERO calls is the one that actually pins the guard: a dropped `if
  // (wasPinned)` cannot make a PINNED-case count wrong (an unconditional
  // eager read is a no-op extra flush on an already-flushed element — see
  // `booking_calendar_invalidation.dart`'s FIX A doc), but it unconditionally
  // BUILDS a previously-nonexistent element in the UNPINNED case, which
  // `verify(...).called(0)` catches immediately.
  group('ITEM 6 — wasPinned gate call-count', () {
    // arbitrary bookingsDayProvider key, never read through
    // BookingDisplayX.isPast — these tests only count getMyBookings calls.
    // future-date-ok: see comment above
    final DateTime affected = DateTime.utc(2026, 7, 20);

    group('invalidateBookingViewsAfterProviderClose', () {
      testWidgets(
        'PINNED — both day-list members already built this session refetch '
        'exactly once each (2 initial + 2 eager reads = 4)',
        (tester) async {
          final repo = _MockBookingRepository();
          _stubGetMyBookings(repo);

          await tester.pumpApp(
            Scaffold(
              body: Consumer(
                builder: (BuildContext context, WidgetRef ref, _) => TextButton(
                  key: const Key('close'),
                  onPressed: () => invalidateBookingViewsAfterProviderClose(
                    ref,
                    'booking-1',
                    affectedDate: affected,
                  ),
                  child: const Text('close'),
                ),
              ),
            ),
            overrides: <Object>[
              bookingRepositoryProvider.overrideWithValue(repo),
              authProvider.overrideWith(_StubAuthNotifier.new),
              bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
            ],
          );

          final ProviderContainer container = ProviderScope.containerOf(
            tester.element(find.byKey(const Key('close'))),
            listen: false,
          );
          await container.read(authProvider.future);

          // PIN both members via a live subscription + await — this is what
          // `DayKeepAliveLru.contains` reads back as `wasPinned`.
          for (final BookingsDayQuery q in <BookingsDayQuery>[
            BookingsDayQuery.dayList(day: affected),
            BookingsDayQuery.of(day: affected),
          ]) {
            final ProviderSubscription<AsyncValue<BookingsDayState>> sub =
                container.listen(bookingsDayProvider(q), (_, _) {});
            addTearDown(sub.close);
            await container.read(bookingsDayProvider(q).future);
          }
          verify(
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
          ).called(2); // sanity: one fetch per member before any tap.

          await tester.tap(find.byKey(const Key('close')));
          await tester.pumpAndSettle();

          verify(
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
          ).called(
            2,
          ); // ONE eager read-back per pinned member, not zero, not two.
        },
      );

      testWidgets('UNPINNED — a date nobody built this session triggers ZERO '
          'getMyBookings calls (proves the eager read is GATED, not '
          'unconditional)', (tester) async {
        final repo = _MockBookingRepository();
        _stubGetMyBookings(repo);

        await tester.pumpApp(
          Scaffold(
            body: Consumer(
              builder: (BuildContext context, WidgetRef ref, _) => TextButton(
                key: const Key('close'),
                onPressed: () => invalidateBookingViewsAfterProviderClose(
                  ref,
                  'booking-1',
                  affectedDate: affected,
                ),
                child: const Text('close'),
              ),
            ),
          ),
          overrides: <Object>[
            bookingRepositoryProvider.overrideWithValue(repo),
            authProvider.overrideWith(_StubAuthNotifier.new),
            bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
          ],
        );

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byKey(const Key('close'))),
          listen: false,
        );
        await container.read(authProvider.future);

        // Deliberately NO subscription/read for `affected`'s queries before
        // tapping — neither member has ever been built this session, so
        // `DayKeepAliveLru.contains` must read `false` for both.
        await tester.tap(find.byKey(const Key('close')));
        await tester.pumpAndSettle();

        verifyNever(
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
        );
      });
    });

    group('invalidateBookingsDayAfterAppointmentItemReschedule', () {
      testWidgets(
        'PINNED — an already-built day-list member refetches exactly once '
        '(1 initial + 1 eager read = 2)',
        (tester) async {
          final repo = _MockBookingRepository();
          _stubGetMyBookings(repo);

          await tester.pumpApp(
            Scaffold(
              body: Consumer(
                builder: (BuildContext context, WidgetRef ref, _) => TextButton(
                  key: const Key('reschedule'),
                  onPressed: () =>
                      invalidateBookingsDayAfterAppointmentItemReschedule(
                        ref,
                        affectedDays: <DateTime>{affected},
                      ),
                  child: const Text('reschedule'),
                ),
              ),
            ),
            overrides: <Object>[
              bookingRepositoryProvider.overrideWithValue(repo),
              authProvider.overrideWith(_StubAuthNotifier.new),
            ],
          );

          final ProviderContainer container = ProviderScope.containerOf(
            tester.element(find.byKey(const Key('reschedule'))),
            listen: false,
          );
          await container.read(authProvider.future);

          final BookingsDayQuery dayListQuery = BookingsDayQuery.dayList(
            day: affected,
          );
          final ProviderSubscription<AsyncValue<BookingsDayState>> sub =
              container.listen(bookingsDayProvider(dayListQuery), (_, _) {});
          addTearDown(sub.close);
          await container.read(bookingsDayProvider(dayListQuery).future);

          await tester.tap(find.byKey(const Key('reschedule')));
          await tester.pumpAndSettle();

          verify(
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
          ).called(
            2,
          ); // 1 initial fetch + 1 eager read-back, never 0, never 2 extra.
        },
      );

      testWidgets(
        'UNPINNED — an untouched date triggers ZERO getMyBookings calls',
        (tester) async {
          final repo = _MockBookingRepository();
          _stubGetMyBookings(repo);

          await tester.pumpApp(
            Scaffold(
              body: Consumer(
                builder: (BuildContext context, WidgetRef ref, _) => TextButton(
                  key: const Key('reschedule'),
                  onPressed: () =>
                      invalidateBookingsDayAfterAppointmentItemReschedule(
                        ref,
                        affectedDays: <DateTime>{affected},
                      ),
                  child: const Text('reschedule'),
                ),
              ),
            ),
            overrides: <Object>[
              bookingRepositoryProvider.overrideWithValue(repo),
              authProvider.overrideWith(_StubAuthNotifier.new),
            ],
          );

          final ProviderContainer container = ProviderScope.containerOf(
            tester.element(find.byKey(const Key('reschedule'))),
            listen: false,
          );
          await container.read(authProvider.future);

          await tester.tap(find.byKey(const Key('reschedule')));
          await tester.pumpAndSettle();

          verifyNever(
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
          );
        },
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 2026-09-19 (mobile-qa, PASS A) — `invalidateBookingViewsAfterBookingCreated`'s
  // NEWEST fan-out target: `salonBookedDaysProvider(salonId)`.
  // ══════════════════════════════════════════════════════════════════════
  //
  // Same shape as the `bookedDaysProvider` groups above, and added for the
  // same reason those were: an arm was added to this helper's fan-out and
  // nothing in this file — the file that owns the helper — could see it. Grep
  // proof at the time of writing: `salonBookedDays` appeared ZERO times under
  // `test/`.
  //
  // WHAT MAKES THIS A FAMILY TEST AND NOT A SINGLETON ONE. The two tests
  // above invalidate a keepAlive SINGLETON, where "was it dropped?" is the
  // whole question. Here the bug class is a WRONG ARGUMENT: an arm written as
  // `ref.invalidate(salonBookedDaysProvider(someOtherId))` drops a member,
  // refetches something, and would satisfy any test that only counts total
  // fetches. So both members are live and counted SEPARATELY, and the
  // negative half («salon-2» stays at 1) is asserted as hard as the positive.
  // Mutation-probed in both directions — see the group body.
  group('invalidateBookingViewsAfterBookingCreated drops '
      'salonBookedDaysProvider — KEYED', () {
    const String kSalonUnderTest = 'salon-1';
    const String kOtherSalon = 'salon-2';

    /// Runs the LITERAL production helper with a real `Ref` (this helper
    /// takes `Ref`, not the `WidgetRef` its three siblings take, because its
    /// only call site is a notifier — so the `Consumer` idiom the groups
    /// above use does not type-check here; `master_create_booking_pin_race_
    /// test.dart:176` captures a real `Ref` the same way), with BOTH day-dot
    /// providers replaced by counting overrides and BOTH named salon members
    /// held LIVE.
    ///
    /// Live subscriptions are not optional: Riverpod DROPS an invalidated
    /// provider that nobody listens to instead of refetching it, which would
    /// make both halves of the assertion below silently unobservable.
    Future<Map<String, int>> runFanOut({required String? salonId}) async {
      final Map<String, int> salonFetches = <String, int>{};

      final ProviderContainer container = ProviderContainer(
        // ignore: avoid_dynamic_calls
        overrides: <Object>[
          // Overridden rather than left real, for the reason stated on every
          // sibling group above: the production bodies park a 30-minute
          // keepAlive `Timer` that `flutter_test` fails on at teardown.
          bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
          salonBookedDaysProvider.overrideWith((ref, String id) async {
            salonFetches[id] = (salonFetches[id] ?? 0) + 1;
            return <DateTime>{};
          }),
        ].cast(),
      );
      addTearDown(container.dispose);

      // AUDIT LOW-4 (2026-09-20) — this group models a walk-in created FROM
      // the board, which means the shell is standing on «Записи». Since the
      // fix, `invalidateBookingViewsAfterBookingCreated` reads that index and
      // DEFERS the board-scoped half when it is any other tab, so a container
      // that left `salonShellProvider` at its default 0 would now be
      // asserting the deferred path while claiming to assert the live one.
      // Held live by a listener because the provider is `autoDispose`.
      // The NOT-selected case is covered by its own group at the bottom of
      // this file.
      for (final String id in const <String>[kSalonUnderTest, kOtherSalon]) {
        final ProviderSubscription<int> shell = container.listen(
          salonShellProvider(id),
          (_, _) {},
        );
        addTearDown(shell.close);
        container
            .read(salonShellProvider(id).notifier)
            .select(kSalonBookingsNavTab);
      }

      for (final String id in const <String>[kSalonUnderTest, kOtherSalon]) {
        final ProviderSubscription<AsyncValue<Set<DateTime>>> sub = container
            .listen(
              salonBookedDaysProvider(id),
              (_, _) {},
              fireImmediately: true,
            );
        addTearDown(sub.close);
        await container.read(salonBookedDaysProvider(id).future);
      }
      expect(
        salonFetches,
        <String, int>{kSalonUnderTest: 1, kOtherSalon: 1},
        reason: 'sanity: one fetch per live member before the fan-out',
      );

      container.read(_createdFanOutProvider)(salonId);
      for (final String id in const <String>[kSalonUnderTest, kOtherSalon]) {
        await container.read(salonBookedDaysProvider(id).future);
      }
      return salonFetches;
    }

    // MUTATION (observed 2026-09-19): deleting the whole
    // `if (salonId != null) { ref.invalidate(salonBookedDaysProvider(salonId)); }`
    // block from `booking_calendar_invalidation.dart:460` → this test FAILED
    // (`salon-1` stayed at 1, expected 2). Restored by `cp` from a backup.
    //
    // MUTATION (observed 2026-09-19): rewriting the arm to
    // `ref.invalidate(salonBookedDaysProvider('salon-2'))` — a member that
    // genuinely exists and genuinely refetches — → this test FAILED
    // (`salon-1` 1, not 2). That is the probe that makes the family KEY, not
    // merely "an invalidate happened", the thing under test. Restored.
    //
    // MUTATION (observed 2026-09-19) for the NEGATIVE half, which the probe
    // above cannot reach (`expect` stops at the first failure): ADDING a
    // second, over-broad `ref.invalidate(salonBookedDaysProvider('salon-2'))`
    // beside the correct one → this test FAILED on the other-salon assertion
    // (`salon-2` 2, not 1). Both halves are therefore load-bearing, proven
    // independently. Restored.
    test('the created booking\'s OWN salon refetches, and no other '
        'salon\'s member is dropped', () async {
      final Map<String, int> fetches = await runFanOut(
        salonId: kSalonUnderTest,
      );

      expect(
        fetches[kSalonUnderTest],
        2,
        reason:
            'the salon «Записи» board the walk-in was created from must '
            'drop its rail-dot set — it is a 30-minute-TTL keepAlive member '
            'that nothing else in this fan-out reaches',
      );
      expect(
        fetches[kOtherSalon],
        1,
        reason:
            'an owner managing several salons must not pay a full ±180-day '
            'sweep per board for a booking that cannot have moved the other '
            'boards\' dots',
      );
    });

    // MUTATION (observed 2026-09-19): replacing the null guard with
    // `ref.invalidate(salonBookedDaysProvider(salonId ?? 'salon-1'))` → this
    // test FAILED (`salon-1` 2, not 1). Restored.
    test('a NULL salonId (the independent-master wizard) drops no '
        'salon member at all', () async {
      final Map<String, int> fetches = await runFanOut(salonId: null);

      expect(
        fetches,
        <String, int>{kSalonUnderTest: 1, kOtherSalon: 1},
        reason:
            '`booking_confirm_screen.dart` has no salon; the null guard is '
            'what keeps the solo flow byte-for-byte what it was',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 2026-09-19 (mobile-perf MEDIUM fix) — the SAME `salonBookedDaysProvider`
  // arm, on the two helpers the CREATE path's fix skipped:
  // `invalidateBookingViewsAfterProviderClose` (decline / complete) and
  // `invalidateBookingsDayAfterAppointmentItemReschedule` (per-item move).
  // ══════════════════════════════════════════════════════════════════════
  //
  // Both are reached from `booking_detail_screen.dart` — the salon «Записи»
  // board's own drill-in (`salon_bookings_screen.dart:_onBookingTap` →
  // `RouteNames.salonStaffBookingDetail`) — so without these arms a close or
  // a move performed from the board left its rail dot stale for the same 30
  // minutes the create-path fix had just closed.
  //
  // Same technique as the KEYED group above, and same reason: the bug class
  // is a WRONG ARGUMENT, not a missing call, so BOTH members are live and
  // counted SEPARATELY and the negative half is asserted as hard as the
  // positive.
  group('the salonBookedDaysProvider arm on the CLOSE and RESCHEDULE '
      'helpers — KEYED', () {
    const String kSalonUnderTest = 'salon-1';
    const String kOtherSalon = 'salon-2';

    /// Pumps a `Consumer` (these two helpers take a `WidgetRef`, unlike the
    /// `Ref`-taking create helper above), holds BOTH named salon members
    /// live, fires [fanOut], and returns the per-salon refetch counts.
    ///
    /// Live subscriptions are not optional: Riverpod DROPS an invalidated
    /// provider nobody listens to instead of refetching it, which would make
    /// every assertion below silently unobservable.
    Future<Map<String, int>> runFanOut(
      WidgetTester tester,
      void Function(WidgetRef ref) fanOut, {

      /// The salon's day set as the SERVER would answer it. Mutated between
      /// the pre-fan-out read and the fan-out by the cross-midnight test
      /// below, so the refetched value proves what the member actually
      /// re-derives — not merely that a refetch happened.
      Set<DateTime>? serverDays,
      void Function(ProviderContainer container)? beforeFanOut,
      void Function(Set<DateTime> refetched)? onRefetched,
    }) async {
      final Map<String, int> salonFetches = <String, int>{};

      await tester.pumpApp(
        Scaffold(
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) => TextButton(
              key: const Key('fan-out'),
              onPressed: () => fanOut(ref),
              child: const Text('fan-out'),
            ),
          ),
        ),
        overrides: <Object>[
          // Overridden rather than left real, for the reason stated on every
          // sibling group: the production bodies park a 30-minute keepAlive
          // `Timer` that `flutter_test` fails on at teardown.
          //
          // `masterArchiveProvider` is deliberately NOT overridden: it is a
          // bare family with nothing listening in this harness, so its
          // invalidation is a documented no-op (same reasoning the
          // `invalidateBookingViewsAfterProviderClose` group above records).
          bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
          salonBookedDaysProvider.overrideWith((ref, String id) async {
            salonFetches[id] = (salonFetches[id] ?? 0) + 1;
            return <DateTime>{...?serverDays};
          }),
        ],
      );

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('fan-out'))),
        listen: false,
      );
      for (final String id in const <String>[kSalonUnderTest, kOtherSalon]) {
        final ProviderSubscription<AsyncValue<Set<DateTime>>> sub = container
            .listen(
              salonBookedDaysProvider(id),
              (_, _) {},
              fireImmediately: true,
            );
        addTearDown(sub.close);
        await container.read(salonBookedDaysProvider(id).future);
      }
      expect(
        salonFetches,
        <String, int>{kSalonUnderTest: 1, kOtherSalon: 1},
        reason: 'sanity: one fetch per live member before the fan-out',
      );

      beforeFanOut?.call(container);
      await tester.tap(find.byKey(const Key('fan-out')));
      await tester.pump();
      Set<DateTime>? refetched;
      for (final String id in const <String>[kSalonUnderTest, kOtherSalon]) {
        final Set<DateTime> value = await container.read(
          salonBookedDaysProvider(id).future,
        );
        if (id == kSalonUnderTest) refetched = value;
      }
      onRefetched?.call(refetched ?? const <DateTime>{});
      return salonFetches;
    }

    // MUTATION (observed 2026-09-19): deleting the
    // `if (salonId != null) { ref.invalidate(salonBookedDaysProvider(salonId)); }`
    // block from `invalidateBookingViewsAfterProviderClose` → FAILED
    // (`salon-1` 1, not 2). Restored by `cp` from a backup.
    testWidgets('a provider CLOSE drops the viewing board\'s own salon '
        'member, and no other salon\'s', (tester) async {
      final Map<String, int> fetches = await runFanOut(
        tester,
        (WidgetRef ref) => invalidateBookingViewsAfterProviderClose(
          ref,
          'booking-1',
          // The date only keys `bookingsDayProvider`, which has no listener
          // here, so that half of the fan-out is a documented no-op.
          // future-date-ok: a bare family key, never fed to `isPast`.
          affectedDate: DateTime.utc(2026, 7, 20),
          salonId: kSalonUnderTest,
        ),
      );

      expect(fetches[kSalonUnderTest], 2);
      expect(
        fetches[kOtherSalon],
        1,
        reason:
            'an owner managing several salons must not pay a full ±180-day '
            'sweep per board for a close on one of them',
      );
    });

    testWidgets('a provider CLOSE with a NULL salonId (the /master/* and '
        'archive mounts) drops no salon member at all', (tester) async {
      final Map<String, int> fetches = await runFanOut(
        tester,
        (WidgetRef ref) => invalidateBookingViewsAfterProviderClose(
          ref,
          'booking-1',
          // future-date-ok: see the test above — a bare family key.
          affectedDate: DateTime.utc(2026, 7, 20),
        ),
      );

      expect(fetches, <String, int>{kSalonUnderTest: 1, kOtherSalon: 1});
    });

    // THE "ONE MEMBER COVERS BOTH DAYS" CLAIM, MECHANICALLY.
    //
    // `salonBookedDays` is NOT keyed by date: it is one unpaged
    // `GET /bookings/salon/{id}/booked-days` over the whole Kyiv-anchored
    // today ± `kBookedDaysSpanDays` window, returning the complete set in a
    // single response (`booked_days_notifier.dart`'s `_bookedDaysWindow`).
    // So a cross-midnight move — TWO entries in `affectedDays` — needs ONE
    // member invalidate to re-derive BOTH the vacated day (dot must GO) and
    // the newly occupied one (dot must APPEAR).
    //
    // Asserted on the refetched VALUE, not on a call count, and what the
    // value pins is the CLAIM ABOVE: ONE un-keyed member invalidate
    // re-derives the WHOLE today ± `kBookedDaysSpanDays` window, so in a
    // SINGLE refetch the vacated day disappears from the dot set and the
    // newly occupied day appears in it. A call count cannot see that — it
    // only counts requests, and says nothing about which days came back.
    //
    // (It also cannot tell the arm's PLACEMENT apart: Riverpod coalesces
    // repeated `invalidate`s of one member within a turn and the provider is
    // not date-keyed, so moving the `if (salonId != null)` block inside the
    // `for (final DateTime day in affectedDays)` loop yields the identical
    // count AND the identical `{occupied}` value — probed 2026-09-19. That
    // placement is a style question here, not a correctness one; this test
    // does not, and cannot, pin it. What it pins is the window re-derivation
    // above, and the `serverDays` swap below is what makes that bite.)
    //
    // MUTATION (observed 2026-09-19): deleting the
    // `if (salonId != null) { ref.invalidate(salonBookedDaysProvider(salonId)); }`
    // block from `invalidateBookingsDayAfterAppointmentItemReschedule` →
    // FAILED (the member still served the pre-move `{20 Jul}`). Restored by
    // `cp` from a backup.
    testWidgets('a CROSS-MIDNIGHT per-item reschedule re-derives BOTH the '
        'vacated and the newly occupied day from ONE member invalidate', (
      tester,
    ) async {
      // A fixed calendar day used ONLY as a day-set element and a
      // `bookingsDayProvider` key — no `isPast`/`hasStarted` predicate and no
      // wall-clock read is reachable from this test, so it cannot expire.
      // future-date-ok: the day the rescheduled item moved OFF of.
      final DateTime vacated = DateTime.utc(2026, 7, 20);
      // future-date-ok: same reasoning — the day the item moved ON to.
      final DateTime occupied = DateTime.utc(2026, 7, 21);

      // The salon's dot set as the SERVER answers it. Starts with the item on
      // `vacated`; the `beforeFanOut` hook below performs the move, standing
      // in for the `PATCH .../reschedule` that has already landed by the time
      // the helper runs.
      final Set<DateTime> serverDays = <DateTime>{vacated};
      Set<DateTime> refetched = const <DateTime>{};

      final Map<String, int> fetches = await runFanOut(
        tester,
        (WidgetRef ref) => invalidateBookingsDayAfterAppointmentItemReschedule(
          ref,
          affectedDays: <DateTime>{vacated, occupied},
          salonId: kSalonUnderTest,
        ),
        serverDays: serverDays,
        beforeFanOut: (_) => serverDays
          ..clear()
          ..add(occupied),
        onRefetched: (Set<DateTime> value) => refetched = value,
      );

      expect(
        refetched,
        <DateTime>{occupied},
        reason:
            'ONE invalidate of the un-keyed salon member must re-derive the '
            'WHOLE window: the vacated day loses its dot and the newly '
            'occupied day gains one, in a single refetch',
      );
      expect(
        fetches[kSalonUnderTest],
        2,
        reason: 'exactly one refetch on top of the initial read',
      );
      expect(fetches[kOtherSalon], 1);
    });

    testWidgets('a per-item reschedule with a NULL salonId (the CLIENT and '
        'independent-master paths) drops no salon member at all', (
      tester,
    ) async {
      final Map<String, int> fetches = await runFanOut(
        tester,
        (WidgetRef ref) => invalidateBookingsDayAfterAppointmentItemReschedule(
          ref,
          // future-date-ok: see the test above — a bare family key.
          affectedDays: <DateTime>{DateTime.utc(2026, 7, 20)},
        ),
      );

      expect(fetches, <String, int>{kSalonUnderTest: 1, kOtherSalon: 1});
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 2026-09-19 (mobile-qa, PASS B) — `_invalidateSalonDayLists`: the salon
  // board's day LIST, the half the `salonBookedDaysProvider` arm above left
  // CONTRADICTING itself.
  // ══════════════════════════════════════════════════════════════════════
  //
  // Teaching the two helpers to drop `salonBookedDaysProvider` refreshed the
  // rail DOT while the board's LIST kept the booking at its old slot — both
  // helpers built only `MasterOwnDayQuery` keys and the board watches a
  // `SalonDayQuery`. Before that arm existed both halves went stale together;
  // afterwards they disagreed, which is strictly worse. This group pins the
  // shared `_invalidateSalonDayLists` that closes it.
  //
  // WHY EVERY FIXTURE HERE IS A *FILTERED* KEY, AND WHY THAT IS THE WHOLE
  // POINT. `bookings_discovery_view.dart:_rebuildQuery` builds the board's
  // member from the screen's own mutable state — the «Майстер» filter's
  // `masterId`, plus the sheet's `statuses`/`serviceIds` — and all four are
  // part of the freezed family key. An UNFILTERED fixture would pass against
  // a naive hand-built `salonDayList(salonId: …, day: …, masterId: null)`
  // literal, i.e. against an implementation that is inert the moment the
  // owner filters anything. So every board fixture below carries a non-null
  // `masterId` AND the day-list default status set, and the mutation log on
  // the first test records that literal going RED.
  //
  // MECHANISM WORTH KNOWING BEFORE READING THE COUNTS. A filtered salon
  // member does NOT fetch and does NOT take an LRU slot
  // (`bookings_day_notifier.dart`'s "SALON FILTER DELEGATION"): it
  // `ref.watch`es its `fetchKey` — the same (day, salonId, masterId) with both
  // list fields emptied — and narrows that member's items client-side. So the
  // member `DayKeepAliveLru.liveQueries` enumerates is the fetchKey, which
  // still carries `masterId`; invalidating it cascades into the filtered
  // member the board actually renders. That cascade is what these counts
  // observe, and it is also why the enumeration cannot be replaced by any
  // literal the helper could build from its own arguments.
  group('the SALON day-LIST arm on the CLOSE and RESCHEDULE helpers', () {
    const String kSalon = 'salon-1';
    const String kOtherSalon = 'salon-2';
    // The «Майстер» filter's selection — the field a hand-built key gets
    // wrong, and the one this group exists to defend.
    const String kBoardMaster = 'master-7';

    // Plain (y, m, d) tokens, LOCAL like everything `dateOnly` produces — no
    // `isPast`/`hasStarted` predicate and no wall-clock read is reachable from
    // this group, so they cannot expire.
    // future-date-ok: bare family keys.
    final DateTime affected = DateTime(2026, 7, 20);
    // future-date-ok: bare family key.
    final DateTime unaffected = DateTime(2026, 7, 21);

    /// The board's REAL live member: filtered by master AND by the day-list
    /// default status set (`BookingStatus.dayListWireStatuses({})`).
    BookingsDayQuery board({
      required DateTime day,
      String salonId = kSalon,
      String? masterId = kBoardMaster,
    }) => BookingsDayQuery.salonDayList(
      day: day,
      salonId: salonId,
      masterId: masterId,
    );

    /// Pumps a bare `Consumer` that hands its real `WidgetRef` back through
    /// [fire], so a test can run a helper SYNCHRONOUSLY from its own body and
    /// read the fetch count before any microtask drains. That timing is the
    /// only signal that separates the eager `ref.read` back (which refetches
    /// inside the helper) from Riverpod's own queued refresh (which does not)
    /// — see the `isWatched` test at the bottom.
    Future<
      ({
        ProviderContainer container,
        _SalonCountingRepository repo,
        void Function(void Function(WidgetRef ref)) fire,
      })
    >
    pumpProbe(WidgetTester tester) async {
      final _SalonCountingRepository repo = _SalonCountingRepository();
      late WidgetRef captured;

      await tester.pumpApp(
        Scaffold(
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) {
              captured = ref;
              return const SizedBox(key: Key('probe'));
            },
          ),
        ),
        overrides: <Object>[
          bookingRepositoryProvider.overrideWithValue(repo),
          authProvider.overrideWith(_StubAuthNotifier.new),
          // Overridden rather than left real, for the reason stated on every
          // sibling group: the production bodies park a 30-minute keepAlive
          // `Timer` that `flutter_test` fails on at teardown.
          bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
          salonBookedDaysProvider.overrideWith(
            (ref, String id) async => <DateTime>{},
          ),
        ],
      );

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('probe'))),
        listen: false,
      );
      // `BookingsDayNotifier.build` watches `authProvider.select(...)`; an
      // unresolved session would rebuild every member mid-flight and inflate
      // the counts below.
      await container.read(authProvider.future);

      return (
        container: container,
        repo: repo,
        fire: (void Function(WidgetRef ref) run) => run(captured),
      );
    }

    /// Holds [query] live for the whole test — a watched board, exactly as a
    /// mounted `BookingsDiscoveryView` would.
    Future<void> watch(ProviderContainer c, BookingsDayQuery query) async {
      final ProviderSubscription<AsyncValue<BookingsDayState>> sub = c.listen(
        bookingsDayProvider(query),
        (_, _) {},
      );
      addTearDown(sub.close);
      await c.read(bookingsDayProvider(query).future);
    }

    // ── 1. THE WHOLE POINT: a FILTERED live member on the affected day is
    //       dropped by BOTH helpers ──────────────────────────────────────
    //
    // MUTATION (observed 2026-09-19, both tests): replacing
    // `_invalidateSalonDayLists`'s enumeration body with the naive hand-built
    // literal
    //   `ref.invalidate(bookingsDayProvider(
    //      BookingsDayQuery.salonDayList(day: day, salonId: salonId)));`
    //   (i.e. `masterId: null`)
    // → BOTH FAILED (1 call, not 2; the board still served the 10:00 slot).
    // Deleting the `_invalidateSalonDayLists(...)` call outright → same two
    // failures. Restored by `cp` from a backup — never `git checkout`.
    for (final ({String label, void Function(WidgetRef, DateTime) run}) arm
        in <({String label, void Function(WidgetRef, DateTime) run})>[
          (
            label: 'a provider CLOSE',
            run: (WidgetRef ref, DateTime day) =>
                invalidateBookingViewsAfterProviderClose(
                  ref,
                  'booking-1',
                  affectedDate: day,
                  salonId: kSalon,
                ),
          ),
          (
            label: 'a per-item RESCHEDULE',
            run: (WidgetRef ref, DateTime day) =>
                invalidateBookingsDayAfterAppointmentItemReschedule(
                  ref,
                  affectedDays: <DateTime>{day},
                  salonId: kSalon,
                ),
          ),
        ]) {
      testWidgets(
        '${arm.label} drops the board\'s FILTERED live salon member on the '
        'affected day — the list re-derives the moved booking, not just the '
        'dot',
        (tester) async {
          final probe = await pumpProbe(tester);
          probe.repo.serverItems = <Booking>[
            _salonBooking(start: DateTime(2026, 7, 20, 10)),
          ];

          await watch(probe.container, board(day: affected));
          expect(
            probe.repo.callsFor(
              salonId: kSalon,
              day: affected,
              masterId: kBoardMaster,
            ),
            1,
            reason:
                'sanity: the filtered member resolved through its fetchKey, '
                'which carries the «Майстер» filter onto the wire',
          );
          expect(
            (await probe.container.read(
              bookingsDayProvider(board(day: affected)).future,
            )).items.single.startAt,
            DateTime(2026, 7, 20, 10),
            reason: 'sanity: the board renders the PRE-write slot',
          );

          // The write has already landed on the server by the time the helper
          // runs — move the booking so a refetch is observable by VALUE and
          // not merely by count.
          probe.repo.serverItems = <Booking>[
            _salonBooking(start: DateTime(2026, 7, 20, 14)),
          ];

          probe.fire((WidgetRef ref) => arm.run(ref, affected));
          await tester.pump();

          expect(
            probe.repo.callsFor(
              salonId: kSalon,
              day: affected,
              masterId: kBoardMaster,
            ),
            2,
            reason:
                'the enumerated SalonDayQuery must be invalidated; a '
                'hand-built masterId:null literal names a member nobody is '
                'watching and leaves this at 1',
          );
          expect(
            (await probe.container.read(
              bookingsDayProvider(board(day: affected)).future,
            )).items.single.startAt,
            DateTime(2026, 7, 20, 14),
            reason:
                'THE BUG: the rail dot refreshed while the board kept drawing '
                'the booking at its old slot',
          );
        },
      );
    }

    // ── 2. a DIFFERENT salon must survive ──────────────────────────────
    //
    // MUTATION (observed 2026-09-19): deleting
    // `if (liveQuery.salonId != salonId) continue;` → FAILED
    // (`salon-2` 2, not 1).
    testWidgets('a live board member for ANOTHER salon on the same day is '
        'left alone — an owner managing several salons pays for one board, '
        'not all of them', (tester) async {
      final probe = await pumpProbe(tester);

      await watch(probe.container, board(day: affected));
      await watch(probe.container, board(day: affected, salonId: kOtherSalon));

      probe.fire(
        (WidgetRef ref) => invalidateBookingViewsAfterProviderClose(
          ref,
          'booking-1',
          affectedDate: affected,
          salonId: kSalon,
        ),
      );
      await tester.pump();

      expect(
        probe.repo.callsFor(
          salonId: kOtherSalon,
          day: affected,
          masterId: kBoardMaster,
        ),
        1,
      );
      expect(
        probe.repo.callsFor(
          salonId: kSalon,
          day: affected,
          masterId: kBoardMaster,
        ),
        2,
        reason: 'sanity: the salon under test DID drop',
      );
    });

    // ── 3. an UNAFFECTED day must survive ──────────────────────────────
    //
    // MUTATION (observed 2026-09-19): deleting
    // `if (!affectedDays.contains(liveQuery.day)) continue;` → FAILED
    // (21 Jul 2, not 1).
    testWidgets('a live board member on an UNAFFECTED day of the SAME salon '
        'is left alone — the per-day scoping is real, not decorative', (
      tester,
    ) async {
      final probe = await pumpProbe(tester);

      await watch(probe.container, board(day: affected));
      await watch(probe.container, board(day: unaffected));

      probe.fire(
        (WidgetRef ref) => invalidateBookingsDayAfterAppointmentItemReschedule(
          ref,
          affectedDays: <DateTime>{affected},
          salonId: kSalon,
        ),
      );
      await tester.pump();

      expect(
        probe.repo.callsFor(
          salonId: kSalon,
          day: unaffected,
          masterId: kBoardMaster,
        ),
        1,
      );
      expect(
        probe.repo.callsFor(
          salonId: kSalon,
          day: affected,
          masterId: kBoardMaster,
        ),
        2,
        reason: 'sanity: the affected day DID drop',
      );
    });

    // ── 4. salonId == null touches nothing ─────────────────────────────
    //
    // MUTATION (observed 2026-09-19): changing the CLOSE helper's guard to
    // `_invalidateSalonDayLists(ref, lru: lru, salonId: salonId ?? kSalon,
    // …)` (i.e. running the sweep unconditionally) → FAILED (2, not 1).
    testWidgets('a NULL salonId (the CLIENT and INDEPENDENT_MASTER mounts) '
        'touches NO salon day-list member, even with one live', (tester) async {
      final probe = await pumpProbe(tester);

      await watch(probe.container, board(day: affected));

      probe.fire(
        (WidgetRef ref) => invalidateBookingViewsAfterProviderClose(
          ref,
          'booking-1',
          affectedDate: affected,
        ),
      );
      probe.fire(
        (WidgetRef ref) => invalidateBookingsDayAfterAppointmentItemReschedule(
          ref,
          affectedDays: <DateTime>{affected},
        ),
      );
      await tester.pump();

      expect(
        probe.repo.callsFor(
          salonId: kSalon,
          day: affected,
          masterId: kBoardMaster,
        ),
        1,
      );
    });

    // ── 5. `isWatched`, NOT `contains` ─────────────────────────────────
    //
    // The two halves are asserted SYNCHRONOUSLY — before any pump — because
    // that is the only window in which the eager `ref.read` and Riverpod's own
    // queued refresh look different. Both end at "the member was dropped";
    // only the eager read refetches inside the helper itself.
    //
    // Repo trap this respects: a PAUSED-only listener still counts for
    // `isWatched` (it is backed by `ref.onAddListener`/`onRemoveListener`,
    // which fire on raw listener COUNT, never on pause/resume), so an open
    // subscription models the paused-but-watched board exactly.
    //
    // MUTATION (observed 2026-09-19): changing
    // `final bool isGenuinelyOrphaned = !lru.isWatched(liveQuery);` to
    // `= lru.contains(liveQuery);` — the tautological spelling the CREATED
    // helper was already fixed for — → the WATCHED half FAILED (2 calls
    // synchronously, not 1). Changing it to `= false` → the ORPHANED half
    // FAILED (1 call synchronously, not 2).
    testWidgets('a PINNED-but-UNWATCHED salon member is eagerly re-read, and '
        'a WATCHED one is not', (tester) async {
      final probe = await pumpProbe(tester);

      // ORPHANED: built this session, then every listener gone. The LRU's
      // keepAlive link is all that holds it — exactly the element a bare
      // invalidate can leave mid-disposal.
      final BookingsDayQuery orphaned = board(day: affected);
      final ProviderSubscription<AsyncValue<BookingsDayState>> transient = probe
          .container
          .listen(bookingsDayProvider(orphaned), (_, _) {});
      await probe.container.read(bookingsDayProvider(orphaned).future);
      transient.close();
      // Let the now-listenerless FILTERED member actually dispose: it is what
      // holds the `ref.watch` on the fetchKey member the LRU pins, so without
      // this pump the fetchKey is still WATCHED and this test would assert the
      // wrong half. (Riverpod queues the disposal; closing the subscription
      // does not run it.)
      await tester.pump();

      // WATCHED: held live for the whole test.
      final BookingsDayQuery watched = board(day: unaffected);
      await watch(probe.container, watched);

      probe.fire(
        (WidgetRef ref) => invalidateBookingsDayAfterAppointmentItemReschedule(
          ref,
          affectedDays: <DateTime>{affected, unaffected},
          salonId: kSalon,
        ),
      );

      // NO pump yet — this is the discriminating moment.
      expect(
        probe.repo.callsFor(
          salonId: kSalon,
          day: affected,
          masterId: kBoardMaster,
        ),
        2,
        reason:
            'the orphaned member must be re-read SYNCHRONOUSLY inside the '
            'helper: re-touching its keepAlive link is what cancels the '
            'disposal `invalidateSelf()` just queued against it',
      );
      expect(
        probe.repo.callsFor(
          salonId: kSalon,
          day: unaffected,
          masterId: kBoardMaster,
        ),
        1,
        reason:
            'the watched (possibly merely PAUSED) member must NOT be force-'
            'read here — Riverpod\'s own pause/resume recovery owns it, and '
            'forcing it is the tautological-`contains` bug',
      );

      // …and it is still genuinely DROPPED, just later.
      await tester.pump();
      expect(
        probe.repo.callsFor(
          salonId: kSalon,
          day: unaffected,
          masterId: kBoardMaster,
        ),
        2,
        reason: 'the watched member refetches on the ordinary flush',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // AUDIT LOW-4 (2026-09-20, user-directed) — the board's share of the
  // booking-created fan-out is DEFERRED while «Записи» is not the selected
  // tab, and REPLAYED when it becomes one.
  // ══════════════════════════════════════════════════════════════════════
  //
  // THE DEFECT. `salon_shell_screen.dart` hosts the board in a plain
  // `IndexedStack`, which sets neither `Offstage` nor `TickerMode` on its
  // non-current children, so the board's `Consumer`s stay ACTIVE while the
  // owner stands on «Салон» or «Профіль» — and every `ref.invalidate` aimed at
  // them genuinely refetched, against the backend's per-user 60/min budget,
  // with nothing on screen.
  //
  // WHAT THIS TEST MUST NOT MEASURE. The rejected fix was to pause or drop the
  // board's watch; an autoDispose provider invalidated with only PAUSED
  // listeners is DISPOSED rather than refreshed, and `invalidate` retains
  // `.value`, so a test that gated on `value == null` would sail straight
  // through that bug. So the "still alive" half below asserts on
  // `ProviderContainer.exists` and on the ELEMENT's own `AsyncValue` — never
  // on a null value.
  //
  // FIXTURE SHAPE is inherited wholesale from the group above (REUSE-FIRST):
  // the board's real live member is FILTERED (non-null `masterId` + the
  // day-list default status set), because a gate written against a naive
  // `masterId: null` literal is inert the moment the owner filters anything.
  group('audit LOW-4 — the created-booking fan-out is deferred while the '
      'board tab is not selected', () {
    const String kSalon = 'salon-1';
    const String kBoardMaster = 'master-7';

    /// «Салон» — the shell's default, and NOT the board.
    const int kSalonNavTab = 0;

    // future-date-ok: bare family key; no `isPast`/`hasStarted` predicate and
    // no wall-clock read is reachable from this group, so it cannot expire.
    final DateTime day = DateTime(2026, 7, 20);

    BookingsDayQuery board({String salonId = kSalon}) =>
        BookingsDayQuery.salonDayList(
          day: day,
          salonId: salonId,
          masterId: kBoardMaster,
        );

    Future<
      ({
        ProviderContainer container,
        _SalonCountingRepository repo,
        Map<String, int> salonDotFetches,
        void Function(void Function(WidgetRef ref)) fire,
      })
    >
    pumpProbe(WidgetTester tester, {required int navTab}) async {
      final _SalonCountingRepository repo = _SalonCountingRepository();
      final Map<String, int> salonDotFetches = <String, int>{};
      late WidgetRef captured;

      await tester.pumpApp(
        Scaffold(
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) {
              captured = ref;
              return const SizedBox(key: Key('probe'));
            },
          ),
        ),
        overrides: <Object>[
          bookingRepositoryProvider.overrideWithValue(repo),
          authProvider.overrideWith(_StubAuthNotifier.new),
          // Overridden rather than left real, for the reason stated on every
          // sibling group: the production bodies park a 30-minute keepAlive
          // `Timer` that `flutter_test` fails on at teardown. The salon one
          // COUNTS here — it is half of what "board-scoped calls" means.
          bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
          salonBookedDaysProvider.overrideWith((ref, String id) async {
            salonDotFetches[id] = (salonDotFetches[id] ?? 0) + 1;
            return <DateTime>{};
          }),
        ],
      );

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('probe'))),
        listen: false,
      );
      await container.read(authProvider.future);

      // THE VISIBILITY SIGNAL UNDER TEST — the shell's own selected nav index,
      // the same `int` its `IndexedStack` indexes on. Held live by a listener
      // because it is `autoDispose`; `select` then puts the owner on the tab
      // this run is about. NOTHING here touches the board's listeners.
      final ProviderSubscription<int> shell = container.listen(
        salonShellProvider(kSalon),
        (_, _) {},
      );
      addTearDown(shell.close);
      container.read(salonShellProvider(kSalon).notifier).select(navTab);
      expect(container.read(salonShellProvider(kSalon)), navTab);

      return (
        container: container,
        repo: repo,
        salonDotFetches: salonDotFetches,
        fire: (void Function(WidgetRef ref) run) => run(captured),
      );
    }

    /// Holds [query] live for the whole test — a watched, ACTIVE board member,
    /// exactly as the `IndexedStack`-hosted screen leaves it on every tab.
    Future<void> watch(ProviderContainer c, BookingsDayQuery query) async {
      final ProviderSubscription<AsyncValue<BookingsDayState>> sub = c.listen(
        bookingsDayProvider(query),
        (_, _) {},
      );
      addTearDown(sub.close);
      await c.read(bookingsDayProvider(query).future);
    }

    /// Holds the salon's day-dot member live too, so an invalidation of it is
    /// OBSERVABLE as a refetch rather than a silent drop.
    Future<void> watchDots(ProviderContainer c) async {
      final ProviderSubscription<AsyncValue<Set<DateTime>>> sub = c.listen(
        salonBookedDaysProvider(kSalon),
        (_, _) {},
      );
      addTearDown(sub.close);
      await c.read(salonBookedDaysProvider(kSalon).future);
    }

    // MUTATION LOG (observed 2026-09-20, against the pre-fix tree restored by
    // `cp` from a backup — never `git checkout`): with
    // `invalidateBookingViewsAfterBookingCreated` reverted to its
    // unconditional form, THIS test FAILED on both counts (2 day-list fetches
    // and 2 dot fetches, expected 1 and 1). The two tests below it stayed
    // green, which is exactly right: they pin the behaviour the fix must NOT
    // change.
    testWidgets('a create while «Салон» is selected issues ZERO board-scoped '
        'calls — neither the board\'s day list nor its day dots refetch', (
      tester,
    ) async {
      final probe = await pumpProbe(tester, navTab: kSalonNavTab);
      await watch(probe.container, board());
      await watchDots(probe.container);
      expect(
        probe.repo.callsFor(salonId: kSalon, day: day, masterId: kBoardMaster),
        1,
        reason:
            'sanity: one fetch for the live board member before the '
            'fan-out',
      );
      expect(probe.salonDotFetches[kSalon], 1, reason: 'sanity');

      probe.container.read(_createdFanOutProvider)(kSalon);
      await tester.pump();
      await tester.pump();

      expect(
        probe.repo.callsFor(salonId: kSalon, day: day, masterId: kBoardMaster),
        1,
        reason:
            'THE FIX: the board is not the selected tab, so its day list must '
            'not be re-fetched at all — not eagerly, and not on the flush',
      );
      expect(
        probe.salonDotFetches[kSalon],
        1,
        reason:
            'the salon day-dot member is board-scoped too and is deferred '
            'with it',
      );
    });

    testWidgets('…and the board provider is STILL ALIVE afterwards — the '
        'deferral changes no listener state', (tester) async {
      final probe = await pumpProbe(tester, navTab: kSalonNavTab);
      await watch(probe.container, board());
      await watchDots(probe.container);
      final BookingsDayState before = probe.container
          .read(bookingsDayProvider(board()))
          .requireValue;

      probe.container.read(_createdFanOutProvider)(kSalon);
      await tester.pump();
      await tester.pump();

      // NOT `value == null` — `invalidate` retains `.value`, so that predicate
      // is satisfied by the dispose bug it is supposed to catch. These three
      // are the honest questions: does an ELEMENT still exist, is it in a
      // settled data state, and is it the same data.
      expect(
        probe.container.exists(bookingsDayProvider(board())),
        isTrue,
        reason:
            'the board element must survive an off-screen create — the whole '
            'reason the rejected pause/`visible:` shape was not used',
      );
      final AsyncValue<BookingsDayState> after = probe.container.read(
        bookingsDayProvider(board()),
      );
      expect(after, isA<AsyncData<BookingsDayState>>());
      expect(after.requireValue, same(before));
      expect(
        probe.container.exists(salonBookedDaysProvider(kSalon)),
        isTrue,
        reason: 'and so must its day-dot member',
      );
    });

    testWidgets('a create while «Записи» IS selected refetches exactly as it '
        'does today — the visible path is untouched', (tester) async {
      final probe = await pumpProbe(tester, navTab: kSalonBookingsNavTab);
      await watch(probe.container, board());
      await watchDots(probe.container);

      probe.container.read(_createdFanOutProvider)(kSalon);
      await tester.pump();
      await tester.pump();

      expect(
        probe.repo.callsFor(salonId: kSalon, day: day, masterId: kBoardMaster),
        2,
        reason:
            'no behaviour change on the visible path — the owner is standing '
            'on the board and must see the booking they just made',
      );
      expect(probe.salonDotFetches[kSalon], 2);
      expect(
        probe.container.read(salonBoardRefreshGateProvider).isStale(kSalon),
        isFalse,
        reason: 'nothing was deferred, so nothing is owed',
      );
    });

    testWidgets('the deferred refresh is REPLAYED when «Записи» becomes the '
        'selected tab — postponed, never dropped', (tester) async {
      final probe = await pumpProbe(tester, navTab: kSalonNavTab);
      await watch(probe.container, board());
      await watchDots(probe.container);

      probe.container.read(_createdFanOutProvider)(kSalon);
      await tester.pump();
      expect(
        probe.container.read(salonBoardRefreshGateProvider).isStale(kSalon),
        isTrue,
        reason: 'the skipped fan-out records what it owes',
      );

      // What `SalonShellScreen._onNavSelected` does on a «Записи» tap.
      probe.container
          .read(salonShellProvider(kSalon).notifier)
          .select(kSalonBookingsNavTab);
      probe.fire((WidgetRef ref) => drainSalonBoardRefresh(ref, kSalon));
      await tester.pump();
      await tester.pump();

      expect(
        probe.repo.callsFor(salonId: kSalon, day: day, masterId: kBoardMaster),
        2,
        reason:
            'the board refetches on RETURN — the deferral must not cost the '
            'owner a stale board, only a later refresh',
      );
      expect(probe.salonDotFetches[kSalon], 2);
      expect(
        probe.container.read(salonBoardRefreshGateProvider).isStale(kSalon),
        isFalse,
        reason: 'takeStale clears as it reads, so a second tap replays nothing',
      );

      // A second drain is a genuine no-op, not a second refetch.
      probe.fire((WidgetRef ref) => drainSalonBoardRefresh(ref, kSalon));
      await tester.pump();
      expect(
        probe.repo.callsFor(salonId: kSalon, day: day, masterId: kBoardMaster),
        2,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // Phase 382 (24.1e) — the OWNER-AS-MASTER scope keys.
  // ══════════════════════════════════════════════════════════════════════
  //
  // Phase 382 added two cache scopes the four fan-out helpers in
  // `booking_calendar_invalidation.dart` were written before:
  //   • `bookingsDayProvider(BookingsDayQuery.dayList/of(day:, asOwnerMaster:
  //     true))` — the owner's OWN master-row day list (a distinct family key);
  //   • `ownerMasterBookedDaysProvider` — the owner's OWN rail-dot set (a
  //     separate keepAlive singleton with the same 30-minute TTL).
  // The three per-date helpers hand-build ONLY the flag-false keys and every
  // helper drops ONLY `bookedDaysProvider`, so once phase 383 mounts owner
  // master mode a decline / close / reschedule / create leaves that mode
  // serving the stale (e.g. cancelled-as-CONFIRMED) booking and stale dots.
  //
  // QA FINDING (phase 382 audit, MEDIUM perf + LOW security): these were
  // FAILING-FIRST regressions (observed RED before the fix, GREEN after) —
  // the fix routes the three hand-built sites through `_masterOwnDayKeys`
  // (both scopes) and drops `ownerMasterBookedDaysProvider` beside every
  // `bookedDaysProvider`. The created-helper day-key test pins the half that
  // already worked (it enumerates `DayKeepAliveLru.liveQueries`).
  //
  // Same technique as every group above: refetch COUNT with a LIVE
  // subscription held (Riverpod drops an unwatched invalidated provider, and a
  // seamless reload retains `.value`, so neither "no listener" nor a value
  // assertion could ever fail).
  group('phase 382 — owner-master scope keys are dropped by every '
      'fan-out helper', () {
    // future-date-ok: an arbitrary calendar-day family key; never read
    // through BookingDisplayX.isPast — these tests only count refetches.
    final DateTime affected = DateTime(2026, 7, 20);

    final Map<String, void Function(WidgetRef ref)> perDateHelpers =
        <String, void Function(WidgetRef ref)>{
          'invalidateBookingViewsAfterExternalDecline': (WidgetRef ref) =>
              invalidateBookingViewsAfterExternalDecline(
                ref,
                const <String>['booking-1'],
                affectedDates: <DateTime>[affected],
              ),
          'invalidateBookingViewsAfterProviderClose': (WidgetRef ref) =>
              invalidateBookingViewsAfterProviderClose(
                ref,
                'booking-1',
                affectedDate: affected,
              ),
          'invalidateBookingsDayAfterAppointmentItemReschedule':
              (WidgetRef ref) =>
                  invalidateBookingsDayAfterAppointmentItemReschedule(
                    ref,
                    affectedDays: <DateTime>{affected},
                  ),
        };

    Future<ProviderContainer> pumpProbe(
      WidgetTester tester,
      void Function(WidgetRef ref) fire,
      List<Object> overrides,
    ) async {
      await tester.pumpApp(
        Scaffold(
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) => TextButton(
              key: const Key('fire'),
              onPressed: () => fire(ref),
              child: const Text('fire'),
            ),
          ),
        ),
        overrides: overrides,
      );
      return ProviderScope.containerOf(
        tester.element(find.byKey(const Key('fire'))),
        listen: false,
      );
    }

    for (final MapEntry<String, void Function(WidgetRef ref)> helper
        in perDateHelpers.entries) {
      testWidgets('${helper.key} drops ownerMasterBookedDaysProvider — the '
          "owner master mode's rail dots", (tester) async {
        int ownerDotFetches = 0;
        final ProviderContainer container = await pumpProbe(
          tester,
          helper.value,
          <Object>[
            // Both overridden: the production bodies park a 30-minute
            // keepAlive `Timer` flutter_test fails on at teardown.
            bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
            ownerMasterBookedDaysProvider.overrideWith((ref) async {
              ownerDotFetches++;
              return <DateTime>{};
            }),
            nextAppointmentProvider.overrideWith((ref) async => null),
          ],
        );
        final ProviderSubscription<AsyncValue<Set<DateTime>>> sub = container
            .listen(ownerMasterBookedDaysProvider, (_, _) {});
        addTearDown(sub.close);
        await container.read(ownerMasterBookedDaysProvider.future);
        expect(ownerDotFetches, 1, reason: 'sanity: one fetch before the tap');

        await tester.tap(find.byKey(const Key('fire')));
        await tester.pumpAndSettle();
        await container.read(ownerMasterBookedDaysProvider.future);

        expect(
          ownerDotFetches,
          2,
          reason:
              '${helper.key} must drop the owner-as-master dot singleton — '
              'it is keepAlive (30-min TTL) and nothing else reaches it',
        );
      });

      testWidgets('${helper.key} refetches the asOwnerMaster: true DEFAULT '
          'day-list member the owner master mode watches', (tester) async {
        final _CountingBookingRepository repo = _CountingBookingRepository();
        final ProviderContainer container =
            await pumpProbe(tester, helper.value, <Object>[
              bookingRepositoryProvider.overrideWithValue(repo),
              authProvider.overrideWith(_StubAuthNotifier.new),
              bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
              ownerMasterBookedDaysProvider.overrideWith(
                (ref) async => <DateTime>{},
              ),
              nextAppointmentProvider.overrideWith((ref) async => null),
            ]);
        await container.read(authProvider.future);

        final BookingsDayQuery ownQuery = BookingsDayQuery.dayList(
          day: affected,
          asOwnerMaster: true,
        );
        expect(
          ownQuery,
          isNot(BookingsDayQuery.dayList(day: affected)),
          reason:
              'the owner-master member must be a DISTINCT family key, or '
              'this test silently re-tests the flag-false member',
        );
        final ProviderSubscription<AsyncValue<BookingsDayState>> sub = container
            .listen(bookingsDayProvider(ownQuery), (_, _) {});
        addTearDown(sub.close);
        await container.read(bookingsDayProvider(ownQuery).future);
        expect(
          repo.callsWithStatusesAndScope(
            BookingStatus.visibleInDayListByDefault,
            asMaster: true,
          ),
          1,
          reason: 'sanity: the owner-master member fetched once before the tap',
        );

        await tester.tap(find.byKey(const Key('fire')));
        await tester.pumpAndSettle();
        await container.read(bookingsDayProvider(ownQuery).future);

        expect(
          repo.callsWithStatusesAndScope(
            BookingStatus.visibleInDayListByDefault,
            asMaster: true,
          ),
          2,
          reason:
              '${helper.key} hand-builds only the flag-false keys — the '
              'owner-master day keeps serving the closed booking as CONFIRMED',
        );
      });
    }

    // Runs the literal created-booking helper (takes `Ref`, not `WidgetRef`)
    // via `_createdFanOutProvider`, as the KEYED group above does.
    ProviderContainer createdContainer(List<Object> overrides) {
      final ProviderContainer container = ProviderContainer(
        overrides: overrides.cast(),
      );
      addTearDown(container.dispose);
      return container;
    }

    test('invalidateBookingViewsAfterBookingCreated drops '
        'ownerMasterBookedDaysProvider', () async {
      int ownerDotFetches = 0;
      final ProviderContainer container = createdContainer(<Object>[
        bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
        ownerMasterBookedDaysProvider.overrideWith((ref) async {
          ownerDotFetches++;
          return <DateTime>{};
        }),
      ]);
      final ProviderSubscription<AsyncValue<Set<DateTime>>> sub = container
          .listen(ownerMasterBookedDaysProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(ownerMasterBookedDaysProvider.future);
      expect(ownerDotFetches, 1, reason: 'sanity: one fetch before fan-out');

      container.read(_createdFanOutProvider)(null);
      await container.read(ownerMasterBookedDaysProvider.future);

      expect(
        ownerDotFetches,
        2,
        reason:
            'a booking the owner creates for themselves must put a dot on '
            'their own master-mode rail',
      );
    });

    // GREEN today — pins the half that already works. The created helper
    // enumerates `DayKeepAliveLru.liveQueries` instead of hand-building keys,
    // so the flag-true member is reached for free. A refactor back to
    // hand-built `dayList/of(day:)` keys (the shape of the three siblings)
    // must turn this red.
    test(
      'invalidateBookingViewsAfterBookingCreated refetches the live '
      'asOwnerMaster: true day member (LRU enumeration reaches it)',
      () async {
        final _CountingBookingRepository repo = _CountingBookingRepository();
        final ProviderContainer container = createdContainer(<Object>[
          bookingRepositoryProvider.overrideWithValue(repo),
          authProvider.overrideWith(_StubAuthNotifier.new),
          bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
          ownerMasterBookedDaysProvider.overrideWith(
            (ref) async => <DateTime>{},
          ),
        ]);
        await container.read(authProvider.future);

        final BookingsDayQuery ownQuery = BookingsDayQuery.dayList(
          day: affected,
          asOwnerMaster: true,
        );
        final ProviderSubscription<AsyncValue<BookingsDayState>> sub = container
            .listen(bookingsDayProvider(ownQuery), (_, _) {});
        addTearDown(sub.close);
        await container.read(bookingsDayProvider(ownQuery).future);
        expect(
          repo.callsWithStatusesAndScope(
            BookingStatus.visibleInDayListByDefault,
            asMaster: true,
          ),
          1,
          reason: 'sanity: one fetch before the fan-out',
        );

        container.read(_createdFanOutProvider)(null);
        await container.read(bookingsDayProvider(ownQuery).future);

        expect(
          repo.callsWithStatusesAndScope(
            BookingStatus.visibleInDayListByDefault,
            asMaster: true,
          ),
          2,
          reason:
              'the owner-master day member is live in the LRU, so the created '
              'fan-out must refetch it',
        );
      },
    );
  });
}
