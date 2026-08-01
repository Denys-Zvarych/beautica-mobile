// Phase 225 — nextAppointmentProvider unit tests.
//
// The Home Hub's «Найближчий запис» card used to be a hardcoded stub
// (always null). It now derives from `BookingRepository.getMyBookings` —
// the SAME endpoint/request shape the «Мої записи» Майбутні tab issues
// (`BookingTab.upcoming.statuses` + `BookingSort.oldest`, page 0). These
// tests pin:
//   • the exact request shape (statuses/sort/page) sent to the repository;
//   • the domain → NextAppointment field mapping (date/time labels, location
//     fallback, master initials, the real `endsAt`);
//   • the elapsed-but-not-yet-transitioned edge case: a CONFIRMED booking
//     whose `endAt` is already in the past (server hasn't flipped its status
//     yet) must be skipped in favour of the next genuinely-upcoming row;
//   • an empty page, or a page where EVERY row is elapsed, resolves to null;
//   • a repository failure propagates as this provider's AsyncError, exactly
//     like `clientProfile`'s unauthenticated-session contract.
//
// Strategy: a hand-written [_FakeBookingRepository] (mirrors
// `client_profile_provider_test.dart`'s `_FakeLocationRepository`) rather
// than a mocktail mock — it records the exact call args made and lets each
// test hand back whatever page it wants without matcher gymnastics over an
// `Iterable<BookingStatus>` parameter.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_tab.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../helpers/booking_fixture_dates.dart';

// ---------------------------------------------------------------------------
// Fake BookingRepository — records the getMyBookings call, everything else
// throws (unused by this provider).
// ---------------------------------------------------------------------------

class _FakeBookingRepository implements BookingRepository {
  _FakeBookingRepository(this._page);

  /// Swap mid-test via [respondWith] when a test needs a second scripted call
  /// (not used currently, but keeps the fake reusable).
  PageResponse<Booking> _page;
  void respondWith(PageResponse<Booking> page) => _page = page;

  /// When set, overrides [_page]: `getMyBookings` returns
  /// `pagesByIndex[page]` instead, so a test can script a DIFFERENT response
  /// per page — the page-forward regression tests need this (page 0
  /// all-elapsed, page 1 carries the real upcoming row).
  Map<int, PageResponse<Booking>>? pagesByIndex;

  /// The Object? failure to throw instead of returning [_page], or null to
  /// return normally.
  Object? throwing;

  // Captured call args — asserted by the "request shape" test. Reflect the
  // MOST RECENT call; [capturedPages]/[capturedFroms] below hold the full
  // history for the multi-call page-forward tests.
  Iterable<BookingStatus>? capturedStatuses;
  BookingSort? capturedSort;
  int? capturedPage;
  int? capturedSize;
  DateTime? capturedFrom;
  int callCount = 0;

  /// The `page` argument of every call, in order.
  final List<int> capturedPages = <int>[];

