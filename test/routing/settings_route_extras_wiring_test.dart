// Phase 21.13 QA follow-up — wiring coverage for `RouteNames.settings`'s
// `state.extra as AccountSettingsExtras?` cast in `app_router.dart`.
//
// WHY THIS FILE EXISTS
// ---------------------
// `app_router.dart`'s `/settings` `GoRoute.builder` reads an optional
// [AccountSettingsExtras] out of `GoRouterState.extra` and forwards its two
// fields into `SettingsScreen`'s constructor. Nothing exercised this before —
// a `grep` for `AccountSettingsExtras` in `test/` returned zero hits. This
// mounts the REAL `appRouterProvider` (not a test-local duplicate of the
// builder logic) via a `ProviderContainer` + `UncontrolledProviderScope`,
// mirroring `salon_manage_route_guard_test.dart`'s proven shape, and drives
// navigation with `router.push` (not `.go`) to mirror how every real caller
// reaches this route (`context.push(RouteNames.settings, extra: ...)` /
// `context.push(RouteNames.settings)`).
//
// Covers:
//   1. Pushing with a valid [AccountSettingsExtras] reaches `SettingsScreen`
//      constructed with those exact values — proven both by reading the
//      constructor fields (data-plumbing correctness) AND, combined with an
//      owner session, by the owner-only delete-salon row actually
//      rendering (observable behaviour — closes the loop with the
//      `_showDeleteSalonRow` truth table in
//      `settings_screen_delete_salon_row_test.dart`).
//   2. Pushing with NO extra (both existing callers' shape) yields the safe
//      defaults (`salonId: null`, `showDeleteSalon: false`) — proven the
//      same way: constructor fields AND the row staying hidden even for an
//      owner session.
//   3. Pushing with a WRONG-TYPED extra falls back to the same safe
//      defaults as no extra — the `/settings` builder type-checks
//      (`extra is AccountSettingsExtras ? extra : null`, commit 49f16c76)
//      instead of the old unguarded `as AccountSettingsExtras?` cast, so a
//      stray extra can never crash the account screen or surface owner-only
//      rows.
//
// Layer: Widget (mounts the real router + screen tree).

import 'dart:async';

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/settings/domain/account_settings_extras.dart';
import 'package:beautica_mobile/features/settings/presentation/settings_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/test_container.dart';

const String _kSalonId = 'salon-21-13-router';

const _ownerUser = User(
  id: 'owner-router-1',
  email: 'owner-router@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Оксана',
  lastName: 'Швець',
);

/// Resolves immediately to an [Authenticated] session for [_ownerUser].
class _OwnerAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _ownerUser, accessToken: 'tok');
}

/// [MaterialApp.router] wrapper for the real [appRouterProvider], mirroring
/// `salon_manage_route_guard_test.dart`'s `_RouterApp`.
class _RouterApp extends StatelessWidget {
  const _RouterApp({required this.router});
  final GoRouter router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk', 'UA'),
  );
}

Finder get _rowFinder => find.byKey(const Key('row-delete-salon'));

void main() {
  group('RouteNames.settings — AccountSettingsExtras wiring', () {
    // Park the splash gate in the past so authRedirect does not pin the
    // router on /splash waiting for AppStartTime.minSplashDuration to elapse
    // (same setup salon_manage_route_guard_test.dart uses).
    setUp(
      () => AppStartTime.setStartForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );
    tearDown(AppStartTime.resetForTest);

    Future<GoRouter> pumpRouterAsOwner(WidgetTester tester) async {
      final container = makeTestContainer(
        retry: (_, _) => null,
        overrides: [
          authProvider.overrideWith(_OwnerAuthNotifier.new),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        ],
      );
      final router = container.read(appRouterProvider);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _RouterApp(router: router),
        ),
      );
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets(
      'pushing with a valid AccountSettingsExtras reaches SettingsScreen '
      'constructed with those values, and (as an owner) the delete-salon '
      'row actually renders',
      (tester) async {
        final router = await pumpRouterAsOwner(tester);

        unawaited(
          router.push(
            RouteNames.settings,
            extra: const AccountSettingsExtras(
              salonId: _kSalonId,
              showDeleteSalon: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SettingsScreen), findsOneWidget);
        final SettingsScreen screen = tester.widget<SettingsScreen>(
          find.byType(SettingsScreen),
        );
        expect(screen.salonId, _kSalonId);
        expect(screen.showDeleteSalon, isTrue);

        // Observable behaviour, not just constructor plumbing: the owner-only
        // row must actually be reachable through the real router wiring.
        expect(_rowFinder, findsOneWidget);
      },
    );

    testWidgets(
      'pushing with NO extra (both existing callers\' shape) yields the safe '
      'defaults — salonId: null, showDeleteSalon: false — and the '
      'delete-salon row stays hidden even for an owner session',
      (tester) async {
        final router = await pumpRouterAsOwner(tester);

        unawaited(router.push(RouteNames.settings));
        await tester.pumpAndSettle();

        expect(find.byType(SettingsScreen), findsOneWidget);
        final SettingsScreen screen = tester.widget<SettingsScreen>(
          find.byType(SettingsScreen),
        );
        expect(screen.salonId, isNull);
        expect(screen.showDeleteSalon, isFalse);

        expect(_rowFinder, findsNothing);
      },
    );

    testWidgets(
      'pushing with a WRONG-TYPED extra does NOT throw — the builder\'s '
      '`is AccountSettingsExtras` check falls back to the safe defaults and '
      'the delete-salon row stays hidden even for an owner session',
      (tester) async {
        final router = await pumpRouterAsOwner(tester);

        // A stray String extra — no real caller does this; every actual call
        // site is a compile-time-checked AccountSettingsExtras(...) literal
        // or omits `extra` entirely.
        unawaited(
          router.push(RouteNames.settings, extra: 'not-the-right-type'),
        );
        await tester.pumpAndSettle();

        // A build-phase throw would be recorded by the binding and surface
        // here; none may occur.
        expect(tester.takeException(), isNull);
        expect(find.byType(SettingsScreen), findsOneWidget);
        final SettingsScreen screen = tester.widget<SettingsScreen>(
          find.byType(SettingsScreen),
        );
        expect(screen.salonId, isNull);
        expect(screen.showDeleteSalon, isFalse);
        expect(screen.fromSalonSettings, isFalse);

        expect(_rowFinder, findsNothing);
      },
    );
  });
}
