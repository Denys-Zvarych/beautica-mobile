// Phase 2.16 — Registration wizard Step 1 (Account / credentials).
//
// SOURCE OF TRUTH: docs/signup-designs/sign-up-page.html. This screen owns
// the credential form only — email + password + confirm-password. The shared
// chrome (status bar, brand row, role chip, hero headline, 4-pill progress,
// "← Назад" link) is drawn by [RegisterFlowShell].
//
// Lifecycle:
//   1. User picks a role on the role-selection screen → registerDraftProvider
//      is initialised with that role.
//   2. /register loads RegisterStep1Screen inside RegisterFlowShell.
//   3. User fills the three fields and taps "Продовжити".
//   4. On valid submit the values are merged into the draft and the wizard
//      navigates to /register/step-2 (Phase 2.17). Step 1 does NOT call the
//      real `AuthNotifier.register` — the registration POST happens at the
//      end of Step 3 (Phase 2.19) once the full draft is assembled.
//
// Design tokens (locked — ARCHITECTURE-mobile.md § 9):
//   Input radius : 12 px
//   Input fill   : white 7% (0x12FFFFFF)
//   CTA height   : 52 dp
//   CTA radius   : 14 px
//   CTA gradient : #4A2E10 → #6A4A28 → #8A6840
//   CTA pattern  : DecoratedBox → ClipRRect → Material(transparent) → InkWell

import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/validators/email_validator.dart';
import '../../../shared/validators/password_validator.dart';
import '../../../shared/widgets/auth_field_label.dart';
import '../../../shared/widgets/password_criteria_row.dart';
import '../state/register_draft_notifier.dart';

// ---------------------------------------------------------------------------
// Static style constants — literal CSS values, allocated once.
// ---------------------------------------------------------------------------

/// sign-up-page.html input { border-radius: 12px }.
const _kInputRadius = BorderRadius.all(Radius.circular(12));

/// sign-up-page.html .cta-btn { border-radius: 14px }.
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
  borderSide: BorderSide(color: BrandColors.errorRust, width: 1),
);

const _kInputBorderFocusedError = OutlineInputBorder(
  borderRadius: _kInputRadius,
  borderSide: BorderSide(color: BrandColors.errorRust, width: 1.5),
);

/// .cta-grad: linear-gradient(135deg, #4a2e10 0%, #6a4a28 60%, #8a6840 100%).
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
    BoxShadow(
      color: Color(0x5B3A240C), // rgba(58,36,12,0.36)
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ],
);

const _kFieldIconColor = Color(0x40FFFFFF); // white ~25%
const _kFieldTextStyle = TextStyle(color: BrandColors.cream, fontSize: 16);

const _kCtaTextStyle = TextStyle(
  color: Colors.white,
  fontSize: 17,
  fontWeight: FontWeight.w500,
  letterSpacing: 0.3,
);

const _kTermsBase = TextStyle(
  fontSize: 10.5,
  color: Color(0x33FFFFFF), // rgba(255,255,255,0.2)
  height: 1.65,
);
const _kTermsLink = TextStyle(
  fontSize: 10.5,
  color: BrandColors.camel,
  fontWeight: FontWeight.w500,
  height: 1.65,
);

const _kLoginPromptStyle = TextStyle(color: Color(0x4DFFFFFF), fontSize: 15);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Step 1 of the multi-step registration wizard — credentials.
class RegisterStep1Screen extends ConsumerStatefulWidget {
  const RegisterStep1Screen({super.key});

  @override
  ConsumerState<RegisterStep1Screen> createState() =>
      _RegisterStep1ScreenState();
}

