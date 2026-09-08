// Widget tests for the CLIENT-only «Видалити акаунт» row on the Account page
// (SettingsScreen) — relocated here (2026-09-08) from the CLIENT settings hub
// (`client_settings_hub_screen_test.dart`), which was the wrong screen: that
// hub's title is «Налаштування», while THIS page's title (`accountTitle`) is
// «Акаунт» — the screen the row was always meant to sit on.
//
// Two groups:
//   • role-gate truth table — mirrors
//     `settings_screen_delete_salon_row_test.dart`'s own truth-table shape
//     for `_showDeleteSalonRow`, one conjunct swapped: CLIENT session ⇒ row
//     renders; every other role (or unauthenticated / unsettled session) ⇒
//     hidden. `DELETE /api/v1/users/me` is CLIENT-only server-side (403 for
//     every other role) — see `_showDeleteAccountRow`'s doc in
//     `settings_screen.dart`.
//   • interaction flow — the full confirm/cancel/dismiss/spinner/double-tap/
//     failure suite, moved verbatim (only the pumped widget + router changed)
//     from the hub's now-removed `ClientSettingsHubScreen delete-account row`
//     group. [runDeleteAccountFlow] itself is untouched.
//
// Finders use widget Keys — never localized strings (M2), except where the
// existing hub tests already asserted on localized dialog copy (kept as-is).
// Layer: Widget.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/settings/presentation/settings_screen.dart';
import 'package:beautica_mobile/features/user/data/user_repository.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/fakes/fake_user_repository.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

User _userWith(UserRole role) => User(
  id: 'u-${role.name}',
  email: '${role.name}@beautica.ua',
  role: role,
  firstName: 'Тест',
  lastName: 'Юзер',
);

/// Resolves immediately to an [Authenticated] session for [user].
class _AuthenticatedAs extends AuthNotifier {
  _AuthenticatedAs(this.user);
  final User user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: user, accessToken: 'tok');
}

/// Resolves immediately to [AuthSession.unauthenticated].
class _UnauthenticatedNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.unauthenticated();
}

/// NEVER resolves — pins the fail-closed behaviour of an unsettled
/// `AsyncValue<AuthSession>` (no prior `.value`) deliberately.
class _LoadingForeverNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() => Completer<AuthSession>().future;
}

/// [_AuthenticatedAs] whose `logout()` resolves immediately — the
/// interaction-flow group needs to observe the flow's post-success
/// navigation actually land on `/login`, unlike the role-gate group which
/// never triggers the flow.
class _ResolvingAuthenticatedAs extends AuthNotifier {
  _ResolvingAuthenticatedAs(this.user);
  final User user;
  int logoutCalls = 0;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: user, accessToken: 'tok');

  @override
  Future<void> logout() async {
    logoutCalls++;
  }
}

Finder get _rowFinder => find.byKey(const Key('row-delete-account'));
Finder get _dividerFinder =>
    find.byKey(const Key('account-settings-delete-account-divider'));

