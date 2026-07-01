// Location-fix — UserMapper field-mapping unit tests.
//
// Covers the city/oblast/district enrichment of the domain [User]:
//   • fromProfileDto maps cityName / oblastName / districtName / phoneNumber
//     (plus cityId / districtId / street / buildingNo / locationNote) from the
//     regenerated [UserProfileResponse] DTO.
//   • fromProfileDto leaves the location fields null when the DTO omits them
//     (CLIENT location is optional).
//   • fromAuthResponse (login / refresh) leaves all location/phone fields null —
//     that payload simply does not carry them.
//
// Pure Dart unit test: no widget tree, no network.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/auth/data/user_mapper.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a fully-populated profile DTO (the "client has a city" shape).
UserProfileResponse _fullProfileDto() => UserProfileResponse(
  (b) => b
    ..id = 'usr-1'
    ..email = 'olena@beautica.test'
    ..role = 'CLIENT'
    ..firstName = 'Олена'
    ..lastName = 'Тест'
    ..phoneNumber = '+380 97 000 00 00'
    ..cityId = 'city-uuid-1'
    ..districtId = 'district-uuid-1'
    ..cityName = 'Київ'
    ..oblastName = 'Київська область'
    ..districtName = 'Шевченківський'
    ..street = 'вул. Хрещатик'
    ..buildingNo = '1'
    ..locationNote = 'Поверх 3',
);

/// Builds a profile DTO with NO location set (the "client has no city" shape).
UserProfileResponse _locationlessProfileDto() => UserProfileResponse(
  (b) => b
    ..id = 'usr-2'
    ..email = 'noloc@beautica.test'
    ..role = 'CLIENT'
    ..firstName = 'Без'
    ..lastName = 'Міста',
);

/// Builds a login-shaped [AuthResponse] (no profile / location fields).
AuthResponse _authResponse() => AuthResponse(
  (b) => b
    ..userId = 'usr-3'
    ..email = 'login@beautica.test'
    ..role = AuthResponseRoleEnum.CLIENT
    ..accessToken = 'access.jwt.token'
    ..refreshToken = 'refresh.jwt.token'
    ..tokenType = 'Bearer',
);

void main() {
  group('UserMapper.fromProfileDto', () {
    test('maps cityName / oblastName / districtName / phoneNumber', () {
      final user = UserMapper.fromProfileDto(_fullProfileDto());

      expect(user.id, 'usr-1');
      expect(user.email, 'olena@beautica.test');
      expect(user.role, UserRole.client);
      expect(user.firstName, 'Олена');
      expect(user.lastName, 'Тест');
      expect(user.phoneNumber, '+380 97 000 00 00');
      expect(user.cityName, 'Київ');
      expect(user.oblastName, 'Київська область');
      expect(user.districtName, 'Шевченківський');
    });

    test('maps the remaining location fields (ids, street, note)', () {
      final user = UserMapper.fromProfileDto(_fullProfileDto());

      expect(user.cityId, 'city-uuid-1');
      expect(user.districtId, 'district-uuid-1');
      expect(user.street, 'вул. Хрещатик');
      expect(user.buildingNo, '1');
      expect(user.locationNote, 'Поверх 3');
    });

    test('leaves location fields null when the DTO omits them', () {
      final user = UserMapper.fromProfileDto(_locationlessProfileDto());

      expect(user.cityName, isNull);
      expect(user.oblastName, isNull);
      expect(user.districtName, isNull);
      expect(user.phoneNumber, isNull);
      expect(user.cityId, isNull);
      expect(user.districtId, isNull);
      expect(user.street, isNull);
      expect(user.buildingNo, isNull);
      expect(user.locationNote, isNull);
    });
  });

  group('UserMapper.fromAuthResponse', () {
    test('leaves cityName / oblastName / districtName / phoneNumber null', () {
      final user = UserMapper.fromAuthResponse(_authResponse());

      expect(user.id, 'usr-3');
      expect(user.email, 'login@beautica.test');
      expect(user.role, UserRole.client);
      // The login response carries none of the profile/location fields.
      expect(user.cityName, isNull);
      expect(user.oblastName, isNull);
      expect(user.districtName, isNull);
      expect(user.phoneNumber, isNull);
      expect(user.cityId, isNull);
      expect(user.districtId, isNull);
      expect(user.street, isNull);
      expect(user.buildingNo, isNull);
      expect(user.locationNote, isNull);
      expect(user.firstName, isNull);
      expect(user.lastName, isNull);
    });
  });
}
