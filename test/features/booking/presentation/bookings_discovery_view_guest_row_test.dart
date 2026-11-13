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

void main() {
  setUpAll(() {
    initBeauticaTimeZones();
    registerFallbackValue(<BookingStatus>{});
    registerFallbackValue(BookingSort.oldest);
  });

  Future<void> pump(
    WidgetTester tester,
    List<Booking> rows, {
    bool showMasterFilter = false,
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
        onBookingTap: (Booking _) {},
      ),
      overrides: <Object>[
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        bookingRepositoryProvider.overrideWithValue(repo),
        bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
        clockProvider.overrideWithValue(() => _fixedNow),
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
}
