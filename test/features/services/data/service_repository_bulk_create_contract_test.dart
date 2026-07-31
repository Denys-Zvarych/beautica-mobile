// Transport-seam regression net (2026-07-31) — bulkCreate field errors.
//
// WHY THIS FILE EXISTS
// --------------------
// Two suites already cover the halves of this path, and BOTH were green while
// the path was broken end-to-end:
//
//   • test/core/network/error_mapper_interceptor_test.dart drives
//     ErrorMapperInterceptor in isolation and proves a 400 `errors` map becomes
//     ValidationFailure.fieldErrors.
//   • test/features/services/data/service_repository_bulk_create_test.dart
//     mocks the whole `Dio`, so NO interceptor ever runs. Its `400 →
//     ValidationFailure` case asserts only `isA<ValidationFailure>()`, which is
//     equally true of the fieldErrors-DROPPING fallback branch.
//
// Nothing pinned the SEAM: that a real 400 actually arrives at the repository
// carrying the interceptor's parsed map. When `integration_test/support/
// fake_backend.dart` built its Dio without interceptors, every 400's `errors`
// map was discarded before reaching a screen:
//
//   1. 400 arrives as a DioException with `e.error == null`
//   2. service_repository.dart `_mapBulkCreateException`: `e.error is Failure`
//      is FALSE → falls through to `_mapDioException`
//   3. `_mapDioException` returns `ValidationFailure(fieldErrors: const {})` —
//      the per-field map is silently dropped
//   4. service_setup_screen.dart `_applyServerFieldErrors` iterates an empty
//      map → returns false → generic snackbar instead of inline row errors
//
// HERE the only fake is the HTTP socket (http_mock_adapter). On top of it run
// the REAL ErrorMapperInterceptor and the REAL HttpServiceRepository — the same
// composition production wires in `dioProvider` (interceptor) +
// `serviceRepositoryProvider` (repository). Shape follows the established
// precedent in test/features/auth/data/auth_repository_contract_test.dart.
//
// THE PINNED PROPERTY: a 400 whose body carries a per-field `errors` map must
// reach the caller as a ValidationFailure with THAT MAP POPULATED — asserted on
// the exact keys and values, never merely on the Failure subtype.
//
// Runs headless in CI:
//   flutter test test/features/services/data/service_repository_bulk_create_contract_test.dart

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:mocktail/mocktail.dart';

// ── Mocks (unused by bulkCreate — it POSTs through the raw Dio) ─────────────

class _MockServiceControllerApi extends Mock implements ServiceControllerApi {}

class _MockCategoryRequestControllerApi extends Mock
    implements CategoryRequestControllerApi {}

class _MockServiceCatalogControllerApi extends Mock
    implements ServiceCatalogControllerApi {}

// ── Fixtures ────────────────────────────────────────────────────────────────

const _baseUrl = 'http://localhost:8080';
const _masterId = 'master-abc';
const _bulkPath = '/api/v1/independent-masters/me/services/bulk';

const _fixedItem = MasterServiceBulkItem(
  serviceTypeId: 'type-fixed',
  durationMinutes: 600,
  priceType: ServicePriceType.fixed,
  price: 500,
);

const _rangeItem = MasterServiceBulkItem(
  serviceTypeId: 'type-range',
  durationMinutes: 90,
  priceType: ServicePriceType.range,
  priceMin: 700,
  priceMax: 1200,
);

/// The backend's `MethodArgumentNotValidException` envelope for the bulk route,
/// keyed exactly as `service_setup_screen.dart` `_applyServerFieldErrors`
/// expects (`items[<index>].<field>`). Mirrors the shape
/// `integration_test/support/fake_backend.dart` replies with when
/// `bulkRejectDurationField` is set.
Map<String, Object?> _fieldErrorEnvelope(Map<String, String> errors) =>
    <String, Object?>{
      'success': false,
      'message': 'Validation failed',
      'errors': errors,
    };

/// A wire-shape `MasterServiceResponse` as the backend returns it inside the
/// `data` array — fed through `standardSerializers`, so keys must match the
/// generated model exactly.
Map<String, Object?> _wireServiceJson({
  String id = 'svc-001',
  String name = 'Манікюр',
  num priceMin = 500,
}) => <String, Object?>{
  'id': id,
  'masterId': _masterId,
  'serviceDefinition': <String, Object?>{
    'id': 'def-$id',
    'name': name,
    'baseDurationMinutes': 60,
    'priceType': 'FIXED',
    'priceMin': priceMin,
    'priceDisplay': '${priceMin.toInt()} ₴',
    'isActive': true,
  },
  'isActive': true,
};

