import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

/// A raised ("extruded") soft surface. The building block for cards, the logo
/// pillow, OTP cells and any resting tactile element.
class NeumorphicCard extends StatelessWidget {
  const NeumorphicCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(VelvetSpacing.lg),
    this.radius = VelvetRadii.card,
    this.shadows = VelvetShadows.extrudedCard,
    this.color = BrandColors.base,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final List<BoxShadow> shadows;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadows,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Paints the recessed ("inset") soft-UI effect — a concave well used for text
/// fields and selected/active surfaces. Flutter's [BoxShadow] cannot render
/// inner shadows, so we paint two offset inner glows on a clipped canvas.
class _InsetShadowPainter extends CustomPainter {
  // Paint objects hoisted to instance fields so they are allocated once per
  // painter instance instead of on every paint() call.
  _InsetShadowPainter({required this.radius});

  final double radius;

  final Paint _dark = Paint()
    ..color = BrandColors.shadowDarkButton
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

  final Paint _light = Paint()
    ..color = BrandColors.shadowLightStrong
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

  final Paint _fill = Paint()..color = BrandColors.base;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas
      ..save()
      ..clipRRect(rrect);

    // Dark inner shadow from the top-left.
    canvas.drawRRect(rrect.shift(const Offset(-5, -5)).inflate(0), _dark);

    // Light inner shadow from the bottom-right (drawn as an inverse stroke).
    canvas.drawRRect(rrect.shift(const Offset(5, 5)).inflate(0), _light);

    // Re-fill the centre with the base tone so only the rim glows remain.
    canvas.drawRRect(rrect.deflate(4), _fill);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_InsetShadowPainter oldDelegate) =>
      oldDelegate.radius != radius;
}

/// A recessed soft well. Wraps any [child] (typically a text field) in the
/// inset neumorphic treatment, optionally drawing a camel focus ring so the
/// otherwise low-contrast field has a clearly visible focused state.
class NeumorphicInset extends StatelessWidget {
  const NeumorphicInset({
    super.key,
    required this.child,
    this.radius = VelvetRadii.field,
    this.focused = false,
    this.hasError = false,
  });

  final Widget child;
  final double radius;
  final bool focused;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final Color? ringColor = hasError
        ? BrandColors.error
        : focused
        ? BrandColors.accent
        : null;

    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: BrandColors.base,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: ringColor ?? Colors.transparent,
            width: ringColor == null ? 0 : 2,
          ),
        ),
        child: CustomPaint(
          painter: _InsetShadowPainter(radius: radius),
          child: child,
        ),
      ),
    );
  }
}

/// A labelled neumorphic text field built on the inset treatment. Always shows
/// a visible label above the field (never placeholder-only) and renders inline
/// error text with an icon below the well when [errorText] is provided.
class NeumorphicTextField extends StatefulWidget {
  // Not `const`: the constructor body runs an assert that calls List.any(),
  // which is a runtime expression and is therefore incompatible with const
  // constructors in Dart.  All call sites that used `const NeumorphicTextField`
  // will continue to work — Dart simply evaluates the widget at runtime.
  NeumorphicTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.obscureToggle = false,
    this.toggleKey,
    this.prefixIcon,
    this.errorText,
    this.helperText,
    this.maxLength,
    this.inputFormatters,
    this.autofillHints,
    this.focusNode,
    this.onSubmitted,
    this.onChanged,
    this.enabled = true,
    this.enableSuggestions,
    this.autocorrect,
    this.enableIMEPersonalizedLearning,
  }) {
    // Development-time contract: if the caller passes password-typed autofill
    // hints (AutofillHints.password / .newPassword) without also setting
    // obscureToggle:true, the OS suggestion strip above the keyboard will show
    // the password as plain text.  This assert fires in debug mode only — it is
    // a programming error, not a runtime failure.
    assert(
      autofillHints == null ||
          obscureToggle ||
          !autofillHints!.any(
            (h) =>
                h == AutofillHints.password || h == AutofillHints.newPassword,
          ),
      'NeumorphicTextField: pass obscureToggle: true when using password autofillHints',
    );
  }

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureToggle;

  /// Optional stable key for the visibility-toggle [IconButton] rendered when
  /// [obscureToggle] is true. When null the auto-generated
  /// `ValueKey<String>('${label}_toggle')` is used (existing behaviour).
  final Key? toggleKey;

  final Widget? prefixIcon;
  final String? errorText;
  final String? helperText;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final List<String>? autofillHints;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  /// Override keyboard suggestions. When [obscureToggle] is true, defaults to
  /// `false` (MASVS-PLATFORM MS-8 — prevents IME from learning password input).
  final bool? enableSuggestions;

  /// Override autocorrect. When [obscureToggle] is true, defaults to `false`.
  final bool? autocorrect;

  /// Override IME personalised learning. When [obscureToggle] is true, defaults
  /// to `false` (MASVS-PLATFORM MS-8).
  final bool? enableIMEPersonalizedLearning;

  @override
  State<NeumorphicTextField> createState() => _NeumorphicTextFieldState();
}

