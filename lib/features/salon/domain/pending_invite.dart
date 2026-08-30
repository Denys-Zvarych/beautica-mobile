// Phase 21.11 — Outbound staff invitation awaiting acceptance.
//
// One entry from `GET /salons/{salonId}/invites/pending` (backend Phase
// 23.1). The DTO carries NO token material by design — [inviteId] is an
// opaque row id used only to address the cancel endpoint
// (`DELETE /salons/{salonId}/invites/{inviteId}`), never the invite secret
// itself, so this model is safe to hold in memory and render.
//
// [role] reuses the EXISTING [SalonStaffRole] enum (`salon_staff_member
// .dart`) rather than introducing a parallel two-value enum: the backend
// only ever issues SALON_ADMIN / SALON_MASTER invitations, which is exactly
// what that enum models, and the shared enum lets the roster and the invite
// list render the same [RoleChip] copy.
//
// `expiresAt` is deliberately NOT mapped: the invite screen already states
// the fixed 48-hour validity window in its helper copy
// (`inviteStaffEmailHelper`), and nothing in this phase's approved design
// renders a per-invite expiry. Add it here only when a surface needs it.
//
// Pure Dart: no Flutter imports in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'salon_staff_member.dart';

part 'pending_invite.freezed.dart';

/// A sent-but-not-yet-accepted staff invitation.
@freezed
abstract class PendingInvite with _$PendingInvite {
  const factory PendingInvite({
    /// Opaque backend `InviteToken` row id — the cancel endpoint's path
    /// parameter, and this entry's stable list key. Never the invite secret.
    required String inviteId,

    /// The address the invitation was sent to.
    required String recipientEmail,

    /// SALON_ADMIN or SALON_MASTER — the role the invitee will hold.
    required SalonStaffRole role,

    /// When the invitation was issued — rendered as a relative "надіслано
    /// N днів тому" caption via `formatRelativeDate`.
    required DateTime createdAt,
  }) = _PendingInvite;
}
