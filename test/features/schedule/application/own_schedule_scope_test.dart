// Phase 312 — Tests for [ownScheduleScopeProvider]
// (lib/features/schedule/application/own_schedule_scope.dart).
//
// THE PIN this file exists for: the role check must run BEFORE the provider
// ever watches [masterProfileProvider] — `GET /masters/me` is gated
// `hasAnyRole('SALON_MASTER', 'INDEPENDENT_MASTER', 'SALON_OWNER')`
// (`MasterController.java:109`), so a SALON_ADMIN session reaching that watch
// at all would 403 in production, on a screen that looks like it merely
// failed to load. The mutation this guards against: "role check moved after
// the profile watch → `verifyNever(getMe)` fires for an admin" — i.e. if the
// ordering regresses, this file's admin/client/owner cases start calling
// `MasterRepository.getMyProfile`, and `verifyNever` below goes red.
//
// Strategy: override [masterRepositoryProvider] with a mocktail mock so a
// call to `getMyProfile` is directly observable, and [authProvider] with a
// fixed session per role. Pure Dart — no widget tree.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/schedule/application/own_schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

class _MockMasterRepository extends Mock implements MasterRepository {}

const String _kUserId = 'own-scope-user-1';
const String _kMasterRowId = 'own-scope-master-row-1';

const Master _kMaster = Master(
  id: _kMasterRowId,
  firstName: 'Тест',
  lastName: 'Майстер',
  avgRating: null,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

User _userWith(UserRole role) => User(
  id: _kUserId,
  email: '${role.name}@beautica.ua',
  role: role,
  firstName: 'Тест',
  lastName: 'Юзер',
);

class _AuthenticatedAs extends AuthNotifier {
  _AuthenticatedAs(this.role);
  final UserRole role;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: _userWith(role), accessToken: 'tok');
}

ProviderContainer _makeContainer(UserRole role, MasterRepository repo) {
  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: [
      authProvider.overrideWith(() => _AuthenticatedAs(role)),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
      masterRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  late _MockMasterRepository repo;

  setUp(() {
    repo = _MockMasterRepository();
    when(() => repo.getMyProfile(any())).thenAnswer((_) async => _kMaster);
  });

  group('ownScheduleScopeProvider — roles WITH their own master row', () {
    for (final UserRole role in <UserRole>[
      UserRole.independentMaster,
      UserRole.salonMaster,
    ]) {
      test('${role.name} resolves ScheduleScope.own(masterId: <resolved>), '
          'and DOES call GET /masters/me', () async {
        final container = _makeContainer(role, repo);
        await container.read(authProvider.future);
        // `ownScheduleScopeProvider` is a plain SYNC provider that watches
        // the ASYNC `masterProfileProvider` internally — await ITS future
        // first (the thing that actually resolves), then re-read the sync
        // scope provider, which recomputes reactively once its dependency
        // settles.
        await container.read(masterProfileProvider.future);
        final ScheduleScope scope = container.read(ownScheduleScopeProvider);

        expect(scope, isA<OwnScheduleScope>());
        expect(scope.masterId, _kMasterRowId);
        verify(() => repo.getMyProfile(_kUserId)).called(1);
      });
    }
  });

  group(
    'ownScheduleScopeProvider — THE PIN: roles WITHOUT their own master row '
    'never reach GET /masters/me',
    () {
      for (final UserRole role in <UserRole>[
        UserRole.salonOwner,
        UserRole.salonAdmin,
        UserRole.client,
      ]) {
        test('${role.name} resolves ScheduleScope.own(masterId: \'\') '
            'WITHOUT ever calling GET /masters/me — verifyNever(getMyProfile) '
            'is the mutation-critical assertion', () async {
          final container = _makeContainer(role, repo);
          await container.read(authProvider.future);

          final ScheduleScope scope = container.read(ownScheduleScopeProvider);

          expect(scope, isA<OwnScheduleScope>());
          expect(scope.masterId, '');
          verifyNever(() => repo.getMyProfile(any()));
        });
      }
    },
  );

  test('a settled Unauthenticated session resolves ScheduleScope.own('
      'masterId: \'\') without calling GET /masters/me', () async {
    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: [
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        masterRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    // No stored token → AuthNotifier's own bootstrap settles to
    // Unauthenticated (FakeSecureStorage starts empty).
    await container.read(authProvider.future);

    final ScheduleScope scope = container.read(ownScheduleScopeProvider);

    expect(scope, isA<OwnScheduleScope>());
    expect(scope.masterId, '');
    verifyNever(() => repo.getMyProfile(any()));
  });
}
