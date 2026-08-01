// Phase 13.7 — Shared hub widget building-blocks.
//
// Ported verbatim from the approved preview at
// `docs/signup-designs/ClientHomeHub/lib/widgets/hub_widgets.dart`.
// VelvetColors.* → BrandColors.*; no other changes.
//
// All user-facing strings are lifted to the callers (l10n-safe) EXCEPT for
// the Google Calendar "31" numeral and the brand-literal section titles
// (BEAUTY PASSPORT, BEAUTY TIMELINE) which are intentionally untranslated
// per the locked product decision.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';

// ---------------------------------------------------------------------------
// Hoisted static style constants (PERF: no per-frame TextStyle allocation)
// ---------------------------------------------------------------------------

// These are module-private constants so they do not pollute the exported API.
TextStyle _statCaptionBase() => VelvetText.statCaption();
TextStyle _sectionLabelBase() => VelvetText.sectionLabel();

// ---------------------------------------------------------------------------
// HubAvatar — circular gradient avatar with initials
// ---------------------------------------------------------------------------

/// A circular camel-gradient avatar stand-in for a network photo.
class HubAvatar extends StatelessWidget {
  const HubAvatar({
    super.key,
    required this.initials,
    this.size = 64,
    this.fontSize = 20,
  });

  final String initials;
  final double size;
  final double fontSize;

  static const _gradientColors = <Color>[
    BrandColors.accentLogo,
    BrandColors.accent,
    BrandColors.accentLatte,
  ];

  // Cached per-size TextStyle map to avoid per-build copyWith allocations.
  // HubAvatar is used with a small fixed set of fontSize values (20, 30).
  static final Map<double, TextStyle> _textStyleCache = {};
  TextStyle get _textStyle => _textStyleCache.putIfAbsent(
    fontSize,
    () => VelvetText.displayName().copyWith(
      fontSize: fontSize,
      color: BrandColors.white,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradientColors,
          stops: <double>[0.0, 0.55, 1.0],
        ),
      ),
      child: Center(child: Text(initials, style: _textStyle)),
    );
  }
}

// ---------------------------------------------------------------------------
// HubPhoto — rounded-rect gradient photo placeholder
// ---------------------------------------------------------------------------

/// A rounded-rect camel-gradient photo placeholder. Shows initials centred.
class HubPhoto extends StatelessWidget {
  const HubPhoto({
    super.key,
    required this.initials,
    this.size = 96,
    this.radius = 18,
    this.fontSize = 24,
  });

  final String initials;
  final double size;
  final double radius;
  final double fontSize;

  static const _gradientColors = <Color>[
    BrandColors.accentLogo,
    BrandColors.accent,
    BrandColors.accentLatte,
  ];

  // Cached per-size TextStyle map to avoid per-build copyWith allocations.
  // HubPhoto is used with a small fixed set of fontSize values (20, 24).
  static final Map<double, TextStyle> _textStyleCache = {};
  TextStyle get _textStyle => _textStyleCache.putIfAbsent(
    fontSize,
    () => VelvetText.displayName().copyWith(
      fontSize: fontSize,
      color: BrandColors.white,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradientColors,
          stops: <double>[0.0, 0.55, 1.0],
        ),
      ),
      child: Center(child: Text(initials, style: _textStyle)),
    );
  }
}

// ---------------------------------------------------------------------------
// HubSectionTitle
// ---------------------------------------------------------------------------

/// A standalone section label drawn flat on the background, with an optional
/// right-aligned [trailing].
class HubSectionTitle extends StatelessWidget {
  const HubSectionTitle({
    super.key,
    required this.title,
    this.trailing,
    this.literal = false,
  });

  final String title;
  final Widget? trailing;

  /// When true, the label is rendered with wider tracking (BEAUTY PASSPORT /
  /// BEAUTY TIMELINE — locked English product constants, never translated).
  final bool literal;

  // Precomputed to avoid per-build TextStyle.copyWith allocations.
  static final TextStyle _literalStyle = VelvetText.homeSectionLiteral;

