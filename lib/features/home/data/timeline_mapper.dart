// Phase 110 (13.9) — BEAUTY TIMELINE mapper.
//
// Maps `GET /clients/me/timeline`'s [api.TimelineItemResponse] rows (backend
// 19.5) into the [TimelineEntry] domain shape [BeautyTimelineSection]
// already renders. The generated DTO type never escapes the data layer.
//
// ── DROP POLICY (mobile-backlog forward-guidance, Phase 240 rating-
//    surfacing row — applies verbatim to this wiring) ──────────────────────
//
// A row is DROPPED (never reaches the rail) when it cannot render
// meaningfully:
//   • `date` is null — nothing to place it on the rail with, and nothing to
//     sort it by.
//   • BOTH `categoryKey` and `categoryName` are null/empty — nothing to
//     label the medallion or resolve an icon from.
// A dropped row is correct; a blank medallion with an empty caption is not.
//
// `bookingId` is carried through EXACTLY as the wire sends it — genuinely
// nullable, never coerced with `?? ''`. A blank-string id would be
// indistinguishable from a real one to `BeautyTimelineSection`'s tap guard,
// which is exactly the bug class this policy exists to prevent (an empty id
// silently "working" until it hits a route that 404s on it).
//
// `category` (the caption text) prefers `categoryName`, falling back to
// `categoryKey` only when `categoryName` is absent — both are guaranteed
// non-empty by the drop rule above, so this never yields a blank caption.
//
// KNOWN BACKEND GAP (flagged, not worked around here): despite
// `TimelineItemResponse`'s own javadoc calling `categoryName` a
// "human-readable category label", the current backend implementation
// (`ClientPassportService.toTimelineResponse`) derives BOTH `categoryKey`
// and `categoryName` from the SAME raw `service_definitions.category`
// column — an uppercase English slug such as `"MANICURE"` or
// `"NAIL_SERVICE"`, never the Ukrainian `platform_categories.display_name`.
// So today `categoryName` is not actually localized, and this mapper passes
// it through as-is per the policy above rather than inventing a client-side
// slug→Ukrainian-label table: categories are server-owned and
// admin-editable (see `favorites_filter.dart`'s header, which rejected a
// frozen client-side category vocabulary for the same reason), so a
// hardcoded translation table here would silently drift the moment an admin
// renames or adds one. This is a backend fix (join `platform_categories` and
// return `display_name`), out of this mobile phase's scope.
//
// ── SORT ─────────────────────────────────────────────────────────────────
//
// Most-recent-first (locked phase decision). The backend already orders by
// `b.startsAt DESC`, but that ordering is NOT relied upon here — rows are
// re-sorted client-side by the parsed [DateTime] descending, so a future
// backend change (or a caller requesting an explicit `sort`) can never
// silently flip the rail's order.
//
// ── DATE HANDLING ────────────────────────────────────────────────────────
//
// `TimelineItemResponse.date` is a built_value [api.Date] — a bare calendar
// day (year/month/day only, backend-derived in Europe/Kyiv), NOT an instant.
// It is converted via `.toDateTime()` ONLY — never through
// `toBeauticaTime`/`.toUtc()`/`.toLocal()`. Those exist to re-anchor a
// canonical-UTC INSTANT onto (or off) the Europe/Kyiv wall clock; feeding
// them an already-resolved calendar day would reinterpret it against the
// device's own zone, which is exactly the date-token-vs-instant class
// `shared/time/kyiv_day.dart` warns about. Same treatment
// `booking_mapper.dart`'s `WorkingDay(date: date.toDateTime())` already gives
// this identical DTO field shape.
//
// Flutter-free in spirit but not pure Dart: `core/errors/failures.dart`
// (pulled in transitively by nothing here directly, but see
// `timeline_repository.dart`) pulls in Flutter — same caveat as
// `passport_mapper.dart`.

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:built_collection/built_collection.dart';

import '../../../shared/formatters/uk_calendar.dart';
import '../domain/home_hub_models.dart';

/// Maps the backend BEAUTY TIMELINE rows into [TimelineEntry] domain models.
abstract final class TimelineMapper {
  /// Maps a page of [api.TimelineItemResponse] into [TimelineEntry]s,
  /// dropping unrenderable rows and sorting most-recent-first. See the file
  /// header for the exact drop / sort / date policy.
  static List<TimelineEntry> fromDtoList(
    BuiltList<api.TimelineItemResponse> dtos,
  ) {
    final List<_DatedEntry> dated = <_DatedEntry>[];
    for (final api.TimelineItemResponse dto in dtos) {
      final api.Date? wireDate = dto.date;
      if (wireDate == null) continue;

      final String? categoryName = dto.categoryName;
      final String? categoryKey = dto.categoryKey;
      final bool hasCategoryName =
          categoryName != null && categoryName.isNotEmpty;
      final bool hasCategoryKey = categoryKey != null && categoryKey.isNotEmpty;
      if (!hasCategoryName && !hasCategoryKey) continue;

      final DateTime date = wireDate.toDateTime();
      final String category = hasCategoryName ? categoryName : categoryKey!;

      dated.add(
        _DatedEntry(
          date: date,
          entry: TimelineEntry(
            category: category,
            dateLabel: _formatTimelineDate(date),
            categoryKey: hasCategoryKey ? categoryKey : null,
            bookingId: dto.bookingId,
            serviceName: dto.serviceName,
          ),
        ),
      );
    }

    dated.sort((_DatedEntry a, _DatedEntry b) => b.date.compareTo(a.date));
    return dated.map((_DatedEntry d) => d.entry).toList(growable: false);
  }
}

/// Pairs a parsed sort key with its mapped [TimelineEntry] so the sort in
/// [TimelineMapper.fromDtoList] never has to re-derive the date from the
/// already-formatted [TimelineEntry.dateLabel] string.
class _DatedEntry {
  const _DatedEntry({required this.date, required this.entry});
  final DateTime date;
  final TimelineEntry entry;
}

/// Compact single-line date label for the rail's narrow (84dp) tile, e.g.
/// "пн, 14 лип" — the same shape as `booking_date_labels.dart`'s
/// `formatBookingDayHeader`, but WITHOUT its `toBeauticaTime` conversion:
/// [date] here is already a resolved calendar day (see the file header), not
/// a UTC instant to re-anchor. Reuses the canonical word tables from
/// `shared/formatters/uk_calendar.dart` directly rather than hand-rolling new
/// vocabulary.
String _formatTimelineDate(DateTime date) {
  final String wd = weekdayAbbrev(date.weekday);
  final String mon = monthAbbrev(date.month);
  return '$wd, ${date.day} $mon';
}
