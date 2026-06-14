// Regression guard for the owner services-list wiring.
//
// History: the original guard (2026-05-31) protected against a masterId UUID
// mismatch bug — serviceRepositoryProvider once extracted masterId from the
// User UUID instead of the Master-row UUID, which made the old public
// GET /masters/{masterId}/services endpoint always return [].
//
// Phase 16.9 repointed listMyServices() to the authenticated owner endpoint
// GET /api/v1/independent-masters/me/services (generated getMyServices()),
// which derives the master from the JWT principal and takes NO masterId path
// parameter. The masterId is therefore no longer sent on the wire — but the
// provider still WATCHES masterProfileProvider so the repository is (re)built
// once the profile resolves and so listMyServices() does not fire on an
// unauthenticated session.
//
// This test now verifies two things:
//   1. listMyServices() delegates to the authenticated owner endpoint
//      (getMyServices), NOT the public getMasterServices(masterId: …).
//   2. The provider waits for the master profile to resolve before the call
//      succeeds (the readiness-guard contract).

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

/// Returns a master whose `.id` field is the master-row UUID ('master-row-uuid').
/// The owner endpoint no longer sends this on the wire, but a non-empty value
/// is still required to pass the repository's readiness guard.
class _StubMasterProfileNotifier extends MasterProfile {
  static const _master = Master(
    id: 'master-row-uuid',
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

    // Stub the authenticated owner endpoint to return an empty list.
    when(() => mockApi.getMyServices()).thenAnswer(
      (_) async => Response(
        data:
            (ApiResponseListMasterServiceResponseBuilder()
                  ..success = true
                  ..data = ListBuilder<MasterServiceResponse>())
                .build(),
        statusCode: 200,
        requestOptions: RequestOptions(
          path: '/api/v1/independent-masters/me/services',
        ),
      ),
    );
  });

  test(
    'serviceRepositoryProvider.listMyServices delegates to the authenticated '
    'owner endpoint (getMyServices), never the public getMasterServices',
    () async {
      final container = ProviderContainer(
        overrides: [
          masterProfileProvider.overrideWith(
            () => _StubMasterProfileNotifier(),
          ),
          serviceApiProvider.overrideWithValue(mockApi),
          dioProvider.overrideWithValue(mockDio),
        ],
      );
      addTearDown(container.dispose);

      // Wait for masterProfileProvider to resolve so serviceRepositoryProvider
      // passes its readiness guard before we call listMyServices.
      await container.read(masterProfileProvider.future);

      // listMyServices() delegates to the JWT-derived owner endpoint.
      await container.read(serviceRepositoryProvider).listMyServices();

      // The owner endpoint (drafts included) must have been called exactly once.
      verify(() => mockApi.getMyServices()).called(1);

      // The public, draft-excluding endpoint must NOT be used for the owner's
      // own list (guards against a regression back to the public path).
      verifyNever(
        () => mockApi.getMasterServices(masterId: any(named: 'masterId')),
      );
    },
  );
}
