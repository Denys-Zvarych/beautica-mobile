// Phase 21.10 — SalonAddressEditScreen («Локація»).
//
// One of the three lightweight edit-form screens reached from the Phase 21.9
// settings hub (unbuilt — this screen has no in-app entry point yet, per this
// phase's own scope note). Edits the locality cascade (Область → Місто →
// Район) plus Вулиця / Будинок / Примітки до адреси.
//
// REUSE-FIRST: [LocalityCascade] (Phase 2.18) is reused VERBATIM for the
// cascade — no second picker implementation. Save goes through the ADDITIVE
// [SalonManagementProfile.saveAddress] method (this phase), a sibling of the
// existing [SalonManagementProfile.save] (Phase 21.2, name/description/
// phone/Instagram only) rather than a brand-new fetch-and-diff notifier —
// both share the SAME [salonManagementProfileProvider] family instance.
//
// Oblast pre-population: [Salon.oblastId] (backend addition alongside this
// screen's own work — see that field's doc) lets [_prePopulateLocality]
// resolve the cascade with a single targeted `oblastId -> cities ->
// districts` lookup chain, the same shape `LocationEditScreen` uses for
// `master.oblastId`. As of backend `dbe27a5`, [Salon.oblastId] is populated
// on the PUBLIC `GET /salons/{salonId}` read path this screen's own data
// loads through too (see that field's doc) — a salon with no city set is the
// only case where the cascade opens unresolved; street/building/note still
// pre-populate immediately regardless.
//
// Design source: `docs/signup-designs/SalonManagementDesign/lib/screens/
// salon_address_edit_screen.dart` — ported onto production's
// `SectionScaffold` + `VelvetField` + `LocalityCascade` (the preview's own
// static-value `LocalityPickerRow`s were a placeholder — "tapping a row is a
// placeholder here", per that file's own doc). The preview's optional
// «Примітки до адреси» field is real production `Salon.locationNote` /
// `UpdateSalonRequest.locationNote`, so it is ported too even though the
// phase doc's own Step 4 prose omits it — preview wins per this phase's
// locked 2026-08-28 decision.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/velvet_field.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/domain/resolved_locality.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/locality_cascade.dart';
import 'package:beautica_mobile/features/location/state/resolved_locality_provider.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/validators/building_validator.dart';
import 'package:beautica_mobile/shared/validators/street_validator.dart';

import '../../master/presentation/widgets/section_scaffold.dart';
import '../application/salon_management_profile_notifier.dart';
import '../domain/salon.dart';

// Backend UpdateSalonRequest.locationNote cap (tool/openapi/api-spec.json),
// matching `LocationEditScreen`'s identical constant.
const int _kLocationNoteMaxLength = 1000;

/// Dedicated «Локація» edit screen for [salonId].
class SalonAddressEditScreen extends ConsumerStatefulWidget {
  const SalonAddressEditScreen({super.key, required this.salonId});

  /// Backend Salon-row UUID this screen edits.
  final String salonId;

  @override
  ConsumerState<SalonAddressEditScreen> createState() =>
      _SalonAddressEditScreenState();
}

