// Phase 407 (9.12) — fake-backed E2E: the full-screen portfolio photo viewer
// over the REAL router + screens + repositories + generated clients
// (Step 2.7 Rule 3b). The widget tier proves the viewer and each call site
// with stubbed repositories; this proves the journey a user actually takes:
//
//   • PUBLIC SALON (12-photo `salonPortfolioPhotoCount` fixture): a CLIENT
//     taps photo 3 → the viewer opens at «3 / 12» showing photo 3's wire URL;
//     swiping moves the counter AND the shown photo; close returns to the
//     profile; «+4» still only expands (never opens the viewer) and a
//     revealed tail tile opens the viewer at its own index;
//   • PUBLIC MASTER: an independent master's photos only (salon photos are
//     seeded and must not leak into the viewer's page count);
//   • EDITOR RAIL (independent master's own «Про мене»): a photo BODY tap
//     opens the viewer; the delete badge opens the delete dialog, not the
//     viewer; a pending upload tile is not tappable; once it lands, the new
//     photo is;
//   • SECURITY: while the viewer is open, a forced logout (the
//     `AuthNotifier.logoutForced()` call the RefreshInterceptor makes on an
//     expired / revoked session — the fake's Dio carries no refresh
//     interceptor, so the flow invokes that same entry point) leaves NO
//     viewer route behind and lands on /login.
//
// Assertions are user-visible: the «n / N» counter, which page key is
// hit-testable, which URL that page renders, route presence and location.
//
// Runs headless: `flutter test integration_test/portfolio_photo_viewer_flow_test.dart
// -d flutter-tester`.

import 'dart:async';
import 'dart:io';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/core/media/pick/image_pick_gateway.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/public_salon_profile_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_photo_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/fake_media_cache.dart';
import '../test/helpers/overflow_guard.dart';
import '../test/helpers/rendered_image_url.dart';
import 'support/app_harness.dart';
import 'support/fixture_avatar_gateway.dart';
import 'support/pager_drag.dart';

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('uk'));

final Finder _viewer = find.byType(PortfolioPhotoViewer);
final Finder _counterPill = find.byKey(PortfolioPhotoViewer.indicatorKey);

Finder _tile(String id) => find.byKey(Key('portfolio-photo-$id'));
Finder _badge(String id) => find.byKey(Key('portfolio-photo-delete-$id'));
Finder _page(String id) => find.byKey(PortfolioPhotoViewer.pageKey(id));

/// A pending (not yet stored) upload tile — by key PREFIX (the id scheme is
/// not part of the contract), excluding its discard badge.
final Finder _pendingTile = find.byWidgetPredicate(
  (Widget w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('portfolio-pending-') &&
      !(w.key! as ValueKey<String>).value.startsWith(
        'portfolio-pending-discard-',
      ),
);

/// `salon-xyz` 12-photo fixture: photo [i] (1-based) and its wire URL.
String _big(int i) => 'media-big-$i';
String _bigUrl(int i) => 'https://media.test/portfolio/salon-xyz/$i.jpg';

/// The counter pill reads «n / N» (asserted INSIDE the pill, by key).
void _expectCounter(int n, int total) => expect(
  find.descendant(
    of: _counterPill,
    matching: find.text(_l10n.portfolioViewerCounter(n, total)),
  ),
  findsOneWidget,
  reason: 'the viewer counter reads «$n / $total»',
);

/// The page of [id] is the one on screen, rendering exactly [url].
void _expectShowing(WidgetTester tester, String id, String url) {
  expect(_page(id).hitTestable(), findsOneWidget, reason: 'page $id shown');
  expect(renderedImageUrls(tester, within: _page(id)), <String>[url]);
}

/// One page-turn swipe — the shared live-binding pager recipe (NOT
/// `tester.fling`, which measurably flakes on this binding), with a
/// finger-like 24 px slop lead-in: without it the recipe's first 57 px sample
/// crosses the page `InteractiveViewer`'s pan slop in one step and the zoom
/// surface wins the arena (QA finding F1 — a real fast flick can do the
/// same; tracked for the audit-fix pass, pinned skipped in
/// `portfolio_photo_viewer_test.dart`).
Future<void> _swipe(WidgetTester tester, {required bool forward}) =>
    dragPagerByOnePage(
      tester,
      PortfolioPhotoViewer.pagerKey,
      forward: forward,
      slopLeadIn: 24,
    );

/// Taps a tile's BODY (bottom-left, clear of a top-right delete badge).
Future<void> _tapBody(WidgetTester tester, Finder tile) async {
  await tester.ensureVisible(tile);
  await AppHarness.settle(tester);
  await tester.tapAt(tester.getBottomLeft(tile) + const Offset(12, -12));
  await AppHarness.settle(tester);
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.byKey(PortfolioPhotoViewer.closeKey));
  await AppHarness.settle(tester);
  expect(_viewer, findsNothing);
}

