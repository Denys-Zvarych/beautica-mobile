// Phase 2.18 — LocalityCascade (integration widget).
//
// The high-level widget that registration Step 3 (Phase 2.19), and later the
// provider profile edit + client discovery filter, all consume. It renders the
// three [LocalityTapRow]s and wires each to its bottom-sheet picker, enforcing
// the cascade dependency rules:
//   - City row is disabled until an Oblast is selected.
//   - District row is disabled until a City is selected.
//   - When the selected City has `hasDistricts == false`, the District row
//     switches to its disabled-with-helper state and is never tappable — no
//     districts request is issued (we trust the backend `hasDistricts` flag
//     rather than fetching an empty list).
//
// This widget is stateless: the parent owns the selection state and is
// notified through the [onOblast] / [onCity] / [onDistrict] callbacks. It does
// NOT touch register_draft — wiring into the wizard happens in Phase 2.19.

import 'package:beautica_mobile/core/theme/app_spacing.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/city.dart';
import '../../domain/city_district.dart';
import '../../domain/oblast.dart';
import '../../state/location_providers.dart';
import 'locality_picker_sheet.dart';
import 'locality_tap_row.dart';

/// A stacked Oblast → City → District cascading picker.
class LocalityCascade extends ConsumerWidget {
  const LocalityCascade({
    required this.onOblast,
    required this.onCity,
    required this.onDistrict,
    this.selectedOblast,
    this.selectedCity,
    this.selectedDistrict,
    this.districtRequired = false,
    this.showDistrictNoneHelper = true,
    this.oblastLabelSuffix,
    super.key,
  });

  /// Fired when the oblast selection changes. Selecting a new oblast clears the
  /// downstream city/district selections — the caller should reset those.
  final ValueChanged<Oblast?> onOblast;

  /// Fired when the city selection changes. Selecting a new city clears the
  /// downstream district selection.
  final ValueChanged<City?> onCity;

  /// Fired when the district selection changes.
  final ValueChanged<CityDistrict?> onDistrict;

  /// Currently selected oblast, or null.
  final Oblast? selectedOblast;

  /// Currently selected city, or null.
  final City? selectedCity;

  /// Currently selected district, or null.
  final CityDistrict? selectedDistrict;

  /// Whether a district must be picked when the city has districts.
  ///
  /// Reserved for the consuming screen's validation (true for providers, false
  /// for clients). The cascade always renders the district row; the parent
  /// screen enforces the "required" rule on submit. Carried here so the API
  /// matches the phase-doc signature and Phase 2.19 can wire it without change.
  final bool districtRequired;

  /// Whether to render the "Не обов'язково для міст без районів" helper line
  /// under the District row when the selected city is a leaf (no districts).
  ///
  /// Defaults to `true` (the Phase 2.18 behaviour). The Phase 2.19 register
  /// Step 3 design dropped this helper line, so that screen passes `false` —
  /// the District row still switches to its disabled state, just without the
  /// caption beneath it.
  final bool showDistrictNoneHelper;

  /// Optional inline widget appended to the RIGHT of the Область row label.
  /// Phase 2.19 passes the CLIENT "— необов'язково" tag + the "?" tip-icon
  /// here; null on every other consumer.
  final Widget? oblastLabelSuffix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    final oblast = selectedOblast;
    final city = selectedCity;

    final cityEnabled = oblast != null;
    // District is interactive only when a city is chosen AND that city
    // subdivides into districts. A city with hasDistricts == false renders the
    // helper line and is non-tappable.
    final cityHasDistricts = city?.hasDistricts ?? false;
    final districtEnabled = city != null && cityHasDistricts;
    final showDistrictHelper = city != null && !cityHasDistricts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocalityTapRow(
          key: const Key('locality_row_oblast'),
          label: l10n.localityOblastLabel,
          placeholder: l10n.localityOblastPlaceholder,
          value: oblast?.name,
          labelSuffix: oblastLabelSuffix,
          onTap: () => _pickOblast(context, ref),
        ),
        const SizedBox(height: AppSpacing.md),
        LocalityTapRow(
          key: const Key('locality_row_city'),
          label: l10n.localityCityLabel,
          placeholder: l10n.localityCityPlaceholder,
          value: city?.name,
          enabled: cityEnabled,
          onTap: () {
            final o = selectedOblast;
            if (o != null) _pickCity(context, ref, o);
          },
        ),
        const SizedBox(height: AppSpacing.md),
        LocalityTapRow(
          key: const Key('locality_row_district'),
          label: l10n.localityDistrictLabel,
          placeholder: l10n.localityDistrictPlaceholder,
          value: selectedDistrict?.name,
          enabled: districtEnabled,
          helper: (showDistrictHelper && showDistrictNoneHelper)
              ? l10n.localityDistrictNoneHelper
              : null,
          onTap: () {
            final c = selectedCity;
            if (c != null && c.hasDistricts) _pickDistrict(context, ref, c);
          },
        ),
      ],
    );
  }

  Future<void> _pickOblast(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final selected = await showLocalityPickerSheet<Oblast>(
      context: context,
      provider: oblastListProvider,
      labelOf: (o) => o.name,
      titleLabel: l10n.localityOblastLabel,
      onRetry: () => ref.invalidate(oblastListProvider),
    );
    if (selected != null) {
      onOblast(selected);
      // A new oblast invalidates the downstream selections.
      onCity(null);
      onDistrict(null);
    }
  }

  Future<void> _pickCity(
    BuildContext context,
    WidgetRef ref,
    Oblast oblast,
  ) async {
    final l10n = AppLocalizations.of(context);
    final provider = cityListProvider(oblast.id);
    final selected = await showLocalityPickerSheet<City>(
      context: context,
      provider: provider,
      labelOf: (c) => c.name,
      titleLabel: l10n.localityCityLabel,
      onRetry: () => ref.invalidate(provider),
    );
    if (selected != null) {
      onCity(selected);
      // Switching city invalidates the district selection.
      onDistrict(null);
    }
  }

  Future<void> _pickDistrict(
    BuildContext context,
    WidgetRef ref,
    City city,
  ) async {
    final l10n = AppLocalizations.of(context);
    final provider = districtListProvider(city.id);
    final selected = await showLocalityPickerSheet<CityDistrict>(
      context: context,
      provider: provider,
      labelOf: (d) => d.name,
      titleLabel: l10n.localityDistrictLabel,
      onRetry: () => ref.invalidate(provider),
    );
    if (selected != null) {
      onDistrict(selected);
    }
  }
}
