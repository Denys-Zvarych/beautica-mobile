// M552 — what picking an existing client hands a booking form (M553): the
// name parts and, when the server sent one, the phone. Built from the client
// CARD, fetched once on pick (D2): the list rows carry no phone (CLI-47).
//
// PII: names and phone — `toString` prints none of them; never logged.
//
// Pure Dart: no Flutter imports.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:beautica_mobile/features/clients/domain/client_card.dart';

part 'client_prefill.freezed.dart';

/// An E.164 number: `+`, then 7–15 digits, no leading zero.
final RegExp _e164 = RegExp(r'^\+[1-9]\d{6,14}$');

@freezed
abstract class ClientPrefill with _$ClientPrefill {
  const factory ClientPrefill({
    /// `null` when the card carries no usable name (never `''`).
    String? firstName,
    String? lastName,

    /// E.164, or `null` when the card has no (valid) phone — e.g. a
    /// registered client without a verified phone.
    String? phone,
  }) = _ClientPrefill;

  const ClientPrefill._();

  /// The card's name parts and its phone when it is E.164. A blank part
  /// counts as absent and leaves its form field empty. Only when BOTH parts
  /// are absent (a pre-B550 backend) does `firstName` fall back to the
  /// display name; a surname-only card never puts the display name in the
  /// first-name field. A nameless client → `null` (never `''`).
  factory ClientPrefill.fromCard(ClientCard card) {
    final String? phone = card.phone;
    final String? first = _present(card.firstName);
    final String? last = _present(card.lastName);
    return ClientPrefill(
      firstName: first == null && last == null
          ? _present(card.displayName)
          : first,
      lastName: last,
      phone: phone != null && _e164.hasMatch(phone) ? phone : null,
    );
  }

  static String? _present(String? part) =>
      part == null || part.trim().isEmpty ? null : part;

  @override
  String toString() => 'ClientPrefill()';
}
