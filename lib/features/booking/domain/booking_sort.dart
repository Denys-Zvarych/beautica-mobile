// Internal result ordering for `GET /bookings/me`. NOT a user-facing feature.
//
// ## Read this before adding a member or building a UI on top of it
//
// Phase 7.8 RETIRED sorting as something the user can choose. There is no sort
// sheet, no sort button, and no screen state holding a sort. What survives here
// is the ordering the CLIENT's «Мої записи» tabs need in order to read
// correctly, hard-coded per tab in `MyBookingsNotifier`:
//
//   • Майбутні   → [oldest] — soonest-first, so the top of the list is
//                  "what's next". This is the whole point of the tab.
//   • Минулі     → [newest] — most-recent-first, the usual history order.
//   • Скасовані  → [newest] — likewise.
//
// The master's «Мої записи» passes [newest] as a fixed constant (see
// `MasterBookingsNotifier`). Phase 7.9 replaces `MasterBookingsQuery` with
// `BookingsDayQuery` and moves that surface to a hard-coded `startsAt,asc` for
// the timeline grid — a deliberate two-step, not an oversight.
//
// So: this enum is an implementation detail of two notifiers. If you find
// yourself adding a member, adding a label, or wiring a picker to it, stop —
// the product decision is that bookings are not user-sortable. On the timeline
// grid a card's POSITION is its time, so no ordering can move it; a sort
// control there would be a no-op affordance.
//
// ## Why the price members are gone
//
// `priceDesc`/`priceAsc` (`priceAtBooking,*`) existed only to feed the retired
// sort sheet. Nothing orders bookings by price any more, and a timeline cannot
// express a price ordering at all.
//
// ## The backend whitelist is NOT advisory
//
// Backend Phase 26.6 replaced Spring's permissive `Pageable` sort binding with
// an explicit property whitelist. Anything outside it returns **HTTP 400**, not
// a silently-ignored param. Backend Phase 26.8 narrows that whitelist to
// `startsAt` alone now that price ordering is retired — it must ship AFTER this
// change, or a live client still sending `priceAtBooking` gets a 400.
//
// Pure Dart: no Flutter imports.

/// The server-side result ordering for `GET /bookings/me`.
///
/// [wireValue] is sent verbatim as the `sort` query param. The client never
/// re-sorts the returned page — the server owns the order (see
/// `MasterBookingsNotifier` and `MyBookingsNotifier`).
///
/// Chosen per-surface in code, never by the user — see the file header.
enum BookingSort {
  /// Latest appointments first. Минулі / Скасовані, and the master's list.
  newest('startsAt,desc'),

  /// Earliest appointments first — "what's next". Майбутні.
  oldest('startsAt,asc');

  const BookingSort(this.wireValue);

  /// The exact `sort=` query value, `<property>,<direction>`. Both members
  /// order by `startsAt`, the one property on the backend's whitelist — see
  /// the file header before adding a member.
  final String wireValue;
}
