// Phase 7.9 — the independent master's «Мої записи» timeline: ONE Kyiv
// calendar day's WHOLE set of bookings, in ONE request. Retires the paged
// `MasterBookingsNotifier` (Phase 7.1–7.8).
//
// A `@riverpod` autoDispose family keyed by [BookingsDayQuery], with a
// BOUNDED keepAlive cache layered on top (MEDIUM-2 — see "A BOUNDED
// `ref.keepAlive()`" below). Changing [BookingsDayQuery.day] or any filter
// builds a NEW query → a NEW family member; the previous member survives
// unwatched for as long as it stays inside that bounded cache, then is let
// go once evicted from it.
//
// ## Why the whole day, not a page
//
// A timeline cannot render page 0. `firstHour` and the grid extent (Phase
// 7.10) are `reduce`s over the ENTIRE filtered set — with page 0 only, the
// ruler's top edge would shift every time another page arrived, and cards
// would jump. Phase 7.6's approved-divergence note (see
// `master_bookings_screen.dart`'s `_BookingsList` doc) listed exactly this as
// one of three reasons the vertical list was chosen over the design's
// timeline grid; scoping to one day dissolves it.
//
// **One day is NOT provably bounded — the render stays safe for a different
// reason.** The backend enforces no minimum service duration:
// `CreateServiceDefinitionRequest.baseDurationMinutes` is only `@Positive`
// and `UpdateServiceDefinitionRequest.baseDurationMinutes` only `@Min(1)` —
// a 1-minute service is legal, so a master CAN in principle book more than
// 100 appointments into one day. `size: 100, page: 0` is fetched
// unconditionally regardless of that: safety comes from
// [BookingsDayState.isTruncated] (below) catching whatever the single page
// doesn't cover and diverting it to an explicit "day too dense" notice
// (Phase 7.11), not from any guarantee that the count fits.
//
// **Locked decision (user, 2026-07-18): single-page fetch, no multi-page
// loop.** If the day is somehow still denser than one page,
// [BookingsDayState.isTruncated] drives an explicit "day too dense" notice
// (Phase 7.11) rather than looping to page 1. Deferring the loop to the salon
// phase — where many masters can genuinely share one day and the loop earns
// its keep — avoids shipping unused machinery that rots.
//
// ## Ascending order is load-bearing (Phase 7.9, the second half of a
// deliberate two-step with 7.8)
//
// The retired `MasterBookingsNotifier` hard-coded `BookingSort.newest`
// (`startsAt,desc`) specifically so the emitted URL stayed byte-identical
// across Phase 7.8 — that constant's own doc comment named this exact
// follow-up: sorting was retired as a user-facing feature in 7.8, and 7.9
// (here) is what "changes the ordering along with the container that makes
// the new ordering correct." [BookingSort.oldest] (`startsAt,asc`) is fixed
// below, not user-chosen — bookings are not sortable at all (see
// `booking_sort.dart`) — and it matters for a reason beyond "reads top-down":
// Phase 7.10's lane-assignment algorithm walks this list ONCE, greedily
// packing each booking into the first lane whose previous occupant has
// already ended, which is only correct if the input stream already arrives
// in ascending `startsAt` order. Do NOT change this constant and do NOT
// re-sort client-side — either breaks lane assignment silently: the grid
// would still render, just with bookings placed in the wrong lanes, with no
// error anywhere.
//
// ## A BOUNDED `ref.keepAlive()` — not plain autoDispose, not unconditional
//
// The retired notifier kept a member alive for 5 (or 2, for a date-narrowed
// query) minutes so a "tap a booking, come back" round trip cost nothing.
// Phase 7.9 originally shipped this family plain-autoDispose instead, on the
// reasoning that THIS family is keyed by a single DAY, so a master scrubbing
// the rail mints one member per day visited — an UNCONDITIONAL keepAlive
// would pin one cached day per rail cell the master has ever glanced at in
// the session. That reasoning against an unconditional keepAlive still
// holds, and [_kMaxKeptDays] below is deliberately small so it cannot
// happen.
//
// But plain autoDispose went too far the other way (MEDIUM-2): it evicts a
// day the INSTANT its `Consumer` unwatches it, so even the single most
// common rail workflow this surface exists for — "today → tomorrow → today",
// a same-session comparison — pays a full round trip on every settled
// return. The 220ms debounce in `bookings_discovery_view.dart` only protects
// a *fling* across several days; it does nothing for a *settled* revisit.
//
// [DayKeepAliveLru] below is the bounded middle ground: it pins the last
// [_kMaxKeptDays] DISTINCT queries alive via `ref.keepAlive()`, evicting the
// least-recently-touched one the instant a new distinct query would exceed
// that cap. A master bouncing between a handful of adjacent days pays for
// the fetch once each; a master who scrubs the whole rail still only ever
// pins [_kMaxKeptDays] members, never one per cell visited. The tracker
// itself lives behind [dayKeepAliveLruProvider] (a `keepAlive: true`
// provider, one per `ProviderContainer`) rather than a bare top-level
// global, so two `ProviderContainer`s — e.g. two tests running in the same
// isolate — never see each other's cached links.
//
// ## Session-boundary PII (mobile-security HIGH, 2026-07-19) — the bounded
// cache survives logout unless torn down explicitly
//
// A `keepAlive()`d family member is, by construction, immune to the ONE
// mechanism that normally scrubs a session's PII on logout: the
// `ref.watch(authProvider)` cascade every other per-user cache in this
// codebase relies on (`master_profile_notifier.dart`,
// `public_master_profile_notifier.dart`, `public_salon_profile_notifier.dart`,
// `pending_service_preselection_provider.dart`,
// `favorite_toggle_notifier.dart`). [BookingsDayNotifier.build] had ZERO
// `ref.watch` calls, so a day pinned by [DayKeepAliveLru] before logout —
// the master's own previous session's client names and phone numbers — would
// still be there, still `AsyncData`, the instant the NEXT account watched the
// same [BookingsDayQuery]: no loading state, no network request, a stale
// account's PII rendered on first paint.
//
// Fixed with BOTH layers, deliberately, not one:
//   (a) [build] now `ref.watch`es the authenticated user id (see below) so an
//       auth-identity change invalidates this member through the ordinary
//       cascade, exactly like every sibling cache above.
//   (b) [AuthNotifier.logout] additionally calls [DayKeepAliveLru.clear] as a
//       deterministic sweep of THIS class's own bookkeeping, run at the exact
//       point of logout rather than left implicit — see below for why (a)
//       alone does not make (b) redundant, even though (a) alone already
//       reclaims an unwatched member's PII.
//
// **Ground truth on what (a) actually does** (verified against Riverpod
// 3.1.0's own source — `package:riverpod/src/core/element.dart` and
// `.../core/scheduler.dart`; 3.1.0 is what `pubspec.lock` pins, an earlier
// version of this note cited 3.2.1, which is not the version this app builds
// against — mobile-qa, 2026-07-19, after an earlier version of this comment described
// the wrong mechanism and an outcome-based regression test built against
// that wrong description could not be made to fail): the `authProvider
// .select` watch above triggers `invalidateSelf()` on an id change.
// `invalidateSelf()` UNCONDITIONALLY calls `runOnDispose()` — which severs
// EVERY `KeepAliveLink` this element is holding, including the one
// [DayKeepAliveLru] was handed by `ref.keepAlive()` — then unconditionally
// calls `mayNeedDispose()`, which queues the element for disposal the moment
// it finds zero links AND zero active listeners. For an UNWATCHED member
// (pinned by the LRU alone), that means (a) ALONE already queues its
// disposal in the same synchronous step that detects the identity change —
// there is no "marked dirty, rebuilt lazily on next read" gap; Riverpod's own
// scheduler (`ProviderScheduler`) drains that queue on the very next
// event-loop turn regardless of whether anything ever reads the provider
// again. For an ACTIVELY WATCHED member (a `Consumer` on screen at the
// moment of logout), `mayNeedDispose()` does NOT queue disposal — but
// `invalidateSelf()` also unconditionally queues a REFRESH, and
// `invalidateSelf()` sets `_mustRecomputeState = true` on the element. So (a)
// alone already covers BOTH cases; see `bookings_day_notifier_test.dart`'s
// "session-boundary PII" group for the regression coverage, including the
// actively-watched case.
//
// **What the queued refresh does and does NOT guarantee.** An earlier version
// of this note said the scheduler "forces `build()` to re-run". That is only
// true when the element is ACTIVE, and it is worth spelling out because the
// «Мої записи» surface routinely is not. `scheduler.dart::_performRefresh`
// reads `if (element.isActive) element.flush();` — a queued refresh for a
// NON-active element is SKIPPED — and `scheduler.dart::_task` then calls
// `stateToRefresh.clear()` UNCONDITIONALLY, so the skipped refresh is
// DROPPED, never re-queued. `element.dart`'s
// `isActive => (listenerCount - pausedActiveSubscriptionCount) > 0` is the
// catch: Riverpod 3 PAUSES the subscriptions of a covered consumer, so a day
// list sitting under a pushed full-screen route (the create-booking wizard,
// a booking detail) is watched but NOT active, and its queued refresh is
// discarded.
//
// Recovery in that case is therefore NOT scheduler-driven. It works because
// `invalidateSelf()` left `_mustRecomputeState = true`, and the next READ —
// the resumed consumer's `ref.watch` on pop-back — recomputes on the spot. A
// lifecycle probe confirmed the ordinary pop-back path does recover, so this
// is latent fragility rather than a live defect. But it means "an
// `invalidate` while the screen is covered lands on RESUME, not immediately",
// and nothing about that is guaranteed by the scheduler. Any caller that
// needs the refetch to have HAPPENED must read the provider, not merely
// invalidate it and assume — see
// `booking_calendar_invalidation.dart`'s `invalidateBookingViewsAfterBookingCreated`,
// whose call site is exactly this covered case.
//
// So what does (b) still buy, if (a) alone already reclaims the PII either
// way? `runOnDispose()` only detaches a link from the Riverpod element's own
// `Ref` — it never touches [DayKeepAliveLru]'s `_links` map. Left alone, a
// logged-out query's entry there becomes a "zombie": a [KeepAliveLink]
// object pointing at a link the element already severed, still occupying one
// of [_kMaxKeptDays] budget slots until some future [touch] for that SAME
// query happens to overwrite it. (b) is the deterministic sweep that clears
// that bookkeeping at logout instead of trusting a hypothetical future touch
// to paper over it — genuine defence-in-depth against the LRU's own budget
// silently wasting slots on already-dead entries, not a second, independent
// path to reclaiming the cached PII itself.
//
// [build] deliberately watches ONLY the authenticated user's id — via
// `authProvider.select(...)` — rather than the whole
// `AsyncValue<AuthSession>`. `RefreshInterceptor` calls
// `AuthNotifier.setAccessToken` on every silent token refresh, which emits a
// NEW `AuthSession.authenticated` with the SAME `user` but a different
// `accessToken`; watching the full session would treat that as "the identity
// changed" and refetch the whole day on every silent refresh — quietly
// defeating the bounded-keepAlive cache this file exists to add. Selecting
// just the id makes a token refresh a no-op for this family (same id, same
// `==`, no rebuild) while a real logout (id → null) or a different account
// logging in (id → a different id) still rebuilds.
//
// ## The day token is a KYIV calendar day
//
// This notifier does not itself convert anything to Kyiv time — it trusts
// [BookingsDayQuery.day] to already be one (Phase 7.11 derives the initial
// day as `dateOnly(toBeauticaTime(DateTime.now()))`). It forwards [day]
// straight through as BOTH `from` and `to` to
// [BookingRepository.getMyBookings], which the backend interprets as
// `LocalDate` in `Europe/Kyiv` — see `shared/formatters/api_date.dart`'s
// header for why this repository call never `.toUtc()`s a bound.

