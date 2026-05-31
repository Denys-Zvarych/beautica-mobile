// Regression guard for the masterId UUID mismatch bug (2026-05-31).
//
// Root cause: serviceRepositoryProvider was extracting masterId from
// authProvider.value?.user.id (User UUID) instead of
// masterProfileProvider.value?.id (Master-row UUID). The backend's
// GET /masters/{masterId}/services endpoint queries by master-row UUID;
// passing a user UUID always returns [].
//
// This test verifies that serviceRepositoryProvider sends the master-row UUID
// to the API, NOT the user UUID. Any regression to the pre-fix wiring will
// cause getMasterServices to be called with the wrong UUID and this test fails.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class _MockServiceControllerApi extends Mock implements ServiceControllerApi {}

class _MockDio extends Mock implements Dio {}

// ── Stub notifier ───────────────────────────────────────────────────────────

/// Returns a master whose `.id` field is the master-row UUID ('master-row-uuid'),
/// deliberately different from any user UUID so the test can distinguish them.
class _StubMasterProfileNotifier extends MasterProfile {
  static const _master = Master(
    id: 'master-row-uuid', // master-table UUID — the correct one for API calls
    firstName: 'T',
    lastName: 'T',
    avgRating: 0,
    reviewCount: 0,
    type: MasterType.independentMaster,
  );

  @override
  Future<Master> build() async => _master;
}

// ── Tests ───────────────────────────────────────────────────────────────────

void main() {
  late _MockServiceControllerApi mockApi;
  late _MockDio mockDio;

  setUp(() {
    mockApi = _MockServiceControllerApi();
    mockDio = _MockDio();

    // Stub getMasterServices to return an empty list for any masterId.
    when(
      () => mockApi.getMasterServices(masterId: any(named: 'masterId')),
    ).thenAnswer(
      (_) async => Response(
        data: (ApiResponseListMasterServiceResponseBuilder()
              ..success = true
              ..data = ListBuilder<MasterServiceResponse>())
            .build(),
        statusCode: 200,
        requestOptions: RequestOptions(
          path: '/api/v1/masters/master-row-uuid/services',
        ),
      ),
    );
  });

  test(
    'serviceRepositoryProvider passes master-row UUID (not user UUID) to getMasterServices',
    () async {
      final container = ProviderContainer(
        overrides: [
          // Override masterProfileProvider with a stub that returns master-row UUID.
          masterProfileProvider.overrideWith(
            () => _StubMasterProfileNotifier(),
          ),
          // Override serviceApiProvider with mock so no real HTTP goes out.
          serviceApiProvider.overrideWithValue(mockApi),
          // Override dioProvider so HttpServiceRepository construction succeeds.
          dioProvider.overrideWithValue(mockDio),
        ],
      );
      addTearDown(container.dispose);

      // Wait for masterProfileProvider to resolve so serviceRepositoryProvider
      // gets the correct masterId before we call listMyServices.
      await container.read(masterProfileProvider.future);

      // listMyServices() delegates to getMasterServices(masterId: _masterId).
      await container.read(serviceRepositoryProvider).listMyServices();

      // The critical assertion: getMasterServices must have been called with
      // the master-row UUID ('master-row-uuid'), NOT with a user UUID.
      // Any regression that restores user.id as the masterId will fail here.
      verify(
        () => mockApi.getMasterServices(masterId: 'master-row-uuid'),
      ).called(1);

      // Confirm the user UUID was never sent (guards against dual-call bugs).
      verifyNever(
        () => mockApi.getMasterServices(masterId: 'user-uuid'),
      );
    },
  );
}
