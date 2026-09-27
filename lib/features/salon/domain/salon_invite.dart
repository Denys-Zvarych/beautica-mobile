// One row of a salon's outbound staff-invitation HISTORY.
//
// One entry from `GET /salons/{salonId}/invites` (backend Phase 23.1,
// widened from the retired `/invites/pending`). The DTO carries NO token
// material by design — [inviteId] is an opaque row id used only to address
// the cancel endpoint (`DELETE /salons/{salonId}/invites/{inviteId}`), never
// the invite secret itself, so this model is safe to hold in memory and
// render.
//
// [role] reuses the EXISTING [SalonStaffRole] enum (`salon_staff_member
// .dart`) rather than introducing a parallel two-value enum: the backend
// only ever issues SALON_ADMIN / SALON_MASTER invitations, which is exactly
// what that enum models, and the shared enum lets the roster and the invite
// list render the same `RoleChip` copy.
//
// [status] is DERIVED SERVER-SIDE and mapped verbatim — the app never
// recomputes it from [expiresAt] and a local clock. Doing so would put the
// device clock in charge of a lifecycle decision the server already made
// (and would disagree with it across a skewed clock or a DST boundary), and
// it could not tell CANCELLED from ACCEPTED at all: both write the same
// `is_used` flag in the schema, which is precisely why the server carries a
// separate revocation marker.
//
// [expiresAt] is mapped but NOT RENDERED ANYWHERE — see its own doc for why
// it is carried anyway. (An earlier draft of this header claimed the history
// list shows it; it does not, and the approved design does not ask for it.)
//
// Pure Dart: no Flutter imports in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'invite_status.dart';
import 'salon_staff_member.dart';

part 'salon_invite.freezed.dart';

/// One sent staff invitation, in any lifecycle state.
@freezed
abstract class SalonInvite with _$SalonInvite {
  const SalonInvite._();

  const factory SalonInvite({
    /// Opaque backend `InviteToken` row id — the cancel endpoint's path
    /// parameter, and this entry's stable list key. Never the invite secret.
    required String inviteId,

    /// The address the invitation was sent to.
    required String recipientEmail,

    /// SALON_ADMIN or SALON_MASTER — the role the invitee will hold.
    required SalonStaffRole role,

    /// Server-derived lifecycle stage. [InviteStatus.unknown] for a wire
    /// value this build does not recognise.
    required InviteStatus status,

    /// When the invitation was issued — rendered as a relative "надіслано
    /// N днів тому" caption via `formatRelativeDate`, and the sort key the
    /// server orders the history by (newest first).
    required DateTime createdAt,

    /// End of the invitation's validity window.
    ///
    /// CURRENTLY UNRENDERED — no surface displays it, and none should be
    /// added just to justify the field: the approved design shows a status
    /// chip («термін минув») rather than a raw expiry timestamp, and the
    /// server, not the device, decides when the window closed (see this
    /// file's header on [status]).
    ///
    /// Retained rather than dropped because it is part of
    /// `SalonInviteResponse` and costs one already-parsed `DateTime` per row:
    /// mapping it keeps the domain entity a faithful mirror of the endpoint,
    /// so a future surface that DOES want the window (an «дійсне до …» line,
    /// a re-invite affordance) needs no data-layer change. Delete it the day
    /// the endpoint stops sending it, not before.
    required DateTime expiresAt,
  }) = _SalonInvite;

  /// Whether this row may be revoked.
  ///
  /// ONE place decides, and both the row widget (which renders «Скасувати»
  /// only when this is true) and the notifier (which early-returns when it is
  /// false) read it — so the visible affordance and the request that follows
  /// it can never disagree. `DELETE /salons/{id}/invites/{inviteId}` 404s for
  /// every non-pending invite, so offering the action anywhere else is a
  /// guaranteed error.
  bool get isCancellable => status == InviteStatus.pending;
}

/// One page of invite history: the rows plus whether older ones were cut.
///
/// A record rather than a second freezed class, mirroring
/// `SalonInvitesState`'s own precedent in this feature: two fields with no
/// behaviour of their own, consumed as a unit by exactly one repository
/// method and one notifier.
///
/// [truncated] is true when the salon has sent MORE invitations than the
/// server's hard cap (200) and the older ones are therefore absent from
/// [invites]. It is surfaced in the UI — a silently short list would read as
/// "this is everything", which is the one thing it is not.
typedef SalonInviteHistory = ({List<SalonInvite> invites, bool truncated});
