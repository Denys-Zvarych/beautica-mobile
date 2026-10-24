// Phase 416 (mobile-security INFO) — the salon service catalogue survived
// logout.
//
// `salonServiceCatalogProvider(salonId)` is keyed on the salon id alone and
// pins itself with `ref.keepAlive()` for 5 minutes; its chain
// (`salonRepositoryProvider` -> dio) holds no auth watch. On a shared tablet a
// DIFFERENT owner/admin signing in to the SAME salon would be served the
// outgoing session's catalogue from memory. `AuthNotifier.logout()` bare
// -invalidates the family; THIS TEST IS THAT LINE'S ONLY GUARD (outcome-based,
// same recipe as `salon_effective_schedule_cross_session_isolation_test.dart`,
// whose header explains why no live listener is held across the boundary).
//
// Mutation: deleting `ref.invalidate(salonServiceCatalogProvider)` from
// `auth_notifier.dart` turns this RED (fetch count stays 1).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_service_catalog_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';

import '../../../helpers/fakes/fake_secure_storage.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockSalonRepository extends Mock implements SalonRepository {}

const String _salonId = 'salon-velvet';

const User _ownerA = User(
  id: 'owner-a',
  email: 'owner-a@beautica.ua',
  role: UserRole.salonOwner,
);
const User _ownerB = User(
  id: 'owner-b',
  email: 'owner-b@beautica.ua',
  role: UserRole.salonOwner,
);
const AuthTokens _tokensA = AuthTokens(
  accessToken: 'access-a',
  refreshToken: 'refresh-a',
);
const AuthTokens _tokensB = AuthTokens(
  accessToken: 'access-b',
  refreshToken: 'refresh-b',
);

List<SalonServiceCategoryEntry> _catalogue(String serviceName) =>
    <SalonServiceCategoryEntry>[
      SalonServiceCategoryEntry(
        category: 'nails',
        displayName: 'Нігті',
        count: 1,
        services: <SalonCatalogService>[
          SalonCatalogService(
            id: 's1',
            name: serviceName,
            durationLabel: '60 хв',
            priceDisplay: '500 ₴',
          ),
        ],
      ),
    ];

void main() {
  test('logout then a DIFFERENT owner on the SAME salon forces a FRESH '
      'catalogue fetch — never the outgoing session\'s pinned one', () async {
    final authRepo = _MockAuthRepository();
    final salonRepo = _MockSalonRepository();
    final storage = FakeSecureStorage();
    await storage.writeRefreshToken(_tokensA.refreshToken);

    when(
      () => authRepo.refresh(_tokensA.refreshToken),
    ).thenAnswer((_) async => _tokensA);
    var meUser = _ownerA;
    when(() => authRepo.me()).thenAnswer((_) async => meUser);
    when(() => authRepo.logout()).thenAnswer((_) async {});
    when(
      () => authRepo.login(email: _ownerB.email, password: 'pw-b'),
    ).thenAnswer((_) async => (_ownerB, _tokensB));

    var fetches = 0;
    when(() => salonRepo.getSalonServiceCatalog(_salonId)).thenAnswer((
      _,
    ) async {
      fetches++;
      return _catalogue(fetches == 1 ? 'Манікюр A' : 'Манікюр B');
    });

    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: [
        authRepositoryProvider.overrideWith((_) => authRepo),
        secureStorageProvider.overrideWith((_) => storage),
        salonRepositoryProvider.overrideWithValue(salonRepo),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authProvider.future);
    final pageA = await container.read(
      salonServiceCatalogProvider(_salonId).future,
    );
    expect(pageA.single.services.single.name, 'Манікюр A');
    expect(fetches, 1);

    // The pin is real (so step 4's fetch cannot be the vacuous-negative).
    await container.read(salonServiceCatalogProvider(_salonId).future);
    expect(fetches, 1, reason: 'keepAlive serves the same key from memory');

    await container.read(authProvider.notifier).logout();
    meUser = _ownerB;
    await container.read(authProvider.notifier).login(_ownerB.email, 'pw-b');

    final pageB = await container.read(
      salonServiceCatalogProvider(_salonId).future,
    );
    expect(fetches, 2, reason: 'the session boundary must evict the family');
    expect(pageB.single.services.single.name, 'Манікюр B');
  });
}
