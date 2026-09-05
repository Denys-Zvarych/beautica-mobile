// Phase 3.2 — Typed mapper from generated DTOs to domain User.
//
// Centralises all DTO → domain translation so that [HttpAuthRepository]
// never touches raw map casts. Two source shapes exist:
//   - [AuthResponse]      — login / refresh / verifyEmail / acceptInvite.
//                           Has [userId] (not [id]), no firstName/lastName.
//   - [UserProfileResponse] — GET /users/me. Has [id] and full profile fields.
//
// Pure Dart: no Flutter imports.

import 'package:beautica_api/beautica_api.dart';

import '../domain/user.dart';
import '../domain/user_role.dart';

/// Maps generated API DTOs to the domain [User] entity.
///
/// Both factory methods assert non-null on the fields the backend guarantees
/// will be present. If a field is absent the assertion fires in debug builds;
/// in production an [UnknownFailure] is thrown by the caller's DioException
/// catch before this code runs.
abstract final class UserMapper {
  /// Maps a login / refresh / verifyEmail / acceptInvite [AuthResponse] to
  /// the domain [User].
  ///
  /// [AuthResponse] carries [userId] (not [id]). firstName and lastName are
  /// absent — the full profile requires a separate GET /users/me call.
  ///
  /// [dto.role] is a [AuthResponseRoleEnum] (a built_value [EnumClass]); its
  /// [name] property returns the wire string (e.g. 'INDEPENDENT_MASTER') that
  /// [UserRole.fromWire] expects.
  static User fromAuthResponse(AuthResponse dto) => User(
    id: dto.userId!,
    email: dto.email!,
    role: UserRole.fromWire(dto.role!.name),
  );

  /// Maps a GET /users/me [UserProfileResponse] to the domain [User].
  ///
  /// [UserProfileResponse.role] is a plain [String] (the backend omitted the
  /// enum constraint in the schema for this endpoint). [UserRole.fromWire]
  /// parses it directly.
  static User fromProfileDto(UserProfileResponse dto) => User(
    id: dto.id!,
    email: dto.email!,
    role: UserRole.fromWire(dto.role!),
    firstName: dto.firstName,
    lastName: dto.lastName,
    phoneNumber: dto.phoneNumber,
    cityId: dto.cityId,
    districtId: dto.districtId,
    oblastId: dto.oblastId,
    cityName: dto.cityName,
    oblastName: dto.oblastName,
    districtName: dto.districtName,
    street: dto.street,
    buildingNo: dto.buildingNo,
    locationNote: dto.locationNote,
    salonId: dto.salonId,
    bio: dto.bio,
    instagram: dto.instagram,
    professionalTitle: dto.professionalTitle,
    // Carried VERBATIM, including null. `UserProfileResponse.hasMasterProfile`
    // is generated as `bool?` because the schema does not mark it required, so
    // an older backend simply omits it — and null must stay null all the way
    // into the domain rather than being coerced to `false` here. See
    // [User.hasMasterProfile] for why an absent field is not a proven "no".
    hasMasterProfile: dto.hasMasterProfile,
  );
}
