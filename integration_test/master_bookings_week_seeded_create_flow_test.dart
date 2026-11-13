// Phase 487 — an empty week-grid tap seeds the create wizard, end to end on
// the fake backend (headless: `flutter test
// integration_test/master_bookings_week_seeded_create_flow_test.dart
// -d flutter-tester`).
//
//   «Записи» → › next week → «День» on Wednesday → tap the EMPTY grid at
//   14:40 → guest step (`…/new?at=<Wed>T14:30`) → service step (`?at=`
//   forwarded on the push, the `WalkInGuest` extra unchanged) → slot picker
//   opens with Wednesday selected and the seeded chip selected → time screen
//   → confirm → the POST's `startsAt` is the seeded slot.
//
// Cases: independent master (exact 14:30 offered); the same with 14:30 NOT
// offered (→ the next later chip, D3); owner master mode (the
// `ownerMasterBookingNew` chain, the owner's own row); and AC3 — a hand-typed
// `?at=` never bypasses the route guards (SALON_MASTER, CLIENT).
//
// CLOCK (pattern M — one clock): every day here derives from the injected
// `kFixedNow` (Sun 2026-06-14). The current week's Wednesday is already PAST
// on that clock (the picker would refuse it), so the flow steps to the NEXT
// week. The fake's slots are dated on the REQUESTED day
// (`masterOwnSlotsOnRequestedDate`), and every slot instant is derived from
// the Kyiv wall clock via `kyivMidnight`, never a hard-coded offset.
//
// NO PATROL FLOW: no OS dialog, permission, notification or WebView.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/walk_in_guest_step_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/walk_in_service_step_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/month_calendar.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_nav_bar.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_time_grid.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/fakes/fake_secure_storage.dart';
import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/week_grid_driver.dart';

/// The injected clock's Kyiv day. A getter: the time-zone database is primed
/// by `AppHarness.boot`, so this may only be read after it.
DateTime get _kyivToday => kyivToday(() => kFixedNow);

/// Monday of the week AFTER the injected clock's week.
DateTime get _nextMonday => kyivAddDays(kyivWeekStart(_kyivToday), 7);

/// The seed day: next week's Wednesday (week index 2).
const int _kWedIndex = 2;
DateTime get _seedWed => kyivAddDays(_nextMonday, _kWedIndex);

/// The instant of Kyiv wall clock [hour]:[minute] on [_seedWed], as a plain
/// UTC `DateTime` (the app's `BookingSlot`/wire type, not a `TZDateTime`).
DateTime _wedAt(int hour, int minute) => DateTime.fromMillisecondsSinceEpoch(
  kyivMidnight(
    _seedWed,
  ).add(Duration(hours: hour, minutes: minute)).millisecondsSinceEpoch,
  isUtc: true,
);

/// A Kyiv wall-clock `(hour, minute)` on [_seedWed] — resolved to an instant
/// only after boot (the time-zone database is primed there).
typedef _KyivTime = (int hour, int minute);

DateTime _wed(_KyivTime t) => _wedAt(t.$1, t.$2);

/// `(hourUtc, minute)` for [FakeBackend.availableSlotUtcStarts].
(int, int) _utcStart(DateTime instant) => (instant.hour, instant.minute);

/// `YYYY-MM-DDTHH:mm` — the `at` value a Wed 14:40 tap must produce (the
/// grid rounds DOWN to the half hour, D2).
String get _expectedAt => '${toApiDate(_seedWed)}T14:30';

const String _kOwnerMasterRowId = 'master-row-owner-1';
const String _kOwnAssignId = 'own-assign-1';

