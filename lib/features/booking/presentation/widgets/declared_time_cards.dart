// Phase 244 follow-up — the master «Мої записи» day view for an
// EXPLICIT_TIMES working day (the master declared discrete times like
// `11:00`, `15:00`, `16:30` instead of a continuous working window).
//
// Ported from the approved preview
// `docs/signup-designs/MasterTimelineExplicitTimes/lib/widgets/
// declared_time_cards.dart`, Option E, the **E2** variant the user approved
// (free card WITHOUT the `+`) — no `_AddAffordance`, no harness duplication
// (the preview rendered the day TWICE, tagged E1/E2, purely so the two could
// be compared; a real screen renders one).
//
// ## The shape, transcribed
//
// One CARD per entry, in ascending time order:
//   * booked  — time (`VelvetText.statValue()`) / client name
//     (`VelvetText.subheading()`) / `service · duration`
//     (`VelvetText.masterCardServiceFull`, duration muted).
//   * free    — time / «Вільно», muted. Same footprint, radius, padding and
//     border as a booked card; the only difference is LIFT — the booked card
//     keeps `VelvetShadows.borderedCard`, the free card drops it and stands
//     on its border alone. NOT a button, no tap target.
//
// NO hour ruler, NO gridlines, NO hour labels — nothing here derives from
// `BookingsTimelineGrid`'s `_kHourH`. Duration is TEXT (line 3), never
// geometry: every card floors at [DeclaredTimeCard._kCardMinHeight] (140)
// regardless of the booking's length, so 30/60/90-minute bookings render
// identically. This is intentionally NOT `MasterBookingCard` — see the
// preview README's cost table for what a card here does not carry (no price
// pill, no status badge — see this file's "STATUS IS NOT SHOWN" section).
//
// ## THE ENTRY LIST IS A UNION, NEVER A FILTER
//
// [_mergeDeclaredAndBookings] is the whole of this file's correctness
// contract. [BookingsDiscoveryView] hands this widget [bookings] UNFILTERED
// by `bookingsInsideScheduleWindow` — that predicate is a GRID concept
// (INTERVAL days only) and must never silently drop a row here. Every
// booking in [bookings] gets exactly one card:
//   * its start matches a declared time  -> that declared time's card is
//     booked;
//   * its start matches NO declared time (e.g. it was booked before the
//     master edited that day's hours) -> it still renders, as its OWN entry
//     at its OWN time, merged into the list in time order. Dropping it would
//     be data loss, not tidiness.
// A declared time with no matching booking renders as a free card. The
// header count above this widget ([BookingsDiscoveryView]'s
// `masterBookingsCount`) is derived from the SAME [bookings] list this widget
// renders every card of — see that file's `_Loaded._body` — so the two can
// never disagree: free entries are not bookings and are never counted.
//
// ## STATUS IS NOT SHOWN — a CANCELLED/DECLINED booking looks identical to a
// CONFIRMED one here
//
// The approved design (E2) carries exactly three lines — time / client /
// `service · duration` — with no price pill and no `TimelineStatusBadge`,
// unlike the shipped `MasterBookingCard`. This is what the approved design
// costs, implemented as approved: a booking's [Booking.status] is not read
// anywhere in this file, so a CANCELLED, DECLINED or NOT_COMPLETED booking on
// an EXPLICIT_TIMES day renders on the same bordered-and-lifted card as a
// CONFIRMED one, with no visual distinction at all. This is a real gap versus
// the INTERVAL-day grid (`MasterBookingCard` always renders a status signal)
// and is flagged here as a product decision to make, not silently absorbed —
// see the phase doc / backlog for the open row. Do NOT re-add the price pill
// or a status badge to "fix" this without a design update — the preview is
// the literal source of truth and does not carry either.
//
// ## Kyiv time discipline
//
// [Booking.startAt] is canonical UTC. Matching it against a declared
// [TimeOfDay] (a pure wall-clock value, carrying no zone of its own) reads
// through [toBeauticaTime] — never `.hour`/`.minute` off the raw UTC instant,
// which would render the wrong card on any non-Kyiv device or CI's UTC
// runner. Mirrors `bookings_timeline_grid.dart`'s own
// `_minutesSinceDayStart` (kept private there; re-derived here rather than
// exported, since the two files' minute conventions — this one never needs
// values >= 1440, that file's R1 fix explicitly does for a booking crossing
// midnight — are not quite the same contract).
//
// ## Gating — EXPLICIT_TIMES days only
//
// This widget is never constructed for an INTERVAL day. `BookingsDiscoveryView
// ._Loaded` gates the branch on `EffectiveDay.isExplicitTimes`; every
// INTERVAL day keeps rendering `BookingsTimelineGrid`, byte-for-byte
// unchanged, exactly as before this feature.

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart'
    show formatTime;
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';

