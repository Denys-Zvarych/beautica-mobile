// Phase 21.12 — the pinned roster strip above the salon «Записи» board: one
// chip per master COLUMN, each chip exactly as wide as, and horizontally
// aligned with, the grid column beneath it.
//
// ============================================================================
// WHY THIS IS NOT `MasterStrip`
// ============================================================================
// REUSE-FIRST was applied and lost on ONE axis only: the AXIS. [MasterStrip] /
// [MasterStripShell] are a horizontal identity ROW — 48dp avatar, then a
// column of «Запис до майстра» / name / role, then a trailing ★ readout — laid
// out to fill a full-width card. This strip's chip is 148dp wide at the 360dp
// baseline (see [TimelineDensity.columnWidth]); that row does not fit, and
// nothing additive to `MasterStripShell` makes it fit, because the constraint
// is the composition itself rather than any one of its sizes.
//
// So this is a compact SIBLING, not a fork, and the parts that CAN be shared
// are shared rather than re-drawn:
//
//   * the avatar glyph is [MasterAvatarBadge] — the same widget, with this
//     track's additive `size:` param, so the Impeller-GLES RRect workaround
//     and the gradient wash stay in one place;
//   * the rating readout is [MasterRatingReadout] — already extracted and
//     public for exactly this reason (see its doc: "the ONE place the app
//     decides what a rating looks like inside a booking-flow identity card"),
//     with this track's additive `compact:` param;
//   * the sub-line falls back to [masterRoleLabel], the same helper
//     [MasterStrip.build] uses, so «Майстер салону» reads identically here and
//     on the booking wizard.
//
// What is genuinely new is the vertical stack and the day's booking count.
//
// ============================================================================
// IT OWNS NO SCROLL CONTROLLER
// ============================================================================
// The strip is a plain child of [BookingsTimelineGrid]'s ONE horizontal
// `SingleChildScrollView` — see that widget's "THE SALON BOARD'S SCROLL LOCK"
// section. There is no controller here, no listener, and no `jumpTo` echo:
// strip and grid share a single `ScrollPosition` by construction, so a chip
// physically cannot drift off its column.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_role_label.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import 'master_avatar_badge.dart';
import 'master_strip.dart';

/// One roster chip's content — the strip is DATA-AGNOSTIC in the same way
/// [MasterStrip] is, taking primitives so the salon screen can build it from a
/// `SalonMasterSummary` without this widget importing the salon feature.
@immutable
class MasterColumnEntry {
  const MasterColumnEntry({
    required this.masterId,
    required this.name,
    required this.type,
    required this.bookingCount,
    this.professionalTitle,
    this.avgRating,
  });

  final String masterId;

  /// Already-joined display name ("Олена Ковальчук"). The chip ellipsises it
  /// to one line rather than abbreviating — a shortened name is a guess, and
  /// the owner reads this column against the cards under it.
  final String name;

  /// Role / tenure type — the sub-line fallback when no title is set.
  final MasterType type;

  /// How many bookings this master has on the SHOWN day. `0` renders the
  /// «вільно» state and dims the avatar.
  final int bookingCount;

  final String? professionalTitle;

  /// `null` renders [MasterStrip.noRatingLabel] — never a damning `0.0` for a
  /// master nobody has reviewed yet, exactly as [MasterStrip] folds it.
  final double? avgRating;
}

/// The pinned roster strip — a `Row` of fixed-width chips, one per column.
class MasterColumnStrip extends StatelessWidget {
  const MasterColumnStrip({
    required this.entries,
    required this.columnWidth,
    required this.gutter,
    this.selectedMasterId,
    this.onSelectMaster,
    super.key,
  });

  final List<MasterColumnEntry> entries;

  /// The rendered width of ONE grid column — the chip is sized to exactly
  /// this, which is the whole mechanism by which a chip stays over its column.
  final double columnWidth;

  /// The inter-column gutter, identical to the grid's own.
  final double gutter;

  /// The column the owner has tapped to inspect; `null` = none.
  final String? selectedMasterId;

  /// `null` leaves every chip inert (no ripple, no `Semantics(button:)`).
  final ValueChanged<String>? onSelectMaster;

  /// The strip's height AT TEXT SCALE 1.0. [BookingsTimelineGrid] reserves
  /// exactly [heightFor] beside the ruler gutter so the first hour label
  /// starts on the same line as the first gridline.
  ///
  /// ⚠ Do NOT reserve this constant directly — reserve [heightFor]. A chip's
  /// body is three stacked text lines, so at an accessibility text scale it
  /// is taller than 64dp and a fixed reserve overflows it (measured: +3.0dp
  /// at textScaler 1.3, +30dp at 2.0, on every chip at once).
  static const double height = 64;

