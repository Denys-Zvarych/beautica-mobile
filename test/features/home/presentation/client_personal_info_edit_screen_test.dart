// Widget tests for ClientPersonalInfoEditScreen (firstName + lastName only).
//
// 1:1 client transcription of the master personal-info screen with the bio field
// REMOVED. Coverage:
//   • NO bio field is rendered (assert absence of field-bio).
//   • firstName / lastName pre-populate from the cached profile.
//   • Save is disabled when pristine, enabled when dirty.
//   • Save sends a ClientProfileUpdate carrying ONLY firstName + lastName (the
//     name slice) and NOT touching location.
//
// Finders use widget Keys (M2). Layer: Widget.

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/home/data/client_profile_repository.dart';
import 'package:beautica_mobile/features/home/domain/client_profile_update.dart';
import 'package:beautica_mobile/features/home/presentation/client_personal_info_edit_screen.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/section_scaffold.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

class _MockClientProfileRepository extends Mock
    implements ClientProfileRepository {}

const _stubUser = User(
  id: 'user-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  phoneNumber: '+380 50 123 45 67',
);

class _StubClientEditProfile extends ClientEditProfile {
  @override
  Future<User> build() => Future<User>.value(_stubUser);
}

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: _stubUser,
    accessToken: 'test-token',
  );
}

GoRouter _buildRouter() => GoRouter(
  initialLocation: RouteNames.clientEditPersonal,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.clientEditPersonal,
      pageBuilder: (_, _) =>
          const NoTransitionPage<void>(child: ClientPersonalInfoEditScreen()),
    ),
    GoRoute(
      path: RouteNames.clientHome,
      pageBuilder: (_, _) => const NoTransitionPage<void>(
        child: Scaffold(body: SizedBox(key: Key('stub-home'))),
      ),
    ),
  ],
);

List<Object> _overrides(_MockClientProfileRepository repo) => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  clientEditProfileProvider.overrideWith(_StubClientEditProfile.new),
  clientProfileRepositoryProvider.overrideWithValue(repo),
];

Finder _field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

void main() {
  late _MockClientProfileRepository repo;

  setUpAll(() {
    registerFallbackValue(const ClientProfileUpdate());
  });

  setUp(() {
    repo = _MockClientProfileRepository();
  });

  testWidgets('does NOT render a bio field', (tester) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('field-firstName')), findsOneWidget);
    expect(find.byKey(const Key('field-lastName')), findsOneWidget);
    expect(
      find.byKey(const Key('field-bio')),
      findsNothing,
      reason: 'clients have no bio — the bio field must be absent',
    );
  });

  testWidgets('pre-populates firstName + lastName from the cached profile', (
    tester,
  ) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<TextField>(_field('field-firstName')).controller?.text,
      'Олена',
    );
    expect(
      tester.widget<TextField>(_field('field-lastName')).controller?.text,
      'Ковальчук',
    );
  });

  testWidgets('Save is disabled when pristine and enables when dirty', (
    tester,
  ) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    expect(
      tester
          .widget<NeumorphicButton>(find.byKey(const Key('btn-save-personal')))
          .onPressed,
      isNull,
    );

    await tester.enterText(_field('field-firstName'), 'Оля');
    await tester.pump();

    expect(
      tester
          .widget<NeumorphicButton>(find.byKey(const Key('btn-save-personal')))
          .onPressed,
      isNotNull,
    );
  });

  // ── PERF (P2): typing must NOT re-run the screen-level build ───────────────
  //
  // The dirty-state gating Save is driven by a ValueNotifier<bool> +
  // ValueListenableBuilder around the footer, NOT setState(() {}) on the whole
  // screen State. A keystroke must therefore leave the SectionScaffold chrome
  // (app-bar / back-button / footer + reveal-animation wrappers) at the same
  // widget object identity. Under the OLD setState-per-keystroke code build()
  // re-ran on every character and produced a brand-new SectionScaffold; this
  // identity check fails on that old behaviour and passes on the ValueNotifier
  // fix. (The avatar initials follow input via their own listenable and the
  // typed field rebuilds via FormState — neither recreates SectionScaffold.)
  testWidgets('typing a valid name does NOT re-run the screen build '
      '(SectionScaffold chrome preserved) yet still enables Save', (
    tester,
  ) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pumpAndSettle();

    SectionScaffold scaffold() =>
        tester.widget<SectionScaffold>(find.byType(SectionScaffold));

    final before = scaffold();

    await tester.enterText(_field('field-firstName'), 'Оля');
    await tester.pump();

    expect(
      identical(before, scaffold()),
      isTrue,
      reason:
          'a keystroke must not re-run the screen build — the old '
          'setState(() {}) recreated the whole SectionScaffold (P2 jank).',
    );

    expect(
      tester
          .widget<NeumorphicButton>(find.byKey(const Key('btn-save-personal')))
          .onPressed,
      isNotNull,
      reason: 'the ValueListenableBuilder footer must still enable Save',
    );
  });

  testWidgets(
    'Save sends a ClientProfileUpdate with only the name slice (no location)',
    (tester) async {
      ClientProfileUpdate? captured;
      when(() => repo.updateMyProfile(any())).thenAnswer((invocation) async {
        captured = invocation.positionalArguments.first as ClientProfileUpdate;
      });

      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      await tester.enterText(_field('field-firstName'), 'Оля');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-personal')));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.firstName, 'Оля');
      expect(captured!.lastName, 'Ковальчук');
      expect(
        captured!.touchesLocation,
        isFalse,
        reason: 'the Personal screen never touches the location slice',
      );
      expect(captured!.phoneNumber, isNull);
    },
  );
}
