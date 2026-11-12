// Phase 483 — WeekDayHeader: «Чт 12» + the day's hours line — «9:00–18:00»
// for a WINDOW day, «Вихідний» for a day off, «Свій час · N» for an
// EXPLICIT_TIMES day; nothing when the schedule is not loaded.
import 'package:beautica_mobile/features/booking/presentation/widgets/week_time_grid.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

final DateTime _day = DateTime(2026, 11, 12);
const Key _hours = Key('hours');
const Key _header = Key('header');

EffectiveDay _schedule({
  List<WorkInterval> intervals = const <WorkInterval>[],
  List<TimeOfDay> times = const <TimeOfDay>[],
}) => EffectiveDay(
  date: _day,
  source: EffectiveSource.template,
  intervals: intervals,
  times: times,
);

Future<AppLocalizations> _pump(
  WidgetTester tester,
  EffectiveDay? schedule, {
  VoidCallback? onTap,
}) async {
  await tester.pumpApp(
    Scaffold(
      body: Center(
        child: SizedBox(
          width: 120,
          height: 60,
          child: WeekDayHeader(
            key: _header,
            label: 'Чт 12',
            semanticsLabel: null,
            schedule: schedule,
            isToday: false,
            hoursKey: _hours,
            onTap: onTap ?? () {},
          ),
        ),
      ),
    ),
  );
  return AppLocalizations.of(tester.element(find.byKey(_header)));
}

String _hoursText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_hours)).data ?? '';

void main() {
  testWidgets('WINDOW day: first start – last end, no leading zero', (
    WidgetTester tester,
  ) async {
    final AppLocalizations l10n = await _pump(
      tester,
      _schedule(
        intervals: <WorkInterval>[
          WorkInterval(
            start: const TimeOfDay(hour: 14, minute: 0),
            end: const TimeOfDay(hour: 18, minute: 0),
          ),
          WorkInterval(
            start: const TimeOfDay(hour: 9, minute: 0),
            end: const TimeOfDay(hour: 13, minute: 0),
          ),
        ],
      ),
    );
    expect(_hoursText(tester), l10n.masterWeekHours('9:00', '18:00'));
  });

  testWidgets('day off: the shipped «Вихідний» string', (
    WidgetTester tester,
  ) async {
    final AppLocalizations l10n = await _pump(tester, _schedule());
    expect(_hoursText(tester), l10n.salonBookingsColumnDayOff);
  });

  testWidgets('EXPLICIT_TIMES(6): «Свій час · 6»', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(
      tester,
      _schedule(
        times: <TimeOfDay>[
          for (int h = 10; h < 16; h++) TimeOfDay(hour: h, minute: 0),
        ],
      ),
    );
    expect(_hoursText(tester), l10n.masterWeekCustomTimes(6));
  });

  testWidgets('schedule not loaded: empty hours line', (
    WidgetTester tester,
  ) async {
    await _pump(tester, null);
    expect(_hoursText(tester), isEmpty);
  });

  testWidgets('the hours line is spoken with the day; tap fires onTap', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    final SemanticsHandle handle = tester.ensureSemantics();
    final AppLocalizations l10n = await _pump(
      tester,
      _schedule(),
      onTap: () => taps++,
    );
    expect(
      tester.getSemantics(find.byKey(_header)).label,
      'Чт 12, ${l10n.salonBookingsColumnDayOff}',
    );
    await tester.tap(find.byKey(_header));
    expect(taps, 1);
    handle.dispose();
  });
}
