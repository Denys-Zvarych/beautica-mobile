// QA (track 14.x booking) — unit suite for [MyBookingsNotifier].
//
// The notifier fans one paginated `GET /bookings/me` fetch out per status a
// tab covers (Минулі = COMPLETED + NOT_COMPLETED; Скасовані = CANCELLED +
// DECLINED), then merges + re-sorts the accumulated set. The merge/sort/
// pagination logic is only exercised INDIRECTLY by the screen test, so this
// suite pins it directly: correct fan-out per tab, correct sort direction per
// tab, load-more append + cursor advance + guards, and a load-more failure
// that must NOT blow away the already-rendered list.
//
// Isolation: a fresh [ProviderContainer] per test with a mocktail-backed
// [BookingRepository] override; disposed via addTearDown.

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/booking/application/my_bookings_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_tab.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

Booking _booking({
  required String id,
  required BookingStatus status,
  required DateTime startAt,
}) => Booking(
  id: id,
  masterId: 'm-$id',
  masterFirstName: 'Марія',
  masterLastName: 'Іванюк',
  masterAvatarUrl: null,
  masterType: 'INDEPENDENT_MASTER',
  salonName: null,
  serviceId: 's-$id',
  serviceName: 'Манікюр',
  categoryName: 'Манікюр',
  cityLabel: 'Львів',
  districtLabel: null,
  street: null,
  buildingNo: null,
  durationMinutes: 60,
  price: 500,
  startAt: startAt,
  endAt: startAt.add(const Duration(hours: 1)),
  status: status,
  canReview: false,
  clientComment: null,
  providerComment: null,
  clientCancellationNote: null,
  masterProfessionalTitle: null,
  locationNote: null,
);

PageResponse<Booking> _page(
  List<Booking> items, {
  int page = 0,
  int totalPages = 1,
}) => PageResponse<Booking>(
  items: items,
  page: page,
  totalPages: totalPages,
  totalElements: items.length,
);

ProviderContainer _container(_MockBookingRepository repo) {
  final ProviderContainer c = ProviderContainer(
    // ignore: avoid_dynamic_calls
    overrides: <Object>[
      bookingRepositoryProvider.overrideWithValue(repo),
    ].cast(),
  );
  addTearDown(c.dispose);
  return c;
}

