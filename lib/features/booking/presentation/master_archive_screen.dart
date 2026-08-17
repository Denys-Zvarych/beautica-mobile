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
// `LeaveClientFeedbackScreen` (Track 7.x Wave B) for a COMPLETED row — see
// that field's own doc for why it is deliberately NOT gated on
// `booking.providerCanReviewClient` (that flag is hardcoded `false` on every
// `GET /bookings/me` row this screen's own list is built from). Every OTHER
// consumer of the card (`bookings_timeline_grid.dart`,
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

import '../application/booking_calendar_invalidation.dart';
import '../application/booking_detail_notifier.dart';
import '../application/master_archive_dialog_visible_notifier.dart';
import '../application/master_archive_in_flight_notifier.dart';
import '../application/master_archive_notifier.dart';
import '../data/booking_providers.dart';
import '../domain/booking.dart';
import '../domain/booking_status.dart';
import '../domain/master_archive_query.dart';
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
  /// Wave B) for a COMPLETED row. See `MasterBookingCard.onReview`'s doc for
  /// why this is offered on every COMPLETED row without a
  /// `providerCanReviewClient` gate (that flag is hardcoded `false` on every
  /// `GET /bookings/me` row, which is what feeds this screen) — a
  /// user-locked decision, 2026-08-16.
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
  void _openReview(Booking booking) {
    final ProviderSubscription<AsyncValue<Booking>> warmup = ref.listenManual(
      bookingDetailProvider(booking.id),
      (AsyncValue<Booking>? previous, AsyncValue<Booking> next) {},
    );
    context.push(RouteNames.clientReview(booking.id));
    WidgetsBinding.instance.addPostFrameCallback((_) => warmup.close());
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
        ref.invalidate(masterArchiveProvider);
        return;
      } catch (e, st) {
        if (kDebugMode) {
          log(
            'completeBooking/completeAppointment failed',
            name: _tag,
            error: e,
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
      invalidateBookingViewsAfterProviderClose(ref, booking.id);
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
    final MasterArchiveState? data = async.value;
    _hasMore = data?.hasMore ?? false;
    _isLoadingMore = data?.isLoadingMore ?? false;

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
        // «Відгук» — additive slot, COMPLETED rows only (the card itself
        // re-checks `booking.status`; see `MasterBookingCard.onReview`'s
        // doc). Not gated on `booking.status` here too — passing a non-null
        // callback unconditionally keeps the "which statuses show it"
        // decision in exactly ONE place (the card) rather than duplicated
        // at every call site.
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
                style: VelvetText.masterBookingsTitle,
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
