// Cross-provider REGRESSION guard — stale home-hub profile card after a CLIENT
// profile edit (Step 2.7 gate + Rule 3b, regression tier).
//
// THE BUG (now fixed)
// -------------------
// After a CLIENT saved a profile edit (PATCH /users/me → 200), the home-hub
// profile card (name / city / phone) showed STALE values until the app was
// restarted. clientProfile now derives from `clientEditProfileProvider` (the
// fresh `GET /users/me` source the Settings edit screens read), NOT from the
// long-lived `authProvider` session User. The save path persists the slice
// (`updateMyProfile`), refreshes the session (`refreshUser()` → `me()`), then
// `invalidate(clientEditProfileProvider)` + `invalidate(clientProfileProvider)`
// — so the card re-derives from a freshly re-fetched `/users/me` in-session.
//
// WHY THIS TEST IS A TRUE REGRESSION GUARD
// ----------------------------------------
// It wires the PRODUCTION graph in a SINGLE ProviderContainer (no restart / no
// container recreate):
//   • the REAL AuthNotifier + REAL clientEditProfileProvider (only their data
//     boundaries — authRepositoryProvider + secureStorageProvider +
//     clientProfileRepository — are overridden). A stubbed notifier (as the
//     per-screen widget tests use) would silently mask the bug — that is exactly
//     why those tests never caught it.
//   • the client profile repo's `getMyProfile()` (the `/users/me` source for
//     clientProfile) returns the OLD profile on the cold-start fetch and the NEW
//     profile on the post-save `invalidate(clientEditProfileProvider)` re-fetch.
//   • a real `ClientContactsEditScreen` drives the real `_save()` path through a
//     mocked `clientProfileRepository.updateMyProfile` (success).
// After the save it reads `clientProfileProvider` IN THE SAME container and pumps
// the real `HomeProfileCard` with that summary, asserting the NEW name / city /
// phone are surfaced WITHOUT any restart.
//
// PRE-FIX BEHAVIOUR (verified): if clientProfile is reverted to read the stale
// `authProvider` session User, the save's invalidate would re-derive from the
// unchanged cold-start snapshot, so `clientProfileProvider` would still report
// the OLD city/phone and these assertions FAIL.
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
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
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

// ── Out-of-band fixtures (Part B): cold-start profile has NO city; the
// `/users/me` source later returns the SAME user WITH a city — simulating a
// DB-seeded / admin / out-of-band change that did NOT go through an in-session
// edit save. Same id so it is unambiguously the same account.
const _noCityUser = User(
  id: 'client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Олена',
  lastName: 'Тест',
  // cityName / cityId intentionally null → placeholder path on cold start.
);

