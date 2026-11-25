// M543 (CLI-80, CLI-E10, CLI-D15, BOOK-80) — «Записати» on the provider
// client card opens the staff walk-in with the card's client prefilled, end to
// end through the REAL router binding, the typed in-memory `extra`, the
// walk-in screens and the staff-booking wire request (fake backend).
//
// What only this tier proves (the widget tier stubs the launcher):
//   • the ROUTE binds the button per role (IM → `/master/bookings/new`, owner
//     / admin → `/salon/bookings/new` of the card's salon; SALON_MASTER →
//     none) and the location never carries PII;
//   • the prefill reaches the wire as a plain walk-in `guest{name,surname,
//     phone}` equal to the card (CLI-D14: no client id in the body);
//   • the card shows the new booking afterwards (the fake links a walk-in
//     to the card's client by phone, as the server does by CLI-62);
//   • a selected master chip (CLI-73) is not booking intent: the salon
//     wizard still opens on its own client step, no master preselected.
//
// Own sibling of `walk_in_pick_client_flow_test.dart` (its helpers are
// private — doc: phase 543 § Test Cases).
//
// CLOCK: the harness pins `clockProvider` to `kFixedNow`; `_kyivToday` derives
// from that SAME clock (`project_test_clock_coherence_invariant`).
//
// Standalone run (one file per invocation):
//   flutter test integration_test/book_client_from_card_flow_test.dart -d flutter-tester

import 'dart:async';

import 'package:beautica_mobile/core/widgets/neumorphic.dart'
    show NeumorphicButton;
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_create_booking_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/walk_in_guest_step_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/walk_in_service_step_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_wizard_steps.dart'
    show ClientStep;
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';
import 'support/fake_backend.dart';

final DateTime _kyivToday = kyivToday(() => kFixedNow);

// Named constants, never literals at a `find.text` call site
// (`scripts/forbid_cyrillic_finder.sh`).
const String _kRegId = 'u-oksana';
const String _kRegFirst = 'Оксана';
const String _kRegLast = 'Мельник';
const String _kRegPhone = '+380501112233';
const String _kRegPhoneShown = '+380 50 111 22 33';

const String _kGuestId = 'b-iryna';
const String _kGuestFirst = 'Ірина';
const String _kGuestLast = 'Коваль';
const String _kGuestPhone = '+380671234567';
const String _kGuestPhoneShown = '+380 67 123 45 67';

/// A registered client without a verified (E.164) phone (CLI-E10).
const String _kNoPhoneId = 'u-nophone';
const String _kNoPhoneFirst = 'Марта';
const String _kNoPhoneLast = 'Бойко';

/// An anonymised / detached registered client (CLI-E10, D8): no display
/// name, no name parts, no phone — nothing to prefill.
const String _kAnonId = 'u-anon';

const String _kAdminSalonId = 'salon-admin-1';

/// A CLI-73 chip id — a UUID, or the card ignores the tap.
const String _kChipMasterId = 'b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';

const Key _first = Key('master-create-booking-first-name');
const Key _last = Key('master-create-booking-last-name');
const Key _phone = Key('master-create-booking-phone');
const Key _next = Key('master-create-booking-client-next');

final Finder _book = find.byKey(ClientCardScreen.bookKey);

/// The card's row for [visitKey] (one row per BOOKING: the booking id) —
/// its history row, or the «Наступний візит» head when it is upcoming.
Finder _visitRow(String visitKey) => find.byWidgetPredicate(
  (Widget w) =>
      w.key == ClientCardScreen.visitKey(visitKey) ||
      w.key == ClientCardScreen.nextVisitKey,
);

/// Waits for the card's row for [visitKey]. The timeline is a lazy sliver
/// below the 800x600 fold, so the surface is made tall enough to build it
/// (restored at tear-down).
Future<void> _expectVisitRow(WidgetTester tester, String visitKey) async {
  tester.view.physicalSize = Size(
    tester.view.physicalSize.width,
    tester.view.physicalSize.height * 3,
  );
  addTearDown(tester.view.resetPhysicalSize);
  await AppHarness.settle(tester);
  await AppHarness.pumpUntilFound(tester, _visitRow(visitKey));
  expect(_visitRow(visitKey), findsOneWidget);
}

