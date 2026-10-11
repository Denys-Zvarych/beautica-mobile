// Phase 369 (9.8) — salon logo / cover editing on the management profile.
//
// Locked product rule (user, 2026-10-04): only the SALON_OWNER can change the
// salon logo and banner. This file pins:
//   • owner: the logo badge + the cover camera control are rendered, a tap
//     opens the 071 source sheet, an upload shows progress and lands in place
//     (no reload frame, no refetch), 403 / 429 / 409 / 503 surface their copy;
//   • admin: neither control exists and a tap on the logo opens nothing;
//   • the logo badge clears the hero's text column (geometry guard).

import 'dart:async';
import 'dart:io';

import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:beautica_mobile/core/media/upload/upload_task.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/core/widgets/upload_state_overlay.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_management_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_cover_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/media/pick/scripted_pick_gateway.dart';
import '../../../helpers/avatar_badge_geometry.dart';
import '../../../helpers/fake_media_cache.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/core/media/beautica_image.dart';

const String _kSalonId = 'salon-1';
const String _kCover = 'https://media.test/salons/1/cover.jpg';
const String _kLogo = 'https://media.test/salons/1/logo.jpg';

const Salon _salon = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  street: 'вул. Велика Васильківська',
  buildingNo: '44',
  avgRating: 4.9,
  reviewCount: 128,
);

User _user(UserRole role) => User(
  id: role == UserRole.salonOwner ? 'owner-1' : 'admin-1',
  email: 'x@beautica.ua',
  role: role,
  firstName: 'Оксана',
  lastName: 'Швець',
  salonId: role == UserRole.salonAdmin ? _kSalonId : null,
);

UserRole _role = UserRole.salonOwner;

class _Auth extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: _user(_role), accessToken: 't');
}

int _manageBuilds = 0;
Salon _seed = _salon;

class _Manage extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async {
    _manageBuilds++;
    return (_seed, const <SalonStaffMember>[]);
  }
}

class _MySalons extends MySalons {
  @override
  Future<List<Salon>> build() async => <Salon>[_seed];
}

/// Phase 369 QA — `mySalonsProvider` that never resolves (the cold-deep-link
/// window `salonManageGuard`'s SALON_OWNER arm admits before ownership is
/// known).
class _MySalonsPending extends MySalons {
  @override
  Future<List<Salon>> build() => Completer<List<Salon>>().future;
}

/// Phase 369 QA — the owner's resolved list holds ONLY another salon.
class _MySalonsOther extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[
    Salon(id: 'salon-A-not-this-one', name: 'Інший салон'),
  ];
}

/// Phase 369 fix — resolves with this salon on the FIRST build, then every
/// rebuild (an `invalidate` after a salon was deleted / registered) hangs:
/// Riverpod 3 holds `AsyncData` + `isLoading: true` for the whole refresh.
class _MySalonsRefreshing extends MySalons {
  int _builds = 0;

  @override
  Future<List<Salon>> build() async {
    if (_builds++ == 0) return <Salon>[_seed];
    return Completer<List<Salon>>().future;
  }
}

class _Uploads implements MediaUploadRepository {
  final List<(String, SalonImageSlot)> uploads = <(String, SalonImageSlot)>[];
  final List<(String, SalonImageSlot)> deletes = <(String, SalonImageSlot)>[];
  Completer<String> result = Completer<String>();
  StreamController<double> progress = StreamController<double>.broadcast();
  UploadFailure? deleteFailure;

  @override
  UploadTask<String> uploadAvatar(File file) => throw UnimplementedError();

  @override
  Future<void> deleteAvatar() => throw UnimplementedError();

  @override
  UploadTask<String> uploadSalonImage(
    String salonId,
    SalonImageSlot slot,
    File file,
  ) {
    uploads.add((salonId, slot));
    result = Completer<String>();
    progress = StreamController<double>.broadcast();
    return UploadTask<String>(
      progress: progress.stream,
      result: result.future,
      onCancel: () {},
    );
  }

