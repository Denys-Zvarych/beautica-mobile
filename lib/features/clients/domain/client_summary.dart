// M509 — one row of the provider's client list (backend B507
// `ClientListItemResponse`, CLI-38..40).
//
// A client is identified EXACTLY one way: a registered account ([ClientRef]
// `registered(userId)`) or a guest by their latest booking in the viewer's
// scope (`guest(bookingId)`, the card handle for M510). After B527 a
// REGISTERED row can mix APP, attached LINK and attached STAFF bookings and a
// GUEST row exists only for a phone not attached to a CLIENT account; the row
// does not tell which (CLI-D10 — no client-kind label).
//
// PII: the display name and avatar are personal data — `toString` prints the
// kind and nothing else, and nothing in this feature logs a row. The API sends
// no phone (CLI-47), and [completedVisits] is mapped but never rendered (D5).
//
// Pure Dart: no Flutter imports.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'client_summary.freezed.dart';

/// How a list row (and its M510 card) addresses its client.
@freezed
sealed class ClientRef with _$ClientRef {
  /// A registered account — the card route's `user/:userId`.
  const factory ClientRef.registered(String userId) = RegisteredClientRef;

  /// A guest, addressed by their latest booking in scope — `guest/:bookingId`.
  const factory ClientRef.guest(String bookingId) = GuestClientRef;
}

/// Which clients the list covers — the request the controller issues.
@freezed
sealed class ClientListScope with _$ClientListScope {
  /// `GET /salons/{salonId}/clients` — the whole salon (owner / admin shell),
  /// or, with [masterId], one master row's clients (owner master mode, B507 D2).
  const factory ClientListScope.salon({
    required String salonId,
    String? masterId,
  }) = SalonClientListScope;

  /// `GET /masters/me/clients` — the caller's own clients (INDEPENDENT_MASTER
  /// and SALON_MASTER).
  const factory ClientListScope.me() = MyClientListScope;
}

/// One list row. See the file header.
@freezed
abstract class ClientSummary with _$ClientSummary {
  const factory ClientSummary({
    required ClientRef ref,

    /// `null` when the client gave no name — the row renders «Гість».
    String? displayName,
    String? avatarUrl,

    /// Latest visit / next confirmed visit (UTC instants; the row formats them
    /// in Kyiv time).
    DateTime? lastVisitAt,
    DateTime? nextVisitAt,

    /// Mapped from the contract but NEVER rendered (user 2026-11-20).
    @Default(0) int completedVisits,

    /// `null` when the client has no visible review.
    double? ratingAvg,
    @Default(0) int ratingCount,
    @Default(false) bool blocked,
  }) = _ClientSummary;

  const ClientSummary._();

  @override
  String toString() => 'ClientSummary(${ref.runtimeType})';

  /// A guest is the only kind without an account.
  bool get isGuest => ref is GuestClientRef;

  /// The id the row is keyed by — userId or guest booking id.
  String get id => switch (ref) {
    RegisteredClientRef(:final String userId) => userId,
    GuestClientRef(:final String bookingId) => bookingId,
  };

  /// Avatar-fallback monogram: the first letters of the first two words of
  /// [displayName]; `null` for a nameless guest (the badge shows its glyph).
  String? get initials {
    final String? name = displayName;
    if (name == null) return null;
    final String letters = name
        .split(' ')
        .where((String w) => w.isNotEmpty)
        .take(2)
        .map((String w) => String.fromCharCode(w.runes.first))
        .join()
        .toUpperCase();
    return letters.isEmpty ? null : letters;
  }

  /// The ★ figure — `null` («—») when nobody rated the client. Rated =
  /// `ratingAvg != null` and at least one rating (the `MyRatingScreen` rule).
  double? get displayRating => ratingCount > 0 ? ratingAvg : null;
}
