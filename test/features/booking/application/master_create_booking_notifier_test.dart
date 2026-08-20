// Phase 246 — unit suite for [MasterCreateBookingNotifier] (the master
// «Новий запис» wizard's submit-state notifier).
//
// Mirrors `master_archive_notifier_test.dart`'s isolation discipline: a
// fresh [ProviderContainer] per test with a mocktail-backed [BookingRepository]
// override, disposed via addTearDown, and `retry: beauticaProviderRetry` (the
// real app-wide retry predicate) rather than Riverpod's own default backoff.
//
// This suite pins:
//   * double-submit is a NO-OP while the first call is still in flight —
//     asserted by mocktail CALL COUNT (`.called(1)`), not merely "no
//     exception was thrown" (a locked test-quality requirement — see the
//     phase doc's Test Cases section).
//   * success invalidates `bookingsDayProvider` — proven by observing a REAL
//     second fetch on an already-live family member, not by inspecting
//     private notifier state.
//   * the mapped [Failure] surfaces on [AsyncError] via an ASYNC throw
//     (`thenAnswer((_) async => throw ...)`), never a sync `thenThrow` — the
//     locked "sync thenThrow can defang an assertion" gotcha this repo's
//     other suites already avoid.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/booking/application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/booking/application/master_create_booking_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_state.dart';
import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

/// A minimal enriched [Booking] fixture — [MasterCreateBookingNotifier]
/// never reads any field off the result (submit state is `void`), so only
/// the shape needs to satisfy the return type.
Booking _bookingFixture() => Booking(
  id: 'booking-1',
  masterId: 'master-1',
  masterFirstName: 'Марія',
  masterLastName: 'Іванюк',
  masterAvatarUrl: null,
  masterType: 'INDEPENDENT_MASTER',
  salonName: null,
  serviceId: 'service-1',
  serviceName: 'Манікюр',
  categoryName: 'Манікюр',
  cityLabel: 'Львів',
  districtLabel: null,
  street: null,
  buildingNo: null,
  durationMinutes: 60,
  price: 500,
  startAt: DateTime.utc(2000, 1, 1, 11),
  endAt: DateTime.utc(2000, 1, 1, 12),
  status: BookingStatus.confirmed,
  canReview: false,
  providerCanReviewClient: false,
  clientComment: null,
  providerComment: null,
  clientCancellationNote: null,
  masterProfessionalTitle: null,
  locationNote: null,
  awaitingClosure: false,
);

final CreateMasterBookingRequest _request = CreateMasterBookingRequest(
  masterServiceId: 'service-1',
  startsAt: DateTime.utc(2000, 1, 1, 11),
  guest: const WalkInGuest(
    name: 'Іван',
    surname: 'Петренко',
    phone: '+380501234567',
  ),
);

final BookingsDayQuery _dayQuery = BookingsDayQuery.of(
  day: DateTime.utc(2000, 1, 1),
);

PageResponse<Booking> _emptyDayPage() => const PageResponse<Booking>(
  items: <Booking>[],
  page: 0,
  totalPages: 1,
  totalElements: 0,
);

/// Stubs [repo.getMyBookings] (what [BookingsDayNotifier.build] calls) so a
/// live `bookingsDayProvider(_dayQuery)` member can build without throwing —
/// mirrors `bookings_day_rebuild_isolation_test.dart`'s setup. Returns a
/// fresh empty page every call so a SECOND call (the post-invalidate
/// refetch) is just as well-formed as the first.
void _stubDayFetch(_MockBookingRepository repo) {
  when(
    () => repo.getMyBookings(
      statuses: any(named: 'statuses'),
      page: any(named: 'page'),
      size: any(named: 'size'),
      sort: any(named: 'sort'),
      serviceIds: any(named: 'serviceIds'),
      from: any(named: 'from'),
      to: any(named: 'to'),
      partition: any(named: 'partition'),
      cancelToken: any(named: 'cancelToken'),
    ),
  ).thenAnswer((_) async => _emptyDayPage());
}

