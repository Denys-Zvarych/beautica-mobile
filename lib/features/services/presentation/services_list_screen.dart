// Phase 5.2 — Services List Screen.
//
// The INDEPENDENT_MASTER's "Мої послуги" catalogue. Three AsyncValue states:
//   • loading → three [_SkeletonCard] widgets (shimmer sweep)
//   • data    → if empty: [_EmptyState]; else [ListView.builder] of [_ServiceCard]
//   • error   → [ErrorState] with retry
//
// A neumorphic extended FAB (hidden in the empty state: the empty state has its
// own primary CTA) sits bottom-right via [Scaffold.floatingActionButton].
//
// Pull-to-refresh via [RefreshIndicator] delegates to
// [ServicesListNotifier.refresh].
//
// Design source: `docs/signup-designs/ServiceListScreen/lib/screens/service_list_screen.dart`
// and `service_widgets.dart` — transcribed 1:1; local state / Navigator
// replaced by Riverpod notifier + go_router.

import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/app_refresh_indicator.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/category_slug.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';

import 'services_list_notifier.dart';

export 'services_list_notifier.dart' show servicesListProvider;

/// The INDEPENDENT_MASTER's services catalogue screen.
///
/// Handles all three [AsyncValue] states (loading / data / error).
/// Pull-to-refresh triggers [ServicesListNotifier.refresh].
///
/// [initialExpandCategory] — when non-null and non-empty, the matching
/// category section is pre-expanded on first build and all others start
/// collapsed. When null or empty (the default — e.g. "Усі послуги" link or
/// bottom-nav "Послуги" tab) ALL sections start collapsed; the user can
/// toggle any section freely afterward.
/// Passed from the profile screen's category cards via the `expandCategory`
/// query parameter on the `/services` route.
///
/// Converted to [ConsumerStatefulWidget] to manage the [ScreenProtector]
/// lifecycle (SEC MEDIUM-1): screenshot suppression is enabled in release
/// builds on entry and lifted on exit, matching the project-wide pattern
/// used by [MasterProfileScreen].
class ServicesListScreen extends ConsumerStatefulWidget {
  const ServicesListScreen({super.key, this.initialExpandCategory});

  /// Optional upper-cased wire slug. When set, the matching category section
  /// is pre-expanded and all others start collapsed on first entry. When null
  /// or empty all sections start collapsed (the default).
  final String? initialExpandCategory;

  @override
  ConsumerState<ServicesListScreen> createState() => _ServicesListScreenState();
}

