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
// → raised camel pillow), and the pinned booking-summary shelf.
//
// REFACTOR NOTE: this screen originally added its own per-category tri-state
// "Обрати всі" / "Прибрати всі" / indeterminate select-all pill
// (`_SelectAllPill`) as a gap-fill beyond the approved preview. That pill has
// since been DELETED (product decision, not a defect) as part of unifying
// this screen's catalogue accordion with `ServiceSelectorSheet`'s
// (independent-master flow) near-identical implementation into the shared
// `widgets/service_catalogue_accordion.dart`. There is no replacement
// affordance in that header slot.
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
import '../application/pending_service_preselection_provider.dart';
import '../domain/pending_service_preselection.dart';
import '../domain/salon_booking_args.dart';
import 'widgets/booking_summary_bar.dart';
import 'widgets/service_catalogue_accordion.dart';

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
  // Shared controller (not a plain Set + setState field) so toggling one
  // checkbox does not rebuild the whole screen — only the bottom summary bar
  // and the category section the toggled tile lives in react. Mirrors
  // ServiceSelectorSheet's mobile-perf pattern exactly (both now delegate to
  // the same `CatalogueSelectionController`).
  final CatalogueSelectionController _selectionController =
      CatalogueSelectionController();
  final Set<String> _expandedKeys = <String>{};
  bool _expandedSeeded = false;

  /// Catalogue-service ids matched by the discovery-search pre-selection
  /// ([_preselection]). Rendered in a pinned section at the TOP of the
  /// catalogue and suppressed from their category accordion below (never shown
  /// twice). Populated once by [_seedOnce]; a stable reference thereafter.
  /// Empty ⇒ the pinned section renders nothing.
  final Set<String> _pinnedIds = <String>{};

  /// The one-shot search pre-selection for THIS salon. Captured (read-only, via
  /// [peekFor]) in [initState] so it is available synchronously before the
  /// catalogue resolves — [_seedOnce] matches it against the resolved services.
  /// Null when the client did not arrive from a search with an active service
  /// filter, or the pending payload targeted a different provider.
  PendingServicePreselection? _preselection;

  @override
  void initState() {
    super.initState();
    // PEEK (read-only) the pending search service pre-selection for this salon
    // so it is captured synchronously for [_seedOnce] — peekFor does NOT mutate
    // the provider, so this is safe inside initState (which for a `context.push`
    // route runs during the next frame's build phase; a provider WRITE here
    // throws "Tried to modify a provider while the widget tree was building").
    _preselection = ref
        .read(pendingServicePreselectionControllerProvider.notifier)
        .peekFor(widget.salonId);
    // Defer the one-shot CLEAR off the build phase. After this frame the payload
    // is gone, so backing out of the booking flow and re-entering will not
    // re-preselect. Only the CLEAR is deferred — the capture above stays
    // synchronous so the seed never races catalogue resolution.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(pendingServicePreselectionControllerProvider.notifier).clear();
    });
  }

  @override
  void dispose() {
    _selectionController.dispose();
    super.dispose();
  }

  /// Seeds selection + expansion exactly once, the first time the catalogue
  /// resolves. A no-op on every later rebuild so toggling a section afterward
  /// is never overwritten.
  ///
  /// When a discovery search service filter arrived ([_preselection]), every
  /// catalogue service whose `serviceTypeSlug` EXACTLY matches is pre-checked
  /// (multi-select) and its category is expanded — with a defensive fallback to
  /// the category display name only when a service has no slug. No match
  /// degrades to nothing pre-checked. Absent any pre-selection, the first
  /// category is expanded (the prior default).
  void _seedOnce(List<SalonServiceCategoryEntry> categories) {
    if (_expandedSeeded) return;
    _expandedSeeded = true;

    final PendingServicePreselection? pre = _preselection;
    if (pre != null) {
      final Set<String> selectedIds = <String>{};
      for (final SalonServiceCategoryEntry c in categories) {
        for (final SalonCatalogService s in c.services) {
          if (_matchesPreselection(
            s.serviceTypeSlug,
            s.serviceTypeNameUk,
            pre,
          )) {
            selectedIds.add(s.id);
            // Pin the match at the top instead of expanding its category —
            // the service is surfaced immediately, so auto-expanding its
            // in-accordion row would be redundant.
            _pinnedIds.add(s.id);
          }
        }
      }
      if (selectedIds.isNotEmpty) {
        _selectionController.replaceAll(selectedIds);
        // Matches are pinned at the top; leave the accordion collapsed (no
        // default first-category expand) so the pinned section is the focus.
        return;
      }
    }

    // No pre-selection (or nothing matched) → keep the default of expanding the
    // first category.
    if (categories.isNotEmpty) {
      _expandedKeys.add(categories.first.category);
    }
  }

  /// EXACT slug match against the pre-selection; falls back to the underlying
  /// platform service-type name only when the service carries no slug
  /// (defensive). Mirrors `ServiceSelectorSheet._matchesPreselection` (the
  /// independent-master flow) 1:1 — the fallback compares the SERVICE-TYPE name
  /// (same namespace as [PendingServicePreselection.serviceTypeLabels]), never
  /// the salon's custom display name.
  bool _matchesPreselection(
    String? slug,
    String? serviceTypeNameUk,
    PendingServicePreselection pre,
  ) {
    if (slug != null && slug.isNotEmpty) {
      return pre.serviceTypeSlugs.contains(slug);
    }
    final String label = (serviceTypeNameUk ?? '').trim();
    return label.isNotEmpty && pre.serviceTypeLabels.contains(label);
  }

  void _toggleExpand(String key) {
    setState(() {
      if (!_expandedKeys.remove(key)) _expandedKeys.add(key);
    });
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
            valueListenable: _selectionController,
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
                onRemove: (MasterService s) =>
                    _selectionController.toggleService(s.id),
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
                  _seedOnce(categories);
                  if (categories.isEmpty) {
                    return const _EmptyCatalogue();
                  }
                  return _CatalogueBody(
                    categories: categories,
                    pinnedIds: _pinnedIds,
                    expandedKeys: _expandedKeys,
                    selectedIdsListenable: _selectionController,
                    onToggleService: _selectionController.toggleService,
                    onToggleExpand: _toggleExpand,
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

/// Pure display projection — [SalonCatalogService] → [CatalogueRow] — so the
/// shared `widgets/service_catalogue_accordion.dart` widgets never depend on
/// this feature's domain model.
CatalogueRow _toCatalogueRow(SalonCatalogService s) => CatalogueRow(
  id: s.id,
  name: s.name,
  categoryLabel: s.category ?? '',
  durationLabel: s.durationLabel,
  priceLabel: s.priceDisplay,
);

/// This screen never showed a plain count/selected badge in the header's
/// trailing slot — that slot used to hold the now-deleted tri-state
/// "select all" pill instead. See the shared widget's `showCountBadges`.
Key _salonTileKeyForId(String id) => Key('salon_booking_service_tile_$id');

class _CatalogueBody extends StatefulWidget {
  const _CatalogueBody({
    required this.categories,
    required this.pinnedIds,
    required this.expandedKeys,
    required this.selectedIdsListenable,
    required this.onToggleService,
    required this.onToggleExpand,
  });

  final List<SalonServiceCategoryEntry> categories;

  /// Catalogue-service ids surfaced in the pinned top section — excluded from
  /// the category accordion so they never appear twice. Empty ⇒ no pinned
  /// section.
  final Set<String> pinnedIds;
  final Set<String> expandedKeys;
  final ValueListenable<Set<String>> selectedIdsListenable;
  final ValueChanged<String> onToggleService;
  final ValueChanged<String> onToggleExpand;

  @override
  State<_CatalogueBody> createState() => _CatalogueBodyState();
}

class _CatalogueBodyState extends State<_CatalogueBody> {
  // Memoized mapping (mobile-perf finding): `_toCatalogueCategoryGroup`
  // allocates a fresh `CatalogueCategoryGroup`/`CatalogueRow` graph on every
  // build — including unrelated rebuilds like toggling a *different*
  // category's expand/collapse, which re-runs this whole widget's build via
  // the parent `State`'s `setState`. A fresh instance every time defeats
  // `CatalogueCategorySection.didUpdateWidget`'s
  // `identical(oldWidget.category, widget.category)` fast path, forcing every
  // currently-expanded section to recompute its selection set even though its
  // own underlying data never changed. Cache the mapped groups and only
  // recompute when the source `categories` list's identity actually changes —
  // mirrors `ServiceSelectorSheet`'s `_CatalogueBodyState._groupsFor`.
  List<CatalogueCategoryGroup>? _cachedGroups;
  List<CatalogueRow>? _cachedPinnedRows;
  List<SalonServiceCategoryEntry>? _cachedCategories;

  List<CatalogueCategoryGroup> _groupsFor(
    List<SalonServiceCategoryEntry> categories,
  ) {
    _rebuildIfNeeded(categories);
    return _cachedGroups!;
  }

  /// The pinned rows (search-preselected services), in catalogue order.
  /// Empty ⇒ the caller renders no pinned section.
  List<CatalogueRow> _pinnedRowsFor(
    List<SalonServiceCategoryEntry> categories,
  ) {
    _rebuildIfNeeded(categories);
    return _cachedPinnedRows!;
  }

  void _rebuildIfNeeded(List<SalonServiceCategoryEntry> categories) {
    if (_cachedGroups != null && identical(_cachedCategories, categories)) {
      return;
    }
    // Pinned services are surfaced in the top section only — collect them and
    // exclude them from the accordion (dropping any category left empty), so a
    // searched service is never shown twice. `pinnedIds` is a stable reference
    // for this screen's lifetime (seeded once), so it needs no cache key.
    final List<CatalogueRow> pinned = <CatalogueRow>[];
    final List<CatalogueCategoryGroup> groups = <CatalogueCategoryGroup>[];
    for (final SalonServiceCategoryEntry entry in categories) {
      final List<CatalogueRow> rows = <CatalogueRow>[];
      for (final SalonCatalogService s in entry.services) {
        final CatalogueRow row = _toCatalogueRow(s);
        if (widget.pinnedIds.contains(s.id)) {
          pinned.add(row);
        } else {
          rows.add(row);
        }
      }
      if (rows.isEmpty) continue;
      groups.add(
        CatalogueCategoryGroup(
          key: entry.category,
          label: entry.displayName,
          rows: rows,
        ),
      );
    }
    _cachedPinnedRows = pinned;
    _cachedGroups = groups;
    _cachedCategories = categories;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final List<CatalogueCategoryGroup> groups = _groupsFor(widget.categories);
    final List<CatalogueRow> pinnedRows = _pinnedRowsFor(widget.categories);
    String headerSemantics({
      required String label,
      required int count,
      required int selectedCount,
      required bool expanded,
    }) {
      final String state = expanded
          ? l10n.salonServiceCategoryExpanded
          : l10n.salonServiceCategoryCollapsed;
      return l10n.salonServiceCategoryHeaderSemanticLabel(label, count, state);
    }

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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  l10n.salonBookingServicesIntro,
                  style: VelvetText.body().copyWith(fontSize: 14),
                ),
                // Pinned search-preselection section — renders nothing when
                // the client did not arrive from a search (pinnedRows empty).
                if (pinnedRows.isNotEmpty) ...<Widget>[
                  const SizedBox(height: VelvetSpacing.xl),
                  CataloguePinnedSection(
                    key: const Key('salon-booking-pinned-services'),
                    heading: l10n.bookingPinnedServicesHeading(
                      pinnedRows.length,
                    ),
                    rows: pinnedRows,
                    selectedIdsListenable: widget.selectedIdsListenable,
                    onToggleService: widget.onToggleService,
                    tileKeyForId: _salonTileKeyForId,
                  ),
                ],
              ],
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
            itemCount: groups.length,
            separatorBuilder: (BuildContext context, int i) =>
                const SizedBox(height: VelvetSpacing.md),
            itemBuilder: (BuildContext context, int i) =>
                CatalogueCategorySection(
                  key: Key('salon_booking_category_${groups[i].key}'),
                  category: groups[i],
                  expanded: widget.expandedKeys.contains(groups[i].key),
                  selectedIdsListenable: widget.selectedIdsListenable,
                  onToggleExpand: () => widget.onToggleExpand(groups[i].key),
                  onToggleService: widget.onToggleService,
                  headerSemanticsLabel: headerSemantics,
                  tileKeyForId: _salonTileKeyForId,
                  headerVerticalPadding: VelvetSpacing.sm + 4,
                  headerKey: Key('salon-booking-category-${groups[i].label}'),
                  showCountBadges: false,
                ),
          ),
        ),
      ],
    );
  }
}
