// Phase 14.1 — ServiceSelectorSheet: booking flow Step 1 (service selection).
//
// The screen the client lands on after tapping "Записатись" /
// "Обрати послугу" on the public master profile (`RouteNames.bookingNew`,
// `extra: masterId`). Shows the master's full catalogue grouped by category;
// the client multi-selects which service(s) to book, then "Далі" advances to
// the slot picker (`RouteNames.bookingSlots`).
//
// DESIGN SOURCE: `docs/signup-designs/BookingServiceSelection/lib/screens/service_selection_screen.dart`
// — the APPROVED design (2026-06-30 status note in the phase doc), which
// supersedes the phase doc's original pre-approval Step-1 sketch ("single
// select flat list"). Transcribed 1:1: category accordions (an EXTRUDED
// header pillow + raised count badge + camel chevron, mirroring
// `services_list_screen.dart`'s `_CategorySection`), a selection-as-depth
// check control (recessed well → raised camel pillow), and the pinned
// `BookingSummaryBar` shelf. The staggered fade-up entrance choreography is
// intentionally NOT ported (out of scope for this phase — matches the plain,
// non-staggered category grouping already used by `services_list_screen.dart`
// in production).
//
// DEVIATION from the phase doc's literal file/widget shape: the doc's Step 1
// prose calls this a `DraggableScrollableSheet`, but the APPROVED preview
// (source of truth per this repo's convention — see
// `docs/mobile-phases/phase-095-14.1-service-selection-slot-picker.md`
// status note) renders a full page with its own top bar + pinned bottom
// shelf, not a modal sheet. This class name is kept as `ServiceSelectorSheet`
// (matching the phase doc's mandated file/class naming) even though it
// renders as a full [Scaffold], not a literal bottom sheet.
//
// Data: [publicMasterProfileProvider] (Phase 13.5) already loads the target
// master + active services in parallel and is explicitly documented as
// "reused as-is by the Phase 14.1 service-selection / slot-picker flow" — so
// this screen watches that family directly instead of a second
// `ServiceRepository.getMasterServices` call.
//
// REFACTOR NOTE: the category accordion (`_CategorySection` / `_CategoryHeader`
// / `_CheckControl` / `_ServiceSelectTile`) now lives in the shared
// `widgets/service_catalogue_accordion.dart`, unified with the near-identical
// implementation `SalonServiceSelectionScreen` (Phase 14.12) had hand-copied.
// This screen keeps its own category-GROUPING logic (bucketing services by
// category + resolving each category's display name via
// [approvedCategoriesProvider]) — that stays Riverpod-aware and screen-owned
// — but the grouped output is now the shared `CatalogueCategoryGroup` shape
// instead of a private `_CategoryGroup` class.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart'
    show maxServicesPerVisit;
import 'package:beautica_mobile/features/services/domain/category_slug.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import '../application/pending_service_preselection_provider.dart';
import '../domain/booking_slot_picker_args.dart';
import '../domain/pending_service_preselection.dart';
import 'widgets/booking_summary_bar.dart';
import 'widgets/master_strip.dart';
import 'widgets/service_catalogue_accordion.dart';

/// Booking flow Step 1 — multi-select service picker, opened by the
/// "Записатись" CTA on the public master profile.
class ServiceSelectorSheet extends ConsumerStatefulWidget {
  const ServiceSelectorSheet({
    super.key,
    required this.masterId,
    this.initialServiceId,
  });

  /// Target master's backend UUID.
  final String masterId;

  /// Optional service id the client tapped BEFORE reaching this screen (e.g.
  /// from a specific service card on the profile). When it resolves to a real
  /// service, that service starts pre-selected and its category starts
  /// expanded. Not currently threaded from any call site (the public master
  /// profile's booking shelf CTA carries only the master id), so this is an
  /// extension point rather than an exercised path today.
  final String? initialServiceId;

  @override
  ConsumerState<ServiceSelectorSheet> createState() =>
      _ServiceSelectorSheetState();
}

