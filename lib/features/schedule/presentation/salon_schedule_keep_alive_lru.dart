// The BOUNDED member budget for `salonEffectiveScheduleProvider`
// (mobile-perf LOW, filed 2026-09-17, shipped 2026-09-20).
//
// ## What this closes
//
// `SalonEffectiveScheduleNotifier.build` pins every SUCCESSFUL fetch with
// `ref.keepAlive()` for a 5-minute TTL. That pin is what defeats autoDispose,
// so nothing evicts a pinned member early — and the whole safety argument for
// having no budget at all rested on there only ever BEING one member per
// salon per session: the board's single watch site passes
// `ScheduleRange.month(kyivToday(clock))`, TODAY's month, not the SELECTED
// day's (measured: 1 fetch across 21 day taps and 6 week pages, 2026-09-17).
//
// That precondition is one named follow-up away from being false. Re-keying
// the family on the selected month — the additive `onDayChanged` seam
// `salon_bookings_screen.dart` describes — turns one member into one PER
// MONTH REACHED: the rail spans ±180 days, so ~12 concurrent members, each
// pinned five minutes with nothing evicting them, ~3,700 live `EffectiveDay`
// objects at a roster of 10.
//
// The old mitigation was a boxed REQUIREMENT comment asking the next author to
// ship a budget in the same change. That is a guard made of attention. This
// file is the budget, shipped AHEAD of the re-key, so the hazard is closed by
// construction instead: at today's one-member-per-salon key it evicts nothing
// and changes no behaviour whatsoever, and the day the key widens it is
// already there.
//
// ## Why not `DayKeepAliveLru`
//
// `bookings_day_notifier.dart`'s LRU is the model this is built on — same
// `LinkedHashMap` insertion-order-as-recency trick, same replace-on-touch rule
// — but it is not reusable here, on two counts. It is keyed concretely to
// `BookingsDayQuery`, and it carries a `markWatched`/`isWatched` reference
// count plus a `liveQueries` enumeration that exist ONLY for
// `booking_calendar_invalidation.dart`'s pinned-but-unwatched fan-out, which
// has no analogue on this family (nothing invalidates it per member). More
// decisively, it lives in `features/booking/application/`, and a
// `features/schedule/` import of it would be a cross-feature reach into
// another feature's application layer — which the layer table forbids.
// Generifying it into `shared/` would mean rewriting a class whose ~150 lines
// of doc encode several empirically-probed Riverpod behaviours, to no benefit
// for either caller. What IS shared is the shape, and this file states where
// it came from.

import 'dart:async';
import 'dart:collection';

// `KeepAliveLink` is not part of `riverpod_annotation`'s show-list — it lives
// on the dedicated advanced-API surface, `misc.dart` (mirrors
// `package:riverpod/misc.dart`; imported via `flutter_riverpod`, an existing
// direct dependency, rather than adding `riverpod` itself as one). Same
// reasoning, same spelling, as `bookings_day_notifier.dart`'s own import.
import 'package:flutter_riverpod/misc.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'schedule_range.dart';

part 'salon_schedule_keep_alive_lru.g.dart';

/// The family key this budget counts — the same `(salonId, range)` pair
/// `salonEffectiveScheduleProvider` is keyed by. A Dart record, so its
/// equality is structural over a `String` and a freezed [ScheduleRange], which
/// is exactly the family's own key equality.
typedef SalonScheduleKey = (String salonId, ScheduleRange range);

/// How many `(salonId, range)` windows may hold a keepAlive pin at once.
///
/// Three, mirroring `bookings_day_notifier.dart`'s `_kMaxKeptDays` and chosen
/// for the same reason: it is the smallest budget that still serves the motion
/// a user actually makes — page back a month, page forward again, land where
/// they started — without holding an unbounded tail of months they walked past
/// once. TODAY it is never reached (the board keys on Kyiv-today's month, so
/// exactly one member exists per salon), which is precisely why shipping it
/// now is free.
const int kMaxKeptSalonScheduleRanges = 3;

/// One pinned window: the [KeepAliveLink] holding it in memory and the [Timer]
/// that releases it when the TTL lapses.
final class _Pin {
  _Pin(this.link, this.timer);

  final KeepAliveLink link;
  final Timer timer;
}

/// A small LRU of [KeepAliveLink]s, one per recently-built
/// `salonEffectiveScheduleProvider` window.
///
/// Reached through [salonScheduleKeepAliveLruProvider] rather than as a
/// top-level global, so its lifetime is scoped to ONE `ProviderContainer` —
/// two containers (two tests in the same isolate, say) never see one another's
/// pins.
class SalonScheduleKeepAliveLru {
  /// Insertion order IS recency: [touch] removes before it re-inserts, so the
  /// map's first key is always the least-recently-touched window.
  final LinkedHashMap<SalonScheduleKey, _Pin> _pins =
      LinkedHashMap<SalonScheduleKey, _Pin>();

  /// Windows currently holding one of the [kMaxKeptSalonScheduleRanges] slots.
  /// Snapshotted, not a live view — callers iterate it while releasing.
  List<SalonScheduleKey> get pinnedKeys => _pins.keys.toList(growable: false);

  /// Registers [link] as [key]'s pin for [ttl], evicting the
  /// least-recently-touched window if that puts the budget over.
  ///
  /// Touching an ALREADY-pinned key replaces its pin rather than accumulating
  /// a second one (a retry-triggered rebuild of the same key would otherwise
  /// leave an orphaned link and an orphaned timer) and marks it
  /// most-recently-used.
  void touch(SalonScheduleKey key, KeepAliveLink link, Duration ttl) {
    _closeAndRemove(key);
    _pins[key] = _Pin(link, Timer(ttl, () => _closeAndRemove(key)));
    while (_pins.length > kMaxKeptSalonScheduleRanges) {
      _closeAndRemove(_pins.keys.first);
    }
  }

  /// Forgets [key] WITHOUT closing its link — for the element's own
  /// `ref.onDispose`.
  ///
  /// The distinction matters: by the time an element disposes, its keepAlive
  /// links are already gone, and calling [KeepAliveLink.close] against a
  /// disposed element is not a no-op contract this file is willing to lean on.
  /// The timer still has to be cancelled, or a superseded build leaves a
  /// pending callback that would evict whatever took its key.
  void forget(SalonScheduleKey key) {
    _pins.remove(key)?.timer.cancel();
  }

  /// Releases every pin — called at the session boundary by
  /// [AuthNotifier.logout], alongside the bare family invalidate it already
  /// performs, so an outgoing session's roster hours are not held in memory
  /// behind a pin the invalidate cannot reach.
  void clear() {
    for (final SalonScheduleKey key in pinnedKeys) {
      _closeAndRemove(key);
    }
  }

  void _closeAndRemove(SalonScheduleKey key) {
    final _Pin? pin = _pins.remove(key);
    if (pin == null) return;
    pin.timer.cancel();
    pin.link.close();
  }
}

/// Container-scoped holder for [SalonScheduleKeepAliveLru]. `keepAlive: true`
/// — the budget must outlive any one window, or it could not bound them.
@Riverpod(keepAlive: true)
SalonScheduleKeepAliveLru salonScheduleKeepAliveLru(Ref ref) =>
    SalonScheduleKeepAliveLru();
