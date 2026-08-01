// QA (track 14.x "Додати в календар") — home-hub calendar wiring.
//
// The next-appointment card exposes TWO affordances (Google / Apple), but both
// route to the SAME `_addNextAppointmentToCalendar` path (the OS, not the app,
// owns the calendar destination). This suite proves that wiring end-to-end
// through the real [HomeHubScreen]:
//   • tapping either button fires the plugin's `add2Cal` platform method,
//   • the payload maps the NextAppointment fields (title = service·master,
//     location = the card's location line, start = startsAt, end = endsAt).
//
// The plugin is mocked at the channel boundary so no real OS sheet opens. Taps
// are key-first; copy is asserted via l10n.
//
// Phase 225: `NextAppointment` now carries a real `endsAt` (sourced from the
// booking's `endAt`), so the event END asserted below is that real instant —
// NOT a guessed 1-hour block. `_apptEnd` is deliberately NOT exactly
// `_apptStart + 1h` so a regression back to the old hardcoded default would
// fail this assertion, not accidentally satisfy it.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/home_hub_screen.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/next_appointment_card.dart';
import 'package:beautica_mobile/features/rating/application/my_rating_notifier.dart';
import 'package:beautica_mobile/features/rating/domain/client_rating.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

const MethodChannel _kCalendarChannel = MethodChannel('add_2_calendar');

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void reset() {}
}

const ClientProfileSummary _profile = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Тест',
  city: 'Львів',
  phone: '+380 97 000 00 00',
  clientRating: null,
  memberSinceYear: 2026,
);

// Fixed UTC instants so the absolute-ms assertion is CI-timezone independent.
final DateTime _apptStart = DateTime.utc(2026, 7, 20, 12, 0);
// Deliberately NOT `_apptStart + 1h` — see the file header.
final DateTime _apptEnd = DateTime.utc(2026, 7, 20, 13, 30);

final NextAppointment _appt = NextAppointment(
  id: 'appt-1',
  masterName: 'Марія Іванюк',
  service: 'Манікюр',
  dateLabel: '20 липня',
  timeLabel: '15:00',
  location: 'Центр, Львів',
  startsAt: _apptStart,
  endsAt: _apptEnd,
  masterInitials: 'МІ',
);

List<Object> _overrides() => <Object>[
  screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
  // Rating pill now sources from myRatingProvider; override it so the widget
  // test makes no real network call and leaks no keepAlive Timer.
  myRatingProvider.overrideWith((ref) async => const ClientRating()),
  clientProfileProvider.overrideWith((ref) async => _profile),
  nextAppointmentProvider.overrideWith((ref) async => _appt),
  favoriteMastersProvider.overrideWith(
    (ref) async => const <FavoriteMasterItem>[],
  ),
  beautyTimelineProvider.overrideWith((ref) async => const <TimelineEntry>[]),
  unlikeFavoriteMasterProvider.overrideWith(() => UnlikeFavoriteMaster()),
];

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

  Future<AppLocalizations> pumpHub(WidgetTester tester) async {
    await tester.pumpApp(const HomeHubScreen(), overrides: _overrides());
    await tester.pumpAndSettle();
    return AppLocalizations.of(
      tester.element(find.byType(NextAppointmentCard)),
    );
  }

  void expectMapsAppointment(AppLocalizations l10n) {
    expect(calls, hasLength(1), reason: 'add2Cal must have fired once');
    expect(calls.single.method, 'add2Cal');
    final Map<Object?, Object?> args =
        calls.single.arguments as Map<Object?, Object?>;
    expect(
      args['title'],
      l10n.bookingCalendarEventTitle(_appt.service, _appt.masterName),
    );
    expect(args['location'], _appt.location);
    expect(args['startDate'], _apptStart.millisecondsSinceEpoch);
    // Phase 225 — the event END is the booking's real `endsAt`, not a
    // guessed block.
    expect(args['endDate'], _apptEnd.millisecondsSinceEpoch);
  }

  testWidgets(
    'tapping the Google-calendar button adds the next appointment via add2Cal',
    (tester) async {
      final AppLocalizations l10n = await pumpHub(tester);

      final Finder button = find.byKey(
        const Key('next_appt_google_cal_button'),
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();

      expectMapsAppointment(l10n);
      expect(find.text(l10n.bookingAddToCalendarError), findsNothing);
    },
  );

  testWidgets('the Apple-calendar button routes to the SAME add2Cal path', (
    tester,
  ) async {
    final AppLocalizations l10n = await pumpHub(tester);

    final Finder button = find.byKey(const Key('next_appt_apple_cal_button'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expectMapsAppointment(l10n);
  });
}
