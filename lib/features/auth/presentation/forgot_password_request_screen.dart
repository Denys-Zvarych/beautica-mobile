// Phase 2.13 — Forgot Password (request) screen.
//
// SOURCE OF TRUTH: docs/signup-designs/forgot-password-request.html
// Every visible element — copy, hex colours, font sizes, spacing, icon paths —
// is transcribed literally from that file. The HTML stacks BOTH states for
// review (State A "enter email" + State B "generic confirmation"); in the app
// they are the SAME screen swapping between two card states after the user
// taps "Надіслати посилання" (per the HTML header comment). There is NO
// top-left back-arrow chip (removed during review) — the only back affordance
// is the bottom "Повернутись до входу" link.
//
// Design tokens (locked — ARCHITECTURE-mobile.md § 9):
//   Glass card radius : BorderRadius.all(Radius.circular(22))
//   Glass card blur   : ImageFilter.blur(sigmaX:20, sigmaY:20)  (1 per screen)
//   Glass card fill   : Color(0x11FFFFFF)
//   Input radius      : BorderRadius.all(Radius.circular(12))
//   Input fill        : Color(0x12FFFFFF)
//   CTA height        : 52 dp
//   CTA radius        : BorderRadius.all(Radius.circular(14))
//   CTA gradient      : [Color(0xFF4A2E10), Color(0xFF6A4A28), Color(0xFF8A6840)]
//   CTA pattern       : DecoratedBox → ClipRRect → Material(transparent) → InkWell
//   Auth background   : AuthGradientBackground (Warm-Mocha LinearGradient)
//
// Anti-enumeration: the confirmation copy is identical whether or not the
// account exists (the backend always returns a generic 200). The screen shows
// the confirmation state on ANY successful (non-throwing) call.
//
// Render-budget / perf rules (mobile-backlog auth scope):
//   - Exactly ONE BackdropFilter (the glass card); the monogram uses fill only.
//   - All TextStyle / InputDecoration / BoxDecoration / OutlineInputBorder
//     hoisted to static const/final — never allocated per build().
//   - CTA-enable is driven by a ValueListenableBuilder on the email controller
//     so chrome (BackdropFilter, brand row, headline) does NOT rebuild per
//     keystroke.
//   - Plain LinearGradient background (AuthGradientBackground) — no dither.
//
// Widget test keys:
//   Key('forgot-email-field')      — email TextFormField
//   Key('forgot-submit')           — "Надіслати посилання" CTA (State A)
//   Key('forgot-back-to-login')    — bottom back-to-login link (State A)
//   Key('forgot-confirm-back')     — "Повернутись до входу" CTA (State B)
//   Key('forgot-resend')           — "Надіслати ще раз" resend link (State B)

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
import '../../../shared/validators/email_validator.dart';
import '../../../shared/widgets/auth_field_label.dart';
import '../../../shared/widgets/auth_scaffold.dart';
import 'auth_notifier.dart';

// ---------------------------------------------------------------------------
// Static style constants — literal CSS values, allocated once at load.
// ---------------------------------------------------------------------------

const _kCardRadius = BorderRadius.all(Radius.circular(22));
const _kInputRadius = BorderRadius.all(Radius.circular(12));
const _kCtaRadius = BorderRadius.all(Radius.circular(14));
const _kMonogramRadius = BorderRadius.all(Radius.circular(10));
const _kEmblemRadius = BorderRadius.all(Radius.circular(18));

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

/// forgot-password-request.html --cta-grad.
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
      color: Color(0x5B3A240C), // rgba(58,36,12,0.36) — Impeller-tuned
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ],
);

const _kCtaTextStyle = TextStyle(
  color: Colors.white,
  fontSize: 16,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.3,
);

const _kFieldIconColor = Color(0x40FFFFFF); // white ~25%
const _kFieldTextStyle = TextStyle(color: BrandColors.white, fontSize: 16);

/// .helper-note { font-size: 11px; color: rgba(255,255,255,0.28) }.
const _kHelperNoteStyle = TextStyle(
  fontSize: 12.5,
  color: Color(0x47FFFFFF), // white 28%
  height: 1.55,
);

/// .confirm-title { font-size: 16px; font-weight: 600; rgba(255,255,255,0.9) }.
const _kConfirmTitleStyle = TextStyle(
  fontFamily: 'Manrope',
  fontSize: 16,
  fontWeight: FontWeight.w600,
  color: Color(0xE6FFFFFF),
  height: 1.3,
);