class _NeumorphicTextFieldState extends State<NeumorphicTextField> {
  // Phase 2.17 fix P1-1: hoisted to avoid a .copyWith() allocation per build.
  // VelvetText.input() already carries FontWeight.w600 — omit it here.
  static final TextStyle _hintStyle = VelvetText.input().copyWith(
    color: BrandColors.placeholder,
  );

  // Hoisted to avoid TextStyle allocation on every keystroke.
  static final TextStyle _errorFeedbackStyle = VelvetText.feedback(
    BrandColors.error,
  );
  static final TextStyle _mutedFeedbackStyle = VelvetText.feedback(
    BrandColors.muted,
  );
  static final TextStyle _labelStyle = VelvetText.label();

  late final FocusNode _focusNode;
  // Cached once in initState — widget.prefixIcon is set at construction time
  // and never changes, so evaluating it once avoids a conditional per build.
  late final EdgeInsets _contentPadding;
  bool _obscured = true;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
    _contentPadding = EdgeInsets.symmetric(
      horizontal: widget.prefixIcon == null
          ? VelvetSpacing.md
          : VelvetSpacing.sm,
      vertical: VelvetSpacing.md,
    );
  }

  void _onFocusChange() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasError = widget.errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: VelvetSpacing.sm),
          child: Text(widget.label, style: _labelStyle),
        ),
        NeumorphicInset(
          focused: _focused,
          hasError: hasError,
          child: SizedBox(
            height: VelvetSizes.field,
            child: Row(
              children: <Widget>[
                if (widget.prefixIcon != null) ...<Widget>[
                  const SizedBox(width: VelvetSpacing.md),
                  IconTheme(
                    data: const IconThemeData(
                      color: BrandColors.muted,
                      size: 20,
                    ),
                    child: widget.prefixIcon!,
                  ),
                ],
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    enabled: widget.enabled,
                    keyboardType: widget.keyboardType,
                    textInputAction: widget.textInputAction,
                    obscureText: widget.obscureToggle && _obscured,
                    // MASVS-PLATFORM MS-8: when this is a password field
                    // (obscureToggle:true), suppress IME learning, suggestions,
                    // and autocorrect by default to prevent keyboard apps from
                    // reading the input stream. Callers may override explicitly.
                    enableSuggestions: widget.obscureToggle
                        ? (widget.enableSuggestions ?? false)
                        : (widget.enableSuggestions ?? true),
                    autocorrect: widget.obscureToggle
                        ? (widget.autocorrect ?? false)
                        : (widget.autocorrect ?? true),
                    enableIMEPersonalizedLearning: widget.obscureToggle
                        ? (widget.enableIMEPersonalizedLearning ?? false)
                        : (widget.enableIMEPersonalizedLearning ?? true),
                    // MASVS-STORAGE MS-2: disable text selection on obscured
                    // fields so users cannot copy the visible ciphertext dots
                    // into a clipboard snoop. Callers that need selection (e.g.
                    // a "show password" toggle already visible) pass
                    // enableInteractiveSelection explicitly.
                    enableInteractiveSelection: widget.obscureToggle
                        ? (widget.obscureToggle && _obscured ? false : true)
                        : true,
                    maxLength: widget.maxLength,
                    inputFormatters: widget.inputFormatters,
                    autofillHints: widget.autofillHints,
                    onSubmitted: widget.onSubmitted,
                    onChanged: widget.onChanged,
                    style: VelvetText.input(),
                    cursorColor: BrandColors.accent,
                    decoration: InputDecoration(
                      counterText: '',
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: widget.hintText,
                      hintStyle: _hintStyle,
                      contentPadding: _contentPadding,
                    ),
                  ),
                ),
                if (widget.obscureToggle)
                  Semantics(
                    button: true,
                    label: _obscured ? 'Показати пароль' : 'Сховати пароль',
                    child: IconButton(
                      key:
                          widget.toggleKey ??
                          ValueKey<String>('${widget.label}_toggle'),
                      onPressed: () => setState(() => _obscured = !_obscured),
                      icon: Icon(
                        _obscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: BrandColors.muted,
                        size: 20,
                      ),
                      tooltip: _obscured ? 'Показати пароль' : 'Сховати пароль',
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(left: 6, top: VelvetSpacing.sm),
            child: Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.error_outline,
                    size: 15,
                    color: BrandColors.error,
                  ),
                  const SizedBox(width: VelvetSpacing.xs + 2),
                  Expanded(
                    child: Text(widget.errorText!, style: _errorFeedbackStyle),
                  ),
                ],
              ),
            ),
          )
        else if (widget.helperText != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, top: VelvetSpacing.sm),
            child: Text(widget.helperText!, style: _mutedFeedbackStyle),
          ),
      ],
    );
  }
}

