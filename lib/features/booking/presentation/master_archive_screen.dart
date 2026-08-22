// Phase 231 — the master «Архів» page: a paginated, filterable list of the
// master's PAST bookings, from which a not-yet-closed visit can be closed in
// place.
//
// Reached from a header button `BookingsDiscoveryView` grew for this phase
// (`onOpenArchive`, wired only by `master_bookings_screen.dart`). Pushed as a
// CHILD of `/master/bookings` (`RouteNames.masterBookingsArchive`), so it
// inherits that prefix's role gate in `auth_redirect.dart` — see
// `RouteNames.masterBookingsArchive`'s doc for why no `/master/*` role
// widening happened in this phase (verified against the shipped @authz
// behaviour, not assumed — see this file's ROLE GATING section below).
//
// ## Composition — reused, and FIXED IN PLACE, not forked or wrapped
//
// The list row is `MasterBookingCard` (`widgets/master_booking_card.dart`)
// pinned to its FULL layout via `minHeight: MasterBookingCard
// .fullLayoutMinHeight` — the archive is a plain list, not a
// duration-proportional timeline, so there is no reason to let a booking's
// own `durationMinutes` pick a denser layout here.
//
// The «Виконано» close action is an ADDITIVE, optional slot ON the card
// itself (`MasterBookingCard.onComplete`/`.completing`), not a wrapper
// composed around it and not a forked near-duplicate widget (user-locked
// decision, 2026-08-16: "reuse widgets that already exist... if one widget
// should be fixed, all other pages that used this widget will have the fix
// as well"). The same day, the «Відгук» leave-client-feedback action was
// added as a SECOND additive slot on the same card
// (`MasterBookingCard.onReview`), pushing the already-shipped
// `LeaveClientFeedbackScreen` (Track 7.x Wave B) for a reviewable row. As of
// 2026-08-18 that slot is gated on `booking.status == BookingStatus.completed`
// AND `booking.providerCanReviewClient` — NOT the flag alone. A brief window
// (2026-08-17 through 2026-08-18) dropped the status term on the theory that
// the server's `isReviewEligible` predicate already covered it; that was
// wrong for this direction, because it let an elapsed-but-unclosed CONFIRMED
// row (ticking «Підтверджено» alone, the archive's «Потребують закриття»
// filter) offer the «Відгук» CTA stacked next to «Виконано» — the master
// could rate the client before ever closing the booking. The provider is the
// party who performs that closing action, so the rating is meant to follow
// it, not precede it; the client has no equivalent control over the
// booking's lifecycle, which is why the client→provider review path keeps
// its own elapsed-time allowance and is unaffected. The backend's
// provider-side predicate was narrowed to COMPLETED-only to match — see
// `MasterBookingCard.onReview`'s doc for the full gate contract, including
// why mobile re-derives it locally instead of trusting the flag alone. Every
// OTHER consumer of the card (`bookings_timeline_grid.dart`,
// `declared_time_cards.dart`) never passes `onComplete` or `onReview`, so it
// renders byte-identically to before either phase — see those fields' own
// docs on `MasterBookingCard` for the full "additive, not disruptive"
// contract and why nesting a real `GestureDetector`-based button inside the
// card's own tap region is safe (Flutter's gesture arena resolves to the
// innermost recognizer; empirically verified while authoring the «Виконано»
// slot — see the handoff notes for the throwaway probe test that confirmed
// it before that shipped).
//
// The filter sheet is the SAME `BookingsFilterSheet`
// (`widgets/bookings_filter_sheet.dart`) «Мої записи» already opens — no
// bespoke chip row. Its three rows (`BookingStatusFilterGroup`:
// confirmed/completed/cancelled) are reused verbatim; ticking «Підтверджено»
// alone IS the «Потребують закриття» filter with NO new UI — see
// `master_archive_notifier.dart`'s file header for exactly why that holds.
//
// The close confirmation is the SAME `CompleteBookingDialog`
// (`widgets/complete_booking_dialog.dart`) the booking-detail screen uses —
// no note field, no new dialog (Phase 231 amendment A1/A4, superseding the
// original 2026-08-02 phase doc's now-retired «Не відбувся» plan — nothing
// in the app can set `NOT_COMPLETED`, see `booking_status.dart:174`).
//
// ## ROLE GATING — verified, not assumed
//
// `auth_redirect.dart`'s `/master/*` prefix gate admits INDEPENDENT_MASTER
// ONLY today (its own comment: "SALON_MASTER has a read-only calendar but
// that surface is under /calendar, not /master — so no /master/* role is
// carved out for it"). This screen lives under that same prefix, so
// SALON_OWNER/SALON_ADMIN/SALON_MASTER cannot reach it in this build,
// regardless of backend authorization on the write endpoints. Separately,
// the backend's own `@PreAuthorize` on `PATCH /bookings/{id}/complete`
// (`BookingController`, beautica-backend) admits `SALON_OWNER, SALON_ADMIN,
// INDEPENDENT_MASTER` — notably NOT `SALON_MASTER`. Widening `/master/*` to
// the other provider roles is therefore a separate, larger decision (it
// would need per-role write gating on this screen too, since SALON_MASTER
// could reach the UI but would 403 on the write) — out of scope here; see
// this phase's handoff notes. Pinned by
// `test/routing/master_bookings_route_guard_test.dart`.
//
// SEC: renders client names + service/price PII, same surface class as
// `master_bookings_screen.dart`'s day timeline — acquires the app-wide
// `ScreenProtectionManager` for its own lifetime, mirroring every other PII
// screen in this feature.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

import '../application/booking_calendar_invalidation.dart';
import '../application/booking_detail_notifier.dart';
import '../application/client_review_signal_provider.dart';
import '../application/master_archive_dialog_visible_notifier.dart';
import '../application/master_archive_in_flight_notifier.dart';
import '../application/master_archive_notifier.dart';
import '../data/booking_providers.dart';
import '../domain/booking.dart';
import '../domain/booking_status.dart';
import '../domain/master_archive_query.dart';
import 'leave_client_feedback_screen.dart' show ClientReviewEntry;
import 'widgets/archive_day_groups.dart';
import 'widgets/bookings_filter_sheet.dart';
import 'widgets/complete_booking_dialog.dart';
import 'widgets/master_booking_card.dart';
import 'widgets/my_bookings_states.dart';

