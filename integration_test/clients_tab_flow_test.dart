// M509 — E2E: the «Клієнти» tab on every provider surface (CLI-46 / CLI-47).
//
// REAL router (authRedirect + role gates), REAL `HttpClientRepository` and
// generated row models over a stubbed Dio (`FakeBackend.wireClientList`); only
// the transport is faked, so the wire contract — FLAT `page`/`size`, `q` only
// when valid, `masterId` only in owner master mode — is what is asserted.
//
//   (a) SALON_OWNER → salon shell → «Клієнти» → list → search → page 2 on
//       scroll → row tap opens the card route → back keeps the tab;
//   (b) INDEPENDENT_MASTER → master bar «Клієнти» → `/masters/me/clients`;
//   (c) SALON_MASTER → `/staff/clients` → `/masters/me/clients`, NEVER the
//       salon endpoint;
//   (d) owner master mode → `/owner/master/clients` → the SALON endpoint with
//       `masterId` = the owner's own master row.
//
// M510 — the client card + «Рейтинг клієнта» on the same real router:
//   (a)  card → next visit / history → master chip (CLI-73/74: visits
//        AND the head's card re-read with masterId, M531) → «Усі майстри» (cached, no
//        re-read) → phone sheet → copy → rating page → back;
//   (a2) the guest card: `/guests/{bookingId}`, phone, unrated chip not a link;
//   (a5) exactly ONE serving master still shows the chip row (≥1, 2026-11-21);
//   (c)  SALON_MASTER: the server sends a phone, the card shows none (D5);
//   (g)  blocked tag, monogram not tappable, visit → booking detail → back, visit timeline page 2 on
//        scroll, summary-only rating page,
//        an unknown client → the uniform not-found;
//   (i)  card «⋯» → block → «Заблоковано» (2026-11-21);
//   (h)  two bookings made together → two rows (BOOK-05), each opening its
//        own booking detail; phone formatted on the card (none on the
//        detail), tel: canonical.
//
// Client-profile audit (2026-11-22) — cross-screen freshness (Rule 3b):
//   (j)  card → booking detail → provider decline → back: the card's
//        «Наступний візит» is gone (the visit drops to the history) and the
//        list row's «Наст.» is gone;
//   (k)  block on the card → back: the list row carries «Заблоковано»;
//        unblock on «Заблоковані клієнти» → back: the chip is gone;
//   (l)  list first-load error → retry → rows;
//   (m)  card pull-to-refresh after a server-side change shows fresh data;
//   (n)  card → detail → client strip POPS back to the card (stack does not
//        grow; one back reaches the list).
//
// Search: `q` is sent only for a trimmed 2–50-char term; the 300 ms debounce
// is a `Timer`, driven with an explicit `pump(kClientSearchDebounce)`
// (`pumpAndSettle` fires no Timer). 800×600 surface: the list is scrolled
// before the next row is asserted.
//
// NO PATROL FLOW: nothing here touches an OS permission dialog, deep link,
// notification, WebView or biometric (mobile-qa explicit statement).