class _ServicesListScreenState extends ConsumerState<ServicesListScreen> {
  // Captured in initState so dispose() never touches `ref` — under Riverpod
  // 3.x using `ref` in dispose() throws. Hold the keepAlive manager instead.
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC MEDIUM: ref-counted screenshot + iOS app-switcher-snapshot guard
    // (single app-wide owner; the manager is internally !kDebugMode-guarded).
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
    // The approved-category list ([approvedCategoriesProvider], keepAlive) is
    // cached in the root container for the whole session, so the picker can go
    // stale after an admin approves a category server-side. Invalidating on
    // first entry guarantees a fresh fetch every time this screen mounts.
    // (Returns to this kept-alive route are handled by [_openAndRefresh],
    // since initState does NOT re-fire on pop-back.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.invalidate(approvedCategoriesProvider);
        // Also drop the whole service-types family (no arg = all categories):
        // a type newly approved under an EXISTING category must appear on entry.
        ref.invalidate(serviceTypesProvider);
      }
    });
  }

  @override
  void dispose() {
    _screenProtection.release();
    super.dispose();
  }

  /// Pushes [location] and, once the pushed flow pops back to this (kept-alive)
  /// screen, invalidates [approvedCategoriesProvider] so a category approved
  /// by an admin while the user was away appears without a cold restart.
  ///
  /// This is the route-return hook: because the /services route is kept alive,
  /// [initState] fires only on first entry and will NOT re-run on pop-back —
  /// awaiting the [GoRouter.push] Future (which completes when the destination
  /// pops) is the simplest mechanism that reliably re-fires on every return
  /// from the create / edit / request-category flows.
  Future<void> _openAndRefresh(String location) async {
    await context.push<void>(location);
    if (mounted) {
      ref.invalidate(approvedCategoriesProvider);
      ref.invalidate(serviceTypesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final asyncServices = ref.watch(servicesListProvider);

    return Scaffold(
      backgroundColor: BrandColors.base,
      appBar: _ServicesAppBar(title: l10n.servicesTitle),
      floatingActionButton: asyncServices.maybeWhen(
        data: (list) => list.isEmpty
            ? null
            : _NeumorphicExtendedFab(
                key: const Key('btn-create-service'),
                label: l10n.servicesAdd,
                onTap: () => _openAndRefresh(RouteNames.serviceCreate),
              ),
        orElse: () => null,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: AppRefreshIndicator(
        // Pull-to-refresh refreshes BOTH the master's own services AND the
        // approved-category cache, so a category approved by an admin appears
        // on the next pull without a cold restart. `refresh()` awaits the
        // services reload; the category provider is invalidated (re-fetches
        // lazily on the next watch) — both are kicked off here.
        onRefresh: () async {
          ref.invalidate(approvedCategoriesProvider);
          ref.invalidate(serviceTypesProvider);
          // approvedCategoriesProvider and serviceTypesProvider are intentionally
          // NOT awaited: their stale humanized-label fallback degrades gracefully,
          // and the spinner dismissal is gated only on the services re-fetch below.
          await ref.read(servicesListProvider.notifier).refresh();
        },
        child: asyncServices.when(
          loading: () => const _LoadingBody(),
          error: (e, _) {
            log(
              'ServicesListScreen: async error — $e',
              name: 'feature.services.presentation',
              level: 900,
            );
            final failure = e is Failure ? e : UnknownFailure(cause: e);
            return _errorScrollable(
              ErrorState(
                key: const Key('services_error_state'),
                failure: failure,
                onRetry: () => ref.invalidate(servicesListProvider),
              ),
            );
          },
          data: (list) {
            if (list.isEmpty) {
              // First-time path: a master with zero services lands on the
              // one-pass setup screen (bulk menu builder), NOT the single-create
              // form. The setup screen invalidates this list and routes back
              // here (now populated) on a successful bulk save.
              return _EmptyState(
                onCreate: () => _openAndRefresh(RouteNames.serviceSetup),
              );
            }
            return _LoadedBody(
              onOpen: _openAndRefresh,
              services: list,
              initialExpandCategory: widget.initialExpandCategory,
            );
          },
        ),
      ),
    );
  }

  /// Wraps [child] in a [SingleChildScrollView] with [AlwaysScrollableScrollPhysics]
  /// so [RefreshIndicator] can still be triggered even on the error state, which
  /// might not have enough content to scroll naturally.
  Widget _errorScrollable(Widget child) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(height: 400, child: child),
    );
  }
}

// ---------------------------------------------------------------------------
// App bar
// ---------------------------------------------------------------------------

class _ServicesAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ServicesAppBar({required this.title});

  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: BrandColors.base,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      title: Text(title, style: VelvetText.heading()),
    );
  }
}

// ---------------------------------------------------------------------------
// Loaded body
// ---------------------------------------------------------------------------

class _LoadedBody extends ConsumerStatefulWidget {
  const _LoadedBody({
    required this.onOpen,
    required this.services,
    this.initialExpandCategory,
  });

  /// Pushes a route and invalidates [approvedCategoriesProvider] on return.
  /// Provided by [_ServicesListScreenState._openAndRefresh].
  final Future<void> Function(String location) onOpen;

  final List<MasterService> services;

  /// Upper-cased wire slug of the category to pre-expand on first build.
  /// When null or empty all sections start collapsed (the default).
  final String? initialExpandCategory;

  @override
  ConsumerState<_LoadedBody> createState() => _LoadedBodyState();
}

class _LoadedBodyState extends ConsumerState<_LoadedBody> {
  // PERF A2 (MEDIUM): the memoized grouping. Re-run [_group] only when the
  // identity of (services, categories.value) changes, so a label-only category
  // refresh ([approvedCategoriesProvider] invalidated on entry / return / pull)
  // does not re-bucket. Living in [State] keeps the cache alive across the
  // frequent rebuilds those invalidations trigger.
  List<MasterService>? _cachedServices;
  List<ServiceCategoryOption>? _cachedCategories;
  List<_CategoryGroup>? _cachedGroups;
  // P-M2 fix: cache the _flatten() result. Invalidated whenever _cachedGroups
  // is recomputed (identity change of services or categories).
  List<_ListItem>? _cachedItems;

  List<_CategoryGroup> _resolveGroups(
    AsyncValue<List<ServiceCategoryOption>> categoriesAsync,
    String uncategorizedLabel,
  ) {
    final List<ServiceCategoryOption>? categoriesValue = categoriesAsync.value;
    final bool hit =
        _cachedGroups != null &&
        identical(_cachedServices, widget.services) &&
        identical(_cachedCategories, categoriesValue);
    if (hit) return _cachedGroups!;

    final List<_CategoryGroup> groups = _group(
      categoriesAsync,
      uncategorizedLabel,
    );
    _cachedServices = widget.services;
    _cachedCategories = categoriesValue;
    _cachedGroups = groups;
    // P-M2: invalidate the flatten cache whenever groups are recomputed.
    _cachedItems = null;
    return groups;
  }

