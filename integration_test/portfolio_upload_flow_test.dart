// Phase 405 (9.10) — fake-backed E2E: add / delete portfolio photos from the
// rail, for every editor role, over the REAL router + screens +
// `PortfolioEditController` + `MediaPickService` + `HttpMediaUploadRepository`
// + generated clients. Only the native pick / crop plugin is replaced, by the
// shared headless `FixtureAvatarGateway` (REUSE-FIRST — it is media-kind
// agnostic; the fixture JPEG goes through the real pipeline).
//
// Proves, end to end:
//   • INDEPENDENT_MASTER: add → pending tile + progress → the photo lands
//     FIRST, «Фото додано», counter n → n+1; delete dialog (back out keeps,
//     confirm removes); a failed delete brings the photo back + snack;
//   • the upload survives a tab switch (the screen holds the auto-dispose
//     write controller with `ref.listen`) — then a CLIENT sees the photo on
//     the public master profile, with no add tile and no delete badges;
//   • the SALON_OWNER adds on «Про салон» of their SECOND salon (request to
//     THAT salon's path); the SALON_ADMIN of the same salon deletes the
//     owner-uploaded photo, and the owner deletes the admin-uploaded one (no
//     uploader gating, O3/D8); the admin gets no logo / cover edit but does
//     get portfolio edit;
//   • a CLIENT sees an owner-added photo on the public salon profile, with no
//     add tile and no delete badges;
//   • the cap: at 30 there is no add tile; a 409 PORTFOLIO_LIMIT_REACHED
//     shows the limit snack;
//   • a 503 busy leaves a failed tile; retry succeeds; discard removes it;
//   • a 403 mid-session shows the no-permission snack and re-reads the list.
//
// Assertions target user-visible outcomes and KEYS (the add tile, per-photo
// keys, the pending-tile key PREFIX, the dialog keys), never the pending id
// scheme or how the rail watches progress. The 403-on-add case asserts NO
// failed tile is left behind (S3 — its retry could only 403 again).
//
// Runs headless: `flutter test integration_test/portfolio_upload_flow_test.dart
// -d flutter-tester`.

import 'dart:async';
import 'dart:io';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/core/media/pick/image_pick_gateway.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart'
    show kPortfolioMaxPhotos;
import 'package:beautica_mobile/core/widgets/upload_state_overlay.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_management_profile_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/fake_media_cache.dart';
import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/fixture_avatar_gateway.dart';

const String _ownerSalon = FakeBackend.kOwnerSalonId;

/// The admin's bound salon — listed as the owner's SECOND salon in the
/// shared-salon test, so both managers edit the SAME salon portfolio.
const String _sharedSalon = FakeBackend.kAdminSalonId;

/// The independent master's row id — `master-aaa` is also the client-facing
/// public fixture, so the client reads the SAME portfolio the master wrote.
const String _masterRow = 'master-aaa';

const Key _addTile = Key('portfolio-add-tile');
const Key _deleteDialog = Key('portfolio-delete-dialog');
const Key _deleteConfirm = Key('portfolio-delete-confirm');
const Key _deleteDismiss = Key('portfolio-delete-dismiss');

Finder _photo(String id) => find.byKey(Key('portfolio-photo-$id'));
Finder _badge(String id) => find.byKey(Key('portfolio-photo-delete-$id'));

