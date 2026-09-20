// mobile-security MEDIUM (audit cycle 3, 2026-09-17) — `myRatingProvider`
// survived logout.
//
// The sibling of `test/features/passport/application/
// passport_session_boundary_test.dart` — read that file's header for the full
// argument; it applies here verbatim. The differences are only the endpoint
// (`GET /users/me/rating`) and the payload (the client's own aggregate rating
// and star distribution, as other providers rated THEM).
//
// KEYLESS `keepAlive` singleton, 5-minute TTL, a chain
// (`ratingRepositoryProvider` → `userApiProvider` → `dioProvider`) that
// watches nothing auth-shaped at any hop. Before the fix the next account
// signed in on the device opened «Мій рейтинг» and read the OUTGOING client's
// rating under their own name — a number they had no business seeing, and one
// that silently misrepresents their own standing.
//
// THE FIX under test is `ref.watch(authProvider.select(authUserIdOrNull))` in
// `myRating(Ref ref)`'s body.
//
// MUTATION that reddens this file and nothing else: delete that one line.
// `fetches` stays at 1 and client B reads client A's rating.

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
import 'package:beautica_mobile/features/rating/application/my_rating_notifier.dart';
import 'package:beautica_mobile/features/rating/data/rating_repository.dart';
import 'package:beautica_mobile/features/rating/domain/client_rating.dart';

import '../../../helpers/fakes/fake_secure_storage.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockRatingRepository extends Mock implements RatingRepository {}

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
      "GET /users/me/rating — client B never observes client A's "
      'keepAlive-cached rating (mobile-security MEDIUM regression guard, '
      '2026-09-17)', () async {
    final authRepo = _MockAuthRepository();
    final ratingRepo = _MockRatingRepository();
    final storage = FakeSecureStorage();
    await storage.writeRefreshToken(_tokensA.refreshToken);

    when(
      () => authRepo.refresh(_tokensA.refreshToken),
    ).thenAnswer((_) async => _tokensA);
    var meUser = _clientA;
    when(() => authRepo.me()).thenAnswer((_) async => meUser);
    when(() => authRepo.logout()).thenAnswer((_) async {});
    when(
      () => authRepo.login(email: _clientB.email, password: 'pw-b'),
    ).thenAnswer((_) async => (_clientB, _tokensB));

    // Manual counter — mocktail's `verify` CONSUMES matched interactions, so a
    // second `verify(...).called(n)` on the same filter would be vacuous.
    var fetches = 0;
    when(ratingRepo.getMyRating).thenAnswer((_) async {
      fetches++;
      // Distinguishable in the DATA, not only in the count: 4.8 over 12
      // reviews is client A, 3.1 over 4 is client B.
      return fetches == 1
          ? const ClientRating(avgRating: 4.8, reviewCount: 12)
          : const ClientRating(avgRating: 3.1, reviewCount: 4);
    });

    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: [
        authRepositoryProvider.overrideWith((_) => authRepo),
        secureStorageProvider.overrideWith((_) => storage),
        ratingRepositoryProvider.overrideWithValue(ratingRepo),
      ],
    );
    addTearDown(container.dispose);

    // ── 1. Client A's session resolves the rating — one real fetch.
    final AuthSession sessionA = await container.read(authProvider.future);
    expect(
      sessionA,
      const AuthSession.authenticated(user: _clientA, accessToken: 'access-a'),
    );

    final ClientRating ratingA = await container.read(myRatingProvider.future);
    expect(ratingA.avgRating, 4.8);
    expect(fetches, 1);

    // ── 2. Same session — served from the pin. Load-bearing: it proves the
    // cache is REAL, so step 4 cannot pass for the wrong reason.
    await container.read(myRatingProvider.future);
    expect(
      fetches,
      1,
      reason:
          'the keepAlive pin genuinely serves from memory — without this the '
          'next assertion would prove nothing',
    );

    // ── 3. The REAL logout → login round trip, within the 5-minute TTL.
    await container.read(authProvider.notifier).logout();
    meUser = _clientB;
    await container.read(authProvider.notifier).login(_clientB.email, 'pw-b');
    expect(
      container.read(authProvider).value,
      const AuthSession.authenticated(user: _clientB, accessToken: 'access-b'),
      reason: 'client B is genuinely signed in before the second read',
    );

    // ── 4. Client B's read must go to the network and return B's OWN rating.
    final ClientRating ratingB = await container.read(myRatingProvider.future);

    expect(
      fetches,
      2,
      reason:
          'the session boundary must EVICT this provider — serving client B '
          "from client A's pin shows one account another account's standing",
    );
    expect(
      ratingB.avgRating,
      3.1,
      reason:
          "client B must observe client B's OWN rating, never client A's "
          'keepAlive-cached one',
    );
    expect(ratingB.reviewCount, 4);
  });
}
