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
// What is genuinely new is the vertical stack.
//
// ============================================================================
// IT OWNS NO SCROLL CONTROLLER
// ============================================================================
// The strip is a plain child of [BookingsTimelineGrid]'s ONE horizontal
// `SingleChildScrollView` — see that widget's "THE SALON BOARD'S SCROLL LOCK"
// section. There is no controller here, no listener, and no `jumpTo` echo:
// strip and grid share a single `ScrollPosition` by construction, so a chip
// physically cannot drift off its column.

import 'package:flutter/foundation.dart' show listEquals;
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
    this.dayOff = false,
  });

  final String masterId;

  /// Already-joined display name ("Олена Ковальчук"). The chip ellipsises it
  /// to one line rather than abbreviating — a shortened name is a guess, and
  /// the owner reads this column against the cards under it.
  final String name;

  /// Role / tenure type — the sub-line fallback when no title is set.
  final MasterType type;

  /// How many bookings this master has on the SHOWN day. `0` puts the chip in
  /// its quiet form — dimmed avatar, muted name. The chip renders no figure:
  /// the count is SPOKEN in the Semantics label only (see [_MasterColumnChip.build])
  /// because the grid directly below already shows the cards themselves.
  final int bookingCount;

  /// Phase 336 — this master is NOT WORKING on the shown day (a settled day
  /// off, or no schedule at all). Renders the chip in its quiet form (the
  /// «Вихідний» wording it once carried is now spoken, not drawn) and greys
  /// that master's whole grid column — where «Вихідний» IS still drawn, as the
  /// column overlay: see [BookingsTimelineGrid]'s `_BoardStack`.
  ///
  /// ⚠ DEFAULTS TO `false`, AND `false` MEANS "NOT KNOWN TO BE OFF", NEVER
  /// "WORKING". Every pre-existing call site omits it and renders exactly as
  /// before. The salon screen derives it from the ROSTER-COMPLETE schedule
  /// response (`SalonBookingsScreen.masterDayOff`) and leaves it `false`
  /// whenever those hours have not resolved — an unloaded roster must never
  /// grey a column out. It is emphatically NOT derived from
  /// [bookingCount] == 0: "working, nothing booked" is a different state with
  /// its own «Вільний день» marker, and conflating the two IS the bug this
  /// field exists to fix.
  final bool dayOff;

  final String? professionalTitle;

  /// `null` renders [MasterStrip.noRatingLabel] — never a damning `0.0` for a
  /// master nobody has reviewed yet, exactly as [MasterStrip] folds it.
  final double? avgRating;
}

/// The pinned roster strip — a `Row` of fixed-width chips, one per column.
///
/// ## IT CACHES ITS OWN SUBTREE (mobile-perf LOW, 2026-09-17)
///
/// `StatefulWidget` for exactly one reason: to hold the built `Row` and hand
/// the SAME widget instance back on a rebuild whose inputs did not change, so
/// `Element.updateChild` skips the whole chip subtree. Measured on this
/// widget alone (element-identity snapshot before/after one no-op parent
/// `setState`, `_p1_measure_scratch_test.dart` methodology): **362 of 512**
/// elements took a fresh widget instance per no-op rebuild at 10 masters,
/// 110/155 at 3 — including an all-day-off board where nothing on screen can
/// possibly have moved. It holds no state of its own; the cache is a pure
/// render-identity optimisation, exactly like `_BoardStack`'s `_columnCache`
/// in `bookings_timeline_grid.dart`.
///
/// ### THE GATE'S INPUTS, ENUMERATED AGAINST WHAT `build()` ACTUALLY READS
///
/// A gate NARROWER than the recompute ships a stale strip, so every read is
/// accounted for here — including the two that are deliberately absent:
///
/// | read by `build()`                                  | in the gate? |
/// |----------------------------------------------------|--------------|
/// | `entries.length`, `entries[i]` (→ chip `entry`)     | yes — `listEquals` |
/// | `entries[i].masterId == selectedMasterId`           | yes — both halves |
/// | `columnWidth` (chip `SizedBox.width`)               | yes |
/// | `gutter` (inter-chip `SizedBox.width`)              | yes |
/// | `selectedMasterId`                                  | yes |
/// | `onSelectMaster` (null-ness AND the captured value) | yes, via `!=` |
/// | `heightFor(context)` → `MediaQuery.textScalerOf`    | yes — `_cachedHeight` |
/// | `AppLocalizations.of(context)` (in `_MasterColumnChip.build`) | NO — see below |
/// | `BrandColors` / `VelvetText` statics                | NO — class-load constants |
///
/// `l10n` is read by the CHIP, not by this `build()`, so each chip element is
/// itself a `Localizations` dependant: a locale change marks those elements
/// dirty directly and they rebuild with their unchanged configuration. Handing
/// back an identical parent widget cannot suppress that — `updateChild` only
/// skips the `update()` call, it does not remove elements from the dirty list.
/// The same holds for `Directionality`, which the `Row` element re-reads
/// itself. Only what THIS `build()` reads from the tree needs a gate entry,
/// and that is `heightFor(context)`.
///
/// `entries` is compared with `listEquals`, NOT `identical`, on purpose:
/// [BookingsTimelineGrid] rebuilds the list literal (`[for (c in columns)
/// c.header]`) every build, so the LIST identity is never stable — but
/// `_columnsFor`'s memo makes each `TimelineBoardColumn`, and therefore each
/// `header`, identity-stable. `MasterColumnEntry` declares no `==`, so
/// `listEquals` IS an element-identity compare at ≤10 elements. A caller that
/// rebuilds its entries wholesale simply gets no cache hit — the conservative
/// direction, never a stale render.
class MasterColumnStrip extends StatefulWidget {
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
  State<MasterColumnStrip> createState() => _MasterColumnStripState();
}

