// Phase 073 — avatar wiring on PersonalInfoEditScreen.
//
// The controller is replaced by a scripted subclass (its own behaviour is
// covered by avatar_upload_controller_test.dart), so this file pins only what
// the SCREEN owns: sheet → controller hand-off, state → editor mapping, snacks.

import 'dart:async';
import 'dart:io';

import 'package:beautica_mobile/core/media/pick/crop_labels.dart';
import 'package:beautica_mobile/core/media/pick/image_source_sheet.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/application/avatar_upload_controller.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/personal_info_edit_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

class _MockMasterRepository extends Mock implements MasterRepository {}

const _user = User(
  id: 'user-1',
  email: 'test@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Олена',
  lastName: 'Ковальчук',
);

Master _master({String? avatarUrl}) => Master(
  id: 'user-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  avgRating: 4.8,
  reviewCount: 10,
  type: MasterType.independentMaster,
  avatarUrl: avatarUrl,
);

class _StubProfile extends MasterProfile {
  _StubProfile(this._m);
  final Master _m;
  @override
  Future<Master> build() => Future<Master>.value(_m);
}

class _StubAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _user, accessToken: 't');
}

/// Scripted controller: records calls, holds the "upload" open on [gate].
class _FakeController extends AvatarUploadController {
  final List<ImageSourceChoice> changes = <ImageSourceChoice>[];
  CropLabels? lastLabels;
  int removes = 0;
  AvatarChangeResult outcome = const AvatarChangeCancelled();
  Completer<void>? gate;

  @override
  AvatarUploadState build() => const AvatarUploadState.idle();

  @override
  Future<AvatarChangeResult> recoverLost({
    CropLabels? labels,
    AvatarPrecache? precache,
  }) async => const AvatarChangeCancelled();

  int retries = 0;

  @override
  Future<AvatarChangeResult> retry({AvatarPrecache? precache}) async {
    retries++;
    return const AvatarChangeCancelled();
  }

  @override
  Future<AvatarChangeResult> change(
    ImageSourceChoice source, {
    CropLabels? labels,
    AvatarPrecache? precache,
  }) async {
    changes.add(source);
    lastLabels = labels;
    state = const AvatarUploadState.uploading(progress: 0.4);
    await gate?.future;
    final AvatarChangeResult r = outcome;
    // Mirrors the real controller: a failure KEEPS the picked photo.
    state = r is AvatarChangeFailed
        ? AvatarUploadState.failed(
            previewFile: File('/tmp/media_upload/kept.jpg'),
            failure: r.failure,
          )
        : const AvatarUploadState.idle();
    return r;
  }

  @override
  Future<AvatarChangeResult> remove() async {
    removes++;
    state = const AvatarUploadState.removing();
    await gate?.future;
    state = const AvatarUploadState.idle();
    return outcome;
  }
}

GoRouter _router() => GoRouter(
  initialLocation: RouteNames.masterEditPersonal,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.masterEditPersonal,
      pageBuilder: (_, _) =>
          const NoTransitionPage<void>(child: PersonalInfoEditScreen()),
    ),
  ],
);

NeumorphicAvatarEditor _editor(WidgetTester t) =>
    t.widget<NeumorphicAvatarEditor>(find.byType(NeumorphicAvatarEditor));

