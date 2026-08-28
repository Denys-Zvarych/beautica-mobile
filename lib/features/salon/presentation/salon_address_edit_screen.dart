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

import 'dart:developer';

import 'package:flutter/foundation.dart';
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
import 'package:beautica_mobile/features/location/presentation/widgets/locality_cascade.dart';
import 'package:beautica_mobile/features/location/state/location_providers.dart';
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
  /// [salon.cityId]/[salon.districtId] via a single targeted lookup chain —
  /// mirrors `LocationEditScreen._prePopulateLocality`'s exact shape.
  Future<void> _prePopulateLocality(Salon salon) async {
    final String? oblastId = salon.oblastId;
    final String? cityId = salon.cityId;
    if (oblastId == null || cityId == null || cityId.isEmpty) return;

    Oblast? matchedOblast;
    City? matchedCity;
    CityDistrict? matchedDistrict;

    try {
      final List<Oblast> oblasts = await ref.read(oblastListProvider.future);
      for (final Oblast o in oblasts) {
        if (o.id == oblastId) {
          matchedOblast = o;
          break;
        }
      }

      final Oblast? oblast = matchedOblast;
      if (oblast != null) {
        final List<City> cities = await ref.read(
          cityListProvider(oblast.id).future,
        );
        for (final City c in cities) {
          if (c.id == cityId) {
            matchedCity = c;
            break;
          }
        }
      }

      final String? districtId = salon.districtId;
      final City? city = matchedCity;
      if (districtId != null && city != null && city.hasDistricts) {
        final List<CityDistrict> districts = await ref.read(
          districtListProvider(city.id).future,
        );
        for (final CityDistrict d in districts) {
          if (d.id == districtId) {
            matchedDistrict = d;
            break;
          }
        }
      }
    } on Object catch (e, st) {
      if (kDebugMode) {
        log(
          'Locality pre-population failed — cascade will be empty',
          name: 'feature.salon.edit.address',
          level: 800,
          error: e,
          stackTrace: st,
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _selectedOblast = matchedOblast;
      _selectedCity = matchedCity;
      _selectedDistrict = matchedDistrict;
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
      _errDistrict = null;
    });
  }

  void _onCity(City? c) {
    setState(() {
      _selectedCity = c;
      _selectedDistrict = null;
      _errDistrict = null;
    });
  }

  void _onDistrict(CityDistrict? d) {
    setState(() {
      _selectedDistrict = d;
      if (d != null) _errDistrict = null;
    });
  }

  /// Finding 1 (2026-08-28) — mirrors `LocationEditScreen._validateLocation`'s
  /// district-required rule: a city that subdivides into districts
  /// ([City.hasDistricts]) MUST have a district picked before Save, or the
  /// per-field cityId/districtId dirty-diff in [SalonManagementProfile.
  /// saveAddress] can PATCH a cityId that requires a district while
  /// districtId reads as "unchanged" (still null) — an invalid locality pair
  /// the backend's `LocalityWriteValidator` rejects. `LocalityCascade`
  /// exposes `districtRequired`/`districtError` for exactly this; wired here.
  bool _validateDistrict() {
    final l10n = AppLocalizations.of(context);
    final bool cityHasDistricts = _selectedCity?.hasDistricts ?? false;
    final String? errDistrict = (cityHasDistricts && _selectedDistrict == null)
        ? l10n.errRequired
        : null;
    setState(() => _errDistrict = errDistrict);
    return errDistrict == null;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final String? streetErr = validateStreet(_streetCtrl.text, l10n);
    final String? buildingErr = validateBuilding(_buildingCtrl.text, l10n);
    final bool districtOk = _validateDistrict();
    if (streetErr != null || buildingErr != null || !districtOk) {
      setState(() {
        _errStreet = streetErr;
        _errBuildingNo = buildingErr;
      });
      showErrorSnack(context, l10n.editValidationSummary);
      return;
    }

    setState(() => _saving = true);
    final Failure? failure = await ref
        .read(salonManagementProfileProvider(widget.salonId).notifier)
        .saveAddress(
          cityId: _selectedCity?.id,
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