  /// Resolves a category wire slug to a display label using the same source the
  /// service form uses ([approvedCategoriesProvider]):
  ///   • match found in the approved list → the Ukrainian [displayName];
  ///   • slug absent (inactive/retired) OR the provider is still loading /
  ///     errored → [humanizeCategorySlug] so the user sees "Brows", never the
  ///     raw ALL-CAPS wire value "BROWS".
  /// Returns null when the service has no category at all.
  String? _resolveCategoryLabel(
    String? slug,
    AsyncValue<List<ServiceCategoryOption>> categoriesAsync,
  ) {
    if (slug == null || slug.isEmpty) return null;
    // `.value` returns the data when in AsyncData state, null otherwise
    // (loading / error) — the humanized fallback covers those states.
    final List<ServiceCategoryOption>? options = categoriesAsync.value;
    if (options != null) {
      for (final ServiceCategoryOption option in options) {
        if (categorySlugMatches(slug, option.name)) return option.displayName;
      }
    }
    return humanizeCategorySlug(slug);
  }

  /// Groups the widget's services into ordered category buckets, preserving the
  /// EXACT creation order the list provider returns.
  ///
  /// - Within a bucket, services keep their original relative order.
  /// - Category buckets are ordered by the FIRST appearance of a service in
  ///   that category in the creation-ordered list (stable, tied to creation
  ///   order — never alphabetical or by price).
  /// - Services with no category share a single trailing bucket keyed on the
  ///   empty string.
  ///
  /// A [LinkedHashMap] preserves insertion order, so iterating the entries
  /// yields the buckets in first-appearance order without an explicit sort.
  /// Each bucketed service is paired with a continuous [_CardEntry.staggerIndex]
  /// (counted across section boundaries) so the entrance cascade is unbroken.
  List<_CategoryGroup> _group(
    AsyncValue<List<ServiceCategoryOption>> categoriesAsync,
    String uncategorizedLabel,
  ) {
    // Bucket key: the upper-cased wire slug, or '' for uncategorized — so two
    // services tagged 'brows' and 'BROWS' land in the same bucket.
    final Map<String, List<MasterService>> buckets =
        <String, List<MasterService>>{};
    for (final MasterService s in widget.services) {
      final String key = (s.category ?? '').trim().toUpperCase();
      (buckets[key] ??= <MasterService>[]).add(s);
    }
    // Running index across all cards, in first-appearance + creation order, so
    // the staggered entrance animation keeps a continuous cascade across
    // section boundaries (preserves the prior behaviour exactly).
    var cardIndex = 0;
    return buckets.entries
        .map((entry) {
          final bool isUncategorized = entry.key.isEmpty;
          final String label = isUncategorized
              ? uncategorizedLabel
              : _resolveCategoryLabel(entry.key, categoriesAsync) ??
                    uncategorizedLabel;
          final List<_CardEntry> cards = <_CardEntry>[
            for (final MasterService service in entry.value)
              _CardEntry(service: service, staggerIndex: cardIndex++),
          ];
          return _CategoryGroup(key: entry.key, label: label, cards: cards);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categoriesAsync = ref.watch(approvedCategoriesProvider);

    final List<_CategoryGroup> groups = _resolveGroups(
      categoriesAsync,
      l10n.serviceCategoryUncategorized,
    );

    // Normalise the requested slug once for O(1) per-section comparison.
    final String? targetSlug =
        (widget.initialExpandCategory?.trim().toUpperCase() ?? '').isEmpty
        ? null
        : widget.initialExpandCategory!.trim().toUpperCase();

    // PERF A1 (HIGH): flatten the active-count header + ordered groups into a
    // single typed item list (header, section, section, …) once, then drive a
    // lazy [ListView.builder] off it. This restores off-screen / collapsed
    // construction laziness (resolves M1 + L1) — only visible sections are
    // built, so off-screen cards never allocate an AnimationController nor
    // schedule a Future.delayed entrance timer.
    //
    // P-M2 fix: cache the flattened list and only recompute when groups
    // changed by identity (tracked via _cachedItems null-check set by
    // _resolveGroups on cache miss).
    _cachedItems ??= _flatten(l10n, groups, widget.services.length);
    final List<_ListItem> items = _cachedItems!;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.md,
        VelvetSpacing.lg,
        // Bottom padding so the last card clears the floating FAB.
        VelvetSpacing.xxl + VelvetSpacing.xl,
      ),
      itemCount: items.length,
      itemBuilder: (BuildContext context, int index) {
        final _ListItem item = items[index];
        switch (item) {
          case _HeaderItem(:final label):
            return Padding(
              padding: const EdgeInsets.only(bottom: VelvetSpacing.sm),
              child: Text(label, style: VelvetText.label()),
            );
          case _SectionItem(:final group):
            // When a target slug was requested:
            //   • the matching section starts expanded,
            //   • every other section starts collapsed.
            // When no target slug is set (null — "Усі послуги" link or
            // bottom-nav tab) all sections start collapsed.
            final bool initiallyExpanded =
                targetSlug != null && group.key == targetSlug;
            final String sectionSlug = group.key.isEmpty ? '_none' : group.key;
            return Padding(
              padding: const EdgeInsets.only(bottom: VelvetSpacing.md),
              child: _CategorySection(
                // Stable key per bucket so expand/collapse state survives
                // rebuilds (e.g. category-cache invalidation on screen return).
                // Also used by widget tests and profile card navigation.
                key: Key('category_section_$sectionSlug'),
                title: group.label,
                count: group.cards.length,
                initiallyExpanded: initiallyExpanded,
                children: <Widget>[
                  for (final _CardEntry entry in group.cards)
                    Padding(
                      padding: const EdgeInsets.only(top: VelvetSpacing.md),
                      child: _ServiceCard(
                        key: Key('service_card_${entry.service.id}'),
                        service: entry.service,
                        onEdit: () => widget.onOpen(
                          RouteNames.serviceEdit(entry.service.id),
                        ),
                        // P-M3 fix: cap the effective stagger index at 5 so
                        // the maximum outstanding delay is 90*5 = 450 ms,
                        // regardless of list length. Visual behaviour is
                        // identical for the first 6 cards.
                        appearDelay: Duration(
                          milliseconds: 90 * entry.staggerIndex.clamp(0, 5),
                        ),
                      ),
                    ),
                ],
              ),
            );
        }
      },
    );
  }

