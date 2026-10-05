// Phase 367 (9.6) QA — fake-backed E2E closing the role × surface ×
// (upload / remove / retry / 503) gaps the phase's own two E2E files leave:
//
//   • CLIENT on Головна (`HomeProfileCard`) and Паспорт (`_ProfileBlock`) —
//     upload FROM the hub card, remove FROM the passport card, and the 503 +
//     retry path on the passport card (the CLIENT 503 path was untested).
//   • SALON_ADMIN 503 + retry on the own-profile identity card.
//   • INDEPENDENT_MASTER upload + remove FROM the own-profile header card
//     (073 only drove it from «Особисті дані»).
//   • SALON_MASTER remove FROM the header card, and 503 + retry there.
//   • Read-only surfaces — another master's public profile, a salon staff
//     profile — render NO camera badge (Scope update 2: "no dead badges").
//
// Every write is also checked on the wire (`expectSelfOnlyAvatarRequests`):
// a bare `POST /media/avatar` whose only multipart part is `file`, a bare
// `DELETE` — no user id anywhere.
//
// Same harness as `owner_admin_avatar_upload_test.dart`: REAL screens,
// controller, `MediaPickService` and upload repository over `FakeBackend`;
// only the native pick / crop plugin is the headless `FixtureAvatarGateway`.
//
// Runs headless: `flutter test integration_test/own_avatar_surface_matrix_test.dart
// -d flutter-tester`.

import 'dart:async';
import 'dart:io';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/core/media/pick/image_pick_gateway.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_staff_profile_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/fake_media_cache.dart';
import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/fixture_avatar_gateway.dart';

const String _firstUrl = 'https://media.test/avatars/u1/1.jpg';

const Key _homeCard = Key('home-hub-avatar-editor');
const Key _passportCard = Key('passport-avatar-editor');
const Key _adminCard = Key('admin-own-profile-avatar-editor');
const Key _masterCard = Key('master-profile-avatar-editor');
const Key _salonMasterCard = Key('salon-master-profile-avatar-editor');
const Key _badge = Key('avatar-edit-badge');

