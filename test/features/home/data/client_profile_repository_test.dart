// Unit tests for [HttpClientProfileRepository.updateMyProfile].
//
// Strategy: mock the generated [UserControllerApi] with mocktail and capture the
// [UpdateProfileRequest] passed to updateMe. The headline assertion is that the
// request NEVER carries an `instagram` value (clients have no Instagram) and
// that each edit slice maps to exactly the keys it owns under the merge-onto-
// cache contract (a non-owned key is left unset, so built_value omits it from
// the wire body).
//
// Pure Dart: no ProviderScope, no widget tree.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/home/data/client_profile_repository.dart';
import 'package:beautica_mobile/features/home/domain/client_profile_update.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockUserControllerApi extends Mock implements UserControllerApi {}

Response<ApiResponseUserProfileResponse> _okUpdateResponse() =>
    Response<ApiResponseUserProfileResponse>(
      requestOptions: RequestOptions(path: '/api/v1/users/me'),
      statusCode: 200,
    );

/// Captures the [UpdateProfileRequest] passed to [UserControllerApi.updateMe].
UpdateProfileRequest _captureRequest(_MockUserControllerApi api) =>
    verify(
          () => api.updateMe(
            updateProfileRequest: captureAny(named: 'updateProfileRequest'),
          ),
        ).captured.single
        as UpdateProfileRequest;

void main() {
  late _MockUserControllerApi userApi;
  late HttpClientProfileRepository repository;

  setUpAll(() {
    registerFallbackValue(UpdateProfileRequest((b) {}));
  });

  setUp(() {
    userApi = _MockUserControllerApi();
    repository = HttpClientProfileRepository(userApi);
    when(
      () => userApi.updateMe(
        updateProfileRequest: any(named: 'updateProfileRequest'),
      ),
    ).thenAnswer((_) async => _okUpdateResponse());
  });

  group('updateMyProfile — request body shape', () {
    test(
      'the name slice sends firstName + lastName and NEVER instagram',
      () async {
        await repository.updateMyProfile(
          const ClientProfileUpdate(firstName: 'Олена', lastName: 'Ковальчук'),
        );

        final req = _captureRequest(userApi);
        expect(req.firstName, 'Олена');
        expect(req.lastName, 'Ковальчук');
        // Sibling slices not owned by this update → keys unset → omitted on wire.
        expect(req.phoneNumber, isNull);
        expect(req.cityId, isNull);
        expect(req.street, isNull);
        // THE HEADLINE GUARD: instagram is never sent for a client.
        expect(req.instagram, isNull);
      },
    );

    test('the phone slice sends phoneNumber and NEVER instagram', () async {
      await repository.updateMyProfile(
        const ClientProfileUpdate(phoneNumber: '+380 67 000 11 22'),
      );

      final req = _captureRequest(userApi);
      expect(req.phoneNumber, '+380 67 000 11 22');
      expect(req.firstName, isNull);
      expect(req.lastName, isNull);
      expect(req.instagram, isNull);
    });

    test('values are trimmed before sending', () async {
      await repository.updateMyProfile(
        const ClientProfileUpdate(
          firstName: '  Олена  ',
          lastName: '  Ковальчук ',
        ),
      );

      final req = _captureRequest(userApi);
      expect(req.firstName, 'Олена');
      expect(req.lastName, 'Ковальчук');
    });

    test(
      'a non-location update omits all location keys (preserves cached location)',
      () async {
        await repository.updateMyProfile(
          const ClientProfileUpdate(firstName: 'Оля'),
        );

        final req = _captureRequest(userApi);
        expect(req.cityId, isNull);
        expect(req.districtId, isNull);
        expect(req.street, isNull);
        expect(req.buildingNo, isNull);
        expect(req.locationNote, isNull);
      },
    );

    test('a location update with touchesLocation true sends the locality slice '
        'including a null cityId (optional for clients), NEVER any address key, '
        'and never instagram', () async {
      await repository.updateMyProfile(
        const ClientProfileUpdate(
          touchesLocation: true,
          cityId: null,
          districtId: null,
        ),
      );

      final req = _captureRequest(userApi);
      expect(req.cityId, isNull);
      // The CLIENT only edits the locality cascade — the free-text address
      // keys are NEVER sent, so the backend preserves any existing values.
      expect(req.street, isNull);
      expect(req.buildingNo, isNull);
      expect(req.locationNote, isNull);
      expect(req.instagram, isNull);
    });

    test(
      'a location update with a selected city + district sends both ids and no '
      'address keys',
      () async {
        await repository.updateMyProfile(
          const ClientProfileUpdate(
            touchesLocation: true,
            cityId: 'city-77',
            districtId: 'district-3',
          ),
        );

        final req = _captureRequest(userApi);
        expect(req.cityId, 'city-77');
        expect(req.districtId, 'district-3');
        expect(req.street, isNull);
        expect(req.buildingNo, isNull);
        expect(req.locationNote, isNull);
        expect(req.instagram, isNull);
      },
    );
  });
}
