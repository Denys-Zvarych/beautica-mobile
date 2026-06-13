// Локація — the location slice of the retired monolithic edit form: a
// three-level locality cascade (Область → Місто → Район, district required when
// the city subdivides) plus the free-text Вулиця, Будинок and Примітка
// (optional) VelvetFields. A pinned "Зберегти" CTA sits at the bottom.
//
// Save flow: validate → [MasterRepository.updateLocality] (this page does NOT
// call updateMyProfile, so no sibling-field-clearing concern) → invalidate
// masterProfileProvider → saved SnackBar → pop.
//
// Pre-population: the cascade selections (oblast → city → district) and the
// address text controllers are seeded from the cached master. The cascade seed
// runs asynchronously in a microtask so setState is never called during build.
//
// Server field errors: [ValidationFailure.fieldErrors] keyed by district/
// street/buildingNo/locationNote.
//
// Security: ScreenProtector active in release builds (PII-bearing screen).
//
// Design source: `docs/signup-designs/ProfileSettingsHub/lib/screens/
// location_edit_screen.dart` — ported with the real LocalityCascade + repository
// (the preview's placeholder selectors are replaced by the production cascade).

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
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/locality_cascade.dart';
import 'package:beautica_mobile/features/location/state/location_providers.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

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

  Oblast? _selectedOblast;
  City? _selectedCity;
  CityDistrict? _selectedDistrict;

  String? _origCityId;
  String? _origOblastId;
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

    _origOblastId = master.oblastId;
    _origCityId = master.cityId;
    _origDistrictId = master.districtId;

    _controller.forward();

    if (master.oblastId != null) {
      Future.microtask(() => _prePopulateLocality(master));
    }
  }

  /// Resolves [Oblast], [City], [CityDistrict] objects from the UUIDs on
  /// [master] and reconciles the pristine snapshot once the lookups complete.
  Future<void> _prePopulateLocality(Master master) async {
    Oblast? matchedOblast;
    City? matchedCity;
    CityDistrict? matchedDistrict;

    try {
      final oblastId = master.oblastId;
      if (oblastId != null) {
        final oblasts = await ref.read(oblastListProvider.future);
        for (final o in oblasts) {
          if (o.id == oblastId) {
            matchedOblast = o;
            break;
          }
        }

        final cityId = master.cityId;
        if (matchedOblast != null && cityId != null) {
          final cities = await ref.read(
            cityListProvider(matchedOblast.id).future,
          );
          for (final c in cities) {
            if (c.id == cityId) {
              matchedCity = c;
              break;
            }
          }
        }

        final districtId = master.districtId;
        if (districtId != null &&
            matchedCity != null &&
            matchedCity.hasDistricts) {
          final districts = await ref.read(
            districtListProvider(matchedCity.id).future,
          );
          for (final d in districts) {
            if (d.id == districtId) {
              matchedDistrict = d;
              break;
            }
          }
        }
      }
    } catch (e, st) {
      log(
        'Locality pre-population failed — cascade will be empty',
        name: 'feature.master.edit.location',
        level: 800,
        error: e,
        stackTrace: st,
      );
    }

    if (!mounted) return;
    setState(() {
      _selectedOblast = matchedOblast;
      _selectedCity = matchedCity;
      _selectedDistrict = matchedDistrict;
      _origOblastId = matchedOblast?.id;
      _origCityId = matchedCity?.id;
      _origDistrictId = matchedDistrict?.id;
    });
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
    super.dispose();
  }

  List<TextEditingController> get _editableControllers =>
      <TextEditingController>[_street, _buildingNo, _locationNote];

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  bool get _isDirty =>
      _initialized &&
      (_selectedOblast?.id != _origOblastId ||
          _selectedCity?.id != _origCityId ||
          _selectedDistrict?.id != _origDistrictId ||
          _street.text.trim() != _origStreet ||
          _buildingNo.text.trim() != _origBuildingNo ||
          _locationNote.text.trim() != _origLocationNote);

  Widget _reveal(CurvedAnimation anim, Widget child) {
    final Animation<Offset> slide = _slideTween.animate(anim);
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

  /// Returns true when the location section is valid. The required-address rule
  /// only kicks in when the user is actively editing the address (the section is
  /// dirty, or street/buildingNo non-empty).
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

    final citySelected = _selectedCity != null;
    final streetFilled = _street.text.trim().isNotEmpty;
    final buildingFilled = _buildingNo.text.trim().isNotEmpty;

    final locationDirty =
        _selectedOblast?.id != _origOblastId ||
        _selectedCity?.id != _origCityId ||
        _selectedDistrict?.id != _origDistrictId ||
        _street.text.trim() != _origStreet ||
        _buildingNo.text.trim() != _origBuildingNo ||
        _locationNote.text.trim() != _origLocationNote;

    final editingAddress = streetFilled || buildingFilled || locationDirty;
    if (!editingAddress) {
      setState(() {
        _errCity = null;
        _errDistrict = null;
        _errStreet = null;
        _errBuildingNo = null;
        _errLocationNote = null;
      });
      return true;
    }

    final String? errCity = !citySelected ? l10n.errRequired : null;
    final String? errStreet = !streetFilled ? l10n.errRequired : null;
    final String? errBuildingNo = !buildingFilled ? l10n.errRequired : null;

    final cityHasDistricts = _selectedCity?.hasDistricts ?? false;
    final String? errDistrict =
        (citySelected && cityHasDistricts && _selectedDistrict == null)
        ? l10n.errRequired
        : null;

    setState(() {
      _errCity = errCity;
      _errDistrict = errDistrict;
      _errStreet = errStreet;
      _errBuildingNo = errBuildingNo;
    });

    final streetLen = _street.text.trim().length;
    final buildingLen = _buildingNo.text.trim().length;
    final noteLen = _locationNote.text.trim().length;
    if (streetLen > _streetMax ||
        buildingLen > _buildingNoMax ||
        noteLen > _locationNoteMax) {
      return false;
    }

    return errCity == null &&
        errDistrict == null &&
        errStreet == null &&
        errBuildingNo == null;
  }

  Future<void> _save() async {
    if (!_initialized) return;
    setState(() {
      _fieldErrors = const <String, String>{};
      _errCity = null;
      _errDistrict = null;
      _errStreet = null;
      _errBuildingNo = null;
      _errLocationNote = null;
    });

    if (!_validateLocation()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const Key('snackbar-validation-summary'),
            content: Text(AppLocalizations.of(context).editValidationSummary),
          ),
        );
      }
      return;
    }

    final selectedCity = _selectedCity;
    if (selectedCity == null) {
      // Nothing to persist (no city chosen, no address entered). Treat as a
      // no-op save and pop — mirrors the monolithic form's touched guard.
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(RouteNames.masterProfile);
      }
      return;
    }

    setState(() => _saving = true);

    try {
      await ref
          .read(masterRepositoryProvider)
          .updateLocality(
            cityId: selectedCity.id,
            districtId: _selectedDistrict?.id,
            street: _street.text.trim(),
            buildingNo: _buildingNo.text.trim(),
            locationNote: _locationNote.text.trim().isEmpty
                ? null
                : _locationNote.text.trim(),
          );

      if (!mounted) return;
      ref.invalidate(masterProfileProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('snackbar-saved'),
          content: Text(AppLocalizations.of(context).savedSnackbar),
        ),
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(RouteNames.masterProfile);
      }
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _fieldErrors = Map<String, String>.unmodifiable(f.fieldErrors);
        _saving = false;
      });
      _validateLocation();
      if (f.fieldErrors.isEmpty) {
        final serverMessage = f.serverMessage?.trim();
        final text = (serverMessage != null && serverMessage.isNotEmpty)
            ? serverMessage
            : AppLocalizations.of(context).errValidation;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const Key('snackbar-validation-error'),
            content: Text(text),
          ),
        );
      }
    } on Failure catch (f) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(f.userMessage(context))));
      setState(() => _saving = false);
    } catch (e, st) {
      if (kDebugMode) {
        log(
          'location save unexpected error',
          name: 'feature.master.edit.location',
          level: 1000,
          error: e,
          stackTrace: st,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).errUnknown)),
      );
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
        NeumorphicButton(
          key: const Key('btn-save-location'),
          label: l10n.masterSaveButton,
          icon: Icons.check_rounded,
          loading: _saving,
          onPressed: (!_saving && _isDirty) ? _save : null,
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
                    l10n.locationSubheading,
                    style: VelvetText.body(),
                  ),
                ),
                LocalityCascade(
                  key: const Key('location-cascade'),
                  selectedOblast: _selectedOblast,
                  selectedCity: _selectedCity,
                  selectedDistrict: _selectedDistrict,
                  districtRequired: true,
                  cityError: _errCity,
                  districtError: _errDistrict,
                  onOblast: (oblast) {
                    setState(() {
                      _selectedOblast = oblast;
                      _selectedCity = null;
                      _selectedDistrict = null;
                      _errCity = null;
                      _errDistrict = null;
                    });
                  },
                  onCity: (city) {
                    setState(() {
                      _selectedCity = city;
                      _selectedDistrict = null;
                      if (city != null) _errCity = null;
                      _errDistrict = null;
                    });
                  },
                  onDistrict: (district) {
                    setState(() {
                      _selectedDistrict = district;
                      if (district != null) _errDistrict = null;
                    });
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
