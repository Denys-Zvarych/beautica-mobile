// Phase 225 — nextAppointmentProvider unit tests.
// Phase 228 — retired the bounded page-forward scan now that
// `GET /bookings/me` supports server-side `partition=UPCOMING` filtering;
// see the group doc comments below for what changed and why.
//
// The Home Hub's «Найближчий запис» card used to be a hardcoded stub
// (always null). It now derives from `BookingRepository.getMyBookings` —
// the SAME endpoint/request shape the «Мої записи» Майбутні tab issues
// (`BookingTab.upcoming.statuses` + `BookingSort.oldest`, page 0). These
// tests pin:
//   • the exact request shape sent to the repository — statuses/partition/
//     sort/page/size/from (Phase 228: `partition: BookingPartition.upcoming`
//     and `size: 1` replace the old 5-row peek + bounded page-forward);
//   • the provider returns `page.items.first` UNCHANGED — the Home Hub now
//     renders it through the SAME shared `BookingCard` widget «Мої записи»
//     uses (a later, USER-LOCKED decision), so there is no lossy
//     NextAppointment DTO projection here any more to unit-test a mapping
//     for;
//   • the single-request resolution of a production-shaped account (many
//     elapsed CONFIRMED rows the server excludes via `partition`, plus one
//     genuinely upcoming row);
//   • an empty page resolves to null;
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
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_partition.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_tab.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
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

  final PageResponse<Booking> _page;

  /// The Object? failure to throw instead of returning [_page], or null to
  /// return normally.
  Object? throwing;

  // Captured call args — asserted by the "request shape" test.
  Iterable<BookingStatus>? capturedStatuses;
  BookingPartition? capturedPartition;
  BookingSort? capturedSort;
  int? capturedPage;
  int? capturedSize;
  DateTime? capturedFrom;
  int callCount = 0;

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required Iterable<BookingStatus> statuses,
    required int page,
    int size = kBookingsPageSize,
    BookingSort? sort,
    Iterable<String>? serviceIds,
    DateTime? from,
    DateTime? to,
    BookingPartition? partition,
    CancelToken? cancelToken,
  }) async {
    callCount++;
    capturedStatuses = statuses;
    capturedPartition = partition;
    capturedSort = sort;
    capturedPage = page;
    capturedSize = size;
    capturedFrom = from;
    final Object? f = throwing;
    if (f != null) throw f;
    return _page;
  }

  @override
  Future<Booking> createBooking(CreateBookingRequest req) =>
      throw UnimplementedError('not used by nextAppointmentProvider');

  @override
  Future<Appointment> createMasterBooking(
    String masterId,
    CreateMasterBookingRequest request,
  ) => throw UnimplementedError('not used by nextAppointmentProvider');

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

/// mobile-qa Phase 228 audit finding: [_FakeBookingRepository] above returns
/// whatever page it was constructed with regardless of what args the
/// notifier actually sends — deliberately, per its own group-level doc
/// comment, because the REAL server-side-filtering proof lives in
/// `client_home_hub_flow_test.dart`'s Phase 228 flow (a genuine
/// partition-filtering fake there, `FakeBackend._partitionOf` +
/// `backendSupportsPartition`). That means the "production-shaped account"
/// test below this class, taken alone, would keep passing even if a future
/// regression silently stopped sending `partition` on the request — it was
/// revert-proven to do exactly that during this audit.
///
/// This fake closes that unit-tier gap cheaply, without re-implementing a
/// whole in-memory backend: its response DEPENDS on the captured `partition`
/// value — [upcoming] only when the call actually carried
/// `BookingPartition.upcoming`, [elapsed] otherwise (covers both "partition
/// omitted" and "wrong partition value" regressions). A test built on this
/// fake is the unit-tier half of the phase doc's "Sanity-check RED" —
/// the cross-the-wire half is `client_home_hub_flow_test.dart`'s Test 4c.
class _PartitionSensitiveFakeBookingRepository implements BookingRepository {
  _PartitionSensitiveFakeBookingRepository({
    required this.upcoming,
    required this.elapsed,
  });

