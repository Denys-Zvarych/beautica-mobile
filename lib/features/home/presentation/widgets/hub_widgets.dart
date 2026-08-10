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

import '../../../../core/media/beautica_image.dart';
import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';

// ---------------------------------------------------------------------------
// Hoisted static style constants (PERF: no per-frame TextStyle allocation)
// ---------------------------------------------------------------------------

// This is a module-private constant so it does not pollute the exported API.
TextStyle _sectionLabelBase() => VelvetText.sectionLabel();

// ---------------------------------------------------------------------------
// HubAvatar — circular gradient avatar with initials
// ---------------------------------------------------------------------------

/// A circular camel-gradient avatar stand-in for a network photo.
///
/// The initials' type scale is DERIVED FROM [size], not passed in. Above
/// [_kPortraitThreshold] the disc is a page-level portrait and takes
/// `displayName`; below it the disc is an in-card mark and takes `statValue`.
/// This is the approved preview's own rule (`docs/signup-designs/BeautyPassport/
/// lib/widgets/hub_widgets.dart:26`) and it exists because a per-call-site
/// `fontSize` is the hole off-scale type walks in through: a 32 dp in-card disc
/// was rendering its initials at 20 pt — a size that appears nowhere in
/// [VelvetText] — purely because that was the parameter's default.
class HubAvatar extends StatelessWidget {
  const HubAvatar({
    super.key,
    required this.initials,
    this.size = 64,
    this.fontSize,
    this.imageUrl,
    this.fallbackIcon,
  });

  final String initials;
  final double size;

  /// An EXPLICIT off-scale override, for the two 96 dp profile portraits that
  /// predate this widget's size-based rule. Leave it null everywhere else: null
  /// is what selects the scale [size] actually calls for.
  final double? fontSize;

  /// An optional network photo. Null (the default, and every call site that
  /// predates this parameter) renders the gradient disc exactly as before —
  /// this is an ADDITIVE, opt-in path, not a replacement of the initials disc.
  /// When set, routes through [RemoteImage]; [isAllowedMediaUrl] failing (a
  /// null/non-https/non-allowed URL, or a decode error) falls through to the
  /// SAME gradient disc, drawing [fallbackIcon] if set, else [initials].
  final String? imageUrl;

  /// Drawn INSIDE the gradient disc instead of [initials] whenever the disc
  /// falls back — either because [imageUrl] is null, or because it failed to
  /// resolve. Null (the default) keeps the initials text. A brand name's
  /// initials read poorly, so a caller with a logo-carrying source (a salon)
  /// should pass its established glyph here rather than relying on text.
  final IconData? fallbackIcon;

  /// At or above this diameter the disc is a page-level portrait, below it an
  /// in-card mark. The preview's `_portraitThreshold`, verbatim: it separates
  /// the profile block (96) from the wish-list discs (38 / 32).
  static const double _kPortraitThreshold = 64;

  static const _gradientColors = <Color>[
    BrandColors.accentLogo,
    BrandColors.accent,
    BrandColors.accentLatte,
  ];

  /// The size-derived scale, hoisted so the common (override-free) path
  /// allocates no [TextStyle] at all.
  static final TextStyle _portraitStyle = VelvetText.displayName().copyWith(
    color: BrandColors.white,
  );
  static final TextStyle _markStyle = VelvetText.statValue().copyWith(
    color: BrandColors.white,
  );

  // Cached per-size TextStyle map for the OVERRIDE path only — a small fixed
  // set of values (27).
  static final Map<double, TextStyle> _textStyleCache = {};

  TextStyle get _textStyle {
    final double? override = fontSize;
    if (override == null) {
      return size >= _kPortraitThreshold ? _portraitStyle : _markStyle;
    }
    return _textStyleCache.putIfAbsent(
      override,
      () => _portraitStyle.copyWith(fontSize: override),
    );
  }

  /// [fallbackIcon]'s size as a fraction of the disc — the same proportion
  /// [ResultThumbnail]'s 32 dp-of-72 dp placeholder glyph uses.
  static const double _kIconSizeRatio = 32 / 72;