Map<String, dynamic> _ownRowService() => <String, dynamic>{
  'id': _kOwnAssignId,
  'masterId': _kOwnerMasterRowId,
  'isActive': true,
  'priceType': 'FIXED',
  'priceMin': 400,
  'priceMax': null,
  'priceDisplay': '400 ₴',
  'effectiveDurationMinutes': 60,
  'serviceDefinition': <String, dynamic>{
    'id': 'own-def-1',
    'name': 'Манікюр класичний',
    'description': null,
    'category': 'NAILS',
    'baseDurationMinutes': 60,
    'bufferMinutesAfter': 0,
    'isActive': true,
    'priceType': 'FIXED',
    'priceMin': 400,
    'priceMax': null,
    'priceDisplay': '400 ₴',
    'photoUrl': null,
  },
};

/// Opens «Записи» (tile 1) and waits for the week grid.
Future<void> _openBookingsTab(WidgetTester tester) async {
  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('master-nav-tile-1')),
  );
  await AppHarness.settle(tester);
  await AppHarness.pumpUntilFound(
    tester,
    find.byType(MasterBookingsScreen),
    timeout: const Duration(seconds: 20),
  );
  await AppHarness.pumpUntilFound(tester, find.byType(WeekTimeGrid));
}

/// › to next week, then the empty Wednesday grid at 14:40.
Future<void> _tapNextWednesdayAt1440(WidgetTester tester) async {
  await tester.tap(find.byKey(WeekStepButton.nextKey));
  await AppHarness.settle(tester);
  expect(
    tester.widget<WeekTimeGrid>(find.byType(WeekTimeGrid)).weekStart,
    _nextMonday,
  );
  await tapEmptyGridAt(
    tester,
    dayIndex: _kWedIndex,
    hour: 14,
    minute: 40,
    settle: AppHarness.settle,
  );
}

/// Guest step (asserting the seeded location) → «Далі» → service step
/// (asserting `?at=` survived the push) → [serviceKey] → «Далі» → date screen.
Future<void> _guestAndService(
  WidgetTester tester,
  GoRouter router, {
  required String newRoute,
  required String servicesRoute,
  required String serviceKey,
}) async {
  await AppHarness.pumpUntilFound(
    tester,
    find.byType(WalkInGuestStepScreen),
    timeout: const Duration(seconds: 20),
  );
  await AppHarness.settle(tester);
  expect(
    AppHarness.nestedPushLocation(router),
    '$newRoute?at=$_expectedAt',
    reason: 'the empty-grid tap pushes the create chain seeded with `at`',
  );

  await tester.enterText(
    find.byKey(const Key('master-create-booking-first-name')),
    'Ірина',
  );
  await tester.enterText(
    find.byKey(const Key('master-create-booking-last-name')),
    'Шевченко',
  );
  await tester.enterText(
    find.byKey(const Key('master-create-booking-phone')),
    '0501234567',
  );
  await tester.pump();
  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('master-create-booking-client-next')),
  );
  await AppHarness.pumpUntilFound(
    tester,
    find.byType(WalkInServiceStepScreen),
    timeout: const Duration(seconds: 20),
  );
  await AppHarness.settle(tester);
  expect(
    AppHarness.nestedPushLocation(router),
    '$servicesRoute?at=$_expectedAt',
    reason: 'the guest step forwards `at` on its push to the service step',
  );

  final Finder card = find.byKey(Key('mcb_service_card_$serviceKey'));
  await AppHarness.pumpUntilFound(
    tester,
    card,
    timeout: const Duration(seconds: 20),
  );
  await AppHarness.tapVisible(tester, card);
  await AppHarness.settle(tester);
  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('booking-summary-cta')),
  );
  await AppHarness.settle(tester);
  await AppHarness.pumpUntilFound(tester, find.byType(SlotDateScreen));
  await AppHarness.settle(tester);
}