  final Booking upcoming;
  final Booking elapsed;
  int callCount = 0;
  BookingPartition? capturedPartition;

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required Iterable<BookingStatus> statuses,
    required int page,
    int size = kBookingsPageSize,
    BookingSort? sort,
    Iterable<String>? serviceIds,
    DateTime? from,
    DateTime? to,
    BookingPartition? partition,
    CancelToken? cancelToken,
  }) async {
    callCount++;
    capturedPartition = partition;
    final Booking chosen = partition == BookingPartition.upcoming
        ? upcoming
        : elapsed;
    return PageResponse<Booking>(
      items: <Booking>[chosen],
      page: 0,
      totalPages: 1,
      totalElements: 1,
    );
  }

  @override
  Future<Booking> createBooking(CreateBookingRequest req) =>
      throw UnimplementedError('not used by nextAppointmentProvider');

  @override
  Future<Appointment> createMasterBooking(
    String masterId,
    CreateMasterBookingRequest request,
  ) => throw UnimplementedError('not used by nextAppointmentProvider');

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

/// Builds a [ProviderContainer] wired to [repo]. When [now] is supplied it
/// overrides [clockProvider] so the provider's "today" is pinned to a fixed
/// instant instead of the real wall clock — required for every test in the
/// 'Kyiv-day boundary' group, since [dateOnly]/[toBeauticaTime] are only
/// interestingly exercised near a calendar-day boundary.
ProviderContainer _container(
  BookingRepository repo, {
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
    test(
      'issues ONE getMyBookings call with BookingTab.upcoming.statuses, '
      'BookingPartition.upcoming, BookingSort.oldest, page 0, size 1, and '
      '`from` pinned to the Europe/Kyiv day (the "Kyiv-day boundary" group '
      'below exercises the narrowing-bug regression this pins the shape of)',
      () async {
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
          reason:
              'must issue exactly one request — Phase 228 retired the '
              'bounded page-forward scan; page 0 row 0 is the whole answer '
              'now that the server filters by partition',
        );
        expect(repo.capturedStatuses, BookingTab.upcoming.statuses);
        expect(
          repo.capturedPartition,
          BookingPartition.upcoming,
          reason:
              'partition must be sent — the Phase 228 headline behaviour '
              'change; omitting it would silently regress to the pre-228 '
              'status-only scan this phase retired',
        );
        expect(
          repo.capturedPartition?.wireValue,
          'UPCOMING',
          reason:
              'asserts the WIRE STRING, not just the enum member — a '
              'wireValue swap on BookingPartition would pass the enum '
              'assertion above and still send the wrong filter',
        );
        expect(repo.capturedSort, BookingSort.oldest);
        expect(repo.capturedPage, 0);
        expect(
          repo.capturedSize,
          1,
          reason:
              'the server has already sorted and filtered by partition — '
              'the first row of page 0 IS the answer, so there is nothing '
              'left to peek a wider page for',
        );
        expect(
          repo.capturedFrom,
          dateOnly(toBeauticaTime(fixedNow)),
          reason:
              '`from` is the Europe/Kyiv calendar day derived from the '
              'injected clock — never the device-local day. It stays even '
              'though `partition` already excludes elapsed rows: `from` is '
              'day-granular, `partition` is instant-granular, and keeping '
              '`from` costs nothing while bounding the query for a '
              'long-history account.',
        );
      },
    );

    test('sends `from` on every call, carrying the EUROPE/KYIV calendar day '
        '(dateOnly(toBeauticaTime(now))) — never the device-local day nor the '
        'raw wall-clock instant — against the real (unpinned) production '
        'clock', () async {
      final repo = _FakeBookingRepository(
        const PageResponse<Booking>(
          items: <Booking>[],
          page: 0,
          totalPages: 1,
          totalElements: 0,
        ),
      );
      final container = _container(repo);

      final DateTime beforeCall = kyivToday(DateTime.now);
      final Booking? result = await container.read(
        nextAppointmentProvider.future,
      );
      final DateTime afterCall = kyivToday(DateTime.now);

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
  });

  // Phase [BookingCard-cutover] — the provider used to map `page.items.first`
  // onto a lean `NextAppointment` DTO (date/time labels, a composed
  // `location` fallback, master initials, ...). It now returns the fetched
  // [Booking] UNCHANGED (see `home_hub_notifier.dart`'s doc): the Home Hub
  // renders it through the SAME shared `BookingCard` widget «Мої записи»
  // uses (a USER-LOCKED decision), so any address-composition /
  // initials-derivation behaviour lives on `Booking`'s own extension getters
  // (`BookingDisplayX` — see `booking_display_x_test.dart`), not here. This
  // group only pins the pass-through contract: whatever the repository hands
  // back as `page.items.first` is exactly what this provider resolves to.
  group('nextAppointment pass-through', () {
    test(
      'resolves to the exact Booking fetched as page.items.first, unchanged',
      () async {
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

        final Booking? result = await container.read(
          nextAppointmentProvider.future,
        );

        expect(
          result,
          booking,
          reason:
              '[Booking] is a freezed value type — this must be the SAME '
              'booking, field for field, as what the repository returned; '
              'no DTO mapping happens in between any more.',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Phase 228: server-side `partition=UPCOMING` retires the Phase 225 bounded
  // page-forward scan. [_FakeBookingRepository] — unlike a real HTTP fake —
  // hands back whatever page a test scripts, so it stands in for the SERVER
  // already having applied `partition=UPCOMING` before responding: an
  // account can still hold a pile of elapsed CONFIRMED rows, but partition
  // filtering means none of them are IN the response at all — only the
  // genuinely upcoming row is, from ONE request.
  // `client_home_hub_flow_test.dart`'s Phase 228 regression test proves this
  // against a REAL partition-filtering fake backend over the actual HTTP
  // round trip; this unit test only proves the provider's own request shape
  // and single-call resolution.
  // ---------------------------------------------------------------------------
  group('nextAppointment single-request partition cutover (Phase 228)', () {
    test('a production-shaped account — 6 elapsed CONFIRMED rows the server '
        'excludes via partition=UPCOMING, plus 1 genuinely upcoming row — '
        'resolves the upcoming row from ONE request (the pre-228 provider '
        'needed 2 pages for this exact shape — the live production defect '
        'Phase 225 fixed with a bounded page-forward scan; Phase 228 removes '
        'the need for the scan entirely)', () async {
      final Booking upcoming = _booking(id: 'bk-real-next');
      // The 6 elapsed rows exist on the account but never reach the
      // client: `partition=UPCOMING` excludes them server-side, so the
      // fake — playing the role of an already-filtered server — hands
      // back ONLY the genuinely upcoming row.
      final repo = _FakeBookingRepository(
        PageResponse<Booking>(
          items: <Booking>[upcoming],
          page: 0,
          totalPages: 1,
          totalElements: 1,
        ),
      );
      final container = _container(repo);

      final Booking? result = await container.read(
        nextAppointmentProvider.future,
      );

      expect(
        result?.id,
        'bk-real-next',
        reason:
            'this mirrors the live production defect Phase 225 fixed — 7 '
            'total CONFIRMED rows, 6 elapsed, 1 genuinely upcoming — but '
            'now resolved by server-side filtering rather than a '
            'client-side scan',
      );
      expect(
        repo.callCount,
        1,
        reason:
            'exactly one request — the old code needed a 2nd page for '
            'this exact fixture shape (5-row peek, 7 total elements); '
            'partition filtering means there is nothing left to page '
            'forward through',
      );
    });

    // mobile-qa Phase 228 audit finding: the "production-shaped account"
    // test above passes purely on `_FakeBookingRepository` handing back a
    // hand-picked page — it was revert-proven during this audit to keep
    // passing even with `partition` entirely removed from the request (that
    // fake ignores what it is asked, by design; see its group-level doc
    // comment). This test closes that unit-tier gap with a fake whose
    // response genuinely depends on the captured `partition` value, so it
    // fails if a future change silently drops or corrupts the parameter —
    // without re-implementing a whole in-memory backend (that full
    // cross-the-wire proof stays in `client_home_hub_flow_test.dart`'s Test
    // 4c, which this audit also revert-proved).
    test('resolving the upcoming booking genuinely depends on `partition: '
        'BookingPartition.upcoming` reaching the repository call — a fake '
        'that answers differently depending on the captured partition value '
        'would surface the stale elapsed row instead if partition were '
        'dropped', () async {
      final Booking upcoming = _booking(id: 'bk-real-next');
      final Booking staleElapsed = _booking(
        id: 'bk-stale-elapsed',
        aheadOfNow: const Duration(days: -2),
      );
      final repo = _PartitionSensitiveFakeBookingRepository(
        upcoming: upcoming,
        elapsed: staleElapsed,
      );
      final container = _container(repo);

      final Booking? result = await container.read(
        nextAppointmentProvider.future,
      );

      expect(
        result?.id,
        'bk-real-next',
        reason:
            'if `partition` were dropped or wrong, this fake would hand '
            'back `bk-stale-elapsed` instead — this assertion is the '
            'unit-tier tripwire for that regression',
      );
      expect(repo.callCount, 1);
      expect(repo.capturedPartition, BookingPartition.upcoming);
    });

    test('an account with zero upcoming bookings resolves to null (empty '
        'card), from one request', () async {
      final repo = _FakeBookingRepository(
        const PageResponse<Booking>(
          items: <Booking>[],
          page: 0,
          totalPages: 1,
          totalElements: 0,
        ),
      );
      final container = _container(repo);

      final Booking? result = await container.read(
        nextAppointmentProvider.future,
      );

      expect(result, isNull);
      expect(repo.callCount, 1);
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
  //
  // Phase 228: this group stays UNEDITED — `partition` narrows WHICH rows
  // come back, not the `from`/Kyiv-day derivation these tests pin, and the
  // fake's loose (no-matcher) `getMyBookings` accepts the new `partition`
  // argument transparently.
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

        final Booking? result = await container.read(
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
      // "Device" wall-clock reads 2026-08-01 23:30, anchored explicitly to
      // UTC (`DateTime.utc`, not a bare local constructor) — so the instant
      // this represents, and its divergence from Kyiv, is a property of the
      // fixture, not of whichever machine (or CI runner) executes the suite.
      // A bare local `DateTime(...)` here would resolve its underlying
      // instant through the HOST PROCESS's own `TZ`: on the dev VM
      // (`TZ=Europe/Kyiv`) the instant IS already Kyiv wall-clock, so
      // `kyivToday` below trivially equals the device-local day and the
      // divergence this test exists to guard never actually fires — vacuous
      // on the dev VM, only accidentally discriminating under CI's
      // `TZ=UTC` runner. The explicit `.utc()` anchor fixes the instant to
      // 2026-08-01 23:30 UTC unconditionally, which is Kyiv (UTC+3 summer)
      // 2026-08-02 02:30 — device-local day (Aug 1) sits BEHIND the Kyiv day
      // (Aug 2) on every host `TZ` the suite runs under.
      final DateTime deviceNow = DateTime.utc(2026, 8, 1, 23, 30);
      final DateTime kyivToday = dateOnly(toBeauticaTime(deviceNow));
      final DateTime deviceLocalToday = dateOnly(deviceNow);

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

      final Booking? result = await container.read(
        nextAppointmentProvider.future,
      );

      expect(result?.id, 'bk-kyiv-behind');
      expect(
        repo.capturedFrom,
        kyivToday,
        reason:
            '`from` must be the Europe/Kyiv calendar day derived from the '
            'injected clock, never the raw device-local day.',
      );
      // The UTC anchor makes this divergence a property of the fixture, not
      // of the host TZ, so this is asserted unconditionally: the injected
      // "device" sits behind Kyiv, so a regression reading the raw
      // device-local day instead of the Kyiv derivation would send a `from`
      // one day EARLY here — a no-op for this particular booking (it still
      // surfaces), but the wrong value nonetheless, which is what
      // `repo.capturedFrom` above actually pins.
      expect(
        deviceLocalToday.isBefore(kyivToday),
        isTrue,
        reason:
            'the injected "device" sits behind Kyiv, so the pre-fix '
            'device-local derivation would have sent a `from` one day '
            'EARLY relative to the correct Kyiv day.',
      );
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
