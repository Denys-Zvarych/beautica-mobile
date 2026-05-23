// Phase 2.19 — Registration wizard Step 3 (Address / Locality).
//
// SOURCE OF TRUTH: docs/signup-designs/sign-up-step-3-address.html.
// Every element is transcribed literally — three role variants are folded into
// one screen, branched on the draft's role:
//
//   CLIENT             → 3 locality rows (each label carries a muted
//                        "— необов'язково" tag; Область has a "?" tip-icon),
//                        NO street/building/note, split CTA [Пропустити | Зберегти].
//   INDEPENDENT_MASTER → 3 locality rows (Область has a "?" tip-icon), divider,
//                        Вулиця + Будинок (two-column) + Примітка textarea,
//                        single CTA "Зберегти і продовжити".
//   SALON_OWNER        → identical to MASTER (headline reframes to "Адреса
//                        салону" in the shell).
//
// This screen renders ONLY the card body — the outer chrome (brand row, role
// chip, per-role hero headline, 4-dot progress, back link, glass card wrapper)
// is owned by [RegisterFlowShell]. The role-aware sub-text sits at the top of
// the card body (the HTML places it directly under the headline; the shell does
// not render sub-text, so the screen owns it for Step 3).
//
// Submit flow (phase doc Step 3):
//   1. Validate per role.
//   2. Write the Step 3 slice (locality + address) into registerDraftProvider.
//   3. register(draft) → POST /auth/register/<role>.
//   4. Navigate to /verification (carrying the email via `extra`).
//
// The role-aware profile/salon save deliberately does NOT run on this screen.
// register() returns VerificationRequired with NO access token, so the
// auth-required PATCH /independent-masters/me and POST /salons calls would 401
// and the address would be silently lost (Defect 8). The locality + address
// slice is stashed in the keepAlive draft and persisted by VerificationScreen
// AFTER OTP verification issues a session:
//   CLIENT             → locality rides along in the register body; nothing
//                        extra to save (and "Пропустити" nulls it out).
//   INDEPENDENT_MASTER → masterRepository.updateLocality(...) post-verification.
//   SALON_OWNER        → salonRepository.create(SalonCreateDto(...)) post-verif.
//
// Design tokens (ARCHITECTURE-mobile.md § 9 — locked): input radius 12, input
// fill white 7%, CTA height 52, CTA radius 14, CTA gradient #4A2E10→#6A4A28→
// #8A6840.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/validators/building_validator.dart';
import '../../../shared/validators/locality_validator.dart';
import '../../../shared/validators/location_note_validator.dart';
import '../../../shared/validators/street_validator.dart';
import '../../../shared/widgets/auth_field_label.dart';
import '../../location/domain/city.dart';
import '../../location/domain/city_district.dart';
import '../../location/domain/oblast.dart';
import '../../location/presentation/widgets/locality_cascade.dart';
import '../domain/register_result.dart';
import '../domain/user_role.dart';
import '../state/register_draft_notifier.dart';
import 'auth_notifier.dart';
import 'widgets/sub_step_indicator.dart';
import 'widgets/two_column_row.dart';

// ---------------------------------------------------------------------------
// Pre-allocated static constants — never constructed inside build() (perf P2).
// ---------------------------------------------------------------------------

/// HTML: input { border-radius: 12px }.
const _kInputRadius = BorderRadius.all(Radius.circular(12));

/// HTML: .cta-btn / .cta-ghost { border-radius: 14px }.
const _kCtaRadius = BorderRadius.all(Radius.circular(14));

const _kInputBorderDefault = OutlineInputBorder(
  borderRadius: _kInputRadius,
  borderSide: BorderSide(color: Color(0x1AFFFFFF), width: 1),
);

const _kInputBorderFocused = OutlineInputBorder(
  borderRadius: _kInputRadius,
  borderSide: BorderSide(color: Color(0x5CB89A7A), width: 1.5),
);

const _kInputBorderError = OutlineInputBorder(
  borderRadius: _kInputRadius,
  borderSide: BorderSide(color: BrandColors.error, width: 1),
);

