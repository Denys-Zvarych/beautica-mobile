// Phase 234 — unit tests for [HttpFavoriteRepository]'s wire-enum translation.
//
// WHY THIS FILE EXISTS
// --------------------
// `HttpFavoriteRepository._wireType` is the SINGLE point where the pure-Dart
// [FavoriteTargetType] becomes the generated `AddFavoriteRequestTargetTypeEnum`,
// and the invariant it protects — "the generated enum never escapes the data
// layer" — means no test above this layer can observe what actually goes on the
// wire. Until Phase 234 the repository had no test at all: the only favorites
// coverage was `favorite_toggle_notifier_test.dart`, which drives a FAKE
// repository and therefore cannot see the enum.
//
// That gap matters now that `SERVICE` exists. A `service` arm that mapped to
// `MASTER` (a plausible copy-paste, since the switch is exhaustive and the
// compiler only demands *an* arm, not the right one) would send a valid enum
// value the backend accepts, silently favouriting a master whose id is really a
// masterServiceId. Nothing else in the suite would go red.
//
// Strategy: mocktail-mock the generated [FavoriteControllerApi] and capture the
// argument. No real Dio, no ProviderScope, no widget tree.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFavoriteControllerApi extends Mock
    implements FavoriteControllerApi {}

class _FakeAddFavoriteRequest extends Fake implements AddFavoriteRequest {}

class _FakePageable extends Fake implements Pageable {}

Response<ApiResponseFavoriteResponse> _addOk() =>
    Response<ApiResponseFavoriteResponse>(
      requestOptions: RequestOptions(path: '/api/v1/favorites'),
      statusCode: 200,
    );

