// Phase 4.3 — Master Edit Screen.
//
// `ConsumerStatefulWidget` edit form for INDEPENDENT_MASTER profile fields.
//
// Design source: `docs/signup-designs/MasterEditScreen/` — transcribed 1:1.
// VelvetTouch soft neumorphism (light-mode, warm taupe base #E6DDD0).
//
// Layout (top → bottom):
//   Top bar     — cancel icon + centred "Редагувати профіль" title.
//   Scrollable  — avatar edit ring → "Змінити фото" caption → hairline →
//                 sub-heading → 5 VelvetField rows (firstName, lastName,
//                 bio, phone [optional + privacy note], instagram [optional]) →
//                 section divider → location section (LocalityCascade +
//                 street, buildingNo, locationNote fields).
//   Pinned foot — NeumorphicButton "Зберегти" (disabled when pristine,
//                 spinner when saving).
//
// Save flow: validates, calls [MasterRepository.updateMyProfile]; if location
// fields touched also calls [MasterRepository.updateLocality]; invalidates
// [masterProfileProvider], shows SnackBar, pops.
//
// Server field errors: [ValidationFailure.fieldErrors] keyed by field name.
// Each validator checks the server error first, then the local rule.
// Typing in a field clears its server error immediately.
//
// Avatar edit: tapping the camera badge shows a "Незабаром…" SnackBar.
// Photo upload is deferred to Phase 9.4.
//
// Staggered entrance: a single 900 ms AnimationController drives 7 staggered
// fade+translate reveals. CurvedAnimation instances are pre-built in initState
// — zero allocations in build().

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:screen_protector/screen_protector.dart';

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
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_update.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/ua_phone_input_formatter.dart';

import 'master_profile_notifier.dart';

/// Edit form for the authenticated INDEPENDENT_MASTER's own profile.
///
/// Pre-populated from [masterProfileProvider]'s current cached value.
/// Handles pristine (Save disabled), dirty (Save enabled), saving (spinner +
/// form locked), server-field-errors (inline per field), and network/server
/// error (SnackBar) states.
class MasterEditScreen extends ConsumerStatefulWidget {
  const MasterEditScreen({super.key});

  @override
  ConsumerState<MasterEditScreen> createState() => _MasterEditScreenState();
}