/// On the date screen: Wednesday is selected, [expected] is selected without
/// a single user tap; then «Далі» → the time screen shows that chip selected
/// → «Далі» → confirm. Also the request log: ONE slots read, for the seed
/// day, before confirm.
Future<void> _assertSeededPickerAndConfirm(
  WidgetTester tester,
  FakeBackend fb,
  DateTime expected,
) async {
  expect(
    tester
        .widget<MonthCalendar>(find.byKey(const Key('booking-month-calendar')))
        .selected,
    _seedWed,
    reason: 'the picker opens with the tapped day selected',
  );

  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('booking-summary-cta')),
  );
  await AppHarness.settle(tester);
  expect(find.byType(SlotTimeScreen), findsOneWidget);
  final Iterable<SlotChip> selected = tester
      .widgetList<SlotChip>(find.byType(SlotChip))
      .where((SlotChip c) => c.selected);
  expect(selected, hasLength(1), reason: 'exactly one chip is preselected');
  expect(
    selected.single.key,
    Key('slot-chip-${expected.toIso8601String()}'),
    reason: 'the preselected chip is the seeded (or nearest offered) slot',
  );
  expect(
    find.byKey(Key('slot-chip-${expected.toIso8601String()}')).hitTestable(),
    findsOneWidget,
    reason: 'the seeded chip is scrolled into view',
  );

  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('booking-summary-cta')),
  );
  await AppHarness.settle(tester);
  expect(find.byType(BookingConfirmScreen), findsOneWidget);

  expect(
    fb.masterOwnSlotsDates,
    <String>[toApiDate(_seedWed)],
    reason:
        'exactly ONE available-slots read before confirm, and it is for '
        'the seed day',
  );
  expect(fb.createStaffBookingCalls, 0, reason: 'nothing submits before OK');

  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('booking-confirm-submit-cta')),
  );
  await AppHarness.settle(tester);
  expect(fb.createStaffBookingCalls, 1);
  expect(
    DateTime.parse(
      fb.lastStaffBookingRequestBody?['startsAt'] as String,
    ).toUtc(),
    expected,
    reason: 'the create request books the seeded slot',
  );
}

/// Independent master: boot, hours on this and next week, open «Записи».
Future<GoRouter> _bootIndependent(
  WidgetTester tester,
  FakeBackend fb,
  List<_KyivTime> slotStarts,
) async {
  final GoRouter router = await AppHarness.boot(tester, fb);
  fb
    ..seedManyBookingsDataset(const <Map<String, dynamic>>[])
    ..masterOwnSlotsOnRequestedDate = true
    ..availableSlotUtcStarts = <(int, int)>[
      for (final _KyivTime s in slotStarts) _utcStart(_wed(s)),
    ]
    ..seedEffectiveSchedule(<Map<String, dynamic>>[
      for (int i = -7; i < 7; i++)
        FakeBackend.seedEffectiveScheduleDay(
          kyivAddDays(_nextMonday, i),
          intervals: const <(String, String)>[('09:00:00', '21:00:00')],
        ),
    ]);
  await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
  await _openBookingsTab(tester);
  AppHarness.expectLocation(router, RouteNames.masterBookings);
  return router;
}

