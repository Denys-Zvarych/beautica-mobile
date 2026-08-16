// Phase 231 amendment — date-group headers for the master «Архів» list.
//
// The archive is a FLAT list spanning arbitrary past dates (unlike «Мої
// записи», where a day rail already supplies the date context), so a bare
// `MasterBookingCard` time range (`14:00 – 15:00`, no date) is ambiguous.
// This file owns exactly one thing: turning the notifier's already-paginated,
// already-merged `MasterArchiveState.items` (server-ordered newest-first)
// into a single flat list of header-or-card entries that
// `master_archive_screen.dart` feeds straight into its existing
// `ListView.separated` — see that file for why virtualization + the per-row
// `RepaintBoundary` must survive this change untouched.
//
// ## Grouping key: the Kyiv CALENDAR day, not device-local or UTC
//
// [kyivDayOf] converts the booking's wire `startAt` (canonical UTC) to the
// Europe/Kyiv wall-clock and truncates to a date — a 00:30 Kyiv booking is
// 21:30 the PREVIOUS day in UTC, so grouping on the raw UTC instant (or the
// device's own local zone, which is NOT necessarily Kyiv — the dev VM's
// `TZ=Europe/Kyiv` masks exactly this) would split one Kyiv day into two
// headers or merge two different Kyiv days under one. See
// `shared/time/kyiv_day.dart`'s file header.
//
// ## Page-boundary merge — for free, not by special-casing
//
// [groupArchiveByKyivDay] is called on [MasterArchiveState.items] — the
// FULLY ACCUMULATED list across every fetched raw page (the notifier appends
// each `loadMore()` page's rows onto the existing list; see
// `master_archive_notifier.dart`). Grouping runs over that single flat list
// EVERY build, comparing each booking only to the PREVIOUS booking in the
// list — never to a page boundary, which does not exist at this layer. So a
// Kyiv day whose rows happen to straddle two raw server pages still produces
// exactly ONE header: the day only "restarts" when the actual calendar day
// changes, never when a page happens to end. A naive alternative that instead
// grouped each freshly-fetched page independently (e.g. always emitting a
// header for the first row of a newly-appended page) would wrongly duplicate
// the header for a day that continues across the boundary — see
// `archive_day_groups_test.dart`'s page-boundary-merge test, which is pinned
// specifically against that mistake.
//
// Pure Dart — no Flutter imports (mirrors `booking_date_labels.dart`).

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

/// One row of the flattened archive list: either a date-group header or a
/// booking card. Sealed so `master_archive_screen.dart`'s `itemBuilder` can
/// exhaustively pattern-match with no default branch to silently miss a new
/// variant.
sealed class ArchiveListEntry {
  const ArchiveListEntry();
}

/// A date-group header, inserted once at the start of every run of bookings
/// that share a Kyiv calendar day.
final class ArchiveDayHeaderEntry extends ArchiveListEntry {
  const ArchiveDayHeaderEntry({
    required this.kyivDay,
    required this.representativeInstant,
  });

  /// The Kyiv calendar DATE TOKEN this header represents (see
  /// `kyiv_day.dart`'s date-token-vs-instant distinction) — comparison/key
  /// use ONLY. Never pass this into `formatBookingDayHeader` or any
  /// `toBeauticaTime`/`.toUtc()`/`.toLocal()` call: it is not an instant, and
  /// re-converting it would silently produce the wrong day depending on the
  /// device's timezone (it compiles and runs — nothing statically catches
  /// it).
  final DateTime kyivDay;

  /// A real wire instant (one booking's `startAt`) known to fall on
  /// [kyivDay] — this is what gets passed to `formatBookingDayHeader`, which
  /// performs its own `toBeauticaTime` conversion to derive the displayed
  /// weekday/day/month.
  final DateTime representativeInstant;
}

/// A single booking row.
final class ArchiveBookingEntry extends ArchiveListEntry {
  const ArchiveBookingEntry(this.booking);

  final Booking booking;
}

/// Flattens [items] (server-ordered, newest-first, already accumulated
/// across every fetched raw page) into a header-or-card list, inserting a
/// header exactly once at the start of every run of consecutive bookings
/// that share a Kyiv calendar day. See file header for the page-boundary
/// merge guarantee.
List<ArchiveListEntry> groupArchiveByKyivDay(List<Booking> items) {
  final List<ArchiveListEntry> entries = <ArchiveListEntry>[];
  DateTime? lastDay;
  for (final Booking booking in items) {
    final DateTime day = kyivDayOf(booking.startAt);
    if (lastDay == null || day != lastDay) {
      entries.add(
        ArchiveDayHeaderEntry(
          kyivDay: day,
          representativeInstant: booking.startAt,
        ),
      );
      lastDay = day;
    }
    entries.add(ArchiveBookingEntry(booking));
  }
  return entries;
}
