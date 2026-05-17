// Phase 2.5 — Login screen — Warm Mocha visual redesign (Phase 2.x).
//
// VISUAL REDESIGN ONLY — all business logic, form validation, Riverpod state,
// Keys, routing, and animation controllers are unchanged from the previous
// "Modern Dark Cinema" version.
//
// What changed:
//   - Background: AuthGradientBackground (Warm Mocha linear gradient) instead of
//     the old navy LinearGradient.
//   - Layout: brand row (monogram + BEAUTICA), Cormorant Garamond italic
//     headline, glass card wrapping both fields.
//   - Input fields: warm-mocha InputDecoration (camel focus ring, white-7% fill,
//     espresso-toned border, 12 px radius, icon prefix).
//   - CTA button: mocha LinearGradient with glow BoxShadow, 52 px height.
//   - "Forgot password" link: camel colour, right-aligned.
//   - "No account?" row: moved inside Column below card, camel accent link.
//   - Logo SVG replaced by text brand row (matches HTML mockup pattern).
//
// ConsumerStatefulWidget: owns TextEditingControllers, FormKey, animation
// controller, and minor UI state (_obscurePassword, _buttonPressed).
// Network-side state lives in [authProvider].
//
// Submit flow (UNCHANGED):
//   1. Validate form locally.
//   2. Call authProvider.notifier.login() — state transitions to AsyncLoading.
//   3. On AsyncData<Authenticated> → navigate to home.
//   4. On AsyncError → show floating SnackBar.
//
// Entrance animation (UNCHANGED): 4-item stagger over 600 ms.
//
// All user-visible strings are fetched through AppLocalizations (UA primary).

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
import '../../../shared/validators/password_validator.dart';
import '../../../shared/widgets/auth_field_label.dart';
import '../../../shared/widgets/auth_scaffold.dart';
import 'auth_notifier.dart';

// ---------------------------------------------------------------------------
// Static style constants — allocated once, never inside build()
// ---------------------------------------------------------------------------

/// Glass card border radius (22 px matching HTML mockup).
const _kCardRadius = BorderRadius.all(Radius.circular(22));

/// Input field border radius (12 px matching HTML mockup).
const _kInputRadius = BorderRadius.all(Radius.circular(12));

/// Monogram container border radius (10 px matching HTML monogram).
const _kMonogramRadius = BorderRadius.all(Radius.circular(10));

/// Default input border — white 10% opacity.
const _kInputBorderDefault = OutlineInputBorder(
  borderRadius: _kInputRadius,
  borderSide: BorderSide(color: Color(0x1AFFFFFF), width: 1),
);

/// Focused input border — camel 36% opacity.
const _kInputBorderFocused = OutlineInputBorder(
  borderRadius: _kInputRadius,
  borderSide: BorderSide(color: Color(0x5CB89A7A), width: 1.5),
);

/// Error input border — errorRust solid.
const _kInputBorderError = OutlineInputBorder(
  borderRadius: _kInputRadius,
  borderSide: BorderSide(color: BrandColors.errorRust, width: 1),
);

/// Focused-error input border — errorRust 1.5 px.
const _kInputBorderFocusedError = OutlineInputBorder(
  borderRadius: _kInputRadius,
  borderSide: BorderSide(color: BrandColors.errorRust, width: 1.5),
);

/// CTA gradient — literal hex from login-page.html
/// `--cta-grad: linear-gradient(135deg, #4a2e10 0%, #6a4a28 60%, #8a6840 100%)`.
/// Literal hex stops (NOT BrandColors tokens) per parity directive #3.
const _kCtaGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF4A2E10), Color(0xFF6A4A28), Color(0xFF8A6840)],
  stops: [0.0, 0.6, 1.0],
);

/// CTA box shadow — mocha glow, reduced for Android/Impeller saturation.
/// HTML value was rgba(58,36,12,0.68) / blur 24 — Android renders this more
/// prominently than browser (blob-like). Reduced to 0.36 opacity / blur 16.
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

// ---------------------------------------------------------------------------
// LoginScreen
// ---------------------------------------------------------------------------

