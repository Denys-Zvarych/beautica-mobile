// Phase 385 (24.1h) — E2E: user decision 7, end to end on the mocked
// backend. A SALON_OWNER who, in master mode, gives their OWN master row
// ≥1 active service AND a weekly schedule appears in the CLIENT's public
// salon «Команда» tab; with either missing, they do not. ONE test walks
// both sides: absent with nothing, still absent with a service alone (a
// direct read of the client's roster endpoint), present with both.
//
// THE RULE UNDER TEST
// -------------------
// Backend `GET /salons/{id}/masters` → `MasterRepository
// .findBookableIdsBySalonId` + `MasterBookabilitySql.BOOKABLE_MASTER_M`
// (≥1 active service AND hours) with NO `master_type` predicate, so the
// owner's row qualifies (pinned server-side by `OwnerMasterSelfServiceIT
// .should_showOwnerEverywhere_when_ownerSetsUpOwnServicesAndSchedule`). The
// FakeBackend mirrors it with `listOwnerRowWhenBookable`, reading the SAME
// owner-row writes this flow drives through the real UI (phase 380's
// `ownRowServices`, phase 381's `ownRowWeeklySchedule`). The mobile client
// adds no owner exclusion (`_MastersTab` only filters by service coverage).
//
// WHAT ONLY THIS TIER PROVES
// --------------------------
// The two halves meet on ONE wire endpoint across TWO sessions in ONE app
// run: the owner's master-mode writes (real «Профіль» entry → «Послуги» →
// «Графік» → «‹ Салон») and the client's public roster read. The public
// salon cache (`publicSalonProfileProvider`, 5-min keepAlive) is evicted by
// the session flip, so the client's second visit is a fresh read — a cache
// that survived logout would show the stale, owner-less roster and fail here.
//
// Every absence check reveals the WHOLE roster first («показати всіх»), so
// "absent" can never mean "beyond the 6-card first-paint cap".
//
// NO PATROL FLOW: no OS dialog, permission, notification or WebView; the
// sessions switch through the real logout rows.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_profile_screen.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/presentation/owner_own_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/public_salon_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/master_schedule_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_template_editor_screen.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_screen.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';
import 'package:dio/dio.dart' show Response;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/fakes/fake_secure_storage.dart';
import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

const String _kSalonId = FakeBackend.kOwnerSalonId;

/// The owner's `masters` ROW id — distinct from the session userId, so a
/// roster entry or a profile push keyed on the wrong id cannot match.
const String _kOwnerMasterRowId = 'master-row-owner-1';

/// A NAILS service type the setup screen renders selectable (the fixture
/// phase 380's own-row flow uses).
const String _kFreeTypeId = 'type-nails-gel';

const Key _kOwnerCard = Key('salon-master-card-$_kOwnerMasterRowId');
const Key _kShowAll = Key('salon-masters-show-all');

FakeBackend _backend() =>
    FakeBackend(
        masterRowId: _kOwnerMasterRowId,
        masterSalonId: _kSalonId,
        wireOwnRowServices: true,
        wireOwnRowSchedule: true,
        listOwnerRowWhenBookable: true,
      )
      ..currentRole = UserRole.client
      ..hasMasterProfile = true;

// ── Client session ──────────────────────────────────────────────────────────

/// Client home → the owner's salon public page → «Команда», with the whole
/// roster revealed. Returns the roster the screen decoded off the wire.
Future<List<SalonMasterSummary>> _openClientTeamTab(
  WidgetTester tester,
  GoRouter router,
  FakeBackend fb,
) async {
  final int rosterReadsBefore = fb.getSalonMastersCalls;
  unawaited(router.push(RouteNames.salonPublicProfile(_kSalonId)));
  await AppHarness.pumpUntilFound(
    tester,
    find.byType(PublicSalonProfileScreen),
  );
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.salonPublicProfile(_kSalonId));
  expect(
    fb.getSalonMastersCalls,
    greaterThan(rosterReadsBefore),
    reason: 'each client visit reads the roster fresh off the wire',
  );
  expect(fb.lastGetSalonMastersId, _kSalonId);

  await AppHarness.tapVisible(tester, find.byKey(const Key('salon-tab-1')));
  await AppHarness.settle(tester);
  // A first master card proves the tab body rendered (never vacuous).
  await AppHarness.revealPublicMasterCard(
    tester,
    find.byKey(const Key('salon-master-card-master-aaa')),
  );

  final Finder showAll = find.byKey(_kShowAll);
  if (showAll.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      showAll,
      200,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 20,
    );
  }
  await AppHarness.tapVisible(tester, showAll);
  await AppHarness.settle(tester);
  expect(showAll, findsNothing, reason: 'the whole roster is now built');

  final ProviderContainer container = ProviderScope.containerOf(
    tester.element(find.byType(PublicSalonProfileScreen)),
  );
  final PublicSalonProfileData? data = container
      .read(publicSalonProfileProvider(_kSalonId))
      .value;
  expect(data, isNotNull, reason: 'the public profile loaded');
  return data?.$2 ?? const <SalonMasterSummary>[];
}

