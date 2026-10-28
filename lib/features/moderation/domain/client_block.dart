// Phase 425 — a provider's block on a client, the domain side of backend
// phase 397 `/api/v1/blocks`.
//
// Mirrors the 397 contract exactly:
//   POST   /blocks { bookingId }  → 201 new / 200 existing  BlockResponse
//   DELETE /blocks/{blockId}      → 204 (also 204 when already gone)
//   GET    /blocks                → [BlockResponse]
//   BlockResponse { id, kind: CLIENT | GUEST, displayName, avatarUrl?,
//                   maskedPhone?, createdAt }
// Errors: 400 STAFF walk-in, 403 CLIENT / SALON_MASTER, 404 booking not in
// the caller's scope. The blocked party is never told (397 D5).
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'client_block.freezed.dart';

/// Who was blocked — backend 397 `kind`.
enum ClientBlockKind {
  /// A registered client account (APP booking).
  client('CLIENT'),

  /// A LINK guest, identified by the OTP-verified phone only.
  guest('GUEST');

  const ClientBlockKind(this.wireName);

  /// The backend enum constant.
  final String wireName;
}

/// One row of the provider's (or salon's) block list.
@freezed
abstract class ClientBlock with _$ClientBlock {
  const factory ClientBlock({
    required String id,
    required ClientBlockKind kind,

    /// Name snapshot (guest: «Ім'я П.»). Never a phone.
    required String displayName,

    /// Registered clients only.
    String? avatarUrl,

    /// «+380 •• ••• 12 34», or `null` when no phone is on file. The app
    /// never sees a raw phone or its hash.
    String? maskedPhone,
    required DateTime createdAt,
  }) = _ClientBlock;

  const ClientBlock._();

  /// Security LOW — redacting `toString`. The freezed default prints every
  /// field, so a stray `log('$block')` would leak the client's name, avatar
  /// URL and masked phone. Only the id and kind are printed. `==` /
  /// `hashCode` stay freezed-generated.
  @override
  String toString() => 'ClientBlock(id: $id, kind: ${kind.wireName})';

  /// Phase 426 — up to two initials for the identity disc: the first code
  /// point of the first two words of [displayName] («Ім'я П.» → «ІП»,
  /// «Клієнт» → «К»). Empty when the name has no letters to offer.
  String get initials => displayName
      .split(' ')
      .where((String w) => w.isNotEmpty)
      .take(2)
      .map((String w) => String.fromCharCode(w.runes.first))
      .join()
      .toUpperCase();
}