import 'dart:collection';
import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
// `KeepAliveLink` is not part of `riverpod_annotation`'s show-list — it lives
// on the dedicated advanced-API surface, `misc.dart` (mirrors
// `package:riverpod/misc.dart`; imported via `flutter_riverpod`, an existing
// direct dependency, rather than adding `riverpod` itself as one).
import 'package:flutter_riverpod/misc.dart';
// `ProviderListenable.select` (used below to narrow the `authProvider` watch
// to the identity-bearing slice — mobile-security HIGH, 2026-07-19) is not
// part of `riverpod_annotation`'s show-list either; every other caller of
// `authProvider.select(...)` in this codebase
// (`search_filters_controller.dart`, `verification_screen.dart`) reaches it
// through the full `flutter_riverpod` package for the same reason.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/network/page_response.dart';

import '../../auth/domain/auth_session.dart';
import '../../auth/domain/user.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../data/booking_providers.dart';
import '../data/booking_repository.dart';
import '../domain/booking.dart';
import '../domain/booking_sort.dart';
import '../domain/bookings_day_query.dart';
import '../domain/bookings_day_state.dart';

part 'bookings_day_notifier.g.dart';

const String _tag = 'feature.booking.bookings_day';

/// How many DISTINCT [BookingsDayQuery] family members [DayKeepAliveLru]
/// pins simultaneously. 3 covers the realistic rail workflow — "today →
/// tomorrow → today", or "today → yesterday → today" — with a slot of slack,
/// without pinning one cached day per rail cell the master has ever glanced
/// at in the session (see the file header's keepAlive section).
///
/// Trade-off, documented rather than fixed (mobile-security LOW, 2026-07-19):
/// the LRU is keyed on the FULL [BookingsDayQuery] — [BookingsDayQuery.day]
/// AND its filters together, per [DayKeepAliveLru]'s `touch` — not on `day`
/// alone. Three filter changes while parked on "today" mint three DISTINCT
/// family members and can therefore evict a genuinely rail-visited
/// "yesterday" out of the window, even though the "today → tomorrow → today"
/// workflow this budget is sized for never touched a second `day` value.
/// Accepted as-is: the worst case is one extra network round trip on the next
/// revisit — no wrong data, no leak, and [BookingsDayState.isTruncated] /
/// the single-fetch guarantee (file header) are unaffected either way.
/// Re-weighting eviction to key on `day` first (a two-level LRU, or a
/// composite key with day-then-filter tie-breaking) would close the gap but
/// is real added complexity for a cosmetic worst case — revisit only if
/// usage data shows filter-churn evictions happening in practice.
const int _kMaxKeptDays = 3;

