// Phase 2.13 — Reset Password (set new password) screen.
//
// SOURCE OF TRUTH: docs/signup-designs/forgot-password-reset.html
// The HTML stacks THREE states for review; in the app they are the SAME screen
// driven by a local _ResetState enum:
//   A — new-password form: new-password field + 3 live criteria pills
//       (8+ симв / Цифра / Велика літера, reusing PasswordCriteriaRow) +
//       confirm-password field with inline "Паролі не співпадають" mismatch.
//   B — success: camel check ring, "Пароль оновлено" + italic "Готово" + desc
//       + "Увійти" CTA → /login.
//   C — invalid/expired token: red error ring, "Посилання недійсне або
//       застаріле" + desc + "Запросити нове посилання" CTA → /forgot-password.
//
// The single-use reset token arrives via the [token] route param (parsed from
// the emailed deep link `/reset-password?token=...`). It is NEVER shown to or
// typed by the user. NO auto-login on success — the user is routed to /login.
//
// New-password policy reuses lib/shared/validators/password_validator.dart →
// validateNewPassword (8 / ≥1 digit / ≥1 uppercase) which now matches the
// backend exactly, keeping the validator and the criteria pills in sync.
//
// Design tokens (locked — ARCHITECTURE-mobile.md § 9): see the constants below.
//   Glass card radius 22, blur(20) ×1, fill 0x11FFFFFF; input radius 12, fill
//   0x12FFFFFF; CTA height 52, radius 14, gradient #4A2E10→#6A4A28→#8A6840,
//   pattern DecoratedBox→ClipRRect→Material(transparent)→InkWell;
//   AuthGradientBackground.
//
// Perf rules (mobile-backlog auth scope):
//   - Exactly ONE BackdropFilter (the glass card); monogram is fill-only.
//   - Styles/decorations/borders hoisted to static const/final.
//   - The criteria pills update via a small StatefulWidget listening to the
//     password controller, so the screen chrome does not rebuild per keystroke.
//   - Plain LinearGradient background (no dither painter).
//
// Widget test keys:
//   Key('reset-new-password-field')       — new-password TextFormField
//   Key('reset-confirm-password-field')   — confirm-password TextFormField
//   Key('reset-criteria-row')             — PasswordCriteriaRow
//   Key('reset-toggle-new')               — new-password visibility toggle
//   Key('reset-toggle-confirm')           — confirm-password visibility toggle
//   Key('reset-submit')                   — "Зберегти пароль" CTA (State A)
//   Key('reset-back-to-login')            — bottom back-to-login link (A / C)
//   Key('reset-success-cta')              — "Увійти" CTA (State B)
//   Key('reset-invalid-cta')              — "Запросити нове посилання" CTA (C)

import 'dart:developer';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../../core/errors/failures.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/validators/password_validator.dart';
import '../../../shared/widgets/auth_field_label.dart';
import '../../../shared/widgets/auth_scaffold.dart';
import '../../../shared/widgets/password_criteria_row.dart';
import 'auth_notifier.dart';

// ---------------------------------------------------------------------------
// Local state machine for the screen.
// ---------------------------------------------------------------------------

enum _ResetState { form, success, invalid }

// ---------------------------------------------------------------------------
// Static style constants — literal CSS values, allocated once at load.
// ---------------------------------------------------------------------------

const _kCardRadius = BorderRadius.all(Radius.circular(22));
const _kInputRadius = BorderRadius.all(Radius.circular(12));
const _kCtaRadius = BorderRadius.all(Radius.circular(14));
const _kMonogramRadius = BorderRadius.all(Radius.circular(10));

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
    BoxShadow(color: Color(0x5B3A240C), blurRadius: 16, offset: Offset(0, 4)),
  ],
);

const _kCtaTextStyle = TextStyle(
  color: Colors.white,
  fontSize: 16,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.3,
);

const _kFieldIconColor = Color(0x40FFFFFF);
const _kFieldTextStyle = TextStyle(color: BrandColors.white, fontSize: 16);

/// .state-title { font-size: 22px; font-weight: 700; color: #fff; lh 1.25 }.
const _kStateTitleStyle = TextStyle(
  fontFamily: 'Manrope',
  fontSize: 22,
  fontWeight: FontWeight.w700,
  color: Colors.white,
  height: 1.25,
);