import '../../domain/booking.dart';
import '../../domain/booking_display_x.dart';

/// One resolved row of the declared-times list — a declared time with an
/// OPTIONAL matched booking, or a booking whose start matched no declared
/// time (see [_mergeDeclaredAndBookings]'s "stray" pass). [time] is always
/// the entry's own Kyiv wall-clock minute, whether it came from the day's
/// declared times or from an unmatched booking's own start.
class _DeclaredEntry {
  const _DeclaredEntry({
    required this.minute,
    required this.time,
    required this.booking,
  });

  /// Minutes since the selected Kyiv day's midnight — the sort key.
  final int minute;
  final TimeOfDay time;
  final Booking? booking;
}

/// Kyiv wall-clock minutes-since-midnight for [instant] on the day
/// [midnight] anchors — mirrors `bookings_timeline_grid.dart`'s
/// `_minutesSinceDayStart`. Not exported from that file (see this file's
/// header); re-derived here rather than duplicated via a shared export
/// because the two live on genuinely separate contracts (see the header).
int _kyivMinutesSinceMidnight(DateTime instant, tz.TZDateTime midnight) {
  final tz.TZDateTime local = toBeauticaTime(instant);
  return local.difference(midnight).inMinutes;
}

/// The union of [declaredTimes] and [bookings] — see this file's "THE ENTRY
/// LIST IS A UNION" section. Every booking in [bookings] appears in exactly
/// one returned entry; nothing is ever dropped.
///
/// Matching is by exact Kyiv minute, first-unconsumed-booking-wins when more
/// than one booking shares a minute (a double-booked declared time is not the
/// common case this mode is designed for, but every such booking still gets
/// its own card rather than being silently discarded). "First" is a
/// genuinely deterministic order: [sortedBookings] below sorts by
/// `startAt` with [Booking.id] as an explicit tie-break, because
/// `List.sort` is NOT stable in Dart — leaving two identical-`startAt`
/// bookings' relative order to the sort algorithm's whim would make this
/// doc's own "first" claim false for that case.
List<_DeclaredEntry> _mergeDeclaredAndBookings(
  List<TimeOfDay> declaredTimes,
  List<Booking> bookings,
  DateTime day,
) {
  final tz.TZDateTime midnight = tz.TZDateTime(
    beauticaZone,
    day.year,
    day.month,
    day.day,
  );

  // Bookings arrive pre-sorted by `startAt` ASC from the server, but the
  // FINAL merge's two-pointer step (further below) depends on that
  // ordering — sort defensively rather than trust it silently. Pass 1
  // (immediately below) does NOT depend on this order for correctness — it
  // looks up by minute via a map — but it DOES rely on it for the
  // documented tie-break (see [_mergeDeclaredAndBookings]'s doc:
  // "first-unconsumed-booking-wins"), since indices are appended to each
  // minute's bucket in this sorted order. `startAt` alone is NOT a
  // sufficient sort key: two bookings can genuinely share one `startAt`
  // (a double-booked declared time), and `List.sort`'s algorithm is
  // explicitly documented as unstable, so equal-`startAt` elements could
  // land in either relative order on any given run. [Booking.id] (globally
  // unique, stable, comparable) is the secondary key that makes the sort —
  // and therefore "first" — actually deterministic.
  final List<Booking> sortedBookings = List<Booking>.of(bookings)
    ..sort((Booking a, Booking b) {
      final int byStart = a.startAt.compareTo(b.startAt);
      return byStart != 0 ? byStart : a.id.compareTo(b.id);
    });
  final List<int> bookingMinutes = sortedBookings
      .map((Booking b) => _kyivMinutesSinceMidnight(b.startAt, midnight))
      .toList(growable: false);
  final List<bool> consumed = List<bool>.filled(sortedBookings.length, false);

  // One O(B) pass building a minute -> booking-indices index, so pass 1
  // below is O(D) lookups instead of an O(D×B) nested scan of
  // `sortedBookings` per declared time. NOT the two-pointer discipline —
  // that applies only to the final merge step further below, where both
  // input lists are already known-ascending; a minute -> indices map is the
  // right tool here because pass 1 needs random-access-by-minute, not a
  // linear co-walk.
  final Map<int, List<int>> indicesByMinute = <int, List<int>>{};
  for (int j = 0; j < sortedBookings.length; j++) {
    indicesByMinute.putIfAbsent(bookingMinutes[j], () => <int>[]).add(j);
  }

  // Pass 1 — one entry per declared time, VERBATIM order, matched against
  // the first unconsumed booking at that exact minute via the map built
  // above (O(1) amortized per declared time, not a scan of every booking).
  final List<_DeclaredEntry> declaredEntries = <_DeclaredEntry>[];
  for (final TimeOfDay t in declaredTimes) {
    final int dm = t.hour * 60 + t.minute;
    int matchIndex = -1;
    final List<int>? candidates = indicesByMinute[dm];
    if (candidates != null) {
      for (final int j in candidates) {
        if (!consumed[j]) {
          matchIndex = j;
          break;
        }
      }
    }
    if (matchIndex == -1) {
      declaredEntries.add(_DeclaredEntry(minute: dm, time: t, booking: null));
    } else {
      consumed[matchIndex] = true;
      declaredEntries.add(
        _DeclaredEntry(
          minute: dm,
          time: t,
          booking: sortedBookings[matchIndex],
        ),
      );
    }
  }

  // Pass 2 — every booking pass 1 did NOT consume (its start matches no
  // declared time) gets its own entry, at its own minute. Never dropped.
  final List<_DeclaredEntry> strayEntries = <_DeclaredEntry>[];
  for (int j = 0; j < sortedBookings.length; j++) {
    if (consumed[j]) continue;
    final int m = bookingMinutes[j];
    strayEntries.add(
      _DeclaredEntry(
        minute: m,
        time: TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60),
        booking: sortedBookings[j],
      ),
    );
  }

  // Merge — both lists are ascending by minute (declaredTimes is resolved
  // sorted+de-duped by the schedule mapper; sortedBookings was just sorted
  // above and pass 2 preserves that order), so a stable two-pointer merge is
  // enough; ties favour the declared entry.
  final List<_DeclaredEntry> merged = <_DeclaredEntry>[];
  int di = 0;
  int si = 0;
  while (di < declaredEntries.length && si < strayEntries.length) {
    if (declaredEntries[di].minute <= strayEntries[si].minute) {
      merged.add(declaredEntries[di++]);
    } else {
      merged.add(strayEntries[si++]);
    }
  }
  merged.addAll(declaredEntries.skip(di));
  merged.addAll(strayEntries.skip(si));
  return merged;
}