  /// [height] grown by the ambient text-scale factor, so the reserve tracks
  /// the chip's own three text lines instead of assuming scale 1.0.
  ///
  /// Derived from a representative body size rather than from
  /// `TextScaler.scale(1.0)`: a non-linear scaler is only meaningful when
  /// asked about a real font size, and 14sp is the largest of the chip's
  /// three (see [VelvetText.timelineColumnName]). Clamped at the bottom to
  /// 1.0 so a shrunken system font never squeezes the strip below its
  /// designed height, and at the top to 2.0 — Android's own accessibility
  /// ceiling — so a runaway scaler cannot push the grid off screen.
  static double heightFor(BuildContext context) {
    final double factor = (MediaQuery.textScalerOf(context).scale(14) / 14)
        .clamp(1.0, 2.0);
    return height * factor;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: heightFor(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < entries.length; i++) ...<Widget>[
            if (i > 0) SizedBox(width: gutter),
            SizedBox(
              width: columnWidth,
              child: _MasterColumnChip(
                entry: entries[i],
                selected: entries[i].masterId == selectedMasterId,
                onTap: onSelectMaster == null
                    ? null
                    : () => onSelectMaster!(entries[i].masterId),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MasterColumnChip extends StatelessWidget {
  const _MasterColumnChip({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final MasterColumnEntry entry;
  final bool selected;
  final VoidCallback? onTap;

  /// The camel ring that marks the inspected column. Hoisted — `Border.all`
  /// over a non-const `Color` cannot be `const`, and resolving it once at
  /// class-load time keeps it off the per-chip rebuild path (the same fix
  /// pattern used throughout `master_booking_card.dart`).
  static final Border _selectedBorder = Border.all(
    color: BrandColors.accent,
    width: 1.5,
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool free = entry.bookingCount == 0;

    // Same precedence as [MasterStrip.build]: the master's own professional
    // title wins, the generic role label is the fallback.
    final String? title = entry.professionalTitle?.trim();
    final String subtitle = (title != null && title.isNotEmpty)
        ? title
        : masterRoleLabel(entry.type, l10n);

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: l10n.salonBookingsMasterColumnSemantics(
        entry.name,
        subtitle,
        free
            ? l10n.salonBookingsMasterColumnFree
            : l10n.masterBookingsCount(entry.bookingCount),
      ),
      child: GestureDetector(
        key: ValueKey<String>('salon-bookings-column-chip-${entry.masterId}'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: VelvetSpacing.sm),
          padding: const EdgeInsets.symmetric(
            horizontal: VelvetSpacing.sm,
            vertical: VelvetSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: BrandColors.base,
            borderRadius: BorderRadius.circular(VelvetRadii.field),
            boxShadow: VelvetShadows.extrudedSmall,
            border: selected ? _selectedBorder : null,
          ),
          child: Row(
            children: <Widget>[
              // The SHARED glyph, at the chip's size — see the file header.
              Opacity(
                opacity: free ? 0.45 : 1,
                child: const MasterAvatarBadge(size: 28),
              ),
              const SizedBox(width: VelvetSpacing.xs + 2),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.name,
                      style: free
                          ? VelvetText.timelineColumnNameMuted
                          : VelvetText.timelineColumnName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: VelvetText.timelineColumnRole,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: <Widget>[
                        // The SHARED rating readout, in its compact form. The
                        // review COUNT is dropped at this width — `compact`
                        // suppresses it — so the trailing figure below is
                        // unambiguously the day's booking count.
                        MasterRatingReadout(
                          avgRating: entry.avgRating,
                          reviewCount: 0,
                          compact: true,
                        ),
                        const SizedBox(width: VelvetSpacing.xs + 1),
                        Flexible(
                          child: Text(
                            free
                                ? l10n.salonBookingsMasterColumnFree
                                : '${entry.bookingCount}',
                            style: free
                                ? VelvetText.timelineColumnCountFree
                                : VelvetText.timelineColumnCount,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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

/// The roster's horizontal scroll readout — a 3dp camel thumb on a faint
/// track, sized to `viewport / content` — pinned just under the strip.
///
/// It carries information the partial next column cannot: how much of the team
/// is off-screen, and in which direction. One accent, one job — there is no
/// edge fade or arrow chrome beside it.
///
/// It READS [controller]'s position rather than riding it, so it sits OUTSIDE
/// the horizontal scroller (see [BookingsTimelineGrid]'s scroll-lock section).
/// The `AnimatedBuilder` confines a scroll tick's rebuild to this 3dp box.
class StripScrollIndicator extends StatelessWidget {
  const StripScrollIndicator({
    required this.controller,
    required this.semanticsLabel,
    super.key,
  });

  final ScrollController controller;

  /// «Показано майстрів: 2 з 5» — the count the thumb encodes, spelled out for
  /// a screen reader, which cannot see a 3dp bar at all.
  final String semanticsLabel;

  static final Color _trackColor = BrandColors.faint.withValues(alpha: 0.45);
  static final BorderRadius _radius = BorderRadius.circular(2);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      child: SizedBox(
        height: 3,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return AnimatedBuilder(
              animation: controller,
              builder: (BuildContext context, Widget? _) {
                if (!controller.hasClients) return const SizedBox.shrink();
                final ScrollPosition position = controller.position;
                if (!position.hasContentDimensions ||
                    !position.hasViewportDimension ||
                    !position.hasPixels ||
                    position.maxScrollExtent <= 0) {
                  return const SizedBox.shrink();
                }
                final double content =
                    position.viewportDimension + position.maxScrollExtent;
                final double track = constraints.maxWidth;
                final double thumb =
                    (position.viewportDimension / content * track).clamp(
                      24.0,
                      track,
                    );
                final double left =
                    (position.pixels.clamp(0.0, position.maxScrollExtent) /
                        position.maxScrollExtent) *
                    (track - thumb);
                return Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _trackColor,
                          borderRadius: _radius,
                        ),
                      ),
                    ),
                    Positioned(
                      left: left,
                      width: thumb,
                      top: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: BrandColors.accent,
                          borderRadius: _radius,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
