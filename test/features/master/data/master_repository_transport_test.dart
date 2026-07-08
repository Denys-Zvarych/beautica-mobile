// Regression safety net (2026-06-02) — Fix 1.
//
// REAL-Dio transport tests for [HttpMasterRepository].
//
// WHY THIS FILE EXISTS
// --------------------
// `master_repository_test.dart` mocks the *generated* [MasterControllerApi] and
// mocks [Dio] with mocktail. That means the real HTTP request body, the real
// path resolution, and the real built_value (de)serialization NEVER run — so a
// contract or serialization drift between the Dart client and the Spring
// backend cannot be caught there. That blind spot is what let a
// "save profile → nothing persists" class of bug ship green.
//
// HERE, by contrast, we fake ONLY the HTTP socket via http_mock_adapter's
// [DioAdapter]. Everything above the socket is the production code path:
//   • the REAL [HttpMasterRepository]
//   • a REAL [Dio] (the same BaseOptions shape dioProvider builds)
//   • the REAL generated [MasterControllerApi] + [standardSerializers]
//
// So these tests exercise:
//   • the EXACT JSON body Dio puts on the wire for updateMyProfile / updateLocality
//   • the EXACT path + verb hit (PATCH /api/v1/independent-masters/me[/profile])
//   • real deserialization of a 200 ApiResponse envelope back into [Master]
//
// CONTRACT (verified against the Spring backend, 2026-06-02):
//   PATCH /api/v1/independent-masters/me/profile
//     MasterProfileUpdateRequest{ firstName, lastName, phoneNumber, bio, instagram }
//   PATCH /api/v1/independent-masters/me
//     IndependentMasterUpdateRequest{ cityId, districtId?, street, buildingNo, locationNote? }
//   GET   /api/v1/masters/me  →  ApiResponse<MasterDetailResponse>
//
// NOTE: AppConfig.baseUrl does NOT carry the /api/v1 prefix; the repository and
// generated client both prepend the full /api/v1/ segment. The Dio used here
// mirrors that exactly (baseUrl WITHOUT /api/v1) so the assembled request path
// matches production. See also app_config_path_test.dart (Fix 3 static guard).

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_update.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

// The baseUrl the production dioProvider uses — WITHOUT the /api/v1 prefix.
// Paths are resolved relative to this, so the full wire path is baseUrl + path.
const _baseUrl = 'http://localhost:8080';

const _profilePath = '/api/v1/independent-masters/me/profile';
const _localityPath = '/api/v1/independent-masters/me';
const _getMePath = '/api/v1/masters/me';

/// Minimal successful `ApiResponse<Void>` envelope the backend returns from the
/// two PATCH endpoints.
const Map<String, dynamic> _okVoidEnvelope = <String, dynamic>{
  'success': true,
  'data': null,
  'message': 'ok',
};

