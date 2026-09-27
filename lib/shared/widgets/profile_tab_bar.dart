import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

/// The profile section switcher — a row of text tabs over a faint hairline,
/// with a single camel underline that slides under the active tab. Selection
/// is owned by the parent.
///
/// REUSE-FIRST — PROMOTED from `SalonTabBar`
/// (`features/salon/presentation/widgets/salon_cover_widgets.dart:323-422`,
/// Phase 13.6), where it drove the public salon profile's «Про салон» /
/// «Майстри» / «Послуги» / «Відгуки» switcher and the salon management
/// screen's own tab row. Phase 351 reuses it VERBATIM for the public master
/// profile's «Про майстра» / «Послуги» / «Відгуки» tabs, so `master/` never
/// imports `salon/` for it. Generic on `tabs`/`selected`/`onSelect` already —
/// no behavioural change, a straight file move + rename.
///
/// [keyPrefix] defaults to `'salon'` so every existing caller
/// (`PublicSalonProfileScreen`, `SalonManagementProfileScreen`) keeps its
/// exact `Key('salon-tab-$i')` finders unchanged. A new caller with a
/// different tab vocabulary (e.g. the public master profile) passes its own
/// prefix so its tab keys read as its own, not borrowed from the salon.
class ProfileTabBar extends StatelessWidget {
  const ProfileTabBar({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
    this.keyPrefix = 'salon',
  });

  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onSelect;

  /// Prefix for each tab's `Key`, e.g. `'salon'` → `Key('salon-tab-0')`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: BrandColors.faint, width: 1)),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < tabs.length; i++)
            Expanded(
              child: _ProfileTab(
                label: tabs[i],
                active: i == selected,
                onTap: () => onSelect(i),
                tabKey: Key('$keyPrefix-tab-$i'),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({
    required this.label,
    required this.active,
    required this.onTap,
    required this.tabKey,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Key tabKey;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        key: tabKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: VelvetSpacing.sm + 2,
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: VelvetText.subheading12.copyWith(
                  // 12 (not the original 14) — «Про салон» at w700 Comfortaa
                  // is the widest of the salon's 4 labels and, at 14px, its
                  // natural width (~82px) exceeds a quarter-screen segment on
                  // a 360dp-wide phone (~78dp after the screen's lg/24dp
                  // margins), forcing a wrap. 12px keeps every label on one
                  // line with headroom down to ~360dp; maxLines/overflow
                  // above are the safety net below that. Kept for every
                  // caller, including the public master profile's 3-tab
                  // (shorter-label) row, so the two switchers read as the
                  // same control.
                  color: active ? BrandColors.text : BrandColors.muted,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            // Sliding camel underline — 3px under the active tab only.
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: 3,
              width: active ? 44 : 0,
              decoration: BoxDecoration(
                color: BrandColors.accent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