/// A small LRU set of `KeepAliveLink`s, one per recently-touched
/// [BookingsDayQuery] — the bounded middle ground between a blanket
/// `ref.keepAlive()` (unbounded — rejected, see the file header) and plain
/// autoDispose (evicts on every unwatch — MEDIUM-2). [touch] is called from
/// every [BookingsDayNotifier.build]; touching an already-tracked query
/// replaces its link (rather than accumulating a duplicate one, which a
/// retry-triggered rebuild of the SAME query would otherwise do) and marks
/// it most-recently-used.
///
/// Deliberately NOT a bare top-level global: it is read through
/// [dayKeepAliveLruProvider], so its lifetime is scoped to one
/// `ProviderContainer` — two containers (e.g. two tests in the same
/// isolate) each get their own tracker and never see one another's links.
///
/// Both the class and the provider are public (not `_DayKeepAliveLru` /
/// `_dayKeepAliveLruProvider`, as originally shipped) SOLELY so
/// [AuthNotifier.logout] can reach [clear] — see the file header's
/// "Session-boundary PII" section for why an explicit sweep at logout is
/// needed in addition to [BookingsDayNotifier.build]'s `authProvider` watch.
/// Only [touch] and [clear] are meant to be called from outside this file;
/// every other file should keep reaching this exclusively through
/// [dayKeepAliveLruProvider], never by constructing one directly.
class DayKeepAliveLru {
  final LinkedHashMap<BookingsDayQuery, KeepAliveLink> _links =
      LinkedHashMap<BookingsDayQuery, KeepAliveLink>();

