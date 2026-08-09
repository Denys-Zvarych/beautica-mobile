// Phase 7.1 — the day-rail's dot set: which days the master has bookings on.
//
// One unpaged call to `GET /bookings/me/booked-days` (backend Phase 26.5)
// covering today ± [kBookedDaysSpanDays].
//
// ## Filter-independent BY DESIGN — do not key this on the query
//
// This provider deliberately takes NO [MasterBookingsQuery] and must never be
// widened into a family keyed by one. The design computes the rail's dots from
// ALL of the master's bookings, not from the filtered list: the rail is a
// navigation affordance ("where in time is my work?"), not a mirror of the
// list below it. Keying it on the filter would make the dots evaporate as the
// user narrows — so the rail would stop showing them the days they'd need to
// clear the filter to reach, which is precisely when it is most useful.
//
// The backend agrees and enforces it: `/me/booked-days` exposes no status or
// serviceId param at all.
//
// Invalidate this after any action that changes a booking's EXISTENCE
// (Phase 7.3 cancel / no-show); a mere status change does not move a dot.
//
// ## Session-boundary PII (mobile-security HIGH, 2026-07-20) — mirrors
// `bookings_day_notifier.dart`'s fix line-for-line
//
// This is a `keepAlive()` singleton with a 30-minute TTL and, before this
// fix, ZERO `ref.watch` calls — exactly the shape `BookingsDayNotifier.build`
// had before its own mobile-security HIGH fix (2026-07-19). On a shared
// device: Master A opens «Мої записи», logs out within the 30-minute TTL;
// Master B logs in and the rail renders A's booked-day dots on first paint —
// no loading state, no refetch, because a `keepAlive()`d provider is immune
// to the `ref.watch(authProvider)` cascade every other per-user cache in this
// codebase relies on to self-clear on logout.
//
// Fixed with [build] now `ref.watch`ing the authenticated user's id (below) —
// see `bookings_day_notifier.dart`'s file header ("Session-boundary PII",
// verified against Riverpod 3.2.1's own disposal internals) for the full
// reasoning behind why this ALONE is sufficient for BOTH the actively
// watched and the unwatched case: `invalidateSelf()` unconditionally severs
// every `KeepAliveLink` an element holds — including the one this provider's
// own `ref.keepAlive()` call below returns — then queues either disposal (no
// active listener) or a rebuild (an active one) for the very next event-loop
// turn.
//
// Deliberately narrowed to `.select((s) => ...id)`, never the whole
// `AsyncValue<AuthSession>`: a silent token refresh
// (`AuthNotifier.setAccessToken`) emits a new session with the SAME id, and
// watching the full session would treat that as an identity change and
// refetch the whole ±180-day sweep on every silent refresh — quietly
// defeating the 30-minute TTL this file exists to add.
//
// Unlike `bookingsDayProvider`, this provider is NOT a family with an
// external LRU bookkeeping map, so there is no second, `AuthNotifier.logout`-
// side sweep to add: the `keepAlive()` link lives entirely inside THIS
// provider's own Riverpod element, and the watch above is what reclaims it.
// A deliberate `ref.invalidate(bookedDaysProvider)` call from inside
// `AuthNotifier.logout` was considered and rejected — `logout` itself already
// documents why calling `ref.invalidate` on a provider that transitively
// `ref.watch`es `authProvider`, from INSIDE that same auth notifier's own
// state transition, records a back-edge Riverpod's `CircularDependencyError`
// assert (debug/test only) rejects; the watch below reaches the exact same
// outcome through the ordinary cascade instead.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

import '../../auth/domain/auth_session.dart';
import '../../auth/domain/user.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../data/booking_providers.dart';

part 'booked_days_notifier.g.dart';

/// Half-width of the rail's window, in days — the design's `_railSpan`.
///
/// The resulting inclusive span is `2 * 180 + 1 = 361` days, deliberately
/// under the backend's 366-day range cap with room to spare. Widening this to
/// 183 would produce 367 days and a hard 400 from the endpoint, so the
/// arithmetic — not just the constant — is what must stay under the cap.
const int kBookedDaysSpanDays = 180;

