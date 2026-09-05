// Phase 21.3 — RegisterSalonScreen («Новий салон»).
//
// Reached from the «Мої салони» hub's «+ Додати салон» CTA
// (`my_salons_screen.dart`'s `_addSalon`, wired this phase). A `SALON_OWNER`
// can own several salons at different addresses; this form adds another
// salon under the same owner: name → cascading locality (oblast → city →
// district) → street/building/note → phone → Instagram (optional).
//
// REUSE-FIRST:
//   - [LocalityCascade] (Phase 2.18) reused VERBATIM for the cascade — same
//     widget `RegisterStep3Screen`/`SalonAddressEditScreen` already consume.
//     Validation follows `RegisterStep3Screen`'s shape (oblast+city required,
//     district required when the city has one — [validateProviderLocality]),
//     NOT `SalonAddressEditScreen`'s simpler district-only check: this is a
//     brand-new salon with no pre-existing address, exactly like a fresh
//     provider registration, not an edit of an address that may already be
//     set.
//   - [SectionScaffold] + [VelvetField] (Phase 21.10 family) reused instead
//     of the approved preview's own `FormScaffold` + `NeumorphicTextField` —
//     mirrors the SAME substitution `SalonProfileEditScreen`/
//     `SalonAddressEditScreen`/`SalonContactsEditScreen` already made for
//     their own preview source (`docs/signup-designs/SalonManagementDesign/
//     lib/screens/register_salon_screen.dart`'s own `FormScaffold` heading
//     text becomes this screen's [SectionScaffold.title] + a body subheading,
//     exactly like those three siblings). The preview's own name/street/
//     building/note/phone/Instagram fields, order, copy, and CTA are
//     transcribed literally otherwise.
//   - Name validator: [validateSalonName] (Phase 2.17, `register_step_2_screen
//     .dart`'s own validator). Street/building: [validateStreet]/
//     [validateBuilding] (Phase 2.19). Phone/Instagram: [validateSalonPhone]/
//     [validateSalonInstagram] — PROMOTED this phase out of
//     `SalonContactsEditScreen`'s private validators (see those files' own
//     doc) rather than a third near-duplicate.
//   - Submit + `mySalonsProvider` invalidation: [RegisterSalon.submit]
//     (`register_salon_notifier.dart`) wraps the EXISTING
//     `SalonRepository.create` — no new write path.
//
// Contact prefill: phone/Instagram seed from the owner's PRIMARY salon (most
// owners run every salon under one contact line) via `mySalonsProvider`,
// which this screen already watches — the approved preview's own
// `prefillPhone`/`prefillInstagram` constructor params are sourced from that
// provider directly in this production port instead of a caller-supplied
// param, since every entry point is the same «+ Додати салон» hub CTA.
// Locality/address fields always start empty — each salon has a distinct
// address.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/velvet_field.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/formatters/ua_phone_input_formatter.dart';
import 'package:beautica_mobile/shared/validators/building_validator.dart';
import 'package:beautica_mobile/shared/validators/locality_validator.dart';
import 'package:beautica_mobile/shared/validators/location_note_validator.dart'
    show kLocationNoteMaxLength;
import 'package:beautica_mobile/shared/validators/salon_instagram_validator.dart';
import 'package:beautica_mobile/shared/validators/salon_name_validator.dart';
import 'package:beautica_mobile/shared/validators/salon_phone_validator.dart';
import 'package:beautica_mobile/shared/validators/street_validator.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/locality_cascade.dart';

import '../../master/presentation/widgets/section_scaffold.dart';
import '../application/my_salons_notifier.dart';
import '../application/register_salon_notifier.dart';
import '../domain/salon.dart';

/// Backend `UpdateSalonRequest`/`CreateSalonRequest` name cap
/// (`tool/openapi/api-spec.json`), matching `SalonProfileEditScreen`'s
/// identical constant.
const int _kNameMaxLength = 255;

/// The `SALON_OWNER`'s «+ Додати салон» form.
class RegisterSalonScreen extends ConsumerStatefulWidget {
  const RegisterSalonScreen({super.key});

  @override
  ConsumerState<RegisterSalonScreen> createState() =>
      _RegisterSalonScreenState();
}