const String _tag = 'feature.booking.masterArchive';

/// Test-only observability for
/// `_MasterArchiveScreenState._groupedEntries`'s identity memo — counts real
/// (cache-MISS) calls into `groupArchiveByKyivDay` so a test can assert the
/// memo actually SKIPS the O(n) regroup on a rebuild that doesn't change
/// `state.items`'s identity, rather than asserting on the grouped output
/// (which would look identical with or without the memo, since the function
/// is pure — see `master_archive_screen_test.dart`'s memoization group).
/// Mirrors `time_zones.dart`'s `@visibleForTesting` debug-hook precedent; an
/// int increment is negligible cost so this stays live in every build
/// config rather than needing a `kReleaseMode` no-op branch.
@visibleForTesting
int debugGroupArchiveByKyivDayCallCount = 0;

/// Resets [debugGroupArchiveByKyivDayCallCount] to 0 — call at the top of
/// each test that asserts on it, since the counter is process-global and
/// otherwise carries over between tests in the same run.
@visibleForTesting
void debugResetGroupArchiveByKyivDayCallCount() {
  debugGroupArchiveByKyivDayCallCount = 0;
}

/// The master's «Архів» page. See file header.
class MasterArchiveScreen extends ConsumerStatefulWidget {
  const MasterArchiveScreen({super.key});

  @override
  ConsumerState<MasterArchiveScreen> createState() =>
      _MasterArchiveScreenState();
}

class _MasterArchiveScreenState extends ConsumerState<MasterArchiveScreen> {
  /// Pixels-from-bottom threshold that triggers the next-page fetch —
  /// mirrors `my_bookings_screen.dart`'s identical constant.
  static const double _loadMoreThreshold = 320;

  final ScrollController _scrollController = ScrollController();

  /// The master's RAW filter-sheet selection — empty until they tick a
  /// group. See `master_archive_notifier.dart`'s file header for how this is
  /// resolved into a wire/predicate set; this screen only ever holds the raw
  /// selection, never a resolved one (mirrors
  /// `_BookingsDiscoveryViewState._statuses`).
  Set<BookingStatus> _statuses = const <BookingStatus>{};
  Set<String> _serviceIds = const <String>{};

  // Cheap scroll-listener guards, refreshed from the watched provider each
  // build — mirrors `my_bookings_screen.dart`'s identical idiom.
  bool _hasMore = false;
  bool _isLoadingMore = false;

  /// mobile-perf HIGH-1/2 fix — number of consecutive AUTOMATIC continuation
  /// fetches fired from the `state.items.isEmpty && state.hasMore` branch
  /// below (a fetched page contained zero rows matching the active
  /// client-side status filter — see `master_archive_notifier.dart`'s
  /// "Pagination interacts with client-side filtering" header for why that
  /// is a legitimate, expected outcome and not an error).
  ///
  /// Bounded at [_kMaxAutoContinueAttempts] rather than left unbounded for
  /// two independent reasons:
  ///   * ANTI-SPIN: `loadMore()` swallows its own failures
  ///     (`master_archive_notifier.dart:294-298`) and, on a failure, leaves
  ///     `page`/`hasMore`/`items` exactly as they were — so a persistently
  ///     failing fetch reproduces `items.isEmpty && hasMore == true` on every
  ///     subsequent build with nothing to distinguish it from genuine
  ///     progress. An unbounded "reschedule whenever this branch renders"
  ///     callback would retry that same failing request every frame,
  ///     hammering the network with no backoff. The cap turns that into a
  ///     bounded number of retries before surfacing a manual affordance
  ///     instead.
  ///   * UX: a heavily-filtered view can legitimately need many raw pages
  ///     before a match surfaces (or the server exhausts) — see the notifier
  ///     header's "several `loadMore` calls before the visible list visibly
  ///     grows" note. An indefinite auto-spinner over an unknown, possibly
  ///     large number of pages with no way to cancel is its own UX problem.
  ///     Capping the AUTOMATIC part and handing control back to the master
  ///     via an explicit "load more" tap (which also resets this counter,
  ///     re-arming another bounded burst) keeps every individual wait short
  ///     and visible progress opt-in beyond that.
  ///
  /// Reset to 0 whenever a page actually surfaces a match (`state.items`
  /// becomes non-empty — see the `data:` branch), when the filter selection
  /// changes ([_applyFilters]), and on [_refresh] (both start a fresh page
  /// 0 with a clean budget).
  int _autoContinueAttempts = 0;

  /// See [_autoContinueAttempts]'s doc. Three raw pages is enough to smooth
  /// over the common case (a filter that happens to miss the first page or
  /// two) without turning a genuinely sparse/failing filter into a long
  /// unattended spin.
  static const int _kMaxAutoContinueAttempts = 3;

  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x
  // throws on a post-dispose `ref` read).
  late final ScreenProtectionManager _screenProtection;

  /// mobile-perf MEDIUM fix — identity-keyed memo for
  /// [groupArchiveByKyivDay]. `build()` also watches
  /// `masterArchiveInFlightProvider`/`masterArchiveDialogVisibleProvider`
  /// (the «Виконано» flow flips both without ever changing `state.items`'s
  /// identity — `master_archive_notifier.dart`'s `copyWith` only allocates a
  /// new `items` list on `_fetchFirstPage`/`refresh`/`loadMore`; every other
  /// `copyWith` call reuses the prior reference), so re-running the O(n)
  /// grouping pass on those rebuilds is pure waste. `identical()` is a sound
  /// cache key here specifically because [groupArchiveByKyivDay] is pure
  /// over `items` alone (no clock/locale read — see that function's file
  /// header) and `MasterArchiveState.items` is only ever REPLACED, never
  /// mutated in place. The day-header LABEL itself is formatted separately,
  /// at widget-build time, in `_ArchiveDayHeader.build()` — so a locale
  /// change is unaffected by this cache.
  List<Booking>? _lastGroupedItems;
  List<ArchiveListEntry>? _lastGroupedEntries;

