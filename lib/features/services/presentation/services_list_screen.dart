// Phase 5.2 — Services List Screen.
//
// The INDEPENDENT_MASTER's "Мої послуги" catalogue. Three AsyncValue states:
//   • loading → three [_SkeletonCard] widgets (shimmer sweep)
//   • data    → if empty: [_EmptyState]; else [ListView.builder] of [ServiceCard]
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
//
// Phase 247 (part 1) — [CategoryGroup], [CategorySection],
// [CategoryCountBadge], [ServiceCard], [PhotoThumbnail], [ServiceInfo],
// [MetaLine] and [MetaItem] were PROMOTED out of this file (dropped their
// leading underscore) into
// `presentation/widgets/service_category_list.dart` so the master booking
// wizard (Phase 247 part 2) can reuse the exact same widgets rather than
// forking a lookalike. Pure move — no behaviour change.

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
import 'package:beautica_mobile/core/widgets/app_refresh_indicator.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_category_list.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';

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
  /// from the setup / edit / request-category flows.
  ///
  /// CONTRACT: every destination opened through here MUST exit by POPPING.
  /// A `context.go(...)` exit replaces the stack instead of popping, so this
  /// Future never completes, the invalidation never fires, and the awaited call
  /// leaks — the exact bug that shipped when [ServiceSetupScreen] exited with
  /// `go`. That screen now pops (see its `_leave`), which is why this hook is
  /// sound for both the FAB and the empty-state CTA.
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
      // Tile 0 ("Послуги") — this screen IS that destination. Hosted via
      // Scaffold's own slot (not nested inside a body SafeArea) so it mounts
      // identically to the other three master tab screens — see
      // `VelvetBottomNavBar`'s doc comment and `ProfileScaffold.bottomNavBar`.
      bottomNavigationBar: const VelvetBottomNavBar(activeIndex: 0),
      floatingActionButton: asyncServices.maybeWhen(
        data: (list) => list.isEmpty
            ? null
            : _NeumorphicExtendedFab(
                key: const Key('btn-create-service'),
                label: l10n.servicesAdd,
                // ONE "add services" surface for both cases: the FAB (master
                // already has services) and the empty-state CTA below both open
                // the multi-select setup screen. The backend bulk endpoint is
                // additive, so the same screen appends to an existing catalogue.
                onTap: () => _openAndRefresh(RouteNames.serviceSetup),
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
            if (kDebugMode) {
              // Log the runtime type only — never the exception object, which
              // can carry server data in its message.
              log(
                'ServicesListScreen: async error — ${e.runtimeType}',
                name: 'feature.services.presentation',
                level: 900,
              );
            }
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
              // Same destination as the FAB — the multi-select setup screen is
              // the only "add services" surface. It POPs back here on save /
              // close, which is what lets [_openAndRefresh]'s awaited push
              // resolve and re-fire the category invalidation.
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
      title: Text(title, style: VelvetText.pageTitle),
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
  List<CategoryGroup>? _cachedGroups;
  // P-M2 fix: cache the _flatten() result. Invalidated whenever _cachedGroups
  // is recomputed (identity change of services or categories).
  List<_ListItem>? _cachedItems;

  List<CategoryGroup> _resolveGroups(
    AsyncValue<List<ServiceCategoryOption>> categoriesAsync,
    String uncategorizedLabel,
  ) {
    final List<ServiceCategoryOption>? categoriesValue = categoriesAsync.value;
    final bool hit =
        _cachedGroups != null &&
        identical(_cachedServices, widget.services) &&
        identical(_cachedCategories, categoriesValue);
    if (hit) return _cachedGroups!;

    final List<CategoryGroup> groups = groupServicesByCategory(
      services: widget.services,
      categoriesAsync: categoriesAsync,
      uncategorizedLabel: uncategorizedLabel,
    );
    _cachedServices = widget.services;
    _cachedCategories = categoriesValue;
    _cachedGroups = groups;
    // P-M2: invalidate the flatten cache whenever groups are recomputed.
    _cachedItems = null;
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categoriesAsync = ref.watch(approvedCategoriesProvider);

    final List<CategoryGroup> groups = _resolveGroups(
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
              child: CategorySection(
                // Stable key per bucket so expand/collapse state survives
                // rebuilds (e.g. category-cache invalidation on screen return).
                // Also used by widget tests and profile card navigation.
                key: Key('category_section_$sectionSlug'),
                title: group.label,
                count: group.cards.length,
                slug: group.key.isEmpty ? null : group.key,
                initiallyExpanded: initiallyExpanded,
                children: <Widget>[
                  for (final CategoryGroupEntry entry in group.cards)
                    Padding(
                      padding: const EdgeInsets.only(top: VelvetSpacing.md),
                      child: ServiceCard(
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
    List<CategoryGroup> groups,
    int total,
  ) {
    return <_ListItem>[
      _HeaderItem(_activeServicesLabel(l10n, total)),
      for (final CategoryGroup group in groups) _SectionItem(group),
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

  final CategoryGroup group;
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
              style: VelvetText.headingSm,
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
