// M544 (CLI-82, CLI-83, CLI-84, Step 2.7 Rule 3b) — E2E: who shares a
// «Клієнти» removal, and how a removed client comes back.
//
// REAL router + REAL `HttpClientRepository` over the stubbed Dio. The fake
// keeps removals per LIST PATH (`FakeBackend.wireClientListRemovals`) and
// clears them when a walk-in is linked to the client (the server's comeback
// rule, CLI-83) — so what this tier pins is the app side of the contract:
// each role writes to ITS scope's path and reads its scope's list back.
//
//   (a) Re-book: IM swipes a client away → the card stays reachable from
//       «Деталі запису» (CLI-84) → «Записати» → walk-in submitted → the list
//       (pull-to-refresh) shows the row again → its card shows the OLD visit
//       AND the new booking (full history).
//   (b) Scope separation (CLI-82), one backend, four sessions (relaunch =
//       another device): owner removes → admin of the SAME salon no longer
//       sees the row; admin removes → owner no longer sees it either; the
//       salon master's own list still has both; the salon master's removal
//       leaves the owner's list untouched.
//
// CLOCK: the harness pins `clockProvider` to `kFixedNow`; the walk-in day
// derives from that SAME clock (M15).
// NO PATROL FLOW: no OS dialog, permission, deep link, notification or
// WebView is touched (mobile-qa explicit statement).
//
// Standalone run (one file per invocation):
//   flutter test integration_test/clients_remove_scope_rebook_flow_test.dart -d flutter-tester

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/walk_in_service_step_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_client_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/clients_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';
import 'support/fake_backend.dart';
import 'support/pull_to_refresh.dart';

final DateTime _kyivToday = kyivToday(() => kFixedNow);

const String _kSalonList =
    '/api/v1/salons/${FakeBackend.kOwnerSalonId}/clients';
const String _kMeList = '/api/v1/masters/me/clients';

const String _kRegId = 'u-oksana';
const String _kRegFirst = 'Оксана';
const String _kRegLast = 'Мельник';
const String _kRegPhone = '+380501112233';

/// The pre-removal visit on the card (a past, completed booking).
const String _kOldBookingId = 'bk-old';

Finder _row(String id) => find.byKey(Key('client-row-$id'));

Map<String, dynamic> _listRow(String id, String name) => <String, dynamic>{
  'kind': 'REGISTERED',
  'userId': id,
  'displayName': name,
  'lastVisitAt': '2026-06-01T10:00:00Z',
  'completedVisits': 1,
  'ratingCount': 0,
  'blocked': false,
};

Future<void> _waitForList(WidgetTester tester) async {
  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(ClientsScreen.listKey),
    timeout: const Duration(seconds: 20),
  );
  await AppHarness.settle(tester);
}

/// Swipes [id]'s row away and lets the undo window run out (pumped
/// explicitly — `pumpAndSettle` fires no `Timer`), so the removal stands.
Future<void> _swipeRemoveAndExpire(WidgetTester tester, String id) async {
  await tester.drag(_row(id), const Offset(-600, 0));
  await AppHarness.pumpUntilFound(tester, find.byType(VelvetSnack));
  expect(_row(id), findsNothing);
  await AppHarness.pumpUntilGone(
    tester,
    find.byType(VelvetSnack),
    timeout: const Duration(seconds: 15),
  );
  await AppHarness.settle(tester);
}

/// The card's row for [bookingId]: its history row, or the «Наступний
/// візит» head when the booking is upcoming.
Finder _visitRow(String bookingId) => find.byWidgetPredicate(
  (Widget w) =>
      w.key == ClientCardScreen.visitKey(bookingId) ||
      w.key == ClientCardScreen.nextVisitKey,
);

/// IM walk-in from the service step: one service → today → first free slot
/// → confirm → submit (same path as `book_client_from_card_flow_test.dart`,
/// whose helpers are private).
Future<void> _submitMasterWalkIn(WidgetTester tester, FakeBackend fb) async {
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
}