  /// Flattens the active-count header + ordered [groups] into a single typed
  /// item list for the lazy [ListView.builder]. Each category section carries
  /// its own cards (with their precomputed continuous stagger index) so the
  /// builder can construct one section at a time as it scrolls into view.
  List<_ListItem> _flatten(
    AppLocalizations l10n,
    List<_CategoryGroup> groups,
    int total,
  ) {
    return <_ListItem>[
      _HeaderItem(_activeServicesLabel(l10n, total)),
      for (final _CategoryGroup group in groups) _SectionItem(group),
    ];
  }

  /// Formats the count sub-heading.
  ///
  /// Full localisation for plural forms is deferred until the l10n team approves
  /// Ukrainian plural copy; for now a simple Ukrainian string is used inline
  /// (will migrate to ARB once copy is approved — backlog LOW).
  String _activeServicesLabel(AppLocalizations l10n, int count) =>
      '$count ${_serviceWordUk(count)}';

  String _serviceWordUk(int n) {
    if (n % 100 >= 11 && n % 100 <= 14) return 'послуг';
    switch (n % 10) {
      case 1:
        return 'послуга';
      case 2:
      case 3:
      case 4:
        return 'послуги';
      default:
        return 'послуг';
    }
  }
}

// ---------------------------------------------------------------------------
// Category grouping
// ---------------------------------------------------------------------------

/// A single service paired with its continuous entrance-stagger index.
///
/// [staggerIndex] is assigned in first-appearance + creation order across ALL
/// sections so the staggered fade/rise cascade is unbroken across section
/// boundaries — independent of which section the card lives in.
@immutable
class _CardEntry {
  const _CardEntry({required this.service, required this.staggerIndex});

  final MasterService service;
  final int staggerIndex;
}

/// An ordered bucket of services that share a category.
///
/// [key] is the upper-cased wire slug (or '' for uncategorized) and is used to
/// derive a stable widget key. [label] is the display-ready Ukrainian header.
/// [cards] preserve their creation order within the bucket and carry the
/// continuous stagger index for the entrance animation.
@immutable
class _CategoryGroup {
  const _CategoryGroup({
    required this.key,
    required this.label,
    required this.cards,
  });

  final String key;
  final String label;
  final List<_CardEntry> cards;
}

// ---------------------------------------------------------------------------
// Flattened list items (header + sections) for the lazy ListView.builder
// ---------------------------------------------------------------------------