class _RegisterStep1ScreenState extends ConsumerState<RegisterStep1Screen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _buttonPressed = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill the form with values from the draft (e.g. when the user
    // returns to Step 1 via the back link from Step 2).
    final draft = ref.read(registerDraftProvider);
    if (draft != null) {
      _emailController.text = draft.email;
      _passwordController.text = draft.password;
      _confirmPasswordController.text = draft.confirmPassword;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ── Submit ────────────────────────────────────────────────────────────

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    ref
        .read(registerDraftProvider.notifier)
        .updateStep1(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          confirmPassword: _confirmPasswordController.text,
        );

    if (kDebugMode) {
      log(
        'Step 1 submitted — advancing to /register/step-2',
        name: 'auth.register.step1',
        level: 800,
      );
    }

    context.go(RouteNames.registerStep2);
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Email ───────────────────────────────────────────────────────
          _LabeledField(
            label: l10n.loginEmailLabel,
            child: TextFormField(
              key: const Key('field-email'),
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              style: _kFieldTextStyle,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: _decor(
                l10n.registerEmailPlaceholder,
                prefixIcon: const Icon(
                  Icons.mail_outline,
                  color: _kFieldIconColor,
                  size: 20,
                ),
              ),
              validator: (v) => validateEmail(v, l10n),
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
            ),
          ),
          const SizedBox(height: 14),

          // ── Password + criteria helper row ──────────────────────────────
          _LabeledField(
            label: l10n.loginPasswordLabel,
            child: _PasswordFieldWithCriteria(
              controller: _passwordController,
              l10n: l10n,
            ),
          ),
          const SizedBox(height: 14),

          // ── Confirm password ────────────────────────────────────────────
          _LabeledField(
            label: l10n.registerConfirmPasswordLabel,
            child: _ConfirmPasswordField(
              controller: _confirmPasswordController,
              passwordController: _passwordController,
              l10n: l10n,
              onSubmit: _submit,
            ),
          ),

          const SizedBox(height: 20),

          // ── CTA ─────────────────────────────────────────────────────────
          _MochaCtaButton(
            buttonKey: const Key('btn-submit-step-1'),
            label: l10n.registerContinue,
            onPressed: _submit,
            onTapDown: () => setState(() => _buttonPressed = true),
            onTapUp: () => setState(() => _buttonPressed = false),
            onTapCancel: () => setState(() => _buttonPressed = false),
            isPressed: _buttonPressed,
          ),

          const SizedBox(height: 12),
          _TermsLine(l10n: l10n),
          const SizedBox(height: 12),
          _LoginLinkRow(
            l10n: l10n,
            onTap: () {
              // Security (Phase 2.16 HIGH-1) — wipe the in-progress draft
              // (password fields included) before abandoning the wizard.
              ref.read(registerDraftProvider.notifier).reset();
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(RouteNames.login);
              }
            },
          ),
        ],
      ),
    );
  }

  InputDecoration _decor(
    String placeholder, {
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) => InputDecoration(
    hintText: placeholder,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: const Color(0x12FFFFFF),
    hintStyle: const TextStyle(color: Color(0x2EFFFFFF)),
    errorStyle: const TextStyle(color: BrandColors.errorRust, fontSize: 11),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: _kInputBorderDefault,
    enabledBorder: _kInputBorderDefault,
    focusedBorder: _kInputBorderFocused,
    errorBorder: _kInputBorderError,
    focusedErrorBorder: _kInputBorderFocusedError,
    isDense: true,
  );
}

// ---------------------------------------------------------------------------
// _LabeledField — uppercase label + 6px gap + child (sign-up-page.html label)
// ---------------------------------------------------------------------------

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [AuthFieldLabel(label), child],
  );
}

// ---------------------------------------------------------------------------
// _PasswordFieldWithCriteria — password field + 3-criteria helper row
// ---------------------------------------------------------------------------

class _PasswordFieldWithCriteria extends StatefulWidget {
  const _PasswordFieldWithCriteria({
    required this.controller,
    required this.l10n,
  });

  final TextEditingController controller;
  final AppLocalizations l10n;

  @override
  State<_PasswordFieldWithCriteria> createState() =>
      _PasswordFieldWithCriteriaState();
}

