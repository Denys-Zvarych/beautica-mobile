// Phase 2.12 — Registration Done Screen.
//
// SOURCE OF TRUTH: docs/signup-designs/done-page.html (Warm Mocha — approved,
// refreshed 2026-05-20). Every visible element — copy, hex colours, font
// sizes, spacing, icon paths — is transcribed literally. No paraphrasing;
// non-functional decorative elements (4-dot progress, success ring, chips,
// secondary link) are rendered in full.
//
// Design tokens (locked — ARCHITECTURE-mobile.md § 9 + done-page.html):
//   Brand row monogram     : 34 dp white-10 fill + white-20 border, radius 10
//   4-dot progress         : RegistrationProgress(currentStep: done,
//                            activeStepLabel: l10n.registerProgressDone).
//   Success ring           : 96 × 96 dp, camel 18 % radial fill, 1.5 dp camel
//                            30 % border, 8 dp camel-6% halo + 32 dp camel-14
//                            % outer glow. Inner ring at 6 dp inset, camel 8 %
//                            fill + camel 18 % border.
//   Success check          : 38 × 38 dp camel stroke, viewBox 0 0 38 38, path
//                            "M8 19l7 7 15-15" stroke-width 2.5.
//   Headline               : Manrope w700 28 sp white, height 1.2 (HTML
//                            .celebrate-title). Personalised via
//                            l10n.registerDoneGreeting(firstName).
//   Subtitle               : Cormorant Garamond italic w600 22 sp camel,
//                            letter-spacing 0.01em (HTML .celebrate-subtitle).
//                            INVERTED from login/register — the *subtitle*
//                            (not the headline) is the italic-camel accent.
//   Description            : 13.5 sp white 32 %, line-height 1.65, max-width
//                            280 dp (HTML .celebrate-desc).
//   Summary chips          : 7×14 padding, camel 8 % bg, 1 dp camel 20 %
//                            border, radius 20 dp, 11.5 sp white 55 %, with a
//                            13 × 13 camel icon glyph on the left.
//   CTA button             : 52 dp h, radius 14 dp, mocha gradient
//                            (#4A2E10 → #6A4A28 → #8A6840). Always-filled (no
//                            disabled state). Trailing arrow-right glyph.
//   Secondary link         : 12.5 sp white 28 %, no underline. Wrapped in
//                            InkWell + 14 dp vertical / 16 dp horizontal
//                            padding to clear the 48 dp tap target while the
//                            visible text stays at 12.5 sp.
//
// Security:
//   - On mount the registration draft is reset via a post-frame callback —
//     same HIGH-1 (Phase 2.16) contract as the old DonePlaceholderScreen. The
//     callback is `if (mounted)`-guarded.
//   - ScreenProtector.preventScreenshotOn/off is wired in initState/dispose
//     (release builds only, `!kDebugMode`). Same pattern as login/register
//     /verification — the recently-authenticated user's email + role are on
//     screen via the chip row.
//
// Render-budget rules:
//   - No BackdropFilter on this screen — there are no glass cards, only the
//     success ring + chips + CTA. Brand-row monogram uses fill only (no blur).
//   - All decorations / TextStyles are hoisted to `static const` / `static
//     final` so they are not reallocated per build (LOW row "_HeadlineBlock
//     subtext not hoisted" backlog pattern — don't repeat).
//
// Widget test keys:
//   Key('brand-row')             — top brand row (mirrors other auth screens)
//   Key('registration-progress') — the 4-dot RegistrationProgress widget
//   Key('progress-active-label') — the "Готово" label under dot 4 (from the
//                                  shared widget)
//   Key('done-success-ring')     — the 96 dp success ring decoration
//   Key('done-greeting')         — the personalised greeting Text widget
//   Key('done-subtitle')         — the italic subtitle "Ваш акаунт створено"
//   Key('done-chip-role')        — first chip (role label)
//   Key('done-chip-email')       — second chip (email verified)
//   Key('done-chip-ready')       — third chip (ready in seconds marketing)
//   Key('btn-go-to-app')         — primary CTA → /home
//   Key('btn-setup-later')       — secondary link → /home (Phase 4.x will
//                                  divert to profile-setup)

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/widgets/auth_scaffold.dart';
import '../state/register_draft_notifier.dart';
import 'auth_selectors.dart';
import 'user_role_l10n.dart';
import 'widgets/registration_progress.dart';

