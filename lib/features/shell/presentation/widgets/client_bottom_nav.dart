// Phase 13.1 — CLIENT 5-tab neumorphic bottom navigation bar.
//
// Ported verbatim from the approved preview app
// `docs/signup-designs/ClientShell/lib/widgets/client_bottom_nav.dart`.
// `VelvetColors.*` → `BrandColors.*`; `VelvetText`/`VelvetSpacing` resolve to
// the project tokens. The hard-coded Ukrainian labels in the preview's
// `clientNavItems` are replaced by l10n strings supplied by the caller (the
// shell), except "BEAUTY PASSPORT" which stays an untranslated brand constant.
//
// This is a NEW widget — NOT a parametrisation of the master shell's 4-tile
// `VelvetBottomNavBar` (profile_avatar.dart ~L459), which has no center-disc
// support.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

/// The untranslated 5th-tab brand label. Product decision: "BEAUTY PASSPORT" is
/// never translated, so it is a const and intentionally NOT an l10n key.
// ignore: constant_identifier_names — brand constant, kept verbatim.
const String kBeautyPassportLabel = 'BEAUTY PASSPORT';

/// One flanking tab in the client bottom nav (the 4 non-center items).
class ClientNavItem {
  const ClientNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// The five CLIENT tabs, in left→right index order. Index 2 (Пошук) is the
/// elevated center item and is rendered specially — it is NOT one of the
/// flanking tiles.
///
/// "BEAUTY PASSPORT" is intentionally left untranslated (product decision); the
/// other four labels are localised and threaded in by the caller.
class ClientBottomNav extends StatelessWidget {
  const ClientBottomNav({
    super.key,
    required this.activeIndex,
    required this.onTap,
    required this.homeLabel,
    required this.favoritesLabel,
    required this.searchLabel,
    required this.bookingsLabel,
  });

  /// 0=Головна, 1=Улюблені, 2=Пошук (center), 3=Записи, 4=BEAUTY PASSPORT.
  final int activeIndex;
  final ValueChanged<int> onTap;

  // Localised labels supplied by the shell (no raw UI strings in the widget).
  final String homeLabel;
  final String favoritesLabel;
  final String searchLabel;
  final String bookingsLabel;

  static const double _barHeight = 64;
  static const double _centerSize = 52;

  /// Fixed footprint for each flanking tile and the uniform gap between every
  /// item. The cluster is centered (not edge-to-edge), so these drive how
  /// close the buttons sit; the same gap brackets the center reservation to
  /// keep the disc equidistant from its neighbors.
  static const double _tileWidth = 60;
  static const double _itemGap = 10;
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