class _MasterEditScreenState extends ConsumerState<MasterEditScreen>
    with SingleTickerProviderStateMixin {
  // -------------------------------------------------------------------------
  // Animation — pre-built in initState; zero allocations in build().
  // -------------------------------------------------------------------------
  late final AnimationController _controller;
  late final CurvedAnimation _anim0; // avatar section
  late final CurvedAnimation _anim1; // sub-heading
  late final CurvedAnimation _anim2; // firstName + lastName
  late final CurvedAnimation _anim3; // bio
  late final CurvedAnimation _anim4; // phone
  late final CurvedAnimation _anim5; // instagram + footer
  late final CurvedAnimation _anim6; // location section

  // -------------------------------------------------------------------------
  // Form state
  // -------------------------------------------------------------------------
  final _formKey = GlobalKey<FormState>();

  // Controllers are late because they are initialized once master data lands.
  // Before _initialized is true, the loading scaffold renders instead.
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _bio;
  late final TextEditingController _phone;
  late final TextEditingController _instagram;

  // True once controllers have been seeded from the provider's master data.
  bool _initialized = false;

  // Snapshot of original values for pristine detection.
  String _origFirstName = '';
  String _origLastName = '';
  String _origBio = '';
  String _origPhone = '';
  String _origInstagram = '';

  // Original locality IDs — set once from master data in _maybeInit and
  // updated in _prePopulateLocality when the async lookup completes.
  // _isDirty compares current selections against these values so that a
  // pre-populated city does not immediately mark the form as dirty.
  String? _origCityId;
  String? _origOblastId;
  String? _origDistrictId;

  // Original address text values for pristine detection.
  String _origStreet = '';
  String _origBuildingNo = '';
  String _origLocationNote = '';

  /// Server-side field errors from the last [ValidationFailure].
  Map<String, String> _fieldErrors = const <String, String>{};

  bool _saving = false;

  // Inline error texts mirrored from FormField state so VelvetField can display
  // them without being a FormField itself. Updated after every validate() call.
  String? _errFirstName;
  String? _errLastName;
  String? _errBio;
  String? _errPhone;
  String? _errInstagram;

  // -------------------------------------------------------------------------
  // Location state — cascade selections + text controllers.
  // Controllers are seeded in _maybeInit from master.street / buildingNo /
  // locationNote. _selectedOblast, _selectedCity and _selectedDistrict are
  // pre-populated asynchronously in _maybeInit using master.oblastId,
  // master.cityId and master.districtId once the locality providers resolve.
  // -------------------------------------------------------------------------
  Oblast? _selectedOblast;
  City? _selectedCity;
  CityDistrict? _selectedDistrict;

  // Initialised lazily in _maybeInit along with the other controllers.
  late final TextEditingController _street;
  late final TextEditingController _buildingNo;
  late final TextEditingController _locationNote;

  // Inline validation errors for the location section.
  String? _errCity;
  String? _errStreet;
  String? _errBuildingNo;
  String? _errLocationNote;

  static const int _bioMax = 2000;
  static const int _phoneMax = 20;
  // Aligned to the backend address DTO (was 200/20/500 — stricter than the
  // server and wrongly rejected valid input).
  static const int _streetMax = 255;
  static const int _buildingNoMax = 50;
  static const int _locationNoteMax = 1000;

  // Pre-built cached styles — never call copyWith inside build().
  static final TextStyle _titleStyle = VelvetText.subheading();
  static final TextStyle _bodyStyle = VelvetText.body();
  static final TextStyle _changePhotoStyle = VelvetText.label().copyWith(
    color: BrandColors.accent,
    letterSpacing: 0.4,
  );

  // Fix 2 (PERF MEDIUM-1): static final Tween reused across all _reveal() calls
  // instead of allocating a new Tween<Offset> per call per build frame.
  static final Tween<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  );

  // Fix 5 (PERF LOW-1): static final RegExp so _validatePhone does not allocate
  // a new RegExp on every keystroke.
  static final RegExp _phoneAllowedChars = RegExp(r'^[+\d\s\-()]*$');

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    // Fix 4 (SEC MEDIUM): protect PII-bearing screen from screenshots/Recent Apps
    // thumbnails in release builds. Mirrors the pattern in master_profile_screen.
    if (!kDebugMode) ScreenProtector.preventScreenshotOn();

    // Controllers are NOT initialized here. They are seeded lazily from
    // the provider's first resolved data value in [_maybeInit] — called from
    // build() the first time [masterProfileProvider] has a non-null value.
    // This avoids a race condition where the provider completes its first
    // async build after initState runs (common in tests with Future.value stubs
    // and in production when the profile cache is cold).

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim0 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.00, 0.42, curve: Curves.easeOutCubic),
    );
    _anim1 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.06, 0.44, curve: Curves.easeOutCubic),
    );
    _anim2 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.10, 0.52, curve: Curves.easeOutCubic),
    );
    _anim3 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.22, 0.66, curve: Curves.easeOutCubic),
    );
    _anim4 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.30, 0.74, curve: Curves.easeOutCubic),
    );
    _anim5 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.38, 0.82, curve: Curves.easeOutCubic),
    );
    _anim6 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.60, 1.0, curve: Curves.easeOutCubic),
    );
  }

  /// Initializes text controllers from [master] on the FIRST call only.
  ///
  /// Called from [build] the first time [masterProfileProvider] resolves to
  /// a non-null [Master]. Subsequent calls are no-ops (guarded by [_initialized]).
  ///
  /// Text controllers are initialised synchronously. The locality cascade
  /// pre-population (oblast → city → district) runs asynchronously in a
  /// [Future.microtask] so that [setState] is never called during [build].
  void _maybeInit(Master master) {
    if (_initialized) return;
    _initialized = true;

    _origFirstName = master.firstName;
    _origLastName = master.lastName;
    _origBio = master.bio ?? '';
    _origPhone = master.phoneNumber ?? '';
    _origInstagram = master.instagram ?? '';

    _firstName = TextEditingController(text: _origFirstName);
    _lastName = TextEditingController(text: _origLastName);
    _bio = TextEditingController(text: _origBio);
    _phone = TextEditingController(text: _origPhone);
    _instagram = TextEditingController(text: _origInstagram);

    // Location text controllers — pre-populated from master data where available.
    _origStreet = master.street ?? '';
    _origBuildingNo = master.buildingNo ?? '';
    _origLocationNote = master.locationNote ?? '';
    _street = TextEditingController(text: _origStreet);
    _buildingNo = TextEditingController(text: _origBuildingNo);
    _locationNote = TextEditingController(text: _origLocationNote);

    // Single source of truth for dirty-tracking: a listener on every text
    // controller rebuilds the pinned footer (and thus re-evaluates _isDirty)
    // on every keystroke, independent of each field's per-onChanged setState.
    // This is what guarantees the Save button enables when only firstName is
    // edited. Listeners are removed in dispose().
    for (final c in _editableControllers) {
      c.addListener(_onFormChanged);
    }

    // Snapshot the original locality IDs for pristine detection. These are
    // updated again in _prePopulateLocality once the domain objects resolve,
    // but setting them here from the raw UUIDs ensures _isDirty is correct
    // even before the async lookup completes.
    _origOblastId = master.oblastId;
    _origCityId = master.cityId;
    _origDistrictId = master.districtId;

    // Start the entrance animation now that we have content to reveal.
    _controller.forward();

    // Async locality pre-population — deferred to a microtask so that this
    // synchronous _maybeInit call (invoked inside build via whenData) does not
    // call setState during the build phase.
    //
    // If any provider lookup fails (e.g. network error), we leave the cascade
    // empty — the user can re-select. We never surface the error here because
    // the locality cascade already has its own retry/error state.
    if (master.oblastId != null) {
      Future.microtask(() => _prePopulateLocality(master));
    }
  }

  /// Async helper: resolves [Oblast], [City], and [CityDistrict] objects from
  /// UUIDs stored on [master] and calls [setState] once all lookups complete.
  ///
  /// Uses [ref.read] (one-shot) — no continuous watching needed here.
  /// Silently no-ops on any exception (provider not yet loaded / network error).
  Future<void> _prePopulateLocality(Master master) async {
    // Resolved objects — default to null so that any unresolved/failed seed
    // leaves both the _selected* AND the _orig*Id side null (see reconcile
    // block below). This keeps the dirty/pristine pair symmetric.
    Oblast? matchedOblast;
    City? matchedCity;
    CityDistrict? matchedDistrict;

    try {
      // ----- Oblast -----
      final oblastId = master.oblastId;
      if (oblastId != null) {
        final oblasts = await ref.read(oblastListProvider.future);
        for (final o in oblasts) {
          if (o.id == oblastId) {
            matchedOblast = o;
            break;
          }
        }

        // ----- City ----- (only reachable if the oblast resolved)
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

        // ----- District (optional) -----
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
        name: 'feature.master.edit',
        level: 800,
        error: e,
        stackTrace: st,
      );
      // Swallow: leave whatever resolved so far. The reconcile block below
      // still runs so the orig/selected pair stays consistent.
    }

    if (!mounted) return;
    setState(() {
      _selectedOblast = matchedOblast;
      _selectedCity = matchedCity;
      _selectedDistrict = matchedDistrict;
      // Reconcile the pristine snapshot with what actually resolved. If a seed
      // UUID could not be resolved to a domain object (lookup miss, network
      // error, or a swallowed throw), the corresponding _selected* is null —
      // so clear its _orig*Id too. Otherwise an unresolved seed would leave
      // _orig*Id non-null while _selected* is null, falsely marking the form
      // dirty (or, in the inverse, falsely clean). Setting _orig*Id to the
      // resolved object's id keeps _isDirty correct in every case.
      _origOblastId = matchedOblast?.id;
      _origCityId = matchedCity?.id;
      _origDistrictId = matchedDistrict?.id;
    });
  }

  @override
  void dispose() {
    if (!kDebugMode) ScreenProtector.preventScreenshotOff();
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
    _anim4.dispose();
    _anim5.dispose();
    _anim6.dispose();
    _controller.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// All editable text controllers, in one place so the dirty-tracking
  /// listeners are attached (in _maybeInit) and detached (in dispose) from a
  /// single source of truth. Only valid after _initialized is true.
  List<TextEditingController> get _editableControllers =>
      <TextEditingController>[
        _firstName,
        _lastName,
        _bio,
        _phone,
        _instagram,
        _street,
        _buildingNo,
        _locationNote,
      ];

  /// Listener attached to every text controller. Rebuilds the form so the
  /// pinned footer's enabled/disabled state (driven by [_isDirty]) stays in
  /// sync with the latest text on every keystroke.
  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  bool get _isDirty =>
      _initialized &&
      (_firstName.text.trim() != _origFirstName ||
          _lastName.text.trim() != _origLastName ||
          _bio.text.trim() != _origBio ||
          _phone.text.trim() != _origPhone ||
          _instagram.text.trim() != _origInstagram ||
          _selectedOblast?.id != _origOblastId ||
          _selectedCity?.id != _origCityId ||
          _selectedDistrict?.id != _origDistrictId ||
          _street.text.trim() != _origStreet ||
          _buildingNo.text.trim() != _origBuildingNo ||
          _locationNote.text.trim() != _origLocationNote);

  Widget _reveal(CurvedAnimation anim, Widget child) {
    // Fix 2: reuse the static _slideTween — only the lightweight
    // _AnimatedEvaluation wrapper is allocated per call.
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

  // -------------------------------------------------------------------------
  // Validators — used by Form.validate() AND by the inline error update path.
  // -------------------------------------------------------------------------

  String? _validateFirstName(String? v) {
    final serverErr = _fieldErrors['firstName'];
    if (serverErr != null) return serverErr;
    if (v == null || v.trim().isEmpty) {
      return AppLocalizations.of(context).errNameRequired;
    }
    if (v.trim().length > 100) {
      return AppLocalizations.of(context).errNameTooLong;
    }
    return null;
  }

  String? _validateLastName(String? v) {
    final serverErr = _fieldErrors['lastName'];
    if (serverErr != null) return serverErr;
    if (v == null || v.trim().isEmpty) {
      return AppLocalizations.of(context).errNameRequired;
    }
    if (v.trim().length > 100) {
      return AppLocalizations.of(context).errNameTooLong;
    }
    return null;
  }

  String? _validateBio(String? v) {
    final serverErr = _fieldErrors['bio'];
    if (serverErr != null) return serverErr;
    if (v != null && v.length > _bioMax) {
      return AppLocalizations.of(context).errBioTooLong;
    }
    return null;
  }

  String? _validatePhone(String? v) {
    final serverErr = _fieldErrors['phoneNumber'];
    if (serverErr != null) return serverErr;
    if (v == null || v.trim().isEmpty) {
      // Phone is REQUIRED for all users — emptying it must block Save with a
      // field-specific message, never the generic errUnknown SnackBar.
      return AppLocalizations.of(context).errPhoneRequired;
    }
    if (v.trim().length > _phoneMax) {
      return AppLocalizations.of(context).errPhoneTooLongEdit;
    }
    if (!_phoneAllowedChars.hasMatch(v.trim())) {
      return AppLocalizations.of(context).errPhoneInvalidEdit;
    }
    return null;
  }

  // Pre-built static RegExps — allocated once, never inside build or validate.
  static final RegExp _instagramHandle = RegExp(r'^@?[A-Za-z0-9._]{1,30}$');
  static final RegExp _instagramUrl = RegExp(
    r'^https://(?:www\.)?instagram\.com/[A-Za-z0-9._/]{1,60}$',
  );

  String? _validateInstagram(String? v) {
    final serverErr = _fieldErrors['instagram'];
    if (serverErr != null) return serverErr;
    if (v == null || v.trim().isEmpty) return null; // optional
    if (!_instagramHandle.hasMatch(v.trim()) &&
        !_instagramUrl.hasMatch(v.trim())) {
      return AppLocalizations.of(context).masterEditInstagramError;
    }
    return null;
  }

  /// Returns true when the location section is fully valid (or untouched).
  ///
  /// The location section's required-address rule only kicks in when the user
  /// is *actively editing* the address — i.e. the section is dirty relative to
  /// its saved seed (`_origCityId`/`_origStreet`/`_origBuildingNo`, same fields
  /// `_isDirty` compares), OR the user has started entering an address (street
  /// or buildingNo non-empty). A pre-populated city with an empty street/
  /// building (a saved master with a partial address) must NOT force the fields
  /// to be required, otherwise Save silently aborts on an untouched section.
  bool _validateLocation() {
    final l10n = AppLocalizations.of(context);

    // Server-side field errors take precedence over the local rules, mirroring
    // the profile-field pattern. The backend keys the address errors by
    // `street` / `buildingNo` / `locationNote`. When any is present, surface it
    // inline regardless of the touched/dirty heuristic below and fail the
    // section so Save does not proceed with stale input.
    final serverStreet = _fieldErrors['street'];
    final serverBuildingNo = _fieldErrors['buildingNo'];
    final serverLocationNote = _fieldErrors['locationNote'];
    if (serverStreet != null ||
        serverBuildingNo != null ||
        serverLocationNote != null) {
      setState(() {
        _errStreet = serverStreet ?? _errStreet;
        _errBuildingNo = serverBuildingNo ?? _errBuildingNo;
        _errLocationNote = serverLocationNote;
      });
      return false;
    }

    final citySelected = _selectedCity != null;
    final streetFilled = _street.text.trim().isNotEmpty;
    final buildingFilled = _buildingNo.text.trim().isNotEmpty;

    // Dirty vs. the saved seed — mirrors the location slice of [_isDirty].
    final locationDirty =
        _selectedOblast?.id != _origOblastId ||
        _selectedCity?.id != _origCityId ||
        _selectedDistrict?.id != _origDistrictId ||
        _street.text.trim() != _origStreet ||
        _buildingNo.text.trim() != _origBuildingNo ||
        _locationNote.text.trim() != _origLocationNote;

    // The address is only "in play" when the user is actually entering one or
    // changing the saved value. A seeded-but-unmodified section is optional.
    final editingAddress = streetFilled || buildingFilled || locationDirty;
    if (!editingAddress) {
      // Section unchanged from its seed and no address entered — skip.
      setState(() {
        _errCity = null;
        _errStreet = null;
        _errBuildingNo = null;
        _errLocationNote = null;
      });
      return true;
    }

    // Presence checks — when actively editing an address, city, street and
    // buildingNo are all required so a half-entered address surfaces inline
    // errors on the missing fields.
    String? errCity = !citySelected ? l10n.errRequired : null;
    String? errStreet = !streetFilled ? l10n.errRequired : null;
    String? errBuildingNo = !buildingFilled ? l10n.errRequired : null;

    setState(() {
      _errCity = errCity;
      _errStreet = errStreet;
      _errBuildingNo = errBuildingNo;
    });

    // Length guard — VelvetField maxLength enforces on input, but guard
    // again here in case the value was seeded programmatically.
    final streetLen = _street.text.trim().length;
    final buildingLen = _buildingNo.text.trim().length;
    final noteLen = _locationNote.text.trim().length;
    if (streetLen > _streetMax ||
        buildingLen > _buildingNoMax ||
        noteLen > _locationNoteMax) {
      return false;
    }

    return errCity == null && errStreet == null && errBuildingNo == null;
  }

  /// Runs the form validators and mirrors errors into the inline state so
  /// VelvetField can display them via its [errorText] parameter.
  bool _validateAndUpdateErrors() {
    final profileOk = _formKey.currentState!.validate();
    setState(() {
      _errFirstName = _validateFirstName(_firstName.text);
      _errLastName = _validateLastName(_lastName.text);
      _errBio = _validateBio(_bio.text);
      _errPhone = _validatePhone(_phone.text);
      _errInstagram = _validateInstagram(_instagram.text);
    });
    final locationOk = _validateLocation();
    return profileOk && locationOk;
  }

  // -------------------------------------------------------------------------
  // Save
  // -------------------------------------------------------------------------

  Future<void> _save() async {
    if (!_initialized) return;
    setState(() {
      _fieldErrors = const <String, String>{};
      _errFirstName = null;
      _errLastName = null;
      _errBio = null;
      _errPhone = null;
      _errInstagram = null;
      _errCity = null;
      _errStreet = null;
      _errBuildingNo = null;
      _errLocationNote = null;
    });

    if (!_validateAndUpdateErrors()) {
      // Defense-in-depth: the inline errors live higher up the scroll view
      // while the Save button is pinned at the bottom, so a silent return
      // looks like a dead button. Surface a summary SnackBar so the user
      // knows why nothing happened. Matches the success-branch style.
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

    setState(() => _saving = true);

    try {
      await ref
          .read(masterRepositoryProvider)
          .updateMyProfile(
            MasterUpdate(
              firstName: _firstName.text.trim(),
              lastName: _lastName.text.trim(),
              bio: _bio.text.trim(),
              contactPhone: _phone.text.trim(),
              instagram: _instagram.text.trim(),
            ),
          );

      // Call updateLocality only when the user has selected a city (the
      // locality section was touched and validated). The guard here mirrors
      // the _validateLocation() "touched" condition.
      final selectedCity = _selectedCity;
      if (selectedCity != null) {
        if (!mounted) return;
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
      }

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
      if (kDebugMode) {
        log(
          'updateMyProfile validation failure: ${f.fieldErrors}',
          name: 'feature.master',
          level: 800,
        );
      }
      if (!mounted) return;
      setState(() {
        _fieldErrors = Map<String, String>.unmodifiable(f.fieldErrors);
        _saving = false;
      });
      // Re-mirror server errors into VelvetField errorText state.
      _validateAndUpdateErrors();
      // Defensive guard: a 400 with an EMPTY field map can highlight no input,
      // so the inline mirroring above renders nothing — the original "dead
      // Save" bug. Surface a generic SnackBar from the server message (or a
      // localized fallback) so the user always gets feedback, even if the
      // backend validation contract drifts again.
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
      // Catch-all: any non-Failure throw (e.g. TypeError / StateError) would
      // otherwise propagate uncaught, the finally would clear _saving, and the
      // user would see NO feedback — the original "absolutely nothing happens"
      // bug. Surface a generic error SnackBar so Save always reacts.
      if (kDebugMode) {
        log(
          'updateMyProfile unexpected error',
          name: 'feature.master',
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

  // -------------------------------------------------------------------------
  // Avatar
  // -------------------------------------------------------------------------

  void _onAvatarTap() {
    if (kDebugMode) {
      log(
        'Avatar edit tapped — photo upload deferred to Phase 9.4',
        name: 'feature.master',
        level: 800,
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).snackbarAvatarSoon)),
    );
  }

  String _buildInitials() {
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    if (first.isEmpty && last.isEmpty) return '?';
    final a = first.isNotEmpty ? first[0].toUpperCase() : '';
    final b = last.isNotEmpty ? last[0].toUpperCase() : '';
    final initials = '$a$b'.trim();
    return initials.isEmpty ? '?' : initials;
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Seed controllers from provider data on first successful resolution.
    // ref.watch ensures this rebuilds when the provider settles from loading.
    final masterAsync = ref.watch(masterProfileProvider);
    masterAsync.whenData<void>(_maybeInit);

    // Show a minimal centered indicator while waiting for data.
    if (!_initialized) {
      return const Scaffold(
        backgroundColor: BrandColors.base,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Top bar.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                VelvetSpacing.lg,
                VelvetSpacing.md,
                VelvetSpacing.lg,
                VelvetSpacing.sm,
              ),
              child: SizedBox(
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: NeumorphicIconButton(
                        key: const Key('btn-cancel-master'),
                        icon: Icons.close_rounded,
                        semanticLabel: l10n.masterCancelButton,
                        onTap: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go(RouteNames.masterProfile);
                          }
                        },
                      ),
                    ),
                    Text(
                      l10n.masterEditTitle,
                      style: _titleStyle,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            // Scrollable form body.
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    VelvetSpacing.lg,
                    VelvetSpacing.md,
                    VelvetSpacing.lg,
                    VelvetSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // 0 — Avatar edit section.
                      _reveal(
                        _anim0,
                        Column(
                          children: <Widget>[
                            Center(
                              child: NeumorphicAvatarEditor(
                                state: AvatarEditState.pristine,
                                initials: _buildInitials(),
                                onTap: _onAvatarTap,
                              ),
                            ),
                            const SizedBox(height: VelvetSpacing.sm),
                            Text(
                              l10n.changePhotoCaption,
                              style: _changePhotoStyle,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: VelvetSpacing.sm),
                            Divider(
                              thickness: 0.6,
                              color: BrandColors.accent.withValues(alpha: 0.25),
                            ),
                            const SizedBox(height: VelvetSpacing.md),
                          ],
                        ),
                      ),

                      // 1 — Sub-heading.
                      _reveal(
                        _anim1,
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 4,
                            bottom: VelvetSpacing.lg,
                          ),
                          child: Text(
                            l10n.updateDataSubheading,
                            style: _bodyStyle,
                          ),
                        ),
                      ),

                      // 2a — First name.
                      _reveal(
                        _anim2,
                        FormField<String>(
                          key: const Key('field-firstName'),
                          initialValue: _firstName.text,
                          validator: (_) => _validateFirstName(_firstName.text),
                          builder: (FormFieldState<String> field) {
                            return VelvetField(
                              label: l10n.firstNameLabel,
                              controller: _firstName,
                              enabled: !_saving,
                              hint: l10n.registerFirstNamePlaceholder,
                              errorText: _errFirstName,
                              onChanged: (v) {
                                _clearServerError('firstName');
                                field.didChange(v);
                                final next = _validateFirstName(
                                  _firstName.text,
                                );
                                if (next != _errFirstName) {
                                  setState(() => _errFirstName = next);
                                }
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: VelvetSpacing.lg),

                      // 2b — Last name.
                      _reveal(
                        _anim2,
                        FormField<String>(
                          key: const Key('field-lastName'),
                          initialValue: _lastName.text,
                          validator: (_) => _validateLastName(_lastName.text),
                          builder: (FormFieldState<String> field) {
                            return VelvetField(
                              label: l10n.lastNameLabel,
                              controller: _lastName,
                              enabled: !_saving,
                              hint: l10n.registerLastNamePlaceholder,
                              errorText: _errLastName,
                              onChanged: (v) {
                                _clearServerError('lastName');
                                field.didChange(v);
                                final next = _validateLastName(_lastName.text);
                                if (next != _errLastName) {
                                  setState(() => _errLastName = next);
                                }
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: VelvetSpacing.lg),

                      // 3 — Bio (multiline, max 2000, live counter).
                      _reveal(
                        _anim3,
                        FormField<String>(
                          key: const Key('field-bio'),
                          initialValue: _bio.text,
                          validator: (_) => _validateBio(_bio.text),
                          builder: (FormFieldState<String> field) {
                            return VelvetField(
                              label: l10n.bioLabel,
                              controller: _bio,
                              enabled: !_saving,
                              hint: l10n.masterEditBioHint,
                              maxLines: 4,
                              maxLength: _bioMax,
                              showCounter: true,
                              errorText: _errBio,
                              onChanged: (v) {
                                _clearServerError('bio');
                                field.didChange(v);
                                final next = _validateBio(_bio.text);
                                if (next != _errBio) {
                                  setState(() => _errBio = next);
                                }
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: VelvetSpacing.lg),

                      // 4 — Phone (optional, privacy helper, formatter).
                      _reveal(
                        _anim4,
                        FormField<String>(
                          key: const Key('field-phone'),
                          initialValue: _phone.text,
                          validator: (_) => _validatePhone(_phone.text),
                          builder: (FormFieldState<String> field) {
                            return VelvetField(
                              label: l10n.phoneLabel,
                              controller: _phone,
                              enabled: !_saving,
                              keyboardType: TextInputType.phone,
                              inputFormatters: const <UaPhoneInputFormatter>[
                                UaPhoneInputFormatter(),
                              ],
                              hint: '+380 __ ___ __ __',
                              errorText: _errPhone,
                              helperText: l10n.phonePrivacyNote,
                              onChanged: (v) {
                                _clearServerError('phoneNumber');
                                field.didChange(v);
                                setState(
                                  () => _errPhone = _validatePhone(_phone.text),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: VelvetSpacing.lg),

                      // 5 — Instagram handle (optional, @ prefix).
                      _reveal(
                        _anim5,
                        FormField<String>(
                          key: const Key('field-instagram'),
                          initialValue: _instagram.text,
                          // SECURITY-LOW: client-side format guard — reuses the
                          // static _validateInstagram method so the RegExps are
                          // allocated only once. Server-side validation remains
                          // the authoritative check.
                          validator: (_) => _validateInstagram(_instagram.text),
                          builder: (FormFieldState<String> field) {
                            return VelvetField(
                              label: l10n.instagramLabel,
                              controller: _instagram,
                              enabled: !_saving,
                              optional: true,
                              prefixText: '@',
                              hint: l10n.masterEditInstagramHint,
                              // _errInstagram is driven by _validateAndUpdateErrors()
                              // on save-tap and by the live onChanged path; it
                              // surfaces both the local format error and any
                              // server-side validation error from _fieldErrors.
                              errorText: _errInstagram,
                              onChanged: (v) {
                                _clearServerError('instagram');
                                field.didChange(v);
                                final next = _validateInstagram(
                                  _instagram.text,
                                );
                                if (next != _errInstagram) {
                                  setState(() => _errInstagram = next);
                                }
                              },
                            );
                          },
                        ),
                      ),

                      // 6 — Location section (city cascade + street/building/note).
                      _reveal(
                        _anim6,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            const SizedBox(height: VelvetSpacing.xl),
                            Divider(
                              thickness: 0.6,
                              color: BrandColors.accent.withValues(alpha: 0.25),
                            ),
                            const SizedBox(height: VelvetSpacing.md),
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 4,
                                bottom: VelvetSpacing.lg,
                              ),
                              child: Text(
                                l10n.masterEditLocationSection,
                                style: _bodyStyle,
                              ),
                            ),
                            LocalityCascade(
                              key: const Key('location-cascade'),
                              selectedOblast: _selectedOblast,
                              selectedCity: _selectedCity,
                              selectedDistrict: _selectedDistrict,
                              cityError: _errCity,
                              onOblast: (oblast) {
                                setState(() {
                                  _selectedOblast = oblast;
                                  _selectedCity = null;
                                  _selectedDistrict = null;
                                  _errCity = null;
                                });
                              },
                              onCity: (city) {
                                setState(() {
                                  _selectedCity = city;
                                  _selectedDistrict = null;
                                  if (city != null) _errCity = null;
                                });
                              },
                              onDistrict: (district) {
                                setState(() {
                                  _selectedDistrict = district;
                                });
                              },
                            ),
                            const SizedBox(height: VelvetSpacing.lg),
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
                            const SizedBox(height: VelvetSpacing.lg),
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
                            const SizedBox(height: VelvetSpacing.lg),
                            VelvetField(
                              key: const Key('field-locationNote'),
                              label: l10n.locationNoteLabel,
                              controller: _locationNote,
                              enabled: !_saving,
                              optional: true,
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
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Pinned Save CTA footer.
            _reveal(
              _anim5,
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: BrandColors.base,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: BrandColors.base,
                      offset: Offset(0, -12),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    VelvetSpacing.lg,
                    VelvetSpacing.sm,
                    VelvetSpacing.lg,
                    VelvetSpacing.md,
                  ),
                  child: NeumorphicButton(
                    key: const Key('btn-save-master'),
                    label: l10n.masterSaveButton,
                    icon: Icons.check_rounded,
                    loading: _saving,
                    onPressed: (!_saving && _isDirty) ? _save : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