  @override
  Future<void> deleteSalonImage(String salonId, SalonImageSlot slot) async {
    deletes.add((salonId, slot));
    final UploadFailure? f = deleteFailure;
    if (f != null) throw f;
  }
}

/// Interleaves real-async turns (the pick pipeline does real file I/O) with
/// frames (the sheet's pop animation) until [cond] holds.
Future<void> pumpUntil(WidgetTester tester, bool Function() cond) async {
  for (int i = 0; i < 300 && !cond(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    // fixed-wait-ok: one frame per real-async turn inside a bounded poll.
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(cond(), isTrue, reason: 'condition never held');
}

void main() {
  late Directory scratch;
  late Directory outside;
  late ScriptedPickGateway gw;
  late _Uploads uploads;

  setUp(() {
    _manageBuilds = 0;
    _seed = _salon;
    scratch = Directory.systemTemp.createTempSync('salon_photo_scratch');
    outside = Directory.systemTemp.createTempSync('salon_photo_out');
    gw = ScriptedPickGateway(scratch: scratch, outside: outside);
    uploads = _Uploads();
    MediaConfig.debugAllowedHosts = <String>{'media.test'};
    debugMediaCacheManager = FakeMediaCacheManager(mediaLoadingForever);
  });
  tearDown(() {
    debugMediaCacheManager = null;
    MediaConfig.debugAllowedHosts = null;
    scratch.deleteSync(recursive: true);
    outside.deleteSync(recursive: true);
  });

  Future<void> pump(
    WidgetTester tester,
    UserRole role, {
    MySalons Function() mySalons = _MySalons.new,
    bool embedded = false,
  }) async {
    _role = role;
    await tester.pumpApp(
      SalonManagementProfileScreen(salonId: _kSalonId, embedded: embedded),
      width: 360,
      height: 900,
      overrides: <Object>[
        authProvider.overrideWith(_Auth.new),
        salonManagementProfileProvider.overrideWith(_Manage.new),
        mySalonsProvider.overrideWith(mySalons),
        hasUnreadNotificationsProvider.overrideWithValue(false),
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        mediaPickServiceProvider.overrideWithValue(
          MediaPickService(gw, tempDir: () async => scratch),
        ),
        mediaUploadRepositoryProvider.overrideWithValue(uploads),
      ],
    );
    await tester.pumpAndSettle();
  }

  SalonCover cover(WidgetTester tester) =>
      tester.widget<SalonCover>(find.byType(SalonCover));
  SalonLogo heroLogo(WidgetTester tester) => tester.widget<SalonLogo>(
    find.descendant(
      of: find.byKey(const Key('salon-manage-hero-card')),
      matching: find.byType(SalonLogo),
    ),
  );

  group('owner', () {
    testWidgets('sees the logo badge and the cover camera control', (
      tester,
    ) async {
      await pump(tester, UserRole.salonOwner);
      expect(find.byKey(const Key('salon-logo-editor')), findsOneWidget);
      expect(find.byKey(const Key('salon-logo-edit-badge')), findsOneWidget);
      expect(find.byKey(const Key('salon-cover-edit')), findsOneWidget);
      expect(find.byKey(const Key('salon-cover-editor')), findsOneWidget);
    });

    testWidgets('a tap on the logo badge opens the source sheet (no remove '
        'without a logo)', (tester) async {
      await pump(tester, UserRole.salonOwner);
      await tester.tap(find.byKey(const Key('salon-logo-edit-badge')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('image-source-gallery')), findsOneWidget);
      expect(find.byKey(const Key('image-source-remove')), findsNothing);
    });

    testWidgets('a tap on the logo mark itself opens the sheet too; with a '
        'logo it offers remove', (tester) async {
      _seed = _salon.copyWith(avatarUrl: _kLogo);
      await pump(tester, UserRole.salonOwner);
      await tester.tap(find.byKey(const Key('salon-logo-editor')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('image-source-remove')), findsOneWidget);
    });

    testWidgets('a tap on the cover control opens the sheet', (tester) async {
      _seed = _salon.copyWith(coverImageUrl: _kCover);
      await pump(tester, UserRole.salonOwner);
      await tester.tap(find.byKey(const Key('salon-cover-edit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('image-source-camera')), findsOneWidget);
      expect(find.byKey(const Key('image-source-remove')), findsOneWidget);
    });

    testWidgets('cover upload: progress overlay (100% is not done), then the '
        'cover patches in place — no reload frame, no refetch', (tester) async {
      await pump(tester, UserRole.salonOwner);
      await tester.tap(find.byKey(const Key('salon-cover-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('image-source-gallery')));
      await pumpUntil(tester, () => uploads.uploads.isNotEmpty);
      await tester.pump();
      expect(uploads.uploads.single, (_kSalonId, SalonImageSlot.cover));
      expect(cover(tester).previewFile, isNotNull);
      expect(
        find.descendant(
          of: find.byKey(const Key('salon-cover-editor')),
          matching: find.byType(UploadProgressOverlay),
        ),
        findsOneWidget,
      );

      uploads.progress.add(1.0);
      await tester.pump();
      expect(
        find.byType(UploadProgressOverlay),
        findsOneWidget,
        reason: '100% sent is not success',
      );
      expect(cover(tester).imageUrl, isNull);

      uploads.result.complete(_kCover);
      await pumpUntil(
        tester,
        () => find.byType(VelvetSnack).evaluate().isNotEmpty,
      );
      await pumpVelvetSnackIn(tester);
      expect(cover(tester).imageUrl, _kCover);
      expect(_manageBuilds, 1, reason: 'patched, never refetched');
      expect(
        find.byKey(const Key('salon-manage-hero-card')),
        findsOneWidget,
        reason: 'no reload frame: the hero never left the tree',
      );
      expectVelvetSnack(
        'Обкладинку оновлено',
        variant: VelvetSnackVariant.success,
      );
      // The local preview is released after a bounded precache.
      // fixed-wait-ok: crosses the 2 s precache bound (kAvatarPrecacheTimeout)
      // that holds the local preview — a TTL crossing, not a guess.
      await tester.pump(const Duration(seconds: 3));
      expect(cover(tester).previewFile, isNull);
      expect(find.byType(UploadProgressOverlay), findsNothing);
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('logo upload lands on the hero logo in place', (tester) async {
      await pump(tester, UserRole.salonOwner);
      await tester.tap(find.byKey(const Key('salon-logo-edit-badge')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('image-source-gallery')));
      await pumpUntil(tester, () => uploads.uploads.isNotEmpty);
      await tester.pump();
      expect(uploads.uploads.single, (_kSalonId, SalonImageSlot.logo));
      expect(heroLogo(tester).overlay, isA<UploadProgressOverlay>());
      uploads.result.complete(_kLogo);
      await pumpUntil(
        tester,
        () => find.byType(VelvetSnack).evaluate().isNotEmpty,
      );
      await pumpVelvetSnackIn(tester);
      expect(heroLogo(tester).imageUrl, _kLogo);
      expect(_manageBuilds, 1);
      expectVelvetSnack('Фото оновлено', variant: VelvetSnackVariant.success);
      // fixed-wait-ok: crosses the 2 s precache bound (kAvatarPrecacheTimeout)
      // that holds the local preview — a TTL crossing, not a guess.
      await tester.pump(const Duration(seconds: 3));
      expect(heroLogo(tester).overlay, isNull);
      await pumpPastVelvetSnack(tester);
    });

    for (final (String name, UploadFailure failure, String copy)
        in <(String, UploadFailure, String)>[
          (
            '403',
            const UploadForbiddenFailure(salonOwnerOnly: true),
            'Змінювати фото салону може лише власник',
          ),
          (
            '429',
            const UploadRateLimitedFailure(retryAfterSeconds: 30),
            'Забагато завантажень. Спробуйте за 30 с',
          ),
          (
            '409',
            const UploadConflictFailure(),
            'Не вдалося зберегти фото. Спробуйте ще раз',
          ),
          (
            '503',
            const UploadStorageUnavailableFailure(),
            'Завантаження фото тимчасово недоступне',
          ),
        ]) {
      testWidgets('a $name upload shows its copy and keeps the photo for '
          'retry; the salon is unchanged', (tester) async {
        await pump(tester, UserRole.salonOwner);
        await tester.tap(find.byKey(const Key('salon-cover-edit')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('image-source-gallery')));
        await pumpUntil(tester, () => uploads.uploads.isNotEmpty);
        uploads.result.completeError(failure);
        await pumpUntil(
          tester,
          () => find.byType(VelvetSnack).evaluate().isNotEmpty,
        );
        await pumpVelvetSnackIn(tester);
        expectVelvetSnack(copy, variant: VelvetSnackVariant.error);
        expect(find.byKey(const Key('upload-retry')), findsOneWidget);
        expect(cover(tester).imageUrl, isNull);
        expect(cover(tester).previewFile, isNotNull);
        await pumpPastVelvetSnack(tester);
      });
    }

    testWidgets('remove clears the cover in place with «Обкладинку видалено»', (
      tester,
    ) async {
      _seed = _salon.copyWith(coverImageUrl: _kCover);
      await pump(tester, UserRole.salonOwner);
      await tester.tap(find.byKey(const Key('salon-cover-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('image-source-remove')));
      await pumpUntil(tester, () => uploads.deletes.isNotEmpty);
      await pumpUntil(
        tester,
        () => find.byType(VelvetSnack).evaluate().isNotEmpty,
      );
      await pumpVelvetSnackIn(tester);
      expect(uploads.deletes.single, (_kSalonId, SalonImageSlot.cover));
      expect(cover(tester).imageUrl, isNull);
      expectVelvetSnack(
        'Обкладинку видалено',
        variant: VelvetSnackVariant.success,
      );
      expect(_manageBuilds, 1);
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('the logo badge clears the hero text column (360 dp, ×1.3)', (
      tester,
    ) async {
      _role = UserRole.salonOwner;
      await tester.pumpApp(
        const SalonManagementProfileScreen(salonId: _kSalonId),
        width: 360,
        height: 900,
        textScaleFactor: 1.3,
        overrides: <Object>[
          authProvider.overrideWith(_Auth.new),
          salonManagementProfileProvider.overrideWith(_Manage.new),
          mySalonsProvider.overrideWith(_MySalons.new),
          hasUnreadNotificationsProvider.overrideWithValue(false),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        ],
      );
      await tester.pumpAndSettle();
      expectBadgeClearsTextColumn(
        tester,
        editorKey: const Key('salon-logo-editor'),
        nameKey: const Key('salon-manage-name'),
        badgeKey: const Key('salon-logo-edit-badge'),
      );
    });
  });

  // Phase 369 QA — security LOW regression (EXPECTED RED until the
  // mobile-dev fix). `canEdit` is derived from the ROLE alone, so a
  // SALON_OWNER of salon A who opens `/salons/B/manage` gets B's logo /
  // cover edit controls (a) for the whole window before `mySalonsProvider`
  // resolves and (b) for as long as the screen stays mounted when B is not in
  // the resolved list (embedded in the Salon Shell, where this screen does not
  // bounce itself). The backend 403 is the real gate; the UI must not offer a
  // control the owner-only rule says this user cannot use. The positive
  // control is the 'owner' group above: same harness, B IS in the list, the
  // controls render.
  group('owner of ANOTHER salon — ownership window '
      '[369 security LOW]', () {
    Future<void> expectNoEditControls(WidgetTester tester) async {
      expect(find.byKey(const Key('salon-manage-hero-card')), findsOneWidget);
      expect(find.byKey(const Key('salon-logo-edit-badge')), findsNothing);
      expect(find.byKey(const Key('salon-cover-edit')), findsNothing);
      expect(find.byKey(const Key('salon-logo-editor')), findsNothing);
      expect(find.byKey(const Key('salon-cover-editor')), findsNothing);
      // …still renders B's photos read-only.
      expect(heroLogo(tester).imageUrl, _kLogo);
      expect(heroLogo(tester).editBadge, isNull);
      expect(cover(tester).imageUrl, _kCover);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('salon-manage-hero-card')),
          matching: find.byType(SalonLogo),
        ),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('image-source-gallery')), findsNothing);
    }

    testWidgets('while mySalonsProvider is still loading: no logo badge, no '
        'cover control', (tester) async {
      _seed = _salon.copyWith(avatarUrl: _kLogo, coverImageUrl: _kCover);
      await pump(tester, UserRole.salonOwner, mySalons: _MySalonsPending.new);
      await expectNoEditControls(tester);
    });

    testWidgets('salon B absent from the resolved list (embedded in the '
        'shell): no logo badge, no cover control', (tester) async {
      _seed = _salon.copyWith(avatarUrl: _kLogo, coverImageUrl: _kCover);
      await pump(
        tester,
        UserRole.salonOwner,
        mySalons: _MySalonsOther.new,
        embedded: true,
      );
      await expectNoEditControls(tester);
    });
  });

  // Phase 369 fix — the ownership gate is `settledValueOrNull`, the same
  // rule `patchImage` uses: a same-session refresh of `mySalonsProvider`
  // (`AsyncData` + `isLoading`) may no longer contain this salon, so the
  // editors are withheld until it settles.
  testWidgets('owner: mySalonsProvider refreshing (AsyncData + isLoading) '
      'hides the logo badge and the cover control', (tester) async {
    _seed = _salon.copyWith(avatarUrl: _kLogo, coverImageUrl: _kCover);
    await pump(
      tester,
      UserRole.salonOwner,
      mySalons: _MySalonsRefreshing.new,
      embedded: true,
    );
    // Positive control — settled AsyncData containing this salon unlocks.
    expect(find.byKey(const Key('salon-logo-edit-badge')), findsOneWidget);
    expect(find.byKey(const Key('salon-cover-edit')), findsOneWidget);

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(SalonManagementProfileScreen)),
    );
    container.invalidate(mySalonsProvider);
    await tester.pump();
    final AsyncValue<List<Salon>> refreshing = container.read(mySalonsProvider);
    expect(refreshing, isA<AsyncData<List<Salon>>>());
    expect(refreshing.isLoading, isTrue);

    expect(find.byKey(const Key('salon-manage-hero-card')), findsOneWidget);
    expect(find.byKey(const Key('salon-logo-edit-badge')), findsNothing);
    expect(find.byKey(const Key('salon-cover-edit')), findsNothing);
    expect(heroLogo(tester).editBadge, isNull);
    expect(cover(tester).imageUrl, _kCover);
  });

  group('admin (SALON_ADMIN)', () {
    testWidgets('sees NO logo badge, NO cover control, NO editor', (
      tester,
    ) async {
      _seed = _salon.copyWith(avatarUrl: _kLogo, coverImageUrl: _kCover);
      await pump(tester, UserRole.salonAdmin);
      expect(find.byKey(const Key('salon-logo-editor')), findsNothing);
      expect(find.byKey(const Key('salon-logo-edit-badge')), findsNothing);
      expect(find.byKey(const Key('avatar-edit-badge')), findsNothing);
      expect(find.byKey(const Key('salon-cover-edit')), findsNothing);
      expect(find.byKey(const Key('salon-cover-editor')), findsNothing);
      // …but still sees the salon's logo and cover.
      expect(heroLogo(tester).imageUrl, _kLogo);
      expect(heroLogo(tester).editBadge, isNull);
      expect(cover(tester).imageUrl, _kCover);
    });

    testWidgets('a tap on the logo does not open the source sheet', (
      tester,
    ) async {
      await pump(tester, UserRole.salonAdmin);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('salon-manage-hero-card')),
          matching: find.byType(SalonLogo),
        ),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('image-source-gallery')), findsNothing);
      expect(uploads.uploads, isEmpty);
    });
  });
}
