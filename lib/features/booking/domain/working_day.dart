// Phase 14.14 — WorkingDay: pure-Dart per-date working/non-working signal.
//
// Wraps `GET /masters/{masterId}/working-days?from=&to=` — the calendar
// day-availability endpoint that landed alongside this phase. Previously the
// backend exposed NO month/day-level availability signal at all (see the
// now-corrected header note in `presentation/widgets/month_calendar.dart`),
// so [SlotDateScreen] treated every non-past day as tappable. This model is
// the real per-date signal that replaces that placeholder heuristic.
//
// [working] answers ONLY "does the master work at all on [date]?" — it says
// nothing about whether every slot that day happens to already be booked out.
// A working day can still resolve to zero bookable slots (fully booked); that
// is the separate Phase 14.15 empty-state, driven by
// `SlotRepository.getMasterSlots` returning an empty list, not by this model.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'working_day.freezed.dart';

/// Whether [date] (date-only; time-of-day is meaningless here) is a day the
/// master works at all.
@freezed
abstract class WorkingDay with _$WorkingDay {
  const factory WorkingDay({required DateTime date, required bool working}) =
      _WorkingDay;
}
