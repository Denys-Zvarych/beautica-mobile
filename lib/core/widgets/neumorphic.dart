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
  const _InsetShadowPainter({required this.radius});

  final double radius;

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
    final Paint dark = Paint()
      ..color = BrandColors.shadowDarkButton
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(rrect.shift(const Offset(-5, -5)).inflate(0), dark);

    // Light inner shadow from the bottom-right (drawn as an inverse stroke).
    final Paint light = Paint()
      ..color = BrandColors.shadowLightStrong
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(rrect.shift(const Offset(5, 5)).inflate(0), light);

    // Re-fill the centre with the base tone so only the rim glows remain.
    final Paint fill = Paint()..color = BrandColors.base;
    canvas.drawRRect(rrect.deflate(4), fill);

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
  const NeumorphicTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.obscureToggle = false,
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
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureToggle;
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

  late final FocusNode _focusNode;
  bool _obscured = true;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
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
          child: Text(widget.label, style: VelvetText.label()),
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
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: widget.prefixIcon == null
                            ? VelvetSpacing.md
                            : VelvetSpacing.sm,
                        vertical: VelvetSpacing.md,
                      ),
                    ),
                  ),
                ),
                if (widget.obscureToggle)
                  Semantics(
                    button: true,
                    label: _obscured ? 'Показати пароль' : 'Сховати пароль',
                    child: IconButton(
                      key: ValueKey<String>('${widget.label}_toggle'),
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
                    child: Text(
                      widget.errorText!,
                      style: VelvetText.feedback(BrandColors.error),
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (widget.helperText != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, top: VelvetSpacing.sm),
            child: Text(
              widget.helperText!,
              style: VelvetText.feedback(BrandColors.muted),
            ),
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
                borderRadius: BorderRadius.circular(VelvetRadii.button),
                boxShadow: _pressed || !_enabled
                    ? null
                    : VelvetShadows.extrudedButtonAccent,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(VelvetRadii.button),
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
                                color: BrandColors.white.withValues(
                                  alpha: _enabled ? 1.0 : 0.55,
                                ),
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                if (widget.icon != null) ...<Widget>[
                                  Icon(
                                    widget.icon,
                                    color: BrandColors.white.withValues(
                                      alpha: _enabled ? 1.0 : 0.55,
                                    ),
                                    size: 20,
                                  ),
                                  const SizedBox(width: VelvetSpacing.sm),
                                ],
                                // Phase 2.17 fix P1-3: zero-allocation on enabled
                                // path — VelvetText.cta() already carries
                                // color: BrandColors.white so no copyWith needed.
                                Text(
                                  widget.label,
                                  style: _enabled
                                      ? VelvetText.cta()
                                      : VelvetText.cta().copyWith(
                                          color: BrandColors.white.withValues(
                                            alpha: 0.55,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                    ),
                    // Inner bevel overlay — white sheen top-left → transparent
                    // mid → dark veil bottom-right. Only visible in the resting
                    // enabled state; hidden when pressed so the flat look sells
                    // the "depressed" feel.
                    if (!_pressed && _enabled)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: <Color>[
                                  Colors.white.withValues(alpha: 0.28),
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.14),
                                ],
                                stops: const <double>[0.0, 0.45, 1.0],
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
              borderRadius: BorderRadius.circular(VelvetRadii.field),
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
                Text(subtitle, style: VelvetText.body().copyWith(fontSize: 13)),
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

/// The Velvet "B" logo pillow + lowercase `beautica` wordmark.
class VelvetLogo extends StatelessWidget {
  const VelvetLogo({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double tile = compact ? 72 : VelvetSizes.logoTile;
    return Semantics(
      label: 'beautica',
      image: true,
      child: Column(
        children: <Widget>[
          Container(
            height: tile,
            width: tile,
            decoration: BoxDecoration(
              color: BrandColors.base,
              borderRadius: BorderRadius.circular(VelvetRadii.logoTile),
              boxShadow: VelvetShadows.extrudedSmall,
            ),
            child: Center(
              child: Text(
                'B',
                style: VelvetText.heading().copyWith(
                  fontSize: compact ? 30 : 36,
                  color: BrandColors.accentLogo,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          Text('beautica', style: VelvetText.wordmark()),
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
          decoration: BoxDecoration(
            color: BrandColors.base,
            borderRadius: BorderRadius.circular(VelvetRadii.field),
            boxShadow: VelvetShadows.extrudedSmall,
          ),
          child: Icon(icon, color: BrandColors.textSecondary, size: 22),
        ),
      ),
    );
  }
}
