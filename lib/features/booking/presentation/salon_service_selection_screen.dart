// Phase 14.12 — SalonServiceSelectionScreen: salon booking flow step 1 of 3
// (services → masters → coming-soon placeholder for the deferred time step).
//
// The screen a CLIENT lands on after tapping "Записатись на послугу" on a
// public salon profile (`RouteNames.salonBookingServices`, `extra: salonId`).
// Shows the salon's FULL catalogue as expandable category accordions; the
// client multi-selects which service(s) to book, then "Далі" advances to the
// master-assignment step (`RouteNames.salonBookingMasters`).
//
// This closes the reported bug: the CTA used to push `RouteNames.bookingNew`
// with `salon.id` misused as a `masterId`, 404ing server-side
// (`NotFoundException: Master not found`) — a salon booking is fundamentally
// different from the independent-master flow (multi-service selection
// against the salon's FULL catalogue → per-service master assignment → N
// appointments across possibly-different masters), which that flow cannot
// represent. See `public_salon_profile_screen.dart`'s `_BookingShelf` for the
// CTA fix.
//
// DESIGN SOURCE: approved preview at
// `docs/signup-designs/SalonBookingServices/lib/screens/salon_services_screen.dart`
// (2026-06-30). Transcribed 1:1: category accordions (an EXTRUDED header
// pillow + camel chevron), a selection-as-depth check control (recessed well
// → raised camel pillow), and the pinned booking-summary shelf. ONE
// deliberate gap-fill beyond the preview (which the phase doc's acceptance
// criteria require but the preview's actual widget code never implemented,
// despite its gallery subtitle mentioning it): a tri-state per-category
// "Обрати всі" / "Прибрати всі" / indeterminate select-all pill, added within
// the same VelvetTouch/BrandColors token vocabulary as everything else on
// this screen (`_SelectAllPill` below) — not a redesign, a gap the preview
// under-delivered.
//
// The staggered fade-up entrance choreography from the preview is
// intentionally NOT ported, mirroring `ServiceSelectorSheet`'s (Phase 14.1)
// own documented decision to skip it — matches the plain, non-staggered
// category grouping already used in production.
//
// Data: [salonServiceCatalogProvider] (Phase 13.6) already loads the salon's
// full, pre-grouped-by-category catalogue — no new repository method.
//
// The pinned bottom shelf reuses the EXISTING production `BookingSummaryBar`
// (Phase 14.1) rather than re-porting the preview's near-duplicate widget:
// visually identical ("Послуги та ціни" list + "Разом" total + camel CTA),
// already tested, and avoids the exact string-parsing anti-pattern that
// widget's own file header documents moving away from. `BookingSummaryBar`
// is typed over `MasterService`; [_toMasterService] below is a pure display
// adapter from [SalonCatalogService] — never sent over the network, never
// used for the actual booking write path (that stays [SalonCatalogService]
// / raw service ids all the way to `SalonBookingMasterSelectionArgs`).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import '../../salon/application/salon_service_catalog_notifier.dart';
import '../../salon/domain/salon_service_catalog.dart';
import '../domain/salon_booking_args.dart';
import 'widgets/booking_summary_bar.dart';

/// Salon booking flow step 1 — multi-select service picker, opened by the
/// "Записатись на послугу" CTA on the public salon profile.
class SalonServiceSelectionScreen extends ConsumerStatefulWidget {
  const SalonServiceSelectionScreen({super.key, required this.salonId});

  /// Target salon's backend UUID.
  final String salonId;

  @override
  ConsumerState<SalonServiceSelectionScreen> createState() =>
      _SalonServiceSelectionScreenState();
}