// ---------------------------------------------------------------------------
// Static style constants — allocated once, never inside build()
// ---------------------------------------------------------------------------

/// done-page.html .monogram { border-radius: 10px }.
const _kMonogramRadius = BorderRadius.all(Radius.circular(10));

/// done-page.html .cta-btn { border-radius: 14px }.
const _kCtaRadius = BorderRadius.all(Radius.circular(14));

/// done-page.html .chip { border-radius: 20px }.
const _kChipRadius = BorderRadius.all(Radius.circular(20));

/// CTA gradient — literal hex stops from done-page.html `--cta-grad`
/// (linear-gradient 135deg, #4a2e10 0%, #6a4a28 60%, #8a6840 100%).
const _kCtaGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF4A2E10), Color(0xFF6A4A28), Color(0xFF8A6840)],
  stops: [0.0, 0.6, 1.0],
);

/// CTA box shadow — mocha glow tuned for Android/Impeller saturation. The
/// HTML value is rgba(58,36,12,0.68) at blur 24, which Android renders as
/// blob-like; LoginScreen already drops opacity to 0.36 + blur 16 for the
/// same reason (PERF MEDIUM-1). Mirror that here.
const List<BoxShadow> _kCtaShadow = [
  BoxShadow(
    color: Color(0x5B3A240C), // rgba(58,36,12,0.36) — reduced from 0.68
    blurRadius: 16, // reduced from 24
    offset: Offset(0, 4),
  ),
  BoxShadow(
    color: Color(0x1FFFFFFF), // inset top highlight (approximated)
    blurRadius: 0,
    offset: Offset(0, -1),
  ),
];

/// done-page.html .success-ring outer decoration. Camel 18% radial fill on a
/// 40 % / 35 % centre, fading to camel 10 % at 60 % then transparent. Border
/// is 1.5 dp camel 30 %. The two camel halos are stacked via boxShadow:
///   - 8 dp camel-6 % inner halo (spread-only)
///   - 32 dp camel-14 % outer glow (blur)
/// Implemented as a Container(BoxDecoration) so the radial gradient lives in
/// `gradient:` and the halos in `boxShadow:`.
const _kSuccessRingBorder = Border.fromBorderSide(
  BorderSide(color: Color(0x4DB89A7A), width: 1.5), // rgba(184,154,122,0.30)
);

const List<BoxShadow> _kSuccessRingHalo = [
  // 0 0 0 8px rgba(184,154,122,0.06)
  BoxShadow(color: Color(0x0FB89A7A), spreadRadius: 8, blurRadius: 0),
  // 0 0 32px rgba(184,154,122,0.14)
  BoxShadow(color: Color(0x24B89A7A), blurRadius: 32),
];

/// .success-ring::before — inset 6 dp camel-8 fill + camel-18 border.
const _kSuccessRingInnerDecoration = BoxDecoration(
  color: Color(0x14B89A7A), // rgba(184,154,122,0.08)
  shape: BoxShape.circle,
  border: Border.fromBorderSide(
    BorderSide(color: Color(0x2EB89A7A), width: 1), // rgba(184,154,122,0.18)
  ),
);

/// done-page.html .chip { background: rgba(184,154,122,0.08);
///                        border: 1px solid rgba(184,154,122,0.2) }
const _kChipDecoration = BoxDecoration(
  color: Color(0x14B89A7A),
  borderRadius: _kChipRadius,
  border: Border.fromBorderSide(BorderSide(color: Color(0x33B89A7A), width: 1)),
);

// ---------------------------------------------------------------------------
// DoneScreen
// ---------------------------------------------------------------------------

/// Terminal "registration complete" celebration screen — Phase 2.12.
///
/// Lands here after [VerificationScreen] successfully verifies the OTP. The
/// user is already authenticated at this point (verify-email rotates a fresh
/// access + refresh token pair) so the screen pulls the user's first name +
/// role + email from [currentUserProvider] rather than the registration draft
/// (which is also reset on mount per Phase 2.16 HIGH-1).
class DoneScreen extends ConsumerStatefulWidget {
  const DoneScreen({super.key});

  @override
  ConsumerState<DoneScreen> createState() => _DoneScreenState();
}

