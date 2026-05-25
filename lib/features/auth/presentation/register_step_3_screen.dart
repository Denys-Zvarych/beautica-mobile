// Phase 2.19 — Registration wizard Step 3 (Address / Locality) — VelvetTouch redesign.
//
// Design source of truth:
//   docs/signup-designs/VelvetTouchDesign/lib/screens/address_screen.dart
//
// This screen renders ONLY the card body — the outer chrome (brand row, role
// chip, per-role hero headline, 4-dot progress, back link, glass card wrapper)
// is owned by [RegisterFlowShell]. The role-aware sub-text sits at the top of
// the card body (the HTML places it directly under the headline; the shell does
// not render sub-text, so the screen owns it for Step 3).
//
// Role variants:
//   CLIENT             → 3 locality rows (optional, tip-icon on Oblast),
//                        NO street/building/note,
//                        bottomBar: NeumorphicButton ("Далі") + GestureDetector skip link.
//   INDEPENDENT_MASTER → 3 locality rows (required, tip-icon on Oblast), divider,
//                        Вулиця + Будинок (two-column) + Примітка,
//                        bottomBar: NeumorphicButton ("Далі").
//   SALON_OWNER        → identical to MASTER (headline reframes to "Адреса салону"
//                        in the shell).
//
// Submit flow (unchanged from glassmorphism version):
//   1. Validate per role (manual errorText, no Form).
//   2. Write the Step 3 slice into registerDraftProvider.
//   3. register(draft) → POST /auth/register/<role>.
//   4. Navigate to /verification carrying the email via `extra`.
//
// Profile/salon save deliberately does NOT run here (Defect 8 fix): register()
// returns VerificationRequired with no access token. Address is stashed in the
// keepAlive draft and saved by VerificationScreen after OTP issues a session.
//
// VelvetTouch constraints (no glassmorphism, no BackdropFilter):
//   - Background: BrandColors.base (#E6DDD0) via AuthScaffold.
//   - Fields:     NeumorphicTextField.
//   - CTA:        NeumorphicButton pinned to AuthScaffold.bottomBar.
//   - Skip link:  GestureDetector + VelvetText.link() (CLIENT only).
//   - Colors:     BrandColors.* only — no raw Color(0xFF…) dark literals.
//   - Spacing:    VelvetSpacing.* only — no raw dp literals.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/validators/building_validator.dart';
import '../../../shared/validators/locality_validator.dart';
import '../../../shared/validators/location_note_validator.dart';
import '../../../shared/validators/street_validator.dart';
import '../../location/domain/city.dart';
import '../../location/domain/city_district.dart';
import '../../location/domain/oblast.dart';
import '../../location/presentation/widgets/locality_cascade.dart';
import '../../location/state/location_providers.dart';
import '../domain/register_result.dart';
import '../domain/user_role.dart';
import '../state/register_draft_notifier.dart';
import 'auth_notifier.dart';
import 'register_flow_shell.dart';
import 'widgets/auth_scaffold.dart';

// ---------------------------------------------------------------------------
// Pre-allocated constants — tip icon (VelvetTouch light palette)
// ---------------------------------------------------------------------------

/// Tip-icon ring colour — camel accent at 40% opacity on light taupe.
/// `BrandColors.accent` is 0xFFB89A7A; 40% opacity → 0x66B89A7A.
const _kTipBorder = Color(0x66B89A7A);

const _kTipTextStyle = TextStyle(
  color: BrandColors.accent,
  fontSize: 10,
  fontWeight: FontWeight.w700,
  height: 1,
);

/// Optional-tag style for the oblast label (CLIENT only) — muted camel.
const _kOptionalTagStyle = TextStyle(
  color: Color(0x8CB89A7A), // rgba(184,154,122,0.55) — same as old dark version
  fontSize: 11,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.3,
);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Step 3 of the multi-step registration wizard — Address / Locality.
///
/// Provides its own [AuthScaffold] (Scaffold + scroll + back button + bottom
/// CTA bar). [RegisterFlowShell] owns the outer header, role chip, hero
/// headline, and 4-dot progress — this screen must NOT duplicate those.
class RegisterStep3Screen extends ConsumerStatefulWidget {
  const RegisterStep3Screen({super.key});

