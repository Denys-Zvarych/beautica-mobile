// Phase 384 debug follow-up — `salonManagementProfileProvider`'s 60 s timed
// keepAlive vs. the shared test container.
//
// The production cache window (`kSalonManagementProfileCacheWindow`) arms a
// real 60 s `Timer` whenever the provider's last watcher leaves (including
// flutter_test's own teardown unmount). A test that owns its container through
// `makeTestContainer` disposes it in `addTearDown` — AFTER flutter_test's
// pending-timer invariant — so that timer failed every real-router owner/admin
// test that reached the salon management surface. The window is now read from
// `salonManagementProfileCacheWindowProvider`, which `makeTestContainer`
// defaults to `Duration.zero` (no keepAlive, no timer) unless the caller
// overrides it itself.
//
// Two cases, both on the REAL `appRouterProvider` as SALON_OWNER:
//   1. default container: shell → «Профіль» (owner master mode) → «‹ Салон»
//      ends with NO pending timer (the flutter_test invariant IS the
//      assertion) and — proof the zero default reached the provider — the
//      returning shell refetches (2 reads).
//   2. the caller's own 60 s override is NOT swallowed by the default: the
//      same trip reads the salon exactly ONCE.
//
// The trip runs on a NON-primary owned salon on purpose: owner master mode's
// `_SalonMasterTabsShell` (app_router.dart, phase 381) holds its own listener
// on the PRIMARY salon's entry, so a primary-salon trip never drops the last
// watcher and could not tell a 60 s window from a zero one.
//
// Layer: Widget (real router, faked providers + FakeSalonRepository).

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
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/owner_own_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_salon_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/test_container.dart';

const String _kOwnerUserId = 'user-owner-U';
const String _kOwnerMasterRowId = 'master-row-owner-M';

/// The owner's PRIMARY salon — the one owner master mode is scoped to.
const String _kPrimarySalonId = 'salon-primary-P';

/// The NON-primary owned salon whose shell the trip leaves and returns to.
const String _kSalonId = 'salon-second-S';

const Salon _kPrimarySalon = Salon(
  id: _kPrimarySalonId,
  name: 'Primary Salon',
  isPrimary: true,
);
const Salon _kSalon = Salon(id: _kSalonId, name: 'Second Salon');

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

class _OwnerMasterProfile extends MasterProfile {
  @override
  Future<Master> build() async => const Master(
    id: _kOwnerMasterRowId,
    firstName: 'Олена',
    lastName: 'Ковальчук',
    reviewCount: 0,
    type: MasterType.salonOwner,
    salonId: _kPrimarySalonId,
  );
}

class _SettledMySalons extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[_kPrimarySalon, _kSalon];
}

/// [FakeSalonRepository] that counts `GET /salons/{id}` and
/// `GET /salons/{id}/staff` for [_kSalonId] only (the master-mode shell's own
/// primary-salon read is not under test).
class _CountingSalonRepository extends FakeSalonRepository {
  _CountingSalonRepository() : super(salon: _kSalon);

  int getSalonByIdCalls = 0;
  int staffCalls = 0;

  @override
  Future<Salon> getSalonById(String salonId) async {
    if (salonId == _kSalonId) getSalonByIdCalls++;
    return salonId == _kPrimarySalonId ? _kPrimarySalon : _kSalon;
  }

  @override
  Future<List<SalonStaffMember>> getSalonStaff(String salonId) {
    if (salonId == _kSalonId) staffCalls++;
    return super.getSalonStaff(salonId);
  }
}

void main() {
  setUp(
    () => AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    ),
  );
  tearDown(AppStartTime.resetForTest);

  /// Mounts the real router as SALON_OWNER on the salon shell, walks
  /// «Профіль» → owner master mode → «‹ Салон», and returns the repository.
  Future<_CountingSalonRepository> ownerTripThroughMasterMode(
    WidgetTester tester, {
    List<Object> extraOverrides = const <Object>[],
  }) async {
    final _CountingSalonRepository repo = _CountingSalonRepository();
    final ProviderContainer container = makeTestContainer(
      retry: (_, _) => null,
      overrides: <Object>[
        ...extraOverrides,
        authProvider.overrideWith(_FixedAuthNotifier.new),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        mySalonsProvider.overrideWith(_SettledMySalons.new),
        salonRepositoryProvider.overrideWithValue(repo),
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
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk', 'UA'),
        ),
      ),
    );
    await container.read(authProvider.future);
    await tester.pumpAndSettle();

    router.go(RouteNames.salonShell(_kSalonId));
    await tester.pumpAndSettle();
    expect(find.byType(SalonShellScreen), findsOneWidget);
    expect(repo.getSalonByIdCalls, 1, reason: 'the shell loads the salon once');

    // «Профіль» — the owner leaves the shell for owner master mode.
    await tester.tap(find.byKey(const Key('salon-nav-tile-3')));
    await tester.pumpAndSettle();
    expect(find.byType(OwnerOwnProfileScreen), findsOneWidget);
    expect(find.byType(SalonShellScreen), findsNothing);

    // «‹ Салон» — back to the LAST-VISITED salon's shell (the second one).
    await tester.tap(find.byKey(const Key('owner-master-mode-back')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SalonShellScreen>(find.byType(SalonShellScreen)).salonId,
      _kSalonId,
    );
    return repo;
  }

  testWidgets('makeTestContainer default: the master-mode trip ends with NO '
      'pending cache-window timer, and the zero window means the returning '
      'shell refetches', (tester) async {
    final _CountingSalonRepository repo = await ownerTripThroughMasterMode(
      tester,
    );

    expect(
      repo.getSalonByIdCalls,
      2,
      reason:
          'makeTestContainer defaults the cache window to zero — no keepAlive, '
          'so leaving the shell disposes the entry and «‹ Салон» refetches',
    );
    expect(repo.staffCalls, 2);
    // No explicit timer drain: flutter_test's pending-timer invariant (run
    // BEFORE the container's addTearDown dispose) is the assertion.
  });

  testWidgets('a caller\'s own 60 s window override is NOT swallowed by the '
      'default: the master-mode trip reads the salon exactly ONCE', (
    tester,
  ) async {
    final _CountingSalonRepository repo = await ownerTripThroughMasterMode(
      tester,
      extraOverrides: <Object>[
        salonManagementProfileCacheWindowProvider.overrideWithValue(
          kSalonManagementProfileCacheWindow,
        ),
      ],
    );

    expect(
      repo.getSalonByIdCalls,
      1,
      reason:
          'inside the 60 s window «‹ Салон» must reuse the cached entry — a '
          'second read means makeTestContainer overrode the caller\'s window',
    );
    expect(repo.staffCalls, 1);

    // The window is armed when the LAST watcher leaves — flutter_test's own
    // teardown unmount would arm it after this body, i.e. pending at the
    // invariant check. Leave explicitly, then drain the real window (this
    // test opted into the production window on purpose).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(
      kSalonManagementProfileCacheWindow + const Duration(seconds: 1),
    );
  });
}