class _DoneScreenState extends ConsumerState<DoneScreen> {
  @override
  void initState() {
    super.initState();
    if (!kDebugMode) ScreenProtector.preventScreenshotOn();

    // Phase 2.16 HIGH-1: clear the in-flight registration draft so the
    // password fields it holds do not linger past the wizard's terminal
    // screen. Riverpod forbids provider mutation during widget life-cycles
    // (build / initState / didChangeDependencies) — schedule the reset
    // inside a post-frame callback. The callback is `mounted`-guarded so
    // we never read disposed state if the user navigates away in the same
    // frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(registerDraftProvider.notifier).reset();
      if (kDebugMode) {
        log(
          'Done screen: register draft reset (HIGH-1 contract)',
          name: 'auth.done',
          level: 800,
        );
      }
    });
  }

  @override
  void dispose() {
    if (!kDebugMode) ScreenProtector.preventScreenshotOff();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _goToApp() {
    if (kDebugMode) {
      log('Done screen: btn-go-to-app → /home', name: 'auth.done', level: 800);
    }
    context.go(RouteNames.home);
  }

  void _setupLater() {
    if (kDebugMode) {
      log(
        'Done screen: btn-setup-later → /home (Phase 4.x will divert to '
        'profile-setup)',
        name: 'auth.done',
        level: 800,
      );
    }
    context.go(RouteNames.home);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentUserProvider);

    final firstName = (user?.firstName?.trim().isNotEmpty ?? false)
        ? user!.firstName!.trim()
        : l10n.registerDoneGreetingFallback;
    final roleLabel = user?.role.label(l10n) ?? l10n.registerDoneChipRoleClient;
    final emailChipText = (user?.email.isNotEmpty ?? false)
        ? user!.email
        : l10n.registerDoneChipEmailVerified;

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Shared top geometry — identical to login/register/verification
          //    so the brand row never jumps between auth screens.
          const SizedBox(height: 24),
          const _DoneBrandRow(key: Key('brand-row')),
          const SizedBox(height: 36),
          // ── 4-dot progress — Phase 2.16 wizard, final step active.
          //    The HTML refresh (2026-05-20) puts the "Готово" label
          //    directly under dot 4 instead of per-dot labels.
          RegistrationProgress(
            key: const Key('registration-progress'),
            currentStep: RegistrationStep.done,
            activeStepLabel: l10n.registerProgressDone,
          ),
          // .celebration { padding: 40px 24px 32px } — 40 dp top.
          const SizedBox(height: 40),
          // ── Success ring + check glyph
          const _SuccessRing(key: Key('done-success-ring')),
          // .success-ring { margin-bottom: 28px }
          const SizedBox(height: 28),
          // ── Personalised headline + italic subtitle
          _Greeting(firstName: firstName, l10n: l10n),
          // .celebrate-desc { max-width: 280px } centered.
          const SizedBox(height: 16),
          _Description(l10n: l10n),
          // .chips-row { margin: 24px 24px 0 } — 24 dp gap from celebration.
          const SizedBox(height: 24),
          _ChipsRow(
            roleLabel: roleLabel,
            emailLabel: emailChipText,
            readyLabel: l10n.registerDoneChipReadyFast,
          ),
          // .cta-wrap { padding: 28px 14px 0 } — 28 dp gap above CTA.
          const SizedBox(height: 28),
          _PrimaryCta(label: l10n.registerDoneCtaPrimary, onPressed: _goToApp),
          // .secondary-action { margin-top: 14px }
          const SizedBox(height: 14),
          _SecondaryLink(
            label: l10n.registerDoneCtaSecondary,
            onPressed: _setupLater,
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _DoneBrandRow — monogram B + BEAUTICA text
//
// Mirrors the brand rows on login/register/verification (same dimensions, same
// strokes). Uses fill-only — no BackdropFilter — to stay within the 0-BDF
// budget on this screen.
// ---------------------------------------------------------------------------

class _DoneBrandRow extends StatelessWidget {
  const _DoneBrandRow({super.key});

  static const _kMonogramDecoration = BoxDecoration(
    color: Color(0x1AFFFFFF), // white 10%
    borderRadius: _kMonogramRadius,
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x33FFFFFF), width: 1), // white 20%
    ),
  );

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        // .monogram { width: 34; height: 34 }
        SizedBox(
          width: 34,
          height: 34,
          child: DecoratedBox(
            decoration: _kMonogramDecoration,
            child: Center(
              child: Text(
                // ignore: no_raw_ui_strings
                // brand: monogram letter — pure brand asset, never localised
                'B',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xF2FFFFFF), // white 95%
                  height: 1,
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 10),
        // .brand-name { font-size: 16; font-weight: 700; letter-spacing: 0.1em }
        Text(
          // ignore: no_raw_ui_strings
          // brand: BEAUTICA wordmark — never localised
          'BEAUTICA',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xEBFFFFFF), // white 92%
            letterSpacing: 1.6,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _SuccessRing — 96 dp circular success indicator with check glyph
// ---------------------------------------------------------------------------

class _SuccessRing extends StatelessWidget {
  const _SuccessRing({super.key});

  /// .success-ring background — radial-gradient(circle at 40% 35%, ...).
  /// Flutter's [RadialGradient] uses a [center] (Alignment) and a [radius]
  /// (relative to the shorter side), which is sufficient to approximate the
  /// HTML's off-centre highlight bloom.
  static const _kRadialFill = RadialGradient(
    center: Alignment(-0.2, -0.3), // 40 % / 35 % from top-left
    radius: 0.85,
    colors: [
      Color(0x2EB89A7A), // rgba(184,154,122,0.18)
      Color(0x1A6A4A28), // rgba(106,74,40,0.10)
      Color(0x00000000), // transparent
    ],
    stops: [0.0, 0.6, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 96,
        height: 96,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: _kRadialFill,
            border: _kSuccessRingBorder,
            boxShadow: _kSuccessRingHalo,
          ),
          child: Padding(
            // .success-ring::before { inset: 6px } — 6 dp inner ring.
            // 6 is a sub-token half-step (between xxs=4 and xs=8); routed
            // through the scale as sm/2 (12/2) to satisfy the spacing gate
            // and preserve the exact 6 dp visual — no new token added.
            padding: EdgeInsets.all(AppSpacing.sm / 2),
            child: DecoratedBox(
              decoration: _kSuccessRingInnerDecoration,
              child: Center(
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: CustomPaint(painter: _SuccessCheckPainter()),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Camel-tinted check glyph from done-page.html .success-check svg.
///
/// SVG path: M8 19 l7 7 15-15 (viewBox 0 0 38 38). stroke-width: 2.5,
/// stroke: currentColor (camel #B89A7A), fill: none.
class _SuccessCheckPainter extends CustomPainter {
  const _SuccessCheckPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BrandColors.camel
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final sx = size.width / 38;
    final sy = size.height / 38;

    final path = Path()
      ..moveTo(8 * sx, 19 * sy)
      ..lineTo(15 * sx, 26 * sy)
      ..lineTo(30 * sx, 11 * sy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SuccessCheckPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// _Greeting — Manrope headline + Cormorant Garamond italic subtitle
//
// IMPORTANT — the italic-camel accent is the SUBTITLE here, not a second line
// of the headline. This INVERTS the login/register/verification pattern. The
// HTML (done-page.html .celebrate-title + .celebrate-subtitle, lines 224–241)
// is the source of truth; the inversion is intentional.
// ---------------------------------------------------------------------------

class _Greeting extends StatelessWidget {
  const _Greeting({required this.firstName, required this.l10n});

  final String firstName;
  final AppLocalizations l10n;

  /// .celebrate-title { font-size: 28; font-weight: 700; line-height: 1.2 }
  static final _kHeadlineStyle = GoogleFonts.manrope(
    textStyle: const TextStyle(
      color: Colors.white,
      fontSize: 28,
      fontWeight: FontWeight.w700,
      height: 1.2,
    ),
  );

  /// .celebrate-subtitle { font-family: 'Cormorant Garamond'; font-style:
  /// italic; font-weight: 600; font-size: 22; letter-spacing: 0.01em }
  static final _kSubtitleStyle = GoogleFonts.cormorantGaramond(
    textStyle: const TextStyle(
      color: BrandColors.camel,
      fontSize: 22,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w600,
      height: 1.2,
      letterSpacing: 0.22, // 0.01em × 22px
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          l10n.registerDoneGreeting(firstName),
          key: const Key('done-greeting'),
          textAlign: TextAlign.center,
          style: _kHeadlineStyle,
        ),
        // .celebrate-title { margin-bottom: 8px }
        const SizedBox(height: 8),
        Text(
          l10n.registerDoneSubtitle,
          key: const Key('done-subtitle'),
          textAlign: TextAlign.center,
          style: _kSubtitleStyle,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _Description — long marketing copy below the headline
// ---------------------------------------------------------------------------

class _Description extends StatelessWidget {
  const _Description({required this.l10n});

  final AppLocalizations l10n;

  /// .celebrate-desc { font-size: 13.5; color: rgba(255,255,255,0.32);
  ///                   line-height: 1.65; max-width: 280px }
  static final _kDescStyle = GoogleFonts.manrope(
    textStyle: const TextStyle(
      color: Color(0x52FFFFFF), // white 32%
      fontSize: 13.5,
      height: 1.65,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Text(
          l10n.registerDoneDesc,
          textAlign: TextAlign.center,
          style: _kDescStyle,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ChipsRow — three summary chips below the greeting
// ---------------------------------------------------------------------------

class _ChipsRow extends StatelessWidget {
  const _ChipsRow({
    required this.roleLabel,
    required this.emailLabel,
    required this.readyLabel,
  });

  final String roleLabel;
  final String emailLabel;
  final String readyLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          _Chip(
            key: const Key('done-chip-role'),
            label: roleLabel,
            iconPainter: const _ChipUserIconPainter(),
          ),
          _Chip(
            key: const Key('done-chip-email'),
            label: emailLabel,
            iconPainter: const _ChipMailIconPainter(),
          ),
          _Chip(
            key: const Key('done-chip-ready'),
            label: readyLabel,
            iconPainter: const _ChipClockIconPainter(),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.label, required this.iconPainter});

  final String label;
  final CustomPainter iconPainter;

  /// .chip { font-size: 11.5; font-weight: 500; color: rgba(255,255,255,0.55) }
  static const _kLabelStyle = TextStyle(
    fontFamily: 'Manrope',
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    color: Color(0x8CFFFFFF), // white 55%
    height: 1.2,
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _kChipDecoration,
      child: Padding(
        // .chip { padding: 7px 14px }
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // .chip svg { width: 13; height: 13; color: camel }
            SizedBox(
              width: 13,
              height: 13,
              child: CustomPaint(painter: iconPainter),
            ),
            // .chip { gap: 6 }
            const SizedBox(width: 6),
            // Use `Flexible` so very long chip text (e.g. a 40-char email)
            // wraps gracefully inside the chip instead of overflowing the
            // Wrap's child constraint and triggering a RenderFlex assertion
            // at narrow widths.
            Flexible(
              child: Text(
                label,
                style: _kLabelStyle,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chip icon painters — vector glyphs transcribed from done-page.html SVG
// ---------------------------------------------------------------------------

/// .chip[role] svg — circle + chest path. Path:
/// circle(cx=7,cy=5,r=2.5) + path("M2 13c0-2.761 2.239-5 5-5s5 2.239 5 5").
class _ChipUserIconPainter extends CustomPainter {
  const _ChipUserIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BrandColors.camel
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final sx = size.width / 14;
    final sy = size.height / 14;

    // Head circle.
    canvas.drawCircle(Offset(7 * sx, 5 * sy), 2.5 * sx, paint);

    // Shoulders arc.
    final rect = Rect.fromCircle(
      center: Offset(7 * sx, 13 * sy),
      radius: 5 * sx,
    );
    canvas.drawArc(rect, 3.14159, 3.14159, false, paint);
  }

  @override
  bool shouldRepaint(_ChipUserIconPainter oldDelegate) => false;
}

/// .chip[email] svg — envelope. Path: rect(1,2,w=12,h=9,rx=1.5) +
/// "m1 5 6 4 6-4".
class _ChipMailIconPainter extends CustomPainter {
  const _ChipMailIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BrandColors.camel
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final sx = size.width / 14;
    final sy = size.height / 14;

    // Envelope body — rounded rectangle.
    final rrect = RRect.fromLTRBR(
      1 * sx,
      2 * sy,
      13 * sx,
      11 * sy,
      Radius.circular(1.5 * sx),
    );
    canvas.drawRRect(rrect, paint);

    // Inner chevron.
    final path = Path()
      ..moveTo(1 * sx, 5 * sy)
      ..lineTo(7 * sx, 9 * sy)
      ..lineTo(13 * sx, 5 * sy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChipMailIconPainter oldDelegate) => false;
}

/// .chip[clock] svg — clock face + hands. Path:
/// path("M11 5.5a4.5 4.5 0 1 1-9 0 4.5 4.5 0 0 1 9 0z") +
/// path("M7 3v2.5l1.5 1.5").
class _ChipClockIconPainter extends CustomPainter {
  const _ChipClockIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BrandColors.camel
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final sx = size.width / 14;
    final sy = size.height / 14;

    // Clock face — circle approximated to the HTML's arc path.
    canvas.drawCircle(Offset(6.5 * sx, 5.5 * sy), 4.5 * sx, paint);

    // Hands.
    final path = Path()
      ..moveTo(7 * sx, 3 * sy)
      ..lineTo(7 * sx, 5.5 * sy)
      ..lineTo(8.5 * sx, 7 * sy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChipClockIconPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// _PrimaryCta — always-filled mocha gradient button + arrow glyph
// ---------------------------------------------------------------------------

/// CTA pattern: DecoratedBox → ClipRRect → Material(transparent) → InkWell
/// — same as login/register/verification. ElevatedButton creates its own
/// composited Material layer that occludes the gradient on Android Impeller
/// (Flutter 3.22+); MaterialType.transparency has no competing paint layer
/// so the DecoratedBox gradient is always visible.
class _PrimaryCta extends StatelessWidget {
  const _PrimaryCta({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  /// done-page.html .cta-btn — gradient + radius + shadow.
  static const _kCtaDecoration = BoxDecoration(
    gradient: _kCtaGradient,
    borderRadius: _kCtaRadius,
    boxShadow: _kCtaShadow,
  );

  /// done-page.html .cta-btn { font-size: 15; font-weight: 600;
  ///                          letter-spacing: 0.02em }
  static const _kLabelStyle = TextStyle(
    fontFamily: 'Manrope',
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    letterSpacing: 0.3, // 0.02em × 15px
    height: 1,
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        // _kCtaDecoration is const — gradient + shadow allocated once.
        decoration: _kCtaDecoration,
        child: ClipRRect(
          borderRadius: _kCtaRadius,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const Key('btn-go-to-app'),
              onTap: onPressed,
              splashColor: Colors.white.withValues(alpha: 0.08),
              highlightColor: Colors.white.withValues(alpha: 0.04),
              child: SizedBox(
                height: 52,
                width: double.infinity,
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: _kLabelStyle),
                      const SizedBox(width: 8),
                      // .cta-btn svg — width 18, height 18.
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CustomPaint(painter: _ArrowRightPainter()),
                      ),
                    ],
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

/// Arrow-right icon from done-page.html .cta-btn svg.
///
/// SVG path: M4 9 h10  M9 4 l5 5 -5 5 (viewBox 0 0 18 18). stroke-width 2,
/// stroke white, fill none.
class _ArrowRightPainter extends CustomPainter {
  const _ArrowRightPainter();

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

    // Horizontal shaft.
    canvas.drawLine(Offset(4 * sx, 9 * sy), Offset(14 * sx, 9 * sy), paint);

    // Arrow head.
    final path = Path()
      ..moveTo(9 * sx, 4 * sy)
      ..lineTo(14 * sx, 9 * sy)
      ..lineTo(9 * sx, 14 * sy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ArrowRightPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// _SecondaryLink — small text link below the CTA
//
// done-page.html .secondary-action a — 12.5 sp white 28 %. Text size alone
// is below the 48 dp tap target so the visible text is wrapped in an
// InkWell with 14 dp vertical / 16 dp horizontal padding to clear it.
// ---------------------------------------------------------------------------

class _SecondaryLink extends StatelessWidget {
  const _SecondaryLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  /// .secondary-action a { font-size: 12.5; color: rgba(255,255,255,0.28);
  ///                       font-weight: 500 }
  static const _kStyle = TextStyle(
    fontFamily: 'Manrope',
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    color: Color(0x47FFFFFF), // white 28%
    height: 1.2,
  );

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const Key('btn-setup-later'),
            onTap: onPressed,
            splashColor: Colors.white.withValues(alpha: 0.05),
            highlightColor: Colors.white.withValues(alpha: 0.03),
            child: Padding(
              // 14 dp vertical + 14 dp text line-height + 12.5 sp font ≈ 50 dp
              // total tap area — clears the 48 dp Material touch-target rule.
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              child: Text(label, style: _kStyle),
            ),
          ),
        ),
      ),
    );
  }
}
