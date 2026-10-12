// Phase 405 (9.10) — the salon portfolio EDITOR on «Про салон»
// (salon_management_profile_screen.dart).
//
//   • D3 gating: owner of THIS salon → editable; owner while `mySalonsProvider`
//     is still settling → read-only; salon admin → editable; logo / cover stay
//     owner-only (regression).
//   • D8: the remove badge is on EVERY salon photo, for owner and admin alike
//     (no uploader branching).
//   • D4 add: add tile → source sheet → upload to `PortfolioOwner.salon(id)`
//     → pending tile with progress → the photo lands first; server 409 →
//     limit warning snack.
//   • D5 delete: badge → «Видалити фото?» → optimistic hide → gone; dismiss →
//     nothing; failure → the photo comes back + error snack; D7 403 →
//     forbidden snack + the list is re-read.
//   • CONTROLLER LIFETIME (403 perf INFO): an in-flight upload survives frames
//     AND a switch to another tab and back — the screen keeps the
//     auto-dispose write controller alive; a `ref.read`-only wiring would
//     dispose it and cancel the upload.

import 'dart:async';
import 'dart:io';

import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_notifier.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_owner.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
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
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_rail.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/media/pick/scripted_pick_gateway.dart';
import '../../../helpers/fake_media_cache.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

/// UA copy resolved from the ARB (no Cyrillic literals in finders).
final AppLocalizations _l10n = lookupAppLocalizations(const Locale('uk'));

const String _kSalonId = 'salon-1';
const PortfolioOwner _owner = PortfolioOwner.salon(_kSalonId);

const Salon _salon = Salon(id: _kSalonId, name: 'Салон «Вельвет»');

const PortfolioPhoto _byOwner = PortfolioPhoto(
  id: 'by-owner',
  url: 'https://media.test/salons/1/a.jpg',
);
const PortfolioPhoto _byAdmin = PortfolioPhoto(
  id: 'by-admin',
  url: 'https://media.test/salons/1/b.jpg',
);
const PortfolioPhoto _fresh = PortfolioPhoto(
  id: 'fresh',
  url: 'https://media.test/salons/1/fresh.jpg',
);

UserRole _role = UserRole.salonOwner;

/// The salon a SALON_ADMIN session is bound to (S2: an admin of ANOTHER
/// salon must get no editor affordances here).
String _adminSalonId = _kSalonId;

User _user(UserRole role) => User(
  id: role == UserRole.salonOwner ? 'owner-1' : 'admin-1',
  email: 'x@beautica.ua',
  role: role,
  firstName: 'Оксана',
  lastName: 'Швець',
  salonId: role == UserRole.salonAdmin ? _adminSalonId : null,
);

class _Auth extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: _user(_role), accessToken: 't');

  /// S2 — the session's bound salon changes mid-session (e.g. the admin was
  /// moved to another salon and the next `/users/me` read says so).
  void rebindAdminTo(String salonId) {
    _adminSalonId = salonId;
    state = AsyncData<AuthSession>(
      AuthSession.authenticated(user: _user(_role), accessToken: 't'),
    );
  }
}

class _Manage extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async =>
      (_salon, const <SalonStaffMember>[]);
}

class _MySalons extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[_salon];
}

class _MySalonsPending extends MySalons {
  @override
  Future<List<Salon>> build() => Completer<List<Salon>>().future;
}

/// The salon portfolio read: [photos], counting builds (a D7 re-read).
List<PortfolioPhoto> _stored = const <PortfolioPhoto>[_byOwner, _byAdmin];
int _portfolioBuilds = 0;

class _Portfolio extends PortfolioNotifier {
  @override
  Future<List<PortfolioPhoto>> build(PortfolioOwner owner) async {
    _portfolioBuilds++;
    return _stored;
  }
}