  void touch(BookingsDayQuery query, KeepAliveLink link) {
    // A rebuild of a query already tracked (e.g. the error state's «retry»
    // invalidating the SAME query) replaces the link instead of leaking a
    // second one for it.
    _links.remove(query)?.close();
    _links[query] = link;
    // `LinkedHashMap` iterates in insertion order, so the first key is the
    // least-recently-touched one once every touch above re-inserts at the
    // end.
    while (_links.length > _kMaxKeptDays) {
      _links.remove(_links.keys.first)?.close();
    }
  }

  /// Closes every held [KeepAliveLink] and forgets all tracked queries.
  ///
  /// Called from [AuthNotifier.logout] (mobile-security HIGH, 2026-07-19) as
  /// a deterministic sweep of THIS class's own bookkeeping — see the file
  /// header's "Session-boundary PII" section for the full reasoning,
  /// verified against Riverpod's own disposal internals. It is NOT what
  /// reclaims an unwatched member's cached PII: [BookingsDayNotifier.build]'s
  /// `authProvider` watch already does that on its own, for both the watched
  /// and unwatched case, the moment the identity changes (`invalidateSelf()`
  /// unconditionally severs every `KeepAliveLink` an element holds and queues
  /// either its disposal or a rebuild — never left lazily pending on a future
  /// read). What [clear] actually prevents is [_links] here accumulating
  /// "zombie" entries: `runOnDispose()` detaches a link from the Riverpod
  /// element's `Ref`, never from this map, so without this sweep a
  /// logged-out query's slot would keep pointing at an already-severed link —
  /// silently wasting one of [_kMaxKeptDays] budget slots — until a future
  /// [touch] for that same query happens to overwrite it.
  void clear() {
    for (final KeepAliveLink link in _links.values) {
      link.close();
    }
    _links.clear();
  }
}

