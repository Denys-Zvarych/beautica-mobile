// Phase 14.16/14.17 — SalonTimeScreen: salon booking flow step 3 of 4
// ("Час") — a horizontal `PageView` slider, one slide per master assigned in
// step 2 (`SalonMasterSelectionScreen`).
//
// DESIGN SOURCE: approved preview at
// `docs/signup-designs/SalonBookingTime/lib/screens/salon_time_screen.dart`
// (2026-06-30). Transcribed 1:1: the top bar ("Час" + step pill), the ‹ ›
// arrow / dot / counter pager, the `PageView.builder` of per-master slides,
// and the pinned `ScheduleConfirmBar`. Reused verbatim from the
// independent-master flow (Phase 14.1/14.14): [MonthCalendar]/[SlotChip] —
// the ONLY widgets locked as shared, per the phase docs' "Architecture
// decision" section.
//
// Each slide (`MasterSchedulePage`) picks ONE date + time PER MASTER — a
// single appointment per master covering ALL their assigned services (not
// per individual service). Forward navigation is entirely CTA-driven
// (`_handleNext`, wired via `ScheduleConfirmBar.onNext`/`onConfirm`) — a date
// pick alone no longer swaps a slide to its time chips, and a slot pick
// alone no longer advances the slider to the next master; both used to fire
// automatically off the tap. The pinned CTA reads «Далі» on every
// intermediate step (DATE phase with a day picked → commits to TIME phase;
// TIME phase with a slot picked → advances to the next unscheduled master)
// and only becomes «Підтвердити» once EVERY slide has both a date and a
// time — see `ScheduleConfirmBar`'s own doc comment for the label contract.
//
// NO `POST /bookings` CALL IN THIS SCREEN: «Підтвердити» (Phase 14.18) is
// PURE FORWARD NAVIGATION — it snapshots every scheduled master's picked
// date/time into concrete `SalonBookingAppointment`s (each with a stable
// idempotency key) and pushes `RouteNames.salonBookingConfirm`, where the
// actual submit runs (`SalonBookingConfirmScreen`, each appointment via the
// SHARED `AppointmentSubmit.submitVisit` — see Phase 271 for why this is no
// longer a bespoke per-master notifier). The booking-write
// lives OFF this screen so the step-3 picker stays a pure local-state editor;
// see `salon_booking_schedule_notifier.dart`'s header for the per-master
// (one appointment per master, primary-service) model.

import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import '../../salon/application/public_salon_profile_notifier.dart';
import '../../salon/application/salon_service_catalog_notifier.dart';
import '../../salon/domain/salon_master_summary.dart';
import '../../salon/domain/salon_service_catalog.dart';

import '../application/salon_booking_schedule_notifier.dart';
import '../application/salon_master_coverage_notifier.dart';
import '../domain/salon_booking_args.dart';
import '../domain/salon_booking_confirm_args.dart';
import '../domain/salon_master_schedule.dart';
import 'widgets/master_schedule_page.dart';
import 'widgets/salon_avatar_gradients.dart';
import 'widgets/schedule_confirm_bar.dart';
import 'widgets/selected_services_shelf.dart';

const Uuid _kUuid = Uuid();

/// Salon booking flow step 3 — per-master date/time picker, opened by
/// `SalonMasterSelectionScreen`'s "Підтвердити" CTA.
class SalonTimeScreen extends ConsumerStatefulWidget {
  const SalonTimeScreen({super.key, required this.args});

  final SalonBookingTimeArgs args;

  @override
  ConsumerState<SalonTimeScreen> createState() => _SalonTimeScreenState();
}

class _SalonTimeScreenState extends ConsumerState<SalonTimeScreen> {
  PageController? _pager;
  int _current = 0;
  bool _poppedForMissingSchedule = false;

