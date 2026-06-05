// Phase 15.2 — Master Schedule presentational widgets.
//
// Transcribed from the approved preview
// `docs/signup-designs/MasterSchedule/lib/widgets/schedule_widgets.dart`, with
// the preview's standalone tokens (VelvetColors / VelvetText / VelvetSpacing /
// VelvetShadows / VelvetRadii) replaced 1:1 by the production equivalents from
// `lib/core/theme/`:
//   • VelvetColors.*  → BrandColors.*
//   • VelvetText.*()  → VelvetText.*()  (same class name in production)
//   • VelvetSpacing.* / VelvetRadii.* / VelvetShadows.* → identical names
//
// Net-new vs. the preview: [NoScheduleBanner] (OQ-3 empty-state) — an
// informational, non-blocking banner shown when the viewed day/period resolves
// to NO_SCHEDULE. It uses the same recessed-well treatment as the legend card so
// it sits naturally above the all-grey grid; its single camel CTA is the only
// saturated element so it reads as the clear action without competing with the
// calendar.
//
// All user-facing strings come from [AppLocalizations] (preview hard-coded the
// Ukrainian) so the screen satisfies `no_raw_ui_strings` and stays EN-ready.
// The Ukrainian wording is byte-for-byte the approved preview copy.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import 'day_schedule.dart';
import 'slot_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Small shared pieces for the calendar-first Master Schedule screen.
// All depth comes from the neumorphic shadow recipes in velvet_geometry; the
// only non-token colours anywhere are the three desaturated slot tints
// (slot_colors.dart).
// ─────────────────────────────────────────────────────────────────────────────

/// Section heading: a title, an optional info glyph, and an optional trailing
/// outlined action (e.g. "Налаштування").
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.info,
    this.trailing,
  });

  final String title;
  final String? info;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(title, style: VelvetText.heading().copyWith(fontSize: 22)),
        if (info != null) ...<Widget>[
          const SizedBox(width: VelvetSpacing.sm),
          Tooltip(
            message: info!,
            child: const Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: BrandColors.muted,
            ),
          ),
        ],
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

/// A compact outlined (ghost) button — the recessed counterpart to the filled
/// [NeumorphicButton]. Rendered as a flat-bordered camel pill; used for
/// "Сьогодні" (month navigator).
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.dense = true,
    this.expand = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool dense;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final Widget row = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 18, color: BrandColors.accentDeep),
          const SizedBox(width: VelvetSpacing.sm - 2),
        ],
        Text(
          label,
          style: VelvetText.link().copyWith(
            color: BrandColors.accentDeep,
            fontSize: dense ? 13 : 14,
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          height: dense ? 40 : 48,
          padding: EdgeInsets.symmetric(horizontal: dense ? 14 : 18),
          decoration: BoxDecoration(
            color: BrandColors.base,
            borderRadius: BorderRadius.circular(VelvetRadii.button),
            border: Border.all(
              color: BrandColors.accent.withValues(alpha: 0.55),
              width: 1.4,
            ),
            boxShadow: VelvetShadows.extrudedSmall,
          ),
          child: Center(child: row),
        ),
      ),
    );
  }
}

/// A single circular weekday pill (Пн, Вт, …). Active = filled camel tint;
/// inactive = recessed inset well.
class WeekdayPill extends StatelessWidget {
  const WeekdayPill({
    super.key,
    required this.label,
    required this.active,
    this.onTap,
    this.size = 42,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Widget pill = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: size,
      width: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active
            ? BrandColors.accent.withValues(alpha: 0.32)
            : BrandColors.base,
        shape: BoxShape.circle,
        border: Border.all(
          color: active
              ? BrandColors.accent.withValues(alpha: 0.85)
              : BrandColors.faint.withValues(alpha: 0.6),
          width: active ? 1.6 : 1,
        ),
        boxShadow: active ? null : VelvetShadows.extrudedSmall,
      ),
      child: Text(
        label,
        style: VelvetText.bodyStrong().copyWith(
          fontSize: 13,
          color: active ? BrandColors.accentDeep : BrandColors.muted,
        ),
      ),
    );

    if (onTap == null) {
      return Semantics(label: label, selected: active, child: pill);
    }
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(onTap: onTap, child: pill),
    );
  }
}