const _kInputBorderFocusedError = OutlineInputBorder(
  borderRadius: _kInputRadius,
  borderSide: BorderSide(color: BrandColors.error, width: 1.5),
);

/// HTML: input { background: rgba(255,255,255,0.07) }.
const _kInputFill = Color(0x12FFFFFF);

/// HTML: .input-icon { color: rgba(255,255,255,0.25) }.
const _kFieldIconColor = Color(0x40FFFFFF);

const _kFieldTextStyle = TextStyle(color: BrandColors.white, fontSize: 14);

const _kFieldHintStyle = TextStyle(
  color: Color(0x2EFFFFFF), // rgba(255,255,255,0.18)
  fontSize: 14,
);

const _kErrorStyle = TextStyle(
  color: BrandColors.error,
  fontSize: 11,
  height: 1.4,
);

/// HTML: .sub-text { color: rgba(255,255,255,0.32); font-size: 12px }.
const _kSubTextStyle = TextStyle(
  color: Color(0x52FFFFFF),
  fontSize: 12,
  height: 1.5,
);

/// HTML: .field-divider { background: rgba(255,255,255,0.08) }.
const _kDividerColor = Color(0x14FFFFFF);

/// CTA gradient: linear-gradient(135deg, #4a2e10 0%, #6a4a28 60%, #8a6840 100%).
const _kCtaGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF4A2E10), Color(0xFF6A4A28), Color(0xFF8A6840)],
  stops: [0.0, 0.6, 1.0],
);

const _kCtaDecoration = BoxDecoration(
  gradient: _kCtaGradient,
  borderRadius: _kCtaRadius,
  boxShadow: [
    // HTML: box-shadow: 0 4px 24px var(--cta-shadow) rgba(58,36,12,0.68).
    BoxShadow(color: Color(0xAD3A240C), blurRadius: 24, offset: Offset(0, 4)),
  ],
);

const _kCtaTextStyle = TextStyle(
  color: Colors.white,
  fontSize: 15,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.3,
);

/// HTML: .cta-ghost { background: rgba(184,154,122,0.06); border: 1px solid
/// rgba(184,154,122,0.42); color: var(--accent) }.
const _kGhostDecoration = BoxDecoration(
  color: Color(0x0FB89A7A), // rgba(184,154,122,0.06)
  borderRadius: _kCtaRadius,
  border: Border.fromBorderSide(
    BorderSide(color: Color(0x6BB89A7A), width: 1), // 0.42 alpha
  ),
);

const _kGhostTextStyle = TextStyle(
  color: BrandColors.accent,
  fontSize: 14,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.3,
);

/// HTML label .label-optional { color: rgba(184,154,122,0.55); font-size: 9px }.
const _kOptionalTagStyle = TextStyle(
  color: Color(0x8CB89A7A), // rgba(184,154,122,0.55)
  fontSize: 11,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.3,
);

/// HTML .tip-icon { border: 1px solid rgba(184,154,122,0.4); color: accent }.
const _kTipBorder = Color(0x66B89A7A); // rgba(184,154,122,0.4)
const _kTipTextStyle = TextStyle(
  color: BrandColors.accent,
  fontSize: 10,
  fontWeight: FontWeight.w700,
  height: 1,
);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Step 3 of the multi-step registration wizard — Address / Locality.
///
/// Renders the card body only; [RegisterFlowShell] owns the outer chrome.
class RegisterStep3Screen extends ConsumerStatefulWidget {
  const RegisterStep3Screen({super.key});

  @override
  ConsumerState<RegisterStep3Screen> createState() =>
      _RegisterStep3ScreenState();
}

class _RegisterStep3ScreenState extends ConsumerState<RegisterStep3Screen> {
  final _formKey = GlobalKey<FormState>();

  final _streetController = TextEditingController();
  final _buildingController = TextEditingController();
  final _noteController = TextEditingController();

  final _streetFocusNode = FocusNode();
  final _buildingFocusNode = FocusNode();
  final _noteFocusNode = FocusNode();