class _PasswordFieldWithCriteriaState
    extends State<_PasswordFieldWithCriteria> {
  String _currentPassword = '';
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onPasswordChanged);
    _currentPassword = widget.controller.text;
  }

  void _onPasswordChanged() {
    final text = widget.controller.text;
    if (text != _currentPassword) {
      setState(() => _currentPassword = text);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPasswordChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const Key('field-password'),
          controller: widget.controller,
          obscureText: _obscurePassword,
          enableSuggestions: false,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          style: _kFieldTextStyle,
          decoration: InputDecoration(
            hintText: l10n.registerPasswordPlaceholder,
            prefixIcon: const Icon(
              Icons.lock_outline,
              color: _kFieldIconColor,
              size: 20,
            ),
            suffixIcon: IconButton(
              key: const Key('btn-toggle-password'),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: const Color(0x47FFFFFF),
                size: 18,
                semanticLabel: _obscurePassword
                    ? l10n.showPasswordSemanticLabel
                    : l10n.hidePasswordSemanticLabel,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
            filled: true,
            fillColor: const Color(0x12FFFFFF),
            hintStyle: const TextStyle(color: Color(0x2EFFFFFF)),
            errorStyle: const TextStyle(
              color: BrandColors.errorRust,
              fontSize: 11,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: _kInputBorderDefault,
            enabledBorder: _kInputBorderDefault,
            focusedBorder: _kInputBorderFocused,
            errorBorder: _kInputBorderError,
            focusedErrorBorder: _kInputBorderFocusedError,
            isDense: true,
          ),
          validator: (v) => validatePassword(v, l10n),
        ),
        PasswordCriteriaRow(
          key: const Key('password-criteria-row'),
          password: _currentPassword,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _ConfirmPasswordField — confirm password field with match validator
// ---------------------------------------------------------------------------

class _ConfirmPasswordField extends StatefulWidget {
  const _ConfirmPasswordField({
    required this.controller,
    required this.passwordController,
    required this.l10n,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final TextEditingController passwordController;
  final AppLocalizations l10n;
  final VoidCallback onSubmit;

  @override
  State<_ConfirmPasswordField> createState() => _ConfirmPasswordFieldState();
}

class _ConfirmPasswordFieldState extends State<_ConfirmPasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return TextFormField(
      key: const Key('field-confirm-password'),
      controller: widget.controller,
      obscureText: _obscure,
      enableSuggestions: false,
      autocorrect: false,
      textInputAction: TextInputAction.done,
      style: _kFieldTextStyle,
      decoration: InputDecoration(
        hintText: l10n.registerConfirmPasswordPlaceholder,
        prefixIcon: const Icon(
          Icons.lock_outline,
          color: _kFieldIconColor,
          size: 20,
        ),
        suffixIcon: IconButton(
          key: const Key('btn-toggle-confirm-password'),
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: const Color(0x47FFFFFF),
            size: 18,
            semanticLabel: _obscure
                ? l10n.showPasswordSemanticLabel
                : l10n.hidePasswordSemanticLabel,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
        filled: true,
        fillColor: const Color(0x12FFFFFF),
        hintStyle: const TextStyle(color: Color(0x2EFFFFFF)),
        errorStyle: const TextStyle(color: BrandColors.errorRust, fontSize: 11),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: _kInputBorderDefault,
        enabledBorder: _kInputBorderDefault,
        focusedBorder: _kInputBorderFocused,
        errorBorder: _kInputBorderError,
        focusedErrorBorder: _kInputBorderFocusedError,
        isDense: true,
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return l10n.errPasswordRequired;
        if (v != widget.passwordController.text) {
          return l10n.errPasswordsMismatch;
        }
        return null;
      },
      onFieldSubmitted: (_) => widget.onSubmit(),
    );
  }
}

// ---------------------------------------------------------------------------
// _MochaCtaButton — DecoratedBox→ClipRRect→Material→InkWell gradient CTA
// ---------------------------------------------------------------------------

class _MochaCtaButton extends StatelessWidget {
  const _MochaCtaButton({
    required this.buttonKey,
    required this.label,
    required this.onPressed,
    required this.onTapDown,
    required this.onTapUp,
    required this.onTapCancel,
    required this.isPressed,
  });

  final Key buttonKey;
  final String label;
  final VoidCallback? onPressed;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;
  final VoidCallback onTapCancel;
  final bool isPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: buttonKey,
      onTapDown: (_) => onTapDown(),
      onTapUp: (_) => onTapUp(),
      onTapCancel: onTapCancel,
      child: AnimatedScale(
        scale: isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: DecoratedBox(
          decoration: _kCtaDecoration,
          child: ClipRRect(
            borderRadius: _kCtaRadius,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onPressed,
                splashColor: const Color(0x14FFFFFF),
                highlightColor: const Color(0x0AFFFFFF),
                child: SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: Align(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(label, style: _kCtaTextStyle),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
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
// _TermsLine — terms + privacy line (sign-up-page.html .terms)
// ---------------------------------------------------------------------------

class _TermsLine extends StatelessWidget {
  const _TermsLine({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: _kTermsBase,
        children: [
          TextSpan(text: '${l10n.registerTermsPrefix}\n'),
          TextSpan(text: l10n.registerTermsTerms, style: _kTermsLink),
          TextSpan(text: l10n.registerTermsConjunction),
          TextSpan(text: l10n.registerTermsPrivacy, style: _kTermsLink),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

// ---------------------------------------------------------------------------
// _LoginLinkRow — "Вже є акаунт? Увійти" (.login-row)
// ---------------------------------------------------------------------------

class _LoginLinkRow extends StatelessWidget {
  const _LoginLinkRow({required this.l10n, required this.onTap});

  final AppLocalizations l10n;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(l10n.registerHaveAccount, style: _kLoginPromptStyle),
        TextButton(
          key: const Key('btn-go-to-login'),
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: BrandColors.camel,
            disabledForegroundColor: BrandColors.camel,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          child: Text(l10n.registerSignIn),
        ),
      ],
    );
  }
}
