// Phase 21.13 QA follow-up — truth-table coverage for
// `SettingsScreen._showDeleteSalonRow`.
//
// WHY THIS FILE EXISTS
// ---------------------
// The owner-only «Видалити салон» row added to the shared account page
// (`settings_screen.dart`) renders only when THREE conjuncts all hold:
//   1. `widget.showDeleteSalon` (caller-supplied navigation state)
//   2. `widget.salonId != null` (caller-supplied navigation state)
//   3. the current `authProvider` session resolves to an `Authenticated`
//      user whose role is `UserRole.salonOwner` (session-derived)
// Before this file, NOTHING exercised this truth table — a `grep` for
// `showDeleteSalon` / `row-delete-salon` in `test/` returned zero hits, and
// no existing caller passes `showDeleteSalon: true` yet (that lands with the
// unbuilt Phase 21.9). Every case below asserts on the RENDERED row AND its
// divider (`find.byKey`), never on a constructor field, per this repo's
// vacuous-widget-field-assertion trap.
//
// Layer: Widget (`tester.pumpApp` — no GoRouter needed; every navigation
// call inside `SettingsScreen` lives behind a tap handler this file never
// triggers).

import 'dart:async';

import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/settings/presentation/settings_screen.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/pump_app.dart';

const String _kSalonId = 'salon-21-13';

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
/// `AsyncValue<AuthSession>` (no prior `.value`) deliberately, rather than
/// relying on an accidental unresolved-by-omission provider state.
class _LoadingForeverNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() => Completer<AuthSession>().future;
}

Finder get _rowFinder => find.byKey(const Key('row-delete-salon'));
Finder get _dividerFinder =>
    find.byKey(const Key('account-settings-delete-salon-divider'));

Future<void> _pump(
  WidgetTester tester, {
  required AuthNotifier Function() authNotifier,
  String? salonId = _kSalonId,
  bool showDeleteSalon = true,
}) async {
  await tester.pumpApp(
    SettingsScreen(salonId: salonId, showDeleteSalon: showDeleteSalon),
    overrides: [
      authProvider.overrideWith(authNotifier),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
    ],
  );
  await tester.pumpAndSettle();
}

void main() {
  group('SettingsScreen — owner-only delete-salon row truth table', () {
    testWidgets(
      'showDeleteSalon:true + non-null salonId + SALON_OWNER session → '
      'row AND divider render',
      (tester) async {
        await _pump(
          tester,
          authNotifier: () => _AuthenticatedAs(_userWith(UserRole.salonOwner)),
        );

        expect(_rowFinder, findsOneWidget);
        expect(_dividerFinder, findsOneWidget);
      },
    );

    for (final role in [
      UserRole.client,
      UserRole.salonAdmin,
      UserRole.salonMaster,
      UserRole.independentMaster,
    ]) {
      testWidgets(
        'showDeleteSalon:true + non-null salonId + ${role.name} session → '
        'row AND divider hidden',
        (tester) async {
          await _pump(
            tester,
            authNotifier: () => _AuthenticatedAs(_userWith(role)),
          );

          expect(_rowFinder, findsNothing);
          expect(_dividerFinder, findsNothing);
        },
      );
    }

    testWidgets(
      'showDeleteSalon:true + non-null salonId + Unauthenticated session → '
      'row AND divider hidden',
      (tester) async {
        await _pump(tester, authNotifier: _UnauthenticatedNotifier.new);

        expect(_rowFinder, findsNothing);
        expect(_dividerFinder, findsNothing);
      },
    );

    testWidgets(
      'showDeleteSalon:true + non-null salonId + AsyncLoading (no prior '
      'value) session → row AND divider hidden (fails closed)',
      (tester) async {
        await _pump(tester, authNotifier: _LoadingForeverNotifier.new);

        expect(_rowFinder, findsNothing);
        expect(_dividerFinder, findsNothing);
      },
    );

    testWidgets(
      'showDeleteSalon:true + NULL salonId + SALON_OWNER session → row '
      'AND divider hidden (never a delete button with nothing to delete)',
      (tester) async {
        await _pump(
          tester,
          authNotifier: () => _AuthenticatedAs(_userWith(UserRole.salonOwner)),
          salonId: null,
        );

        expect(_rowFinder, findsNothing);
        expect(_dividerFinder, findsNothing);
      },
    );

    testWidgets('showDeleteSalon:false (the default, every existing caller) + '
        'non-null salonId + SALON_OWNER session → row AND divider hidden', (
      tester,
    ) async {
      await _pump(
        tester,
        authNotifier: () => _AuthenticatedAs(_userWith(UserRole.salonOwner)),
        showDeleteSalon: false,
      );

      expect(_rowFinder, findsNothing);
      expect(_dividerFinder, findsNothing);
    });
  });
}
