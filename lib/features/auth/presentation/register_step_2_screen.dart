// Phase 2.21 — Registration wizard Step 2 (Profile) — VelvetTouch redesign.
// (Updated from Phase 2.17: phone field uses UaPhoneInputFormatter for real-time
// +380 XX XXX XX XX mask instead of FilteringTextInputFormatter.)
//
// Design source of truth:
//   docs/signup-designs/VelvetTouchDesign/lib/screens/sign_up_screen.dart
//   (profile-fields section only — email/password not included here).
//
// This screen renders ONLY the card body — the outer chrome (progress dots,
// back button, brand header) is owned by [AuthScaffold] / [RegisterFlowShell].
//
// Role-conditional field matrix (LOCKED per spec):
//   CLIENT / INDEPENDENT_MASTER:  Ім'я · Прізвище (two-column)
//   SALON_OWNER:                  Same two + Назва салону
// M515 (AUTH-D11) — step 4 of the phone-first wizard; the phone moved to
// step 1 (verified by SMS), so this step no longer has a phone field.
//
// On "Продовжити":
//   1. ref.read(registerDraftProvider.notifier).updateStep2(...)
//   2. context.go(RouteNames.registerStep3)
//
// VelvetTouch design constraints (no glassmorphism, no BackdropFilter):
//   - Background: BrandColors.base (#E6DDD0) via AuthScaffold.
//   - Fields:     NeumorphicTextField (inset neumorphic well).
//   - CTA:        NeumorphicButton pinned to AuthScaffold.bottomBar.
//   - Colors:     BrandColors.* only — no raw Color(0xFF…) literals.
//   - Spacing:    VelvetSpacing.* only — no raw dp literals.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/velvet_geometry.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/validators/name_validator.dart';
import '../../../shared/validators/salon_name_validator.dart';
import '../domain/user_role.dart';
import '../state/register_draft_notifier.dart';
import 'register_flow_shell.dart';
import 'widgets/auth_icon_tile.dart';
import 'widgets/auth_scaffold.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Step 2 of the multi-step registration wizard — Profile fields.
///
/// Renders the profile-fields body only; [AuthScaffold] owns the outer chrome
/// (back button, scroll physics, bottom CTA pinning, safe-area).
class RegisterStep2Screen extends ConsumerStatefulWidget {
  const RegisterStep2Screen({super.key});

  @override
  ConsumerState<RegisterStep2Screen> createState() =>
      _RegisterStep2ScreenState();
}

class _RegisterStep2ScreenState extends ConsumerState<RegisterStep2Screen> {
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _salonNameController = TextEditingController();

  /// True once the user has interacted with the first-name field at least once.
  /// The inline required-error is only surfaced after the first touch.
  bool _firstNameTouched = false;

  /// True once the user has interacted with the last-name field at least once.
  /// The inline required-error is only surfaced after the first touch.
  bool _lastNameTouched = false;

  /// True once the user has interacted with the salon-name field at least once.
  /// The inline error is only surfaced after the first touch.
  bool _salonNameTouched = false;

  // ── Derived state ──────────────────────────────────────────────────────────

  /// The role stored in the draft — determines whether the salon-name field
  /// is shown. Read once from the provider (no watch — role is set in Step 1
  /// and must not cause a rebuild here when other draft slices change).
  bool get _isOwner =>
      ref.read(registerDraftProvider)?.role == UserRole.salonOwner;

  /// Inline first-name error — required + max-length (100) guard via
  /// [validateName]. Only surfaced after the first touch.
  String? get _firstNameError {
    if (!_firstNameTouched) return null;
    final l10n = AppLocalizations.of(context);
    return validateName(_firstNameController.text, l10n);
  }

  /// Inline last-name error — required + max-length (100) guard via
  /// [validateName]. Only surfaced after the first touch.
  String? get _lastNameError {
    if (!_lastNameTouched) return null;
    final l10n = AppLocalizations.of(context);
    return validateName(_lastNameController.text, l10n);
  }

