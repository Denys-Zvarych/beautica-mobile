// Phase 2.17 — Registration wizard Step 2 (Profile).
//
// SOURCE OF TRUTH: docs/signup-designs/sign-up-step-2-profile.html.
// Every element is transcribed literally — non-functional elements rendered.
//
// This screen renders ONLY the card body — the outer chrome (monogram, brand
// row, role chip, hero headline, 4-dot progress, back link, glass card
// wrapper) is owned by [RegisterFlowShell] (Phase 2.16).
//
// Role-conditional field matrix (LOCKED per spec + HTML):
//   CLIENT / INDEPENDENT_MASTER:  Ім'я · Прізвище (two-column) · Телефон
//   SALON_OWNER:                  Same three + Назва салону
//
// On "Продовжити":
//   1. Validate all visible fields.
//   2. Auto-focus first invalid field (UX focus-management rule).
//   3. ref.read(registerDraftProvider.notifier).updateStep2(...)
//   4. context.go(RouteNames.registerStep3)
//
// Design tokens (ARCHITECTURE-mobile.md § 9 — locked):
//   Input radius         : 12 dp
//   Input fill           : white 7% (0x12FFFFFF)
//   CTA height           : 52 dp
//   CTA radius           : 14 dp
//   CTA gradient         : #4A2E10 → #6A4A28 → #8A6840
//   CTA pattern          : DecoratedBox → ClipRRect → Material(transparent) → InkWell

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/validators/name_validator.dart';
import '../../../shared/validators/phone_validator.dart';
import '../../../shared/validators/salon_name_validator.dart';
import '../../../shared/widgets/auth_field_label.dart';
import '../domain/user_role.dart';
import '../state/register_draft_notifier.dart';
import 'widgets/sub_step_indicator.dart';
import 'widgets/two_column_row.dart';

// ---------------------------------------------------------------------------
// Pre-allocated static constants — never constructed inside build().
// ---------------------------------------------------------------------------

/// HTML: input { border-radius: 12px }.
const _kInputRadius = BorderRadius.all(Radius.circular(12));

/// HTML: .cta-btn { border-radius: 14px }.
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

const _kFieldTextStyle = TextStyle(
  color: BrandColors.white,
  fontSize: 14, // HTML: font-size: 14px
);

const _kFieldHintStyle = TextStyle(
  color: Color(0x2EFFFFFF), // rgba(255,255,255,0.18) — HTML: input::placeholder
  fontSize: 14,
);

const _kErrorStyle = TextStyle(
  color: BrandColors.error,
  fontSize: 11,
  height: 1.4,
);

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
  fontSize: 15, // HTML: font-size: 15px
  fontWeight: FontWeight.w600,
  letterSpacing: 0.3,
);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Step 2 of the multi-step registration wizard — Profile.
///
/// Renders the card body only; [RegisterFlowShell] owns the outer chrome.
class RegisterStep2Screen extends ConsumerStatefulWidget {
  const RegisterStep2Screen({super.key});

  @override
  ConsumerState<RegisterStep2Screen> createState() =>
      _RegisterStep2ScreenState();
}

