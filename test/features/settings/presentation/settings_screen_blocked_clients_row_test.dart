// Phase 426 D1 — the «Заблоковані клієнти» row on «Акаунт» (SettingsScreen):
//   • role-gate truth table — INDEPENDENT_MASTER / SALON_OWNER / SALON_ADMIN
//     see it; SALON_MASTER / CLIENT / signed-out / unsettled never do
//     (`canManageClientBlocksProvider`, fails closed);
//   • placement — after «Змінити пароль», before the legal group;
//   • tap → pushes RouteNames.blockedClients.
// Layer: Widget.

import 'dart:async';

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/settings/presentation/settings_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/pump_app.dart';

class _AuthenticatedAs extends AuthNotifier {
  _AuthenticatedAs(this.role);
  final UserRole role;

  @override
  Future<AuthSession> build() async => AuthSession.authenticated(
    user: User(id: 'u-${role.name}', email: '${role.name}@b.ua', role: role),
    accessToken: 'tok',
  );
}

class _Unauthenticated extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.unauthenticated();
}

class _LoadingForever extends AuthNotifier {
  @override
  Future<AuthSession> build() => Completer<AuthSession>().future;
}

final Finder _row = find.byKey(const Key('row-blocked-clients'));

List<Object> _overrides(AuthNotifier Function() auth) => <Object>[
  authProvider.overrideWith(auth),
  authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
  secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
];

Future<void> _pump(WidgetTester tester, AuthNotifier Function() auth) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpApp(const SettingsScreen(), overrides: _overrides(auth));
  await tester.pumpAndSettle();
}

void main() {
  group('role gate', () {
    for (final UserRole role in <UserRole>[
      UserRole.independentMaster,
      UserRole.salonOwner,
      UserRole.salonAdmin,
    ]) {
      testWidgets('${role.name} → row shown with its label', (tester) async {
        await _pump(tester, () => _AuthenticatedAs(role));
        expect(_row, findsOne);
        final AppLocalizations l10n = AppLocalizations.of(tester.element(_row));
        expect(
          find.descendant(
            of: _row,
            matching: find.text(l10n.blockedClientsRowLabel),
          ),
          findsOne,
        );
      });
    }

    for (final UserRole role in <UserRole>[
      UserRole.salonMaster,
      UserRole.client,
    ]) {
      testWidgets('${role.name} → row hidden', (tester) async {
        await _pump(tester, () => _AuthenticatedAs(role));
        expect(find.byKey(const Key('row-change-password')), findsOne);
        expect(_row, findsNothing);
      });
    }

    testWidgets('signed out → row hidden', (tester) async {
      await _pump(tester, _Unauthenticated.new);
      expect(_row, findsNothing);
    });

    testWidgets('unsettled session → row hidden (fails closed)', (
      tester,
    ) async {
      await _pump(tester, _LoadingForever.new);
      expect(_row, findsNothing);
    });
  });

  testWidgets('placement: after «Змінити пароль», before the legal group', (
    tester,
  ) async {
    await _pump(tester, () => _AuthenticatedAs(UserRole.independentMaster));
    final double password = tester
        .getTopLeft(find.byKey(const Key('row-change-password')))
        .dy;
    final double blocked = tester.getTopLeft(_row).dy;
    final double legal = tester
        .getTopLeft(find.byKey(const Key('account-legal-section')))
        .dy;
    expect(password < blocked && blocked < legal, isTrue);
  });

  testWidgets('tap → pushes ${RouteNames.blockedClients}', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final GoRouter router = GoRouter(
      initialLocation: RouteNames.settings,
      routes: <RouteBase>[
        GoRoute(
          path: RouteNames.settings,
          builder: (_, _) => const SettingsScreen(),
        ),
        GoRoute(
          path: RouteNames.blockedClients,
          builder: (_, _) => const SizedBox(key: Key('blocked-stub')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpRoutedApp(
      router,
      overrides: _overrides(() => _AuthenticatedAs(UserRole.salonAdmin)),
    );
    await tester.pumpAndSettle();

    await tester.tap(_row);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('blocked-stub')), findsOne);
    // A push is an imperative match: `currentConfiguration.uri` keeps the
    // base location, so read the pushed match itself.
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      RouteNames.blockedClients,
    );
  });
}
