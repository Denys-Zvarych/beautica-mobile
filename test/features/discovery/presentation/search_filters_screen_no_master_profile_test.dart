// Regression test (Step 2.7 Rule 3) — CLIENT-search 403 decoupling.
//
// THE BUG THIS GUARDS
// -------------------
// A logged-in CLIENT entering the Пошук (Search) screen used to transitively
// call the MASTER-only `GET /api/v1/masters/me`. Cause: the category grid read
// `approvedCategoriesProvider`, which went through `serviceRepositoryProvider`,
// which eagerly watched `masterProfileProvider` → `MasterRepository.getMyProfile`
// → `GET /masters/me`. That endpoint 403s for a CLIENT, and Riverpod's backoff
// then auto-retried it ~4×, spamming the backend with 403s.
//
// THE FIX (lib/features/services/data/service_repository.dart)
// `approvedCategoriesProvider` now fetches DIRECTLY via
// `categoryRequestApiProvider.listApproved()` (Dio only — no master profile),
// so the CLIENT search path never touches `masterProfileProvider`.
//
// WHY A NEW FILE (not an edit to search_filters_screen_test.dart)
// The sibling widget test overrides `approvedCategoriesProvider` ITSELF, which
// short-circuits the real provider chain and therefore CANNOT catch the
// `/masters/me` coupling. This file deliberately does the opposite: it lets the
// REAL `approvedCategoriesProvider` run and stubs only its leaf dependency
// (`categoryRequestApiProvider`), then asserts the master leaf
// (`MasterRepository.getMyProfile`, i.e. `GET /masters/me`) is NEVER hit while
// the public `listApproved()` IS. Keeping it separate avoids weakening the
// existing state-coverage tests.
//
// RED-AGAINST-BUG
// Against the OLD code, mounting the client search grid resolves
// `approvedCategoriesProvider` → `serviceRepositoryProvider` → (watch)
// `masterProfileProvider` → `getMyProfile(...)`, so `verifyNever(getMyProfile)`
// would FAIL. With the fix it passes. The companion `verify(listApproved)`
// pins the NEW sourcing so a future "refactor back through the repository"
// regression is caught from both directions.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/discovery/presentation/search_filters_screen.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/category_rail.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/overflow_guard.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// The two leaves on either side of the (now severed) coupling:
//   • the PUBLIC approved-categories source the fixed provider now depends on,
//   • the MASTER-only profile source the buggy chain used to drag in.
class _MockCategoryRequestControllerApi extends Mock
    implements CategoryRequestControllerApi {}

class _MockMasterRepository extends Mock implements MasterRepository {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _testUser = User(
  id: 'u-client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Дмитро',
  lastName: 'Клієнт',
);

const _authenticated = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _testUser, accessToken: 'tok'),
);

// Stub authProvider so the keepAlive search controllers build cleanly and the
// session is settled-authenticated from the first frame (mirrors the sibling
// widget test's _FixedAuthNotifier).
class _FixedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    state = _authenticated;
    return const AuthSession.authenticated(user: _testUser, accessToken: 'tok');
  }
}

/// Builds the `GET /service-categories/approved` success envelope the real
/// `approvedCategoriesProvider` parses (same shape used in
/// service_repository_test.dart).
Response<ApiResponseListApprovedCategoryResponse> _approvedResponse(
  List<ApprovedCategoryResponse> items,
) {
  final envelope = ApiResponseListApprovedCategoryResponse(
    (b) => b
      ..data = ListBuilder<ApprovedCategoryResponse>(items)
      ..success = true,
  );
  return Response<ApiResponseListApprovedCategoryResponse>(
    data: envelope,
    requestOptions: RequestOptions(path: '/api/v1/service-categories/approved'),
    statusCode: 200,
  );
}

ApprovedCategoryResponse _approvedDto(String name, String displayName) =>
    (ApprovedCategoryResponseBuilder()
          ..name = name
          ..displayName = displayName)
        .build();

