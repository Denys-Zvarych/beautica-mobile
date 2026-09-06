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
    ..locationNote = 'Поверх 3'
    ..salonId = 'salon-uuid-1',
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

/// Builds an [AuthResponse] with NO `salonId` — the login/verify-email shape
/// for a role that belongs to no salon.
AuthResponse _authResponse() => AuthResponse(
  (b) => b
    ..userId = 'usr-3'
    ..email = 'login@beautica.test'
    ..role = AuthResponseRoleEnum.CLIENT
    ..accessToken = 'access.jwt.token'
    ..refreshToken = 'refresh.jwt.token'
    ..tokenType = 'Bearer',
);

/// Builds the `POST /auth/invite/accept` shape for an invited `SALON_ADMIN`:
/// no profile/location fields, but a POPULATED `salonId`.
///
/// The non-null value is load-bearing. This is the ONLY session-establishing
/// flow that never follows with `GET /users/me`, so if the mapper drops
/// `salonId` the admin's session carries null and `SalonHomeResolverScreen`
/// dead-ends instead of forwarding to their salon shell. A fixture that left
/// `salonId` unset would make the assertion below pass whether the mapper
/// carries the field or discards it.
AuthResponse _adminInviteAcceptResponse() => AuthResponse(
  (b) => b
    ..userId = 'usr-4'
    ..email = 'admin@beautica.test'
    ..role = AuthResponseRoleEnum.SALON_ADMIN
    ..salonId = 'salon-uuid-4'
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

    // mobile-security MEDIUM follow-up (2026-08-27): salonId powers
    // `salonManageGuard`'s SALON_ADMIN ownership check in `app_router.dart`.
    test('maps salonId (SALON_ADMIN ownership binding)', () {
      final user = UserMapper.fromProfileDto(_fullProfileDto());

      expect(user.salonId, 'salon-uuid-1');
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
      expect(user.salonId, isNull);
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

    // Regression (2026-09-06): this assertion USED to read `isNull`, against a
    // fixture that never set `salonId` — the defect written down as correct
    // behaviour, and vacuous besides. A newly-invited SALON_ADMIN reached
    // `roleHomePath(salonAdmin)` → `SalonHomeResolverScreen` with a null
    // `salonId` and got «Щось пішло не так. Спробуйте ще раз.» with no retry,
    // because `acceptInvite` is the one session-establishing flow that never
    // follows with `repo.me()` (its "point of no return" contract forbids a
    // network call after the 2xx). The backend DOES populate `salonId` on this
    // envelope — the mapper was discarding it.
    test('carries salonId (invite-accept SALON_ADMIN salon binding)', () {
      final user = UserMapper.fromAuthResponse(_adminInviteAcceptResponse());

      expect(user.id, 'usr-4');
      expect(user.role, UserRole.salonAdmin);
      expect(user.salonId, 'salon-uuid-4');
    });

    test('leaves salonId null when the response omits it', () {
      final user = UserMapper.fromAuthResponse(_authResponse());

      expect(user.salonId, isNull);
    });
  });
}
