// Phase 484 — WeekNavBar: the row above the week strip on the master's
// «Записи». Port of the MasterWeekBookings preview
// (`docs/signup-designs/MasterWeekBookings/lib/widgets/week_nav_bar.dart`).
//
// ```
// 16–22 листопада ⌄                 [ День | 3 дні ]
// Наступний тиждень  (Сьогодні)
// ```
//
// WHICH week (title) on the left, HOW to look at it («День / 3 дні») on the
// right. The title IS the month-jump button (its chevron turns while the
// month is open); a horizontal swipe on it steps weeks. Week stepping
// otherwise lives at the strip's edges ([WeekStepButton]).
//
// One deliberate change from the preview: the relative line WRAPS the
// «Сьогодні» chip onto its own line when both do not fit (360 dp at text
// scale 1.3) instead of eliding «Наступний…» — no text here is ever cut.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

/// The week title: «16–22 листопада»; across a month boundary the CLDR short
/// genitive, «28 жовт. – 3 листоп.», so it still fits one line. [weekStart]
/// is the Monday date token; Sunday is calendar arithmetic, never
/// `Duration(hours: 24)` stepping.
String weekTitleLabel(DateTime weekStart) {
  final DateTime sunday = kyivAddDays(weekStart, 6);
  if (weekStart.month == sunday.month) {
    return '${weekStart.day}–${sunday.day} ${monthGenitive(sunday.month)}';
  }
  return '${weekStart.day} ${monthAbbrevGenitive(weekStart.month)} – '
      '${sunday.day} ${monthAbbrevGenitive(sunday.month)}';
}

/// The relative line under the title for a week [weekOffset] weeks from the
/// current one: «Цей тиждень» / «Наступний тиждень» / «Минулий тиждень» /
/// «Через 3 тижні» / «3 тижні тому».
String relativeWeekLabel(AppLocalizations l10n, int weekOffset) {
  if (weekOffset == 0) return l10n.masterWeekThisWeek;
  if (weekOffset == 1) return l10n.masterWeekNextWeek;
  if (weekOffset == -1) return l10n.masterWeekPrevWeek;
  return weekOffset > 0
      ? l10n.masterWeekRelative(weekOffset)
      : l10n.masterWeekAgo(-weekOffset);
}

/// Minimum fling velocity (logical px/s) for a swipe on the title to step a
/// week — the preview's figure.
const double _kTitleSwipeVelocity = 250;

/// Duration of the title cross-fade, chevron turn and toggle-thumb slide.
const Duration _kNavMotion = Duration(milliseconds: 220);

class WeekNavBar extends StatelessWidget {
  const WeekNavBar({
    super.key,
    required this.weekStart,
    required this.weekOffset,
    required this.threeDays,
    required this.monthOpen,
    required this.onToggleView,
    required this.onToggleMonth,
    required this.onToday,
    required this.onPrevWeek,
    required this.onNextWeek,
  });

  /// The shown week's Monday date token.
  final DateTime weekStart;

  /// Weeks from the current Kyiv week (0 = this week).
  final int weekOffset;

  /// «3 дні» when `true`, «День» when `false`.
  final bool threeDays;

  /// Whether the month calendar is open (turns the title's chevron).
  final bool monthOpen;

  final ValueChanged<bool> onToggleView;
  final VoidCallback onToggleMonth;

  /// The «Сьогодні» chip — only rendered off the current week.
  final VoidCallback onToday;

  /// A swipe on the title steps weeks too.
  final VoidCallback onPrevWeek;
  final VoidCallback onNextWeek;

