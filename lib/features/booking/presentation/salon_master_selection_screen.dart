// Phase 14.13 — SalonMasterSelectionScreen: salon booking flow step 2 of 3
// (services → masters → coming-soon placeholder for the deferred time step).
//
// After selecting services (Phase 14.12, `SalonServiceSelectionScreen`), the
// CLIENT sees only the masters who perform ≥1 of the selected services and
// assigns exactly one master per selected service — auto-attached when only
// one candidate performs it, tap-to-choose when several can. This is the
// last implemented step for now: step 3 (per-master time picker,
// `docs/signup-designs/SalonBookingTime/`) stays deferred — "Підтвердити"
// routes to `SalonBookingComingSoonScreen`, never the independent-master
// `SlotPickerScreen` (that flow assumes one master, not the salon's
// N-appointments-per-master model).
//
// DESIGN SOURCE: approved preview at
// `docs/signup-designs/SalonBookingMasters/lib/screens/salon_masters_screen.dart`
// (2026-06-30). Transcribed 1:1: the multi-select master rows (camel "Виконує:
// …" sub-line), the live per-master grouped preview + contested-service
// resolver chips, and the pinned assign-confirm bar. Explicitly NO "Будь-який
// вільний майстер" auto-assign option anywhere on this screen — excluded per
// the approved design. The preview's `_Service.short` label (a hand-curated
// short category word distinct from the full service name) has no real-data
// equivalent, so the full [SalonCatalogService.name] is used everywhere the
// preview used `short` — every text that reads it wraps/ellipsises, so this
// is a display-only simplification, not a behavior change. The staggered
// fade-up entrance choreography is intentionally NOT ported, mirroring
// `ServiceSelectorSheet`'s (Phase 14.1) and `SalonServiceSelectionScreen`'s
// (Phase 14.12) own documented decision to skip it.
//
// DATA — per-master service coverage gap
// -----------------------------------------
// Neither existing salon read carries master↔service coverage:
// [SalonMasterSummary] (the masters rail) has no service list, and
// [SalonCatalogService] (the catalogue) has no master list — a salon service
// can be assigned to several masters. [salonMasterServiceCoverageProvider]
// (Phase 14.13, rewired Phase 23.x onto the dedicated bookable-masters
// endpoint in `salon_master_coverage_notifier.dart`) resolves that mapping
// with one `GET /salons/{salonId}/services/{serviceDefId}/masters` call per
// selected service — see that file's header for the full rationale,
// including why a scheduleless master (the calendar-all-dates-disabled bug)
// can never appear in the resulting map. Master DISPLAY data (name/avatar/
// rating) still comes from [publicSalonProfileProvider]'s roster below —
// the coverage map is purely the eligibility/assignment-id gate.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import '../../salon/application/public_salon_profile_notifier.dart';
import '../../salon/application/salon_service_catalog_notifier.dart';
import '../../salon/domain/salon_master_summary.dart';
import '../../salon/domain/salon_service_catalog.dart';
import '../application/salon_master_coverage_notifier.dart';
import '../domain/salon_booking_args.dart';
import 'widgets/master_strip.dart';

/// Avatar gradients cycled by roster position — the exact palette
/// `SalonMasterCard` (Phase 13.6) uses, kept in sync here since only camel/
/// mocha gradient placeholders exist for master avatars anywhere in the app
/// (no photo pipeline is wired yet).
const List<List<Color>> _kAvatarGradients = <List<Color>>[
  <Color>[Color(0xFFD4B896), Color(0xFF8A6840)],
  <Color>[Color(0xFFB89A7A), Color(0xFF6A4A28)],
  <Color>[Color(0xFFDFC6A8), Color(0xFFB89A7A)],
  <Color>[Color(0xFFC8A878), Color(0xFF6A4A28)],
  <Color>[Color(0xFFCFB090), Color(0xFF8A6840)],
  <Color>[Color(0xFFE0CAAC), Color(0xFFB89A7A)],
];

List<Color> _avatarGradient(int index) =>
    _kAvatarGradients[index % _kAvatarGradients.length];

/// Salon booking flow step 2 — multi-select master assignment, opened by
/// `SalonServiceSelectionScreen`'s "Далі" CTA.
class SalonMasterSelectionScreen extends ConsumerStatefulWidget {
  const SalonMasterSelectionScreen({super.key, required this.args});

  final SalonBookingMasterSelectionArgs args;

  @override
  ConsumerState<SalonMasterSelectionScreen> createState() =>
      _SalonMasterSelectionScreenState();
}