/// Container-scoped home for [DayKeepAliveLru] — see that class's doc for
/// why this must be a provider rather than a top-level global. `keepAlive:
/// true` because the TRACKER is meant to outlive any single day it tracks
/// (it is the thing doing the pinning); it still dies with its
/// `ProviderContainer`, same as every other provider.
@Riverpod(keepAlive: true)
DayKeepAliveLru dayKeepAliveLru(Ref ref) => DayKeepAliveLru();

/// One Kyiv calendar day's bookings for one [BookingsDayQuery].
///
/// Generated provider name: `bookingsDayProvider` (a family — call
/// `bookingsDayProvider(query)`).
@riverpod
class BookingsDayNotifier extends _$BookingsDayNotifier {
  @override
  Future<BookingsDayState> build(BookingsDayQuery query) async {
    // Security (mobile-security HIGH, 2026-07-19) — see the file header's
    // "Session-boundary PII" section. Ties this family member's lifetime to
    // the AUTHENTICATED IDENTITY, not just to its listeners: a logout (id →
    // null) or a different account logging in (id → a different id) rebuilds
    // this member through the ordinary Riverpod cascade instead of leaving a
    // `keepAlive()`d member serving a previous account's cached booking PII.
    // Selecting ONLY the user id — never the whole `AsyncValue<AuthSession>`
    // — is deliberate: a silent token refresh (`AuthNotifier.setAccessToken`)
    // emits a new session with the SAME id, so it does not rebuild this
    // provider and does not defeat the bounded keepAlive cache below.
    ref.watch(
      authProvider.select(
        (AsyncValue<AuthSession> session) => switch (session.value) {
          Authenticated(:final User user) => user.id,
          Unauthenticated() || null => null,
        },
      ),
    );

    // Bounded keepAlive (MEDIUM-2) — see the file header. Registered before
    // the fetch so a query that ultimately errors is still tracked; an
    // errored member is cheap to keep and its own «retry» affordance
    // (`ref.invalidate`) re-touches the SAME query rather than minting a new
    // one.
    ref.read(dayKeepAliveLruProvider).touch(query, ref.keepAlive());

    // mobile-perf MEDIUM-3 (2026-07-20) — cancel this member's OWN in-flight
    // request when the member itself is torn down (evicted from the bounded
    // LRU, or superseded by a rebuild), mirroring `WorkingDaysNotifier.build`.
    // Disposing a Riverpod element stops the RESULT from landing but does not
    // by itself abort the underlying Dio request — without this, scrubbing
    // the day rail past the 220ms debounce on a slow connection left
    // abandoned `GET /bookings/me` requests running to completion for every
    // day flicked past.
    final CancelToken cancelToken = CancelToken();
    ref.onDispose(() => cancelToken.cancel());

    // `async` + `await` is deliberate, not a redundant wrapper around a
    // passthrough return. It guarantees that a SYNCHRONOUS throw from the
    // repository call is captured as a rejected Future instead of escaping
    // `build()` itself — an escaped sync throw leaves the provider stuck in
    // its loading state and surfaces as a StateError on disposal rather than
    // as the repository's own typed Failure. Same reasoning as
    // `WorkingDaysNotifier.build` / the retired `MasterBookingsNotifier
    // .build`.
    return await _fetchDay(query, cancelToken);
  }

  /// Fetches [query]'s WHOLE day in ONE request — see the file header for
  /// why this can never need a second one in practice, and why no loop is
  /// written to handle it if it somehow does.
  Future<BookingsDayState> _fetchDay(
    BookingsDayQuery query,
    CancelToken cancelToken,
  ) async {
    final BookingRepository repo = ref.read(bookingRepositoryProvider);
    final PageResponse<Booking> page = await repo.getMyBookings(
      statuses: query.statuses,
      serviceIds: query.serviceIds,
      from: query.day,
      to: query.day,
      // Fixed, not user-chosen — see the file header on why ascending order
      // is load-bearing for Phase 7.10's lane assignment.
      sort: BookingSort.oldest,
      page: 0,
      size: 100,
      cancelToken: cancelToken,
    );

    // The server reported more matches than this single page returned — the
    // "day too dense" case the locked single-fetch decision explicitly
    // accepted rather than looping for. No second request is issued.
    final bool isTruncated = page.totalElements > page.items.length;
    if (isTruncated && kDebugMode) {
      log(
        'Day ${query.day} reports ${page.totalElements} bookings but only '
        '${page.items.length} were returned in one page — surfacing '
        'isTruncated instead of fetching page 1 (locked decision, '
        '2026-07-18).',
        name: _tag,
        level: 900,
      );
    }

    return BookingsDayState(
      items: page.items,
      totalElements: page.totalElements,
      isTruncated: isTruncated,
    );
  }
}