/// The declared-times day body — a plain scrolling list of [DeclaredTimeCard]
/// s, one per [_mergeDeclaredAndBookings] entry. Sits inside the same
/// `Expanded(child: Padding(...))` slot `BookingsDiscoveryView._Loaded._body`
/// gives `BookingsTimelineGrid` on an INTERVAL day, so it owns its own
/// scrolling exactly like that widget does.
///
/// A [StatefulWidget], NOT the `StatelessWidget` this shipped as originally
/// (mobile-perf MEDIUM fix) — `_Loaded` (the parent) is itself a
/// `StatelessWidget` constructed fresh by its own parent `Consumer` on every
/// rebuild, so a plain `build()`-time call to [_mergeDeclaredAndBookings]
/// reran on every rebuild regardless of whether [declaredTimes]/[bookings]/
/// [day] had actually changed — the same regression class already fixed
/// twice on the sibling INTERVAL path (see `bookings_discovery_view.dart`'s
/// `_visibleBookingsFor` feeding [BookingsTimelineGrid]'s own
/// `didUpdateWidget` gate). [BookingsTimelineGrid] is the closer sibling of
/// the two idioms available: it is itself a leaf `StatefulWidget` occupying
/// this exact slot, owning its OWN recompute cache in `didUpdateWidget`
/// rather than reaching up into a parent `State` — no plumbing across a
/// widget boundary, and no need to expose the file-private [_DeclaredEntry]
/// shape outside this file (hoisting the memo into
/// `_BookingsDiscoveryViewState`, `_visibleBookingsFor`'s home, would
/// require exactly that). This widget mirrors that shape instead.
class DeclaredTimeCards extends StatefulWidget {
  const DeclaredTimeCards({
    required this.declaredTimes,
    required this.bookings,
    required this.day,
    required this.onTapBooking,
    super.key,
  });