class _SalonAddressEditScreenState
    extends ConsumerState<SalonAddressEditScreen> {
  bool _initialized = false;
  late final TextEditingController _streetCtrl;
  late final TextEditingController _buildingCtrl;
  late final TextEditingController _noteCtrl;

  Oblast? _selectedOblast;
  City? _selectedCity;
  CityDistrict? _selectedDistrict;

  bool _saving = false;
  String? _errStreet;
  String? _errBuildingNo;
  String? _errCity;
  String? _errDistrict;

  void _initControllers(Salon salon) {
    if (_initialized) return;
    _initialized = true;
    _streetCtrl = TextEditingController(text: salon.street ?? '');
    _buildingCtrl = TextEditingController(text: salon.buildingNo ?? '');
    _noteCtrl = TextEditingController(text: salon.locationNote ?? '');
    Future.microtask(() => _prePopulateLocality(salon));
  }

  /// Resolves [Oblast], [City], [CityDistrict] objects from [salon.oblastId]/
  /// [salon.cityId]/[salon.districtId].
  ///
  /// Phase 21.14 — the by-id scan itself (oblast -> city -> district, one
  /// targeted lookup chain) moved to the shared [resolvedLocalityProvider]
  /// (REUSE-FIRST — it was hand-copied here AND in
  /// `LocationEditScreen._prePopulateLocality`; a third near-identical
  /// private copy is exactly what that promotion prevents). This method is
  /// now just the one-shot `ref.read(...future)` call plus the `setState`
  /// that seeds the cascade's mutable local selection — error handling
  /// (never throws; logs in debug builds only) lives in the provider, so
  /// this method needs no try/catch of its own any more.
  Future<void> _prePopulateLocality(Salon salon) async {
    final ResolvedLocality resolved = await ref.read(
      resolvedLocalityProvider(
        oblastId: salon.oblastId,
        cityId: salon.cityId,
        districtId: salon.districtId,
      ).future,
    );

    if (!mounted) return;
    setState(() {
      _selectedOblast = resolved.oblast;
      _selectedCity = resolved.city;
      _selectedDistrict = resolved.district;
    });
  }

  @override
  void dispose() {
    if (_initialized) {
      _streetCtrl.dispose();
      _buildingCtrl.dispose();
      _noteCtrl.dispose();
    }
    super.dispose();
  }

  void _onOblast(Oblast? o) {
    setState(() {
      _selectedOblast = o;
      _selectedCity = null;
      _selectedDistrict = null;
      // Finding (2026-08-29) — an oblast change resets the city to null,
      // which un-does whatever satisfied _errCity a moment ago; a stale
      // `null` here left Save un-blocked even though no city is selected
      // any more (the field-level error only re-evaluates in _validateLocality,
      // which only runs on Save). Clearing both here mirrors
      // LocationEditScreen's cascade handlers, which never carry a stale
      // error across a selection reset either.
      _errCity = null;
      _errDistrict = null;
    });
  }

  void _onCity(City? c) {
    setState(() {
      _selectedCity = c;
      _selectedDistrict = null;
      if (c != null) _errCity = null;
      _errDistrict = null;
    });
  }

  void _onDistrict(CityDistrict? d) {
    setState(() {
      _selectedDistrict = d;
      if (d != null) _errDistrict = null;
    });
  }

  /// Mirrors `LocationEditScreen._validateLocation`'s locality rules: the
  /// city is UNCONDITIONALLY required (Finding, 2026-08-29 — this screen had
  /// no client-side city-required guard at all, so Save was never blocked on
  /// a missing city; the missing guard is what let the notifier's since-fixed
  /// city/district dirty-diff surface as a bare backend 400 instead of an
  /// inline field error), and a city that subdivides into districts
  /// ([City.hasDistricts]) MUST also have a district picked before Save —
  /// Finding 1 (2026-08-28), otherwise `saveAddress` can PATCH a cityId that
  /// requires a district while districtId is still unset, an invalid
  /// locality pair the backend's `LocalityWriteValidator` rejects.
  /// `LocalityCascade` exposes `cityError`/`districtError` for exactly this;
  /// wired here.
  bool _validateLocality() {
    final l10n = AppLocalizations.of(context);
    final bool citySelected = _selectedCity != null;
    final bool cityHasDistricts = _selectedCity?.hasDistricts ?? false;
    final String? errCity = !citySelected ? l10n.errRequired : null;
    final String? errDistrict = (cityHasDistricts && _selectedDistrict == null)
        ? l10n.errRequired
        : null;
    setState(() {
      _errCity = errCity;
      _errDistrict = errDistrict;
    });
    return errCity == null && errDistrict == null;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final String? streetErr = validateStreet(_streetCtrl.text, l10n);
    final String? buildingErr = validateBuilding(_buildingCtrl.text, l10n);
    final bool localityOk = _validateLocality();
    if (streetErr != null || buildingErr != null || !localityOk) {
      setState(() {
        _errStreet = streetErr;
        _errBuildingNo = buildingErr;
      });
      showErrorSnack(context, l10n.editValidationSummary);
      return;
    }

    final City? selectedCity = _selectedCity;
    if (selectedCity == null) {
      // Defensive: unreachable once _validateLocality() returns true, since
      // the city is now unconditionally required (it sets _errCity and
      // returns false when no city is chosen). Mirrors
      // `LocationEditScreen._save()`'s identical guard — never fall through
      // to `saveAddress` with a null city.
      return;
    }

    setState(() => _saving = true);
    final Failure? failure = await ref
        .read(salonManagementProfileProvider(widget.salonId).notifier)
        .saveAddress(
          cityId: selectedCity.id,
          districtId: _selectedDistrict?.id,
          street: _streetCtrl.text,
          buildingNo: _buildingCtrl.text,
          locationNote: _noteCtrl.text,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (failure != null) {
      showErrorSnack(context, failure.userMessage(context));
      return;
    }
    showSuccessSnack(context, l10n.savedSnackbar);
    context.pop();
  }

  void _onBack() {
    if (context.canPop()) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<SalonManagementProfileData> async = ref.watch(
      salonManagementProfileProvider(widget.salonId),
    );

    final SalonManagementProfileData? data = async.value;
    if (data == null) {
      return const Scaffold(
        backgroundColor: BrandColors.base,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final (Salon salon, _) = data;
    _initControllers(salon);

    return SectionScaffold(
      title: l10n.locationTitle,
      backSemanticLabel: l10n.salonProfileBackLabel,
      onBack: _onBack,
      footer: NeumorphicButton(
        key: const Key('save_salon_address'),
        label: l10n.masterSaveButton,
        icon: Icons.check_rounded,
        loading: _saving,
        onPressed: _saving ? null : _save,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.lg),
            child: Text(
              l10n.salonAddressEditSubheading,
              style: VelvetText.body(),
            ),
          ),
          LocalityCascade(
            selectedOblast: _selectedOblast,
            selectedCity: _selectedCity,
            selectedDistrict: _selectedDistrict,
            districtRequired: true,
            cityError: _errCity,
            districtError: _errDistrict,
            onOblast: _onOblast,
            onCity: _onCity,
            onDistrict: _onDistrict,
          ),
          const SizedBox(height: VelvetSpacing.lg),
          VelvetField(
            fieldKey: const Key('salon_street'),
            label: l10n.streetLabel,
            controller: _streetCtrl,
            enabled: !_saving,
            maxLength: kStreetMaxLength,
            errorText: _errStreet,
            onChanged: (String v) {
              final next = validateStreet(v, l10n);
              if (next != _errStreet) setState(() => _errStreet = next);
            },
          ),
          const SizedBox(height: VelvetSpacing.lg),
          VelvetField(
            fieldKey: const Key('salon_building'),
            label: l10n.buildingNoLabel,
            controller: _buildingCtrl,
            enabled: !_saving,
            maxLength: kBuildingMaxLength,
            errorText: _errBuildingNo,
            onChanged: (String v) {
              final next = validateBuilding(v, l10n);
              if (next != _errBuildingNo) {
                setState(() => _errBuildingNo = next);
              }
            },
          ),
          const SizedBox(height: VelvetSpacing.lg),
          VelvetField(
            fieldKey: const Key('salon_location_note'),
            label: l10n.locationNoteLabel,
            controller: _noteCtrl,
            enabled: !_saving,
            optional: true,
            maxLines: 3,
            maxLength: _kLocationNoteMaxLength,
            showCounter: true,
          ),
        ],
      ),
    );
  }
}