/// Scripted portfolio transport.
class _Uploads implements MediaUploadRepository {
  final List<PortfolioOwner> uploaded = <PortfolioOwner>[];
  final List<(PortfolioOwner, String)> deletes = <(PortfolioOwner, String)>[];
  Completer<PortfolioPhoto> result = Completer<PortfolioPhoto>();
  StreamController<double> progress = StreamController<double>.broadcast();
  int cancelCalls = 0;
  UploadFailure? deleteFailure;
  Completer<void>? holdDelete;

  @override
  UploadTask<PortfolioPhoto> uploadPortfolioPhoto(
    PortfolioOwner owner,
    File file,
  ) {
    uploaded.add(owner);
    final Completer<PortfolioPhoto> c = result = Completer<PortfolioPhoto>();
    progress = StreamController<double>.broadcast();
    return UploadTask<PortfolioPhoto>(
      progress: progress.stream,
      result: c.future,
      onCancel: () {
        cancelCalls++;
        if (!c.isCompleted) c.completeError(const UploadCancelledFailure());
      },
    );
  }

  @override
  Future<void> deletePortfolioPhoto(
    PortfolioOwner owner,
    String mediaId,
  ) async {
    deletes.add((owner, mediaId));
    final Completer<void>? hold = holdDelete;
    if (hold != null) await hold.future;
    final UploadFailure? f = deleteFailure;
    if (f != null) throw f;
  }

  @override
  Future<List<PortfolioPhoto>> getMasterPortfolio(String masterId) =>
      throw UnimplementedError();

  @override
  UploadTask<String> uploadAvatar(File file) => throw UnimplementedError();

  @override
  Future<void> deleteAvatar() => throw UnimplementedError();

  @override
  UploadTask<String> uploadSalonImage(
    String salonId,
    SalonImageSlot slot,
    File file,
  ) => throw UnimplementedError();

  @override
  Future<void> deleteSalonImage(String salonId, SalonImageSlot slot) =>
      throw UnimplementedError();
}

/// Interleaves real-async turns (the pick pipeline does real file I/O) with
/// frames until [cond] holds.
Future<void> _pumpUntil(WidgetTester tester, bool Function() cond) async {
  for (int i = 0; i < 300 && !cond(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    // fixed-wait-ok: one frame per real-async turn inside a bounded poll.
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(cond(), isTrue, reason: 'condition never held');
}

const Key _addTile = Key('portfolio-add-tile');
Key _deleteBadge(String id) => Key('portfolio-photo-delete-$id');
Key _photo(String id) => Key('portfolio-photo-$id');

/// Any pending-upload tile (or its discard badge) on the rail.
final Finder _anyPendingTile = find.byWidgetPredicate(
  (Widget w) => switch (w.key) {
    ValueKey<String>(:final String value) => value.startsWith(
      'portfolio-pending-',
    ),
    _ => false,
  },
);

/// Pumps until a VelvetSnack is up, then plays its entrance.
Future<void> _awaitSnack(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () => find.byType(VelvetSnack).evaluate().isNotEmpty,
  );
  await pumpVelvetSnackIn(tester);
}

/// Delete badge of photo [id] → the confirm dialog's confirm button.
Future<void> _confirmDelete(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(_deleteBadge(id)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('portfolio-delete-confirm')));
  await tester.pumpAndSettle();
}

/// Add tile → the source sheet → dismissed via its modal barrier.
Future<void> _openAndCloseSourceSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(_addTile));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('image-source-gallery')), findsOneWidget);
  await tester.tapAt(const Offset(8, 8)); // the modal barrier
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('image-source-gallery')), findsNothing);
}

/// Delete badge of photo [id] → the dialog → dismissed.
Future<void> _openAndDismissDeleteDialog(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(_deleteBadge(id)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('portfolio-delete-dismiss')));
  await tester.pumpAndSettle();
}