  /// The day's declared times, VERBATIM — one card each, in declared order.
  /// Nothing is generated between them and nothing is padded onto the ends.
  final List<TimeOfDay> declaredTimes;

  /// The day's bookings, UNFILTERED by any working-hours window — see this
  /// file's header. Every one of these renders as a card.
  final List<Booking> bookings;

  /// The selected Kyiv calendar day — the anchor
  /// [_kyivMinutesSinceMidnight] measures every booking's start against.
  final DateTime day;

  /// Fires with the tapped booking. No `Navigator`/`context.push` in this
  /// leaf widget — the caller owns navigation, same contract as
  /// `BookingsTimelineGrid.onBookingTap`.
  final ValueChanged<Booking> onTapBooking;

  @override
  State<DeclaredTimeCards> createState() => _DeclaredTimeCardsState();
}

class _DeclaredTimeCardsState extends State<DeclaredTimeCards> {
  /// The last-computed merge — recomputed only in [initState] and,
  /// conditionally, in [didUpdateWidget]. `build()` never calls
  /// [_mergeDeclaredAndBookings] directly, which is the whole of the fix:
  /// a rebuild with unchanged inputs (a fresh `DeclaredTimeCards` instance
  /// from the parent's own rebuild, same data) reuses this list instead of
  /// reallocating one.
  late List<_DeclaredEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = _mergeDeclaredAndBookings(
      widget.declaredTimes,
      widget.bookings,
      widget.day,
    );
  }

  @override
  void didUpdateWidget(covariant DeclaredTimeCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Mirrors [BookingsTimelineGrid.didUpdateWidget]'s gate:
    //   * `bookings` — `identical`, not `==`. `List` has reference equality
    //     anyway, and `BookingsDayState.items` (this file's caller always
    //     passes that list, or a filtered derivative of it) only changes
    //     identity on a genuine re-fetch — see `bookings_discovery_view
    //     .dart`'s `_visibleBookingsFor` doc.
    //   * `day` — value comparison; `DateTime` overrides `==`.
    //   * `declaredTimes` — value comparison via [listEquals], NOT
    //     `identical`. Unlike `bookings`, this list is `resolved.times` off
    //     a fresh `EffectiveDay` the schedule notifier constructs on every
    //     resolve regardless of whether the declared times actually changed
    //     (the same reason `_visibleBookingsFor` compares
    //     `ScheduleTimelineWindow`'s fields by value rather than by
    //     reference) — an `identical` check here would defeat the memo on
    //     every schedule refetch, changed or not. [TimeOfDay] overrides
    //     `==`, so [listEquals] is a true value comparison.
    if (!identical(widget.bookings, oldWidget.bookings) ||
        widget.day != oldWidget.day ||
        !listEquals(widget.declaredTimes, oldWidget.declaredTimes)) {
      _entries = _mergeDeclaredAndBookings(
        widget.declaredTimes,
        widget.bookings,
        widget.day,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const Key('declared-time-cards'),
      padding: EdgeInsets.zero,
      itemCount: _entries.length,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: VelvetSpacing.md),
      itemBuilder: (BuildContext context, int index) {
        final _DeclaredEntry entry = _entries[index];
        final Booking? booking = entry.booking;
        return booking == null
            ? DeclaredTimeCard.free(time: entry.time)
            : DeclaredTimeCard.booked(
                time: entry.time,
                booking: booking,
                onTap: () => widget.onTapBooking(booking),
              );
      },
    );
  }
}

/// One declared time. Booked -> time / client / `service · duration`.
/// Free -> time / «Вільно» — informational only, never a button.
class DeclaredTimeCard extends StatelessWidget {
  const DeclaredTimeCard._({required this.time, this.booking, this.onTap});

  /// A declared time that carries a booking.
  factory DeclaredTimeCard.booked({
    required TimeOfDay time,
    required Booking booking,
    required VoidCallback onTap,
  }) => DeclaredTimeCard._(time: time, booking: booking, onTap: onTap);

  /// A declared time with nothing on it.
  factory DeclaredTimeCard.free({required TimeOfDay time}) =>
      DeclaredTimeCard._(time: time);

  final TimeOfDay time;
  final Booking? booking;
  final VoidCallback? onTap;

