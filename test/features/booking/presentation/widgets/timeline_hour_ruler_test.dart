// Phase 482 — TimelineHourRuler's ADDITIVE `hourHeight` override. `null`
// (every caller before the week grid) must keep the density's band; a value
// overrides it for label spacing AND the ruler's own extent.
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_density.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_hour_ruler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const int _kFirst = 8;
const int _kLast = 12;

Future<void> _pumpRuler(
  WidgetTester tester, {
  TimelineDensity density = TimelineDensity.master,
  double? hourHeight,
}) async {
  await tester.pumpApp(
    Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: TimelineHourRuler(
          firstHour: _kFirst,
          lastHour: _kLast,
          density: density,
          hourHeight: hourHeight,
        ),
      ),
    ),
    width: 360,
    height: 800,
  );
}

/// Vertical distance between consecutive hour labels — the band in use.
List<double> _labelSteps(WidgetTester tester) {
  final List<double> tops = <double>[
    for (int h = _kFirst; h <= _kLast; h++)
      // i18n-finder-ok: wall-clock digits, not localised copy.
      tester.getTopLeft(find.text('${h.toString().padLeft(2, '0')}:00')).dy,
  ];
  return <double>[for (int i = 1; i < tops.length; i++) tops[i] - tops[i - 1]];
}

void main() {
  testWidgets('hourHeight null keeps the master density band (120 dp)', (
    WidgetTester tester,
  ) async {
    await _pumpRuler(tester);

    for (final double step in _labelSteps(tester)) {
      expect(step, closeTo(TimelineDensity.master.hourHeight, 0.01));
    }
  });

  testWidgets('hourHeight null keeps the salon density band', (
    WidgetTester tester,
  ) async {
    await _pumpRuler(tester, density: TimelineDensity.salon);

    for (final double step in _labelSteps(tester)) {
      expect(step, closeTo(TimelineDensity.salon.hourHeight, 0.01));
    }
  });

  testWidgets('an explicit hourHeight overrides the density label spacing', (
    WidgetTester tester,
  ) async {
    await _pumpRuler(tester, hourHeight: 72);

    for (final double step in _labelSteps(tester)) {
      expect(step, closeTo(72, 0.01));
    }
  });

  testWidgets('the ruler extent follows the override, not the density', (
    WidgetTester tester,
  ) async {
    await _pumpRuler(tester);
    final double defaultH = tester
        .getSize(find.byType(TimelineHourRuler))
        .height;

    await _pumpRuler(tester, hourHeight: 72);
    final double overriddenH = tester
        .getSize(find.byType(TimelineHourRuler))
        .height;

    // Same label + trailing-margin terms, only the band differs.
    expect(
      defaultH - overriddenH,
      closeTo(
        (_kLast - _kFirst) * (TimelineDensity.master.hourHeight - 72),
        0.01,
      ),
    );
  });
}