/// Asserts the owner is NOT on the fully revealed client roster — neither
/// in the decoded data nor as a card anywhere along the lazy grid.
Future<void> _expectOwnerAbsent(
  WidgetTester tester,
  List<SalonMasterSummary> roster,
) async {
  expect(
    roster.map((SalonMasterSummary m) => m.masterId),
    isNot(contains(_kOwnerMasterRowId)),
    reason: 'a non-bookable owner row must not be served to clients',
  );
  // Sweep the lazy grid top → bottom: the card must not be built anywhere.
  final ScrollableState scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  scrollable.position.jumpTo(0);
  await AppHarness.settle(tester);
  const int maxSteps = 50;
  for (int step = 0; ; step++) {
    expect(find.byKey(_kOwnerCard), findsNothing);
    if (scrollable.position.pixels >= scrollable.position.maxScrollExtent) {
      break;
    }
    if (step >= maxSteps) {
      fail(
        'roster sweep did not reach the end of the scrollable within '
        '$maxSteps × 200px steps (pixels=${scrollable.position.pixels}, '
        'max=${scrollable.position.maxScrollExtent})',
      );
    }
    scrollable.position.jumpTo(
      (scrollable.position.pixels + 200).clamp(
        0,
        scrollable.position.maxScrollExtent,
      ),
    );
    await tester.pump();
  }
}

/// The master ids the CLIENT roster endpoint serves right now — the same
/// `GET /salons/{id}/masters` wire read [_openClientTeamTab] decodes, issued
/// directly so a mid-flow check needs no session flip.
Future<List<String>> _servedRosterIds(FakeBackend fb) async {
  final int readsBefore = fb.getSalonMastersCalls;
  final Response<dynamic> res = await fb.dio.get<dynamic>(
    '/api/v1/salons/$_kSalonId/masters',
  );
  expect(fb.getSalonMastersCalls, readsBefore + 1);
  final Map<String, dynamic> page =
      (res.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
  final List<String> ids = (page['data'] as List<dynamic>)
      .map((dynamic m) => (m as Map<String, dynamic>)['masterId'] as String)
      .toList();
  expect(ids, isNotEmpty, reason: 'the static roster is served (not vacuous)');
  return ids;
}

Future<void> _logoutClient(
  WidgetTester tester,
  GoRouter router,
  FakeBackend fb,
  FakeSecureStorage storage,
) async {
  router.go(RouteNames.clientHome);
  await AppHarness.tapVisible(tester, find.byKey(const Key('btn-menu-client')));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.clientMenu);
  await _confirmLogout(tester, router, fb, storage);
}

// ── Owner session ───────────────────────────────────────────────────────────

/// Confirms logout and proves it was a REAL sign-out: one `POST
/// /auth/logout` reached the server and the refresh token is wiped.
Future<void> _confirmLogout(
  WidgetTester tester,
  GoRouter router,
  FakeBackend fb,
  FakeSecureStorage storage,
) async {
  expect(
    await storage.readRefreshToken(),
    isNotNull,
    reason: 'the session being ended holds a refresh token',
  );
  final int logoutsBefore = fb.logoutCalls;
  await AppHarness.tapVisible(tester, find.byKey(const Key('row-logout')));
  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('btn-logout-confirm')),
  );
  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(const ValueKey<String>('login_email')),
  );
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.login);
  expect(
    fb.logoutCalls,
    logoutsBefore + 1,
    reason: 'logout must revoke server-side (POST /auth/logout once)',
  );
  expect(
    await storage.readRefreshToken(),
    isNull,
    reason: 'logout must wipe the refresh token',
  );
}

