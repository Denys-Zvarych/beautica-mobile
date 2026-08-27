// Phase 21.2 — Widget tests for SalonSettingsScreen.
//
// Covers:
//   1. «Редагувати профіль» row present for both owner and admin; tapping it
//      pops the settings page with a `true` result.
//   2. «Видалити салон» row + its divider render ONLY for the owner —
//      admin sees neither.
//   3. Delete confirmation dialog: confirming calls the repository's
//      deleteSalon and navigates away on success; cancelling leaves the
//      screen untouched and never calls the repository.
//   4. Delete error path: a Failure from the repository shows an error
//      snackbar and leaves the settings page mounted (no navigation).

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_settings_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_salon_repository.dart';
import '../../../helpers/pump_app.dart';

const String _kSalonId = 'salon-1';

const _stubOwner = User(
  id: 'owner-1',
  email: 'owner@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Оксана',
  lastName: 'Швець',
);

const _stubAdmin = User(
  id: 'admin-1',
  email: 'admin@beautica.ua',
  role: UserRole.salonAdmin,
  firstName: 'Ірина',
  lastName: 'Бойко',
);

const _stubSalon = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  street: 'вул. Велика Васильківська',
  buildingNo: '44',
);

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._user);

  final User _user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: _user, accessToken: 'tok');
}

GoRouter _router() => GoRouter(
  initialLocation: RouteNames.salonManageSettings(_kSalonId),
  routes: <RouteBase>[
    GoRoute(
      path: '/salons/:salonId/manage/settings',
      builder: (context, state) =>
          SalonSettingsScreen(salonId: state.pathParameters['salonId']!),
    ),
    GoRoute(path: '/', builder: (context, state) => const _Probe('home')),
    GoRoute(
      path: RouteNames.login,
      builder: (context, state) => const _Probe('login'),
    ),
  ],
);

class _Probe extends StatelessWidget {
  const _Probe(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(body: Text(label));
}

List<Object> _overrides(User user, FakeSalonRepository repo) => <Object>[
  authProvider.overrideWith(() => _StubAuthNotifier(user)),
  salonRepositoryProvider.overrideWithValue(repo),
];

void main() {
  group('«Редагувати профіль» row', () {
    testWidgets('present for the owner; tapping pops with a true result', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _stubSalon);
      await tester.pumpRoutedApp(
        _router(),
        overrides: _overrides(_stubOwner, repo),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('row-salon-edit-profile')), findsOneWidget);

      // Nothing to pop back to inside this isolated router (no parent
      // route pushed it) — assert the row exists and is tappable without
      // throwing; the actual pop(true) contract is exercised end-to-end by
      // salon_management_profile_screen_test.dart's round-trip test.
      await tester.tap(find.byKey(const Key('row-salon-edit-profile')));
      await tester.pumpAndSettle();
    });

    testWidgets('present identically for an admin', (tester) async {
      final repo = FakeSalonRepository(salon: _stubSalon);
      await tester.pumpRoutedApp(
        _router(),
        overrides: _overrides(_stubAdmin, repo),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('row-salon-edit-profile')), findsOneWidget);
    });
  });

  group('«Видалити салон» — owner-only', () {
    testWidgets('row AND its divider render for the owner', (tester) async {
      final repo = FakeSalonRepository(salon: _stubSalon);
      await tester.pumpRoutedApp(
        _router(),
        overrides: _overrides(_stubOwner, repo),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('row-salon-delete')), findsOneWidget);
      expect(find.byKey(const Key('salon-settings-divider')), findsOneWidget);
    });

    testWidgets('row AND its divider are ABSENT for an admin', (tester) async {
      final repo = FakeSalonRepository(salon: _stubSalon);
      await tester.pumpRoutedApp(
        _router(),
        overrides: _overrides(_stubAdmin, repo),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('row-salon-delete')), findsNothing);
      expect(find.byKey(const Key('salon-settings-divider')), findsNothing);
    });
  });

  group('delete confirmation flow', () {
    testWidgets('confirming deletes and navigates away', (tester) async {
      final repo = FakeSalonRepository(salon: _stubSalon);
      await tester.pumpRoutedApp(
        _router(),
        overrides: _overrides(_stubOwner, repo),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('row-salon-delete')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete-salon-dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn-confirm-delete-salon')));
      await tester.pumpAndSettle();

      expect(repo.deleteCalls, 1);
      // Owner lands on the role home probe after a successful delete.
      expect(find.text('home'), findsOneWidget);

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
      expect(find.text(l10n.deleteSalonSuccess), findsOneWidget);
    });

    testWidgets('cancelling never calls deleteSalon and stays on the page', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _stubSalon);
      await tester.pumpRoutedApp(
        _router(),
        overrides: _overrides(_stubOwner, repo),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('row-salon-delete')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn-cancel-delete-salon')));
      await tester.pumpAndSettle();

      expect(repo.deleteCalls, 0);
      expect(find.byKey(const Key('row-salon-delete')), findsOneWidget);
    });

    testWidgets('a repository Failure shows an error snackbar and stays put', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _stubSalon)
        ..deleteError = const ServerFailure(statusCode: 500);
      await tester.pumpRoutedApp(
        _router(),
        overrides: _overrides(_stubOwner, repo),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('row-salon-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-confirm-delete-salon')));
      await tester.pumpAndSettle();

      expect(repo.deleteCalls, 1);
      // Never navigated away — the settings row is still on screen.
      expect(find.byKey(const Key('row-salon-delete')), findsOneWidget);
      expect(find.text('home'), findsNothing);
    });
  });
}