/// .confirm-desc { font-size: 13px; color: rgba(255,255,255,0.34); lh 1.65 }.
const _kConfirmDescStyle = TextStyle(
  fontFamily: 'Manrope',
  fontSize: 13.5,
  color: Color(0x57FFFFFF), // white 34%
  height: 1.65,
);

/// .hint-block p { font-size: 11.5px; color: rgba(255,255,255,0.34) }.
const _kHintTextStyle = TextStyle(
  fontFamily: 'Manrope',
  fontSize: 12.5,
  color: Color(0x57FFFFFF),
  height: 1.55,
);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Forgot-password request screen — Phase 2.13.
///
/// Two card states on one screen:
///   A — email entry + "Надіслати посилання" CTA.
///   B — generic anti-enumeration confirmation (envelope ring, spam hint,
///       resend link, "Повернутись до входу" CTA).
class ForgotPasswordRequestScreen extends ConsumerStatefulWidget {
  const ForgotPasswordRequestScreen({super.key});

  @override
  ConsumerState<ForgotPasswordRequestScreen> createState() =>
      _ForgotPasswordRequestScreenState();
}

class _ForgotPasswordRequestScreenState
    extends ConsumerState<ForgotPasswordRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  /// True once a request has succeeded → swap to the confirmation state.
  bool _linkSent = false;

  /// True while a forgot-password request is in flight (drives the CTA spinner
  /// and disables re-submit). Local — the AuthNotifier does not flip the global
  /// session state for this side-effect-only call.
  bool _submitting = false;

  /// Inline error shown under the email field when a genuine transport / server
  /// error occurs (NOT shown for the generic anti-enumeration success).
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    if (!kDebugMode) ScreenProtector.preventScreenshotOn();
  }

  @override
  void dispose() {
    _emailController.dispose();
    if (!kDebugMode) ScreenProtector.preventScreenshotOff();
    super.dispose();
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final email = _emailController.text.trim();
    setState(() {
      _submitting = true;
      _inlineError = null;
    });

    try {
      await ref.read(authProvider.notifier).requestPasswordReset(email);
      if (!mounted) return;
      // Anti-enumeration: ANY successful (non-throwing) call shows the generic
      // confirmation — identical whether or not the account exists.
      setState(() {
        _submitting = false;
        _linkSent = true;
      });
      if (kDebugMode) {
        log(
          'Forgot-password: showing generic confirmation',
          name: 'auth.reset',
          level: 800,
        );
      }
    } catch (e) {
      if (!mounted) return;
      // A real failure (network / 5xx) — surface it inline so the user can
      // retry. Token / email never appear in the message (Failure.userMessage
      // is a fixed localized string).
      final l10n = AppLocalizations.of(context);
      final message = e is Failure ? e.userMessage(context) : l10n.errUnknown;
      setState(() {
        _submitting = false;
        _inlineError = message;
      });
    }
  }

  void _backToLogin() => context.go(RouteNames.login);

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Shared top geometry — identical to login/register so the brand row
          // never jumps when transitioning between auth screens.
          const SizedBox(height: 24),
          const _BrandRow(key: Key('brand-row')),
          const SizedBox(height: 36),
          // Headline swaps between "Забули пароль?" (A) and "Перевірте вашу
          // пошту" (B) — both Manrope 700 + Cormorant Garamond italic accent.
          _Headline(
            line1: _linkSent
                ? l10n.forgotPasswordConfirmHeadline
                : l10n.forgotPasswordHeadline,
            accent: _linkSent
                ? l10n.forgotPasswordConfirmHeadlineAccent
                : l10n.forgotPasswordHeadlineAccent,
            // The sub-text only exists in State A per the mockup.
            subText: _linkSent ? null : l10n.forgotPasswordSubText,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_linkSent)
            _ConfirmationCard(
              l10n: l10n,
              onBackToLogin: _backToLogin,
              onResend: () {
                // "Надіслати ще раз" — return to the entry state so the user
                // can re-confirm / change the email before re-requesting.
                setState(() {
                  _linkSent = false;
                  _inlineError = null;
                });
              },
            )
          else
            _RequestCard(
              formKey: _formKey,
              emailController: _emailController,
              l10n: l10n,
              submitting: _submitting,
              inlineError: _inlineError,
              onSubmit: _submit,
            ),
          const SizedBox(height: 18),
          // State A shows the bottom back-to-login link; State B's back action
          // is the in-card CTA, so the bottom link is hidden there (mockup).
          if (!_linkSent)
            _BackToLoginLink(
              key: const Key('forgot-back-to-login'),
              label: l10n.forgotPasswordBackToLogin,
              onTap: _backToLogin,
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _RequestCard — State A: lock emblem + email field + helper + CTA.
// ---------------------------------------------------------------------------

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.formKey,
    required this.emailController,
    required this.l10n,
    required this.submitting,
    required this.inlineError,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
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
            // .lock-emblem-wrap — 56px camel-tinted rounded box.
            const Center(child: _LockEmblem()),
            const SizedBox(height: 18),
            AuthFieldLabel(l10n.forgotPasswordEmailLabel),
            TextFormField(
              key: const Key('forgot-email-field'),
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              style: _kFieldTextStyle,
              autocorrect: false,
              enableSuggestions: false,
              enabled: !submitting,
              decoration: _decor(
                l10n.forgotPasswordEmailPlaceholder,
                prefixIcon: const Icon(
                  Icons.mail_outline,
                  color: _kFieldIconColor,
                  size: 20,
                ),
              ),
              validator: (v) => validateEmail(v, l10n),
              onFieldSubmitted: (_) => submitting ? null : onSubmit(),
            ),
            // .helper-note { margin-top: 10px }.
            const SizedBox(height: 10),
            Text(l10n.forgotPasswordEmailHelper, style: _kHelperNoteStyle),
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
            // .cta-btn { margin-top: 16px }.
            const SizedBox(height: 16),
            // CTA-enable is driven by the email controller via a
            // ValueListenableBuilder so chrome does not rebuild per keystroke.
            // The button stays tappable while the field is non-empty; the
            // validator gates the actual submit.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: emailController,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                return _MochaCtaButton(
                  buttonKey: const Key('forgot-submit'),
                  label: l10n.forgotPasswordSubmit,
                  isLoading: submitting,
                  onPressed: (submitting || !hasText) ? null : onSubmit,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decor(String placeholder, {Widget? prefixIcon}) =>
      InputDecoration(
        hintText: placeholder,
        prefixIcon: prefixIcon,
        filled: true,
        fillColor: const Color(0x12FFFFFF),
        hintStyle: const TextStyle(color: Color(0x2EFFFFFF)),
        errorStyle: const TextStyle(color: BrandColors.error, fontSize: 12),
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
      );
}

