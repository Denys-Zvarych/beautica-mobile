// M544 (CLI-82, CLI-86, Step 2.7 Rule 3b) — E2E: remove a client from the
// «Клієнти» list, by swipe and from the card «⋯», with the undo snack.
//
// REAL router, REAL `HttpClientRepository` (incl. the B564 removal writes)
// over the stubbed Dio (`FakeBackend.wireClientListRemovals`): what is
// asserted is the wire — which list path, which body key — and the list the
// server serves back afterwards, never a provider override.
//
//   (a) SALON_OWNER swipe: guest row → row gone + undo snack with a draining
//       countdown bar → «Повернути» → row back at the SAME position, restore
//       posted once; registered row swiped → the 5 s window runs out (pumped
//       explicitly: `pumpAndSettle` fires no `Timer`) → pull-to-refresh →
//       the row stays gone, no restore was posted.
//   (c) SALON_OWNER swipe, server refuses (500) → the row is back at the
//       same index, the sanitized «Не вдалося прибрати…» snack, no raw server
//       message, no undo snack.
//   (b) INDEPENDENT_MASTER card «⋯» → «Прибрати зі списку» → back on the
//       list without the row + the same undo snack → «Повернути» → row back.
//
// Copy is read from `AppLocalizations`, never re-typed.
// NO PATROL FLOW: no OS dialog, permission, deep link, notification or
// WebView is touched (mobile-qa explicit statement).
//
// Standalone run (one file per invocation):
//   flutter test integration_test/clients_remove_from_list_flow_test.dart -d flutter-tester

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/clients_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_removed_snack.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/content_actions_sheet.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';
import 'support/client_card_actions.dart';
import 'support/pull_to_refresh.dart';

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('uk'));

const String _kSalonList =
    '/api/v1/salons/${FakeBackend.kOwnerSalonId}/clients';
const String _kMeList = '/api/v1/masters/me/clients';

/// The snack's trailing action (`VelvetSnack.actionKey`).
final Finder _undo = find.byKey(VelvetSnack.actionKey);

Finder _row(String id) => find.byKey(Key('client-row-$id'));

Map<String, dynamic> _registeredRow(String id, String name) =>
    <String, dynamic>{
      'kind': 'REGISTERED',
      'userId': id,
      'displayName': name,
      'lastVisitAt': '2026-06-01T10:00:00Z',
      'completedVisits': 1,
      'ratingCount': 0,
      'blocked': false,
    };

