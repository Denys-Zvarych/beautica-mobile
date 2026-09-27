// CLIENT Локація — the location slice of the client profile: the shared
// [SettlementLocalityField] (one «Населений пункт» autocomplete, plus a «Район»
// row when the chosen settlement subdivides). A pinned "Зберегти" CTA sits at
// the bottom.
//
// Phase 346 — the «Область» + «Місто» cascade is GONE. The three-object
// selection state collapsed to a `String?` settlement id plus the district, and
// the pre-population reads the denormalised [User.cityName] the profile already
// carries instead of walking the oblast -> cities -> districts chain.
//
// For a CLIENT only the locality (settlement + district) is meaningful, so
// the free-text address fields (Вулиця / Будинок / Примітка) are NOT shown,
// collected, validated, or sent — the backend preserves any existing address
// values because the PATCH omits those keys.
//
// 1:1 transcription of the master [LocationEditScreen] with the approved CLIENT
// modifications:
//   • The settlement is OPTIONAL — the master's "city required when editing
//     address" rule is DROPPED. A CLIENT may save with none selected (the
//     backend's validateClientLocality permits a null city for clients).
//   • The free-text address fields are omitted entirely (client-only change).
//   • District is required ONLY when a settlement with districts is chosen.
//   • Save goes through [ClientProfileRepository.updateMyProfile] with
//     `touchesLocation: true` (PATCH /users/me) — the same endpoint as the other
//     client edit screens — sending the locality slice with a possibly-null
//     cityId and no address keys.
//
// Pre-population: the User profile carries cityId + the denormalised cityName,
// so the settlement field needs no lookup at all. Only the district still does
// (districtId has no denormalised counterpart), and only when one is saved —
// that seed runs asynchronously in a microtask so setState is never called
// during build.
//
// Security: ScreenProtector active in release builds (PII-bearing screen).

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
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/data/client_profile_repository.dart';
import 'package:beautica_mobile/features/home/domain/client_profile_update.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/presentation/saved_settlement_label.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/settlement_locality_field.dart';
import 'package:beautica_mobile/features/location/state/location_providers.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';

import 'package:beautica_mobile/features/master/presentation/widgets/section_scaffold.dart';

/// CLIENT location edit page (optional locality cascade only).
class ClientLocationEditScreen extends ConsumerStatefulWidget {
  const ClientLocationEditScreen({super.key});

  @override
  ConsumerState<ClientLocationEditScreen> createState() =>
      _ClientLocationEditScreenState();
}

