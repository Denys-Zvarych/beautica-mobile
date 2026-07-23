// Widget tests for ClientContactsEditScreen (phone only).
//
// 1:1 client transcription of the master contacts screen with the Instagram
// field REMOVED. Coverage:
//   • the phone field renders and pre-populates from the cached profile.
//   • NO Instagram field is rendered (assert absence of field-instagram).
//   • Save sends a ClientProfileUpdate carrying only the phone slice.
//   • The repository is never asked to send instagram (verified at the unit
//     layer in client_profile_repository_test.dart).
//
// Finders use widget Keys (M2). Layer: Widget.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/home/data/client_profile_repository.dart';
import 'package:beautica_mobile/features/home/domain/client_profile_update.dart';
import 'package:beautica_mobile/features/home/presentation/client_contacts_edit_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
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
  initialLocation: RouteNames.clientEditContacts,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.clientEditContacts,
      pageBuilder: (_, _) =>
          const NoTransitionPage<void>(child: ClientContactsEditScreen()),
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

  testWidgets(
    'renders the phone field and does NOT render an Instagram field',
    (tester) async {
      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('field-phone')), findsOneWidget);
      expect(
        find.byKey(const Key('field-instagram')),
        findsNothing,
        reason:
            'clients have no Instagram — the master instagram field key must '
            'be absent',
      );
    },
  );

  testWidgets('pre-populates the phone from the cached profile', (
    tester,
  ) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<TextField>(_field('field-phone')).controller?.text,
      '+380 50 123 45 67',
    );
  });

  testWidgets(
    'Save sends a ClientProfileUpdate with only the phone slice (no location)',
    (tester) async {
      ClientProfileUpdate? captured;
      when(() => repo.updateMyProfile(any())).thenAnswer((invocation) async {
        captured = invocation.positionalArguments.first as ClientProfileUpdate;
      });

      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      await tester.enterText(_field('field-phone'), '+380 67 000 11 22');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-contacts')));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.phoneNumber, isNotNull);
      expect(captured!.firstName, isNull);
      expect(captured!.lastName, isNull);
      expect(
        captured!.touchesLocation,
        isFalse,
        reason: 'the Contacts screen never touches the location slice',
      );
    },
  );

  testWidgets(
    'a ServerFailure on save surfaces an error snackbar and does NOT navigate '
    'away',
    (tester) async {
      when(
        () => repo.updateMyProfile(any()),
      ).thenThrow(const ServerFailure(statusCode: 500));

      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      // Make the form dirty so the Save CTA is enabled.
      await tester.enterText(_field('field-phone'), '+380 67 000 11 22');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-contacts')));
      await tester.pump(); // run the save future + showSnackBar
      await tester.pump(); // let the SnackBar animate in

      // The screen stays put — no navigation to the stub home occurred.
      expect(find.byKey(const Key('stub-home')), findsNothing);
      expect(find.byKey(const Key('field-phone')), findsOneWidget);

      // The localized ServerFailure message renders inside a SnackBar.
      final BuildContext ctx = tester.element(
        find.byKey(const Key('field-phone')),
      );
      final String expected = AppLocalizations.of(ctx).errServer;
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(expected),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('renders the CLIENT phone privacy note (not the master one)', (
    tester,
  ) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    final BuildContext ctx = tester.element(
      find.byKey(const Key('field-phone')),
    );
    final AppLocalizations l10n = AppLocalizations.of(ctx);

    expect(
      find.text(l10n.clientPhonePrivacyNote),
      findsOneWidget,
      reason:
          'the client phone field shows the client-appropriate privacy note '
          '(masters do not see the client number)',
    );
    expect(
      find.text(l10n.phonePrivacyNote),
      findsNothing,
      reason:
          'the master-context privacy note must not appear on the client '
          'screen',
    );
  });
}