/// Boots (after unmounting a previous session = another device), logs in
/// as [role] and opens its «Клієнти» tab.
Future<void> _session(
  WidgetTester tester,
  FakeBackend fb,
  UserRole role, {
  bool relaunch = true,
}) async {
  if (relaunch) {
    await tester.pumpWidget(const SizedBox.shrink());
    await AppHarness.settle(tester);
  }
  await AppHarness.boot(tester, fb);
  await AppHarness.loginAs(tester, fb, role);
  await AppHarness.settle(tester);
  await AppHarness.tapVisible(
    tester,
    find.byKey(
      Key(
        role == UserRole.salonMaster ? 'master-nav-tile-3' : 'salon-nav-tile-3',
      ),
    ),
  );
  await _waitForList(tester);
}

void _expectListed(String path, FakeBackend fb, Map<String, bool> rows) {
  expect(fb.clientListCalls.last.path, path);
  for (final MapEntry<String, bool> e in rows.entries) {
    expect(
      _row(e.key),
      e.value ? findsOneWidget : findsNothing,
      reason: '${e.key} ${e.value ? 'listed' : 'removed'} on $path',
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('(a) a removed client who books again is back on the list, and '
      'the card shows the old visit AND the new booking', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.independentMaster
        ..bookingRegisteredClientId = _kRegId
        ..seedManyBookingsDataset(const <Map<String, dynamic>>[])
        ..availableSlotUtcStarts = const <(int, int)>[(7, 0)]
        ..wireClientList()
        ..wireClientListRemovals();
      fb.clientRows
        ..clear()
        ..add(_listRow(_kRegId, '$_kRegFirst $_kRegLast'))
        ..add(_listRow('u-anna', 'Анна Перша'));
      fb
        ..clientCards[_kRegId] = <String, dynamic>{
          'kind': 'REGISTERED',
          'userId': _kRegId,
          'displayName': '$_kRegFirst $_kRegLast',
          'firstName': _kRegFirst,
          'lastName': _kRegLast,
          'phone': _kRegPhone,
          'blocked': false,
          'ratingCount': 0,
          'ratingDistribution': <Map<String, int>>[],
          'servedByMasters': <Map<String, dynamic>>[],
        }
        ..clientVisits[_kRegId] = <Map<String, dynamic>>[
          <String, dynamic>{
            'visitKey': _kOldBookingId,
            'startsAt': '2026-05-10T10:00:00Z',
            'items': <Map<String, dynamic>>[
              <String, dynamic>{
                'bookingId': _kOldBookingId,
                'serviceName': 'Манікюр',
                'status': 'COMPLETED',
                'startsAt': '2026-05-10T10:00:00Z',
                'priceAtBooking': 650,
              },
            ],
          },
        ]
        ..clientIdByWalkInPhone[_kRegPhone] = _kRegId
        ..wireClientCard();
      final GoRouter router = await AppHarness.boot(tester, fb);
      fb.seedEffectiveSchedule(<Map<String, dynamic>>[
        FakeBackend.seedEffectiveScheduleDay(
          _kyivToday,
          intervals: const <(String, String)>[('09:00:00', '21:00:00')],
        ),
      ]);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await AppHarness.settle(tester);
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('master-nav-tile-3')),
      );
      await _waitForList(tester);

      await _swipeRemoveAndExpire(tester, _kRegId);
      expect(fb.clientRemovalCalls, <String>[
        'remove $_kMeList {clientId: $_kRegId}',
      ]);
      expect(_row(_kRegId), findsNothing);

      // CLI-84 — the removed client's card is still reachable from
      // «Деталі запису» (their booking).
      unawaited(router.push(RouteNames.masterBookingDetail('booking-1')));
      await AppHarness.settle(tester);
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      await AppHarness.tapVisible(
        tester,
        find.byKey(BookingClientStrip.defaultShellKey),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.nameKey),
      );
      await AppHarness.settle(tester);

      // Books again: «Записати» → the walk-in for this client.
      await AppHarness.tapVisible(tester, find.byKey(ClientCardScreen.bookKey));
      await AppHarness.settle(tester);
      expect(find.byType(WalkInServiceStepScreen), findsOneWidget);
      await _submitMasterWalkIn(tester, fb);
      expect(
        (fb.lastStaffBookingRequestBody!['guest'] as Map)['phone'],
        _kRegPhone,
      );

      // Back on the list: the row is back after a refresh (CLI-83).
      router.go(RouteNames.masterClients);
      await _waitForList(tester);
      await pullToRefresh(
        tester,
        () => fb.clientListCalls.length,
        scrollable: find.byKey(ClientsScreen.listKey),
      );
      await AppHarness.pumpUntilFound(tester, _row(_kRegId));
      expect(fb.clientListCalls.last.path, _kMeList);

      // The card shows the FULL history: the old visit and the new booking.
      await AppHarness.tapVisible(tester, _row(_kRegId));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.nameKey),
      );
      tester.view.physicalSize = Size(
        tester.view.physicalSize.width,
        tester.view.physicalSize.height * 3,
      );
      addTearDown(tester.view.resetPhysicalSize);
      await AppHarness.settle(tester);
      await AppHarness.pumpUntilFound(tester, _visitRow(kWalkInBookingId));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.visitKey(_kOldBookingId)),
      );
      expect(fb.clientVisits[_kRegId], hasLength(2));
      expect(tester.takeException(), isNull);
    });
  }, timeout: const Timeout(Duration(seconds: 150)));

  testWidgets('(b) owner and admin share ONE salon list both ways; the salon '
      'master\'s list is separate both ways', (tester) async {
    await mockNetworkImagesFor(() async {
      // The admin works in the OWNER's salon (one shared list, CLI-82).
      adminSalonIdOverride = FakeBackend.kOwnerSalonId;
      addTearDown(() => adminSalonIdOverride = null);
      final FakeBackend fb =
          FakeBackend(
              masterRowId: 'master-removable',
              masterSalonId: 'salon-xyz',
            )
            ..wireClientList()
            ..wireClientListRemovals();
      fb.clientRows
        ..clear()
        ..add(_listRow('u-a', 'Анна Перша'))
        ..add(_listRow('u-b', 'Богдана Друга'))
        ..add(_listRow('u-c', 'Віра Третя'));

      // 1 — owner removes u-a.
      await _session(tester, fb, UserRole.salonOwner, relaunch: false);
      _expectListed(_kSalonList, fb, <String, bool>{
        'u-a': true,
        'u-b': true,
        'u-c': true,
      });
      await _swipeRemoveAndExpire(tester, 'u-a');

      // 2 — admin (same salon, another device): u-a is gone; removes u-b.
      await _session(tester, fb, UserRole.salonAdmin);
      _expectListed(_kSalonList, fb, <String, bool>{
        'u-a': false,
        'u-b': true,
        'u-c': true,
      });
      await _swipeRemoveAndExpire(tester, 'u-b');

      // 3 — salon master: their OWN list is untouched by the salon's
      // removals; removes u-c.
      await _session(tester, fb, UserRole.salonMaster);
      _expectListed(_kMeList, fb, <String, bool>{
        'u-a': true,
        'u-b': true,
        'u-c': true,
      });
      await _swipeRemoveAndExpire(tester, 'u-c');

      // 4 — owner again: the admin's removal applies here too, the salon
      // master's does not.
      await _session(tester, fb, UserRole.salonOwner);
      _expectListed(_kSalonList, fb, <String, bool>{
        'u-a': false,
        'u-b': false,
        'u-c': true,
      });

      expect(fb.clientRemovalCalls, <String>[
        'remove $_kSalonList {clientId: u-a}',
        'remove $_kSalonList {clientId: u-b}',
        'remove $_kMeList {clientId: u-c}',
      ]);
      expect(tester.takeException(), isNull);
    });
  }, timeout: const Timeout(Duration(seconds: 150)));
}