  List<ArchiveListEntry> _groupedEntries(List<Booking> items) {
    if (identical(_lastGroupedItems, items)) return _lastGroupedEntries!;
    debugGroupArchiveByKyivDayCallCount++;
    final List<ArchiveListEntry> entries = groupArchiveByKyivDay(items);
    _lastGroupedItems = items;
    _lastGroupedEntries = entries;
    return entries;
  }

  MasterArchiveQuery get _query =>
      MasterArchiveQuery.of(statuses: _statuses, serviceIds: _serviceIds);

  int get _activeFilterCount => bookingsActiveFilterCount(
    hasStatuses: _statuses.isNotEmpty,
    hasServiceIds: _serviceIds.isNotEmpty,
  );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _screenProtection.release();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore) return;
    if (!_scrollController.hasClients) return;
    final ScrollPosition pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - _loadMoreThreshold) {
      // The notifier itself guards against double-fetch + last-page no-op.
      ref.read(masterArchiveProvider(_query).notifier).loadMore();
    }
  }

  Future<void> _refresh() {
    // A fresh page 0 gets a fresh auto-continue budget.
    _autoContinueAttempts = 0;
    return ref.read(masterArchiveProvider(_query).notifier).refresh();
  }

  Future<void> _applyFilters() async {
    final List<MasterService> services =
        ref.read(masterServiceCatalogProvider).asData?.value ??
        const <MasterService>[];
    final BookingsFilterSelection? applied = await BookingsFilterSheet.show(
      context,
      initial: BookingsFilterSelection(
        statuses: _statuses,
        serviceIds: _serviceIds,
      ),
      services: services,
    );
    if (!mounted || applied == null) return;
    setState(() {
      _statuses = applied.statuses;
      _serviceIds = applied.serviceIds;
      // A new filter combination is a different provider-family instance
      // (fresh page 0) — give it its own auto-continue budget.
      _autoContinueAttempts = 0;
    });
  }

  void _openDetail(Booking booking) {
    context.push(RouteNames.masterBookingDetail(booking.id));
  }

  /// «Відгук» — pushes the SHIPPED leave-client-feedback screen (Track 7.x
  /// Wave B) for a COMPLETED row the SERVER also says is still reviewable.
  /// The card gates the slot on `booking.status == BookingStatus.completed`
  /// AND `booking.providerCanReviewClient` (2026-08-18 — the status term was
  /// briefly dropped and is now restored: a provider must close a booking
  /// before rating the client, not before). See
  /// `MasterBookingCard.onReview`'s doc for the full gate contract.
  ///
  /// Unlike the detail→review path (where `BookingDetailScreen` stays
  /// mounted underneath and keeps `bookingDetailProvider(id)` warm), this
  /// screen is fed by `GET /bookings/me`, which never touches that provider
  /// — so a bare push here would be a guaranteed cold `GET /bookings/{id}`
  /// AFTER `LeaveClientFeedbackScreen` builds. Kick the fetch off first so it
  /// overlaps the push transition instead.
  ///
  /// A bare `ref.read(bookingDetailProvider(id).future)` would NOT be
  /// enough: that is a one-off read, not a durable listener, so
  /// `bookingDetailProvider` (an autoDispose family) gets disposed again the
  /// instant this synchronous call stack unwinds — well before the pushed
  /// `LeaveClientFeedbackScreen` gets a chance to attach its OWN
  /// `ref.watch`, so it would just fire a SECOND, independent
  /// `GET /bookings/{id}` on a fresh element (proven red first — see
  /// `master_archive_screen_test.dart`'s «Відгук» real-route-topology
  /// group). `listenManual` instead holds a REAL subscription, keeping the
  /// SAME element (and its in-flight/resolved future) alive across the
  /// navigation for `LeaveClientFeedbackScreen`'s `ref.watch` to attach to
  /// — exactly one network round trip, just started earlier. The
  /// subscription is closed one frame after the push (by then the
  /// destination screen's own watch is what's keeping the provider alive),
  /// not left open for this screen's remaining lifetime — `MasterArchiveScreen`
  /// itself never rebuilds off `bookingDetailProvider`, so no rebuild is
  /// lost by closing it.
  ///
  /// The `(_, _) {}` listener body is a deliberate no-op: any error surfaces
  /// through `LeaveClientFeedbackScreen`'s own `AsyncValue.error` branch,
  /// which watches this very same provider — never through this warm-up.
  ///
  /// ## The pop result, and why this is NOT an invalidate
  ///
  /// The pushed screen reports a `bool` upward — `true` meaning "this booking
  /// is no longer reviewable by this provider" (feedback submitted, or its own
  /// `GET /bookings/{id}` pre-gate found the row already reviewed). See
  /// `LeaveClientFeedbackScreen`'s file header for the full contract.
  ///
  /// That result drives `MasterArchiveNotifier.markClientReviewed`, which
  /// rewrites JUST that row's [Booking.providerCanReviewClient] — zero
  /// network, accumulated pages and scroll position untouched, CTA gone on the
  /// same frame the pop lands. It REPLACES the bare
  /// `ref.invalidate(masterArchiveProvider)` the review screen used to fire on
  /// its own behalf, which discarded every cached filter combination's pages
  /// (and, on a filtered archive, burned up to [_kMaxAutoContinueAttempts]
  /// extra `loadMore` round trips re-walking pages the master had already
  /// paged past) to learn one boolean — mobile-perf MEDIUM, 2026-08-17. A
  /// refetch is only defensible when a row's STATUS moved, which is why
  /// «Виконано» still reloads through [_reloadArchive] and this does not.
  ///
  /// `extra` carries the entry point so the destination knows NOT to invalidate
  /// `bookingDetailProvider` on success — nothing on this stack watches it, so
  /// that refetch would be read by nobody. See [ClientReviewEntry].
  ///
  /// [_query] is re-read AFTER the await deliberately: it is the filter
  /// combination the row was tapped from, since a covered archive cannot open
  /// its filter sheet. If a future change ever lets it, the worst case is a
  /// no-op — `markClientReviewed` ignores an id no loaded row carries.
  ///
  /// ## Why the warm-up is preceded by an INVALIDATE (mobile-qa LOW, 2026-08-17
  /// cycle 3)
  ///
  /// `bookingDetailProvider` is autoDispose, but Riverpod DEFERS disposing an
  /// element whose last listener just left. A master who backs out of this
  /// screen and immediately re-taps «Відгук» therefore re-attaches to the SAME
  /// cached element and is re-served its stored value with NO
  /// `GET /bookings/{id}` at all — measured: the re-entry leaves
  /// `getBookingDetailCalls` flat, and only ~10 s of idling lets the element go.
  /// On a failed first attempt that replays the `AsyncError` (the master must
  /// tap «Повторити» to get anywhere); on a successful one it replays a
  /// possibly-STALE `providerCanReviewClient`, which is the half that matters
  /// here — this screen's entire job is to gate on the freshest answer to that
  /// one flag.
  ///
  /// Invalidating first makes the destination ALWAYS fetch fresh. It is close
  /// to free on the ordinary path: with no element alive, `invalidate` is a
  /// null-safe lookup that does nothing (`ProviderContainer.invalidate` →
  /// `readElement(provider)?.invalidateSelf()`), so the exactly-one-round-trip
  /// property the `listenManual` warm-up below buys is untouched. It must run
  /// BEFORE the warm-up: invalidating the element the warm-up just subscribed
  /// to would re-fire the very fetch it exists to start early.
  ///
  /// Deliberately NOT done at `BookingDetailScreen`'s own review CTA: there the
  /// detail screen stays mounted and `ref.watch`es this family itself, so the
  /// element is never in the disposal-deferred state this fixes — and an
  /// invalidate there would cost a real refetch of data that screen is actively
  /// rendering.
  Future<void> _openReview(Booking booking) async {
    ref.invalidate(bookingDetailProvider(booking.id));
    final ProviderSubscription<AsyncValue<Booking>> warmup = ref.listenManual(
      bookingDetailProvider(booking.id),
      (AsyncValue<Booking>? previous, AsyncValue<Booking> next) {},
    );
    // Captured BEFORE the post-frame close is scheduled so the synchronous
    // push→schedule ordering the warm-up depends on is exactly as it was; the
    // await happens only after both have run.
    final Future<bool?> popped = context.push<bool>(
      RouteNames.clientReview(booking.id),
      extra: ClientReviewEntry.masterArchive,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => warmup.close());
    final bool? noLongerReviewable = await popped;
    if (!mounted || noLongerReviewable != true) return;
    // ADJACENT-PATH patch. This is one of TWO paths that drop a row's «Відгук»
    // CTA, and the duplication is deliberate — see
    // [_scheduleClientReviewSignalPatch] for the other one and why neither
    // subsumes it. This one is the instant patch: it lands synchronously on the
    // frame the pop resolves, with no dependence on provider delivery ordering,
    // and it is what QA's integration scenarios pin. It also fires for a case
    // the signal set never sees at all: the master backing out of an
    // ALREADY-reviewed booking, where nothing was submitted but the
    // destination's own pre-gate fetch still popped `true`.
    ref
        .read(masterArchiveProvider(_query).notifier)
        .markClientReviewed(booking.id);
  }

  /// NON-ADJACENT-PATH patch — the other half of the pair described in
  /// [_openReview], and the fix for the journey that one structurally cannot
  /// reach (mobile-perf MEDIUM, 2026-08-17 cycle 2):
  ///
  ///   archive → row tap → `BookingDetailScreen` → footer «Залишити відгук про
  ///   клієнта» → review → submit → pop → pop back to the archive
  ///
  /// On that path [_openDetail] is fire-and-forget and the review screen pops
  /// to the DETAIL screen, so no pop result ever reaches this one; chaining a
  /// result back through `BookingDetailScreen` would still lose it whenever the
  /// master leaves via a system/predictive back gesture (which pops `null`).
  /// The review screen therefore deposits the booking id in the session-scoped
  /// [clientReviewSignalProvider] instead, and this reads it.
  ///
  /// Handles BOTH shapes with one code path, because it runs on every build:
  /// a signal arriving while this screen is alive (the watch in `build` wakes
  /// it — on RESUME if this screen is covered, which is when the master can see
  /// it again), and ids already in the set when this screen is (re)built later.
  ///
  /// TERMINATES: the patch flips exactly the matched rows'
  /// [Booking.providerCanReviewClient] to `false`, so the very next build finds
  /// no pending id and schedules nothing. The `providerCanReviewClient` term in
  /// the filter below is what makes that true — without it this would rewrite
  /// `items` on every build, spinning the frame loop AND defeating
  /// [_groupedEntries]'s identity memo.
  ///
  /// Deferred to a post-frame callback because it WRITES to a provider and is
  /// called from `build`. [_query] is re-read there: if the filter changed in
  /// between, the worst case is a no-op (`markClientsReviewed` ignores an id no
  /// loaded row carries) and the new family member's own build re-derives its
  /// pending set from its own rows.
  ///
  /// Takes the whole [AsyncValue], not just its value, so it can bail on a
  /// state that CANNOT be patched — an `AsyncError`/`AsyncLoading` that RETAINS
  /// a previous value still exposes `items` through `.value`, and `pending`
  /// there never clears (nothing rewrites those rows), so every build in that
  /// state used to allocate a list + closure for a post-frame callback that
  /// `markClientsReviewed`'s own `is! AsyncData` guard then dropped on the
  /// floor. Dead scheduling, not a spin — it emitted nothing — but it is now
  /// skipped outright (mobile-perf INFO, 2026-08-17 cycle 3). The guard MIRRORS
  /// `markClientsReviewed`'s deliberately: when the reload lands as `AsyncData`
  /// this method runs again on that build and patches then.
  ///
  /// The patch is applied as ONE batch call rather than a loop of single-id
  /// ones — see `MasterArchiveNotifier.markClientsReviewed` for why (O(k·n)
  /// list copies and `k` state emissions collapse to one of each).
  void _scheduleClientReviewSignalPatch(
    AsyncValue<MasterArchiveState> async,
    Set<String> signalled,
  ) {
    if (signalled.isEmpty) return;
    if (async is! AsyncData<MasterArchiveState>) return;
    final Set<String> pending = <String>{
      for (final Booking b in async.value.items)
        if (b.providerCanReviewClient && signalled.contains(b.id)) b.id,
    };
    if (pending.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(masterArchiveProvider(_query).notifier)
          .markClientsReviewed(pending);
    });
  }

  /// The ONE place this screen drops its own cached pages — every «Виконано»
  /// path routes its invalidation through here (mobile-perf LOW, 2026-08-17).
  ///
  /// Exists to make ONE invariant local: a reload starts a fresh page 0, so it
  /// starts with a fresh [_autoContinueAttempts] budget — exactly like
  /// [_refresh] and [_applyFilters], the two other paths that reset it.
  ///
  /// HONEST SCOPE: on THESE two call sites the reset is DEFENSIVE, not a live
  /// bug fix. Both are reachable only by tapping «Виконано» on a rendered row,
  /// and `build`'s `data:` branch zeroes the counter on every build whose
  /// `state.items` is non-empty — so it is provably already 0 whenever a row
  /// exists to tap. The reset is written here anyway because that argument is
  /// an emergent property of ANOTHER branch's bookkeeping, one relaxation away
  /// from silently going stale, and because [_refresh] (reachable by pulling on
  /// the auto-continue/empty branch, where the counter genuinely IS non-zero)
  /// proves the invariant belongs to "a fresh page 0", not to "a non-empty
  /// list". mobile-perf LOW, 2026-08-17.
  ///
  /// No `setState`: the invalidation itself rebuilds this widget off the
  /// watched provider, and [_autoContinueAttempts] is only ever READ during
  /// that rebuild (same idiom as [_refresh]).
  ///
  /// The reload is SEAMLESS — the master keeps their rows and scroll position
  /// while the fresh page 0 lands. See `build`'s `async.when` note for what
  /// actually delivers that (measured, not the flag one would assume).
  ///
  /// A reload — not a surgical row patch like [_openReview]'s — is genuinely
  /// right here: closing a booking changes its [BookingStatus], so the row can
  /// legitimately leave the master's active filter selection or its day group
  /// entirely, which no local rewrite can decide.
  void _reloadArchive(void Function() invalidate) {
    _autoContinueAttempts = 0;
    invalidate();
  }

  /// «Виконано» — see file header's ROLE GATING/CLOSE ACTION notes.
  ///
  /// RE-ENTRANCY (mirrors `booking_cancel_navigation.dart`'s
  /// `startBookingCancel` shape): the guard is checked-then-set
  /// SYNCHRONOUSLY before anything async happens, spans the confirmation
  /// dialog AND the write, and clears in a single outer `finally` on every
  /// exit path — dialog dismissed, write failure, and success alike. ONE
  /// shared flag for the whole screen, not keyed per booking — see
  /// `master_archive_in_flight_notifier.dart`'s file header for why that is
  /// the deliberate choice here.
  Future<void> _confirmComplete(Booking booking) async {
    if (ref.read(masterArchiveInFlightProvider)) return;
    final MasterArchiveInFlight inFlight = ref.read(
      masterArchiveInFlightProvider.notifier,
    );
    inFlight.begin();
    try {
      final bool isAppointment = booking.appointmentId != null;
      // Brackets ONLY the dialog-open window so the row's spinner can mute
      // its ticker while it's obscured — see
      // `master_archive_dialog_visible_notifier.dart`'s file header. `end()`
      // in `finally` clears it whether the master confirms or backs out.
      final MasterArchiveDialogVisible dialogVisible = ref.read(
        masterArchiveDialogVisibleProvider.notifier,
      );
      final bool? confirmed;
      dialogVisible.begin();
      try {
        confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => CompleteBookingDialog(isAppointment: isAppointment),
        );
      } finally {
        dialogVisible.end();
      }
      if (confirmed != true || !mounted) return;

      try {
        final String? appointmentId = booking.appointmentId;
        if (appointmentId != null) {
          // PER-ITEM, never whole-visit. This list renders ONE ROW PER
          // SERVICE, so «Виконано» on a row must complete exactly that
          // service and leave its siblings CONFIRMED. The whole-visit
          // `completeAppointment` that used to be called here completed the
          // visit in lockstep AND guarded only the visit's `startsAt` (the
          // FIRST service), so tapping one row silently completed every other
          // service of the same visit — including ones that had not started —
          // and they then surfaced as fresh COMPLETED rows in this very
          // archive. See `AppointmentRepository.completeAppointmentService`.
          await ref
              .read(appointmentRepositoryProvider)
              .completeAppointmentService(appointmentId, booking.id);
        } else {
          await ref.read(bookingRepositoryProvider).completeBooking(booking.id);
        }
      } on ProviderCompleteNotStartedFailure catch (failure) {
        // Defense-in-depth — the booking's start slipped back into the
        // future relative to this (possibly stale) row, or the device clock
        // was rolled back and the server refused to honour it. Same
        // resolution as `booking_detail_screen.dart`'s identical 409:
        // localized message + refetch so the row re-renders from the
        // server's authoritative state.
        if (!mounted) return;
        showErrorSnack(context, failure.userMessage(context));
        _reloadArchive(() => ref.invalidate(masterArchiveProvider));
        return;
      } catch (e, st) {
        if (kDebugMode) {
          // SEC: the exception is NOT passed as `error:` — a `DioException`'s
          // `toString()` embeds the response body/headers, which on this
          // feature's endpoints carry client PII. The runtime type is enough
          // to tell a network failure from a mapping bug, and the stack trace
          // (project code paths only) is not sensitive.
          // `booking_repository.dart`'s malformed-envelope logs interpolate
          // `runtimeType` the same way (mobile-security INFO, 2026-08-17).
          //
          // Stated precisely, because the earlier blanket claim here ("this is
          // the shape every OTHER `log()` in this feature already uses — none
          // of them passes `error:`") was FALSE: the one other `error:`-passing
          // `log()` in this feature is
          // `salon_master_coverage_notifier.dart:155`. It is not a
          // counterexample to the rule this comment defends — what it passes is
          // a MAPPED `Failure`, which does not override `toString()` (so it
          // logs `Instance of 'NetworkFailure'`), never a raw `DioException`
          // whose `toString()` embeds the response body. That site is
          // deliberately left unchanged.
          log(
            'completeBooking/completeAppointment failed: ${e.runtimeType}',
            name: _tag,
            stackTrace: st,
          );
        }
        if (!mounted) return;
        showErrorSnack(context, AppLocalizations.of(context).errUnknown);
        return;
      }

      if (!mounted) return;
      // Same shared fan-out `booking_detail_screen.dart`'s own
      // decline/complete now routes through — see
      // `invalidateBookingViewsAfterProviderClose`'s doc: EVERY cached
      // archive filter combination, the master's own day timeline (which
      // just lost a CONFIRMED row to COMPLETED), and — a no-op here, since
      // this screen never has the booking's own detail warm to begin with —
      // `bookingDetailProvider(booking.id)`. Migrated to the shared helper
      // (2026-08-16) so this screen and `booking_detail_screen.dart` cannot
      // independently drift on the contract again; this call site's own
      // observable behaviour (which caches drop) is unchanged.
      //
      // Wrapped in [_reloadArchive] (2026-08-17) purely for the auto-continue
      // budget reset the archive's own reload needs — WHICH caches drop is
      // still entirely the shared helper's decision, unchanged.
      _reloadArchive(
        () => invalidateBookingViewsAfterProviderClose(
          ref,
          booking.id,
          affectedDate: kyivDayOf(booking.startAt),
        ),
      );
    } finally {
      inFlight.end();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<MasterArchiveState> async = ref.watch(
      masterArchiveProvider(_query),
    );
    final bool completing = ref.watch(masterArchiveInFlightProvider);
    // Mutes every ticker in the list body (notably the close button's own
    // indeterminate spinner) for exactly the confirmation-dialog-open
    // window — see `master_archive_dialog_visible_notifier.dart`'s file
    // header for why an un-muted spinner there breaks `pumpAndSettle()`
    // behind the modal `showDialog` barrier.
    final bool dialogVisible = ref.watch(masterArchiveDialogVisibleProvider);
    // Injected clock seam for the rows' «Виконано» start-time gate — read
    // ONCE here (the only place `ref.watch` is legal on this state) and
    // threaded down through `_archiveBookingRow`, which runs inside a lazy
    // `itemBuilder` where watching would be out of build scope. See
    // `core/time/clock_provider.dart`.
    final DateTime now = ref.watch(clockProvider)();
    // The session-scoped set of bookings whose client this provider has already
    // reviewed — see [_scheduleClientReviewSignalPatch]. `ref.watch` (not
    // `ref.listen`) on purpose: it is what makes an id deposited while this
    // screen was COVERED still land, since Riverpod 3 pauses a covered
    // consumer and flushes the change when it resumes.
    final Set<String> reviewSignals = ref.watch(clientReviewSignalProvider);
    final MasterArchiveState? data = async.value;
    _hasMore = data?.hasMore ?? false;
    _isLoadingMore = data?.isLoadingMore ?? false;
    _scheduleClientReviewSignalPatch(async, reviewSignals);

    return Scaffold(
      key: const Key('master-archive-screen'),
      backgroundColor: BrandColors.base,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _ArchiveHeader(
              title: l10n.masterArchiveTitle,
              activeFilterCount: _activeFilterCount,
              onOpenFilters: _applyFilters,
              onBack: () => context.pop(),
            ),
            Expanded(
              child: TickerMode(
                enabled: !dialogVisible,
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  color: BrandColors.accentDeep,
                  backgroundColor: BrandColors.base,
                  // A RELOAD of an already-rendered list must keep that list on
                  // screen instead of replacing every accumulated page (and the
                  // master's scroll position) with the skeleton — mobile-perf
                  // LOW, 2026-08-17.
                  //
                  // NO FLAG IS NEEDED HERE, and there deliberately isn't one.
                  // [_reloadArchive] reloads via `ref.invalidate`, and
                  // `AsyncValue.when` ALREADY skips the loading branch for an
                  // invalidate/refresh — that is `skipLoadingOnRefresh`, which
                  // defaults to `true`. Mutation-verified 2026-08-17 against a
                  // deliberately PENDING reload: with the flag deleted,
                  // `master_archive_screen_test.dart`'s frame-by-frame
                  // "«Виконано» reload keeps the list" test stays GREEN.
                  //
                  // A `skipLoadingOnReload: true` used to sit below, justified
                  // as covering the OTHER trigger `skipLoadingOnRefresh` does
                  // not: a reload caused by one of the provider's own
                  // dependencies changing. That justification is FALSE for THIS
                  // provider (mobile-perf INFO, 2026-08-17 cycle 2) —
                  // `MasterArchiveNotifier.build` only ever `ref.read`s
                  // (`master_archive_notifier.dart:262,312`), so it has zero
                  // dependencies and `isReloading` can never be true. The flag
                  // was provably inert and is removed rather than left as a
                  // comment a reader would trust. (It IS load-bearing on
                  // `leave_client_feedback_screen.dart`, whose
                  // `bookingDetailProvider` really does `ref.watch` — do not
                  // "consistency-clean" that one away.)
                  //
                  // The FIRST load still shows the skeleton below — there is no
                  // previous value to keep. Pull-to-refresh is unaffected too,
                  // deliberately: `MasterArchiveNotifier.refresh` assigns a bare
                  // `const AsyncLoading()` that DROPS the value, so no flag
                  // could apply and the skeleton renders under the master's own
                  // pull gesture, where a visible reload is the point.
                  child: async.when(
                    loading: () => ListView(
                      key: const Key('master-archive-skeleton'),
                      // Attached in EVERY branch, not just the non-empty one
                      // (mobile-perf HIGH-2 fix) — a scroll/pull gesture must
                      // always have a live `ScrollController` to drive
                      // `_onScroll`, even though this particular branch never
                      // has more to load.
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: kMyBookingsListPadding,
                      children: const <Widget>[BookingsSkeleton()],
                    ),
                    error: (Object e, StackTrace _) => ListView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: kMyBookingsListPadding,
                      children: <Widget>[
                        MyBookingsErrorState(
                          error: e,
                          onRetry: () =>
                              ref.invalidate(masterArchiveProvider(_query)),
                        ),
                      ],
                    ),
                    data: (MasterArchiveState state) {
                      if (state.items.isNotEmpty) {
                        // A page matched — any earlier auto-continue streak
                        // is moot; a LATER empty stretch (paging further with
                        // a narrow filter) gets its own fresh budget.
                        _autoContinueAttempts = 0;
                      }
                      if (state.items.isEmpty && state.hasMore) {
                        // mobile-perf HIGH-1 fix — server pages remain and
                        // NONE fetched so far matched the active client-side
                        // filter (see `master_archive_notifier.dart`'s
                        // "Pagination interacts with client-side filtering"
                        // header). The terminal `_ArchiveEmptyState` would be
                        // WRONG here: a match may exist on a later raw page.
                        // Keep advancing instead — bounded, see
                        // [_autoContinueAttempts]'s doc for the anti-spin
                        // reasoning and the bounded-vs-indefinite UX choice.
                        final bool budgetLeft =
                            _autoContinueAttempts < _kMaxAutoContinueAttempts;
                        if (budgetLeft) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            // Re-read the LATEST provider state rather than
                            // trusting the closed-over `state` snapshot — it
                            // may already be stale by the time this callback
                            // actually runs (e.g. this build fired more than
                            // once before the frame settled).
                            final MasterArchiveState? latest = ref
                                .read(masterArchiveProvider(_query))
                                .value;
                            if (latest == null) return;
                            if (latest.isLoadingMore || !latest.hasMore) {
                              return;
                            }
                            if (latest.items.isNotEmpty) return;
                            _autoContinueAttempts++;
                            ref
                                .read(masterArchiveProvider(_query).notifier)
                                .loadMore();
                          });
                        }
                        return ListView(
                          key: const Key('master-archive-auto-continue'),
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: kMyBookingsListPadding,
                          children: <Widget>[
                            if (budgetLeft)
                              Semantics(
                                label: l10n.masterArchiveScanningSemantics,
                                liveRegion: true,
                                child: const MyBookingsLoadMoreSpinner(),
                              )
                            else
                              _ArchiveContinueState(
                                onLoadMore: () {
                                  setState(() => _autoContinueAttempts = 0);
                                  ref
                                      .read(
                                        masterArchiveProvider(_query).notifier,
                                      )
                                      .loadMore();
                                },
                              ),
                          ],
                        );
                      }
                      if (state.items.isEmpty) {
                        return ListView(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: kMyBookingsListPadding,
                          children: <Widget>[
                            _ArchiveEmptyState(
                              filtered: _query.hasFilters,
                              onClearFilters: () => setState(() {
                                _statuses = const <BookingStatus>{};
                                _serviceIds = const <String>{};
                                _autoContinueAttempts = 0;
                              }),
                            ),
                          ],
                        );
                      }
                      // Flattened header-or-card list over the FULL
                      // accumulated `state.items` (every raw page fetched so
                      // far, already merged by the notifier) — see
                      // `archive_day_groups.dart`'s file header for why
                      // grouping the merged list, rather than each freshly
                      // fetched page independently, is exactly what makes a
                      // Kyiv day that straddles a page boundary collapse to
                      // ONE header instead of two. `ListView.separated` stays
                      // index-addressable over this flat list, so
                      // virtualization and the per-row `RepaintBoundary`
                      // below are unaffected — only the index math changed,
                      // not the widget shape.
                      final List<ArchiveListEntry> entries = _groupedEntries(
                        state.items,
                      );
                      final int extra = state.hasMore ? 1 : 0;
                      return ListView.separated(
                        key: const Key('master-archive-list'),
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: kMyBookingsListPadding,
                        itemCount: entries.length + extra,
                        separatorBuilder: (BuildContext context, int i) {
                          final ArchiveListEntry? current = i < entries.length
                              ? entries[i]
                              : null;
                          final ArchiveListEntry? next = i + 1 < entries.length
                              ? entries[i + 1]
                              : null;
                          if (current is ArchiveDayHeaderEntry) {
                            // Header directly above its first card — a tight
                            // gap reads as "belongs together".
                            return const SizedBox(height: VelvetSpacing.sm);
                          }
                          if (next is ArchiveDayHeaderEntry) {
                            // Last card of a group directly above the NEXT
                            // day's header — a wider gap reads as "new
                            // group".
                            return const SizedBox(height: VelvetSpacing.lg);
                          }
                          return const SizedBox(height: VelvetSpacing.md);
                        },
                        itemBuilder: (BuildContext context, int i) {
                          if (i >= entries.length) {
                            return const MyBookingsLoadMoreSpinner();
                          }
                          final ArchiveListEntry entry = entries[i];
                          return switch (entry) {
                            ArchiveDayHeaderEntry() => _ArchiveDayHeader(
                              key: ValueKey<String>(
                                'master-archive-day-header-'
                                '${entry.kyivDay.toIso8601String()}',
                              ),
                              entry: entry,
                            ),
                            ArchiveBookingEntry(:final Booking booking) =>
                              _archiveBookingRow(booking, completing, now),
                          };
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The per-row `RepaintBoundary`-wrapped `MasterBookingCard` — split out
  /// of the `itemBuilder` switch above purely so that switch stays a clean
  /// one-line-per-variant match; identical widget to what this screen
  /// rendered before date-group headers existed.
  Widget _archiveBookingRow(Booking booking, bool completing, DateTime now) {
    return RepaintBoundary(
      key: ValueKey<String>(booking.id),
      // «Виконано» is now an ADDITIVE slot on `MasterBookingCard` itself
      // (user-locked decision, 2026-08-16 — reuse and fix shared widgets in
      // place, never fork/wrap) — see that widget's `onComplete` doc. Pinned
      // to the FULL layout regardless of `durationMinutes`: the archive is a
      // list, not a duration-proportional timeline. Mirrors
      // `declared_time_cards.dart`'s existing non-timeline caller of the
      // same `minHeight` knob.
      child: MasterBookingCard(
        booking: booking,
        onTap: () => _openDetail(booking),
        minHeight: MasterBookingCard.fullLayoutMinHeight,
        onComplete: () => _confirmComplete(booking),
        completing: completing,
        // Required alongside `onComplete` — the card's start-time gate. See
        // `MasterBookingCard.now`.
        now: now,
        // «Відгук» — additive slot, still-reviewable rows only (the card
        // itself gates on `booking.providerCanReviewClient`; see
        // `MasterBookingCard.onReview`'s doc). Not re-gated here — passing a
        // non-null callback unconditionally keeps the "which rows show it"
        // decision in exactly ONE place (the card) rather than duplicated at
        // every call site.
        onReview: () => _openReview(booking),
      ),
    );
  }
}

/// A date-group header row above every run of bookings that share a Kyiv
/// calendar day — see `archive_day_groups.dart`'s file header for the
/// grouping/page-boundary-merge contract this renders. Plain (non-sticky),
/// matching the approved preview shape; no scroll-pinning behaviour.
class _ArchiveDayHeader extends StatelessWidget {
  const _ArchiveDayHeader({required this.entry, super.key});

  final ArchiveDayHeaderEntry entry;

  @override
  Widget build(BuildContext context) {
    // `formatBookingDayHeader` performs its OWN `toBeauticaTime` conversion,
    // so it takes the group's REPRESENTATIVE INSTANT — never `entry.kyivDay`
    // itself, which is a date token, not an instant (see that field's doc
    // and `kyiv_day.dart`'s date-token-vs-instant warning).
    final String label = formatBookingDayHeader(entry.representativeInstant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.xs,
        0,
        VelvetSpacing.xs,
        0,
      ),
      // `header: true` + `excludeSemantics: true` collapses the header text
      // into a SINGLE semantic announcement per date group, rather than a
      // screen reader reading it as an ordinary stray label indistinguishable
      // from the cards around it.
      child: Semantics(
        header: true,
        label: label,
        excludeSemantics: true,
        child: Text(label, style: VelvetText.label()),
      ),
    );
  }
}

/// The screen's own header — title, back arrow, and the reused
/// `BookingsFilterButton`. Deliberately NOT `bookings_discovery_view.dart`'s
/// private `_Header` (that class is `private` to its file and carries the
/// «+ add booking» affordance this screen has no use for).
class _ArchiveHeader extends StatelessWidget {
  const _ArchiveHeader({
    required this.title,
    required this.activeFilterCount,
    required this.onOpenFilters,
    required this.onBack,
  });

  final String title;
  final int activeFilterCount;
  final VoidCallback onOpenFilters;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: BrandColors.accent.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          VelvetSpacing.lg,
          VelvetSpacing.md,
          VelvetSpacing.lg,
          VelvetSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            NeumorphicIconButton(
              key: const Key('master-archive-back'),
              icon: Icons.arrow_back_ios_new_rounded,
              semanticLabel: l10n.bookingsDiscoveryBackSemantics,
              onTap: onBack,
            ),
            const SizedBox(width: VelvetSpacing.md),
            Expanded(
              child: Text(
                title,
                style: VelvetText.pageTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: VelvetSpacing.sm),
            BookingsFilterButton(
              activeCount: activeFilterCount,
              onTap: onOpenFilters,
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty state — true-empty (no past bookings at all) vs filter-empty
/// (bookings exist, none match the active filter). Mirrors
/// `bookings_discovery_view.dart`'s equivalent split, new copy scoped to this
/// screen (see l10n keys).
class _ArchiveEmptyState extends StatelessWidget {
  const _ArchiveEmptyState({
    required this.filtered,
    required this.onClearFilters,
  });

  final bool filtered;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Center(
      key: const Key('master-archive-empty'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(VelvetSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                filtered
                    ? Icons.filter_alt_off_rounded
                    : Icons.inventory_2_outlined,
                size: 48,
                color: BrandColors.muted,
              ),
              const SizedBox(height: VelvetSpacing.md),
              Text(
                filtered
                    ? l10n.masterBookingsNoResultsTitle
                    : l10n.masterArchiveEmptyTitle,
                textAlign: TextAlign.center,
                style: VelvetText.subheading(),
              ),
              const SizedBox(height: VelvetSpacing.xs),
              Text(
                filtered
                    ? l10n.masterArchiveNoResultsBody
                    : l10n.masterArchiveEmptyBody,
                textAlign: TextAlign.center,
                style: VelvetText.body(),
              ),
              if (filtered) ...<Widget>[
                const SizedBox(height: VelvetSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: NeumorphicButton(
                    key: const Key('master-archive-clear-filters'),
                    label: l10n.masterBookingsClearFilters,
                    icon: Icons.filter_alt_off_rounded,
                    onPressed: onClearFilters,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// mobile-perf HIGH-1 fix — shown once [_MasterArchiveScreenState
/// ._autoContinueAttempts] hits its bounded cap while `hasMore` is STILL
/// true and no visible row has surfaced yet: NOT the terminal `_ArchiveEmptyState`
/// (a match may still exist further on), and NOT another indefinite spinner
/// (see [_MasterArchiveScreenState._autoContinueAttempts]'s doc for why an
/// unbounded auto-spin is its own UX problem). [onLoadMore] resumes fetching
/// and re-arms a fresh auto-continue burst.
class _ArchiveContinueState extends StatelessWidget {
  const _ArchiveContinueState({required this.onLoadMore});

  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Center(
      key: const Key('master-archive-continue'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(VelvetSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.filter_alt_off_rounded,
                size: 48,
                color: BrandColors.muted,
              ),
              const SizedBox(height: VelvetSpacing.md),
              Text(
                l10n.masterArchiveContinueBody,
                textAlign: TextAlign.center,
                style: VelvetText.body(),
              ),
              const SizedBox(height: VelvetSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: NeumorphicButton(
                  key: const Key('master-archive-load-more'),
                  label: l10n.masterArchiveLoadMoreCta,
                  icon: Icons.expand_more_rounded,
                  onPressed: onLoadMore,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
