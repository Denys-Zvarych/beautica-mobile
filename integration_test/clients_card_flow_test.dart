// M510 / client-profile audit — the client card E2E flows split out of
// `clients_tab_flow_test.dart` (>180 s; no assertion changes): (g) card
// states, (h) two bookings → two rows, (i) «⋯» → block, and the
// cross-screen freshness tests (j)–(n). Scenario descriptions: the header of
// `clients_tab_flow_test.dart`. Shared seeds/helpers:
// `support/clients_flow_support.dart`.
//
// NO PATROL FLOW: nothing here touches an OS permission dialog, deep link,
// notification, WebView or biometric (mobile-qa explicit statement).

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/client_rating_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/phone_link.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/blocked_tag.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_avatar.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/rating_body.dart';
import 'package:beautica_mobile/features/clients/presentation/clients_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_list_row.dart';
import 'package:beautica_mobile/features/moderation/presentation/blocked_clients_screen.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/block_confirm_dialog.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/content_actions_sheet.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_photo_viewer.dart';
import 'package:beautica_mobile/shared/widgets/profile_photo_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/fake_backend.dart';
import 'support/clients_flow_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('(g) INDEPENDENT_MASTER card states: blocked tag, the visit '
      'timeline pages on scroll, a rated client\'s summary-only rating page, an '
      'unknown client → not found', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()..wireClientList();
      seedClientsRoster(fb);
      seedEdgeClientCards(fb);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await AppHarness.settle(tester);
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('master-nav-tile-3')),
      );
      await waitForClientList(tester);

      // ── blocked card + timeline paging ──────────────────────────────
      await AppHarness.tapVisible(tester, clientRow('u-2'));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.nameKey),
      );
      AppHarness.expectLocation(router, '/master/clients/user/u-2');
      expect(find.byKey(BlockedTag.tagKey), findsOneWidget);
      // No photo → the monogram: no preview wrapper, a tap opens nothing.
      expect(find.byType(ClientAvatar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ProfilePhotoPreviewTap),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
        reason: 'a monogram is not tappable',
      );
      await tester.tap(find.byType(ClientAvatar), warnIfMissed: false);
      await AppHarness.settle(tester);
      expect(find.byType(PortfolioPhotoViewer), findsNothing);
      expect(find.byKey(ClientCardScreen.nameKey), findsOneWidget);
      expect(find.byKey(ClientCardScreen.phoneChipKey), findsOneWidget);
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.visitKey('booking-1')),
      );
      expect(find.byKey(ClientCardScreen.nextVisitKey), findsNothing);
      expect(clientVisitsPageCalled(fb, 1), isFalse);

      // A visit card → booking detail of its first item → back to the card.
      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientCardScreen.visitKey('booking-1')),
      );
      await AppHarness.pumpUntilFound(tester, find.byType(BookingDetailScreen));
      AppHarness.expectLocation(router, '/master/bookings/booking-1');
      await AppHarness.settle(tester);
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('booking-detail-back')),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.visitKey('booking-1')),
      );
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, '/master/clients/user/u-2');

      await tester.drag(clientCardScroll(), const Offset(0, -3000));
      await AppHarness.pumpUntilCondition(
        tester,
        () => clientVisitsPageCalled(fb, 1),
        description: 'visits page 2 requested on scroll',
      );
      await AppHarness.settle(tester);
      await tester.drag(clientCardScroll(), const Offset(0, -3000));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.visitKey('bk-h24')),
      );
      await tester.drag(clientCardScroll(), const Offset(0, -3000));
      await AppHarness.settle(tester);
      expect(
        clientVisitsPageCalled(fb, 2),
        isFalse,
        reason: 'the history is exhausted after page 2',
      );

      // ── rating page: summary only (CLI-60) ──────────────────────────
      await tester.drag(clientCardScroll(), const Offset(0, 20000));
      await AppHarness.settle(tester);
      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientCardScreen.ratingChipKey),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(RatingBody.averageKey),
      );
      AppHarness.expectLocation(router, '/master/clients/user/u-2/rating');
      expect(
        tester.widget<Text>(find.byKey(RatingBody.averageKey)).data,
        '4,0',
      );
      expect(find.byKey(RatingBody.privacyNoteKey), findsOneWidget);
      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientRatingScreen.backKey),
      );
      await AppHarness.settle(tester);
      await AppHarness.tapVisible(tester, find.byKey(ClientCardScreen.backKey));
      await AppHarness.settle(tester);
      expect(find.byKey(ClientsScreen.listKey), findsOneWidget);

      // ── unknown client → the uniform not-found, back to the list ────
      await AppHarness.tapVisible(tester, clientRow('u-3'));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.notFoundKey),
      );
      AppHarness.expectLocation(router, '/master/clients/user/u-3');
      expect(find.byKey(ClientCardScreen.nameKey), findsNothing);
      expect(find.byKey(const Key('error_state_retry_button')), findsNothing);
      await AppHarness.tapVisible(tester, find.byKey(ClientCardScreen.backKey));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.masterClients);
      expect(find.byKey(ClientsScreen.listKey), findsOneWidget);
    });
  });

  testWidgets('(h) two bookings made together show as TWO rows, each opening '
      'its OWN booking detail; the phone is formatted on the card only (none '
      'on the detail), tel: stays canonical', (tester) async {
    await mockNetworkImagesFor(() async {
      final MockClientsUrlLauncher launcher = MockClientsUrlLauncher();
      final UrlLauncherPlatform original = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = original);
      registerFallbackValue(const LaunchOptions());
      when(
        () => launcher.launchUrl(any(), any()),
      ).thenAnswer((_) async => true);

      const String phone = '+380931112233';
      const String phoneShown = '+380 93 111 22 33';
      const String at1 = '2026-06-10T10:00:00Z';
      const String at2 = '2026-06-10T11:00:00Z';
      final FakeBackend fb = FakeBackend()
        ..wireClientList()
        ..bookingClientPhone = phone;
      seedClientsRoster(fb);
      seedClientCards(
        fb,
        more: () {
          fb.clientCards['u-4'] = <String, dynamic>{
            'kind': 'REGISTERED',
            'userId': 'u-4',
            'displayName': 'Клієнтка Номер4',
            'phone': phone,
            'blocked': false,
            'ratingCount': 0,
            'ratingDistribution': <Map<String, int>>[],
          };
          // The API groups the two bookings of one appointment into ONE visit;
          // `booking-1` / `booking-2` are the fake's two seeded detail ids.
          fb.clientVisits['u-4'] = <Map<String, dynamic>>[
            <String, dynamic>{
              'visitKey': 'appt-1',
              'startsAt': at1,
              'items': <Map<String, dynamic>>[
                <String, dynamic>{
                  'bookingId': 'booking-1',
                  'serviceName': 'Манікюр з покриттям',
                  'status': 'COMPLETED',
                  'startsAt': at1,
                  'priceAtBooking': 650,
                },
                <String, dynamic>{
                  'bookingId': 'booking-2',
                  'serviceName': 'Дизайн нігтів',
                  'status': 'CANCELLED',
                  'startsAt': at2,
                  'priceAtBooking': 400,
                },
              ],
            },
          ];
        },
      );
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await AppHarness.settle(tester);
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('master-nav-tile-3')),
      );
      await waitForClientList(tester);
      await AppHarness.tapVisible(tester, clientRow('u-4'));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.nameKey),
      );
      AppHarness.expectLocation(router, '/master/clients/user/u-4');
      await AppHarness.settle(tester);

      // ── card phone: formatted chip + sheet title, canonical tel: ──────
      final Finder chip = find.byKey(ClientCardScreen.phoneChipKey);
      expect(
        find.descendant(of: chip, matching: find.text(phoneShown)),
        findsOneWidget,
      );
      expect(find.text(phone), findsNothing);
      await AppHarness.tapVisible(tester, chip);
      await AppHarness.pumpUntilFound(tester, find.byKey(kPhoneSheetCallKey));
      expect(find.text(phoneShown), findsNWidgets(2), reason: 'chip + title');
      await AppHarness.tapVisible(tester, find.byKey(kPhoneSheetCallKey));
      await AppHarness.settle(tester);
      expect(
        verify(() => launcher.launchUrl(captureAny(), any())).captured.single,
        'tel:$phone',
      );

      // ── one row per booking, newest first, no grouped row ─────────────
      final Finder row1 = find.byKey(ClientCardScreen.visitKey('booking-1'));
      final Finder row2 = find.byKey(ClientCardScreen.visitKey('booking-2'));
      await AppHarness.pumpUntilFound(tester, row1);
      expect(row2, findsOneWidget);
      expect(find.byKey(ClientCardScreen.visitKey('appt-1')), findsNothing);
      expect(
        tester.getTopLeft(row2).dy,
        lessThan(tester.getTopLeft(row1).dy),
        reason: 'the 11:00 booking sits above the 10:00 one',
      );
      expect(
        // i18n-finder-ok: fixture service name (server data, not UI copy)
        find.descendant(of: row1, matching: find.text('Дизайн нігтів')),
        findsNothing,
      );

      // ── row 1 → ITS detail (no phone there since 2026-11-21) → back ───
      await AppHarness.tapVisible(tester, row1);
      await AppHarness.pumpUntilFound(tester, find.byType(BookingDetailScreen));
      AppHarness.expectLocation(router, '/master/bookings/booking-1');
      await AppHarness.settle(tester);
      expect(find.byKey(const Key('booking-detail-guest-phone')), findsNothing);
      expect(find.text(phoneShown), findsNothing);
      expect(find.text(phone), findsNothing);
      verifyNever(() => launcher.launchUrl(any(), any()));
      expect(fb.getSiblingBookingDetailCalls, 0);
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('booking-detail-back')),
      );
      await AppHarness.pumpUntilFound(tester, row2);
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, '/master/clients/user/u-4');

      // ── row 2 → ITS OWN detail, not the first booking's ───────────────
      await AppHarness.tapVisible(tester, row2);
      await AppHarness.pumpUntilFound(tester, find.byType(BookingDetailScreen));
      AppHarness.expectLocation(router, '/master/bookings/booking-2');
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.getSiblingBookingDetailCalls > 0,
        description: 'booking-2 detail fetched',
      );
      await AppHarness.settle(tester);
      expect(
        find.descendant(
          of: find.byType(BookingDetailScreen),
          matching: find.textContaining('Дизайн нігтів'),
        ),
        findsWidgets,
      );
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('booking-detail-back')),
      );
      await AppHarness.pumpUntilFound(tester, row1);
      AppHarness.expectLocation(router, '/master/clients/user/u-4');
    });
  });

  testWidgets('(i) INDEPENDENT_MASTER card «⋯» → block → «Заблоковано» '
      '(through the newest visit\'s booking, the detail\'s own flow)', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      const String userId = 'u-blk';
      final FakeBackend fb = FakeBackend()..bookingRegisteredClientId = userId;
      seedClientCards(
        fb,
        more: () {
          fb.clientCards[userId] = <String, dynamic>{
            'kind': 'REGISTERED',
            'userId': userId,
            'displayName': 'Клієнтка Блок',
            'blocked': false,
            'ratingCount': 0,
            'ratingDistribution': <Map<String, int>>[],
          };
          // `booking-1` is the fake's seeded detail (its client = [userId]).
          fb.clientVisits[userId] = <Map<String, dynamic>>[
            <String, dynamic>{
              'visitKey': 'booking-1',
              'startsAt': '2026-06-10T10:00:00Z',
              'items': <Map<String, dynamic>>[
                <String, dynamic>{
                  'bookingId': 'booking-1',
                  'serviceName': 'Манікюр',
                  'status': 'COMPLETED',
                  'startsAt': '2026-06-10T10:00:00Z',
                  'priceAtBooking': 650,
                },
              ],
            },
          ];
        },
      );
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await AppHarness.settle(tester);
      unawaited(router.push('/master/clients/user/$userId'));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.nameKey),
      );
      await AppHarness.settle(tester);
      expect(find.byKey(BlockedTag.tagKey), findsNothing);

      await AppHarness.tapVisible(tester, find.byKey(ClientCardScreen.moreKey));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientActionsSheet.blockKey),
      );
      expect(find.byKey(ClientActionsSheet.reportKey), findsOneWidget);
      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientActionsSheet.blockKey),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(BlockClientDialog.confirmKey),
      );
      // The fake card body is static: the server now reports the block.
      fb.clientCards[userId]!['blocked'] = true;
      final int cardReads = fb.clientCardCalls
          .where((String c) => c.startsWith('card '))
          .length;
      await AppHarness.tapVisible(
        tester,
        find.byKey(BlockClientDialog.confirmKey),
      );
      await AppHarness.pumpUntilFound(tester, find.byKey(BlockedTag.tagKey));
      await AppHarness.settle(tester);

      expect(fb.blockPostBookingIds, <String>['booking-1']);
      expect(
        fb.clientCardCalls.where((String c) => c.startsWith('card ')).length,
        greaterThan(cardReads),
        reason: 'the card re-read after the block',
      );
      expect(find.byKey(BlockedTag.tagKey), findsOneWidget);
    });
  });

  testWidgets(
    '(f) search over-length is cut to 50 on the wire; a failed page 2 '
    'keeps the list and is not hammered',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend()..wireClientList();
        seedClientsRoster(fb);
        seedClientCards(fb);
        await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
        await AppHarness.settle(tester);
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('master-nav-tile-3')),
        );
        await waitForClientList(tester);

        // 60 chars typed → the field keeps 50 → exactly one 50-char `q`.
        await searchClients(tester, 'я' * 60);
        await AppHarness.pumpUntilCondition(
          tester,
          () => fb.clientListCalls.last.q != null,
          description: 'the debounced search request',
        );
        expect(fb.clientListCalls.last.q, 'я' * 50);
        expect(
          fb.clientListCalls.every(
            (ClientListCall c) => (c.q ?? '').length <= 50,
          ),
          isTrue,
        );

        // Back to the full roster, then fail page 2.
        await searchClients(tester, '');
        await AppHarness.pumpUntilCondition(
          tester,
          () =>
              fb.clientListCalls.last.q == null &&
              clientRow('u-oksana').evaluate().isNotEmpty,
          description: 'the unfiltered list after clearing the search',
        );
        fb.clientFailPages.add(1);
        await tester.drag(
          find.byKey(ClientsScreen.listKey),
          const Offset(0, -3000),
        );
        await AppHarness.pumpUntilCondition(
          tester,
          () => fb.clientListCalls.any((ClientListCall c) => c.page == 1),
          description: 'page 2 requested on scroll',
        );
        await AppHarness.settle(tester);
        final int page2 = fb.clientListCalls
            .where((ClientListCall c) => c.page == 1)
            .length;

        expect(find.byKey(ClientsScreen.errorKey), findsNothing);
        expect(find.byKey(ClientsScreen.listKey), findsOneWidget);
        expect(
          find.byKey(const Key('my_bookings_load_more_spinner')),
          findsNothing,
        );
        await tester.drag(
          find.byKey(ClientsScreen.listKey),
          const Offset(0, -300),
        );
        await AppHarness.settle(tester);
        expect(
          fb.clientListCalls.where((ClientListCall c) => c.page == 1),
          hasLength(page2),
          reason: 'no retry storm on scroll',
        );

        // The append failure has a UI: tap the retry footer, page 2 loads.
        expect(
          find.byKey(ClientsScreen.loadMoreRetryKey),
          findsOneWidget,
          reason: 'the failed page 2 shows a retry footer',
        );
        expect(
          clientRow('u-24'),
          findsNothing,
          reason: 'page 2 has not landed',
        );
        fb.clientFailPages.clear();
        await AppHarness.tapVisible(
          tester,
          find.byKey(ClientsScreen.loadMoreRetryKey),
        );
        await AppHarness.pumpUntilCondition(
          tester,
          () =>
              fb.clientListCalls
                  .where((ClientListCall c) => c.page == 1)
                  .length ==
              page2 + 1,
          description: 'page 2 re-requested by the retry footer',
        );
        await AppHarness.settle(tester);
        expect(find.byKey(ClientsScreen.loadMoreRetryKey), findsNothing);
        await tester.drag(
          find.byKey(ClientsScreen.listKey),
          const Offset(0, -3000),
        );
        await AppHarness.settle(tester);
        expect(
          clientRow('u-24'),
          findsOneWidget,
          reason: 'row 25 came with page 2',
        );
      });
    },
  );

  testWidgets(
    '(j) card → booking detail → provider decline → back: the card\'s '
    '«Наступний візит» and the list row\'s «Наст.» are both fresh',
    (tester) async {
      await mockNetworkImagesFor(() async {
        const String userId = 'u-j';
        final FakeBackend fb = FakeBackend()..wireClientList();
        seedOneVisitClient(fb, userId, kFixedNow.add(const Duration(days: 6)));
        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
        await AppHarness.settle(tester);
        await openMasterClients(tester);
        expect(clientRowPart(userId, ClientListRow.nextKey), findsOneWidget);

        await AppHarness.tapVisible(tester, clientRow(userId));
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(ClientCardScreen.nextVisitKey),
        );
        await AppHarness.settle(tester);
        await AppHarness.tapVisible(
          tester,
          find.byKey(ClientCardScreen.nextVisitKey),
        );
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('booking-detail-decline')),
        );
        await AppHarness.settle(tester);

        await tester.tap(find.byKey(const Key('booking-detail-decline')));
        await AppHarness.settle(tester);
        await tester.enterText(
          find.byKey(const Key('cancel-booking-note-field')),
          'Audit decline',
        );
        // The fake's client reads are static: the server now has no next visit.
        ((fb.clientVisits[userId]!.first['items'] as List<Map<String, dynamic>>)
                .first)['status'] =
            'DECLINED';
        fb.clientCards[userId]!.remove('nextVisitAt');
        fb.clientRows
            .firstWhere((Map<String, dynamic> r) => r['userId'] == userId)
            .remove('nextVisitAt');
        await tester.tap(find.byKey(const Key('decline-booking-confirm')));
        await AppHarness.settle(tester);
        await AppHarness.pumpUntilGone(
          tester,
          find.byKey(const Key('booking-detail-decline')),
        );
        expect(fb.declineBookingCalls, 1);

        // Back on the card: the declined visit is history, no head any more.
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('booking-detail-back')),
        );
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(ClientCardScreen.visitKey('booking-1')),
        );
        await AppHarness.settle(tester);
        AppHarness.expectLocation(router, '/master/clients/user/$userId');
        expect(find.byKey(ClientCardScreen.nextVisitKey), findsNothing);

        // Back on the list: the row's «Наст.» is gone, «Ост.» stays.
        await AppHarness.tapVisible(
          tester,
          find.byKey(ClientCardScreen.backKey),
        );
        await waitForClientList(tester);
        expect(clientRowPart(userId, ClientListRow.lastKey), findsOneWidget);
        expect(clientRowPart(userId, ClientListRow.nextKey), findsNothing);
      });
    },
  );

  testWidgets('(k) block on the card → back: the list row shows «Заблоковано»; '
      'unblock on «Заблоковані клієнти» → back: the chip is gone', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      const String userId = 'u-k';
      final FakeBackend fb = FakeBackend()..wireClientList();
      seedOneVisitClient(fb, userId, kFixedNow.add(const Duration(days: 6)));
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await AppHarness.settle(tester);
      await openMasterClients(tester);
      expect(clientRowPart(userId, ClientListRow.blockedKey), findsNothing);

      // ── block from the card «⋯» ─────────────────────────────────────────
      await AppHarness.tapVisible(tester, clientRow(userId));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.nextVisitKey),
      );
      await AppHarness.settle(tester);
      await AppHarness.tapVisible(tester, find.byKey(ClientCardScreen.moreKey));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientActionsSheet.blockKey),
      );
      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientActionsSheet.blockKey),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(BlockClientDialog.confirmKey),
      );
      fb.clientCards[userId]!['blocked'] = true;
      fb.clientRows.firstWhere(
        (Map<String, dynamic> r) => r['userId'] == userId,
      )['blocked'] = true;
      await AppHarness.tapVisible(
        tester,
        find.byKey(BlockClientDialog.confirmKey),
      );
      await AppHarness.pumpUntilFound(tester, find.byKey(BlockedTag.tagKey));
      await AppHarness.settle(tester);
      expect(fb.blockPostBookingIds, <String>['booking-1']);

      await AppHarness.tapVisible(tester, find.byKey(ClientCardScreen.backKey));
      await waitForClientList(tester);
      expect(
        clientRowPart(userId, ClientListRow.blockedKey),
        findsOneWidget,
        reason: 'the block write dropped the cached list',
      );

      // ── unblock on «Заблоковані клієнти» ────────────────────────────────
      final String blockId = fb.blocks.first['id'] as String;
      unawaited(router.push(RouteNames.blockedClients));
      final Finder unblock = find.byKey(
        ValueKey<String>('blocked-unblock-$blockId'),
      );
      await AppHarness.pumpUntilFound(tester, unblock);
      await AppHarness.settle(tester);
      fb.clientRows.firstWhere(
        (Map<String, dynamic> r) => r['userId'] == userId,
      )['blocked'] = false;
      await AppHarness.tapVisible(tester, unblock);
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(UnblockClientDialog.confirmKey),
      );
      await tester.tap(find.byKey(UnblockClientDialog.confirmKey));
      await AppHarness.settle(tester);
      expect(fb.blockDeleteIds, <String>[blockId]);
      expect(find.byType(BlockedClientsScreen), findsOneWidget);

      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('btn-back-blocked-clients')),
      );
      await waitForClientList(tester);
      expect(clientRow(userId), findsOneWidget);
      expect(clientRowPart(userId, ClientListRow.blockedKey), findsNothing);
    });
  });

  testWidgets('(l) a failed first list load → the error state → retry → rows', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()..wireClientList();
      seedClientsRoster(fb);
      seedClientCards(fb);
      fb.clientFailPages.add(0);
      await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await AppHarness.settle(tester);
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('master-nav-tile-3')),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientsScreen.errorKey),
      );
      await AppHarness.settle(tester);
      expect(clientRow('u-oksana'), findsNothing);
      final int calls = fb.clientListCalls.length;

      fb.clientFailPages.clear();
      await AppHarness.tapVisible(
        tester,
        find.descendant(
          of: find.byKey(ClientsScreen.errorKey),
          matching: find.byKey(const Key('error_state_retry_button')),
        ),
      );
      await waitForClientList(tester);
      expect(fb.clientListCalls.length, greaterThan(calls));
      expect(fb.clientListCalls.last.page, 0);
      expect(find.byKey(ClientsScreen.errorKey), findsNothing);
      expect(clientRow('u-oksana'), findsOneWidget);
      expect(clientRow('b-iryna'), findsOneWidget);
    });
  });

  testWidgets('(m) card pull-to-refresh after a server-side change shows the '
      'fresh card and timeline', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()..wireClientList();
      seedClientsRoster(fb);
      seedClientCards(fb);
      await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await AppHarness.settle(tester);
      await openMasterClients(tester);
      await AppHarness.tapVisible(tester, clientRow('u-oksana'));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.nextVisitKey),
      );
      await AppHarness.settle(tester);
      expect(find.byKey(ClientCardScreen.visitKey('bk-v-next')), findsNothing);
      final int cardReads = fb.clientCardCalls
          .where((String c) => c.startsWith('card '))
          .length;

      // Server-side: the upcoming visit was cancelled and the name changed.
      ((fb.clientVisits['u-oksana']!.first['items']
                  as List<Map<String, dynamic>>)
              .first)['status'] =
          'CANCELLED';
      fb.clientCards['u-oksana']!['displayName'] = 'Оксана Нова';

      await tester.fling(clientCardScroll(), const Offset(0, 400), 1000);
      await AppHarness.pumpUntilGone(
        tester,
        find.byKey(ClientCardScreen.nextVisitKey),
      );
      await AppHarness.settle(tester);
      expect(
        fb.clientCardCalls.where((String c) => c.startsWith('card ')).length,
        greaterThan(cardReads),
      );
      expect(
        find.byKey(ClientCardScreen.visitKey('bk-v-next')),
        findsOneWidget,
        reason: 'the cancelled visit moved into the history',
      );
      expect(
        tester.widget<Text>(find.byKey(ClientCardScreen.nameKey)).data,
        'Оксана Нова',
      );
    });
  });

  testWidgets('(n) card → booking detail → client strip POPS back to the card: '
      'the stack does not grow and one back reaches the list', (tester) async {
    await mockNetworkImagesFor(() async {
      const String userId = 'u-n';
      final FakeBackend fb = FakeBackend()..wireClientList();
      seedOneVisitClient(fb, userId, kFixedNow.add(const Duration(days: 6)));
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await AppHarness.settle(tester);
      await openMasterClients(tester);
      await AppHarness.tapVisible(tester, clientRow(userId));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.nextVisitKey),
      );
      await AppHarness.settle(tester);
      final int cardDepth = routerStackDepth(router);

      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientCardScreen.nextVisitKey),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('booking-detail-client-strip')),
      );
      await AppHarness.settle(tester);
      expect(
        AppHarness.location(router),
        contains('$kBookingFromClientCardQuery=1'),
      );
      expect(routerStackDepth(router), cardDepth + 1);

      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('booking-detail-client-strip')),
      );
      await AppHarness.pumpUntilGone(tester, find.byType(BookingDetailScreen));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, '/master/clients/user/$userId');
      expect(routerStackDepth(router), cardDepth, reason: 'popped, not pushed');
      expect(find.byKey(ClientCardScreen.screenKey), findsOneWidget);

      await AppHarness.tapVisible(tester, find.byKey(ClientCardScreen.backKey));
      await waitForClientList(tester);
      expect(find.byKey(ClientCardScreen.screenKey), findsNothing);
      AppHarness.expectLocation(router, RouteNames.masterClients);
    });
  });
}