  /// Inline salon-name error (SALON_OWNER only) — non-blank + max-length (255)
  /// + control-char-free guard via [validateSalonName]. Only surfaced after the
  /// first touch.
  String? get _salonNameError {
    if (!_salonNameTouched) return null;
    if (!_isOwner) return null;
    final l10n = AppLocalizations.of(context);
    return validateSalonName(_salonNameController.text, l10n);
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Seed controllers from draft — restores values when user returns via back.
    final draft = ref.read(registerDraftProvider);
    if (draft != null) {
      _firstNameController.text = draft.firstName;
      _lastNameController.text = draft.lastName;
      _salonNameController.text = draft.salonName;
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _salonNameController.dispose();
    super.dispose();
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  void _onSubmit() {
    final l10n = AppLocalizations.of(context);

    // Name fields are required for all roles (non-blank + max-length 100) —
    // surface inline errors and block.
    final String? firstNameErr = validateName(_firstNameController.text, l10n);
    final String? lastNameErr = validateName(_lastNameController.text, l10n);
    if (firstNameErr != null || lastNameErr != null) {
      setState(() {
        _firstNameTouched = true;
        _lastNameTouched = true;
      });
      return;
    }

    // Salon name (SALON_OWNER only) — non-blank + max-length 255 +
    // control-char-free. Block submit and surface the inline error.
    if (_isOwner) {
      final String? salonErr = validateSalonName(
        _salonNameController.text,
        l10n,
      );
      if (salonErr != null) {
        setState(() => _salonNameTouched = true);
        return;
      }
    }

    ref
        .read(registerDraftProvider.notifier)
        .updateStep2(
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          // Non-owner roles pass the empty string — exercises the updateStep2
          // optional salonName='' default branch for CLIENT/INDEPENDENT_MASTER.
          salonName: _isOwner ? _salonNameController.text.trim() : '',
        );

    if (!mounted) return;
    context.go(RouteNames.registerStep3);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Watch only the role slice — other draft mutations (e.g. back-filling
    // address in Step 3) must not trigger a Step 2 rebuild.
    final role =
        ref.watch(registerDraftProvider.select((d) => d?.role)) ??
        UserRole.client;

    final isOwner = role == UserRole.salonOwner;

    return AuthScaffold(
      showBack: true,
      onBack: () => context.go(RouteNames.registerPassword),
      bottomBar: NeumorphicButton(
        key: const ValueKey<String>('step2_submit'),
        label: l10n.step2CtaContinue,
        onPressed: _onSubmit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── Icon tile + wizard chrome (step 4 of the phone-first wizard) ──
          const AuthIconTile(icon: Icons.person_outline_rounded),
          const SizedBox(height: VelvetSpacing.lg),
          WizardStepChrome(
            step: 4,
            headline: l10n.registerStep2ShellHeadline,
            totalSteps: kPhoneFirstRegisterSteps,
          ),

          // ── Name row (Ім'я + Прізвище side-by-side) ─────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: NeumorphicTextField(
                  key: const ValueKey<String>('step2_first_name'),
                  label: l10n.step2FieldNameLabel,
                  controller: _firstNameController,
                  hintText: l10n.step2FieldNamePlaceholder,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.name,
                  maxLength: 100,
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  autofillHints: const <String>[AutofillHints.givenName],
                  errorText: _firstNameError,
                  onChanged: (String v) =>
                      setState(() => _firstNameTouched = true),
                ),
              ),
              const SizedBox(width: VelvetSpacing.md),
              Expanded(
                child: NeumorphicTextField(
                  key: const ValueKey<String>('step2_last_name'),
                  label: l10n.step2FieldSurnameLabel,
                  controller: _lastNameController,
                  hintText: l10n.step2FieldSurnamePlaceholder,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.name,
                  maxLength: 100,
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  autofillHints: const <String>[AutofillHints.familyName],
                  errorText: _lastNameError,
                  onChanged: (String v) =>
                      setState(() => _lastNameTouched = true),
                ),
              ),
            ],
          ),
          // ── Salon name (SALON_OWNER only) ─────────────────────────────────
          if (isOwner) ...<Widget>[
            const SizedBox(height: VelvetSpacing.md),
            NeumorphicTextField(
              key: const ValueKey<String>('step2_salon_name'),
              label: l10n.step2FieldSalonLabel,
              controller: _salonNameController,
              hintText: l10n.step2FieldSalonPlaceholder,
              textInputAction: TextInputAction.done,
              keyboardType: TextInputType.text,
              maxLength: 255,
              prefixIcon: const Icon(Icons.storefront_outlined),
              helperText: l10n.step2SalonNameHelper,
              errorText: _salonNameError,
              onChanged: (String v) => setState(() => _salonNameTouched = true),
            ),
          ],

          const SizedBox(height: VelvetSpacing.lg),
        ],
      ),
    );
  }
}