  static const BoxDecoration _discDecoration = BoxDecoration(
    shape: BoxShape.circle,
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: _gradientColors,
      stops: <double>[0.0, 0.55, 1.0],
    ),
  );

  /// The gradient disc's content: [fallbackIcon] when the caller supplied
  /// one, else [initials] — the ORIGINAL, only content this widget ever drew
  /// before [imageUrl] existed.
  Widget _discContent() {
    final IconData? icon = fallbackIcon;
    if (icon == null) return Text(initials, style: _textStyle);
    return Icon(icon, size: size * _kIconSizeRatio, color: BrandColors.white);
  }

  Widget _disc() {
    return Container(
      height: size,
      width: size,
      decoration: _discDecoration,
      child: Center(child: _discContent()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? url = imageUrl;
    // Null is the ORIGINAL, still by-far-the-most-common path — every
    // call site that predates this parameter, and every MASTER-row wish-list
    // avatar today. It renders the exact disc this widget always has, with
    // no RemoteImage wrapper in the tree at all — zero behavioural or golden
    // change for any caller that does not pass imageUrl.
    if (url == null) return _disc();
    return RemoteImage(
      url: url,
      width: size,
      height: size,
      shape: RemoteImageShape.circle,
      excludeFromSemantics: true,
      fallback: _disc(),
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
    // widget.target is a canonical UTC appointment instant — a countdown
    // measures elapsed time, not a calendar day.
    // instant-ok: absolute-instant duration
    _remaining = widget.target.difference(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      // instant-ok: absolute-instant duration, same as above.
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
// Compact-button geometry — shared by HubFilledButton and HubOutlineButton
// ---------------------------------------------------------------------------

// The compact hub button's height and corner radius. `velvet_geometry.dart`
// names neither (its `VelvetSizes.cta` is the 49dp full-width CTA, a different
// control), so they live here beside their only two consumers rather than as
// bare numbers repeated in each — the same shape `client_bottom_nav.dart` and
// `HubEmptyState` already use for their own local geometry.
//
// The two buttons MUST share these: the outline variant is the section's
// overflow control sitting directly under a filled «Записатись», and a
// one-pixel difference in height or radius between the two reads as a mistake
// rather than as a hierarchy.
const double _kCompactButtonHeight = 38;
const double _kCompactButtonRadius = 12;

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

  // The locked VelvetTouch CTA fill — camel→mocha, same two colours as
  // `ARCHITECTURE-mobile.md` § 9's "CTA button (neumorphic gradient)" row.
  // A flat `BrandColors.accent` fill paired with the cream label
  // (`VelvetText.cta135`'s own colour) reads as LOW-CONTRAST — accent is a
  // light camel close in luminance to the cream text, so the button looked
  // disabled rather than like the primary action it is. The gradient's mocha
  // end restores the contrast the architecture doc's own accessibility table
  // assumes ("white on accentDeep — ~6:1, AA").
  //
  // Direction is VERTICAL (top→bottom), not the diagonal top-left→bottom-
  // right a first pass used. `cta135` is Comfortaa 11sp/w700 — ordinary text
  // under WCAG (nowhere near the 14pt-bold "large text" floor), so its
  // threshold is 4.5:1, not 3:1. A diagonal's `latte`-end corner sits under
  // exactly the label's leading edge for a natural-width button (no slack
  // between text and padding), so the region nearest that corner is the
  // region most likely to sit under a glyph. A vertical gradient decouples
  // contrast from the label's HORIZONTAL position entirely — every label,
  // whatever its width, sees the same vertical slice — so one measurement
  // covers every caller for good. `stops` biases the midline so no point in
  // the label's bounding box (vertically centred, `cta135` at this size
  // painting roughly y=13..25 inside the 38 dp box) sits closer to `latte`
  // than the gradient's OWN midpoint would: measured worst case under the
  // label is ~5.64:1 (both current labels, «Записатись» and «Обрати
  // майстра» — see `hub_filled_button_contrast_test.dart`), vs. the
  // unbiased vertical's ~5.09:1 and the old diagonal's ~4.6-4.7:1, all of
  // which already clear 4.5:1 but with far less margin against font-metric
  // drift (a fallback glyph, a Comfortaa update) than this leaves.
  static const BoxDecoration _decoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: <double>[0.0, 0.6],
      colors: <Color>[BrandColors.accentLatte, BrandColors.accentDeep],
    ),
    borderRadius: BorderRadius.all(Radius.circular(_kCompactButtonRadius)),
  );

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
            height: _kCompactButtonHeight,
            // Real breathing room around the label rather than the edge-to-edge
            // fit the caller's own oversized width used to fake: a caller that
            // sizes exactly to this button's natural width (any label longer
            // than «Записатись») now gets padding instead of a near-zero-margin
            // FittedBox squeeze. `VelvetSpacing.md` — no new magic number.
            padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.md),
            alignment: Alignment.center,
            decoration: _decoration,
            // Overflow-hardening: scale the label down instead of clipping when
            // the button is squeezed (narrow widths + large font scale). This
            // only engages when a caller gives this `Container` a BOUNDED max
            // width — `Alignment.center` makes it an `Align`, which fills to
            // its incoming max the instant that max is bounded (see
            // `wishlist_row.dart`'s `_kActionWidthCeiling` for the call site
            // that now supplies one, and why it uses `IntrinsicWidth` rather
            // than handing the bound straight to this `Container` — a bare
            // bound here would inflate every label, including ones already
            // under the floor, to the ceiling).
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

/// An outline secondary action (e.g. «Показати всі (5)»). Same compact pill
/// footprint as [HubFilledButton] — [_kCompactButtonHeight],
/// [_kCompactButtonRadius], [VelvetText.cta135] — differing ONLY in fill and
/// stroke.
///
/// Outline is load-bearing, not decoration. This is a section's overflow
/// control, and it sits directly under the camel-filled «Записатись» CTAs that
/// are the section's real actions: a second filled button would read as a
/// second peer action and flatten the hierarchy the section depends on. The
/// face is a near-transparent cream wash rather than nothing at all, so the
/// control still reads as a surface against the warm-taupe base instead of as a
/// floating stroke.
///
/// [danger] swaps the label and stroke to [BrandColors.error] for a destructive
/// secondary action ("Скасувати"). The face is unchanged: the stroke and the
/// label carry the warning, and tinting the fill red as well would make a
/// secondary control shout louder than the primary one beside it.
class HubOutlineButton extends StatefulWidget {
  const HubOutlineButton({
    super.key,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;

  /// Renders the label and stroke in [BrandColors.error] instead of mocha.
  final bool danger;

  @override
  State<HubOutlineButton> createState() => _HubOutlineButtonState();
}

class _HubOutlineButtonState extends State<HubOutlineButton> {
  bool _pressed = false;

  /// The outline button's own two washes, named so the same alpha is never
  /// re-derived by hand at a second call site.
  static const double _kFaceAlpha = 0.4;
  static const double _kStrokeAlpha = 0.45;

  /// Precomputed per foreground colour, mirroring the memoization every other
  /// widget in this file already applies: only two foregrounds exist (mocha and
  /// error), so the map converges at two entries and no `copyWith` /
  /// `BoxDecoration` is allocated per build.
  static final Map<Color, TextStyle> _labelStyleCache = <Color, TextStyle>{};
  static final Map<Color, BoxDecoration> _decorationCache =
      <Color, BoxDecoration>{};

  static TextStyle _labelStyle(Color fg) => _labelStyleCache.putIfAbsent(
    fg,
    () => VelvetText.cta135.copyWith(color: fg),
  );

  static BoxDecoration _decoration(Color fg) => _decorationCache.putIfAbsent(
    fg,
    () => BoxDecoration(
      color: BrandColors.white.withValues(alpha: _kFaceAlpha),
      borderRadius: BorderRadius.circular(_kCompactButtonRadius),
      border: Border.all(color: fg.withValues(alpha: _kStrokeAlpha)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final Color fg = widget.danger ? BrandColors.error : BrandColors.accentDeep;
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        key: const Key('hub_outline_button'),
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: const Duration(milliseconds: 110),
          child: Container(
            height: _kCompactButtonHeight,
            alignment: Alignment.center,
            decoration: _decoration(fg),
            // Overflow-hardening, identical to [HubFilledButton]: scale the
            // label down instead of clipping when the button is squeezed
            // (narrow widths + large font scale).
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _labelStyle(fg),
              ),
            ),
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
