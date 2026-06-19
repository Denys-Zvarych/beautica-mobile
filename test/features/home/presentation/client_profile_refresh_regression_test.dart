// Cross-provider REGRESSION guard — stale home-hub profile card after a CLIENT
// profile edit (Step 2.7 gate + Rule 3b, regression tier).
//
// THE BUG (now fixed)
// -------------------
// After a CLIENT saved a profile edit (PATCH /users/me → 200), the home-hub
// profile card (name / city / phone) showed STALE values until the app was
// restarted. Root cause: `clientProfileProvider` (home_hub_notifier.dart)
// derives from the `authProvider` session User, which was NEVER re-fetched after
// the save — the edit screens only invalidated the seed/profile providers, which
// re-derive from the same stale session snapshot. Fix: each client edit-screen
// save now calls `AuthNotifier.refreshUser()` (re-runs `repo.me()`, preserves
// the token) BEFORE invalidating clientEditProfileProvider / clientProfileProvider,
// so every consumer re-derives from the freshly-fetched session User.
//
// WHY THIS TEST IS A TRUE REGRESSION GUARD
// ----------------------------------------
// It wires the PRODUCTION graph in a SINGLE ProviderContainer (no restart / no
// container recreate):
//   • the REAL AuthNotifier (only its data boundary — authRepositoryProvider +
//     secureStorageProvider — is overridden), so a save's `refreshUser()` call
//     actually re-runs `repo.me()`. A stubbed notifier (as the per-screen widget
//     tests use) would silently mask the bug — that is exactly why those tests
//     never caught it.
//   • the auth repo's `me()` returns the OLD user on cold start and the NEW user
//     on the post-save refresh.
//   • a real `ClientContactsEditScreen` drives the real `_save()` path through a
//     mocked `clientProfileRepository.updateMyProfile` (success).
// After the save it reads `clientProfileProvider` IN THE SAME container and pumps
// the real `HomeProfileCard` with that summary, asserting the NEW name / city /
// phone are surfaced WITHOUT any restart.
//
// PRE-FIX BEHAVIOUR (verified): delete the `refreshUser()` line in
// client_contacts_edit_screen.dart `_save()` and these tests FAIL — the session
// User stays the cold-start snapshot, so `clientProfileProvider` still reports
// the OLD city/phone and `me()` is invoked only once (cold start), never on save.
//
// Layer: Widget / cross-provider. Finders use Keys for taps (M2); the card's
// rendered name/city/phone are plain Text (no per-field key) so they are asserted
// via find.text content assertions, which is acceptable for value-binding checks.

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/data/client_profile_repository.dart';
import 'package:beautica_mobile/features/home/domain/client_profile_update.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/home_profile_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/features/home/presentation/client_contacts_edit_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/overflow_guard.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockClientProfileRepository extends Mock
    implements ClientProfileRepository {}

// ── Fixtures: the SAME user id/email/role, only name/city/phone differ. ──────
const _oldUser = User(
  id: 'client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Old',
  lastName: 'Name',
  cityName: 'OldCity',
  phoneNumber: '+380 50 000 00 00',
);

const _newUser = User(
  id: 'client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'New',
  lastName: 'Name',
  cityName: 'NewCity',
  phoneNumber: '+380 67 111 22 33',
);

const _tokens = AuthTokens(accessToken: 'access-1', refreshToken: 'refresh-1');

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

Finder _phoneField() => find.descendant(
  of: find.byKey(const Key('field-phone')),
  matching: find.byType(TextField),
);

