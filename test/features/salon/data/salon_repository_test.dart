// Phase 2.19 — Unit tests for [HttpSalonRepository] + [SalonCreateDto].
//
// Strategy: mock the [Dio] instance with mocktail and drive `create`.
// Verifies:
//   1. create POSTs /salons with the full body when all fields are present.
//   2. SalonCreateDto.toJson omits null/empty optionals (districtId, note).
//   3. A bad-response DioException surfaces as ServerFailure (with status).
//   4. A connectionError DioException surfaces as NetworkFailure.
//   5. A pre-mapped Failure attached as e.error is re-thrown unchanged.
//   6. getSiblingSalons goes through the GENERATED SalonControllerApi (not a
//      raw Dio GET), normalises the rows, and maps a 403 to ServerFailure.
//   7. A malformed 2xx sibling payload degrades to its readable rows rather
//      than dead-ending the destination picker — but never to an empty list.
//
// Pure Dart: no ProviderScope, no widget tree.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

class _MockSalonApi extends Mock implements SalonControllerApi {}

class _MockServiceApi extends Mock implements ServiceControllerApi {}

class _MockReviewApi extends Mock implements ReviewControllerApi {}

class _MockMediaApi extends Mock implements MediaControllerApi {}

Response<Map<String, dynamic>> _okEnvelope() => Response<Map<String, dynamic>>(
  requestOptions: RequestOptions(path: '/api/v1/salons'),
  statusCode: 201,
  data: const {'success': true, 'data': <String, dynamic>{}, 'message': 'ok'},
);

SiblingSalonOption _sibling({
  required String id,
  String name = 'Салон',
  String? street,
  String? buildingNo,
}) => SiblingSalonOption(
  (SiblingSalonOptionBuilder b) => b
    ..id = id
    ..name = name
    ..street = street
    ..buildingNo = buildingNo,
);

Response<ApiResponseListSiblingSalonOption> _siblingEnvelope(
  Iterable<SiblingSalonOption>? rows,
) => Response<ApiResponseListSiblingSalonOption>(
  requestOptions: RequestOptions(path: '/api/v1/salons/s-1/sibling-salons'),
  statusCode: 200,
  data: ApiResponseListSiblingSalonOption(
    (ApiResponseListSiblingSalonOptionBuilder b) => b
      ..success = true
      ..message = 'ok'
      ..data = rows == null ? null : ListBuilder<SiblingSalonOption>(rows),
  ),
);