void main() {
  late _MockCategoryRequestControllerApi categoryApi;
  late _MockMasterRepository masterRepo;

  setUp(() {
    categoryApi = _MockCategoryRequestControllerApi();
    masterRepo = _MockMasterRepository();

    // The PUBLIC leaf returns two approved categories.
    when(() => categoryApi.listApproved()).thenAnswer(
      (_) async => _approvedResponse(<ApprovedCategoryResponse>[
        _approvedDto('NAILS', 'Манікюр'),
        _approvedDto('BROWS', 'Брови'),
      ]),
    );

    // The MASTER leaf is wired to THROW: a CLIENT calling `GET /masters/me` is
    // exactly the 403 the fix prevents, so the stub models that forbidden
    // outcome. If the buggy chain were still in place, the real
    // approvedCategoriesProvider would invoke this — `verifyNever` below fails
    // first on the unexpected interaction (and the thrown error would also
    // break the grid), pinning the regression from both directions.
    when(() => masterRepo.getMyProfile(any())).thenThrow(
      Exception('GET /masters/me must NOT be called on the CLIENT search path'),
    );
  });

  Future<void> pumpSearch(WidgetTester tester) async {
    installOverflowGuard();
    // Tall surface so the whole scrollable filter column lays out on-screen.
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        retry: beauticaProviderRetry,
        overrides: [
          authProvider.overrideWith(_FixedAuthNotifier.new),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          // CRITICAL: do NOT override approvedCategoriesProvider here — the
          // REAL provider must run so the master-coupling (if reintroduced)
          // would actually fire. Stub ONLY its leaf dependency.
          categoryRequestApiProvider.overrideWithValue(categoryApi),
          // The master leaf. If the buggy chain comes back, the real
          // approvedCategoriesProvider → serviceRepositoryProvider →
          // masterProfileProvider would call getMyProfile on THIS mock, and the
          // verifyNever below would fail.
          masterRepositoryProvider.overrideWithValue(masterRepo),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('uk'),
          home: ClientSearchScreen(),
        ),
      ),
    );
  }

  group('ClientSearchScreen — CLIENT 403 decoupling (regression)', () {
    testWidgets(
      'mounting the client search grid NEVER calls GET /masters/me; categories '
      'come from listApproved() and the grid renders',
      (tester) async {
        await pumpSearch(tester);
        await tester.pumpAndSettle();

        // The rail rendered the categories sourced from the PUBLIC leaf
        // (Variant A — CategoryRailTile replaced the old grid's ServiceTypeTile).
        expect(
          find.byType(CategoryRailTile),
          findsNWidgets(2),
          reason:
              'the real approvedCategoriesProvider must hydrate the rail '
              'from listApproved()',
        );
        expect(
          find.byKey(const Key('search_service_type_NAILS')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('search_service_type_BROWS')),
          findsOneWidget,
        );

        // NEW sourcing exercised: the public approved-categories endpoint WAS
        // hit (at least once — keepAlive controllers may rebuild).
        verify(
          () => categoryApi.listApproved(),
        ).called(greaterThanOrEqualTo(1));

        // THE INVARIANT: the master self-profile endpoint (`GET /masters/me`,
        // wrapped by MasterRepository.getMyProfile) was NEVER touched on the
        // CLIENT search path. Against the pre-fix code this fails; with the fix
        // it passes.
        verifyNever(() => masterRepo.getMyProfile(any()));
      },
    );

    testWidgets('selecting a category tile still does not reach /masters/me', (
      tester,
    ) async {
      await pumpSearch(tester);
      await tester.pumpAndSettle();

      // Interact with the grid (the realistic CLIENT action) and re-assert
      // the master leaf stays untouched through the selection rebuild.
      await tester.tap(find.byKey(const Key('search_service_type_NAILS')));
      await tester.pumpAndSettle();

      verifyNever(() => masterRepo.getMyProfile(any()));
    });
  });
}