void main() {
  setUpAll(() {
    registerFallbackValue(const ClientProfileUpdate());
  });

  late _MockAuthRepository authRepo;
  late _MockClientProfileRepository profileRepo;
  late FakeSecureStorage storage;

  setUp(() {
    installOverflowGuard();
    authRepo = _MockAuthRepository();
    profileRepo = _MockClientProfileRepository();
    storage = FakeSecureStorage();
  });

  /// Builds the production graph in ONE container: real AuthNotifier (data
  /// boundary overridden), real clientProfile/clientEditProfile providers, mocked
  /// clientProfileRepository. `me()` returns OLD on cold start, NEW afterwards.
  Future<ProviderContainer> bootAuthenticated(WidgetTester tester) async {
    await storage.writeRefreshToken('refresh-stored');
    when(() => authRepo.refresh('refresh-stored')).thenAnswer((_) async => _tokens);

    // me() : 1st call (cold-start build) → OLD user; later (refreshUser) → NEW.
    var meCalls = 0;
    when(() => authRepo.me()).thenAnswer((_) async {
      meCalls++;
      return meCalls == 1 ? _oldUser : _newUser;
    });

    // The Contacts edit screen seeds its phone field from getMyProfile()
    // (clientEditProfileProvider). Seed it with the OLD phone.
    when(() => profileRepo.getMyProfile()).thenAnswer((_) async => _oldUser);
    // The save itself succeeds (200) — we are testing the post-save refresh.
    when(() => profileRepo.updateMyProfile(any())).thenAnswer((_) async {});

    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((_) => authRepo),
        secureStorageProvider.overrideWith((_) => storage),
        clientProfileRepositoryProvider.overrideWithValue(profileRepo),
      ],
    );
    addTearDown(container.dispose);

    // Resolve the cold-start session (settles Authenticated with the OLD user).
    final session = await container.read(authProvider.future);
    expect(session, isA<Authenticated>());
    expect((session as Authenticated).user, equals(_oldUser));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: _buildRouter(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
        ),
      ),
    );
    // Let clientEditProfileProvider resolve and the field pre-populate.
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'after a CLIENT saves the Contacts edit, clientProfileProvider re-derives '
    'the NEW name/city/phone IN-SESSION (no restart) — refreshUser regression '
    'guard',
    (tester) async {
      final container = await bootAuthenticated(tester);

      // Pre-condition: the card still derives the OLD session user.
      final before = await container.read(clientProfileProvider.future);
      expect(before.city, 'OldCity');
      expect(before.phone, '+380 50 000 00 00');
      expect(before.firstName, 'Old');

      // Drive a real save: change the phone so the form is dirty, tap Save.
      await tester.enterText(_phoneField(), '+380 67 111 22 33');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-save-contacts')));
      await tester.pumpAndSettle();

      // The save persisted and navigated home (proves the success path ran).
      verify(() => profileRepo.updateMyProfile(any())).called(1);

      // REGRESSION ASSERTION — the SAME container now derives the NEW user.
      // Without the refreshUser() call in _save(), the session User would still
      // be the cold-start OLD snapshot and these would read OldCity/OldPhone.
      final after = await container.read(clientProfileProvider.future);
      expect(
        after.city,
        'NewCity',
        reason:
            'clientProfileProvider must re-derive from the refreshed session '
            'User after save — stale OldCity proves refreshUser() did not run',
      );
      expect(after.phone, '+380 67 111 22 33');
      expect(after.firstName, 'New');

      // refreshUser() must have hit /users/me a SECOND time (cold start = 1st).
      verify(() => authRepo.me()).called(2);

      // And the live session User itself is the fresh one (in-session, no restart).
      final session = container.read(authProvider).value;
      expect((session as Authenticated).user, equals(_newUser));
    },
  );

  testWidgets(
    'the refreshed clientProfile summary renders the NEW values on the real '
    'HomeProfileCard',
    (tester) async {
      final container = await bootAuthenticated(tester);

      await tester.enterText(_phoneField(), '+380 67 111 22 33');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-save-contacts')));
      await tester.pumpAndSettle();

      final ClientProfileSummary summary = await container.read(
        clientProfileProvider.future,
      );

      // Pump the REAL profile card with the post-save summary in the SAME
      // container and assert the user-visible name/city/phone are the new ones.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
            home: Scaffold(
              body: HomeProfileCard(
                profile: summary,
                onCamera: () {},
                onLocation: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('New Name'), findsOneWidget);
      expect(find.text('NewCity'), findsOneWidget);
      expect(find.text('+380 67 111 22 33'), findsOneWidget);
      // The stale values must be gone from the card.
      expect(find.text('Old Name'), findsNothing);
      expect(find.text('OldCity'), findsNothing);
    },
  );
}