class _SalonMasterSelectionScreenState
    extends ConsumerState<SalonMasterSelectionScreen> {
  // Selection/assignment state lives in a ValueNotifier (not plain fields +
  // top-level setState) so a single master toggle or per-service chip tap
  // notifies only the small subtree that actually cares (the toggled row,
  // the grouping-preview card, the bottom bar) instead of rebuilding the
  // whole screen and re-deriving `_MasterSelectionStatic.eligible` from
  // scratch every tap — mirrors `SalonServiceSelectionScreen`'s
  // `_selectedIdsNotifier` mobile-perf pattern (Phase 14.12; HIGH-2 fix,
  // Phase 14.13 audit).
  final ValueNotifier<_PickState> _pickNotifier = ValueNotifier<_PickState>(
    const _PickState(picked: <String>{}, choice: <String, String>{}),
  );

  @override
  void dispose() {
    _pickNotifier.dispose();
    super.dispose();
  }

  void _toggleMaster(String id) {
    final _PickState current = _pickNotifier.value;
    final Set<String> nextPicked = Set<String>.of(current.picked);
    Map<String, String> nextChoice = current.choice;
    if (nextPicked.remove(id)) {
      nextChoice = Map<String, String>.of(current.choice)
        ..removeWhere((_, String mId) => mId == id);
    } else {
      nextPicked.add(id);
    }
    _pickNotifier.value = _PickState(picked: nextPicked, choice: nextChoice);
  }

  void _choose(String serviceId, String masterId) {
    final _PickState current = _pickNotifier.value;
    _pickNotifier.value = _PickState(
      picked: current.picked,
      choice: Map<String, String>.of(current.choice)..[serviceId] = masterId,
    );
  }

  // Phase 14.16 — retargeted from the `salonBookingComingSoon` placeholder to
  // the real step-3 "Час" screen. Builds the EXACT per-master assignment the
  // client just resolved (including any contested-service resolver-chip
  // choice) — see `SalonBookingTimeArgs`'s file header for why this can't be
  // safely re-derived from `salonMasterServiceCoverageProvider` alone on the
  // next screen.
  void _confirm(
    _MasterSelectionStatic staticModel,
    _MasterSelectionDerived derived,
  ) {
    final Map<String, List<String>> assignments = <String, List<String>>{};
    for (final SalonMasterSummary m in staticModel.eligible) {
      final List<String> ids = staticModel.selected
          .where(
            (SalonCatalogService s) => derived.effective(s.id) == m.masterId,
          )
          .map((SalonCatalogService s) => s.id)
          .toList(growable: false);
      if (ids.isNotEmpty) assignments[m.masterId] = ids;
    }
    context.push(
      RouteNames.salonBookingTime,
      extra: SalonBookingTimeArgs(
        salonId: widget.args.salonId,
        selectedServiceIds: widget.args.selectedServiceIds,
        assignedServiceIdsByMaster: assignments,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String salonId = widget.args.salonId;

    final salonAsync = ref.watch(publicSalonProfileProvider(salonId));
    final catalogAsync = ref.watch(salonServiceCatalogProvider(salonId));
    final coverageAsync = ref.watch(
      salonMasterServiceCoverageProvider(widget.args),
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
            key: const Key('salon-master-selection-error-state'),
            failure: failure,
            onRetry: () {
              ref.invalidate(publicSalonProfileProvider(salonId));
              ref.invalidate(salonServiceCatalogProvider(salonId));
              ref.invalidate(salonMasterServiceCoverageProvider(widget.args));
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
      final List<SalonCatalogService> selected = <SalonCatalogService>[
        for (final String id in widget.args.selectedServiceIds)
          if (allServices
              .where((SalonCatalogService s) => s.id == id)
              .isNotEmpty)
            allServices.firstWhere((SalonCatalogService s) => s.id == id),
      ];

      // Recomputed only when the underlying async data changes (masters /
      // catalog / coverage) — never on a pick/choice toggle, since the O(N ×
      // selected) `eligible` filter + `eligibleIndex` map are built once per
      // data load rather than once per tap.
      final _MasterSelectionStatic staticModel = _MasterSelectionStatic(
        masters: masters,
        selected: selected,
        coverage: coverage,
      );

      body = _Body(
        staticModel: staticModel,
        pickListenable: _pickNotifier,
        onToggleMaster: _toggleMaster,
        onChoose: _choose,
      );

      bottomBar = ValueListenableBuilder<_PickState>(
        valueListenable: _pickNotifier,
        builder: (BuildContext context, _PickState pick, Widget? _) {
          final _MasterSelectionDerived derived = _MasterSelectionDerived(
            staticModel: staticModel,
            pick: pick,
          );
          return _AssignConfirmBar(
            selected: selected,
            assignedCount: derived.assignedCount,
            totalCount: selected.length,
            onNext: derived.allAssigned
                ? () => _confirm(staticModel, derived)
                : null,
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
              title: l10n.salonBookingMastersTitle,
              onBack: () => context.pop(),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Selection state + derived view models — mirrors the approved preview's
// `_SalonMastersScreenState` derivation methods, wired to real data, but
// split into a STATIC half (masters / selected services / coverage — never
// affected by picking) and a PICK-dependent half (picked masters + per-
// service choice). Toggling a master or resolving a contested service only
// ever recomputes the PICK-dependent half inside the small subtree that
// listens to the pick `ValueNotifier` — never the O(N × selected) `eligible`
// filter, and never the 50-row master list (mobile-perf HIGH-2 fix, Phase
// 14.13 audit).
// ---------------------------------------------------------------------------

/// Picked master ids (multi-select) + explicit per-service choice when
/// several picked masters can perform it (serviceId → masterId). Held as one
/// immutable value in a single `ValueNotifier` so a toggle is one atomic
/// update rather than two separate, potentially out-of-sync field mutations.
@immutable
class _PickState {
  const _PickState({required this.picked, required this.choice});

  final Set<String> picked;
  final Map<String, String> choice;
}

/// The half of the screen's derived data that depends only on the loaded
/// masters/selected-services/coverage, not on what the client has picked.
@immutable
class _MasterSelectionStatic {
  _MasterSelectionStatic({
    required this.masters,
    required this.selected,
    required this.coverage,
  }) : eligible = masters
           .where(
             (SalonMasterSummary m) => selected.any(
               (SalonCatalogService s) =>
                   coverage[m.masterId]?.containsKey(s.id) ?? false,
             ),
           )
           .toList(growable: false),
       eligibleIndex = <String, int>{} {
    for (int i = 0; i < eligible.length; i++) {
      eligibleIndex[eligible[i].masterId] = i;
    }
  }

  final List<SalonMasterSummary> masters;
  final List<SalonCatalogService> selected;
  final Map<String, Map<String, String>> coverage;

  /// Masters who perform ≥1 selected service — the only ones rendered.
  final List<SalonMasterSummary> eligible;

  /// masterId → its position in [eligible] — an O(1) avatar-gradient lookup
  /// instead of repeated `eligible.indexOf(m)` inside a loop over [eligible]
  /// (was O(n²) per render pass; LOW fix, Phase 14.13 audit — negligible at
  /// the current 50-master cap, but avoided for headroom).
  final Map<String, int> eligibleIndex;

  SalonMasterSummary? masterById(String id) {
    for (final SalonMasterSummary m in masters) {
      if (m.masterId == id) return m;
    }
    return null;
  }

  /// The selected services this master covers, joined by " · ".
  String coveredLabel(SalonMasterSummary m) => selected
      .where(
        (SalonCatalogService s) =>
            coverage[m.masterId]?.containsKey(s.id) ?? false,
      )
      .map((SalonCatalogService s) => s.name)
      .join(' · ');
}

/// The pick-dependent half — recomputed only inside the subtree that
/// listens to the pick `ValueNotifier` (the grouping-preview card + the
/// bottom assign-confirm bar), never the master-row list itself.
@immutable
class _MasterSelectionDerived {
  const _MasterSelectionDerived({
    required this.staticModel,
    required this.pick,
  });

  final _MasterSelectionStatic staticModel;
  final _PickState pick;

  /// The PICKED eligible masters who can perform [serviceId].
  List<String> candidateIds(String serviceId) => staticModel.eligible
      .where(
        (SalonMasterSummary m) =>
            pick.picked.contains(m.masterId) &&
            (staticModel.coverage[m.masterId]?.containsKey(serviceId) ?? false),
      )
      .map((SalonMasterSummary m) => m.masterId)
      .toList(growable: false);

  /// The master who will perform [serviceId], or null if unresolved.
  String? effective(String serviceId) {
    final List<String> cands = candidateIds(serviceId);
    if (cands.isEmpty) return null;
    final String? chosen = pick.choice[serviceId];
    if (chosen != null && cands.contains(chosen)) return chosen;
    if (cands.length == 1) return cands.first;
    return null;
  }

  int get assignedCount => staticModel.selected
      .where((SalonCatalogService s) => effective(s.id) != null)
      .length;

  bool get allAssigned =>
      pick.picked.isNotEmpty &&
      assignedCount == staticModel.selected.length &&
      staticModel.selected.isNotEmpty;

  /// One group per picked master with ≥1 resolved service.
  List<_MasterGroupVM> get groups {
    final List<_MasterGroupVM> result = <_MasterGroupVM>[];
    for (final SalonMasterSummary m in staticModel.eligible) {
      if (!pick.picked.contains(m.masterId)) continue;
      final List<String> svc = staticModel.selected
          .where((SalonCatalogService s) => effective(s.id) == m.masterId)
          .map((SalonCatalogService s) => s.name)
          .toList();
      if (svc.isEmpty) continue;
      result.add(
        _MasterGroupVM(
          key: m.masterId,
          name: '${m.firstName} ${m.lastName}'.trim(),
          avatarGradient: _avatarGradient(
            staticModel.eligibleIndex[m.masterId] ?? 0,
          ),
          services: svc,
        ),
      );
    }
    return result;
  }

  /// Selected services more than one PICKED master can perform.
  List<_ServiceChoiceVM> get choices {
    final List<_ServiceChoiceVM> list = <_ServiceChoiceVM>[];
    for (final SalonCatalogService s in staticModel.selected) {
      final List<String> cands = candidateIds(s.id);
      if (cands.length < 2) continue;
      list.add(
        _ServiceChoiceVM(
          serviceId: s.id,
          serviceName: s.name,
          candidates: <_MasterChipVM>[
            for (final String id in cands)
              if (staticModel.masterById(id) case final SalonMasterSummary m)
                _MasterChipVM(
                  masterId: id,
                  shortName: '${m.firstName} ${m.lastName}'.trim(),
                  avatarGradient: _avatarGradient(
                    staticModel.eligibleIndex[m.masterId] ?? 0,
                  ),
                ),
          ],
          selectedMasterId: effective(s.id),
        ),
      );
    }
    return list;
  }

  /// Selected services no picked master can perform yet.
  List<String> get uncovered => staticModel.selected
      .where((SalonCatalogService s) => candidateIds(s.id).isEmpty)
      .map((SalonCatalogService s) => s.name)
      .toList();
}

@immutable
class _MasterGroupVM {
  const _MasterGroupVM({
    required this.key,
    required this.name,
    required this.avatarGradient,
    required this.services,
  });

  final String key;
  final String name;
  final List<Color> avatarGradient;
  final List<String> services;
}

@immutable
class _MasterChipVM {
  const _MasterChipVM({
    required this.masterId,
    required this.shortName,
    required this.avatarGradient,
  });

  final String masterId;
  final String shortName;
  final List<Color> avatarGradient;
}

@immutable
class _ServiceChoiceVM {
  const _ServiceChoiceVM({
    required this.serviceId,
    required this.serviceName,
    required this.candidates,
    required this.selectedMasterId,
  });

  final String serviceId;
  final String serviceName;
  final List<_MasterChipVM> candidates;
  final String? selectedMasterId;
}

// ---------------------------------------------------------------------------
// Top bar + step indicator (mirrors SalonServiceSelectionScreen's copy)
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                key: const Key('salon-master-selection-back'),
                icon: Icons.arrow_back_ios_new_rounded,
                semanticLabel: l10n.registerBackStep,
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
              child: _StepIndicator(current: 2, total: 4),
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
              style: VelvetText.bookChipSecW800,
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
            height: 96,
            radius: VelvetRadii.card,
          ),
          SizedBox(height: VelvetSpacing.md),
          SkeletonBlock(
            width: double.infinity,
            height: 140,
            radius: VelvetRadii.card,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — eligible masters list + live grouped preview
// ---------------------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({
    required this.staticModel,
    required this.pickListenable,
    required this.onToggleMaster,
    required this.onChoose,
  });

  final _MasterSelectionStatic staticModel;
  final ValueListenable<_PickState> pickListenable;
  final ValueChanged<String> onToggleMaster;
  final void Function(String serviceId, String masterId) onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (staticModel.eligible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(VelvetSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                height: 88,
                width: 88,
                child: NeumorphicInset(
                  radius: 44,
                  child: Center(
                    child: Icon(
                      Icons.groups_2_outlined,
                      size: 36,
                      color: BrandColors.accent.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: VelvetSpacing.lg),
              Text(
                l10n.salonMastersEmpty,
                key: const Key('salon-master-selection-empty'),
                style: VelvetText.heading20,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // CustomScrollView + SliverList.separated (not a plain `ListView(children:
    // [...])`) so the up-to-`kSalonMastersPageSize` (50) master rows are
    // built lazily — mirrors `SalonServiceSelectionScreen._CatalogueBody`'s
    // identical sliver-list pattern (mobile-perf HIGH-2 fix, Phase 14.13
    // audit).
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.md,
            VelvetSpacing.lg,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(l10n.salonBookingMastersIntro, style: VelvetText.body14),
                const SizedBox(height: VelvetSpacing.lg),
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.groups_2_rounded,
                      size: 16,
                      color: BrandColors.accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.salonBookingMastersSectionLabel,
                      style: VelvetText.sectionLabel(),
                    ),
                    const Spacer(),
                    Text(
                      l10n.salonBookingMastersSectionHint,
                      style: VelvetText.feedbackMutedSm,
                    ),
                  ],
                ),
                const SizedBox(height: VelvetSpacing.sm + 4),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
          sliver: SliverList.separated(
            itemCount: staticModel.eligible.length,
            separatorBuilder: (BuildContext context, int i) =>
                const SizedBox(height: VelvetSpacing.sm + 4),
            itemBuilder: (BuildContext context, int i) {
              final SalonMasterSummary m = staticModel.eligible[i];
              return _MasterPickRowListener(
                key: Key('salon_booking_master_row_${m.masterId}'),
                masterId: m.masterId,
                name: '${m.firstName} ${m.lastName}'.trim(),
                type: m.type,
                professionalTitle: m.professionalTitle,
                // `SalonMasterSummary.avgRating` is null exactly when the
                // master has no reviews; re-assert it here so a stale non-null
                // rating on a zero-review roster entry still reads as "no
                // rating yet" (the card's em-dash branch).
                avgRating: m.reviewCount > 0 ? m.avgRating : null,
                reviewCount: m.reviewCount,
                covered: staticModel.coveredLabel(m),
                avatarGradient: _avatarGradient(
                  staticModel.eligibleIndex[m.masterId] ?? i,
                ),
                pickListenable: pickListenable,
                onTap: () => onToggleMaster(m.masterId),
              );
            },
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
          ),
          sliver: SliverToBoxAdapter(
            // A single listener for the grouping-preview card + the
            // hint text — the pick-dependent half of the derived data
            // (`groups`/`choices`/`uncovered`/`allAssigned`), isolated from
            // the master-row list above it.
            child: ValueListenableBuilder<_PickState>(
              valueListenable: pickListenable,
              builder: (BuildContext context, _PickState pick, Widget? _) {
                final _MasterSelectionDerived derived = _MasterSelectionDerived(
                  staticModel: staticModel,
                  pick: pick,
                );
                return Column(
                  children: <Widget>[
                    _MasterGroupingPreview(
                      groups: derived.groups,
                      choices: derived.choices,
                      uncovered: derived.uncovered,
                      hasPicks: pick.picked.isNotEmpty,
                      onChoose: onChoose,
                    ),
                    const SizedBox(height: VelvetSpacing.sm),
                    Center(
                      child: Text(
                        derived.allAssigned
                            ? l10n.salonBookingAllAssignedHint
                            : l10n.salonBookingPartialAssignedHint,
                        style: VelvetText.feedbackMutedSm,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Listens to the shared pick `ValueNotifier` directly (rather than via a
/// `ValueListenableBuilder` wrapping the whole master list) so toggling one
/// master only rebuilds the ONE row whose `selected` flag actually flipped —
/// mirrors `_CategorySectionState`'s identical listener pattern in
/// `SalonServiceSelectionScreen` (Phase 14.12; HIGH-2 fix, Phase 14.13
/// audit).
class _MasterPickRowListener extends StatefulWidget {
  const _MasterPickRowListener({
    super.key,
    required this.masterId,
    required this.name,
    required this.type,
    required this.professionalTitle,
    required this.avgRating,
    required this.reviewCount,
    required this.covered,
    required this.avatarGradient,
    required this.pickListenable,
    required this.onTap,
  });

  final String masterId;
  final String name;
  final MasterType type;
  final String? professionalTitle;
  final double? avgRating;
  final int reviewCount;

  /// The selected services this master covers, e.g. "Манікюр · Педикюр".
  final String covered;
  final List<Color> avatarGradient;
  final ValueListenable<_PickState> pickListenable;
  final VoidCallback onTap;

  @override
  State<_MasterPickRowListener> createState() => _MasterPickRowListenerState();
}

class _MasterPickRowListenerState extends State<_MasterPickRowListener> {
  late bool _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.pickListenable.value.picked.contains(widget.masterId);
    widget.pickListenable.addListener(_handleChanged);
  }

  @override
  void didUpdateWidget(covariant _MasterPickRowListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pickListenable != widget.pickListenable) {
      oldWidget.pickListenable.removeListener(_handleChanged);
      widget.pickListenable.addListener(_handleChanged);
      _selected = widget.pickListenable.value.picked.contains(widget.masterId);
    }
  }

  @override
  void dispose() {
    widget.pickListenable.removeListener(_handleChanged);
    super.dispose();
  }

  void _handleChanged() {
    final bool next = widget.pickListenable.value.picked.contains(
      widget.masterId,
    );
    if (next == _selected) return;
    setState(() => _selected = next);
  }

  @override
  Widget build(BuildContext context) {
    return _MasterPickRow(
      name: widget.name,
      type: widget.type,
      professionalTitle: widget.professionalTitle,
      avgRating: widget.avgRating,
      reviewCount: widget.reviewCount,
      covered: widget.covered,
      avatarGradient: widget.avatarGradient,
      selected: _selected,
      onTap: widget.onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Master pick row + shared select token
// ---------------------------------------------------------------------------

class _SelectToken extends StatelessWidget {
  const _SelectToken({required this.selected});

  final bool selected;

  static const double _size = 30;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _size,
      width: _size,
      child: selected
          ? AnimatedScale(
              scale: 1,
              duration: const Duration(milliseconds: 260),
              curve: Curves.elasticOut,
              child: Container(
                key: const ValueKey<bool>(true),
                decoration: const BoxDecoration(
                  // Visually a circle, but drawn as an RRect (radius = half the
                  // 30dp side). Impeller-GLES mis-rasterizes a blurred box-shadow
                  // on BoxShape.circle as a hard white square; its RRect blur
                  // path is correct — so shadow-bearing "circles" use RRect.
                  borderRadius: BorderRadius.all(Radius.circular(15)),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      BrandColors.accentLatte,
                      BrandColors.accentDeep,
                    ],
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Color(0xFF8C6A44),
                      offset: Offset(2, 2),
                      blurRadius: 5,
                      spreadRadius: -1,
                    ),
                    BoxShadow(
                      color: BrandColors.shadowLightStrong,
                      offset: Offset(-2, -2),
                      blurRadius: 5,
                      spreadRadius: -1,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: BrandColors.white,
                  ),
                ),
              ),
            )
          : const NeumorphicInset(
              radius: 999,
              child: SizedBox(height: _size, width: _size),
            ),
    );
  }
}

/// One selectable master row: the SHARED [MasterStrip] identity card (the same
/// widget the calendar/time/confirm/success screens render, so a change there
/// lands here too) wrapped in this screen's selection chrome — the tap target,
/// the press-scale, the [_SelectToken] checkbox, and the "covers these
/// services" line beneath the card.
///
/// The card's own surface is fixed (`#EDE4D5`), so — unlike the bespoke row it
/// replaced — selection is no longer signalled by swapping the row's fill;
/// the [_SelectToken] (gradient check vs. empty inset well) carries it.
class _MasterPickRow extends StatefulWidget {
  // No `key` param: this widget is only ever built by
  // `_MasterPickRowListener` (its own key sits on that outer wrapper — the
  // one Widgets/Element/Key needs for identity in the sliver list above).
  const _MasterPickRow({
    required this.name,
    required this.type,
    required this.professionalTitle,
    required this.avgRating,
    required this.reviewCount,
    required this.covered,
    required this.avatarGradient,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final MasterType type;
  final String? professionalTitle;
  final double? avgRating;
  final int reviewCount;

  /// The selected services this master covers, e.g. "Манікюр · Педикюр".
  final String covered;
  final List<Color> avatarGradient;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_MasterPickRow> createState() => _MasterPickRowState();
}

class _MasterPickRowState extends State<_MasterPickRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool sel = widget.selected;
    final String? ownTitle = widget.professionalTitle?.trim();
    // Recomputed here (rather than passed in) purely for the row's semantics
    // label — the card itself derives the very same two strings internally.
    final String role = (ownTitle != null && ownTitle.isNotEmpty)
        ? ownTitle
        : masterRoleLabel(widget.type, l10n);
    final String ratingLabel =
        widget.avgRating?.toStringAsFixed(1) ?? MasterStrip.noRatingLabel;

    return Semantics(
      button: true,
      checked: sel,
      label: l10n.salonMasterPickRowSemantics(
        widget.name,
        role,
        ratingLabel,
        widget.covered,
      ),
      // The row speaks for its whole subtree (identity card + covered line),
      // so the card's own Semantics node is folded away rather than read out
      // a second time after this label.
      child: ExcludeSemantics(
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onTap();
          },
          child: AnimatedScale(
            scale: _pressed ? 0.99 : 1,
            duration: const Duration(milliseconds: 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      // THE shared card — identical widget to the one on the
                      // calendar / time / confirm / success screens. Only the
                      // «Запис до майстра» caption is off: no master has been
                      // picked yet on this screen.
                      child: MasterStrip(
                        name: widget.name,
                        type: widget.type,
                        professionalTitle: widget.professionalTitle,
                        avgRating: widget.avgRating,
                        reviewCount: widget.reviewCount,
                        showLabel: false,
                        showRole: true,
                        showRating: true,
                        avatarGradient: widget.avatarGradient,
                        avatarBordered: true,
                      ),
                    ),
                    const SizedBox(width: VelvetSpacing.sm + 2),
                    _SelectToken(selected: sel),
                  ],
                ),
                const SizedBox(height: VelvetSpacing.sm),
                // Kept OUTSIDE the shared card: which of the picked services
                // this master covers is a property of this screen's selection,
                // not of the master's identity.
                Padding(
                  padding: const EdgeInsets.only(left: VelvetSpacing.sm + 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 13,
                        color: BrandColors.accent,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.covered,
                          style: VelvetText.bookCoveredLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Live per-master grouped preview + contested-service resolver
// ---------------------------------------------------------------------------

class _MasterGroupingPreview extends StatelessWidget {
  const _MasterGroupingPreview({
    required this.groups,
    required this.choices,
    required this.uncovered,
    required this.hasPicks,
    required this.onChoose,
  });

  final List<_MasterGroupVM> groups;
  final List<_ServiceChoiceVM> choices;
  final List<String> uncovered;
  final bool hasPicks;
  final void Function(String serviceId, String masterId) onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NeumorphicCard(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.md + 4,
        VelvetSpacing.md + 2,
        VelvetSpacing.md + 4,
        VelvetSpacing.md + 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.event_note_rounded,
                size: 16,
                color: BrandColors.accent,
              ),
              const SizedBox(width: 6),
              Text(
                l10n.salonBookingGroupingTitle,
                style: VelvetText.sectionLabel(),
              ),
              const Spacer(),
              if (groups.isNotEmpty)
                Text(
                  l10n.salonBookingRecordCount(groups.length),
                  style: VelvetText.feedbackMutedSm,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.salonBookingGroupingSubtitle,
            style: VelvetText.feedbackMutedSm,
          ),
          const SizedBox(height: VelvetSpacing.md),
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !hasPicks
                  ? _EmptyPrompt(l10n: l10n)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (choices.isNotEmpty) ...<Widget>[
                          _MiniLabel(
                            icon: Icons.alt_route_rounded,
                            text: l10n.salonBookingResolverHint,
                          ),
                          const SizedBox(height: VelvetSpacing.sm),
                          for (int i = 0; i < choices.length; i++) ...<Widget>[
                            _ChoiceRow(choice: choices[i], onChoose: onChoose),
                            if (i < choices.length - 1)
                              const SizedBox(height: VelvetSpacing.sm),
                          ],
                          if (groups.isNotEmpty || uncovered.isNotEmpty)
                            const SizedBox(height: VelvetSpacing.md),
                        ],
                        if (groups.isNotEmpty)
                          for (int i = 0; i < groups.length; i++) ...<Widget>[
                            _GroupRow(group: groups[i]),
                            if (i < groups.length - 1)
                              const SizedBox(height: VelvetSpacing.sm + 4),
                          ],
                        if (uncovered.isNotEmpty) ...<Widget>[
                          if (groups.isNotEmpty)
                            const SizedBox(height: VelvetSpacing.md),
                          for (
                            int i = 0;
                            i < uncovered.length;
                            i++
                          ) ...<Widget>[
                            _UncoveredRow(service: uncovered[i]),
                            if (i < uncovered.length - 1)
                              const SizedBox(height: VelvetSpacing.sm),
                          ],
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPrompt extends StatelessWidget {
  const _EmptyPrompt({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return NeumorphicInset(
      radius: VelvetRadii.field,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.md,
          vertical: VelvetSpacing.md - 2,
        ),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.groups_2_outlined,
              size: 18,
              color: BrandColors.placeholder,
            ),
            const SizedBox(width: VelvetSpacing.sm),
            Flexible(
              child: Text(
                l10n.salonBookingGroupingEmptyPrompt,
                style: VelvetText.bookFeedbackPlaceholder125,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group});

  final _MasterGroupVM group;

  @override
  Widget build(BuildContext context) {
    final String services = group.services.join(', ');
    return Semantics(
      label: '${group.name}: $services',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              // RRect (radius = half the 40dp side) reads as a circle but avoids
              // Impeller-GLES's broken circle box-shadow blur path.
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: group.avatarGradient,
              ),
              boxShadow: VelvetShadows.borderedCard,
              border: Border.all(
                color: BrandColors.white.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Icon(
                Icons.person_rounded,
                size: 20,
                color: BrandColors.white.withValues(alpha: 0.85),
              ),
            ),
          ),
          const SizedBox(width: VelvetSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  group.name,
                  style: VelvetText.bookGroupName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(services, style: VelvetText.bookFeedbackSec125),
              ],
            ),
          ),
          const SizedBox(width: VelvetSpacing.sm),
          const NeumorphicInset(
            radius: 999,
            child: SizedBox(
              height: 30,
              width: 30,
              child: Center(
                child: Icon(
                  Icons.schedule_rounded,
                  size: 16,
                  color: BrandColors.accentDeep,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.choice, required this.onChoose});

  final _ServiceChoiceVM choice;
  final void Function(String serviceId, String masterId) onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool unresolved = choice.selectedMasterId == null;
    return NeumorphicInset(
      radius: VelvetRadii.field,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.md,
          vertical: VelvetSpacing.sm + 4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  unresolved
                      ? Icons.help_outline_rounded
                      : Icons.task_alt_rounded,
                  size: 15,
                  color: unresolved
                      ? BrandColors.accentDeep
                      : BrandColors.success,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    choice.serviceName,
                    style: VelvetText.bodyStrong135,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (unresolved)
                  Text(
                    l10n.salonBookingChooseMasterHint,
                    style: VelvetText.bookFeedbackPlaceholder115,
                  ),
              ],
            ),
            const SizedBox(height: VelvetSpacing.sm),
            Wrap(
              spacing: VelvetSpacing.sm,
              runSpacing: VelvetSpacing.sm,
              children: <Widget>[
                for (final _MasterChipVM c in choice.candidates)
                  _CandidateChip(
                    key: Key(
                      'salon_booking_candidate_chip_${choice.serviceId}_${c.masterId}',
                    ),
                    chip: c,
                    selected: choice.selectedMasterId == c.masterId,
                    onTap: () => onChoose(choice.serviceId, c.masterId),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateChip extends StatelessWidget {
  const _CandidateChip({
    super.key,
    required this.chip,
    required this.selected,
    required this.onTap,
  });

  final _MasterChipVM chip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: selected,
      label: chip.shortName,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.xs + 2,
            VelvetSpacing.xs + 1,
            VelvetSpacing.sm + 4,
            VelvetSpacing.xs + 1,
          ),
          decoration: BoxDecoration(
            color: selected ? null : BrandColors.base,
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      BrandColors.accentLatte,
                      BrandColors.accentDeep,
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(VelvetRadii.pill),
            boxShadow: VelvetShadows.extrudedSmall,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                height: 22,
                width: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: chip.avatarGradient,
                  ),
                  border: Border.all(
                    color: BrandColors.white.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: BrandColors.white,
                        )
                      : Icon(
                          Icons.person_rounded,
                          size: 12,
                          color: BrandColors.white.withValues(alpha: 0.85),
                        ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                chip.shortName,
                style: VelvetText.bookFeedback125w800.copyWith(
                  color: selected
                      ? BrandColors.white
                      : BrandColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UncoveredRow extends StatelessWidget {
  const _UncoveredRow({required this.service});

  final String service;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.salonBookingUncoveredSemantics(service),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: BrandColors.error,
          ),
          const SizedBox(width: VelvetSpacing.sm),
          Expanded(
            child: Text(
              l10n.salonBookingUncoveredSemantics(service),
              style: VelvetText.bookFeedbackSec125,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniLabel extends StatelessWidget {
  const _MiniLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 15, color: BrandColors.accent),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: VelvetText.bookFeedback125w800.copyWith(
              color: BrandColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pinned assign-confirm bar
// ---------------------------------------------------------------------------

class _AssignConfirmBar extends StatelessWidget {
  const _AssignConfirmBar({
    required this.selected,
    required this.assignedCount,
    required this.totalCount,
    required this.onNext,
  });

  final List<SalonCatalogService> selected;
  final int assignedCount;
  final int totalCount;
  final VoidCallback? onNext;

  static const Color _shelfSurface = Color(0xFFEDE4D5);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (double minSum, double maxSum, int minutes) = _totals(selected);
    final String price = minSum == maxSum
        ? '${minSum.toStringAsFixed(0)} грн'
        : '${minSum.toStringAsFixed(0)}–${maxSum.toStringAsFixed(0)} грн';
    final String? duration = minutes > 0
        ? DurationMinutes.format(minutes)
        : null;

    return Container(
      decoration: const BoxDecoration(
        color: _shelfSurface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(VelvetRadii.card),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: BrandColors.shadowDarkCard,
            offset: Offset(0, -9),
            blurRadius: 24,
          ),
          BoxShadow(
            color: BrandColors.shadowLightStrong,
            offset: Offset(0, -1),
            blurRadius: 3,
            spreadRadius: -1,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Semantics(
                label: '${l10n.bookingTotalLabel} ${duration ?? ''} $price',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      l10n.bookingTotalLabel,
                      style: VelvetText.bodyStrong(),
                    ),
                    if (duration != null) ...<Widget>[
                      const SizedBox(width: VelvetSpacing.sm),
                      Text(duration, style: VelvetText.feedbackMutedSm),
                    ],
                    const Spacer(),
                    Text(price, style: VelvetText.bookPriceLg),
                  ],
                ),
              ),
              const SizedBox(height: VelvetSpacing.md),
              _ProgressHint(assigned: assignedCount, total: totalCount),
              const SizedBox(height: VelvetSpacing.md),
              NeumorphicButton(
                key: const Key('salon-assign-confirm-cta'),
                label: l10n.bookingConfirmCta,
                icon: Icons.arrow_forward_rounded,
                onPressed: onNext,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sums typed price/duration fields directly — no display-string parsing
  /// (see this screen's file header for why).
  (double, double, int) _totals(List<SalonCatalogService> services) {
    double minSum = 0;
    double maxSum = 0;
    int minutes = 0;
    for (final SalonCatalogService s in services) {
      final double lo = s.priceMin ?? 0;
      final double hi = s.priceType == ServicePriceType.range
          ? (s.priceMax ?? lo)
          : lo;
      minSum += lo;
      maxSum += hi;
      minutes += s.durationMinutes ?? 0;
    }
    return (minSum, maxSum, minutes);
  }
}

class _ProgressHint extends StatelessWidget {
  const _ProgressHint({required this.assigned, required this.total});

  final int assigned;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool done = assigned >= total && total > 0;
    final double fraction = total == 0 ? 0 : assigned / total;
    return Semantics(
      label: l10n.salonBookingAssignedProgress(assigned, total),
      child: NeumorphicInset(
        radius: VelvetRadii.field,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: VelvetSpacing.md,
            vertical: VelvetSpacing.sm + 4,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                done
                    ? Icons.check_circle_rounded
                    : Icons.assignment_turned_in_outlined,
                size: 18,
                color: done ? BrandColors.success : BrandColors.accentDeep,
              ),
              const SizedBox(width: VelvetSpacing.sm),
              Text(
                done
                    ? l10n.salonBookingAllAssignedLabel
                    : l10n.salonBookingAssignedProgress(assigned, total),
                style: VelvetText.bookFeedbackSec13w800,
              ),
              const SizedBox(width: VelvetSpacing.md),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(VelvetRadii.pill),
                  child: Stack(
                    children: <Widget>[
                      Container(
                        height: 5,
                        color: BrandColors.faint.withValues(alpha: 0.5),
                      ),
                      AnimatedFractionallySizedBox(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        widthFactor: fraction.clamp(0.0, 1.0),
                        child: Container(
                          height: 5,
                          decoration: const BoxDecoration(
                            borderRadius: BorderRadius.all(
                              Radius.circular(VelvetRadii.pill),
                            ),
                            gradient: LinearGradient(
                              colors: <Color>[
                                BrandColors.accentLatte,
                                BrandColors.accentDeep,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
