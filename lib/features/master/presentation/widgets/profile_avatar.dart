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
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/routing/route_names.dart';

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
// ContactTile
// ---------------------------------------------------------------------------

/// A tappable raised contact row (phone / Instagram). A small inset glyph well
/// on the left, the value in the middle, a chevron on the right. Depresses on
/// press to confirm the tap.
///
/// When [label] is provided (e.g. "Instagram"), it renders as a muted caption
/// above [value], turning the text column into a two-line block so the platform
/// is always clear without relying on a branded icon.
///
/// Ported verbatim from
/// `docs/signup-designs/MasterProfileScreen/lib/widgets/profile_widgets.dart`.
/// `VelvetColors.*` → `BrandColors.*`; all VelvetSpacing/VelvetRadii/VelvetShadows
/// are identical in production.
class ContactTile extends StatefulWidget {
  const ContactTile({
    super.key,
    required this.icon,
    required this.value,
    required this.onTap,
    required this.semanticLabel,
    this.label,
  });

  final IconData icon;
  final String value;
  final VoidCallback onTap;
  final String semanticLabel;

  /// Optional platform label shown above [value] in muted caption style.
  final String? label;

  @override
  State<ContactTile> createState() => _ContactTileState();
}

class _ContactTileState extends State<ContactTile> {
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
          scale: _pressed ? 0.985 : 1,
          duration: const Duration(milliseconds: 110),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: BrandColors.base,
              borderRadius: BorderRadius.circular(VelvetRadii.field),
              boxShadow: _pressed ? null : VelvetShadows.extrudedSmall,
            ),
            padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
            child: Row(
              children: <Widget>[
                SizedBox(
                  height: 40,
                  width: 40,
                  child: NeumorphicInset(
                    radius: VelvetRadii.field - 4,
                    child: Center(
                      child: Icon(
                        widget.icon,
                        size: 18,
                        color: BrandColors.accentDeep,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: VelvetSpacing.md),
                Expanded(
                  child: widget.label != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              widget.label!,
                              // M-2 fix: pre-composed static; zero per-frame
                              // allocation.
                              style: VelvetText.contactPlatformLabel,
                            ),
                            const SizedBox(height: 2),
                            Text(widget.value, style: VelvetText.bodyStrong()),
                          ],
                        )
                      : Text(widget.value, style: VelvetText.bodyStrong()),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: BrandColors.faint,
                ),
              ],
            ),
          ),
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
// VelvetBottomNavBar
// ---------------------------------------------------------------------------

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Full left→right layout: [Послуги(0)] [Мої записи(1)] [Календар(2)] [Профіль(3)].
const List<_NavItem> _navItems = <_NavItem>[
  _NavItem(
    icon: Icons.design_services_outlined,
    activeIcon: Icons.design_services_rounded,
    label: 'Послуги',
  ),
  _NavItem(
    icon: Icons.event_note_outlined,
    activeIcon: Icons.event_note_rounded,
    label: 'Мої записи',
  ),
  _NavItem(
    icon: Icons.calendar_month_outlined,
    activeIcon: Icons.calendar_month_rounded,
    label: 'Календар',
  ),
  _NavItem(
    icon: Icons.person_outline,
    activeIcon: Icons.person_rounded,
    label: 'Профіль',
  ),
];

/// Neumorphic bottom navigation bar for the master-profile shell. The bar is
/// extruded from the surface — a top-facing light highlight raises it above the
/// content, the dark shadow anchors it to the page floor.
///
/// [activeIndex] selects the highlighted item (0 = Послуги, 1 = Мої записи,
/// 2 = Календар, 3 = Профіль). A camel accent pill floats above the active icon.
///
/// Ported verbatim from
/// `docs/signup-designs/MasterProfileScreen/lib/widgets/profile_widgets.dart`.
/// `VelvetColors.*` → `BrandColors.*`.
class VelvetBottomNavBar extends StatelessWidget {
  const VelvetBottomNavBar({super.key, required this.activeIndex});

  final int activeIndex;

  static const BorderRadius _pillRadius = BorderRadius.all(Radius.circular(28));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.md,
        0,
        VelvetSpacing.md,
        VelvetSpacing.md,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: BrandColors.base,
          borderRadius: _pillRadius,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: BrandColors.shadowLightStrong,
              offset: Offset(-6, -6),
              blurRadius: 16,
            ),
            BoxShadow(
              color: BrandColors.shadowDarkCard,
              offset: Offset(6, 6),
              blurRadius: 16,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: _pillRadius,
          child: SafeArea(
            top: false,
            // ConstrainedBox (minHeight, not a fixed SizedBox height) so the bar
            // grows with the tile's intrinsic content at large text scales
            // (textScale 1.3 pushed the icon + pill + label past a fixed 62 dp
            // and overflowed the nav tile column by 5 px). IntrinsicHeight keeps
            // all four tiles the same height as the tallest one.
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 62),
              child: IntrinsicHeight(
                child: Row(
                  children: <Widget>[
                    for (int i = 0; i < _navItems.length; i++)
                      Expanded(
                        child: _VelvetNavTile(
                          key: Key('master-nav-tile-$i'),
                          item: _navItems[i],
                          index: i,
                          active: i == activeIndex,
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

class _VelvetNavTile extends StatelessWidget {
  const _VelvetNavTile({
    super.key,
    required this.item,
    required this.index,
    required this.active,
  });

  final _NavItem item;
  final int index;
  final bool active;

  /// Resolves the go_router path for a nav-bar [index]. Returns `null` when the
  /// tile has no destination yet (e.g. "Мої записи" has no route) — the tap is
  /// then a no-op. Tapping the already-active tile also resolves to `null` so
  /// we never issue a redundant navigation to the current location.
  String? _routeFor(int index) {
    if (active) return null;
    return switch (index) {
      0 => RouteNames.services, // Послуги
      2 => RouteNames.masterSchedule, // Календар → Phase 15.2 schedule screen
      _ => null, // Мої записи (1) — no route yet; Профіль (3) — current shell.
    };
  }

  @override
  Widget build(BuildContext context) {
    final Color color = active ? BrandColors.accentDeep : BrandColors.muted;
    final String? route = _routeFor(index);

    return Semantics(
      label: item.label,
      selected: active,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: route == null ? null : () => context.push(route),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // Camel pill indicator above the active icon.
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: active ? 26 : 0,
              height: 3,
              margin: const EdgeInsets.only(bottom: VelvetSpacing.xs),
              decoration: BoxDecoration(
                gradient: active
                    ? const LinearGradient(
                        colors: <Color>[
                          BrandColors.accentDeep,
                          BrandColors.accent,
                        ],
                      )
                    : null,
                color: active ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Icon(active ? item.activeIcon : item.icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              item.label,
              // M-1 fix: pre-composed base; one copyWith for the dynamic color
              // instead of two allocations (feedback() + copyWith) per frame.
              style: VelvetText.navTabLabel.copyWith(color: color),
            ),
          ],
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
  });

  final IconData icon;
  final String value;
  final String caption;
  final Color iconColor;

  /// Optional [Key] placed on the value [Text] — used by widget tests.
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$value $caption',
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
              Icon(icon, size: 18, color: iconColor),
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