/// A wrap-free row of seven weekday pills sized to fit any phone width.
class WeekdayPillRow extends StatelessWidget {
  const WeekdayPillRow({
    super.key,
    required this.labels,
    required this.active,
    this.onTap,
  });

  /// Seven Ukrainian short labels Пн…Нд.
  final List<String> labels;

  /// Seven booleans, ISO order Mon→Sun.
  final List<bool> active;

  /// Optional per-index tap (propagate picker). Null → display only.
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        // 7 pills + 6 gaps; clamp so it always fits.
        const double gap = VelvetSpacing.sm - 2;
        final double size = ((c.maxWidth - gap * 6) / 7)
            .clamp(34.0, 46.0)
            .toDouble();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            for (int i = 0; i < 7; i++)
              WeekdayPill(
                label: labels[i],
                active: active[i],
                size: size,
                onTap: onTap == null ? null : () => onTap!(i),
              ),
          ],
        );
      },
    );
  }
}

/// One date in the week strip: weekday initial over the day number, with an
/// optional override dot beneath. The selected date sits in a camel disc.
class WeekStripDay extends StatelessWidget {
  const WeekStripDay({
    super.key,
    required this.weekdayLabel,
    required this.day,
    required this.selected,
    required this.inMonth,
    required this.hasOverride,
    required this.onTap,
    required this.pastSemanticLabel,
    required this.plainSemanticLabel,
    this.past = false,
  });

  final String weekdayLabel;
  final int day;
  final bool selected;
  final bool inMonth;
  final bool hasOverride;
  final VoidCallback onTap;

  /// Localised semantic label for a past day (e.g. "Пн 13, минулий день").
  final String pastSemanticLabel;

  /// Localised semantic label for a present/future day (e.g. "Пн 13").
  final String plainSemanticLabel;

  /// Past days (before "today"): still tappable for read-only viewing, but
  /// rendered with a subtle muted cue so they read as in-the-past.
  final bool past;

  @override
  Widget build(BuildContext context) {
    final Color numberColor = selected
        ? BrandColors.accentDeep
        : !inMonth
        ? BrandColors.faint
        : past
        ? BrandColors.muted
        : BrandColors.text;

    final FontWeight numberWeight = past && !selected
        ? FontWeight.w500
        : FontWeight.w700;

    final Column body = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          weekdayLabel,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: VelvetText.label().copyWith(fontSize: 11),
        ),
        const SizedBox(height: VelvetSpacing.sm),
        // The 38px camel disc is the natural pill size, but on narrow phone
        // widths a single strip cell can be slimmer than 38px once the seven
        // cells share the row via Expanded. FittedBox scales the disc down to
        // fit the cell instead of overflowing, preserving the selected ring.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            height: 38,
            width: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? BrandColors.accent.withValues(alpha: 0.35)
                  : Colors.transparent,
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(
                      color: BrandColors.accent.withValues(alpha: 0.9),
                      width: 1.6,
                    )
                  : null,
            ),
            child: Text(
              '$day',
              style: VelvetText.bodyStrong().copyWith(
                fontSize: 16,
                color: numberColor,
                fontWeight: numberWeight,
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        // The override dot marks non-selected days that carry a schedule
        // override; reserved space is kept on the selected day so the number's
        // baseline never shifts.
        Container(
          height: 5,
          width: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hasOverride && !selected
                ? BrandColors.accentDeep
                : Colors.transparent,
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      selected: selected,
      label: past ? pastSemanticLabel : plainSemanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: body,
      ),
    );
  }
}

/// A single 30-minute time chip. Colour-coded by [SlotCell.state]; tappable.
class SlotChip extends StatelessWidget {
  const SlotChip({
    super.key,
    required this.cell,
    required this.onTap,
    required this.stateLabel,
  });

  final SlotCell cell;
  final VoidCallback? onTap;

  /// Pre-localised label for [cell].state (legend wording), used in the
  /// semantic label so the chip never carries a raw inline string.
  final String stateLabel;

  String get _timeLabel =>
      '${cell.time.hour.toString().padLeft(2, '0')}:${cell.time.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final SlotState s = cell.state;
    final bool empty = s == SlotState.unavailable;