  /// The resolved masterIds from the most recent successful `build()`,
  /// retained as a field — mirrors `_current`/`_pager`'s existing "mutate
  /// directly inside `build()`, no `setState`" convention already used in
  /// this file (see the `_current` clamp a few lines below) — so the back
  /// handlers (`PopScope` + `_TopBar`'s in-app arrow) can resolve the ACTIVE
  /// slide's master without threading it through as a parameter. Empty
  /// before the first successful load (loading/error state); the back
  /// handlers below treat that as "not in time phase", so back correctly
  /// falls through to a real pop while there's nothing to be mid-flow of yet.
  List<String> _masterIds = const <String>[];

  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x
  // throws on a post-dispose `ref` read).
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC: this screen renders the client's selected service names + prices
    // via `SelectedServicesShelf` (the pinned `ScheduleConfirmBar`) — guard
    // against screenshots / app-switcher snapshots while it is mounted.
    // Mirrors the INTENTIONAL PRODUCT DECISION already applied to the salon
    // flow's booking confirm/success screens
    // (`salon_booking_confirm_screen.dart`, `salon_booking_success_screen.dart`)
    // and the independent-master `booking_confirm_screen.dart` — see
    // `core/security/screen_protection.dart`'s file header. Do not remove in
    // a future audit pass.
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    _pager?.dispose();
    super.dispose();
  }

  void _goTo(int index, int count) {
    if (index < 0 || index >= count) return;
    final PageController? pager = _pager;
    if (pager == null || !pager.hasClients) return;
    pager.animateToPage(
      index,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  /// The step-3 CTA's action while the active slide isn't the final one
  /// (`ScheduleConfirmBar.onNext` — see that widget's doc comment for the
  /// label/enablement contract). Two phases, keyed on [activeInTimePhase]
  /// (the ACTIVE master's [SalonScheduleEntry.viewingTime]):
  ///  - DATE phase (a day picked, not yet viewing time): commits [masterId]
  ///    into its TIME phase via `enterTimePhase` — `MasterSchedulePage`'s own
  ///    `AnimatedSwitcher` reacts to `entry.viewingTime` flipping; the pager
  ///    itself does not move.
  ///  - TIME phase (a slot picked): advances the pager to the next
  ///    unscheduled master, mirroring the removed `_handleCompleted`'s
  ///    `nextUnscheduledIndex` lookup — just fired from the CTA instead of
  ///    automatically after `MasterSchedulePage._selectSlot`. Once every
  ///    master is scheduled there IS no "next unscheduled" left to jump to;
  ///    `ScheduleConfirmBar` itself switches to the «Підтвердити»/[_confirm]
  ///    branch at that point (via its own `_allScheduled`), so this method is
  ///    never even called for the last pick.
  void _handleNext(
    int index,
    List<String> masterIds, {
    required bool activeInTimePhase,
  }) {
    if (index < 0 || index >= masterIds.length) return;
    final String masterId = masterIds[index];
    if (!activeInTimePhase) {
      ref.read(salonBookingScheduleProvider.notifier).enterTimePhase(masterId);
      return;
    }
    final int? next = ref
        .read(salonBookingScheduleProvider)
        .nextUnscheduledIndex(masterIds, index);
    if (next != null) _goTo(next, masterIds.length);
  }

  /// Snapshots every scheduled master's picked date/time into concrete
  /// [SalonBookingAppointment]s and pushes the step-4 confirmation screen.
  /// The CTA is only enabled once every master is scheduled, so each
  /// [SalonScheduleEntry] here has a non-null slot — any without one is
  /// defensively skipped rather than force-unwrapped. Each appointment gets a
  /// STABLE idempotency key generated here (once, not on retry) so a later
  /// retry de-duplicates server-side.
  void _confirm(List<SalonMasterSchedule> schedules) {
    final SalonBookingScheduleState schedule = ref.read(
      salonBookingScheduleProvider,
    );
    final List<SalonBookingAppointment> appointments =
        <SalonBookingAppointment>[
          for (final SalonMasterSchedule s in schedules)
            if (schedule.entryFor(s.masterId).slot case final slot?)
              SalonBookingAppointment(
                schedule: s,
                startAt: slot.startAt,
                idempotencyKey: _kUuid.v4(),
              ),
        ];
    if (appointments.isEmpty) return;
    context.push(
      RouteNames.salonBookingConfirm,
      extra: SalonBookingConfirmArgs(
        salonId: widget.args.salonId,
        appointments: appointments,
      ),
    );
  }

  /// Pure predicate — reads (never mutates) whether the ACTIVE slide's
  /// master is past the date pick, i.e. `MasterSchedulePage`'s in-widget
  /// `AnimatedSwitcher` (`master_schedule_page.dart:220-235`) is currently
  /// showing the time-slot grid rather than the calendar. Must stay
  /// side-effect-free — the actual `clearDate` mutation lives in
  /// [_exitActiveMasterTimePhase] instead, called only from
  /// `onPopInvokedWithResult` / the top-bar tap handler below.
  ///
  /// Used ONLY by [_handleTopBarBack] (an event callback, a one-shot
  /// `ref.read` is correct there). `PopScope.canPop` does NOT call this —
  /// it has its own scoped `ref.watch(...select(...))` inline in the
  /// `Consumer` wrapping it at the bottom of `build()`, so that the ACTIVE
  /// slide's date-phase flip only rebuilds `PopScope`, never the outer
  /// `build()` / the `Scaffold` subtree below it. See that `Consumer`'s
  /// comment for why duplicating the read (rather than reusing this method
  /// from inside `ref.watch`) is the point, not an oversight.
  bool _activeMasterIsInTimePhase() {
    if (_current < 0 || _current >= _masterIds.length) return false;
    final String masterId = _masterIds[_current];
    return ref
        .read(salonBookingScheduleProvider)
        .entryFor(masterId)
        .viewingTime;
  }

  /// The mutating half of the split above — clears the ACTIVE slide's date
  /// (and therefore its slot, per `SalonScheduleEntry`'s contract), which
  /// returns that ONE master's `MasterSchedulePage` to its date/calendar
  /// phase. Reuses `salonBookingScheduleProvider.clearDate` verbatim — the
  /// SAME notifier method `MasterSchedulePage`'s own `_clearDate()` already
  /// wraps for its left-edge swipe-back gesture and `_NoSlotsEmptyState`
  /// (`master_schedule_page.dart:167-169`) — so no other master's entry, and
  /// no pager position (`_current`), is ever touched.
  void _exitActiveMasterTimePhase() {
    if (_current < 0 || _current >= _masterIds.length) return;
    ref
        .read(salonBookingScheduleProvider.notifier)
        .clearDate(_masterIds[_current]);
  }

  /// The in-app ‹ arrow's tap handler (`_TopBar.onBack`) — routes through
  /// the SAME predicate/mutation split as the `PopScope` in `build()` below,
  /// mirroring `SalonBookingConfirmScreen._onBack`'s identical "check a
  /// predicate, either handle locally or `context.pop()`" shape — so both
  /// back affordances (system gesture and in-app arrow) stay behaviourally
  /// identical.
  void _handleTopBarBack() {
    if (_activeMasterIsInTimePhase()) {
      _exitActiveMasterTimePhase();
      return;
    }
    context.pop();
  }

  /// Shared `select` predicate for "is the ACTIVE slide in its time phase" —
  /// used by every narrow `Consumer` below that needs this fresh on every
  /// date/`clearDate` pick WITHOUT the outer `build()` rerunning: the
  /// `PopScope` `canPop` `Consumer` and the top-bar back-label `Consumer`.
  /// Takes `current`/`masterIds` as parameters rather than closing over the
  /// State fields directly — each call site reads `_current`/`_masterIds`
  /// fresh into locals inside its OWN `Consumer.builder` first (mirroring
  /// the pre-existing "bounds-guarded inline" pattern), so this stays a pure
  /// function shared by both without either depending on the other's
  /// rebuild timing.
  static bool _activeSlideInTimePhase(
    SalonBookingScheduleState s,
    int current,
    List<String> masterIds,
  ) {
    if (current < 0 || current >= masterIds.length) return false;
    return s.entryFor(masterIds[current]).viewingTime;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String salonId = widget.args.salonId;

    final salonAsync = ref.watch(publicSalonProfileProvider(salonId));
    final catalogAsync = ref.watch(salonServiceCatalogProvider(salonId));
    // Per-master `serviceDefId -> assignmentId` coverage (Phase 14.16 bugfix)
    // — needed here (not just on the previous master-selection step) to
    // resolve each schedule's `orderedMasterServiceIds`: the ids the slot-
    // availability endpoint actually requires, distinct from the salon-wide
    // catalog id `SalonCatalogService.id` carries. See
    // `salon_master_schedule.dart`'s file header for the full id-space note.
    // [coverageArgs] rebuilds [SalonBookingMasterSelectionArgs] from this
    // screen's own [SalonBookingTimeArgs] (same salonId/selectedServiceIds
    // carried forward from step 2) — freezed's deep-collection equality means
    // this resolves to the SAME cached family member
    // `SalonMasterSelectionScreen` already populated, not a re-fetch.
    final SalonBookingMasterSelectionArgs coverageArgs =
        SalonBookingMasterSelectionArgs(
          salonId: widget.args.salonId,
          selectedServiceIds: widget.args.selectedServiceIds,
        );
    final coverageAsync = ref.watch(
      salonMasterServiceCoverageProvider(coverageArgs),
    );

    final Object? error =
        salonAsync.error ?? catalogAsync.error ?? coverageAsync.error;
    final PublicSalonProfileData? salonData = salonAsync.value;
    final List<SalonServiceCategoryEntry>? catalog = catalogAsync.value;
    final Map<String, Map<String, String>>? coverage = coverageAsync.value;

    Widget body;
    Widget? bottomBar;

    if (error != null) {
      final Failure failure = error is Failure
          ? error
          : UnknownFailure(cause: error);
      body = SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: 400,
          child: ErrorState(
            key: const Key('salon-time-error-state'),
            failure: failure,
            onRetry: () {
              ref.invalidate(publicSalonProfileProvider(salonId));
              ref.invalidate(salonServiceCatalogProvider(salonId));
              ref.invalidate(salonMasterServiceCoverageProvider(coverageArgs));
            },
          ),
        ),
      );
    } else if (salonData == null || catalog == null || coverage == null) {
      body = const _LoadingBody();
    } else {
      final (_, List<SalonMasterSummary> masters) = salonData;
      final List<SalonCatalogService> allServices = <SalonCatalogService>[
        for (final SalonServiceCategoryEntry c in catalog) ...c.services,
      ];

      final List<SalonMasterSchedule> schedules = <SalonMasterSchedule>[
        for (final MapEntry<String, List<String>> e
            in widget.args.assignedServiceIdsByMaster.entries)
          if (_resolveSchedule(masters, e.key, e.value, allServices, coverage)
              case final SalonMasterSchedule schedule)
            schedule,
      ];

      if (schedules.isEmpty) {
        // Defensive: this route is only reachable via
        // `SalonMasterSelectionScreen`'s "Підтвердити" (which requires every
        // selected service to be assigned to a master first) — reaching it
        // with no resolvable schedules is a broken-flow edge case (e.g. a
        // stale deep link), not a normal path. Mirrors `SlotTimeScreen`'s
        // identical defensive self-pop guard.
        if (!_poppedForMissingSchedule) {
          _poppedForMissingSchedule = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.pop();
          });
        }
        return const Scaffold(body: SizedBox.shrink());
      }

      final List<String> masterIds = <String>[
        for (final SalonMasterSchedule s in schedules) s.masterId,
      ];
      _masterIds = masterIds;

      // Computed once per outer `build()` (never per the `Consumer` below,
      // which only reruns on a `scheduledCount` change) — flattens every
      // assigned master's services back into the client's full original
      // selection (each selected service is assigned to exactly one master,
      // so this recovers the same set `SalonMasterSelectionScreen` started
      // from) and adapts it for the pinned selected-services shelf. Mirrors
      // that screen's identical `shelfServices` precompute.
      final List<MasterService> selectedServices = <MasterService>[
        for (final SalonMasterSchedule s in schedules)
          for (final SalonCatalogService svc in s.services)
            salonServiceForShelf(svc),
      ];

      if (_pager == null) {
        // One-shot seed only — this branch runs at most once (guarded by
        // the null check), the very first time `masterIds` becomes
        // available, to decide which slide the pager opens on.
        // Deliberately `ref.read`, NOT `ref.watch`: watching
        // `salonBookingScheduleProvider` here would re-run this ENTIRE
        // `build()` — and therefore reconstruct the `PageView.builder`
        // below with a brand-new `SliverChildBuilderDelegate` — on every
        // single per-master date/slot pick anywhere in the flow. That was
        // mobile-perf Finding A (HIGH); `_MasterPager`, `ScheduleConfirmBar`,
        // and the `PopScope`-wrapping `Consumer` at the bottom of `build()`
        // all read the schedule state through their own scoped `Consumer`s
        // instead, so this outer `build()` only reruns when
        // `salonData`/`catalog`/`coverage` change — NEVER on a date/slot
        // pick, including a date pick (or `clearDate`) on the ACTIVE slide.
        // (A narrower version of this same watch briefly lived directly in
        // this outer `build()` to keep `PopScope.canPop` fresh — that
        // reopened a slice of Finding A: a date pick on the active slide
        // rebuilt the outer `build()` and therefore the mounted ±1
        // neighbour slides. Hoisted into the `Consumer` below instead.)
        final int initialPage =
            ref
                .read(salonBookingScheduleProvider)
                .nextUnscheduledIndex(masterIds, -1) ??
            0;
        _pager = PageController(initialPage: initialPage);
        _current = initialPage;
      }
      if (_current >= masterIds.length) _current = masterIds.length - 1;

      body = Column(
        children: <Widget>[
          Padding(
            // Tightened top/bottom insets (was xs/sm) to lower this pager
            // block's overall height so the per-master slide gets more of the
            // viewport.
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.lg,
              0,
              VelvetSpacing.lg,
              VelvetSpacing.xs,
            ),
            child: Consumer(
              builder: (BuildContext context, WidgetRef ref, Widget? child) {
                // mobile-perf Finding 2 (LOW, 14.16/14.17 re-audit): a
                // `List<bool>` has reference equality only, so `select`
                // could never treat two evaluations as equal — this
                // `Consumer` rebuilt on every `salonBookingScheduleProvider`
                // mutation regardless of whether the scheduled-set actually
                // changed. Pack the flags into a single `int` bitmask
                // instead — `int` has correct value equality, so `select`
                // now genuinely memoizes.
                final int scheduledMask = ref.watch(
                  salonBookingScheduleProvider.select((
                    SalonBookingScheduleState s,
                  ) {
                    int mask = 0;
                    for (int i = 0; i < masterIds.length; i++) {
                      if (s.isScheduled(masterIds[i])) mask |= 1 << i;
                    }
                    return mask;
                  }),
                );
                return _MasterPager(
                  count: masterIds.length,
                  current: _current,
                  isScheduled: (int i) => (scheduledMask & (1 << i)) != 0,
                  onPrev: _current > 0
                      ? () => _goTo(_current - 1, masterIds.length)
                      : null,
                  onNext: _current < masterIds.length - 1
                      ? () => _goTo(_current + 1, masterIds.length)
                      : null,
                  onJump: (int i) => _goTo(i, masterIds.length),
                );
              },
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pager,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (int i) => setState(() => _current = i),
              itemCount: schedules.length,
              itemBuilder: (BuildContext context, int i) {
                final SalonMasterSchedule schedule = schedules[i];
                return MasterSchedulePage(
                  key: ValueKey<String>(
                    'salon-schedule-page-${schedule.masterId}',
                  ),
                  schedule: schedule,
                  avatarGradient: salonAvatarGradient(i),
                  // `onCompleted` is deliberately NOT passed — forward
                  // navigation is CTA-driven now (`_handleNext`, wired below
                  // via `ScheduleConfirmBar.onNext`), never triggered by a
                  // date/slot tap inside the slide itself. See
                  // `MasterSchedulePage.onCompleted`'s own doc comment.
                  // mobile-perf Finding B (MEDIUM): bound
                  // `AutomaticKeepAliveClientMixin` retention to the active
                  // slide and its immediate neighbours instead of keeping
                  // every visited master's State (and its
                  // `workingDaysProvider`/`salonMasterDaySlotsProvider`
                  // subscriptions) alive for the whole screen session.
                  keepAlive: (i - _current).abs() <= 1,
                );
              },
            ),
          ),
        ],
      );

      // Scoped `Consumer` (mirrors `_MasterPager`'s rationale above): the CTA
      // must react to BOTH the aggregate `scheduledCount` AND the ACTIVE
      // slide's own phase/selection — a date pick, a slot pick, or an
      // `enterTimePhase` commit on the CURRENT master only — without the
      // outer `build()` re-running (mobile-perf Finding A). `select` returns
      // a record (Dart 3 records have value equality), so this only rebuilds
      // when one of those four values actually changes.
      bottomBar = Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? child) {
          final int current = _current;
          final List<String> ids = masterIds;
          final (
            int scheduledCount,
            bool activeViewingTime,
            bool activeHasDate,
            bool activeHasSlot,
          ) = ref.watch(
            salonBookingScheduleProvider.select((SalonBookingScheduleState s) {
              final int count = s.scheduledCount(ids);
              if (current < 0 || current >= ids.length) {
                return (count, false, false, false);
              }
              final SalonScheduleEntry e = s.entryFor(ids[current]);
              return (count, e.viewingTime, e.date != null, e.slot != null);
            }),
          );
          // DATE phase: a picked day is enough to advance to TIME.
          // TIME phase: a picked slot is enough to advance to the next
          // unscheduled master (or confirm — `ScheduleConfirmBar` handles
          // that branch itself once `scheduledCount == totalCount`).
          final bool nextEnabled = activeViewingTime
              ? activeHasSlot
              : activeHasDate;
          return ScheduleConfirmBar(
            schedules: schedules,
            selectedServices: selectedServices,
            scheduledCount: scheduledCount,
            totalCount: masterIds.length,
            onConfirm: () => _confirm(schedules),
            onNext: () =>
                _handleNext(current, ids, activeInTimePhase: activeViewingTime),
            nextEnabled: nextEnabled,
          );
        },
      );
    }

    // `PopScope` is wrapped in its OWN scoped `Consumer` — mirroring the
    // `_MasterPager`/`ScheduleConfirmBar` pattern above — rather than reading
    // the ACTIVE slide's date phase via `ref.watch` directly in this outer
    // `build()`. `canPop` still needs to be fresh on every date/`clearDate`
    // pick (else it silently reintroduces the "back pops past a live
    // time-phase slide" bug this screen exists to fix), but this outer
    // `build()` must NOT rerun for that — per the mobile-perf Finding A note
    // above, rerunning it reconstructs `PageView.builder`'s
    // `SliverChildBuilderDelegate` and rebuilds the mounted ±1 neighbour
    // slides. So the `select` bool lives in a `Consumer` whose `builder`
    // returns ONLY `PopScope`; everything else — the whole `Scaffold`,
    // including the `PageView`, `_TopBar`, and the pinned `bottomBar`
    // (`SelectedServicesShelf`) — is passed through as `child`, built ONCE
    // by this outer `build()` and reused untouched across the `Consumer`'s
    // internal rebuilds (same "child param bypasses the rebuilt subtree"
    // contract `AnimatedBuilder`/`ValueListenableBuilder` use). A date pick
    // on the active slide therefore only rebuilds `PopScope` itself now —
    // nothing under `child`.
    //
    // Bounds-guarded inline via the shared [_activeSlideInTimePhase]
    // predicate (mirrors `_activeMasterIsInTimePhase()`'s own
    // `_current`/`_masterIds` guard) rather than reusing that method here:
    // that method does a one-shot `ref.read` correct for an event callback
    // (`_handleTopBarBack`), but `canPop` needs a build-time `ref.watch` —
    // this `Consumer` and the top-bar back-label `Consumer` inside `child`
    // below are the ONLY two places that watch may live without reopening
    // Finding A (each is independently scoped, so neither's rebuild
    // triggers the other's, nor the outer `build()`'s).
    return Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? child) {
        final int current = _current;
        final List<String> masterIds = _masterIds;
        final bool inTimePhase = ref.watch(
          salonBookingScheduleProvider.select(
            (SalonBookingScheduleState s) =>
                _activeSlideInTimePhase(s, current, masterIds),
          ),
        );
        return PopScope(
          // System back gesture / hardware back: while the ACTIVE slide is
          // in its time-slot phase, block the real pop and step that ONE
          // master back to its date/calendar phase instead
          // (`_exitActiveMasterTimePhase`) — otherwise allow a normal pop
          // out to master-selection. Mirrors the `canPop` +
          // `onPopInvokedWithResult` shape of `SalonBookingConfirmScreen`'s
          // `PopScope` (`salon_booking_confirm_screen.dart:227-235`), and
          // `BookingSuccessScaffold`'s `PopScope(canPop: false, ...)`
          // (`booking_success_scaffold.dart:173-174`) for the "stay mounted
          // on a blocked pop" precedent — this widget's `dispose()` only
          // fires on a real, allowed pop (`didPop == true`), never on the
          // handled case below, so `ScreenProtectionManager.release()` and
          // the pinned `SelectedServicesShelf` (via `bottomBar`, inside
          // `child`) are unaffected by a blocked back press.
          canPop: !inTimePhase,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (!didPop) _exitActiveMasterTimePhase();
          },
          child: child!,
        );
      },
      child: Scaffold(
        backgroundColor: BrandColors.base,
        bottomNavigationBar: bottomBar,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              // Own scoped `Consumer` — same rationale as the `PopScope`
              // one above, and independent of it: the back arrow's
              // semantic label must flip the moment the ACTIVE slide
              // enters/exits its time phase (see [_activeSlideInTimePhase]
              // and the HIGH finding this fixes — the label used to be a
              // STATIC "back to master selection" string that lied once
              // the arrow started returning to the calendar instead), but
              // `_TopBar` sits inside this outer `build()`'s `child:` —
              // built ONCE and reused across the `PopScope` `Consumer`'s
              // own rebuilds — so its label can only be kept fresh by
              // watching the schedule state through its OWN `Consumer`
              // here, never by the outer `build()` watching it directly
              // (that would reopen Finding A — see the `PopScope`
              // `Consumer`'s comment above `build()`).
              Consumer(
                builder: (BuildContext context, WidgetRef ref, Widget? child) {
                  final int current = _current;
                  final List<String> masterIds = _masterIds;
                  final bool inTimePhase = ref.watch(
                    salonBookingScheduleProvider.select(
                      (SalonBookingScheduleState s) =>
                          _activeSlideInTimePhase(s, current, masterIds),
                    ),
                  );
                  return _TopBar(
                    title: l10n.salonBookingTimeTitle,
                    backSemantics: inTimePhase
                        ? l10n.salonBookingTimeBackToCalendarSemantics
                        : l10n.salonBookingTimeBackSemantics,
                    onBack: _handleTopBarBack,
                  );
                },
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }

  /// Resolves [masterId]'s [SalonMasterSchedule], or `null` if either the
  /// master itself isn't in [masters] (a stale roster — defensive, mirrors
  /// the pre-existing guard this replaced) or ANY of its assigned services'
  /// assignment ids can't be resolved from [coverage] (a data-consistency
  /// edge case: the bookable-masters read for that service no longer lists
  /// this master — e.g. they deactivated the assignment, or lost their
  /// usable schedule, a step ago). Dropping just the one broken schedule —
  /// logged, never thrown — mirrors `SalonPortfolioMapper.fromDtoList`'s "one
  /// broken entry must not blank the whole list" precedent elsewhere in this
  /// codebase. A partially-resolved [orderedMasterServiceIds] (some services
  /// resolved, others not) is refused outright rather than silently trimmed
  /// — trimming it would resolve to the SAME single-service drop-defect this
  /// list was introduced to remove (see `salon_master_schedule.dart`'s file
  /// header, D1).
  ///
  /// [coverage] is [salonMasterServiceCoverageProvider]'s
  /// `masterId -> {serviceDefId: assignmentId}` map — the SAME bookable-
  /// masters read `SalonMasterSelectionScreen` already fetches for this
  /// exact `(salonId, selectedServiceIds)` pair, reused here rather than
  /// re-fetched (see `salon_master_coverage_notifier.dart`'s file header).
  SalonMasterSchedule? _resolveSchedule(
    List<SalonMasterSummary> masters,
    String masterId,
    List<String> serviceIds,
    List<SalonCatalogService> allServices,
    Map<String, Map<String, String>> coverage,
  ) {
    SalonMasterSummary? master;
    for (final SalonMasterSummary m in masters) {
      if (m.masterId == masterId) {
        master = m;
        break;
      }
    }
    if (master == null) return null;

    final List<SalonCatalogService> services = <SalonCatalogService>[
      for (final String id in serviceIds)
        if (allServices.where((SalonCatalogService s) => s.id == id).isNotEmpty)
          allServices.firstWhere((SalonCatalogService s) => s.id == id),
    ];
    // Defensive: `assignedServiceIdsByMaster` only ever carries masters with
    // ≥1 assigned service (see `salon_master_schedule.dart`'s file header),
    // so this should never actually be empty — guarded anyway rather than
    // asserting, since `services.first` below would otherwise throw.
    if (services.isEmpty) return null;

    // Resolve EVERY assigned service's own assignment id, in the SAME order
    // as [services] — the chained-visit order `orderedMasterServiceIds` must
    // preserve (D5). Any single unresolved entry drops the whole schedule
    // (see this method's doc comment) rather than silently trimming down to
    // the ones that DID resolve.
    final Map<String, String>? masterCoverage = coverage[master.masterId];
    final List<String> assignmentIds = <String>[];
    for (final SalonCatalogService s in services) {
      final String? assignmentId = masterCoverage?[s.id];
      if (assignmentId == null) {
        log(
          'Could not resolve a master-service assignment id for '
          'masterId=$masterId, catalogServiceId=${s.id} — '
          "dropping this master's schedule slide.",
          name: 'feature.booking.salon_time',
          level: 900,
        );
        return null;
      }
      assignmentIds.add(assignmentId);
    }

    return SalonMasterSchedule(
      masterId: master.masterId,
      firstName: master.firstName,
      lastName: master.lastName,
      type: master.type,
      professionalTitle: master.professionalTitle,
      // Normalized here (once) rather than at each card: an unrated master is
      // `avgRating == null` downstream, which is exactly the em-dash branch
      // `MasterStrip` renders. Guards the (contract-wise impossible, but
      // cheap to rule out) case of a stale non-null rating on a zero-review
      // roster entry.
      avgRating: master.reviewCount > 0 ? master.avgRating : null,
      reviewCount: master.reviewCount,
      services: services,
      orderedMasterServiceIds: assignmentIds,
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar + step indicator (mirrors SalonMasterSelectionScreen's copy)
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.backSemantics,
    required this.onBack,
  });

  final String title;
  final String backSemantics;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.md,
        VelvetSpacing.lg,
        VelvetSpacing.sm,
      ),
      child: SizedBox(
        height: 56,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: NeumorphicIconButton(
                key: const Key('salon-time-back'),
                icon: Icons.arrow_back_ios_new_rounded,
                semanticLabel: backSemantics,
                onTap: onBack,
              ),
            ),
            Text(
              title,
              style: VelvetText.subheading(),
              textAlign: TextAlign.center,
            ),
            const Align(
              alignment: Alignment.centerRight,
              child: _StepIndicator(current: 3, total: 4),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.salonBookingStepLabel(current, total),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.sm + 2,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: BrandColors.base,
              borderRadius: BorderRadius.circular(VelvetRadii.pill),
              boxShadow: VelvetShadows.extrudedSmall,
            ),
            child: Text(
              l10n.salonBookingStepLabel(current, total),
              style: VelvetText.stepPillLabel,
            ),
          ),
          const SizedBox(height: VelvetSpacing.sm),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int i = 1; i <= total; i++) ...<Widget>[
                Container(
                  height: 4,
                  width: i == current ? 20 : 12,
                  decoration: BoxDecoration(
                    color: i <= current
                        ? BrandColors.accent
                        : BrandColors.faint.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(VelvetRadii.pill),
                  ),
                ),
                if (i < total) const SizedBox(width: 4),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading state
// ---------------------------------------------------------------------------

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmerScope(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          VelvetSpacing.lg,
          VelvetSpacing.md,
          VelvetSpacing.lg,
          VelvetSpacing.lg,
        ),
        children: const <Widget>[
          SkeletonBlock(
            width: double.infinity,
            height: 96,
            radius: VelvetRadii.card,
          ),
          SizedBox(height: VelvetSpacing.md),
          SkeletonBlock(
            width: double.infinity,
            height: 320,
            radius: VelvetRadii.card,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slider position indicator — ‹ › arrows + per-master dots + counter.
// ---------------------------------------------------------------------------

class _MasterPager extends StatelessWidget {
  const _MasterPager({
    required this.count,
    required this.current,
    required this.isScheduled,
    required this.onPrev,
    required this.onNext,
    required this.onJump,
  });

  final int count;
  final int current;
  final bool Function(int) isScheduled;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final int doneCount = List<int>.generate(
      count,
      (int i) => i,
    ).where(isScheduled).length;
    return Semantics(
      label: l10n.salonSchedulePagerSemantics(current + 1, count, doneCount),
      child: Row(
        children: <Widget>[
          _PagerArrow(
            icon: Icons.chevron_left_rounded,
            semanticLabel: l10n.salonSchedulePagerPrevSemantics,
            onTap: onPrev,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    for (int i = 0; i < count; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _PagerDot(
                          key: Key('salon-time-pager-dot-$i'),
                          current: i == current,
                          done: isScheduled(i),
                          semanticLabel: isScheduled(i)
                              ? l10n.salonSchedulePagerDotDoneLabel(i + 1)
                              : l10n.salonSchedulePagerDotLabel(i + 1),
                          onTap: () => onJump(i),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: VelvetSpacing.xs),
                Text(
                  l10n.salonSchedulePagerCounterLabel(current + 1, count),
                  style: VelvetText.schedulePagerCounter,
                ),
              ],
            ),
          ),
          _PagerArrow(
            icon: Icons.chevron_right_rounded,
            semanticLabel: l10n.salonSchedulePagerNextSemantics,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

class _PagerDot extends StatelessWidget {
  const _PagerDot({
    super.key,
    required this.current,
    required this.done,
    required this.semanticLabel,
    required this.onTap,
  });

  final bool current;
  final bool done;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget dot = AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      height: 10,
      width: current ? 26 : 10,
      decoration: BoxDecoration(
        gradient: done
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  BrandColors.accentLatte,
                  BrandColors.accentDeep,
                ],
              )
            : null,
        color: done
            ? null
            : current
            ? BrandColors.accent
            : BrandColors.faint.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: done && !current
          ? const Icon(Icons.check_rounded, size: 8, color: BrandColors.white)
          : null,
    );
    return Semantics(
      button: true,
      selected: current,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          // Slimmed from 6 to trim the pager block height (see the
          // _MasterPager Padding note above).
          padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.xs),
          child: dot,
        ),
      ),
    );
  }
}

class _PagerArrow extends StatefulWidget {
  const _PagerArrow({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  State<_PagerArrow> createState() => _PagerArrowState();
}

class _PagerArrowState extends State<_PagerArrow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null;
    final Color glyph = enabled ? BrandColors.accentDeep : BrandColors.faint;

    final Widget face = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 40,
      width: 40,
      decoration: BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.circular(VelvetRadii.field),
        boxShadow: (!enabled || _pressed) ? null : VelvetShadows.extrudedSmall,
      ),
      child: Icon(widget.icon, color: glyph, size: 24),
    );

    if (!enabled) {
      return Semantics(
        button: true,
        enabled: false,
        label: widget.semanticLabel,
        child: Opacity(opacity: 0.55, child: face),
      );
    }
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap!();
        },
        child: face,
      ),
    );
  }
}