  // Local selection mirror — holds the full domain objects (not just ids) so
  // the cascade can render names and so we can read City.hasDistricts for
  // per-role validation. Mirrored into the draft on submit.
  Oblast? _oblast;
  City? _city;
  CityDistrict? _district;

  /// True while register + profile-save is in flight. Disables both CTAs and
  /// shows a spinner (UX: loading-buttons, submit-feedback).
  bool _submitting = false;

  /// Set when the provider tapped submit with an unsatisfied locality — drives
  /// the inline locality error message under the FAILING row (the cascade has
  /// no FormField hook). Carries the level so the message attaches to the
  /// matching row (Defect 7), not once below the whole cascade.
  LocalityValidationError? _localityError;

  @override
  void dispose() {
    _streetController.dispose();
    _buildingController.dispose();
    _noteController.dispose();
    _streetFocusNode.dispose();
    _buildingFocusNode.dispose();
    _noteFocusNode.dispose();
    super.dispose();
  }

  // ── Cascade callbacks ──────────────────────────────────────────────────────

  void _onOblast(Oblast? o) => setState(() {
    _oblast = o;
    // Changing oblast invalidates downstream selections.
    _city = null;
    _district = null;
    _localityError = null;
  });

  void _onCity(City? c) => setState(() {
    _city = c;
    _district = null;
    _localityError = null;
  });

  void _onDistrict(CityDistrict? d) => setState(() {
    _district = d;
    _localityError = null;
  });

  // ── Submit ──────────────────────────────────────────────────────────────

  /// Whether the currently selected city subdivides into districts. False when
  /// no city is chosen or the city is a leaf.
  bool get _cityHasDistricts => _city?.hasDistricts ?? false;

  /// CLIENT "Зберегти" / provider "Зберегти і продовжити".
  Future<void> _submit(AppLocalizations l10n, UserRole role) async {
    if (_submitting) return;

    final isProvider = role != UserRole.client;

    // Provider locality + address validation.
    if (isProvider) {
      final localityErr = validateProviderLocality(
        oblastCode: _oblast?.id,
        cityId: _city?.id,
        districtId: _district?.id,
        cityHasDistricts: _cityHasDistricts,
        l10n: l10n,
      );
      final fieldsValid = _formKey.currentState?.validate() ?? false;
      if (localityErr != null || !fieldsValid) {
        setState(() => _localityError = localityErr);
        // Focus the first invalid text field (UX: focus-management) once
        // locality is satisfied.
        if (localityErr == null) {
          // (locality satisfied — fall through to address-field focusing below)
          if (validateStreet(_streetController.text, l10n) != null) {
            _streetFocusNode.requestFocus();
          } else if (validateBuilding(_buildingController.text, l10n) != null) {
            _buildingFocusNode.requestFocus();
          }
        }
        return;
      }
    }
    // CLIENT "Зберегти" is always valid — a partial / empty selection is
    // tolerated and simply persists whatever (if anything) was chosen.

    await _runRegisterAndSave(
      l10n: l10n,
      role: role,
      // CLIENT "Зберегти" persists the chosen locality (if any) via the register
      // body; providers persist via the dedicated profile/salon save.
      skipLocality: false,
    );
  }

  /// CLIENT "Пропустити" — null out locality, register, navigate, no save.
  Future<void> _skip(AppLocalizations l10n, UserRole role) async {
    if (_submitting) return;
    assert(
      role == UserRole.client,
      'Пропустити CTA must never be shown to MASTER/OWNER',
    );
    await _runRegisterAndSave(l10n: l10n, role: role, skipLocality: true);
  }

