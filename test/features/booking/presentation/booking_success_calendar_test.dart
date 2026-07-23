// MO-3 (single-visit «Додати в календар») — the booking-success calendar call
// site.
//
// `add_to_calendar_test.dart` covers the shared [addBookingToCalendar] helper
// and `booking_detail_interactions_test.dart` covers «Деталі запису»'s call
// site. The BOOKING-SUCCESS screen is the remaining, structurally DISTINCT one:
// its `_onAddToCalendar` maps the WHOLE visit into ONE Event —
//   • provider    = "<master.firstName> <master.lastName>" (NOT Booking.masterName);
//   • location    = formatStreetCityLine(master.street/buildingNo/city);
//   • start       = the visit start;
//   • end         = start + the SUMMED duration of every service in the visit
//                   (COMPUTED here — the success screen has no Booking.endAt);
//   • title/desc  = the joined service label + the visit total price.
//
// ONE BUTTON FOR THE WHOLE VISIT (the MO-3 model): the services are a single
// back-to-back arrival, so the recap carries ONE `CalendarButton`
// (keyed `booking-success-add-calendar`) exporting one event that spans the
// whole visit — not one button/event per service.
//
// FAILURE PATH + GUARD RELEASE: `_calendarInFlight` is cleared in a `finally`,
// so a FAILED export must leave the button usable (the screen is a dead end —
// `PopScope(canPop: false)`). Both native failure shapes are driven from the
// channel (a thrown `PlatformException` and a plain `false` return).
//
// The `add_2_calendar` plugin is mocked at the CHANNEL boundary — no real OS
// sheet ever opens. Copy is asserted through l10n keys and the location through
// the real `formatStreetCityLine`, never a raw Cyrillic literal.

import 'dart:async';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/domain/booking_success_args.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/calendar_button.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/street_city_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

const MethodChannel _kCalendarChannel = MethodChannel('add_2_calendar');

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

const MasterService _kFirstService = MasterService(
  id: 's1',
  serviceDefId: 'def-1',
  name: 'Манікюр з покриттям',
  durationMinutes: 90,
  priceMin: 650,
  priceDisplay: '650 ₴',
  category: 'MANICURE',
);

const MasterService _kSecondService = MasterService(
  id: 's2',
  serviceDefId: 'def-2',
  name: 'Педикюр',
  durationMinutes: 45,
  priceMin: 550,
  priceDisplay: '550 ₴',
  category: 'PEDICURE',
);

// Summed visit duration: 90 + 45 = 135 min.
const int _kSummedMinutes = 135;

final DateTime _kStart = futureBookingStart();

const Key _kCalendarKey = Key('booking-success-add-calendar');

BookingSuccessArgs _args({List<MasterService>? services}) => BookingSuccessArgs(
  master: _kMaster,
  services: services ?? const <MasterService>[_kFirstService, _kSecondService],
  startAt: _kStart,
);

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(BookingSuccessScreen)));