  /// The `from` argument of every call, in order.
  final List<DateTime?> capturedFroms = <DateTime?>[];

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required Iterable<BookingStatus> statuses,
    required int page,
    int size = kBookingsPageSize,
    BookingSort? sort,
    Iterable<String>? serviceIds,
    DateTime? from,
    DateTime? to,
    CancelToken? cancelToken,
  }) async {
    callCount++;
    capturedStatuses = statuses;
    capturedSort = sort;
    capturedPage = page;
    capturedSize = size;
    capturedFrom = from;
    capturedPages.add(page);
    capturedFroms.add(from);
    final Object? f = throwing;
    if (f != null) throw f;
    final Map<int, PageResponse<Booking>>? byIndex = pagesByIndex;
    if (byIndex != null) {
      final PageResponse<Booking>? scripted = byIndex[page];
      if (scripted == null) {
        throw StateError(
          '_FakeBookingRepository: no scripted response for page $page — '
          'the provider paged further than this test scripted for.',
        );
      }
      return scripted;
    }
    return _page;
  }

  @override
  Future<Booking> createBooking(CreateBookingRequest req) =>
      throw UnimplementedError('not used by nextAppointmentProvider');

  @override
  Future<List<DateTime>> getMyBookedDays({
    required DateTime from,
    required DateTime to,
    CancelToken? cancelToken,
  }) => throw UnimplementedError('not used by nextAppointmentProvider');

  @override
  Future<Booking> getBookingById(String id) =>
      throw UnimplementedError('not used by nextAppointmentProvider');

  @override
  Future<void> cancelBooking(String id, {String? reason}) =>
      throw UnimplementedError('not used by nextAppointmentProvider');

  @override
  Future<Booking> rescheduleBooking(String id, DateTime newStartAt) =>
      throw UnimplementedError('not used by nextAppointmentProvider');

  @override
  Future<void> declineBooking(String id, {String? comment}) =>
      throw UnimplementedError('not used by nextAppointmentProvider');

  @override
  Future<void> completeBooking(String id) =>
      throw UnimplementedError('not used by nextAppointmentProvider');

  @override
  Future<void> createReview({
    required String bookingId,
    required int rating,
    String? comment,
  }) => throw UnimplementedError('not used by nextAppointmentProvider');
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// A CONFIRMED booking starting [aheadOfNow] from now and ending
/// [durationMinutes] later — genuinely upcoming when [aheadOfNow] is positive
/// and [durationMinutes] doesn't carry the end back into the past.
Booking _booking({
  required String id,
  Duration aheadOfNow = const Duration(days: 2),
  int durationMinutes = 60,
  String? salonName,
  String? cityLabel,
  String? street,
  String? buildingNo,
}) {
  final DateTime start = futureBookingStart(aheadOfNow: aheadOfNow);
  return Booking(
    id: id,
    masterId: 'master-$id',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    salonName: salonName,
    serviceId: 'svc-$id',
    serviceName: 'Манікюр',
    cityLabel: cityLabel,
    street: street,
    buildingNo: buildingNo,
    durationMinutes: durationMinutes,
    price: 500,
    startAt: start,
    endAt: start.add(Duration(minutes: durationMinutes)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

/// An ALREADY-ELAPSED CONFIRMED booking — `endAt` in the past even though the
/// status is still CONFIRMED (the server hasn't transitioned it yet). Exists
/// to drive the client-side [BookingDisplayX.isPast] skip.
Booking _elapsedBooking(String id) {
  final DateTime start = DateTime.utc(2000, 1, 1, 9);
  return Booking(
    id: id,
    masterId: 'master-$id',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    serviceId: 'svc-$id',
    serviceName: 'Манікюр',
    durationMinutes: 60,
    price: 500,
    startAt: start,
    endAt: start.add(const Duration(minutes: 60)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

/// Builds a [ProviderContainer] wired to [repo]. When [now] is supplied it
/// overrides [clockProvider] so the provider's "today" is pinned to a fixed
/// instant instead of the real wall clock — required for every test in the
/// 'Kyiv-day boundary' group, since [dateOnly]/[toBeauticaTime] are only
/// interestingly exercised near a calendar-day boundary.
ProviderContainer _container(
  _FakeBookingRepository repo, {
  DateTime Function()? now,
}) {
  final container = ProviderContainer(
    overrides: [
      bookingRepositoryProvider.overrideWithValue(repo),
      if (now != null) clockProvider.overrideWithValue(now),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('nextAppointment request shape', () {
    test('issues ONE getMyBookings call with BookingTab.upcoming.statuses, '
        'BookingSort.oldest, page 0, and `from` pinned to the Europe/Kyiv day '
        '(the "Kyiv-day boundary" group below exercises the narrowing-bug '
        'regression this pins the shape of)', () async {
      final repo = _FakeBookingRepository(
        const PageResponse<Booking>(
          items: <Booking>[],
          page: 0,
          totalPages: 1,
          totalElements: 0,
        ),
      );
      // A fixed instant (not the real wall clock) so `capturedFrom` can be
      // asserted against an exact expected value rather than merely
      // "non-null" — `from` IS part of this provider's pinned request
      // shape, not an incidental extra.
      final DateTime fixedNow = DateTime.utc(2026, 8, 1, 10, 0);
      final container = _container(repo, now: () => fixedNow);

      final result = await container.read(nextAppointmentProvider.future);

      expect(result, isNull);
      expect(
        repo.callCount,
        1,
        reason: 'must issue exactly one request, never per-status fan-out',
      );
      expect(repo.capturedStatuses, BookingTab.upcoming.statuses);
      expect(repo.capturedSort, BookingSort.oldest);
      expect(repo.capturedPage, 0);
      expect(
        repo.capturedFrom,
        dateOnly(toBeauticaTime(fixedNow)),
        reason:
            '`from` is the Europe/Kyiv calendar day derived from the '
            'injected clock — never the device-local day.',
      );
    });
  });

  group('nextAppointment mapping', () {
    test('maps the soonest upcoming booking to a NextAppointment', () async {
      final Booking booking = _booking(
        id: 'bk-1',
        street: 'вул. Хрещатик',
        buildingNo: '22',
        cityLabel: 'Київ',
      );
      final repo = _FakeBookingRepository(
        PageResponse<Booking>(
          items: <Booking>[booking],
          page: 0,
          totalPages: 1,
          totalElements: 1,
        ),
      );
      final container = _container(repo);

      final NextAppointment? result = await container.read(
        nextAppointmentProvider.future,
      );

      expect(result, isNotNull);
      expect(result!.id, booking.id);
      expect(result.masterName, 'Марія Іванюк');
      expect(result.service, 'Манікюр');
      expect(result.startsAt, booking.startAt);
      expect(result.endsAt, booking.endAt);
      expect(result.masterInitials, 'МІ');
      expect(result.location, 'вул. Хрещатик, 22, Київ');
    });

    test(
      'falls back to salonName when the booking has no composed address',
      () async {
        final Booking booking = _booking(
          id: 'bk-2',
          salonName: 'Lviv Nails Studio',
        );
        final repo = _FakeBookingRepository(
          PageResponse<Booking>(
            items: <Booking>[booking],
            page: 0,
            totalPages: 1,
            totalElements: 1,
          ),
        );
        final container = _container(repo);

        final NextAppointment? result = await container.read(
          nextAppointmentProvider.future,
        );

        expect(result!.location, 'Lviv Nails Studio');
      },
    );

    test('location is the empty string when neither an address nor a salon '
        'name is on file', () async {
      final Booking booking = _booking(id: 'bk-3');
      final repo = _FakeBookingRepository(
        PageResponse<Booking>(
          items: <Booking>[booking],
          page: 0,
          totalPages: 1,
          totalElements: 1,
        ),
      );
      final container = _container(repo);

      final NextAppointment? result = await container.read(
        nextAppointmentProvider.future,
      );

      expect(result!.location, '');
    });
  });

  group('nextAppointment elapsed-row skip', () {
    test('a head row whose endAt has already elapsed is skipped in favour of '
        'the next genuinely-upcoming row in the same page', () async {
      final Booking elapsed = _elapsedBooking('bk-elapsed');
      final Booking upcoming = _booking(id: 'bk-upcoming');
      final repo = _FakeBookingRepository(
        PageResponse<Booking>(
          items: <Booking>[elapsed, upcoming],
          page: 0,
          totalPages: 1,
          totalElements: 2,
        ),
      );
      final container = _container(repo);

      final NextAppointment? result = await container.read(
        nextAppointmentProvider.future,
      );

      expect(
        result!.id,
        'bk-upcoming',
        reason:
            'the elapsed row must be skipped client-side even though the '
            'server still reports it CONFIRMED',
      );
    });

    test('a page where every row has already elapsed resolves to null, not the '
        'stale head row — and does NOT over-fetch when totalElements says '
        'nothing more exists', () async {
      final repo = _FakeBookingRepository(
        PageResponse<Booking>(
          items: <Booking>[
            _elapsedBooking('bk-elapsed-1'),
            _elapsedBooking('bk-elapsed-2'),
          ],
          page: 0,
          totalPages: 1,
          totalElements: 2,
        ),
      );
      final container = _container(repo);

      final NextAppointment? result = await container.read(
        nextAppointmentProvider.future,
      );

      expect(result, isNull);
      expect(
        repo.callCount,
        1,
        reason:
            'totalElements (2) == items scanned (2) — no further page '
            'exists, so this is a genuine null and must not page-forward',
      );
    });

    test(
      'an empty page resolves to null (no upcoming bookings at all)',
      () async {
        final repo = _FakeBookingRepository(
          const PageResponse<Booking>(
            items: <Booking>[],
            page: 0,
            totalPages: 1,
            totalElements: 0,
          ),
        );
        final container = _container(repo);

        final NextAppointment? result = await container.read(
          nextAppointmentProvider.future,
        );

        expect(result, isNull);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Phase 225 production-bug regression: the `from`-window bound and the
  // bounded page-forward that replaced the old unconditional 5-row cap. This
  // is the exact scenario 1080+164+11 GREEN tests missed — a page where
  // EVERY row is elapsed but `totalElements` EXCEEDS the page size, with a
  // genuinely upcoming row beyond the first page.
  // ---------------------------------------------------------------------------
  group('nextAppointment from-window + bounded page-forward (Phase 225)', () {
    test(
      'first page all-elapsed with totalElements exceeding the page size '
      'pages forward and surfaces the real upcoming booking on page 1',
      () async {
        final Booking upcoming = _booking(id: 'bk-real-next');
        final repo =
            _FakeBookingRepository(
                const PageResponse<Booking>(
                  items: <Booking>[],
                  page: 0,
                  totalPages: 1,
                  totalElements: 0,
                ),
              )
              ..pagesByIndex = <int, PageResponse<Booking>>{
                0: PageResponse<Booking>(
                  items: <Booking>[
                    _elapsedBooking('bk-elapsed-1'),
                    _elapsedBooking('bk-elapsed-2'),
                    _elapsedBooking('bk-elapsed-3'),
                    _elapsedBooking('bk-elapsed-4'),
                    _elapsedBooking('bk-elapsed-5'),
                  ],
                  page: 0,
                  totalPages: 2,
                  totalElements: 7,
                ),
                1: PageResponse<Booking>(
                  items: <Booking>[_elapsedBooking('bk-elapsed-6'), upcoming],
                  page: 1,
                  totalPages: 2,
                  totalElements: 7,
                ),
              };
        final container = _container(repo);

        final NextAppointment? result = await container.read(
          nextAppointmentProvider.future,
        );

        expect(
          result?.id,
          'bk-real-next',
          reason:
              'this mirrors the live production defect: 7 total CONFIRMED '
              'rows, the first 6 all elapsed, the 7th genuinely upcoming — '
              'the old hard 5-row cap returned null here',
        );
        expect(repo.capturedPages, <int>[0, 1]);
      },
    );

    test('sends `from` on every call, carrying the EUROPE/KYIV calendar day '
        '(dateOnly(toBeauticaTime(now))) — never the device-local day nor the '
        'raw wall-clock instant', () async {
      // Superseded from its original (Phase 225) form: it used to assert
      // `dateOnly(DateTime.now())` (the device-local day), which is exactly
      // Finding 1's bug — this is the tautological test QA flagged as
      // unable to pin a device-ahead-of-Kyiv scenario at all. The
      // `clockProvider`-pinned tests in the "Kyiv-day boundary" group above
      // now own that regression coverage; this test keeps only the
      // production-default (no clock override, real wall clock) sanity
      // check, corrected to the right contract.
      final repo = _FakeBookingRepository(
        const PageResponse<Booking>(
          items: <Booking>[],
          page: 0,
          totalPages: 1,
          totalElements: 0,
        ),
      );
      final container = _container(repo);

      final DateTime beforeCall = dateOnly(toBeauticaTime(DateTime.now()));
      final NextAppointment? result = await container.read(
        nextAppointmentProvider.future,
      );
      final DateTime afterCall = dateOnly(toBeauticaTime(DateTime.now()));

      expect(result, isNull);
      expect(repo.callCount, 1);
      final DateTime? sentFrom = repo.capturedFrom;
      expect(sentFrom, isNotNull);
      // Tolerant of the test happening to straddle Kyiv midnight: `from`
      // must equal ONE of the two Kyiv calendar-day snapshots taken either
      // side of the call, and it must already be date-only (no time-of-day
      // component leaking onto the wire — `toApiDate` truncates, but the
      // domain value handed to the repository should already be clean).
      expect(sentFrom, anyOf(beforeCall, afterCall));
      expect(sentFrom, dateOnly(sentFrom!));
    });

    test('page-forward is bounded — an account where every page is elapsed '
        'never fetches beyond the hard cap', () async {
      PageResponse<Booking> allElapsedPage(int pageIndex) =>
          PageResponse<Booking>(
            items: <Booking>[
              _elapsedBooking('bk-elapsed-p$pageIndex-1'),
              _elapsedBooking('bk-elapsed-p$pageIndex-2'),
              _elapsedBooking('bk-elapsed-p$pageIndex-3'),
              _elapsedBooking('bk-elapsed-p$pageIndex-4'),
              _elapsedBooking('bk-elapsed-p$pageIndex-5'),
            ],
            page: pageIndex,
            totalPages: 20,
            // Deliberately far larger than any page budget could ever
            // drain, so the loop can ONLY stop via the hard cap — if the
            // cap were missing or wrong, this test would hang/over-fetch
            // rather than false-pass.
            totalElements: 1000,
          );
      final repo = _FakeBookingRepository(allElapsedPage(0))
        ..pagesByIndex = <int, PageResponse<Booking>>{
          0: allElapsedPage(0),
          1: allElapsedPage(1),
          2: allElapsedPage(2),
        };
      final container = _container(repo);

      final NextAppointment? result = await container.read(
        nextAppointmentProvider.future,
      );

      expect(result, isNull);
      expect(
        repo.capturedPages,
        <int>[0, 1, 2],
        reason:
            'exactly 3 pages (the hard cap) — a 4th call would have hit '
            'the fake\'s "no scripted response" StateError instead of '
            'quietly returning null, so this also proves there is no '
            'unbounded fan-out',
      );
      expect(repo.callCount, 3);
    });
  });

  // ---------------------------------------------------------------------------
  // Finding 1 (HIGH) regression: `today` must be the EUROPE/KYIV calendar
  // day, not the device-local day. A device-local mismatch narrows (not
  // merely widens) the `from` bound whenever the device sits AHEAD of Kyiv —
  // silently excluding a booking still due later that same Kyiv day. These
  // tests inject `now` via [clockProvider] (Finding 2 — the seam that makes
  // this boundary testable at all) rather than relying on the real wall
  // clock.
  //
  // Every fixture below is anchored to a FIXED absolute instant — either the
  // `.utc` constructor, or (for the AHEAD case, which needs a genuinely
  // positive-offset "device" zone to diverge from Kyiv) an explicit
  // `tz.TZDateTime` built against the IANA `Asia/Tokyo` location — never the
  // bare local `DateTime(...)` constructor. A bare local constructor's
  // underlying instant is resolved through the HOST PROCESS's own OS
  // timezone, so whether such a fixture actually diverges from Kyiv would
  // depend on which `TZ` the suite runs under — degenerate on the dev VM
  // (Europe/Kyiv) and, worse, on CI's `ubuntu-latest` runner (defaults to
  // UTC — see `.github/workflows/pr-validate.yml`), silently no-op'ing any
  // assertion gated on the divergence actually showing up. Anchoring each
  // fixture to an explicit zone/instant instead makes every assertion below
  // unconditional and true under any host `TZ` — `TZ=UTC`, `TZ=Europe/Kyiv`,
  // `TZ=Asia/Tokyo` all assert identically, and each test genuinely proves
  // its direction of the fix on every one of them, not just one.
  group('nextAppointment Kyiv-day boundary (Finding 1 — HIGH)', () {
    test(
      'device clock AHEAD of Kyiv (device-local date > Kyiv date): `from` is '
      'the Kyiv day, and a booking still due later that Kyiv day is surfaced',
      () async {
        // "Device" wall-clock reads 2026-08-02 05:00, anchored to the IANA
        // `Asia/Tokyo` location (UTC+9, no DST) rather than the host
        // process's own `TZ` — so the instant this represents, and its
        // divergence from Kyiv, is a property of the fixture, not of
        // whichever machine (or CI runner) executes the suite. That instant
        // is Kyiv (UTC+3 summer) 2026-08-01 23:00 — the device-local day
        // (Aug 2) is genuinely AHEAD of the Kyiv day (Aug 1), the exact
        // narrowing scenario Finding 1 closes.
        final DateTime deviceNow = tz.TZDateTime(
          tz.getLocation('Asia/Tokyo'),
          2026,
          8,
          2,
          5,
          0,
        );
        final DateTime kyivToday = dateOnly(toBeauticaTime(deviceNow));
        final DateTime deviceLocalToday = dateOnly(deviceNow);

        final Booking booking = _booking(id: 'bk-kyiv-ahead');
        final repo = _FakeBookingRepository(
          PageResponse<Booking>(
            items: <Booking>[booking],
            page: 0,
            totalPages: 1,
            totalElements: 1,
          ),
        );
        final container = _container(repo, now: () => deviceNow);

        final NextAppointment? result = await container.read(
          nextAppointmentProvider.future,
        );

        expect(result?.id, 'bk-kyiv-ahead');
        expect(
          repo.capturedFrom,
          kyivToday,
          reason:
              '`from` must be the Europe/Kyiv calendar day derived from the '
              'injected clock, never the raw device-local day.',
        );
        // The Tokyo anchor makes this divergence a property of the fixture,
        // not of the host TZ, so this is asserted unconditionally: the
        // device-local day is LATER than the correct Kyiv day, exactly the
        // narrowing direction Finding 1 fixes.
        expect(
          deviceLocalToday.isAfter(kyivToday),
          isTrue,
          reason:
              'the injected "device" sits ahead of Kyiv, so the pre-fix '
              'device-local derivation would have sent a `from` one day '
              'LATE, narrowing the window past this booking.',
        );
      },
    );

    test('device clock BEHIND Kyiv (device-local date < Kyiv date): no '
        'regression — `from` is still the Kyiv day and the upcoming booking '
        'still surfaces', () async {
      // Under `TZ=UTC` this instant is Kyiv (UTC+3 summer) 2026-08-02
      // 02:30 — device-local day (Aug 1) sits BEHIND the Kyiv day (Aug 2).
      final DateTime deviceNow = DateTime(2026, 8, 1, 23, 30);
      final DateTime kyivToday = dateOnly(toBeauticaTime(deviceNow));

      final Booking booking = _booking(id: 'bk-kyiv-behind');
      final repo = _FakeBookingRepository(
        PageResponse<Booking>(
          items: <Booking>[booking],
          page: 0,
          totalPages: 1,
          totalElements: 1,
        ),
      );
      final container = _container(repo, now: () => deviceNow);

      final NextAppointment? result = await container.read(
        nextAppointmentProvider.future,
      );

      expect(result?.id, 'bk-kyiv-behind');
      expect(repo.capturedFrom, kyivToday);
    });

    test('midnight-crossing in Kyiv itself: instants either side of Kyiv local '
        'midnight compute their OWN Kyiv day, one day apart', () async {
      // Kyiv local midnight (start of 2026-08-02) is 2026-08-01 21:00 UTC
      // (Kyiv summer = UTC+3). `.utc` fixtures make this fully
      // host-TZ-independent — it must hold under every `TZ` the suite runs
      // under.
      final DateTime justBeforeKyivMidnight = DateTime.utc(2026, 8, 1, 20, 59);
      final DateTime justAfterKyivMidnight = DateTime.utc(2026, 8, 1, 21, 1);

      final repoBefore = _FakeBookingRepository(
        const PageResponse<Booking>(
          items: <Booking>[],
          page: 0,
          totalPages: 1,
          totalElements: 0,
        ),
      );
      final containerBefore = _container(
        repoBefore,
        now: () => justBeforeKyivMidnight,
      );
      await containerBefore.read(nextAppointmentProvider.future);
      expect(repoBefore.capturedFrom, DateTime(2026, 8, 1));

      final repoAfter = _FakeBookingRepository(
        const PageResponse<Booking>(
          items: <Booking>[],
          page: 0,
          totalPages: 1,
          totalElements: 0,
        ),
      );
      final containerAfter = _container(
        repoAfter,
        now: () => justAfterKyivMidnight,
      );
      await containerAfter.read(nextAppointmentProvider.future);
      expect(repoAfter.capturedFrom, DateTime(2026, 8, 2));
    });
  });

  group('nextAppointment error propagation', () {
    test(
      'a repository failure propagates as this provider\'s AsyncError, '
      'exactly like clientProfile\'s unauthenticated-session contract',
      () async {
        final repo = _FakeBookingRepository(
          const PageResponse<Booking>(
            items: <Booking>[],
            page: 0,
            totalPages: 1,
            totalElements: 0,
          ),
        )..throwing = const UnauthorizedFailure();
        final container = ProviderContainer(
          retry: (_, _) => null,
          overrides: [bookingRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        await expectLater(
          container.read(nextAppointmentProvider.future),
          throwsA(isA<UnauthorizedFailure>()),
        );
      },
    );
  });
}