  /// Shared register + navigate pipeline.
  ///
  /// [skipLocality] true for CLIENT "Пропустити": locality is nulled out.
  ///
  /// Defect 8 — the role-aware profile/salon save (PATCH /independent-masters/me
  /// and POST /salons) is AUTH-REQUIRED, but `register()` returns
  /// [VerificationRequired] with NO access token, so calling those endpoints
  /// here always 401'd and the address was silently lost. The Step 3 locality +
  /// address are stashed in the keepAlive draft; the actual provider save now
  /// runs in [VerificationScreen] AFTER OTP verification issues a session.
  ///
  /// Defect 2 — the body is wrapped in try/finally so `_submitting` is ALWAYS
  /// reset even on a throw/early-return, otherwise both CTAs (incl. the CLIENT
  /// "Пропустити" ghost button) could stick permanently disabled.
  Future<void> _runRegisterAndSave({
    required AppLocalizations l10n,
    required UserRole role,
    required bool skipLocality,
  }) async {
    final draftNotifier = ref.read(registerDraftProvider.notifier);

    // Write the Step 3 slice. For skip, force every locality field to null.
    if (skipLocality) {
      draftNotifier.updateStep3();
    } else {
      draftNotifier.updateStep3(
        oblastCode: _oblast?.id,
        cityId: _city?.id,
        districtId: _district?.id,
        street: _streetController.text.trim(),
        buildingNo: _buildingController.text.trim(),
        locationNote: _noteController.text.trim(),
      );
    }

    final draft = ref.read(registerDraftProvider);
    if (draft == null) return; // defensive — guard should prevent this

    setState(() => _submitting = true);

    try {
      if (kDebugMode) {
        log(
          'Step 3 submit: role=${role.toWire} skipLocality=$skipLocality '
          'isProvider=${role != UserRole.client}',
          name: 'auth.register.step3',
          level: 800,
        );
      }

      // 1. Register the account.
      final result = await ref
          .read(authProvider.notifier)
          .register(
            email: draft.email,
            password: draft.password,
            firstName: draft.firstName,
            lastName: draft.lastName,
            role: role,
            businessName: role == UserRole.salonOwner ? draft.salonName : null,
            phone: draft.phone,
          );

      if (!mounted) return;

      // register() returns null only when an AsyncError was captured — surface
      // it and stop (the account was NOT created).
      if (result == null) {
        final error = ref.read(authProvider).error;
        _showSnackBar(
          error is Failure ? error.userMessage(context) : l10n.errUnknown,
        );
        return;
      }

      // Security (MEDIUM-1) — the account now exists, so the plaintext password
      // is no longer needed by the wizard (the OTP step keys off the email).
      // Wipe it from the keepAlive draft immediately, BEFORE navigation, so the
      // credential's in-memory lifetime is minimal. The full reset still runs
      // at /done; this is the earlier, narrower clear. The locality/address
      // slice stays in the draft so the post-verification save can read it.
      draftNotifier.clearCredentials();

      // 2. Navigate to verification, carrying the email for the OTP screen.
      //    The provider profile/salon save deliberately does NOT run here — see
      //    the method doc (Defect 8); it runs post-verification once a session
      //    token exists.
      final email = result is VerificationRequired ? result.email : draft.email;
      if (!mounted) return;
      context.go(RouteNames.verification, extra: email);
    } finally {
      // Defect 2 — always re-enable the CTAs, even on a throw or early return.
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          key: const Key('step3-snackbar'),
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final role =
        ref.watch(registerDraftProvider.select((d) => d?.role)) ??
        UserRole.client;

    final isClient = role == UserRole.client;
    final isProvider = !isClient;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Role-aware sub-text (HTML places it under the headline) ──────
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              _subTextFor(role, l10n),
              key: const Key('step3-subtext'),
              style: _kSubTextStyle,
            ),
          ),

          // ── Sub-step indicator (two pill dots, second active) ────────────
          const SubStepIndicator(key: Key('substep-indicator'), activeIndex: 1),
          const SizedBox(height: AppSpacing.md),

          // ── Locality cascade with per-role labels ────────────────────────
          _LocalityBlock(
            isClient: isClient,
            oblast: _oblast,
            city: _city,
            district: _district,
            localityError: _localityError,
            onOblast: _onOblast,
            onCity: _onCity,
            onDistrict: _onDistrict,
            l10n: l10n,
          ),