/// Login screen for the Beautica app — Warm Mocha design.
///
/// Presents email + password fields with a staggered entrance animation and
/// submits to [AuthNotifier.login]. Navigates to [RouteNames.home] on success;
/// surfaces [Failure.userMessage] in a floating [SnackBar] on error.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  // ---------------------------------------------------------------------------
  // Form state (UNCHANGED)
  // ---------------------------------------------------------------------------

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _buttonPressed = false;

  // ---------------------------------------------------------------------------
  // Entrance animation (UNCHANGED)
  // ---------------------------------------------------------------------------

  late final AnimationController _entranceCtrl;

  // Cached per-item animations — 4 items: headline, email, password+forgot,
  // CTA row. Initialized in initState() after _entranceCtrl is created so
  // they are never recreated on build(). The brand row (item 0 in the Column)
  // is unwrapped from stagger — it is always visible.
  late final List<Animation<double>> _opacities;
  late final List<Animation<Offset>> _slides;

  Widget _staggered(int index, Widget child) => FadeTransition(
    opacity: _opacities[index],
    child: SlideTransition(position: _slides[index], child: child),
  );

  // ---------------------------------------------------------------------------
  // Lifecycle (UNCHANGED)
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _opacities = [
      for (var i = 0; i < 4; i++)
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _entranceCtrl,
            curve: Interval(
              (i * 0.12).clamp(0.0, 1.0),
              (i * 0.12 + 0.5).clamp(0.0, 1.0),
              curve: Curves.easeOut,
            ),
          ),
        ),
    ];
    _slides = [
      for (var i = 0; i < 4; i++)
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceCtrl,
            curve: Interval(
              (i * 0.12).clamp(0.0, 1.0),
              (i * 0.12 + 0.5).clamp(0.0, 1.0),
              curve: Curves.easeOut,
            ),
          ),
        ),
    ];

    if (!kDebugMode) {
      ScreenProtector.preventScreenshotOn();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        _entranceCtrl.value = 1.0;
      } else {
        _entranceCtrl.forward();
      }
    });
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    if (!kDebugMode) {
      ScreenProtector.preventScreenshotOff();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Submit logic (UNCHANGED)
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    await ref.read(authProvider.notifier).login(email, password);

    if (!mounted) return;

    final authState = ref.read(authProvider);
    authState.when(
      data: (_) {
        if (kDebugMode) {
          log(
            'Login screen: navigating to home',
            name: 'auth.login',
            level: 800,
          );
        }
        context.go(RouteNames.home);
      },
      loading: () {
        // Still loading — guard only; shouldn't happen right after await.
      },
      error: (e, _) {
        final l10n = AppLocalizations.of(context);
        final message = e is Failure ? e.userMessage(context) : l10n.errUnknown;
        _showErrorSnackBar(message);
      },
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: BrandColors.errorRust,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppSpacing.sm)),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Field decoration helper — warm mocha style
  // ---------------------------------------------------------------------------

  InputDecoration _fieldDecor(
    String hint, {
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) => InputDecoration(
    hintText: hint,
    // login-page.html: input::placeholder { color: rgba(255,255,255,0.18) }
    hintStyle: const TextStyle(color: Color(0x2EFFFFFF)),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: const Color(0x12FFFFFF), // white 7%
    labelStyle: const TextStyle(color: Color(0x6BFFFFFF)),
    floatingLabelStyle: const TextStyle(color: BrandColors.camel),
    errorStyle: const TextStyle(
      color: BrandColors.errorRust,
      fontSize: 13,
    ), // increased from 12
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    border: _kInputBorderDefault,
    enabledBorder: _kInputBorderDefault,
    focusedBorder: _kInputBorderFocused,
    errorBorder: _kInputBorderError,
    focusedErrorBorder: _kInputBorderFocusedError,
    isDense: true,
  );

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authProvider);
    final isLoading = authState.isLoading;

    return AuthScaffold(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Shared top geometry — identical to register so the brand
            //    row never jumps when switching Login ↔ Register.
            const SizedBox(height: 24),

            // ── Brand row: monogram + BEAUTICA
            const _BrandRow(key: Key('brand-row')),

            const SizedBox(height: 36),

            // ── Stagger 0: Headline block
            _staggered(0, _HeadlineBlock(l10n: l10n)),

            // headline → glass card gap (mockup .headline + .sub-text block
            // sits directly above the card; 24 keeps a comfortable rhythm).
            const SizedBox(height: AppSpacing.lg),

            // ── Stagger 1: Glass card with email + password
            _staggered(
              1,
              _GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Email field
                    _staggered(
                      2,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AuthFieldLabel(l10n.loginEmailLabel),
                          TextFormField(
                            key: const Key('field-email'),
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(
                              color: BrandColors.cream,
                              fontSize: 16, // increased from 15
                            ),
                            decoration: _fieldDecor(
                              l10n.loginEmailPlaceholder,
                              prefixIcon: const _FieldIcon(
                                icon: Icons.mail_outline,
                              ),
                            ),
                            validator: (v) => validateEmail(v, l10n),
                            enabled: !isLoading,
                            autocorrect: false,
                          ),
                        ],
                      ),
                    ),

                    // .field-group { margin-bottom: 14px }
                    const SizedBox(height: 14),

                    // ── Password + forgot row
                    _staggered(
                      3,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AuthFieldLabel(l10n.loginPasswordLabel),
                          TextFormField(
                            key: const Key('field-password'),
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            enableSuggestions: false,
                            autocorrect: false,
                            textInputAction: TextInputAction.done,
                            style: const TextStyle(
                              color: BrandColors.cream,
                              fontSize: 16, // increased from 15
                            ),
                            decoration: _fieldDecor(
                              l10n.loginPasswordPlaceholder,
                              prefixIcon: const _FieldIcon(
                                icon: Icons.lock_outline,
                              ),
                              suffixIcon: IconButton(
                                key: const Key('btn-toggle-password'),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: const Color(0x47FFFFFF),
                                  size: 20, // increased from 18
                                  semanticLabel: _obscurePassword
                                      ? l10n.showPasswordSemanticLabel
                                      : l10n.hidePasswordSemanticLabel,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                            validator: (v) => validatePassword(v, l10n),
                            enabled: !isLoading,
                            onFieldSubmitted: (_) =>
                                isLoading ? null : _submit(),
                          ),

                          // .forgot-row { margin-top: 6px }
                          const SizedBox(height: 6),

                          // ── Forgot password link — right-aligned, camel.
                          // login-page.html:334 `.forgot-link`: camel @ 0.8
                          // opacity, 11.5px, w500. Backend flow is a future
                          // phase; the link must render in its NORMAL (not
                          // disabled/greyed) visual state per parity directive
                          // #2, so onPressed is a harmless no-op.
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              key: const Key('btn-forgot-password'),
                              onPressed: () {},
                              style: TextButton.styleFrom(
                                foregroundColor: BrandColors.camel.withValues(
                                  alpha: 0.8,
                                ),
                                disabledForegroundColor: BrandColors.camel
                                    .withValues(alpha: 0.8),
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.xxs,
                                  horizontal: AppSpacing.xs,
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 14, // increased from 13
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 0.02,
                                ),
                              ),
                              child: Text(l10n.loginForgotPassword),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // .cta-btn { margin-top: 4px }
                    const SizedBox(height: 4),

                    // ── CTA button — mocha gradient
                    _MochaCtaButton(
                      buttonKey: const Key('btn-submit-login'),
                      onPressed: isLoading ? null : _submit,
                      onTapDown: () => setState(() => _buttonPressed = true),
                      onTapUp: () => setState(() => _buttonPressed = false),
                      onTapCancel: () => setState(() => _buttonPressed = false),
                      isPressed: _buttonPressed,
                      isLoading: isLoading,
                      label: l10n.loginSubmit,
                    ),
                  ],
                ),
              ),
            ),

            // .register-row { margin-top: 20px } — sits 20 px below the
            // card, NOT bottom-anchored (Spacer removed → no vertical jump).
            const SizedBox(height: 20),

            _buildRegisterRow(l10n, isLoading),

            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  Widget _buildRegisterRow(AppLocalizations l10n, bool isLoading) {
    // login-page.html .register-row: a single centred line —
    // "<p>Ще немає акаунту? &nbsp;<a>Зареєструватись</a></p>". The previous
    // rigid Row overflowed by 36 px at 360–430 px widths because Text +
    // TextButton could not shrink. Wrap centres the line at normal phone
    // widths and gracefully drops the camel link onto a second centred line
    // at the narrowest widths instead of throwing a RenderFlex overflow.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l10n.loginNoAccount,
          style: const TextStyle(
            color: Color(0x4DFFFFFF),
            fontSize: 15,
          ), // increased from 14
        ),
        // The HTML uses a non-breaking space (&nbsp;) between the prompt and
        // the link; reproduce that gap so they read as one line when they fit.
        const SizedBox(width: AppSpacing.xs),
        TextButton(
          key: const Key('btn-go-to-register'),
          onPressed: isLoading ? null : () => context.push(RouteNames.register),
          style: TextButton.styleFrom(
            foregroundColor: BrandColors.camel,
            // Compact tap padding keeps the line tight while still meeting the
            // 48 dp touch target via the button's default minimum height.
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 15, // increased from 14
            ),
          ),
          child: Text(l10n.loginCreateAccount),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _BrandRow — monogram B + BEAUTICA text