/// The primary CTA — a camel/mocha-filled extruded pill that depresses (scales
/// + loses its raised shadow) on press for tactile feedback. This is the single
/// canonical primary button used on every screen of the flow.
class NeumorphicButton extends StatefulWidget {
  const NeumorphicButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  State<NeumorphicButton> createState() => _NeumorphicButtonState();
}

class _NeumorphicButtonState extends State<NeumorphicButton> {
  // Hoisted to avoid re-allocation on every build; VelvetRadii.button is a
  // compile-time constant so the whole BorderRadius can be const.
  static const BorderRadius _buttonRadius = BorderRadius.all(
    Radius.circular(VelvetRadii.button),
  );

  // Disabled CTA text style — BrandColors.white (0xFFF5EDE0) at alpha 0.55
  // (0x8C = 140 ≈ 0.55 × 255). Static so copyWith() runs only once.
  static final TextStyle _ctaDisabledStyle = VelvetText.cta().copyWith(
    color: const Color(0x8CF5EDE0),
  );

  // Hoisted: BrandColors.white (0xFFF5EDE0) at alpha 55% (0x8C = round(0.55 × 255)).
  // Avoids allocating a Color on every button rebuild when disabled.
  static const Color _ctaIconDisabledColor = Color(0x8CF5EDE0);

  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  @override
  Widget build(BuildContext context) {
    // Phase 2.17 fix P1-2: isolate press-animation repaints from parent scroll.
    return RepaintBoundary(
      child: Semantics(
        button: true,
        enabled: _enabled,
        label: widget.label,
        child: GestureDetector(
          onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
          onTapUp: _enabled
              ? (_) {
                  setState(() => _pressed = false);
                  widget.onPressed!.call();
                }
              : null,
          child: AnimatedScale(
            scale: _pressed ? 0.97 : 1,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: VelvetSizes.cta,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    BrandColors.accentLatte,
                    BrandColors.accentDeep,
                  ],
                ),
                borderRadius: _buttonRadius,
                boxShadow: _pressed || !_enabled
                    ? null
                    : VelvetShadows.extrudedButtonAccent,
              ),
              child: ClipRRect(
                borderRadius: _buttonRadius,
                child: Stack(
                  children: <Widget>[
                    // Label / spinner layer.
                    Center(
                      child: widget.loading
                          ? SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: _enabled
                                    ? BrandColors.white
                                    : _ctaIconDisabledColor,
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                if (widget.icon != null) ...<Widget>[
                                  Icon(
                                    widget.icon,
                                    color: _enabled
                                        ? BrandColors.white
                                        : _ctaIconDisabledColor,
                                    size: 20,
                                  ),
                                  const SizedBox(width: VelvetSpacing.sm),
                                ],
                                // Phase 2.17 fix P1-3: zero-allocation on enabled
                                // path — VelvetText.cta() already carries
                                // color: BrandColors.white so no copyWith needed.
                                // Disabled style cached in _ctaDisabledStyle.
                                Text(
                                  widget.label,
                                  style: _enabled
                                      ? VelvetText.cta()
                                      : _ctaDisabledStyle,
                                ),
                              ],
                            ),
                    ),
                    // Inner bevel overlay — white sheen top-left → transparent
                    // mid → dark veil bottom-right. Only visible in the resting
                    // enabled state; hidden when pressed so the flat look sells
                    // the "depressed" feel.
                    if (!_pressed && _enabled)
                      const Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: <Color>[
                                  Color(0x47FFFFFF), // white @ 0.28 (71/255)
                                  Colors.transparent,
                                  Color(0x24000000), // black @ 0.14 (36/255)
                                ],
                                stops: <double>[0.0, 0.45, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tappable extruded tile (role-selection rows). Depresses to an inset look
/// when [selected], giving a clear pressed-in active state.
class NeumorphicTile extends StatelessWidget {
  const NeumorphicTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.selected = false,
  });

  // Cached subtitle style — body at 13 px. Static so copyWith() runs once.
  static final TextStyle _subtitleStyle = VelvetText.body().copyWith(
    fontSize: 13,
  );

  // Hoisted: VelvetRadii.field is a compile-time constant so the BorderRadius
  // can be static const, avoiding an allocation per build for the icon container.
  static const BorderRadius _iconContainerRadius = BorderRadius.all(
    Radius.circular(VelvetRadii.field),
  );

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md,
        vertical: VelvetSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: BrandColors.base,
              borderRadius: _iconContainerRadius,
              boxShadow: selected ? null : VelvetShadows.extrudedSmall,
            ),
            child: Icon(
              icon,
              color: selected ? BrandColors.accent : BrandColors.textSecondary,
              size: 24,
            ),
          ),
          const SizedBox(width: VelvetSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: VelvetText.subheading()),
                const SizedBox(height: 2),
                Text(subtitle, style: _subtitleStyle),
              ],
            ),
          ),
          const SizedBox(width: VelvetSpacing.sm),
          Icon(
            selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
            color: selected ? BrandColors.accent : BrandColors.faint,
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $subtitle',
      child: GestureDetector(
        onTap: onTap,
        child: NeumorphicCard(
          padding: EdgeInsets.zero,
          shadows: selected ? const <BoxShadow>[] : VelvetShadows.extrudedCard,
          child: selected
              ? NeumorphicInset(radius: VelvetRadii.card, child: content)
              : content,
        ),
      ),
    );
  }
}