void main() {
  late _MockDio dio;
  late _MockSalonApi salonApi;
  late HttpSalonRepository repository;

  setUp(() {
    dio = _MockDio();
    salonApi = _MockSalonApi();
    repository = HttpSalonRepository(
      dio,
      salonApi,
      _MockServiceApi(),
      _MockReviewApi(),
      _MockMediaApi(),
    );
  });

  group('SalonCreateDto.toJson', () {
    test('includes all fields when present', () {
      const dto = SalonCreateDto(
        name: 'Salon Lumière',
        cityId: 'city-1',
        districtId: 'district-1',
        street: 'вул. Хрещатик',
        buildingNo: '12А',
        locationNote: '3 поверх',
        phone: '+380501112233',
      );

      expect(dto.toJson(), {
        'name': 'Salon Lumière',
        'cityId': 'city-1',
        'street': 'вул. Хрещатик',
        'buildingNo': '12А',
        'districtId': 'district-1',
        'locationNote': '3 поверх',
        'phone': '+380501112233',
      });
    });

    test('omits null/empty districtId and note', () {
      const dto = SalonCreateDto(
        name: 'Salon',
        cityId: 'city-1',
        districtId: null,
        street: 'St.',
        buildingNo: '8',
        locationNote: '   ', // whitespace-only → omitted
      );

      final json = dto.toJson();
      expect(json.containsKey('districtId'), isFalse);
      expect(json.containsKey('locationNote'), isFalse);
      expect(json['name'], 'Salon');
      expect(json['cityId'], 'city-1');
    });

    test('includes phone when non-null and non-empty', () {
      const dto = SalonCreateDto(
        name: 'Salon',
        cityId: 'city-1',
        street: 'St.',
        buildingNo: '8',
        phone: '+380501112233',
      );
      expect(dto.toJson()['phone'], '+380501112233');
    });

    test('omits phone when null', () {
      const dto = SalonCreateDto(
        name: 'Salon',
        cityId: 'city-1',
        street: 'St.',
        buildingNo: '8',
        // phone: null (default)
      );
      expect(dto.toJson().containsKey('phone'), isFalse);
    });

    test('omits phone when empty string', () {
      const dto = SalonCreateDto(
        name: 'Salon',
        cityId: 'city-1',
        street: 'St.',
        buildingNo: '8',
        phone: '',
      );
      expect(dto.toJson().containsKey('phone'), isFalse);
    });

    test('omits phone when whitespace-only', () {
      const dto = SalonCreateDto(
        name: 'Salon',
        cityId: 'city-1',
        street: 'St.',
        buildingNo: '8',
        phone: '   ',
      );
      expect(dto.toJson().containsKey('phone'), isFalse);
    });

    // Phase 21.3 QA follow-up — instagramUrl is an ADDITIVE field this phase
    // added to SalonCreateDto (RegisterSalonScreen is the first caller that
    // ever collects one). Mirrors the phone omission group above exactly —
    // this coverage was missing entirely before this file: neither the
    // "includes all fields when present" nor any omission case above ever
    // set instagramUrl, so nothing pinned that it reaches the wire OR that
    // it is correctly omitted when empty.
    test('includes instagramUrl when non-null and non-empty', () {
      const dto = SalonCreateDto(
        name: 'Salon',
        cityId: 'city-1',
        street: 'St.',
        buildingNo: '8',
        instagramUrl: 'velvet_salon',
      );
      expect(dto.toJson()['instagramUrl'], 'velvet_salon');
    });

    test('omits instagramUrl when null', () {
      const dto = SalonCreateDto(
        name: 'Salon',
        cityId: 'city-1',
        street: 'St.',
        buildingNo: '8',
        // instagramUrl: null (default)
      );
      expect(dto.toJson().containsKey('instagramUrl'), isFalse);
    });

    test('omits instagramUrl when empty string', () {
      const dto = SalonCreateDto(
        name: 'Salon',
        cityId: 'city-1',
        street: 'St.',
        buildingNo: '8',
        instagramUrl: '',
      );
      expect(dto.toJson().containsKey('instagramUrl'), isFalse);
    });

    test('omits instagramUrl when whitespace-only', () {
      const dto = SalonCreateDto(
        name: 'Salon',
        cityId: 'city-1',
        street: 'St.',
        buildingNo: '8',
        instagramUrl: '   ',
      );
      expect(dto.toJson().containsKey('instagramUrl'), isFalse);
    });

    test('POSTs a body carrying instagramUrl when set (real wire round '
        'trip through create())', () async {
      const dto = SalonCreateDto(
        name: 'Salon',
        cityId: 'city-1',
        street: 'St.',
        buildingNo: '8',
        instagramUrl: 'velvet_salon',
      );
      when(
        () => dio.post<Map<String, dynamic>>(
          '/api/v1/salons',
          data: dto.toJson(),
        ),
      ).thenAnswer((_) async => _okEnvelope());

      await repository.create(dto: dto);

      verify(
        () => dio.post<Map<String, dynamic>>(
          '/api/v1/salons',
          data: <String, dynamic>{
            'name': 'Salon',
            'cityId': 'city-1',
            'street': 'St.',
            'buildingNo': '8',
            'instagramUrl': 'velvet_salon',
          },
        ),
      ).called(1);
    });
  });

  group('create', () {
    test('POSTs /salons with the DTO body', () async {
      const dto = SalonCreateDto(
        name: 'Salon',
        cityId: 'city-1',
        districtId: 'district-1',
        street: 'St.',
        buildingNo: '8',
      );
      when(
        () => dio.post<Map<String, dynamic>>(
          '/api/v1/salons',
          data: dto.toJson(),
        ),
      ).thenAnswer((_) async => _okEnvelope());

      await repository.create(dto: dto);

      verify(
        () => dio.post<Map<String, dynamic>>(
          '/api/v1/salons',
          data: dto.toJson(),
        ),
      ).called(1);
    });

    test('bad-response DioException → ServerFailure with status', () async {
      const dto = SalonCreateDto(
        name: 'Salon',
        cityId: 'city-1',
        street: 'St.',
        buildingNo: '8',
      );
      when(
        () => dio.post<Map<String, dynamic>>(
          '/api/v1/salons',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/salons'),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/api/v1/salons'),
            statusCode: 422,
          ),
        ),
      );

      await expectLater(
        repository.create(dto: dto),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 422),
        ),
      );
    });

    test('connectionError DioException → NetworkFailure', () async {
      const dto = SalonCreateDto(
        name: 'Salon',
        cityId: 'city-1',
        street: 'St.',
        buildingNo: '8',
      );
      when(
        () => dio.post<Map<String, dynamic>>(
          '/api/v1/salons',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/salons'),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.create(dto: dto),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('pre-mapped Failure on e.error is re-thrown unchanged', () async {
      const dto = SalonCreateDto(
        name: 'Salon',
        cityId: 'city-1',
        street: 'St.',
        buildingNo: '8',
      );
      const mapped = ValidationFailure(fieldErrors: {'name': 'taken'});
      when(
        () => dio.post<Map<String, dynamic>>(
          '/api/v1/salons',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/salons'),
          type: DioExceptionType.badResponse,
          error: mapped,
        ),
      );

      await expectLater(repository.create(dto: dto), throwsA(same(mapped)));
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Phase 21.6 — getSiblingSalons, after the OpenAPI snapshot refresh.
  //
  // These pin the thing that CHANGED: the call now goes through the
  // GENERATED `SalonControllerApi.getSiblingSalons` instead of a raw
  // `dio.get`. The `verifyNever` below is the load-bearing half — without it
  // a silent regression back to the hand-rolled GET would still satisfy the
  // returned-rows assertion via a re-added mapper.
  // ───────────────────────────────────────────────────────────────────────
  group('getSiblingSalons', () {
    test(
      'calls the GENERATED client with salonId and normalises the rows',
      () async {
        when(() => salonApi.getSiblingSalons(salonId: 's-1')).thenAnswer(
          (_) async => _siblingEnvelope(<SiblingSalonOption>[
            _sibling(id: 'a', name: 'A', street: '  вул. Хрещатик  '),
            _sibling(id: '', name: 'Порожній id'),
            _sibling(id: 'b', name: 'B', street: '   ', buildingNo: ''),
          ]),
        );

        final List<SiblingSalonOption> out = await repository.getSiblingSalons(
          's-1',
        );

        expect(out.map((SiblingSalonOption o) => o.id), <String>['a', 'b']);
        expect(out.first.street, 'вул. Хрещатик');
        expect(out.last.street, isNull);
        expect(out.last.buildingNo, isNull);
        verify(() => salonApi.getSiblingSalons(salonId: 's-1')).called(1);
        // `verifyZeroInteractions`, NOT `verifyNever(dio.get<Map<..>>(any()))`.
        // The narrow form was mutation-probed and found VACUOUS against a
        // realistic regression: a re-added raw
        // `dio.get<Map<String, dynamic>>(path, queryParameters: {...})` — and
        // likewise a `dio.get<List<dynamic>>(...)` — leaves it GREEN, because
        // mocktail matches the named-argument set and the type argument, not
        // just the member name. `verifyZeroInteractions` catches ANY call on
        // the raw Dio, whatever its shape, which is the actual contract:
        // this read touches the generated client ONLY.
        verifyZeroInteractions(dio);
      },
    );

    test('a null envelope data maps to an empty list, never null', () async {
      when(
        () => salonApi.getSiblingSalons(salonId: 's-1'),
      ).thenAnswer((_) async => _siblingEnvelope(null));

      expect(await repository.getSiblingSalons('s-1'), isEmpty);
    });

    test('403 DioException → ServerFailure(403), unchanged mapping', () async {
      when(() => salonApi.getSiblingSalons(salonId: 's-1')).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/sibling-salons'),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/sibling-salons'),
            statusCode: 403,
          ),
        ),
      );

      await expectLater(
        repository.getSiblingSalons('s-1'),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 403),
        ),
      );
    });

    test('connectionError DioException → NetworkFailure', () async {
      when(() => salonApi.getSiblingSalons(salonId: 's-1')).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/sibling-salons'),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.getSiblingSalons('s-1'),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Phase 21.6 QA — getSiblingSalons at the WIRE level.
  //
  // Every test above hands the repository a pre-built `SiblingSalonOption`,
  // so none of them can express a malformed payload: the built_value type
  // makes an absent/non-String `id` unconstructable in Dart. That is exactly
  // why the two old mapper cases ("row is not a JSON object", "non-String or
  // absent name") were dropped — but dropping them removed the ONLY coverage
  // of what the app does with such a payload, and the compile fix CHANGED
  // that behaviour: a malformed row used to be dropped silently, leaving the
  // picker usable; it now fails the WHOLE call.
  //
  // These tests therefore drive a REAL `SalonControllerApi` over a mocked
  // `Dio.request`, so the generated built_value deserializer actually runs.
  // They pin the new contract end-to-end:
  //   malformed wire → DeserializationError → DioException(unknown)
  //                  → ServerFailure for the whole call (empty picker gone,
  //                    `MoveAdminSalonScreen` renders `ErrorState` + retry).
  //
  // The two "safe" cases below matter just as much: an explicit `null`
  // address and an UNKNOWN extra field must NOT trip the same wire, or every
  // pre-Phase-10.6 salon and every additive backend field would blank the
  // picker for real.
  // ───────────────────────────────────────────────────────────────────────
  group('getSiblingSalons — real deserializer over a mocked transport', () {
    late HttpSalonRepository wireRepository;

    /// Stubs the ONE call the generated `SalonControllerApi.getSiblingSalons`
    /// makes, returning [body] as the raw (already JSON-decoded) response.
    void stubWire(Object? body) {
      when(
        () => dio.request<Object>(
          any(),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
          onSendProgress: any(named: 'onSendProgress'),
          onReceiveProgress: any(named: 'onReceiveProgress'),
        ),
      ).thenAnswer(
        (_) async => Response<Object>(
          requestOptions: RequestOptions(
            path: '/api/v1/salons/s-1/sibling-salons',
          ),
          statusCode: 200,
          data: body,
        ),
      );
    }

    Map<String, dynamic> envelope(List<dynamic> rows) => <String, dynamic>{
      'success': true,
      'message': 'ok',
      'data': rows,
    };

    setUp(() {
      // The REAL generated client, wired to the mocked Dio and the SAME
      // `standardSerializers` the app uses at runtime.
      wireRepository = HttpSalonRepository(
        dio,
        SalonControllerApi(dio, standardSerializers),
        _MockServiceApi(),
        _MockReviewApi(),
        _MockMediaApi(),
      );
    });

    // Positive control: without this, a green malformed-payload test could be
    // green because the wire never deserializes at all.
    test('a well-formed wire payload round-trips through the mapper', () async {
      stubWire(
        envelope(<dynamic>[
          <String, dynamic>{
            'id': 'salon-2',
            'name': 'Студія «Камелія»',
            'street': '  вул. Хрещатик  ',
            'buildingNo': ' 12 ',
          },
        ]),
      );

      final List<SiblingSalonOption> out = await wireRepository
          .getSiblingSalons('s-1');

      expect(out, hasLength(1));
      expect(out.single.id, 'salon-2');
      expect(out.single.name, 'Студія «Камелія»');
      expect(out.single.street, 'вул. Хрещатик');
      expect(out.single.buildingNo, '12');
    });

    // REPLACES the dropped mapper case 'drops a row that is not a JSON
    // object'. UPDATED for the Phase 21.6 QA MEDIUM recoverability fix: the
    // row still never reaches the mapper through the envelope deserializer,
    // but `_salvageSiblingSalons` re-reads the raw 2xx body row by row, so the
    // healthy sibling is returned and only the broken row is lost. Retry on a
    // dead-end ErrorState is no longer the owner's only option.
    test('a row that is not a JSON object is dropped per-row — the healthy '
        'sibling still resolves', () async {
      stubWire(
        envelope(<dynamic>[
          <String, dynamic>{'id': 'salon-2', 'name': 'Ціла'},
          'not-an-object',
        ]),
      );

      final List<SiblingSalonOption> out = await wireRepository
          .getSiblingSalons('s-1');

      expect(
        out.map((SiblingSalonOption o) => o.id),
        <String>['salon-2'],
        reason:
            'the whole-envelope deserializer rejects this payload, so the '
            'salvage path must recover the readable rows; the picker '
            'degrades to N-1 destinations instead of blocking rotation '
            'entirely.',
      );
      expect(out.single.name, 'Ціла');
    });

    // The salvage must NEVER manufacture an empty list: `[]` renders "you own
    // no other salon" on the move-admin screen, so degrading an unreadable
    // payload to `[]` would state something false. Zero survivors stays a
    // whole-call ServerFailure — and there the ErrorState retry is honest,
    // because a total contract break is fixed by a backend redeploy.
    test('a payload whose every row is malformed still fails the whole call — '
        'it never degrades to a false empty picker', () async {
      stubWire(
        envelope(<dynamic>[
          'not-an-object',
          <String, dynamic>{'id': 'salon-2'},
        ]),
      );

      await expectLater(
        wireRepository.getSiblingSalons('s-1'),
        throwsA(isA<ServerFailure>()),
      );
    });

    // Guards the salvage gate from being widened to any DioException: an
    // error envelope must never be mined for rows. Thrown (not returned)
    // because a real 403 reaches the repository as a thrown DioException.
    test('a non-2xx response is NOT salvaged even when its body carries '
        'readable rows', () async {
      when(
        () => dio.request<Object>(
          any(),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
          onSendProgress: any(named: 'onSendProgress'),
          onReceiveProgress: any(named: 'onReceiveProgress'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(
            path: '/api/v1/salons/s-1/sibling-salons',
          ),
          type: DioExceptionType.badResponse,
          response: Response<Object>(
            requestOptions: RequestOptions(
              path: '/api/v1/salons/s-1/sibling-salons',
            ),
            statusCode: 403,
            data: envelope(<dynamic>[
              <String, dynamic>{'id': 'salon-2', 'name': 'Ціла'},
            ]),
          ),
        ),
      );

      await expectLater(
        wireRepository.getSiblingSalons('s-1'),
        throwsA(
          isA<ServerFailure>().having(
            (ServerFailure f) => f.statusCode,
            'statusCode',
            403,
          ),
        ),
      );
    });

    // REPLACES the dropped mapper case 'a non-String or absent name collapses
    // to empty, row still kept'. `name` is a required non-nullable String on
    // the generated model, so "kept with an empty name" is unreachable — and
    // this payload's ONLY row is the broken one, so nothing is salvageable
    // and the call fails as a whole.
    test('an absent required name fails the whole call', () async {
      stubWire(
        envelope(<dynamic>[
          <String, dynamic>{'id': 'salon-2'},
        ]),
      );

      await expectLater(
        wireRepository.getSiblingSalons('s-1'),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('a non-String name fails the whole call', () async {
      stubWire(
        envelope(<dynamic>[
          <String, dynamic>{'id': 'salon-2', 'name': 42},
        ]),
      );

      await expectLater(
        wireRepository.getSiblingSalons('s-1'),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('an absent required id fails the whole call', () async {
      stubWire(
        envelope(<dynamic>[
          <String, dynamic>{'name': 'Без id'},
        ]),
      );

      await expectLater(
        wireRepository.getSiblingSalons('s-1'),
        throwsA(isA<ServerFailure>()),
      );
    });

    // The counterweight to the four cases above. `street`/`buildingNo` are
    // documented on the generated model as "May be null for a salon persisted
    // before Phase 10.6", and Spring serialises those as an EXPLICIT JSON
    // null. If that tripped the same whole-call failure, every owner with one
    // legacy salon would be permanently unable to rotate an administrator.
    test('an explicit null street/buildingNo keeps the row', () async {
      stubWire(
        envelope(<dynamic>[
          <String, dynamic>{
            'id': 'legacy-1',
            'name': 'Старий салон',
            'street': null,
            'buildingNo': null,
          },
        ]),
      );

      final List<SiblingSalonOption> out = await wireRepository
          .getSiblingSalons('s-1');

      expect(out, hasLength(1));
      expect(out.single.id, 'legacy-1');
      expect(out.single.street, isNull);
      expect(out.single.buildingNo, isNull);
    });

    // An ADDITIVE backend field must stay non-breaking: the generated
    // deserializer collects unknown keys into `unhandled` and ignores them.
    // Without this, nobody would notice if a future regeneration made the
    // client strict and turned every backend field addition into an outage.
    test('an unknown extra wire field is tolerated, not fatal', () async {
      stubWire(
        envelope(<dynamic>[
          <String, dynamic>{
            'id': 'salon-2',
            'name': 'Нове поле',
            'street': 'вул. Хрещатик',
            'buildingNo': '12',
            'someFieldAddedLater': <String, dynamic>{'nested': true},
          },
        ]),
      );

      final List<SiblingSalonOption> out = await wireRepository
          .getSiblingSalons('s-1');

      expect(out.single.id, 'salon-2');
      expect(out.single.name, 'Нове поле');
    });

    test('a blank id still drops ONLY its own row at the wire level', () async {
      stubWire(
        envelope(<dynamic>[
          <String, dynamic>{'id': '', 'name': 'Порожній id'},
          <String, dynamic>{'id': 'salon-2', 'name': 'Ціла'},
        ]),
      );

      final List<SiblingSalonOption> out = await wireRepository
          .getSiblingSalons('s-1');

      expect(out.map((SiblingSalonOption o) => o.id), <String>['salon-2']);
    });
  });
}
