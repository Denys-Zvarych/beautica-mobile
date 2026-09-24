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
// `settlementType` is modelled for ONE purpose: the row's name takes a
// localised type prefix («м.» CITY, «с.» VILLAGE) in [composeSettlementLabel].
// It is kept as the raw wire string (CITY / SETTLEMENT / VILLAGE); nothing else
// on the picker branches on it.
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

    /// Raw wire `settlementType` — `CITY`, `SETTLEMENT` or `VILLAGE`.
    ///
    /// Selects the label's name prefix (see [composeSettlementLabel]).
    /// `null` when a caller builds a row without a type (tests, legacy seeds):
    /// such a row is rendered unprefixed, never guessed from its name.
    String? settlementType,
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
    // Defensive: a non-string type (bad row) degrades to "no type" (no
    // prefix) instead of a TypeError that would fail the whole list —
    // the repository only catches DioException.
    settlementType: json['settlementType'] is String
        ? json['settlementType'] as String
        : null,
  );

  /// Builds a [Settlement] from the label parts a SAVED locality carries on
  /// its own read — `/users/me`, a salon read, a master read (phase-330) —
  /// so a saved locality is labelled by the SAME [composeSavedSettlementLabel]
  /// → [composeSettlementLabel] path as a picked row.
  ///
  /// Returns `null` when there is no settlement name at all (no saved
  /// locality). [id] may be null on a read that masks it; the label never
  /// uses it. [oblastName] null is carried as `''`, which the label drops as a
  /// segment with no visible content.
  static Settlement? fromSaved({
    required String? id,
    required String? name,
    required String? settlementType,
    required String? hromadaName,
    required String? oblastName,
  }) {
    if (name == null) return null;
    return Settlement(
      id: id ?? '',
      name: name,
      oblastName: oblastName ?? '',
      hromadaName: hromadaName,
      settlementType: settlementType,
    );
  }
}

/// Composes the label for a SAVED locality (a profile/salon/master read) — the
/// seed of every settlement field and the locality line of every profile.
///
/// Delegates to [composeSettlementLabel], so a saved label and a picked label
/// are formatted — and sanitised — by the one function. The only difference is
/// the FALLBACK: a saved settlement whose [Settlement.settlementType] is `null`
/// (older data, a read that predates phase-330) renders as its bare sanitised
/// name, exactly as it did before. The type is never guessed from the name.
///
/// Returns `null` for a null [saved] or a name that reduces to nothing, so the
/// caller shows its placeholder.
String? composeSavedSettlementLabel(
  Settlement? saved, {
  required String hromadaWord,
  required String oblastWord,
  required String cityPrefix,
  required String villagePrefix,
}) {
  if (saved == null) return null;
  final String? bare = _visibleOrNull(saved.name);
  if (bare == null) return null;
  if (saved.settlementType == null) return bare;
  // The name is already sanitised — hand it through rather than sanitising
  // it a second time inside [composeSettlementLabel].
  return _composeWithName(
    saved,
    bare,
    hromadaWord: hromadaWord,
    oblastWord: oblastWord,
    cityPrefix: cityPrefix,
    villagePrefix: villagePrefix,
  );
}

