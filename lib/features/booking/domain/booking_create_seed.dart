// Phase 487 — the empty week-grid tap's "create here" hint.
//
// A tap on an empty week-grid cell (`WeekTimeGrid.onTapEmpty`) yields a Kyiv
// DATE TOKEN plus Kyiv wall-clock minutes since midnight, already rounded
// down to the half hour by the grid (D2). This value carries that pair from
// the grid through the walk-in chain to the slot picker.
//
// TRAVEL (D1): as the query parameter `at=YYYY-MM-DDTHH:mm` (Kyiv wall
// clock), never as `extra` — the walk-in chain's `extra` contract
// (`WalkInGuest` on `…/new/services`) and its redirect stay untouched, and a
// query string survives state restoration.
//
// WALL CLOCK, NOT AN INSTANT: the pair is stored as calendar fields + minutes
// and never converted to an instant, so a DST-switch day keeps the tapped
// wall-clock time. Matching against the server's slots ([pickSeededSlot])
// compares Kyiv wall-clock minutes via `minutesSinceDayStart`, the same
// DST-safe derivation the grid itself buckets with.
//
// A HINT (D4): applied once by the slot picker, never submits anything, and
// never invents a slot — only a returned, available slot can be selected
// (D3: exact match, else the nearest later, else the nearest earlier).
//
// Pure Dart.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:beautica_mobile/shared/time/kyiv_day.dart';

import 'booking_slot.dart';

part 'booking_create_seed.freezed.dart';

/// The query-parameter name the seed travels under.
const String bookingCreateSeedQueryKey = 'at';

const int _minutesPerDay = 24 * 60;

final RegExp _queryPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$',
);

/// A Kyiv [day] (date token, see `kyiv_day.dart`) + wall-clock [minute] since
/// that day's midnight (0..1439).
@freezed
abstract class BookingCreateSeed with _$BookingCreateSeed {
  const BookingCreateSeed._();

  @Assert('minute >= 0 && minute < 1440', 'minute must be within one day')
  const factory BookingCreateSeed({
    /// Kyiv calendar day as a date token — only `.year/.month/.day` are read.
    required DateTime day,

    /// Kyiv wall-clock minutes since [day]'s midnight.
    required int minute,
  }) = _BookingCreateSeed;

  /// Parses `YYYY-MM-DDTHH:mm`; `null` when [raw] is absent or malformed
  /// (bad shape, impossible date, hour > 23, minute > 59).
  static BookingCreateSeed? fromQuery(String? raw) {
    if (raw == null) return null;
    final RegExpMatch? m = _queryPattern.firstMatch(raw);
    if (m == null) return null;
    final int year = int.parse(m.group(1) ?? '');
    final int month = int.parse(m.group(2) ?? '');
    final int dayOfMonth = int.parse(m.group(3) ?? '');
    final int hour = int.parse(m.group(4) ?? '');
    final int min = int.parse(m.group(5) ?? '');
    if (hour > 23 || min > 59) return null;
    final DateTime day = DateTime(year, month, dayOfMonth);
    // `DateTime` normalises overflow (Feb 30 → Mar 2) — reject instead.
    if (day.year != year || day.month != month || day.day != dayOfMonth) {
      return null;
    }
    return BookingCreateSeed(day: day, minute: hour * 60 + min);
  }

  /// The seed's own date token (time-of-day stripped, calendar fields only).
  DateTime get dayToken => DateTime(day.year, day.month, day.day);

  /// `YYYY-MM-DDTHH:mm`, Kyiv wall clock.
  String toQuery() {
    String two(int v) => v.toString().padLeft(2, '0');
    final String y = day.year.toString().padLeft(4, '0');
    return '$y-${two(day.month)}-${two(day.day)}'
        'T${two(minute ~/ 60)}:${two(minute % 60)}';
  }

  /// [path] with `?at=<toQuery()>` appended (or `&at=` when [path] already
  /// carries a query).
  String appendTo(String path) {
    final String sep = path.contains('?') ? '&' : '?';
    return '$path$sep$bookingCreateSeedQueryKey=${toQuery()}';
  }
}

/// [path] with [seed] appended, or [path] unchanged when [seed] is `null`.
String withBookingCreateSeed(String path, BookingCreateSeed? seed) =>
    seed == null ? path : seed.appendTo(path);

/// D3 — the slot the seed selects from [slots] (the server's list for the
/// seed day): the available slot starting exactly at the seed's Kyiv
/// wall-clock time; else the first available one after it; else the last
/// available one before it; `null` when none is available (or none falls on
/// the seed day). Never invents a slot.
BookingSlot? pickSeededSlot(List<BookingSlot> slots, BookingCreateSeed seed) {
  final DateTime day = seed.dayToken;
  final midnight = kyivMidnight(day);
  BookingSlot? firstAfter;
  int firstAfterMinute = _minutesPerDay * 2;
  BookingSlot? lastBefore;
  int lastBeforeMinute = -_minutesPerDay;
  for (final BookingSlot s in slots) {
    if (!s.available) continue;
    if (kyivDayOf(s.startAt) != day) continue;
    final int minute = minutesSinceDayStart(s.startAt, midnight);
    if (minute == seed.minute) return s;
    if (minute > seed.minute) {
      if (minute < firstAfterMinute) {
        firstAfterMinute = minute;
        firstAfter = s;
      }
    } else if (minute > lastBeforeMinute) {
      lastBeforeMinute = minute;
      lastBefore = s;
    }
  }
  return firstAfter ?? lastBefore;
}