Map<String, dynamic> _cardJson(
  String id, {
  required String first,
  required String last,
  String? phone,
  bool blocked = false,
  List<Map<String, dynamic>> served = const <Map<String, dynamic>>[],
}) {
  final bool guest = !id.startsWith('u-');
  return <String, dynamic>{
    'kind': guest ? 'GUEST' : 'REGISTERED',
    guest ? 'guestBookingId' : 'userId': id,
    'displayName': '$first $last',
    'firstName': first,
    'lastName': last,
    'phone': ?phone,
    'blocked': blocked,
    'ratingCount': 0,
    'ratingDistribution': <Map<String, int>>[],
    'servedByMasters': served,
  };
}

/// Cards for a registered client ([blocked] as asked), a guest (with a
/// CLI-73 master chip), a phone-less registered client and an anonymised
/// one (no name, no phone), on the `me` scope
/// and every salon in [salonIds]. A walk-in naming a card's phone lands in
/// that card's visits (CLI-62 link).
void _seedCards(
  FakeBackend fb, {
  List<String> salonIds = const <String>[FakeBackend.kOwnerSalonId],
  bool blocked = false,
}) {
  fb
    ..clientCards[_kRegId] = _cardJson(
      _kRegId,
      first: _kRegFirst,
      last: _kRegLast,
      phone: _kRegPhone,
      blocked: blocked,
    )
    ..clientCards[_kGuestId] = _cardJson(
      _kGuestId,
      first: _kGuestFirst,
      last: _kGuestLast,
      phone: _kGuestPhone,
      served: <Map<String, dynamic>>[
        <String, dynamic>{'masterId': _kChipMasterId, 'name': 'Олена Шевчук'},
      ],
    )
    ..clientCards[_kNoPhoneId] = _cardJson(
      _kNoPhoneId,
      first: _kNoPhoneFirst,
      last: _kNoPhoneLast,
    )
    ..clientCards[_kAnonId] = <String, dynamic>{
      'kind': 'REGISTERED',
      'userId': _kAnonId,
      'blocked': false,
      'ratingCount': 0,
      'ratingDistribution': <Map<String, int>>[],
      'servedByMasters': <Map<String, dynamic>>[],
    }
    ..clientIdByWalkInPhone[_kRegPhone] = _kRegId
    ..clientIdByWalkInPhone[_kGuestPhone] = _kGuestId
    ..wireClientCard(salonIds: salonIds);
}

String _text(WidgetTester tester, Key key) => tester
    .widget<EditableText>(
      find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
    )
    .controller
    .text;

bool _nextEnabled(WidgetTester tester) =>
    tester.widget<NeumorphicButton>(find.byKey(_next)).onPressed != null;

/// Pushes the card at [location] and waits for it to load.
Future<void> _openCard(
  WidgetTester tester,
  GoRouter router,
  String location,
) async {
  unawaited(router.push(location));
  await AppHarness.settle(tester);
  await AppHarness.pumpUntilFound(tester, find.byKey(ClientCardScreen.nameKey));
  await AppHarness.settle(tester);
}

/// Taps «Записати» (scrolled into view first — 800x600 surface).
Future<void> _tapBook(WidgetTester tester) async {
  await AppHarness.pumpUntilFound(tester, _book);
  await AppHarness.tapVisible(tester, _book);
  await AppHarness.settle(tester);
}

/// IM: boots with an empty board, a free slot today and the cards seeded.
Future<GoRouter> _bootMaster(WidgetTester tester, FakeBackend fb) async {
  fb
    ..seedManyBookingsDataset(const <Map<String, dynamic>>[])
    ..availableSlotUtcStarts = const <(int, int)>[(7, 0)];
  _seedCards(fb);
  final GoRouter router = await AppHarness.boot(tester, fb);
  fb.seedEffectiveSchedule(<Map<String, dynamic>>[
    FakeBackend.seedEffectiveScheduleDay(
      _kyivToday,
      intervals: const <(String, String)>[('09:00:00', '21:00:00')],
    ),
  ]);
  await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
  await AppHarness.settle(tester);
  return router;
}