// ---------------------------------------------------------------------------

/// Brand row matching the HTML mockup's `.brand-row`.
///
/// Monogram: 34 × 34 frosted-glass rounded box (white 10% + white 20% border
/// + backdrop blur 8). Brand name: BEAUTICA uppercase, Manrope 700.
///
/// Extracted as a private StatelessWidget to avoid allocating its decoration
/// inside the parent's build() method on every rebuild.
class _BrandRow extends StatelessWidget {
  const _BrandRow({super.key});

  static final _kBlur = ImageFilter.blur(sigmaX: 8, sigmaY: 8);

  static const _kMonogramDecoration = BoxDecoration(
    color: Color(0x1AFFFFFF), // white 10%
    borderRadius: _kMonogramRadius,
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x33FFFFFF), width: 1), // white 20%
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Frosted glass monogram
        SizedBox(
          width: 34,
          height: 34,
          child: ClipRRect(
            borderRadius: _kMonogramRadius,
            child: Stack(
              children: [
                // Blur + decoration background — no content in SaveLayer.
                Positioned.fill(
                  child: BackdropFilter(
                    filter: _kBlur,
                    child: const DecoratedBox(decoration: _kMonogramDecoration),
                  ),
                ),
                // 'B' text above the blur — crisp rendering.
                const Center(
                  child: Text(
                    'B',
                    style: TextStyle(
                      color: Color(0xF2FFFFFF), // white 95%
                      fontSize: 20, // increased from 18
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: AppSpacing.xs),

        // BEAUTICA label
        const Text(
          'BEAUTICA',
          style: TextStyle(
            color: Color(0xEBFFFFFF), // white 92%
            fontSize: 18, // increased from 17
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6, // absolute px — kept unchanged
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _HeadlineBlock — login headline + italic accent + sub-text
// ---------------------------------------------------------------------------

/// Matches the HTML mockup's `.headline` + `.sub-text` block.
///
/// Main headline: Manrope 700, 26 sp, white.
/// Italic accent: Cormorant Garamond italic 600, camel colour.
/// Sub-text: 13 sp, white 32%.
class _HeadlineBlock extends StatelessWidget {
  const _HeadlineBlock({required this.l10n});

  final AppLocalizations l10n;

  // login-page.html .headline em { font-family: 'Cormorant Garamond';
  // font-style: italic; font-weight: 600; font-size: 1.15em (= 1.15 × 30 =
  // 34.5 ≈ 34); color: var(--accent) #b89a7a }.
  // Weight set to w400 — the italic Cormorant Garamond face has sufficient
  // visual presence at regular weight; bold italic competes with the headline.
  static final _kAccentStyle = GoogleFonts.cormorantGaramond(
    textStyle: const TextStyle(
      color: BrandColors.camel,
      fontSize: 34, // 1.15× of 30 (increased from 32)
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w400,
      height: 1.22,
    ),
  );

  // login-page.html .headline { font-family: 'Manrope'; font-size: 26px;
  // font-weight: 700; color: #fff; line-height: 1.22 }. Increased to 30 for
  // better on-device readability (+2 px pass; was 28).
  static final _kHeadlineStyle = GoogleFonts.manrope(
    textStyle: const TextStyle(
      color: Colors.white,
      fontSize: 30, // increased from 28
      fontWeight: FontWeight.w700,
      height: 1.22,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main headline + italic accent on same line via RichText
        Text.rich(
          TextSpan(
            text: '${l10n.loginHeadline}\n',
            style: _kHeadlineStyle,
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Text(l10n.loginHeadlineAccent, style: _kAccentStyle),
              ),
            ],
          ),
        ),
        // .headline margin-bottom 8 + .sub-text margin-top 10 → 10 px gap
        // (task spec: headline→subtext gap 10). Literal — no AppSpacing token
        // is 10; snapping to a token is what caused Defect 1 drift.
        const SizedBox(height: 10),
        // login-page.html .sub-text { font-size: 13px;
        // color: rgba(255,255,255,0.32); line-height: 1.55 }.
        // Increased to 15 for on-device readability (+2 px pass; was 14).
        Text(
          l10n.loginSubText,
          style: GoogleFonts.manrope(
            textStyle: const TextStyle(
              color: Color(0x52FFFFFF), // white 32%
              fontSize: 15, // increased from 14
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _GlassCard — glassmorphism container
// ---------------------------------------------------------------------------

/// Glassmorphism card matching the HTML `.glass-card`:
///   background rgba(255,255,255,0.065), border rgba(255,255,255,0.1),
///   border-radius 22px, backdrop-filter blur(20px).
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  // HTML: backdrop-filter: blur(20px). Match directly with sigma 20 — the
  // earlier sigma 12 under-blurred, making the card appear heavier/darker.
  static final _kBlur = ImageFilter.blur(sigmaX: 20, sigmaY: 20);

  static const _kDecoration = BoxDecoration(
    color: Color(0x11FFFFFF), // rgba(255,255,255,0.065) ≈ 0x10
    borderRadius: _kCardRadius,
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x1AFFFFFF), width: 1), // white 10%
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: _kCardRadius,
      child: Stack(
        children: [
          // Blur + glass fill — no content inside the SaveLayer.
          Positioned.fill(
            child: BackdropFilter(
              filter: _kBlur,
              child: const DecoratedBox(decoration: _kDecoration),
            ),
          ),
          // Content rendered above the blur, outside SaveLayer — crisp text.
          // .glass-card { padding: 22px 18px 20px } → LTRB(18, 22, 18, 20).
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _FieldIcon — left-prefix icon inside input fields
// ---------------------------------------------------------------------------

/// Small dimmed icon aligned to the vertical centre of the input field,
/// matching the HTML `.input-icon` style (white 25% opacity, 15 px svg).
class _FieldIcon extends StatelessWidget {
  const _FieldIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Icon(
    icon,
    color: const Color(0x40FFFFFF), // white ~25%
    size: 20, // increased from 18
  );
}

// ---------------------------------------------------------------------------
// _MochaCtaButton — gradient CTA button
// ---------------------------------------------------------------------------

/// Gradient CTA button matching the HTML `.cta-btn`:
///   gradient #4A2E10→#6A4A28→#8A6840, height 52px, radius 14px, mocha glow.
///
/// Uses [DecoratedBox] → [ClipRRect] → [Material] (transparent) → [InkWell]
/// instead of [ElevatedButton]. This pattern is required for Android Impeller
/// (Flutter 3.22+): [ElevatedButton] creates its own composited [Material]
/// layer that sits above any [Ink] gradient placed outside it, making the
/// gradient invisible on device. [Material.transparency] has no competing
/// paint layer, so the [DecoratedBox] gradient is always visible.
///
/// The gradient is rendered unconditionally in all states — idle, loading, and
/// when [onPressed] is null (form invalid / no role selected). The design has
/// no disabled visual state; a null [onPressed] makes the button non-tappable
/// but keeps the filled mocha look.
///
/// The [Key] is placed on the outermost [GestureDetector] so that
/// `find.byKey(...)` resolves regardless of the inner widget type.
class _MochaCtaButton extends StatelessWidget {
  const _MochaCtaButton({
    this.buttonKey,
    required this.onPressed,
    required this.onTapDown,
    required this.onTapUp,
    required this.onTapCancel,
    required this.isPressed,
    required this.isLoading,
    required this.label,
  });

  /// Key placed on the outermost [GestureDetector] — tests locate the button
  /// via `find.byKey(...)` without needing to cast to a specific button type.
  final Key? buttonKey;
  final VoidCallback? onPressed;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;
  final VoidCallback onTapCancel;
  final bool isPressed;
  final bool isLoading;
  final String label;

  // CTA border radius — 14px per login-page.html `.cta-btn { border-radius: 14px }`.
  static const _kCtaRadius = BorderRadius.all(Radius.circular(14));

  // Gradient decoration applied unconditionally — no onPressed guard.
  static const _kGradientDecoration = BoxDecoration(
    gradient: _kCtaGradient,
    borderRadius: _kCtaRadius,
    boxShadow: _kCtaShadow,
  );

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
        // DecoratedBox paints the gradient on its own layer — Impeller sees it.
        child: DecoratedBox(
          decoration: _kGradientDecoration,
          child: ClipRRect(
            borderRadius: _kCtaRadius,
            // MaterialType.transparency: no competing paint layer so the
            // DecoratedBox gradient above is never occluded.
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onPressed,
                splashColor: Colors.white.withValues(alpha: 0.08),
                highlightColor: Colors.white.withValues(alpha: 0.04),
                child: SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: Align(
                    child: isLoading
                        ? const CircularProgressIndicator(
                            color: BrandColors.cream,
                            strokeWidth: 2,
                          )
                        // login-page.html .cta-btn { display: flex; gap: 8px }
                        // with a trailing right-arrow SVG.
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17, // increased from 16
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward,
                                color: Colors.white,
                                size: 20, // increased from 18
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
