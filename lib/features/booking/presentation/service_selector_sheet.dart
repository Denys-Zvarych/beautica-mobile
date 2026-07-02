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
import 'package:beautica_mobile/features/services/domain/category_slug.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import '../domain/booking_slot_picker_args.dart';
import 'widgets/booking_summary_bar.dart';
import 'widgets/master_strip.dart';

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
  // A [ValueNotifier] rather than a plain `Set` + `setState` field
  // (mobile-perf finding #2): toggling one checkbox must NOT rebuild the
  // whole screen (Scaffold → catalogue → every category → every tile) — only
  // the widgets that actually depend on the selection should react. Bottom
  // summary bar listens via [ValueListenableBuilder]; each [_CategorySection]
  // subscribes directly and only calls its OWN `setState` when the
  // selection *within that category* actually changed (see
  // `_CategorySectionState._handleSelectionChanged`), so sibling categories
  // and the rest of the tree never rebuild for an unrelated toggle.
  final ValueNotifier<Set<String>> _selectedIdsNotifier =
      ValueNotifier<Set<String>>(<String>{});
  final Set<String> _expandedKeys = <String>{};
  bool _seeded = false;

  @override
  void dispose() {
    _selectedIdsNotifier.dispose();
    super.dispose();
  }

  /// Seeds selection/expansion from [widget.initialServiceId] exactly once,
  /// the first time the catalogue resolves. A no-op on every later rebuild
  /// (guarded by [_seeded]), so toggling a section afterward is never
  /// overwritten by a stale re-seed.
  void _seedOnce(List<MasterService> services) {
    if (_seeded) return;
    _seeded = true;
    final String? initial = widget.initialServiceId;
    if (initial == null || initial.isEmpty) return;
    final MasterService? match = services
        .where((MasterService s) => s.id == initial)
        .firstOrNull;
    if (match == null) return;
    _selectedIdsNotifier.value = <String>{match.id};
    _expandedKeys.add((match.category ?? '').trim().toUpperCase());
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
            valueListenable: _selectedIdsNotifier,
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
                    selectedIdsListenable: _selectedIdsNotifier,
                    expandedKeys: _expandedKeys,
                    onToggleService: _toggleService,
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
// Catalogue body — category accordions
// ---------------------------------------------------------------------------

class _CatalogueBody extends ConsumerStatefulWidget {
  const _CatalogueBody({
    required this.master,
    required this.services,
    required this.selectedIdsListenable,
    required this.expandedKeys,
    required this.onToggleService,
    required this.onToggleExpand,
  });

  final Master master;
  final List<MasterService> services;
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
  List<_CategoryGroup>? _cachedGroups;
  List<MasterService>? _cachedServices;
  List<ServiceCategoryOption>? _cachedOptions;

  List<_CategoryGroup> _groupsFor(
    AsyncValue<List<ServiceCategoryOption>> categoriesAsync,
    AppLocalizations l10n,
  ) {
    final List<ServiceCategoryOption>? options = categoriesAsync.value;
    final List<_CategoryGroup>? cached = _cachedGroups;
    if (cached != null &&
        identical(_cachedServices, widget.services) &&
        identical(_cachedOptions, options)) {
      return cached;
    }
    final List<_CategoryGroup> groups = _group(
      widget.services,
      categoriesAsync,
      l10n,
    );
    _cachedGroups = groups;
    _cachedServices = widget.services;
    _cachedOptions = options;
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categoriesAsync = ref.watch(approvedCategoriesProvider);
    final List<_CategoryGroup> groups = _groupsFor(categoriesAsync, l10n);

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
                  l10n.bookingServiceSelectIntro,
                  style: VelvetText.body().copyWith(fontSize: 14),
                ),
                const SizedBox(height: VelvetSpacing.lg),
                MasterStrip(master: widget.master),
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
            itemBuilder: (BuildContext context, int i) => _CategorySection(
              key: Key(
                'booking_category_${groups[i].key.isEmpty ? '_none' : groups[i].key}',
              ),
              group: groups[i],
              expanded: widget.expandedKeys.contains(groups[i].key),
              selectedIdsListenable: widget.selectedIdsListenable,
              onToggleExpand: () => widget.onToggleExpand(groups[i].key),
              onToggleService: widget.onToggleService,
            ),
          ),
        ),
      ],
    );
  }

  /// Groups [services] into category buckets in first-appearance order,
  /// mirroring `services_list_screen.dart`'s `_LoadedBodyState._group`.
  List<_CategoryGroup> _group(
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
          return _CategoryGroup(
            key: entry.key,
            label: label,
            services: entry.value,
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

@immutable
class _CategoryGroup {
  const _CategoryGroup({
    required this.key,
    required this.label,
    required this.services,
  });

  final String key;
  final String label;
  final List<MasterService> services;
}

// ---------------------------------------------------------------------------
// Category accordion section
// ---------------------------------------------------------------------------

class _CategorySection extends StatefulWidget {
  const _CategorySection({
    super.key,
    required this.group,
    required this.expanded,
    required this.selectedIdsListenable,
    required this.onToggleExpand,
    required this.onToggleService,
  });

  final _CategoryGroup group;
  final bool expanded;
  final ValueListenable<Set<String>> selectedIdsListenable;
  final VoidCallback onToggleExpand;
  final ValueChanged<String> onToggleService;

  @override
  State<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<_CategorySection> {
  // mobile-perf finding #2: toggling a checkbox anywhere on screen notifies
  // the SHARED `selectedIdsListenable`, but this section only rebuilds
  // itself (via its OWN `setState`) when the subset of ITS OWN services that
  // are selected actually changed — a toggle inside a sibling category is a
  // no-op here, so sibling `_CategorySection`s never rebuild for it.
  late Set<String> _selectedInGroup;

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
    } else if (!identical(oldWidget.group, widget.group)) {
      // Catalogue data changed (new services/categories) — recompute
      // unconditionally rather than waiting for the next notification.
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
      for (final MasterService s in widget.group.services)
        if (selected.contains(s.id)) s.id,
    };
  }

  void _handleSelectionChanged() {
    final Set<String> next = _computeSelectedInGroup();
    if (setEquals(next, _selectedInGroup)) return;
    setState(() => _selectedInGroup = next);
  }

  @override
  Widget build(BuildContext context) {
    final _CategoryGroup group = widget.group;
    final bool expanded = widget.expanded;
    final int selectedInCat = _selectedInGroup.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _CategoryHeader(
          label: group.label,
          count: group.services.length,
          selectedCount: selectedInCat,
          expanded: expanded,
          onTap: widget.onToggleExpand,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          // Rows are only constructed while expanded (mobile-perf finding
          // #2's collapsed-state half) — a collapsed category pays no
          // `_ServiceSelectTile` build cost at all.
          child: expanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final MasterService s in group.services)
                      Padding(
                        padding: const EdgeInsets.only(top: VelvetSpacing.md),
                        child: _ServiceSelectTile(
                          key: Key('booking_service_tile_${s.id}'),
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

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    required this.label,
    required this.count,
    required this.selectedCount,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final int count;
  final int selectedCount;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String state = expanded
        ? l10n.bookingCategoryExpandedState
        : l10n.bookingCategoryCollapsedState;
    // Reuses the existing services-list ICU key for the "Категорія X, N
    // послуг" core sentence, then appends the booking-only selected-count and
    // expand-state suffixes — see services_list_screen.dart precedent for the
    // count-suffix NOT being routed through a fresh ARB entry.
    final String semanticsLabel =
        '${l10n.servicesCategorySectionSemantics(label, count)}, $state'
        '${selectedCount > 0 ? ', обрано $selectedCount' : ''}';

    return Semantics(
      button: true,
      header: true,
      expanded: expanded,
      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: VelvetSpacing.md,
            vertical: VelvetSpacing.sm + 2,
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
              if (selectedCount > 0) ...<Widget>[
                _SelectedBadge(count: selectedCount),
                const SizedBox(width: VelvetSpacing.sm),
              ],
              _CountBadge(count: count),
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

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.circular(VelvetRadii.pill),
        boxShadow: VelvetShadows.extrudedSmall,
      ),
      child: Text(
        '$count',
        style: VelvetText.feedback(
          BrandColors.textSecondary,
        ).copyWith(fontSize: 12.5, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _SelectedBadge extends StatelessWidget {
  const _SelectedBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[BrandColors.accentLatte, BrandColors.accentDeep],
        ),
        borderRadius: BorderRadius.all(Radius.circular(VelvetRadii.pill)),
        boxShadow: VelvetShadows.extrudedSmall,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.sm,
        vertical: 3,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.check_rounded, size: 12, color: BrandColors.white),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: VelvetText.feedback(
              BrandColors.white,
            ).copyWith(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ],
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

  final MasterService service;
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
    final MasterService s = widget.service;
    final String typeName = (s.serviceTypeNameUk ?? '').trim();
    final String customName = s.name.trim();
    final String name = customName.isNotEmpty ? customName : typeName;
    final String duration = DurationMinutes.format(s.durationMinutes);
    final String price = ServicePriceDisplay.format(s);
    final bool sel = widget.selected;

    return Semantics(
      button: true,
      checked: sel,
      label: l10n.bookingServiceTileSemantics(name, duration, price),
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
                        name,
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
                            duration,
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
                  price,
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