/// Any widget whose string key starts with [prefix] (and is not a [except]).
Finder _keyed(String prefix, {String? except}) => find.byWidgetPredicate(
  (Widget w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith(prefix) &&
      (except == null ||
          !(w.key! as ValueKey<String>).value.startsWith(except)),
);

/// A pending (not yet stored) upload tile — by key PREFIX, so the id scheme
/// may change without breaking the flow.
Finder _pendingTile() =>
    _keyed('portfolio-pending-', except: 'portfolio-pending-discard-');

/// Every delete badge on screen (for "none on a public profile").
Finder _anyBadge() => _keyed('portfolio-photo-delete-');

/// A public salon tile for [id] — the shared [PortfolioRail]'s
/// `portfolio-photo-<id>` (phase 406 moved the public salon onto it).
Finder _publicSalonPhoto(String id) => find.byKey(Key('portfolio-photo-$id'));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installOverflowGuard();
    MediaConfig.debugAllowedHosts = <String>{'media.test'};
    debugMediaCacheManager = FakeMediaCacheManager(mediaLoadingForever);
  });
  tearDown(() async {
    debugMediaCacheManager = null;
    MediaConfig.debugAllowedHosts = null;
    await AppHarness.tearDownHarness();
  });

  Future<GoRouter> bootAs(
    WidgetTester tester,
    FakeBackend fb,
    UserRole role,
  ) async {
    final FixtureAvatarGateway gateway = FixtureAvatarGateway();
    final Directory scratch = Directory.systemTemp.createTempSync('pf_upload');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      extraOverrides: <Object>[
        imagePickGatewayProvider.overrideWithValue(gateway),
        mediaPickServiceProvider.overrideWithValue(
          MediaPickService(gateway, tempDir: () async => scratch),
        ),
      ],
    );
    await AppHarness.loginAs(tester, fb, role);
    await AppHarness.settle(tester);
    return router;
  }

  AppLocalizations l10n(WidgetTester t) =>
      AppLocalizations.of(t.element(find.byType(Scaffold).first));

  ProviderContainer container(WidgetTester t) =>
      ProviderScope.containerOf(t.element(find.byType(Scaffold).first));

  Future<void> switchUser(
    WidgetTester tester,
    FakeBackend fb,
    UserRole role,
  ) async {
    await container(tester).read(authProvider.notifier).logout();
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('login_email')),
    );
    await AppHarness.loginAs(tester, fb, role);
    await AppHarness.settle(tester);
  }

  /// Scrolls the screen's vertical scroll until [target] is built + visible.
  /// [within] scopes the scrollable to one screen (after a session switch
  /// the previous shell's lists can still be first in the tree).
  Future<void> scrollTo(
    WidgetTester tester,
    Finder target, {
    Finder? within,
  }) async {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: within == null
          ? find.byType(Scrollable).first
          : find
                .descendant(of: within, matching: find.byType(Scrollable))
                .first,
    );
    await AppHarness.settle(tester);
  }

  Future<void> openManage(
    WidgetTester tester,
    GoRouter router,
    String salonId,
  ) async {
    router.go(RouteNames.salonManage(salonId));
    await AppHarness.settle(tester);
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const Key('salon-manage-hero-card')),
    );
    expect(find.byType(SalonManagementProfileScreen), findsOneWidget);
  }

  Future<void> scrollToSalonRail(WidgetTester tester) =>
      scrollTo(tester, find.byKey(const Key('salon-manage-portfolio')));

  Future<void> openOwnMasterProfile(WidgetTester tester) async {
    await AppHarness.pumpUntilFound(tester, find.byType(MasterProfileScreen));
    await AppHarness.settle(tester);
  }

  void expectCount(WidgetTester tester, int n) => expect(
    find.text(l10n(tester).portfolioLabelWithCount(n, kPortfolioMaxPhotos)),
    findsOneWidget,
    reason: 'the editor counter reads $n/$kPortfolioMaxPhotos',
  );

  /// Add tile → «Галерея». Returns once the upload request has been SENT
  /// (never settles while it is in flight).
  Future<void> addFromGallery(WidgetTester tester) async {
    await scrollTo(tester, find.byKey(_addTile));
    await AppHarness.tapVisible(tester, find.byKey(_addTile));
    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('image-source-gallery')),
    );
    await tester.pump();
  }

  Future<void> waitSnack(WidgetTester tester, String text) =>
      AppHarness.pumpUntilFound(
        tester,
        find.text(text),
        timeout: const Duration(seconds: 15),
      );

  Future<void> waitSnackGone(WidgetTester tester, String text) =>
      AppHarness.pumpUntilGone(
        tester,
        find.text(text),
        timeout: const Duration(seconds: 15),
      );

  /// Badge → dialog → confirm (or back out when [confirm] is false).
  Future<void> deleteVia(
    WidgetTester tester,
    String id, {
    bool confirm = true,
  }) async {
    await scrollTo(tester, _badge(id));
    await AppHarness.tapVisible(tester, _badge(id));
    await AppHarness.pumpUntilFound(tester, find.byKey(_deleteDialog));
    await AppHarness.tapVisible(
      tester,
      find.byKey(confirm ? _deleteConfirm : _deleteDismiss),
    );
    await AppHarness.settle(tester);
  }

  /// [first] is laid out left of [second] on the rail.
  void expectLeftOf(WidgetTester tester, Finder first, Finder second) => expect(
    tester.getTopLeft(first).dx,
    lessThan(tester.getTopLeft(second).dx),
  );

  // ── INDEPENDENT_MASTER ────────────────────────────────────────────────────

  testWidgets('INDEPENDENT_MASTER adds a photo: pending tile + progress, then '
      'it lands FIRST with «Фото додано» and the counter 1 → 2; delete: back '
      'out keeps it, confirm removes it; a failed delete brings the photo '
      'back with the delete-failed snack', (tester) async {
    final FakeBackend fb = FakeBackend(
      masterRowId: _masterRow,
      wirePortfolio: true,
      portfolioUploadDelay: const Duration(milliseconds: 1500),
    )..currentRole = UserRole.independentMaster;
    fb.masterPortfolioRows.add(fb.portfolioRow('MASTER', _masterRow)); // pf-1
    await bootAs(tester, fb, UserRole.independentMaster);
    await openOwnMasterProfile(tester);
    await scrollTo(tester, _photo('pf-1'));
    expectCount(tester, 1);

    // ── Add ──
    await addFromGallery(tester);
    await AppHarness.pumpUntilFound(
      tester,
      find.descendant(
        of: _pendingTile(),
        matching: find.byType(UploadProgressOverlay),
      ),
    );
    expectCount(tester, 2);
    await waitSnack(tester, l10n(tester).portfolioPhotoAdded);
    await AppHarness.pumpUntilGone(tester, _pendingTile());
    expect(_photo('pf-2'), findsOneWidget);
    expectLeftOf(tester, _photo('pf-2'), _photo('pf-1'));
    expectCount(tester, 2);
    expect(fb.portfolioUploadUris.map((Uri u) => u.path), <String>[
      '/api/v1/media/portfolio',
    ]);
    expect(fb.portfolioUploadPartNames, <List<String>>[
      <String>['file'],
    ]);
    await waitSnackGone(tester, l10n(tester).portfolioPhotoAdded);

    // ── Delete: back out keeps the photo ──
    await deleteVia(tester, 'pf-2', confirm: false);
    expect(find.byKey(_deleteDialog), findsNothing);
    expect(_photo('pf-2'), findsOneWidget);
    expect(fb.portfolioDeleteUris, isEmpty);

    // ── Delete: confirm removes it ──
    await deleteVia(tester, 'pf-2');
    await waitSnack(tester, l10n(tester).portfolioPhotoDeleted);
    expect(_photo('pf-2'), findsNothing);
    expect(_photo('pf-1'), findsOneWidget);
    expectCount(tester, 1);
    expect(fb.portfolioDeleteUris.map((Uri u) => u.path), <String>[
      '/api/v1/media/portfolio/pf-2',
    ]);
    await waitSnackGone(tester, l10n(tester).portfolioPhotoDeleted);

    // ── A failed delete: the photo comes back + the delete-failed snack ──
    fb.failPortfolioDeletes(500);
    await deleteVia(tester, 'pf-1');
    await waitSnack(tester, l10n(tester).portfolioDeleteFailed);
    expect(_photo('pf-1'), findsOneWidget);
    expect(fb.portfolioDeleteUris, hasLength(2));
    expect(fb.masterPortfolioRows, hasLength(1));
    expectCount(tester, 1);
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('INDEPENDENT_MASTER: an upload in flight SURVIVES a switch to '
      '«Послуги» and back (the screen holds the write controller); one that '
      'LANDS while «Послуги» is open still shows «Фото додано»; then a '
      'CLIENT sees the photo on the public master profile — no add tile, no '
      'delete badges', (tester) async {
    final FakeBackend fb = FakeBackend(
      masterRowId: _masterRow,
      wirePortfolio: true,
      portfolioUploadDelay: const Duration(seconds: 4),
    )..currentRole = UserRole.independentMaster;
    final GoRouter router = await bootAs(
      tester,
      fb,
      UserRole.independentMaster,
    );
    await openOwnMasterProfile(tester);

    await addFromGallery(tester);
    await AppHarness.pumpUntilFound(tester, _pendingTile());

    // «Послуги» unmounts the «Про мене» rail — the rail's own watch of the
    // write controller goes away while the upload is still in flight. No
    // settle here: the in-flight overlay may keep frames scheduled.
    final Finder services = find.byKey(const Key('master-profile-tab-1'));
    await Scrollable.ensureVisible(tester.element(services), alignment: 0.5);
    await tester.pump();
    await tester.tap(services);
    await AppHarness.pumpUntilGone(tester, find.byType(PortfolioRail));
    // Still in flight: the reply (held by `portfolioUploadDelay`) has not
    // landed, so no result snack yet. (The fake stores the row BEFORE the
    // delay, so the row list is no signal.)
    expect(find.text(l10n(tester).portfolioPhotoAdded), findsNothing);
    expect(fb.portfolioUploadUris, hasLength(1));

    final Finder about = find.byKey(const Key('master-profile-tab-0'));
    await Scrollable.ensureVisible(tester.element(about), alignment: 0.5);
    await tester.pump();
    await tester.tap(about);
    // Back BEFORE the reply lands: the SAME upload is still pending (a
    // disposed controller would have cancelled it and come back empty).
    await AppHarness.pumpUntilFound(tester, _pendingTile());
    expect(find.text(l10n(tester).portfolioPhotoAdded), findsNothing);
    await AppHarness.pumpUntilGone(tester, _pendingTile());
    await AppHarness.pumpUntilFound(tester, _photo('pf-1'));
    expectCount(tester, 1);
    expect(fb.portfolioUploadUris, hasLength(1), reason: 'never re-sent');
    await AppHarness.settle(tester);

    // ── Q1: an upload that LANDS while «Послуги» is open still shows
    // «Фото додано» (the snack is not tied to the unmounted rail) ──
    await addFromGallery(tester);
    await AppHarness.pumpUntilFound(tester, _pendingTile());
    await Scrollable.ensureVisible(tester.element(services), alignment: 0.5);
    await tester.pump();
    await tester.tap(services);
    await AppHarness.pumpUntilGone(tester, find.byType(PortfolioRail));
    await waitSnack(tester, l10n(tester).portfolioPhotoAdded);
    expect(
      find.byType(PortfolioRail),
      findsNothing,
      reason: 'the snack showed while the rail was still unmounted',
    );
    expect(fb.portfolioUploadUris, hasLength(2));
    await waitSnackGone(tester, l10n(tester).portfolioPhotoAdded);
    await Scrollable.ensureVisible(tester.element(about), alignment: 0.5);
    await tester.pump();
    await tester.tap(about);
    await AppHarness.pumpUntilFound(tester, _photo('pf-2'));
    expectCount(tester, 2);
    await AppHarness.settle(tester);

    // ── A CLIENT on the public master profile ──
    await switchUser(tester, fb, UserRole.client);
    unawaited(router.push(RouteNames.masterPublicProfile(_masterRow)));
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const Key('public-master-profile-about-tab')),
    );
    expect(find.byType(PublicMasterProfileScreen), findsOneWidget);
    await scrollTo(
      tester,
      _photo('pf-1'),
      within: find.byType(PublicMasterProfileScreen),
    );
    expect(_photo('pf-1'), findsOneWidget);
    expect(find.byKey(_addTile), findsNothing);
    expect(find.byType(PortfolioAddTile), findsNothing);
    expect(_anyBadge(), findsNothing);
    expect(_pendingTile(), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 150)));

  // ── SALON — owner and admin manage the SAME salon ─────────────────────────

  testWidgets('one salon, two managers: the OWNER adds on «Про салон» of '
      'their SECOND salon (that salon\'s path); the ADMIN gets portfolio edit '
      'but no logo / cover edit, adds a photo and deletes the OWNER\'s; the '
      'OWNER then deletes the ADMIN\'s — no uploader gating', (tester) async {
    final FakeBackend fb = FakeBackend(wirePortfolio: true)
      ..currentRole = UserRole.salonOwner;
    fb.mySalons.add(<String, dynamic>{
      'id': _sharedSalon,
      'ownerId': 'user-owner-1',
      'name': 'Студія «Друга»',
      'city': 'Київ',
      'cityId': 'city-kyiv',
      'oblastId': 'oblast-kyiv',
      'street': 'Хрещатик',
      'buildingNo': '12',
      'isActive': true,
      'isPrimary': false,
    });
    final GoRouter router = await bootAs(tester, fb, UserRole.salonOwner);

    // ── OWNER adds to salon #2 ──
    await openManage(tester, router, _sharedSalon);
    expect(find.byKey(const Key('salon-logo-editor')), findsOneWidget);
    await scrollToSalonRail(tester);
    expectCount(tester, 0);
    await addFromGallery(tester);
    await waitSnack(tester, l10n(tester).portfolioPhotoAdded);
    await AppHarness.pumpUntilFound(tester, _photo('pf-1')); // owner's
    expectCount(tester, 1);
    expect(fb.portfolioUploadUris.map((Uri u) => u.path), <String>[
      '/api/v1/salons/$_sharedSalon/portfolio',
    ]);
    expect(fb.ownerSalonPortfolioRows, isEmpty, reason: 'never salon #1');
    await waitSnackGone(tester, l10n(tester).portfolioPhotoAdded);

    // ── ADMIN: portfolio edit yes, logo / cover no ──
    await switchUser(tester, fb, UserRole.salonAdmin);
    await openManage(tester, router, _sharedSalon);
    expect(find.byKey(const Key('salon-cover-edit')), findsNothing);
    expect(find.byKey(const Key('salon-logo-edit-badge')), findsNothing);
    expect(find.byKey(const Key('salon-logo-editor')), findsNothing);
    await scrollToSalonRail(tester);
    expect(find.byKey(_addTile), findsOneWidget);
    expect(_badge('pf-1'), findsOneWidget, reason: 'the OWNER\'s photo');

    await addFromGallery(tester);
    await waitSnack(tester, l10n(tester).portfolioPhotoAdded);
    await AppHarness.pumpUntilFound(tester, _photo('pf-2')); // admin's
    await waitSnackGone(tester, l10n(tester).portfolioPhotoAdded);

    await deleteVia(tester, 'pf-1');
    await waitSnack(tester, l10n(tester).portfolioPhotoDeleted);
    expect(_photo('pf-1'), findsNothing);
    expect(_photo('pf-2'), findsOneWidget);
    await waitSnackGone(tester, l10n(tester).portfolioPhotoDeleted);

    // ── OWNER deletes the ADMIN's photo ──
    await switchUser(tester, fb, UserRole.salonOwner);
    await openManage(tester, router, _sharedSalon);
    await scrollToSalonRail(tester);
    expect(_badge('pf-2'), findsOneWidget, reason: 'the ADMIN\'s photo');
    await deleteVia(tester, 'pf-2');
    await waitSnack(tester, l10n(tester).portfolioPhotoDeleted);
    expect(_photo('pf-2'), findsNothing);
    expectCount(tester, 0);

    expect(fb.portfolioUploadUris.map((Uri u) => u.path), <String>[
      '/api/v1/salons/$_sharedSalon/portfolio',
      '/api/v1/salons/$_sharedSalon/portfolio',
    ]);
    expect(fb.portfolioDeleteUris.map((Uri u) => u.path), <String>[
      '/api/v1/salons/$_sharedSalon/portfolio/pf-1',
      '/api/v1/salons/$_sharedSalon/portfolio/pf-2',
    ]);
    expect(fb.adminSalonPortfolioRows, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 180)));

  testWidgets('SALON_OWNER adds on «Про салон»; a CLIENT then sees the photo '
      'on the public salon profile — no add tile, no delete badges', (
    tester,
  ) async {
    final FakeBackend fb = FakeBackend(wirePortfolio: true)
      ..currentRole = UserRole.salonOwner;
    fb.ownerSalonPortfolioRows.add(
      fb.portfolioRow('SALON', _ownerSalon), // pf-1
    );
    final GoRouter router = await bootAs(tester, fb, UserRole.salonOwner);
    await openManage(tester, router, _ownerSalon);
    await scrollToSalonRail(tester);
    await addFromGallery(tester);
    await waitSnack(tester, l10n(tester).portfolioPhotoAdded);
    await AppHarness.pumpUntilFound(tester, _photo('pf-2'));
    expectLeftOf(tester, _photo('pf-2'), _photo('pf-1'));
    expectCount(tester, 2);
    await waitSnackGone(tester, l10n(tester).portfolioPhotoAdded);

    await switchUser(tester, fb, UserRole.client);
    router.go(RouteNames.salonPublicProfile(_ownerSalon));
    await AppHarness.settle(tester);
    await scrollTo(tester, _publicSalonPhoto('pf-2'));
    expect(_publicSalonPhoto('pf-2'), findsOneWidget);
    expect(_publicSalonPhoto('pf-1'), findsOneWidget);
    expect(find.byKey(_addTile), findsNothing);
    expect(find.byType(PortfolioAddTile), findsNothing);
    expect(_anyBadge(), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 120)));

  // ── Cap / failures ────────────────────────────────────────────────────────

  testWidgets('the cap: at 30 photos there is no add tile; deleting one '
      'brings it back; a server 409 PORTFOLIO_LIMIT_REACHED shows the limit '
      'snack and stores nothing', (tester) async {
    final FakeBackend fb = FakeBackend(wirePortfolio: true)
      ..currentRole = UserRole.salonOwner;
    for (int i = 0; i < kPortfolioMaxPhotos; i++) {
      fb.ownerSalonPortfolioRows.add(fb.portfolioRow('SALON', _ownerSalon));
    }
    final GoRouter router = await bootAs(tester, fb, UserRole.salonOwner);
    await openManage(tester, router, _ownerSalon);
    await scrollTo(tester, _photo('pf-1'));
    expectCount(tester, kPortfolioMaxPhotos);
    expect(find.byKey(_addTile), findsNothing);
    expect(_badge('pf-1'), findsOneWidget, reason: 'still deletable at cap');

    await deleteVia(tester, 'pf-1');
    await waitSnack(tester, l10n(tester).portfolioPhotoDeleted);
    expectCount(tester, kPortfolioMaxPhotos - 1);
    expect(find.byKey(_addTile), findsOneWidget);
    await waitSnackGone(tester, l10n(tester).portfolioPhotoDeleted);

    // The server is authoritative (e.g. another manager filled the slot).
    fb.failPortfolioUploads(409, code: 'PORTFOLIO_LIMIT_REACHED');
    await addFromGallery(tester);
    await waitSnack(
      tester,
      l10n(tester).uploadErrorPortfolioLimit(kPortfolioMaxPhotos),
    );
    expect(fb.portfolioUploadUris, hasLength(1));
    expect(fb.ownerSalonPortfolioRows, hasLength(kPortfolioMaxPhotos - 1));
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('503 busy: a failed tile with retry; retry re-sends and the '
      'photo lands; a second 503 → discard removes the failed tile and '
      'stores nothing', (tester) async {
    final FakeBackend fb = FakeBackend(
      masterRowId: _masterRow,
      wirePortfolio: true,
    )..currentRole = UserRole.independentMaster;
    await bootAs(tester, fb, UserRole.independentMaster);
    await openOwnMasterProfile(tester);

    fb.failPortfolioUploads(503, retryAfterSeconds: 2);
    await addFromGallery(tester);
    await waitSnack(tester, l10n(tester).uploadErrorConflict);
    final Finder failedRetry = find.descendant(
      of: _pendingTile(),
      matching: find.byKey(const Key('upload-retry')),
    );
    await AppHarness.pumpUntilFound(tester, failedRetry);
    expect(fb.masterPortfolioRows, isEmpty);
    await waitSnackGone(tester, l10n(tester).uploadErrorConflict);

    // ── Retry succeeds ──
    fb.failPortfolioUploads(null);
    await AppHarness.tapVisible(tester, failedRetry);
    await waitSnack(tester, l10n(tester).portfolioPhotoAdded);
    await AppHarness.pumpUntilGone(tester, _pendingTile());
    expect(_photo('pf-1'), findsOneWidget);
    expect(fb.portfolioUploadUris, hasLength(2), reason: 'the SAME photo');
    expectCount(tester, 1);
    await waitSnackGone(tester, l10n(tester).portfolioPhotoAdded);

    // ── Discard ──
    fb.failPortfolioUploads(503, retryAfterSeconds: 2);
    await addFromGallery(tester);
    await AppHarness.pumpUntilFound(tester, failedRetry);
    expectCount(tester, 2);
    await AppHarness.tapVisible(
      tester,
      _keyed('portfolio-pending-discard-').first,
    );
    await AppHarness.pumpUntilGone(tester, _pendingTile());
    expectCount(tester, 1);
    expect(fb.masterPortfolioRows, hasLength(1));
    expect(fb.portfolioUploadUris, hasLength(3));
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('403 mid-session on add (the role changed): the no-permission '
      'snack, the portfolio list is re-read from the server, and no failed '
      'tile is left to retry', (tester) async {
    final FakeBackend fb = FakeBackend(wirePortfolio: true)
      ..currentRole = UserRole.salonAdmin;
    fb.adminSalonPortfolioRows.add(fb.portfolioRow('SALON', _sharedSalon));
    final GoRouter router = await bootAs(tester, fb, UserRole.salonAdmin);
    await openManage(tester, router, _sharedSalon);
    await scrollToSalonRail(tester);
    expect(find.byKey(_addTile), findsOneWidget);
    final int readsBefore = fb.portfolioReadUris.length;

    fb.failPortfolioUploads(403);
    await addFromGallery(tester);
    await waitSnack(tester, l10n(tester).uploadErrorForbidden);
    await AppHarness.pumpUntilCondition(
      tester,
      () => fb.portfolioReadUris.length > readsBefore,
      description: 'the salon portfolio to be re-read after the 403',
    );
    expect(
      fb.portfolioReadUris.skip(readsBefore).map((Uri u) => u.path),
      everyElement('/api/v1/salons/$_sharedSalon/portfolio'),
    );
    expect(_photo('pf-1'), findsOneWidget);
    expect(fb.adminSalonPortfolioRows, hasLength(1));
    // S3 — no failed tile is left behind: its retry could only 403 again.
    await AppHarness.pumpUntilGone(tester, _pendingTile());
    expect(find.byKey(const Key('upload-retry')), findsNothing);
    expectCount(tester, 1);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
