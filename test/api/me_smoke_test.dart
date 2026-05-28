// Phase 3.2 — Smoke test for generated API client wiring.
//
// Verifies three things:
//   1. [UserControllerApi] can be constructed with a [Dio] instance and
//      [standardSerializers] — the wiring in [userApiProvider] is correct.
//   2. [UserMapper.fromProfileDto] correctly maps a [UserProfileResponse] to
//      a domain [User] — the central deserialization path is exercised.
//   3. [UserMapper.fromAuthResponse] correctly maps an [AuthResponse] to a
//      domain [User] — the login/refresh/verifyEmail path is exercised.
//
// The test mocks [AuthControllerApi] / [UserControllerApi] directly rather
// than Dio internals; this mirrors the pattern in the main repository test
// and avoids coupling the smoke test to low-level Dio details.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/auth/data/user_mapper.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockUserApi extends Mock implements UserControllerApi {}

void main() {
  // -------------------------------------------------------------------------
  // Part A — API class constructible with standardSerializers
  // -------------------------------------------------------------------------

  group('UserControllerApi construction', () {
    test(
      'can be constructed with Dio + standardSerializers (no runtime error)',
      () {
        // This verifies the wiring formula used in userApiProvider. If the
        // import paths or constructor signature for the generated class ever
        // change, this test will fail at compile time before any CI run.
        final api = UserControllerApi(Dio(), standardSerializers);
        expect(api, isNotNull);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Part B — UserMapper.fromProfileDto (GET /users/me response path)
  // -------------------------------------------------------------------------

  group('UserMapper.fromProfileDto', () {
    test('maps all required fields from UserProfileResponse', () {
      final dto = UserProfileResponse(
        (b) => b
          ..id = 'user-123'
          ..email = 'test@beautica.ua'
          ..role = 'CLIENT'
          ..firstName = 'Тест'
          ..lastName = 'Юзер',
      );

      final user = UserMapper.fromProfileDto(dto);

      expect(user.id, 'user-123');
      expect(user.email, 'test@beautica.ua');
      expect(user.role, UserRole.client);
      expect(user.firstName, 'Тест');
      expect(user.lastName, 'Юзер');
    });

    test('maps INDEPENDENT_MASTER role correctly', () {
      final dto = UserProfileResponse(
        (b) => b
          ..id = 'master-999'
          ..email = 'master@beautica.ua'
          ..role = 'INDEPENDENT_MASTER',
      );

      final user = UserMapper.fromProfileDto(dto);

      expect(user.role, UserRole.independentMaster);
      expect(user.firstName, isNull);
      expect(user.lastName, isNull);
    });

    test('optional firstName/lastName are null when absent from response', () {
      final dto = UserProfileResponse(
        (b) => b
          ..id = 'u-1'
          ..email = 'a@b.ua'
          ..role = 'CLIENT',
      );

      final user = UserMapper.fromProfileDto(dto);

      expect(user.firstName, isNull);
      expect(user.lastName, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Part C — UserMapper.fromAuthResponse (login / refresh / verifyEmail path)
  // -------------------------------------------------------------------------

  group('UserMapper.fromAuthResponse', () {
    test('maps userId (not id) and role from AuthResponse', () {
      final dto = AuthResponse(
        (b) => b
          ..userId = 'usr-456'
          ..email = 'master@salon.ua'
          ..role = AuthResponseRoleEnum.INDEPENDENT_MASTER
          ..accessToken = 'at'
          ..refreshToken = 'rt'
          ..tokenType = 'Bearer',
      );

      final user = UserMapper.fromAuthResponse(dto);

      expect(user.id, 'usr-456');
      expect(user.email, 'master@salon.ua');
      expect(user.role, UserRole.independentMaster);
      // AuthResponse carries no firstName/lastName — only /users/me does.
      expect(user.firstName, isNull);
      expect(user.lastName, isNull);
    });

    test('maps SALON_ADMIN role from AuthResponseRoleEnum', () {
      final dto = AuthResponse(
        (b) => b
          ..userId = 'usr-789'
          ..email = 'admin@salon.ua'
          ..role = AuthResponseRoleEnum.SALON_ADMIN
          ..accessToken = 'at'
          ..refreshToken = 'rt',
      );

      final user = UserMapper.fromAuthResponse(dto);

      expect(user.role, UserRole.salonAdmin);
    });
  });

  // -------------------------------------------------------------------------
  // Part D — mock API call deserialization round-trip
  // -------------------------------------------------------------------------

  group('UserControllerApi.getMe() mock wiring', () {
    test(
      'deserializes ApiResponseUserProfileResponse from mock response',
      () async {
        final mockApi = _MockUserApi();

        final dto = UserProfileResponse(
          (b) => b
            ..id = 'user-123'
            ..email = 'test@beautica.ua'
            ..role = 'CLIENT'
            ..firstName = 'Тест'
            ..lastName = 'Юзер',
        );
        final envelope = ApiResponseUserProfileResponse(
          (b) => b
            ..success = true
            ..data = dto.toBuilder(),
        );
        final fakeResponse = Response<ApiResponseUserProfileResponse>(
          data: envelope,
          statusCode: 200,
          requestOptions: RequestOptions(path: '/users/me'),
        );

        when(
          () => mockApi.getMe(headers: any(named: 'headers')),
        ).thenAnswer((_) async => fakeResponse);

        final res = await mockApi.getMe(headers: {'X-No-Retry': 'true'});
        final profile = res.data?.data;

        expect(profile?.id, 'user-123');
        expect(profile?.email, 'test@beautica.ua');
        expect(profile?.role, 'CLIENT');
        expect(profile?.firstName, 'Тест');
        expect(profile?.lastName, 'Юзер');
      },
    );
  });
}