class _RegisterSalonScreenState extends ConsumerState<RegisterSalonScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _streetCtrl = TextEditingController();
  final TextEditingController _buildingCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _instagramCtrl = TextEditingController();

  Oblast? _selectedOblast;
  City? _selectedCity;
  CityDistrict? _selectedDistrict;

  bool _contactsPrefilled = false;
  bool _prefilledFromPrimary = false;
  bool _submitting = false;

  String? _errName;
  LocalityValidationError? _localityError;
  String? _errStreet;
  String? _errBuildingNo;
  String? _errPhone;
  String? _errInstagram;

  /// Manual, non-`build()` subscription to [mySalonsProvider] — see
  /// [initState]'s own doc (mobile-perf LOW fix) for why `build()` no longer
  /// `ref.watch`es this provider directly.
  ProviderSubscription<AsyncValue<List<Salon>>>? _mySalonsSub;

  @override
  void initState() {
    super.initState();
    // mobile-perf LOW fix — decouple this form's rebuild rate from
    // `mySalonsProvider`'s lifecycle. `build()` used to `ref.watch(
    // mySalonsProvider)` purely to drive the ONE-TIME contact prefill below,
    // which meant the WHOLE form (LocalityCascade + all 6 VelvetFields)
    // rebuilt on every emission of that keepAlive provider, not just the
    // first:
    //   1. `_submit()` invalidates `mySalonsProvider` immediately before
    //      `context.pop()`, and this screen was still a live `watch`
    //      listener at that instant — one wasted full-form rebuild moments
    //      before disposal.
    //   2. Any future UNRELATED invalidation of `mySalonsProvider` while
    //      this screen happened to stay open would rebuild the whole form
    //      for nothing, since the prefill had already run.
    //
    // Two-path handling of the ASYNC-ARRIVAL case (mySalonsProvider still
    // `AsyncLoading` when this screen mounts — a genuine cold deep link;
    // ordinarily the keepAlive provider is already resolved from the hub
    // visit that reaches this screen):
    //   (a) ALREADY RESOLVED at mount time (the common case) — handled by
    //       the plain `ref.read` immediately below, SYNCHRONOUSLY, before
    //       the first `build()` ever runs. No `setState` needed: the first
    //       build simply reads the already-populated controllers.
    //   (b) STILL LOADING at mount time — handled by the `ref.listenManual`
    //       subscription below, which fires again once the provider
    //       transitions to `AsyncData`. That callback only ever runs on a
    //       genuine state CHANGE (never synchronously at registration —
    //       `fireImmediately` is deliberately NOT set), so it is always
    //       strictly after the first `build()`, making `setState` inside it
    //       safe by construction — no "setState during initState/build"
    //       ambiguity to reason about.
    //
    // After a successful prefill (either path), `_contactsPrefilled` gates
    // the listener body to an early-return no-op — including for the
    // `_submit()`-triggered invalidation above, which by then always finds
    // `_contactsPrefilled == true` (the user has already filled the whole
    // form by the time they can tap submit). No `setState`, no rebuild, for
    // every emission after the first successful prefill.
    //
    // Riverpod trap avoided: `.value` here is read ONLY to detect "is there
    // ANY resolved data yet", never to infer "did a reload just happen" —
    // the latter is the documented footgun (`ref.invalidate` RETAINS the
    // previous `.value`, so gating reload-detection on `value == null`
    // silently lies). The actual "already done" gate is the dedicated
    // `_contactsPrefilled` bool, checked BEFORE `.value` is even read.
    final List<Salon>? alreadyResolved = ref.read(mySalonsProvider).value;
    if (alreadyResolved != null) {
      _prefillContactsOnce(alreadyResolved);
    }
    _mySalonsSub = ref.listenManual<AsyncValue<List<Salon>>>(mySalonsProvider, (
      AsyncValue<List<Salon>>? previous,
      AsyncValue<List<Salon>> next,
    ) {
      if (_contactsPrefilled) return; // one-time — nothing left to do, ever
      final List<Salon>? salons = next.value;
      if (salons == null) return; // still loading / errored — wait for data
      setState(() => _prefillContactsOnce(salons));
    });
  }

  @override
  void dispose() {
    _mySalonsSub?.close();
    _nameCtrl.dispose();
    _streetCtrl.dispose();
    _buildingCtrl.dispose();
    _noteCtrl.dispose();
    _phoneCtrl.dispose();
    _instagramCtrl.dispose();
    super.dispose();
  }

  /// Seeds phone/Instagram from the owner's PRIMARY salon, once — called
  /// from [initState] (see its own doc for the two arrival paths). Falls
  /// back to the first owned salon if none is flagged primary. A no-op
  /// (never sets [_prefilledFromPrimary]) when the owner has no salons yet —
  /// should not happen in practice (this screen is reached FROM the hub,
  /// which always has ≥1 entry), but degrades gracefully.
  void _prefillContactsOnce(List<Salon> salons) {
    if (_contactsPrefilled) return;
    _contactsPrefilled = true;
    if (salons.isEmpty) return;
    final Salon primary = salons.firstWhere(
      (Salon s) => s.isPrimary ?? false,
      orElse: () => salons.first,
    );
    _phoneCtrl.text = primary.phone ?? '';
    _instagramCtrl.text = primary.instagramUrl ?? '';
    _prefilledFromPrimary =
        _phoneCtrl.text.isNotEmpty || _instagramCtrl.text.isNotEmpty;
  }

  void _onOblast(Oblast? o) => setState(() {
    _selectedOblast = o;
    _selectedCity = null;
    _selectedDistrict = null;
    _localityError = null;
  });

  void _onCity(City? c) => setState(() {
    _selectedCity = c;
    _selectedDistrict = null;
    _localityError = null;
  });

  void _onDistrict(CityDistrict? d) => setState(() {
    _selectedDistrict = d;
    _localityError = null;
  });

  Future<void> _submit() async {
    if (_submitting) return;
    final l10n = AppLocalizations.of(context);

    final String? nameErr = validateSalonName(_nameCtrl.text, l10n);
    final LocalityValidationError? localityErr = validateProviderLocality(
      oblastCode: _selectedOblast?.id,
      cityId: _selectedCity?.id,
      districtId: _selectedDistrict?.id,
      cityHasDistricts: _selectedCity?.hasDistricts ?? false,
      l10n: l10n,
    );
    final String? streetErr = validateStreet(_streetCtrl.text, l10n);
    final String? buildingErr = validateBuilding(_buildingCtrl.text, l10n);
    final String? phoneErr = validateSalonPhone(_phoneCtrl.text, l10n);
    final String? instagramErr = validateSalonInstagram(
      _instagramCtrl.text,
      l10n,
    );

    if (nameErr != null ||
        localityErr != null ||
        streetErr != null ||
        buildingErr != null ||
        phoneErr != null ||
        instagramErr != null) {
      setState(() {
        _errName = nameErr;
        _localityError = localityErr;
        _errStreet = streetErr;
        _errBuildingNo = buildingErr;
        _errPhone = phoneErr;
        _errInstagram = instagramErr;
      });
      showErrorSnack(context, l10n.editValidationSummary);
      return;
    }

    final City? city = _selectedCity;
    if (city == null) return; // guarded by validateProviderLocality above

    setState(() => _submitting = true);
    final Failure? failure = await ref
        .read(registerSalonProvider.notifier)
        .submit(
          name: _nameCtrl.text,
          cityId: city.id,
          districtId: _selectedDistrict?.id,
          street: _streetCtrl.text,
          buildingNo: _buildingCtrl.text,
          locationNote: _noteCtrl.text,
          phone: _phoneCtrl.text,
          instagramUrl: _instagramCtrl.text,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (failure != null) {
      showErrorSnack(context, failure.userMessage(context));
      return;
    }
    showSuccessSnack(context, l10n.registerSalonSuccess);
    // `mySalonsProvider` was already invalidated by `submit()` above — the
    // hub refetches on its own the moment it is watched again, no manual
    // refresh needed.
    context.pop();
  }

  /// Guards the top-bar back icon against the SAME reachable defect the
  /// enclosing `PopScope` guards for the system back gesture/hardware
  /// button — see this file's `build()` doc for the full CRITICAL-fix
  /// residual this closes (audit-fix cycle 3, mobile-qa MEDIUM). `PopScope
  /// .canPop` only governs SYSTEM-initiated pops; it does NOT block an
  /// explicit imperative `context.pop()` call like this one, so this
  /// method needs its OWN `_submitting` guard even with the PopScope in
  /// place.
  void _onBack() {
    if (_submitting) {
      showInfoSnack(
        context,
        AppLocalizations.of(context).registerSalonSubmitInProgressHint,
      );
      return;
    }
    if (context.canPop()) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Deliberately NOT `ref.watch(mySalonsProvider)` — see [initState]'s own
    // doc (mobile-perf LOW fix). Contact prefill is driven entirely by the
    // one-time `ref.read` + `ref.listenManual` pair registered there.
    //
    // `ref.watch(registerSalonProvider)` — mobile-security/mobile-perf
    // CRITICAL fix. `registerSalonProvider` is a plain (autoDispose)
    // `@riverpod` provider and `_submit` only ever `ref.read`s its
    // `.notifier` — nothing else held its element alive. Against a REAL
    // (non-synchronous) `POST /salons` round trip, Riverpod disposed the
    // element WHILE `submit()` was still suspended on the `await`, so its
    // post-await `ref.invalidate(mySalonsProvider)` fired on a dead `ref`
    // and threw `UnmountedRefException` on every real-backend submit — a
    // deterministic production crash a synchronous fake repository could
    // never reproduce. This watch registers the screen as a live listener
    // for this screen's WHOLE lifetime, so the element is never disposed
    // mid-flight regardless of how long the network call takes.
    //
    // NOT a regression of the mobile-perf LOW fix above: `registerSalonProvider`
    // is a DIFFERENT provider from `mySalonsProvider`, its `build()` returns
    // `void` and `submit()` never reassigns `state` — so this watch NEVER
    // fires a rebuild after the first one. The whole point of the LOW fix
    // (decoupling this form from `mySalonsProvider`'s OWN churn) is untouched.
    //
    // `mySalonsProvider` invalidation deliberately STAYS inside `submit()`
    // (not moved here to the screen) — that keeps it co-located with the
    // mutation it belongs to, mirrors `SalonManagementProfile.save/
    // saveAddress/deleteSalon`'s identical shape, and keeps
    // `test/core/provider_cycle_guard_test.dart`'s bare
    // `registerSalonProvider.notifier.submit()` entrypoint (no screen
    // involved at all) meaningful — moving the invalidate to the screen's
    // own `ref` would silently stop that entrypoint from proving anything.
    ref.watch(registerSalonProvider);
    final LocalityValidationError? err = _localityError;

    // mobile-qa MEDIUM fix (audit-fix cycle 3) — the `ref.watch(
    // registerSalonProvider)` CRITICAL fix above only keeps the provider
    // alive while THIS screen stays mounted. Nothing previously stopped the
    // user backing out (top-bar icon OR the system back gesture/hardware
    // button -- neither was guarded) while `POST /salons` was still in
    // flight: that unmounts the screen, drops the watch, and reproduces the
    // SAME `UnmountedRefException` in `submit()`'s post-await
    // `ref.invalidate(mySalonsProvider)` -- narrower than the original
    // always-fires crash, but genuinely reachable by ordinary back-tap or
    // back-gesture behaviour on a slow connection, not merely theoretical.
    //
    // `canPop: !_submitting` blocks the SYSTEM back gesture/hardware button
    // while a submit is in flight, keeping the screen mounted so
    // `ref.invalidate(mySalonsProvider)` still runs and the hub-refresh
    // acceptance criterion survives. `PopScope.canPop` does NOT cover an
    // explicit imperative `context.pop()` call, so the top-bar icon needs
    // its OWN guard too -- see [_onBack]'s own doc. `onPopInvokedWithResult`
    // surfaces a neutral `showInfoSnack` (the SAME snack mechanism already
    // used elsewhere on this screen -- no new visual idiom) so a blocked
    // back press is not silently swallowed with no explanation.
    return PopScope(
      canPop: !_submitting,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          showInfoSnack(context, l10n.registerSalonSubmitInProgressHint);
        }
      },
      child: SectionScaffold(
        title: l10n.registerSalonTitle,
        backSemanticLabel: l10n.salonProfileBackLabel,
        onBack: _onBack,
        footer: NeumorphicButton(
          key: const Key('create_salon'),
          label: l10n.registerSalonCta,
          icon: Icons.add_business_rounded,
          loading: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.lg),
              child: Text(
                l10n.registerSalonSubheading,
                style: VelvetText.body(),
              ),
            ),
            VelvetField(
              fieldKey: const Key('salon_name'),
              label: l10n.salonManageNameLabel,
              controller: _nameCtrl,
              enabled: !_submitting,
              hint: l10n.registerSalonNameHint,
              maxLength: _kNameMaxLength,
              errorText: _errName,
              onChanged: (String v) {
                final next = validateSalonName(v, l10n);
                if (next != _errName) setState(() => _errName = next);
              },
            ),
            const SizedBox(height: VelvetSpacing.lg),
            LocalityCascade(
              key: const Key('register-salon-locality-cascade'),
              selectedOblast: _selectedOblast,
              selectedCity: _selectedCity,
              selectedDistrict: _selectedDistrict,
              districtRequired: true,
              onOblast: _onOblast,
              onCity: _onCity,
              onDistrict: _onDistrict,
              oblastError: err?.level == LocalityLevel.oblast
                  ? err!.message
                  : null,
              cityError: err?.level == LocalityLevel.city ? err!.message : null,
              districtError: err?.level == LocalityLevel.district
                  ? err!.message
                  : null,
            ),
            const SizedBox(height: VelvetSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 2,
                  child: VelvetField(
                    fieldKey: const Key('salon_street'),
                    label: l10n.streetLabel,
                    controller: _streetCtrl,
                    enabled: !_submitting,
                    hint: l10n.step3FieldStreetPlaceholder,
                    maxLength: kStreetMaxLength,
                    errorText: _errStreet,
                    onChanged: (String v) {
                      final next = validateStreet(v, l10n);
                      if (next != _errStreet) setState(() => _errStreet = next);
                    },
                  ),
                ),
                const SizedBox(width: VelvetSpacing.md),
                Expanded(
                  child: VelvetField(
                    fieldKey: const Key('salon_building'),
                    label: l10n.buildingNoLabel,
                    controller: _buildingCtrl,
                    enabled: !_submitting,
                    hint: l10n.step3FieldBuildingPlaceholder,
                    maxLength: kBuildingMaxLength,
                    errorText: _errBuildingNo,
                    onChanged: (String v) {
                      final next = validateBuilding(v, l10n);
                      if (next != _errBuildingNo) {
                        setState(() => _errBuildingNo = next);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: VelvetSpacing.lg),
            VelvetField(
              fieldKey: const Key('salon_location_note'),
              label: l10n.locationNoteLabel,
              controller: _noteCtrl,
              enabled: !_submitting,
              optional: true,
              hint: l10n.step3FieldNotePlaceholder,
              maxLines: 3,
              maxLength: kLocationNoteMaxLength,
              showCounter: true,
            ),
            const SizedBox(height: VelvetSpacing.lg),
            if (_prefilledFromPrimary) ...<Widget>[
              Padding(
                padding: const EdgeInsets.only(
                  left: 4,
                  bottom: VelvetSpacing.sm,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.info_outline_rounded,
                        size: 14,
                        color: BrandColors.muted,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        l10n.registerSalonPrefilledHint,
                        // No `fontSize` override (forbid_inline_fontsize.sh):
                        // every `_feedbackBase`-derived token in velvet_text
                        // .dart — bookFeedbackMuted125, feedbackMuted13, etc.
                        // — has already been normalised to the SAME base 11sp
                        // regardless of its (stale) doc-comment name, so there
                        // is no real token that renders at the preview's 12.5
                        // sp; this now renders at the app-wide 11sp for this
                        // style family instead. `height` alone is untouched by
                        // the guard.
                        style: VelvetText.feedback(
                          BrandColors.muted,
                        ).copyWith(height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            VelvetField(
              fieldKey: const Key('salon_phone'),
              label: l10n.phoneLabel,
              controller: _phoneCtrl,
              enabled: !_submitting,
              keyboardType: TextInputType.phone,
              inputFormatters: const <UaPhoneInputFormatter>[
                UaPhoneInputFormatter(),
              ],
              hint: '+380 __ ___ __ __',
              errorText: _errPhone,
              onChanged: (String v) {
                final next = validateSalonPhone(v, l10n);
                if (next != _errPhone) setState(() => _errPhone = next);
              },
            ),
            const SizedBox(height: VelvetSpacing.lg),
            VelvetField(
              fieldKey: const Key('salon_instagram'),
              label: l10n.instagramLabel,
              controller: _instagramCtrl,
              enabled: !_submitting,
              optional: true,
              prefixText: '@',
              hint: l10n.masterEditInstagramHint,
              maxLength: kSalonInstagramMaxLength,
              errorText: _errInstagram,
              onChanged: (String v) {
                final next = validateSalonInstagram(v, l10n);
                if (next != _errInstagram) setState(() => _errInstagram = next);
              },
            ),
          ],
        ),
      ),
    );
  }
}