class _SalonServiceSelectionScreenState
    extends ConsumerState<SalonServiceSelectionScreen> {
  // ValueNotifier (not a plain Set + setState field) so toggling one checkbox
  // does not rebuild the whole screen — only the bottom summary bar and the
  // category section the toggled tile lives in react. Mirrors
  // ServiceSelectorSheet's mobile-perf pattern exactly.
  final ValueNotifier<Set<String>> _selectedIdsNotifier =
      ValueNotifier<Set<String>>(<String>{});
  final Set<String> _expandedKeys = <String>{};
  bool _expandedSeeded = false;

  @override
  void dispose() {
    _selectedIdsNotifier.dispose();
    super.dispose();
  }

  /// Expands the FIRST category on load only — a no-op on every later
  /// rebuild so toggling a section afterward is never overwritten.
  void _seedExpansionOnce(List<SalonServiceCategoryEntry> categories) {
    if (_expandedSeeded) return;
    _expandedSeeded = true;
    if (categories.isNotEmpty) {
      _expandedKeys.add(categories.first.category);
    }
  }

  void _toggleService(String id) {
    final Set<String> next = Set<String>.of(_selectedIdsNotifier.value);
    if (!next.remove(id)) next.add(id);
    _selectedIdsNotifier.value = next;
  }

  void _toggleExpand(String key) {
    setState(() {
      if (!_expandedKeys.remove(key)) _expandedKeys.add(key);
    });
  }

  /// Selects/clears every service id in [ids] as one atomic update.
  void _setCategorySelection(List<String> ids, {required bool selected}) {
    final Set<String> next = Set<String>.of(_selectedIdsNotifier.value);
    if (selected) {
      next.addAll(ids);
    } else {
      next.removeAll(ids);
    }
    _selectedIdsNotifier.value = next;
  }

  void _goNext(List<SalonCatalogService> selected) {
    context.push(
      RouteNames.salonBookingMasters,
      extra: SalonBookingMasterSelectionArgs(
        salonId: widget.salonId,
        selectedServiceIds: <String>[
          for (final SalonCatalogService s in selected) s.id,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<List<SalonServiceCategoryEntry>> async = ref.watch(
      salonServiceCatalogProvider(widget.salonId),
    );

    return Scaffold(
      backgroundColor: BrandColors.base,
      bottomNavigationBar: async.maybeWhen(
        data: (List<SalonServiceCategoryEntry> categories) {
          final List<SalonCatalogService> all = <SalonCatalogService>[
            for (final SalonServiceCategoryEntry c in categories) ...c.services,
          ];
          return ValueListenableBuilder<Set<String>>(
            valueListenable: _selectedIdsNotifier,
            builder: (BuildContext context, Set<String> selectedIds, _) {
              final List<SalonCatalogService> selected = all
                  .where((SalonCatalogService s) => selectedIds.contains(s.id))
                  .toList(growable: false);
              return BookingSummaryBar(
                services: <MasterService>[
                  for (final SalonCatalogService s in selected)
                    _toMasterService(s),
                ],
                ctaLabel: l10n.bookingNextCta,
                ctaIcon: Icons.arrow_forward_rounded,
                enabled: selected.isNotEmpty,
                onAction: () => _goNext(selected),
                // The mapped MasterService.id round-trips to the original
                // SalonCatalogService.id (see _toMasterService above), so
                // this is the same toggle the catalogue checkbox uses — both
                // removal paths converge on identical end-state.
                onRemove: (MasterService s) => _toggleService(s.id),
              );
            },
          );
        },
        orElse: () => null,
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _TopBar(
              title: l10n.salonBookingServicesTitle,
              onBack: () => context.pop(),
            ),
            Expanded(
              child: async.when(
                loading: () => const _LoadingBody(),
                error: (Object e, StackTrace _) {
                  final Failure failure = e is Failure
                      ? e
                      : UnknownFailure(cause: e);
                  return _errorScrollable(
                    ErrorState(
                      key: const Key('salon-service-selection-error-state'),
                      failure: failure,
                      onRetry: () => ref.invalidate(
                        salonServiceCatalogProvider(widget.salonId),
                      ),
                    ),
                  );
                },
                data: (List<SalonServiceCategoryEntry> categories) {
                  _seedExpansionOnce(categories);
                  if (categories.isEmpty) {
                    return const _EmptyCatalogue();
                  }
                  return _CatalogueBody(
                    categories: categories,
                    expandedKeys: _expandedKeys,
                    selectedIdsListenable: _selectedIdsNotifier,
                    onToggleService: _toggleService,
                    onToggleExpand: _toggleExpand,
                    onSetCategorySelection: _setCategorySelection,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorScrollable(Widget child) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(height: 400, child: child),
    );
  }
}

/// Pure display adapter — [SalonCatalogService] → [MasterService] — so this
/// screen can reuse the existing [BookingSummaryBar] widget verbatim. Never
/// used for the actual booking write path; [priceDisplay]/[durationLabel]
/// pass straight through, so the rendered totals never diverge from what the
/// service tile above shows.
MasterService _toMasterService(SalonCatalogService s) => MasterService(
  id: s.id,
  serviceDefId: s.id,
  name: s.name,
  category: s.category,
  durationMinutes: s.durationMinutes ?? 0,
  priceType: s.priceType ?? ServicePriceType.fixed,
  priceMin: s.priceMin ?? 0,
  priceMax: s.priceMax,
  priceDisplay: s.priceDisplay,
);

// ---------------------------------------------------------------------------
// Top bar
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
                key: const Key('salon-service-selection-back'),
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
              child: _StepIndicator(current: 1, total: 4),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact "Крок N з M" pill above a dash rail whose active segment widens
/// and fills camel. Shared visual language across every salon booking screen
/// (this screen and `SalonMasterSelectionScreen`) — kept as a small private
/// widget in each file, mirroring the approved preview's own two verbatim
/// copies rather than a shared file for a ~30-line read-only display widget.
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
              style: VelvetText.feedback(
                BrandColors.textSecondary,
              ).copyWith(fontSize: 12, fontWeight: FontWeight.w800),
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
// Loading / empty states
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
            height: 64,
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
            height: 96,
            radius: VelvetRadii.card,
          ),
        ],
      ),
    );
  }
}

class _EmptyCatalogue extends StatelessWidget {
  const _EmptyCatalogue();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                    Icons.spa_rounded,
                    size: 36,
                    color: BrandColors.accent.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
            const SizedBox(height: VelvetSpacing.lg),
            Text(
              l10n.salonServicesEmpty,
              key: const Key('salon-service-selection-empty'),
              style: VelvetText.heading().copyWith(fontSize: 20),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Catalogue body — category accordions (already grouped server-side)
// ---------------------------------------------------------------------------

class _CatalogueBody extends StatelessWidget {
  const _CatalogueBody({
    required this.categories,
    required this.expandedKeys,
    required this.selectedIdsListenable,
    required this.onToggleService,
    required this.onToggleExpand,
    required this.onSetCategorySelection,
  });

  final List<SalonServiceCategoryEntry> categories;
  final Set<String> expandedKeys;
  final ValueListenable<Set<String>> selectedIdsListenable;
  final ValueChanged<String> onToggleService;
  final ValueChanged<String> onToggleExpand;
  final void Function(List<String> ids, {required bool selected})
  onSetCategorySelection;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

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
            child: Text(
              l10n.salonBookingServicesIntro,
              style: VelvetText.body().copyWith(fontSize: 14),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.xxl,
          ),
          sliver: SliverList.separated(
            itemCount: categories.length,
            separatorBuilder: (BuildContext context, int i) =>
                const SizedBox(height: VelvetSpacing.md),
            itemBuilder: (BuildContext context, int i) => _CategorySection(
              key: Key('salon_booking_category_${categories[i].category}'),
              category: categories[i],
              expanded: expandedKeys.contains(categories[i].category),
              selectedIdsListenable: selectedIdsListenable,
              onToggleExpand: () => onToggleExpand(categories[i].category),
              onToggleService: onToggleService,
              onSetCategorySelection: onSetCategorySelection,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Category accordion section
// ---------------------------------------------------------------------------

class _CategorySection extends StatefulWidget {
  const _CategorySection({
    super.key,
    required this.category,
    required this.expanded,
    required this.selectedIdsListenable,
    required this.onToggleExpand,
    required this.onToggleService,
    required this.onSetCategorySelection,
  });

  final SalonServiceCategoryEntry category;
  final bool expanded;
  final ValueListenable<Set<String>> selectedIdsListenable;
  final VoidCallback onToggleExpand;
  final ValueChanged<String> onToggleService;
  final void Function(List<String> ids, {required bool selected})
  onSetCategorySelection;

  @override
  State<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<_CategorySection> {
  late Set<String> _selectedInGroup;

  List<String> get _allIds => <String>[
    for (final SalonCatalogService s in widget.category.services) s.id,
  ];

  @override
  void initState() {
    super.initState();
    _selectedInGroup = _computeSelectedInGroup();
    widget.selectedIdsListenable.addListener(_handleSelectionChanged);
  }

  @override
  void didUpdateWidget(covariant _CategorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIdsListenable != widget.selectedIdsListenable) {
      oldWidget.selectedIdsListenable.removeListener(_handleSelectionChanged);
      widget.selectedIdsListenable.addListener(_handleSelectionChanged);
      _selectedInGroup = _computeSelectedInGroup();
    } else if (!identical(oldWidget.category, widget.category)) {
      _selectedInGroup = _computeSelectedInGroup();
    }
  }

  @override
  void dispose() {
    widget.selectedIdsListenable.removeListener(_handleSelectionChanged);
    super.dispose();
  }

  Set<String> _computeSelectedInGroup() {
    final Set<String> selected = widget.selectedIdsListenable.value;
    return <String>{
      for (final SalonCatalogService s in widget.category.services)
        if (selected.contains(s.id)) s.id,
    };
  }

  void _handleSelectionChanged() {
    final Set<String> next = _computeSelectedInGroup();
    if (setEquals(next, _selectedInGroup)) return;
    setState(() => _selectedInGroup = next);
  }

  void _handleSelectAll() {
    final bool allSelected =
        _selectedInGroup.length == widget.category.services.length &&
        widget.category.services.isNotEmpty;
    widget.onSetCategorySelection(_allIds, selected: !allSelected);
  }

  @override
  Widget build(BuildContext context) {
    final SalonServiceCategoryEntry cat = widget.category;
    final bool expanded = widget.expanded;
    final int selectedInCat = _selectedInGroup.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _CategoryHeader(
          label: cat.displayName,
          count: cat.services.length,
          selectedCount: selectedInCat,
          expanded: expanded,
          onTap: widget.onToggleExpand,
          onSelectAll: _handleSelectAll,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: expanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final SalonCatalogService s in cat.services)
                      Padding(
                        padding: const EdgeInsets.only(top: VelvetSpacing.md),
                        child: _ServiceSelectTile(
                          key: Key('salon_booking_service_tile_${s.id}'),
                          service: s,
                          selected: _selectedInGroup.contains(s.id),
                          onToggle: () => widget.onToggleService(s.id),
                        ),
                      ),
                  ],
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Category header + select-all pill + camel chevron
// ---------------------------------------------------------------------------

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    required this.label,
    required this.count,
    required this.selectedCount,
    required this.expanded,
    required this.onTap,
    required this.onSelectAll,
  });

  final String label;
  final int count;
  final int selectedCount;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String state = expanded
        ? l10n.salonServiceCategoryExpanded
        : l10n.salonServiceCategoryCollapsed;
    final String semanticsLabel = l10n.salonServiceCategoryHeaderSemanticLabel(
      label,
      count,
      state,
    );

    return Semantics(
      button: true,
      header: true,
      expanded: expanded,
      label: semanticsLabel,
      child: GestureDetector(
        key: Key('salon-booking-category-$label'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: VelvetSpacing.md,
            vertical: VelvetSpacing.sm + 4,
          ),
          decoration: BoxDecoration(
            color: BrandColors.base,
            borderRadius: BorderRadius.circular(VelvetRadii.card),
            boxShadow: VelvetShadows.extrudedCard,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: VelvetText.subheading().copyWith(fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: VelvetSpacing.sm),
              _SelectAllPill(
                categoryLabel: label,
                selected: selectedCount,
                total: count,
                onTap: onSelectAll,
              ),
              const SizedBox(width: VelvetSpacing.sm),
              AnimatedRotation(
                turns: expanded ? 0.0 : -0.25,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 22,
                  color: BrandColors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Per-category tri-state select-all pill — the phase-doc-mandated affordance
/// the approved preview's gallery blurb promised ("мультивибір + «Обрати
/// всі»") but its actual widget code never implemented. Added within the same
/// extruded-pillow vocabulary as the sibling [_CountBadge] it replaces on
/// this (selectable) screen — the read-only accordion on the public salon
/// profile keeps its own plain count badge unchanged.
///
/// Nested inside [_CategoryHeader]'s outer `GestureDetector` (which toggles
/// expand/collapse): Flutter's gesture arena resolves nested `GestureDetector`
/// taps to whichever recognizer was hit-tested first (innermost), so a tap
/// squarely on this pill fires ONLY [onTap] here, never the header's expand
/// toggle.
class _SelectAllPill extends StatelessWidget {
  const _SelectAllPill({
    required this.categoryLabel,
    required this.selected,
    required this.total,
    required this.onTap,
  });

  /// The owning category's display label — used ONLY to key this pill
  /// uniquely per category (multiple categories render side-by-side in the
  /// same accordion, so a fixed literal key would duplicate across them).
  final String categoryLabel;
  final int selected;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool allSelected = total > 0 && selected == total;
    final bool none = selected == 0;
    final IconData icon = allSelected
        ? Icons.check_box_rounded
        : none
        ? Icons.check_box_outline_blank_rounded
        : Icons.indeterminate_check_box_rounded;
    final String label = allSelected
        ? l10n.salonServiceClearAllLabel
        : l10n.salonServiceSelectAllLabel;
    final Color tint = none ? BrandColors.muted : BrandColors.accentDeep;

    return Semantics(
      button: true,
      label: l10n.salonServiceSelectAllSemantics(label, selected, total),
      child: GestureDetector(
        key: Key('salon-booking-category-select-all-$categoryLabel'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: VelvetSpacing.sm,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: BrandColors.base,
            borderRadius: BorderRadius.circular(VelvetRadii.pill),
            boxShadow: VelvetShadows.extrudedSmall,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 15, color: tint),
              const SizedBox(width: 3),
              Text(
                label,
                style: VelvetText.feedback(
                  tint,
                ).copyWith(fontSize: 11.5, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Selectable service tile + depth check control
// ---------------------------------------------------------------------------

class _CheckControl extends StatelessWidget {
  const _CheckControl({required this.selected});

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
                  shape: BoxShape.circle,
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

class _ServiceSelectTile extends StatefulWidget {
  const _ServiceSelectTile({
    super.key,
    required this.service,
    required this.selected,
    required this.onToggle,
  });

  final SalonCatalogService service;
  final bool selected;
  final VoidCallback onToggle;

  @override
  State<_ServiceSelectTile> createState() => _ServiceSelectTileState();
}

class _ServiceSelectTileState extends State<_ServiceSelectTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final SalonCatalogService s = widget.service;
    final bool sel = widget.selected;

    return Semantics(
      button: true,
      checked: sel,
      label: l10n.bookingServiceTileSemantics(
        s.name,
        s.durationLabel,
        s.priceDisplay,
      ),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onToggle();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1,
          duration: const Duration(milliseconds: 110),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: sel ? const Color(0xFFEDE4D5) : BrandColors.base,
              borderRadius: BorderRadius.circular(VelvetRadii.field),
              boxShadow: _pressed ? null : VelvetShadows.extrudedSmall,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.sm + 4,
              vertical: VelvetSpacing.sm + 2,
            ),
            child: Row(
              children: <Widget>[
                _CheckControl(selected: sel),
                const SizedBox(width: VelvetSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        s.name,
                        style: VelvetText.bodyStrong(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.schedule_outlined,
                            size: 12,
                            color: BrandColors.muted,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            s.durationLabel,
                            style: VelvetText.feedback(
                              BrandColors.muted,
                            ).copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Text(
                  s.priceDisplay,
                  style: VelvetText.bodyStrong().copyWith(
                    color: BrandColors.accentDeep,
                    fontWeight: FontWeight.w800,
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
