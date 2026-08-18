// Phase 4.2 — ProfileAvatar and RoleChip for master-profile screens.
//
// Ported verbatim from the approved preview app at
// `docs/signup-designs/MasterProfileScreen/lib/widgets/profile_widgets.dart`.
//
// Changes from the preview:
//   • VelvetColors.* → BrandColors.*
//   • VelvetSpacing.* unchanged (same constants in velvet_geometry.dart)
//   • VelvetSizes.avatar not in production VelvetSizes — using the preview
//     value 104 directly via the named constant [ProfileAvatar.kDiameter].

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
// Phase 13.6 — ContactTile moved to `shared/widgets/` for cross-feature reuse
// (the salon public profile also renders a contact row). Re-exported here so
// every existing `import 'widgets/profile_avatar.dart';` call site keeps
// working unchanged.
export 'package:beautica_mobile/shared/widgets/contact_tile.dart';
// Phase 7.14 — VelvetBottomNavBar moved to `shared/widgets/` for cross-feature
// reuse (the booking feature's MasterBookingsScreen also renders this bar).
// Re-exported here so every existing
// `import 'widgets/profile_avatar.dart';` call site keeps working unchanged.
export 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';

/// The avatar well — a recessed circular well that "sinks" into the surface,
/// holding a camel [Icons.person_outline] placeholder. The concave look reads
/// as an empty photo slot waiting to be filled (Phase 4.4).
///
/// The production [NeumorphicInset] does not support a `circle` parameter, so
/// this widget paints the inset inner-shadow effect directly via a circular
/// [CustomPaint] layer, then clips child content with [ClipOval].
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, this.diameter = kDiameter});

  /// Default avatar diameter — matches the preview spec (96–112 px band).
  static const double kDiameter = 104;

  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Фото профілю',
      image: true,
      child: SizedBox(
        key: const Key('master-profile-avatar'),
        height: diameter,
        width: diameter,
        child: CustomPaint(
          painter: const _CircleInsetPainter(),
          child: ClipOval(
            child: ColoredBox(
              color: BrandColors.base,
              child: Center(
                child: Icon(
                  Icons.person_outline,
                  color: BrandColors.accent,
                  size: diameter * 0.42,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the neumorphic inset inner-shadow effect on a circular shape.
///
/// Mirrors the logic of [_InsetShadowPainter] in `neumorphic.dart` but
/// clips to [Rect.fromLTWH] as a full circle (no rounded rect needed).
class _CircleInsetPainter extends CustomPainter {
  const _CircleInsetPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.width / 2;
    final Offset center = Offset(r, r);

    final Paint dark = Paint()
      ..color = BrandColors.shadowDarkButton
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final Paint light = Paint()
      ..color = BrandColors.shadowLightStrong
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final Paint fill = Paint()..color = BrandColors.base;

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: r)),
    );

    // Dark inner shadow from top-left.
    canvas.drawCircle(center.translate(-5, -5), r, dark);
    // Light inner shadow from bottom-right.
    canvas.drawCircle(center.translate(5, 5), r, light);
    // Re-fill the centre with base tone — only rim glows remain.
    canvas.drawCircle(center, r - 4, fill);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_CircleInsetPainter oldDelegate) => false;
}

/// A small recessed pill for the role label ("Незалежний майстер").
///
/// Inset treatment signals non-tappable badge rather than an action.
class RoleChip extends StatelessWidget {
  const RoleChip({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return NeumorphicInset(
      radius: 999,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.md,
          vertical: VelvetSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 14, color: BrandColors.accentDeep),
              const SizedBox(width: VelvetSpacing.xs - 2),
            ],
            Flexible(
              child: Text(
                label,
                // Fix 3: use 11 sp variant so 'Незалежний майстер' fits on
                // typical phone widths; soft-wrap allowed (no ellipsis).
                style: VelvetText.feedbackAccentXs,
                softWrap: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ServiceTile
// ---------------------------------------------------------------------------

/// A tappable service row — photo thumbnail left, name + duration centre,
/// price right. Raises on its own neumorphic shadow; depresses on press.
///
/// Ported verbatim from
/// `docs/signup-designs/MasterProfileScreen/lib/widgets/profile_widgets.dart`.
/// `VelvetColors.*` → `BrandColors.*`; all VelvetSpacing/VelvetRadii/VelvetShadows
/// are identical in production.
class ServiceTile extends StatefulWidget {
  const ServiceTile({
    super.key,
    required this.name,
    required this.duration,
    required this.price,
    required this.photoGradient,
  });

  final String name;
  final String duration;
  final String price;
  final List<Color> photoGradient;

  @override
  State<ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends State<ServiceTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${widget.name}, ${widget.duration}, ${widget.price}',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          decoration: BoxDecoration(
            color: BrandColors.base,
            borderRadius: BorderRadius.circular(VelvetRadii.field),
            boxShadow: _pressed ? null : VelvetShadows.extrudedSmall,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: VelvetSpacing.sm + 4,
            vertical: VelvetSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              // Photo thumbnail — gradient fill simulates a real photo.
              ClipRRect(
                borderRadius: BorderRadius.circular(VelvetRadii.field - 6),
                child: Container(
                  height: 38,
                  width: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: widget.photoGradient,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.spa_outlined,
                      size: 18,
                      color: BrandColors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: VelvetSpacing.md),
              // Vertical layout: full-width name on top, then a metadata row
              // pairing the duration (left) with the price pill (right). This
              // lets long names ellipsize without competing with the price for
              // horizontal space, eliminating the persistent row overflow.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Line 1 — service name, full width.
                    Text(
                      widget.name,
                      style: VelvetText.bodyStrong(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: VelvetSpacing.xs + 1),
                    // Line 2 — duration (left) · price pill (right).
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.schedule_outlined,
                          size: 12,
                          color: BrandColors.muted,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            widget.duration,
                            // M-2 fix: pre-composed static; zero per-frame
                            // allocation.
                            style: VelvetText.serviceDurationLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(width: VelvetSpacing.sm),
                        // Price pill — capped so an extreme value can never
                        // push the second row into overflow.
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: NeumorphicInset(
                            radius: 999,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: VelvetSpacing.sm + 2,
                                vertical: VelvetSpacing.xs + 1,
                              ),
                              child: Text(
                                widget.price,
                                // M-2 fix: pre-composed static; zero per-frame
                                // allocation.
                                style: VelvetText.servicePriceLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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
// StatTile
// ---------------------------------------------------------------------------

/// A single raised stat tile — icon → value → caption centred in a column.
///
/// Used in the 4-up stats row (bookings/rating/services/reviews).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.caption,
    this.iconColor = BrandColors.accent,
    this.valueKey,
    this.iconWidget,
  });

  final IconData icon;
  final String value;
  final String caption;
  final Color iconColor;

  /// Optional [Key] placed on the value [Text] — used by widget tests.
  final Key? valueKey;

  /// Optional widget rendered in place of the [icon] glyph (e.g. a tinted
  /// SVG [AppIcon] or a [RatingStar]). When non-null, [icon]/[iconColor] are
  /// ignored. Mirrors the location-marker swap pattern.
  final Widget? iconWidget;

  /// The em-dash a caller passes as [value] for a zero / unresolved state.
  ///
  /// Public so the placeholder contract lives in ONE place: callers that render
  /// it (the rating / reviews / experience tiles here, [ServicesStatTile]'s
  /// `null || 0` branch) and the semantics mapping below cannot drift apart.
  static const String noDataGlyph = '—';

  /// The glyph a caller passes as [value] for a FAILED load
  /// ([ServicesStatTile.hasError]). Deliberately distinct from
  /// [noDataGlyph] — a suppressed response must never read as an empty one.
  static const String loadFailedGlyph = '?';

  /// The spoken form of this tile.
  ///
  /// A bare glyph is meaningless read aloud — the zero-state used to announce
  /// "— Послуги" / "— Рейтинг" / "— Відгуки", and a failed load announced
  /// "? Послуги". Both now get an explicit phrase. Purely a semantics
  /// concern: the VISUAL [value] is rendered untouched either way, so the
  /// sighted layout is byte-identical.
  ///
  /// The l10n lookup is lazy — a tile with a real value never touches
  /// [AppLocalizations], so hosts that pump a bare [StatTile] without
  /// localization delegates keep working.
  String _semanticsLabel(BuildContext context) {
    if (value == noDataGlyph) {
      return AppLocalizations.of(context).statTileNoDataSemantics(caption);
    }
    if (value == loadFailedGlyph) {
      return AppLocalizations.of(context).statTileLoadFailedSemantics(caption);
    }
    return '$value $caption';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _semanticsLabel(context),
      // The value/caption [Text]s below otherwise MERGE into this node and get
      // appended to the label — the tile announced
      // "Послуги: немає даних | — | Послуги", i.e. the meaningless glyph this
      // label exists to replace came straight back, plus a duplicated caption.
      // Excluding the descendants leaves exactly the composed label. Affects
      // the semantics tree ONLY — the rendered widget subtree is untouched.
      excludeSemantics: true,
      child: NeumorphicCard(
        padding: const EdgeInsets.symmetric(
          vertical: VelvetSpacing.xs,
          horizontal: VelvetSpacing.xs,
        ),
        radius: VelvetRadii.field + 2,
        shadows: VelvetShadows.extrudedSmall,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              iconWidget ?? Icon(icon, size: 18, color: iconColor),
              const SizedBox(height: VelvetSpacing.xs),
              Text(value, key: valueKey, style: VelvetText.statValue()),
              const SizedBox(height: 1),
              Text(
                caption,
                style: VelvetText.statCaption(),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
