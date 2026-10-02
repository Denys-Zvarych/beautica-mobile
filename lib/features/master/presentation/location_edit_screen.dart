// Локація — the location slice of the retired monolithic edit form: the shared
// [SettlementLocalityField] (one «Населений пункт» autocomplete, plus a «Район»
// row for the seventeen settlements that subdivide) plus the free-text Вулиця,
// Будинок and Примітка (optional) VelvetFields. A pinned "Зберегти" CTA sits at
// the bottom.
//
// Phase 346 — the «Область» + «Місто» cascade is GONE. The three-object
// selection state collapsed to a `String?` settlement id plus the district; the
// by-id oblast -> city -> district pre-population became the denormalised
// [Master.city] name handed to the field as its initial label; and the
// district-presence test moved from [City.hasDistricts] to [districtsOf],
// because the settlement search response deliberately carries no such flag.
//
// Save flow: validate → [MasterRepository.updateLocality] (this page does NOT
// call updateMyProfile, so no sibling-field-clearing concern) → invalidate
// masterProfileProvider → saved VelvetSnack → pop.
//
// Pre-population: the settlement label, the district and the address text
// controllers are seeded from the cached master. The district seed runs
// asynchronously in a microtask so setState is never called during build.
//
// Server field errors: [ValidationFailure.fieldErrors] keyed by district/
// street/buildingNo/locationNote.
//
// Security: ScreenProtector active in release builds (PII-bearing screen).
//
// Design source: `docs/signup-designs/ProfileSettingsHub/lib/screens/
// location_edit_screen.dart` — ported with the real locality field + repository
// (the preview's placeholder selectors are replaced by the production
// `SettlementLocalityField`).

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/velvet_field.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/presentation/saved_settlement_label.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/settlement_locality_field.dart';
import 'package:beautica_mobile/features/location/state/location_providers.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/validators/building_validator.dart';
import 'package:beautica_mobile/shared/validators/street_validator.dart';

import 'master_profile_notifier.dart';
import 'widgets/section_scaffold.dart';

/// Location edit page (locality cascade + street/buildingNo/locationNote).
class LocationEditScreen extends ConsumerStatefulWidget {
  const LocationEditScreen({super.key});

  @override
  ConsumerState<LocationEditScreen> createState() => _LocationEditScreenState();
}

