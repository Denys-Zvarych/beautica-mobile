// Phase 21.8 — Salon-role bottom navigation bar (SALON_OWNER / SALON_ADMIN
// shell).
//
// Ported verbatim from the approved preview app
// `docs/signup-designs/SalonManagementDesign/lib/widgets/salon_bottom_nav.dart`
// (`VelvetColors.*` → `BrandColors.*`; `VelvetText`/`VelvetSpacing` resolve to
// the project tokens). Structurally a 1:1 match of the shipped CLIENT bar
// (`lib/features/shell/presentation/widgets/client_bottom_nav.dart`) minus
// the client-only elevated center disc: a floating rounded pill (all four
// corners `radius 28`), a dual-direction neumorphic extruded shadow, and a
// thin gradient indicator bar that animates in above the active icon.
//
// SCOPE (Phase 21.8): only [SalonBottomNav.ownerAdminItems] is shipped — the
// design source's `ownerMasterPersonalItems` (owner-as-master 5-tab set,
// Phase 21.15) and `masterItems` (Phase 21.18, SALON_MASTER shell) are
// deliberately NOT ported yet; their source fields
// (`UserProfileResponse.masterProfile`, the master-shell hosts) don't exist
// in this codebase today. Widening this item-set list later is an ADDITIVE
// change (a new static const list), never a fork of this file.
//
// Lives in `lib/shared/widgets/`, NOT `features/salon/presentation/widgets/`
// — Phase 21.18's future SALON_MASTER shell is a DIFFERENT feature, and
// cross-feature `presentation/` imports are illegal per the architecture.
// Promoted here now rather than letting a later phase fork it (REUSE-FIRST).

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// One destination in the salon bottom navigation bar. Carries an
/// outline/filled icon pair so the active tab swaps to the filled glyph.
///
/// Supports two icon sources, mirroring [ClientNavItem]
/// (`features/shell/presentation/widgets/client_bottom_nav.dart`, REUSE-FIRST
/// — same field names, same precedence, same fallback):
///   - **Material** (default): supply [icon] and [activeIcon] as [IconData].
///   - **SVG asset**: supply [svgIcon] and [svgActiveIcon] as paths from
///     [BeauticaAssetIcons]. When non-null these take precedence over the
///     [IconData] fields — a tile renders `AppIcon(path)` instead of `Icon`.
///
/// Exactly one source should be provided per item; [svgIcon] always wins
/// when non-null.
class SalonNavItem {
  const SalonNavItem({
    required this.label,
    this.icon,
    this.activeIcon,
    this.svgIcon,
    this.svgActiveIcon,
  });

  final String label;

  /// Inactive (outline) glyph. Ignored when [svgIcon] is set.
  final IconData? icon;

  /// Active (filled) glyph. Ignored when [svgActiveIcon] is set.
  final IconData? activeIcon;

  /// SVG asset path (from [BeauticaAssetIcons]) for the inactive state. When
  /// non-null, [AppIcon] is rendered instead of [Icon].
  final String? svgIcon;

  /// SVG asset path (from [BeauticaAssetIcons]) for the active/selected
  /// state. When non-null, [AppIcon] is rendered instead of [Icon].
  final String? svgActiveIcon;

  /// Whether this item uses SVG rather than Material [IconData].
  bool get isSvg => svgIcon != null;
}

/// The salon-role bottom navigation bar. Purely presentational — the parent
/// owns the selected index and the item set.
class SalonBottomNav extends StatelessWidget {
  const SalonBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final List<SalonNavItem> items;

  static const double _barHeight = 64;
  static const BorderRadius _barRadius = BorderRadius.all(Radius.circular(28));

  static const List<BoxShadow> _barShadow = <BoxShadow>[
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
  ];

