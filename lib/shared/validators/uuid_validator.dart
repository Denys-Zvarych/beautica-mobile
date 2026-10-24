// Shared "is this server-supplied id a UUID?" check.
//
// Promoted from `NotificationMapper._uuid` (the first caller) so every
// surface that drops a server id into a route path (`/salons/{id}/...`,
// `/bookings/{id}`) gates it on the same rule (MASVS-CODE-4): a value like
// `x/../..?tab=` must never reach `go_router` as a path segment.
//
// Case: hex digits of either case are accepted and the value is kept
// VERBATIM — the app compares ids with plain `==` against what the backend
// sent elsewhere, so normalising here would break that equality. The backend
// (`java.util.UUID.toString()`) always emits lowercase.

/// Canonical 8-4-4-4-12 hex UUID, either case, nothing else.
final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Whether [value] is a canonical 8-4-4-4-12 hex UUID (either case). No
/// trimming: surrounding whitespace is a rejection, not a repair.
bool isUuid(String value) => _uuidPattern.hasMatch(value);