/// Composes the user-visible label for one settlement row (phase-346 D4).
///
/// Two forms, chosen by [Settlement.hromadaName]'s nullability and nothing
/// else:
///   - «‹назва›, ‹область› ‹oblastWord›» when it is null;
///   - «‹назва›, ‹hromada› ‹hromadaWord›, ‹область› ‹oblastWord›» when it is
///     not.
///
/// The name is prefixed by [Settlement.settlementType], in ONE switch
/// ([_typePrefix]): a CITY gets «‹cityPrefix› » («м. Львів, Львівська обл.»),
/// a VILLAGE gets «‹villagePrefix› » («с. Іванівка, Шишацька громада,
/// Полтавська обл.»). SETTLEMENT (селище) rows and rows with no type are left
/// unprefixed — a SETTLEMENT prefix is one added case in that switch. An EMPTY
/// localised prefix (English ships none) is skipped, with no leading space.
/// Any other type value — unknown, lower-case, empty — is unprefixed.
///
/// [hromadaWord], [oblastWord], [cityPrefix] and [villagePrefix] are the
/// localised words («громада», «обл.», «м.», «с.») the server deliberately does
/// NOT concatenate, because the form depends on where the label is shown; the
/// caller passes `AppLocalizations.of(context).settlementHromadaWord`,
/// `.settlementOblastAbbrev`, `.settlementCityPrefix` and
/// `.settlementVillagePrefix`.
///
/// KYIV is the one degenerate case. It is an oblast-EQUIVALENT (a city with
/// special status) whose oblast row is also named «Київ», so the naive
/// composition renders «м. Київ, Київ обл.». [_regionIsTheSettlement] is the
/// ONE place that recognises it: when the region name equals the settlement
/// name the whole region segment — name and [oblastWord] alike — is dropped,
/// and the city reads «м. Київ». The comparison uses the BARE name, never the
/// prefixed one. This is presentation, not disambiguation logic: a row whose
/// region is its own name is by construction unique in that region, so nothing
/// is lost. It needs no
/// hard-coded name: the city of Kyiv is the only settlement filed under the
/// «Київ» region (verified against the imported taxonomy), and a VILLAGE named
/// «Київ» sits under a real oblast («Миколаївська»), so it keeps its segment
/// and its «обл.» («с. Київ, Миколаївська обл.»).
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
  required String oblastWord,
  required String cityPrefix,
  required String villagePrefix,
}) => _composeWithName(
  settlement,
  _visibleOrNull(settlement.name),
  hromadaWord: hromadaWord,
  oblastWord: oblastWord,
  cityPrefix: cityPrefix,
  villagePrefix: villagePrefix,
);

/// [composeSettlementLabel]'s body, taking the settlement name ALREADY
/// sanitised (`null` when it has no visible content) so
/// [composeSavedSettlementLabel], which must test the name first, sanitises it
/// once rather than twice. Every other part is sanitised here.
String _composeWithName(
  Settlement settlement,
  String? name, {
  required String hromadaWord,
  required String oblastWord,
  required String cityPrefix,
  required String villagePrefix,
}) {
  final String? hromada = _visibleOrNull(settlement.hromadaName);
  final String? oblast = _visibleOrNull(settlement.oblastName);

  final String? prefix = _typePrefix(
    settlement.settlementType,
    cityPrefix: cityPrefix,
    villagePrefix: villagePrefix,
  );

  final List<String> parts = <String>[
    if (name != null) prefix == null || prefix.isEmpty ? name : '$prefix $name',
    if (hromada != null) '$hromada $hromadaWord',
    if (oblast != null && !_regionIsTheSettlement(oblast, name))
      '$oblast $oblastWord',
  ];
  return parts.join(', ');
}

/// Wire `settlementType` values (backend `cities.settlement_type`).
const String kSettlementTypeCity = 'CITY';
const String kSettlementTypeVillage = 'VILLAGE';
const String kSettlementTypeSettlement = 'SETTLEMENT';

/// The localised name prefix for a settlement type, or `null` for none.
///
/// The ONE place a type maps to a prefix. SETTLEMENT (селище) is deliberately
/// unprefixed for now; giving it one is a single added case here.
String? _typePrefix(
  String? settlementType, {
  required String cityPrefix,
  required String villagePrefix,
}) => switch (settlementType) {
  kSettlementTypeCity => cityPrefix,
  kSettlementTypeVillage => villagePrefix,
  _ => null,
};

/// True when the region segment names the settlement itself — the city of Kyiv,
/// whose oblast-equivalent region is «Київ». Such a region is not an oblast, so
/// it gets neither a repeated segment nor the oblast abbreviation.
bool _regionIsTheSettlement(String region, String? name) => region == name;

/// Sanitises a settlement label a caller hands the settlement field as its
/// SEED (`initialLabel`) — normally already built by
/// [composeSavedSettlementLabel], but the field does not trust its caller.
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
