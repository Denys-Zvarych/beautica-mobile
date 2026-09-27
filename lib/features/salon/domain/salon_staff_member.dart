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
// [role] and [masterType] answer two DIFFERENT questions and must not be
// conflated: [role] is CAPABILITY (performs services / manages), [masterType]
// is ACCOUNT IDENTITY (owner / salon master / independent). The salon owner
// is auto-enrolled as a master of their own salon (`SalonService.java:140`),
// so they arrive here as `role: master` WITH `masterType: salonOwner`.
//
// Pure Dart: no Flutter imports in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../master/domain/master.dart';

part 'salon_staff_member.freezed.dart';

/// The two CAPABILITIES this roster can carry — what an entry may DO for this
/// salon, never who the account is.
///
/// This enum deliberately has exactly two values and is shared with
/// `SalonInvite`. It does NOT encode account identity: `SALON_OWNER` is
/// routinely present on `GET /salons/{salonId}/staff` (the owner is
/// auto-enrolled as a master of their first salon) and is correctly a
/// [master] here, because they do perform services. Identity rides on
/// [SalonStaffMember.masterType] instead — see [SalonStaffMemberMapper] in
/// `salon_mapper.dart`.
enum SalonStaffRole {
  /// A master (any `MasterType`, the salon's own owner included) performing
  /// services for this salon.
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

    /// The account identity behind a [SalonStaffRole.master] entry — what
    /// the backend's `role` says this user IS, as opposed to what [role]
    /// says they may do.
    ///
    /// Null for an admin entry BY DESIGN — an admin has no master row, hence
    /// no master type — and null for an unrecognised wire role, where
    /// guessing an identity would be worse than naming none. A display site
    /// therefore falls back to [MasterType.salonMaster], the roster's
    /// commonest case.
    MasterType? masterType,
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
