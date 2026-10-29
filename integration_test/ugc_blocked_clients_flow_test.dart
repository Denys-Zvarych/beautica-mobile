// Phase 426 (+ 425 follow-ups) (Step 2.7 Rule 3b) — fake-backed E2E for the
// «Заблоковані клієнти» list and the booking-detail block / unblock on the
// REAL wire: NO repository override — the real `HttpClientBlockRepository`
// over the generated `BlockControllerApi` talks to `FakeBackend`'s stateful
// `/api/v1/blocks` routes, so the asserted request counts are HTTP requests.
//
//   (a) INDEPENDENT_MASTER: menu → «Акаунт» → «Заблоковані клієнти» → list
//       with a CLIENT row (no phone line) and a GUEST row (server-masked
//       phone) in the server's order → «Розблокувати» → confirm → ONE
//       `DELETE /blocks/{id}` → the row is gone (list refetched) + snack.
//       Empty list → the empty notice. SALON_ADMIN sees the row; SALON_MASTER
//       and CLIENT do not.
//   (b) «Деталі запису»: a blocked client → «Розблокувати клієнта» → ONE
//       DELETE of `clientBlockId`, no POST, and the refreshed detail offers
//       «Заблокувати» again; block → ONE POST → refreshed detail offers
//       «Розблокувати». A walk-in the server marks `clientBlockable: false`
//       (registered client) → report only, no block row.
//   (c) 429 on a block write → the «Забагато змін блокувань» snack, one
//       request, nothing changed (detail block + list unblock).
//
// Runs headless: `flutter test integration_test/
// ugc_blocked_clients_flow_test.dart -d flutter-tester`.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_counterparty_header.dart';
import 'package:beautica_mobile/features/moderation/presentation/blocked_clients_screen.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/block_confirm_dialog.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/content_actions_sheet.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('uk'));

const Key _row = Key('row-blocked-clients');
final Finder _clientMore = find.byKey(BookingCounterpartyHeader.clientMoreKey);

Key _card(String id) => ValueKey<String>('blocked-card-$id');
Key _phone(String id) => ValueKey<String>('blocked-phone-$id');
Key _unblock(String id) => ValueKey<String>('blocked-unblock-$id');

/// Backend 397 `BlockResponse` rows, newest first (the server's order).
List<Map<String, dynamic>> _seedRows() => <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 'block-guest',
    'kind': 'GUEST',
    'displayName': 'Оксана К.',
    'maskedPhone': '+380 •• ••• 12 34',
    'createdAt': '2026-06-12T09:00:00Z',
  },
  <String, dynamic>{
    'id': 'block-client',
    'kind': 'CLIENT',
    'displayName': 'Ірина Мельник',
    'createdAt': '2026-06-01T09:00:00Z',
  },
];

void _expectSnack(String text) => expect(
  find.descendant(of: find.byType(VelvetSnack), matching: find.text(text)),
  findsOneWidget,
);

/// INDEPENDENT_MASTER: profile → menu → «Акаунт» → «Заблоковані клієнти».
Future<GoRouter> _openListViaMenu(WidgetTester tester, FakeBackend fb) async {
  final GoRouter router = await AppHarness.boot(tester, fb);
  await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
  await AppHarness.settle(tester);
  await AppHarness.tapVisible(tester, find.byKey(const Key('btn-menu-master')));
  await AppHarness.settle(tester);
  await AppHarness.tapVisible(tester, find.byKey(const Key('row-account')));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.settings);
  await AppHarness.tapVisible(tester, find.byKey(_row));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.blockedClients);
  expect(find.byType(BlockedClientsScreen), findsOneWidget);
  return router;
}

/// Logs [role] in and opens the «Акаунт» page directly.
Future<void> _openSettingsAs(
  WidgetTester tester,
  FakeBackend fb,
  UserRole role,
) async {
  final GoRouter router = await AppHarness.boot(tester, fb);
  await AppHarness.loginAs(tester, fb, role);
  await AppHarness.settle(tester);
  unawaited(router.push(RouteNames.settings));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.settings);
  // A row that every role's «Акаунт» page carries — proves the page rendered,
  // so an absent blocked-clients row is a real absence.
  expect(find.byKey(const Key('row-change-password')), findsOneWidget);
}

