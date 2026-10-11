// Phase 367 (9.6) — fake-backed E2E: SALON_OWNER, SALON_ADMIN and CLIENT set
// their OWN avatar through the shared flow, end to end.
//
// Drives the REAL screens, the REAL `AvatarUploadController` (+ the promoted
// `MediaUploadFlow`), the REAL `MediaPickService` and the REAL
// `HttpMediaUploadRepository` over `FakeBackend`; only the native pick / crop
// plugin is the shared headless `FixtureAvatarGateway`.
//
// Also pins the locked rule "a personal avatar is set only by the person
// themselves": every upload is a bare `POST /api/v1/media/avatar` whose only
// multipart part is `file`, and every removal a bare `DELETE` — no query, no
// body, no user id anywhere on the wire (`expectSelfOnlyAvatarRequests`).
//
// Runs headless: `flutter test integration_test/owner_admin_avatar_upload_test.dart
// -d flutter-tester`.

import 'dart:io';

import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/core/media/pick/image_pick_gateway.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
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
    final Directory scratch = Directory.systemTemp.createTempSync('own_avatar');
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
      find.descendant(
        of: find.byKey(editor),
        matching: find.byKey(const Key('avatar-edit-badge')),
      ),
    );
    // `tapVisible`, not found-then-tap: the source sheet is still sliding in
    // when its rows first exist, and a tap then lands below the 800x600
    // viewport (flaked the owner cases ~2 in 5 runs).
    await AppHarness.tapVisible(tester, find.byKey(Key(row)));
    await tester.pump();
  }

  testWidgets('SALON_OWNER: upload from the own-profile identity card, the '
      'photo lands in place; «Особисті дані» (/owner/edit/personal) shows it; '
      'remove reverts to the monogram', (tester) async {
    final FakeBackend fb = FakeBackend();
    final GoRouter router = await bootAs(tester, fb, UserRole.salonOwner);
    const Key card = Key('owner-own-profile-avatar-editor');

    router.go(RouteNames.ownerOwnProfile);
    await AppHarness.settle(tester);
    expect(editorAt(tester, card).state, AvatarEditState.pristine);

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
      // The local preview is held (<= 2 s) until the remote photo is warm.
      description: 'owner identity card to render the new photo',
    );
    expect(
      find.descendant(
        of: find.byKey(card),
        matching: find.byWidgetPredicate(
          (Widget w) => w is RemoteImage && w.url == _firstUrl,
        ),
      ),
      findsOneWidget,
    );
    expect(fb.mediaAvatarUploadCalls, 1);
    expectSelfOnlyAvatarRequests(fb, uploads: 1);

    router.go(RouteNames.ownerEditPersonal);
    await AppHarness.settle(tester);
    expect(
      editorAt(tester, const Key('avatar-editor')).imageUrl,
      _firstUrl,
      reason: 'the owner «Особисті дані» reads the same patched session user',
    );

    await AppHarness.pumpUntilGone(
      tester,
      find.text(l10n(tester).avatarUpdated),
      timeout: const Duration(seconds: 15),
    );
    await tapBadgeThen(
      tester,
      const Key('avatar-editor'),
      'image-source-remove',
    );
    await AppHarness.pumpUntilFound(
      tester,
      find.text(l10n(tester).avatarRemoved),
    );
    expect(fb.mediaAvatarDeleteCalls, 1);
    expectSelfOnlyAvatarRequests(fb, uploads: 1, deletes: 1);
    await AppHarness.pumpUntilCondition(
      tester,
      () =>
          editorAt(tester, const Key('avatar-editor')).state ==
          AvatarEditState.pristine,
      description: 'owner edit screen to fall back to the monogram',
    );
  });

  // Team-tab fix (2026-10-05) — the shell keeps the «Команда» roster
  // (`salonManagementProfileProvider`) alive in IndexedStack slot 0, keyed
  // only on the user id, so a self-avatar upload from the «Профіль» slot left
  // the owner's OWN staff card on the old photo. `applySelfAvatarUrl` now
  // patches that cached roster row in place — no `GET …/staff` refetch.
  // The fake roster's GET never learns the new URL, so ONLY the in-place
  // patch can turn this green.
  //
  // Phase 384 (24.1g) — the owner's «Профіль» nav tile now LEAVES the shell
  // for owner master mode (`go`), which drops the roster's last watcher —
  // the roster then only lingers in its 60 s leave-armed cache window, not as
  // a live watched entry, so that path is no longer the one this test pins.
  // The upload is now made from the owner's own-row tap on «Команда»
  // (`/profile/owner`, a PUSH over the still-mounted shell) — the one owner
  // path that still uploads while the roster is live — then back to «Команда».
  testWidgets('SALON_OWNER in the shell: upload from the own «Команда» card '
      '(/profile/owner), then back — the owner card shows the new photo with '
      'no roster refetch', (tester) async {
    const String salonId = 'salon-xyz';
    const Key ownerCard = Key('salon-manage-staff-card-user-owner-1');
    final FakeBackend fb = FakeBackend();
    fb.mySalons.add(<String, dynamic>{
      'id': salonId,
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
    // The owner is auto-enrolled as a master of their own salon — first row,
    // so the card sits in the grid's first row.
    fb.salonStaff.insert(0, <String, dynamic>{
      'userId': 'user-owner-1',
      'masterId': 'master-owner-1',
      'role': 'SALON_MASTER',
      'masterType': 'SALON_OWNER',
      'firstName': 'Оксана',
      'lastName': 'Власниця',
      'professionalTitle': null,
      'avatarUrl': null,
      'phoneNumber': '+380671110000',
      'instagram': null,
      'bio': null,
      'avgRating': null,
      'reviewCount': 0,
      'serviceCount': 0,
    });
    final GoRouter router = await bootAs(tester, fb, UserRole.salonOwner);
    router.go(RouteNames.salonShell(salonId));
    await AppHarness.settle(tester);

    Finder ownerPhoto() => find.descendant(
      of: find.byKey(ownerCard),
      matching: find.byWidgetPredicate(
        (Widget w) => w is RemoteImage && w.url == _firstUrl,
      ),
    );

    // «Команда» (nav 2): the owner card renders, photo-less.
    await tester.tap(find.byKey(const Key('salon-nav-tile-2')));
    await AppHarness.settle(tester);
    await tester.ensureVisible(find.byKey(ownerCard));
    await AppHarness.settle(tester);
    expect(find.byKey(ownerCard), findsOneWidget);
    expect(ownerPhoto(), findsNothing);
    final int staffCalls = fb.getSalonStaffCalls;

    // Own card → /profile/owner (pushed over the shell): upload from the
    // owner identity card.
    await tester.tap(find.byKey(ownerCard));
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.ownerOwnProfile);
    await tapBadgeThen(
      tester,
      const Key('owner-own-profile-avatar-editor'),
      'image-source-gallery',
    );
    await AppHarness.pumpUntilFound(
      tester,
      find.text(l10n(tester).avatarUpdated),
    );
    expectSelfOnlyAvatarRequests(fb, uploads: 1);

    // The success snack floats over the bottom nav — let it go first.
    await AppHarness.pumpUntilGone(
      tester,
      find.text(l10n(tester).avatarUpdated),
      timeout: const Duration(seconds: 15),
    );

    // Back (pop) on «Команда»: the SAME live roster now carries the new photo.
    await tester.binding.handlePopRoute();
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.salonShell(salonId));
    await tester.ensureVisible(find.byKey(ownerCard));
    await AppHarness.settle(tester);
    expect(ownerPhoto(), findsOneWidget);
    expect(
      fb.getSalonStaffCalls,
      staffCalls,
      reason: 'patched in place — never a GET /salons/{id}/staff refetch',
    );
  });

  testWidgets('SALON_ADMIN: upload from «Особисті дані»; the own-profile '
      'identity card then shows it; remove', (tester) async {
    final FakeBackend fb = FakeBackend();
    final GoRouter router = await bootAs(tester, fb, UserRole.salonAdmin);
    const Key edit = Key('avatar-editor');
    const Key card = Key('admin-own-profile-avatar-editor');

    router.go(RouteNames.adminEditPersonal);
    await AppHarness.settle(tester);
    expect(editorAt(tester, edit).state, AvatarEditState.pristine);

    await tapBadgeThen(tester, edit, 'image-source-gallery');
    await AppHarness.pumpUntilFound(
      tester,
      find.text(l10n(tester).avatarUpdated),
    );
    await AppHarness.pumpUntilCondition(
      tester,
      () => editorAt(tester, edit).imageUrl == _firstUrl,
      description: 'admin edit screen to render the new photo',
    );
    expectSelfOnlyAvatarRequests(fb, uploads: 1);

    router.go(RouteNames.adminOwnProfile);
    await AppHarness.settle(tester);
    await AppHarness.pumpUntilCondition(
      tester,
      () => editorAt(tester, card).imageUrl == _firstUrl,
      description: 'admin identity card to carry the new photo (no refetch)',
    );

    await AppHarness.pumpUntilGone(
      tester,
      find.text(l10n(tester).avatarUpdated),
      timeout: const Duration(seconds: 15),
    );
    await tapBadgeThen(tester, card, 'image-source-remove');
    await AppHarness.pumpUntilFound(
      tester,
      find.text(l10n(tester).avatarRemoved),
    );
    expect(fb.mediaAvatarDeleteCalls, 1);
    expectSelfOnlyAvatarRequests(fb, uploads: 1, deletes: 1);
    await AppHarness.pumpUntilCondition(
      tester,
      () => editorAt(tester, card).state == AvatarEditState.pristine,
      description: 'admin identity card to fall back to the monogram',
    );
  });

  testWidgets('CLIENT: the «Особисті дані» badge is LIVE (no «Незабаром»): '
      'upload lands on the edit screen and the Головна profile card', (
    tester,
  ) async {
    final FakeBackend fb = FakeBackend();
    final GoRouter router = await bootAs(tester, fb, UserRole.client);

    router.go(RouteNames.clientEditPersonal);
    await AppHarness.settle(tester);
    await tapBadgeThen(
      tester,
      const Key('avatar-editor'),
      'image-source-gallery',
    );
    await AppHarness.pumpUntilFound(
      tester,
      find.text(l10n(tester).avatarUpdated),
    );
    expect(find.text(l10n(tester).snackbarAvatarSoon), findsNothing);
    expect(fb.mediaAvatarUploadCalls, 1);
    expectSelfOnlyAvatarRequests(fb, uploads: 1);

    router.go(RouteNames.clientHome);
    await AppHarness.settle(tester);
    await AppHarness.pumpUntilCondition(
      tester,
      () =>
          editorAt(tester, const Key('home-hub-avatar-editor')).imageUrl ==
          _firstUrl,
      description: 'Головна profile card to carry the new photo',
    );
  });

  testWidgets('503 storage-off (owner): failure snack, nothing set, the '
      'photo is kept under the retry veil', (tester) async {
    final FakeBackend fb = FakeBackend(mediaAvatarUploadStatus: 503);
    final GoRouter router = await bootAs(tester, fb, UserRole.salonOwner);
    const Key card = Key('owner-own-profile-avatar-editor');

    router.go(RouteNames.ownerOwnProfile);
    await AppHarness.settle(tester);
    await tapBadgeThen(tester, card, 'image-source-gallery');
    await AppHarness.pumpUntilFound(
      tester,
      find.text(l10n(tester).uploadErrorStorage),
    );

    expect(fb.mediaAvatarUrl, isNull);
    expect(editorAt(tester, card).uploadFailed, isTrue);
    expect(editorAt(tester, card).imageUrl, isNull);
    expect(find.text(l10n(tester).avatarUpdated), findsNothing);

    // Retry from the card's veil re-sends the SAME kept photo (no picker).
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
      description: 'the owner retry to reach POST /media/avatar and fail again',
    );
    expect(gateway.picks, 1, reason: 'retry must not reopen the picker');
    expectSelfOnlyAvatarRequests(fb, uploads: 2);
    await AppHarness.pumpUntilGone(
      tester,
      find.text(l10n(tester).uploadErrorStorage),
      timeout: const Duration(seconds: 15),
    );
  });
}
