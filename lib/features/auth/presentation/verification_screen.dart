// Phase 2.11 — Email Verification Screen.
//
// SOURCE OF TRUTH: docs/signup-designs/verification-page.html
// Every visible element — copy, hex colours, font sizes, spacing, icon paths —
// is transcribed literally from that file. No paraphrasing; non-functional
// decorative elements (progress row, email icon) are rendered in full.
//
// Design tokens (locked — ARCHITECTURE-mobile.md § 9):
//   Glass card radius : BorderRadius.all(Radius.circular(22))   (_kCardRadius)
//   Glass card blur   : ImageFilter.blur(sigmaX:20, sigmaY:20)  (1 per screen max)
//   Glass card fill   : Color(0x11FFFFFF)
//   Input radius      : BorderRadius.all(Radius.circular(12))   (_kInputRadius)
//   Input fill        : Color(0x12FFFFFF)
//   CTA height        : 52 dp
//   CTA radius        : BorderRadius.all(Radius.circular(14))   (_kCtaRadius)
//   CTA gradient      : [Color(0xFF4A2E10), Color(0xFF6A4A28), Color(0xFF8A6840)]
//   CTA pattern       : DecoratedBox → ClipRRect → Material(transparent) → InkWell
//   Auth background   : AuthGradientBackground CustomPainter (Bayer dithering)
//   OTP boxes         : same input radius (12) and fill (white 7%) as inputs
//
// Render-budget rules:
//   - Exactly ONE BackdropFilter (the glass card). The monogram uses fill only.
//   - const constructors wherever possible.
//   - Timer callback updates only _secondsLeft — minimal rebuild scope.
//
// Widget test keys:
//   Key('otp-box-0') … Key('otp-box-5') — 6 OTP digit TextFields
//   Key('btn-verify')                   — CTA "Підтвердити" button
//   Key('btn-resend')                   — resend link (enabled when timer = 0)
//   Key('btn-back')                     — "← Повернутись назад" link

import 'dart:async';
import 'dart:developer';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../../core/errors/failures.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/widgets/auth_scaffold.dart';
import 'auth_notifier.dart';

// ---------------------------------------------------------------------------
// Static style constants — literal CSS values from verification-page.html.
// ---------------------------------------------------------------------------

/// verification-page.html .glass-card { border-radius: 22px }
const _kCardRadius = BorderRadius.all(Radius.circular(22));

/// verification-page.html .otp-box / input { border-radius: 12px }
const _kInputRadius = BorderRadius.all(Radius.circular(12));

/// verification-page.html .cta-btn { border-radius: 14px }
const _kCtaRadius = BorderRadius.all(Radius.circular(14));

/// verification-page.html .monogram { border-radius: 10px }
const _kMonogramRadius = BorderRadius.all(Radius.circular(10));

/// OTP countdown duration in seconds (1:30 = 90 s).
const _kResendCooldownSeconds = 90;

/// Number of OTP digits.
const _kOtpLength = 6;

// ---------------------------------------------------------------------------
// OTP box borders — literal CSS rgba values from verification-page.html.
// ---------------------------------------------------------------------------

/// Default: border: 1px solid rgba(255,255,255,0.1)
const _kOtpBorderDefault = OutlineInputBorder(
  borderRadius: _kInputRadius,
  borderSide: BorderSide(color: Color(0x1AFFFFFF), width: 1),
);

/// Focused: border-color: rgba(184,154,122,0.55)
const _kOtpBorderFocused = OutlineInputBorder(
  borderRadius: _kInputRadius,
  borderSide: BorderSide(color: Color(0x8CB89A7A), width: 1.5),
);