class _MasterColumnStripState extends State<MasterColumnStrip> {
  /// The last built strip, and the resolved height it was built at. Returned
  /// UNCHANGED — the same instance — whenever nothing `build()` reads has
  /// moved, which is what makes `Element.updateChild` skip the chip subtree.
  ///
  /// Cleared by [didUpdateWidget] on ANY change to a widget field the built
  /// tree depends on, and bypassed in [build] when the ambient text scale
  /// resolves to a different height, so a stale strip can never survive a
  /// real change. See the class doc for the full input enumeration.
  Widget? _cached;
  double? _cachedHeight;

  @override
  void didUpdateWidget(covariant MasterColumnStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `!=` on the callback, NOT `!identical` — the host hands over an
    // instance-method tear-off, and Dart mints a fresh closure object for each
    // one, so two tear-offs of the same method on the same receiver are `==`
    // but never `identical`. `!identical` here would clear the cache on every
    // rebuild and silently delete this whole optimisation with no test
    // failing. Same trap, same reasoning as `_BoardStack.didUpdateWidget`'s
    // `onBookingTap` line in `bookings_timeline_grid.dart`.
    if (!listEquals(oldWidget.entries, widget.entries) ||
        oldWidget.columnWidth != widget.columnWidth ||
        oldWidget.gutter != widget.gutter ||
        oldWidget.selectedMasterId != widget.selectedMasterId ||
        oldWidget.onSelectMaster != widget.onSelectMaster) {
      _cached = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // The ONE thing this build reads from the tree rather than from `widget`.
    // A `MediaQuery` text-scale change marks THIS element dirty (the read
    // below registers the dependency), so the gate has to notice it here —
    // `didUpdateWidget` does not even run for an inherited-dependency rebuild.
    final double height = MasterColumnStrip.heightFor(context);
    final Widget? cached = _cached;
    if (cached != null && height == _cachedHeight) return cached;

    final Widget built = SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < widget.entries.length; i++) ...<Widget>[
            if (i > 0) SizedBox(width: widget.gutter),
            SizedBox(
              width: widget.columnWidth,
              child: _MasterColumnChip(
                entry: widget.entries[i],
                selected: widget.entries[i].masterId == widget.selectedMasterId,
                onTap: widget.onSelectMaster == null
                    ? null
                    : () => widget.onSelectMaster!(widget.entries[i].masterId),
              ),
            ),
          ],
        ],
      ),
    );
    _cached = built;
    _cachedHeight = height;
    return built;
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

  /// The hairline every UNSELECTED chip wears, mirroring `NeumorphicCard`'s
  /// `showBorder` path. It is the definition the chip used to get from
  /// [VelvetShadows.extrudedSmall]'s near-white highlight — see the decoration
  /// below for why that highlight had to go.
  ///
  /// The two borders are mutually EXCLUSIVE, never stacked: a selected chip
  /// wears its camel ring alone (the ring is the stronger, more specific
  /// signal and already defines the edge), an unselected chip the faint
  /// hairline. So selection still reads as exactly one visual change — taupe
  /// hairline → camel ring — and no chip is ever double-bordered.
  static final Border _restBorder = Border.all(
    color: BrandColors.faint,
    width: 1,
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool free = entry.bookingCount == 0;
    // Phase 336 — the two quiet states share the chip's DE-EMPHASIS (dimmed
    // avatar, muted name). A master who is off always has nothing booked in
    // practice, so `free` is usually true alongside `dayOff`.
    final bool quiet = free || entry.dayOff;
    // SPOKEN ONLY — the chip renders NO trailing load readout any more (the
    // owner asked for the strip to carry identity, not a second copy of the
    // figure the grid below already shows). The load survives here purely as
    // the third placeholder of the Semantics label: a screen-reader user has
    // no grid to scan and would otherwise lose the information outright.
    //
    // `dayOff` is checked FIRST so «Вихідний» ("not working") is never
    // overwritten by «вільно» ("working, free"), which is the weaker and, on
    // an off day, the wrong statement.
    final String load = entry.dayOff
        ? l10n.salonBookingsColumnDayOff
        : (free
              ? l10n.salonBookingsMasterColumnFree
              : l10n.masterBookingsCount(entry.bookingCount));

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
        load,
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
          // IMPELLER-GLES CORNER FIX: this chip shipped on
          // `VelvetShadows.extrudedSmall` — an OPAQUE `shadowDarkButton` at
          // `Offset(5,5)` paired with an OPAQUE `shadowLightStrong` at
          // `Offset(-5,-5)`. A shadow's rrect is the surface's shape
          // TRANSLATED then blurred, so its untranslated corner protrudes past
          // the rounded fill, and Impeller's OpenGLES backend rasterizes that
          // blur hard into a crisp un-antialiased square in whatever hue the
          // shadow carries — the "background bleeding through the corners" the
          // owner saw along this roster strip.
          //
          // Judge a recipe by "is it OPAQUE and OFFSET?", never by its colour:
          // the rule was once written as "near-white is the offender" and a
          // *dark* opaque offset shadow then shipped black rectangles on
          // `MasterBookingCard`. The remedy is the button-scaled
          // `borderedButton` sibling — a single `shadowDarkButton` at alpha
          // 0.45 with NO offset, safe for two independent reasons (attenuated
          // AND non-offset), so its footprint exactly matches the chip and can
          // only read as a uniform halo. The hairline border below carries the
          // definition the extruded highlight used to, mirroring
          // `NeumorphicCard`'s `showBorder` path — the same repair
          // `master_strip_shell.dart` and `calendar_button.dart` already made.
          //
          // Guarded structurally (not by a golden — the artifact is
          // Impeller-GLES-only and a Skia render draws it correctly) in
          // `test/features/booking/impeller_circle_shadow_guard_test.dart`.
          decoration: BoxDecoration(
            color: BrandColors.base,
            borderRadius: BorderRadius.circular(VelvetRadii.field),
            boxShadow: VelvetShadows.borderedButton,
            border: selected ? _selectedBorder : _restBorder,
          ),
          child: Row(
            children: <Widget>[
              // The SHARED glyph, at the chip's size — see the file header.
              Opacity(
                opacity: quiet ? 0.45 : 1,
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
                      style: quiet
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
                    // The SHARED rating readout, in its compact form — the
                    // review COUNT is dropped at this width (`compact`
                    // suppresses it). It is now the LAST line of the chip:
                    // the trailing load readout that used to sit beside it
                    // («3» / «вільно» / «Вихідний») no longer renders in any
                    // state, so the separator and the `Row` that held the two
                    // side by side went with it rather than leaving a
                    // one-child row and a dangling gap. The load is still
                    // announced — see the Semantics label above.
                    MasterRatingReadout(
                      avgRating: entry.avgRating,
                      reviewCount: 0,
                      compact: true,
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
