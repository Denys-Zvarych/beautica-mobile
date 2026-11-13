// Phase 485 — the master «Записи» week view's «День / 3 дні» choice.
//
// Session-remembered, never persisted (decision D2): `keepAlive` so leaving
// the tab and coming back keeps the master's choice; reset to «3 дні» by
// `AuthNotifier.logout`'s session sweep (an `invalidate`, same as the week
// LRU). There is no prefs store in the app, and secure storage is for tokens
// and PII only — a view preference belongs in neither.

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'master_bookings_view_mode.g.dart';

/// How the master's week grid is looked at.
enum BookingsWeekViewMode {
  /// «День» — one day column per swipe.
  day,

  /// «3 дні» — three day columns, free scrolling resting on a day boundary.
  threeDays;

  /// Day columns on screen.
  int get visibleColumns => this == day ? 1 : 3;
}

@Riverpod(keepAlive: true)
class MasterBookingsViewMode extends _$MasterBookingsViewMode {
  @override
  BookingsWeekViewMode build() => BookingsWeekViewMode.threeDays;

  void set(BookingsWeekViewMode mode) {
    if (state != mode) state = mode;
  }
}
