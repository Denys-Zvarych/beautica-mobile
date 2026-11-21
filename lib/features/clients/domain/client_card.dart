// M510 — the provider's client card (backend B508 `ClientCardResponse` +
// B526 rating aggregate), CLI-48.
//
// ONE shape for every client kind (CLI-D07): nothing here branches on
// guest-vs-registered. [ref] is the handle the card was REQUESTED with, never
// read from the payload; the data decides what shows (no photo → monogram, no
// phone → no chip, no rating → «Ще немає оцінок»).
//
// `stats` / `firstVisitAt` / `kind` are deliberately NOT mapped (D3).
//
// PII: name, avatar and phone are personal data — `toString` prints nothing
// about them and nothing in this feature logs them.
//
// Pure Dart: no Flutter imports.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:beautica_mobile/features/clients/domain/client_summary.dart';

part 'client_card.freezed.dart';

/// Number of star buckets in [ClientCard.ratingDistribution] (5 → 1).
const int kClientRatingBuckets = 5;

@freezed
abstract class ClientCard with _$ClientCard {
  const factory ClientCard({
    required ClientRef ref,

    /// `null` when the client gave no name — the card shows «Гість».
    String? displayName,
    String? avatarUrl,

    /// The server's phone for this client (a guest's, or a registered client's
    /// verified one) — only ever sent to IM / owner / admin (B518). The card
    /// STILL gates it on `canSeeClientPhone(role)` (D5).
    String? phone,
    @Default(false) bool blocked,

    /// `null` when the client has no visible rating.
    double? ratingAvg,
    @Default(0) int ratingCount,

    /// Counts per star, index 0 = 5 stars … index 4 = 1 star.
    @Default(<int>[0, 0, 0, 0, 0]) List<int> ratingDistribution,
    DateTime? nextVisitAt,

    /// CLI-73 — the salon masters who served this client, most recent first
    /// (salon scope only; always salon-wide, even on a `masterId` read).
    @Default(<ClientServedMaster>[]) List<ClientServedMaster> servedByMasters,
  }) = _ClientCard;

  const ClientCard._();

  @override
  String toString() => 'ClientCard(${ref.runtimeType})';

  /// Monogram: first letters of the first two words of [displayName]; `null`
  /// for a nameless client.
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

  /// The ★ figure, `null` when nobody rated the client (count 0 or no average).
  double? get displayRating => ratingCount > 0 ? ratingAvg : null;
}

/// One entry of [ClientCard.servedByMasters] — a master chip (CLI-73).
@freezed
abstract class ClientServedMaster with _$ClientServedMaster {
  const factory ClientServedMaster({
    required String masterId,
    required String name,
    String? avatarUrl,
  }) = _ClientServedMaster;

  const ClientServedMaster._();

  @override
  String toString() => 'ClientServedMaster($masterId)';
}
