// mobile-security MEDIUM-2 (2026-07-20) — regression coverage for
// `masterServiceCatalogProvider`'s explicit session-identity watch.
//
// Before this fix, this `keepAlive` provider's only protection against
// serving a previous account's service names across a logout was INCIDENTAL:
// `ref.watch(serviceRepositoryProvider)` transitively watches
// `masterProfileProvider`, which watches `authProvider`. This test isolates
// [masterServiceCatalogProvider] from that cascade entirely — overriding
// [serviceRepositoryProvider] with a fixed mocktail value, which by
// construction watches nothing — so the ONLY thing that can force a refetch
// on an identity change is [masterServiceCatalogProvider]'s OWN explicit
// `authProvider.select(...)` watch. Before the fix, this exact setup would
// have served master-1's catalogue to master-2 with no second fetch — the
// leak the fix closes.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';

class _MockServiceRepository extends Mock implements ServiceRepository {}

const User _master1 = User(
  id: 'master-1',
  email: 'master1@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Оля',
  lastName: 'Коваль',
);

const User _master2 = User(
  id: 'master-2',
  email: 'master2@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Ірина',
  lastName: 'Бондар',
);

class _MutableAuthNotifier extends AuthNotifier {
  _MutableAuthNotifier(this._initial);

  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;

  void setSession(AuthSession session) =>
      state = AsyncData<AuthSession>(session);
}

MasterService _service({required String id, required String name}) =>
    MasterService(
      id: id,
      serviceDefId: 'def-$id',
      name: name,
      durationMinutes: 60,
      priceMin: 500,
    );

Future<({ProviderContainer container, _MutableAuthNotifier auth})>
_containerWithAuth(ServiceRepository repo, AuthSession initialAuth) async {
  final auth = _MutableAuthNotifier(initialAuth);
  final container = ProviderContainer(
    overrides: <Object>[
      // Deliberately a fixed value, not the real provider — see the file
      // header for why this isolates the fix's own watch from the cascade
      // it used to depend on incidentally.
      serviceRepositoryProvider.overrideWithValue(repo),
      authProvider.overrideWith(() => auth),
    ].cast(),
  );
  addTearDown(container.dispose);
  await container.read(authProvider.future);
  return (container: container, auth: auth);
}

void main() {
  late _MockServiceRepository repo;

  setUp(() {
    repo = _MockServiceRepository();
  });

  test(
    "a logout followed by a different account logging in forces a FRESH "
    "fetch — master-1's catalogue is never served to master-2, even with "
    "serviceRepositoryProvider itself watching nothing (HIGH-class "
    'regression guard, mirrors bookedDaysProvider / bookingsDayProvider)',
    () async {
      when(repo.listMyServices).thenAnswer(
        (_) async => <MasterService>[_service(id: 's1', name: 'Манікюр')],
      );
      final result = await _containerWithAuth(
        repo,
        const AuthSession.authenticated(user: _master1, accessToken: 'token-1'),
      );

      final List<MasterService> master1Catalogue = await result.container.read(
        masterServiceCatalogProvider.future,
      );
      expect(master1Catalogue.single.name, 'Манікюр');

      result.auth.setSession(const AuthSession.unauthenticated());
      when(repo.listMyServices).thenAnswer(
        (_) async => <MasterService>[_service(id: 's2', name: 'Педикюр')],
      );
      result.auth.setSession(
        const AuthSession.authenticated(user: _master2, accessToken: 'token-2'),
      );

      final List<MasterService> master2Catalogue = await result.container.read(
        masterServiceCatalogProvider.future,
      );

      verify(repo.listMyServices).called(2);
      expect(master2Catalogue.single.name, 'Педикюр');
      expect(
        master2Catalogue.any((MasterService s) => s.name == 'Манікюр'),
        isFalse,
        reason:
            "master-1's service names must not leak into master-2's "
            'catalogue',
      );
    },
  );

  test('a silent token refresh for the SAME account does NOT evict the '
      'cache — proves the watch is narrowed to the user id, not the whole '
      'session', () async {
    when(repo.listMyServices).thenAnswer(
      (_) async => <MasterService>[_service(id: 's1', name: 'Манікюр')],
    );
    final result = await _containerWithAuth(
      repo,
      const AuthSession.authenticated(user: _master1, accessToken: 'token-1'),
    );

    await result.container.read(masterServiceCatalogProvider.future);

    result.auth.setSession(
      const AuthSession.authenticated(
        user: _master1,
        accessToken: 'token-1-refreshed',
      ),
    );

    await result.container.read(masterServiceCatalogProvider.future);

    verify(repo.listMyServices).called(1);
  });
}