void main() {
  late _FakeController fake;

  Future<void> pumpScreen(WidgetTester tester, {String? avatarUrl}) async {
    fake = _FakeController();
    await tester.pumpRoutedApp(
      _router(),
      overrides: <Object>[
        authProvider.overrideWith(_StubAuth.new),
        masterProfileProvider.overrideWith(
          () => _StubProfile(_master(avatarUrl: avatarUrl)),
        ),
        masterRepositoryProvider.overrideWithValue(_MockMasterRepository()),
        avatarUploadControllerProvider.overrideWith(() => fake),
      ],
    );
    // Let the reveal animation finish so the badge is hit-testable.
    await tester.pumpAndSettle();
  }

  Future<void> tapBadge(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('avatar-edit-badge')));
    await tester.pumpUntilFound(find.byKey(const Key('image-source-gallery')));
    await tester.pumpAndSettle(); // sheet slide-in
  }

  Future<void> choose(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    // Sheet pop + the controller's first state write.
    await tester.pump();
    await tester.pump();
  }

  const String url = 'https://media.test/avatars/u1/1.jpg';

  testWidgets('tap opens the source sheet; no remove row without an avatar', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(_editor(tester).state, AvatarEditState.pristine);

    await tapBadge(tester);

    expect(find.byKey(const Key('image-source-gallery')), findsOneWidget);
    expect(find.byKey(const Key('image-source-camera')), findsOneWidget);
    expect(find.byKey(const Key('image-source-remove')), findsNothing);
  });

  testWidgets('remove row appears when an avatar exists; editor is loaded', (
    tester,
  ) async {
    await pumpScreen(tester, avatarUrl: url);
    expect(_editor(tester).state, AvatarEditState.loaded);
    expect(_editor(tester).imageUrl, url);

    await tapBadge(tester);

    expect(find.byKey(const Key('image-source-remove')), findsOneWidget);
  });

  testWidgets('gallery choice -> controller.change with localised crop labels; '
      'progress maps to picking + value; success snack', (tester) async {
    await pumpScreen(tester);
    fake
      ..gate = Completer<void>()
      ..outcome = const AvatarChangeSucceeded();

    await tapBadge(tester);
    await choose(tester, 'image-source-gallery');

    expect(fake.changes, <ImageSourceChoice>[ImageSourceChoice.gallery]);
    expect(
      fake.lastLabels?.title,
      AppLocalizations.of(
        tester.element(find.byType(PersonalInfoEditScreen)),
      ).cropTitle,
    );
    expect(_editor(tester).state, AvatarEditState.picking);
    expect(_editor(tester).progress, 0.4);

    await tester.pumpAndSettle(); // sheet slide-out
    // A tap while busy is ignored (no second sheet).
    await tester.tap(find.byKey(const Key('avatar-edit-badge')));
    await tester.pump();
    expect(find.byKey(const Key('image-source-gallery')), findsNothing);

    fake.gate!.complete();
    await pumpVelvetSnackIn(tester);

    expectVelvetSnack('Фото оновлено', variant: VelvetSnackVariant.success);
    expect(_editor(tester).state, AvatarEditState.pristine);
    await pumpPastVelvetSnack(tester);
  });

  testWidgets('remove choice -> controller.remove, picking w/o progress, '
      'removed snack', (tester) async {
    await pumpScreen(tester, avatarUrl: url);
    fake
      ..gate = Completer<void>()
      ..outcome = const AvatarChangeSucceeded();

    await tapBadge(tester);
    await choose(tester, 'image-source-remove');

    expect(fake.removes, 1);
    expect(fake.changes, isEmpty);
    expect(_editor(tester).state, AvatarEditState.picking);
    expect(_editor(tester).progress, isNull);

    fake.gate!.complete();
    await pumpVelvetSnackIn(tester);
    expectVelvetSnack('Фото видалено', variant: VelvetSnackVariant.success);
    await pumpPastVelvetSnack(tester);
  });

  testWidgets('storage-unavailable failure -> error snack + the picked photo '
      'kept under the retry veil; retry re-sends it WITHOUT the picker', (
    tester,
  ) async {
    await pumpScreen(tester);
    fake.outcome = const AvatarChangeFailed(UploadStorageUnavailableFailure());

    await tapBadge(tester);
    await choose(tester, 'image-source-gallery');
    await pumpVelvetSnackIn(tester);

    expectVelvetSnack(
      'Завантаження фото тимчасово недоступне',
      variant: VelvetSnackVariant.error,
    );
    expect(_editor(tester).uploadFailed, isTrue);
    expect(_editor(tester).state, AvatarEditState.loaded);
    expect(_editor(tester).previewFile?.path, '/tmp/media_upload/kept.jpg');
    await pumpPastVelvetSnack(tester);

    await tester.tap(find.byKey(const Key('upload-retry')));
    await tester.pump();

    expect(fake.retries, 1);
    expect(fake.changes, hasLength(1), reason: 'retry must not re-pick');
    expect(find.byKey(const Key('image-source-gallery')), findsNothing);
  });

  for (final (String, UploadFailure) c in <(String, UploadFailure)>[
    ('too large', const UploadTooLargeFailure()),
    ('network', const UploadNetworkFailure()),
    ('unsupported format', const UploadUnsupportedFormatFailure()),
    ('unauthorized', const UploadUnauthorizedFailure()),
  ]) {
    testWidgets('${c.$1} failure shows its own localised error snack', (
      tester,
    ) async {
      await pumpScreen(tester);
      fake.outcome = AvatarChangeFailed(c.$2);
      await tapBadge(tester);
      await choose(tester, 'image-source-camera');
      await pumpVelvetSnackIn(tester);

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(PersonalInfoEditScreen)),
      );
      expectVelvetSnack(c.$2.message(l10n), variant: VelvetSnackVariant.error);
      await pumpPastVelvetSnack(tester);
    });
  }

  testWidgets('cancel shows no snack and no veil', (tester) async {
    await pumpScreen(tester);
    fake.outcome = const AvatarChangeCancelled();

    await tapBadge(tester);
    await choose(tester, 'image-source-gallery');
    await tester.pumpAndSettle();

    expect(find.byType(VelvetSnack), findsNothing);
    expect(_editor(tester).uploadFailed, isFalse);
  });

  testWidgets('dismissing the sheet does nothing', (tester) async {
    await pumpScreen(tester);
    await tapBadge(tester);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(fake.changes, isEmpty);
    expect(find.byType(VelvetSnack), findsNothing);
  });

  testWidgets('the «Незабаром…» placeholder is gone', (tester) async {
    await pumpScreen(tester);
    await tapBadge(tester);
    await choose(tester, 'image-source-gallery');
    await tester.pumpAndSettle();
    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(PersonalInfoEditScreen)),
    );
    expect(find.text(l10n.snackbarAvatarSoon), findsNothing);
  });
}