class _ClientLocationEditScreenState
    extends ConsumerState<ClientLocationEditScreen>
    with SingleTickerProviderStateMixin {
  bool _initialized = false;

  /// The chosen settlement UUID — submitted as `cityId`.
  String? _settlementId;

  /// The settlement NAME shown before the user picks anything: the
  /// denormalised [User.cityName] `/users/me` already returns. Never submitted.
  String? _settlementLabel;

  CityDistrict? _selectedDistrict;

  String? _origCityId;
  String? _origDistrictId;

  Map<String, String> _fieldErrors = const <String, String>{};
  bool _saving = false;

  String? _errDistrict;

  // Animation — pre-built in initState; zero allocations in build().
  late final AnimationController _controller;
  late final CurvedAnimation _anim0; // subheading + cascade
  late final CurvedAnimation _animFooter; // pinned Save

  static final Tween<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  );

  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x rule).
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    _screenProtection = ref.read(screenProtectionProvider)..acquire();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim0 = _curve(0.00, 0.46);
    _animFooter = _curve(0.60, 1.0);
  }

  CurvedAnimation _curve(double start, double end) => CurvedAnimation(
    parent: _controller,
    curve: Interval(start, end, curve: Curves.easeOutCubic),
  );

  void _maybeInit(User user) {
    if (_initialized) return;
    _initialized = true;

    _origCityId = user.cityId;
    _origDistrictId = user.districtId;
    _settlementId = user.cityId;
    // Seeded with the SAME label the picker composes («м. Львів, Львівська
    // обл.»), never the bare name — see [savedSettlementLabel].
    _settlementLabel = savedSettlementLabel(
      AppLocalizations.of(context),
      user.savedSettlement,
    );

    _controller.forward();

    if (user.cityId != null && user.districtId != null) {
      Future.microtask(() => _prePopulateDistrict(user));
    }
  }

  /// Re-resolves the saved [User.districtId] to its display object.
  ///
  /// The settlement itself needs no resolving — `/users/me` returns its name
  /// denormalised as [User.cityName] — but the district row renders a
  /// `CityDistrict.name` and `districtId` has no denormalised counterpart. This
  /// is the SAME `GET /locations/cities/{id}/districts` read
  /// [SettlementLocalityField] issues to decide whether to render the row at
  /// all, so the provider is already warm.
  ///
  /// A failure leaves the row unlabelled rather than blocking the form. The
  /// pristine snapshot is NOT reconciled from the lookup: the id on the profile
  /// is authoritative whether or not its label resolved, so overwriting the
  /// snapshot with a failed resolve would make the untouched form read dirty.
  Future<void> _prePopulateDistrict(User user) async {
    final String? settlementId = user.cityId;
    final String? districtId = user.districtId;
    if (settlementId == null || districtId == null) return;

    List<CityDistrict> districts;
    try {
      districts = await ref.read(districtListProvider(settlementId).future);
    } on Object catch (e, st) {
      if (kDebugMode) {
        // Log only the error's runtime TYPE — never the raw error object,
        // whose toString() can embed PII (a DioException carrying the
        // /locations request/response). MS5/MS14 hygiene.
        log(
          'district pre-population failed (${e.runtimeType})',
          name: 'feature.client.edit.location',
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
    _anim0.dispose();
    _animFooter.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool get _isDirty =>
      _initialized &&
      (_settlementId != _origCityId ||
          _selectedDistrict?.id != _origDistrictId);

  Widget _reveal(CurvedAnimation anim, Widget child) {
    final Animation<Offset> slide = _slideTween.animate(anim);
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(position: slide, child: child),
    );
  }

  /// Returns true when the locality section is valid for a CLIENT.
  ///
  /// CLIENT modification vs master: the settlement is OPTIONAL (no "required"
  /// rule). The ONLY local rule is that a district must be chosen when the
  /// selected settlement subdivides into districts. A server `district` field
  /// error takes precedence and short-circuits to invalid.
  bool _validateLocation() {
    final l10n = AppLocalizations.of(context);

    final serverDistrict = _fieldErrors['district'];
    if (serverDistrict != null) {
      setState(() => _errDistrict = serverDistrict);
      return false;
    }

    final citySelected = _settlementId != null;
    // Phase 346 — the same [districtsOf] read the field itself uses to decide
    // whether to render the row, so the form and the row can never disagree.
    // `listen: false` — a validation callback, not `build`. [_save] awaits
    // [pendingDistrictLookup] before calling this.
    final cityHasDistricts = districtsOf(
      ref,
      _settlementId,
      listen: false,
    ).isNotEmpty;

    // District is required only when a settlement WITH districts is chosen.
    final String? errDistrict =
        (citySelected && cityHasDistricts && _selectedDistrict == null)
        ? l10n.errRequired
        : null;

    setState(() => _errDistrict = errDistrict);

    return errDistrict == null;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_initialized) return;
    setState(() {
      _fieldErrors = const <String, String>{};
      _errDistrict = null;
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

    setState(() => _saving = true);

    try {
      // CLIENT location is OPTIONAL — send the locality slice with a
      // possibly-null cityId (touchesLocation flags the repository to send the
      // locality keys exactly as carried, null included). The free-text address
      // keys (street / buildingNo / locationNote) are deliberately NOT passed,
      // so the PATCH omits them and the backend preserves any existing values.
      // Name + phone are untouched and preserved server-side too.
      await ref
          .read(clientProfileRepositoryProvider)
          .updateMyProfile(
            ClientProfileUpdate(
              touchesLocation: true,
              cityId: _settlementId,
              districtId: _selectedDistrict?.id,
            ),
          );

      if (!mounted) return;
      // Re-fetch the session User so clientProfile (derived from authProvider)
      // re-derives the fresh city; then invalidate the edit-seed + profile
      // providers so they re-read from the now-current session.
      await ref.read(authProvider.notifier).refreshUser();
      if (!mounted) return;
      ref.invalidate(clientEditProfileProvider);
      ref.invalidate(clientProfileProvider);
      // The Пошук (Search) screen's locality filter must reflect THIS just-saved
      // address AUTHORITATIVELY — via
      // [SearchFiltersController.applyProfileLocationSave], NOT the passive
      // [SearchFiltersController.prefillFromProfileIfNeeded] (see that method's
      // doc for why: an explicit "save my home address" here must always win,
      // even if the user already manually picked/cleared a DIFFERENT locality
      // inside Search's own picker earlier this session — those are different
      // intents and the passive method's anti-clobber guard must not apply
      // here). The passive method only runs from
      // `_ClientSearchScreenState.initState()`, which fires AT MOST ONCE per
      // app session: the Search tab lives inside `ClientShell`'s
      // `StatefulShellRoute.indexedStack`, so switching away from (and back to)
      // the Search branch never disposes/recreates its State. Invalidating the
      // two keepAlive controllers here would just reset them to blank defaults
      // with nothing left to re-seed them — the Search tab would come back
      // empty instead of showing the new locality. Calling
      // [applyProfileLocationSave] directly with the already-held settlement
      // id + label and the resolved [_selectedDistrict] closes that gap without
      // depending on `initState` firing again, needs no extra taxonomy fetch,
      // and also updates the sibling [SearchFilterLabelsController] labels
      // inline.
      //
      // Phase 346 — `cityHasDistricts` is read from the same [districtsOf] the
      // form validated against a moment ago, so Search's own district row gates
      // exactly as this screen's did.
      ref
          .read(searchFiltersControllerProvider.notifier)
          .applyProfileLocationSave(
            cityId: _settlementId,
            cityName: _settlementLabel,
            district: _selectedDistrict,
            cityHasDistricts: districtsOf(
              ref,
              _settlementId,
              listen: false,
            ).isNotEmpty,
          );
      if (!mounted) return;
      showSuccessSnack(context, AppLocalizations.of(context).savedSnackbar);
      context.go(RouteNames.clientHome);
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
        // Log only the error's runtime type — never the raw error object,
        // whose toString() can embed PII (e.g. a DioException carrying the
        // /users/me request/response: email, phone, saved locality). MS5/MS14
        // hygiene. Mirrors search_filters_controller.dart's
        // prefillFromProfileIfNeeded catch block.
        log(
          'client location save unexpected error (${e.runtimeType})',
          name: 'feature.client.edit.location',
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

    final profileAsync = ref.watch(clientEditProfileProvider);
    profileAsync.whenData<void>(_maybeInit);

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
          context.go(RouteNames.clientMenu);
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
                SettlementLocalityField(
                  key: const Key('location-cascade'),
                  settlementId: _settlementId,
                  initialSettlementLabel: _settlementLabel,
                  selectedDistrict: _selectedDistrict,
                  districtError: _errDistrict,
                  enabled: !_saving,
                  // A new settlement always clears the district: a
                  // `CityDistrict` belongs to exactly one settlement.
                  onSettlement: (String id, String label) {
                    setState(() {
                      _settlementId = id;
                      // The label moves with the id. It is not decoration: it
                      // is forwarded to `applyProfileLocationSave` on save, so
                      // a stale one would label the Пошук tab's locality chip
                      // with the PREVIOUS settlement while filtering by the
                      // new one.
                      _settlementLabel = label;
                      _selectedDistrict = null;
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
        ],
      ),
    );
  }
}
