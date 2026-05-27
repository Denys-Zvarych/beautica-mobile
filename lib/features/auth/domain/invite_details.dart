// Phase 2.20 — InviteDetails domain entity.
//
// Pure Dart — no Flutter imports, no generated code. Holds the read-only
// snapshot returned by `GET /auth/invite/validate?token=<token>`.
//
// [expiresInHours] is a derived convenience property so the presentation layer
// never needs to perform DateTime arithmetic directly.

import 'user_role.dart';

/// Immutable snapshot of an invitation as returned by the backend's
/// `GET /auth/invite/validate?token=<token>` endpoint.
///
/// Roles for invited users are limited to [UserRole.salonAdmin] and
/// [UserRole.salonMaster]; the backend enforces this at the API level.
class InviteDetails {
  const InviteDetails({
    required this.email,
    required this.role,
    required this.expiresAt,
  });

  /// The email address the invite was sent to — pre-filled, not editable.
  final String email;

  /// The role that will be assigned when the user accepts the invite.
  final UserRole role;

  /// Absolute UTC instant at which the invite token expires.
  final DateTime expiresAt;

  /// Remaining hours until expiry. Returns 0 once the invite has expired.
  int get expiresInHours {
    final remaining = expiresAt.difference(DateTime.now());
    return remaining.isNegative ? 0 : remaining.inHours;
  }
}
