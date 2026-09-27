// Phase 13.6 — Relative-date formatter for review timestamps.
//
// The salon reviews endpoint (`GET /salons/{salonId}/reviews`) returns a raw
// `createdAt` DateTime, not a pre-formatted relative string — this formatter
// bridges that gap client-side so the "Відгуки" tab can render "2 тижні тому"
// / "місяць тому" style copy per the approved design.
//
// Buckets (from [dateTime] to [now], both Kyiv civil time — backlog :226; was
// `.toLocal()`, the device's own zone, until this file's last raw clock read
// — see `shared/time/kyiv_day.dart` for why that silently drifted a day near
// midnight for a device outside Europe/Kyiv):
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
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

/// How long a cached "now → Kyiv day" conversion (see [_resolveTodayKyiv])
/// stays valid. Bounded tight enough that it can never span a real Kyiv
/// midnight rollover in any way a user could notice — see
/// [_resolveTodayKyiv]'s doc comment for the full reasoning.
const Duration _kNowCacheWindow = Duration(seconds: 1);

/// Formats [dateTime] as a localized relative-date string, e.g. "2 тижні
/// тому". [now] defaults to [DateTime.now] — pass an explicit value in tests
/// for deterministic output.
String formatRelativeDate(
  AppLocalizations l10n,
  DateTime dateTime, {
  DateTime? now,
}) {
  // Bucket by calendar-day difference (not raw hours) so "today" / "yesterday"
  // read correctly regardless of time-of-day.
  //
  // Both operands are KYIV DATE TOKENS and the subtraction goes through
  // [kyivDaysBetween], never a hand-written `.difference(...).inDays`: until
  // Phase 284 this built two HOST-LOCAL midnights from Kyiv components and
  // subtracted them, so a host DST transition between them measured 23 h and
  // truncated a whole day away — an invite or review from 29 March rendered
  // «Сьогодні» on 30 March, every year, on every Kyiv-zoned device.
  final DateTime todayKyiv = _resolveTodayKyiv(now);
  final DateTime thenKyiv = kyivDayOf(dateTime);
  final int days = kyivDaysBetween(thenKyiv, todayKyiv);

  if (days <= 0) return l10n.relativeDateToday;
  if (days == 1) return l10n.relativeDateYesterday;
  if (days < 7) return l10n.relativeDateDaysAgo(days);
  if (days < 30) return l10n.relativeDateWeeksAgo(days ~/ 7);
  if (days < 365) return l10n.relativeDateMonthsAgo(days ~/ 30);
  return l10n.relativeDateYearsAgo(days ~/ 365);
}

/// The last resolved (raw instant, Kyiv day token) pair from the production
/// default path of [_resolveTodayKyiv] — `null` until the first call. See that
/// function's doc comment for what this is and is not allowed to do, and why
/// it deliberately carries NO test-visible reset.
DateTime? _cachedRealNow;
DateTime? _cachedRealTodayKyiv;

/// Resolves "today" as a KYIV DATE TOKEN (see `shared/time/kyiv_day.dart`),
/// Kyiv-anchored (mobile-perf MEDIUM, 2026-08-02 audit).
///
/// [toBeauticaTime] is a tz-transition binary search + [DateTime]
/// (`TZDateTime`) allocation per call — cheap for one card, but this
/// formatter's only production caller (`ReviewCard`) is rendered eagerly and
/// UNBOUNDED by `salon_reviews_section.dart` (pre-existing, out of scope —
/// see the backlog), so a reviews list with N cards paid N full conversions
/// of what is, for all practical purposes, the SAME instant.
///
/// [explicitNow] (every call in `relative_date_test.dart` passes one) is
/// converted fresh EVERY time and never cached: a test may deliberately reuse
/// the same literal instant across cases and must see an uncached,
/// byte-identical conversion each time, and the whole point of the parameter
/// is deterministic test control, not perf.
///
/// THE DEFAULT PATH *IS* REACHED FROM TESTS — this comment used to claim the
/// opposite ("never hit by a test with [explicitNow] null"), and the tree
/// violated it the day it was written: the seven `ReviewCard` renders in
/// `test/features/review/presentation/widgets/review_card_test.dart` all go
/// through the default, so the module globals below DO leak across widget
/// tests sharing one process. Harmless — the host clock is real and
/// monotonic, so a leaked entry is either still inside the window (and
/// correct) or outside it (and refreshed) — but it is a fact about this
/// module, not an invariant.
///
/// THERE IS DELIBERATELY NO `@visibleForTesting` RESET FOR THESE GLOBALS.
/// Phase 284 D3 proposed one; the QA audit removed it as unreachable. No test
/// can observe the leak: an entry older than [_kNowCacheWindow] is refreshed,
/// and one younger names the same Kyiv day (except inside the sub-second
/// window spanning a real Kyiv midnight, which a reset would not fix either,
/// because the very next uncached read is subject to the identical race). The
/// seam for a test that needs a deterministic "today" is [explicitNow] —
/// which every case in `relative_date_test.dart` already passes — not a cache
/// reset. See the phase doc's `## Status` for the reversal.
///
/// The production default path (`explicitNow == null`) instead caches the
/// last resolved (raw instant, Kyiv day token) pair and reuses it when the new raw
/// instant falls within [_kNowCacheWindow] of the cached one. This is NOT the
/// "memoise [toBeauticaTime] globally" move backlog `:191` warns against —
/// that warning is about caching results for an ARBITRARY instant (here,
/// `then` in [formatRelativeDate], which stays uncached, exactly per that
/// guidance). "Now" is different: it is monotonically increasing, and across
/// a burst of calls issued milliseconds apart while rendering a list it is
/// the same Kyiv calendar day in every case except the sub-1-second window
/// actually spanning a real Kyiv midnight rollover — a burst that happens to
/// straddle exactly that instant reuses a stale bucket for under a second and
/// self-corrects on the very next call outside the window; no persistent
/// staleness is possible.
DateTime _resolveTodayKyiv(DateTime? explicitNow) {
  if (explicitNow != null) return kyivDayOf(explicitNow);
  // instant-ok: value fallback, cache-checked and Kyiv-anchored below
  final DateTime raw = DateTime.now();
  final DateTime? cachedRaw = _cachedRealNow;
  final DateTime? cachedToday = _cachedRealTodayKyiv;
  if (cachedRaw != null &&
      cachedToday != null &&
      raw.difference(cachedRaw).abs() < _kNowCacheWindow) {
    return cachedToday;
  }
  final DateTime today = kyivDayOf(raw);
  _cachedRealNow = raw;
  _cachedRealTodayKyiv = today;
  return today;
}
