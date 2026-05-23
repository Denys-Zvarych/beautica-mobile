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
//   Auth background   : AuthGradientBackground (Warm-Mocha LinearGradient)
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
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../../core/errors/failures.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/util/mask_email.dart';
import '../../../shared/widgets/auth_scaffold.dart';
import '../../master/data/master_repository.dart';
import '../../salon/data/salon_repository.dart';
import '../domain/user_role.dart';
import '../state/register_draft_notifier.dart';
import 'auth_notifier.dart';
import 'widgets/registration_progress.dart';

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
// OTP sizing tokens — Phase 2.16 migration to the new --otp-* HTML tokens.
//
// SOURCE OF TRUTH: docs/signup-designs/verification-page.html  :root vars
// (2026-05-20 redesign). Default sizing on phones > 340 dp:
//   --otp-box:    42 px  →  [OtpTokens.boxWidth]
//   --otp-height: 52 px  →  [OtpTokens.boxHeight]
//   --otp-gap:     8 px  →  [OtpTokens.gap]
//   font-size:    20 px  →  [OtpTokens.digitFont]
//
// On phones ≤ 340 dp the HTML @media rule swaps to:
//   --otp-box:    36 px / --otp-height: 48 px / --otp-gap: 4 px / font 18 px
//
// Math (default): 6 × 42 + 5 × 8 = 252 + 40 = 292 px ≤ 311 px card content
// area at 375 dp. (Compact: 6 × 36 + 5 × 4 = 236 px ≤ 256 px at 320 dp.)
// ---------------------------------------------------------------------------

abstract final class OtpTokens {
  /// Default (phones > 340 dp).
  static const double boxWidth = 42;
  static const double boxHeight = 52;
  static const double gap = 8;
  static const double digitFont = 20;

  /// Compact tokens used when `MediaQuery.size.width <= 340`.
  static const double compactBoxWidth = 36;
  static const double compactBoxHeight = 48;
  static const double compactGap = 4;
  static const double compactDigitFont = 18;