/// Scrolls the screen's vertical scroll until [target] is built + visible.
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await AppHarness.settle(tester);
}

/// Ends the session the way an expired / revoked refresh token does
/// (`RefreshInterceptor` → `AuthNotifier.logoutForced()`), then waits for the
/// login form.
Future<void> _forceLogout(WidgetTester tester) async {
  final ProviderContainer c = ProviderScope.containerOf(
    tester.element(_viewer),
  );
  await c.read(authProvider.notifier).logoutForced();
  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(const ValueKey<String>('login_email')),
  );
  await AppHarness.settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installOverflowGuard();
    // Allow-list the fixture host and serve a decodable image, so viewer
    // pages render the REAL wire URL (an off-allowlist URL would render the
    // fallback glyph, and `renderedImageUrls` would come back empty).
    MediaConfig.debugAllowedHosts = <String>{'media.test'};
    debugMediaCacheManager = FakeMediaCacheManager(mediaLoaded);
  });
  tearDown(() async {
    debugMediaCacheManager = null;
    MediaConfig.debugAllowedHosts = null;
    await AppHarness.tearDownHarness();
  });

  // ── PUBLIC SALON ──────────────────────────────────────────────────────────

  Future<GoRouter> openPublicSalon(WidgetTester tester, FakeBackend fb) async {
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.settle(tester);
    unawaited(router.push(RouteNames.salonPublicProfile('salon-xyz')));
    await AppHarness.settle(tester);
    expect(find.byType(PublicSalonProfileScreen), findsOneWidget);
    await _scrollTo(tester, find.byKey(const Key('salon-about-portfolio')));
    await tester.ensureVisible(find.byKey(const Key('salon-about-portfolio')));
    await AppHarness.settle(tester);
    return router;
  }

  testWidgets('CLIENT on a 12-photo salon taps photo 3: the viewer opens at '
      '«3 / 12» on photo 3; swiping moves counter + photo; close returns to '
      'the profile; «+4» only expands and a revealed tile opens at its own '
      'index', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.client
        ..salonPortfolioPhotoCount = 12;
      final GoRouter router = await openPublicSalon(tester, fb);

      await tester.tap(_tile(_big(3)));
      await AppHarness.settle(tester);
      expect(_viewer, findsOneWidget);
      _expectCounter(3, 12);
      _expectShowing(tester, _big(3), _bigUrl(3));

      await _swipe(tester, forward: true);
      _expectCounter(4, 12);
      _expectShowing(tester, _big(4), _bigUrl(4));
      await _swipe(tester, forward: true);
      _expectCounter(5, 12);
      _expectShowing(tester, _big(5), _bigUrl(5));
      await _swipe(tester, forward: false);
      _expectCounter(4, 12);
      _expectShowing(tester, _big(4), _bigUrl(4));

      await _close(tester);
      expect(find.byType(PublicSalonProfileScreen), findsOneWidget);
      AppHarness.expectLocation(
        router,
        RouteNames.salonPublicProfile('salon-xyz'),
      );
      expect(_tile(_big(3)).hitTestable(), findsOneWidget);

      // «+4» expands inline — it is never a viewer entry point.
      final Finder showAll = find.byKey(const Key('portfolio-show-all'));
      await tester.ensureVisible(showAll);
      await AppHarness.settle(tester);
      await tester.tap(showAll.hitTestable());
      await AppHarness.settle(tester);
      expect(_viewer, findsNothing, reason: '«+4» expands, never opens');
      expect(showAll, findsNothing);

      // The revealed tail opens at ITS index of the full 12.
      await tester.scrollUntilVisible(
        _tile(_big(12)),
        200,
        scrollable: find.descendant(
          of: find.byKey(const Key('salon-about-portfolio')),
          matching: find.byType(Scrollable),
        ),
      );
      await AppHarness.settle(tester);
      await tester.tap(_tile(_big(12)));
      await AppHarness.settle(tester);
      _expectCounter(12, 12);
      _expectShowing(tester, _big(12), _bigUrl(12));
      // Last page: a further forward swipe stays on 12.
      await _swipe(tester, forward: true);
      _expectCounter(12, 12);
      await _close(tester);
      expect(find.byType(PublicSalonProfileScreen), findsOneWidget);
    });
  }, timeout: const Timeout(Duration(seconds: 120)));

  // ── PUBLIC MASTER ─────────────────────────────────────────────────────────

  testWidgets('CLIENT on an independent master\'s public profile: a tap opens '
      'the viewer with THAT master\'s photos only', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend(wirePortfolio: true)
        ..currentRole = UserRole.client;
      fb.publicMasterPortfolioRows
        ..add(fb.portfolioRow('MASTER', 'master-aaa')) // pf-1
        ..add(fb.portfolioRow('MASTER', 'master-aaa')); // pf-2
      // Salon photos exist in the same backend — they must never page into
      // this master's viewer (D5).
      fb.ownerSalonPortfolioRows
        ..add(fb.portfolioRow('SALON', FakeBackend.kOwnerSalonId))
        ..add(fb.portfolioRow('SALON', FakeBackend.kOwnerSalonId))
        ..add(fb.portfolioRow('SALON', FakeBackend.kOwnerSalonId));
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await AppHarness.settle(tester);
      unawaited(router.push(RouteNames.masterPublicProfile('master-aaa')));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('public-master-profile-about-tab')),
      );
      await AppHarness.settle(tester);
      expect(find.byType(PublicMasterProfileScreen), findsOneWidget);

      await _scrollTo(tester, _tile('pf-1'));
      await tester.tap(_tile('pf-1'));
      await AppHarness.settle(tester);
      expect(_viewer, findsOneWidget);
      _expectCounter(1, 2);
      _expectShowing(
        tester,
        'pf-1',
        'https://media.test/portfolio/master-aaa/1.jpg',
      );

      await _swipe(tester, forward: true);
      _expectCounter(2, 2);
      _expectShowing(
        tester,
        'pf-2',
        'https://media.test/portfolio/master-aaa/2.jpg',
      );
      // The end of THIS master's photos — no salon photo follows.
      await _swipe(tester, forward: true);
      _expectCounter(2, 2);
      expect(_page('pf-3'), findsNothing);

      await _close(tester);
      expect(find.byType(PublicMasterProfileScreen), findsOneWidget);
    });
  }, timeout: const Timeout(Duration(seconds: 90)));

  // ── EDITOR RAIL ───────────────────────────────────────────────────────────

  Future<FakeBackend> bootMasterEditor(WidgetTester tester) async {
    final FakeBackend fb = FakeBackend(
      masterRowId: 'master-aaa',
      wirePortfolio: true,
      portfolioUploadDelay: const Duration(seconds: 3),
    )..currentRole = UserRole.independentMaster;
    fb.masterPortfolioRows
      ..add(fb.portfolioRow('MASTER', 'master-aaa')) // pf-1
      ..add(fb.portfolioRow('MASTER', 'master-aaa')); // pf-2
    final FixtureAvatarGateway gateway = FixtureAvatarGateway();
    final Directory scratch = Directory.systemTemp.createTempSync('pf_viewer');
    addTearDown(() => scratch.deleteSync(recursive: true));
    await AppHarness.boot(
      tester,
      fb,
      extraOverrides: <Object>[
        imagePickGatewayProvider.overrideWithValue(gateway),
        mediaPickServiceProvider.overrideWithValue(
          MediaPickService(gateway, tempDir: () async => scratch),
        ),
      ],
    );
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
    await AppHarness.pumpUntilFound(tester, find.byType(MasterProfileScreen));
    await AppHarness.settle(tester);
    await _scrollTo(tester, _tile('pf-1'));
    return fb;
  }

  testWidgets('INDEPENDENT_MASTER editor rail: a photo body tap opens the '
      'viewer; the delete badge opens the delete dialog, not the viewer; a '
      'pending upload is not tappable, and once it lands it is', (
    tester,
  ) async {
    final FakeBackend fb = await bootMasterEditor(tester);

    // Body tap → viewer on that photo.
    await _tapBody(tester, _tile('pf-2'));
    expect(_viewer, findsOneWidget);
    _expectCounter(2, 2);
    _expectShowing(
      tester,
      'pf-2',
      'https://media.test/portfolio/master-aaa/2.jpg',
    );
    await _close(tester);
    expect(find.byType(MasterProfileScreen), findsOneWidget);

    // Badge → the delete dialog, never the viewer; backing out deletes
    // nothing.
    await tester.ensureVisible(_badge('pf-1'));
    await AppHarness.settle(tester);
    await tester.tap(_badge('pf-1'));
    await AppHarness.settle(tester);
    expect(find.byKey(const Key('portfolio-delete-dialog')), findsOneWidget);
    expect(_viewer, findsNothing);
    await tester.tap(find.byKey(const Key('portfolio-delete-dismiss')));
    await AppHarness.settle(tester);
    expect(fb.portfolioDeleteUris, isEmpty);

    // A pending upload tile is NOT a viewer entry point.
    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('portfolio-add-tile')),
    );
    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('image-source-gallery')),
    );
    await AppHarness.pumpUntilFound(tester, _pendingTile);
    await tester.tapAt(tester.getCenter(_pendingTile.first));
    await tester.pump();
    await tester.pump();
    expect(_viewer, findsNothing, reason: 'a pending tile is not tappable');
    // While it is in flight the tile stays — and still no viewer once the
    // upload lands (a viewer pushed over the rail would also make the
    // pending tile offstage, so this wait cannot pass for the wrong reason
    // with the assertion below).
    await AppHarness.pumpUntilGone(
      tester,
      _pendingTile,
      timeout: const Duration(seconds: 15),
    );
    expect(_viewer, findsNothing);

    // Landed (newest first): now a stored photo — tappable, at index 0.
    await AppHarness.pumpUntilFound(tester, _tile('pf-3'));
    await AppHarness.settle(tester);
    await _tapBody(tester, _tile('pf-3'));
    expect(_viewer, findsOneWidget);
    _expectCounter(1, 3);
    _expectShowing(
      tester,
      'pf-3',
      'https://media.test/portfolio/master-aaa/3.jpg',
    );
    await _close(tester);
  }, timeout: const Timeout(Duration(seconds: 120)));

  // ── SECURITY: forced logout while the viewer is open ──────────────────────

  testWidgets('session expiry while the viewer is open (CLIENT, public salon '
      'route): no viewer route remains and the user lands on /login', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.client
        ..salonPortfolioPhotoCount = 12;
      final GoRouter router = await openPublicSalon(tester, fb);
      await tester.tap(_tile(_big(2)));
      await AppHarness.settle(tester);
      _expectCounter(2, 12);

      await _forceLogout(tester);

      expect(_viewer, findsNothing);
      expect(_viewer.evaluate(), isEmpty);
      expect(
        find.byType(PortfolioPhotoViewer, skipOffstage: false),
        findsNothing,
        reason: 'not even an offstage viewer route survives the logout',
      );
      AppHarness.expectLocation(router, RouteNames.login);
      expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
    });
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('session expiry while the viewer is open (INDEPENDENT_MASTER, '
      'own profile in the shell): no viewer route remains and the user lands '
      'on /login', (tester) async {
    await bootMasterEditor(tester);
    await _tapBody(tester, _tile('pf-1'));
    _expectCounter(1, 2);

    await _forceLogout(tester);

    expect(
      find.byType(PortfolioPhotoViewer, skipOffstage: false),
      findsNothing,
      reason: 'not even an offstage viewer route survives the logout',
    );
    expect(find.byType(MasterProfileScreen, skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
