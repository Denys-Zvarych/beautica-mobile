// mobile-security MEDIUM-1 regression — logout must empty the shared media
// disk cache (2026-07-24, authored by mobile-qa for the consolidated fix round).
//
// ## THE DEFECT THIS PINS
//
// The shared media loader (core/media/beautica_image.dart) disk-caches remote
// avatars/photos for 7 days through `beauticaImageCacheManager`. `logout()`
// wipes secure storage, the register draft, the day-timeline PII cache and the
// screen-protection latch — but does NOT purge that media cache. So after a
// user signs out (or is force-logged-out on a failed refresh) the cached FACES
// of the clients that account viewed survive on disk for up to a week, readable
// by the next account to use the device. Client photos are PII; a sign-out must
// not leave them behind.
//
// ## STATUS: GREEN — RESOLVED (fix shipped in f35b8a3)
//
// `AuthNotifier.logout()` now purges the media cache through the OVERRIDE-AWARE
// active manager (`_activeMediaCacheManager.emptyCache()` in beautica_image.dart),
// NOT the raw `beauticaImageCacheManager` directly, so this test passes against
// the current tree. It remains as a regression pin: if a future change drops
// the purge from `logout()`, this goes red again.
//
// WHY THE OVERRIDE-AWARE PATH IS PART OF THE CONTRACT: the real
// `beauticaImageCacheManager` is backed by path_provider + sqflite and CANNOT
// run under `flutter test`. The only seam a test can observe the purge through
// is `debugMediaCacheManager` — the same seam every other media test uses. A
// fix that calls `beauticaImageCacheManager.emptyCache()` directly would both
// be untestable here AND throw `MissingPluginException` the first time it runs
// in a widget test. So "purge the ACTIVE manager" is the testable, correct
// shape — this test asserts exactly that.

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// A cache manager that records emptyCache() — the purge the fix must trigger.
//
// Deliberately NOT the shared FakeMediaCacheManager (which throws on every
// method but getFileStream): logout does not fetch, so getFileStream is never
// hit; emptyCache is the ONE method under test and it must record, not throw.
// ---------------------------------------------------------------------------
class _SpyMediaCacheManager implements BaseCacheManager {
  int emptyCacheCalls = 0;

  @override
  Future<void> emptyCache() async {
    emptyCacheCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '_SpyMediaCacheManager.${invocation.memberName} is not wired for this test',
  );
}

// ---------------------------------------------------------------------------
// Fixtures (mirrors logout_flow_test.dart)
// ---------------------------------------------------------------------------

const _testUser = User(
  id: 'u1',
  email: 'master@beautica.test',
  role: UserRole.independentMaster,
  firstName: 'Test',
  lastName: 'User',
);

const _testTokens = AuthTokens(
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
);

Future<(ProviderContainer, FakeAuthRepository)>
_makeAuthenticatedContainer() async {
  final storage = FakeSecureStorage();
  await storage.writeRefreshToken('stored-refresh');

  final repo = FakeAuthRepository()
    ..refreshResult = _testTokens
    ..meResult = _testUser;

  final container = ProviderContainer(
    overrides: [
      secureStorageProvider.overrideWith((_) => storage),
      authRepositoryProvider.overrideWith((_) => repo),
    ],
  );
  addTearDown(container.dispose);

  // Background restore flips state to Authenticated — drain it.
  await container.read(authProvider.future);
  await pumpEventQueue();

  return (container, repo);
}

void main() {
  late _SpyMediaCacheManager spy;

  setUp(() {
    spy = _SpyMediaCacheManager();
    debugMediaCacheManager = spy;
  });

  tearDown(() {
    debugMediaCacheManager = null;
  });

  group('AuthNotifier.logout — media cache purge (MEDIUM-1)', () {
    test('logout() empties the shared media disk cache so cached client faces do '
        'not survive sign-out [RED until the purge is added]', () async {
      final (container, _) = await _makeAuthenticatedContainer();
      expect(container.read(authProvider).value, isA<Authenticated>());
      expect(
        spy.emptyCacheCalls,
        0,
        reason: 'precondition: nothing has purged the media cache yet',
      );

      await container.read(authProvider.notifier).logout();
      // Tolerate a fire-and-forget purge (unawaited) as well as an awaited one.
      await pumpEventQueue();

      expect(
        spy.emptyCacheCalls,
        greaterThanOrEqualTo(1),
        reason:
            'logout() must purge the active media cache manager — the '
            'client photos this account viewed are PII cached on disk for 7 '
            'days and must not survive sign-out (mobile-security MEDIUM-1). '
            'Route the purge through _activeMediaCacheManager.emptyCache() '
            'so it respects debugMediaCacheManager and never touches sqflite '
            'in tests.',
      );
    });

    test('the purge still runs when the server-side logout call fails — the '
        'local wipe (tokens, draft, media) is unconditional', () async {
      final storage = FakeSecureStorage();
      await storage.writeRefreshToken('stored-refresh');
      final repo = FakeAuthRepository()
        ..refreshResult = _testTokens
        ..meResult = _testUser
        ..logoutThrows = true; // server revocation 4xx — tolerated

      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWith((_) => storage),
          authRepositoryProvider.overrideWith((_) => repo),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authProvider.future);
      await pumpEventQueue();

      await container.read(authProvider.notifier).logout();
      await pumpEventQueue();

      expect(
        container.read(authProvider).value,
        equals(const AuthSession.unauthenticated()),
      );
      expect(
        spy.emptyCacheCalls,
        greaterThanOrEqualTo(1),
        reason:
            'like the token wipe, the media purge must be best-effort and '
            'unconditional: a failed server revocation must not leave the '
            'previous account\'s cached faces on disk.',
      );
    });
  });
}