/// One row in the flattened item list driving [ListView.builder].
@immutable
sealed class _ListItem {
  const _ListItem();
}

/// The active-count sub-heading row at the top of the list.
@immutable
class _HeaderItem extends _ListItem {
  const _HeaderItem(this.label);

  final String label;
}

/// A category section (header pillow + its collapsible cards).
@immutable
class _SectionItem extends _ListItem {
  const _SectionItem(this.group);

  final _CategoryGroup group;
}

// ---------------------------------------------------------------------------
// Expandable category section
// ---------------------------------------------------------------------------

/// A soft neumorphic disclosure section: an extruded header pillow (category
/// name + count badge + rotating chevron) over a collapsible body of service
/// cards.
///
/// [initiallyExpanded] controls the initial open/close state of this section:
/// `true` starts expanded, `false` (the default) starts collapsed. The
/// [_LoadedBodyState] passes `true` only for the explicitly-targeted category
/// (when the master navigated via a specific category card). The user can
/// toggle freely after first build — the initial value is applied only once
/// in [initState].
///
/// This is the VelvetTouch analogue of an [ExpansionTile] — no raw Material
/// chrome. The header reuses the same [BrandColors.base] + [VelvetShadows]
/// language as the cards beneath it so the page reads as one carved surface.
class _CategorySection extends StatefulWidget {
  const _CategorySection({
    super.key,
    required this.title,
    required this.count,
    required this.children,
    this.initiallyExpanded = false,
  });

  final String title;
  final int count;
  final List<Widget> children;

  /// Whether this section starts expanded. Applied once in [initState];
  /// the user can toggle freely afterward. Defaults to `false` (collapsed).
  /// [_LoadedBodyState] passes `true` only for the explicitly-requested
  /// category (non-null [_LoadedBody.initialExpandCategory] that matches this
  /// section's slug).
  final bool initiallyExpanded;

  @override
  State<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<_CategorySection> {
  // Seeded from widget.initiallyExpanded in initState.
  late bool _expanded;

  // P-M1 fix: hoisted to avoid per-build TextStyle allocation.
  static final TextStyle _headerStyle = VelvetText.subheading().copyWith(
    fontSize: 16,
  );

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          button: true,
          header: true,
          expanded: _expanded,
          label: l10n.servicesCategorySectionSemantics(
            widget.title,
            widget.count,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
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
                      widget.title,
                      style: _headerStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: VelvetSpacing.sm),
                  _CategoryCountBadge(count: widget.count),
                  const SizedBox(width: VelvetSpacing.sm),
                  AnimatedRotation(
                    // 0.25 turns = 90°: chevron points down when expanded,
                    // right when collapsed.
                    turns: _expanded ? 0.0 : -0.25,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: BrandColors.accent,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Collapsible body — AnimatedSize gives a smooth reveal/hide that keeps
        // the cards' own staggered entrance intact on first build.
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.children,
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}

/// A small recessed count badge shown on the right of a category header.
class _CategoryCountBadge extends StatelessWidget {
  const _CategoryCountBadge({required this.count});

  final int count;

  // Hoisted to avoid per-build allocation.
  static final TextStyle _style = VelvetText.pill().copyWith(fontSize: 12.5);

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
      child: Text('$count', style: _style),
    );
  }
}

// ---------------------------------------------------------------------------
// Service card
// ---------------------------------------------------------------------------

/// A tappable service card. Extrudes at rest; depresses (scale 0.99, shadow
/// removed) on press for tactile "tap-to-edit" affordance.
///
/// Entrance animation: staggered fade + rise driven by [appearDelay].
class _ServiceCard extends StatefulWidget {
  const _ServiceCard({
    super.key,
    required this.service,
    required this.onEdit,
    this.appearDelay = Duration.zero,
  });

  final MasterService service;

  /// Opens the edit form for this service and invalidates the category cache
  /// on return. Provided by [_LoadedBody.onOpen].
  final VoidCallback onEdit;

  final Duration appearDelay;

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _appear;

  // PERF MEDIUM-1: CurvedAnimation moved from build() to initState() so a
  // new instance is not allocated on every frame. Typed as CurvedAnimation
  // (not Animation<double>) so dispose() is accessible.
  late final CurvedAnimation _curve;