/// Letter-by-letter reveal of the "beautica" wordmark.
///
/// Each letter fades in (opacity 0→1) and slides up
/// (Offset(0, 0.3)→Offset.zero) over [perLetterDurationMs] ms, staggered by
/// [perLetterDelayMs] ms. The animation is driven by an externally-owned
/// [AnimationController] — this widget never disposes it.
///
/// Accessibility: the enclosing [VelvetLogo] already provides a
/// `Semantics(label: 'beautica', image: true)` ancestor node; no additional
/// [Semantics] wrapper is added here to avoid a double-announce on TalkBack.
class AnimatedWordmark extends StatefulWidget {
  const AnimatedWordmark({
    super.key,
    required this.controller,
    this.text = 'beautica',
    this.startDelayMs = 0,
    this.perLetterDelayMs = 90,
    this.perLetterDurationMs = 250,
    this.fontSize = 14,
  });

  /// The [AnimationController] whose [duration] must be at least
  /// [startDelayMs] + ([text.length] − 1) × [perLetterDelayMs] +
  /// [perLetterDurationMs] milliseconds (default 880 ms for 8 letters).
  /// The controller is owned by the caller — [AnimatedWordmark] never
  /// disposes it.
  final AnimationController controller;

  /// The word to animate. Each character becomes one animated [Text] widget.
  final String text;

