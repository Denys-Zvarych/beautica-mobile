// Phase 367 (9.6) — the «Особисті дані» avatar on [ClientPersonalInfoEditScreen]
// is LIVE for every role that reuses it (CLIENT, SALON_ADMIN, SALON_OWNER):
// the camera badge opens the 071 source sheet and hands the choice to the
// shared own-avatar controller. The old «Незабаром» snack is gone (Scope
// update 2 — no dead badges).

import 'dart:async';

import 'package:beautica_mobile/core/media/pick/crop_labels.dart';
import 'package:beautica_mobile/core/media/pick/image_source_sheet.dart';
import 'package:beautica_mobile/core/media/upload/avatar_upload_controller.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/home/presentation/client_personal_info_edit_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

const String _url = 'https://media.test/avatars/u1/1.jpg';

User _user(UserRole role, String? avatarUrl) => User(
  id: 'user-1',
  email: 'me@beautica.ua',
  role: role,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  avatarUrl: avatarUrl,
);

class _Auth extends AuthNotifier {
  _Auth(this._u);
  final User _u;
  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: _u, accessToken: 't');
}

class _EditProfile extends ClientEditProfile {
  _EditProfile(this._u);
  final User _u;
  @override
  Future<User> build() async => _u;
}

class _FakeController extends AvatarUploadController {
  final List<ImageSourceChoice> changes = <ImageSourceChoice>[];
  CropLabels? lastLabels;
  int removes = 0;
  Completer<void>? gate;

  @override
  AvatarUploadState build() => const AvatarUploadState.idle();

  @override
  Future<AvatarChangeResult> recoverLost({
    CropLabels? labels,
    AvatarPrecache? precache,
  }) async => const AvatarChangeCancelled();

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
    state = const AvatarUploadState.idle();
    return const AvatarChangeSucceeded();
  }

  @override
  Future<AvatarChangeResult> remove() async {
    removes++;
    return const AvatarChangeSucceeded();
  }
}

GoRouter _router() => GoRouter(
  initialLocation: RouteNames.clientEditPersonal,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.clientEditPersonal,
      pageBuilder: (_, _) =>
          const NoTransitionPage<void>(child: ClientPersonalInfoEditScreen()),
    ),
  ],
);

NeumorphicAvatarEditor _editor(WidgetTester t) =>
    t.widget<NeumorphicAvatarEditor>(find.byType(NeumorphicAvatarEditor));

void main() {
  late _FakeController fake;

  Future<void> pump(
    WidgetTester tester,
    UserRole role, {
    String? avatarUrl,
  }) async {
    fake = _FakeController();
    final User u = _user(role, avatarUrl);
    await tester.pumpRoutedApp(
      _router(),
      overrides: <Object>[
        authProvider.overrideWith(() => _Auth(u)),
        clientEditProfileProvider.overrideWith(() => _EditProfile(u)),
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

  for (final UserRole role in <UserRole>[
    UserRole.client,
    UserRole.salonAdmin,
    UserRole.salonOwner,
  ]) {
    group(role.name, () {
      testWidgets('no photo: monogram editor; badge opens the source sheet '
          'without a remove row; NO «Незабаром» snack', (tester) async {
        await pump(tester, role);
        expect(_editor(tester).state, AvatarEditState.pristine);
        expect(_editor(tester).initials, 'ОК');

        await tapBadge(tester);

        expect(find.byKey(const Key('image-source-camera')), findsOneWidget);
        expect(find.byKey(const Key('image-source-remove')), findsNothing);
        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(ClientPersonalInfoEditScreen)),
        );
        expect(find.text(l10n.snackbarAvatarSoon), findsNothing);
      });

      testWidgets('session photo: loaded editor + remove row', (tester) async {
        await pump(tester, role, avatarUrl: _url);
        expect(_editor(tester).state, AvatarEditState.loaded);
        expect(_editor(tester).imageUrl, _url);

        await tapBadge(tester);
        expect(find.byKey(const Key('image-source-remove')), findsOneWidget);
      });

      testWidgets('gallery -> controller.change with localised crop labels; '
          'progress shows; success snack', (tester) async {
        await pump(tester, role);
        fake.gate = Completer<void>();

        await tapBadge(tester);
        await tester.tap(find.byKey(const Key('image-source-gallery')));
        await tester.pump();
        await tester.pump();

        expect(fake.changes, <ImageSourceChoice>[ImageSourceChoice.gallery]);
        expect(fake.lastLabels, isNotNull);
        expect(_editor(tester).state, AvatarEditState.picking);
        expect(_editor(tester).progress, 0.4);

        fake.gate!.complete();
        await pumpVelvetSnackIn(tester);
        expectVelvetSnack('Фото оновлено', variant: VelvetSnackVariant.success);
        await pumpPastVelvetSnack(tester);
      });

      testWidgets('remove -> controller.remove', (tester) async {
        await pump(tester, role, avatarUrl: _url);
        await tapBadge(tester);
        await tester.tap(find.byKey(const Key('image-source-remove')));
        await pumpVelvetSnackIn(tester);

        expect(fake.removes, 1);
        expectVelvetSnack('Фото видалено', variant: VelvetSnackVariant.success);
        await pumpPastVelvetSnack(tester);
      });
    });
  }

  // Phase 367 audit (perf L1): the session-avatar watch lives INSIDE the
  // editor's Consumer, so an upload/remove (`patchAvatarUrl`) rebuilds the
  // avatar only — the form above/below it is NOT rebuilt. The form field's
  // widget instance is created in the screen's build(); it stays identical
  // only when that build did not run again.
  testWidgets('an avatar patch rebuilds the editor only, not the form', (
    tester,
  ) async {
    await pump(tester, UserRole.client, avatarUrl: _url);
    expect(_editor(tester).imageUrl, _url);
    final Widget formFieldBefore = tester.widget(
      find.byKey(const Key('field-firstName')),
    );

    ProviderScope.containerOf(
      tester.element(find.byType(ClientPersonalInfoEditScreen)),
    ).read(authProvider.notifier).patchAvatarUrl(null);
    await tester.pump();

    expect(_editor(tester).imageUrl, isNull, reason: 'the editor follows');
    expect(_editor(tester).state, AvatarEditState.pristine);
    expect(
      identical(
        tester.widget(find.byKey(const Key('field-firstName'))),
        formFieldBefore,
      ),
      isTrue,
      reason: 'the screen build() must not re-run for an avatar patch',
    );
  });
}
