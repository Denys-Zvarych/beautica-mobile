// Phase 2.3 — User domain model.
//
// Immutable value object representing a Beautica user as returned by the
// backend. Uses `freezed` for value equality, copyWith, and pattern matching;
// `json_serializable` for JSON round-tripping.
//
// The [_UserRoleConverter] translates between Dart's lowercase enum values and
// the backend's SCREAMING_SNAKE_CASE strings so that the rest of the domain
// layer only ever works with [UserRole] — never raw strings.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'user_role.dart';

part 'user.freezed.dart';
part 'user.g.dart';

/// [JsonConverter] that bridges [UserRole] ↔ the backend wire string.
///
/// Applied via `@_UserRoleConverter()` on the [User.role] field so that
/// `json_serializable` delegates the conversion automatically.
class _UserRoleConverter implements JsonConverter<UserRole, String> {
  const _UserRoleConverter();

  @override
  UserRole fromJson(String json) => UserRole.fromWire(json);

  @override
  String toJson(UserRole role) => role.toWire;
}

/// An authenticated Beautica user.
///
/// Cached in `flutter_secure_storage` as JSON (key: [StorageKeys.userJson])
/// to allow offline bootstrap without a round-trip on cold start.
@freezed
abstract class User with _$User {
  const factory User({
    /// Backend-assigned UUID for the user.
    required String id,

    /// The user's email address (also used as login identifier).
    required String email,

    /// The role that governs which features this user can access.
    @_UserRoleConverter() required UserRole role,

    /// Optional first name; may be null for newly-registered accounts.
    String? firstName,

    /// Optional last name; may be null for newly-registered accounts.
    String? lastName,

    /// Optional phone number (E.164-ish); null until the user supplies it.
    String? phoneNumber,

    /// Backend UUID of the user's city; null when no location is set.
    String? cityId,

    /// Backend UUID of the user's district; null when no location is set.
    String? districtId,

    /// Backend UUID of the oblast that contains the user's city; null when no
    /// city is set. Populated by GET /users/me — lets the locality cascade seed
    /// its oblast selection directly instead of scanning every oblast's cities.
    String? oblastId,

    /// Resolved display name of the user's city (e.g. "Київ"); null when no
    /// city is set. Populated by GET /users/me — absent on the login response.
    String? cityName,

    /// Resolved display name of the user's oblast/region; null when unset.
    /// Populated by GET /users/me — absent on the login response.
    String? oblastName,

    /// Resolved display name of the user's district; null when unset.
    /// Populated by GET /users/me — absent on the login response.
    String? districtName,

    /// Free-text street name; null when no location is set.
    String? street,

    /// Building number; null when no location is set.
    String? buildingNo,

    /// Optional location note (e.g. entrance / floor hints); null when unset.
    String? locationNote,

    /// Backend UUID of the salon this user is staff of; null for roles that
    /// are not salon staff (CLIENT, INDEPENDENT_MASTER) and for SALON_OWNER
    /// (an owner can own MANY salons — see `UserProfileResponse.salonId`
    /// backend doc — so a single session-wide id cannot represent ownership;
    /// the authoritative list for an owner is `GET /salons/mine`, Phase
    /// 21.1). Populated by GET /users/me for SALON_ADMIN — the mechanism by
    /// which an admin is routed to their own salon (`salonManageGuard`,
    /// `app_router.dart`).
    String? salonId,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