class _ServiceSelectorSheetState extends ConsumerState<ServiceSelectorSheet> {
  // A shared [CatalogueSelectionController] rather than a plain `Set` +
  // `setState` field (mobile-perf finding #2): toggling one checkbox must NOT
  // rebuild the whole screen (Scaffold → catalogue → every category → every
  // tile) — only the widgets that actually depend on the selection should
  // react. Bottom summary bar listens via [ValueListenableBuilder]; each
  // `CatalogueCategorySection` subscribes directly and only calls its OWN
  // `setState` when the selection *within that category* actually changed,
  // so sibling categories and the rest of the tree never rebuild for an
  // unrelated toggle. Same controller `SalonServiceSelectionScreen` now uses.
  final CatalogueSelectionController _selectionController =
      CatalogueSelectionController();
  final Set<String> _expandedKeys = <String>{};
  bool _seeded = false;

  /// Category keys (uppercased-trimmed `category` slugs) that contain a service
  /// matched by the discovery-search pre-selection ([_preselection]). These
  /// categor(ies) are HOISTED to the TOP of the accordion and start EXPANDED,
  /// so the searched service is visible immediately in its normal category row
  /// alongside its siblings. Populated once by [_seedOnce]; a stable reference
  /// thereafter, so the catalogue body's memoized grouping never invalidates on
  /// it. Empty when the client did not arrive from a search — the catalogue
  /// then renders in normal category order with default (collapsed) expansion.
  /// Deliberately does NOT include [widget.initialServiceId]'s category (that
  /// extension point expands its own section but is not hoisted).
  final Set<String> _hoistedKeys = <String>{};

  /// The one-shot search pre-selection for THIS master. Captured (read-only,
  /// via [peekFor]) in [initState] so it is available synchronously before the
  /// catalogue resolves — [_seedOnce] matches it against the resolved services.
  /// Null when the client did not arrive from a search with an active service
  /// filter, or the pending payload targeted a different provider.
  PendingServicePreselection? _preselection;

