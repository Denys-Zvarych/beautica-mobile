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
// per individual service). Completing a master's date+time auto-advances the
// slider to the next unscheduled master; «Підтвердити» enables only once
// EVERY slide has both a date and a time.
//
// NO `POST /bookings` CALL IN THIS SCREEN: «Підтвердити» (Phase 14.18) is
// PURE FORWARD NAVIGATION — it snapshots every scheduled master's picked
// date/time into concrete `SalonBookingAppointment`s (each with a stable
// idempotency key) and pushes `RouteNames.salonBookingConfirm`, where the
// actual N-booking submit runs (`SalonBookingConfirmScreen` →
// `SalonBookingSubmit`, one `POST /bookings` per master). The booking-write
// lives OFF this screen so the step-3 picker stays a pure local-state editor;
// see `salon_booking_schedule_notifier.dart`'s header for the per-master
// (one appointment per master, primary-service) model.

import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
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

  @override
  void dispose() {
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

  void _handleCompleted(int index, List<String> masterIds) {
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String salonId = widget.args.salonId;

    final salonAsync = ref.watch(publicSalonProfileProvider(salonId));
    final catalogAsync = ref.watch(salonServiceCatalogProvider(salonId));
    // Per-master `serviceDefId -> assignmentId` coverage (Phase 14.16 bugfix)
    // — needed here (not just on the previous master-selection step) to
    // resolve each schedule's `primaryServiceAssignmentId`: the id the slot-
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

      if (_pager == null) {
        // One-shot seed only — this branch runs at most once (guarded by
        // the null check), the very first time `masterIds` becomes
        // available, to decide which slide the pager opens on.
        // Deliberately `ref.read`, NOT `ref.watch`: watching
        // `salonBookingScheduleProvider` here would re-run this ENTIRE
        // `build()` — and therefore reconstruct the `PageView.builder`
        // below with a brand-new `SliverChildBuilderDelegate` — on every
        // single per-master date/slot pick anywhere in the flow. That was
        // mobile-perf Finding A (HIGH); `_MasterPager` and
        // `ScheduleConfirmBar` below now read the schedule state through
        // their own scoped `Consumer`s instead, so this outer `build()`
        // only reruns when `salonData`/`catalog` change.
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
                  onCompleted: () => _handleCompleted(i, masterIds),
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

      bottomBar = Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? child) {
          final int scheduledCount = ref.watch(
            salonBookingScheduleProvider.select(
              (SalonBookingScheduleState s) => s.scheduledCount(masterIds),
            ),
          );
          return ScheduleConfirmBar(
            schedules: schedules,
            scheduledCount: scheduledCount,
            totalCount: masterIds.length,
            onConfirm: () => _confirm(schedules),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: BrandColors.base,
      bottomNavigationBar: bottomBar,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _TopBar(
              title: l10n.salonBookingTimeTitle,
              backSemantics: l10n.salonBookingTimeBackSemantics,
              onBack: () => context.pop(),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  /// Resolves [masterId]'s [SalonMasterSchedule], or `null` if either the
  /// master itself isn't in [masters] (a stale roster — defensive, mirrors
  /// the pre-existing guard this replaced) or its `primaryServiceAssignmentId`
  /// can't be resolved from [coverage] (a data-consistency edge case: the
  /// bookable-masters read for the service no longer lists this master —
  /// e.g. they deactivated the assignment, or lost their usable schedule,
  /// a step ago). Dropping just the one broken schedule — logged, never
  /// thrown — mirrors `SalonPortfolioMapper.fromDtoList`'s "one broken entry
  /// must not blank the whole list" precedent elsewhere in this codebase.
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

    final String? assignmentId = coverage[master.masterId]?[services.first.id];
    if (assignmentId == null) {
      log(
        'Could not resolve a master-service assignment id for '
        'masterId=$masterId, catalogServiceId=${services.first.id} — '
        "dropping this master's schedule slide.",
        name: 'feature.booking.salon_time',
        level: 900,
      );
      return null;
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
      primaryServiceAssignmentId: assignmentId,
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