          // ── Provider-only address fields ─────────────────────────────────
          if (isProvider) ...[
            const SizedBox(height: AppSpacing.md),
            // HTML: .field-divider — divider then fields directly (NO header).
            const Divider(
              key: Key('step3-address-divider'),
              height: 1,
              thickness: 1,
              color: _kDividerColor,
            ),
            const SizedBox(height: AppSpacing.md),
            TwoColumnRow(
              gap: AppSpacing.xs,
              // HTML: .row-2 { grid-template-columns: 2fr 1fr } — street wider.
              flexLeft: 2,
              flexRight: 1,
              left: _StreetField(
                controller: _streetController,
                focusNode: _streetFocusNode,
                nextFocusNode: _buildingFocusNode,
                l10n: l10n,
              ),
              right: _BuildingField(
                controller: _buildingController,
                focusNode: _buildingFocusNode,
                nextFocusNode: _noteFocusNode,
                l10n: l10n,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _NoteField(
              controller: _noteController,
              focusNode: _noteFocusNode,
              l10n: l10n,
            ),
          ],

          const SizedBox(height: AppSpacing.md),

          // ── CTA(s) ────────────────────────────────────────────────────────
          if (isClient)
            _ClientCtaRow(
              submitting: _submitting,
              onSkip: () => _skip(l10n, role),
              onSave: () => _submit(l10n, role),
              l10n: l10n,
            )
          else
            _ProviderCta(
              submitting: _submitting,
              label: l10n.step3CtaSaveAndContinue,
              onTap: () => _submit(l10n, role),
            ),
        ],
      ),
    );
  }

  static String _subTextFor(UserRole role, AppLocalizations l10n) =>
      switch (role) {
        UserRole.client => l10n.step3SubtextClient,
        UserRole.salonOwner => l10n.step3SubtextOwner,
        _ => l10n.step3SubtextMaster,
      };
}

// ---------------------------------------------------------------------------
// _LocalityBlock — cascade + per-role labels + inline error
// ---------------------------------------------------------------------------

class _LocalityBlock extends StatelessWidget {
  const _LocalityBlock({
    required this.isClient,
    required this.oblast,
    required this.city,
    required this.district,
    required this.localityError,
    required this.onOblast,
    required this.onCity,
    required this.onDistrict,
    required this.l10n,
  });

  final bool isClient;
  final Oblast? oblast;
  final City? city;
  final CityDistrict? district;
  final LocalityValidationError? localityError;
  final ValueChanged<Oblast?> onOblast;
  final ValueChanged<City?> onCity;
  final ValueChanged<CityDistrict?> onDistrict;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    // Defect 7 — route the single first-unsatisfied message to the FAILING
    // row only, so e.g. "Оберіть місто" renders under the City row instead of
    // once below the whole cascade (which placed it under the District row).
    final err = localityError;
    return LocalityCascade(
      key: const Key('locality-cascade'),
      selectedOblast: oblast,
      selectedCity: city,
      selectedDistrict: district,
      onOblast: onOblast,
      onCity: onCity,
      onDistrict: onDistrict,
      districtRequired: !isClient,
      oblastError: err?.level == LocalityLevel.oblast ? err!.message : null,
      cityError: err?.level == LocalityLevel.city ? err!.message : null,
      districtError: err?.level == LocalityLevel.district ? err!.message : null,
      // Defect 5 — re-enable the "Не обов'язково для міст без районів" caption
      // on the District row for leaf cities so users understand WHY the field
      // is disabled (backend has districts only for ~17 large cities).
      showDistrictNoneHelper: true,
      // HTML: the Область label carries (CLIENT only) a muted optional tag,
      // and (all roles) a "?" tip-icon. Appended inline to the row label.
      oblastLabelSuffix: _OblastLabelSuffix(isClient: isClient, l10n: l10n),
    );
  }
}

// ---------------------------------------------------------------------------
// _OblastLabelSuffix — CLIENT optional tag + "?" tip-icon, appended inline
// ---------------------------------------------------------------------------

class _OblastLabelSuffix extends StatelessWidget {
  const _OblastLabelSuffix({required this.isClient, required this.l10n});