class _RegisterStep2ScreenState extends ConsumerState<RegisterStep2Screen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _salonNameController = TextEditingController();

  final _nameFocusNode = FocusNode();
  final _surnameFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();
  final _salonNameFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Seed from draft — restores values when user returns via "← Назад".
    final draft = ref.read(registerDraftProvider);
    if (draft != null) {
      _nameController.text = draft.firstName;
      _surnameController.text = draft.lastName;
      _phoneController.text = draft.phone;
      _salonNameController.text = draft.salonName;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _phoneController.dispose();
    _salonNameController.dispose();
    _nameFocusNode.dispose();
    _surnameFocusNode.dispose();
    _phoneFocusNode.dispose();
    _salonNameFocusNode.dispose();
    super.dispose();
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  void _submit(AppLocalizations l10n, UserRole role) {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      // Auto-focus the first invalid field (UX: focus-management rule).
      if (validateName(_nameController.text, l10n) != null) {
        _nameFocusNode.requestFocus();
      } else if (validateName(_surnameController.text, l10n) != null) {
        _surnameFocusNode.requestFocus();
      } else if (validatePhone(_phoneController.text, l10n) != null) {
        _phoneFocusNode.requestFocus();
      } else {
        _salonNameFocusNode.requestFocus();
      }
      return;
    }

    final isSalonOwner = role == UserRole.salonOwner;

    if (kDebugMode) {
      log(
        'Step 2 submit: role=${role.toWire} '
        'firstName=[REDACTED] '
        'isSalonOwner=$isSalonOwner',
        name: 'auth.register.step2',
        level: 800,
      );
    }

    ref
        .read(registerDraftProvider.notifier)
        .updateStep2(
          firstName: _nameController.text.trim(),
          lastName: _surnameController.text.trim(),
          phone: _phoneController.text.trim(),
          // Non-owner roles pass the empty string — exercises the updateStep2
          // optional salonName='' default branch for CLIENT/INDEPENDENT_MASTER.
          salonName: isSalonOwner ? _salonNameController.text.trim() : '',
        );

    if (!mounted) return;
    context.go(RouteNames.registerStep3);
  }

  // ── Role-aware field tree ─────────────────────────────────────────────────

  /// Returns the role-specific field widget tree.
  ///
  /// CLIENT / INDEPENDENT_MASTER: Ім'я + Прізвище (two-column) + Телефон.
  /// SALON_OWNER: same three + Назва салону (no divider, no section label).
  Widget _fieldsForRole(UserRole role, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // HTML: .row-2 { grid-template-columns: 1fr 1fr; gap: 10px }
        TwoColumnRow(
          gap: AppSpacing.xs, // 8 dp ≈ HTML 10 px gap
          left: _NameField(
            controller: _nameController,
            focusNode: _nameFocusNode,
            nextFocusNode: _surnameFocusNode,
            l10n: l10n,
          ),
          right: _SurnameField(
            controller: _surnameController,
            focusNode: _surnameFocusNode,
            nextFocusNode: _phoneFocusNode,
            l10n: l10n,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        _PhoneField(
          controller: _phoneController,
          focusNode: _phoneFocusNode,
          nextFocusNode: role == UserRole.salonOwner
              ? _salonNameFocusNode
              : null,
          l10n: l10n,
        ),

        // ── SALON_OWNER only ──────────────────────────────────────────────
        if (role == UserRole.salonOwner) ...[
          const SizedBox(height: AppSpacing.sm),
          _SalonNameField(
            controller: _salonNameController,
            focusNode: _salonNameFocusNode,
            l10n: l10n,
          ),
        ],
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Watch only the role slice — other draft changes (keystrokes in Step 1)
    // must not cause this screen to rebuild.
    final role =
        ref.watch(registerDraftProvider.select((d) => d?.role)) ??
        UserRole.client;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Sub-step indicator (two pill dots, first active) ──────────
          // HTML: .substep-row / .substep-dots — dots only, no visible text.
          const SubStepIndicator(key: Key('substep-indicator'), activeIndex: 0),
          const SizedBox(height: AppSpacing.sm),

          // ── Role-aware fields ─────────────────────────────────────────
          _fieldsForRole(role, l10n),
          const SizedBox(height: AppSpacing.xs),

          // ── CTA: Продовжити ───────────────────────────────────────────
          // HTML: .cta-btn { height:52px; border-radius:14px; gradient }
          // Pattern: DecoratedBox → ClipRRect → Material(transparent) → InkWell
          _CtaButton(
            label: l10n.step2CtaContinue,
            onTap: () => _submit(l10n, role),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _NameField — "Ім'я" with person icon
// ---------------------------------------------------------------------------

class _NameField extends StatelessWidget {
  const _NameField({
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
        AuthFieldLabel(l10n.step2FieldNameLabel),
        TextFormField(
          key: const Key('field-name'),
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.next,
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
          style: _kFieldTextStyle,
          decoration: InputDecoration(
            hintText: l10n.step2FieldNamePlaceholder,
            hintStyle: _kFieldHintStyle,
            filled: true,
            fillColor: _kInputFill,
            prefixIcon: const Icon(
              Icons.person_outline,
              size: 15,
              color: _kFieldIconColor,
            ),
            // HTML: .input-icon { left:13px } → contentPadding right,
            // prefixIconConstraints shrinks the left icon zone.
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
          validator: (v) => validateName(v, l10n),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _SurnameField — "Прізвище" with person icon
// ---------------------------------------------------------------------------

class _SurnameField extends StatelessWidget {
  const _SurnameField({
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
        AuthFieldLabel(l10n.step2FieldSurnameLabel),
        TextFormField(
          key: const Key('field-surname'),
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.next,
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
          style: _kFieldTextStyle,
          decoration: InputDecoration(
            hintText: l10n.step2FieldSurnamePlaceholder,
            hintStyle: _kFieldHintStyle,
            filled: true,
            fillColor: _kInputFill,
            prefixIcon: const Icon(
              Icons.person_outline,
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
          validator: (v) => validateName(v, l10n),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _PhoneField — "Телефон" with phone icon, tel keyboard
// ---------------------------------------------------------------------------

class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.controller,
    required this.focusNode,
    this.nextFocusNode,
    required this.l10n,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Null when phone is the last field (CLIENT / MASTER variants).
  final FocusNode? nextFocusNode;

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthFieldLabel(l10n.step2FieldPhoneLabel),
        TextFormField(
          key: const Key('field-phone'),
          controller: controller,
          focusNode: focusNode,
          textInputAction: nextFocusNode != null
              ? TextInputAction.next
              : TextInputAction.done,
          keyboardType: TextInputType.phone,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          style: _kFieldTextStyle,
          decoration: InputDecoration(
            hintText: l10n.step2FieldPhonePlaceholder,
            hintStyle: _kFieldHintStyle,
            filled: true,
            fillColor: _kInputFill,
            // HTML: phone icon SVG — map to phone_outlined Material icon
            prefixIcon: const Icon(
              Icons.phone_outlined,
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
          onFieldSubmitted: (_) => nextFocusNode?.requestFocus(),
          validator: (v) => validatePhone(v, l10n),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _SalonNameField — "Назва салону" with building icon (OWNER only)
// ---------------------------------------------------------------------------

class _SalonNameField extends StatelessWidget {
  const _SalonNameField({
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
        AuthFieldLabel(l10n.step2FieldSalonLabel),
        TextFormField(
          key: const Key('field-salon-name'),
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.done,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.words,
          style: _kFieldTextStyle,
          decoration: InputDecoration(
            hintText: l10n.step2FieldSalonPlaceholder,
            hintStyle: _kFieldHintStyle,
            filled: true,
            fillColor: _kInputFill,
            // HTML: building icon SVG — map to storefront_outlined Material icon
            prefixIcon: const Icon(
              Icons.storefront_outlined,
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
          validator: (v) => validateSalonName(v, l10n),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _CtaButton — "Продовжити" gradient button
// ---------------------------------------------------------------------------
//
// HTML: .cta-btn { height:52px; border-radius:14px; gradient; arrow icon }
// Pattern: DecoratedBox → ClipRRect → Material(transparent) → InkWell

class _CtaButton extends StatelessWidget {
  const _CtaButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _kCtaDecoration,
      child: ClipRRect(
        borderRadius: _kCtaRadius,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const Key('btn-continue-step2'),
            onTap: onTap,
            child: SizedBox(
              height: 52,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: _kCtaTextStyle),
                  const SizedBox(width: AppSpacing.xs),
                  // HTML: arrow SVG icon — map to arrow_forward Material icon
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
    );
  }
}
