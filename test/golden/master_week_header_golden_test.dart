// Phase 484 — the master week header (WeekNavBar + WeekStrip) at 360 dp,
// ×1.0 / ×1.3:
//   this_week   — «16–22 листопада», «Цей тиждень», window on Ср–Пт, today Чт;
//   next_week   — «23–29 листопада», «Наступний тиждень» + «Сьогодні», «День»;
//   cross_month — «30 листоп. – 6 груд.», «Через 2 тижні» + «Сьогодні».
// Composed with the preview screen's insets
// (`docs/signup-designs/MasterWeekBookings/lib/screens/
// master_week_bookings_screen.dart`). Reviewed against the preview (AC1).
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_nav_bar.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_time_grid.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

const double _kWidth = 360;
const double _kHeight = 180;

// future-date-ok: pinned fixture week; `today` is injected, never the host.
final DateTime _thisMonday = DateTime(2026, 11, 16);
final DateTime _today = kyivAddDays(_thisMonday, 3); // Чт 19

Widget _scene({
  required int weekOffset,
  required bool threeDays,
  required List<int> counts,
  required List<bool> dayOff,
  int firstVisibleDay = 2,
}) {
  final DateTime weekStart = kyivAddDays(_thisMonday, 7 * weekOffset);
  final int columns = threeDays ? 3 : 1;
  final PageController pager = WeekTimeGrid.controllerFor(
    visibleColumns: columns,
    firstVisibleDay: firstVisibleDay,
  );
  return SizedBox(
    width: _kWidth,
    height: _kHeight,
    child: ColoredBox(
      color: BrandColors.base,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.lg,
              VelvetSpacing.sm,
              VelvetSpacing.md,
              VelvetSpacing.xs,
            ),
            child: WeekNavBar(
              weekStart: weekStart,
              weekOffset: weekOffset,
              threeDays: threeDays,
              monthOpen: false,
              onToggleView: (_) {},
              onToggleMonth: () {},
              onToday: () {},
              onPrevWeek: () {},
              onNextWeek: () {},
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: WeekStrip(
              weekStart: weekStart,
              today: _today,
              counts: counts,
              dayOff: dayOff,
              pageController: pager,
              visibleColumns: columns,
              onTapDay: (_) {},
              onPrevWeek: () {},
              onNextWeek: () {},
            ),
          ),
          // The pager's client — the strip's window reads its position.
          Expanded(
            child: PageView.builder(
              controller: pager,
              itemCount: 7,
              itemBuilder: (_, _) => const SizedBox.expand(),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  final Map<String, Widget Function()> scenes = <String, Widget Function()>{
    'this_week': () => _scene(
      weekOffset: 0,
      threeDays: true,
      counts: const <int>[2, 3, 8, 7, 3, 1, 0],
      dayOff: const <bool>[false, false, false, false, false, false, true],
    ),
    'next_week': () => _scene(
      weekOffset: 1,
      threeDays: false,
      firstVisibleDay: 1,
      counts: const <int>[4, 2, 0, 5, 3, 0, 0],
      dayOff: const <bool>[false, false, true, false, false, false, true],
    ),
    'cross_month': () => _scene(
      weekOffset: 2,
      threeDays: true,
      firstVisibleDay: 0,
      counts: const <int>[1, 0, 2, 0, 0, 0, 0],
      dayOff: const <bool>[false, false, false, false, false, false, true],
    ),
  };
  for (final double scale in kGoldenTextScales) {
    final String suffix = widthScaleSuffix(_kWidth, scale);
    for (final MapEntry<String, Widget Function()> scene in scenes.entries) {
      goldenTest(
        'master week header ${scene.key} $suffix',
        fileName: 'master_week_header_${scene.key}_$suffix',
        constraints: BoxConstraints.tight(const Size(_kWidth, _kHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(width: _kWidth),
        builder: scene.value,
      );
    }
  }
}