  final bool isClient;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isClient) ...[
          const SizedBox(width: 5),
          Text(l10n.localityLabelOptional, style: _kOptionalTagStyle),
        ],
        const SizedBox(width: 5),
        _TipIcon(
          tooltip: isClient
              ? l10n.localityOblastTipClient
              : l10n.localityOblastTipProvider,
          semanticLabel: l10n.localityOblastTipSemanticLabel,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _TipIcon — circular "?" affordance, tap shows a tooltip (icon-only a11y)
// ---------------------------------------------------------------------------

class _TipIcon extends StatelessWidget {
  const _TipIcon({required this.tooltip, required this.semanticLabel});

  final String tooltip;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    // Tooltip with triggerMode.tap makes the hint reachable on touch devices
    // (HTML `title` is hover-only; mobile needs tap). Wrapped in a 44x44 hit
    // target via Semantics + a sized tap region (touch-target rule).
    return Tooltip(
      message: tooltip,
      triggerMode: TooltipTriggerMode.tap,
      preferBelow: true,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  BorderSide(color: _kTipBorder, width: 1),
                ),
              ),
              child: const Text(
                // ignore: no_raw_ui_strings
                // Single-glyph affordance marker (a literal question mark) —
                // exempt from l10n per mobile-backlog §5 (same class as the
                // brand monogram). The meaning is carried by [semanticLabel]
                // and the localised [tooltip].
                '?',
                style: _kTipTextStyle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _StreetField — "Вулиця"
// ---------------------------------------------------------------------------

class _StreetField extends StatelessWidget {
  const _StreetField({
    required this.controller,
    required this.focusNode,
    required this.nextFocusNode,
    required this.l10n,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode nextFocusNode;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthFieldLabel(l10n.step3FieldStreetLabel),
        TextFormField(
          key: const Key('field-street'),
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.next,
          keyboardType: TextInputType.streetAddress,
          textCapitalization: TextCapitalization.words,
          style: _kFieldTextStyle,
          inputFormatters: [LengthLimitingTextInputFormatter(kStreetMaxLength)],
          decoration: InputDecoration(
            hintText: l10n.step3FieldStreetPlaceholder,
            hintStyle: _kFieldHintStyle,
            filled: true,
            fillColor: _kInputFill,
            prefixIcon: const Icon(
              Icons.signpost_outlined,
              size: 15,
              color: _kFieldIconColor,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 38,
              minHeight: 46,
            ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 14,
              horizontal: AppSpacing.sm,
            ),
            border: _kInputBorderDefault,
            enabledBorder: _kInputBorderDefault,
            focusedBorder: _kInputBorderFocused,
            errorBorder: _kInputBorderError,
            focusedErrorBorder: _kInputBorderFocusedError,
            errorStyle: _kErrorStyle,
          ),
          onFieldSubmitted: (_) => nextFocusNode.requestFocus(),
          validator: (v) => validateStreet(v, l10n),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _BuildingField — "Будинок"
// ---------------------------------------------------------------------------

class _BuildingField extends StatelessWidget {
  const _BuildingField({
    required this.controller,
    required this.focusNode,
    required this.nextFocusNode,
    required this.l10n,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode nextFocusNode;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthFieldLabel(l10n.step3FieldBuildingLabel),
        TextFormField(
          key: const Key('field-building'),
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.next,
          keyboardType: TextInputType.text,
          style: _kFieldTextStyle,
          inputFormatters: [
            LengthLimitingTextInputFormatter(kBuildingMaxLength),
          ],
          decoration: InputDecoration(
            hintText: l10n.step3FieldBuildingPlaceholder,
            hintStyle: _kFieldHintStyle,
            filled: true,
            fillColor: _kInputFill,
            prefixIcon: const Icon(
              Icons.home_outlined,
              size: 15,
              color: _kFieldIconColor,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 38,
              minHeight: 46,
            ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 14,
              horizontal: AppSpacing.sm,
            ),
            border: _kInputBorderDefault,
            enabledBorder: _kInputBorderDefault,
            focusedBorder: _kInputBorderFocused,
            errorBorder: _kInputBorderError,
            focusedErrorBorder: _kInputBorderFocusedError,
            errorStyle: _kErrorStyle,
          ),
          onFieldSubmitted: (_) => nextFocusNode.requestFocus(),
          validator: (v) => validateBuilding(v, l10n),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _NoteField — "Примітка" (3-row textarea, optional, capped at 250)
// ---------------------------------------------------------------------------

class _NoteField extends StatelessWidget {
  const _NoteField({
    required this.controller,
    required this.focusNode,
    required this.l10n,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthFieldLabel(l10n.step3FieldNoteLabel),
        TextFormField(
          key: const Key('field-note'),
          controller: controller,
          focusNode: focusNode,
          // HTML: textarea — 3 visible rows.
          minLines: 3,
          maxLines: 3,
          textInputAction: TextInputAction.newline,
          keyboardType: TextInputType.multiline,
          style: _kFieldTextStyle,
          inputFormatters: [
            LengthLimitingTextInputFormatter(kLocationNoteMaxLength),
          ],
          decoration: InputDecoration(
            hintText: l10n.step3FieldNotePlaceholder,
            hintStyle: _kFieldHintStyle,
            filled: true,
            fillColor: _kInputFill,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 11,
              horizontal: AppSpacing.sm,
            ),
            border: _kInputBorderDefault,
            enabledBorder: _kInputBorderDefault,
            focusedBorder: _kInputBorderFocused,
            errorBorder: _kInputBorderError,
            focusedErrorBorder: _kInputBorderFocusedError,
            errorStyle: _kErrorStyle,
          ),
          validator: (v) => validateLocationNote(v, l10n),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _ClientCtaRow — split [ghost Пропустити | filled Зберегти]
// ---------------------------------------------------------------------------

class _ClientCtaRow extends StatelessWidget {
  const _ClientCtaRow({
    required this.submitting,
    required this.onSkip,
    required this.onSave,
    required this.l10n,
  });

  final bool submitting;
  final VoidCallback onSkip;
  final VoidCallback onSave;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    // Balanced split: equal width so the Ukrainian "Пропустити" (wider than
    // "Зберегти") fits on a single line and the two CTAs read as a balanced
    // pair. The previous 1:6 ratio starved the ghost button, wrapping its
    // label to two lines.
    return Row(
      children: [
        Expanded(
          child: _GhostButton(
            label: l10n.step3CtaSkip,
            onTap: submitting ? null : onSkip,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: _ProviderCta(
            submitting: submitting,
            label: l10n.step3CtaSave,
            onTap: onSave,
            buttonKey: const Key('btn-save-step3'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _GhostButton — camel-bordered ghost CTA (CLIENT "Пропустити")
// ---------------------------------------------------------------------------

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _kGhostDecoration,
      child: ClipRRect(
        borderRadius: _kCtaRadius,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const Key('btn-skip-step3'),
            onTap: onTap,
            child: SizedBox(
              height: 52,
              child: Center(
                child: Text(
                  label,
                  // Keep "Пропустити" on a single line (no wrap) — balanced
                  // against the Save CTA's single-line label.
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: _kGhostTextStyle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ProviderCta — gradient CTA with loading spinner (provider single + CLIENT save)
// ---------------------------------------------------------------------------

class _ProviderCta extends StatelessWidget {
  const _ProviderCta({
    required this.submitting,
    required this.label,
    required this.onTap,
    this.buttonKey = const Key('btn-save-continue-step3'),
  });

  final bool submitting;
  final String label;
  final VoidCallback onTap;
  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _kCtaDecoration,
      child: ClipRRect(
        borderRadius: _kCtaRadius,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: buttonKey,
            // Disabled while submitting — prevents double submission.
            onTap: submitting ? null : onTap,
            child: SizedBox(
              height: 52,
              child: Center(
                child: submitting
                    ? const SizedBox(
                        key: Key('step3-cta-spinner'),
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _kCtaTextStyle,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          const Icon(
                            Icons.arrow_forward,
                            color: Colors.white,
                            size: 18,
                            semanticLabel: null,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