/// .state-desc { font-size: 13px; color: rgba(255,255,255,0.34); lh 1.65 }.
const _kStateDescStyle = TextStyle(
  fontFamily: 'Manrope',
  fontSize: 13.5,
  color: Color(0x57FFFFFF),
  height: 1.65,
);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Reset-password screen — Phase 2.13.
///
/// [token] is the single-use reset token from the emailed deep link, parsed
/// from the `?token=` query parameter by the router. It is never displayed or
/// editable. A missing/empty token still renders the form; the first submit
/// then surfaces the backend's generic 400 as the invalid-link state.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.token});

  /// Single-use reset token from the emailed deep link.
  final String token;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  _ResetState _state = _ResetState.form;
  bool _submitting = false;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    if (!kDebugMode) ScreenProtector.preventScreenshotOn();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    if (!kDebugMode) ScreenProtector.preventScreenshotOff();
    super.dispose();
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _inlineError = null;
    });

    try {
      await ref
          .read(authProvider.notifier)
          .confirmPasswordReset(
            token: widget.token,
            newPassword: _passwordController.text,
          );
      if (!mounted) return;
      // No auto-login — show the success state, user taps "Увійти" to /login.
      // Clear the password fields from memory now that they are no longer
      // needed (in-memory tradeoff accepted, same as register).
      _passwordController.clear();
      _confirmController.clear();
      setState(() {
        _submitting = false;
        _state = _ResetState.success;
      });
      if (kDebugMode) {
        log('Reset-password: success state', name: 'auth.reset', level: 800);
      }
    } on ResetTokenInvalidFailure {
      if (!mounted) return;
      // Generic backend 400 — invalid / used / expired token. Swap to the
      // dedicated recovery state (request a fresh link).
      setState(() {
        _submitting = false;
        _state = _ResetState.invalid;
      });
      if (kDebugMode) {
        log(
          'Reset-password: invalid-token state',
          name: 'auth.reset',
          level: 800,
        );
      }
    } catch (e) {
      if (!mounted) return;
      // Generic retryable error (network / 5xx) — stay on the form, show inline.
      final l10n = AppLocalizations.of(context);
      final message = e is Failure ? e.userMessage(context) : l10n.errUnknown;
      setState(() {
        _submitting = false;
        _inlineError = message;
      });
    }
  }

  void _goToLogin() => context.go(RouteNames.login);

  void _requestNewLink() => context.go(RouteNames.forgotPassword);

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          const _BrandRow(key: Key('brand-row')),
          const SizedBox(height: 36),
          // The headline only renders in the form state; the success / invalid
          // states are self-contained hero cards per the mockup.
          if (_state == _ResetState.form) ...[
            _Headline(
              line1: l10n.resetPasswordHeadline,
              accent: l10n.resetPasswordHeadlineAccent,
              subText: l10n.resetPasswordSubText,
            ),
            const SizedBox(height: AppSpacing.lg),
            _FormCard(
              formKey: _formKey,
              passwordController: _passwordController,
              confirmController: _confirmController,
              l10n: l10n,
              submitting: _submitting,
              inlineError: _inlineError,
              onSubmit: _submit,
            ),
            const SizedBox(height: 18),
            _BackToLoginLink(
              key: const Key('reset-back-to-login'),
              label: l10n.resetPasswordBackToLogin,
              onTap: _goToLogin,
            ),
          ] else if (_state == _ResetState.success) ...[
            const SizedBox(height: 16),
            _SuccessCard(l10n: l10n, onLogin: _goToLogin),
          ] else ...[
            const SizedBox(height: 16),
            _InvalidCard(l10n: l10n, onRequestNewLink: _requestNewLink),
            const SizedBox(height: 18),
            _BackToLoginLink(
              key: const Key('reset-back-to-login'),
              label: l10n.resetPasswordBackToLogin,
              onTap: _goToLogin,
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _FormCard — State A: new-password + criteria pills + confirm + CTA.
// ---------------------------------------------------------------------------

class _FormCard extends StatelessWidget {
  const _FormCard({
    required this.formKey,
    required this.passwordController,
    required this.confirmController,
    required this.l10n,
    required this.submitting,
    required this.inlineError,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final AppLocalizations l10n;
  final bool submitting;
  final String? inlineError;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthFieldLabel(l10n.resetPasswordNewLabel),
            _NewPasswordField(
              controller: passwordController,
              l10n: l10n,
              enabled: !submitting,
            ),
            const SizedBox(height: 14),
            AuthFieldLabel(l10n.resetPasswordConfirmLabel),
            _ConfirmPasswordField(
              controller: confirmController,
              passwordController: passwordController,
              l10n: l10n,
              enabled: !submitting,
              onSubmit: onSubmit,
            ),
            if (inlineError != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  inlineError!,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12.5,
                    color: BrandColors.error,
                    height: 1.4,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            _MochaCtaButton(
              buttonKey: const Key('reset-submit'),
              label: l10n.resetPasswordSubmit,
              isLoading: submitting,
              trailingIcon: Icons.check,
              onPressed: submitting ? null : onSubmit,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _NewPasswordField — password field + live PasswordCriteriaRow.
// Local StatefulWidget so per-keystroke rebuilds are scoped to the pills.
// ---------------------------------------------------------------------------

class _NewPasswordField extends StatefulWidget {
  const _NewPasswordField({
    required this.controller,
    required this.l10n,
    required this.enabled,
  });

  final TextEditingController controller;
  final AppLocalizations l10n;
  final bool enabled;

  @override
  State<_NewPasswordField> createState() => _NewPasswordFieldState();
}

class _NewPasswordFieldState extends State<_NewPasswordField> {
  String _password = '';
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _password = widget.controller.text;
  }

  void _onChanged() {
    final text = widget.controller.text;
    if (text != _password) setState(() => _password = text);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const Key('reset-new-password-field'),
          controller: widget.controller,
          obscureText: _obscure,
          enableSuggestions: false,
          autocorrect: false,
          enableIMEPersonalizedLearning: false,
          enabled: widget.enabled,
          textInputAction: TextInputAction.next,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          style: _kFieldTextStyle,
          decoration: _passwordDecor(
            hint: l10n.resetPasswordNewPlaceholder,
            toggleKey: const Key('reset-toggle-new'),
            obscure: _obscure,
            onToggle: () => setState(() => _obscure = !_obscure),
            l10n: l10n,
          ),
          validator: (v) => validateNewPassword(v, l10n),
        ),
        PasswordCriteriaRow(
          key: const Key('reset-criteria-row'),
          password: _password,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _ConfirmPasswordField — confirm field with "Паролі не співпадають" mismatch.
// ---------------------------------------------------------------------------

class _ConfirmPasswordField extends StatefulWidget {
  const _ConfirmPasswordField({
    required this.controller,
    required this.passwordController,
    required this.l10n,
    required this.enabled,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final TextEditingController passwordController;
  final AppLocalizations l10n;
  final bool enabled;
  final Future<void> Function() onSubmit;

  @override
  State<_ConfirmPasswordField> createState() => _ConfirmPasswordFieldState();
}

class _ConfirmPasswordFieldState extends State<_ConfirmPasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return TextFormField(
      key: const Key('reset-confirm-password-field'),
      controller: widget.controller,
      obscureText: _obscure,
      enableSuggestions: false,
      autocorrect: false,
      enableIMEPersonalizedLearning: false,
      enabled: widget.enabled,
      textInputAction: TextInputAction.done,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: _kFieldTextStyle,
      decoration: _passwordDecor(
        hint: l10n.resetPasswordConfirmPlaceholder,
        toggleKey: const Key('reset-toggle-confirm'),
        obscure: _obscure,
        onToggle: () => setState(() => _obscure = !_obscure),
        l10n: l10n,
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return l10n.errPasswordRequired;
        if (v != widget.passwordController.text) {
          return l10n.errPasswordsMismatch;
        }
        return null;
      },
      onFieldSubmitted: (_) => widget.enabled ? widget.onSubmit() : null,
    );
  }
}

/// Shared InputDecoration for the two password fields (lock prefix + toggle).
InputDecoration _passwordDecor({
  required String hint,
  required Key toggleKey,
  required bool obscure,
  required VoidCallback onToggle,
  required AppLocalizations l10n,
}) => InputDecoration(
  hintText: hint,
  prefixIcon: const Icon(Icons.lock_outline, color: _kFieldIconColor, size: 20),
  suffixIcon: IconButton(
    key: toggleKey,
    icon: Icon(
      obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      color: const Color(0x47FFFFFF),
      size: 20,
      semanticLabel: obscure
          ? l10n.showPasswordSemanticLabel
          : l10n.hidePasswordSemanticLabel,
    ),
    onPressed: onToggle,
  ),
  filled: true,
  fillColor: const Color(0x12FFFFFF),
  hintStyle: const TextStyle(color: Color(0x2EFFFFFF)),
  errorStyle: const TextStyle(color: BrandColors.error, fontSize: 12),
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  border: _kInputBorderDefault,
  enabledBorder: _kInputBorderDefault,
  focusedBorder: _kInputBorderFocused,
  errorBorder: _kInputBorderError,
  focusedErrorBorder: _kInputBorderFocusedError,
  isDense: true,
);

// ---------------------------------------------------------------------------
// _SuccessCard — State B: camel check ring + title + italic sub + desc + CTA.
// ---------------------------------------------------------------------------

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({required this.l10n, required this.onLogin});

  final AppLocalizations l10n;
  final VoidCallback onLogin;

  // .state-sub { Cormorant Garamond italic; font-size 18px; camel }.
  static final _kSubStyle = GoogleFonts.cormorantGaramond(
    textStyle: const TextStyle(
      color: BrandColors.accent,
      fontSize: 19,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w600,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      // .glass-card (state B) { padding: 34px 22px 28px }.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: _HeroRing(ok: true)),
          const SizedBox(height: 24),
          Text(
            l10n.resetPasswordSuccessTitle,
            textAlign: TextAlign.center,
            style: _kStateTitleStyle,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.resetPasswordSuccessSub,
            textAlign: TextAlign.center,
            style: _kSubStyle,
          ),
          const SizedBox(height: 14),
          Text(
            l10n.resetPasswordSuccessDesc,
            textAlign: TextAlign.center,
            style: _kStateDescStyle,
          ),
          const SizedBox(height: 16),
          _MochaCtaButton(
            buttonKey: const Key('reset-success-cta'),
            label: l10n.resetPasswordSuccessCta,
            isLoading: false,
            trailingIcon: Icons.arrow_forward,
            onPressed: onLogin,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _InvalidCard — State C: red error ring + title + desc + recovery CTA.
// ---------------------------------------------------------------------------

class _InvalidCard extends StatelessWidget {
  const _InvalidCard({required this.l10n, required this.onRequestNewLink});

  final AppLocalizations l10n;
  final VoidCallback onRequestNewLink;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: _HeroRing(ok: false)),
          const SizedBox(height: 24),
          Text(
            l10n.resetPasswordInvalidTitle,
            textAlign: TextAlign.center,
            style: _kStateTitleStyle,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.resetPasswordInvalidDesc,
            textAlign: TextAlign.center,
            style: _kStateDescStyle,
          ),
          const SizedBox(height: 18),
          _MochaCtaButton(
            buttonKey: const Key('reset-invalid-cta'),
            label: l10n.resetPasswordInvalidCta,
            isLoading: false,
            trailingIcon: Icons.refresh,
            onPressed: onRequestNewLink,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _HeroRing — 84px success (camel check) / error (rust warning) ring.
// (forgot-password-reset.html .hero-ring.ok / .hero-ring.bad)
// ---------------------------------------------------------------------------

class _HeroRing extends StatelessWidget {
  const _HeroRing({required this.ok});

  final bool ok;

  @override
  Widget build(BuildContext context) {
    final ringColor = ok ? BrandColors.accent : BrandColors.error;
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ok ? const Color(0x14B89A7A) : const Color(0x14A84040),
        border: Border.fromBorderSide(
          BorderSide(color: ringColor.withValues(alpha: 0.32), width: 1.5),
        ),
        boxShadow: [
          BoxShadow(
            color: ringColor.withValues(alpha: 0.16),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(
        ok ? Icons.check_rounded : Icons.error_outline,
        size: 36,
        color: ringColor,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _Headline — Manrope 700 line 1 + Cormorant Garamond italic camel accent
// + sub-text (forgot-password-reset.html .headline / .sub-text).
// ---------------------------------------------------------------------------

class _Headline extends StatelessWidget {
  const _Headline({
    required this.line1,
    required this.accent,
    required this.subText,
  });

  final String line1;
  final String accent;
  final String subText;

  static final _kHeadlineStyle = GoogleFonts.manrope(
    textStyle: const TextStyle(
      color: Colors.white,
      fontSize: 30,
      fontWeight: FontWeight.w700,
      height: 1.22,
    ),
  );

  static final _kAccentStyle = GoogleFonts.cormorantGaramond(
    textStyle: const TextStyle(
      color: BrandColors.accent,
      fontSize: 34,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w400,
      height: 1.22,
    ),
  );

  static final _kSubTextStyle = GoogleFonts.manrope(
    textStyle: const TextStyle(
      color: Color(0x52FFFFFF),
      fontSize: 15,
      height: 1.55,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(line1, style: _kHeadlineStyle),
        Text(accent, style: _kAccentStyle),
        const SizedBox(height: 10),
        Text(subText, style: _kSubTextStyle),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _BrandRow — fill-only monogram + BEAUTICA (no BackdropFilter).
// ---------------------------------------------------------------------------

class _BrandRow extends StatelessWidget {
  const _BrandRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(
            color: Color(0x1AFFFFFF),
            borderRadius: _kMonogramRadius,
            border: Border.fromBorderSide(BorderSide(color: Color(0x33FFFFFF))),
          ),
          alignment: Alignment.center,
          child: const Text(
            // ignore: no_raw_ui_strings
            // Brand identity monogram — not localised copy (mobile-backlog §5).
            'B',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xF2FFFFFF),
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          // ignore: no_raw_ui_strings
          // Brand wordmark — not localised copy (mobile-backlog §5).
          'BEAUTICA',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xEBFFFFFF),
            letterSpacing: 1.6,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _GlassCard — the single BackdropFilter glass card for this screen.
// ---------------------------------------------------------------------------

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, this.padding});

  final Widget child;

  /// Optional override for the card padding (state B/C use a larger inset per
  /// the mockup `padding: 34px 22px 28px`).
  final EdgeInsets? padding;

  static final _kBlur = ImageFilter.blur(sigmaX: 20, sigmaY: 20);

  static const _kDecoration = BoxDecoration(
    color: Color(0x11FFFFFF),
    borderRadius: _kCardRadius,
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x1AFFFFFF), width: 1),
    ),
  );

  static const _kDefaultPadding = EdgeInsets.fromLTRB(
    AppSpacing.md,
    AppSpacing.lg,
    AppSpacing.md,
    AppSpacing.md,
  );

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: _kCardRadius,
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: _kBlur,
                child: const DecoratedBox(decoration: _kDecoration),
              ),
            ),
            Padding(padding: padding ?? _kDefaultPadding, child: child),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _MochaCtaButton — DecoratedBox → ClipRRect → Material(transparent) → InkWell.
// ---------------------------------------------------------------------------

class _MochaCtaButton extends StatelessWidget {
  const _MochaCtaButton({
    required this.buttonKey,
    required this.label,
    required this.isLoading,
    required this.trailingIcon,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final bool isLoading;
  final IconData trailingIcon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 180),
        child: DecoratedBox(
          decoration: _kCtaDecoration,
          child: ClipRRect(
            borderRadius: _kCtaRadius,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: buttonKey,
                onTap: enabled ? onPressed : null,
                splashColor: const Color(0x14FFFFFF),
                highlightColor: const Color(0x0AFFFFFF),
                child: SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: Center(
                    child: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                BrandColors.white,
                              ),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(label, style: _kCtaTextStyle),
                              const SizedBox(width: 8),
                              Icon(trailingIcon, color: Colors.white, size: 18),
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
// _BackToLoginLink — bottom centred "← Повернутись до входу" link.
// ---------------------------------------------------------------------------

class _BackToLoginLink extends StatelessWidget {
  const _BackToLoginLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: BrandColors.accent,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.west,
              size: 15,
              color: BrandColors.accent.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: BrandColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