const _seededCityUser = User(
  id: 'client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Олена',
  lastName: 'Тест',
  cityName: 'Львів',
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
    when(
      () => authRepo.refresh('refresh-stored'),
    ).thenAnswer((_) async => _tokens);

    // me() : 1st call (cold-start build) → OLD user; later (refreshUser) → NEW.
    var meCalls = 0;
    when(() => authRepo.me()).thenAnswer((_) async {
      meCalls++;
      return meCalls == 1 ? _oldUser : _newUser;
    });

    // clientProfile now derives from clientEditProfileProvider (the fresh
    // `GET /users/me` source), so getMyProfile() — NOT me() — is what drives the
    // card's name/city/phone. The Contacts edit screen also seeds its phone
    // field from this same source. Return the OLD profile on the cold-start
    // fetch and the NEW profile on every fetch after the save's
    // `invalidate(clientEditProfileProvider)` re-fetch.
    var getMyProfileCalls = 0;
    when(() => profileRepo.getMyProfile()).thenAnswer((_) async {
      getMyProfileCalls++;
      return getMyProfileCalls == 1 ? _oldUser : _newUser;
    });
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

  // ── Part B — THE ACTUAL BUG: out-of-band /users/me change (no edit save) ─────
  //
  // The two tests above prove freshness AFTER an in-session edit-screen save
  // (which calls refreshUser() + invalidate). The shipped bug was different: the
  // hub did NOT reflect a `/users/me` change that NEVER went through an
  // in-session edit — e.g. a DB-seeded / admin / out-of-band city — until a cold
  // restart. Because the OLD clientProfile read the long-lived `authProvider`
  // session User (only re-hydrated on cold start / login / explicit
  // refreshUser()), such a change stayed invisible.
  //
  // This test reproduces exactly that path WITHOUT any edit save: it boots an
  // authenticated session whose cold-start `/users/me` has NO city, then makes
  // the `/users/me` source (clientEditProfileProvider → getMyProfile) return a
  // profile WITH cityName="Львів" and invalidates it, and asserts the card
  // surfaces "Львів" with NO restart. The session User itself is never refreshed
  // (me() is called only once, on cold start), so this is RED against the pre-fix
  // wiring: a clientProfile that reads the session User would still report the
  // city-less cold-start snapshot ("Місто не вказано" placeholder) here.
  testWidgets(
    'REGRESSION: an out-of-band /users/me city change surfaces on the home '
    'card after clientEditProfileProvider invalidation — NO edit save, NO '
    'restart (does NOT keep showing the placeholder)',
    (tester) async {
      await storage.writeRefreshToken('refresh-stored');
      when(
        () => authRepo.refresh('refresh-stored'),
      ).thenAnswer((_) async => _tokens);

      // The session User is the city-less cold-start snapshot and NEVER changes
      // here (no refreshUser, no edit save) — pre-fix clientProfile read THIS.
      when(() => authRepo.me()).thenAnswer((_) async => _noCityUser);

      // The FRESH /users/me source: city-less on cold start, then "Львів" after
      // the out-of-band change. The mock closure reads the mutable [meProfile].
      User meProfile = _noCityUser;
      when(() => profileRepo.getMyProfile()).thenAnswer((_) async => meProfile);

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWith((_) => authRepo),
          secureStorageProvider.overrideWith((_) => storage),
          clientProfileRepositoryProvider.overrideWithValue(profileRepo),
        ],
      );
      addTearDown(container.dispose);

      // Resolve the cold-start authenticated session (city-less).
      final session = await container.read(authProvider.future);
      expect(session, isA<Authenticated>());

      // Pre-condition: cold-start /users/me carries no city → placeholder path.
      final before = await container.read(clientProfileProvider.future);
      expect(
        before.city,
        '',
        reason:
            'the cold-start /users/me profile has no city → empty string '
            '(the card then renders its "Місто не вказано" placeholder)',
      );

      // Out-of-band change: /users/me now returns a city WITHOUT any in-session
      // edit save. Invalidate the fresh source exactly as a pull/refresh would.
      meProfile = _seededCityUser;
      container.invalidate(clientEditProfileProvider);

      // THE ASSERTION: the hub surfaces the new city WITHOUT a restart and
      // WITHOUT an edit-screen save.
      final after = await container.read(clientProfileProvider.future);
      expect(
        after.city,
        'Львів',
        reason:
            'clientProfile must derive from clientEditProfileProvider (fresh '
            '/users/me), so the out-of-band "Львів" surfaces after invalidation '
            'with no restart. Pre-fix it read the stale authProvider session '
            'User (still city-less) and would report "" here.',
      );

      // The session User itself never changed — freshness came from the
      // /users/me source, NOT authProvider. me() ran only once (cold start),
      // proving no refreshUser / edit save was involved.
      final live = container.read(authProvider).value;
      expect(
        (live as Authenticated).user.cityName,
        isNull,
        reason:
            'no refreshUser ran — the session User stays city-less; the card '
            'freshness came from clientEditProfileProvider',
      );
      verify(() => authRepo.me()).called(1);

      // Render the REAL profile card with the resolved summary and confirm the
      // user-visible city is the out-of-band "Львів" (not the placeholder).
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
            home: Scaffold(
              body: HomeProfileCard(
                profile: after,
                onCamera: () {},
                onLocation: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        // i18n-finder-ok: city name is fixture data, not UI copy
        find.text('Львів'),
        findsOneWidget,
        reason:
            'the home profile card must surface the out-of-band city "Львів" '
            'without a restart',
      );
    },
  );
}