/// A realistic `ApiResponse<MasterDetailResponse>` 200 envelope as the backend
/// serializes it — used to prove the repository deserializes it into [Master].
Map<String, dynamic> _masterDetailEnvelope() => <String, dynamic>{
  'success': true,
  'message': 'ok',
  'data': <String, dynamic>{
    'masterId': 'master-1',
    'firstName': 'Оля',
    'lastName': 'Коваль',
    'bio': 'Майстер манікюру',
    'phoneNumber': '+380501111111',
    'instagram': '@beauty_ua',
    'city': 'Київ',
    'cityId': 'city-99',
    'oblastId': 'oblast-01',
    'avatarUrl': null,
    'avgRating': 4.5,
    'reviewCount': 12,
    'masterType': 'INDEPENDENT_MASTER',
  },
};

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late HttpMasterRepository repository;

  setUp(() {
    dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        headers: const <String, dynamic>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );
    adapter = DioAdapter(dio: dio);
    // The generated MasterControllerApi shares the SAME real Dio, so its
    // GET /masters/me goes through the same faked socket.
    final masterApi = MasterControllerApi(dio, standardSerializers);
    repository = HttpMasterRepository(dio, masterApi);
  });

  // -------------------------------------------------------------------------
  // updateMyProfile — real request body on the wire
  // -------------------------------------------------------------------------

  group('updateMyProfile — real Dio transport', () {
    test(
      'PATCHes /api/v1/independent-masters/me/profile with the exact JSON body '
      '(firstName/lastName/bio/instagram present, phoneNumber present when set)',
      () async {
        Map<String, dynamic>? sentBody;
        String? sentMethod;

        adapter.onRoute(
          _profilePath,
          (server) => server.reply(200, _okVoidEnvelope),
          request: const Request(
            method: RequestMethods.patch,
            // The matcher captures whatever body Dio actually serialized.
            data: Matchers.any,
          ),
        );

        // Intercept to capture the real outgoing request that Dio assembled.
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              sentMethod = options.method;
              sentBody = options.data as Map<String, dynamic>?;
              handler.next(options);
            },
          ),
        );

        await repository.updateMyProfile(
          const MasterUpdate(
            firstName: 'Аня',
            lastName: 'Коваль',
            bio: 'Топ майстер',
            contactPhone: '+380501111111',
            instagram: '@beauty_ua',
            professionalTitle: '',
          ),
        );

        expect(sentMethod, 'PATCH', reason: 'verb must be PATCH');
        expect(sentBody, isNotNull);
        // Exact keys the Spring MasterProfileUpdateRequest record expects.
        expect(sentBody!['firstName'], 'Аня');
        expect(sentBody!['lastName'], 'Коваль');
        expect(sentBody!['bio'], 'Топ майстер');
        expect(sentBody!['instagram'], '@beauty_ua');
        expect(
          sentBody!.containsKey('phoneNumber'),
          isTrue,
          reason: 'backend field is "phoneNumber", not "contactPhone"',
        );
        expect(sentBody!['phoneNumber'], '+380501111111');
        expect(
          sentBody!.containsKey('contactPhone'),
          isFalse,
          reason: 'the Dart param name must never leak onto the wire',
        );
      },
    );

    test(
      'sends cleared bio/instagram as empty strings (key always present)',
      () async {
        Map<String, dynamic>? sentBody;
        adapter.onRoute(
          _profilePath,
          (server) => server.reply(200, _okVoidEnvelope),
          request: const Request(
            method: RequestMethods.patch,
            data: Matchers.any,
          ),
        );
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              sentBody = options.data as Map<String, dynamic>?;
              handler.next(options);
            },
          ),
        );

        await repository.updateMyProfile(
          const MasterUpdate(
            firstName: 'Аня',
            lastName: 'Коваль',
            bio: '',
            contactPhone: '',
            instagram: '',
            professionalTitle: '',
          ),
        );

        expect(sentBody!.containsKey('bio'), isTrue);
        expect(sentBody!['bio'], '');
        expect(sentBody!.containsKey('instagram'), isTrue);
        expect(sentBody!['instagram'], '');
        expect(
          sentBody!.containsKey('phoneNumber'),
          isFalse,
          reason: 'blank phone is omitted (cannot be cleared by design)',
        );
      },
    );

    test('resolves on a real 200 ApiResponse<Void> envelope', () async {
      adapter.onRoute(
        _profilePath,
        (server) => server.reply(200, _okVoidEnvelope),
        request: const Request(
          method: RequestMethods.patch,
          data: Matchers.any,
        ),
      );

      await expectLater(
        repository.updateMyProfile(
          const MasterUpdate(
            firstName: 'Аня',
            lastName: 'Коваль',
            bio: '',
            contactPhone: '',
            instagram: '',
            professionalTitle: '',
          ),
        ),
        completes,
      );
    });

    // ── professionalTitle on the wire (feat/provider-professional-title) ──────
    //
    // Guards that professionalTitle is (a) always present in the PATCH body
    // and (b) trimmed and forwarded correctly, using the REAL Dio transport path
    // (not a mocktail stub). This tests the actual serialisation boundary between
    // the Dart client and the Spring backend contract.

    test('sends professionalTitle on the wire when set — key present, value '
        'forwarded exactly', () async {
      Map<String, dynamic>? sentBody;

      adapter.onRoute(
        _profilePath,
        (server) => server.reply(200, _okVoidEnvelope),
        request: const Request(
          method: RequestMethods.patch,
          data: Matchers.any,
        ),
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            sentBody = options.data as Map<String, dynamic>?;
            handler.next(options);
          },
        ),
      );

      await repository.updateMyProfile(
        const MasterUpdate(
          firstName: 'Аня',
          lastName: 'Коваль',
          bio: '',
          contactPhone: '',
          instagram: '',
          professionalTitle: 'Майстер манікюру',
        ),
      );

      expect(sentBody, isNotNull);
      expect(
        sentBody!.containsKey('professionalTitle'),
        isTrue,
        reason:
            'professionalTitle key must be present on the wire — the backend '
            'clear-on-empty contract requires the key to always be sent',
      );
      expect(
        sentBody!['professionalTitle'],
        'Майстер манікюру',
        reason: 'non-empty professionalTitle must be forwarded verbatim',
      );
    });

    test('sends professionalTitle as empty string on the wire when cleared — key '
        'present, value is \'\'', () async {
      Map<String, dynamic>? sentBody;

      adapter.onRoute(
        _profilePath,
        (server) => server.reply(200, _okVoidEnvelope),
        request: const Request(
          method: RequestMethods.patch,
          data: Matchers.any,
        ),
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            sentBody = options.data as Map<String, dynamic>?;
            handler.next(options);
          },
        ),
      );

      await repository.updateMyProfile(
        const MasterUpdate(
          firstName: 'Аня',
          lastName: 'Коваль',
          bio: '',
          contactPhone: '',
          instagram: '',
          professionalTitle: '',
        ),
      );

      expect(sentBody, isNotNull);
      expect(
        sentBody!.containsKey('professionalTitle'),
        isTrue,
        reason:
            'professionalTitle key must be present even when cleared — omitting '
            'it would leave the stale server value intact (same bug that once '
            'broke bio/instagram clearing)',
      );
      expect(sentBody!['professionalTitle'], '');
    });
  });

  // -------------------------------------------------------------------------
  // updateLocality — real request body on the wire
  // -------------------------------------------------------------------------

  group('updateLocality — real Dio transport', () {
    test(
      'PATCHes /api/v1/independent-masters/me with the exact locality body',
      () async {
        Map<String, dynamic>? sentBody;
        String? sentMethod;

        adapter.onRoute(
          _localityPath,
          (server) => server.reply(200, _okVoidEnvelope),
          request: const Request(
            method: RequestMethods.patch,
            data: Matchers.any,
          ),
        );
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              sentMethod = options.method;
              sentBody = options.data as Map<String, dynamic>?;
              handler.next(options);
            },
          ),
        );

        await repository.updateLocality(
          cityId: 'city-99',
          districtId: 'district-7',
          street: 'вул. Хрещатик',
          buildingNo: '12А',
          locationNote: '3 поверх',
        );

        expect(sentMethod, 'PATCH');
        expect(sentBody!['cityId'], 'city-99');
        expect(sentBody!['districtId'], 'district-7');
        expect(sentBody!['street'], 'вул. Хрещатик');
        expect(sentBody!['buildingNo'], '12А');
        expect(sentBody!['locationNote'], '3 поверх');
      },
    );

    test('omits null districtId / locationNote on the wire', () async {
      Map<String, dynamic>? sentBody;
      adapter.onRoute(
        _localityPath,
        (server) => server.reply(200, _okVoidEnvelope),
        request: const Request(
          method: RequestMethods.patch,
          data: Matchers.any,
        ),
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            sentBody = options.data as Map<String, dynamic>?;
            handler.next(options);
          },
        ),
      );

      await repository.updateLocality(
        cityId: 'city-1',
        street: 'St.',
        buildingNo: '8',
      );

      expect(sentBody!.containsKey('districtId'), isFalse);
      expect(sentBody!.containsKey('locationNote'), isFalse);
      expect(sentBody!['cityId'], 'city-1');
    });
  });

  // -------------------------------------------------------------------------
  // getMyProfile — real built_value deserialization of a 200 envelope
  // -------------------------------------------------------------------------

  group('getMyProfile — real Dio + real serialization', () {
    test('GET /api/v1/masters/me parses the envelope into a Master', () async {
      adapter.onRoute(
        _getMePath,
        (server) => server.reply(200, _masterDetailEnvelope()),
        request: const Request(method: RequestMethods.get),
      );

      final master = await repository.getMyProfile('master-1');

      expect(master.id, 'master-1');
      expect(master.firstName, 'Оля');
      expect(master.lastName, 'Коваль');
      expect(master.bio, 'Майстер манікюру');
      expect(master.phoneNumber, '+380501111111');
      expect(master.instagram, '@beauty_ua');
      expect(master.city, 'Київ');
      expect(master.cityId, 'city-99');
      expect(master.avgRating, 4.5);
      expect(master.reviewCount, 12);
      expect(master.type, MasterType.independentMaster);
    });
  });
}
