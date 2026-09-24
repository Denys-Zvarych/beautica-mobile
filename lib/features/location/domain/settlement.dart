// Phase 346 — Settlement: one row of the «Населений пункт» autocomplete.
//
// The domain counterpart of the backend's `SettlementSearchResponse`
// (`GET /api/v1/settlements?query=…`, phase-326 + phase-327), the surface that
// REPLACES the Область → Місто cascade for address entry. Where [City] models
// a node of that cascade (and is reachable only through its oblast parent, and
// only for `settlement_type = 'CITY'`), this models a hit in a flat, typed
// search over all 25 698 free Ukrainian settlements — villages included.
//
// WIRE SHAPE (camelCase JSON, inside the usual `{ success, data, message }`
// envelope):
//   { settlementId (UUID), nameUk, settlementType, oblastNameUk,
//     hromadaNameUk (NULLABLE) }
//
// `settlementType` is deliberately NOT modelled. Phase-346 D4 defines the row
// label exactly — name, optional hromada, oblast — and nothing else on the
// picker consumes the type. Mirrors [City], which drops `nameEn` for the same
// reason.
//
// `hromadaNameUk`'s NULLABILITY IS THE CONTRACT (phase-327 D3). The server
// populates it for exactly the 6 103 of 25 697 rows whose name+oblast pair is
// ambiguous, and leaves it null for the other 76 %. The client therefore
// branches on null and NEVER computes ambiguity itself.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../shared/util/sanitize_display_text.dart';

part 'settlement.freezed.dart';

/// One settlement returned by the `/settlements` autocomplete.
@freezed
abstract class Settlement with _$Settlement {
  const factory Settlement({
    /// Backend-assigned UUID (string form) — THE contract (phase-326 D6).
    ///
    /// This is the value a screen stores and submits as `cityId`; the name is
    /// neither unique (99 «Іванівка») nor stable and is never round-tripped.
    required String id,

    /// Canonical Ukrainian settlement name, exactly as `cities.name_uk` stores
    /// it.
    required String name,

    /// Ukrainian name of the parent oblast, as stored — the BARE adjective
    /// («Полтавська»), with no «область» suffix. For Kyiv, which is an
    /// oblast-EQUIVALENT, this is «Київ» — i.e. identical to [name]. See
    /// [composeSettlementLabel] for how that degenerate case is composed.
    required String oblastName,

    /// Bare hromada adjective («Шишацька»), or `null` when the oblast already
    /// disambiguates this row.
    ///
    /// NEVER derive this: `null` means "the server decided the oblast is
    /// enough", and non-null means "it is not".
    String? hromadaName,
  }) = _Settlement;

  /// Maps a raw backend `SettlementSearchResponse` map to the domain model.
  ///
  /// Named `fromResponse` (not `fromJson`) so freezed does not wire
  /// json_serializable glue — every field is renamed off the wire key.
  static Settlement fromResponse(Map<String, dynamic> json) => Settlement(
    id: json['settlementId'] as String,
    name: json['nameUk'] as String,
    oblastName: json['oblastNameUk'] as String,
    hromadaName: json['hromadaNameUk'] as String?,
  );
}

/// Composes the user-visible label for one settlement row (phase-346 D4).
///
/// Two forms, chosen by [Settlement.hromadaName]'s nullability and nothing
/// else:
///   - «‹назва›, ‹область›» when it is null;
///   - «‹назва›, ‹hromada› ‹hromadaWord›, ‹область›» when it is not.
///
/// [hromadaWord] is the localised noun («громада») the server deliberately does
/// NOT concatenate, because the grammatical form depends on where the label is
/// shown; the caller passes `AppLocalizations.of(context).settlementHromadaWord`.
///
/// KYIV is the one degenerate case. It is an oblast-EQUIVALENT whose oblast row
/// is also named «Київ», so the naive composition renders «Київ, Київ». When
/// the oblast name equals the settlement name the oblast segment is dropped
/// entirely rather than repeated — this is presentation, not disambiguation
/// logic: a row whose oblast is its own name is by construction unique in that
/// oblast, so nothing is lost.
///
/// Every segment is routed through `sanitizeDisplayText` before it is joined.
/// These are 25 698 server-supplied strings newly reaching the UI, and although
/// they are government reference data the sweep in `shared/formatters/
/// address_lines.dart` applies the same rule to every other server string an
/// address screen renders (backlog 2026-09-18, line 110). Sanitising BEFORE the
/// emptiness test is deliberate and mirrors that file: a segment that reduces
/// to nothing must lose its separator with it, not leave a dangling comma.
String composeSettlementLabel(
  Settlement settlement, {
  required String hromadaWord,
}) {
  final String? name = _visibleOrNull(settlement.name);
  final String? hromada = _visibleOrNull(settlement.hromadaName);
  final String? oblast = _visibleOrNull(settlement.oblastName);

  final List<String> parts = <String>[
    ?name,
    if (hromada != null) '$hromada $hromadaWord',
    // Kyiv: the oblast IS the settlement — never render «Київ, Київ».
    if (oblast != null && oblast != name) oblast,
  ];
  return parts.join(', ');
}

/// Sanitises a settlement label that did NOT come through
/// [composeSettlementLabel] — the SEED a screen passes the settlement field
/// from its own profile/salon read (`UserProfileResponse.cityName`,
/// `SalonResponse.city`).
///
/// Exactly the rule [composeSettlementLabel] applies to every segment of a
/// picked row, so a seeded label and a picked label can never be sanitised
/// differently. Returns `null` when [label] is null or reduces to nothing
/// visible — the field then shows its placeholder rather than a blank value.
String? sanitizeSettlementLabel(String? label) => _visibleOrNull(label);

String? _visibleOrNull(String? value) {
  if (value == null) return null;
  final String sanitized = sanitizeDisplayText(
    value,
    collapseNewlines: true,
  ).trim();
  return sanitized.isEmpty ? null : sanitized;
}
