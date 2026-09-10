// Phase 5.1 — Unit tests for [HttpServiceRepository].
//
// Strategy:
//   All tests mock [ServiceControllerApi] and/or [Dio] with mocktail.
//   [HttpServiceRepository] is constructed directly so there is no Riverpod
//   overhead — pure Dart unit tests.
//
// Coverage:
//   1.  listMyServices() — empty list
//   2.  listMyServices() — populated list; mapper applied (name, price, duration)
//   3.  create()         — happy path; correct request fields forwarded
//   4.  create()         — price: -1 → ArgumentError (local validation; no network call)
//   5.  deactivate()     — correct API method called; idempotent (2× → no throw)
//   6.  update()         — happy path; PATCH issued, domain object returned (no second GET)
//   7.  empty masterId   — listMyServices() throws UnauthorizedFailure without network call
//   7b. _assertAuthenticated D4 matrix (phase 314) — FIVE named rows over the
//       (ServiceTarget, masterId-empty) combinations: the phase doc's four,
//       plus row 4b, which splits the salon arm's `salonId.isEmpty ||
//       masterId.isEmpty` into two independently load-bearing halves.
//       Mutation-verified 2026-09-09: reducing the salon arm to
//       `masterId.isEmpty` reddens row 4 ALONE, reducing it to
//       `salonId.isEmpty` reddens row 4b ALONE, and neutering the null arm
//       reddens row 2 ALONE — no row masks another. A single "salon mode does
//       not throw" test would hide row 2, the independent-master arm a careless
//       "just make salon mode work" refactor deletes.
//
//       Row 5 — "salon target on an UNAUTHENTICATED session" — deliberately
//       does NOT live here. HttpServiceRepository holds no session object, and
//       row 3 exists precisely to allow `_masterId` to be empty in salon mode,
//       so the case is only expressible where target and session meet: see
//       `service_repository_provider_test.dart`'s `row 5`. That row is LIVE —
//       unskipped and green since the phase-314 audit pass landed the
//       `sessionUserId` readiness predicate on the salon arm (D4 revision). Do
//       not read it as an inert placeholder.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_target.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

/// The path segments Dio ACTUALLY puts on the wire for [rawPath].
///
/// Dio sends `RequestOptions.uri`, i.e. `Uri.parse(baseUrl + path)
/// .normalizePath()` (`dio-5.9.2/lib/src/options.dart:642`) — NOT the string
/// handed to `Dio.delete/get/post`. `normalizePath` REMOVES dot-segments
/// (RFC 3986 §5.2.4) and `Uri.encodeComponent` does not escape `.`, so a
/// corpus asserted against the raw argument string is structurally incapable
/// of failing on a bare `..` (mobile-security S2, phase-316 audit cycle 1).
/// Note [Uri.pathSegments] DECODES, so an injected value is compared verbatim
/// — what is being pinned is that it is ONE element, not that it looks
/// encoded.
List<String> _wireSegments(String rawPath) =>
    Uri.parse('http://localhost:8080$rawPath').normalizePath().pathSegments;

// ── Mocks ──────────────────────────────────────────────────────────────────

class _MockServiceControllerApi extends Mock implements ServiceControllerApi {}

class _MockCategoryRequestControllerApi extends Mock
    implements CategoryRequestControllerApi {}

class _MockServiceCatalogControllerApi extends Mock
    implements ServiceCatalogControllerApi {}

/// Only exercised by the phase 315 D1 salon-target read-dispatch group below
/// — every other test in this file uses a real `Dio()` because it never
/// leaves the generated-client (mocked `serviceApi`) path.
class _MockDio extends Mock implements Dio {}

// ── Helpers ─────────────────────────────────────────────────────────────────

const _masterId = 'master-abc';
const _serviceId = 'svc-001';

/// A valid service-type id. Service type is MANDATORY on create (backend
/// `@NotNull` on `CreateServiceDefinitionRequest.serviceTypeId`), so every
/// create fixture that is expected to reach the mapper/network must carry one.
const _serviceTypeId = 'stype-777';

/// The service-definition id used for update/deactivate (distinct from the
/// assignment id [_serviceId]). The backend keys
/// `PATCH/DELETE /api/v1/services/{serviceDefId}` on this id.
const _serviceDefId = 'def-001';
// Phase 16.9: listMyServices() now hits the authenticated owner endpoint
// (no masterId path param). Used only as the mock RequestOptions.path.
const _listPath = '/api/v1/independent-masters/me/services';

/// Builds a [ServiceDefinitionResponse] with sensible defaults.
/// Phase 5.6: uses priceType/priceMin/priceMax instead of basePrice.
ServiceDefinitionResponse _buildDef({
  String id = 'def-001',
  String name = 'Манікюр',
  String? description,
  int baseDurationMinutes = 60,
  ServiceDefinitionResponsePriceTypeEnum priceType =
      ServiceDefinitionResponsePriceTypeEnum.FIXED,
  num priceMin = 500,
  num? priceMax,
  String? priceDisplay,
  int? bufferMinutesAfter,
  bool isActive = true,
}) =>
    (ServiceDefinitionResponseBuilder()
          ..id = id
          ..name = name
          ..description = description
          ..baseDurationMinutes = baseDurationMinutes
          ..priceType = priceType
          ..priceMin = priceMin
          ..priceMax = priceMax
          ..priceDisplay = priceDisplay ?? '${priceMin.toInt()} ₴'
          ..bufferMinutesAfter = bufferMinutesAfter
          ..isActive = isActive)
        .build();

/// Builds a [MasterServiceResponse] with sensible defaults.
MasterServiceResponse _buildMasterServiceDto({
  String id = _serviceId,
  String masterId = _masterId,
  ServiceDefinitionResponse? serviceDefinition,
  num? effectivePrice,
  int? effectiveDurationMinutes,
  bool isActive = true,
}) {
  final def = serviceDefinition ?? _buildDef();
  return (MasterServiceResponseBuilder()
        ..id = id
        ..masterId = masterId
        ..serviceDefinition.replace(def)
        ..effectivePrice = effectivePrice
        ..effectiveDurationMinutes = effectiveDurationMinutes
        ..isActive = isActive)
      .build();
}

/// Wraps a list of [MasterServiceResponse] DTOs in the API envelope.
Response<ApiResponseListMasterServiceResponse> _listResponse(
  List<MasterServiceResponse> items,
) {
  final envelope = ApiResponseListMasterServiceResponse(
    (b) => b
      ..data = ListBuilder<MasterServiceResponse>(items)
      ..success = true,
  );
  return Response<ApiResponseListMasterServiceResponse>(
    data: envelope,
    requestOptions: RequestOptions(path: _listPath),
    statusCode: 200,
  );
}

/// Wraps a single [MasterServiceResponse] DTO in the API envelope.
Response<ApiResponseMasterServiceResponse> _singleResponse(
  MasterServiceResponse dto,
) {
  final envelope = ApiResponseMasterServiceResponse(
    (b) => b
      ..data.replace(dto)
      ..success = true,
  );
  return Response<ApiResponseMasterServiceResponse>(
    data: envelope,
    requestOptions: RequestOptions(
      path: '/api/v1/independent-masters/me/services',
    ),
    statusCode: 201,
  );
}

/// Wraps a single [ServiceDefinitionResponse] DTO in the API envelope returned
/// by `PATCH /api/v1/services/{serviceDefId}` (updateServiceDefinition).
Response<ApiResponseServiceDefinitionResponse> _updateResponse(
  ServiceDefinitionResponse dto,
) {
  final envelope = ApiResponseServiceDefinitionResponse(
    (b) => b
      ..data.replace(dto)
      ..success = true,
  );
  return Response<ApiResponseServiceDefinitionResponse>(
    data: envelope,
    requestOptions: RequestOptions(path: '/api/v1/services/$_serviceDefId'),
    statusCode: 200,
  );
}

// ── Test suite ───────────────────────────────────────────────────────────────