void main() {
  group('SettingsScreen — CLIENT-only delete-account row truth table', () {
    testWidgets('CLIENT session → row AND divider render', (tester) async {
      await tester.pumpApp(
        const SettingsScreen(),
        overrides: [
          authProvider.overrideWith(
            () => _AuthenticatedAs(_userWith(UserRole.client)),
          ),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        ],
      );
      await tester.pumpAndSettle();

      expect(_rowFinder, findsOneWidget);
      expect(_dividerFinder, findsOneWidget);
    });

    for (final role in [
      UserRole.salonOwner,
      UserRole.salonAdmin,
      UserRole.salonMaster,
      UserRole.independentMaster,
    ]) {
      testWidgets('${role.name} session → row AND divider hidden', (
        tester,
      ) async {
        await tester.pumpApp(
          const SettingsScreen(),
          overrides: [
            authProvider.overrideWith(() => _AuthenticatedAs(_userWith(role))),
            authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
            secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          ],
        );
        await tester.pumpAndSettle();

        expect(_rowFinder, findsNothing);
        expect(_dividerFinder, findsNothing);
      });
    }

    testWidgets('Unauthenticated session → row AND divider hidden', (
      tester,
    ) async {
      await tester.pumpApp(
        const SettingsScreen(),
        overrides: [
          authProvider.overrideWith(_UnauthenticatedNotifier.new),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        ],
      );
      await tester.pumpAndSettle();

      expect(_rowFinder, findsNothing);
      expect(_dividerFinder, findsNothing);
    });

    testWidgets(
      'AsyncLoading (no prior value) session → row AND divider hidden '
      '(fails closed)',
      (tester) async {
        await tester.pumpApp(
          const SettingsScreen(),
          overrides: [
            authProvider.overrideWith(_LoadingForeverNotifier.new),
            authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
            secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          ],
        );
        await tester.pumpAndSettle();

        expect(_rowFinder, findsNothing);
        expect(_dividerFinder, findsNothing);
      },
    );
  });

  group('SettingsScreen delete-account row interaction (CLIENT session)', () {
    GoRouter router({required AuthNotifier Function() authNotifier}) =>
        GoRouter(
          initialLocation: RouteNames.settings,
          redirect: (context, state) => null,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.settings,
              builder: (_, _) => const SettingsScreen(),
            ),
            GoRoute(
              path: RouteNames.login,
              builder: (_, _) =>
                  const Scaffold(body: SizedBox(key: Key('stub-login'))),
            ),
          ],
        );

    Future<GoRouter> pump(
      WidgetTester tester, {
      required AuthNotifier Function() authNotifier,
      FakeUserRepository? userRepo,
    }) async {
      final r = router(authNotifier: authNotifier);
      addTearDown(r.dispose);
      await tester.pumpRoutedApp(
        r,
        overrides: <Object>[
          authProvider.overrideWith(authNotifier),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          if (userRepo != null)
            userRepositoryProvider.overrideWithValue(userRepo),
        ],
      );
      await tester.pumpAndSettle();
      return r;
    }

    AuthNotifier Function() clientAuth() =>
        () => _AuthenticatedAs(_userWith(UserRole.client));

    testWidgets('renders at the bottom of the Account page', (tester) async {
      await pump(tester, authNotifier: clientAuth());

      expect(_rowFinder, findsOneWidget);

      final double changePasswordY = tester
          .getTopLeft(find.byKey(const Key('row-change-password')))
          .dy;
      final double deleteAccountY = tester.getTopLeft(_rowFinder).dy;
      expect(
        deleteAccountY,
        greaterThan(changePasswordY),
        reason: 'row-delete-account must render below the other rows',
      );
    });

    testWidgets(
      'tapping raises a confirm dialog whose copy carries no digits — no '
      'booking count is fetched or shown (locked product decision)',
      (tester) async {
        await pump(tester, authNotifier: clientAuth());

        await tester.ensureVisible(_rowFinder);
        await tester.pumpAndSettle();
        await tester.tap(_rowFinder);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.byKey(const Key('btn-delete-account-cancel')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('btn-delete-account-confirm')),
          findsOneWidget,
        );

        final l10n = lookupAppLocalizations(const Locale('uk'));
        expect(find.text(l10n.deleteAccountConfirmBody), findsOneWidget);
        expect(
          RegExp(r'\d').hasMatch(l10n.deleteAccountConfirmBody),
          isFalse,
          reason:
              'the dialog body must never surface a booking COUNT — a '
              'locked product decision (see delete_account_flow.dart header)',
        );

        await tester.tap(find.byKey(const Key('btn-delete-account-cancel')));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'cancel does not call deleteMyAccount and resets inFlight so the row '
      'is tappable again',
      (tester) async {
        final fakeRepo = FakeUserRepository();
        await pump(tester, authNotifier: clientAuth(), userRepo: fakeRepo);

        await tester.ensureVisible(_rowFinder);
        await tester.pumpAndSettle();
        await tester.tap(_rowFinder);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn-delete-account-cancel')));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(fakeRepo.deleteMyAccountCalls, 0);

        await tester.tap(_rowFinder);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);

        await tester.tap(find.byKey(const Key('btn-delete-account-cancel')));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'a barrier-tap dismiss does not call deleteMyAccount and resets '
      'inFlight',
      (tester) async {
        final fakeRepo = FakeUserRepository();
        await pump(tester, authNotifier: clientAuth(), userRepo: fakeRepo);

        await tester.ensureVisible(_rowFinder);
        await tester.pumpAndSettle();
        await tester.tap(_rowFinder);
        await tester.pumpAndSettle();

        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(fakeRepo.deleteMyAccountCalls, 0);

        await tester.tap(_rowFinder);
        await tester.pumpAndSettle();
        expect(
          find.byType(AlertDialog),
          findsOneWidget,
          reason: 'inFlight must be reset after a barrier dismiss',
        );

        await tester.tap(find.byKey(const Key('btn-delete-account-cancel')));
        await tester.pumpAndSettle();
      },
    );

    testWidgets('the OS back gesture does not call deleteMyAccount and '
        'resets inFlight', (tester) async {
      final fakeRepo = FakeUserRepository();
      await pump(tester, authNotifier: clientAuth(), userRepo: fakeRepo);

      await tester.ensureVisible(_rowFinder);
      await tester.pumpAndSettle();
      await tester.tap(_rowFinder);
      await tester.pumpAndSettle();

      final bool handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(handled, isTrue, reason: 'the dialog route must consume back');
      expect(find.byType(AlertDialog), findsNothing);
      expect(fakeRepo.deleteMyAccountCalls, 0);

      await tester.tap(_rowFinder);
      await tester.pumpAndSettle();
      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason: 'inFlight must be reset after the OS back gesture',
      );

      await tester.tap(find.byKey(const Key('btn-delete-account-cancel')));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'confirming calls deleteMyAccount exactly once, tears auth down, and '
      'lands on login',
      (tester) async {
        final fakeRepo = FakeUserRepository();
        final auth = _ResolvingAuthenticatedAs(_userWith(UserRole.client));
        await pump(tester, authNotifier: () => auth, userRepo: fakeRepo);

        await tester.ensureVisible(_rowFinder);
        await tester.pumpAndSettle();
        await tester.tap(_rowFinder);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
        await tester.pumpAndSettle();

        expect(fakeRepo.deleteMyAccountCalls, 1);
        expect(
          auth.logoutCalls,
          1,
          reason:
              'a successful delete must tear the session down via '
              'AuthNotifier.logout(), same as runLogoutFlow',
        );
        expect(find.byKey(const Key('stub-login')), findsOneWidget);
      },
    );

    testWidgets(
      'the spinner is post-consent only — the row is not loading while the '
      'confirm dialog is open, only after confirming',
      (tester) async {
        final fakeRepo = FakeUserRepository()
          ..deleteMyAccountGate = Completer<void>();
        final auth = _ResolvingAuthenticatedAs(_userWith(UserRole.client));
        await pump(tester, authNotifier: () => auth, userRepo: fakeRepo);

        await tester.ensureVisible(_rowFinder);
        await tester.pumpAndSettle();
        await tester.tap(_rowFinder);
        await tester.pumpAndSettle();

        Finder rowSpinner() => find.descendant(
          of: _rowFinder,
          matching: find.byType(CircularProgressIndicator),
        );

        expect(
          rowSpinner(),
          findsNothing,
          reason: 'the row must not be loading while consent is pending',
        );

        await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
        await tester.pump(); // apply pop(true) + flip loading + start the call
        // fixed-wait-ok: draining the confirm dialog's exit transition so the
        // spinner assertion below reads the fully-settled row, not a
        // mid-animation frame.
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          rowSpinner(),
          findsOneWidget,
          reason:
              'the row must show loading only AFTER consent, before the '
              'network call resolves',
        );

        fakeRepo.deleteMyAccountGate!.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'double-tap guard: a second confirm while the delete call is still '
      'in flight does not fire a second deleteMyAccount call',
      (tester) async {
        final fakeRepo = FakeUserRepository()
          ..deleteMyAccountGate = Completer<void>();
        final auth = _ResolvingAuthenticatedAs(_userWith(UserRole.client));
        await pump(tester, authNotifier: () => auth, userRepo: fakeRepo);

        await tester.ensureVisible(_rowFinder);
        await tester.pumpAndSettle();
        await tester.tap(_rowFinder);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
        await tester.pump(); // the DELETE call is now in flight (gated)

        expect(fakeRepo.deleteMyAccountCalls, 1);

        await tester.tap(_rowFinder, warnIfMissed: false);
        await tester.pump();
        // fixed-wait-ok: draining any dialog transition a wrongly-raised
        // second confirm would have started, so the findsNothing assertion
        // below reads the fully-settled tree.
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.byKey(const Key('btn-delete-account-confirm')),
          findsNothing,
          reason: 'a second tap while in flight must not raise a new dialog',
        );
        expect(
          fakeRepo.deleteMyAccountCalls,
          1,
          reason: 'the in-flight guard must prevent a second concurrent call',
        );

        fakeRepo.deleteMyAccountGate!.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets('a 422 booking-limit failure renders the backend '
        'serverMessage verbatim', (tester) async {
      const String marker =
          'QA-422-MARKER: спочатку скасуйте бронювання №A1B2C3';
      final fakeRepo = FakeUserRepository()
        ..deleteMyAccountError = const AccountDeleteBookingLimitFailure(
          serverMessage: marker,
        );
      await pump(tester, authNotifier: clientAuth(), userRepo: fakeRepo);

      await tester.ensureVisible(_rowFinder);
      await tester.pumpAndSettle();
      await tester.tap(_rowFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
      await tester.pump();
      await pumpVelvetSnackIn(tester);

      expectVelvetSnack(marker, variant: VelvetSnackVariant.error);
      expect(find.byKey(const Key('stub-login')), findsNothing);

      await pumpPastVelvetSnack(tester);
    });

    testWidgets('a 429 rate-limit failure renders the rate-limit message', (
      tester,
    ) async {
      final fakeRepo = FakeUserRepository()
        ..deleteMyAccountError = const AccountDeleteRateLimitedFailure();
      await pump(tester, authNotifier: clientAuth(), userRepo: fakeRepo);

      await tester.ensureVisible(_rowFinder);
      await tester.pumpAndSettle();
      await tester.tap(_rowFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
      await tester.pump();
      await pumpVelvetSnackIn(tester);

      final l10n = lookupAppLocalizations(const Locale('uk'));
      expectVelvetSnack(
        l10n.accountDeleteErrRateLimited,
        variant: VelvetSnackVariant.error,
      );
      expect(find.byKey(const Key('stub-login')), findsNothing);

      await pumpPastVelvetSnack(tester);
    });

    testWidgets('on failure both flags reset — the row is usable again and the '
        'screen is not left inert', (tester) async {
      final fakeRepo = FakeUserRepository()
        ..deleteMyAccountError = const NetworkFailure();
      await pump(tester, authNotifier: clientAuth(), userRepo: fakeRepo);

      await tester.ensureVisible(_rowFinder);
      await tester.pumpAndSettle();
      await tester.tap(_rowFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
      await tester.pump();
      await pumpVelvetSnackIn(tester);
      await pumpPastVelvetSnack(tester);

      expect(
        find.descendant(
          of: _rowFinder,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
        reason: 'loading must reset on failure',
      );

      await tester.tap(_rowFinder);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        fakeRepo.deleteMyAccountCalls,
        1,
        reason: 'only the first tap should have reached the network',
      );

      await tester.tap(find.byKey(const Key('btn-delete-account-cancel')));
      await tester.pumpAndSettle();
    });
  });
}