  /// Breakpoint at which the layout switches to the compact tokens.
  /// Matches the HTML `@media (max-width: 340px)` rule.
  static const double compactBreakpoint = 340;
}

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
    color: BrandColors.accent,
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

  /// True once OTP verification has succeeded and a session token exists.
  ///
  /// Defect 8 — the provider profile/salon save (auth-required) runs HERE,
  /// after verification, not on Step 3 (where there is no token yet). If that
  /// save throws, the account is already verified, so a re-tap must NOT re-run
  /// `verifyEmail` (the code is consumed) — it should retry only the save. This
  /// flag drives that branch in [_submit].
  bool _emailVerified = false;

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
    _startTickerIfStopped();
  }

  /// Ensures the periodic 1-second ticker is running so [_secondsLeft] can
  /// drain to zero. Does NOT reset [_secondsLeft] — the caller is responsible
  /// for setting the starting value before invoking this helper.
  ///
  /// Used by the throttle-aware resend catch (M-Sec-1): when the server
  /// returns 429 with `retryAfterSeconds`, the existing timer may have already
  /// drained to 0 and been cancelled. We bump `_secondsLeft` to the server
  /// value and call this to restart the periodic tick without clobbering it
  /// back to the 90-second default.
  void _startTickerIfStopped() {
    if (_countdownTimer?.isActive ?? false) return;
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
      // Skip re-verification when the code was already accepted but the
      // post-verification provider save failed (Defect 8 retry path): the OTP
      // is consumed, so only retry the save.
      if (!_emailVerified) {
        await ref
            .read(authProvider.notifier)
            .verifyEmail(email: widget.email, otp: _otp);
        if (!mounted) return;
        _emailVerified = true;
      }

      // Defect 8 — a session token now exists, so persist the provider's
      // locality/address that was stashed in the draft on Step 3. This is the
      // FIRST point the auth-required PATCH /independent-masters/me and
      // POST /salons calls can succeed. A failure here surfaces a real inline
      // error (not silent) and keeps the user on this screen so they can retry.
      await _saveProviderProfile(l10n);
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

  /// Persists the provider's locality/address after verification.
  ///
  /// Reads the stashed Step 3 slice from the keepAlive register draft and calls
  /// the role-appropriate endpoint:
  ///   INDEPENDENT_MASTER → PATCH /independent-masters/me
  ///   SALON_OWNER        → POST  /salons
  ///   CLIENT             → no provider profile; locality rode along in the
  ///                        register body — nothing to save.
  ///
  /// Rethrows the typed [Failure] on error so [_submit]'s catch surfaces it as
  /// a real inline message (Defect 8 — never silent).
  Future<void> _saveProviderProfile(AppLocalizations l10n) async {
    final draft = ref.read(registerDraftProvider);
    // No draft (e.g. deep-link straight to /verification) or no city selected →
    // nothing to persist. CLIENT also has no provider profile.
    if (draft == null) return;
    final cityId = draft.cityId;
    if (cityId == null || cityId.isEmpty) return;

    final districtId = draft.districtId;

    switch (draft.role) {
      case UserRole.independentMaster:
        await ref
            .read(masterRepositoryProvider)
            .updateLocality(
              cityId: cityId,
              districtId: districtId,
              street: draft.street,
              buildingNo: draft.buildingNo,
              locationNote: draft.locationNote,
            );
      case UserRole.salonOwner:
        await ref
            .read(salonRepositoryProvider)
            .create(
              dto: SalonCreateDto(
                name: draft.salonName,
                cityId: cityId,
                districtId: districtId,
                street: draft.street,
                buildingNo: draft.buildingNo,
                locationNote: draft.locationNote,
              ),
            );
      case UserRole.client:
      case UserRole.salonAdmin:
      case UserRole.salonMaster:
        // No provider profile to persist for these roles.
        return;
    }
  }

  Future<void> _resend() async {
    if (!_canResend) return;
    final l10n = AppLocalizations.of(context);

    // M-Sec-1 (2026-05-20): Side-effects (clearing OTP boxes, restarting the
    // countdown, moving focus, clearing the inline error) MUST fire AFTER the
    // await succeeds — never before. Doing them optimistically meant a 429
    // ResendThrottledFailure (server still throttling) would silently wipe
    // the user's typed digits and reset the timer to 90 s — possibly SHORTER
    // than the server's retryAfterSeconds, allowing a second tap before the
    // server is ready.
    try {
      await ref.read(authProvider.notifier).resendCode(email: widget.email);

      if (!mounted) return;

      // Success path — now we may safely clear the OTP boxes, reset the
      // inline error, restart the full 90 s timer, and move focus.
      for (final c in _controllers) {
        c.clear();
      }
      setState(() => _inlineError = null);
      _startCountdown();
      _focusNodes[0].requestFocus();

      if (kDebugMode) {
        log('Resend code dispatched', name: 'auth.verification', level: 800);
      }
    } on ResendThrottledFailure catch (throttle) {
      if (!mounted) return;
      // Adopt the server's retryAfterSeconds. We take the max of the current
      // local timer and the server value so a malformed 0 from the body
      // cannot SHORTEN an already-running cooldown. OTP digits are NOT
      // cleared — the request never consumed a slot.
      setState(() {
        _secondsLeft = math.max(_secondsLeft, throttle.retryAfterSeconds);
        _inlineError = throttle.userMessage(context);
      });
      // The periodic timer may have already drained to 0 and cancelled itself
      // (btn-resend is only tappable when _secondsLeft == 0). Restart the
      // ticker so the new _secondsLeft can drain back to 0 organically.
      _startTickerIfStopped();
    } catch (e) {
      if (!mounted) return;
      // Non-throttle failures (NetworkFailure / ServerFailure / etc.) — show
      // the inline error but do NOT restart the timer; the user should be
      // able to retry immediately.
      final message = _errorMessage(e, l10n);
      setState(() => _inlineError = message);
    }
  }

  String _errorMessage(Object? error, AppLocalizations l10n) {
    // UnimplementedError historically signalled "endpoint not yet live" while
    // the backend stub was in place. Phase 1.5/1.6 ship the real endpoints so
    // this branch is now a defensive fallback only (e.g. a future repository
    // path that has not been wired yet).
    if (error is UnimplementedError) {
      return l10n.verificationServiceUnavailable;
    }
    if (error is Failure) {
      // Each Failure subclass knows its own user-facing message via
      // userMessage(context) — VerificationFailure handles the three typed
      // verify-email codes; ResendThrottledFailure substitutes the
      // retry-after seconds.
      return error.userMessage(context);
    }
    return l10n.verificationServiceUnavailable;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authProvider);
    final isLoading = authState.isLoading;
    final maskedEmail = maskEmail(widget.email);

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
          const SizedBox(height: 28),
          // Phase 2.16 — 4-dot progress (Акаунт / Профіль / Верифікація / Готово).
          // 2026-05-20 design refresh: dot 3 is active; the under-dot label
          // "Верифікація" is supplied via [activeStepLabel] (no per-pill
          // label rendering anymore).
          RegistrationProgress(
            key: const Key('registration-progress'),
            currentStep: RegistrationStep.verification,
            activeStepLabel: l10n.registerProgressVerification,
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
            ),
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
  //
  // Phase 2.16 — tokenised sizing via [OtpTokens]. Default 42×52×8, swapping
  // to 36×48×4 on phones ≤ 340 dp. Matches the HTML --otp-* :root vars.

  Widget _buildOtpRow() {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width <= OtpTokens.compactBreakpoint;
    final boxWidth = isCompact ? OtpTokens.compactBoxWidth : OtpTokens.boxWidth;
    final boxHeight = isCompact
        ? OtpTokens.compactBoxHeight
        : OtpTokens.boxHeight;
    final gap = isCompact ? OtpTokens.compactGap : OtpTokens.gap;
    final digitFont = isCompact
        ? OtpTokens.compactDigitFont
        : OtpTokens.digitFont;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_kOtpLength, (i) {
        final isFilled = _controllers[i].text.isNotEmpty;
        return Padding(
          padding: EdgeInsets.only(right: i < _kOtpLength - 1 ? gap : 0),
          child: _OtpBox(
            key: Key('otp-box-$i'),
            controller: _controllers[i],
            focusNode: _focusNodes[i],
            isFilled: isFilled,
            semanticIndex: i + 1,
            boxWidth: boxWidth,
            boxHeight: boxHeight,
            digitFont: digitFont,
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
          color: BrandColors.error,
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
                    color: BrandColors.accent,
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
                                BrandColors.white,
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
        // Phase 2.16 — back from verification returns to the wizard. Step 3
        // (Phase 2.19) is the natural previous step; until that ships, the
        // placeholder still loads inside the wizard shell.
        onTap: () => context.go(RouteNames.registerStep3),
        child: Semantics(
          button: true,
          label: l10n.verificationBackBtn,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icons.west is a Material icon (always paints). The Manrope UI
              // font has no glyph for U+2190 (←), so a literal "← " baked into
              // the ARB rendered a blank tofu square. This mirrors the
              // already-correct back-link pattern in RegisterFlowShell.
              Icon(
                Icons.west,
                size: 15,
                color: BrandColors.accent.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 6),
              Text(
                l10n.verificationBackBtn,
                // .back-row a { color: var(--accent); font-weight: 600 }
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
// OTP single-character input box.
// ---------------------------------------------------------------------------

class _OtpBox extends StatefulWidget {
  const _OtpBox({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isFilled,
    required this.semanticIndex,
    required this.boxWidth,
    required this.boxHeight,
    required this.digitFont,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isFilled;
  final int semanticIndex;
  final double boxWidth;
  final double boxHeight;
  final double digitFont;
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
        // Phase 2.16 — tokenised sizing via [OtpTokens] (42×52 default,
        // 36×48 compact). See the OtpTokens block at the top of this file.
        width: widget.boxWidth,
        height: widget.boxHeight,
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
            fontSize: widget.digitFont,
            fontWeight: FontWeight.w700,
            // Filled: camel; unfilled: white 90%
            color: widget.isFilled
                ? BrandColors.accent
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
      ..color = BrandColors.accent
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