/// Owner login → salon shell → «Профіль» (`salon-nav-tile-3`, the real
/// phase-384 entry) → master mode.
Future<void> _ownerEntersMasterMode(
  WidgetTester tester,
  GoRouter router,
  FakeBackend fb,
) async {
  await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonId));
  expect(find.byType(SalonShellScreen), findsOneWidget);

  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('salon-nav-tile-3')),
  );
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.ownerMasterProfile);
  expect(find.byType(OwnerOwnProfileScreen), findsOneWidget);
  expect(find.byType(ErrorState), findsNothing);
}

/// Master mode → «Послуги» → empty own-row catalogue → setup → one NAILS
/// service saved onto the owner's OWN row.
Future<void> _ownerAddsService(
  WidgetTester tester,
  GoRouter router,
  FakeBackend fb,
) async {
  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('master-nav-tile-0')),
  );
  await AppHarness.pumpUntilFound(tester, find.byType(ServicesListScreen));
  await AppHarness.pumpUntilCondition(
    tester,
    () => fb.ownRowServicesGetCalls >= 1,
    description: 'the own-row list GET to reach the fake backend',
  );
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.ownerMasterServices);

  final Finder emptyCta = find.byKey(const Key('btn-create-service-empty'));
  await AppHarness.pumpUntilFound(tester, emptyCta);
  await AppHarness.tapVisible(tester, emptyCta);
  await AppHarness.pumpUntilFound(tester, find.byType(ServiceSetupScreen));

  await AppHarness.tapVisible(
    tester,
    find.byKey(const ValueKey<String>('cat_NAILS')),
  );
  final Finder freeRow = find.byKey(const Key('setup_row_$_kFreeTypeId'));
  await AppHarness.pumpUntilFound(tester, freeRow);
  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('setup_row_toggle_$_kFreeTypeId')),
  );
  final Finder durationField = find.descendant(
    of: freeRow,
    matching: find.byKey(const Key('service-setup-duration')),
  );
  final Finder priceField = find.descendant(
    of: freeRow,
    matching: find.byKey(const Key('pricing-fixed-amount')),
  );
  await AppHarness.pumpUntilFound(tester, priceField);
  await tester.enterText(durationField, '45');
  await tester.pump();
  await tester.enterText(priceField, '350');
  await tester.pump();

  await AppHarness.tapVisible(tester, find.byKey(const Key('btn-setup-save')));
  await AppHarness.pumpUntilCondition(
    tester,
    () => fb.ownRowBulkCreateCalls >= 1,
    description: 'the own-row bulk POST to reach the fake backend',
  );
  expect(
    fb.lastOwnRowBulkPath,
    '/api/v1/salons/$_kSalonId/masters/$_kOwnerMasterRowId/services/bulk',
  );
  await AppHarness.pumpUntilGone(tester, find.byType(ServiceSetupScreen));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.ownerMasterServices);
  expect(fb.ownRowServices, hasLength(1));
}

/// Master mode → «Графік» → «Додати години» → Monday on (09:00–18:00 seed)
/// + this-month window → save onto the owner's OWN row.
Future<void> _ownerSetsMondayHours(
  WidgetTester tester,
  GoRouter router,
  FakeBackend fb,
) async {
  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('master-nav-tile-2')),
  );
  await AppHarness.pumpUntilFound(tester, find.byType(MasterScheduleScreen));
  await AppHarness.pumpUntilCondition(
    tester,
    () => fb.ownRowScheduleGetCalls >= 1,
    description: 'the own-row weekly GET to reach the fake backend',
  );
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.ownerMasterSchedule);

  final Finder addHours = find.byKey(const Key('no-schedule-add-hours'));
  await AppHarness.pumpUntilFound(tester, addHours);
  await AppHarness.tapVisible(tester, addHours);
  await AppHarness.pumpUntilFound(
    tester,
    find.byType(WeeklyTemplateEditorScreen),
  );

  await AppHarness.tapVisible(tester, find.byKey(const Key('weekly-toggle-1')));
  await AppHarness.settle(tester);

  // First create REQUIRES a validity window (staged, not persisted).
  final Finder windowCard = find.byKey(const Key('weekly-active-window-card'));
  await tester.scrollUntilVisible(
    windowCard,
    -120,
    scrollable: find.byType(Scrollable).first,
  );
  await AppHarness.tapVisible(tester, windowCard);
  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('preset-this-month')),
  );
  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('btn-apply-schedule')),
  );

  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('btn-save-weekly-template')),
  );
  await AppHarness.pumpUntilCondition(
    tester,
    () => fb.ownRowSchedulePostCalls >= 1,
    description: 'the own-row weekly POST to reach the fake backend',
  );
  expect(
    fb.lastOwnRowSchedulePostPath,
    '/api/v1/masters/$_kOwnerMasterRowId/weekly-schedules',
  );
  await AppHarness.pumpUntilGone(
    tester,
    find.byType(WeeklyTemplateEditorScreen),
  );
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.ownerMasterSchedule);
}