  static const Key titleKey = Key('week-nav-title');
  static const Key todayKey = Key('week-nav-today');
  static const Key relativeKey = Key('week-nav-relative');

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _TitleButton(
                label: weekTitleLabel(weekStart),
                open: monthOpen,
                onTap: onToggleMonth,
                onSwipe: (double v) => v > 0 ? onPrevWeek() : onNextWeek(),
                l10n: l10n,
              ),
              const SizedBox(height: 2),
              _RelativeLine(
                label: relativeWeekLabel(l10n, weekOffset),
                showToday: weekOffset != 0,
                onToday: onToday,
                todayLabel: l10n.scheduleTodayAction,
              ),
            ],
          ),
        ),
        const SizedBox(width: VelvetSpacing.sm),
        ViewModeToggle(threeDays: threeDays, onChanged: onToggleView),
      ],
    );
  }
}

class _TitleButton extends StatelessWidget {
  const _TitleButton({
    required this.label,
    required this.open,
    required this.onTap,
    required this.onSwipe,
    required this.l10n,
  });

  final String label;
  final bool open;
  final VoidCallback onTap;
  final ValueChanged<double> onSwipe;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: open,
      label: l10n.masterWeekTitleSemantics(label),
      excludeSemantics: true,
      child: GestureDetector(
        key: WeekNavBar.titleKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onHorizontalDragEnd: (DragEndDetails d) {
          final double v = d.primaryVelocity ?? 0;
          if (v.abs() > _kTitleSwipeVelocity) onSwipe(v);
        },
        // Never truncates: one size, and at very large text the whole title
        // scales down rather than eliding.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedSwitcher(
                duration: _kNavMotion,
                transitionBuilder: (Widget child, Animation<double> a) =>
                    // dim-decorative: title cross-fade on a week change; 1 at rest
                    FadeTransition(opacity: a, child: child),
                child: Text(
                  label,
                  key: ValueKey<String>(label),
                  maxLines: 1,
                  softWrap: false,
                  style: VelvetText.weekRangeLabel,
                ),
              ),
              const SizedBox(width: VelvetSpacing.xs),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: _kNavMotion,
                child: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: BrandColors.accentDeep,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelativeLine extends StatelessWidget {
  const _RelativeLine({
    required this.label,
    required this.showToday,
    required this.onToday,
    required this.todayLabel,
  });

  final String label;
  final bool showToday;
  final VoidCallback onToday;
  final String todayLabel;

  @override
  Widget build(BuildContext context) {
    final Widget text = Text(
      label,
      key: WeekNavBar.relativeKey,
      style: VelvetText.feedbackMutedSm,
    );
    if (!showToday) return text;
    // `Wrap`, not `Row` + ellipsis: when label + chip do not fit side by side
    // the chip drops under the label and nothing is cut.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: VelvetSpacing.xs,
      runSpacing: 2,
      children: <Widget>[
        text,
        _TodayChip(label: todayLabel, onTap: onToday),
      ],
    );
  }
}

/// «Сьогодні» — only off the current week. A raised base-tone pill with
/// mocha link text (the shipped bordered-button recipe at pill radius): an
/// action, quieter than the CTA.
class _TodayChip extends StatelessWidget {
  const _TodayChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  static final BoxDecoration _decoration = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.circular(VelvetRadii.pill),
    border: Border.all(
      color: BrandColors.accent.withValues(alpha: 0.38),
      width: 1.5,
    ),
    boxShadow: VelvetShadows.borderedButton,
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        key: WeekNavBar.todayKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: _decoration,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.sm + 2,
              vertical: 2,
            ),
            child: Text(label, maxLines: 1, style: VelvetText.link()),
          ),
        ),
      ),
    );
  }
}

/// ‹ / › at the week strip's edges — a small raised neumorphic disc (the
/// bordered-button recipe at circle shape). A tap steps one week.
class WeekStepButton extends StatefulWidget {
  const WeekStepButton({super.key, required this.forward, required this.onTap});

  final bool forward;
  final VoidCallback onTap;

  /// The disc's diameter.
  static const double size = 30;

  /// The hit target around the disc (44 dp tall).
  static const Size hitSize = Size(36, 44);

  static const Key prevKey = Key('week-prev');
  static const Key nextKey = Key('week-next');