/// Stubs every status with an empty page except those named in [byStatus].
void _stubAll(
  _MockBookingRepository repo, {
  Map<BookingStatus, PageResponse<Booking>> byStatus =
      const <BookingStatus, PageResponse<Booking>>{},
}) {
  for (final BookingStatus s in BookingStatus.values) {
    when(
      () => repo.getMyBookings(
        status: s,
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer((_) async => byStatus[s] ?? _page(const <Booking>[]));
  }
}

void main() {
  group('build — fan-out + merge per tab', () {
    test('Майбутні fetches ONLY CONFIRMED (single-status tab)', () async {
      final repo = _MockBookingRepository();
      _stubAll(
        repo,
        byStatus: <BookingStatus, PageResponse<Booking>>{
          BookingStatus.confirmed: _page(<Booking>[
            _booking(
              id: 'c1',
              status: BookingStatus.confirmed,
              startAt: DateTime.utc(2026, 8, 1, 10),
            ),
          ]),
        },
      );
      final c = _container(repo);

      final MyBookingsState state = await c.read(
        myBookingsProvider(BookingTab.upcoming).future,
      );

      expect(state.items.map((Booking b) => b.id), <String>['c1']);
      verify(
        () => repo.getMyBookings(
          status: BookingStatus.confirmed,
          page: 0,
          size: any(named: 'size'),
        ),
      ).called(1);
      verifyNever(
        () => repo.getMyBookings(
          status: BookingStatus.declined,
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      );
    });

    test('Скасовані merges CANCELLED + DECLINED into one list', () async {
      final repo = _MockBookingRepository();
      _stubAll(
        repo,
        byStatus: <BookingStatus, PageResponse<Booking>>{
          BookingStatus.cancelled: _page(<Booking>[
            _booking(
              id: 'x1',
              status: BookingStatus.cancelled,
              startAt: DateTime.utc(2026, 7, 10),
            ),
          ]),
          BookingStatus.declined: _page(<Booking>[
            _booking(
              id: 'd1',
              status: BookingStatus.declined,
              startAt: DateTime.utc(2026, 7, 12),
            ),
          ]),
        },
      );
      final c = _container(repo);

      final MyBookingsState state = await c.read(
        myBookingsProvider(BookingTab.cancelled).future,
      );

      expect(state.items.map((Booking b) => b.id).toSet(), <String>{
        'x1',
        'd1',
      });
    });
  });

  group('merge sort direction', () {
    test('Майбутні sorts soonest-first (ascending startAt)', () async {
      final repo = _MockBookingRepository();
      _stubAll(
        repo,
        byStatus: <BookingStatus, PageResponse<Booking>>{
          BookingStatus.confirmed: _page(<Booking>[
            _booking(
              id: 'late',
              status: BookingStatus.confirmed,
              startAt: DateTime.utc(2026, 8, 5),
            ),
            _booking(
              id: 'soon',
              status: BookingStatus.confirmed,
              startAt: DateTime.utc(2026, 8, 1),
            ),
          ]),
        },
      );
      final c = _container(repo);

      final MyBookingsState state = await c.read(
        myBookingsProvider(BookingTab.upcoming).future,
      );

      expect(state.items.map((Booking b) => b.id), <String>['soon', 'late']);
    });

    test('Минулі sorts most-recent-first (descending startAt)', () async {
      final repo = _MockBookingRepository();
      _stubAll(
        repo,
        byStatus: <BookingStatus, PageResponse<Booking>>{
          BookingStatus.completed: _page(<Booking>[
            _booking(
              id: 'older',
              status: BookingStatus.completed,
              startAt: DateTime.utc(2026, 6, 1),
            ),
          ]),
          BookingStatus.notCompleted: _page(<Booking>[
            _booking(
              id: 'newer',
              status: BookingStatus.notCompleted,
              startAt: DateTime.utc(2026, 6, 20),
            ),
          ]),
        },
      );
      final c = _container(repo);

      final MyBookingsState state = await c.read(
        myBookingsProvider(BookingTab.past).future,
      );

      expect(state.items.map((Booking b) => b.id), <String>['newer', 'older']);
    });
  });

  group('loadMore', () {
    test('appends the next page and advances only the paged status', () async {
      final repo = _MockBookingRepository();
      // CANCELLED has a 2nd page; DECLINED is exhausted at page 0.
      when(
        () => repo.getMyBookings(
          status: BookingStatus.cancelled,
          page: 0,
          size: any(named: 'size'),
        ),
      ).thenAnswer(
        (_) async => _page(
          <Booking>[
            _booking(
              id: 'x0',
              status: BookingStatus.cancelled,
              startAt: DateTime.utc(2026, 7, 10),
            ),
          ],
          page: 0,
          totalPages: 2,
        ),
      );
      when(
        () => repo.getMyBookings(
          status: BookingStatus.cancelled,
          page: 1,
          size: any(named: 'size'),
        ),
      ).thenAnswer(
        (_) async => _page(
          <Booking>[
            _booking(
              id: 'x1',
              status: BookingStatus.cancelled,
              startAt: DateTime.utc(2026, 7, 9),
            ),
          ],
          page: 1,
          totalPages: 2,
        ),
      );
      when(
        () => repo.getMyBookings(
          status: BookingStatus.declined,
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).thenAnswer((_) async => _page(const <Booking>[]));
      final c = _container(repo);

      await c.read(myBookingsProvider(BookingTab.cancelled).future);
      expect(
        c.read(myBookingsProvider(BookingTab.cancelled)).value!.hasMore,
        isTrue,
      );

      await c
          .read(myBookingsProvider(BookingTab.cancelled).notifier)
          .loadMore();

      final MyBookingsState after = c
          .read(myBookingsProvider(BookingTab.cancelled))
          .value!;
      expect(after.items.map((Booking b) => b.id).toSet(), <String>{
        'x0',
        'x1',
      });
      expect(after.hasMore, isFalse);
      // DECLINED was already exhausted → only its page-0 fetch, never page 1.
      verify(
        () => repo.getMyBookings(
          status: BookingStatus.declined,
          page: 0,
          size: any(named: 'size'),
        ),
      ).called(1);
      verifyNever(
        () => repo.getMyBookings(
          status: BookingStatus.declined,
          page: 1,
          size: any(named: 'size'),
        ),
      );
    });

    test('is a no-op when every status is already exhausted', () async {
      final repo = _MockBookingRepository();
      _stubAll(
        repo,
        byStatus: <BookingStatus, PageResponse<Booking>>{
          BookingStatus.confirmed: _page(<Booking>[
            _booking(
              id: 'c1',
              status: BookingStatus.confirmed,
              startAt: DateTime.utc(2026, 8, 1),
            ),
          ]),
        },
      );
      final c = _container(repo);

      await c.read(myBookingsProvider(BookingTab.upcoming).future);
      await c.read(myBookingsProvider(BookingTab.upcoming).notifier).loadMore();

      // Exactly ONE page-0 fetch — the no-op loadMore issued no second call.
      verify(
        () => repo.getMyBookings(
          status: BookingStatus.confirmed,
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).called(1);
    });

    test(
      'a failed load-more keeps the current list and clears the spinner',
      () async {
        final repo = _MockBookingRepository();
        when(
          () => repo.getMyBookings(
            status: BookingStatus.confirmed,
            page: 0,
            size: any(named: 'size'),
          ),
        ).thenAnswer(
          (_) async => _page(
            <Booking>[
              _booking(
                id: 'c1',
                status: BookingStatus.confirmed,
                startAt: DateTime.utc(2026, 8, 1),
              ),
            ],
            page: 0,
            totalPages: 2,
          ),
        );
        when(
          () => repo.getMyBookings(
            status: BookingStatus.confirmed,
            page: 1,
            size: any(named: 'size'),
          ),
        ).thenThrow(Exception('network'));
        final c = _container(repo);

        await c.read(myBookingsProvider(BookingTab.upcoming).future);
        await c
            .read(myBookingsProvider(BookingTab.upcoming).notifier)
            .loadMore();

        final MyBookingsState after = c
            .read(myBookingsProvider(BookingTab.upcoming))
            .value!;
        // List survived the failed append — still AsyncData, not AsyncError.
        expect(
          c.read(myBookingsProvider(BookingTab.upcoming)).hasError,
          isFalse,
        );
        expect(after.items.map((Booking b) => b.id), <String>['c1']);
        expect(after.isLoadingMore, isFalse);
      },
    );
  });

  group('refresh', () {
    test('re-fetches page 0 for the tab', () async {
      final repo = _MockBookingRepository();
      _stubAll(
        repo,
        byStatus: <BookingStatus, PageResponse<Booking>>{
          BookingStatus.confirmed: _page(<Booking>[
            _booking(
              id: 'c1',
              status: BookingStatus.confirmed,
              startAt: DateTime.utc(2026, 8, 1),
            ),
          ]),
        },
      );
      final c = _container(repo);

      await c.read(myBookingsProvider(BookingTab.upcoming).future);
      await c.read(myBookingsProvider(BookingTab.upcoming).notifier).refresh();

      verify(
        () => repo.getMyBookings(
          status: BookingStatus.confirmed,
          page: 0,
          size: any(named: 'size'),
        ),
      ).called(2);
    });
  });

  group('build error', () {
    test('propagates a repository failure as AsyncError', () async {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          status: any(named: 'status'),
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).thenAnswer((_) async => throw Exception('boom'));
      final c = _container(repo);

      // Keep the autoDispose provider alive across the async gap, then trigger
      // the build and let the rejected fan-out settle.
      c.listen(myBookingsProvider(BookingTab.upcoming), (_, _) {});
      c.read(myBookingsProvider(BookingTab.upcoming));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(c.read(myBookingsProvider(BookingTab.upcoming)).hasError, isTrue);
    });
  });
}