void main() {
  late _MockServiceControllerApi serviceApi;
  late _MockCategoryRequestControllerApi categoryApi;
  late _MockServiceCatalogControllerApi catalogApi;
  late HttpServiceRepository repository;

  setUp(() {
    serviceApi = _MockServiceControllerApi();
    categoryApi = _MockCategoryRequestControllerApi();
    catalogApi = _MockServiceCatalogControllerApi();
    repository = HttpServiceRepository(
      serviceApi: serviceApi,
      categoryApi: categoryApi,
      catalogApi: catalogApi,
      dio: Dio(),
      masterId: _masterId,
    );
    // Register fallback values required by mocktail for named-typed matchers.
    registerFallbackValue(
      CreateServiceDefinitionRequest(
        (b) => b
          ..name = 'fallback'
          ..baseDurationMinutes = 30
          ..priceType = CreateServiceDefinitionRequestPriceTypeEnum.FIXED
          ..price = 100
          ..category = 'FALLBACK'
          ..serviceTypeId = _serviceTypeId,
      ),
    );
    registerFallbackValue(
      CreateCategoryRequestRequest(
        (b) => b
          ..name = 'FALLBACK'
          ..displayName = 'fallback',
      ),
    );
    registerFallbackValue(
      UpdateServiceDefinitionRequest((b) => b..name = 'fallback'),
    );
  });

  // ── 1. listMyServices — empty list ──────────────────────────────────────────

  group('listMyServices', () {
    test(
      'returns empty list when the backend returns an empty array',
      () async {
        when(
          () => serviceApi.getMyServices(),
        ).thenAnswer((_) async => _listResponse([]));

        final result = await repository.listMyServices();

        expect(result, isEmpty);
      },
    );

    // ── 2. listMyServices — populated list, mapper applied ───────────────────

    test('returns mapped domain objects for a populated list', () async {
      final dto1 = _buildMasterServiceDto(
        id: 'svc-001',
        serviceDefinition: _buildDef(
          name: 'Манікюр',
          baseDurationMinutes: 60,
          priceMin: 500,
          priceDisplay: '500 ₴',
        ),
        isActive: true,
      );
      final dto2 = _buildMasterServiceDto(
        id: 'svc-002',
        serviceDefinition: _buildDef(
          id: 'def-002',
          name: 'Педикюр',
          baseDurationMinutes: 90,
          priceMin: 700,
          priceDisplay: '700 ₴',
        ),
        // effectivePrice is the floor for booking but priceMin is used for domain.
        effectivePrice: 650,
        isActive: true,
      );

      when(
        () => serviceApi.getMyServices(),
      ).thenAnswer((_) async => _listResponse([dto1, dto2]));

      final result = await repository.listMyServices();

      expect(result.length, 2);

      // First item — priceMin = 500.
      final first = result.first;
      expect(first.id, 'svc-001');
      expect(first.name, 'Манікюр');
      expect(first.durationMinutes, 60);
      expect(first.priceMin, 500.0);
      expect(first.priceDisplay, '500 ₴');
      expect(first.isActive, isTrue);

      // Second item — priceMin = 700 (from serviceDefinition).
      final second = result[1];
      expect(second.id, 'svc-002');
      expect(second.name, 'Педикюр');
      expect(second.durationMinutes, 90);
      expect(second.priceMin, 700.0);
      expect(second.isActive, isTrue);
    });

    test('maps NetworkFailure on connectionError', () async {
      when(() => serviceApi.getMyServices()).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _listPath),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.listMyServices(),
        throwsA(isA<NetworkFailure>()),
      );
    });

    // ── Phase 16.9 — owner-endpoint repoint ──────────────────────────────────
    //
    // The master's own list MUST hit the authenticated owner endpoint
    // getMyServices() (`GET /independent-masters/me/services`, which INCLUDES
    // drafts), NOT the public getMasterServices(masterId) browse endpoint
    // (`GET /masters/{masterId}/services`, which filters drafts out). This test
    // would FAIL if the repository were reverted to the public endpoint.

    test('calls getMyServices() (owner endpoint) and NEVER getMasterServices() '
        '(public browse endpoint)', () async {
      when(
        () => serviceApi.getMyServices(),
      ).thenAnswer((_) async => _listResponse([_buildMasterServiceDto()]));

      await repository.listMyServices();

      verify(() => serviceApi.getMyServices()).called(1);
      verifyNever(
        () => serviceApi.getMasterServices(masterId: any(named: 'masterId')),
      );
    });
  });

  // ── Phase 315 D1 — listMyServices() salon-target dispatch ─────────────────
  //
  // Read dispatch: a `null` target hits the owner endpoint via the generated
  // client (already pinned above); a SalonMasterTarget hits the raw-Dio
  // salon-scoped GET. Assert the URI the fake Dio actually SAW, never the
  // response payload — a mapper test passes on either path
  // (`project_widget_field_assertion_is_vacuous`).

  group('listMyServices — salon-target dispatch (phase 315 D1)', () {
    late _MockDio mockDio;

    setUp(() {
      mockDio = _MockDio();
    });

    HttpServiceRepository salonRepo({
      String salonId = 'salon-row-uuid',
      String masterId = 'master-row-uuid',
    }) => HttpServiceRepository(
      serviceApi: serviceApi,
      categoryApi: categoryApi,
      catalogApi: catalogApi,
      dio: mockDio,
      masterId: '',
      target: SalonMasterTarget(salonId: salonId, masterId: masterId),
      sessionUserId: 'user-row-uuid',
    );

    test(
      'null target — listMyServices() hits the owner endpoint, NEVER the raw '
      'Dio (the byte-identical-to-today branch)',
      () async {
        when(
          () => serviceApi.getMyServices(),
        ).thenAnswer((_) async => _listResponse(const []));

        final result = await repository.listMyServices();

        expect(result, isEmpty);
        verify(() => serviceApi.getMyServices()).called(1);
      },
    );

    test(
      'SalonMasterTarget — GETs /api/v1/salons/{salonId}/masters/{masterId}/services',
      () async {
        String? capturedPath;
        when(() => mockDio.get<Object?>(any())).thenAnswer((invocation) async {
          capturedPath = invocation.positionalArguments[0] as String;
          return Response<Object?>(
            requestOptions: RequestOptions(path: capturedPath!),
            statusCode: 200,
            data: <String, Object?>{'success': true, 'data': <Object?>[]},
          );
        });

        final result = await salonRepo(
          salonId: 'salon-abc',
          masterId: 'master-xyz',
        ).listMyServices();

        expect(result, isEmpty);
        expect(
          capturedPath,
          '/api/v1/salons/salon-abc/masters/master-xyz/services',
        );
        verifyNever(() => serviceApi.getMyServices());
      },
    );

    test('SalonMasterTarget — masterId is sent VERBATIM even when it is a '
        'user-id-shaped UUID (no re-derivation from the session; resolving the '
        'id kind is phase 317\'s job)', () async {
      const userIdShaped = '11111111-2222-3333-4444-555555555555';
      String? capturedPath;
      when(() => mockDio.get<Object?>(any())).thenAnswer((invocation) async {
        capturedPath = invocation.positionalArguments[0] as String;
        return Response<Object?>(
          requestOptions: RequestOptions(path: capturedPath!),
          statusCode: 200,
          data: <String, Object?>{'success': true, 'data': <Object?>[]},
        );
      });

      await salonRepo(
        salonId: 'salon-abc',
        masterId: userIdShaped,
      ).listMyServices();

      expect(
        capturedPath,
        '/api/v1/salons/salon-abc/masters/$userIdShaped/services',
        reason:
            'this layer is a pass-through — a future "helpful" '
            'normalisation must be caught here',
      );
    });

    test(
      'SalonMasterTarget — a populated response maps to domain objects',
      () async {
        when(() => mockDio.get<Object?>(any())).thenAnswer(
          (_) async => Response<Object?>(
            requestOptions: RequestOptions(
              path: '/api/v1/salons/salon-abc/masters/master-xyz/services',
            ),
            statusCode: 200,
            data: <String, Object?>{
              'success': true,
              'data': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'svc-001',
                  'masterId': 'master-xyz',
                  'serviceDefinition': <String, Object?>{
                    'id': 'def-001',
                    'name': 'Манікюр',
                    'baseDurationMinutes': 60,
                    'priceType': 'FIXED',
                    'priceMin': 500,
                    'priceDisplay': '500 ₴',
                    'isActive': true,
                  },
                  'isActive': true,
                },
              ],
            },
          ),
        );

        final result = await salonRepo(
          salonId: 'salon-abc',
          masterId: 'master-xyz',
        ).listMyServices();

        expect(result, hasLength(1));
        expect(result.first.name, 'Манікюр');
        expect(result.first.priceMin, 500.0);
      },
    );

    test(
      'SalonMasterTarget — connectionError maps to NetworkFailure through the '
      'shared mapper',
      () async {
        when(() => mockDio.get<Object?>(any())).thenThrow(
          DioException(
            requestOptions: RequestOptions(
              path: '/api/v1/salons/salon-abc/masters/master-xyz/services',
            ),
            type: DioExceptionType.connectionError,
          ),
        );

        await expectLater(
          salonRepo(
            salonId: 'salon-abc',
            masterId: 'master-xyz',
          ).listMyServices(),
          throwsA(isA<NetworkFailure>()),
        );
      },
    );

    // ── mobile-security finding 1/2 (phase-315 audit-fix cycle 1) ──────────
    //
    // [t.salonId] / [t.masterId] are interpolated raw into this path (no
    // generated-client encoding, unlike every other salon/master path param
    // in this codebase). A value containing `/`, `..`, `?`, or `#` could
    // silently retarget this request on the authenticated [_dio] — the one
    // that carries the bearer token. These pin the SHAPE of the resulting
    // path (exactly the intended segments, no extra one carved out by an
    // unencoded separator), not merely "the string changed" — a broken
    // re-implementation that still mangles the URL differently would still
    // pass a weaker assertion.
    const pathInjections = <String>[
      'a/b',
      '../evil',
      'x?y=1',
      'z#frag',
      '%2Falready-encoded',
      // The deliberate near-miss (mobile-security S2): CONTAINS dot-segments,
      // but its separators encode to %2F and `normalizePath` splits on
      // literal `/` only — so it must still fly, as ONE segment. `'../evil'`
      // above is NOT this case: it encodes to `..%2Fevil`. Neither of them is
      // a BARE `..`, which is the input that actually collapses the path and
      // which `_pathSegment` now rejects outright (see the reject rows below
      // and `service_repository_contract_test.dart`).
      'a/../../b',
    ];

    // Bare dot-segments survive `Uri.encodeComponent` verbatim and are eaten
    // by dio's `normalizePath()` — `_pathSegment` REJECTS them rather than
    // sanitising, so no request is issued at all.
    const pathRejections = <String>['..', '.'];

    for (final injected in pathRejections) {
      test(
        'SalonMasterTarget — a masterId of "$injected" is REJECTED and NO GET '
        'is issued: encoding leaves it verbatim and dio normalizePath() would '
        'then delete/collapse its segment',
        () async {
          when(() => mockDio.get<Object?>(any())).thenAnswer(
            (_) async => Response<Object?>(
              requestOptions: RequestOptions(path: '/'),
              statusCode: 200,
              data: <String, Object?>{'success': true, 'data': <Object?>[]},
            ),
          );

          await expectLater(
            salonRepo(
              salonId: 'salon-abc',
              masterId: injected,
            ).listMyServices(),
            throwsA(isA<UnknownFailure>()),
          );
          verifyNever(() => mockDio.get<Object?>(any()));
        },
      );
    }

    test(
      'SalonMasterTarget — a salonId containing a path-significant '
      'character is percent-encoded, never widening the path shape',
      () async {
        for (final injected in pathInjections) {
          String? capturedPath;
          when(() => mockDio.get<Object?>(any())).thenAnswer((
            invocation,
          ) async {
            capturedPath = invocation.positionalArguments[0] as String;
            return Response<Object?>(
              requestOptions: RequestOptions(path: capturedPath!),
              statusCode: 200,
              data: <String, Object?>{'success': true, 'data': <Object?>[]},
            );
          });

          await salonRepo(
            salonId: injected,
            masterId: 'master-xyz',
          ).listMyServices();

          final segments = _wireSegments(capturedPath!);
          expect(
            segments,
            <String>[
              'api',
              'v1',
              'salons',
              injected,
              'masters',
              'master-xyz',
              'services',
            ],
            reason:
                'injected salonId "$injected" must land as ONE encoded '
                'segment, not create/shift a segment boundary',
          );
        }
      },
    );

    test(
      'SalonMasterTarget — a masterId containing a path-significant '
      'character is percent-encoded, never widening the path shape',
      () async {
        for (final injected in pathInjections) {
          String? capturedPath;
          when(() => mockDio.get<Object?>(any())).thenAnswer((
            invocation,
          ) async {
            capturedPath = invocation.positionalArguments[0] as String;
            return Response<Object?>(
              requestOptions: RequestOptions(path: capturedPath!),
              statusCode: 200,
              data: <String, Object?>{'success': true, 'data': <Object?>[]},
            );
          });

          await salonRepo(
            salonId: 'salon-abc',
            masterId: injected,
          ).listMyServices();

          final segments = _wireSegments(capturedPath!);
          expect(
            segments,
            <String>[
              'api',
              'v1',
              'salons',
              'salon-abc',
              'masters',
              injected,
              'services',
            ],
            reason:
                'injected masterId "$injected" must land as ONE encoded '
                'segment, not create/shift a segment boundary',
          );
        }
      },
    );
  });

  // ── getMyService — list round-trip + filter + failure mapping ───────────────
  //
  // getMyService(id) has no single-resource endpoint: it calls listMyServices()
  // and filters client-side on s.id == id, throwing NotFoundFailure on a miss.
  // It therefore inherits listMyServices()'s _assertAuthenticated() guard and
  // its DioException→Failure mapping.

  group('getMyService', () {
    test(
      'returns the matching service when present in the owner list',
      () async {
        final wanted = _buildMasterServiceDto(
          id: 'svc-002',
          serviceDefinition: _buildDef(
            id: 'def-002',
            name: 'Педикюр',
            baseDurationMinutes: 90,
            priceMin: 700,
            priceDisplay: '700 ₴',
          ),
        );
        when(() => serviceApi.getMyServices()).thenAnswer(
          (_) async =>
              _listResponse([_buildMasterServiceDto(id: 'svc-001'), wanted]),
        );

        final result = await repository.getMyService('svc-002');

        expect(result.id, 'svc-002');
        expect(result.name, 'Педикюр');
        expect(result.durationMinutes, 90);
        expect(result.priceMin, 700.0);
        // Confirms it goes through the owner list endpoint, not a single-GET.
        verify(() => serviceApi.getMyServices()).called(1);
      },
    );

    test(
      'throws NotFoundFailure when the id is absent from the list',
      () async {
        when(() => serviceApi.getMyServices()).thenAnswer(
          (_) async => _listResponse([_buildMasterServiceDto(id: 'svc-001')]),
        );

        await expectLater(
          repository.getMyService('does-not-exist'),
          throwsA(isA<NotFoundFailure>()),
        );
      },
    );

    test('throws NotFoundFailure when the owner list is empty', () async {
      when(
        () => serviceApi.getMyServices(),
      ).thenAnswer((_) async => _listResponse([]));

      await expectLater(
        repository.getMyService('svc-001'),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test(
      'propagates NetworkFailure from the underlying list call on connectionError',
      () async {
        when(() => serviceApi.getMyServices()).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: _listPath),
            type: DioExceptionType.connectionError,
          ),
        );

        await expectLater(
          repository.getMyService('svc-001'),
          throwsA(isA<NetworkFailure>()),
        );
      },
    );

    test(
      'throws UnauthorizedFailure (empty masterId) without any network call',
      () async {
        final unauthRepo = HttpServiceRepository(
          serviceApi: serviceApi,
          categoryApi: categoryApi,
          catalogApi: catalogApi,
          dio: Dio(),
          masterId: '',
        );

        await expectLater(
          unauthRepo.getMyService('svc-001'),
          throwsA(isA<UnauthorizedFailure>()),
        );

        verifyNever(() => serviceApi.getMyServices());
      },
    );
  });

  // ── badResponse status → Failure mapping (shared _mapDioException) ───────────
  //
  // listMyServices() routes any DioException through the shared _mapDioException.
  // These pin the badResponse status→Failure contract that every list/get/
  // update/deactivate path inherits: 400/422 → ValidationFailure, 404 →
  // NotFoundFailure, 5xx (and any other badResponse) → ServerFailure.

  group('badResponse status mapping', () {
    DioException badResponse(int status) => DioException(
      requestOptions: RequestOptions(path: _listPath),
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: _listPath),
        statusCode: status,
      ),
      type: DioExceptionType.badResponse,
    );

    test('400 → ValidationFailure', () async {
      when(() => serviceApi.getMyServices()).thenThrow(badResponse(400));

      await expectLater(
        repository.listMyServices(),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('422 → ValidationFailure', () async {
      when(() => serviceApi.getMyServices()).thenThrow(badResponse(422));

      await expectLater(
        repository.listMyServices(),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('404 → NotFoundFailure', () async {
      when(() => serviceApi.getMyServices()).thenThrow(badResponse(404));

      await expectLater(
        repository.listMyServices(),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('500 → ServerFailure carrying the status code', () async {
      when(() => serviceApi.getMyServices()).thenThrow(badResponse(500));

      await expectLater(
        repository.listMyServices(),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('503 → ServerFailure carrying the status code', () async {
      when(() => serviceApi.getMyServices()).thenThrow(badResponse(503));

      await expectLater(
        repository.listMyServices(),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 503),
        ),
      );
    });
  });

  // ── transport-type mapping: badCertificate → NetworkFailure ─────────────────
  //
  // A TLS / certificate-validation failure (DioExceptionType.badCertificate) is
  // a transport-layer security problem, NOT a retryable 5xx. The shared
  // _mapDioException classifies it alongside the connectivity failures
  // (NetworkFailure) so the UI never invites a "try again" against an untrusted
  // connection — it must NOT surface as a recoverable ServerFailure. listMyServices()
  // routes every DioException through that shared mapper, so it pins the contract
  // every list/get/update/deactivate path inherits.

  group('badCertificate transport mapping', () {
    DioException badCertificate() => DioException(
      requestOptions: RequestOptions(path: _listPath),
      type: DioExceptionType.badCertificate,
    );

    test('badCertificate → NetworkFailure (NOT ServerFailure)', () async {
      when(() => serviceApi.getMyServices()).thenThrow(badCertificate());

      await expectLater(
        repository.listMyServices(),
        throwsA(
          isA<NetworkFailure>().having(
            (f) => f,
            'is not a ServerFailure',
            isNot(isA<ServerFailure>()),
          ),
        ),
      );
    });
  });

  // ── 3. create — happy path ─────────────────────────────────────────────────

  group('create', () {
    test(
      'calls addIndependentMasterService with correct fields (FIXED)',
      () async {
        final dto = _buildMasterServiceDto(
          id: 'svc-new',
          serviceDefinition: _buildDef(
            name: 'Брови',
            baseDurationMinutes: 45,
            priceMin: 350,
            priceDisplay: '350 ₴',
          ),
        );

        when(
          () => serviceApi.addIndependentMasterService(
            createServiceDefinitionRequest: any(
              named: 'createServiceDefinitionRequest',
            ),
          ),
        ).thenAnswer((_) async => _singleResponse(dto));

        const input = MasterServiceCreate(
          name: 'Брови',
          durationMinutes: 45,
          priceType: ServicePriceType.fixed,
          price: 350.0,
          description: 'Оформлення брів',
          category: 'BROWS',
          serviceTypeId: _serviceTypeId,
        );

        final result = await repository.create(input);

        expect(result.id, 'svc-new');
        expect(result.name, 'Брови');
        expect(result.priceMin, 350.0);

        // Verify the generated request carried the correct fields.
        final captured =
            verify(
                  () => serviceApi.addIndependentMasterService(
                    createServiceDefinitionRequest: captureAny(
                      named: 'createServiceDefinitionRequest',
                    ),
                  ),
                ).captured.single
                as CreateServiceDefinitionRequest;

        expect(captured.name, 'Брови');
        expect(captured.baseDurationMinutes, 45);
        expect(
          captured.priceType,
          CreateServiceDefinitionRequestPriceTypeEnum.FIXED,
        );
        expect(captured.price, 350.0);
        expect(captured.description, 'Оформлення брів');
        expect(captured.category, 'BROWS');
        // Service type is mandatory on create — the mapper must forward it.
        expect(captured.serviceTypeId, _serviceTypeId);
      },
    );

    // ── 4. create — invalid input → ArgumentError (local; no network call) ───

    test(
      'throws ArgumentError for zero price (FIXED) before any network call',
      () async {
        // No mock set up for serviceApi — if the network call were made the
        // test would fail with a "no stub found" error from mocktail, which
        // proves the validation fires locally.
        await expectLater(
          repository.create(
            const MasterServiceCreate(
              name: 'Invalid',
              durationMinutes: 30,
              priceType: ServicePriceType.fixed,
              price: 0,
              category: 'MANICURE',
              // Type present so the ArgumentError provably comes from price=0,
              // not from the (earlier) mandatory-service-type guard.
              serviceTypeId: _serviceTypeId,
            ),
          ),
          throwsA(isA<ArgumentError>()),
        );

        // Confirm no API call was made.
        verifyNever(
          () => serviceApi.addIndependentMasterService(
            createServiceDefinitionRequest: any(
              named: 'createServiceDefinitionRequest',
            ),
          ),
        );
      },
    );

    test(
      'throws ArgumentError for zero durationMinutes before any network call',
      () async {
        await expectLater(
          repository.create(
            const MasterServiceCreate(
              name: 'Invalid',
              durationMinutes: 0,
              priceType: ServicePriceType.fixed,
              price: 100,
              category: 'MANICURE',
            ),
          ),
          throwsA(isA<ArgumentError>()),
        );

        verifyNever(
          () => serviceApi.addIndependentMasterService(
            createServiceDefinitionRequest: any(
              named: 'createServiceDefinitionRequest',
            ),
          ),
        );
      },
    );

    test('re-throws pre-mapped Failure unchanged', () async {
      const mapped = NetworkFailure();
      when(
        () => serviceApi.addIndependentMasterService(
          createServiceDefinitionRequest: any(
            named: 'createServiceDefinitionRequest',
          ),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(
            path: '/api/v1/independent-masters/me/services',
          ),
          type: DioExceptionType.unknown,
          error: mapped,
        ),
      );

      await expectLater(
        repository.create(
          const MasterServiceCreate(
            name: 'Test',
            durationMinutes: 30,
            priceType: ServicePriceType.fixed,
            price: 100,
            category: 'MANICURE',
            // Valid type so the mapper passes and the call reaches the network,
            // exercising the pre-mapped-Failure re-throw path.
            serviceTypeId: _serviceTypeId,
          ),
        ),
        throwsA(same(mapped)),
      );
    });
  });

  // ── 5. deactivate — correct method called; idempotent ──────────────────────

  group('deactivate', () {
    test(
      'calls deactivateServiceDefinition with the serviceDefId (not assignment id)',
      () async {
        when(
          () => serviceApi.deactivateServiceDefinition(
            serviceDefId: _serviceDefId,
          ),
        ).thenAnswer(
          (_) async => Response<void>(
            requestOptions: RequestOptions(
              path: '/api/v1/services/$_serviceDefId',
            ),
            statusCode: 200,
          ),
        );

        await repository.deactivate(_serviceDefId);

        // The path id must be the service-definition id, NOT the assignment id.
        verify(
          () => serviceApi.deactivateServiceDefinition(
            serviceDefId: _serviceDefId,
          ),
        ).called(1);
        verifyNever(
          () =>
              serviceApi.deactivateServiceDefinition(serviceDefId: _serviceId),
        );
      },
    );

    test(
      'calling deactivate twice does not throw (idempotent server 200)',
      () async {
        when(
          () => serviceApi.deactivateServiceDefinition(
            serviceDefId: _serviceDefId,
          ),
        ).thenAnswer(
          (_) async => Response<void>(
            requestOptions: RequestOptions(
              path: '/api/v1/services/$_serviceDefId',
            ),
            statusCode: 200,
          ),
        );

        await repository.deactivate(_serviceDefId);
        await repository.deactivate(_serviceDefId); // must not throw

        verify(
          () => serviceApi.deactivateServiceDefinition(
            serviceDefId: _serviceDefId,
          ),
        ).called(2);
      },
    );

    test('throws NetworkFailure when connectionError', () async {
      when(
        () =>
            serviceApi.deactivateServiceDefinition(serviceDefId: _serviceDefId),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(
            path: '/api/v1/services/$_serviceDefId',
          ),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.deactivate(_serviceDefId),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  // ── 5b. deactivate — salon-target dispatch (phase 316 D1) ───────────────────
  //
  // Mirrors the "listMyServices — salon-target dispatch (phase 315 D1)" group
  // above: null target keeps using the generated client (already pinned in
  // the `deactivate` group above, byte-identical); a SalonMasterTarget hits
  // the raw-Dio salon-scoped DELETE. Assert the URI the fake Dio actually
  // SAW, never a mocked success payload — a mapper test passes on either path
  // (`project_widget_field_assertion_is_vacuous`).

  group('deactivate — salon-target dispatch (phase 316 D1)', () {
    late _MockDio mockDio;

    setUp(() {
      mockDio = _MockDio();
    });

    HttpServiceRepository salonRepo({
      String salonId = 'salon-row-uuid',
      String masterId = 'master-row-uuid',
    }) => HttpServiceRepository(
      serviceApi: serviceApi,
      categoryApi: categoryApi,
      catalogApi: catalogApi,
      dio: mockDio,
      masterId: '',
      target: SalonMasterTarget(salonId: salonId, masterId: masterId),
      sessionUserId: 'user-row-uuid',
    );

    /// Stubs [mockDio.delete] to succeed with [statusCode] and returns a
    /// getter for the path the fake Dio actually saw.
    String? Function() stubDelete({int statusCode = 204}) {
      String? capturedPath;
      when(() => mockDio.delete<Object?>(any())).thenAnswer((invocation) async {
        capturedPath = invocation.positionalArguments[0] as String;
        return Response<Object?>(
          requestOptions: RequestOptions(path: capturedPath!),
          statusCode: statusCode,
        );
      });
      return () => capturedPath;
    }

    test('null target — deactivate() hits the generated client, NEVER the raw '
        'Dio (the byte-identical-to-today branch)', () async {
      when(
        () =>
            serviceApi.deactivateServiceDefinition(serviceDefId: _serviceDefId),
      ).thenAnswer(
        (_) async => Response<void>(
          requestOptions: RequestOptions(
            path: '/api/v1/services/$_serviceDefId',
          ),
          statusCode: 200,
        ),
      );

      await repository.deactivate(_serviceDefId);

      verify(
        () =>
            serviceApi.deactivateServiceDefinition(serviceDefId: _serviceDefId),
      ).called(1);
      verifyNever(() => mockDio.delete<Object?>(any()));
    });

    test('SalonMasterTarget — DELETEs '
        '/api/v1/salons/{salonId}/masters/{masterId}/services/{serviceDefId}, '
        'NEVER DELETE /api/v1/services/{serviceDefId}', () async {
      final capturedPath = stubDelete();

      await salonRepo(
        salonId: 'salon-abc',
        masterId: 'master-xyz',
      ).deactivate(_serviceDefId);

      expect(
        capturedPath(),
        '/api/v1/salons/salon-abc/masters/master-xyz/services/$_serviceDefId',
      );
      verifyNever(
        () => serviceApi.deactivateServiceDefinition(
          serviceDefId: any(named: 'serviceDefId'),
        ),
      );
    });

    test('SalonMasterTarget — the id sent is the DEFINITION id, NOT the '
        'assignment id (differing-ids fixture: $_serviceDefId vs $_serviceId — '
        'with equal ids this assertion would pass on either, which is exactly '
        'how this bug ships)', () async {
      final capturedPath = stubDelete();

      // Mirrors `service_edit_screen.dart:115-156`, which passes
      // `service.serviceDefId` — never `service.id`.
      await salonRepo(
        salonId: 'salon-abc',
        masterId: 'master-xyz',
      ).deactivate(_serviceDefId);

      expect(capturedPath(), endsWith('/services/$_serviceDefId'));
      expect(
        capturedPath(),
        isNot(contains(_serviceId)),
        reason: 'the assignment id must never appear in the unassign path',
      );
    });

    // ── Status mapping (salon branch) — phase 316 D2 ───────────────────────
    //
    // Five NAMED rows: a single "non-2xx throws" test would hide the two
    // that are handled DIFFERENTLY upstream (409, 429) from the three that
    // fall through to the shared mapper unchanged (204, 404, 403).

    DioException badResponse(int status) => DioException(
      requestOptions: RequestOptions(
        path:
            '/api/v1/salons/salon-abc/masters/master-xyz/services/'
            '$_serviceDefId',
      ),
      response: Response<dynamic>(
        requestOptions: RequestOptions(
          path:
              '/api/v1/salons/salon-abc/masters/master-xyz/services/'
              '$_serviceDefId',
        ),
        statusCode: status,
      ),
      type: DioExceptionType.badResponse,
    );

    test('204 → completes normally', () async {
      stubDelete(statusCode: 204);

      await expectLater(
        salonRepo(
          salonId: 'salon-abc',
          masterId: 'master-xyz',
        ).deactivate(_serviceDefId),
        completes,
      );
    });

    test('409 → ServiceUnassignBlockedFailure (future CONFIRMED bookings block '
        'the unassign; NOTHING written)', () async {
      when(() => mockDio.delete<Object?>(any())).thenThrow(badResponse(409));

      await expectLater(
        salonRepo(
          salonId: 'salon-abc',
          masterId: 'master-xyz',
        ).deactivate(_serviceDefId),
        throwsA(isA<ServiceUnassignBlockedFailure>()),
      );
    });

    test('404 → NotFoundFailure (no active assignment for this pair — a '
        'second tap after a stale-list race)', () async {
      when(() => mockDio.delete<Object?>(any())).thenThrow(badResponse(404));

      await expectLater(
        salonRepo(
          salonId: 'salon-abc',
          masterId: 'master-xyz',
        ).deactivate(_serviceDefId),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('403 → falls through to the shared mapper with NO special handling '
        '(D2 — the route guard makes this unreachable)', () async {
      when(() => mockDio.delete<Object?>(any())).thenThrow(badResponse(403));

      await expectLater(
        salonRepo(
          salonId: 'salon-abc',
          masterId: 'master-xyz',
        ).deactivate(_serviceDefId),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 403),
        ),
      );
    });

    test(
      '429 → ServiceRateLimitedFailure (shares the single-write bucket)',
      () async {
        when(() => mockDio.delete<Object?>(any())).thenThrow(badResponse(429));

        await expectLater(
          salonRepo(
            salonId: 'salon-abc',
            masterId: 'master-xyz',
          ).deactivate(_serviceDefId),
          throwsA(isA<ServiceRateLimitedFailure>()),
        );
      },
    );

    // ── Encoding — every segment, mirroring phase 315's list/bulk precedent ──

    const pathInjections = <String>[
      'a/b',
      '../evil',
      'x?y=1',
      'z#frag',
      '%2Falready-encoded',
      // The deliberate near-miss (mobile-security S2): CONTAINS dot-segments,
      // but its separators encode to %2F and `normalizePath` splits on
      // literal `/` only — so it must still fly, as ONE segment. `'../evil'`
      // above is NOT this case: it encodes to `..%2Fevil`. Neither of them is
      // a BARE `..`, which is the input that actually collapses the path and
      // which `_pathSegment` now rejects outright (see the reject rows below
      // and `service_repository_contract_test.dart`).
      'a/../../b',
    ];

    // Bare dot-segments survive `Uri.encodeComponent` verbatim and are eaten
    // by dio's `normalizePath()` — `_pathSegment` REJECTS them rather than
    // sanitising, so no request is issued at all.
    const pathRejections = <String>['..', '.'];

    for (final injected in pathRejections) {
      test(
        'a masterId of "$injected" is REJECTED and NO DELETE is issued',
        () async {
          stubDelete();

          await expectLater(
            salonRepo(
              salonId: 'salon-abc',
              masterId: injected,
            ).deactivate(_serviceDefId),
            throwsA(isA<UnknownFailure>()),
          );
          verifyNever(() => mockDio.delete<Object?>(any()));
        },
      );

      test(
        'a serviceDefId of "$injected" is REJECTED and NO DELETE is issued — '
        'unlike salonId/masterId it has NO _assertAuthenticated guard behind '
        'it, so this is the only thing between it and the wire',
        () async {
          stubDelete();

          await expectLater(
            salonRepo(
              salonId: 'salon-abc',
              masterId: 'master-xyz',
            ).deactivate(injected),
            throwsA(isA<UnknownFailure>()),
          );
          verifyNever(() => mockDio.delete<Object?>(any()));
        },
      );
    }

    test(
      'a salonId containing a path-significant character is percent-encoded, '
      'never widening the path shape',
      () async {
        for (final injected in pathInjections) {
          final capturedPath = stubDelete();

          await salonRepo(
            salonId: injected,
            masterId: 'master-xyz',
          ).deactivate(_serviceDefId);

          final segments = _wireSegments(capturedPath()!);
          expect(
            segments,
            <String>[
              'api',
              'v1',
              'salons',
              injected,
              'masters',
              'master-xyz',
              'services',
              _serviceDefId,
            ],
            reason:
                'injected salonId "$injected" must land as ONE encoded '
                'segment, not create/shift a segment boundary',
          );
        }
      },
    );

    test(
      'a masterId containing a path-significant character is percent-encoded, '
      'never widening the path shape',
      () async {
        for (final injected in pathInjections) {
          final capturedPath = stubDelete();

          await salonRepo(
            salonId: 'salon-abc',
            masterId: injected,
          ).deactivate(_serviceDefId);

          final segments = _wireSegments(capturedPath()!);
          expect(
            segments,
            <String>[
              'api',
              'v1',
              'salons',
              'salon-abc',
              'masters',
              injected,
              'services',
              _serviceDefId,
            ],
            reason:
                'injected masterId "$injected" must land as ONE encoded '
                'segment, not create/shift a segment boundary',
          );
        }
      },
    );

    test('a serviceDefId containing a path-significant character is '
        'percent-encoded, never widening the path shape — it is '
        'CALLER-SUPPLIED too', () async {
      for (final injected in pathInjections) {
        final capturedPath = stubDelete();

        await salonRepo(
          salonId: 'salon-abc',
          masterId: 'master-xyz',
        ).deactivate(injected);

        final segments = _wireSegments(capturedPath()!);
        expect(
          segments,
          <String>[
            'api',
            'v1',
            'salons',
            'salon-abc',
            'masters',
            'master-xyz',
            'services',
            injected,
          ],
          reason:
              'injected serviceDefId "$injected" must land as ONE encoded '
              'segment, not create/shift a segment boundary',
        );
      }
    });
  });

  // ── 5c. deactivate — D4: a 409 leaves servicesListProvider untouched ────────
  //
  // The backend refuses BEFORE any write (`ServiceCatalogService.java:289-297`),
  // so the mobile side must leave local state exactly as it found it: no
  // optimistic removal, no `ref.invalidate(servicesListProvider)`, no pop.
  //
  // ⚠️ Riverpod seamless-invalidate trap: `invalidate` RETAINS `.value`, so
  // "the list is still non-null" would pass even after an invalidation that
  // is merely PENDING a rebuild. This asserts on the underlying GET call
  // count (via the fake Dio `verify(...).called(n)`) AND a rebuild-notify
  // counter — both are insensitive to `.value` staying populated and only
  // move if a REAL re-fetch happens.

  group('deactivate — D4 no-write-on-refusal (salon 409)', () {
    test('a 409 leaves servicesListProvider untouched — no invalidation, no '
        'refetch, list still holds all three seeded services', () async {
      final mockDio = _MockDio();
      final salonRepository = HttpServiceRepository(
        serviceApi: serviceApi,
        categoryApi: categoryApi,
        catalogApi: catalogApi,
        dio: mockDio,
        masterId: '',
        target: const SalonMasterTarget(
          salonId: 'salon-abc',
          masterId: 'master-xyz',
        ),
        sessionUserId: 'user-row-uuid',
      );

      final container = ProviderContainer(
        overrides: [
          serviceRepositoryProvider.overrideWithValue(salonRepository),
        ],
      );
      addTearDown(container.dispose);

      // Seed with three services via the salon-target GET. A manual
      // counter (not a second `verify(...).called()`) tracks invocations —
      // mocktail's `verify` CONSUMES matched calls, so a second `verify`
      // with the same matcher only sees calls made AFTER the first verify,
      // which is exactly right for "no NEW call happened" but reads
      // confusingly; a plain counter is unambiguous either way.
      var getCallCount = 0;
      when(() => mockDio.get<Object?>(any())).thenAnswer((_) async {
        getCallCount++;
        return Response<Object?>(
          requestOptions: RequestOptions(
            path: '/api/v1/salons/salon-abc/masters/master-xyz/services',
          ),
          statusCode: 200,
          data: <String, Object?>{
            'success': true,
            'data': <Map<String, Object?>>[
              for (final id in ['svc-1', 'svc-2', 'svc-3'])
                <String, Object?>{
                  'id': id,
                  'masterId': 'master-xyz',
                  'serviceDefinition': <String, Object?>{
                    'id': 'def-$id',
                    'name': 'Послуга $id',
                    'baseDurationMinutes': 60,
                    'priceType': 'FIXED',
                    'priceMin': 500,
                    'priceDisplay': '500 ₴',
                    'isActive': true,
                  },
                  'isActive': true,
                },
            ],
          },
        );
      });

      final initial = await container.read(servicesListProvider.future);
      expect(initial, hasLength(3));
      expect(getCallCount, 1);

      // A widget still watching the list (e.g. ServicesListScreen behind
      // the just-closed delete dialog) would receive a rebuild
      // notification if the provider were invalidated.
      var notifyCount = 0;
      container.listen(
        servicesListProvider,
        (_, _) => notifyCount++,
        fireImmediately: false,
      );

      // Drive the 409.
      when(() => mockDio.delete<Object?>(any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(
            path:
                '/api/v1/salons/salon-abc/masters/master-xyz/services/'
                '$_serviceDefId',
          ),
          response: Response<dynamic>(
            requestOptions: RequestOptions(
              path:
                  '/api/v1/salons/salon-abc/masters/master-xyz/services/'
                  '$_serviceDefId',
            ),
            statusCode: 409,
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      await expectLater(
        container.read(serviceRepositoryProvider).deactivate(_serviceDefId),
        throwsA(isA<ServiceUnassignBlockedFailure>()),
      );

      // ⚠️ DRAIN THE EVENT LOOP BEFORE ASSERTING — without this the test is
      // VACUOUS against the very mutation it exists to catch.
      //
      // `ref.invalidate` is LAZY: it marks the provider dirty and the rebuild
      // (and therefore the re-fetch and the listener notification) is
      // scheduled, not synchronous. `expectLater` above resolves the moment
      // `deactivate` throws, so assertions placed directly after it run in the
      // SAME event-loop turn — before any scheduled rebuild could possibly be
      // observed. Measured, not assumed (phase-316 mutation check 4,
      // 2026-09-10): injecting `container.invalidate(servicesListProvider)` at
      // the 409 handler left this test GREEN without the drain and turns it
      // RED with it (`getCallCount` 1 → 2).
      //
      // `Future.delayed(Duration.zero)` and not `Future.value()`: the latter
      // yields ONE microtask, which is not guaranteed to cover Riverpod's
      // scheduling plus the repository's own async GET; a full event-loop turn
      // covers both.
      await Future<void>.delayed(Duration.zero);

      // D4 — assert on the GET call count / rebuild-notify count, never on
      // `.value != null` (that stays non-null through an invalidation too).
      expect(
        getCallCount,
        1,
        reason: 'a 409 refusal must not trigger any re-fetch of the list',
      );
      expect(
        notifyCount,
        0,
        reason:
            'a 409 refusal must not trigger any rebuild of '
            'servicesListProvider',
      );
      expect(container.read(servicesListProvider).value, hasLength(3));
    });
  });

  // ── 6. update — happy path; no second GET ──────────────────────────────────

  group('update', () {
    test(
      'PATCHes /services/{serviceDefId} (not the assignment id) and maps result',
      () async {
        // The update endpoint returns a ServiceDefinitionResponse.
        final updatedDef = _buildDef(
          id: _serviceDefId,
          name: 'Манікюр Оновлений',
          baseDurationMinutes: 75,
          priceMin: 600,
          priceDisplay: '600 ₴',
        );

        when(
          () => serviceApi.updateServiceDefinition(
            serviceDefId: _serviceDefId,
            updateServiceDefinitionRequest: any(
              named: 'updateServiceDefinitionRequest',
            ),
          ),
        ).thenAnswer((_) async => _updateResponse(updatedDef));

        const patch = MasterServiceUpdate(
          name: 'Манікюр Оновлений',
          durationMinutes: 75,
          priceType: ServicePriceType.fixed,
          price: 600.0,
        );

        final result = await repository.update(
          _serviceDefId,
          patch,
          assignmentId: _serviceId,
        );

        // Assignment id is threaded through; serviceDefId comes from the response.
        expect(result.id, _serviceId);
        expect(result.serviceDefId, _serviceDefId);
        expect(result.name, 'Манікюр Оновлений');
        expect(result.durationMinutes, 75);
        expect(result.priceMin, 600.0);

        // Verify the call used the serviceDefId path param (not the assignment
        // id) and forwarded a request with the mapped wire fields.
        final captured =
            verify(
                  () => serviceApi.updateServiceDefinition(
                    serviceDefId: _serviceDefId,
                    updateServiceDefinitionRequest: captureAny(
                      named: 'updateServiceDefinitionRequest',
                    ),
                  ),
                ).captured.single
                as UpdateServiceDefinitionRequest;
        expect(captured.name, 'Манікюр Оновлений');
        expect(captured.baseDurationMinutes, 75);
        expect(
          captured.priceType,
          UpdateServiceDefinitionRequestPriceTypeEnum.FIXED,
        );
        expect(captured.price, 600.0);

        // The list endpoint must NOT have been called (no extra round-trip).
        verifyNever(() => serviceApi.getMyServices());
      },
    );

    test(
      'throws ArgumentError for zero/invalid FIXED price in update before network call',
      () async {
        await expectLater(
          repository.update(
            _serviceDefId,
            const MasterServiceUpdate(
              priceType: ServicePriceType.fixed,
              price: 0,
            ),
            assignmentId: _serviceId,
          ),
          throwsA(isA<ArgumentError>()),
        );

        verifyNever(
          () => serviceApi.updateServiceDefinition(
            serviceDefId: any(named: 'serviceDefId'),
            updateServiceDefinitionRequest: any(
              named: 'updateServiceDefinitionRequest',
            ),
          ),
        );
      },
    );

    test(
      'throws NetworkFailure when the PATCH hits a connectionError',
      () async {
        when(
          () => serviceApi.updateServiceDefinition(
            serviceDefId: _serviceDefId,
            updateServiceDefinitionRequest: any(
              named: 'updateServiceDefinitionRequest',
            ),
          ),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(
              path: '/api/v1/services/$_serviceDefId',
            ),
            type: DioExceptionType.connectionError,
          ),
        );

        await expectLater(
          repository.update(
            _serviceDefId,
            const MasterServiceUpdate(name: 'Нова назва'),
            assignmentId: _serviceId,
          ),
          throwsA(isA<NetworkFailure>()),
        );
      },
    );

    test(
      'throws UnauthorizedFailure (empty masterId) without any network call',
      () async {
        final unauthRepo = HttpServiceRepository(
          serviceApi: serviceApi,
          categoryApi: categoryApi,
          catalogApi: catalogApi,
          dio: Dio(),
          masterId: '',
        );

        await expectLater(
          unauthRepo.update(
            _serviceDefId,
            const MasterServiceUpdate(name: 'Нова назва'),
            assignmentId: _serviceId,
          ),
          throwsA(isA<UnauthorizedFailure>()),
        );

        verifyNever(
          () => serviceApi.updateServiceDefinition(
            serviceDefId: any(named: 'serviceDefId'),
            updateServiceDefinitionRequest: any(
              named: 'updateServiceDefinitionRequest',
            ),
          ),
        );
      },
    );
  });

  // ── 6b. create/update — 409 DUPLICATE_SERVICE → ServiceDuplicateFailure ─────
  //
  // The typed `{ data: { code: DUPLICATE_SERVICE, serviceName, existingServiceDefId } }`
  // 409 envelope must map to [ServiceDuplicateFailure] (NOT the generic
  // [ServerFailure] the interceptor attaches for a non-auth 409), on both the
  // create and update write paths. `serviceName` / `existingServiceDefId` are
  // both nullable and threaded onto the failure when present.

  group('service-catalog write — 409 DUPLICATE_SERVICE', () {
    DioException duplicate409({
      Object? serviceName = 'Манікюр класичний',
      Object? existingServiceDefId = 'def-existing',
      // The interceptor attaches a generic ServerFailure(409) as e.error for a
      // non-auth 409; include it so the test proves the hand-decode runs BEFORE
      // the `e.error is Failure` fallthrough.
      Failure? attached = const ServerFailure(statusCode: 409),
    }) => DioException(
      requestOptions: RequestOptions(path: _listPath),
      type: DioExceptionType.badResponse,
      error: attached,
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: _listPath),
        statusCode: 409,
        data: <String, dynamic>{
          'success': false,
          'data': <String, dynamic>{
            'code': 'DUPLICATE_SERVICE',
            'serviceName': serviceName,
            'existingServiceDefId': existingServiceDefId,
          },
          'message': 'This service already exists',
        },
      ),
    );

    test('create → ServiceDuplicateFailure with the typed fields', () async {
      when(
        () => serviceApi.addIndependentMasterService(
          createServiceDefinitionRequest: any(
            named: 'createServiceDefinitionRequest',
          ),
        ),
      ).thenThrow(duplicate409());

      final failure = await repository
          .create(
            const MasterServiceCreate(
              name: 'Манікюр класичний',
              durationMinutes: 60,
              priceType: ServicePriceType.fixed,
              price: 500,
              category: 'MANICURE',
              serviceTypeId: _serviceTypeId,
            ),
          )
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(failure, isA<ServiceDuplicateFailure>());
      final dup = failure! as ServiceDuplicateFailure;
      expect(dup.serviceName, 'Манікюр класичний');
      expect(dup.existingServiceDefId, 'def-existing');
    });

    test(
      'update → ServiceDuplicateFailure (not a generic ServerFailure)',
      () async {
        when(
          () => serviceApi.updateServiceDefinition(
            serviceDefId: _serviceDefId,
            updateServiceDefinitionRequest: any(
              named: 'updateServiceDefinitionRequest',
            ),
          ),
        ).thenThrow(duplicate409());

        final failure = await repository
            .update(
              _serviceDefId,
              const MasterServiceUpdate(name: 'Манікюр класичний'),
              assignmentId: _serviceId,
            )
            .then<Object?>((_) => null, onError: (Object e) => e);

        expect(failure, isA<ServiceDuplicateFailure>());
        expect(failure, isNot(isA<ServerFailure>()));
      },
    );

    test(
      'null serviceName/existingServiceDefId still maps (no throw)',
      () async {
        when(
          () => serviceApi.addIndependentMasterService(
            createServiceDefinitionRequest: any(
              named: 'createServiceDefinitionRequest',
            ),
          ),
        ).thenThrow(
          duplicate409(serviceName: null, existingServiceDefId: null),
        );

        final failure = await repository
            .create(
              const MasterServiceCreate(
                name: 'Манікюр класичний',
                durationMinutes: 60,
                priceType: ServicePriceType.fixed,
                price: 500,
                category: 'MANICURE',
                serviceTypeId: _serviceTypeId,
              ),
            )
            .then<Object?>((_) => null, onError: (Object e) => e);

        expect(failure, isA<ServiceDuplicateFailure>());
        final dup = failure! as ServiceDuplicateFailure;
        expect(dup.serviceName, isNull);
        expect(dup.existingServiceDefId, isNull);
      },
    );

    test(
      'a 409 WITHOUT the DUPLICATE_SERVICE code is NOT a ServiceDuplicateFailure',
      () async {
        when(
          () => serviceApi.addIndependentMasterService(
            createServiceDefinitionRequest: any(
              named: 'createServiceDefinitionRequest',
            ),
          ),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: _listPath),
            type: DioExceptionType.badResponse,
            error: const ServerFailure(statusCode: 409),
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: _listPath),
              statusCode: 409,
              data: <String, dynamic>{
                'success': false,
                'data': <String, dynamic>{'code': 'SOMETHING_ELSE'},
              },
            ),
          ),
        );

        final failure = await repository
            .create(
              const MasterServiceCreate(
                name: 'Манікюр класичний',
                durationMinutes: 60,
                priceType: ServicePriceType.fixed,
                price: 500,
                category: 'MANICURE',
                serviceTypeId: _serviceTypeId,
              ),
            )
            .then<Object?>((_) => null, onError: (Object e) => e);

        // Falls through to the interceptor-attached generic ServerFailure.
        expect(failure, isNot(isA<ServiceDuplicateFailure>()));
        expect(failure, isA<ServerFailure>());
      },
    );
  });

  // ── 7. empty masterId — UnauthorizedFailure without network call ───────────

  group('empty masterId guard', () {
    late HttpServiceRepository unauthRepo;

    setUp(() {
      unauthRepo = HttpServiceRepository(
        serviceApi: serviceApi,
        categoryApi: categoryApi,
        catalogApi: catalogApi,
        dio: Dio(),
        masterId: '',
      );
    });

    test(
      'listMyServices throws UnauthorizedFailure without making a network call',
      () async {
        await expectLater(
          unauthRepo.listMyServices(),
          throwsA(isA<UnauthorizedFailure>()),
        );

        verifyNever(() => serviceApi.getMyServices());
      },
    );

    test(
      'create throws UnauthorizedFailure without making a network call',
      () async {
        await expectLater(
          unauthRepo.create(
            const MasterServiceCreate(
              name: 'Test',
              durationMinutes: 30,
              priceType: ServicePriceType.fixed,
              price: 100,
              category: 'MANICURE',
            ),
          ),
          throwsA(isA<UnauthorizedFailure>()),
        );

        verifyNever(
          () => serviceApi.addIndependentMasterService(
            createServiceDefinitionRequest: any(
              named: 'createServiceDefinitionRequest',
            ),
          ),
        );
      },
    );

    test(
      'deactivate throws UnauthorizedFailure without making a network call',
      () async {
        await expectLater(
          unauthRepo.deactivate(_serviceId),
          throwsA(isA<UnauthorizedFailure>()),
        );

        verifyNever(
          () => serviceApi.deactivateServiceDefinition(
            serviceDefId: any(named: 'serviceDefId'),
          ),
        );
      },
    );
  });

  // ── 7b. _assertAuthenticated — the phase 314 D4 matrix ─────────────────────
  //
  // `_assertAuthenticated()` is the repository's readiness guard. Phase 314
  // gave it a SECOND arm rather than widening the first:
  //
  //   | target                          | masterId   | expected             |
  //   |---------------------------------|------------|----------------------|
  //   | null (independent master)       | non-empty  | passes               |
  //   | null (independent master)       | ''         | UnauthorizedFailure  |
  //   | SalonMasterTarget (both set)    | '' (owner) | PASSES               |
  //   | SalonMasterTarget(salonId: '')  | anything   | UnauthorizedFailure  |
  //
  // Row 3 is the whole point of the second arm: in salon mode the acting user
  // is a SALON_OWNER/SALON_ADMIN who has NO master row of their own, so
  // `_masterId` is legitimately '' and the first arm would reject every call.
  // Row 2 is the arm that must survive that change — it is pinned separately
  // for exactly that reason.
  //
  // Driven through `listMyServices()` because it is the first thing the guard
  // runs on and `verifyNever` proves the guard fired BEFORE any network call.

  group('_assertAuthenticated D4 matrix', () {
    /// [sessionUserId] is the signed-in principal's User UUID — the salon
    /// arm's session-readiness evidence. It defaults to a non-empty value
    /// here because every row below is about the TARGET/masterId axes, not
    /// the session axis: "salon target on an unauthenticated session" is not
    /// expressible on the guard alone (D4 row 3 exists precisely to allow an
    /// empty `masterId` in salon mode, so the repository holds no other
    /// session evidence) and is pinned at the provider seam instead —
    /// `service_repository_provider_test`'s row 5.
    HttpServiceRepository repoWith({
      required String masterId,
      ServiceTarget? target,
      String sessionUserId = 'user-row-uuid',
      Dio? dio,
    }) => HttpServiceRepository(
      serviceApi: serviceApi,
      categoryApi: categoryApi,
      catalogApi: catalogApi,
      dio: dio ?? Dio(),
      masterId: masterId,
      target: target,
      sessionUserId: sessionUserId,
    );

    test('row 1 — target null + non-empty masterId → PASSES (the independent '
        'master, i.e. every shipped call site today)', () async {
      when(
        () => serviceApi.getMyServices(),
      ).thenAnswer((_) async => _listResponse(const []));

      await expectLater(
        repoWith(masterId: _masterId).listMyServices(),
        completion(isEmpty),
      );

      verify(() => serviceApi.getMyServices()).called(1);
    });

    test(
      'row 2 — target null + EMPTY masterId → throws UnauthorizedFailure with '
      'no network call (the arm a "just make salon mode work" edit deletes)',
      () async {
        await expectLater(
          repoWith(masterId: '').listMyServices(),
          throwsA(isA<UnauthorizedFailure>()),
        );

        verifyNever(() => serviceApi.getMyServices());
      },
    );

    test(
      'row 3 — SalonMasterTarget + EMPTY masterId → PASSES; an owner/admin has '
      'no master row of their own, so an empty masterId is legitimate here',
      () async {
        // Phase 315 D1 — a SalonMasterTarget now DISPATCHES to the raw-Dio
        // salon GET (see the dedicated "salon-target dispatch" group above),
        // never `serviceApi.getMyServices()`. This row's job is ONLY the
        // readiness guard (`_assertAuthenticated` must not throw with an
        // empty masterId in salon mode), so the mocked Dio just needs to
        // resolve — the URI itself is pinned by the dispatch group.
        final mockDio = _MockDio();
        when(() => mockDio.get<Object?>(any())).thenAnswer(
          (_) async => Response<Object?>(
            requestOptions: RequestOptions(
              path:
                  '/api/v1/salons/salon-row-uuid/masters/master-row-uuid/services',
            ),
            statusCode: 200,
            data: <String, Object?>{'success': true, 'data': <Object?>[]},
          ),
        );

        await expectLater(
          repoWith(
            masterId: '',
            target: const SalonMasterTarget(
              salonId: 'salon-row-uuid',
              // The `masters` ROW id — NOT a userId. A userId on
              // /salons/{s}/masters/{m}/... yields 404, not 403.
              masterId: 'master-row-uuid',
            ),
            dio: mockDio,
          ).listMyServices(),
          completion(isEmpty),
        );

        verifyNever(() => serviceApi.getMyServices());
      },
    );

    test(
      'row 4 — SalonMasterTarget with an EMPTY salonId → throws '
      'UnauthorizedFailure with no network call, whatever masterId says',
      () async {
        const unresolved = SalonMasterTarget(
          salonId: '',
          masterId: 'master-row-uuid',
        );

        // Non-empty masterId on the repository: proves the salon arm is what
        // rejected the call, not a fallback onto the independent-master arm.
        await expectLater(
          repoWith(masterId: _masterId, target: unresolved).listMyServices(),
          throwsA(isA<UnauthorizedFailure>()),
        );

        // And with an empty one too.
        await expectLater(
          repoWith(masterId: '', target: unresolved).listMyServices(),
          throwsA(isA<UnauthorizedFailure>()),
        );

        verifyNever(() => serviceApi.getMyServices());
      },
    );

    test('row 4b — SalonMasterTarget with an EMPTY masterId → throws '
        'UnauthorizedFailure with no network call', () async {
      await expectLater(
        repoWith(
          masterId: _masterId,
          target: const SalonMasterTarget(
            salonId: 'salon-row-uuid',
            masterId: '',
          ),
        ).listMyServices(),
        throwsA(isA<UnauthorizedFailure>()),
      );

      verifyNever(() => serviceApi.getMyServices());
    });
  });

  // ── 8. fetchApprovedCategories ──────────────────────────────────────────────

  group('fetchApprovedCategories', () {
    Response<ApiResponseListApprovedCategoryResponse> approvedResponse(
      List<ApprovedCategoryResponse> items,
    ) {
      final envelope = ApiResponseListApprovedCategoryResponse(
        (b) => b
          ..data = ListBuilder<ApprovedCategoryResponse>(items)
          ..success = true,
      );
      return Response<ApiResponseListApprovedCategoryResponse>(
        data: envelope,
        requestOptions: RequestOptions(
          path: '/api/v1/service-categories/approved',
        ),
        statusCode: 200,
      );
    }

    ApprovedCategoryResponse approvedDto(String name, String displayName) =>
        (ApprovedCategoryResponseBuilder()
              ..name = name
              ..displayName = displayName)
            .build();

    test('maps approved categories preserving name + displayName', () async {
      when(() => categoryApi.listApproved()).thenAnswer(
        (_) async => approvedResponse(<ApprovedCategoryResponse>[
          approvedDto('MANICURE', 'Манікюр'),
          approvedDto('NAIL_ART', 'Нейл-арт'),
        ]),
      );

      final result = await repository.fetchApprovedCategories();

      expect(result.map((o) => o.name).toList(), <String>[
        'MANICURE',
        'NAIL_ART',
      ]);
      expect(result.first.displayName, 'Манікюр');
    });

    test('returns empty list when envelope data is null', () async {
      final envelope = ApiResponseListApprovedCategoryResponse(
        (b) => b..success = true,
      );
      when(() => categoryApi.listApproved()).thenAnswer(
        (_) async => Response<ApiResponseListApprovedCategoryResponse>(
          data: envelope,
          requestOptions: RequestOptions(
            path: '/api/v1/service-categories/approved',
          ),
          statusCode: 200,
        ),
      );

      expect(await repository.fetchApprovedCategories(), isEmpty);
    });

    test('maps DioException to a Failure', () async {
      when(() => categoryApi.listApproved()).thenThrow(
        DioException(
          requestOptions: RequestOptions(
            path: '/api/v1/service-categories/approved',
          ),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.fetchApprovedCategories(),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  // ── 9. requestCategory ──────────────────────────────────────────────────────

  group('requestCategory', () {
    Response<ApiResponseCategoryRequestResponse> createdResponse() {
      final dto =
          (CategoryRequestResponseBuilder()
                ..name = 'NAIL_ART'
                ..displayName = 'Нейл-арт'
                ..status = 'PENDING')
              .build();
      final envelope = ApiResponseCategoryRequestResponse(
        (b) => b
          ..data.replace(dto)
          ..success = true,
      );
      return Response<ApiResponseCategoryRequestResponse>(
        data: envelope,
        requestOptions: RequestOptions(
          path: '/api/v1/service-categories/requests',
        ),
        statusCode: 201,
      );
    }

    DioException dioWithStatus(int status) => DioException(
      requestOptions: RequestOptions(
        path: '/api/v1/service-categories/requests',
      ),
      response: Response<dynamic>(
        requestOptions: RequestOptions(
          path: '/api/v1/service-categories/requests',
        ),
        statusCode: status,
      ),
      type: DioExceptionType.badResponse,
    );

    test('success forwards the correct name + displayName once', () async {
      when(
        () => categoryApi.submitRequest(
          createCategoryRequestRequest: any(
            named: 'createCategoryRequestRequest',
          ),
        ),
      ).thenAnswer((_) async => createdResponse());

      await repository.requestCategory(
        name: 'NAIL_ART',
        displayName: 'Нейл-арт',
      );

      final captured =
          verify(
                () => categoryApi.submitRequest(
                  createCategoryRequestRequest: captureAny(
                    named: 'createCategoryRequestRequest',
                  ),
                ),
              ).captured.single
              as CreateCategoryRequestRequest;
      expect(captured.name, 'NAIL_ART');
      expect(captured.displayName, 'Нейл-арт');
    });

    // ── Change 3 — optional initialServiceName wire shape ─────────────────────
    // Mirrors the suggestServiceType description-omission guard: the value is
    // attached to the request model ONLY when non-empty; a blank/whitespace
    // value must be omitted (null on the wire), and a real value is trimmed.

    test(
      'Change 3: non-empty initialServiceName is forwarded (trimmed) on the body',
      () async {
        when(
          () => categoryApi.submitRequest(
            createCategoryRequestRequest: any(
              named: 'createCategoryRequestRequest',
            ),
          ),
        ).thenAnswer((_) async => createdResponse());

        await repository.requestCategory(
          name: 'NAIL_ART',
          displayName: 'Нейл-арт',
          initialServiceName: '  Ламінування вій  ',
        );

        final captured =
            verify(
                  () => categoryApi.submitRequest(
                    createCategoryRequestRequest: captureAny(
                      named: 'createCategoryRequestRequest',
                    ),
                  ),
                ).captured.single
                as CreateCategoryRequestRequest;
        expect(captured.initialServiceName, 'Ламінування вій');
      },
    );

    test(
      'Change 3: null initialServiceName → request.initialServiceName omitted',
      () async {
        when(
          () => categoryApi.submitRequest(
            createCategoryRequestRequest: any(
              named: 'createCategoryRequestRequest',
            ),
          ),
        ).thenAnswer((_) async => createdResponse());

        await repository.requestCategory(
          name: 'NAIL_ART',
          displayName: 'Нейл-арт',
          // initialServiceName omitted (defaults to null).
        );

        final captured =
            verify(
                  () => categoryApi.submitRequest(
                    createCategoryRequestRequest: captureAny(
                      named: 'createCategoryRequestRequest',
                    ),
                  ),
                ).captured.single
                as CreateCategoryRequestRequest;
        expect(captured.initialServiceName, isNull);
      },
    );

    test(
      'Change 3: blank / whitespace initialServiceName → omitted (null on wire)',
      () async {
        when(
          () => categoryApi.submitRequest(
            createCategoryRequestRequest: any(
              named: 'createCategoryRequestRequest',
            ),
          ),
        ).thenAnswer((_) async => createdResponse());

        await repository.requestCategory(
          name: 'NAIL_ART',
          displayName: 'Нейл-арт',
          initialServiceName: '   ',
        );

        final captured =
            verify(
                  () => categoryApi.submitRequest(
                    createCategoryRequestRequest: captureAny(
                      named: 'createCategoryRequestRequest',
                    ),
                  ),
                ).captured.single
                as CreateCategoryRequestRequest;
        expect(
          captured.initialServiceName,
          isNull,
          reason: 'a blank optional name must not be sent as an empty string',
        );
      },
    );

    test('409 → CategoryAlreadyExistsFailure', () async {
      when(
        () => categoryApi.submitRequest(
          createCategoryRequestRequest: any(
            named: 'createCategoryRequestRequest',
          ),
        ),
      ).thenThrow(dioWithStatus(409));

      await expectLater(
        repository.requestCategory(name: 'NAIL_ART', displayName: 'Нейл-арт'),
        throwsA(isA<CategoryAlreadyExistsFailure>()),
      );
    });

    test('429 → CategoryRequestThrottledFailure', () async {
      when(
        () => categoryApi.submitRequest(
          createCategoryRequestRequest: any(
            named: 'createCategoryRequestRequest',
          ),
        ),
      ).thenThrow(dioWithStatus(429));

      await expectLater(
        repository.requestCategory(name: 'NAIL_ART', displayName: 'Нейл-арт'),
        throwsA(isA<CategoryRequestThrottledFailure>()),
      );
    });

    test('other status → generic Failure (ServerFailure)', () async {
      when(
        () => categoryApi.submitRequest(
          createCategoryRequestRequest: any(
            named: 'createCategoryRequestRequest',
          ),
        ),
      ).thenThrow(dioWithStatus(500));

      await expectLater(
        repository.requestCategory(name: 'NAIL_ART', displayName: 'Нейл-арт'),
        throwsA(isA<ServerFailure>()),
      );
    });
  });
}
