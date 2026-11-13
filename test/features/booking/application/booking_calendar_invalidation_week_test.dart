// Phase 480 — booking_calendar_invalidation.dart's week twin: each fan-out
// that invalidates a live `bookingsDayProvider(day)` also invalidates the
// LIVE `bookingsWeekProvider` member covering that day — and nothing else
// (not a live week elsewhere, not a live day elsewhere in the same week).
//
// Asserted by refetch COUNT per (from, to) range, never by value:
// `ref.invalidate` reloads seamlessly and retains the previous `.value`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_calendar_invalidation.dart';
import 'package:beautica_mobile/features/booking/application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/booking/application/bookings_week_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_week_query.dart';

import '../../../helpers/pump_app.dart';

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

/// Counts `getMyBookings` calls per `(from, to)` range.
class _RangeCountingRepository implements BookingRepository {
  final Map<(DateTime?, DateTime?), int> calls =
      <(DateTime?, DateTime?), int>{};

  int callsFor(DateTime from, DateTime to) => calls[(from, to)] ?? 0;

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
    calls.update((from, to), (int n) => n + 1, ifAbsent: () => 1);
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

/// Test-only seam giving the `Ref`-taking create fan-out a caller.
final Provider<void Function()> _createdFanOutProvider =
    Provider<void Function()>(
      (Ref ref) =>
          () => invalidateBookingViewsAfterBookingCreated(ref),
    );

/// Test-only seam giving the `Ref`-taking bulk-cancel fan-out a caller.
final Provider<void Function()> _bulkCancelFanOutProvider =
    Provider<void Function()>(
      (Ref ref) =>
          () => invalidateBookingViewsAfterBulkCancel(ref),
    );

// All fixture dates are in the past and only key family members / ranges —
// never read through `BookingDisplayX.isPast`.
final DateTime _wed = DateTime(2026, 7, 22); // the affected day
final DateTime _thu = DateTime(2026, 7, 23); // same week, not affected
final DateTime _mon = DateTime(2026, 7, 20);
final DateTime _sun = DateTime(2026, 7, 26);
final DateTime _nextMon = DateTime(2026, 7, 27);
final DateTime _nextSun = DateTime(2026, 8, 2);

void main() {
  late _RangeCountingRepository repo;

  /// Pumps a button running [action] with a `WidgetRef`, then builds and
  /// WATCHES: the affected day, another day of the same week, the affected
  /// week, and the following week.
  Future<ProviderContainer> arrange(
    WidgetTester tester,
    void Function(WidgetRef ref) action,
  ) async {
    repo = _RangeCountingRepository();
    await tester.pumpApp(
      Scaffold(
        body: Consumer(
          builder: (BuildContext context, WidgetRef ref, _) => TextButton(
            key: const Key('act'),
            onPressed: () => action(ref),
            child: const Text('act'),
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
      tester.element(find.byKey(const Key('act'))),
      listen: false,
    );
    await container.read(authProvider.future);

    for (final DateTime day in <DateTime>[_wed, _thu]) {
      final BookingsDayQuery q = BookingsDayQuery.dayList(day: day);
      final ProviderSubscription<Object?> sub = container.listen(
        bookingsDayProvider(q),
        (_, _) {},
      );
      addTearDown(sub.close);
      await container.read(bookingsDayProvider(q).future);
    }
    for (final DateTime day in <DateTime>[_wed, _nextMon]) {
      final BookingsWeekQuery q = BookingsWeekQuery.of(day: day);
      final ProviderSubscription<Object?> sub = container.listen(
        bookingsWeekProvider(q),
        (_, _) {},
      );
      addTearDown(sub.close);
      await container.read(bookingsWeekProvider(q).future);
    }
    // Sanity: one initial fetch each.
    expect(repo.callsFor(_wed, _wed), 1);
    expect(repo.callsFor(_thu, _thu), 1);
    expect(repo.callsFor(_mon, _sun), 1);
    expect(repo.callsFor(_nextMon, _nextSun), 1);
    return container;
  }

  Future<void> act(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('act')));
    await tester.pumpAndSettle();
  }

  void expectAffectedDayAndWeekOnly() {
    expect(repo.callsFor(_wed, _wed), 2, reason: 'affected day refetched');
    expect(repo.callsFor(_mon, _sun), 2, reason: 'covering week refetched');
    expect(repo.callsFor(_thu, _thu), 1, reason: 'other day untouched');
    expect(
      repo.callsFor(_nextMon, _nextSun),
      1,
      reason: 'other live week untouched',
    );
  }

  testWidgets('COMPLETE (provider close) on a day → that day + its week, '
      'nothing else', (tester) async {
    await arrange(
      tester,
      (WidgetRef ref) => invalidateBookingViewsAfterProviderClose(
        ref,
        'booking-1',
        affectedDate: _wed,
      ),
    );
    await act(tester);
    expectAffectedDayAndWeekOnly();
  });

  testWidgets('CANCEL (external decline) on a day → that day + its week, '
      'nothing else', (tester) async {
    await arrange(
      tester,
      (WidgetRef ref) => invalidateBookingViewsAfterExternalDecline(
        ref,
        const <String>['booking-1'],
        affectedDates: <DateTime>[_wed],
      ),
    );
    await act(tester);
    expectAffectedDayAndWeekOnly();
  });

  testWidgets('reschedule touching two days of ONE week refetches that week '
      'once', (tester) async {
    await arrange(
      tester,
      (WidgetRef ref) => invalidateBookingsDayAfterAppointmentItemReschedule(
        ref,
        affectedDays: <DateTime>{_wed, _thu},
      ),
    );
    await act(tester);
    expect(repo.callsFor(_mon, _sun), 2);
    expect(repo.callsFor(_nextMon, _nextSun), 1);
  });

  testWidgets('CREATE (day unknown) → every LIVE day and week member, and no '
      'week that was never built', (tester) async {
    final ProviderContainer container = await arrange(tester, (_) {});
    container.read(_createdFanOutProvider)();
    await tester.pumpAndSettle();

    expect(repo.callsFor(_wed, _wed), 2);
    expect(repo.callsFor(_thu, _thu), 2);
    expect(repo.callsFor(_mon, _sun), 2);
    expect(repo.callsFor(_nextMon, _nextSun), 2);
    // A week nobody built this session is never fetched by the fan-out.
    expect(repo.callsFor(DateTime(2026, 7, 13), DateTime(2026, 7, 19)), 0);
  });

  testWidgets('a pinned-but-UNWATCHED covering week is dropped with NO '
      'immediate request and refetches on its next visit', (tester) async {
    final ProviderContainer container = await arrange(
      tester,
      (WidgetRef ref) => invalidateBookingsWeekCovering(ref, <DateTime>[
        DateTime(2026, 7, 15),
      ]),
    );
    // Build a third week and drop its only listener — pinned by the LRU only.
    final BookingsWeekQuery prev = BookingsWeekQuery.of(
      day: DateTime(2026, 7, 15),
    );
    final ProviderSubscription<Object?> sub = container.listen(
      bookingsWeekProvider(prev),
      (_, _) {},
    );
    await container.read(bookingsWeekProvider(prev).future);
    sub.close();
    await tester.pump();
    expect(container.read(weekKeepAliveLruProvider).isWatched(prev), isFalse);

    await act(tester);

    expect(
      repo.callsFor(DateTime(2026, 7, 13), DateTime(2026, 7, 19)),
      1,
      reason: 'unwatched covering week must NOT be fetched by the invalidate',
    );
    expect(repo.callsFor(_mon, _sun), 1);
    expect(repo.callsFor(_nextMon, _nextSun), 1);

    // Not served stale: the next visit fetches fresh data.
    final ProviderSubscription<Object?> revisit = container.listen(
      bookingsWeekProvider(prev),
      (_, _) {},
    );
    addTearDown(revisit.close);
    await container.read(bookingsWeekProvider(prev).future);
    expect(
      repo.callsFor(DateTime(2026, 7, 13), DateTime(2026, 7, 19)),
      2,
      reason: 'the dropped week refetches on its next visit',
    );
  });

  // Phase 480 perf fix — create/bulk-cancel no longer eager-read pinned-but-
  // UNWATCHED weeks. A day-unknown fan-out hitting all ≤ 3 cached weeks must
  // not fire a network request for a week nobody is looking at; it only
  // drops it, and the next visit refetches.
  final DateTime prevMon = DateTime(2026, 7, 13);
  final DateTime prevSun = DateTime(2026, 7, 19);

  for (final (String name, Provider<void Function()> fanOut)
      in <(String, Provider<void Function()>)>[
        ('CREATE', _createdFanOutProvider),
        ('BULK CANCEL', _bulkCancelFanOutProvider),
      ]) {
    testWidgets(
      '$name → a watched week refetches; a cached UNWATCHED week is dropped with NO '
      'immediate request and refetches on its next visit',
      (tester) async {
        final ProviderContainer container = await arrange(tester, (_) {});
        final BookingsWeekQuery prev = BookingsWeekQuery.of(day: prevMon);
        final ProviderSubscription<Object?> sub = container.listen(
          bookingsWeekProvider(prev),
          (_, _) {},
        );
        await container.read(bookingsWeekProvider(prev).future);
        sub.close();
        await tester.pump();
        expect(
          container.read(weekKeepAliveLruProvider).isWatched(prev),
          isFalse,
        );
        expect(repo.callsFor(prevMon, prevSun), 1);

        container.read(fanOut)();
        await tester.pumpAndSettle();

        expect(repo.callsFor(_mon, _sun), 2, reason: 'watched week refetched');
        expect(
          repo.callsFor(_nextMon, _nextSun),
          2,
          reason: 'watched week refetched',
        );
        expect(
          repo.callsFor(prevMon, prevSun),
          1,
          reason: 'unwatched cached week must NOT be fetched by the fan-out',
        );

        // Not served stale: the next visit fetches fresh data.
        final ProviderSubscription<Object?> revisit = container.listen(
          bookingsWeekProvider(prev),
          (_, _) {},
        );
        addTearDown(revisit.close);
        await container.read(bookingsWeekProvider(prev).future);
        expect(
          repo.callsFor(prevMon, prevSun),
          2,
          reason: 'the dropped week refetches on its next visit',
        );
      },
    );
  }
}