  @override
  void initState() {
    super.initState();
    // PEEK (read-only) the pending search service pre-selection for this master
    // so it is captured synchronously for [_seedOnce] — peekFor does NOT mutate
    // the provider, so this is safe inside initState (which for a `context.push`
    // route runs during the next frame's build phase; a provider WRITE here
    // throws "Tried to modify a provider while the widget tree was building").
    _preselection = ref
        .read(pendingServicePreselectionControllerProvider.notifier)
        .peekFor(widget.masterId);
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

  /// Seeds selection/expansion exactly once, the first time the catalogue
  /// resolves. A no-op on every later rebuild (guarded by [_seeded]), so
  /// toggling a section afterward is never overwritten by a stale re-seed.
  ///
  /// Two independent seed sources, unioned:
  ///   1. [widget.initialServiceId] — a specific service tapped before this
  ///      screen (extension point; not currently threaded from any call site).
  ///   2. [_preselection] — the discovery search service filter, matched by
  ///      EXACT `serviceTypeSlug` equality across ALL of the master's services
  ///      (multi-select), with a defensive fallback to the service-type display
  ///      name only when a service has no slug of its own. Each matched
  ///      service's CATEGORY is hoisted to the top and expanded (see
  ///      [_hoistedKeys]) — the service itself stays in its normal category row
  ///      with its siblings, just checked. No match degrades to nothing
  ///      pre-checked and no hoisting — never a wrong check.
  ///
  /// Expansion + hoist are LOCAL widget state ([_expandedKeys] / [_hoistedKeys])
  /// seeded here — never a provider write — so they are safe to mutate off the
  /// build phase and cannot trip Riverpod's "modified a provider while building".
  void _seedOnce(List<MasterService> services) {
    if (_seeded) return;
    _seeded = true;

    final Set<String> selectedIds = <String>{};

    final String? initial = widget.initialServiceId;
    if (initial != null && initial.isNotEmpty) {
      final MasterService? match = services
          .where((MasterService s) => s.id == initial)
          .firstOrNull;
      if (match != null) {
        selectedIds.add(match.id);
        _expandedKeys.add((match.category ?? '').trim().toUpperCase());
      }
    }

    final PendingServicePreselection? pre = _preselection;
    if (pre != null) {
      for (final MasterService s in services) {
        if (_matchesPreselection(s.serviceTypeSlug, s.serviceTypeNameUk, pre)) {
          selectedIds.add(s.id);
          // Hoist + expand the matched service's category so it sits at the top
          // of the accordion with all its sibling services visible and this one
          // checked — instead of surfacing the match alone in a pinned section.
          final String key = (s.category ?? '').trim().toUpperCase();
          _hoistedKeys.add(key);
          _expandedKeys.add(key);
        }
      }
    }

    if (selectedIds.isNotEmpty) {
      _selectionController.replaceAll(selectedIds);
    }
  }

  /// EXACT slug match against the pre-selection; falls back to the service-type
  /// display name only when the service carries no slug (defensive).
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

  /// Toggles [id] in/out of the visit selection, capped at
  /// [maxServicesPerVisit] (the backend `MAX_SERVICES_PER_VISIT`). An ADD that
  /// would exceed the cap is refused with a friendly SnackBar rather than
  /// silently dropped — a removal is never blocked. Deselection also naturally
  /// dedupes the eventual `POST /appointments` payload: the selection is a
  /// `Set` keyed by service id, so a service can be chosen at most once.
  void _onToggleService(String id) {
    final bool willAdd = !_selectionController.isSelected(id);
    if (willAdd && _selectionController.value.length >= maxServicesPerVisit) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.bookingMaxServicesReached(maxServicesPerVisit)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    _selectionController.toggleService(id);
  }

  void _goNext(Master master, List<MasterService> selected) {
    context.push(
      RouteNames.bookingSlots,
      extra: BookingSlotPickerArgs(
        masterId: widget.masterId,
        master: master,
        services: selected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final asyncData = ref.watch(publicMasterProfileProvider(widget.masterId));

    return Scaffold(
      backgroundColor: BrandColors.base,
      // Narrow ValueListenable watch (mobile-perf finding #2): only this
      // small bottom shelf rebuilds on a checkbox toggle, not the Scaffold
      // or the catalogue above it.
      bottomNavigationBar: asyncData.maybeWhen(
        data: (PublicMasterProfileData data) {
          final (Master master, List<MasterService> services) = data;
          return ValueListenableBuilder<Set<String>>(
            valueListenable: _selectionController,
            builder: (BuildContext context, Set<String> selectedIds, _) {
              final List<MasterService> selected = services
                  .where((MasterService s) => selectedIds.contains(s.id))
                  .toList(growable: false);
              return BookingSummaryBar(
                services: selected,
                ctaLabel: l10n.bookingNextCta,
                ctaIcon: Icons.arrow_forward_rounded,
                enabled: selected.isNotEmpty,
                onAction: () => _goNext(master, selected),
                // Same toggle the catalogue checkbox uses, so both removal
                // paths converge on identical end-state. (Removal is never
                // cap-blocked.)
                onRemove: (MasterService s) => _onToggleService(s.id),
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
              title: l10n.bookingServiceSelectTitle,
              onBack: () => context.pop(),
            ),
            Expanded(
              child: asyncData.when(
                loading: () => const _LoadingBody(),
                error: (Object e, StackTrace _) {
                  final Failure failure = e is Failure
                      ? e
                      : UnknownFailure(cause: e);
                  return _errorScrollable(
                    ErrorState(
                      key: const Key('service-selector-error-state'),
                      failure: failure,
                      onRetry: () => ref.invalidate(
                        publicMasterProfileProvider(widget.masterId),
                      ),
                    ),
                  );
                },
                data: (PublicMasterProfileData data) {
                  final (Master master, List<MasterService> services) = data;
                  _seedOnce(services);
                  if (services.isEmpty) {
                    return _EmptyCatalogue(masterName: master.firstName);
                  }
                  return _CatalogueBody(
                    master: master,
                    services: services,
                    hoistedKeys: _hoistedKeys,
                    selectedIdsListenable: _selectionController,
                    expandedKeys: _expandedKeys,
                    onToggleService: _onToggleService,
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
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: NeumorphicIconButton(
                key: const Key('service-selector-back'),
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
          ],
        ),
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
  const _EmptyCatalogue({required this.masterName});

  final String masterName;

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
              l10n.publicMasterBookingEmptyPrompt,
              style: VelvetText.heading20,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Catalogue body — category accordions
// ---------------------------------------------------------------------------

/// Pure display projection — [MasterService] → [CatalogueRow] — so the
/// shared `widgets/service_catalogue_accordion.dart` widgets never depend on
/// this feature's domain model. Preserves the pre-existing name-fallback
/// (custom name, else the platform service-type's Ukrainian name) and the
/// server-formatted duration/price strings.
CatalogueRow _toCatalogueRow(MasterService s) {
  final String typeName = (s.serviceTypeNameUk ?? '').trim();
  final String customName = s.name.trim();
  final String name = customName.isNotEmpty ? customName : typeName;
  return CatalogueRow(
    id: s.id,
    name: name,
    categoryLabel: s.category ?? '',
    durationLabel: DurationMinutes.format(s.durationMinutes),
    priceLabel: ServicePriceDisplay.format(s),
  );
}

/// This screen always shows the plain count / selected-count badges in the
/// header's trailing slot (unlike the salon flow, which shows neither — see
/// `showCountBadges` on `CatalogueCategorySection`).
Key _bookingTileKeyForId(String id) => Key('booking_service_tile_$id');

class _CatalogueBody extends ConsumerStatefulWidget {
  const _CatalogueBody({
    required this.master,
    required this.services,
    required this.hoistedKeys,
    required this.selectedIdsListenable,
    required this.expandedKeys,
    required this.onToggleService,
    required this.onToggleExpand,
  });

  final Master master;
  final List<MasterService> services;

  /// Category keys hoisted to the top of the accordion (they contain a
  /// search-matched service). Empty ⇒ normal first-appearance category order.
  final Set<String> hoistedKeys;
  final ValueListenable<Set<String>> selectedIdsListenable;
  final Set<String> expandedKeys;
  final ValueChanged<String> onToggleService;
  final ValueChanged<String> onToggleExpand;

  @override
  ConsumerState<_CatalogueBody> createState() => _CatalogueBodyState();
}

class _CatalogueBodyState extends ConsumerState<_CatalogueBody> {
  // Memoized grouping (mobile-perf finding #1): re-bucketing `services` by
  // category + resolving each category's display label (which scans
  // `approvedCategoriesProvider`) is pure work over data that is IDENTICAL
  // across most rebuilds — e.g. every expand/collapse toggle re-runs this
  // widget's build (via the parent's `setState`) even though `services` and
  // the resolved category options never changed. Cache the grouped result
  // and only recompute when either input's identity actually changes.
  List<CatalogueCategoryGroup>? _cachedGroups;
  List<MasterService>? _cachedServices;
  List<ServiceCategoryOption>? _cachedOptions;

  List<CatalogueCategoryGroup> _groupsFor(
    AsyncValue<List<ServiceCategoryOption>> categoriesAsync,
    AppLocalizations l10n,
  ) {
    _rebuildIfNeeded(categoriesAsync, l10n);
    return _cachedGroups!;
  }

  void _rebuildIfNeeded(
    AsyncValue<List<ServiceCategoryOption>> categoriesAsync,
    AppLocalizations l10n,
  ) {
    final List<ServiceCategoryOption>? options = categoriesAsync.value;
    if (_cachedGroups != null &&
        identical(_cachedServices, widget.services) &&
        identical(_cachedOptions, options)) {
      return;
    }
    // Group by category (first-appearance order), then hoist the matched
    // categor(ies) to the top in the SAME memoized pass — `hoistedKeys` is a
    // stable reference for this screen's lifetime (seeded once), so it needs no
    // separate cache key.
    _cachedGroups = _hoistMatched(
      _group(widget.services, categoriesAsync, l10n),
    );
    _cachedServices = widget.services;
    _cachedOptions = options;
  }

  /// Stable partition: categories containing a search-matched service first (in
  /// their original relative order), then every other category (original
  /// order). A no-op when nothing was hoisted.
  List<CatalogueCategoryGroup> _hoistMatched(
    List<CatalogueCategoryGroup> groups,
  ) {
    if (widget.hoistedKeys.isEmpty) return groups;
    final List<CatalogueCategoryGroup> matched = <CatalogueCategoryGroup>[];
    final List<CatalogueCategoryGroup> rest = <CatalogueCategoryGroup>[];
    for (final CatalogueCategoryGroup g in groups) {
      (widget.hoistedKeys.contains(g.key) ? matched : rest).add(g);
    }
    return <CatalogueCategoryGroup>[...matched, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categoriesAsync = ref.watch(approvedCategoriesProvider);
    final List<CatalogueCategoryGroup> groups = _groupsFor(
      categoriesAsync,
      l10n,
    );
    String headerSemantics({
      required String label,
      required int count,
      required int selectedCount,
      required bool expanded,
    }) {
      final String state = expanded
          ? l10n.bookingCategoryExpandedState
          : l10n.bookingCategoryCollapsedState;
      // Reuses the existing services-list ICU key for the "Категорія X,
      // N послуг" core sentence, then appends the booking-only
      // selected-count and expand-state suffixes — see
      // services_list_screen.dart precedent for the count-suffix NOT
      // being routed through a fresh ARB entry.
      return '${l10n.servicesCategorySectionSemantics(label, count)}, $state'
          '${selectedCount > 0 ? ', обрано $selectedCount' : ''}';
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
                Text(l10n.bookingServiceSelectIntro, style: VelvetText.body14),
                const SizedBox(height: VelvetSpacing.lg),
                MasterStrip.fromMaster(
                  widget.master,
                  showRole: true,
                  showRating: true,
                ),
                const SizedBox(height: VelvetSpacing.xl),
              ],
            ),
          ),
        ),
        // Lazily built (mobile-perf finding #6): each category section only
        // builds once it scrolls into range, instead of every category being
        // constructed eagerly up front by a plain `Column` inside a
        // `SingleChildScrollView`.
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            0,
            VelvetSpacing.lg,
            VelvetSpacing.xxl,
          ),
          sliver: SliverList.separated(
            itemCount: groups.length,
            separatorBuilder: (BuildContext context, int i) =>
                const SizedBox(height: VelvetSpacing.md),
            itemBuilder: (BuildContext context, int i) => CatalogueCategorySection(
              key: Key(
                'booking_category_${groups[i].key.isEmpty ? '_none' : groups[i].key}',
              ),
              category: groups[i],
              expanded: widget.expandedKeys.contains(groups[i].key),
              selectedIdsListenable: widget.selectedIdsListenable,
              onToggleExpand: () => widget.onToggleExpand(groups[i].key),
              onToggleService: widget.onToggleService,
              headerSemanticsLabel: headerSemantics,
              tileKeyForId: _bookingTileKeyForId,
              headerVerticalPadding: VelvetSpacing.sm + 2,
            ),
          ),
        ),
      ],
    );
  }

  /// Groups [services] into category buckets in first-appearance order,
  /// mirroring `services_list_screen.dart`'s `_LoadedBodyState._group`.
  List<CatalogueCategoryGroup> _group(
    List<MasterService> services,
    AsyncValue<List<ServiceCategoryOption>> categoriesAsync,
    AppLocalizations l10n,
  ) {
    final Map<String, List<MasterService>> buckets =
        <String, List<MasterService>>{};
    for (final MasterService s in services) {
      final String key = (s.category ?? '').trim().toUpperCase();
      (buckets[key] ??= <MasterService>[]).add(s);
    }
    return buckets.entries
        .map((MapEntry<String, List<MasterService>> entry) {
          final bool isUncategorized = entry.key.isEmpty;
          final String label = isUncategorized
              ? l10n.serviceCategoryUncategorized
              : _resolveCategoryLabel(entry.key, categoriesAsync) ??
                    l10n.serviceCategoryUncategorized;
          return CatalogueCategoryGroup(
            key: entry.key,
            label: label,
            rows: <CatalogueRow>[
              for (final MasterService s in entry.value) _toCatalogueRow(s),
            ],
          );
        })
        .toList(growable: false);
  }

  String? _resolveCategoryLabel(
    String slug,
    AsyncValue<List<ServiceCategoryOption>> categoriesAsync,
  ) {
    final List<ServiceCategoryOption>? options = categoriesAsync.value;
    if (options != null) {
      for (final ServiceCategoryOption option in options) {
        if (categorySlugMatches(slug, option.name)) return option.displayName;
      }
    }
    return humanizeCategorySlug(slug);
  }
}