/// Wires the production composition over a faked socket:
///   real ErrorMapperInterceptor + real HttpServiceRepository.
///
/// REVERSION PROOF: deleting the `dio.interceptors.add(...)` line below must
/// turn the fieldErrors tests in this file RED. If they still pass, they pin
/// nothing and this file has rotted the same way its predecessors did.
({Dio dio, DioAdapter adapter, HttpServiceRepository repo}) _wire() {
  final dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      headers: const <String, dynamic>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );
  dio.interceptors.add(ErrorMapperInterceptor());
  final adapter = DioAdapter(dio: dio);
  final repo = HttpServiceRepository(
    serviceApi: _MockServiceControllerApi(),
    categoryApi: _MockCategoryRequestControllerApi(),
    catalogApi: _MockServiceCatalogControllerApi(),
    dio: dio,
    masterId: _masterId,
  );
  return (dio: dio, adapter: adapter, repo: repo);
}

/// Runs [bulkCreate] and returns whatever it threw (or `null` on success), so
/// tests can assert on the Failure's PAYLOAD rather than just its type.
Future<Object?> _captureFailure(
  HttpServiceRepository repo,
  List<MasterServiceBulkItem> items,
) =>
    repo.bulkCreate(items).then<Object?>((_) => null, onError: (Object e) => e);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // The regression this file exists for.
  // =========================================================================
  group('bulkCreate 400 — per-field errors survive the real interceptor', () {
    test('LIVE-SYMPTOM GUARD: a 400 `errors` map reaches the caller POPULATED, '
        'not as an empty ValidationFailure.fieldErrors', () async {
      final h = _wire();
      h.adapter.onPost(
        _bulkPath,
        (s) => s.reply(
          400,
          _fieldErrorEnvelope(const <String, String>{
            'items[0].durationMinutes':
                'Duration must be at most 480 minutes (8 hours)',
          }),
        ),
        data: Matchers.any,
      );

      final failure = await _captureFailure(h.repo, <MasterServiceBulkItem>[
        _fixedItem,
      ]);

      expect(failure, isA<ValidationFailure>());
      final validation = failure! as ValidationFailure;
      expect(
        validation.fieldErrors,
        isNotEmpty,
        reason:
            'THE regression. With no ErrorMapperInterceptor on the Dio, the '
            '400 arrives with `e.error == null`, `_mapBulkCreateException` '
            'falls through to `_mapDioException`, and the field map is '
            'replaced by `const {}`. service_setup_screen then shows the '
            'generic snackbar instead of the inline per-row error.',
      );
      expect(
        validation.fieldErrors['items[0].durationMinutes'],
        'Duration must be at most 480 minutes (8 hours)',
        reason:
            'The key must survive VERBATIM — service_setup_screen matches it '
            'against the `items[<index>].<field>` pattern to attribute the '
            'error to the originating service row.',
      );
    });

    test(
      'every key of a multi-field 400 survives (not just the first)',
      () async {
        final h = _wire();
        h.adapter.onPost(
          _bulkPath,
          (s) => s.reply(
            400,
            _fieldErrorEnvelope(const <String, String>{
              'items[0].durationMinutes': 'must be at most 480',
              'items[1].priceMin': 'must be greater than 0',
              'items[1].priceMax': 'must be greater than priceMin',
            }),
          ),
          data: Matchers.any,
        );

        final failure = await _captureFailure(h.repo, <MasterServiceBulkItem>[
          _fixedItem,
          _rangeItem,
        ]);

        final validation = failure! as ValidationFailure;
        expect(validation.fieldErrors, hasLength(3));
        expect(
          validation.fieldErrors['items[0].durationMinutes'],
          'must be at most 480',
        );
        expect(
          validation.fieldErrors['items[1].priceMin'],
          'must be greater than 0',
        );
        expect(
          validation.fieldErrors['items[1].priceMax'],
          'must be greater than priceMin',
        );
      },
    );

    test('the top-level `message` survives as serverMessage (the snackbar '
        'fallback when no field key maps to a submitted row)', () async {
      final h = _wire();
      h.adapter.onPost(
        _bulkPath,
        (s) => s.reply(
          400,
          _fieldErrorEnvelope(const <String, String>{
            'items[0].durationMinutes': 'must be at most 480',
          }),
        ),
        data: Matchers.any,
      );

      final failure = await _captureFailure(h.repo, <MasterServiceBulkItem>[
        _fixedItem,
      ]);

      expect(
        (failure! as ValidationFailure).serverMessage,
        'Validation failed',
      );
    });

    test('NEGATIVE CONTROL: a 400 with NO `errors` key still yields an EMPTY '
        'fieldErrors map — so the assertions above prove transmission, not a '
        'map fabricated somewhere in the chain', () async {
      final h = _wire();
      h.adapter.onPost(
        _bulkPath,
        (s) => s.reply(400, <String, Object?>{
          'success': false,
          'message': 'Validation failed',
        }),
        data: Matchers.any,
      );

      final failure = await _captureFailure(h.repo, <MasterServiceBulkItem>[
        _fixedItem,
      ]);

      expect(failure, isA<ValidationFailure>());
      expect((failure! as ValidationFailure).fieldErrors, isEmpty);
      expect((failure as ValidationFailure).serverMessage, 'Validation failed');
    });

    test('422 carries its field map through the same seam', () async {
      final h = _wire();
      h.adapter.onPost(
        _bulkPath,
        (s) => s.reply(
          422,
          _fieldErrorEnvelope(const <String, String>{
            'items[0].price': 'must be a positive amount',
          }),
        ),
        data: Matchers.any,
      );

      final failure = await _captureFailure(h.repo, <MasterServiceBulkItem>[
        _fixedItem,
      ]);

      expect(
        (failure! as ValidationFailure).fieldErrors['items[0].price'],
        'must be a positive amount',
      );
    });
  });

  // =========================================================================
  // Domain remaps that must still WIN over the interceptor's generic mapping.
  // Only provable through the real interceptor: it maps a non-auth 409 to
  // ServerFailure, and `_mapBulkCreateException` must override that.
  // =========================================================================
  group('bulkCreate 409 — repository remap beats the interceptor', () {
    test(
      'plain 409 → MasterAlreadyHasServicesFailure, NOT the ServerFailure(409) '
      'the interceptor attached',
      () async {
        final h = _wire();
        h.adapter.onPost(
          _bulkPath,
          (s) => s.reply(409, <String, Object?>{
            'success': false,
            'message': 'Master already has services',
          }),
          data: Matchers.any,
        );

        final failure = await _captureFailure(h.repo, <MasterServiceBulkItem>[
          _fixedItem,
        ]);

        expect(failure, isA<MasterAlreadyHasServicesFailure>());
      },
    );

    test('409 DUPLICATE_SERVICE → ServiceDuplicateFailure with the '
        'existingServiceDefId decoded from the body', () async {
      final h = _wire();
      h.adapter.onPost(
        _bulkPath,
        (s) => s.reply(409, <String, Object?>{
          'success': false,
          'data': <String, Object?>{
            'code': 'DUPLICATE_SERVICE',
            'serviceName': null,
            'existingServiceDefId': 'def-existing',
          },
          'message': 'This service already exists',
        }),
        data: Matchers.any,
      );

      final failure = await _captureFailure(h.repo, <MasterServiceBulkItem>[
        _fixedItem,
      ]);

      expect(failure, isA<ServiceDuplicateFailure>());
      final dup = failure! as ServiceDuplicateFailure;
      expect(dup.serviceName, isNull);
      expect(dup.existingServiceDefId, 'def-existing');
    });
  });

  // =========================================================================
  // The seam is genuinely live: the success path parses over the same socket.
  // Without this, a broken adapter wiring could make every negative test above
  // pass for the wrong reason.
  // =========================================================================
  group('bulkCreate 2xx — the same wiring parses a real success envelope', () {
    test('201 envelope → domain MasterService list', () async {
      final h = _wire();
      h.adapter.onPost(
        _bulkPath,
        (s) => s.reply(201, <String, Object?>{
          'success': true,
          'data': <Map<String, Object?>>[
            _wireServiceJson(id: 'svc-001', name: 'Манікюр', priceMin: 500),
            _wireServiceJson(id: 'svc-002', name: 'Педикюр', priceMin: 700),
          ],
        }),
        data: Matchers.any,
      );

      final result = await h.repo.bulkCreate(<MasterServiceBulkItem>[
        _fixedItem,
        _rangeItem,
      ]);

      expect(result, hasLength(2));
      expect(result.first.name, 'Манікюр');
      expect(result.first.priceMin, 500.0);
      expect(result[1].name, 'Педикюр');
    });
  });
}