Map<String, dynamic> _guestRow(String bookingId, String name) =>
    <String, dynamic>{
      'kind': 'GUEST',
      'guestBookingId': bookingId,
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

/// Swipes [id]'s row end → start and waits for the undo snack (shown once
/// the write landed). No settle: the countdown animation keeps frames
/// scheduled for the whole window.
Future<void> _swipeRemove(WidgetTester tester, String id) async {
  await tester.drag(_row(id), const Offset(-600, 0));
  await AppHarness.pumpUntilFound(tester, find.byType(VelvetSnack));
  await pumpVelvetSnackIn(tester);
}

/// The countdown bar's remaining fraction (1 → 0 over the window).
double _countdownLeft(WidgetTester tester) => tester
    .widget<FractionallySizedBox>(
      find.descendant(
        of: find.byKey(VelvetSnack.countdownKey),
        matching: find.byType(FractionallySizedBox),
      ),
    )
    .widthFactor!;

void _expectUndoSnack() {
  expectVelvetSnack(
    _l10n.clientsRemovedSnack,
    actionLabel: _l10n.clientsRemoveUndo,
    variant: VelvetSnackVariant.info,
  );
  expect(find.byKey(VelvetSnack.countdownKey), findsOneWidget);
}

/// Vertical order of the listed rows, top first.
List<String> _order(WidgetTester tester, List<String> ids) =>
    <String>[
      for (final String id in ids)
        if (_row(id).evaluate().isNotEmpty) id,
    ]..sort(
      (String a, String b) => tester
          .getTopLeft(_row(a))
          .dy
          .compareTo(tester.getTopLeft(_row(b)).dy),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('(a) SALON_OWNER: swipe → undo snack with a draining countdown → '
      '«Повернути» puts the row back in place; a second swipe left to expire '
      'stays gone after pull-to-refresh', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..wireClientList()
        ..wireClientListRemovals();
      fb.clientRows
        ..clear()
        ..add(_registeredRow('u-anna', 'Анна Перша'))
        ..add(_guestRow('b-iryna', 'Ірина Гостя'))
        ..add(_registeredRow('u-olha', 'Ольга Третя'));
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);
      AppHarness.expectLocation(
        router,
        RouteNames.salonShell(FakeBackend.kOwnerSalonId),
      );
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('salon-nav-tile-3')),
      );
      await _waitForList(tester);
      const List<String> all = <String>['u-anna', 'b-iryna', 'u-olha'];
      expect(_order(tester, all), all);

      // ── swipe the middle (guest) row → undo ─────────────────────────────
      await _swipeRemove(tester, 'b-iryna');
      expect(_row('b-iryna'), findsNothing);
      _expectUndoSnack();
      expect(fb.clientRemovalCalls, <String>[
        'remove $_kSalonList {guestBookingId: b-iryna}',
      ]);
      // The bar is visible AND draining over the window.
      final double first = _countdownLeft(tester);
      // fixed-wait-ok: samples the countdown bar 1 s apart — the elapsed time
      // IS the quantity under test.
      await tester.pump(const Duration(seconds: 1));
      final double later = _countdownLeft(tester);
      expect(later, lessThan(first), reason: 'the countdown bar drains');
      expect(later, greaterThan(0));

      final int listCallsBeforeUndo = fb.clientListCalls.length;
      await tester.tap(_undo);
      await AppHarness.pumpUntilFound(tester, _row('b-iryna'));
      // Position checked BEFORE any refetch could reorder it: the controller's
      // own optimistic reinsert put it back at its former index.
      expect(
        fb.clientListCalls.length,
        listCallsBeforeUndo,
        reason: 'no list refetch yet',
      );
      expect(
        _order(tester, all),
        all,
        reason: 'the restored row is back at its former index',
      );
      await AppHarness.pumpUntilGone(tester, find.byType(VelvetSnack));
      await AppHarness.settle(tester);
      expect(fb.clientRemovalCalls, <String>[
        'remove $_kSalonList {guestBookingId: b-iryna}',
        'restore $_kSalonList {guestBookingId: b-iryna}',
      ]);

      // ── swipe a registered row → let the window run out ─────────────────
      await _swipeRemove(tester, 'u-olha');
      _expectUndoSnack();
      // `pumpAndSettle` fires no Timer: drive the dwell explicitly.
      await tester.pump(kClientRemoveUndoWindow);
      await tester.pump(VelvetSnackMotion.exit);
      await AppHarness.pumpUntilGone(tester, find.byType(VelvetSnack));
      await AppHarness.settle(tester);
      expect(_row('u-olha'), findsNothing);

      await pullToRefresh(
        tester,
        () => fb.clientListCalls.length,
        scrollable: find.byKey(ClientsScreen.listKey),
      );
      await AppHarness.settle(tester);
      expect(_row('u-olha'), findsNothing, reason: 'gone on the server too');
      expect(_order(tester, all), <String>['u-anna', 'b-iryna']);
      expect(fb.clientRemovalCalls, <String>[
        'remove $_kSalonList {guestBookingId: b-iryna}',
        'restore $_kSalonList {guestBookingId: b-iryna}',
        'remove $_kSalonList {clientId: u-olha}',
      ], reason: 'an expired undo posts no restore');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('(c) SALON_OWNER: swipe → the server refuses → the row is back '
      'at the SAME index with the sanitized error snack, never the undo '
      'snack', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..wireClientList()
        ..wireClientListRemovals(removeFailureStatusCode: 500);
      fb.clientRows
        ..clear()
        ..add(_registeredRow('u-anna', 'Анна Перша'))
        ..add(_guestRow('b-iryna', 'Ірина Гостя'))
        ..add(_registeredRow('u-olha', 'Ольга Третя'));
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);
      AppHarness.expectLocation(
        router,
        RouteNames.salonShell(FakeBackend.kOwnerSalonId),
      );
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('salon-nav-tile-3')),
      );
      await _waitForList(tester);
      const List<String> all = <String>['u-anna', 'b-iryna', 'u-olha'];
      expect(_order(tester, all), all);
      final int listCalls = fb.clientListCalls.length;

      await _swipeRemove(tester, 'b-iryna');
      await AppHarness.pumpUntilFound(tester, _row('b-iryna'));
      expect(fb.clientRemovalCalls, <String>[
        'remove $_kSalonList {guestBookingId: b-iryna}',
      ]);
      expect(fb.clientListCalls.length, listCalls, reason: 'no refetch');
      expect(_order(tester, all), all, reason: 'back at its former index');
      expectVelvetSnack(
        _l10n.clientsRemoveFailed,
        variant: VelvetSnackVariant.error,
      );
      expect(find.textContaining('FAKE-'), findsNothing);
      expect(find.text(_l10n.clientsRemovedSnack), findsNothing);
      expect(_undo, findsNothing);
      await pumpPastVelvetSnack(tester);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('(b) INDEPENDENT_MASTER: card «⋯» → «Прибрати зі списку» → back '
      'on the list without the row + the undo snack → «Повернути» → row back', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      // The guest card is keyed by `booking-1`, the fake's seeded booking
      // (the card's «⋯» gate reads it).
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.independentMaster
        ..bookingClientIsGuest = true
        ..wireClientList()
        ..wireClientListRemovals();
      seedClientCardForBooking1(fb);
      fb.clientRows
        ..clear()
        ..add(_registeredRow('u-anna', 'Анна Перша'))
        ..add(
          _guestRow('booking-1', '${fb.clientFirstName} ${fb.clientLastName}'),
        );
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await AppHarness.settle(tester);
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('master-nav-tile-3')),
      );
      await _waitForList(tester);
      AppHarness.expectLocation(router, RouteNames.masterClients);

      await AppHarness.tapVisible(tester, _row('booking-1'));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.nameKey),
      );
      await AppHarness.settle(tester);
      await openClientCardMore(tester);
      await AppHarness.settle(tester);
      expect(find.byKey(ClientActionsSheet.removeKey), findsOneWidget);
      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientActionsSheet.removeKey),
      );

      await AppHarness.pumpUntilFound(tester, find.byType(VelvetSnack));
      await pumpVelvetSnackIn(tester);
      await AppHarness.pumpUntilGone(tester, find.byType(ClientCardScreen));
      _expectUndoSnack();
      AppHarness.expectLocation(router, RouteNames.masterClients);
      expect(fb.clientRemovalCalls, <String>[
        'remove $_kMeList {guestBookingId: booking-1}',
      ]);
      // The list refetched after the write; the row is gone, the other stays.
      await AppHarness.pumpUntilGone(tester, _row('booking-1'));
      expect(_row('u-anna'), findsOneWidget);

      await tester.tap(_undo);
      await AppHarness.pumpUntilFound(tester, _row('booking-1'));
      await AppHarness.pumpUntilGone(tester, find.byType(VelvetSnack));
      await AppHarness.settle(tester);
      expect(_row('booking-1'), findsOneWidget);
      expect(fb.clientRemovalCalls, <String>[
        'remove $_kMeList {guestBookingId: booking-1}',
        'restore $_kMeList {guestBookingId: booking-1}',
      ]);
      expect(tester.takeException(), isNull);
    });
  });
}
