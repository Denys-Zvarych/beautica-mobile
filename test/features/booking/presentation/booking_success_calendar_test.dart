// QA (track 14.x "Додати в календар") — the THIRD calendar call site.
//
// `add_to_calendar_test.dart` covers the shared [addBookingToCalendar] helper
// and `booking_detail_interactions_test.dart` covers «Деталі запису»'s call
// site. The BOOKING-SUCCESS screen is the remaining, structurally DISTINCT one:
// its `_onAddToCalendar` maps its OWN domain shapes into the Event, and none of
// that mapping is exercised elsewhere —
//   • provider    = "<master.firstName> <master.lastName>" (NOT Booking.masterName);
//   • location    = formatStreetCityLine(master.street/buildingNo/city);
//   • start       = the FIRST appointment's start;
//   • end         = first.start + first.service.durationMinutes (COMPUTED here —
//                   the success screen has no Booking.endAt to read).
//
// A multi-service success recap seeds ONLY the first appointment (one OS INSERT
// sheet per invocation — see the screen's `_onAddToCalendar` doc), so the
// fixture books TWO services with different durations to pin that the mapping
// reads the FIRST, not the last / longest / summed.
//
// The `add_2_calendar` plugin is mocked at the CHANNEL boundary (the same
// `setMockMethodCallHandler('add_2_calendar', …)` seam the two sibling suites
// use) — no real OS sheet ever opens. Copy is asserted through l10n keys and
// the location through the real `formatStreetCityLine`, never a raw Cyrillic
// literal, so the assertions stay in lockstep with the source.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/domain/booking_success_args.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/street_city_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

// The add_2_calendar plugin's platform boundary — intercepted so tapping
// «Додати в календар» never opens a real OS calendar sheet.
const MethodChannel _kCalendarChannel = MethodChannel('add_2_calendar');

// A solo master with a full home address AND a private location note. The note
// must NEVER ride into the calendar Event (only street/buildingNo/city do).
const Master _kMaster = Master(
  id: 'm1',
  firstName: 'Марія',
  lastName: 'Іванюк',
  city: 'Львів',
  street: 'вул. Городоцька',
  buildingNo: '12',
  locationNote: 'кв. 3, домашня адреса — СЕКРЕТ',
  avgRating: 4.9,
  reviewCount: 20,
  type: MasterType.independentMaster,
);

// FIRST appointment (the one the single calendar button seeds): 90 min.
const MasterService _kFirstService = MasterService(
  id: 's1',
  serviceDefId: 'def-1',
  name: 'Манікюр з покриттям',
  durationMinutes: 90,
  priceMin: 650,
  priceDisplay: '650 ₴',
  category: 'MANICURE',
);

// SECOND appointment: a DIFFERENT duration + later start, so the test can prove
// the mapping reads the first appointment, not the last / longest.
const MasterService _kSecondService = MasterService(
  id: 's2',
  serviceDefId: 'def-2',
  name: 'Педикюр',
  durationMinutes: 45,
  priceMin: 550,
  priceDisplay: '550 ₴',
  category: 'PEDICURE',
);

final DateTime _kFirstStart = DateTime.utc(2026, 7, 20, 15);
final DateTime _kSecondStart = DateTime.utc(2026, 7, 21, 11);

BookingSuccessArgs _args() => BookingSuccessArgs(
  master: _kMaster,
  appointments: <BookingSuccessAppointment>[
    BookingSuccessAppointment(service: _kFirstService, start: _kFirstStart),
    BookingSuccessAppointment(service: _kSecondService, start: _kSecondStart),
  ],
);

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(BookingSuccessScreen)));

Future<void> _pumpSuccess(WidgetTester tester) async {
  await tester.pumpApp(
    BookingSuccessScreen(args: _args()),
    overrides: <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
    ],
  );
  await tester.pumpAndSettle();
}

void main() {
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kCalendarChannel, (MethodCall call) async {
          calls.add(call);
          return true; // pretend a calendar app opened
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kCalendarChannel, null);
  });

  group('booking success — «Додати в календар»', () {
    testWidgets(
      'invokes add2Cal with the service·master title, the formatStreetCityLine '
      'location, the FIRST appointment start and the COMPUTED end '
      '(start + service.durationMinutes)',
      (tester) async {
        await _pumpSuccess(tester);
        final AppLocalizations l10n = _l10n(tester);

        final Finder calendar = find.byKey(const Key('booking-add-calendar'));
        expect(calendar, findsOneWidget);
        await tester.ensureVisible(calendar);
        await tester.pumpAndSettle();
        await tester.tap(calendar);
        await tester.pumpAndSettle();

        expect(calls, hasLength(1), reason: 'add2Cal must have fired once');
        expect(calls.single.method, 'add2Cal');
        final Map<Object?, Object?> args =
            calls.single.arguments as Map<Object?, Object?>;

        // Title: service · "<firstName> <lastName>" — the success screen builds
        // the provider from the Master, not from a Booking.masterName.
        expect(
          args['title'],
          l10n.bookingCalendarEventTitle(
            _kFirstService.name,
            '${_kMaster.firstName} ${_kMaster.lastName}',
          ),
        );

        // Location: the SAME street/buildingNo/city join the recap card renders.
        expect(
          args['location'],
          formatStreetCityLine(
            street: _kMaster.street,
            buildingNo: _kMaster.buildingNo,
            city: _kMaster.city,
          ),
        );

        // Start = FIRST appointment; end = start + FIRST service's duration
        // (90 min) — not the second appointment's, not summed.
        expect(args['startDate'], _kFirstStart.millisecondsSinceEpoch);
        expect(
          args['endDate'],
          _kFirstStart
              .add(Duration(minutes: _kFirstService.durationMinutes))
              .millisecondsSinceEpoch,
        );
        expect(
          args['endDate'],
          isNot(_kSecondStart.millisecondsSinceEpoch),
          reason: 'the calendar event must map the FIRST appointment',
        );

        // Success path: the OS sheet "opened" — no error SnackBar.
        expect(find.text(l10n.bookingAddToCalendarError), findsNothing);
      },
    );

    testWidgets(
      'the master locationNote (home-address PII) never rides into the Event; '
      'desc stays null',
      (tester) async {
        await _pumpSuccess(tester);

        final Finder calendar = find.byKey(const Key('booking-add-calendar'));
        await tester.ensureVisible(calendar);
        await tester.pumpAndSettle();
        await tester.tap(calendar);
        await tester.pumpAndSettle();

        final Map<Object?, Object?> args =
            calls.single.arguments as Map<Object?, Object?>;
        expect(
          args['desc'],
          isNull,
          reason: 'no description field is populated',
        );
        final String payload = args.values.map((Object? v) => '$v').join('|');
        expect(
          payload.contains(_kMaster.locationNote!),
          isFalse,
          reason:
              'the private location note must not leak into any Event field',
        );
      },
    );
  });
}
