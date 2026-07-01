// Phase 13.6 — Relative-date formatter for review timestamps.
//
// The salon reviews endpoint (`GET /salons/{salonId}/reviews`) returns a raw
// `createdAt` DateTime, not a pre-formatted relative string — this formatter
// bridges that gap client-side so the "Відгуки" tab can render "2 тижні тому"
// / "місяць тому" style copy per the approved design.
//
// Buckets (from [dateTime] to [now], both local time):
//   0 days            → "Сьогодні"
//   1 day             → "Вчора"
//   2–6 days          → "N днів тому" (Ukrainian plural)
//   7–29 days         → "N тижнів/тиждень тому"
//   30–364 days       → "N місяців/місяць тому"
//   >= 365 days       → "N років/рік тому"
//
// Requires [AppLocalizations] (not pure Dart) — lives alongside the other
// l10n-consuming shared formatters/widgets rather than in
// `shared/formatters/duration_minutes.dart` (which is pure Dart).

import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Formats [dateTime] as a localized relative-date string, e.g. "2 тижні
/// тому". [now] defaults to [DateTime.now] — pass an explicit value in tests
/// for deterministic output.
String formatRelativeDate(
  AppLocalizations l10n,
  DateTime dateTime, {
  DateTime? now,
}) {
  final DateTime nowLocal = (now ?? DateTime.now()).toLocal();
  final DateTime then = dateTime.toLocal();
  // Bucket by calendar-day difference (not raw hours) so "today" / "yesterday"
  // read correctly regardless of time-of-day.
  final DateTime todayStart = DateTime(
    nowLocal.year,
    nowLocal.month,
    nowLocal.day,
  );
  final DateTime thenStart = DateTime(then.year, then.month, then.day);
  final int days = todayStart.difference(thenStart).inDays;

  if (days <= 0) return l10n.relativeDateToday;
  if (days == 1) return l10n.relativeDateYesterday;
  if (days < 7) return l10n.relativeDateDaysAgo(days);
  if (days < 30) return l10n.relativeDateWeeksAgo(days ~/ 7);
  if (days < 365) return l10n.relativeDateMonthsAgo(days ~/ 30);
  return l10n.relativeDateYearsAgo(days ~/ 365);
}
