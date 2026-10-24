// Phase 414 — who may see which booking link (client-side access rule).
//
// User decisions (2026-10-20):
//   * The «Посилання для запису» row + screen exist ONLY for
//     INDEPENDENT_MASTER, SALON_OWNER and SALON_ADMIN — never SALON_MASTER or
//     CLIENT.
//   * INDEPENDENT_MASTER sees its MASTER link only.
//   * SALON_OWNER and SALON_ADMIN see the SAME thing — SALON links only. The
//     owner gets NO personal MASTER card on this screen.
//
// The backend enforces the same rule; this filter makes it hold regardless of
// what the server returns (defence in depth).
//
// Pure Dart: no Flutter imports in this file.

import '../../auth/domain/user_role.dart';
import 'booking_link.dart';

/// Whether [role] may use booking links at all (row + screen).
bool bookingLinksAllowedFor(UserRole? role) => switch (role) {
  UserRole.independentMaster ||
  UserRole.salonOwner ||
  UserRole.salonAdmin => true,
  UserRole.salonMaster || UserRole.client || null => false,
};

/// The only [BookingLinkKind] [role] may see; `null` = none.
BookingLinkKind? bookingLinkKindFor(UserRole? role) => switch (role) {
  UserRole.independentMaster => BookingLinkKind.master,
  UserRole.salonOwner || UserRole.salonAdmin => BookingLinkKind.salon,
  UserRole.salonMaster || UserRole.client || null => null,
};

/// [links] narrowed to what [role] may see. A disallowed role gets
/// [BookingLinks.hidden]; an allowed role keeps the kill-switch and only the
/// links of its own kind, in backend order.
BookingLinks scopeBookingLinksToRole(BookingLinks links, UserRole? role) {
  final BookingLinkKind? kind = bookingLinkKindFor(role);
  if (kind == null) return BookingLinks.hidden;
  final List<BookingLink> kept = links.links
      .where((BookingLink l) => l.kind == kind)
      .toList(growable: false);
  if (kept.length == links.links.length) return links;
  return links.copyWith(links: kept);
}