  static final TextStyle _normalStyle = _sectionLabelBase().copyWith(
    letterSpacing: 1.0,
    color: BrandColors.textSecondary,
    fontWeight: FontWeight.w700,
  );

  @override
  Widget build(BuildContext context) {
    final TextStyle style = literal ? _literalStyle : _normalStyle;
    return Row(
      children: <Widget>[
        Expanded(child: Text(title.toUpperCase(), style: style)),
        ?trailing,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// HubSeeAllLink
// ---------------------------------------------------------------------------

/// A subtle right-aligned "see all" link: text + chevron in muted tone.
class HubSeeAllLink extends StatelessWidget {
  const HubSeeAllLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  static final TextStyle _style = VelvetText.homeSeeAllLink;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        key: const Key('hub_see_all_link'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(label, style: _style),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: BrandColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HubFlatCard
// ---------------------------------------------------------------------------

// Memoized card decoration — computes each unique radius once and caches it.
// HubFlatCard is used with a small fixed set of radii (16, 18, 20) so the map
// stays tiny while eliminating the per-build BoxDecoration + BoxShadow allocation.
final Map<double, BoxDecoration> _flatCardDecorationCache = {};
BoxDecoration _flatCardDecoration(double radius) =>
    _flatCardDecorationCache.putIfAbsent(
      radius,
      () => BoxDecoration(
        color: BrandColors.white.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: BrandColors.shadowLightStrong.withValues(alpha: 0.9),
          width: 1,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: BrandColors.shadowDarkCard.withValues(alpha: 0.45),
            offset: const Offset(0, 6),
            blurRadius: 16,
          ),
        ],
      ),
    );

/// A flat, airy surface card: very light fill + hairline border, near-flat
/// elevation. Matches the reference mockup's "HubFlatCard" verbatim.
class HubFlatCard extends StatelessWidget {
  const HubFlatCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(VelvetSpacing.md),
    this.radius = 20,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget card = DecoratedBox(
      decoration: _flatCardDecoration(radius),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CountdownChip
// ---------------------------------------------------------------------------

/// A live countdown pill that ticks toward the next appointment.
class CountdownChip extends StatefulWidget {
  const CountdownChip({super.key, required this.target});

  final DateTime target;

  @override
  State<CountdownChip> createState() => _CountdownChipState();
}

class _CountdownChipState extends State<CountdownChip> {
  late Timer _timer;
  late Duration _remaining;

  static final TextStyle _labelStyle = VelvetText.homeCountdownLabel;

  @override
  void initState() {
    super.initState();
    _remaining = widget.target.difference(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _remaining = widget.target.difference(DateTime.now()));
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String get _label {
    if (_remaining.isNegative) return 'Зараз'; // intentional – time label
    final int days = _remaining.inDays;
    final int hours = _remaining.inHours % 24;
    final int minutes = _remaining.inMinutes % 60;
    if (days > 0) return 'Через $days дн';
    if (hours > 0) return 'Через $hours год';
    return 'Через $minutes хв';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.schedule_rounded, size: 15, color: BrandColors.accent),
        const SizedBox(width: VelvetSpacing.xs + 1),
        Text(_label, style: _labelStyle),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// HubFilledButton
// ---------------------------------------------------------------------------

/// A filled camel/mocha primary action (e.g. "Перенести"). Compact pill.
class HubFilledButton extends StatefulWidget {
  const HubFilledButton({
    super.key,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  final String label;
  final VoidCallback onTap;

  /// When true the button swaps its label for a spinner and ignores taps —
  /// used while an action seeded from this button is loading (e.g. the
  /// reschedule navigation's up-to-two seeding GETs).
  final bool loading;

  @override
  State<HubFilledButton> createState() => _HubFilledButtonState();
}

class _HubFilledButtonState extends State<HubFilledButton> {
  bool _pressed = false;

  static final TextStyle _style = VelvetText.cta135;

  @override
  Widget build(BuildContext context) {
    final bool loading = widget.loading;
    return Semantics(
      button: true,
      enabled: !loading,
      label: widget.label,
      child: GestureDetector(
        onTapDown: loading ? null : (_) => setState(() => _pressed = true),
        onTapCancel: loading ? null : () => setState(() => _pressed = false),
        onTapUp: loading
            ? null
            : (_) {
                setState(() => _pressed = false);
                widget.onTap();
              },
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: const Duration(milliseconds: 110),
          child: Container(
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: BrandColors.accent,
              borderRadius: BorderRadius.circular(12),
            ),
            // Overflow-hardening: scale the label down instead of clipping when
            // the button is squeezed (narrow widths + large font scale).
            child: loading
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: BrandColors.white,
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _style,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HubOutlineButton
// ---------------------------------------------------------------------------

/// An outline secondary action (e.g. "Скасувати"). Tinted mocha or error.
class HubOutlineButton extends StatefulWidget {
  const HubOutlineButton({
    super.key,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.loading = false,
    this.spinnerPaused = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  /// When true the button swaps its label for a spinner and ignores taps —
  /// mirrors [HubFilledButton.loading]. Used while an action seeded from this
  /// button is loading (e.g. the shared cancel navigation's booking-detail
  /// GET before the confirmation dialog can show).
  final bool loading;

  /// When true AND [loading] is true, the spinner stops TICKING (rendered as
  /// a static frame) instead of animating.
  ///
  /// Phase 225 audit-fix cycle 3 (mobile-perf LOW): `loading` alone spans the
  /// shared cancel navigation's ENTIRE flow — load, confirm dialog, and the
  /// write — by design (see `booking_cancel_navigation.dart`'s RE-ENTRANCY
  /// note), including the dialog-open window, which is a user-paced,
  /// unbounded duration. `CancelBookingDialog` opens via `showDialog` with
  /// `useRootNavigator: true`, mounting on the ROOT Navigator — a different
  /// Navigator from the Home Hub branch this button lives in — so the
  /// `StatefulShellRoute.indexedStack` offstage-pause that mutes a genuinely
  /// INACTIVE branch's `TickerMode` never applies: the Home Hub branch stays
  /// active, merely covered by a non-opaque `DialogRoute`. Callers pass
  /// `spinnerPaused: true` for exactly that covered window (see
  /// `bookingCancelDialogVisibleProvider` /
  /// `booking_cancel_dialog_visible_notifier.dart`) so the ticker doesn't
  /// keep calling `scheduleFrame()` at vsync while it is fully obscured.
  /// The button stays disabled/non-tappable via [loading] regardless of this
  /// flag — this only gates the animation, never the guard.
  final bool spinnerPaused;

  @override
  State<HubOutlineButton> createState() => _HubOutlineButtonState();
}

class _HubOutlineButtonState extends State<HubOutlineButton> {
  bool _pressed = false;

  // Pre-composed per-variant styles — avoids per-build copyWith allocation.
  static final TextStyle _styleSafe = VelvetText.cta135.copyWith(
    color: BrandColors.accentDeep,
  );
  static final TextStyle _styleDanger = VelvetText.cta135.copyWith(
    color: BrandColors.error,
  );

  @override
  Widget build(BuildContext context) {
    final bool loading = widget.loading;
    final Color fg = widget.danger ? BrandColors.error : BrandColors.accentDeep;
    final TextStyle style = widget.danger ? _styleDanger : _styleSafe;
    return Semantics(
      button: true,
      enabled: !loading,
      label: widget.label,
      child: GestureDetector(
        onTapDown: loading ? null : (_) => setState(() => _pressed = true),
        onTapCancel: loading ? null : () => setState(() => _pressed = false),
        onTapUp: loading
            ? null
            : (_) {
                setState(() => _pressed = false);
                widget.onTap();
              },
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: const Duration(milliseconds: 110),
          child: Container(
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: BrandColors.white.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: fg.withValues(alpha: 0.45), width: 1.2),
            ),
            // Overflow-hardening: scale the label down instead of clipping when
            // the button is squeezed (narrow widths + large font scale).
            child: loading
                ? SizedBox(
                    height: 16,
                    width: 16,
                    // TickerMode(enabled: false) freezes the indeterminate
                    // animation without hiding it — a static ring, not a
                    // blank box — while `widget.spinnerPaused` is true (the
                    // confirm dialog is covering this button). See
                    // `spinnerPaused`'s doc for why the offstage-pause
                    // machinery doesn't already handle this.
                    child: TickerMode(
                      enabled: !widget.spinnerPaused,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: fg,
                      ),
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HubSquareIconButton
// ---------------------------------------------------------------------------

/// A small square icon button (Google Calendar / Apple).
class HubSquareIconButton extends StatefulWidget {
  const HubSquareIconButton({
    super.key,
    required this.builder,
    required this.semanticLabel,
    required this.onTap,
  });

  final WidgetBuilder builder;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  State<HubSquareIconButton> createState() => _HubSquareIconButtonState();
}

class _HubSquareIconButtonState extends State<HubSquareIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1,
          duration: const Duration(milliseconds: 110),
          child: Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              color: BrandColors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: BrandColors.faint.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Center(child: widget.builder(context)),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HubEmptyState
// ---------------------------------------------------------------------------

/// A calm in-card empty state: a soft glyph well, a one-line message, and an
/// optional CTA.
class HubEmptyState extends StatelessWidget {
  const HubEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.ctaLabel,
    this.onCta,
    this.iconWidget,
  });

  final IconData icon;
  final String message;
  final String? ctaLabel;
  final VoidCallback? onCta;

  /// Optional widget rendered in place of the [icon] glyph (e.g. a tinted SVG
  /// [AppIcon]). When non-null, [icon] is ignored. Mirrors the StatTile pattern.
  final Widget? iconWidget;

  static final TextStyle _msgStyle = VelvetText.body14;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          height: 52,
          width: 52,
          decoration: BoxDecoration(
            color: BrandColors.white.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(color: BrandColors.faint.withValues(alpha: 0.5)),
          ),
          child: iconWidget ?? Icon(icon, size: 24, color: BrandColors.faint),
        ),
        const SizedBox(height: VelvetSpacing.md),
        Text(message, textAlign: TextAlign.center, style: _msgStyle),
        if (ctaLabel != null && onCta != null) ...<Widget>[
          const SizedBox(height: VelvetSpacing.md),
          HubFilledButton(label: ctaLabel!, onTap: onCta!),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// GoogleCalendarGlyph
// ---------------------------------------------------------------------------

/// Paints a small Google-Calendar-style glyph so the app needs no brand assets.
class GoogleCalendarGlyph extends StatelessWidget {
  const GoogleCalendarGlyph({super.key, this.size = 20});

  final double size;

  static const Color _googleBlue = Color(0xFF1A73E8);
  static const Color _googleFrame = Color(0xFFDADCE0);

  // Cached per-size styles — avoids per-build copyWith allocation.
  // All call sites use the default size (20); the map keeps the cache
  // correct if a non-default size is ever passed.
  static final Map<double, TextStyle> _textStyleCache = {};
  TextStyle get _textStyle => _textStyleCache.putIfAbsent(
    size,
    () => _statCaptionBase().copyWith(
      fontSize: size * 0.5,
      height: 1,
      color: _googleBlue,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
  );

  // Cached per-size BoxDecoration map — avoids allocating a new BoxDecoration
  // (+ BoxShadow list + BoxBorder) on every build() call.
  static final Map<double, BoxDecoration> _decorationCache = {};
  BoxDecoration get _decoration => _decorationCache.putIfAbsent(
    size,
    () => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(size * 0.16),
      border: Border.all(color: _googleFrame, width: 1),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.10),
          blurRadius: 1.5,
          offset: const Offset(0, 0.5),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      width: size,
      child: DecoratedBox(
        decoration: _decoration,
        child: Center(child: Text('31', style: _textStyle)),
      ),
    );
  }
}
