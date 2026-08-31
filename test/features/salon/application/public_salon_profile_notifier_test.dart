// Unit tests for [publicSalonProfileProvider]'s NARROWED auth watch.
//
// mobile-perf LOW (2026-09-01). The loader opens with an auth-boundary watch
// so its 5-minute `ref.keepAlive()` cache is torn down on a session flip
// (logout, or login as a different account). That watch used to be a bare
// `ref.watch(authProvider)`, which cannot tell a session flip apart from a
// silent token refresh: `AuthNotifier.setAccessToken` is called by
// `refresh_interceptor.dart` after every 401 → refresh and re-emits
// `Authenticated` with the SAME user and a new accessToken, so every refresh
// discarded a live cache entry and refired `GET /salons/{id}` +
// `GET /salons/{id}/masters` under the user.
//
// The two tests here are a PAIR and neither is meaningful alone:
//   • the token-only re-emission must be INERT — a bare watch fails this;
//   • a real identity change must STILL rebuild — a `.select` narrowed to a
//     constant (or to the wrong field) passes the first test while silently
//     deleting the eviction the watch exists for.
//
// Pure Dart — no widget tree. Mirrors
// `public_master_profile_notifier_test.dart`'s harness (that file owns the
// happy-path / ParallelWaitError-unwrap coverage for the sibling loader).

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSalonRepository extends Mock implements SalonRepository {}

/// A settled authenticated CLIENT session a test can flip AFTER `build()`, so
/// the pair below can push a token-only re-emission and a real identity change
/// separately. `state =` is only reachable from inside an [AsyncNotifier]
/// subclass, hence this stub rather than an external poke.
class _ControllableAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(
      id: 'client-1',
      email: 'client@beautica.ua',
      role: UserRole.client,
    ),
    accessToken: 'test-token',
  );

  void emit(AuthSession session) => state = AsyncData<AuthSession>(session);
}

const String _kSalonId = 'salon-1';

const _salon = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  description: 'Затишний салон краси.',
  street: 'вул. Велика Васильківська',
  buildingNo: '44',
);

const _masters = <SalonMasterSummary>[
  SalonMasterSummary(
    masterId: 'master-1',
    firstName: 'Олена',
    lastName: 'Ковальчук',
    type: MasterType.salonMaster,
  ),
];

void main() {
  late _MockSalonRepository repo;

  setUp(() {
    repo = _MockSalonRepository();
  });

  ProviderContainer makeContainer(_ControllableAuthNotifier auth) {
    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: [
        authProvider.overrideWith(() => auth),
        salonRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  void stubHappyPath() {
    when(() => repo.getSalonById(_kSalonId)).thenAnswer((_) async => _salon);
    when(
      () => repo.getSalonMasters(_kSalonId),
    ).thenAnswer((_) async => _masters);
  }

  group('publicSalonProfile — narrowed authProvider watch', () {
    test('a silent token refresh (same user id, new accessToken) does NOT '
        'refetch the salon or the masters rail', () async {
      stubHappyPath();

      final auth = _ControllableAuthNotifier();
      final container = makeContainer(auth);
      // Settle auth BEFORE the loader first builds, so the loading→data
      // transition cannot itself mark the loader dirty and defeat `.called(1)`.
      await container.read(authProvider.future);
      final sub = container.listen(
        publicSalonProfileProvider(_kSalonId),
        (_, _) {},
      );
      addTearDown(sub.close);
      await container.read(publicSalonProfileProvider(_kSalonId).future);
      verify(() => repo.getSalonById(_kSalonId)).called(1);
      verify(() => repo.getSalonMasters(_kSalonId)).called(1);

      // Exactly what `refresh_interceptor.dart` does after a 401 → refresh.
      container.read(authProvider.notifier).setAccessToken('token-rotated-2');
      await pumpEventQueue();

      verifyNever(() => repo.getSalonById(any()));
      verifyNever(() => repo.getSalonMasters(any()));
      expect(
        container.read(authProvider).value,
        isA<Authenticated>()
            .having(
              (Authenticated a) => a.accessToken,
              'accessToken',
              'token-rotated-2',
            )
            .having((Authenticated a) => a.user.id, 'user.id', 'client-1'),
        reason:
            'sanity: the session really did re-emit, with a NEW token and the '
            'SAME user — so the no-refetch assertions above are about the '
            '.select narrowing, not about setAccessToken having no-opped',
      );
    });

    test('a real identity change (different user id) DOES rebuild', () async {
      stubHappyPath();

      final auth = _ControllableAuthNotifier();
      final container = makeContainer(auth);
      await container.read(authProvider.future);
      final sub = container.listen(
        publicSalonProfileProvider(_kSalonId),
        (_, _) {},
      );
      addTearDown(sub.close);
      await container.read(publicSalonProfileProvider(_kSalonId).future);
      verify(() => repo.getSalonById(_kSalonId)).called(1);
      verify(() => repo.getSalonMasters(_kSalonId)).called(1);

      auth.emit(
        const AuthSession.authenticated(
          user: User(
            id: 'client-2',
            email: 'other@beautica.ua',
            role: UserRole.client,
          ),
          accessToken: 'test-token',
        ),
      );
      await pumpEventQueue();
      await container.read(publicSalonProfileProvider(_kSalonId).future);

      verify(() => repo.getSalonById(_kSalonId)).called(1);
      verify(() => repo.getSalonMasters(_kSalonId)).called(1);
    });
  });
}
