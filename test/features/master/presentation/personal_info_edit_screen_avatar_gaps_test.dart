// Phase 073 QA — screen gaps: failed REMOVE, busy-tap matrix, Ukrainian crop labels.
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
    await tester.pumpAndSettle();
  }

  Future<void> tapBadge(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('avatar-edit-badge')));
    await tester.pumpUntilFound(find.byKey(const Key('image-source-gallery')));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
    await tester.pump();
  }

  const String url = 'https://media.test/avatars/u1/1.jpg';

  testWidgets('failed REMOVE -> error snack, no retry veil, avatar kept', (
    tester,
  ) async {
    await pumpScreen(tester, avatarUrl: url);
    fake.outcome = const AvatarChangeFailed(UploadNetworkFailure());

    await tapBadge(tester);
    await choose(tester, 'image-source-remove');
    await pumpVelvetSnackIn(tester);

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(PersonalInfoEditScreen)),
    );
    expectVelvetSnack(
      const UploadNetworkFailure().message(l10n),
      variant: VelvetSnackVariant.error,
    );
    expect(fake.removes, 1);
    expect(_editor(tester).uploadFailed, isFalse);
    expect(_editor(tester).state, AvatarEditState.loaded);
    expect(_editor(tester).imageUrl, url);
    await pumpPastVelvetSnack(tester);
  });

  testWidgets('badge tap while REMOVING is ignored: no sheet, no 2nd call', (
    tester,
  ) async {
    await pumpScreen(tester, avatarUrl: url);
    fake
      ..gate = Completer<void>()
      ..outcome = const AvatarChangeSucceeded();
    await tapBadge(tester);
    await choose(tester, 'image-source-remove');
    // Sheet slide-out; the busy editor animates forever, so no pumpAndSettle.
    await tester.pump(
      const Duration(milliseconds: 500),
    ); // fixed-wait-ok: sheet slide-out; the busy editor animates forever
    expect(_editor(tester).state, AvatarEditState.picking);

    await tester.tap(find.byKey(const Key('avatar-edit-badge')));
    await tester.pump();

    expect(find.byKey(const Key('image-source-remove')), findsNothing);
    expect(fake.removes, 1);
    expect(fake.changes, isEmpty);

    fake.gate!.complete();
    await pumpVelvetSnackIn(tester);
    await pumpPastVelvetSnack(tester);
  });

  testWidgets('camera choice hands the Ukrainian crop labels (all three) to '
      'the controller', (tester) async {
    await pumpScreen(tester);
    await tapBadge(tester);
    await choose(tester, 'image-source-camera');
    await tester.pumpAndSettle();

    expect(fake.changes, <ImageSourceChoice>[ImageSourceChoice.camera]);
    final CropLabels? labels = fake.lastLabels;
    expect(labels, isNotNull);
    expect(labels!.title, 'Обрізати фото');
    expect(labels.doneButton, 'Готово');
    expect(labels.cancelButton, 'Скасувати');
  });

  testWidgets('a cancelled pick leaves the saved avatar untouched', (
    tester,
  ) async {
    await pumpScreen(tester, avatarUrl: url);
    fake.outcome = const AvatarChangeCancelled();

    await tapBadge(tester);
    await choose(tester, 'image-source-gallery');
    await tester.pumpAndSettle();

    expect(find.byType(VelvetSnack), findsNothing);
    expect(_editor(tester).imageUrl, url);
    expect(_editor(tester).state, AvatarEditState.loaded);
    expect(_editor(tester).uploadFailed, isFalse);
  });
}
