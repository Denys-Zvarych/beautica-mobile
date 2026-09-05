// Invite-history status — the lifecycle stage of one outbound staff
// invitation, as DERIVED server-side and delivered on the wire as a bare
// String by `GET /salons/{salonId}/invites`.
//
// The backend does NOT store a status column: PENDING/EXPIRED are a function
// of `expires_at` and the read-time clock, ACCEPTED is `is_used`, and
// CANCELLED is a dedicated revocation marker. All four collapse into one
// string per row at read time, so the app never re-derives anything — it maps
// the wire value and renders it.
//
// [unknown] is the FORWARD-COMPATIBILITY fallback for a value this build does
// not recognise (a newer backend adding a fifth state, or a malformed row).
// It is deliberately NOT user-visible: a row with an unknown status renders
// its role chip and its caption but NO status chip and NO cancel action, so
// an unrecognised state can never be mislabelled, and can never offer an
// action the server would reject.
//
// Pure Dart: no Flutter imports in this file.

/// Lifecycle stage of one sent staff invitation.
enum InviteStatus {
  /// Sent, not yet accepted, not yet expired — the ONLY cancellable state.
  pending,

  /// The invitee followed the link and joined the salon.
  accepted,

  /// The 48-hour window elapsed, or a newer invitation to the same address
  /// superseded this one.
  expired,

  /// Revoked by the owner/admin via `DELETE /salons/{id}/invites/{inviteId}`.
  cancelled,

  /// Unrecognised wire value — renders no status chip and no cancel action.
  unknown,
}
