// Phase 346 — SettlementLocalityField: the whole locality block, on every
// address surface, in one widget.
//
// This is what `LocalityCascade` was, minus the cascade. Where that widget
// rendered three dependent tap-rows (Область -> Місто -> Район) and enforced
// the dependency rules between them, this renders ONE typed autocomplete plus
// the district row, and the district row is the only thing left that depends on
// anything.
//
// WHY THE DISTRICT ROW SURVIVES. The phase retires «Область» and «Місто»; it
// says nothing about «Район», and the backend still requires one. Seventeen
// cities subdivide into the 76 rows of `city_districts`, and
// `LocalityWriteValidator.validateProviderLocality` rejects a save that omits a
// district for one of them ("District is required for the selected city") and
// equally rejects one that supplies a district for a settlement that has none
// ("The selected city has no districts"). A village picked from the new field
// is in the second class. Both branches have to keep working.
//
// HOW IT KNOWS. The settlement search response carries no `hasDistricts` flag —
// deliberately (phase-326 §I withholds every internal id and flag the client
// does not demonstrably need), and the cascade's `CityResponse.hasDistricts`
// is unreachable now that no oblast is chosen. So presence is established by
// ASKING: `districtListProvider(settlementId)` is the existing
// `GET /locations/cities/{id}/districts` read, and it answers `[]` with a 200
// for a village (verified against the live endpoint). An empty list hides the
// row; a non-empty one shows it.
//
// That inverts one small thing about the old cascade, which "trusted the
// backend `hasDistricts` flag rather than fetching an empty list". One extra
// GET now follows each settlement pick on the surfaces that render a district.
// A SUCCESSFUL lookup stays pinned, so re-picking the same settlement is free
// (a failed one disposes and refetches), and the key space is bounded by how
// many settlements one user picks in one session.
//
// WHO OWNS THE VALIDATION. Not this widget. The screens each have their own
// per-role rule (a provider must pick a district when one exists; a CLIENT
// never must) and their own server-field-error plumbing, so they read the same
// `districtListProvider` and decide for themselves. [districtsOf] is the one
// place that read is spelled, so a screen and this widget can never disagree
// about whether a settlement subdivides.

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/locality_picker_sheet.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/locality_tap_row.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/settlement_select_field.dart';
import 'package:beautica_mobile/features/location/state/location_providers.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The urban districts of [settlementId], or an empty list while the lookup is
/// in flight, when it failed, or when [settlementId] is null.
///
/// The ONE spelling of "does this settlement subdivide". A screen validating a
/// save and the widget deciding whether to render the row must never answer
/// that differently, and a failed lookup degrading to "no districts" is the
/// safe direction: the save is then attempted without one, and the server's own
/// «District is required» 400 surfaces through the existing field-error path
/// rather than the form blocking on a row it could not populate.
///
/// [listen] selects `ref.watch` (the default — for `build`) or `ref.read` (for
/// a submit/validation CALLBACK, where a watch would be illegal outside
/// `build`). Both go through [_districtLookup], so the two spellings cannot
/// drift.
///
/// A callback must not treat a lookup that is still IN FLIGHT as "no
/// districts" — that would let a provider save without a district the server
/// then demands. Await [pendingDistrictLookup] first.
List<CityDistrict> districtsOf(
  WidgetRef ref,
  String? settlementId, {
  bool listen = true,
}) =>
    _districtLookup(ref, settlementId, listen: listen)?.value ??
    const <CityDistrict>[];

/// The in-flight district lookup for [settlementId], or `null` when there is
/// nothing to wait for (no settlement, or the lookup already resolved or
/// failed).
///
/// For submit handlers: `await` it (then re-check `mounted`) before calling
/// [districtsOf] with `listen: false`, so a submit that races the lookup
/// validates against the real answer instead of the empty loading default. A
/// FAILED lookup still degrades to "no districts" exactly as [districtsOf]
/// documents — the returned future never throws.
Future<void>? pendingDistrictLookup(WidgetRef ref, String? settlementId) {
  if (settlementId == null || settlementId.isEmpty) return null;
  final AsyncValue<List<CityDistrict>>? lookup = _districtLookup(
    ref,
    settlementId,
    listen: false,
  );
  if (lookup == null || !lookup.isLoading || lookup.hasValue) return null;
  return ref
      .read(districtListProvider(settlementId).future)
      .then<void>((_) {}, onError: (Object _) {});
}

