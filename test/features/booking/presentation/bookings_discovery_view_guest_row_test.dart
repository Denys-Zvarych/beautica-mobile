// THE GUEST / STAFF-SOURCED BOOKING ROW — the coverage hole that let the
// walk-in feature ship untested end to end.
//
// WHY THIS FILE EXISTS
// --------------------
// A booking created by the master's own «Новий запис» wizard is `booking_source
// = STAFF`: no registered client account behind it. On the wire that means a
// row shaped UNLIKE every fixture the mobile suite had ever rendered —
//
//   • `clientId`        null  (backend V89 `chk_bookings_guest_fields`)
//   • `clientAvatarUrl` null
//   • `appointmentId`   null  (not part of a multi-service visit)
//   • `clientFirstName` / `clientLastName` SERVER-filled from the OTP-verified
//     `guestName` / `guestSurname`, and each independently nullable.
//
// Before this file, NO test in either repo had ever listed such a row: every
// mobile day-view fixture carried a `clientId`, and the backend's own
// `/bookings/me` coverage hardcodes `'LINK'` as the source. So the master
// could create a walk-in the app had never once been asked to display — and
// the day view is the first place they would look for it.
//
// WHAT IS PINNED
// --------------
// That the guest row renders through the SAME path a registered-client row
// does: the card, its key, its position on the timeline grid, the guest's
// name, and the avatar glyph fallback. Plus the degenerate case (`guest with
// no surname on file` → both name fields null) landing on the localised
// «Гість» label rather than a blank or a crash.
//
// Assertions go through `Key`s and `AppLocalizations`, never a hard-coded
// Cyrillic literal (`scripts/forbid_cyrillic_finder.sh`); the two `find.text`
// calls below interpolate fixture constants, so the literal in the source
// carries no Cyrillic code point.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/presentation/bookings_discovery_view.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

// ONE clock for both the fixture and the widget — `BookingsDiscoveryView`
// derives its day from `kyivToday(clockProvider)` and ignores `query.day`, so
// a fixture built off the host clock would land on a day the view never shows.
final DateTime _fixedNow = futureBookingStart();
final DateTime _day = kyivToday(() => _fixedNow);

DateTime _kyivAtUtc(int hour) =>
    tz.TZDateTime(beauticaZone, _day.year, _day.month, _day.day, hour).toUtc();

const String _guestFirst = 'Ірина';
const String _guestLast = 'Шевченко';
const String _serviceName = 'Манікюр';
const String _guestId = 'walkin-1';
const String _clientId = 'client-1';