Future<void> _bootDetail(WidgetTester tester, FakeBackend fb) async {
  final GoRouter router = await AppHarness.boot(tester, fb);
  await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
  unawaited(router.push(RouteNames.masterBookingDetail('booking-1')));
  await AppHarness.settle(tester);
  expect(find.byType(BookingDetailScreen), findsOneWidget);
}

Future<void> _openClientSheet(WidgetTester tester) async {
  await AppHarness.pumpUntilFound(tester, _clientMore);
  await AppHarness.tapVisible(tester, _clientMore);
  await AppHarness.settle(tester);
  expect(find.byType(ClientActionsSheet), findsOneWidget);
}

/// Closes an open bottom sheet by tapping the barrier above it.
Future<void> _dismissSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(20, 20));
  await AppHarness.settle(tester);
  expect(find.byType(ClientActionsSheet), findsNothing);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  // ── (a) «Заблоковані клієнти» ────────────────────────────────────────────

  testWidgets('INDEPENDENT_MASTER: menu → «Акаунт» → «Заблоковані клієнти» '
      'lists the CLIENT (no phone) and the GUEST (masked phone) newest first; '
      '«Розблокувати» → confirm → ONE DELETE → row gone + snack', (
    tester,
  ) async {
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster;
    fb.blocks.addAll(_seedRows());
    await _openListViaMenu(tester, fb);

    expect(find.byKey(_card('block-guest')), findsOneWidget);
    expect(find.byKey(_card('block-client')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(_card('block-guest'))).dy,
      lessThan(tester.getTopLeft(find.byKey(_card('block-client'))).dy),
      reason: 'server order (newest first) is kept',
    );
    expect(
      tester.widget<Text>(find.byKey(_phone('block-guest'))).data,
      '+380 •• ••• 12 34',
    );
    expect(find.byKey(_phone('block-client')), findsNothing);
    expect(find.byKey(BlockedClientsScreen.emptyKey), findsNothing);

    final int listsBefore = fb.blockListCalls;
    await AppHarness.tapVisible(tester, find.byKey(_unblock('block-guest')));
    await AppHarness.settle(tester);
    expect(find.byType(UnblockClientDialog), findsOneWidget);
    expect(fb.blockDeleteIds, isEmpty, reason: 'nothing before confirming');

    await tester.tap(find.byKey(UnblockClientDialog.confirmKey));
    await AppHarness.settle(tester);

    expect(fb.blockDeleteIds, <String>['block-guest']);
    expect(fb.blockPostBookingIds, isEmpty);
    expect(fb.blockListCalls, greaterThan(listsBefore), reason: 'refetched');
    expect(find.byKey(_card('block-guest')), findsNothing);
    expect(find.byKey(_card('block-client')), findsOneWidget);
    _expectSnack(_l10n.clientUnblockedSnack);
    await pumpPastVelvetSnack(tester);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('INDEPENDENT_MASTER with no blocks: the empty notice, no '
      'cards', (tester) async {
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster;
    await _openListViaMenu(tester, fb);

    expect(find.byKey(BlockedClientsScreen.emptyKey), findsOneWidget);
    expect(find.text(_l10n.blockedClientsEmptyTitle), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(fb.blockListCalls, 1);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('SALON_ADMIN: «Акаунт» shows the «Заблоковані клієнти» row '
      '(salon list)', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.salonAdmin;
    await _openSettingsAs(tester, fb, UserRole.salonAdmin);
    expect(find.byKey(_row), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 90)));

  for (final UserRole role in <UserRole>[
    UserRole.salonMaster,
    UserRole.client,
  ]) {
    testWidgets(
      '${role.name}: «Акаунт» has NO «Заблоковані клієнти» row',
      (tester) async {
        final FakeBackend fb = FakeBackend()..currentRole = role;
        await _openSettingsAs(tester, fb, role);
        expect(find.byKey(_row), findsNothing);
        expect(fb.blockListCalls, 0);
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  }

  // ── (b) «Деталі запису» on the wire ──────────────────────────────────────

  testWidgets('blocked client on «Деталі запису»: «Розблокувати клієнта» → '
      'ONE DELETE of clientBlockId, no POST; the refreshed detail offers '
      '«Заблокувати» again', (tester) async {
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster
      ..bookingClientBlockId = 'block-client';
    fb.blocks.addAll(_seedRows());
    await _bootDetail(tester, fb);

    await _openClientSheet(tester);
    expect(find.byKey(ClientActionsSheet.blockKey), findsNothing);
    await AppHarness.tapVisible(
      tester,
      find.byKey(ClientActionsSheet.unblockKey),
    );
    await AppHarness.settle(tester);
    await tester.tap(find.byKey(UnblockClientDialog.confirmKey));
    await AppHarness.settle(tester);

    expect(fb.blockDeleteIds, <String>['block-client']);
    expect(fb.blockPostBookingIds, isEmpty);
    _expectSnack(_l10n.clientUnblockedSnack);
    await pumpPastVelvetSnack(tester);

    await _openClientSheet(tester);
    expect(find.byKey(ClientActionsSheet.blockKey), findsOneWidget);
    expect(find.byKey(ClientActionsSheet.unblockKey), findsNothing);
    await _dismissSheet(tester);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('block on «Деталі запису»: ONE POST {bookingId}; the refreshed '
      'detail offers «Розблокувати»', (tester) async {
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster;
    await _bootDetail(tester, fb);

    await _openClientSheet(tester);
    await AppHarness.tapVisible(
      tester,
      find.byKey(ClientActionsSheet.blockKey),
    );
    await AppHarness.settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(BlockClientDialog.confirmKey),
        matching: find.text(_l10n.blockDialogConfirm),
      ),
    );
    await AppHarness.settle(tester);

    expect(fb.blockPostBookingIds, <String>['booking-1']);
    expect(fb.blockDeleteIds, isEmpty);
    _expectSnack(_l10n.clientBlockedSnack);
    await pumpPastVelvetSnack(tester);

    await _openClientSheet(tester);
    expect(find.byKey(ClientActionsSheet.unblockKey), findsOneWidget);
    expect(find.byKey(ClientActionsSheet.blockKey), findsNothing);
    await _dismissSheet(tester);
  }, timeout: const Timeout(Duration(seconds: 90)));

  // Backend 398 — a NEW block DECLINEs the client's future visits in scope
  // and answers only their COUNT. The real journey: «Мої записи» day list →
  // card → «Деталі запису» → block → the plural snack names the count (and
  // replaces «Клієнта заблоковано») → back → the cancelled visit is gone from
  // the day list (DECLINED is hidden by default), refetched on the REAL wire.
  testWidgets('block that auto-cancels visits: «Скасовано 3 записи» snack, '
      'and back on «Мої записи» the cancelled visit has left the day list', (
    tester,
  ) async {
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster
      // On the harness's pinned «today» so the landing day shows the card
      // (fixture clock == app clock — M15).
      ..bookingStartsAt = kFixedNow
          .add(const Duration(hours: 1))
          .toIso8601String()
      ..bookingEndsAt = kFixedNow
          .add(const Duration(hours: 2, minutes: 30))
          .toIso8601String()
      ..blockCancelsFutureVisits = 3;
    final GoRouter router = await AppHarness.boot(tester, fb);
    // A working window on the landing day (opening at 15:00 Kyiv = kFixedNow,
    // so the 16:00 card sits inside the grid's first viewport), or the grid
    // hides the card. Seeded after boot: `kyivToday` needs the time zones
    // `AppHarness.boot` initialises.
    fb.seedEffectiveSchedule(<Map<String, dynamic>>[
      FakeBackend.seedEffectiveScheduleDay(
        kyivToday(() => kFixedNow),
        intervals: const <(String, String)>[('15:00:00', '21:00:00')],
      ),
    ]);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
    await tester.tap(find.byKey(const Key('master-nav-tile-1')));
    await AppHarness.settle(tester);
    expect(find.byType(MasterBookingsScreen), findsOneWidget);

    final Finder card = find.byKey(const Key('master-booking-card-booking-1'));
    await AppHarness.pumpUntilFound(tester, card);
    await AppHarness.tapVisible(tester, card);
    await AppHarness.settle(tester);
    expect(find.byType(BookingDetailScreen), findsOneWidget);

    await _openClientSheet(tester);
    await AppHarness.tapVisible(
      tester,
      find.byKey(ClientActionsSheet.blockKey),
    );
    await AppHarness.settle(tester);
    final int listCallsBefore = fb.getMyBookingsCalls;
    await tester.tap(
      find.descendant(
        of: find.byKey(BlockClientDialog.confirmKey),
        matching: find.text(_l10n.blockDialogConfirm),
      ),
    );
    await AppHarness.settle(tester);

    expect(fb.blockPostBookingIds, <String>['booking-1']);
    expect(fb.bookingStatus, 'DECLINED', reason: 'server-side cascade ran');
    _expectSnack(_l10n.clientBlockCancelledBookingsSnack(3));
    // i18n-finder-ok: pins the uk `few` plural form on the real snack
    expect(find.text('Скасовано 3 записи'), findsOneWidget);
    expect(find.text(_l10n.clientBlockedSnack), findsNothing);
    await pumpPastVelvetSnack(tester);

    router.pop();
    await AppHarness.settle(tester);
    expect(find.byType(MasterBookingsScreen), findsOneWidget);
    await AppHarness.pumpUntilGone(tester, card);
    expect(card, findsNothing);
    expect(
      fb.getMyBookingsCalls,
      greaterThan(listCallsBefore),
      reason: 'the day list refetched after the bulk cancel',
    );
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('walk-in the server marks clientBlockable=false (registered '
      'client): the sheet offers report only — no block row', (tester) async {
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster
      ..bookingClientBlockable = false;
    await _bootDetail(tester, fb);

    await _openClientSheet(tester);
    expect(find.byKey(ClientActionsSheet.reportKey), findsOneWidget);
    expect(find.byKey(ClientActionsSheet.blockKey), findsNothing);
    expect(find.byKey(ClientActionsSheet.unblockKey), findsNothing);
    await _dismissSheet(tester);
    expect(fb.blockPostBookingIds, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 90)));

  // ── (c) 429 ──────────────────────────────────────────────────────────────

  testWidgets('429 on block: «Забагато змін блокувань» snack, ONE POST (no '
      'retry), the detail still offers «Заблокувати»', (tester) async {
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster
      ..blockWriteFailureStatusCode = 429;
    await _bootDetail(tester, fb);

    await _openClientSheet(tester);
    await AppHarness.tapVisible(
      tester,
      find.byKey(ClientActionsSheet.blockKey),
    );
    await AppHarness.settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(BlockClientDialog.confirmKey),
        matching: find.text(_l10n.blockDialogConfirm),
      ),
    );
    await AppHarness.settle(tester);

    expect(fb.blockPostBookingIds, <String>['booking-1']);
    _expectSnack(_l10n.clientBlockErrRateLimited);
    expect(find.text(_l10n.clientBlockedSnack), findsNothing);
    await pumpPastVelvetSnack(tester);

    await _openClientSheet(tester);
    expect(find.byKey(ClientActionsSheet.blockKey), findsOneWidget);
    await _dismissSheet(tester);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('429 on unblock from the list: rate-limit snack, ONE DELETE, '
      'the row stays', (tester) async {
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster;
    fb.blocks.addAll(_seedRows());
    fb.blockWriteFailureStatusCode = 429;
    await _openListViaMenu(tester, fb);

    await AppHarness.tapVisible(tester, find.byKey(_unblock('block-client')));
    await AppHarness.settle(tester);
    await tester.tap(find.byKey(UnblockClientDialog.confirmKey));
    await AppHarness.settle(tester);

    expect(fb.blockDeleteIds, <String>['block-client']);
    _expectSnack(_l10n.clientBlockErrRateLimited);
    expect(find.byKey(_card('block-client')), findsOneWidget);
    await pumpPastVelvetSnack(tester);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
