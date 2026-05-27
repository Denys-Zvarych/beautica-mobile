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
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