// ---------------------------------------------------------------------------
// _ConfirmationCard — State B: envelope ring + title + desc + hint + CTAs.
// ---------------------------------------------------------------------------

class _ConfirmationCard extends StatelessWidget {
  const _ConfirmationCard({
    required this.l10n,
    required this.onBackToLogin,
    required this.onResend,
  });

  final AppLocalizations l10n;
  final VoidCallback onBackToLogin;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // .confirm-icon-wrap — 72px envelope ring.
          const Center(child: _EnvelopeRing()),
          const SizedBox(height: 22),
          Text(
            l10n.forgotPasswordConfirmTitle,
            textAlign: TextAlign.center,
            style: _kConfirmTitleStyle,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.forgotPasswordConfirmDesc,
            textAlign: TextAlign.center,
            style: _kConfirmDescStyle,
          ),
          const SizedBox(height: 18),
          // .hint-block — faint info row (spam folder + 60-min validity).
          const _HintBlock(),
          const SizedBox(height: 16),
          _MochaCtaButton(
            buttonKey: const Key('forgot-confirm-back'),
            label: l10n.forgotPasswordBackToLogin,
            isLoading: false,
            onPressed: onBackToLogin,
          ),
          // .resend-row { margin-top: 18px }.
          const SizedBox(height: 18),
          _ResendRow(l10n: l10n, onResend: onResend),
        ],
      ),
    );
  }
}

class _HintBlock extends StatelessWidget {
  const _HintBlock();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      // .hint-block { background: rgba(255,255,255,0.04); border:
      // rgba(255,255,255,0.07); border-radius: 14px; padding: 12px 14px }.
      decoration: const BoxDecoration(
        color: Color(0x0AFFFFFF),
        borderRadius: BorderRadius.all(Radius.circular(14)),
        border: Border.fromBorderSide(
          BorderSide(color: Color(0x12FFFFFF), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // .hint-block svg — info circle, camel.
          const Icon(Icons.info_outline, size: 16, color: BrandColors.accent),
          const SizedBox(width: 9),
          Expanded(
            child: Text(l10n.forgotPasswordConfirmHint, style: _kHintTextStyle),
          ),
        ],
      ),
    );
  }
}

class _ResendRow extends StatelessWidget {
  const _ResendRow({required this.l10n, required this.onResend});