  /// Admin's fixed set, and the owner's set (Phase 21.8 scope — the
  /// owner-as-master 5-tab replacement is Phase 21.15, not shipped here).
  /// **Admin always uses exactly this list**, so admin's nav shape can never
  /// change out from under it.
  ///
  /// A method (not a `static const` list, unlike the preview source) because
  /// labels come from [AppLocalizations] — never hard-coded Ukrainian in
  /// shipped `lib/` source (`no_raw_ui_strings` is CI-fatal).
  static List<SalonNavItem> ownerAdminItems(AppLocalizations l10n) =>
      <SalonNavItem>[
        SalonNavItem(
          label: l10n.salonShellTabSalon,
          svgIcon: BeauticaAssetIcons.homeOutline,
          svgActiveIcon: BeauticaAssetIcons.homeFilled,
        ),
        SalonNavItem(
          label: l10n.salonShellTabBookings,
          // Matches the independent-master shell's «Мої записи» tab glyph —
          // `velvet_bottom_nav_bar.dart` lines 45–58.
          icon: Icons.event_note_outlined,
          activeIcon: Icons.event_note_rounded,
        ),
        SalonNavItem(
          label: l10n.salonShellTabTeam,
          svgIcon: BeauticaAssetIcons.teamOutline,
          svgActiveIcon: BeauticaAssetIcons.teamFilled,
        ),
        SalonNavItem(
          label: l10n.salonShellTabProfile,
          // Matches the independent-master shell's «Профіль» tab glyph —
          // `velvet_bottom_nav_bar.dart` lines 45–58 (note: `person_outline`,
          // not `person_outline_rounded`, to match exactly).
          icon: Icons.person_outline,
          activeIcon: Icons.person_rounded,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    // Floating pill: an outer margin lets the taupe base show behind and
    // around the bar so its all-sides shadow reads as elevation.
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
          borderRadius: _barRadius,
          boxShadow: _barShadow,
        ),
        child: ClipRRect(
          borderRadius: _barRadius,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: _barHeight,
              child: Row(
                children: <Widget>[
                  for (int i = 0; i < items.length; i++)
                    Expanded(
                      child: _NavCell(
                        key: Key('salon-nav-tile-$i'),
                        item: items[i],
                        active: i == currentIndex,
                        onTap: () => onSelect(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single tab: a thin camel→mocha gradient indicator bar animates in ABOVE
/// the icon when active (grows from width 0 → 24, height 3, rounded ends);
/// the icon swaps outline→filled and warms muted→mocha. Depresses slightly on
/// tap for tactile feedback — matches the shipped `_ClientNavTile`.
class _NavCell extends StatefulWidget {
  const _NavCell({
    super.key,
    required this.item,
    required this.active,
    required this.onTap,
  });

  final SalonNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_NavCell> createState() => _NavCellState();
}

class _NavCellState extends State<_NavCell> {
  bool _pressed = false;

  /// Uniform label box so a two-line wrap never clips. Two lines at
  /// fontSize 9 / line-height 1.1 ≈ 19.8px, rounded up.
  static const double _labelBoxHeight = 22;

  static const LinearGradient _pillGradient = LinearGradient(
    colors: <Color>[BrandColors.accentDeep, BrandColors.accent],
  );

  static final BoxDecoration _pillActiveDecoration = BoxDecoration(
    gradient: _pillGradient,
    borderRadius: BorderRadius.circular(2),
  );
  static const BoxDecoration _pillInactiveDecoration = BoxDecoration(
    borderRadius: BorderRadius.all(Radius.circular(2)),
  );

  @override
  Widget build(BuildContext context) {
    final bool active = widget.active;
    final Color color = active ? BrandColors.accentDeep : BrandColors.muted;
    final TextStyle labelStyle = active
        ? VelvetText.shellNavLabelActive
        : VelvetText.shellNavLabelInactive;

    return Semantics(
      button: true,
      selected: active,
      label: widget.item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1,
          duration: const Duration(milliseconds: 110),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Indicator bar — grows in above the icon when active.
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: active ? 24 : 0,
                height: 3,
                margin: const EdgeInsets.only(bottom: VelvetSpacing.xs),
                decoration: active
                    ? _pillActiveDecoration
                    : _pillInactiveDecoration,
              ),
              if (widget.item.isSvg)
                AppIcon(
                  active
                      ? (widget.item.svgActiveIcon ?? widget.item.svgIcon!)
                      : widget.item.svgIcon!,
                  size: 22,
                  color: color,
                )
              else
                Icon(
                  (active ? widget.item.activeIcon : widget.item.icon) ??
                      Icons.circle,
                  size: 22,
                  color: color,
                ),
              const SizedBox(height: 2),
              SizedBox(
                height: _labelBoxHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Center(
                    child: Text(
                      widget.item.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: labelStyle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