    return Semantics(
      button: onTap != null,
      label: '$_timeLabel — $stateLabel',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: s.fill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: s.border, width: 1),
          ),
          child: empty
              ? Text(
                  '–',
                  style: VelvetText.bodyStrong().copyWith(
                    color: BrandColors.faint,
                    fontSize: 16,
                  ),
                )
              // Time-off slots are conveyed by the pink fill + border ALONE; the
              // legend ("Час відпочинку") carries the meaning. No in-chip tag.
              : Text(
                  _timeLabel,
                  style: VelvetText.bodyStrong().copyWith(
                    fontSize: 14,
                    color: s.accent,
                  ),
                ),
        ),
      ),
    );
  }
}

/// The legend: three swatch + label rows describing the grid states.
class SlotLegend extends StatelessWidget {
  const SlotLegend({super.key, required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final SlotState s in SlotState.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: <Widget>[
                Container(
                  height: 18,
                  width: 18,
                  decoration: BoxDecoration(
                    color: s.fill,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: s.border, width: 1),
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm + 2),
                Text(
                  slotStateLabel(l10n, s),
                  style: VelvetText.body().copyWith(
                    fontSize: 14,
                    color: BrandColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NoScheduleBanner (OQ-3) — persistent empty-state banner.
// ─────────────────────────────────────────────────────────────────────────────

/// A persistent, non-blocking banner shown when the viewed day (or the whole
/// visible period) resolves to [EffectiveSource.noSchedule] — no working hours
/// published. It coexists with the all-grey grid (the grid still renders below
/// it) and never prevents month/week navigation or scrolling.
///
/// frontend-design craft (within locked Velvet Touch): a recessed bordered well
/// matching the legend card treatment so it reads as part of the calendar card
/// rather than an alert. A muted `event_busy` glyph in its own inset disc, a
/// strong primary line, an optional muted helper, and — for editable viewers
/// only — a single camel-filled CTA that is the lone saturated element so it
/// reads as the clear action without competing with the grid.
///
/// [onAddHours] is null for read-only viewers (SALON_MASTER, OQ-2): the banner
/// still shows informationally but with no action button.
class NoScheduleBanner extends StatelessWidget {
  const NoScheduleBanner({
    super.key,
    required this.message,
    required this.helper,
    required this.ctaLabel,
    required this.onAddHours,
  });

  /// Primary line — «На цей день графік не задано» (single day) or «На цей
  /// період графік не задано» (whole visible period).
  final String message;

  /// Secondary muted helper line.
  final String helper;

  /// CTA label — «Додати робочі години».
  final String ctaLabel;

  /// Tap handler for the CTA. Null → read-only viewer → CTA is hidden.
  final VoidCallback? onAddHours;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$message. $helper',
      child: Container(
        key: const Key('no-schedule-banner'),
        padding: const EdgeInsets.all(VelvetSpacing.md),
        decoration: BoxDecoration(
          color: BrandColors.base,
          borderRadius: BorderRadius.circular(VelvetRadii.field),
          border: Border.all(color: BrandColors.faint.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Muted glyph well — calendar-off, not an error red.
                Container(
                  height: 38,
                  width: 38,
                  decoration: const BoxDecoration(
                    color: BrandColors.base,
                    shape: BoxShape.circle,
                    boxShadow: VelvetShadows.extrudedSmall,
                  ),
                  child: const Icon(
                    Icons.event_busy_rounded,
                    size: 19,
                    color: BrandColors.accentDeep,
                  ),
                ),
                const SizedBox(width: VelvetSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(message, style: VelvetText.bodyStrong()),
                      const SizedBox(height: VelvetSpacing.xs),
                      Text(
                        helper,
                        style: VelvetText.label().copyWith(
                          color: BrandColors.muted,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Editable viewers only: the lone camel-filled action.
            if (onAddHours != null) ...<Widget>[
              const SizedBox(height: VelvetSpacing.md),
              GhostButton(
                key: const Key('no-schedule-add-hours'),
                label: ctaLabel,
                icon: Icons.add_rounded,
                expand: true,
                dense: false,
                onPressed: onAddHours!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
