// BookingTopBar: the shared back-button + centered-title top bar for the
// booking flow (SlotDateScreen, SlotTimeScreen, BookingConfirmScreen).
//
// Extracted from two byte-near-identical private widgets — `_BookingTopBar`
// (`slot_picker_screen.dart`, shared by `SlotDateScreen` "Оберіть дату" AND
// `SlotTimeScreen` "Оберіть час") and `_TopBar` (`booking_confirm_screen.dart`,
// "Підтвердження") — each of which rendered an unconstrained `Text` centered
// inside a `Stack` alongside an `Align(centerLeft)` back button. `Stack` does
// NOT reflow non-positioned children around siblings, so a long title (or a
// large accessibility text scale) could visually extend under/behind the
// back button instead of wrapping or staying clear of it. Mirrors the
// `ClientTopBar` extraction precedent
// (`shell/presentation/widgets/client_top_bar.dart`'s own file header) for
// de-duplicating a byte-identical private `_TopBar` into one shared,
// promoted widget.
//
// FIX: restructured as a `Row` — the back button pinned to its own fixed
// `NeumorphicIconButton.extent` (48dp) box, the title in an `Expanded` +
// `Center` with `maxLines: 1` + `TextOverflow.ellipsis` as a safety net, and
// a matching trailing 48dp `SizedBox` so the title still reads as visually
// centered in the remaining space. The title can now never overlap the back
// button, regardless of length or text scale.
//
// PADDING NORMALIZATION: the two donor widgets used slightly different
// vertical padding — `slot_picker_screen.dart`'s `_BookingTopBar` used
// `md`/`sm` (top/bottom), `booking_confirm_screen.dart`'s `_TopBar` used the
// tighter `sm`/`xs`. Standardized on `md`/`sm` (16dp/8dp) — the roomier of
// the two, already established by `SlotDateScreen`/`SlotTimeScreen` — since
// the confirm screen's tighter `xs` (4dp) bottom inset was part of why its
// gap above `MasterStrip` had shrunk to 12dp total versus the 24dp gap
// `SlotTimeScreen` established (8dp bottom here + 16dp scroll-view top inset
// at each call site = 24dp everywhere).

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

/// The shared booking-flow top bar: a back button + centered screen title.
///
/// Used by `SlotDateScreen`, `SlotTimeScreen` (both in
/// `slot_picker_screen.dart`) and `BookingConfirmScreen`. The title is laid
/// out in a `Row` (fixed-width back button / `Expanded` title / matching
/// trailing spacer) rather than a `Stack`, so it can never render underneath
/// or behind the back button.
class BookingTopBar extends StatelessWidget {
  const BookingTopBar({
    super.key,
    required this.title,
    required this.backSemantics,
    required this.onBack,
    this.backKey,
  });

  final String title;
  final String backSemantics;
  final VoidCallback onBack;

  /// Stable [Key] for the back button — per-host test target, since existing
  /// widget tests pin distinct key strings per screen
  /// (`booking-confirm-back`, `slot-picker-back`).
  final Key? backKey;

  /// Fixed square extent reserved for the back button AND a matching
  /// trailing spacer, so the title's `Expanded` slot is centered in the row
  /// rather than skewed toward the trailing edge.
  static const double _sideExtent = NeumorphicIconButton.extent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.md,
        VelvetSpacing.lg,
        VelvetSpacing.sm,
      ),
      child: SizedBox(
        height: _sideExtent,
        child: Row(
          children: <Widget>[
            NeumorphicIconButton(
              key: backKey,
              icon: Icons.arrow_back_ios_new_rounded,
              semanticLabel: backSemantics,
              onTap: onBack,
            ),
            Expanded(
              child: Center(
                child: Text(
                  title,
                  style: VelvetText.subheading(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: _sideExtent),
          ],
        ),
      ),
    );
  }
}