/// `salon-xyz` is not in the default `/salons/mine` list — the same seed
/// `salon_staff_settings_flow_test.dart` uses so `salonManageGuard` admits
/// the owner onto its staff profile.
void _seedSalonXyzIntoMySalons(FakeBackend fb) {
  fb.mySalons.add(<String, dynamic>{
    'id': 'salon-xyz',
    'ownerId': 'user-owner-1',
    'name': 'Студія Краси «Камелія»',
    'city': 'Київ',
    'cityId': 'city-kyiv',
    'oblastId': 'oblast-kyiv',
    'street': 'вул. Хрещатик',
    'buildingNo': '12',
    'isActive': true,
    'isPrimary': false,
  });
}

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

  late FixtureAvatarGateway gateway;

  Future<GoRouter> bootAs(
    WidgetTester tester,
    FakeBackend fb,
    UserRole role,
  ) async {
    gateway = FixtureAvatarGateway();
    final Directory scratch = Directory.systemTemp.createTempSync('own_matrix');
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

  NeumorphicAvatarEditor editorAt(WidgetTester t, Key key) =>
      t.widget<NeumorphicAvatarEditor>(find.byKey(key));

  Future<void> tapBadgeThen(WidgetTester tester, Key editor, String row) async {
    await AppHarness.tapVisible(
      tester,
      find.descendant(of: find.byKey(editor), matching: find.byKey(_badge)),
    );
    // `tapVisible`: the source sheet is still sliding in when its rows first
    // exist — a found-then-tap can land below the 800x600 viewport.
    await AppHarness.tapVisible(tester, find.byKey(Key(row)));
    await tester.pump();
  }

  Future<void> uploadAndWait(WidgetTester tester, Key card) async {
    await tapBadgeThen(tester, card, 'image-source-gallery');
    await AppHarness.pumpUntilFound(
      tester,
      find.text(l10n(tester).avatarUpdated),
    );
    await AppHarness.pumpUntilCondition(
      tester,
      () =>
          editorAt(tester, card).imageUrl == _firstUrl &&
          editorAt(tester, card).previewFile == null,
      description: '$card to render the uploaded photo, preview released',
    );
    // The snack host is a process-wide singleton: let the success snack go
    // before the next action so its own snack is not pre-empted.
    await AppHarness.pumpUntilGone(
      tester,
      find.text(l10n(tester).avatarUpdated),
      timeout: const Duration(seconds: 15),
    );
  }

  Future<void> removeAndWait(WidgetTester tester, Key card) async {
    await tapBadgeThen(tester, card, 'image-source-remove');
    await AppHarness.pumpUntilFound(
      tester,
      find.text(l10n(tester).avatarRemoved),
    );
    await AppHarness.pumpUntilCondition(
      tester,
      () =>
          editorAt(tester, card).state == AvatarEditState.pristine &&
          editorAt(tester, card).imageUrl == null,
      description: '$card to fall back to the monogram',
    );
  }

  /// 503 on [card], then the veil's retry re-sends the kept photo: a second
  /// request, no picker, still failed (the fake's status is fixed at
  /// construction), nothing set.
  Future<void> failThenRetry(
    WidgetTester tester,
    FakeBackend fb,
    Key card,
  ) async {
    await tapBadgeThen(tester, card, 'image-source-gallery');
    await AppHarness.pumpUntilFound(
      tester,
      find.text(l10n(tester).uploadErrorStorage),
    );
    expect(fb.mediaAvatarUploadCalls, 1);
    expect(fb.mediaAvatarUrl, isNull, reason: 'a 503 never sets the avatar');
    expect(editorAt(tester, card).uploadFailed, isTrue);
    expect(editorAt(tester, card).imageUrl, isNull);
    expect(editorAt(tester, card).previewFile, isNotNull);
    expect(find.text(l10n(tester).avatarUpdated), findsNothing);

    await AppHarness.tapVisible(
      tester,
      find.descendant(
        of: find.byKey(card),
        matching: find.byKey(const Key('upload-retry')),
      ),
    );
    await AppHarness.pumpUntilCondition(
      tester,
      () =>
          fb.mediaAvatarUploadCalls == 2 && editorAt(tester, card).uploadFailed,
      description: '$card retry to reach POST /media/avatar and fail again',
    );
    expect(gateway.picks, 1, reason: 'retry must not reopen the picker');
    expect(find.byKey(const Key('image-source-gallery')), findsNothing);
    expect(fb.mediaAvatarUrl, isNull);
    expectSelfOnlyAvatarRequests(fb, uploads: 2);
    await AppHarness.pumpUntilGone(
      tester,
      find.text(l10n(tester).uploadErrorStorage),
      timeout: const Duration(seconds: 15),
    );
  }

  group('CLIENT — Головна + Паспорт cards', () {
    testWidgets('upload FROM the Головна card; Паспорт shows it; remove FROM '
        'the Паспорт card; Головна reverts to the monogram', (tester) async {
      final FakeBackend fb = FakeBackend();
      final GoRouter router = await bootAs(tester, fb, UserRole.client);

      router.go(RouteNames.clientHome);
      await AppHarness.settle(tester);
      expect(editorAt(tester, _homeCard).state, AvatarEditState.pristine);
      await uploadAndWait(tester, _homeCard);
      expect(fb.mediaAvatarUploadCalls, 1);

      router.go(RouteNames.clientPassport);
      await AppHarness.settle(tester);
      await AppHarness.pumpUntilCondition(
        tester,
        () => editorAt(tester, _passportCard).imageUrl == _firstUrl,
        description: 'Паспорт card to carry the Головна upload (no refetch)',
      );

      await removeAndWait(tester, _passportCard);
      expect(fb.mediaAvatarDeleteCalls, 1);
      expect(fb.mediaAvatarUrl, isNull);
      expectSelfOnlyAvatarRequests(fb, uploads: 1, deletes: 1);

      router.go(RouteNames.clientHome);
      await AppHarness.settle(tester);
      await AppHarness.pumpUntilCondition(
        tester,
        () =>
            editorAt(tester, _homeCard).imageUrl == null &&
            editorAt(tester, _homeCard).state == AvatarEditState.pristine,
        description: 'Головна card to fall back to the monogram',
      );
    });

    testWidgets('503 on the Паспорт card: failure snack, photo kept under the '
        'veil; retry re-sends it without the picker', (tester) async {
      final FakeBackend fb = FakeBackend(mediaAvatarUploadStatus: 503);
      final GoRouter router = await bootAs(tester, fb, UserRole.client);

      router.go(RouteNames.clientPassport);
      await AppHarness.settle(tester);

      await failThenRetry(tester, fb, _passportCard);
    });
  });

  testWidgets('SALON_ADMIN: 503 on the own-profile identity card, retry '
      're-sends the kept photo', (tester) async {
    final FakeBackend fb = FakeBackend(mediaAvatarUploadStatus: 503);
    final GoRouter router = await bootAs(tester, fb, UserRole.salonAdmin);

    router.go(RouteNames.adminOwnProfile);
    await AppHarness.settle(tester);

    await failThenRetry(tester, fb, _adminCard);
  });

  testWidgets('INDEPENDENT_MASTER: upload FROM the own-profile header; '
      '«Особисті дані» shows it; remove FROM the header', (tester) async {
    final FakeBackend fb = FakeBackend();
    final GoRouter router = await bootAs(
      tester,
      fb,
      UserRole.independentMaster,
    );

    router.go(RouteNames.masterProfile);
    await AppHarness.settle(tester);
    expect(editorAt(tester, _masterCard).state, AvatarEditState.pristine);
    await uploadAndWait(tester, _masterCard);

    unawaited(router.push<void>(RouteNames.masterEditPersonal));
    await AppHarness.settle(tester);
    expect(
      editorAt(tester, const Key('avatar-editor')).imageUrl,
      _firstUrl,
      reason: '«Особисті дані» reads the same patched master profile',
    );
    router.pop();
    await AppHarness.settle(tester);

    await removeAndWait(tester, _masterCard);
    expect(fb.mediaAvatarDeleteCalls, 1);
    expect(fb.mediaAvatarUrl, isNull);
    expectSelfOnlyAvatarRequests(fb, uploads: 1, deletes: 1);
  });

  group('SALON_MASTER — own-profile header', () {
    testWidgets('upload then remove FROM the header card', (tester) async {
      final FakeBackend fb = FakeBackend();
      final GoRouter router = await bootAs(tester, fb, UserRole.salonMaster);

      router.go(RouteNames.salonMasterProfile);
      await AppHarness.settle(tester);
      await uploadAndWait(tester, _salonMasterCard);
      await removeAndWait(tester, _salonMasterCard);

      expect(fb.mediaAvatarDeleteCalls, 1);
      expect(fb.mediaAvatarUrl, isNull);
      expectSelfOnlyAvatarRequests(fb, uploads: 1, deletes: 1);
    });

    testWidgets('503 on the header card, retry re-sends the kept photo', (
      tester,
    ) async {
      final FakeBackend fb = FakeBackend(mediaAvatarUploadStatus: 503);
      final GoRouter router = await bootAs(tester, fb, UserRole.salonMaster);

      router.go(RouteNames.salonMasterProfile);
      await AppHarness.settle(tester);

      await failThenRetry(tester, fb, _salonMasterCard);
    });
  });

  group('read-only surfaces render NO camera badge', () {
    testWidgets('CLIENT viewing another master\'s public profile', (
      tester,
    ) async {
      final FakeBackend fb = FakeBackend();
      final GoRouter router = await bootAs(tester, fb, UserRole.client);

      // Positive control: the SAME finder sees the badge on the own card, so
      // the absence below is not a finder that can never match.
      router.go(RouteNames.clientHome);
      await AppHarness.settle(tester);
      expect(find.byKey(_badge), findsOneWidget);

      unawaited(router.push(RouteNames.masterPublicProfile('master-aaa')));
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(PublicMasterProfileScreen),
      );
      await AppHarness.settle(tester);

      final Finder screen = find.byType(PublicMasterProfileScreen);
      expect(
        find.descendant(of: screen, matching: find.byKey(_badge)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: screen,
          matching: find.byType(NeumorphicAvatarEditor),
        ),
        findsNothing,
      );
    });

    testWidgets('SALON_OWNER viewing a salon staff member\'s profile', (
      tester,
    ) async {
      final FakeBackend fb = FakeBackend();
      _seedSalonXyzIntoMySalons(fb);
      final GoRouter router = await bootAs(tester, fb, UserRole.salonOwner);

      // Positive control (see above): the owner's OWN card has the badge.
      router.go(RouteNames.ownerOwnProfile);
      await AppHarness.settle(tester);
      expect(find.byKey(_badge), findsOneWidget);

      router.go(RouteNames.salonManageStaffMember('salon-xyz', 'admin-zzz'));
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(SalonStaffProfileScreen),
      );
      await AppHarness.settle(tester);

      final Finder screen = find.byType(SalonStaffProfileScreen);
      expect(
        find.descendant(of: screen, matching: find.byKey(_badge)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: screen,
          matching: find.byType(NeumorphicAvatarEditor),
        ),
        findsNothing,
      );
    });
  });
}