/// IM walk-in: «Далі» → one service → today → first free slot → confirm →
/// submit. Returns the wire guest payload.
Future<Map<String, dynamic>> _submitMasterWalkIn(
  WidgetTester tester,
  FakeBackend fb,
) async {
  await AppHarness.tapVisible(tester, find.byKey(_next));
  await AppHarness.settle(tester);
  expect(find.byType(WalkInServiceStepScreen), findsOneWidget);

  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(const Key('mcb_service_card_assign-1')),
  );
  await tester.tap(find.byKey(const Key('mcb_service_card_assign-1')));
  await AppHarness.settle(tester);
  await tester.tap(find.byKey(const Key('booking-summary-cta')));
  await AppHarness.settle(tester);

  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(Key('booking-calendar-day-${_kyivToday.day}')),
  );
  await tester.tapCalendarDay(_kyivToday.day);
  await AppHarness.settle(tester);
  await tester.tap(find.byKey(const Key('booking-summary-cta')));
  await AppHarness.settle(tester);
  final Finder chip = find
      .byWidgetPredicate((Widget w) => w is SlotChip && w.available)
      .first;
  await AppHarness.pumpUntilFound(tester, chip);
  await tester.ensureVisible(chip);
  await AppHarness.settle(tester);
  await tester.tap(chip);
  await AppHarness.settle(tester);
  await tester.tap(find.byKey(const Key('booking-summary-cta')));
  await AppHarness.settle(tester);
  expect(find.byType(BookingConfirmScreen), findsOneWidget);

  await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
  await AppHarness.settle(tester);

  expect(fb.createStaffBookingCalls, 1);
  final Map<String, dynamic> body = fb.lastStaffBookingRequestBody!;
  expect(
    body.keys.toSet(),
    <String>{'masterServiceIds', 'startsAt', 'guest'},
    reason: 'CLI-D14 — a plain walk-in: no client id field in the request',
  );
  return (body['guest'] as Map).cast<String, dynamic>();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('M543 IM: registered card → «Записати» → prefilled walk-in → '
      'the wire guest equals the card → the card shows the new booking', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.independentMaster;
      final GoRouter router = await _bootMaster(tester, fb);
      const String cardLocation = '${RouteNames.masterClients}/user/$_kRegId';
      await _openCard(tester, router, cardLocation);

      await _tapBook(tester);
      // D6 — the typed extra never reaches the location.
      AppHarness.expectNestedPushLocation(router, RouteNames.masterBookingNew);
      expect(find.byType(WalkInGuestStepScreen), findsOneWidget);
      expect(_text(tester, _first), _kRegFirst);
      expect(_text(tester, _last), _kRegLast);
      expect(_text(tester, _phone), _kRegPhoneShown);
      // D7 — no picked-client chip for a card launch.
      expect(find.byKey(ClientStep.pickedChipKey), findsNothing);

      final Map<String, dynamic> guest = await _submitMasterWalkIn(tester, fb);
      expect(guest, <String, dynamic>{
        'name': _kRegFirst,
        'surname': _kRegLast,
        'phone': _kRegPhone,
      });

      // The fake linked the walk-in to this client by phone (CLI-62).
      expect(fb.clientVisits[_kRegId], hasLength(1));
      // Back on the card: the new booking is its own row (CLI-78).
      await _openCard(tester, router, cardLocation);
      await _expectVisitRow(tester, kWalkInBookingId);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('M543 owner: guest card with a master chip selected → the '
      'salon wizard on its client step, no master preselected → submit → '
      'closing returns to the card, which shows the booking', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..salonBoardBookings = <Map<String, dynamic>>[];
      _seedCards(fb);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);

      await _openCard(
        tester,
        router,
        '${RouteNames.salonClients(FakeBackend.kOwnerSalonId)}/guest/$_kGuestId',
      );
      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientCardScreen.masterChipKey(_kChipMasterId)),
      );
      await AppHarness.settle(tester);

      await _tapBook(tester);
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.salonStaffBookingNew,
      );
      expect(find.byType(SalonCreateBookingScreen), findsOneWidget);
      expect(_text(tester, _first), _kGuestFirst);
      expect(_text(tester, _last), _kGuestLast);
      expect(_text(tester, _phone), _kGuestPhoneShown);

      await AppHarness.tapVisible(tester, find.byKey(_next));
      await AppHarness.settle(tester);
      final Finder svc = find.byKey(
        const Key('mcb_service_card_${FakeBackend.kSalonWizSvcA}'),
      );
      await AppHarness.pumpUntilFound(tester, svc);
      await tester.ensureVisible(svc);
      await tester.tap(svc);
      await tester.pump();
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);

      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('salon-create-booking-date-calendar')),
      );
      await tester.tapCalendarDay(_kyivToday.day);
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('salon-create-booking-date-next')));
      await AppHarness.settle(tester);

      // D4 — the masters step decides: nothing is picked yet, so no submit.
      final Finder tile = find.byKey(
        const Key('salon-master-tile-${FakeBackend.kSalonWizardMasterFull}'),
      );
      await AppHarness.pumpUntilFound(tester, tile);
      final Finder submit = find.byKey(
        const Key('salon-create-booking-submit-cta'),
      );
      expect(submit, findsNothing);
      await tester.ensureVisible(tile);
      await AppHarness.settle(tester);
      await tester.tap(tile);
      await AppHarness.settle(tester);
      final Finder chip = find
          .byWidgetPredicate((Widget w) => w is SlotChip && w.available)
          .first;
      await AppHarness.pumpUntilFound(tester, chip);
      await tester.ensureVisible(chip);
      await AppHarness.settle(tester);
      await tester.tap(chip);
      await AppHarness.settle(tester);

      await AppHarness.pumpUntilFound(tester, submit);
      await AppHarness.tapVisible(tester, submit);
      await AppHarness.settle(tester);

      expect(fb.createSalonWizardBookingCalls, 1);
      final Map<String, dynamic> body = fb.lastSalonWizardBookingRequestBody!;
      expect(body.keys.toSet(), <String>{
        'masterServiceIds',
        'startsAt',
        'guest',
      });
      expect(body['guest'], <String, dynamic>{
        'name': _kGuestFirst,
        'surname': _kGuestLast,
        'phone': _kGuestPhone,
      });

      // The done step's close pops back to the card, refreshed.
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('salon-create-booking-done-cta')),
      );
      await AppHarness.settle(tester);
      expect(find.byType(ClientCardScreen), findsOneWidget);
      expect(fb.clientVisits[_kGuestId], hasLength(1));
      await _expectVisitRow(tester, 'salon-wizard-booking-1');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('M543 SALON_ADMIN: blocked client card → «Записати» shown → '
      'the salon wizard opens prefilled', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonAdmin
        ..salonBoardBookings = <Map<String, dynamic>>[];
      _seedCards(
        fb,
        salonIds: const <String>[_kAdminSalonId, FakeBackend.kOwnerSalonId],
        blocked: true,
      );
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonAdmin);
      await AppHarness.settle(tester);

      await _openCard(
        tester,
        router,
        '${RouteNames.salonClients(_kAdminSalonId)}/user/$_kRegId',
      );
      await _tapBook(tester);
      expect(find.byType(SalonCreateBookingScreen), findsOneWidget);
      expect(_text(tester, _first), _kRegFirst);
      expect(_text(tester, _last), _kRegLast);
      expect(_text(tester, _phone), _kRegPhoneShown);
      expect(_nextEnabled(tester), isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('M543 SALON_MASTER: the card loads with no «Записати»', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()..currentRole = UserRole.salonMaster;
      _seedCards(fb);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonMaster);
      await AppHarness.settle(tester);

      await _openCard(
        tester,
        router,
        '${RouteNames.salonMasterClients}/user/$_kRegId',
      );
      expect(find.byKey(ClientCardScreen.nameKey), findsOneWidget);
      expect(_book, findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('M543 IM: a card without a phone → names prefilled, phone '
      'empty, «Далі» disabled until a phone is typed', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.independentMaster;
      final GoRouter router = await _bootMaster(tester, fb);
      await _openCard(
        tester,
        router,
        '${RouteNames.masterClients}/user/$_kNoPhoneId',
      );

      await _tapBook(tester);
      expect(find.byType(WalkInGuestStepScreen), findsOneWidget);
      expect(_text(tester, _first), _kNoPhoneFirst);
      expect(_text(tester, _last), _kNoPhoneLast);
      expect(_text(tester, _phone), isEmpty);
      expect(_nextEnabled(tester), isFalse);

      await tester.enterText(find.byKey(_phone), '0509998877');
      await tester.pump();
      expect(_nextEnabled(tester), isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('M543 IM: an anonymised card (no name, no phone) loads with no '
      '«Записати» (D8 / CLI-E10)', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.independentMaster;
      final GoRouter router = await _bootMaster(tester, fb);
      await _openCard(
        tester,
        router,
        '${RouteNames.masterClients}/user/$_kAnonId',
      );

      expect(find.byKey(ClientCardScreen.nameKey), findsOneWidget);
      expect(_book, findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
