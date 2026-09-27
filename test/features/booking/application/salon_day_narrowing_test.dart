// Phase 21.12 QA — the SALON branch of `bookingsDayProvider`:
// `SalonDayQuery` on the wire, and `BookingsDayNotifier._narrowSalonDay`
// behind it.
//
// WHY THIS FILE EXISTS
// --------------------
// The phase shipped with `grep -arln` finding NO test reference to
// `SalonDayQuery`, `salonDayList`, `salonOf(` or `_narrowSalonDay` anywhere
// under `test/` or `integration_test/`. `_narrowSalonDay` is the code that
// hides CANCELLED and DECLINED rows by default on a MULTI-TENANT PII surface
// — a salon-wide board an owner and every admin can open — and it was
// entirely unexercised.
//
// It is also the only narrowing in the app that happens CLIENT-SIDE. `GET
// /bookings/salon/{salonId}` accepts no repeated `status` list and no
// `serviceId` predicate at all, so the wire carries NOTHING filter-shaped and
// the whole day comes back unnarrowed. Two invariants follow, and both are
// asserted here rather than assumed:
//
//   1. NOTHING filter-shaped goes on the wire. If a future change started
//      sending a single `status`, the truncation boundary would depend on
//      which filter the owner picked (`bookings_day_notifier.dart` states the
//      rejected design); `verify` with EXACT arguments is what catches it.
//   2. `totalElements` is recomputed from the NARROWED list, never taken from
//      the server's count — the host's «N записів» header reads it, and it
//      must equal the cards on screen.
//
// `_narrowSalonDay` is private, so it is exercised through the provider, which
// is the only way it ever runs in production anyway.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_state.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

const String _salonId = 'salon-1';

/// A fixed, DST-safe Kyiv calendar day. Both the query's `day` and every
/// fixture's `startAt` are derived from this ONE constant — the clock
/// coherence invariant is about mixing two clocks, not about pinning.
// future-date-ok: fixed PAST Kyiv day; no isPast/elapsed predicate is read.
final DateTime _day = DateTime(2026, 6, 15);

const User _owner = User(
  id: 'user-owner-1',
  email: 'owner@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Настя',
  lastName: 'Салон',
);

class _SettledAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _owner, accessToken: 'token');
}

Booking _booking({
  required String id,
  required BookingStatus status,
  String masterId = 'm1',
  String serviceId = 'svc-a',
  int hour = 10,
}) {
  // future-date-ok: the SAME fixed PAST Kyiv day as _day; no isPast is read.
  final DateTime start = DateTime.utc(2026, 6, 15, hour - 3);
  return Booking(
    id: id,
    masterId: masterId,
    masterFirstName: 'Оля',
    masterLastName: 'Коваль',
    masterType: 'SALON_MASTER',
    clientFirstName: 'Марія',
    clientLastName: 'Іванюк',
    serviceId: serviceId,
    serviceName: 'Манікюр',
    durationMinutes: 60,
    price: 500,
    startAt: start,
    endAt: start.add(const Duration(hours: 1)),
    status: status,
    canReview: false,
  );
}

PageResponse<Booking> _page(List<Booking> items, {int? totalElements}) =>
    PageResponse<Booking>(
      items: items,
      page: 0,
      totalPages: 1,
      totalElements: totalElements ?? items.length,
    );

Future<ProviderContainer> _container(BookingRepository repo) async {
  final ProviderContainer container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: <Object>[
      bookingRepositoryProvider.overrideWithValue(repo),
      authProvider.overrideWith(_SettledAuth.new),
    ].cast(),
  );
  addTearDown(container.dispose);
  // Settle auth BEFORE the first provider read — `BookingsDayNotifier.build`
  // watches `authProvider.select(...)`, and reading it mid-`AsyncLoading`
  // would fire a second, unrelated fetch.
  await container.read(authProvider.future);
  return container;
}

