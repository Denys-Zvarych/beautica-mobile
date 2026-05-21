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

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/validators/email_validator.dart';
import '../../../shared/validators/password_validator.dart';
import '../../../shared/widgets/auth_field_label.dart';
import '../../../shared/widgets/password_criteria_row.dart';
import '../state/register_draft_notifier.dart';

// ---------------------------------------------------------------------------
// Bottom back-link style — matches Step 2/3 _BackLink in RegisterFlowShell.
// ---------------------------------------------------------------------------

/// .back-row a { font-size: 13px; color: var(--accent); font-weight: 600;
/// opacity: 0.85 }.
final _kBackToRoleStyle = TextStyle(
  color: BrandColors.camel.withValues(alpha: 0.85),
  fontSize: 13,
  fontWeight: FontWeight.w600,
);

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

const _kLoginPromptStyle = TextStyle(color: Color(0x4DFFFFFF), fontSize: 13);

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
          // ── 2026-05-20 design refresh: bottom-of-card "← Назад" link ────
          //    Mirrors the Step 2/3 _BackLink placement so the wizard has a
          //    consistent back affordance at the same on-screen location on
          //    every step. Going back ONE wizard step preserves the draft
          //    (incl. the chosen role) so the role-selection screen can
          //    re-highlight the previously chosen role — see role_selection_
          //    screen.dart initState. The HIGH-1 credential-leak concern is
          //    NOT triggered by a single-step back: the draft only escapes the
          //    wizard via the "log in instead" link (which still resets).
          // .back-row { margin-top: 16px }. The back link reclaims 14px of this
          // gap as TOP tap padding (a11y), so this spacer carries the
          // remaining 16 − 14 = 2px. Visible gap above the back text stays
          // 2 (here) + 14 (back-link top pad) = 16. No AppSpacing token equals
          // 2 — it is a derived padding-compensation offset, not a design
          // value, so it is written as a literal.
          const SizedBox(height: 2),
          _BackToRoleLink(
            l10n: l10n,
            onTap: () {
              // Going back one wizard step PRESERVES the draft (incl. role) so
              // the role-selection screen re-highlights the chosen role and
              // keeps Continue enabled. Do NOT reset() here.
              context.go(RouteNames.registerRole);
            },
          ),
          // .login-row { margin-top: 12px }. The back link contributes 2px
          // BOTTOM tap pad and the login link 2px TOP tap pad, so this spacer
          // carries 12 − 2 − 2 = 8px. Visible gap below the back text stays
          // 2 + 8 + 2 = 12, and the two links' hit boxes remain 8px apart
          // (ui-ux-pro-max `touch-spacing` minimum). AppSpacing.xs == 8.
          const SizedBox(height: AppSpacing.xs),
          _LoginLinkRow(
            l10n: l10n,
            onTap: () {
              // Security (Phase 2.16 HIGH-1) — wipe the in-progress draft
              // (password fields included) before abandoning the wizard.
              ref.read(registerDraftProvider.notifier).reset();
              // Navigate unconditionally to login. The wizard nav stack is
              // role→step1, so canPop() would land on role-selection, not the
              // login page — go() guarantees the correct destination.
              context.go(RouteNames.login);
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
// _BackToRoleLink — "← Назад" link below the glass card on Step 1.
//
// Mirrors the visual treatment of the Step 2/3 _BackLink in
// register_flow_shell.dart (camel, 13 px, font-weight 600, decorative "←"
// arrow). Destination is the role-selection screen; the tap handler is
// supplied by the caller so the in-progress draft can be reset BEFORE
// navigation (Phase 2.16 HIGH-1).
// ---------------------------------------------------------------------------

class _BackToRoleLink extends StatelessWidget {
  const _BackToRoleLink({required this.l10n, required this.onTap});

  final AppLocalizations l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A11y: the visible "← Назад" text keeps its exact position and the
    // design's 16-above / 12-below gaps, but the *tap* area is enlarged by
    // pulling the adjacent whitespace INTO the button as hit padding and
    // stretching it full-width. The vertical padding is asymmetric:
    //   top    = 14  → reclaims most of the 16px SizedBox above (now 16−14=2)
    //   bottom = 2   → reclaims 2px of the 12px gap below
    // Net visible gap above = 2 (SizedBox) + 14 (top pad) = 16 ✓. Material's
    // own padded box is suppressed (shrinkWrap) so this padding is exact and
    // never inflates the layout. Effective hit area ≈ 13px text line + 14 + 2
    // ≈ 33px tall × full row width — well above the previous ~13px text-only
    // target. 44px is geometrically unreachable here (two links only 12px
    // apart cannot both have a 44px box while keeping the required ≥8px
    // touch-spacing between hit boxes — ui-ux-pro-max `touch-spacing`), so we
    // maximise within the available rhythm and prioritise full WIDTH. A wide
    // ~33px target is an acceptable a11y improvement for a secondary inline
    // link (ui-ux-pro-max `touch-target-size`: extend hit area beyond visual
    // bounds when a full box doesn't fit).
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        key: const Key('btn-back-to-role'),
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: BrandColors.camel,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size(0, 0),
          padding: const EdgeInsets.only(top: 14, bottom: 2),
        ),
        // The leading arrow is a Material [Icon] (not a unicode "←" glyph): the
        // Manrope UI font has no fontFamilyFallback covering U+2190, so the
        // textual arrow rendered blank. Icons.west is a bundled, thin
        // leftward arrow that matches the back-link aesthetic and always paints.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.west,
              size: 15,
              color: BrandColors.camel.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 6),
            Text(l10n.registerBackToRole, style: _kBackToRoleStyle),
          ],
        ),
      ),
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
        // HTML `.login-row` renders "Вже є акаунт? &nbsp;<a>" — the small gap
        // between prompt and link. The button now has zero padding, so the gap
        // is supplied here. AppSpacing.xxs == 4 ≈ the "&nbsp;" + trailing space.
        const SizedBox(width: AppSpacing.xxs),
        TextButton(
          key: const Key('btn-go-to-login'),
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: BrandColors.camel,
            disabledForegroundColor: BrandColors.camel,
            // A11y + alignment: symmetric vertical padding centres the "Увійти"
            // text within its ~33px hit box (13px line + 8 + 8 = 33), so it
            // shares the same vertical centre/baseline as the centred prompt
            // "Вже є акаунт?". The total box height is unchanged from the prior
            // 2 + 14 split, so the row height, the prompt position, and the gap
            // above the row all stay put — only the text moves down into
            // alignment. shrinkWrap keeps the padding exact so Material's own
            // box never re-inflates the row (ui-ux-pro-max `touch-target-size`).
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: const Size(0, 0),
            padding: const EdgeInsets.symmetric(vertical: 8),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          child: Text(l10n.registerSignIn),
        ),
      ],
    );
  }
}