  /// Milliseconds before the first letter starts animating.
  final int startDelayMs;

  /// Stagger delay between consecutive letters, in milliseconds.
  final int perLetterDelayMs;

  /// Duration of the per-letter fade+slide animation, in milliseconds.
  final int perLetterDurationMs;

  /// Font size passed to [VelvetText.wordmark] via [TextStyle.copyWith].
  /// Defaults to 14, matching the static wordmark. Splash screen passes 17.
  final double fontSize;

  @override
  State<AnimatedWordmark> createState() => _AnimatedWordmarkState();
}

class _AnimatedWordmarkState extends State<AnimatedWordmark> {
  /// The [CurvedAnimation] instances — one per letter — are tracked here so
  /// they can be disposed in [dispose] / [didUpdateWidget]. Each removes its
  /// listener from the parent [AnimationController] when disposed, preventing
  /// the leak that fires Flutter debug-mode animation assertions.
  late List<CurvedAnimation> _curves;
  late List<Animation<double>> _opacities;
  late List<Animation<Offset>> _slides;
  late TextStyle _style;

  void _initAnimations() {
    final int totalMs = widget.controller.duration?.inMilliseconds ?? 880;
    _curves = <CurvedAnimation>[];
    _opacities = <Animation<double>>[];
    _slides = <Animation<Offset>>[];
    _style = VelvetText.wordmark().copyWith(fontSize: widget.fontSize);

    for (int i = 0; i < widget.text.length; i++) {
      final int startMs = widget.startDelayMs + i * widget.perLetterDelayMs;
      final int endMs = startMs + widget.perLetterDurationMs;

      // Interval ensures begin < end even for the last letter at the edge.
      final CurvedAnimation curved = CurvedAnimation(
        parent: widget.controller,
        curve: Interval(
          (startMs / totalMs).clamp(0.0, 1.0),
          (endMs / totalMs).clamp(0.0, 1.0),
          curve: Curves.easeOut,
        ),
      );
      _curves.add(curved);
      _opacities.add(Tween<double>(begin: 0.0, end: 1.0).animate(curved));
      _slides.add(
        Tween<Offset>(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
        ).animate(curved),
      );
    }
  }

  void _disposeAnimations() {
    for (final CurvedAnimation c in _curves) {
      c.dispose();
    }
    _curves = <CurvedAnimation>[];
    _opacities = <Animation<double>>[];
    _slides = <Animation<Offset>>[];
  }

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  @override
  void didUpdateWidget(covariant AnimatedWordmark oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-create animations whenever any parameter that affects the curve
    // intervals or style changes, including a new controller reference.
    if (oldWidget.controller != widget.controller ||
        oldWidget.text != widget.text ||
        oldWidget.fontSize != widget.fontSize ||
        oldWidget.startDelayMs != widget.startDelayMs ||
        oldWidget.perLetterDelayMs != widget.perLetterDelayMs ||
        oldWidget.perLetterDurationMs != widget.perLetterDurationMs) {
      _disposeAnimations();
      _initAnimations();
    }
  }

  @override
  void dispose() {
    // Dispose the CurvedAnimations we own. The AnimationController is owned
    // by the caller (e.g. SplashScreen) and must NOT be disposed here.
    _disposeAnimations();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < widget.text.length; i++) {
      children.add(
        FadeTransition(
          opacity: _opacities[i],
          child: SlideTransition(
            position: _slides[i],
            child: Text(widget.text[i], style: _style),
          ),
        ),
      );
    }

    // No Semantics wrapper here — the enclosing VelvetLogo already provides
    // Semantics(label: 'beautica', image: true). Adding one here would cause
    // TalkBack to announce "beautica" twice (LOW-3 double-announce fix).
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: children,
    );
  }
}

/// The Velvet "B" logo pillow + lowercase `beautica` wordmark.
///
/// By default renders a static wordmark ([Text]). When [animationController]
/// is supplied, the wordmark is replaced by an [AnimatedWordmark] that reveals
/// the letters one-by-one.
///
/// The optional [tileSize], [markFontSize], and [wordmarkFontSize] parameters
/// allow the splash screen to render a slightly larger logo without affecting
/// any other call site. All params have defaults that exactly reproduce the
/// original two-param behaviour (`VelvetLogo()` and `VelvetLogo(compact: true)`
/// are unaffected).
class VelvetLogo extends StatelessWidget {
  const VelvetLogo({
    super.key,
    this.compact = false,
    this.animationController,
    this.tileSize,
    this.markFontSize = 36,
    this.wordmarkFontSize = 14,
  });