void main() {
  setUpAll(() {
    registerFallbackValue(BookingSort.oldest);
  });

  late _MockBookingRepository repo;

  setUp(() {
    repo = _MockBookingRepository();
  });

  void stub(List<Booking> items, {int? totalElements}) {
    when(
      () => repo.getSalonBookings(
        salonId: any(named: 'salonId'),
        masterId: any(named: 'masterId'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        sort: any(named: 'sort'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => _page(items, totalElements: totalElements));
  }

  // ═════════════════════════════════════════════════════════════════════════
  group('the salon branch hits the salon endpoint, and nothing else', () {
    test('a SalonDayQuery calls getSalonBookings — NEVER getMyBookings — with '
        'from == to == day, size 100, page 0, ascending sort, and NOTHING '
        'filter-shaped on the wire', () async {
      stub(const <Booking>[]);

      final ProviderContainer container = await _container(repo);
      await container.read(
        bookingsDayProvider(
          BookingsDayQuery.salonDayList(
            day: _day,
            salonId: _salonId,
            // A status selection that would ABSOLUTELY be a query param on
            // the master branch — proving it is dropped here, not merely
            // absent because nothing was selected.
            statuses: <BookingStatus>{BookingStatus.completed},
            serviceIds: <String>{'svc-a'},
          ),
        ).future,
      );

      verify(
        () => repo.getSalonBookings(
          salonId: _salonId,
          masterId: null,
          from: _day,
          to: _day,
          sort: BookingSort.oldest,
          page: 0,
          size: 100,
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
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

    test('masterId IS a wire param and travels when the query carries it', () {
      stub(const <Booking>[]);
      return _container(repo).then((ProviderContainer c) async {
        await c.read(
          bookingsDayProvider(
            BookingsDayQuery.salonOf(
              day: _day,
              salonId: _salonId,
              masterId: 'm7',
            ),
          ).future,
        );
        verify(
          () => repo.getSalonBookings(
            salonId: _salonId,
            masterId: 'm7',
            from: any(named: 'from'),
            to: any(named: 'to'),
            sort: any(named: 'sort'),
            page: any(named: 'page'),
            size: any(named: 'size'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).called(1);
      });
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('_narrowSalonDay — the DEFAULT is the PII decision', () {
    test('CANCELLED and DECLINED are HIDDEN on an untouched board, while '
        'CONFIRMED, COMPLETED and NOT_COMPLETED are kept', () async {
      stub(<Booking>[
        _booking(id: 'confirmed', status: BookingStatus.confirmed, hour: 9),
        _booking(id: 'cancelled', status: BookingStatus.cancelled, hour: 10),
        _booking(id: 'completed', status: BookingStatus.completed, hour: 11),
        _booking(id: 'declined', status: BookingStatus.declined, hour: 12),
        _booking(
          id: 'notCompleted',
          status: BookingStatus.notCompleted,
          hour: 13,
        ),
      ]);

      final ProviderContainer container = await _container(repo);
      final BookingsDayState state = await container.read(
        // `salonDayList` — the factory the SCREEN uses — with NO statuses,
        // i.e. exactly what an owner sees on first open.
        bookingsDayProvider(
          BookingsDayQuery.salonDayList(day: _day, salonId: _salonId),
        ).future,
      );

      expect(
        state.items.map((Booking b) => b.id),
        <String>['confirmed', 'completed', 'notCompleted'],
        reason:
            'the locked 2026-08-13 default (CANCELLED + DECLINED hidden, '
            'NOT_COMPLETED kept) must hold on the SALON board exactly as it '
            'does on the master board — it is a PRODUCT decision, not a '
            'per-endpoint one',
      );
      expect(
        state.items.any((Booking b) => b.status == BookingStatus.cancelled),
        isFalse,
      );
      expect(
        state.items.any((Booking b) => b.status == BookingStatus.declined),
        isFalse,
      );
    });

    test(
      'the SERVER count is discarded — totalElements is recomputed from '
      'the NARROWED list, so «N записів» equals the cards on screen',
      () async {
        stub(<Booking>[
          _booking(id: 'confirmed', status: BookingStatus.confirmed, hour: 9),
          _booking(id: 'cancelled', status: BookingStatus.cancelled, hour: 10),
          _booking(id: 'declined', status: BookingStatus.declined, hour: 11),
        ]);

        final ProviderContainer container = await _container(repo);
        final BookingsDayState state = await container.read(
          bookingsDayProvider(
            BookingsDayQuery.salonDayList(day: _day, salonId: _salonId),
          ).future,
        );

        expect(state.items, hasLength(1));
        expect(
          state.totalElements,
          1,
          reason:
              'the server said 3; two were narrowed away client-side, so the '
              'header must say 1 or it describes a list nobody can see',
        );
      },
    );

    test('isTruncated is computed from the RAW page, BEFORE narrowing — it '
        'answers "did the server have more than it could send", which the '
        'client-side narrowing cannot change', () async {
      stub(
        <Booking>[
          _booking(id: 'a', status: BookingStatus.confirmed, hour: 9),
          _booking(id: 'b', status: BookingStatus.cancelled, hour: 10),
        ],
        // The server reports MORE than this page carried.
        totalElements: 140,
      );

      final ProviderContainer container = await _container(repo);
      final BookingsDayState state = await container.read(
        bookingsDayProvider(
          BookingsDayQuery.salonDayList(day: _day, salonId: _salonId),
        ).future,
      );

      expect(state.isTruncated, isTrue);
      expect(state.items, hasLength(1));
      expect(state.totalElements, 1);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('_narrowSalonDay — explicit narrowing', () {
    test('an explicit status selection narrows to exactly it', () async {
      stub(<Booking>[
        _booking(id: 'confirmed', status: BookingStatus.confirmed, hour: 9),
        _booking(id: 'cancelled', status: BookingStatus.cancelled, hour: 10),
        _booking(id: 'completed', status: BookingStatus.completed, hour: 11),
      ]);

      final ProviderContainer container = await _container(repo);
      final BookingsDayState state = await container.read(
        bookingsDayProvider(
          BookingsDayQuery.salonOf(
            day: _day,
            salonId: _salonId,
            statuses: <BookingStatus>{BookingStatus.cancelled},
          ),
        ).future,
      );

      expect(state.items.map((Booking b) => b.id), <String>['cancelled']);
    });

    test('a service selection narrows by serviceId', () async {
      stub(<Booking>[
        _booking(
          id: 'a',
          status: BookingStatus.confirmed,
          serviceId: 'svc-a',
          hour: 9,
        ),
        _booking(
          id: 'b',
          status: BookingStatus.confirmed,
          serviceId: 'svc-b',
          hour: 10,
        ),
        _booking(
          id: 'c',
          status: BookingStatus.confirmed,
          serviceId: 'svc-a',
          hour: 11,
        ),
      ]);

      final ProviderContainer container = await _container(repo);
      final BookingsDayState state = await container.read(
        bookingsDayProvider(
          BookingsDayQuery.salonOf(
            day: _day,
            salonId: _salonId,
            serviceIds: <String>{'svc-a'},
          ),
        ).future,
      );

      expect(state.items.map((Booking b) => b.id), <String>['a', 'c']);
    });

    test('status AND service are ANDed, not ORed', () async {
      stub(<Booking>[
        _booking(
          id: 'keep',
          status: BookingStatus.confirmed,
          serviceId: 'svc-a',
          hour: 9,
        ),
        _booking(
          id: 'wrongService',
          status: BookingStatus.confirmed,
          serviceId: 'svc-b',
          hour: 10,
        ),
        _booking(
          id: 'wrongStatus',
          status: BookingStatus.completed,
          serviceId: 'svc-a',
          hour: 11,
        ),
      ]);

      final ProviderContainer container = await _container(repo);
      final BookingsDayState state = await container.read(
        bookingsDayProvider(
          BookingsDayQuery.salonOf(
            day: _day,
            salonId: _salonId,
            statuses: <BookingStatus>{BookingStatus.confirmed},
            serviceIds: <String>{'svc-a'},
          ),
        ).future,
      );

      expect(state.items.map((Booking b) => b.id), <String>['keep']);
    });

    test('an EMPTY selection means "no predicate" — it means MORE here, not '
        'less — and returns the server list ITSELF, unchanged', () async {
      final List<Booking> served = <Booking>[
        _booking(id: 'a', status: BookingStatus.confirmed, hour: 9),
        _booking(id: 'b', status: BookingStatus.cancelled, hour: 10),
        _booking(id: 'c', status: BookingStatus.declined, hour: 11),
      ];
      stub(served);

      final ProviderContainer container = await _container(repo);
      final BookingsDayState state = await container.read(
        // `salonOf`, NOT `salonDayList` — the raw member with genuinely empty
        // statuses. This is what "the owner ticked every filter group"
        // resolves to on the wire, and it must show CANCELLED/DECLINED too.
        bookingsDayProvider(
          BookingsDayQuery.salonOf(day: _day, salonId: _salonId),
        ).future,
      );

      expect(state.items.map((Booking b) => b.id), <String>['a', 'b', 'c']);
      expect(
        state.totalElements,
        3,
        reason: 'nothing was narrowed, so the server count stands',
      );
    });

    test(
      'ORDER IS PRESERVED — the list is filtered, never re-sorted',
      () async {
        // Deliberately fed back in a NON-ascending id order so a stray sort
        // shows up as a failure rather than as a plausible-looking list.
        stub(<Booking>[
          _booking(id: 'z', status: BookingStatus.confirmed, hour: 9),
          _booking(id: 'm', status: BookingStatus.cancelled, hour: 10),
          _booking(id: 'a', status: BookingStatus.confirmed, hour: 11),
          _booking(id: 'b', status: BookingStatus.confirmed, hour: 12),
        ]);

        final ProviderContainer container = await _container(repo);
        final BookingsDayState state = await container.read(
          bookingsDayProvider(
            BookingsDayQuery.salonDayList(day: _day, salonId: _salonId),
          ).future,
        );

        expect(
          state.items.map((Booking b) => b.id),
          <String>['z', 'a', 'b'],
          reason:
              'assignLanes walks its input once and is correct ONLY on an '
              'ascending-startsAt stream — the narrowing must not reorder it',
        );
      },
    );

    test(
      'a narrowing that removes the LAST element only still works (the '
      'copy-on-first-exclusion branch, entered at the final index)',
      () async {
        stub(<Booking>[
          _booking(id: 'a', status: BookingStatus.confirmed, hour: 9),
          _booking(id: 'b', status: BookingStatus.confirmed, hour: 10),
          _booking(id: 'tail', status: BookingStatus.declined, hour: 11),
        ]);

        final ProviderContainer container = await _container(repo);
        final BookingsDayState state = await container.read(
          bookingsDayProvider(
            BookingsDayQuery.salonDayList(day: _day, salonId: _salonId),
          ).future,
        );

        expect(state.items.map((Booking b) => b.id), <String>['a', 'b']);
      },
    );

    test(
      'a narrowing that removes the FIRST element only still works',
      () async {
        stub(<Booking>[
          _booking(id: 'head', status: BookingStatus.cancelled, hour: 9),
          _booking(id: 'a', status: BookingStatus.confirmed, hour: 10),
          _booking(id: 'b', status: BookingStatus.completed, hour: 11),
        ]);

        final ProviderContainer container = await _container(repo);
        final BookingsDayState state = await container.read(
          bookingsDayProvider(
            BookingsDayQuery.salonDayList(day: _day, salonId: _salonId),
          ).future,
        );

        expect(state.items.map((Booking b) => b.id), <String>['a', 'b']);
      },
    );

    test(
      'everything narrowed away yields an EMPTY day, not an error',
      () async {
        stub(<Booking>[
          _booking(id: 'a', status: BookingStatus.cancelled, hour: 9),
          _booking(id: 'b', status: BookingStatus.declined, hour: 10),
        ]);

        final ProviderContainer container = await _container(repo);
        final BookingsDayState state = await container.read(
          bookingsDayProvider(
            BookingsDayQuery.salonDayList(day: _day, salonId: _salonId),
          ).future,
        );

        expect(state.items, isEmpty);
        expect(state.totalElements, 0);
      },
    );
  });

  // ═════════════════════════════════════════════════════════════════════════
  group(
    'BookingsDayQuery.salonOf / .salonDayList — family-key normalisation',
    () {
      test('salonOf truncates `day` to date-only, so two instants on one '
          'calendar day are ONE family member and ONE fetch', () async {
        stub(const <Booking>[]);
        final ProviderContainer container = await _container(repo);

        await container.read(
          bookingsDayProvider(
            BookingsDayQuery.salonOf(
              day: DateTime(2026, 6, 15, 9, 14),
              salonId: _salonId,
            ),
          ).future,
        );
        await container.read(
          bookingsDayProvider(
            BookingsDayQuery.salonOf(
              day: DateTime(2026, 6, 15, 9, 15),
              salonId: _salonId,
            ),
          ).future,
        );

        verify(
          () => repo.getSalonBookings(
            salonId: any(named: 'salonId'),
            masterId: any(named: 'masterId'),
            from: any(named: 'from'),
            to: any(named: 'to'),
            sort: any(named: 'sort'),
            page: any(named: 'page'),
            size: any(named: 'size'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).called(1);
      });

      test(
        'salonOf canonicalises filter ORDER — two spellings of one selection '
        'are ONE family member and ONE fetch',
        () async {
          stub(const <Booking>[]);
          final ProviderContainer container = await _container(repo);

          await container.read(
            bookingsDayProvider(
              BookingsDayQuery.salonOf(
                day: _day,
                salonId: _salonId,
                statuses: <BookingStatus>{
                  BookingStatus.completed,
                  BookingStatus.confirmed,
                },
                serviceIds: <String>{'svc-b', 'svc-a'},
              ),
            ).future,
          );
          await container.read(
            bookingsDayProvider(
              BookingsDayQuery.salonOf(
                day: _day,
                salonId: _salonId,
                statuses: <BookingStatus>{
                  BookingStatus.confirmed,
                  BookingStatus.completed,
                },
                serviceIds: <String>{'svc-a', 'svc-b'},
              ),
            ).future,
          );

          verify(
            () => repo.getSalonBookings(
              salonId: any(named: 'salonId'),
              masterId: any(named: 'masterId'),
              from: any(named: 'from'),
              to: any(named: 'to'),
              sort: any(named: 'sort'),
              page: any(named: 'page'),
              size: any(named: 'size'),
              cancelToken: any(named: 'cancelToken'),
            ),
          ).called(1);
        },
      );

      test(
        'a DIFFERENT salonId is a DIFFERENT family member — two salons never '
        'share one cached day (the multi-tenant leak this keys against)',
        () async {
          stub(const <Booking>[]);
          final ProviderContainer container = await _container(repo);

          await container.read(
            bookingsDayProvider(
              BookingsDayQuery.salonOf(day: _day, salonId: 'salon-a'),
            ).future,
          );
          await container.read(
            bookingsDayProvider(
              BookingsDayQuery.salonOf(day: _day, salonId: 'salon-b'),
            ).future,
          );

          verify(
            () => repo.getSalonBookings(
              salonId: 'salon-a',
              masterId: any(named: 'masterId'),
              from: any(named: 'from'),
              to: any(named: 'to'),
              sort: any(named: 'sort'),
              page: any(named: 'page'),
              size: any(named: 'size'),
              cancelToken: any(named: 'cancelToken'),
            ),
          ).called(1);
          verify(
            () => repo.getSalonBookings(
              salonId: 'salon-b',
              masterId: any(named: 'masterId'),
              from: any(named: 'from'),
              to: any(named: 'to'),
              sort: any(named: 'sort'),
              page: any(named: 'page'),
              size: any(named: 'size'),
              cancelToken: any(named: 'cancelToken'),
            ),
          ).called(1);
        },
      );

      test('salonDayList resolves the SAME default wire set as dayList — the '
          'product decision is shared, not re-derived per endpoint', () {
        final BookingsDayQuery salon = BookingsDayQuery.salonDayList(
          day: _day,
          salonId: _salonId,
        );
        final BookingsDayQuery master = BookingsDayQuery.dayList(day: _day);

        expect(salon.statuses, master.statuses);
        expect(salon.statuses, isNot(contains(BookingStatus.cancelled)));
        expect(salon.statuses, isNot(contains(BookingStatus.declined)));
        expect(salon.statuses, contains(BookingStatus.notCompleted));
      });

      test('salonDayList is a SalonDayQuery carrying the salon id, and its '
          'day is date-only', () {
        final BookingsDayQuery q = BookingsDayQuery.salonDayList(
          day: DateTime(2026, 6, 15, 23, 59, 59),
          salonId: _salonId,
        );

        expect(q, isA<SalonDayQuery>());
        expect((q as SalonDayQuery).salonId, _salonId);
        expect(q.day, DateTime(2026, 6, 15));
        expect(q.masterId, isNull);
      });
    },
  );

  // ═════════════════════════════════════════════════════════════════════════
  group('AUDIT M2 — a salon filter combination does NOT key a fetch', () {
    test('fetchKey is IDENTITY on the master member — its statuses and '
        'serviceIds are real query params', () {
      final BookingsDayQuery master = BookingsDayQuery.of(
        day: _day,
        statuses: <BookingStatus>{BookingStatus.confirmed},
        serviceIds: <String>{'s1'},
      );
      expect(identical(master.fetchKey, master), isTrue);
    });

    test('fetchKey STRIPS statuses/serviceIds on the salon member, and is '
        'identity once there is nothing left to strip', () {
      final BookingsDayQuery filtered = BookingsDayQuery.salonOf(
        day: _day,
        salonId: _salonId,
        masterId: 'm1',
        statuses: <BookingStatus>{BookingStatus.confirmed},
        serviceIds: <String>{'s1'},
      );
      final BookingsDayQuery bare = BookingsDayQuery.salonOf(
        day: _day,
        salonId: _salonId,
        masterId: 'm1',
      );
      expect(filtered.fetchKey, bare);
      expect(identical(bare.fetchKey, bare), isTrue);
      // The wire-bearing fields survive — only the two that never reach the
      // salon endpoint are dropped.
      expect((filtered.fetchKey as SalonDayQuery).salonId, _salonId);
      expect((filtered.fetchKey as SalonDayQuery).masterId, 'm1');
      expect(filtered.fetchKey.day, filtered.day);
    });

    test('FIVE status combinations on ONE salon day issue exactly ONE '
        'request — before this fix each was its own family member fetching '
        'a byte-identical page', () async {
      stub(<Booking>[
        _booking(id: 'a', status: BookingStatus.confirmed, hour: 9),
        _booking(id: 'b', status: BookingStatus.completed, hour: 10),
        _booking(id: 'c', status: BookingStatus.cancelled, hour: 11),
      ]);

      final ProviderContainer container = await _container(repo);
      for (final Set<BookingStatus> selection in <Set<BookingStatus>>[
        <BookingStatus>{},
        <BookingStatus>{BookingStatus.confirmed},
        <BookingStatus>{BookingStatus.completed},
        <BookingStatus>{BookingStatus.confirmed, BookingStatus.completed},
        <BookingStatus>{BookingStatus.cancelled},
      ]) {
        await container.read(
          bookingsDayProvider(
            BookingsDayQuery.salonOf(
              day: _day,
              salonId: _salonId,
              statuses: selection,
            ),
          ).future,
        );
      }

      verify(
        () => repo.getSalonBookings(
          salonId: any(named: 'salonId'),
          masterId: any(named: 'masterId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
    });

    test(
      'and each of those members still serves its OWN narrowed list — the '
      'shared fetch is an implementation detail, not a shared answer',
      () async {
        stub(<Booking>[
          _booking(id: 'a', status: BookingStatus.confirmed, hour: 9),
          _booking(id: 'b', status: BookingStatus.completed, hour: 10),
        ]);

        final ProviderContainer container = await _container(repo);
        final BookingsDayState onlyConfirmed = await container.read(
          bookingsDayProvider(
            BookingsDayQuery.salonOf(
              day: _day,
              salonId: _salonId,
              statuses: <BookingStatus>{BookingStatus.confirmed},
            ),
          ).future,
        );
        final BookingsDayState onlyCompleted = await container.read(
          bookingsDayProvider(
            BookingsDayQuery.salonOf(
              day: _day,
              salonId: _salonId,
              statuses: <BookingStatus>{BookingStatus.completed},
            ),
          ).future,
        );

        expect(onlyConfirmed.items.map((Booking b) => b.id), <String>['a']);
        expect(onlyCompleted.items.map((Booking b) => b.id), <String>['b']);
        expect(onlyConfirmed.totalElements, 1);
        expect(onlyCompleted.totalElements, 1);
      },
    );

    test('a DIFFERENT day is still a different fetch — the day is the one '
        'thing that does travel', () async {
      stub(const <Booking>[]);
      final ProviderContainer container = await _container(repo);
      await container.read(
        bookingsDayProvider(
          BookingsDayQuery.salonOf(day: _day, salonId: _salonId),
        ).future,
      );
      await container.read(
        bookingsDayProvider(
          BookingsDayQuery.salonOf(
            day: _day.add(const Duration(days: 1)),
            salonId: _salonId,
          ),
        ).future,
      );
      verify(
        () => repo.getSalonBookings(
          salonId: any(named: 'salonId'),
          masterId: any(named: 'masterId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(2);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // QA 2026-09-17 — `BookingsDayState.items` HAS A STABLE IDENTITY.
  //
  // `BookingsDayState` is freezed, and freezed generates its list getter as
  //
  //     if (_items is EqualUnmodifiableListView) return _items;
  //     return EqualUnmodifiableListView(_items);
  //
  // so a RAW stored list makes every single `state.items` read allocate a
  // brand-new wrapper. That was the shipped behaviour on EVERY route —
  // `PageResponse` is hand-written, not freezed, so `page.items` is a plain
  // `List` and all three `BookingsDayState(...)` sites stored one — and it
  // silently defeated three identity gates that the code documents as live:
  // `_visibleBookingsFor`'s memo, `BookingsTimelineGrid.didUpdateWidget`'s
  // `identical(widget.bookings, oldWidget.bookings)` (which decides whether
  // to re-run `assignLanes` + every card's layout), and
  // `bookingsInsideScheduleWindow`'s return-the-input optimisation that
  // exists to feed them. It also misfired `_Loaded.build`'s vacuity assert,
  // red-screening the salon board on an ordinary day.
  //
  // `stableBookingList` (`bookings_day_state.dart`) is what fixes it, at the
  // three construction sites in `BookingsDayNotifier`. NOTHING ELSE CATCHES
  // ITS REMOVAL: the wrapper compares `==` by value, so every content
  // assertion in this repo stays green with it gone. Only an `identical`
  // assertion on TWO SEPARATE READS of the getter can see it — which is what
  // these tests are.
  //
  // Both narrowing branches are covered, because they are separate
  // constructor call sites: `_narrowSalonDay` returns `items` itself when
  // nothing is excluded and a `sublist`-seeded copy when something is.
  //
  // THEIR STRENGTH DIFFERS, and the weaker one says so on itself. Reverting
  // `stableBookingList` (2026-09-17) turns the NARROWED test red and leaves
  // the UNNARROWED one green: on the salon branch the pass-through case
  // stores `base.items`, which is itself a freezed getter result and so is
  // ALREADY an `EqualUnmodifiableListView`. That branch was stable by
  // accident before the fix. It is kept as a characterisation guard — if the
  // delegation ever starts handing a raw list through, it turns red — but
  // the sites that were genuinely broken are the `sublist` branch here and
  // `items: page.items` on the master branch, the latter pinned in
  // `bookings_day_notifier_test.dart`.
  // ═════════════════════════════════════════════════════════════════════════
  group('BookingsDayState.items is identity-stable across reads', () {
    test(
      'the NARROWED salon branch (a CANCELLED row is hidden, so the state '
      'is built from a fresh sublist) still hands out ONE instance',
      () async {
        stub(<Booking>[
          _booking(id: 'keep', status: BookingStatus.confirmed),
          // Excluded by the DEFAULT status selection — this is what forces
          // `_narrowSalonDay` down its `items.sublist(0, i)` branch.
          _booking(id: 'drop', status: BookingStatus.cancelled, hour: 12),
        ]);

        final ProviderContainer container = await _container(repo);
        final BookingsDayState state = await container.read(
          bookingsDayProvider(
            BookingsDayQuery.salonDayList(day: _day, salonId: _salonId),
          ).future,
        );

        // Precondition — the narrowing genuinely happened, so this is the
        // sublist branch and not the pass-through one.
        expect(state.items.map((Booking b) => b.id), <String>['keep']);
        expect(
          identical(state.items, state.items),
          isTrue,
          reason:
              'two reads of the freezed getter handed back two different '
              'wrappers. Every identity gate downstream now misses on every '
              'rebuild — restore stableBookingList in BookingsDayNotifier',
        );
      },
    );

    // CHARACTERISATION, not a regression pin — see the group doc: this branch
    // stores `base.items`, already an `EqualUnmodifiableListView`, so it is
    // green with or without `stableBookingList`. It guards the day that stops
    // being true.
    test(
      'the UNNARROWED salon branch (nothing hidden, so the delegated '
      'base.items is stored through verbatim) still hands out ONE instance',
      () async {
        stub(<Booking>[_booking(id: 'a', status: BookingStatus.confirmed)]);

        final ProviderContainer container = await _container(repo);
        final BookingsDayState state = await container.read(
          bookingsDayProvider(
            BookingsDayQuery.salonDayList(day: _day, salonId: _salonId),
          ).future,
        );

        expect(state.items.single.id, 'a');
        expect(
          identical(state.items, state.items),
          isTrue,
          reason:
              'the pass-through branch stopped handing through an already-'
              'wrapped base.items — it now stores a raw list, so wrap it with '
              'stableBookingList like the other two construction sites',
        );
      },
    );
  });
}