class _LocationEditScreenState extends ConsumerState<LocationEditScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _street;
  late final TextEditingController _buildingNo;
  late final TextEditingController _locationNote;

  bool _initialized = false;

  /// The chosen settlement UUID — submitted as `cityId` (phase-326 D6).
  String? _settlementId;

  /// The settlement NAME to show before the user picks anything: the
  /// denormalised [Master.city] the profile read already carries. Purely a seed
  /// for the field's closed state; it is never submitted.
  String? _settlementLabel;

  CityDistrict? _selectedDistrict;

  String? _origCityId;
  String? _origDistrictId;
  String _origStreet = '';
  String _origBuildingNo = '';
  String _origLocationNote = '';

  Map<String, String> _fieldErrors = const <String, String>{};
  bool _saving = false;

  String? _errCity;
  String? _errDistrict;
  String? _errStreet;
  String? _errBuildingNo;
  String? _errLocationNote;

  // PERF (P2): drives the Save button's enabled state in isolation. Text
  // keystrokes update this notifier (via [_onFormChanged]) instead of
  // setState-ing the whole form and its reveal animation wrappers. Cascade
  // selection changes still go through setState (they are infrequent and also
  // mutate other UI), and the footer's builder recomputes [_isDirty] freshly on
  // both paths.
  final ValueNotifier<bool> _dirty = ValueNotifier<bool>(false);

  // Aligned to the backend address DTO.
  static const int _streetMax = 255;
  static const int _buildingNoMax = 50;
  static const int _locationNoteMax = 1000;

  // Animation — pre-built in initState; zero allocations in build().
  late final AnimationController _controller;
  late final CurvedAnimation _anim0; // subheading + cascade
  late final CurvedAnimation _anim1; // street
  late final CurvedAnimation _anim2; // buildingNo
  late final CurvedAnimation _anim3; // note
  late final CurvedAnimation _animFooter; // pinned Save

  static final Tween<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  );

  // Captured in initState so dispose() never touches `ref` — under Riverpod 3.x
  // using `ref` in dispose() throws ("widget is about to or has been
  // unmounted"). Hold the keepAlive manager reference instead.
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC MEDIUM-1/-2: ref-counted screenshot + iOS app-switcher-snapshot guard.
    _screenProtection = ref.read(screenProtectionProvider)..acquire();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim0 = _curve(0.00, 0.46);
    _anim1 = _curve(0.18, 0.62);
    _anim2 = _curve(0.26, 0.70);
    _anim3 = _curve(0.34, 0.78);
    _animFooter = _curve(0.60, 1.0);
  }

  CurvedAnimation _curve(double start, double end) => CurvedAnimation(
    parent: _controller,
    curve: Interval(start, end, curve: Curves.easeOutCubic),
  );

  void _maybeInit(Master master) {
    if (_initialized) return;
    _initialized = true;

    _origStreet = master.street ?? '';
    _origBuildingNo = master.buildingNo ?? '';
    _origLocationNote = master.locationNote ?? '';
    _street = TextEditingController(text: _origStreet);
    _buildingNo = TextEditingController(text: _origBuildingNo);
    _locationNote = TextEditingController(text: _origLocationNote);

    for (final c in _editableControllers) {
      c.addListener(_onFormChanged);
    }

    _origCityId = master.cityId;
    _origDistrictId = master.districtId;
    _settlementId = master.cityId;
    // Seeded with the SAME label the picker composes («м. Львів, Львівська
    // обл.»), never the bare name — see [savedSettlementLabel].
    _settlementLabel = savedSettlementLabel(
      AppLocalizations.of(context),
      master.savedSettlement,
    );

    _controller.forward();

    if (master.cityId != null && master.districtId != null) {
      Future.microtask(() => _prePopulateDistrict(master));
    }
  }

  /// Re-resolves the saved [Master.districtId] to its display object.
  ///
  /// The settlement itself no longer needs resolving — its name arrives
  /// denormalised on `/masters/me` (`UserProfileResponse.cityName`) and goes
  /// straight onto the field — but the district row renders a
  /// `CityDistrict.name`, and `districtId` has no denormalised counterpart.
  /// This is the SAME `GET /locations/cities/{id}/districts` read the field
  /// itself issues to decide whether to render the row at all, so the provider
  /// is already warm and this is a cache scan rather than a second round trip.
  ///
  /// A failure leaves the row unlabelled rather than blocking the form — the
  /// same degradation [districtsOf] documents. The pristine snapshot
  /// ([_origDistrictId]) is NOT reconciled from the lookup: unlike the cascade,
  /// which could only offer a district it had resolved, the id on the profile
  /// is authoritative whether or not its label resolved, so overwriting the
  /// snapshot with a failed resolve would make the untouched form read dirty.
  Future<void> _prePopulateDistrict(Master master) async {
    final String? settlementId = master.cityId;
    final String? districtId = master.districtId;
    if (settlementId == null || districtId == null) return;

    List<CityDistrict> districts;
    try {
      districts = await ref.read(districtListProvider(settlementId).future);
    } on Object catch (e, st) {
      if (kDebugMode) {
        // Log only the error's runtime TYPE — never the raw error object,
        // whose toString() can embed PII (a DioException carrying the
        // /locations request/response). Mirrors ClientLocationEditScreen.
        log(
          'District pre-population failed (${e.runtimeType}) — the row will '
          'render unlabelled',
          name: 'feature.master.edit.location',
          level: 800,
          stackTrace: st,
        );
      }
      return;
    }

    if (!mounted) return;
    for (final CityDistrict d in districts) {
      if (d.id == districtId) {
        setState(() => _selectedDistrict = d);
        return;
      }
    }
  }

  @override
  void dispose() {
    _screenProtection.release();
    if (_initialized) {
      for (final c in _editableControllers) {
        c.removeListener(_onFormChanged);
        c.dispose();
      }
    }
    _anim0.dispose();
    _anim1.dispose();
    _anim2.dispose();
    _anim3.dispose();
    _animFooter.dispose();
    _controller.dispose();
    _dirty.dispose();
    super.dispose();
  }

  List<TextEditingController> get _editableControllers =>
      <TextEditingController>[_street, _buildingNo, _locationNote];

  // PERF (P2): recompute the dirty flag only — no setState, so the form subtree
  // (locality cascade + address fields + animation wrappers) is not rebuilt on
  // every address keystroke. The footer's ValueListenableBuilder rebuilds just
  // the Save button when the flag flips.
  void _onFormChanged() {
    _dirty.value = _isDirty;
  }

  bool get _isDirty =>
      _initialized &&
      (_settlementId != _origCityId ||
          _selectedDistrict?.id != _origDistrictId ||
          _street.text.trim() != _origStreet ||
          _buildingNo.text.trim() != _origBuildingNo ||
          _locationNote.text.trim() != _origLocationNote);

  Widget _reveal(CurvedAnimation anim, Widget child) {
    final Animation<Offset> slide = _slideTween.animate(anim);
    // dim-decorative: screen entrance fade (`_reveal`); 1 at rest
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(position: slide, child: child),
    );
  }

  void _clearServerError(String fieldName) {
    if (_fieldErrors.containsKey(fieldName)) {
      setState(() {
        _fieldErrors = Map<String, String>.unmodifiable(
          Map<String, String>.from(_fieldErrors)..remove(fieldName),
        );
      });
    }
  }

  /// Returns true when the location section is valid.
  ///
  /// Street and building number are UNCONDITIONALLY required (mirrors the
  /// backend's `@NotBlank` contract on the provider location endpoints — the
  /// Phase 10.6 reversal), as is the locality (city, plus district when the
  /// city subdivides). Only [locationNote] is optional. The required-address
  /// rule no longer hides behind an "editing the address" gate — a master can
  /// never persist a locality with an empty street/building.
  bool _validateLocation() {
    final l10n = AppLocalizations.of(context);

    final serverDistrict = _fieldErrors['district'];
    final serverStreet = _fieldErrors['street'];
    final serverBuildingNo = _fieldErrors['buildingNo'];
    final serverLocationNote = _fieldErrors['locationNote'];
    if (serverDistrict != null ||
        serverStreet != null ||
        serverBuildingNo != null ||
        serverLocationNote != null) {
      setState(() {
        _errDistrict = serverDistrict ?? _errDistrict;
        _errStreet = serverStreet ?? _errStreet;
        _errBuildingNo = serverBuildingNo ?? _errBuildingNo;
        _errLocationNote = serverLocationNote;
      });
      return false;
    }

    final citySelected = _settlementId != null;
    // Phase 346 — no longer [City.hasDistricts] (the settlement search response
    // carries no such flag): the SAME [districtsOf] read the field itself uses
    // to decide whether to render the row, so the form and the row can never
    // disagree about whether a district is owed.
    // `listen: false` — a validation callback, not `build`. [_save] awaits
    // [pendingDistrictLookup] before calling this.
    final cityHasDistricts = districtsOf(
      ref,
      _settlementId,
      listen: false,
    ).isNotEmpty;

    final String? errCity = !citySelected ? l10n.errSettlementRequired : null;
    final String? errDistrict =
        (citySelected && cityHasDistricts && _selectedDistrict == null)
        ? l10n.errRequired
        : null;
    // Reuse the shared provider validators — the same ones RegisterStep3Screen
    // uses (registration is the canonical always-required behaviour). They emit
    // errStreetRequired / errBuildingRequired (and the too-long variants).
    final String? errStreet = validateStreet(_street.text, l10n);
    final String? errBuildingNo = validateBuilding(_buildingNo.text, l10n);

    setState(() {
      _errCity = errCity;
      _errDistrict = errDistrict;
      _errStreet = errStreet;
      _errBuildingNo = errBuildingNo;
    });

    final noteLen = _locationNote.text.trim().length;
    if (noteLen > _locationNoteMax) {
      return false;
    }

    return errCity == null &&
        errDistrict == null &&
        errStreet == null &&
        errBuildingNo == null;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_initialized) return;
    setState(() {
      _fieldErrors = const <String, String>{};
      _errCity = null;
      _errDistrict = null;
      _errStreet = null;
      _errBuildingNo = null;
      _errLocationNote = null;
    });

    final Future<void>? districtLookup = pendingDistrictLookup(
      ref,
      _settlementId,
    );
    if (districtLookup != null) {
      // Busy BEFORE the await (perf N1): the CTA disables and a second tap
      // hits the `_saving` guard instead of starting a second submit. Reset
      // straight after — everything from here to the submit's own
      // `_saving = true` is synchronous, so no tap can slip in between, and
      // every early return below leaves the flag clear.
      setState(() => _saving = true);
      await districtLookup;
      if (!mounted) return;
      setState(() => _saving = false);
    }

    if (!_validateLocation()) {
      if (mounted) {
        showErrorSnack(
          context,
          AppLocalizations.of(context).editValidationSummary,
        );
      }
      return;
    }

    final selectedSettlementId = _settlementId;
    if (selectedSettlementId == null) {
      // Defensive: unreachable once _validateLocation() returns true, since the
      // city is now unconditionally required (it sets _errCity and returns
      // false when no city is chosen). We must NOT fall through to a "no-op
      // save + navigate" here — that was the escape hatch that let an
      // empty-street/building locality slip past. Stay on the form.
      return;
    }

    setState(() => _saving = true);

    try {
      await ref
          .read(masterRepositoryProvider)
          .updateLocality(
            cityId: selectedSettlementId,
            districtId: _selectedDistrict?.id,
            street: _street.text.trim(),
            buildingNo: _buildingNo.text.trim(),
            locationNote: _locationNote.text.trim().isEmpty
                ? null
                : _locationNote.text.trim(),
          );

      if (!mounted) return;
      ref.invalidate(masterProfileProvider);
      showSuccessSnack(context, AppLocalizations.of(context).savedSnackbar);
      context.go(RouteNames.masterProfile);
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _fieldErrors = Map<String, String>.unmodifiable(f.fieldErrors);
        _saving = false;
      });
      _validateLocation();
      if (f.fieldErrors.isEmpty) {
        // Localized only — the raw backend serverMessage can be
        // untranslated/technical and must not reach this VelvetSnack
        // (mobile-security, 2026-08). f.userMessage() already returns the
        // localized errValidation copy for ValidationFailure.
        showErrorSnack(context, f.userMessage(context));
      }
    } on Failure catch (f) {
      if (!mounted) return;
      showErrorSnack(context, f.userMessage(context));
      setState(() => _saving = false);
    } catch (e, st) {
      if (kDebugMode) {
        // Runtime TYPE only — the raw error's toString() can embed the
        // submitted address (MS5/MS14 hygiene).
        log(
          'location save unexpected error (${e.runtimeType})',
          name: 'feature.master.edit.location',
          level: 1000,
          stackTrace: st,
        );
      }
      if (!mounted) return;
      showErrorSnack(context, AppLocalizations.of(context).errUnknown);
      setState(() => _saving = false);
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final masterAsync = ref.watch(masterProfileProvider);
    masterAsync.whenData<void>(_maybeInit);

    if (!_initialized) {
      return const Scaffold(
        backgroundColor: BrandColors.base,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SectionScaffold(
      title: l10n.locationTitle,
      backKey: const Key('btn-back-location'),
      backSemanticLabel: l10n.masterCancelButton,
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(RouteNames.masterMenu);
        }
      },
      footer: _reveal(
        _animFooter,
        ValueListenableBuilder<bool>(
          valueListenable: _dirty,
          // Recompute [_isDirty] freshly: text keystrokes flip [_dirty] (this
          // rebuilds the builder), and cascade selections setState the parent
          // (which also rebuilds the builder) — both paths land here.
          builder: (context, _, _) => NeumorphicButton(
            key: const Key('btn-save-location'),
            label: l10n.masterSaveButton,
            icon: Icons.check_rounded,
            loading: _saving,
            onPressed: (!_saving && _isDirty) ? _save : null,
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _reveal(
            _anim0,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(
                    left: 4,
                    bottom: VelvetSpacing.lg,
                  ),
                  child: Text(
                    l10n.masterLocationSubheading,
                    style: VelvetText.body(),
                  ),
                ),
                SettlementLocalityField(
                  key: const Key('location-cascade'),
                  settlementId: _settlementId,
                  initialSettlementLabel: _settlementLabel,
                  selectedDistrict: _selectedDistrict,
                  settlementError: _errCity,
                  districtError: _errDistrict,
                  enabled: !_saving,
                  // A new settlement always clears the district: a
                  // `CityDistrict` belongs to exactly one settlement.
                  onSettlement: (String id, String label) {
                    setState(() {
                      _settlementId = id;
                      _settlementLabel = label;
                      _selectedDistrict = null;
                      _errCity = null;
                      _errDistrict = null;
                    });
                    _onFormChanged();
                  },
                  onDistrict: (district) {
                    setState(() {
                      _selectedDistrict = district;
                      if (district != null) _errDistrict = null;
                    });
                    _onFormChanged();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: VelvetSpacing.lg),
          _reveal(
            _anim1,
            VelvetField(
              key: const Key('field-street'),
              label: l10n.streetLabel,
              controller: _street,
              enabled: !_saving,
              hint: l10n.step3FieldStreetPlaceholder,
              errorText: _errStreet,
              maxLength: _streetMax,
              onChanged: (_) {
                _clearServerError('street');
                if (_errStreet != null) {
                  setState(() => _errStreet = null);
                }
              },
            ),
          ),
          const SizedBox(height: VelvetSpacing.lg),
          _reveal(
            _anim2,
            VelvetField(
              key: const Key('field-buildingNo'),
              label: l10n.buildingNoLabel,
              controller: _buildingNo,
              enabled: !_saving,
              hint: l10n.step3FieldBuildingPlaceholder,
              errorText: _errBuildingNo,
              maxLength: _buildingNoMax,
              onChanged: (_) {
                _clearServerError('buildingNo');
                if (_errBuildingNo != null) {
                  setState(() => _errBuildingNo = null);
                }
              },
            ),
          ),
          const SizedBox(height: VelvetSpacing.lg),
          _reveal(
            _anim3,
            VelvetField(
              key: const Key('field-locationNote'),
              label: l10n.locationNoteLabel,
              controller: _locationNote,
              enabled: !_saving,
              optional: true,
              maxLines: 3,
              hint: l10n.step3FieldNotePlaceholder,
              errorText: _errLocationNote,
              maxLength: _locationNoteMax,
              onChanged: (_) {
                _clearServerError('locationNote');
                if (_errLocationNote != null) {
                  setState(() => _errLocationNote = null);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