  // P-H1 fix: pre-built SlideTransition offset animation. Derived from
  // _curve so it shares the same timing. FadeTransition + SlideTransition
  // are compositing-friendly — they do not create extra raster layers unlike
  // Opacity + Transform.translate.
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _appear = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _curve = CurvedAnimation(parent: _appear, curve: Curves.easeOutCubic);
    // P-H1: derive the slide animation once here (mirrors _ProfileBody._revealWith).
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(_curve);
    if (widget.appearDelay == Duration.zero) {
      _appear.forward();
    } else {
      Future<void>.delayed(widget.appearDelay, () {
        if (mounted) _appear.forward();
      });
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _appear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MasterService s = widget.service;
    final durationLabel = DurationMinutes.format(s.durationMinutes);
    // Price label: FIXED renders the server-formatted priceDisplay
    // ("750 грн"); RANGE is reformatted client-side to a hyphenated band
    // ("200 - 600 грн") via [ServicePriceDisplay]. Falls back gracefully when
    // priceDisplay is empty (pre-V67 data / broken contract).
    final priceLabel = ServicePriceDisplay.format(s);

    // Item 1: the PRIMARY card label is the platform service-type name
    // (e.g. "Стрижка"), not the master's custom name. The custom name — now
    // optional — is shown as a quiet secondary line ONLY when it is present AND
    // differs from the service-type label (so we never echo the same text
    // twice). When no service type is selected the custom name (or, if also
    // empty, the empty string) takes the primary slot so a card is never blank.
    //
    // M4 (contract correctness): serviceTypeNameUk is read straight off the
    // mapped MasterService; the mapper sources it from
    // MasterServiceResponse.serviceTypeNameUk (top-level, V16.3+) with a
    // ServiceDefinitionResponse.serviceTypeNameUk fallback — both confirmed
    // present in the generated DTOs. A null here means no type is assigned,
    // NOT a dropped field.
    final String typeName = (s.serviceTypeNameUk ?? '').trim();
    final String customName = s.name.trim();
    final String primaryLabel = typeName.isNotEmpty ? typeName : customName;
    final String? secondaryLabel =
        (typeName.isNotEmpty && customName.isNotEmpty && customName != typeName)
        ? customName
        : null;

    // P-H1 fix: FadeTransition + SlideTransition replace Opacity +
    // Transform.translate. Both transitions are compositing-friendly and
    // do not force an extra GPU raster layer per card.
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: _slide,
        child: Semantics(
          button: true,
          label:
              '$primaryLabel. '
              '${secondaryLabel != null ? '$secondaryLabel. ' : ''}'
              '$durationLabel, $priceLabel. Редагувати',
          // priceLabel renders from priceDisplay (server-formatted) so the
          // accessibility label always matches what the user sees in the card.
          child: GestureDetector(
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) {
              setState(() => _pressed = false);
              widget.onEdit();
            },
            child: AnimatedScale(
              scale: _pressed ? 0.99 : 1.0,
              duration: const Duration(milliseconds: 110),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: BrandColors.base,
                  borderRadius: BorderRadius.circular(VelvetRadii.card),
                  boxShadow: _pressed ? null : VelvetShadows.extrudedCard,
                ),
                // Compact dense row: tighter vertical padding (~halved height)
                // versus the original VelvetSpacing.sm + 2 with a stacked pill
                // Wrap below the title.
                padding: const EdgeInsets.fromLTRB(
                  VelvetSpacing.sm + 2,
                  VelvetSpacing.sm,
                  VelvetSpacing.sm + 2,
                  VelvetSpacing.sm,
                ),
                child: Row(
                  children: <Widget>[
                    _PhotoThumbnail(key: Key('thumb_${s.id}')),
                    const SizedBox(width: VelvetSpacing.sm + 2),
                    Expanded(
                      child: _ServiceInfo(
                        name: primaryLabel,
                        secondaryName: secondaryLabel,
                        durationLabel: durationLabel,
                        priceLabel: priceLabel,
                      ),
                    ),
                    const SizedBox(width: VelvetSpacing.sm),
                    const _EditButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Photo thumbnail (no-photo placeholder — service photo deferred to Phase 9.x)
// ---------------------------------------------------------------------------

/// 40×40 recessed inset well with a centred camel spa icon.
///
/// Compact-row sizing (was 48×48) so the dense list fits more rows on screen.
/// When actual photo upload is implemented (Phase 9.x), this widget will
/// accept a `photoUrl` and render an [Image.network] inside the same
/// 40×40 rounded [ClipRRect]. Until then, every service shows the icon
/// placeholder so depth always comes from shadows, never a flat grey box.
class _PhotoThumbnail extends StatelessWidget {
  const _PhotoThumbnail({super.key});

  static const double _size = 40;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _size,
      width: _size,
      child: NeumorphicInset(
        radius: VelvetRadii.field,
        child: Center(
          child: Icon(
            Icons.spa_rounded,
            size: 18,
            color: BrandColors.accent.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Service info (name + pills)
// ---------------------------------------------------------------------------

class _ServiceInfo extends StatelessWidget {
  const _ServiceInfo({
    required this.name,
    required this.durationLabel,
    required this.priceLabel,
    this.secondaryName,
  });

  /// Primary card label — the platform service-type name (Item 1), or the
  /// custom name as a fallback when no service type is assigned.
  final String name;

  /// Optional secondary label — the master's custom name, shown as a quiet
  /// subtitle beneath [name] only when a custom name is present and differs
  /// from the service-type label. Null suppresses the row entirely.
  final String? secondaryName;

  final String durationLabel;
  final String priceLabel;

  // Hoisted to avoid per-build allocation (MEDIUM-3).
  static final TextStyle _nameStyle = VelvetText.cardTitle().copyWith(
    fontSize: 15,
    height: 1.15,
  );

  // Secondary (custom name) style — quieter than the primary: smaller and
  // muted, so the service-type name stays the dominant label.
  static final TextStyle _secondaryStyle = VelvetText.pill().copyWith(
    fontSize: 12.5,
  );

  @override
  Widget build(BuildContext context) {
    final String? secondary = secondaryName;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          name,
          // Compact row: single line, slightly smaller than the full cardTitle
          // so the dense list reads as rows rather than tall cards.
          style: _nameStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (secondary != null) ...<Widget>[
          const SizedBox(height: 1),
          Text(
            secondary,
            key: const Key('service-card-custom-name'),
            style: _secondaryStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: VelvetSpacing.xs),
        // Inline duration · price metadata line. The category is shown as the
        // section header the card lives under, not here.
        _MetaLine(durationLabel: durationLabel, priceLabel: priceLabel),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Inline metadata line (replaces the stacked inset pills for density)
// ---------------------------------------------------------------------------

/// A compact, single-line metadata strip: a duration glyph + value, a thin
/// divider dot, and a price glyph + value.
///
/// Overflow-safe: the whole strip clips with an ellipsis if the row is narrow.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.durationLabel, required this.priceLabel});

  final String durationLabel;
  final String priceLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _MetaItem(icon: Icons.schedule_rounded, value: durationLabel),
        const _MetaDot(),
        Flexible(
          child: _MetaItem(icon: Icons.sell_rounded, value: priceLabel),
        ),
      ],
    );
  }
}

/// A small icon + value pair used inside [_MetaLine]. Compact glyph (13) and
/// the existing [VelvetText.pill] tone, but flat (no inset well).
class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.value});

  final IconData icon;
  final String value;

  // Hoisted to avoid per-build allocation (MEDIUM-3).
  static final TextStyle _valueStyle = VelvetText.pill().copyWith(
    fontSize: 12.5,
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 13, color: BrandColors.accent),
        const SizedBox(width: VelvetSpacing.xs),
        Flexible(
          child: Text(
            value,
            style: _valueStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// A thin separator dot between metadata items.
class _MetaDot extends StatelessWidget {
  const _MetaDot();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.sm - 2),
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: BrandColors.accent.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trailing edit button
// ---------------------------------------------------------------------------

/// 30×30 neumorphic raised pillow with the edit icon. Signals tap-to-edit.
///
/// Compact-row sizing (was 32×32). The whole row remains the tap target for
/// edit, so this remains a non-interactive affordance glyph.
class _EditButton extends StatelessWidget {
  const _EditButton();

  // Hoisted: VelvetRadii.field is a compile-time constant.
  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(VelvetRadii.field),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      width: 30,
      decoration: const BoxDecoration(
        color: BrandColors.base,
        borderRadius: _radius,
        boxShadow: VelvetShadows.extrudedSmall,
      ),
      child: const Icon(
        Icons.edit_outlined,
        color: BrandColors.accent,
        size: 16,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading body — three shimmer skeleton cards
// ---------------------------------------------------------------------------

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    const List<double> titleWidths = <double>[0.62, 0.45, 0.54];
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.md,
        VelvetSpacing.lg,
        VelvetSpacing.lg,
      ),
      children: <Widget>[
        for (int i = 0; i < titleWidths.length; i++) ...<Widget>[
          _SkeletonCard(
            key: Key('skeleton_card_$i'),
            titleWidthFactor: titleWidths[i],
          ),
          const SizedBox(height: VelvetSpacing.md),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton card
// ---------------------------------------------------------------------------

/// A raised neumorphic card whose content areas are replaced by shimmering
/// inset bars — depth preserved (never flat grey) so the loading state reads
/// on-brand. One [AnimationController] per card (each card is independent).
class _SkeletonCard extends StatefulWidget {
  const _SkeletonCard({super.key, this.titleWidthFactor = 0.62});

  final double titleWidthFactor;

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NeumorphicCard(
      child: Row(
        children: <Widget>[
          _ShimmerBar(
            controller: _shimmer,
            height: 48,
            width: 48,
            radius: VelvetRadii.field,
          ),
          const SizedBox(width: VelvetSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _ShimmerBar(
                  controller: _shimmer,
                  height: 16,
                  widthFactor: widget.titleWidthFactor,
                  radius: 6,
                ),
                const SizedBox(height: VelvetSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: _ShimmerBar(
                        controller: _shimmer,
                        height: 26,
                        radius: VelvetRadii.pill,
                      ),
                    ),
                    const SizedBox(width: VelvetSpacing.sm),
                    Expanded(
                      flex: 4,
                      child: _ShimmerBar(
                        controller: _shimmer,
                        height: 26,
                        radius: VelvetRadii.pill,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: VelvetSpacing.md),
          _ShimmerBar(
            controller: _shimmer,
            height: 32,
            width: 32,
            radius: VelvetRadii.field,
          ),
        ],
      ),
    );
  }
}

/// A single recessed bar with a travelling camel highlight sweep.
class _ShimmerBar extends StatelessWidget {
  const _ShimmerBar({
    required this.controller,
    required this.height,
    required this.radius,
    this.width,
    this.widthFactor,
  });

  final AnimationController controller;
  final double height;
  final double radius;
  final double? width;
  final double? widthFactor;

  @override
  Widget build(BuildContext context) {
    final Widget bar = AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        final double t = controller.value;
        final double pos = -1.3 + t * 2.6;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: BrandColors.shadowDarkCard.withValues(alpha: 0.55),
            gradient: LinearGradient(
              begin: Alignment(pos - 0.6, 0),
              end: Alignment(pos + 0.6, 0),
              colors: <Color>[
                BrandColors.shadowDarkCard.withValues(alpha: 0.0),
                BrandColors.accent.withValues(alpha: 0.35),
                BrandColors.shadowDarkCard.withValues(alpha: 0.0),
              ],
              stops: const <double>[0.0, 0.5, 1.0],
            ),
          ),
          child: SizedBox(height: height),
        );
      },
    );

    if (widthFactor != null) {
      return FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widthFactor,
        child: bar,
      );
    }
    return SizedBox(width: width, child: bar);
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

/// Vertically centred empty-state: recessed camel medallion + headline +
/// supporting text + single primary CTA. The empty state does NOT show the
/// FAB — the inline CTA is the only first-run path so intent is unmistakable.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  /// Opens the create form and invalidates the category cache on return.
  /// Provided by [_ServicesListScreenState._openAndRefresh].
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(VelvetSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              height: 104,
              width: 104,
              child: NeumorphicInset(
                // Circular inset medallion — same carved-in treatment as the
                // empty-state in the approved preview.
                radius: 52,
                child: Center(
                  child: Icon(
                    Icons.spa_rounded,
                    size: 44,
                    color: BrandColors.accent.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
            const SizedBox(height: VelvetSpacing.xl),
            Text(
              l10n.servicesEmpty,
              style: VelvetText.heading().copyWith(fontSize: 22),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VelvetSpacing.sm),
            Text(
              l10n.servicesEmptyBody,
              style: VelvetText.body(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VelvetSpacing.xl),
            SizedBox(
              width: 240,
              child: NeumorphicButton(
                key: const Key('btn-create-service-empty'),
                label: l10n.servicesAdd,
                icon: Icons.add_rounded,
                onPressed: onCreate,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Neumorphic extended FAB
// ---------------------------------------------------------------------------

/// A hand-built neumorphic extended FAB — camel/mocha gradient pill that
/// depresses on press. Material's [FloatingActionButton.extended] cannot
/// render the paired soft-UI shadows, so this widget replicates the approved
/// preview's approach exactly.
class _NeumorphicExtendedFab extends StatefulWidget {
  const _NeumorphicExtendedFab({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  State<_NeumorphicExtendedFab> createState() => _NeumorphicExtendedFabState();
}

class _NeumorphicExtendedFabState extends State<_NeumorphicExtendedFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  BrandColors.accentLatte,
                  BrandColors.accentDeep,
                ],
              ),
              borderRadius: BorderRadius.circular(VelvetRadii.pill),
              boxShadow: _pressed ? null : VelvetShadows.extrudedButtonAccent,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.add_rounded,
                  color: BrandColors.white,
                  size: 22,
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Text(widget.label, style: VelvetText.cta()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