  List<ClientNavItem> _items() => <ClientNavItem>[
    ClientNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: homeLabel,
    ),
    ClientNavItem(
      icon: Icons.favorite_outline_rounded,
      activeIcon: Icons.favorite_rounded,
      label: favoritesLabel,
    ),
    // index 2 — Пошук, the elevated center button.
    ClientNavItem(
      icon: Icons.search_rounded,
      activeIcon: Icons.search_rounded,
      label: searchLabel,
    ),
    ClientNavItem(
      icon: Icons.event_note_outlined,
      activeIcon: Icons.event_note_rounded,
      label: bookingsLabel,
    ),
    const ClientNavItem(
      icon: Icons.badge_outlined,
      activeIcon: Icons.badge_rounded,
      label: kBeautyPassportLabel,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final List<ClientNavItem> items = _items();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.md,
        0,
        VelvetSpacing.md,
        VelvetSpacing.md,
      ),
      // The center disc overflows the bar's top edge, so the stack is taller
      // than the bar and clipping is disabled.
      child: SizedBox(
        height: _barHeight + _centerSize / 2,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: <Widget>[
            // ── The raised taupe bar ───────────────────────────────────────
            Align(
              alignment: Alignment.bottomCenter,
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
                      // Tighter layout: instead of spreading four Expanded
                      // tiles edge-to-edge, the items are a centered cluster of
                      // fixed-width tiles separated by a small uniform gap. The
                      // same gap sits on both sides of the center reservation,
                      // so the floating disc stays centered over its notch and
                      // visually equidistant from its two neighbors.
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          _flank(items, 0),
                          const SizedBox(width: _itemGap),
                          _flank(items, 1),
                          const SizedBox(width: _itemGap),
                          // Center gap reserved for the floating disc.
                          const SizedBox(width: _centerSize + _itemGap),
                          _flank(items, 3),
                          const SizedBox(width: _itemGap),
                          _flank(items, 4),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── The elevated center Пошук disc ─────────────────────────────
            Positioned(
              top: 0,
              child: _CenterSearchButton(
                key: const Key('client-nav-search-center'),
                size: _centerSize,
                active: activeIndex == 2,
                semanticLabel: searchLabel,
                onTap: () => onTap(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _flank(List<ClientNavItem> items, int index) {
    return SizedBox(
      width: _tileWidth,
      child: _ClientNavTile(
        key: Key('client-nav-tile-$index'),
        item: items[index],
        active: index == activeIndex,
        onTap: () => onTap(index),
      ),
    );
  }
}

/// A flanking tab: a camel indicator pill animates in above the active icon;
/// the icon swaps to its filled variant and warms to mocha. Unselected glyphs
/// stay muted. Depresses slightly on tap for tactile feedback.
class _ClientNavTile extends StatefulWidget {
  const _ClientNavTile({
    super.key,
    required this.item,
    required this.active,
    required this.onTap,
  });

  final ClientNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_ClientNavTile> createState() => _ClientNavTileState();
}

class _ClientNavTileState extends State<_ClientNavTile> {
  bool _pressed = false;

  /// Uniform height reserved for the label of every tile so a two-line wrap of
  /// "BEAUTY PASSPORT" never clips while shorter labels keep a shared baseline.
  /// Two lines at fontSize 9 / line-height 1.1 ≈ 19.8px, rounded up.
  static const double _labelBoxHeight = 22;

  // Hoisted label styles (one per active/inactive color) — computed once at
  // class-load time so no TextStyle is allocated per build/tap.
  static final TextStyle _labelActive = VelvetText.feedback(
    BrandColors.accentDeep,
  ).copyWith(fontSize: 9, height: 1.1, letterSpacing: 0.1);
  static final TextStyle _labelInactive = VelvetText.feedback(
    BrandColors.muted,
  ).copyWith(fontSize: 9, height: 1.1, letterSpacing: 0.1);

  static const LinearGradient _pillGradient = LinearGradient(
    colors: <Color>[BrandColors.accentDeep, BrandColors.accent],
  );

  @override
  Widget build(BuildContext context) {
    final Color color = widget.active
        ? BrandColors.accentDeep
        : BrandColors.muted;

    return Semantics(
      label: widget.item.label,
      selected: widget.active,
      button: true,
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
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: widget.active ? 24 : 0,
                height: 3,
                margin: const EdgeInsets.only(bottom: VelvetSpacing.xs),
                decoration: BoxDecoration(
                  gradient: widget.active ? _pillGradient : null,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Icon(
                widget.active ? widget.item.activeIcon : widget.item.icon,
                size: 22,
                color: color,
              ),
              const SizedBox(height: 2),
              // Every tile reserves the same two-line label box so the long
              // "BEAUTY PASSPORT" label can wrap to two lines without clipping
              // while the short single-line labels stay vertically centered on
              // the shared baseline (no tile-to-tile jumping).
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
                      style: widget.active ? _labelActive : _labelInactive,
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

/// The elevated center search disc — a camel→mocha gradient circle that floats
/// above the bar with its own accent extruded shadow. Lifts a touch higher and
/// loses its shadow when active/pressed (depresses into the surface) for a
/// tactile pressed feel. Rendered with raw containers (NOT a Material FAB) so it
/// stays inside the soft-UI metaphor.
class _CenterSearchButton extends StatefulWidget {
  const _CenterSearchButton({
    super.key,
    required this.size,
    required this.active,
    required this.semanticLabel,
    required this.onTap,
  });

  final double size;
  final bool active;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  State<_CenterSearchButton> createState() => _CenterSearchButtonState();
}

class _CenterSearchButtonState extends State<_CenterSearchButton> {
  bool _pressed = false;

  /// Accent extruded shadow scaled down to suit the smaller (52px) disc — a
  /// local copy of [VelvetShadows.extrudedButtonAccent] with offsets/blur
  /// reduced ~52/64 so the elevation reads proportional, not heavy.
  static const List<BoxShadow> _discShadow = <BoxShadow>[
    BoxShadow(color: Color(0xFF8C6A44), offset: Offset(5, 5), blurRadius: 11),
    BoxShadow(
      color: BrandColors.shadowLightStrong,
      offset: Offset(-5, -5),
      blurRadius: 11,
    ),
  ];

  static const LinearGradient _faceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[BrandColors.accentLatte, BrandColors.accentDeep],
  );

  static final LinearGradient _bevelGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Colors.white.withValues(alpha: 0.30),
      Colors.transparent,
      Colors.black.withValues(alpha: 0.14),
    ],
    stops: const <double>[0.0, 0.5, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    final bool depressed = _pressed || widget.active;

    return Semantics(
      label: widget.semanticLabel,
      selected: widget.active,
      button: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        // Icon-only elevated disc — no caption beneath it. The disc is sized
        // to [widget.size]; vertical placement is handled by the bar's Stack.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: widget.size,
          width: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: _faceGradient,
            boxShadow: depressed ? null : _discShadow,
          ),
          child: Stack(
            children: <Widget>[
              const Center(
                child: Icon(
                  Icons.search_rounded,
                  color: BrandColors.white,
                  size: 22,
                ),
              ),
              // Inner bevel sheen so the disc reads as a physical pillow —
              // hidden while depressed to sell the pressed-in feel.
              if (!depressed)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: _bevelGradient,
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