  /// The one box every card gets, booked or free, 30 minutes or 90 — a
  /// FLOOR, not a fixed size, so real content past it (a large text scale)
  /// grows the card with it. Measured naturals at textScaler 1.0 in the
  /// approved preview: booked ~122dp, free ~90dp; floored at 140 for a little
  /// clearance on both. See the preview's `declared_time_cards.dart` for the
  /// full measurement note.
  static const double _kCardMinHeight = 140;

  static const EdgeInsets _kCardPadding = EdgeInsets.all(VelvetSpacing.lg);

  /// The booked card's decoration — `MasterBookingCard`'s own recipe: base
  /// fill, card radius, the 1.5dp camel border at 0.38, and the
  /// Impeller-safe non-offset `borderedCard` lift.
  static final BoxDecoration _bookedDecoration = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.circular(VelvetRadii.card),
    border: Border.all(
      color: BrandColors.accent.withValues(alpha: 0.38),
      width: 1.5,
    ),
    boxShadow: VelvetShadows.borderedCard,
  );

  /// The free card's decoration — identical, minus the lift: same footprint,
  /// same radius, same border, it simply does not rise off the base.
  static final BoxDecoration _freeDecoration = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.circular(VelvetRadii.card),
    border: Border.all(
      color: BrandColors.accent.withValues(alpha: 0.38),
      width: 1.5,
    ),
  );

  /// Line 1 — the declared time. Shipped `VelvetText.statValue()`, mocha
  /// rather than espresso so the card's anchor reads as structure rather
  /// than competing with the client name below it.
  static final TextStyle _timeStyle = VelvetText.statValue().copyWith(
    color: BrandColors.accentDeep,
  );

  /// Line 2 — the client, when booked.
  static final TextStyle _nameStyle = VelvetText.subheading();

  /// Line 2, free variant — «Вільно» in the same slot, muted.
  static final TextStyle _freeStyle = VelvetText.subheading().copyWith(
    color: BrandColors.muted,
  );

  /// Line 3 — the service, the shipped full-layout recipe.
  static final TextStyle _serviceStyle = VelvetText.masterCardServiceFull;

  /// Line 3 — the duration half, muted so `service · duration` reads as one
  /// line with a subordinate tail.
  static final TextStyle _durationStyle = VelvetText.masterCardServiceFull
      .copyWith(color: BrandColors.muted, fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context) {
    final Booking? b = booking;
    final Widget card = Container(
      constraints: const BoxConstraints(minHeight: _kCardMinHeight),
      padding: _kCardPadding,
      decoration: b == null ? _freeDecoration : _bookedDecoration,
      child: b == null ? _buildFreeBody(context) : _buildBookedBody(context, b),
    );

    if (b == null) {
      final AppLocalizations l10n = AppLocalizations.of(context);
      return MergeSemantics(
        child: Semantics(
          key: Key(
            'declared-time-card-free-'
            '${time.hour.toString().padLeft(2, '0')}'
            '${time.minute.toString().padLeft(2, '0')}',
          ),
          label: '${formatTime(time)} — ${l10n.masterBookingsDeclaredTimeFree}',
          child: card,
        ),
      );
    }

    final AppLocalizations l10n = AppLocalizations.of(context);
    final String clientName = b.clientName ?? l10n.bookingDetailGuestClient;
    return Semantics(
      button: true,
      label: l10n.masterBookingCardSemantics(clientName, b.serviceName),
      child: GestureDetector(
        key: Key('declared-time-card-${b.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: card,
      ),
    );
  }

  Widget _buildBookedBody(BuildContext context, Booking b) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String clientName = b.clientName ?? l10n.bookingDetailGuestClient;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(formatTime(time), style: _timeStyle),
        const SizedBox(height: VelvetSpacing.sm),
        Text(
          clientName,
          style: _nameStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: VelvetSpacing.xs + 2),
        // «Манікюр · 60 хв» — the service and its DURATION, per the sketch.
        // NOT the shipped card's start–end RANGE.
        Row(
          children: <Widget>[
            Flexible(
              child: Text(
                b.serviceName,
                style: _serviceStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(' · ${b.durationLabel}', style: _durationStyle),
          ],
        ),
      ],
    );
  }

  Widget _buildFreeBody(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(formatTime(time), style: _timeStyle),
        const SizedBox(height: VelvetSpacing.sm),
        Text(l10n.masterBookingsDeclaredTimeFree, style: _freeStyle),
      ],
    );
  }
}