ProviderContainer _container(_MockBookingRepository repo) {
  final ProviderContainer c = ProviderContainer(
    retry: beauticaProviderRetry,
    // ignore: avoid_dynamic_calls
    overrides: <Object>[
      bookingRepositoryProvider.overrideWithValue(repo),
    ].cast(),
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUpAll(() {
    registerFallbackValue(<BookingStatus>{});
    registerFallbackValue(_request);
  });

  late _MockBookingRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = _MockBookingRepository();
    container = _container(repo);
  });

  // The OTHER half of `invalidateBookingViewsAfterBookingCreated`'s fan-out
  // (2026-08-20). `bookedDaysProvider` is a filter-independent `keepAlive()`
  // SINGLETON with a THIRTY-MINUTE TTL, so it is not a member of the
  // `bookingsDayProvider` family the test below covers and nothing else drops
  // it. Without this invalidation the day the master had just booked carried
  // no rail/month dot for up to half an hour — a brand-new booking on a day
  // that had none is precisely a change to a booking's EXISTENCE, which is the
  // condition `booked_days_notifier.dart`'s header names as requiring an
  // explicit invalidation.
  //
  // Asserted by REFETCH COUNT: `ref.invalidate` reloads seamlessly and retains
  // the previous `.value`, so no value-shape assertion could ever fail here.
  test('submit(): a successful create also invalidates bookedDaysProvider — '
      'the rail/month dot for the newly-booked day', () async {
    _stubDayFetch(repo);
    when(
      () => repo.createMasterBooking(any(), any()),
    ).thenAnswer((_) async => _bookingFixture());

    int bookedDaysFetches = 0;
    final ProviderContainer c = ProviderContainer(
      retry: beauticaProviderRetry,
      // ignore: avoid_dynamic_calls
      overrides: <Object>[
        bookingRepositoryProvider.overrideWithValue(repo),
        // Overridden rather than real: the production provider parks its own
        // 30-minute keepAlive `Timer`, and a counting closure is the only way
        // to observe a seamless invalidate at all.
        bookedDaysProvider.overrideWith((ref) async {
          bookedDaysFetches++;
          return <DateTime>{};
        }),
      ].cast(),
    );
    addTearDown(c.dispose);

    // A LIVE subscription — invalidating a provider with no active listener
    // DROPS it instead of refetching, which would make this unobservable.
    final ProviderSubscription<AsyncValue<Set<DateTime>>> sub = c.listen(
      bookedDaysProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    await c.read(bookedDaysProvider.future);
    expect(bookedDaysFetches, 1, reason: 'sanity: one fetch for the watcher');

    await c.read(masterCreateBookingProvider.future);
    await c
        .read(masterCreateBookingProvider.notifier)
        .submit(masterId: 'master-1', request: _request);

    await c.read(bookedDaysProvider.future);
    expect(
      bookedDaysFetches,
      2,
      reason:
          'the dot set must be dropped alongside the day list — it is a '
          '30-minute-TTL singleton that nothing else here invalidates',
    );
  });

  test('submit(): happy path calls createMasterBooking with the exact args, '
      'ends AsyncData, and invalidates bookingsDayProvider (a second live '
      'fetch actually happens)', () async {
    _stubDayFetch(repo);
    when(
      () => repo.createMasterBooking(any(), any()),
    ).thenAnswer((_) async => _bookingFixture());

    // Instantiate + subscribe to a LIVE bookingsDayProvider member BEFORE
    // submit — invalidating a family with no active listener is a
    // documented no-op (see `booking_calendar_invalidation.dart`'s header),
    // so this is what makes the second fetch observable at all.
    final List<AsyncValue<BookingsDayState>> emissions =
        <AsyncValue<BookingsDayState>>[];
    container.listen<AsyncValue<BookingsDayState>>(
      bookingsDayProvider(_dayQuery),
      (_, AsyncValue<BookingsDayState> next) => emissions.add(next),
      fireImmediately: true,
    );
    await container.read(bookingsDayProvider(_dayQuery).future);

    // Let the notifier's own idle `build()` settle first — otherwise its
    // still-pending initial AsyncLoading trips the `state.isLoading`
    // double-submit guard on this very first call.
    await container.read(masterCreateBookingProvider.future);

    await container
        .read(masterCreateBookingProvider.notifier)
        .submit(masterId: 'master-1', request: _request);

    final AsyncValue<void> state = container.read(masterCreateBookingProvider);
    expect(state.hasError, isFalse);
    expect(state.isLoading, isFalse);
    expect(state, isA<AsyncData<void>>());

    verify(() => repo.createMasterBooking('master-1', _request)).called(1);

    // The invalidated member rebuilds and re-fetches — a second
    // getMyBookings call, and a fresh AsyncLoading→AsyncData cycle on the
    // already-live listener.
    await container.read(bookingsDayProvider(_dayQuery).future);
    verify(
      () => repo.getMyBookings(
        statuses: any(named: 'statuses'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
        serviceIds: any(named: 'serviceIds'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        partition: any(named: 'partition'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).called(2);
    expect(
      emissions.any((AsyncValue<BookingsDayState> e) => e.isLoading),
      isTrue,
      reason:
          'the invalidated member must have gone through a fresh '
          'AsyncLoading — proof this was a REAL rebuild, not the retained '
          'previous value read again',
    );
  });

  test(
    'submit(): a second call while the first is still in flight is a NO-OP '
    '— the repository is called exactly ONCE, not merely "no exception"',
    () async {
      final completer = Completer<Booking>();
      when(
        () => repo.createMasterBooking(any(), any()),
      ).thenAnswer((_) => completer.future);

      // Let the notifier's own idle `build()` settle first — see the happy-
      // path test's identical note.
      await container.read(masterCreateBookingProvider.future);
      final notifier = container.read(masterCreateBookingProvider.notifier);

      // Fire both without awaiting the first — the guard must trip
      // SYNCHRONOUSLY (state is written to AsyncLoading before any `await`),
      // so the second call sees it immediately, before the event loop gets a
      // chance to interleave anything else.
      final Future<void> first = notifier.submit(
        masterId: 'master-1',
        request: _request,
      );
      final Future<void> second = notifier.submit(
        masterId: 'master-1',
        request: _request,
      );

      completer.complete(_bookingFixture());
      await first;
      await second;

      verify(() => repo.createMasterBooking(any(), any())).called(1);
    },
  );

  test(
    'submit(): a mapped Failure surfaces as AsyncError — stubbed with an '
    'ASYNC throw (thenAnswer(() async => throw ...)), never a sync '
    'thenThrow (locked gotcha: a sync throw can defang the assertion)',
    () async {
      when(() => repo.createMasterBooking(any(), any())).thenAnswer((_) async {
        throw const MasterBookingNotPermittedFailure();
      });

      // Let the notifier's own idle `build()` settle first — see the happy-
      // path test's identical note.
      await container.read(masterCreateBookingProvider.future);
      await container
          .read(masterCreateBookingProvider.notifier)
          .submit(masterId: 'master-1', request: _request);

      final AsyncValue<void> state = container.read(
        masterCreateBookingProvider,
      );
      expect(state.hasError, isTrue);
      expect(state.error, isA<MasterBookingNotPermittedFailure>());
    },
  );
}