  final AppLocalizations l10n;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        // .resend-text { font-size: 12px; color: rgba(255,255,255,0.25) }.
        Text(
          l10n.forgotPasswordResendPrompt,
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 12.5,
            color: Color(0x40FFFFFF),
          ),
        ),
        GestureDetector(
          key: const Key('forgot-resend'),
          onTap: onResend,
          child: Semantics(
            button: true,
            label: l10n.forgotPasswordResendLink,
            child: Text(
              l10n.forgotPasswordResendLink,
              // .resend-link { font-size: 12px; font-weight: 600; camel }.
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: BrandColors.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _LockEmblem — 56px camel-tinted rounded box with a padlock glyph.
// (forgot-password-request.html .lock-emblem)
// ---------------------------------------------------------------------------

class _LockEmblem extends StatelessWidget {
  const _LockEmblem();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: const BoxDecoration(
        // .lock-emblem { background: rgba(184,154,122,0.1); border: 1px
        // solid rgba(184,154,122,0.25) }.
        color: Color(0x1AB89A7A),
        borderRadius: _kEmblemRadius,
        border: Border.fromBorderSide(
          BorderSide(color: Color(0x40B89A7A), width: 1),
        ),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.lock_outline,
        size: 28,
        color: BrandColors.accent,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _EnvelopeRing — 72px radial-glow ring with an envelope glyph.
// (forgot-password-request.html .confirm-ring)
// ---------------------------------------------------------------------------

class _EnvelopeRing extends StatelessWidget {
  const _EnvelopeRing();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        // .confirm-ring radial-gradient approximated with a flat camel tint +
        // ring border + soft glow (single fill, no extra blur layer).
        color: Color(0x14B89A7A),
        border: Border.fromBorderSide(
          BorderSide(color: Color(0x4DB89A7A), width: 1.5),
        ),
        boxShadow: [
          BoxShadow(color: Color(0x24B89A7A), blurRadius: 28, spreadRadius: 2),
        ],
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.mail_outline,
        size: 32,
        color: BrandColors.accent,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _Headline — Manrope 700 line 1 + Cormorant Garamond italic camel accent
// + optional sub-text (forgot-password-request.html .headline / .sub-text).
// ---------------------------------------------------------------------------

class _Headline extends StatelessWidget {
  const _Headline({
    required this.line1,
    required this.accent,
    required this.subText,
  });

  final String line1;
  final String accent;
  final String? subText;

  // .headline { font-size: 26px; font-weight: 700; color: #fff; lh 1.22 }.
  static final _kHeadlineStyle = GoogleFonts.manrope(
    textStyle: const TextStyle(
      color: Colors.white,
      fontSize: 30,
      fontWeight: FontWeight.w700,
      height: 1.22,
    ),
  );

  // .headline em { Cormorant Garamond italic; font-size 1.15em; camel }.
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
      color: Color(0x52FFFFFF), // white 32%
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
        if (subText != null) ...[
          const SizedBox(height: 10),
          Text(subText!, style: _kSubTextStyle),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _BrandRow — monogram B + BEAUTICA (fill-only, no BackdropFilter — keeps the
// 1-BackdropFilter-per-screen budget for the glass card).
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
  const _GlassCard({required this.child});

  final Widget child;

  static final _kBlur = ImageFilter.blur(sigmaX: 20, sigmaY: 20);

  static const _kDecoration = BoxDecoration(
    color: Color(0x11FFFFFF), // rgba(255,255,255,0.065)
    borderRadius: _kCardRadius,
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x1AFFFFFF), width: 1), // white 10%
    ),
  );

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: _kCardRadius,
        child: Stack(
          children: [
            // Blur + fill — no content inside the SaveLayer (crisp text above).
            Positioned.fill(
              child: BackdropFilter(
                filter: _kBlur,
                child: const DecoratedBox(decoration: _kDecoration),
              ),
            ),
            // .glass-card { padding: 22px 18px 20px }.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _MochaCtaButton — DecoratedBox → ClipRRect → Material(transparent) → InkWell.
// Gradient renders unconditionally; a null onPressed only removes the tap.
// ---------------------------------------------------------------------------

class _MochaCtaButton extends StatelessWidget {
  const _MochaCtaButton({
    required this.buttonKey,
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final bool isLoading;
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
                              const Icon(
                                Icons.arrow_forward,
                                color: Colors.white,
                                size: 18,
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
// _BackToLoginLink — bottom centred "← Повернутись до входу" link.
// (forgot-password-request.html .back-row a — Icons.west, NOT a "←" glyph,
// because the Manrope UI font has no U+2190 coverage.)
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