void main() {
  late Directory scratch;
  late Directory outside;
  late ScriptedPickGateway gw;
  late _Uploads uploads;

  setUp(() {
    _stored = const <PortfolioPhoto>[_byOwner, _byAdmin];
    _portfolioBuilds = 0;
    _adminSalonId = _kSalonId;
    scratch = Directory.systemTemp.createTempSync('salon_portfolio_scratch');
    outside = Directory.systemTemp.createTempSync('salon_portfolio_out');
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
  }) async {
    _role = role;
    await tester.pumpApp(
      const SalonManagementProfileScreen(salonId: _kSalonId),
      width: 360,
      height: 1200,
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
        portfolioProvider.overrideWith(_Portfolio.new),
      ],
    );
    await tester.pumpAndSettle();
  }

  group('D3 gating', () {
    testWidgets('owner of THIS salon: add tile, a remove badge on EVERY '
        'photo, «Портфоліо · 2/30»; logo / cover editors present', (
      tester,
    ) async {
      await pump(tester, UserRole.salonOwner);
      expect(find.byKey(_addTile), findsOneWidget);
      expect(find.byKey(_deleteBadge(_byOwner.id)), findsOneWidget);
      expect(find.byKey(_deleteBadge(_byAdmin.id)), findsOneWidget);
      expect(
        find.text(_l10n.portfolioLabelWithCount(2, kPortfolioMaxPhotos)),
        findsOneWidget,
      );
      expect(find.byKey(const Key('salon-logo-editor')), findsOneWidget);
      expect(find.byKey(const Key('salon-cover-edit')), findsOneWidget);
    });

    testWidgets('owner while mySalonsProvider is still settling: the 404 '
        'read-only rail — no add tile, no badges, plain label', (tester) async {
      _role = UserRole.salonOwner;
      await pump(tester, UserRole.salonOwner, mySalons: _MySalonsPending.new);
      expect(find.byType(PortfolioTile), findsNWidgets(2));
      expect(find.byKey(_addTile), findsNothing);
      expect(find.byKey(_deleteBadge(_byOwner.id)), findsNothing);
      expect(find.text(_l10n.masterPortfolioLabel), findsOneWidget);
    });

    testWidgets('salon admin: edits the portfolio (add tile + a badge on '
        'EVERY photo, incl. the owner\'s — D8) but logo / cover stay '
        'owner-only', (tester) async {
      await pump(tester, UserRole.salonAdmin);
      expect(find.byKey(_addTile), findsOneWidget);
      expect(find.byKey(_deleteBadge(_byOwner.id)), findsOneWidget);
      expect(find.byKey(_deleteBadge(_byAdmin.id)), findsOneWidget);
      expect(find.byKey(const Key('salon-logo-editor')), findsNothing);
      expect(find.byKey(const Key('salon-logo-edit-badge')), findsNothing);
      expect(find.byKey(const Key('salon-cover-edit')), findsNothing);
    });

    testWidgets('S2 — a salon admin bound to ANOTHER salon: the read-only '
        'rail — no add tile, no badges, plain label', (tester) async {
      _adminSalonId = 'salon-other';
      await pump(tester, UserRole.salonAdmin);
      expect(find.byType(PortfolioTile), findsNWidgets(2));
      expect(find.byKey(_addTile), findsNothing);
      expect(find.byKey(_deleteBadge(_byOwner.id)), findsNothing);
      expect(find.byKey(_deleteBadge(_byAdmin.id)), findsNothing);
      expect(find.text(_l10n.masterPortfolioLabel), findsOneWidget);
    });

    testWidgets('S2 — an admin re-bound to ANOTHER salon MID-SESSION loses '
        'the editor affordances at once (no re-navigation)', (tester) async {
      await pump(tester, UserRole.salonAdmin);
      expect(find.byKey(_addTile), findsOneWidget);
      expect(find.byKey(_deleteBadge(_byOwner.id)), findsOneWidget);

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(SalonManagementProfileScreen)),
      );
      (container.read(authProvider.notifier) as _Auth).rebindAdminTo(
        'salon-other',
      );
      await tester.pumpAndSettle();

      expect(find.byType(PortfolioTile), findsNWidgets(2));
      expect(find.byKey(_addTile), findsNothing);
      expect(find.byKey(_deleteBadge(_byOwner.id)), findsNothing);
      expect(find.byKey(_deleteBadge(_byAdmin.id)), findsNothing);
      expect(find.text(_l10n.masterPortfolioLabel), findsOneWidget);
    });

    testWidgets('at the cap (30 stored) there is no add tile', (tester) async {
      _stored = <PortfolioPhoto>[
        for (int i = 0; i < kPortfolioMaxPhotos; i++)
          PortfolioPhoto(id: 'p$i', url: 'https://media.test/$i.jpg'),
      ];
      await pump(tester, UserRole.salonOwner);
      expect(find.byKey(_addTile), findsNothing);
      expect(
        find.text(_l10n.portfolioLabelWithCount(30, kPortfolioMaxPhotos)),
        findsOneWidget,
      );
    });
  });

  group('D5 delete', () {
    testWidgets('admin deletes the OWNER\'s photo: confirm → request for '
        'THIS salon → gone + «Фото видалено»', (tester) async {
      await pump(tester, UserRole.salonAdmin);
      await tester.tap(find.byKey(_deleteBadge(_byOwner.id)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('portfolio-delete-dialog')), findsOneWidget);
      expect(find.text(_l10n.portfolioDeleteDialogTitle), findsOneWidget);

      await tester.tap(find.byKey(const Key('portfolio-delete-confirm')));
      await tester.pumpAndSettle();
      expect(uploads.deletes, <(PortfolioOwner, String)>[
        (_owner, _byOwner.id),
      ]);
      expect(find.byKey(_photo(_byOwner.id)), findsNothing);
      expect(find.byKey(_photo(_byAdmin.id)), findsOneWidget);
      expectVelvetSnack(
        _l10n.portfolioPhotoDeleted,
        variant: VelvetSnackVariant.success,
      );
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('perf (cycle 2) — after a delete, pushing / popping a sheet '
        'and a dialog above the rail does NOT rebuild it (no route-status '
        'dependency registered by the result sink)', (tester) async {
      await pump(tester, UserRole.salonOwner);
      // The rail state builds a fresh PortfolioRail on every build: the SAME
      // instance before and after means the rail state never rebuilt.
      Widget rail() => tester.widget(find.byType(PortfolioRail));

      // A completed delete runs the result sink (snack + any re-read).
      await _confirmDelete(tester, _byAdmin.id);
      await pumpPastVelvetSnack(tester);

      final Widget before = rail();
      await _openAndCloseSourceSheet(tester);
      expect(rail(), same(before), reason: 'sheet push / pop rebuilt the rail');
      await _openAndDismissDeleteDialog(tester, _byOwner.id);
      expect(
        rail(),
        same(before),
        reason: 'dialog push / pop rebuilt the rail',
      );
    });

    testWidgets('owner deletes the ADMIN\'s photo (no uploader gating)', (
      tester,
    ) async {
      await pump(tester, UserRole.salonOwner);
      await tester.tap(find.byKey(_deleteBadge(_byAdmin.id)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('portfolio-delete-confirm')));
      await tester.pumpAndSettle();
      expect(uploads.deletes.single, (_owner, _byAdmin.id));
      expect(find.byKey(_photo(_byAdmin.id)), findsNothing);
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('backing out of the dialog deletes nothing', (tester) async {
      await pump(tester, UserRole.salonOwner);
      await tester.tap(find.byKey(_deleteBadge(_byOwner.id)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('portfolio-delete-dismiss')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('portfolio-delete-dialog')), findsNothing);
      expect(uploads.deletes, isEmpty);
      expect(find.byKey(_photo(_byOwner.id)), findsOneWidget);
    });

    testWidgets('optimistic: the photo hides while the delete is in flight; '
        'a failure brings it back with «Не вдалося видалити фото»', (
      tester,
    ) async {
      final Completer<void> hold = Completer<void>();
      uploads
        ..holdDelete = hold
        ..deleteFailure = const UploadNetworkFailure();
      await pump(tester, UserRole.salonOwner);
      await tester.tap(find.byKey(_deleteBadge(_byOwner.id)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('portfolio-delete-confirm')));
      await tester.pumpAndSettle();
      expect(uploads.deletes, hasLength(1));
      expect(find.byKey(_photo(_byOwner.id)), findsNothing, reason: 'hidden');

      hold.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(_photo(_byOwner.id)), findsOneWidget);
      expectVelvetSnack(
        _l10n.portfolioDeleteFailed,
        variant: VelvetSnackVariant.error,
      );
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('Q1 (delete) — a delete that FAILS while the rail is '
        'unmounted (tab switch) still shows «Не вдалося видалити фото», and '
        'the photo is back on return', (tester) async {
      final Completer<void> hold = Completer<void>();
      uploads
        ..holdDelete = hold
        ..deleteFailure = const UploadNetworkFailure();
      await pump(tester, UserRole.salonOwner);
      await tester.tap(find.byKey(_deleteBadge(_byOwner.id)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('portfolio-delete-confirm')));
      await tester.pumpAndSettle();
      expect(uploads.deletes, hasLength(1));

      await tester.tap(find.byKey(const Key('salon-tab-1')));
      await tester.pumpAndSettle();
      expect(find.byType(PortfolioRail), findsNothing);
      hold.complete();
      await tester.pumpAndSettle();
      expect(find.byType(PortfolioRail), findsNothing, reason: 'still away');
      expectVelvetSnack(
        _l10n.portfolioDeleteFailed,
        variant: VelvetSnackVariant.error,
      );

      await tester.tap(find.byKey(const Key('salon-tab-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(_photo(_byOwner.id)), findsOneWidget);
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('D7 — a 403 (role changed mid-session): forbidden snack and '
        'the portfolio is re-read from the server', (tester) async {
      uploads.deleteFailure = const UploadForbiddenFailure();
      await pump(tester, UserRole.salonAdmin);
      final int buildsBefore = _portfolioBuilds;
      await tester.tap(find.byKey(_deleteBadge(_byOwner.id)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('portfolio-delete-confirm')));
      await tester.pumpAndSettle();
      expectVelvetSnack(
        _l10n.uploadErrorForbidden,
        variant: VelvetSnackVariant.error,
      );
      expect(_portfolioBuilds, greaterThan(buildsBefore));
      expect(find.byKey(_photo(_byOwner.id)), findsOneWidget);
      await pumpPastVelvetSnack(tester);
    });
  });

  group('D4 add', () {
    Future<void> startUpload(WidgetTester tester) async {
      await tester.tap(find.byKey(_addTile));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('image-source-gallery')), findsOneWidget);
      expect(find.byKey(const Key('image-source-remove')), findsNothing);
      await tester.tap(find.byKey(const Key('image-source-gallery')));
      await _pumpUntil(tester, () => uploads.uploaded.isNotEmpty);
      await tester.pump();
    }

    testWidgets('admin: add tile → sheet → upload to THIS salon → progress '
        'tile (add tile inert) → the photo lands FIRST + «Фото додано»', (
      tester,
    ) async {
      await pump(tester, UserRole.salonAdmin);
      await startUpload(tester);
      expect(uploads.uploaded.single, _owner);
      expect(find.byType(UploadProgressOverlay), findsOneWidget);
      expect(
        find.text(_l10n.portfolioLabelWithCount(3, kPortfolioMaxPhotos)),
        findsOneWidget,
      );

      uploads.result.complete(_fresh);
      await _pumpUntil(
        tester,
        () => find.byType(VelvetSnack).evaluate().isNotEmpty,
      );
      await pumpVelvetSnackIn(tester);
      expect(find.byType(UploadProgressOverlay), findsNothing);
      expect(find.byKey(_photo(_fresh.id)), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(_photo(_fresh.id))).dx,
        lessThan(tester.getTopLeft(find.byKey(_photo(_byOwner.id))).dx),
      );
      expectVelvetSnack(
        _l10n.portfolioPhotoAdded,
        variant: VelvetSnackVariant.success,
      );
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('server 409 limit → the limit warning snack', (tester) async {
      await pump(tester, UserRole.salonOwner);
      await startUpload(tester);
      uploads.result.completeError(const PortfolioLimitReachedFailure());
      await _pumpUntil(
        tester,
        () => find.byType(VelvetSnack).evaluate().isNotEmpty,
      );
      await pumpVelvetSnackIn(tester);
      expectVelvetSnack(
        _l10n.uploadErrorPortfolioLimit(kPortfolioMaxPhotos),
        variant: VelvetSnackVariant.warning,
      );
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('CONTROLLER LIFETIME — an in-flight upload survives frames '
        'and a tab switch away and back; it is never cancelled and lands', (
      tester,
    ) async {
      await pump(tester, UserRole.salonOwner);
      await startUpload(tester);
      uploads.progress.add(0.5);
      for (int i = 0; i < 10; i++) {
        // fixed-wait-ok: frames DURING the upload are the point of the test.
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(uploads.cancelCalls, 0);

      // «Команда» unmounts the «Про салон» rail (the only rail watcher).
      await tester.tap(find.byKey(const Key('salon-tab-1')));
      await tester.pumpAndSettle();
      expect(find.byType(PortfolioRail), findsNothing);
      for (int i = 0; i < 10; i++) {
        // fixed-wait-ok: frames while the rail is unmounted.
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(uploads.cancelCalls, 0, reason: 'the screen keeps it alive');

      await tester.tap(find.byKey(const Key('salon-tab-0')));
      await tester.pumpAndSettle();
      expect(find.byType(UploadProgressOverlay), findsOneWidget);
      uploads.result.complete(_fresh);
      await _pumpUntil(
        tester,
        () => find.byKey(_photo(_fresh.id)).evaluate().isNotEmpty,
      );
      expect(uploads.cancelCalls, 0);
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('Q1 — an upload that lands while the rail is UNMOUNTED (tab '
        'switch) still shows «Фото додано»', (tester) async {
      await pump(tester, UserRole.salonOwner);
      await startUpload(tester);
      await tester.tap(find.byKey(const Key('salon-tab-1')));
      await tester.pumpAndSettle();
      expect(find.byType(PortfolioRail), findsNothing);

      uploads.result.complete(_fresh);
      await _pumpUntil(
        tester,
        () => find.byType(VelvetSnack).evaluate().isNotEmpty,
      );
      await pumpVelvetSnackIn(tester);
      expect(find.byType(PortfolioRail), findsNothing, reason: 'still away');
      expectVelvetSnack(
        _l10n.portfolioPhotoAdded,
        variant: VelvetSnackVariant.success,
      );
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('Q4 / S3 — a 403 on add (role changed mid-session): the '
        'forbidden snack, the portfolio is re-read, and the failed tile is '
        'DISCARDED (its retry could only 403 again)', (tester) async {
      await pump(tester, UserRole.salonAdmin);
      final int buildsBefore = _portfolioBuilds;
      await startUpload(tester);
      expect(find.byType(UploadProgressOverlay), findsOneWidget);

      uploads.result.completeError(const UploadForbiddenFailure());
      await _awaitSnack(tester);
      expectVelvetSnack(
        _l10n.uploadErrorForbidden,
        variant: VelvetSnackVariant.error,
      );
      expect(_portfolioBuilds, greaterThan(buildsBefore));
      expect(find.byType(UploadProgressOverlay), findsNothing);
      expect(find.byType(UploadFailedOverlay), findsNothing);
      expect(
        _anyPendingTile,
        findsNothing,
        reason: 'the failed tile is discarded',
      );
      expect(
        find.text(_l10n.portfolioLabelWithCount(2, kPortfolioMaxPhotos)),
        findsOneWidget,
      );
      await pumpPastVelvetSnack(tester);
    });
  });
}