/// Filled: border-color: rgba(184,154,122,0.35)
const _kOtpBorderFilled = OutlineInputBorder(
  borderRadius: _kInputRadius,
  borderSide: BorderSide(color: Color(0x59B89A7A), width: 1),
);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Email verification screen — Phase 2.11.
///
/// Accepts [email] via the constructor (passed from RegisterScreen via
/// [GoRouter] extra). If no email is available (e.g. deep-link edge case),
/// an empty string is used — the masked display degrades gracefully.
class VerificationScreen extends ConsumerStatefulWidget {
  const VerificationScreen({super.key, required this.email});

  /// The email address that the OTP was sent to, passed as GoRouter extra.
  final String email;

  @override
  ConsumerState<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends ConsumerState<VerificationScreen> {
  // ── Static styles ─────────────────────────────────────────────────────────

  /// .headline em { font-family: Cormorant Garamond; font-style: italic;
  ///               font-size: 1.15em; color: #b89a7a }
  /// Hoisted to a static final to avoid allocating a new TextStyle on every
  /// build frame (PERF MEDIUM-2 fix).
  static final _kAccentStyle = GoogleFonts.cormorantGaramond(
    fontStyle: FontStyle.italic,
    fontWeight: FontWeight.w600,
    fontSize: 29.9, // 1.15 × 26
    color: BrandColors.camel,
    height: 1.22,
  );

  // ── OTP state ────────────────────────────────────────────────────────────

  /// Individual character controllers for each OTP box.
  late final List<TextEditingController> _controllers;

  /// Focus nodes for auto-advance / auto-back behaviour.
  late final List<FocusNode> _focusNodes;

  /// The current 6-char OTP string built from the controllers.
  String get _otp => _controllers.map((c) => c.text).join();

  bool get _isOtpComplete => _otp.length == _kOtpLength;

  // ── Countdown timer ───────────────────────────────────────────────────────

  int _secondsLeft = _kResendCooldownSeconds;
  Timer? _countdownTimer;

  bool get _canResend => _secondsLeft == 0;

  // ── Error state ───────────────────────────────────────────────────────────

  /// Inline error message shown below the OTP row.
  String? _inlineError;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_kOtpLength, (_) => TextEditingController());
    _focusNodes = List.generate(_kOtpLength, (_) => FocusNode());
    _startCountdown();
    if (!kDebugMode) ScreenProtector.preventScreenshotOn();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _countdownTimer?.cancel();
    if (!kDebugMode) ScreenProtector.preventScreenshotOff();
    super.dispose();
  }

  // ── Timer ─────────────────────────────────────────────────────────────────

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _secondsLeft = _kResendCooldownSeconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        _countdownTimer?.cancel();
      }
    });
  }

  String _formatTimer(int seconds) {
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  // ── OTP input handling ────────────────────────────────────────────────────

  void _onOtpChanged(int index, String value) {
    // Track whether any state mutation requires a rebuild.
    var needsRebuild = false;

    // Clear any previous inline error on new input.
    if (_inlineError != null) {
      _inlineError = null;
      needsRebuild = true;
    }

    if (value.isEmpty) {
      // Backspace / delete — move focus back to previous box.
      if (index > 0) _focusNodes[index - 1].requestFocus();
    } else if (value.length == 1) {
      // Single digit entered — advance to next box.
      if (index < _kOtpLength - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        // Last box — dismiss keyboard.
        _focusNodes[index].unfocus();
      }
      // Re-evaluate CTA enabled state.
      needsRebuild = true;
    } else if (value.length >= _kOtpLength) {
      // Paste of full OTP — distribute across all boxes.
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i < _kOtpLength && i < digits.length; i++) {
        _controllers[i].text = digits[i];
      }
      _focusNodes[_kOtpLength - 1].unfocus();
      needsRebuild = true;
    }

    if (needsRebuild) setState(() {});
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_isOtpComplete) return;
    final l10n = AppLocalizations.of(context);

    try {
      await ref
          .read(authProvider.notifier)
          .verifyEmail(email: widget.email, otp: _otp);

      if (!mounted) return;

      if (kDebugMode) {
        log(
          'Verification screen: navigating to done',
          name: 'auth.verification',
          level: 800,
        );
      }
      context.go(RouteNames.done);
    } catch (e) {
      if (!mounted) return;
      final message = _errorMessage(e, l10n);
      setState(() => _inlineError = message);
    }
  }

  Future<void> _resend() async {
    if (!_canResend) return;
    final l10n = AppLocalizations.of(context);

    // Clear boxes and restart timer optimistically.
    for (final c in _controllers) {
      c.clear();
    }
    _startCountdown();
    _focusNodes[0].requestFocus();

    try {
      await ref.read(authProvider.notifier).resendCode(email: widget.email);

      if (!mounted) return;

      if (kDebugMode) {
        log('Resend code dispatched', name: 'auth.verification', level: 800);
      }
    } catch (e) {
      if (!mounted) return;
      final message = _errorMessage(e, l10n);
      setState(() => _inlineError = message);
    }
  }

  String _errorMessage(Object? error, AppLocalizations l10n) {
    if (error is UnimplementedError) {
      return l10n.verificationServiceUnavailable;
    }
    if (error is Failure) return l10n.verificationError;
    return l10n.verificationServiceUnavailable;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Masks an email address: `anya@example.com` → `a***@example.com`.
  String _maskEmail(String email) {
    final atIdx = email.indexOf('@');
    if (atIdx <= 0) return email;
    final local = email.substring(0, atIdx);
    final domain = email.substring(atIdx);
    if (local.isEmpty) return email;
    return '${local[0]}***$domain';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authProvider);
    final isLoading = authState.isLoading;
    final maskedEmail = _maskEmail(widget.email);

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Shared top geometry — identical to login/register so the brand row
          // never jumps when transitioning between auth screens.
          const SizedBox(height: 24),
          const _VerifBrandRow(key: Key('brand-row')),
          const SizedBox(height: 36),
          _buildHeadline(l10n),
          const SizedBox(height: 0),
          _ProgressRow(
            stepDetails: l10n.progressStepDetails,
            stepVerification: l10n.progressStepVerification,
            stepDone: l10n.progressStepDone,
          ),
          const SizedBox(height: 20),
          _buildGlassCard(l10n, maskedEmail, isLoading),
          const SizedBox(height: 18),
          _buildBackLink(l10n),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Headline block (verification-page.html .screen-header) ─────────────

  Widget _buildHeadline(AppLocalizations l10n) {
    return Padding(
      // verification-page.html .screen-header { padding: 26px 24px 20px }
      // AuthScaffold already provides 16 px horizontal padding; add 8 more.
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // .headline { font-size: 26px; font-weight: 700; color: #fff }
          Text(
            l10n.verificationHeadline,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.22,
            ),
          ),
          // .headline em { font-family: Cormorant Garamond; font-style: italic;
          //                font-size: 1.15em; color: #b89a7a }
          Text(l10n.verificationHeadlineAccent, style: _kAccentStyle),
        ],
      ),
    );
  }

  // ── Glass card (verification-page.html .glass-card) ────────────────────
  //
  // ONE BackdropFilter per screen — the card only. Do not add more.

  Widget _buildGlassCard(
    AppLocalizations l10n,
    String maskedEmail,
    bool isLoading,
  ) {
    return Padding(
      // verification-page.html .glass-card { margin: 0 14px }
      // AuthScaffold already pads 16 px; compensate with -2 px per side.
      padding: const EdgeInsets.symmetric(horizontal: 0),
      child: ClipRRect(
        borderRadius: _kCardRadius,
        child: BackdropFilter(
          // One BackdropFilter per screen (render-budget rule).
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              // verification-page.html rgba(255,255,255,0.065)
              color: const Color(0x11FFFFFF),
              borderRadius: _kCardRadius,
              border: Border.all(
                // rgba(255,255,255,0.1)
                color: const Color(0x1AFFFFFF),
              ),
            ),
            // verification-page.html padding: 24px 18px 22px
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildEmailIconArea(),
                const SizedBox(height: 20),
                _buildCardTitle(l10n),
                const SizedBox(height: 6),
                _buildCardDesc(l10n, maskedEmail),
                const SizedBox(height: 24),
                _buildOtpRow(),
                if (_inlineError != null) ...[
                  const SizedBox(height: 8),
                  _buildInlineError(_inlineError!),
                ],
                const SizedBox(height: 8),
                _buildResendRow(l10n, isLoading),
                const SizedBox(height: 20),
                _buildCtaButton(l10n, isLoading),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Email icon area (verification-page.html .email-icon-wrap) ───────────

  Widget _buildEmailIconArea() {
    return Center(
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          // .email-icon { background: rgba(184,154,122,0.1); border: 1px solid rgba(184,154,122,0.25) }
          color: const Color(0x1AB89A7A),
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          border: Border.all(color: const Color(0x40B89A7A)),
        ),
        child: Center(
          child: CustomPaint(
            size: const Size(28, 28),
            painter: _EnvelopeIconPainter(),
          ),
        ),
      ),
    );
  }

  // ── Card title (verification-page.html .card-title) ────────────────────

  Widget _buildCardTitle(AppLocalizations l10n) {
    return Text(
      l10n.verificationCardTitle,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: 'Manrope',
        fontSize: 15,
        fontWeight: FontWeight.w600,
        // rgba(255,255,255,0.88)
        color: Color(0xE0FFFFFF),
        height: 1.3,
      ),
    );
  }

  // ── Card description (verification-page.html .card-desc) ───────────────

  Widget _buildCardDesc(AppLocalizations l10n, String maskedEmail) {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        // .card-desc { font-size: 12px; color: rgba(255,255,255,0.3) }
        style: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          color: Color(0x4DFFFFFF),
          height: 1.55,
        ),
        children: [
          TextSpan(text: '${l10n.verificationCardDesc}\n'),
          // .card-desc strong { color: rgba(255,255,255,0.55) }
          TextSpan(
            text: maskedEmail,
            style: const TextStyle(
              color: Color(0x8CFFFFFF),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── OTP boxes (verification-page.html .otp-row / .otp-box) ──────────────

  Widget _buildOtpRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_kOtpLength, (i) {
        final isFilled = _controllers[i].text.isNotEmpty;
        return Padding(
          // verification-page.html .otp-row { gap: 10px }
          padding: EdgeInsets.only(right: i < _kOtpLength - 1 ? 10 : 0),
          child: _OtpBox(
            key: Key('otp-box-$i'),
            controller: _controllers[i],
            focusNode: _focusNodes[i],
            isFilled: isFilled,
            semanticIndex: i + 1,
            onChanged: (v) => _onOtpChanged(i, v),
          ),
        );
      }),
    );
  }

  // ── Inline error ─────────────────────────────────────────────────────────

  Widget _buildInlineError(String message) {
    return Semantics(
      liveRegion: true,
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          color: BrandColors.errorRust,
          height: 1.4,
        ),
      ),
    );
  }

  // ── Resend row (verification-page.html .resend-row) ─────────────────────

  Widget _buildResendRow(AppLocalizations l10n, bool isLoading) {
    // Wrap instead of Row prevents horizontal overflow when the countdown
    // string is wide (e.g. "Повторно через 01:24" on narrow test viewports).
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          // "Не отримали?" — .resend-text { color: rgba(255,255,255,0.25) }
          Text(
            l10n.verificationResendPrompt,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              color: Color(0x40FFFFFF),
            ),
          ),
          if (_canResend)
            // Resend link — active when timer = 0
            GestureDetector(
              key: const Key('btn-resend'),
              onTap: isLoading ? null : _resend,
              child: Semantics(
                button: true,
                label: l10n.verificationResendBtn,
                child: Text(
                  l10n.verificationResendBtn,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: BrandColors.camel,
                  ),
                ),
              ),
            )
          else
            // Timer countdown — .timer { color: rgba(255,255,255,0.35) }
            Text(
              l10n.verificationResendTimer(_formatTimer(_secondsLeft)),
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0x59FFFFFF),
              ),
            ),
        ],
      ),
    );
  }

  // ── CTA button (verification-page.html .cta-btn) ─────────────────────────
  // Pattern: DecoratedBox → ClipRRect → Material(transparent) → InkWell

  Widget _buildCtaButton(AppLocalizations l10n, bool isLoading) {
    final enabled = _isOtpComplete && !isLoading;
    return Semantics(
      button: true,
      enabled: enabled,
      label: l10n.verificationConfirmBtn,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 180),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            // verification-page.html --cta-grad: linear-gradient(135deg, …)
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF4A2E10), Color(0xFF6A4A28), Color(0xFF8A6840)],
              stops: [0.0, 0.6, 1.0],
            ),
            borderRadius: _kCtaRadius,
            // verification-page.html box-shadow: 0 4px 24px rgba(58,36,12,0.68)
            boxShadow: [
              BoxShadow(
                color: Color(0xAD3A240C),
                blurRadius: 24,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: _kCtaRadius,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: const Key('btn-verify'),
                onTap: enabled ? _submit : null,
                splashColor: Colors.white10,
                highlightColor: Colors.white10,
                child: SizedBox(
                  height: 52,
                  child: Center(
                    child: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                BrandColors.cream,
                              ),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                l10n.verificationConfirmBtn,
                                style: const TextStyle(
                                  fontFamily: 'Manrope',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  letterSpacing: 0.02 * 15,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // verification-page.html .cta-btn svg (arrow-right)
                              CustomPaint(
                                size: const Size(18, 18),
                                painter: _ArrowRightPainter(),
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

  // ── Back link (verification-page.html .back-row) ─────────────────────────

  Widget _buildBackLink(AppLocalizations l10n) {
    return Center(
      child: GestureDetector(
        key: const Key('btn-back'),
        onTap: () => context.go(RouteNames.register),
        child: Semantics(
          button: true,
          label: l10n.verificationBackBtn,
          child: Text(
            l10n.verificationBackBtn,
            // .back-row a { color: var(--accent); font-weight: 600 }
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: BrandColors.camel,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Progress row — extracted StatelessWidget so timer ticks do NOT rebuild it.
//
// The three label strings are stable for the life of the screen (they come
// from l10n which does not change), so constructing this widget once from
// the parent's build() is correct — subsequent timer ticks bypass this subtree
// entirely (PERF MEDIUM-1 fix).
// ---------------------------------------------------------------------------

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.stepDetails,
    required this.stepVerification,
    required this.stepDone,
  });

  /// Label for step 1 (done).
  final String stepDetails;

  /// Label for step 2 (active — verification).
  final String stepVerification;

  /// Label for step 3 (inactive — done screen).
  final String stepDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 36, 8, 0),
      child: Row(
        children: [
          // Step 1 — done (checkmark, camel-tinted circle)
          _ProgItem(label: stepDetails, state: _ProgState.done),
          // Line between 1 and 2 — done (camel-tinted)
          const _ProgLine(done: true),
          // Step 2 — active ('2', camel filled)
          _ProgItem(
            label: stepVerification,
            state: _ProgState.active,
            number: '2',
          ),
          // Line between 2 and 3 — inactive
          const _ProgLine(done: false),
          // Step 3 — inactive ('3', outlined)
          _ProgItem(label: stepDone, state: _ProgState.inactive, number: '3'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Brand row — identical structure to login/register (verification-page.html
// .brand-row).
// ---------------------------------------------------------------------------

class _VerifBrandRow extends StatelessWidget {
  const _VerifBrandRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // .monogram { width:34; height:34; border-radius:10; backdrop-filter:blur(8) }
        // No BackdropFilter here — uses fill only to stay within the 1-BDF budget.
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
        // .brand-name { font-size:16; font-weight:700; letter-spacing:0.1em }
        const Text(
          'BEAUTICA',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 16,
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
// Progress step indicator.
// ---------------------------------------------------------------------------

enum _ProgState { done, active, inactive }

class _ProgItem extends StatelessWidget {
  const _ProgItem({required this.label, required this.state, this.number});

  final String label;
  final _ProgState state;

  /// Shown inside the circle for active/inactive steps. Null for done steps.
  final String? number;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Circle
        _ProgCircle(state: state, number: number),
        const SizedBox(width: 6),
        // Label
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.07 * 10,
            color: switch (state) {
              // .prog-item.done { color: rgba(255,255,255,0.45) }
              _ProgState.done => const Color(0x73FFFFFF),
              // .prog-item.active { color: rgba(255,255,255,0.85) }
              _ProgState.active => const Color(0xD9FFFFFF),
              // .prog-item.inactive { color: rgba(255,255,255,0.2) }
              _ProgState.inactive => const Color(0x33FFFFFF),
            },
          ),
        ),
      ],
    );
  }
}

class _ProgCircle extends StatelessWidget {
  const _ProgCircle({required this.state, this.number});

  final _ProgState state;
  final String? number;

  @override
  Widget build(BuildContext context) {
    // .prog-num { width:22; height:22; border-radius:50% }
    const size = 22.0;

    return SizedBox(
      width: size,
      height: size,
      child: switch (state) {
        _ProgState.done => Container(
          decoration: const BoxDecoration(
            // .prog-item.done .prog-num { background: rgba(184,154,122,0.22) }
            color: Color(0x38B89A7A),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          // Checkmark icon path from verification-page.html svg
          child: CustomPaint(
            size: const Size(11, 11),
            painter: _CheckmarkPainter(),
          ),
        ),
        _ProgState.active => Container(
          decoration: const BoxDecoration(
            // .prog-item.active .prog-num { background: var(--accent) }
            color: BrandColors.camel,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            number ?? '',
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              // color: var(--prog-color) = #3a2810
              color: Color(0xFF3A2810),
            ),
          ),
        ),
        _ProgState.inactive => Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              // .prog-item.inactive .prog-num { border: 1.5px solid rgba(255,255,255,0.15) }
              color: const Color(0x26FFFFFF),
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            number ?? '',
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              // rgba(255,255,255,0.2)
              color: Color(0x33FFFFFF),
            ),
          ),
        ),
      },
    );
  }
}

// Horizontal connector line between progress steps.
class _ProgLine extends StatelessWidget {
  const _ProgLine({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 1,
        // Horizontal margin matches verification-page.html .prog-line { margin: 0 8px }
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: done
            // .prog-line.done { background: rgba(184,154,122,0.25) }
            ? const Color(0x40B89A7A)
            // .prog-line { background: rgba(255,255,255,0.08) }
            : const Color(0x14FFFFFF),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// OTP single-character input box.
// ---------------------------------------------------------------------------

class _OtpBox extends StatefulWidget {
  const _OtpBox({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isFilled,
    required this.semanticIndex,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isFilled;
  final int semanticIndex;
  final ValueChanged<String> onChanged;

  @override
  State<_OtpBox> createState() => _OtpBoxState();
}

class _OtpBoxState extends State<_OtpBox> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Semantics(
      label: l10n.verificationOtpSemantics(widget.semanticIndex),
      textField: true,
      child: SizedBox(
        // verification-page.html .otp-box { width: 46px; height: 54px }
        width: 46,
        height: 54,
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          // Numeric keyboard — triggers the correct mobile keyboard.
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            // Accept up to 6 digits (for paste), trimmed in onChanged.
            LengthLimitingTextInputFormatter(_kOtpLength),
          ],
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            // Filled: camel; unfilled: white 90%
            color: widget.isFilled
                ? BrandColors.camel
                : const Color(0xE6FFFFFF),
          ),
          // No floating label — box itself is the affordance.
          decoration: InputDecoration(
            filled: true,
            fillColor: widget.focusNode.hasFocus
                // .otp-box.active { background: rgba(184,154,122,0.06) }
                ? const Color(0x0FB89A7A)
                // .otp-box default { background: rgba(255,255,255,0.07) }
                : const Color(0x12FFFFFF),
            contentPadding: EdgeInsets.zero,
            enabledBorder: widget.isFilled
                ? _kOtpBorderFilled
                : _kOtpBorderDefault,
            focusedBorder: _kOtpBorderFocused,
            // Active outer glow ring: 3px spread, camel 12%
            // Implemented via focused box shadow inside InputDecoration
            // by wrapping the Container (see below).
          ),
          // Prevent IME/keyboard from learning OTP digits (security).
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          // Enables SMS autofill on Android and iOS for OTP codes.
          autofillHints: const [AutofillHints.oneTimeCode],
          onChanged: widget.onChanged,
          onTap: () {
            // Select all text on tap so the digit is replaced, not appended.
            widget.controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: widget.controller.text.length,
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Custom painters — vector icons transcribed from verification-page.html SVG.
// ---------------------------------------------------------------------------

/// Envelope icon from verification-page.html .email-icon svg.
///
/// SVG path: rect(2,4,20,16,rx=3) + path("m2 7 10 7 10-7")
/// stroke-width: 1.6, stroke: currentColor (camel #B89A7A), fill: none.
class _EnvelopeIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BrandColors.camel
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Scale factor: SVG viewBox is 24×24, painting into [size] (28×28).
    final sx = size.width / 24;
    final sy = size.height / 24;

    // Rounded rectangle body: x=2,y=4 w=20,h=16 rx=3
    final rrect = RRect.fromLTRBR(
      2 * sx,
      4 * sy,
      22 * sx,
      20 * sy,
      Radius.circular(3 * sx),
    );
    canvas.drawRRect(rrect, paint);

    // Chevron path: m2 7 10 7 10-7
    final path = Path()
      ..moveTo(2 * sx, 7 * sy)
      ..lineTo(12 * sx, 14 * sy)
      ..lineTo(22 * sx, 7 * sy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_EnvelopeIconPainter old) => false;
}

/// Checkmark icon from verification-page.html .prog-item.done svg.
///
/// SVG path: M2 5.5 l2.5 2.5 4.5-4.5 (viewBox 11×11)
/// stroke-width: 2, stroke: camel, fill: none.
class _CheckmarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BrandColors.camel
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Scale into size (11×11 logical).
    final sx = size.width / 11;
    final sy = size.height / 11;

    final path = Path()
      ..moveTo(2 * sx, 5.5 * sy)
      ..lineTo(4.5 * sx, 8 * sy)
      ..lineTo(9 * sx, 3.5 * sy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckmarkPainter old) => false;
}

/// Arrow-right icon from verification-page.html .cta-btn svg.
///
/// SVG path: M4 9h10  M9 4l5 5-5 5 (viewBox 18×18)
/// stroke-width: 2, stroke: white, fill: none.
class _ArrowRightPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final sx = size.width / 18;
    final sy = size.height / 18;

    // Horizontal line: M4 9 h10
    canvas.drawLine(Offset(4 * sx, 9 * sy), Offset(14 * sx, 9 * sy), paint);

    // Arrow head: M9 4 l5 5 -5 5
    final path = Path()
      ..moveTo(9 * sx, 4 * sy)
      ..lineTo(14 * sx, 9 * sy)
      ..lineTo(9 * sx, 14 * sy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ArrowRightPainter old) => false;
}
