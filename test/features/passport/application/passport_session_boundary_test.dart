// mobile-security MEDIUM (audit cycle 3, 2026-09-17) — `passportProvider`
// survived logout.
//
// Same bug class as the `salonEffectiveScheduleProvider` leak closed earlier
// the same day (`test/features/schedule/presentation/
// salon_effective_schedule_cross_session_isolation_test.dart`), but strictly
// WORSE, and the difference is the key:
//
//   * `salonEffectiveScheduleProvider` is keyed on `(salonId, ScheduleRange)`.
//     It collides only for two accounts that manage the SAME salon.
//   * `passportProvider` is KEYLESS. There is exactly one member for every
//     account that ever signs in on the device, so the collision is total —
//     client B lands on client A's member unconditionally.
//
// The payload is `GET /clients/me/passport`: visit history, favourite
// districts/cities, budget band, reviews-written count, member-since year.
// `keepAlive` + a 5-minute TTL held it across the boundary, and its whole
// chain (`passportRepositoryProvider` → `clientApiProvider` → `dioProvider`)
// watches nothing auth-shaped at any hop — so nothing rebuilt it and nothing
// evicted it.
//
// THE FIX under test is `ref.watch(authProvider.select(authUserIdOrNull))` in
// `passport(Ref ref)`'s body — the `booked_days_notifier.dart:163` idiom.
// Self-healing (it evicts on logout, on login AND on an account switch),
// and it needs no `auth_notifier.dart` edit, so it records no back-edge into
// `authProvider` and carries no `CircularDependencyError` risk.
//
// MUTATION that reddens this file and nothing else: delete that one `ref.watch`
// line. `fetches` stays at 1 and client B reads client A's passport.
//
// No live listener is held across the boundary, deliberately: the realistic
// shape is the client tapping «Вийти» with the passport page unmounted, which
// leaves the member pinned ONLY by its own `keepAlive()`. That is exactly the
// state the finding describes.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/passport/application/passport_notifier.dart';
import 'package:beautica_mobile/features/passport/data/passport_repository.dart';
import 'package:beautica_mobile/features/passport/domain/passport.dart';

import '../../../helpers/fakes/fake_secure_storage.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockPassportRepository extends Mock implements PassportRepository {}

const User _clientA = User(
  id: 'client-a',
  email: 'client-a@beautica.ua',
  role: UserRole.client,
  firstName: 'Оля',
  lastName: 'Коваль',
);

const User _clientB = User(
  id: 'client-b',
  email: 'client-b@beautica.ua',
  role: UserRole.client,
  firstName: 'Ірина',
  lastName: 'Бондар',
);

const AuthTokens _tokensA = AuthTokens(
  accessToken: 'access-a',
  refreshToken: 'refresh-a',
);

const AuthTokens _tokensB = AuthTokens(
  accessToken: 'access-b',
  refreshToken: 'refresh-b',
);

void main() {
  test('a logout followed by a DIFFERENT client signing in forces a FRESH '
      "GET /clients/me/passport — client B never observes client A's "
      'keepAlive-cached passport (mobile-security MEDIUM regression guard, '
      '2026-09-17)', () async {
    final authRepo = _MockAuthRepository();
    final passportRepo = _MockPassportRepository();
    final storage = FakeSecureStorage();
    await storage.writeRefreshToken(_tokensA.refreshToken);

    when(
      () => authRepo.refresh(_tokensA.refreshToken),
    ).thenAnswer((_) async => _tokensA);
    // `GET /auth/me` answers whoever is currently signing in — the cold-start
    // restore resolves client A, and `login()` re-reads it for client B.
    var meUser = _clientA;
    when(() => authRepo.me()).thenAnswer((_) async => meUser);
    when(() => authRepo.logout()).thenAnswer((_) async {});
    when(
      () => authRepo.login(email: _clientB.email, password: 'pw-b'),
    ).thenAnswer((_) async => (_clientB, _tokensB));

    // A manual counter, not a second `verify(...).called(n)` — mocktail's
    // `verify` CONSUMES the interactions it matches, so asserting the same
    // filter twice would see "no matching calls" the second time regardless of
    // what actually happened.
    var fetches = 0;
    when(passportRepo.getMyPassport).thenAnswer((_) async {
      fetches++;
      // The two sessions differ in the DATA, not only in the call count — so a
      // regression that produced the right count for the wrong reason cannot
      // slip through. 2019 is client A's member-since year, 2024 client B's.
      return Passport.empty(memberSinceYear: fetches == 1 ? 2019 : 2024);
    });

    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: [
        authRepositoryProvider.overrideWith((_) => authRepo),
        secureStorageProvider.overrideWith((_) => storage),
        passportRepositoryProvider.overrideWithValue(passportRepo),
      ],
    );
    addTearDown(container.dispose);

    // ── 1. Client A's session resolves the passport — one real fetch, then
    // keepAlive-pinned for 5 minutes.
    final AuthSession sessionA = await container.read(authProvider.future);
    expect(
      sessionA,
      const AuthSession.authenticated(user: _clientA, accessToken: 'access-a'),
    );

    final Passport passportA = await container.read(passportProvider.future);
    expect(passportA.memberSinceYear, 2019);
    expect(fetches, 1);

    // ── 2. Same session, same (absent) key — served from the pin. Load-bearing:
    // it proves the cache is REAL, so step 4's "a fetch happened" cannot be
    // explained away by the member never having been cached at all.
    await container.read(passportProvider.future);
    expect(
      fetches,
      1,
      reason:
          'the keepAlive pin genuinely serves from memory — without this the '
          'next assertion would prove nothing',
    );

    // ── 3. Client A signs out; client B signs in, well within the 5-minute
    // TTL. The REAL `logout()`/`login()`, not a hand-rolled equivalent.
    await container.read(authProvider.notifier).logout();
    meUser = _clientB;
    await container.read(authProvider.notifier).login(_clientB.email, 'pw-b');
    expect(
      container.read(authProvider).value,
      const AuthSession.authenticated(user: _clientB, accessToken: 'access-b'),
      reason: 'client B is genuinely signed in before the second read',
    );

    // ── 4. Client B's read must go to the network and return B's OWN passport.
    final Passport passportB = await container.read(passportProvider.future);

    expect(
      fetches,
      2,
      reason:
          'the session boundary must EVICT this provider — serving client B '
          "from client A's pin is a visit-history read with no wire call and "
          'no server re-check',
    );
    expect(
      passportB.memberSinceYear,
      2024,
      reason:
          "client B must observe client B's OWN passport, never client A's "
          'keepAlive-cached one',
    );
  });
}