/// A STAFF-sourced walk-in row: every client-account-derived field null.
Booking _guestRow({
  String id = _guestId,
  String? firstName = _guestFirst,
  String? lastName = _guestLast,
  int hour = 11,
}) {
  final DateTime start = _kyivAtUtc(hour);
  return Booking(
    id: id,
    masterId: 'master-1',
    masterFirstName: 'Оля',
    masterLastName: 'Коваль',
    masterType: 'INDEPENDENT_MASTER',
    // clientId, clientAvatarUrl and appointmentId are ALL absent — that
    // triple is what makes this a guest row rather than a styling choice.
    clientFirstName: firstName,
    clientLastName: lastName,
    serviceId: 'svc-1',
    serviceName: _serviceName,
    durationMinutes: 60,
    price: 500,
    startAt: start,
    endAt: start.add(const Duration(minutes: 60)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

/// The registered-client control — identical in every respect except that it
/// HAS an account behind it.
Booking _registeredRow() {
  final DateTime start = _kyivAtUtc(13);
  return Booking(
    id: 'registered-1',
    masterId: 'master-1',
    masterFirstName: 'Оля',
    masterLastName: 'Коваль',
    masterType: 'INDEPENDENT_MASTER',
    clientId: _clientId,
    clientFirstName: 'Олена',
    clientLastName: 'Ковальчук',
    serviceId: 'svc-1',
    serviceName: _serviceName,
    durationMinutes: 60,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 60)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

/// A RESOLVED working-hours verdict for [_day]. Local rather than shared —
/// seven test files already declare their own one-line `EffectiveScheduleNotifier`
/// double (`grep -rn 'extends EffectiveScheduleNotifier' test/`); there is no
/// shared harness to reuse and inventing one is out of scope here.
class _DataSchedule extends EffectiveScheduleNotifier {
  _DataSchedule(this._days);
  final List<EffectiveDay> _days;
  @override
  Future<List<EffectiveDay>> build(
    ScheduleScope scope,
    ScheduleRange range,
  ) async => _days;
}

/// 09:00–18:00 on [_day] — the guest row below starts at 11:00, comfortably
/// inside it, so anything that drops the row is the row's own shape and never
/// the window arithmetic.
Object _resolvedWorkingHours() => effectiveScheduleProvider.overrideWith(
  () => _DataSchedule(<EffectiveDay>[
    EffectiveDay(
      date: _day,
      source: EffectiveSource.template,
      intervals: <WorkInterval>[
        WorkInterval(
          start: const TimeOfDay(hour: 9, minute: 0),
          end: const TimeOfDay(hour: 18, minute: 0),
        ),
      ],
    ),
  ]),
);

void main() {
  setUpAll(() {
    initBeauticaTimeZones();
    registerFallbackValue(<BookingStatus>{});
    registerFallbackValue(BookingSort.oldest);
  });

  Future<void> pump(
    WidgetTester tester,
    List<Booking> rows, {
    // ADDITIVE (2026-08-20, audit cycle 2) — defaults reproduce the original
    // master-scope pump byte for byte, so every call site above is unaffected.
    // See the "salon-reuse branch" group at the bottom of this file.
    bool useScheduleWindow = false,
    bool showMasterFilter = false,
    Object? scheduleOverride,
  }) async {
    final repo = _MockBookingRepository();
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
      (_) async => PageResponse<Booking>(
        items: rows,
        page: 0,
        totalPages: 1,
        totalElements: rows.length,
      ),
    );

    await tester.pumpApp(
      BookingsDiscoveryView(
        query: BookingsDayQuery.of(day: _day),
        title: 'Мої записи',
        showMasterFilter: showMasterFilter,
        useScheduleWindow: useScheduleWindow,
        onAddWorkingHours: useScheduleWindow ? (DateTime _) {} : null,
        onBookingTap: (Booking _) {},
      ),
      overrides: <Object>[
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        bookingRepositoryProvider.overrideWithValue(repo),
        bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
        clockProvider.overrideWithValue(() => _fixedNow),
        ?scheduleOverride,
      ],
    );
    await tester.pumpUntilGone(
      find.byKey(const Key('master-bookings-skeleton')),
    );
  }

  testWidgets('a STAFF-sourced guest booking renders a card on the timeline '
      'grid — null clientId / avatar / appointmentId and all', (tester) async {
    await pump(tester, <Booking>[_guestRow()]);

    expect(
      find.byType(BookingsTimelineGrid),
      findsOneWidget,
      reason: 'the day must render the GRID, not an empty or error state',
    );
    expect(
      find.byKey(const Key('master-booking-card-$_guestId')),
      findsOneWidget,
      reason:
          'the walk-in the master just created is the row they came here to '
          'see; nothing in either repo had ever listed one before this test',
    );
    // Placed BY the grid, not merely present somewhere in the subtree — the
    // grid keys its own placements separately.
    expect(
      find.byKey(const ValueKey<String>('timeline-card-$_guestId')),
      findsOneWidget,
    );

    expect(find.byKey(const Key('master-bookings-empty')), findsNothing);
    expect(find.byKey(const Key('my_bookings_error')), findsNothing);

    // The server-filled guest name is what the master reads off the card.
    expect(find.text('$_guestFirst $_guestLast'), findsOneWidget);
    // Guest rows have no avatar URL, so the card falls back to its glyph
    // rather than attempting a network image (which would throw in a test).
    expect(find.byIcon(Icons.person_outlined), findsWidgets);
  });

  testWidgets('a guest row and a registered-client row list side by side on '
      'the same day', (tester) async {
    await pump(tester, <Booking>[_guestRow(), _registeredRow()]);

    expect(
      find.byKey(const Key('master-booking-card-$_guestId')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('master-booking-card-registered-1')),
      findsOneWidget,
      reason:
          'a guest row must not displace or suppress the ordinary rows around '
          'it — the day list is mixed in production from the first walk-in on',
    );
    expect(find.byKey(const Key('master-bookings-count')), findsOneWidget);
  });

  testWidgets('a guest with no name on file falls back to the localised '
      '«Гість» label, never a blank card', (tester) async {
    await pump(tester, <Booking>[_guestRow(firstName: null, lastName: null)]);

    final Finder card = find.byKey(const Key('master-booking-card-$_guestId'));
    expect(card, findsOneWidget);

    // `clientFirstName`/`clientLastName` are INDEPENDENTLY nullable on the
    // wire — the backend's `guestSurname` column is optional — so this is a
    // reachable row, not a defensive hypothetical.
    final AppLocalizations l10n = AppLocalizations.of(tester.element(card));
    expect(find.text(l10n.bookingDetailGuestClient), findsOneWidget);
  });

  // ══════════════════════════════════════════════════════════════════════
  // THE SALON-REUSE BRANCH (audit cycle 2, 2026-08-20 — MEDIUM gap)
  // ══════════════════════════════════════════════════════════════════════
  //
  // Everything above pumps the DEFAULT configuration: `useScheduleWindow:
  // false`, so `_Loaded.build` short-circuits at its first line
  // (`bookings_discovery_view.dart:1181`) and `state.items` reaches
  // `BookingsTimelineGrid` untouched. The reuse seam the same widget exposes
  // — the flag pair `showMasterFilter` / `useScheduleWindow` — routes the
  // SAME rows through a different composition: the `data:` arm resolves a
  // working-hours window and hands the grid `visibleBookingsFor(...)`, and the
  // header count switches from `state.totalElements` to the RENDERED set
  // (`bookings_discovery_view.dart:1274-1279`). A guest row had never once
  // been listed through that arm.
  //
  // Why it is not obviously safe: a STAFF walk-in is the one row shape whose
  // client-account fields are all null, and the window arm is the one arm
  // that re-derives the rendered list AND the count from a predicate. If that
  // predicate ever grew an account-shaped precondition, the master's own
  // walk-in would vanish from the list AND from the count together — a
  // perfectly self-consistent screen showing nothing, which is the hardest
  // possible failure to notice.
  //
  // `showMasterFilter: true` is carried alongside deliberately. It is a pure
  // no-op in `bookings_discovery_view.dart` today (declared at :281, read
  // nowhere), so it is NOT what makes these tests non-vacuous and no
  // assertion below rests on it — see `bookings_discovery_view_reuse_test
  // .dart`, which owns that flag's own contract. It is set here only so the
  // configuration this file exercises is the one the salon screen will
  // actually construct.
  //
  // MUTATION PROBE (M14) — with `&& b.clientId != null` appended to
  // `bookingsInsideScheduleWindow`'s predicate, both tests below go RED (no
  // card, count 0/«Немає записів»); restored, both are GREEN. So the
  // assertions are load-bearing on this arm, not merely satisfied by it.
  group('the schedule-window (salon-reuse) branch', () {
    testWidgets('a STAFF-sourced guest row renders AND is counted once the '
        'working-hours window resolves', (tester) async {
      await pump(
        tester,
        <Booking>[_guestRow()],
        useScheduleWindow: true,
        showMasterFilter: true,
        scheduleOverride: _resolvedWorkingHours(),
      );

      // Fixture sanity: a resolved INTERVAL day, not the gray "no working
      // hours" state — without this the geometry assertions below would be
      // vacuously satisfied by a screen with no grid at all.
      expect(
        find.byKey(const Key('master-bookings-no-schedule')),
        findsNothing,
      );
      expect(find.byType(BookingsTimelineGrid), findsOneWidget);

      expect(
        find.byKey(const Key('master-booking-card-$_guestId')),
        findsOneWidget,
        reason:
            'the walk-in must survive `visibleBookingsFor` — 11:00 sits '
            'inside the seeded 09:00–18:00 window, so the only thing that '
            'could drop it is its own accountless shape',
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-card-$_guestId')),
        findsOneWidget,
        reason: 'placed BY the grid, not merely present in the subtree',
      );

      // THE COUNT IS THE HALF THE OTHER ARM CANNOT TEST. On this arm the
      // header reads the RENDERED list, not `state.totalElements`, so a
      // guest row silently filtered out would take the count down with it and
      // leave the screen internally consistent while showing the master
      // nothing.
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(BookingsDiscoveryView)),
      );
      expect(find.text(l10n.masterBookingsCount(1)), findsOneWidget);

      expect(find.text('$_guestFirst $_guestLast'), findsOneWidget);
      expect(
        find.byIcon(Icons.person_outlined),
        findsWidgets,
        reason:
            'no `clientAvatarUrl`, so the card must fall back to its glyph '
            'rather than attempting a network image',
      );
    });

    testWidgets('a nameless guest still falls back to the localised «Гість» '
        'label on this branch too', (tester) async {
      await pump(
        tester,
        <Booking>[_guestRow(firstName: null, lastName: null)],
        useScheduleWindow: true,
        showMasterFilter: true,
        scheduleOverride: _resolvedWorkingHours(),
      );

      final Finder card = find.byKey(
        const Key('master-booking-card-$_guestId'),
      );
      expect(card, findsOneWidget);

      final AppLocalizations l10n = AppLocalizations.of(tester.element(card));
      expect(find.text(l10n.bookingDetailGuestClient), findsOneWidget);
      expect(find.text(l10n.masterBookingsCount(1)), findsOneWidget);
    });
  });
}
