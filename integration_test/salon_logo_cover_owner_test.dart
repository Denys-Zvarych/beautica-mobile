// Phase 369 (9.8) — fake-backed E2E: the SALON_OWNER changes the salon logo
// and cover; a client sees them on the public profile; the error copy for
// 429 / 503 / 409; remove; and a SALON_ADMIN sees no controls and is refused
// (403) even when the controller is driven directly.
//
// Drives the REAL management / public screens, the REAL
// `SalonImageUploadController` (the 367 `MediaUploadFlow`), the REAL
// `MediaPickService` and the REAL `HttpMediaUploadRepository` over
// `FakeBackend`; only the native pick / crop plugin is the shared headless
// `FixtureAvatarGateway`.
//
// Runs headless: `flutter test integration_test/salon_logo_cover_owner_test.dart
// -d flutter-tester`.

import 'dart:io';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/core/media/pick/image_pick_gateway.dart';
import 'package:beautica_mobile/core/media/pick/image_source_sheet.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/media/upload/salon_image_upload_controller.dart';
import 'package:beautica_mobile/core/widgets/upload_state_overlay.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_cover_widgets.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
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
const String _adminSalon = FakeBackend.kAdminSalonId;

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
    final Directory scratch = Directory.systemTemp.createTempSync('salon_img');
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
    return router;
  }

  AppLocalizations l10n(WidgetTester t) =>
      AppLocalizations.of(t.element(find.byType(Scaffold).first));

  ProviderContainer container(WidgetTester t) =>
      ProviderScope.containerOf(t.element(find.byType(Scaffold).first));

  SalonCover cover(WidgetTester t) =>
      t.widget<SalonCover>(find.byType(SalonCover).first);

  SalonLogo heroLogo(WidgetTester t, String heroKey) => t.widget<SalonLogo>(
    find.descendant(
      of: find.byKey(Key(heroKey)),
      matching: find.byType(SalonLogo),
    ),
  );

  Future<void> openManage(
    WidgetTester tester,
    GoRouter router,
    String id,
  ) async {
    router.go(RouteNames.salonManage(id));
    await AppHarness.settle(tester);
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const Key('salon-manage-hero-card')),
    );
  }

  Future<void> pickFrom(WidgetTester tester, Key control, String row) async {
    await AppHarness.tapVisible(tester, find.byKey(control));
    await AppHarness.tapVisible(tester, find.byKey(Key(row)));
    await tester.pump();
  }

  Future<void> waitSnackGone(WidgetTester tester, String text) =>
      AppHarness.pumpUntilGone(
        tester,
        find.text(text),
        timeout: const Duration(seconds: 15),
      );

  testWidgets('SALON_OWNER uploads the cover and the logo: progress, in-place '
      'hero update, exact wire shape; a CLIENT then sees both on the public '
      'salon profile', (tester) async {
    final FakeBackend fb = FakeBackend();
    final GoRouter router = await bootAs(tester, fb, UserRole.salonOwner);
    await openManage(tester, router, _ownerSalon);
    final int salonReads = fb.getSalonByIdCalls;

    expect(find.byKey(const Key('salon-cover-edit')), findsOneWidget);
    expect(find.byKey(const Key('salon-logo-edit-badge')), findsOneWidget);
    expect(cover(tester).imageUrl, isNull);

    // ── Cover ──
    await pickFrom(
      tester,
      const Key('salon-cover-edit'),
      'image-source-gallery',
    );
    await AppHarness.pumpUntilFound(
      tester,
      find.descendant(
        of: find.byKey(const Key('salon-cover-editor')),
        matching: find.byType(UploadProgressOverlay),
      ),
    );
    await AppHarness.pumpUntilFound(
      tester,
      find.text(l10n(tester).salonCoverUpdated),
    );
    final String coverUrl = fb.mySalons.first['coverImageUrl'] as String;
    await AppHarness.pumpUntilCondition(
      tester,
      () =>
          cover(tester).imageUrl == coverUrl &&
          cover(tester).previewFile == null,
      description: 'the hero cover to render the uploaded photo',
    );
    expect(
      find.byWidgetPredicate(
        (Widget w) => w is RemoteImage && w.url == coverUrl,
      ),
      findsOneWidget,
    );
    await waitSnackGone(tester, l10n(tester).salonCoverUpdated);

    // ── Logo ──
    await pickFrom(
      tester,
      const Key('salon-logo-edit-badge'),
      'image-source-gallery',
    );
    await AppHarness.pumpUntilFound(
      tester,
      find.text(l10n(tester).avatarUpdated),
    );
    final String logoUrl = fb.mySalons.first['avatarUrl'] as String;
    await AppHarness.pumpUntilCondition(
      tester,
      () =>
          heroLogo(tester, 'salon-manage-hero-card').imageUrl == logoUrl &&
          heroLogo(tester, 'salon-manage-hero-card').previewFile == null,
      description: 'the hero logo to render the uploaded photo',
    );
    expect(
      fb.getSalonByIdCalls,
      salonReads,
      reason: 'patched in place — never a GET /salons/{id} refetch',
    );

    // Wire: exactly the slot path, exactly one `file` part.
    expect(fb.salonMediaUploadUris.map((Uri u) => u.path).toList(), <String>[
      '/api/v1/salons/$_ownerSalon/media/cover',
      '/api/v1/salons/$_ownerSalon/media/logo',
    ]);
    expect(fb.salonMediaUploadUris.every((Uri u) => u.query.isEmpty), isTrue);
    expect(fb.salonMediaUploadPartNames, <List<String>>[
      <String>['file'],
      <String>['file'],
    ]);
    await waitSnackGone(tester, l10n(tester).avatarUpdated);

    // ── A client sees both on the public salon profile ──
    await container(tester).read(authProvider.notifier).logout();
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('login_email')),
    );
    await AppHarness.loginAs(tester, fb, UserRole.client);
    router.go(RouteNames.salonPublicProfile(_ownerSalon));
    await AppHarness.settle(tester);
    await AppHarness.pumpUntilCondition(
      tester,
      () =>
          find.byType(SalonCover).evaluate().isNotEmpty &&
          cover(tester).imageUrl == coverUrl,
      description: 'the public profile to show the new cover',
    );
    expect(find.byKey(const Key('salon-cover-edit')), findsNothing);
    expect(find.byKey(const Key('salon-logo-edit-badge')), findsNothing);
    expect(
      find.byWidgetPredicate(
        (Widget w) => w is SalonLogo && w.imageUrl == logoUrl,
      ),
      findsOneWidget,
      reason: 'the public hero renders the logo',
    );
  });

  testWidgets('SALON_OWNER: 429 / 503 / 409 surface their copy and keep the '
      'photo for retry; remove brings back the gradient and the monogram', (
    tester,
  ) async {
    final FakeBackend fb = FakeBackend();
    fb.mySalons.first['coverImageUrl'] = 'https://media.test/salons/c0.jpg';
    fb.mySalons.first['avatarUrl'] = 'https://media.test/salons/l0.jpg';
    final GoRouter router = await bootAs(tester, fb, UserRole.salonOwner);
    await openManage(tester, router, _ownerSalon);

    for (final (int status, String copy) in <(int, String)>[
      (429, l10n(tester).uploadErrorRateLimited(30)),
      (503, l10n(tester).uploadErrorStorage),
      (409, l10n(tester).uploadErrorConflict),
    ]) {
      fb.salonMediaFailStatus = status;
      await pickFrom(
        tester,
        const Key('salon-cover-edit'),
        'image-source-gallery',
      );
      await AppHarness.pumpUntilFound(tester, find.text(copy));
      expect(find.byKey(const Key('upload-retry')), findsOneWidget);
      expect(
        cover(tester).imageUrl,
        'https://media.test/salons/c0.jpg',
        reason: '$status leaves the cover unchanged',
      );
      await waitSnackGone(tester, copy);
    }

    // The retry target re-sends the SAME photo once the server recovers.
    fb.salonMediaFailStatus = null;
    final int before = fb.salonMediaUploadUris.length;
    await AppHarness.tapVisible(tester, find.byKey(const Key('upload-retry')));
    await AppHarness.pumpUntilFound(
      tester,
      find.text(l10n(tester).salonCoverUpdated),
    );
    expect(fb.salonMediaUploadUris.length, before + 1);
    await waitSnackGone(tester, l10n(tester).salonCoverUpdated);

    // Remove the cover → gradient.
    await pickFrom(
      tester,
      const Key('salon-cover-edit'),
      'image-source-remove',
    );
    await AppHarness.pumpUntilFound(
      tester,
      find.text(l10n(tester).salonCoverRemoved),
    );
    await AppHarness.pumpUntilCondition(
      tester,
      () => cover(tester).imageUrl == null,
      description: 'the cover to fall back to the gradient',
    );
    expect(find.byIcon(Icons.photo_camera_back_outlined), findsOneWidget);
    await waitSnackGone(tester, l10n(tester).salonCoverRemoved);

    // Remove the logo → monogram.
    await pickFrom(
      tester,
      const Key('salon-logo-edit-badge'),
      'image-source-remove',
    );
    await AppHarness.pumpUntilFound(
      tester,
      find.text(l10n(tester).avatarRemoved),
    );
    await AppHarness.pumpUntilCondition(
      tester,
      () => heroLogo(tester, 'salon-manage-hero-card').imageUrl == null,
      description: 'the logo to fall back to the monogram',
    );
    expect(fb.salonMediaDeleteUris.map((Uri u) => u.path).toList(), <String>[
      '/api/v1/salons/$_ownerSalon/media/cover',
      '/api/v1/salons/$_ownerSalon/media/logo',
    ]);
    expect(fb.mySalons.first['coverImageUrl'], isNull);
    expect(fb.mySalons.first['avatarUrl'], isNull);
  });

  testWidgets('SALON_ADMIN sees NO edit controls; a forced upload / removal '
      'is refused (403) with the owner-only copy and changes nothing', (
    tester,
  ) async {
    final FakeBackend fb = FakeBackend();
    final GoRouter router = await bootAs(tester, fb, UserRole.salonAdmin);
    await openManage(tester, router, _adminSalon);

    expect(find.byKey(const Key('salon-cover-edit')), findsNothing);
    expect(find.byKey(const Key('salon-cover-editor')), findsNothing);
    expect(find.byKey(const Key('salon-logo-editor')), findsNothing);
    expect(find.byKey(const Key('salon-logo-edit-badge')), findsNothing);

    // Test hook: drive the controller directly against the fake's 403.
    final ProviderContainer c = container(tester);
    final ProviderSubscription<AvatarUploadState> keep = c.listen(
      salonImageUploadControllerProvider(_adminSalon, SalonImageSlot.cover),
      (_, _) {},
    );
    addTearDown(keep.close);
    final AvatarChangeResult removed = await c
        .read(
          salonImageUploadControllerProvider(
            _adminSalon,
            SalonImageSlot.cover,
          ).notifier,
        )
        .remove();
    final AvatarChangeResult uploaded =
        await tester.runAsync(
          () => c
              .read(
                salonImageUploadControllerProvider(
                  _adminSalon,
                  SalonImageSlot.cover,
                ).notifier,
              )
              .change(ImageSourceChoice.gallery),
        ) ??
        const AvatarChangeCancelled();
    for (final AvatarChangeResult r in <AvatarChangeResult>[
      removed,
      uploaded,
    ]) {
      expect(r, isA<AvatarChangeFailed>());
      expect(
        (r as AvatarChangeFailed).failure.message(l10n(tester)),
        'Змінювати фото салону може лише власник',
      );
    }
    expect(
      fb.salonMediaDeleteUris.single.path,
      '/api/v1/salons/$_adminSalon/media/cover',
    );
    expect(
      fb.salonMediaUploadUris.single.path,
      '/api/v1/salons/$_adminSalon/media/cover',
    );
    await tester.pump();
    expect(cover(tester).imageUrl, isNull, reason: 'the salon is unchanged');
    expect(heroLogo(tester, 'salon-manage-hero-card').imageUrl, isNull);
  });
}