  final bool compact;

  /// When non-null, an [AnimatedWordmark] is rendered instead of the static
  /// wordmark [Text]. The controller must be started by the caller.
  final AnimationController? animationController;

  /// Overrides the default tile dimension (`compact ? 72 : VelvetSizes.logoTile`).
  /// Used by the splash screen to render a slightly larger pillow.
  final double? tileSize;

  /// Font size of the "B" glyph inside the logo pillow. Defaults to 36.
  final double markFontSize;

  /// Font size forwarded to [AnimatedWordmark] (or applied to the static
  /// wordmark via [TextStyle.copyWith]). Defaults to 14 (= VelvetText.wordmark()).
  final double wordmarkFontSize;

  // Hoisted: VelvetRadii.logoTile is a compile-time constant so the whole
  // BorderRadius can be a static const, avoiding an allocation per build.
  static const BorderRadius _logoTileRadius = BorderRadius.all(
    Radius.circular(VelvetRadii.logoTile),
  );

  @override
  Widget build(BuildContext context) {
    final double tile = tileSize ?? (compact ? 72 : VelvetSizes.logoTile);

    // Compute mark style — hoist the common parts, vary only markFontSize.
    // Using a local final (not a static) because markFontSize is an instance param.
    final TextStyle markStyle = VelvetText.heading().copyWith(
      fontSize: markFontSize,
      color: BrandColors.accentLogo,
      fontWeight: FontWeight.w700,
    );

    final Widget wordmark = animationController != null
        ? AnimatedWordmark(
            controller: animationController!,
            fontSize: wordmarkFontSize,
          )
        : Text(
            'beautica',
            style: VelvetText.wordmark().copyWith(fontSize: wordmarkFontSize),
          );

    return Semantics(
      label: 'beautica',
      image: true,
      child: Column(
        children: <Widget>[
          Container(
            key: const Key('velvet_logo_pillow'),
            height: tile,
            width: tile,
            decoration: const BoxDecoration(
              color: BrandColors.base,
              borderRadius: _logoTileRadius,
              boxShadow: VelvetShadows.extrudedSmall,
            ),
            child: Center(child: Text('B', style: markStyle)),
          ),
          const SizedBox(height: VelvetSpacing.md),
          wordmark,
        ],
      ),
    );
  }
}

/// Standardised brand header used at the top of EVERY auth screen so the logo
/// sits at an identical position with equal top spacing everywhere. It pairs a
/// fixed top inset with the compact [VelvetLogo] and a fixed gap below, so the
/// monogram + wordmark never shift vertically or horizontally between screens.
class VelvetHeader extends StatelessWidget {
  const VelvetHeader({super.key});

  /// Top spacing above the logo — identical on every screen.
  static const double topSpacing = VelvetSpacing.sm;

  /// Gap below the logo before screen content begins — identical everywhere.
  static const double bottomSpacing = VelvetSpacing.xl;

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: <Widget>[
        SizedBox(height: topSpacing),
        VelvetLogo(compact: true),
        SizedBox(height: bottomSpacing),
      ],
    );
  }
}

/// A subtle inset "back" affordance used in app bars across the flow.
class NeumorphicIconButton extends StatelessWidget {
  const NeumorphicIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  // Hoisted: VelvetRadii.field is a compile-time constant so the BorderRadius
  // can be static const, avoiding an allocation per build.
  static const BorderRadius _buttonRadius = BorderRadius.all(
    Radius.circular(VelvetRadii.field),
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          width: 48,
          decoration: const BoxDecoration(
            color: BrandColors.base,
            borderRadius: _buttonRadius,
            boxShadow: VelvetShadows.extrudedSmall,
          ),
          child: Icon(icon, color: BrandColors.textSecondary, size: 22),
        ),
      ),
    );
  }
}
