// Phase 379 (24.1b) — mobile-qa: the `/owner/master/*` ShellRoute mounts
// `_SalonMasterTabsShell(role: UserRole.salonOwner)`, which must scope
// `serviceTargetProvider` to the OWNER's own `SalonMasterTarget` (salonId +
// `masters` ROW id off `/masters/me`) — the scope 380's «Послуги» tab reads.
//
// Nothing else in 379 consumes that scope, so without this file the
// `role: UserRole.salonOwner` argument could be dropped (falling back to the
// SALON_MASTER default) with every other test still green. Mutation-verified:
// removing the argument turns the first case RED.
//
// Layer: Widget (real `appRouterProvider`, faked providers, no network).
//
// Remount probe (2026-10-06): the page is not remounted when `/masters/me`
// resolves — the ShellRoute child is a GlobalKey-ed Navigator (probed:
// target null before, SalonMasterTarget after, identical State). Since the
// phase-379 perf fix the shell no longer flips bare-`child` ->
// `ProviderScope(child)` at all: once the role matches it always wraps,
// overriding with `null` until the ids resolve.

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/owner_own_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/presentation/owner_own_profile_screen.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_target.dart';
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

/// Session userId, masters ROW id and salon id are deliberately distinct, so
/// a target carrying the userId (or a wrong salon) cannot pass.
const String _kOwnerUserId = 'user-owner-U';
const String _kOwnerMasterRowId = 'master-row-owner-M';
const String _kSalonId = 'salon-owner-S';

const User _kOwner = User(
  id: _kOwnerUserId,
  email: 'owner@beautica.test',
  role: UserRole.salonOwner,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  hasMasterProfile: true,
);

class _FixedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _kOwner, accessToken: 'token');
}

/// `/masters/me` for the owner: their SALON_OWNER row.
class _OwnerMasterProfile extends MasterProfile {
  @override
  Future<Master> build() async {
    return const Master(
      id: _kOwnerMasterRowId,
      firstName: 'Олена',
      lastName: 'Ковальчук',
      reviewCount: 0,
      type: MasterType.salonOwner,
      salonId: _kSalonId,
    );
  }
}

class _SettledMySalons extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[
    Salon(id: _kSalonId, name: 'Test Salon', isPrimary: true),
  ];
}

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

void main() {
  setUp(
    () => AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    ),
  );
  tearDown(AppStartTime.resetForTest);

  Future<GoRouter> pumpOwnerRouter(WidgetTester tester) async {
    final ProviderContainer container = makeTestContainer(
      retry: (_, _) => null,
      overrides: <Object>[
        authProvider.overrideWith(_FixedAuthNotifier.new),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        mySalonsProvider.overrideWith(_SettledMySalons.new),
        masterProfileProvider.overrideWith(_OwnerMasterProfile.new),
        ownerOwnProfileProvider.overrideWith(
          (ref) async => (owner: _kOwner, master: null),
        ),
        approvedCategoriesProvider.overrideWith(
          (ref) async => const <ServiceCategoryOption>[],
        ),
      ],
    );
    final GoRouter router = container.read(appRouterProvider);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _RouterApp(router: router),
      ),
    );
    await container.read(authProvider.future);
    await tester.pumpAndSettle();
    return router;
  }

  ServiceTarget? targetSeenByProfile(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(OwnerOwnProfileScreen)),
      ).read(serviceTargetProvider);

  testWidgets('SALON_OWNER at /owner/master/profile: the page is scoped to the '
      'owner\'s OWN SalonMasterTarget (salonId + masters ROW id, never the '
      'session userId)', (tester) async {
    final GoRouter router = await pumpOwnerRouter(tester);

    router.go(RouteNames.ownerMasterProfile);
    await tester.pumpAndSettle();

    expect(find.byType(OwnerOwnProfileScreen), findsOneWidget);
    expect(
      targetSeenByProfile(tester),
      const ServiceTarget.salonMaster(
        salonId: _kSalonId,
        masterId: _kOwnerMasterRowId,
      ),
      reason:
          'the /owner/master/* shell must mount _SalonMasterTabsShell with '
          'role: salonOwner — the SALON_MASTER default would hand the owner '
          'bare `child` and 380\'s «Послуги» would read the independent '
          'catalogue',
    );
  });

  testWidgets('CONTROL: the same owner on the stand-alone /profile/owner (no '
      'master-mode shell) gets NO SalonMasterTarget scope', (tester) async {
    final GoRouter router = await pumpOwnerRouter(tester);

    router.go(RouteNames.ownerOwnProfile);
    await tester.pumpAndSettle();

    expect(find.byType(OwnerOwnProfileScreen), findsOneWidget);
    expect(targetSeenByProfile(tester), isNot(isA<SalonMasterTarget>()));
  });
}
