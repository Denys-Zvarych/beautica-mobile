// Phase 21.8 QA follow-up — golden coverage for [SalonBottomNav] (the new
// SALON_OWNER/SALON_ADMIN shell bar, `lib/shared/widgets/salon_bottom_nav.dart`).
//
// Structurally the SAME chrome family as `client_bottom_nav_golden_test.dart`
// (this file mirrors its shape) minus the client bar's elevated center disc:
// a floating rounded pill, dual-direction neumorphic shadow, and a thin
// gradient indicator bar that grows in above the active icon. Pins the
// active/inactive appearance of every one of the 4 `ownerAdminItems` tabs —
// the indicator, the muted->accentDeep tint, AND the outline->filled icon
// swap for BOTH icon sources `SalonNavItem` supports (Material `IconData`
// for Записи/Профіль, SVG `AppIcon` assets for Салон/Команда).
//
// mobile-qa CORRECTION (2026-08-28, Priority 1) — the previous version of
// this file built its OWN local `_items` fixture with hardcoded Material
// `Icons.storefront_*`/`Icons.groups_*` glyphs and passed it straight into
// `SalonBottomNav`, never touching `SalonBottomNav.ownerAdminItems` — the
// actual production item list. Every one of the four production tabs
// changed glyph in the 2026-08-28 re-icon (Салон/Команда moved from Material
// icons to SVG assets; Записи/Профіль swapped Material glyphs), and every
// golden in this file passed UNCHANGED, because none of them ever rendered
// a production icon in the first place — this file's own header claimed
// "a regression in any of those reads as a pixel diff", which was false for
// every icon. Fixed by building the SAME `_host` around
// `SalonBottomNav.ownerAdminItems(l10n)` used by the real shell
// (`lib/features/salon/presentation/salon_shell_screen.dart`), so a
// reverted/wrong icon on ANY tab is a real pixel diff again. Proven by
// mutation: swapping `teamFilled` back to `Icons.groups_rounded` in
// `salon_bottom_nav.dart` fails `salon_bottom_nav active tab 2` — see the
// mobile-qa audit note for the verbatim failure.
//
// `ownerAdminItems` sources its labels from [AppLocalizations] (labels are
// never hard-coded Ukrainian in shipped `lib/` source — `no_raw_ui_strings`
// is CI-fatal), so the fixture needs a localized `context` to build the item
// list. [goldenPumpWidget] already wraps the tree in a `MaterialApp` with the
// UK locale + [AppLocalizations] delegates (see its own doc); `_host` below
// resolves `l10n` from a `Builder`'s `context` rather than working around it
// with a second hand-copied item list.
//
// Matrix kept tight (chrome): {360} dp x {1.0} scale, one golden per active
// index (0..3) so each tab's selected state AND the other three tabs'
// inactive state are captured in the same frame.
//
// File names: salon_bottom_nav_active_<index>_360_1x.png (index 0..3)

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

/// Hosts the bar bottom-aligned on the brand base background, mirroring
/// `client_bottom_nav_golden_test.dart`'s `_host` — but built around the REAL
/// production item list, [SalonBottomNav.ownerAdminItems], not a hand-copied
/// fixture (see file header).
Widget _host(double width, int activeIndex) => ColoredBox(
  color: BrandColors.base,
  child: SizedBox(
    width: width,
    child: Align(
      alignment: Alignment.bottomCenter,
      child: Builder(
        builder: (context) {
          final AppLocalizations l10n = AppLocalizations.of(context);
          return SalonBottomNav(
            currentIndex: activeIndex,
            onSelect: (_) {},
            items: SalonBottomNav.ownerAdminItems(l10n),
          );
        },
      ),
    ),
  ),
);

void main() {
  const double width = 360;

  // 0=Салон (SVG homeOutline/homeFilled), 1=Записи (Material event_note),
  // 2=Команда (SVG teamOutline/teamFilled), 3=Профіль (Material person).
  for (final int activeIndex in <int>[0, 1, 2, 3]) {
    goldenTest(
      'salon_bottom_nav active tab $activeIndex',
      fileName: 'salon_bottom_nav_active_${activeIndex}_360_1x',
      constraints: BoxConstraints.tight(const Size(width, 100)),
      textScaleFactor: 1.0,
      pumpWidget: goldenPumpWidget(width: width),
      builder: () => _host(width, activeIndex),
    );
  }
}
