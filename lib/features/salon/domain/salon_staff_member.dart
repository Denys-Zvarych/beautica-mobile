// Phase 21.5 — Salon staff member domain model.
//
// A single entry from the management-scoped `GET /salons/{salonId}/staff`
// roster — masters (any type performing services for this salon) AND
// SALON_ADMINs, with unmasked contact details (unlike the public
// `GET /salons/{salonId}/masters` rail, `SalonMasterSummary`'s own source,
// which never carries phone/instagram/bio and never lists admins at all).
//
// [masterId] is null for an admin entry — an admin has no master row. [bio]
// is null for an admin BY DESIGN (backend contract — admins have no "about
// the master" blurb), not merely unset; do not treat a null admin bio as a
// gap to backfill.
//
// Pure Dart: no Flutter imports in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'salon_staff_member.freezed.dart';

/// The two roles this roster can carry. Any other backend role value
/// (CLIENT/SALON_OWNER/INDEPENDENT_MASTER) is unreachable on this endpoint by
/// contract — see [SalonStaffMemberMapper] in `salon_mapper.dart` for the
/// fail-safe fallback if one ever appears.
enum SalonStaffRole {
  /// A master (any `MasterType`) performing services for this salon.
  master,

  /// A SALON_ADMIN with management access to this salon.
  admin,
}

/// One entry in a salon's staff roster (masters + admins).
@freezed
abstract class SalonStaffMember with _$SalonStaffMember {
  const factory SalonStaffMember({
    /// Backend `User` row id — always present, and the ONLY id an admin
    /// entry carries. Used as this entry's stable list key.
    required String userId,

    /// Backend `Master` row id — null for an admin entry.
    String? masterId,
    required SalonStaffRole role,
    required String firstName,
    required String lastName,
    String? professionalTitle,
    String? avatarUrl,
    String? phoneNumber,
    String? instagram,

    /// Null for an admin entry BY DESIGN — see this file's header doc.
    String? bio,

    /// Null when [reviewCount] is 0 — no reviews yet. Always null for an
    /// admin entry (no service rating).
    double? avgRating,
    @Default(0) int reviewCount,
    @Default(0) int serviceCount,
  }) = _SalonStaffMember;
}