  @override
  State<WeekStepButton> createState() => _WeekStepButtonState();
}

class _WeekStepButtonState extends State<WeekStepButton> {
  bool _down = false;

  void _setDown(bool down) {
    if (_down == down) return;
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: widget.forward ? l10n.scheduleNextWeek : l10n.schedulePrevWeek,
      excludeSemantics: true,
      child: GestureDetector(
        key: widget.forward ? WeekStepButton.nextKey : WeekStepButton.prevKey,
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setDown(true),
        onTapCancel: () => _setDown(false),
        onTapUp: (_) {
          _setDown(false);
          widget.onTap();
        },
        child: SizedBox.fromSize(
          size: WeekStepButton.hitSize,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: WeekStepButton.size,
              height: WeekStepButton.size,
              decoration: BoxDecoration(
                color: BrandColors.base,
                shape: BoxShape.circle,
                border: Border.all(
                  color: BrandColors.accent.withValues(alpha: 0.18),
                ),
                boxShadow: _down ? null : VelvetShadows.borderedButton,
              ),
              child: Icon(
                widget.forward
                    ? Icons.chevron_right_rounded
                    : Icons.chevron_left_rounded,
                size: 20,
                color: BrandColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «День / 3 дні» — a recessed pill track with a raised thumb under the
/// active segment (depth only, no colour fill). The thumb slides.
class ViewModeToggle extends StatelessWidget {
  const ViewModeToggle({
    super.key,
    required this.threeDays,
    required this.onChanged,
  });

  final bool threeDays;
  final ValueChanged<bool> onChanged;

  static const Key dayKey = Key('week-view-day');
  static const Key threeDaysKey = Key('week-view-three-days');

  /// Track inset around the thumb.
  static const double _pad = 3;

  static final BoxDecoration _thumb = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.circular(VelvetRadii.pill),
    border: Border.all(
      color: BrandColors.accent.withValues(alpha: 0.38),
      width: 1.5,
    ),
    boxShadow: VelvetShadows.borderedButton,
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextScaler ts = MediaQuery.textScalerOf(context);
    // Both grow with the text scale so a label never clips.
    final double segW = 36 + ts.scale(11) * 1.6;
    final double h = 26 + ts.scale(11) * 0.4;
    return SizedBox(
      width: segW * 2 + _pad * 2,
      height: h + _pad * 2,
      child: NeumorphicInset(
        radius: VelvetRadii.pill,
        // The track never takes focus or an error — no ring transition.
        animatedRing: false,
        child: Stack(
          children: <Widget>[
            AnimatedPositioned(
              duration: _kNavMotion,
              curve: Curves.easeOutCubic,
              left: threeDays ? segW + _pad : _pad,
              top: _pad,
              width: segW,
              height: h,
              child: DecoratedBox(decoration: _thumb),
            ),
            Positioned.fill(
              child: Row(
                children: <Widget>[
                  const SizedBox(width: _pad),
                  _Segment(
                    segmentKey: dayKey,
                    label: l10n.masterWeekViewDay,
                    active: !threeDays,
                    width: segW,
                    onTap: () => onChanged(false),
                  ),
                  _Segment(
                    segmentKey: threeDaysKey,
                    label: l10n.masterWeekViewThreeDays,
                    active: threeDays,
                    width: segW,
                    onTap: () => onChanged(true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.segmentKey,
    required this.label,
    required this.active,
    required this.width,
    required this.onTap,
  });

  final Key segmentKey;
  final String label;
  final bool active;
  final double width;
  final VoidCallback onTap;

  static final TextStyle _active = VelvetText.label().copyWith(
    letterSpacing: 0.2,
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
  );
  static final TextStyle _inactive = VelvetText.label().copyWith(
    letterSpacing: 0.2,
    color: BrandColors.muted,
    fontWeight: FontWeight.w700,
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        key: segmentKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: width,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: active ? _active : _inactive,
            ),
          ),
        ),
      ),
    );
  }
}