AsyncValue<List<CityDistrict>>? _districtLookup(
  WidgetRef ref,
  String? settlementId, {
  required bool listen,
}) {
  if (settlementId == null || settlementId.isEmpty) return null;
  final provider = districtListProvider(settlementId);
  return listen ? ref.watch(provider) : ref.read(provider);
}

/// The locality block: one «Населений пункт» autocomplete, and a «Район» row
/// for the seventeen settlements that have districts.
class SettlementLocalityField extends ConsumerWidget {
  const SettlementLocalityField({
    super.key,
    required this.settlementId,
    required this.onSettlement,
    required this.selectedDistrict,
    required this.onDistrict,
    this.initialSettlementLabel,
    this.settlementError,
    this.districtError,
    this.labelSuffix,
    this.enabled = true,
    this.onSettlementCleared,
    this.fieldKey = const Key('settlement_select_field'),
  });

  /// The currently-chosen settlement UUID, or null when nothing is chosen.
  final String? settlementId;

  /// Fired with the newly-chosen settlement UUID and the label the field
  /// composed for it.
  ///
  /// The ID is the value (phase-346 D3) — it is what every screen submits, and
  /// the label is never round-tripped to the server. The label is handed over
  /// for the one thing a screen cannot do without it: rendering the chosen
  /// settlement somewhere OUTSIDE this field. Four of the five address
  /// surfaces ignore it; `ClientLocationEditScreen` does not — it forwards the
  /// name to `SearchFiltersController.applyProfileLocationSave` so the Пошук
  /// tab's locality chip reads the settlement the client just saved. Dropping
  /// it there left that chip showing the PREVIOUS settlement's name against
  /// the new settlement's id.
  ///
  /// The caller MUST clear its district selection in this handler: a district
  /// belongs to exactly one settlement, so carrying one across a settlement
  /// change would submit a district that is not a child of the submitted city
  /// and earn a «Selected district does not belong to the selected city» 400.
  final void Function(String settlementId, String label) onSettlement;

  /// Currently-selected district, or null.
  final CityDistrict? selectedDistrict;

  /// Fired when the district selection changes.
  final ValueChanged<CityDistrict?> onDistrict;

  /// Label to show before anything is picked — the settlement name the screen
  /// already holds denormalised on its own read (`UserProfileResponse.cityName`,
  /// `SalonResponse.city`). This is what makes re-opening a saved address show
  /// the settlement (D7).
  final String? initialSettlementLabel;

  /// Inline validation error under the settlement field.
  final String? settlementError;

  /// Inline validation error under the district row.
  final String? districtError;

  /// Optional inline widget to the right of the settlement label — the CLIENT
  /// «— необов'язково» tag plus its "?" tip icon.
  final Widget? labelSuffix;

  /// Suppresses both controls while a submit is in flight.
  final bool enabled;

  /// When non-null, the settlement field grows a «×». The caller MUST clear its
  /// district in this handler for the same reason [onSettlement] must.
  final VoidCallback? onSettlementCleared;

  /// Key on the settlement field itself.
  final Key fieldKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<CityDistrict> districts = districtsOf(ref, settlementId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SettlementSelectField(
          fieldKey: fieldKey,
          initialLabel: initialSettlementLabel,
          labelSuffix: labelSuffix,
          errorText: settlementError,
          enabled: enabled,
          onSelected: onSettlement,
          onCleared: onSettlementCleared,
        ),
        if (districts.isNotEmpty) ...<Widget>[
          const SizedBox(height: VelvetSpacing.md),
          LocalityTapRow(
            key: const Key('locality_row_district'),
            label: l10n.localityDistrictLabel,
            placeholder: l10n.localityDistrictPlaceholder,
            value: selectedDistrict?.name,
            enabled: enabled,
            errorText: districtError,
            onTap: () => _pickDistrict(context, ref, l10n),
          ),
        ],
      ],
    );
  }

  Future<void> _pickDistrict(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final String? id = settlementId;
    if (id == null || id.isEmpty) return;
    final provider = districtListProvider(id);
    final CityDistrict? selected = await showLocalityPickerSheet<CityDistrict>(
      context: context,
      provider: provider,
      labelOf: (CityDistrict d) => d.name,
      idOf: (CityDistrict d) => d.id,
      titleLabel: l10n.localityDistrictLabel,
      onRetry: () => ref.invalidate(provider),
    );
    if (selected != null) {
      onDistrict(selected);
    }
  }
}