Response<void> _removeOk() => Response<void>(
  requestOptions: RequestOptions(path: '/api/v1/favorites'),
  statusCode: 204,
);

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeAddFavoriteRequest());
    // `any(named: 'pageable')` on the two list calls needs its own fallback —
    // mocktail cannot synthesise a non-nullable built_value argument.
    registerFallbackValue(_FakePageable());
  });

  late _MockFavoriteControllerApi api;
  late HttpFavoriteRepository repository;

  setUp(() {
    api = _MockFavoriteControllerApi();
    repository = HttpFavoriteRepository(api);
    when(
      () =>
          api.addFavorite(addFavoriteRequest: any(named: 'addFavoriteRequest')),
    ).thenAnswer((_) async => _addOk());
    when(
      () => api.removeFavorite(
        targetType: any(named: 'targetType'),
        targetId: any(named: 'targetId'),
      ),
    ).thenAnswer((_) async => _removeOk());
  });

  /// The `AddFavoriteRequest` the repository actually handed to the generated
  /// API on the single captured `addFavorite` call.
  AddFavoriteRequest capturedAddRequest() =>
      verify(
            () => api.addFavorite(
              addFavoriteRequest: captureAny(named: 'addFavoriteRequest'),
            ),
          ).captured.single
          as AddFavoriteRequest;

  group('HttpFavoriteRepository.add — wire enum translation', () {
    test('sends the SERVICE wire enum when targetType is service', () async {
      await repository.add(
        const FavoriteTarget(
          type: FavoriteTargetType.service,
          id: 'master-service-1',
        ),
      );

      final AddFavoriteRequest sent = capturedAddRequest();
      expect(sent.targetType, AddFavoriteRequestTargetTypeEnum.SERVICE);
      // The id must ride along untouched — a `service` favourite keys on the
      // masterServiceId, not the master.
      expect(sent.targetId, 'master-service-1');
    });

    // NEGATIVE CONTROLS. Without these, a `_wireType` that returned SERVICE for
    // everything would satisfy the case above. Each existing arm is pinned to a
    // DIFFERENT enum value so no single collapsed mapping can pass all three.
    test('still sends MASTER for a master target', () async {
      await repository.add(
        const FavoriteTarget(type: FavoriteTargetType.master, id: 'm1'),
      );

      expect(
        capturedAddRequest().targetType,
        AddFavoriteRequestTargetTypeEnum.MASTER,
      );
    });

    test('still sends SALON for a salon target', () async {
      await repository.add(
        const FavoriteTarget(type: FavoriteTargetType.salon, id: 's1'),
      );

      expect(
        capturedAddRequest().targetType,
        AddFavoriteRequestTargetTypeEnum.SALON,
      );
    });

    // Phase E — the salon booking flow's service-selection step favourites
    // against `service_definitions.id` (owner_type = SALON), a DIFFERENT id
    // space than `service` (master_services). Pinned separately so a
    // `salonService` arm that collapsed onto SERVICE (a plausible copy-paste
    // of the case above) would send the id under the wrong target type and
    // still pass every other test in this file.
    test('sends the SALON_SERVICE wire enum when targetType is '
        'salonService', () async {
      await repository.add(
        const FavoriteTarget(
          type: FavoriteTargetType.salonService,
          id: 'service-def-1',
        ),
      );

      final AddFavoriteRequest sent = capturedAddRequest();
      expect(sent.targetType, AddFavoriteRequestTargetTypeEnum.SALON_SERVICE);
      expect(sent.targetId, 'service-def-1');
    });
  });

  group('HttpFavoriteRepository.remove — wire enum translation', () {
    test(
      'sends the SERVICE wire enum when removing a service favorite',
      () async {
        await repository.remove(
          const FavoriteTarget(
            type: FavoriteTargetType.service,
            id: 'master-service-1',
          ),
        );

        // `remove` sends the enum's NAME as a query param, so the assertion is on
        // the string the backend will parse — the literal 'SERVICE', which is
        // what the regenerated `targetType` query enum now accepts.
        verify(
          () => api.removeFavorite(
            targetType: 'SERVICE',
            targetId: 'master-service-1',
          ),
        ).called(1);
      },
    );

    test(
      'still sends MASTER / SALON for the pre-existing target types',
      () async {
        await repository.remove(
          const FavoriteTarget(type: FavoriteTargetType.master, id: 'm1'),
        );
        await repository.remove(
          const FavoriteTarget(type: FavoriteTargetType.salon, id: 's1'),
        );

        verify(
          () => api.removeFavorite(targetType: 'MASTER', targetId: 'm1'),
        ).called(1);
        verify(
          () => api.removeFavorite(targetType: 'SALON', targetId: 's1'),
        ).called(1);
      },
    );

    test('sends the SALON_SERVICE wire enum when removing a salonService '
        'favorite', () async {
      await repository.remove(
        const FavoriteTarget(
          type: FavoriteTargetType.salonService,
          id: 'service-def-1',
        ),
      );

      // `remove` sends the enum's NAME as a query param — pinning the exact
      // string proves `.name` on the generated enum constant round-trips to
      // 'SALON_SERVICE' rather than some `.name`-derived mangling (e.g. a
      // hypothetical camelCase-to-upper transform would have produced
      // 'SALONSERVICE').
      verify(
        () => api.removeFavorite(
          targetType: 'SALON_SERVICE',
          targetId: 'service-def-1',
        ),
      ).called(1);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Phase 111 (mobile-qa) — the two LIST calls and their failure mapping.
  //
  // The `badCertificate` arm at `favorite_repository.dart:218` is a BACKLOG FIX
  // shipped in this phase and, until now, unpinned. It is also the one arm that
  // was wrong TWICE: `badCertificate` used to fall into `ServerFailure` (the
  // server never spoke, so there is no server to blame), and the first
  // correction folded it into `NetworkFailure` — whose copy tells the client to
  // check their connection, the exact wrong advice when the cause is an
  // intercepting proxy. This app PINS, so `badCertificate` fires only after the
  // chain failed against the pinned anchors.
  //
  // `thenThrow` is correct HERE and would be wrong one layer up (M13): this is
  // a plain class with no Riverpod retry in play, so there is no retry curve to
  // bypass. The notifier tier uses the async shape instead.
  // ─────────────────────────────────────────────────────────────────────────

  DioException dioError(DioExceptionType type, {int? status}) => DioException(
    requestOptions: RequestOptions(path: '/api/v1/favorites/masters'),
    type: type,
    response: status == null
        ? null
        : Response<void>(
            requestOptions: RequestOptions(path: '/api/v1/favorites/masters'),
            statusCode: status,
          ),
  );

  Response<ApiResponsePageResponseFavoriteMasterResponse> mastersEnvelope(
    PageResponseFavoriteMasterResponse? page,
  ) => Response<ApiResponsePageResponseFavoriteMasterResponse>(
    requestOptions: RequestOptions(path: '/api/v1/favorites/masters'),
    statusCode: 200,
    data: ApiResponsePageResponseFavoriteMasterResponse((
      ApiResponsePageResponseFavoriteMasterResponseBuilder b,
    ) {
      b.success = true;
      if (page != null) b.data.replace(page);
    }),
  );

  group('HttpFavoriteRepository.getFavoriteMasters — failure mapping', () {
    test('maps badCertificate to CertificateFailure, NOT NetworkFailure', () {
      when(
        () => api.listMasterFavorites(pageable: any(named: 'pageable')),
      ).thenThrow(dioError(DioExceptionType.badCertificate));

      expect(
        () => repository.getFavoriteMasters(),
        throwsA(isA<CertificateFailure>()),
      );
      // The negative half is load-bearing: `CertificateFailure` would satisfy
      // an `isA<Failure>` check no matter which arm produced it, and both wrong
      // answers this fix superseded are named here so neither can come back.
      expect(
        () => repository.getFavoriteMasters(),
        throwsA(isNot(isA<NetworkFailure>())),
      );
      expect(
        () => repository.getFavoriteMasters(),
        throwsA(isNot(isA<ServerFailure>())),
      );
    });

    test('a CertificateFailure is NOT transient — no automatic retry', () {
      // A pin miss is deterministic: the chain that was rejected is the chain
      // the next identical attempt meets, so an auto-retry burns the same ~38 s
      // spinner and rejects again. Asserted against the SHIPPED predicate, so
      // the repository's typed failure and the container's policy cannot drift.
      expect(beauticaProviderRetry(0, const CertificateFailure()), isNull);
    });

    test('maps a connection timeout to NetworkFailure', () {
      when(
        () => api.listMasterFavorites(pageable: any(named: 'pageable')),
      ).thenThrow(dioError(DioExceptionType.connectionTimeout));

      expect(
        () => repository.getFavoriteMasters(),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('maps 404 to NotFoundFailure and 500 to ServerFailure', () {
      when(
        () => api.listMasterFavorites(pageable: any(named: 'pageable')),
      ).thenThrow(dioError(DioExceptionType.badResponse, status: 404));
      expect(
        () => repository.getFavoriteMasters(),
        throwsA(isA<NotFoundFailure>()),
      );

      when(
        () => api.listMasterFavorites(pageable: any(named: 'pageable')),
      ).thenThrow(dioError(DioExceptionType.badResponse, status: 500));
      expect(
        () => repository.getFavoriteMasters(),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('no raw DioException ever escapes the data layer', () {
      when(
        () => api.listMasterFavorites(pageable: any(named: 'pageable')),
      ).thenThrow(dioError(DioExceptionType.unknown));

      expect(
        () => repository.getFavoriteMasters(),
        throwsA(isNot(isA<DioException>())),
      );
    });
  });

  group('HttpFavoriteRepository.getFavoriteMasters — envelope handling', () {
    test('a MISSING envelope is a broken payload → ServerFailure', () {
      when(
        () => api.listMasterFavorites(pageable: any(named: 'pageable')),
      ).thenAnswer((_) async => mastersEnvelope(null));

      expect(
        () => repository.getFavoriteMasters(),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('an ABSENT rows list is an EMPTY favourites list, not an error', () {
      // The distinction the repository draws deliberately: the envelope
      // arrived, so the server answered — it just has nothing saved to report.
      when(
        () => api.listMasterFavorites(pageable: any(named: 'pageable')),
      ).thenAnswer(
        (_) async => mastersEnvelope(
          PageResponseFavoriteMasterResponse(
            (PageResponseFavoriteMasterResponseBuilder b) => b
              ..page = 0
              ..size = 20
              ..totalElements = 0
              ..totalPages = 0,
          ),
        ),
      );

      expect(repository.getFavoriteMasters(), completion(isEmpty));
    });

    test('asks for the page size the endpoint itself defaults to', () {
      // Stated explicitly rather than relied on, so a backend-side
      // `@PageableDefault` change cannot silently resize the client's list.
      when(
        () => api.listMasterFavorites(pageable: any(named: 'pageable')),
      ).thenAnswer((_) async => mastersEnvelope(null));

      expect(() => repository.getFavoriteMasters(), throwsA(isA<Failure>()));

      final Pageable sent =
          verify(
                () => api.listMasterFavorites(
                  pageable: captureAny(named: 'pageable'),
                ),
              ).captured.single
              as Pageable;
      expect(sent.page, 0);
      expect(sent.size, HttpFavoriteRepository.pageSize);
      expect(HttpFavoriteRepository.pageSize, 20);
    });
  });

  group('FavoriteTargetType — enum surface', () {
    test('declares exactly master, salon, service and salonService', () {
      // Guards the domain enum against silently gaining a member that
      // `_wireType` cannot translate. The switch there is exhaustive with no
      // default, so a new member is a COMPILE error — this test documents the
      // intended surface so a `default:` added to silence that error is caught
      // in review rather than shipping an untranslated type.
      expect(FavoriteTargetType.values, <FavoriteTargetType>[
        FavoriteTargetType.master,
        FavoriteTargetType.salon,
        FavoriteTargetType.service,
        FavoriteTargetType.salonService,
      ]);
    });
  });
}