/// The «Графік» tab's «‹ Салон» pill — no dedicated key, so found by its
/// l10n label inside the master-mode [VelvetTopBar].
Finder _scheduleBackPill(WidgetTester tester) {
  final AppLocalizations l10n = AppLocalizations.of(
    tester.element(find.byType(MasterScheduleScreen)),
  );
  return find.descendant(
    of: find.byType(VelvetTopBar),
    matching: find.text(l10n.ownerMasterModeBack),
  );
}

/// «‹ Салон» via [back] (the pill of the master-mode tab the owner stands
/// on), then sign out through the salon settings hub.
Future<void> _ownerLeavesAndLogsOut(
  WidgetTester tester,
  GoRouter router,
  Finder back,
  FakeBackend fb,
  FakeSecureStorage storage,
) async {
  await AppHarness.tapVisible(tester, back);
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonId));
  expect(find.byType(SalonShellScreen), findsOneWidget);

  unawaited(router.push(RouteNames.salonManageSettings(_kSalonId)));
  await AppHarness.settle(tester);
  await _confirmLogout(tester, router, fb, storage);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('decision 7 — CLIENT «Команда» lacks the owner → OWNER (master '
      'mode) adds a service (roster still lacks the owner) + Monday hours → '
      '«‹ Салон» → CLIENT «Команда» shows the owner (salonOwner) and opens '
      'their public profile', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = _backend();
      final FakeSecureStorage storage = FakeSecureStorage();
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        storage: storage,
      );

      // ── 1. Client: owner absent (no service, no schedule) ───────────────
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.clientHome);
      expect(fb.ownerRowBookable, isFalse);
      await _expectOwnerAbsent(
        tester,
        await _openClientTeamTab(tester, router, fb),
      );
      await _logoutClient(tester, router, fb, storage);

      // ── 2. Owner: master mode → service → Monday hours → «‹ Салон» ──────
      await _ownerEntersMasterMode(tester, router, fb);
      await _ownerAddsService(tester, router, fb);
      expect(fb.ownRowWeeklySchedule, isEmpty);
      // A service alone is not bookable: the roster clients are served must
      // still lack the owner (a real wire read, not just the fake's flag).
      expect(
        await _servedRosterIds(fb),
        isNot(contains(_kOwnerMasterRowId)),
        reason: 'a service alone is not bookable — hours are still missing',
      );
      expect(fb.ownerRowBookable, isFalse);
      await _ownerSetsMondayHours(tester, router, fb);
      expect(fb.ownerRowBookable, isTrue);
      await _ownerLeavesAndLogsOut(
        tester,
        router,
        _scheduleBackPill(tester),
        fb,
        storage,
      );

      // ── 3. Client: owner present, typed salonOwner, tappable ────────────
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.clientHome);
      final List<SalonMasterSummary> roster = await _openClientTeamTab(
        tester,
        router,
        fb,
      );
      final List<SalonMasterSummary> owners = roster
          .where((SalonMasterSummary m) => m.masterId == _kOwnerMasterRowId)
          .toList();
      expect(owners, hasLength(1), reason: 'the bookable owner is listed');
      expect(owners.single.type, MasterType.salonOwner);
      expect(owners.single.firstName, fb.masterFirstName);
      expect(owners.single.lastName, fb.masterLastName);

      final Finder ownerCard = find.byKey(_kOwnerCard);
      await AppHarness.revealPublicMasterCard(tester, ownerCard);
      expect(ownerCard, findsOneWidget);
      expect(
        find.descendant(
          of: ownerCard,
          matching: find.textContaining(fb.masterFirstName),
        ),
        findsOneWidget,
        reason: 'the card renders the owner\'s name off the wire',
      );

      await AppHarness.tapVisible(tester, ownerCard);
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(PublicMasterProfileScreen),
      );
      await AppHarness.settle(tester);
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        RouteNames.masterPublicProfile(_kOwnerMasterRowId),
      );
      expect(fb.lastGetPublicMasterId, _kOwnerMasterRowId);
      expect(find.byType(ErrorState), findsNothing);
    });
  });
}