  @override
  ConsumerState<RegisterStep3Screen> createState() =>
      _RegisterStep3ScreenState();
}

class _RegisterStep3ScreenState extends ConsumerState<RegisterStep3Screen> {
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _buildingController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  final FocusNode _streetFocusNode = FocusNode();
  final FocusNode _buildingFocusNode = FocusNode();
  final FocusNode _noteFocusNode = FocusNode();

  // Local selection mirror — holds full domain objects so the cascade can
  // render names and so we can read City.hasDistricts for per-role validation.
  // Mirrored into the draft on submit.
  Oblast? _oblast;
  City? _city;
  CityDistrict? _district;

  /// True while register + navigate is in flight. Passed as null to
  /// NeumorphicButton.onPressed and to GestureDetector.onTap to disable them.
  bool _submitting = false;

  /// Set when provider submits with an unsatisfied locality — routes to the
  /// failing cascade row only (Defect 7 per-row error placement).
  LocalityValidationError? _localityError;

  /// Inline errors for the address fields (manual, not Form-based).
  String? _streetError;
  String? _buildingError;

  @override
  void initState() {
    super.initState();
    // Eagerly warm the oblast cache so the picker sheet opens instantly on the
    // first tap.  The provider is keepAlive:true — this read kicks off the HTTP
    // fetch; the result is memoized for the lifetime of the app.  We fire after
    // the first frame so the widget tree is fully mounted before we touch `ref`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(oblastListProvider);
    });
  }

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

  // ── Submit helpers ─────────────────────────────────────────────────────────

  /// Whether the currently selected city subdivides into districts.
  bool get _cityHasDistricts => _city?.hasDistricts ?? false;

  /// Both CLIENT and provider CTAs use "Далі".
  Future<void> _submit(AppLocalizations l10n, UserRole role) async {
    if (_submitting) return;

    final bool isProvider = role != UserRole.client;

    if (isProvider) {
      final LocalityValidationError? localityErr = validateProviderLocality(
        oblastCode: _oblast?.id,
        cityId: _city?.id,
        districtId: _district?.id,
        cityHasDistricts: _cityHasDistricts,
        l10n: l10n,
      );
      final String? streetErr = validateStreet(_streetController.text, l10n);
      final String? buildingErr = validateBuilding(
        _buildingController.text,
        l10n,
      );

      if (localityErr != null || streetErr != null || buildingErr != null) {
        setState(() {
          _localityError = localityErr;
          _streetError = streetErr;
          _buildingError = buildingErr;
        });
        // Focus the first invalid address field once locality is satisfied.
        if (localityErr == null) {
          if (streetErr != null) {
            _streetFocusNode.requestFocus();
          } else if (buildingErr != null) {
            _buildingFocusNode.requestFocus();
          }
        }
        return;
      }
    }
    // CLIENT "Далі" is always valid — a partial/empty selection is
    // tolerated and persists whatever was chosen.

    await _runRegisterAndSave(l10n: l10n, role: role, skipLocality: false);
  }

  /// CLIENT "Пропустити" — null out locality, register, navigate, no save.
  Future<void> _skip(AppLocalizations l10n, UserRole role) async {
    if (_submitting) return;
    assert(
      role == UserRole.client,
      'Skip CTA must never be shown to MASTER/OWNER',
    );
    await _runRegisterAndSave(l10n: l10n, role: role, skipLocality: true);
  }

  /// Shared register + navigate pipeline.
  ///
  /// [skipLocality] true for CLIENT "Пропустити": locality is nulled out.
  ///
  /// Defect 8 — profile/salon save deferred to VerificationScreen after OTP
  /// issues a session (POST /independent-masters/me and POST /salons need a
  /// valid access token; register() returns VerificationRequired with none).
  ///
  /// Defect 2 — try/finally guarantees _submitting resets even on a throw /
  /// early return so both CTAs never stick permanently disabled.
  Future<void> _runRegisterAndSave({
    required AppLocalizations l10n,
    required UserRole role,
    required bool skipLocality,
  }) async {
    final draftNotifier = ref.read(registerDraftProvider.notifier);

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
    if (draft == null) return; // guard: router guard should prevent this

    // Already-registered guard — clearCredentials() wipes draft.password to ''
    // after the first successful submit. If the user navigates back from the
    // verification screen and re-taps "Далі", skip the duplicate register()
    // call and go straight to verification (Phase 2.19 fix, bug #1).
    if (draft.password.isEmpty) {
      if (!mounted) return;
      context.go(RouteNames.verification, extra: draft.email);
      return;
    }

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

      // register() returns null only when an AsyncError was captured.
      if (result == null) {
        final error = ref.read(authProvider).error;
        _showSnackBar(
          error is Failure ? error.userMessage(context) : l10n.errUnknown,
        );
        return;
      }

      // Security (MEDIUM-1) — wipe plaintext password from the keepAlive draft
      // immediately after registration, before navigation. The locality/address
      // slice stays in the draft for the post-verification save.
      draftNotifier.clearCredentials();

      // 2. Navigate to verification carrying the email for the OTP screen.
      final email = result is VerificationRequired ? result.email : draft.email;
      if (!mounted) return;
      context.go(RouteNames.verification, extra: email);
    } finally {
      // Defect 2 — always re-enable CTAs.
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
          backgroundColor: BrandColors.error,
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(VelvetRadii.field)),
          ),
        ),
      );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final role =
        ref.watch(registerDraftProvider.select((d) => d?.role)) ??
        UserRole.client;

    final bool isClient = role == UserRole.client;
    final bool isProvider = !isClient;

    return AuthScaffold(
      showBack: true,
      onBack: () => context.go(RouteNames.registerStep2),
      bottomBar: _buildBottomBar(isClient, l10n, role),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── Location icon tile (72×72 neumorphic) + wizard chrome ─────────
          Center(
            child: Container(
              height: 72,
              width: 72,
              decoration: const BoxDecoration(
                color: BrandColors.base,
                borderRadius: BorderRadius.all(
                  Radius.circular(VelvetRadii.logoTile),
                ),
                boxShadow: VelvetShadows.extrudedSmall,
              ),
              child: const Icon(
                Icons.location_on_outlined,
                color: BrandColors.accent,
                size: 30,
              ),
            ),
          ),
          const SizedBox(height: VelvetSpacing.lg),
          WizardStepChrome(
            step: 2,
            headline: switch (role) {
              UserRole.client => l10n.registerStep3ShellHeadlineClient,
              UserRole.salonOwner => l10n.registerStep3ShellHeadlineOwner,
              _ => l10n.registerStep3ShellHeadlineMaster,
            },
          ),

          // ── Role-aware sub-text (shell owns the headline; screen owns context)
          Text(
            _subTextFor(role, l10n),
            key: const Key('step3-subtext'),
            style: VelvetText.body(),
          ),
          const SizedBox(height: VelvetSpacing.sm),

          // ── Locality cascade ───────────────────────────────────────────────
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

          // ── Provider-only address fields ───────────────────────────────────
          if (isProvider) ...<Widget>[
            const SizedBox(height: VelvetSpacing.md),
            const Divider(
              key: Key('step3-address-divider'),
              color: BrandColors.faint,
              height: 1,
              thickness: 1,
            ),
            const SizedBox(height: VelvetSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 2,
                  child: NeumorphicTextField(
                    key: const ValueKey<String>('address_street'),
                    label: l10n.step3FieldStreetLabel,
                    controller: _streetController,
                    hintText: l10n.step3FieldStreetPlaceholder,
                    keyboardType: TextInputType.streetAddress,
                    textInputAction: TextInputAction.next,
                    maxLength: kStreetMaxLength,
                    prefixIcon: const Icon(Icons.signpost_outlined),
                    focusNode: _streetFocusNode,
                    onSubmitted: (_) => _buildingFocusNode.requestFocus(),
                    errorText: _streetError,
                    onChanged: (_) => setState(() => _streetError = null),
                    inputFormatters: <TextInputFormatter>[
                      LengthLimitingTextInputFormatter(kStreetMaxLength),
                    ],
                    // autofillHints intentionally omitted — street address data is not autofilled by policy
                  ),
                ),
                const SizedBox(width: VelvetSpacing.md),
                Expanded(
                  child: NeumorphicTextField(
                    key: const ValueKey<String>('address_building'),
                    label: l10n.step3FieldBuildingLabel,
                    controller: _buildingController,
                    hintText: l10n.step3FieldBuildingPlaceholder,
                    textInputAction: TextInputAction.next,
                    maxLength: kBuildingMaxLength,
                    prefixIcon: const Icon(Icons.home_outlined),
                    focusNode: _buildingFocusNode,
                    onSubmitted: (_) => _noteFocusNode.requestFocus(),
                    errorText: _buildingError,
                    onChanged: (_) => setState(() => _buildingError = null),
                    inputFormatters: <TextInputFormatter>[
                      LengthLimitingTextInputFormatter(kBuildingMaxLength),
                    ],
                    // autofillHints intentionally omitted — street address data is not autofilled by policy
                  ),
                ),
              ],
            ),
            const SizedBox(height: VelvetSpacing.md),
            NeumorphicTextField(
              key: const ValueKey<String>('address_note'),
              label: l10n.step3FieldNoteLabel,
              controller: _noteController,
              hintText: l10n.step3FieldNotePlaceholder,
              textInputAction: TextInputAction.done,
              maxLength: kLocationNoteMaxLength,
              prefixIcon: const Icon(Icons.sticky_note_2_outlined),
              focusNode: _noteFocusNode,
              helperText: l10n.step3FieldNoteHelper,
              inputFormatters: <TextInputFormatter>[
                LengthLimitingTextInputFormatter(kLocationNoteMaxLength),
              ],
            ),
          ],

          const SizedBox(height: VelvetSpacing.md),
        ],
      ),
    );
  }

  Widget _buildBottomBar(bool isClient, AppLocalizations l10n, UserRole role) {
    if (isClient) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          NeumorphicButton(
            key: const ValueKey<String>('address_submit'),
            label: l10n.step2CtaContinue,
            onPressed: _submitting ? null : () => _submit(l10n, role),
          ),
          const SizedBox(height: VelvetSpacing.sm),
          Semantics(
            button: true,
            label: l10n.step3CtaSkip,
            child: GestureDetector(
              key: const ValueKey<String>('address_skip'),
              onTap: _submitting ? null : () => _skip(l10n, role),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: VelvetSizes.field,
                child: Center(
                  child: Text(
                    l10n.step3CtaSkip,
                    style: VelvetText.link(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return NeumorphicButton(
      key: const ValueKey<String>('address_submit'),
      label: l10n.step2CtaContinue,
      onPressed: _submitting ? null : () => _submit(l10n, role),
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
    // once below the whole cascade.
    final LocalityValidationError? err = localityError;
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
      // Defect 5 — explanatory helper caption on the disabled District row for
      // leaf cities so users understand why the field is disabled.
      showDistrictNoneHelper: true,
      // HTML: Oblast label carries CLIENT optional tag + "?" tip-icon.
      oblastLabelSuffix: _OblastLabelSuffix(isClient: isClient, l10n: l10n),
    );
  }
}

// ---------------------------------------------------------------------------
// _OblastLabelSuffix — CLIENT optional tag + "?" tip-icon
// ---------------------------------------------------------------------------

class _OblastLabelSuffix extends StatelessWidget {
  const _OblastLabelSuffix({required this.isClient, required this.l10n});

  final bool isClient;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (isClient) ...<Widget>[
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
// _TipIcon — circular "?" affordance, tap shows a tooltip (a11y)
// ---------------------------------------------------------------------------

class _TipIcon extends StatelessWidget {
  const _TipIcon({required this.tooltip, required this.semanticLabel});

  final String tooltip;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
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
                // Single-glyph affordance marker — exempt from l10n (same as
                // brand monogram). Meaning is carried by [semanticLabel] and
                // the localised [tooltip].
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
