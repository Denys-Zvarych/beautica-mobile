// Phase 2.17 — Registration wizard Step 2 (Profile) — VelvetTouch redesign.
//
// Design source of truth:
//   docs/signup-designs/VelvetTouchDesign/lib/screens/sign_up_screen.dart
//   (profile-fields section only — email/password not included here).
//
// This screen renders ONLY the card body — the outer chrome (progress dots,
// back button, brand header) is owned by [AuthScaffold] / [RegisterFlowShell].
//
// Role-conditional field matrix (LOCKED per spec):
//   CLIENT / INDEPENDENT_MASTER:  Ім'я · Прізвище (two-column) · Телефон
//   SALON_OWNER:                  Same three + Назва салону
//
// On "Продовжити":
//   1. Block submit if phone is empty (surface inline error).
//   2. ref.read(registerDraftProvider.notifier).updateStep2(...)
//   3. context.go(RouteNames.registerStep3)
//
// VelvetTouch design constraints (no glassmorphism, no BackdropFilter):
//   - Background: BrandColors.base (#E6DDD0) via AuthScaffold.
//   - Fields:     NeumorphicTextField (inset neumorphic well).
//   - CTA:        NeumorphicButton pinned to AuthScaffold.bottomBar.
//   - Colors:     BrandColors.* only — no raw Color(0xFF…) literals.
//   - Spacing:    VelvetSpacing.* only — no raw dp literals.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/velvet_geometry.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/validators/phone_validator.dart';
import '../domain/user_role.dart';
import '../state/register_draft_notifier.dart';
import 'widgets/auth_scaffold.dart';

// ---------------------------------------------------------------------------
// Module-level constants — never constructed inside build().
// Phase 2.16 fix P1-1: RegExp hoisted to avoid per-frame allocation.
// ---------------------------------------------------------------------------

/// Allows only digits, +, spaces, hyphens, and parentheses — UA phone charset.
final RegExp _phoneInputPattern = RegExp(r'[+\d\s\-()]');

/// Pre-built formatter derived from the hoisted pattern.
final FilteringTextInputFormatter _phoneFormatter =
    FilteringTextInputFormatter.allow(_phoneInputPattern);

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
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _salonNameController = TextEditingController();

  /// Mirrors the raw text value of the phone field so we can derive
  /// [_phoneError] without touching the controller inside build().
  String _phoneValue = '';

  /// True once the user has interacted with the phone field at least once.
  /// The inline required-error is only surfaced after the first touch.
  bool _phoneTouched = false;

  /// Set by [_onSubmit] when [validatePhone] rejects the entered value.
  /// Cleared on every [onChanged] so stale format errors disappear while
  /// the user is actively editing.
  String? _phoneFormatError;

  // ── Derived state ──────────────────────────────────────────────────────────

  /// The role stored in the draft — determines whether the salon-name field
  /// is shown. Read once from the provider (no watch — role is set in Step 1
  /// and must not cause a rebuild here when other draft slices change).
  bool get _isOwner =>
      ref.read(registerDraftProvider)?.role == UserRole.salonOwner;

  /// Inline phone error, evaluated in priority order:
  ///   1. Format error set by [_onSubmit] (takes precedence over empty guard).
  ///   2. Required-field guard — only surfaced after the first touch.
  String? get _phoneError {
    if (_phoneFormatError != null) return _phoneFormatError;
    if (!_phoneTouched) return null;
    final l10n = AppLocalizations.of(context);
    return _phoneValue.trim().isEmpty ? l10n.registerPhoneRequired : null;
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
      _phoneController.text = draft.phone;
      _phoneValue = draft.phone;
      _salonNameController.text = draft.salonName;
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _salonNameController.dispose();
    super.dispose();
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  void _onSubmit() {
    // Phone is required for all roles — surface the inline error and block.
    if (_phoneController.text.trim().isEmpty) {
      setState(() => _phoneTouched = true);
      return;
    }

    // Format validation — rejects structurally invalid Ukrainian numbers.
    final l10n = AppLocalizations.of(context);
    final String? phoneErr = validatePhone(_phoneController.text.trim(), l10n);
    if (phoneErr != null) {
      setState(() {
        _phoneTouched = true;
        _phoneFormatError = phoneErr;
      });
      return;
    }

    ref
        .read(registerDraftProvider.notifier)
        .updateStep2(
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          phone: _phoneController.text.trim(),
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
      bottomBar: NeumorphicButton(
        key: const ValueKey<String>('step2_submit'),
        label: l10n.step2CtaContinue,
        onPressed: _onSubmit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
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
                ),
              ),
            ],
          ),
          const SizedBox(height: VelvetSpacing.md),

          // ── Phone ────────────────────────────────────────────────────────
          NeumorphicTextField(
            key: const ValueKey<String>('step2_phone'),
            label: l10n.step2FieldPhoneLabel,
            controller: _phoneController,
            hintText: l10n.registerPhoneHint,
            keyboardType: TextInputType.phone,
            textInputAction: isOwner
                ? TextInputAction.next
                : TextInputAction.done,
            maxLength: 20,
            prefixIcon: const Icon(Icons.phone_outlined),
            autofillHints: const <String>[AutofillHints.telephoneNumber],
            errorText: _phoneError,
            inputFormatters: <TextInputFormatter>[_phoneFormatter],
            autocorrect: false,
            onChanged: (String v) => setState(() {
              _phoneValue = v;
              _phoneTouched = true;
              _phoneFormatError = null; // clear stale format error on edit
            }),
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
            ),
          ],

          const SizedBox(height: VelvetSpacing.lg),
        ],
      ),
    );
  }
}