/// The set of local, date-only days on which the master has at least one
/// booking, across today ± [kBookedDaysSpanDays].
///
/// Returns a `Set` because the only consumer question is membership ("does
/// this rail cell get a dot?"), which must stay O(1) — the rail rebuilds this
/// lookup for every visible cell on every scroll frame.
///
/// Generated provider name: `bookedDaysProvider`.
@riverpod
Future<Set<DateTime>> bookedDays(Ref ref) async {
  // Security (mobile-security HIGH, 2026-07-20) — see the file header's
  // "Session-boundary PII" section. Ties this singleton's lifetime to the
  // AUTHENTICATED IDENTITY, not just to its listeners, exactly like
  // `BookingsDayNotifier.build`'s identical watch.
  ref.watch(
    authProvider.select(
      (AsyncValue<AuthSession> session) => switch (session.value) {
        Authenticated(:final User user) => user.id,
        Unauthenticated() || null => null,
      },
    ),
  );

  // Survive navigation for 30 minutes (perf P3). This is the single heaviest
  // request in the feature — a full ±180-day sweep — and plain autoDispose
  // re-issued it on every entry to «Мої записи» AND every return from a
  // detail screen.
  //
  // 30 minutes rather than the list's 5 because the dots are a navigational
  // HINT, not a correctness gate (nothing is authorised off them), so staleness
  // is cheap here. It is not free, though: the window below is computed from
  // Kyiv "today" at build time, so a cached instance held across Kyiv
  // midnight describes a window one day behind. The TTL is what bounds that
  // drift — 30 minutes of a one-day-shifted ±180-day window moves no dot the
  // user can see, whereas an unconditional keepAlive would let it persist for
  // the whole session. Any action that changes a booking's EXISTENCE should
  // still invalidate this explicitly (see the file header).
  final link = ref.keepAlive();
  final Timer timer = Timer(const Duration(minutes: 30), link.close);
  ref.onDispose(timer.cancel);

  // Abort the in-flight sweep when this element goes away (mobile-perf LOW,
  // 2026-07-22). Disposal alone stops the RESULT from landing but leaves the
  // request itself running — and this is the feature's heaviest call (a full
  // ±180-day range). A logout (the `authProvider` watch above severs the
  // keepAlive link and disposes this element) or a screen pop now cancels it
  // outright, mirroring `BookingsDayNotifier`'s own token.
  final CancelToken cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);

  // Recomputed on every build — never hoisted to a field or a top-level final,
  // which would pin "today" to first-use for the process's lifetime.
  //
  // KYIV-ANCHORED (backlog :226's clockProvider half): the backend interprets
  // `from`/`to` as Kyiv civil days (`atStartOfDay(TimeZones.KYIV)` throughout
  // `BookingService`), so "today" here must be the KYIV day the device's
  // current instant falls on, not the device's own calendar day — see
  // `shared/time/kyiv_day.dart`'s file header for why those two silently
  // diverge near midnight for a device outside Europe/Kyiv. `ref.read`, not
  // `ref.watch`: this is a one-shot read inside a provider body (mirrors the
  // notifier-action convention in `clock_provider.dart:28`), and `clockProvider`
  // is `keepAlive`, so a `watch` here would add a dependency edge that never
  // fires.
  final DateTime today = kyivToday(ref.read(clockProvider));
  // CALENDAR arithmetic, not `Duration(days: n)`. `DateTime.add`/`subtract`
  // add absolute 24h blocks, so crossing a Europe/Kyiv DST transition lands on
  // 23:00 or 01:00 — and `toApiDate`, which reads local `.day` verbatim, would
  // then send a bound one day off twice a year. `DateTime(y, m, d ± n)`
  // normalises out-of-range day components against the calendar and always
  // yields local midnight.
  final DateTime from = DateTime(
    today.year,
    today.month,
    today.day - kBookedDaysSpanDays,
  );
  final DateTime to = DateTime(
    today.year,
    today.month,
    today.day + kBookedDaysSpanDays,
  );

  final List<DateTime> days = await ref
      .read(bookingRepositoryProvider)
      .getMyBookedDays(from: from, to: to, cancelToken: cancelToken);

  // The repository already returns date-only locals; `dateOnly` again is a
  // cheap idempotent guard so a membership test can never miss on a stray
  // time component.
  return days.map(dateOnly).toSet();
}