Future<void> _independentSeededRun(
  WidgetTester tester, {
  required List<_KyivTime> slotStarts,
  required _KyivTime expected,
}) async {
  final FakeBackend fb = FakeBackend()
    ..currentRole = UserRole.independentMaster;
  final GoRouter router = await _bootIndependent(tester, fb, slotStarts);
  await _tapNextWednesdayAt1440(tester);
  await _guestAndService(
    tester,
    router,
    newRoute: RouteNames.masterBookingNew,
    servicesRoute: RouteNames.masterBookingNewServices,
    serviceKey: 'assign-1',
  );
  await _assertSeededPickerAndConfirm(tester, fb, _wed(expected));
  expect(tester.takeException(), isNull);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('INDEPENDENT_MASTER: empty Wed 14:40 tap → guest → service → '
      'picker preselects Wed + 14:30 → confirm books 14:30', (tester) async {
    await _independentSeededRun(
      tester,
      slotStarts: const <_KyivTime>[(10, 0), (14, 30), (16, 0)],
      expected: (14, 30),
    );
  });

  testWidgets('INDEPENDENT_MASTER: 14:30 not offered → the next LATER chip '
      '(15:00) is preselected and booked', (tester) async {
    await _independentSeededRun(
      tester,
      // 14:00 is offered too: a nearest-EARLIER pick would book it instead.
      slotStarts: const <_KyivTime>[(14, 0), (15, 0), (16, 0)],
      expected: (15, 0),
    );
  });

  testWidgets('SALON_OWNER master mode: empty Wed 14:40 tap → the owner '
      'chain (ownerMasterBookingNew?at=) preselects Wed + 14:30 → confirm '
      'books it on the owner row', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb =
          FakeBackend(
              masterRowId: _kOwnerMasterRowId,
              masterSalonId: 'salon-owner-1',
              wireOwnRowSchedule: true,
              wireOwnRowServices: true,
            )
            ..currentRole = UserRole.salonOwner
            ..hasMasterProfile = true;
      fb.ownRowServices.add(_ownRowService());
      fb.ownRowWeeklySchedule.add(<String, dynamic>{
        'id': 'own-weekly-1',
        'validFrom': '2026-01-01',
        'validTo': null,
        'days': <Map<String, dynamic>>[
          for (int dow = 1; dow <= 7; dow++)
            <String, dynamic>{
              'dayOfWeek': dow,
              'intervals': <Map<String, dynamic>>[
                <String, dynamic>{'startTime': '08:00', 'endTime': '20:00'},
              ],
            },
        ],
      });
      fb
        ..seedManyBookingsDataset(<Map<String, dynamic>>[])
        ..ownerMasterRowBookingIds = <String>{}
        ..masterOwnSlotsOnRequestedDate = true;

      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        storage: FakeSecureStorage(),
      );
      fb.availableSlotUtcStarts = <(int, int)>[
        _utcStart(_wedAt(10, 0)),
        _utcStart(_wedAt(14, 30)),
      ];
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);
      // Master mode: the salon shell's «Профіль».
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('salon-nav-tile-3')),
      );
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.ownerMasterProfile);

      await _openBookingsTab(tester);
      AppHarness.expectLocation(router, RouteNames.ownerMasterBookings);
      await _tapNextWednesdayAt1440(tester);
      await _guestAndService(
        tester,
        router,
        newRoute: RouteNames.ownerMasterBookingNew,
        servicesRoute: RouteNames.ownerMasterBookingNewServices,
        serviceKey: _kOwnAssignId,
      );
      await _assertSeededPickerAndConfirm(tester, fb, _wedAt(14, 30));
      expect(fb.lastStaffBookingRequestBody?['masterServiceIds'], <String>[
        _kOwnAssignId,
      ]);
      expect(tester.takeException(), isNull);
    });
  });

  // AC3 — `?at=` is a hint on an already-guarded route, never a key: a role
  // that may not create is bounced exactly as without it.
  for (final UserRole role in <UserRole>[
    UserRole.salonMaster,
    UserRole.client,
  ]) {
    testWidgets('${role.name}: a hand-typed /master/bookings/new?at=… is '
        'bounced by the route guard — no create chain', (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend()..currentRole = role;
        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, role);
        await AppHarness.settle(tester);
        final String home = AppHarness.location(router);

        router.go('${RouteNames.masterBookingNew}?at=$_expectedAt');
        await AppHarness.settle(tester);

        expect(find.byType(WalkInGuestStepScreen), findsNothing);
        expect(
          AppHarness.location(router),
          isNot(startsWith(RouteNames.masterBookingNew)),
          reason: 'the guard redirects whatever the query carries',
        );
        expect(
          Uri.parse(AppHarness.location(router)).path,
          Uri.parse(home).path,
          reason: '${role.name} lands back on its own home',
        );
      });
    });
  }
}
