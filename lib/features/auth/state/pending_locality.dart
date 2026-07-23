// Durable post-OTP locality slice (silent-data-loss fix).
//
// WHY THIS EXISTS:
//   Registration collects the user's locality on Step 3, but the backend's
//   register endpoint drops those fields — locality is only persisted AFTER
//   email verification, via an authenticated PATCH (the FIRST point a Bearer
//   token exists). The cross-step [RegisterDraft] that carries the Step 3
//   selection through the wizard is IN-MEMORY ONLY: the 6-digit OTP arrives by
//   email, so users routinely background the app to read it, and low-memory
//   Android kills the process. On relaunch the draft is back to `null` and the
//   locality PATCH silently never runs — the user reaches /home with no
//   location and no error.
//
//   This minimal slice is mirrored to [SecureStorage] when Step 3 is submitted
//   so the verification screen can re-hydrate the locality even when the draft
//   was discarded. It deliberately holds ONLY the locality slice + email +
//   role — NEVER the password or the OTP.
//
// Pure Dart (no Flutter imports) — must be serialisable and testable without a
// widget tree.

import '../domain/user_role.dart';

/// Minimal locality slice persisted across the OTP step.
///
/// Keyed (in storage) by the user's [email] so the verification screen — which
/// already has the email via the GoRouter `extra` — can look it up after the
/// in-memory draft is gone.
///
/// [localityProvided] distinguishes a genuine CLIENT "skip Step 3" (false) from
/// "a city WAS chosen but the draft was lost" (true). Without it the two cases
/// are indistinguishable and the lost-draft case is silently swallowed.
final class PendingLocality {
  const PendingLocality({
    required this.email,
    required this.role,
    required this.localityProvided,
    this.cityId,
    this.districtId,
    this.street = '',
    this.buildingNo = '',
    this.locationNote = '',
    this.salonName = '',
    this.phone = '',
  });

  /// The email the OTP was sent to — the storage lookup key.
  final String email;

  /// The role chosen at the start of the wizard. Drives which save path runs.
  final UserRole role;

  /// `true` when the user actually chose a city on Step 3; `false` for a
  /// genuine CLIENT skip. The discriminator that de-silences the lost-draft
  /// case from the legitimate skip case.
  final bool localityProvided;

  /// Chosen city UUID (null when [localityProvided] is false).
  final String? cityId;

  /// Chosen district UUID (optional even when a city was chosen).
  final String? districtId;

  // Provider-only address slice (INDEPENDENT_MASTER / SALON_OWNER). CLIENT no
  // longer sends these (commit 490febc), so they stay empty for CLIENT.
  final String street;
  final String buildingNo;
  final String locationNote;

  /// SALON_OWNER-only — the salon name needed by POST /salons.
  final String salonName;

  /// SALON_OWNER-only — the salon contact phone needed by POST /salons.
  final String phone;

  /// JSON map for [SecureStorage]. Contains NO password and NO OTP — only the
  /// locality slice, email, and role.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'email': email,
    'role': role.toWire,
    'localityProvided': localityProvided,
    'cityId': cityId,
    'districtId': districtId,
    'street': street,
    'buildingNo': buildingNo,
    'locationNote': locationNote,
    'salonName': salonName,
    'phone': phone,
  };

  /// Parses a stored blob. Returns `null` for any malformed / unknown-role blob
  /// so callers treat corruption as "absent" rather than crashing the
  /// verification flow.
  static PendingLocality? tryFromJson(Map<String, dynamic> json) {
    final email = json['email'];
    final rawRole = json['role'];
    if (email is! String || email.isEmpty || rawRole is! String) return null;

    final UserRole role;
    try {
      role = UserRole.fromWire(rawRole);
    } on ArgumentError {
      return null;
    }

    String asString(Object? v) => v is String ? v : '';
    String? asNullableString(Object? v) =>
        (v is String && v.isNotEmpty) ? v : null;

    return PendingLocality(
      email: email,
      role: role,
      localityProvided: json['localityProvided'] == true,
      cityId: asNullableString(json['cityId']),
      districtId: asNullableString(json['districtId']),
      street: asString(json['street']),
      buildingNo: asString(json['buildingNo']),
      locationNote: asString(json['locationNote']),
      salonName: asString(json['salonName']),
      phone: asString(json['phone']),
    );
  }
}