//
// SPLIT (M531 audit): the card-state + freshness tests (g)–(n) live in
// `clients_card_flow_test.dart`; shared seeds/helpers in
// `support/clients_flow_support.dart`.

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/client_rating_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/phone_link.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/blocked_tag.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/rating_body.dart';
import 'package:beautica_mobile/features/clients/presentation/clients_screen.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_list_row.dart';
import 'package:beautica_mobile/features/moderation/data/content_report_repository.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/report_sheet.dart';
import 'package:beautica_mobile/features/master/presentation/salon_master_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/owner_own_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_photo_viewer.dart';
import 'package:beautica_mobile/shared/widgets/profile_photo_preview.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/features/moderation/support/fake_content_report_repository.dart';
import '../test/helpers/fake_media_cache.dart';
import '../test/helpers/overflow_guard.dart';
import '../test/helpers/rendered_image_url.dart';
import 'support/app_harness.dart';
import 'support/fake_backend.dart';
import 'support/clients_flow_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('(a) SALON_OWNER: shell «Клієнти» → list → search → page 2 → '
      'row opens the card → back keeps the tab', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..wireClientList();
      seedClientsRoster(fb);
      seedClientCards(fb);
      // MOD-39 — the avatar viewer's «Поскаржитися» submits here.
      final FakeContentReportRepository reports = FakeContentReportRepository();
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: <Object>[
          contentReportRepositoryProvider.overrideWithValue(reports),
        ],
      );
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.salonShell(kClientsSalonId));
      expect(
        fb.clientListCalls,
        isEmpty,
        reason: 'the tab is lazy: nothing is fetched before it is opened',
      );

      // The bar has 5 destinations and «Клієнти» is the 4th (index 3).
      expect(find.byKey(const Key('salon-nav-tile-4')), findsOneWidget);
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('salon-nav-tile-3')),
      );
      await waitForClientList(tester);

      expect(
        tester
            .widget<SalonBottomNav>(
              find.byKey(const Key('salon-shell-bottom-nav')),
            )
            .currentIndex,
        3,
      );
      // The salon-wide endpoint, FLAT paging, no `q`, no `masterId`.
      final ClientListCall first = fb.clientListCalls.first;
      expect(first.path, kClientsSalonPath);
      expect(first.page, 0);
      expect(first.size, 20);
      expect(first.q, isNull);
      expect(first.masterId, isNull);

      // Rows: rated registered client with both short dates, a guest without
      // any kind label, and no phone / completed count in the tree.
      expect(clientRow('u-oksana'), findsOneWidget);
      // i18n-finder-ok: asserts the exact approved UA copy / data value
      expect(find.text('Оксана Мельник'), findsOneWidget);
      expect(find.text('4.9'), findsOneWidget);
      // The row's short dates by key; the values pin the approved format.
      expect(
        tester
            .widget<Text>(clientRowPart('u-oksana', ClientListRow.lastKey))
            .data,
        'Ост.: 7 чер',
      );
      expect(
        tester
            .widget<Text>(clientRowPart('u-oksana', ClientListRow.nextKey))
            .data,
        'Наст.: сб, 20 чер, 15:00',
      );
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(ClientsScreen)),
      );
      expect(find.text(l10n.bookingDetailGuestBookingLabel), findsNothing);
      expect(find.textContaining('+380'), findsNothing);
      expect(clientRow('b-iryna'), findsOneWidget);

      // ── search ────────────────────────────────────────────────────────
      final int beforeShort = fb.clientListCalls.length;
      await searchClients(tester, 'О'); // 1 char: error line, NO request
      expect(fb.clientListCalls.length, beforeShort);
      expect(
        find.byKey(const Key('search_query_min_length_hint')),
        findsOneWidget,
      );

      await searchClients(tester, 'Мел');
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.clientListCalls.last.q == 'Мел',
        description: 'the debounced search request',
      );
      await AppHarness.settle(tester);
      expect(fb.clientListCalls.last.page, 0);
      expect(clientRow('u-oksana'), findsOneWidget);
      expect(clientRow('b-iryna'), findsNothing);
      expect(
        find.byKey(const Key('search_query_min_length_hint')),
        findsNothing,
      );

      // No match → notice, the field stays.
      await searchClients(tester, 'Яяяя');
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientsScreen.noMatchKey),
      );
      expect(find.byKey(ClientsScreen.searchKey), findsOneWidget);

      // Clearing the box drops `q` and brings the full roster back.
      await searchClients(tester, '');
      await AppHarness.pumpUntilCondition(
        tester,
        () =>
            fb.clientListCalls.last.q == null &&
            clientRow('u-oksana').evaluate().isNotEmpty,
        description: 'the unfiltered list after clearing the search',
      );

      // ── paging ────────────────────────────────────────────────────────
      expect(
        fb.clientListCalls.where((ClientListCall c) => c.page == 1),
        isEmpty,
      );
      await tester.drag(
        find.byKey(ClientsScreen.listKey),
        const Offset(0, -3000),
      );
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.clientListCalls.any((ClientListCall c) => c.page == 1),
        description: 'page 2 requested on scroll',
      );
      final ClientListCall second = fb.clientListCalls.firstWhere(
        (ClientListCall c) => c.page == 1,
      );
      expect(second.path, kClientsSalonPath);
      expect(second.q, isNull);
      // The list is lazy: let page 2 land, then scroll its tail into the
      // 800x600 viewport before asserting the last row exists.
      await AppHarness.settle(tester);
      await tester.drag(
        find.byKey(ClientsScreen.listKey),
        const Offset(0, -3000),
      );
      await AppHarness.pumpUntilFound(tester, clientRow('u-24'));
      expect(
        clientRow('u-24'),
        findsOneWidget,
        reason: 'row 25 came with page 2',
      );

      // The list is exhausted: no page 3.
      await tester.drag(
        find.byKey(ClientsScreen.listKey),
        const Offset(0, -3000),
      );
      await AppHarness.settle(tester);
      expect(
        fb.clientListCalls.where((ClientListCall c) => c.page == 2),
        isEmpty,
      );

      // ── row → card → back ─────────────────────────────────────────────
      await tester.drag(
        find.byKey(ClientsScreen.listKey),
        const Offset(0, 6000),
      );
      await AppHarness.settle(tester);
      // 2026-11-21 — the card carries a photo (allow-listed fixture host,
      // decodable image) so the avatar → full-screen viewer step below runs
      // on the real wire URL. Set before the tap: the card is fetched then.
      MediaConfig.debugAllowedHosts = <String>{'media.test'};
      debugMediaCacheManager = FakeMediaCacheManager(mediaLoaded);
      addTearDown(() {
        debugMediaCacheManager = null;
        MediaConfig.debugAllowedHosts = null;
      });
      fb.clientCards['u-oksana']!['avatarUrl'] = kClientsOksanaPhoto;
      await AppHarness.tapVisible(tester, clientRow('u-oksana'));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.nameKey),
      );
      AppHarness.expectLocation(
        router,
        '/salons/$kClientsSalonId/clients/user/u-oksana',
      );
      // The salon card is read through the salon endpoint, no `masterId`.
      expect(
        fb.clientCardCalls.firstWhere((String c) => c.startsWith('card ')),
        contains('/api/v1/salons/$kClientsSalonId/clients/users/u-oksana'),
      );
      expect(fb.clientCardCalls.first, endsWith('masterId=null'));
      // Read off the card's own name key: mid-push the list row behind still
      // shows the same name, so a bare text finder would see two.
      await AppHarness.settle(tester);
      expect(
        tester.widget<Text>(find.byKey(ClientCardScreen.nameKey)).data,
        'Оксана Мельник',
      );
      // The next visit is the timeline head, the past visit sits in history.
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.nextVisitKey),
      );
      expect(
        find.byKey(ClientCardScreen.visitKey('bk-v-past')),
        findsOneWidget,
      );

      // ── CLI-73 / CLI-74: master chip → filtered visits → «Усі майстри» ──
      expect(find.byKey(ClientCardScreen.masterChipsKey), findsOneWidget);
      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientCardScreen.masterChipKey(kClientsMasterB)),
      );
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.clientCardCalls.any(
          (String c) => c.startsWith('visits ') && c.endsWith(kClientsMasterB),
        ),
        description: 'the visits re-read with the chip\'s masterId',
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.visitKey('bk-v-past')),
      );
      expect(find.byKey(ClientCardScreen.nextVisitKey), findsNothing);
      expect(
        find.byKey(ClientCardScreen.masterChipKey(kClientsMasterA)),
        findsOneWidget,
        reason: 'the chips stay salon-wide',
      );
      final int callsBeforeAll = fb.clientCardCalls.length;
      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientCardScreen.masterChipAllKey),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.nextVisitKey),
      );
      // Cache-for: the salon-wide visits are reused, not re-read.
      expect(
        fb.clientCardCalls,
        hasLength(callsBeforeAll),
        reason: '«Усі майстри» reuses the cached salon-wide visits',
      );

      // ── phone chip → sheet → copy snackbar ───────────────────────────
      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientCardScreen.phoneChipKey),
      );
      await AppHarness.pumpUntilFound(tester, find.byKey(kPhoneSheetCopyKey));
      expect(find.byKey(kPhoneSheetCallKey), findsOneWidget);
      await AppHarness.tapVisible(tester, find.byKey(kPhoneSheetCopyKey));
      await AppHarness.settle(tester);
      expect(find.byKey(kPhoneSheetCopyKey), findsNothing);
      expect(
        find.text(
          AppLocalizations.of(
            tester.element(find.byType(ClientCardScreen)),
          ).clientPhoneCopied,
        ),
        findsOneWidget,
      );

      // ── rating chip → «Рейтинг клієнта» → back ───────────────────────
      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientCardScreen.ratingChipKey),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientRatingScreen.screenKey),
      );
      AppHarness.expectLocation(
        router,
        '/salons/$kClientsSalonId/clients/user/u-oksana/rating',
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(RatingBody.privacyNoteKey),
      );
      // CLI-60 — summary + distribution + note only: no «Ваші оцінки».
      // i18n-finder-ok: the removed section's heading must not render
      expect(find.text('Ваші оцінки'), findsNothing);
      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientRatingScreen.backKey),
      );
      await AppHarness.settle(tester);
      expect(find.byKey(ClientCardScreen.nameKey), findsOneWidget);
      expect(
        // The route-scope (salon-wide) card only: the master chip above read
        // its OWN chip-scoped card (M531 — the head is that card's
        // `nextVisit`, CLI-89).
        fb.clientCardCalls
            .where(
              (String c) =>
                  c.startsWith('card ') && c.endsWith('masterId=null'),
            )
            .length,
        1,
        reason: 'the rating page reuses the card — no refetch (D7)',
      );

      // ── avatar photo → full-screen viewer → back to the card ─────────
      await AppHarness.tapVisible(tester, find.byType(ProfilePhotoPreviewTap));
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(PortfolioPhotoViewer),
      );
      expect(
        renderedImageUrls(
          tester,
          within: find.byKey(PortfolioPhotoViewer.pageKey('profile')),
        ),
        <String>[kClientsOksanaPhoto],
      );
      expect(find.byKey(PortfolioPhotoViewer.indicatorKey), findsNothing);

      // ── MOD-39 / CLI-70: viewer «Поскаржитися» → report sheet → submit ─
      await AppHarness.tapVisible(
        tester,
        find.byKey(PortfolioPhotoViewer.reportKey),
      );
      await AppHarness.pumpUntilFound(tester, find.byType(ReportSheet));
      await AppHarness.tapVisible(
        tester,
        find.byKey(ReportSheet.reasonKey(ReportReason.offensive)),
      );
      await AppHarness.settle(tester);
      await AppHarness.tapVisible(tester, find.byKey(ReportSheet.submitKey));
      await AppHarness.settle(tester);
      expect(find.byType(ReportSheet), findsNothing);
      final ContentReportRequest sent = reports.requests.single;
      expect(sent.targetType, ReportTargetType.clientProfile);
      expect(sent.targetId, 'u-oksana');
      expect(sent.reason, ReportReason.offensive);
      // Reported once → the flag is gone (MOD-06); still in the viewer.
      expect(find.byType(PortfolioPhotoViewer), findsOneWidget);
      expect(find.byKey(PortfolioPhotoViewer.reportKey), findsNothing);

      await AppHarness.tapVisible(
        tester,
        find.byKey(PortfolioPhotoViewer.closeKey),
      );
      await AppHarness.settle(tester);
      expect(find.byType(PortfolioPhotoViewer), findsNothing);
      expect(find.byKey(ClientCardScreen.nameKey), findsOneWidget);
      AppHarness.expectLocation(
        router,
        '/salons/$kClientsSalonId/clients/user/u-oksana',
      );

      await AppHarness.tapVisible(tester, find.byKey(ClientCardScreen.backKey));
      await AppHarness.settle(tester);
      expect(find.byType(SalonShellScreen), findsOneWidget);
      expect(find.byKey(ClientsScreen.listKey), findsOneWidget);
      expect(
        tester
            .widget<SalonBottomNav>(
              find.byKey(const Key('salon-shell-bottom-nav')),
            )
            .currentIndex,
        3,
        reason: 'back returns to «Клієнти», not «Салон»',
      );
    });
  });

  testWidgets('(a2) a guest row opens …/guest/:bookingId', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..wireClientList();
      seedClientsRoster(fb);
      seedClientCards(fb);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);

      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('salon-nav-tile-3')),
      );
      await waitForClientList(tester);
      await AppHarness.tapVisible(tester, clientRow('b-iryna'));
      await AppHarness.pumpUntilFound(tester, find.byType(ClientCardScreen));
      AppHarness.expectLocation(
        router,
        '/salons/$kClientsSalonId/clients/guest/b-iryna',
      );

      // The SAME card for a guest (D1): read through `/guests/{bookingId}`,
      // phone chip for the owner, the unrated chip is NOT a link.
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.nameKey),
      );
      expect(
        fb.clientCardCalls.firstWhere((String c) => c.startsWith('card ')),
        contains('/api/v1/salons/$kClientsSalonId/clients/guests/b-iryna'),
      );
      // Read off the card's own name key: mid-push the list row behind still
      // shows the same name, so a bare text finder would see two.
      await AppHarness.settle(tester);
      expect(
        tester.widget<Text>(find.byKey(ClientCardScreen.nameKey)).data,
        'Ірина Коваль',
      );
      expect(find.byKey(ClientCardScreen.phoneChipKey), findsOneWidget);
      expect(find.byKey(BlockedTag.tagKey), findsNothing);
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.visitKey('bk-v-g1')),
      );
      expect(find.byKey(ClientCardScreen.nextVisitKey), findsNothing);

      await tester.tap(
        find.byKey(ClientCardScreen.ratingChipKey),
        warnIfMissed: false,
      );
      await AppHarness.settle(tester);
      expect(find.byType(ClientRatingScreen), findsNothing);
      AppHarness.expectLocation(
        router,
        '/salons/$kClientsSalonId/clients/guest/b-iryna',
      );
    });
  });

  // 2026-11-21 (CLI-73 / CLI-74) — the chips are owner AND admin: the admin's
  // own salon card shows them and a chip re-reads the visits with masterId.
  testWidgets('(a4) SALON_ADMIN: «Клієнти» → card → master chip filters the '
      'visits → «Усі майстри» restores them', (tester) async {
    await mockNetworkImagesFor(() async {
      const String adminSalon = 'salon-admin-1';
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonAdmin
        ..wireClientList(salonIds: const <String>[adminSalon]);
      seedClientsRoster(fb);
      seedClientCards(fb, salonIds: const <String>[adminSalon]);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonAdmin);
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.salonShell(adminSalon));

      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('salon-nav-tile-3')),
      );
      await waitForClientList(tester);
      expect(
        fb.clientListCalls.first.path,
        '/api/v1/salons/$adminSalon/clients',
      );

      await AppHarness.tapVisible(tester, clientRow('u-oksana'));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.nextVisitKey),
      );
      AppHarness.expectLocation(
        router,
        '/salons/$adminSalon/clients/user/u-oksana',
      );
      await AppHarness.settle(tester);
      expect(
        find.byKey(ClientCardScreen.visitKey('bk-v-past')),
        findsOneWidget,
      );

      expect(find.byKey(ClientCardScreen.masterChipsKey), findsOneWidget);
      expect(find.byKey(ClientCardScreen.masterChipAllKey), findsOneWidget);
      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientCardScreen.masterChipKey(kClientsMasterB)),
      );
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.clientCardCalls.any(
          (String c) =>
              c.startsWith('visits ') &&
              c.contains('/salons/$adminSalon/') &&
              c.endsWith(kClientsMasterB),
        ),
        description: 'the admin visits re-read with the chip\'s masterId',
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.visitKey('bk-v-past')),
      );
      expect(
        find.byKey(ClientCardScreen.nextVisitKey),
        findsNothing,
        reason: 'master B served only the past visit',
      );

      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientCardScreen.masterChipAllKey),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.nextVisitKey),
      );
    });
  });

  // 2026-11-21 (CLI-73) — the chips show with ≥1 master: a card served by
  // exactly ONE master still gets «Усі майстри» + that master's chip, and
  // the chip re-reads the visits with its masterId.
  testWidgets('(a5) SALON_ADMIN: a card with exactly ONE master shows the '
      'chip row; the chip filters the visits', (tester) async {
    await mockNetworkImagesFor(() async {
      const String adminSalon = 'salon-admin-1';
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonAdmin
        ..wireClientList(salonIds: const <String>[adminSalon]);
      seedClientsRoster(fb);
      seedClientCards(
        fb,
        salonIds: const <String>[adminSalon],
        more: () => fb.clientCards['u-oksana']!['servedByMasters'] =
            <Map<String, dynamic>>[
              <String, dynamic>{
                'masterId': kClientsMasterB,
                'name': 'Марта Бондар',
              },
            ],
      );
      await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonAdmin);
      await AppHarness.settle(tester);

      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('salon-nav-tile-3')),
      );
      await waitForClientList(tester);
      await AppHarness.tapVisible(tester, clientRow('u-oksana'));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.nextVisitKey),
      );
      await AppHarness.settle(tester);

      expect(find.byKey(ClientCardScreen.masterChipsKey), findsOneWidget);
      expect(find.byKey(ClientCardScreen.masterChipAllKey), findsOneWidget);
      expect(
        find.byKey(ClientCardScreen.masterChipKey(kClientsMasterB)),
        findsOneWidget,
      );
      expect(
        find.byKey(ClientCardScreen.masterChipKey(kClientsMasterA)),
        findsNothing,
      );

      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientCardScreen.masterChipKey(kClientsMasterB)),
      );
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.clientCardCalls.any(
          (String c) =>
              c.startsWith('visits ') &&
              c.contains('/salons/$adminSalon/') &&
              c.endsWith(kClientsMasterB),
        ),
        description: 'the visits re-read with the single chip\'s masterId',
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.visitKey('bk-v-past')),
      );
      expect(find.byKey(ClientCardScreen.nextVisitKey), findsNothing);
    });
  });

  testWidgets('(a3) SALON_OWNER «Профіль» (index 4) still leaves the shell for '
      'owner master mode', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..hasMasterProfile = true
        ..wireClientList();
      seedClientsRoster(fb);
      seedClientCards(fb);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);

      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('salon-nav-tile-4')),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(OwnerOwnProfileScreen),
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.ownerMasterProfile);
      expect(find.byType(SalonShellScreen), findsNothing);
    });
  });

  testWidgets('(b) INDEPENDENT_MASTER: master bar «Клієнти» → '
      '/masters/me/clients', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()..wireClientList();
      seedClientsRoster(fb);
      seedClientCards(fb);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await AppHarness.settle(tester);
      expect(find.byType(MasterProfileScreen), findsOneWidget);
      AppHarness.expectLocation(router, RouteNames.masterProfile);

      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('master-nav-tile-3')),
      );
      await waitForClientList(tester);

      AppHarness.expectLocation(router, RouteNames.masterClients);
      expect(
        tester
            .widget<VelvetBottomNavBar>(find.byType(VelvetBottomNavBar))
            .activeIndex,
        3,
      );
      expect(fb.clientListCalls.first.path, kClientsMasterPath);
      expect(fb.clientListCalls.first.masterId, isNull);
      expect(clientRow('u-oksana'), findsOneWidget);

      // A guest row → the guest card route below the master list.
      await AppHarness.tapVisible(tester, clientRow('b-iryna'));
      await AppHarness.pumpUntilFound(tester, find.byType(ClientCardScreen));
      AppHarness.expectLocation(router, '/master/clients/guest/b-iryna');
      await AppHarness.tapVisible(tester, find.byKey(ClientCardScreen.backKey));
      await AppHarness.settle(tester);

      // «Профіль» is now index 4 and still lands on the profile.
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('master-nav-tile-4')),
      );
      await AppHarness.pumpUntilFound(tester, find.byType(MasterProfileScreen));
      AppHarness.expectLocation(router, RouteNames.masterProfile);
    });
  });

  testWidgets('(c) SALON_MASTER: «Клієнти» → /staff/clients → '
      '/masters/me/clients, never the salon endpoint', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend(
        masterRowId: 'master-removable',
        masterSalonId: 'salon-xyz',
      )..wireClientList(salonIds: const <String>[kClientsSalonId, 'salon-xyz']);
      seedClientsRoster(fb);
      seedClientCards(fb);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonMaster);
      await AppHarness.settle(tester);
      expect(find.byType(SalonMasterProfileScreen), findsOneWidget);
      AppHarness.expectLocation(router, RouteNames.salonMasterProfile);

      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('master-nav-tile-3')),
      );
      await waitForClientList(tester);

      AppHarness.expectLocation(router, RouteNames.salonMasterClients);
      expect(fb.clientListCalls, isNotEmpty);
      expect(
        fb.clientListCalls.every(
          (ClientListCall c) => c.path == kClientsMasterPath,
        ),
        isTrue,
        reason:
            'a SALON_MASTER lists the master\'s OWN clients — the salon '
            'endpoint is owner / admin only (403)',
      );
      expect(clientRow('u-oksana'), findsOneWidget);

      await AppHarness.tapVisible(tester, clientRow('u-oksana'));
      await AppHarness.pumpUntilFound(tester, find.byType(ClientCardScreen));
      AppHarness.expectLocation(router, '/staff/clients/user/u-oksana');

      // D5 fail-closed: the fake SENDS a phone, a SALON_MASTER never sees it.
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.nameKey),
      );
      expect(
        fb.clientCardCalls.firstWhere((String c) => c.startsWith('card ')),
        contains('$kClientsMasterPath/users/u-oksana'),
      );
      expect(find.byKey(ClientCardScreen.phoneChipKey), findsNothing);
      expect(find.textContaining('+380'), findsNothing);
      expect(find.byKey(ClientCardScreen.ratingChipKey), findsOneWidget);
    });
  });

  testWidgets('(d) owner master mode: «Клієнти» → the SALON endpoint with '
      'masterId = the owner\'s own master row', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb =
          FakeBackend(
              masterRowId: kClientsOwnerMasterRowId,
              masterSalonId: kClientsSalonId,
            )
            ..currentRole = UserRole.salonOwner
            ..hasMasterProfile = true
            ..wireClientList();
      seedClientsRoster(fb);
      seedClientCards(fb);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.salonShell(kClientsSalonId));

      // Enter master mode through «Профіль» (index 4).
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('salon-nav-tile-4')),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(OwnerOwnProfileScreen),
        timeout: const Duration(seconds: 20),
      );
      AppHarness.expectLocation(router, RouteNames.ownerMasterProfile);

      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('master-nav-tile-3')),
      );
      await waitForClientList(tester);

      AppHarness.expectLocation(router, RouteNames.ownerMasterClients);
      expect(
        tester
            .widget<VelvetBottomNavBar>(find.byType(VelvetBottomNavBar))
            .activeIndex,
        3,
      );
      final ClientListCall call = fb.clientListCalls.first;
      expect(call.path, kClientsSalonPath);
      expect(call.masterId, kClientsOwnerMasterRowId);
      expect(find.byType(SalonShellScreen), findsNothing);

      // The card route is the salon-scoped one, narrowed by ?masterId=.
      await AppHarness.tapVisible(tester, clientRow('u-oksana'));
      await AppHarness.pumpUntilFound(tester, find.byType(ClientCardScreen));
      AppHarness.expectLocation(
        router,
        '/salons/$kClientsSalonId/clients/user/u-oksana?masterId=$kClientsOwnerMasterRowId',
      );
      // Owner master mode (route ?masterId=): no master chip row and no
      // «Усі майстри», even though the salon-wide servedByMasters lists the
      // owner's own row (phase 510 — the view stays scoped to the owner).
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.nameKey),
      );
      expect(find.byKey(ClientCardScreen.masterChipsKey), findsNothing);
      expect(find.byKey(ClientCardScreen.masterChipAllKey), findsNothing);
    });
  });

  testWidgets(
    '(e) an EMPTY roster shows the notice and hides the search field',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend()..wireClientList(); // no rows
        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
        await AppHarness.settle(tester);

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('master-nav-tile-3')),
        );
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(ClientsScreen.emptyKey),
          timeout: const Duration(seconds: 20),
        );
        await AppHarness.settle(tester);

        AppHarness.expectLocation(router, RouteNames.masterClients);
        expect(fb.clientListCalls.first.path, kClientsMasterPath);
        expect(find.byKey(ClientsScreen.searchKey), findsNothing);
        expect(find.byKey(ClientsScreen.listKey), findsNothing);
      });
    },
  );
}
