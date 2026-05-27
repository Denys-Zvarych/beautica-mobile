// Phase 2.3 — UserRole enum.
//
// Maps backend wire strings (SCREAMING_SNAKE_CASE) to Dart idiomatic enum
// values. `fromWire` is used by the JSON converter in `User.fromJson`;
// `toWire` is used when serialising back to JSON (e.g. registration payload).
//
// This file is pure Dart — no Flutter imports, no generated code.

/// The role assigned to a Beautica user account, as reported by the backend.
///
/// See ARCHITECTURE-mobile.md § 4 for the full role/permission matrix.
/// For Phase 1 MVP, only [independentMaster] is fully implemented on mobile;
/// all other roles show a "coming soon" screen.
enum UserRole {
  client,
  salonOwner,
  salonAdmin,
  salonMaster,
  independentMaster;

  /// Deserializes from the backend's SCREAMING_SNAKE_CASE wire representation.
  ///
  /// Throws [ArgumentError] on an unrecognised value so that unknown roles
  /// surface as a hard crash during development rather than silently
  /// defaulting to an incorrect role.
  static UserRole fromWire(String raw) => switch (raw) {
    'CLIENT' => UserRole.client,
    'SALON_OWNER' => UserRole.salonOwner,
    'SALON_ADMIN' => UserRole.salonAdmin,
    'SALON_MASTER' => UserRole.salonMaster,
    'INDEPENDENT_MASTER' => UserRole.independentMaster,
    _ => throw ArgumentError('Unknown UserRole: $raw'),
  };

  /// Serializes to the backend's SCREAMING_SNAKE_CASE wire representation.
  String get toWire => switch (this) {
    UserRole.client => 'CLIENT',
    UserRole.salonOwner => 'SALON_OWNER',
    UserRole.salonAdmin => 'SALON_ADMIN',
    UserRole.salonMaster => 'SALON_MASTER',
    UserRole.independentMaster => 'INDEPENDENT_MASTER',
  };
}
