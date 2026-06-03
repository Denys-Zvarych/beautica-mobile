// Phase 6.1 — WorkingHours domain model.
//
// Immutable value object representing one ISO day-of-week working window for a
// master. Time-of-day is stored in the wire format ("HH:mm:ss") the backend
// uses, with [start] / [end] getters exposing the parsed [TimeOfDay] the Phase
// 6.2 editor's time pickers need. Serialising from a single source (the wire
// strings) keeps the model the single source of truth — the getters are derived,
// never stored, so they can never drift from the persisted value.
//
// `dayOfWeek` follows the ISO-8601 convention the backend uses: 1 = Monday …
// 7 = Sunday.
//
// Uses `freezed` for value equality, copyWith, and pattern matching. The only
// Flutter dependency is [TimeOfDay] (material) — required by the spec so the
// presentation layer never has to re-parse the wire strings itself.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:freezed_annotation/freezed_annotation.dart';

part 'working_hours.freezed.dart';

/// A single working-hours window for one ISO day-of-week.
///
/// Closed days are represented as an entry with [isActive] `false` (the mapper
/// fills them in with a default window so the editor always has all 7 days).
@freezed
abstract class WorkingHours with _$WorkingHours {
  const WorkingHours._();

  const factory WorkingHours({
    /// ISO-8601 day of week: 1 = Monday … 7 = Sunday.
    required int dayOfWeek,

    /// Window start in wire format ("HH:mm:ss").
    required String startTime,

    /// Window end in wire format ("HH:mm:ss").
    required String endTime,

    /// Whether the master works on this day. Closed days are persisted as an
    /// inactive entry rather than omitted so the editor keeps a stable window.
    @Default(true) bool isActive,
  }) = _WorkingHours;

  /// Parsed start of the window, for the Phase 6.2 time picker.
  TimeOfDay get start => _parse(startTime);

  /// Parsed end of the window, for the Phase 6.2 time picker.
  TimeOfDay get end => _parse(endTime);

  /// Parses an "HH:mm" / "HH:mm:ss" wire string into a [TimeOfDay].
  ///
  /// Seconds (when present) are intentionally dropped — [TimeOfDay] has no
  /// second component and the editor only ever picks minute granularity.
  static TimeOfDay _parse(String s) {
    final p = s.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  /// Serialises a [TimeOfDay] back into the backend wire format ("HH:mm:00").
  ///
  /// Always zero-pads and appends `:00` seconds so the value round-trips
  /// through [start] / [end] and satisfies the backend's "HH:mm:ss" contract.
  static String fromTimeOfDay(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:00';
}