Future<void> _pumpSuccess(
  WidgetTester tester, {
  BookingSuccessArgs? args,
}) async {
  await tester.pumpApp(
    BookingSuccessScreen(args: args ?? _args()),
    overrides: <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
    ],
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final Finder button = find.byKey(key);
  expect(button, findsOneWidget);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _dismissErrorSnackBar(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  final Finder snack = find.text(l10n.bookingAddToCalendarError);
  expect(snack, findsOneWidget);
  await tester.pumpUntilGone(snack);
}

Map<Object?, Object?> _argsOf(List<MethodCall> calls) {
  expect(calls, hasLength(1));
  return calls.single.arguments as Map<Object?, Object?>;
}

void main() {
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kCalendarChannel, (MethodCall call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kCalendarChannel, null);
  });

  group('booking success — «Додати в календар» (single visit)', () {
    testWidgets('renders ONE visit-level calendar button', (tester) async {
      await _pumpSuccess(tester);

      expect(find.byType(CalendarButton), findsOneWidget);
      expect(find.byKey(_kCalendarKey), findsOneWidget);
      // The retired per-service pill keys must not reappear.
      expect(find.byKey(const Key('booking-add-calendar')), findsNothing);
    });

    testWidgets('invokes add2Cal ONCE with the joined-service title, the '
        'formatStreetCityLine location, the visit start and the COMPUTED end '
        '(start + summed duration of all services)', (tester) async {
      await _pumpSuccess(tester);
      final AppLocalizations l10n = _l10n(tester);

      await _tap(tester, _kCalendarKey);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'add2Cal');
      final Map<Object?, Object?> args =
          calls.single.arguments as Map<Object?, Object?>;

      final String serviceLabel =
          '${_kFirstService.name}, ${_kSecondService.name}';
      final String provider = '${_kMaster.firstName} ${_kMaster.lastName}';
      expect(
        args['title'],
        l10n.bookingCalendarEventTitle(serviceLabel, provider),
      );
      expect(
        args['location'],
        formatStreetCityLine(
          street: _kMaster.street,
          buildingNo: _kMaster.buildingNo,
          city: _kMaster.city,
        ),
      );
      // Start = the visit start; end = start + the SUMMED duration (135 min).
      expect(args['startDate'], _kStart.millisecondsSinceEpoch);
      expect(
        args['endDate'],
        _kStart
            .add(const Duration(minutes: _kSummedMinutes))
            .millisecondsSinceEpoch,
      );
      expect(find.text(l10n.bookingAddToCalendarError), findsNothing);
    });

    testWidgets(
      'the Event description carries the STRUCTURED facts (every service, '
      'master, date-time, address, total price, status) yet the master '
      'locationNote (home-address PII) never rides into it',
      (tester) async {
        await _pumpSuccess(tester);
        final AppLocalizations l10n = _l10n(tester);

        await _tap(tester, _kCalendarKey);

        final Map<Object?, Object?> args =
            calls.single.arguments as Map<Object?, Object?>;
        final String desc = args['desc'] as String;
        expect(desc, isNotEmpty);
        for (final String label in <String>[
          l10n.bookingCalendarNoteService,
          l10n.bookingCalendarNoteMaster,
          l10n.bookingCalendarNoteDateTime,
          l10n.bookingCalendarNoteAddress,
          l10n.bookingCalendarNotePrice,
          l10n.bookingCalendarNoteStatus,
        ]) {
          expect(desc.contains(label), isTrue, reason: 'missing «$label» line');
        }
        // Both services appear in the visit description.
        expect(desc.contains(_kFirstService.name), isTrue);
        expect(desc.contains(_kSecondService.name), isTrue);
        // The visit TOTAL price (650 + 550 = 1200), not a single service's.
        expect(desc.contains('1200'), isTrue);
        expect(desc.contains(l10n.bookingStatusConfirmed), isTrue);

        // PRIVACY: the private location note must not leak into ANY Event field.
        final String payload = args.values.map((Object? v) => '$v').join('|');
        expect(payload.contains(_kMaster.locationNote!), isFalse);
      },
    );

    testWidgets(
      'a double-tap while the first INSERT is in flight is coalesced — never '
      'two stacked platform intents — and the guard releases on resolve',
      (tester) async {
        final Completer<bool> gate = Completer<bool>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_kCalendarChannel, (MethodCall call) {
              calls.add(call);
              return gate.future;
            });

        await _pumpSuccess(tester);

        await tester.ensureVisible(find.byKey(_kCalendarKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_kCalendarKey));
        await tester.pump();
        // Second tap while the first is still pending — dropped by the guard.
        await tester.tap(find.byKey(_kCalendarKey));
        await tester.pump();

        expect(calls, hasLength(1));

        gate.complete(true);
        await tester.pumpAndSettle();

        await _tap(tester, _kCalendarKey);
        expect(calls, hasLength(2), reason: 'the guard released after resolve');
      },
    );

    testWidgets(
      'a FAILED export (PlatformException) surfaces the error SnackBar AND '
      'releases the guard — a repeat tap re-exports',
      (tester) async {
        bool failNext = true;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_kCalendarChannel, (
              MethodCall call,
            ) async {
              calls.add(call);
              if (failNext) {
                failNext = false;
                throw PlatformException(code: 'no_activity');
              }
              return true;
            });

        await _pumpSuccess(tester);
        final AppLocalizations l10n = _l10n(tester);

        await _tap(tester, _kCalendarKey);
        expect(calls, hasLength(1));
        await _dismissErrorSnackBar(tester, l10n);

        calls.clear();
        await _tap(tester, _kCalendarKey);
        expect(_argsOf(calls)['startDate'], _kStart.millisecondsSinceEpoch);
        expect(find.text(l10n.bookingAddToCalendarError), findsNothing);
      },
    );

    testWidgets(
      'the plugin answering FALSE (no calendar app) is a failure too — '
      'SnackBar shown, guard released, a repeat tap re-exports',
      (tester) async {
        bool refuseNext = true;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_kCalendarChannel, (
              MethodCall call,
            ) async {
              calls.add(call);
              if (refuseNext) {
                refuseNext = false;
                return false;
              }
              return true;
            });

        await _pumpSuccess(tester);
        final AppLocalizations l10n = _l10n(tester);

        await _tap(tester, _kCalendarKey);
        expect(calls, hasLength(1));
        await _dismissErrorSnackBar(tester, l10n);

        calls.clear();
        await _tap(tester, _kCalendarKey);
        expect(_argsOf(calls)['startDate'], _kStart.millisecondsSinceEpoch);
      },
    );

    testWidgets(
      'a SINGLE-service visit still gets the one visit-level button spanning '
      'just that service',
      (tester) async {
        await _pumpSuccess(
          tester,
          args: _args(services: const <MasterService>[_kFirstService]),
        );

        expect(find.byType(CalendarButton), findsOneWidget);
        await _tap(tester, _kCalendarKey);
        final Map<Object?, Object?> args = _argsOf(calls);
        expect(args['startDate'], _kStart.millisecondsSinceEpoch);
        expect(
          args['endDate'],
          _kStart
              .add(Duration(minutes: _kFirstService.durationMinutes))
              .millisecondsSinceEpoch,
        );
      },
    );

    // STRESS SIZES: 320dp @ 2.0 and 400dp @ 2.0 — the recap must not overflow.
    for (final (double width, double scale) in <(double, double)>[
      (320, 2.0),
      (400, 2.0),
    ]) {
      testWidgets(
        'the visit recap lays out at ${width.toInt()}dp / $scale× text — the '
        'pill hugs its label instead of overflowing its card',
        (tester) async {
          await tester.pumpApp(
            BookingSuccessScreen(args: _args()),
            overrides: <Object>[
              screenProtectionProvider.overrideWithValue(
                _NoOpScreenProtection(),
              ),
            ],
            width: width,
            textScaleFactor: scale,
          );
          await tester.pumpAndSettle();

          final Finder pill = find.byKey(_kCalendarKey);
          expect(pill, findsOneWidget);
          expect(tester.getSize(pill).width, lessThanOrEqualTo(width));
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
