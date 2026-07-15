// Phase 14.3 — the three-way tab selector: Майбутні / Минулі / Скасовані.
//
// Ported from `docs/signup-designs/MyBookings/lib/widgets/bookings_tab_bar.dart`.
// Rendered as the soft-UI archetype rather than a Material `TabBar` — a
// recessed track with a single raised camel pill that slides between the
// three stops. That is the one piece of motion on the screen, and it is the
// right one: it is the only control the client actually manipulates, and the
// slide makes the three tabs read as one physical switch with three
// positions rather than three independent buttons.
//
// ⚠ PORT DEVIATION: the preview's per-tab row COUNT ("2" beside the label)
// is dropped here. The preview's counts were the full length of a hardcoded
// sample list; in production the notifier only knows how many rows have been
// FETCHED so far (page 0..N), not the true total — showing "3" while 20 more
// exist beyond the loaded page would be a small lie the preview never had to
// tell. Simpler and honest: labels only. `MyBookingsScreen` still drives this
// widget from a real `TabController` so tap AND swipe stay in sync.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../../domain/booking_tab.dart';

/// Localised label for [tab].
String bookingTabLabel(BookingTab tab, AppLocalizations l10n) => switch (tab) {
  BookingTab.upcoming => l10n.myBookingsTabUpcoming,
  BookingTab.past => l10n.myBookingsTabPast,
  BookingTab.cancelled => l10n.myBookingsTabCancelled,
};

class MyBookingsTabBar extends StatelessWidget {
  const MyBookingsTabBar({
    super.key,
    required this.active,
    required this.onChanged,
  });

  final BookingTab active;
  final ValueChanged<BookingTab> onChanged;

  static const double _height = 46;
  static const double _pad = 4;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const List<BookingTab> tabs = BookingTab.values;
    final int index = tabs.indexOf(active);
    // Three stops mapped onto the [-1, 1] alignment axis.
    final double x = -1 + index * 1.0;

    return NeumorphicInset(
      radius: VelvetRadii.field,
      child: SizedBox(
        key: const Key('my-bookings-tab-bar'),
        height: _height,
        child: Padding(
          padding: const EdgeInsets.all(_pad),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double pillWidth = c.maxWidth / tabs.length;
              return Stack(
                children: <Widget>[
                  AnimatedAlign(
                    alignment: Alignment(x, 0),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    child: Container(
                      width: pillWidth,
                      height: _height - _pad * 2,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            BrandColors.accentLatte,
                            BrandColors.accentDeep,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: BrandColors.accentDeep.withValues(
                              alpha: 0.28,
                            ),
                            offset: const Offset(0, 3),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      for (final BookingTab tab in tabs)
                        Expanded(
                          child: _TabLabel(
                            key: ValueKey<BookingTab>(tab),
                            label: bookingTabLabel(tab, l10n),
                            active: tab == active,
                            onTap: () => onChanged(tab),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color fg = active ? BrandColors.white : BrandColors.textSecondary;

    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            // VelvetText.cta() is already Comfortaa 13 — only the resting/active
            // colour + weight vary, so no inline fontSize is needed here.
            style: VelvetText.cta().copyWith(
              color: fg,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            ),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    );
  }
}
