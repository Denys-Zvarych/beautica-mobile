// Phase 13.3 — CLIENT Пошук (Search) filters screen.
//
// The elevated-center bottom-nav tab (branch index 2). Ports the approved
// preview `docs/signup-designs/SearchBooking/lib/screens/search_filters_screen.dart`
// into the real Riverpod + go_router structure, mapping the preview's standalone
// tokens to the in-app VelvetTouch design system.
//
// Layout (scrollable body + sticky CTA):
//   1. Top bar — shared [ClientTopBar] (wordmark · bell · burger). Branch root,
//      so no back button.
//   2. Pill search field — «Пошук майстра або послуги» (free-text; INERT
//      backend-side in v1 but wired forward via the controller).
//   3. «Місто» — recessed select row → opens the existing locality picker
//      (oblast → city cascade) and writes the chosen city onto SearchFilters.
//   4. «Категорія» — a fixed-height horizontal rail of the popular categories
//      ([CategoryRailTile]) ending in a «Всі категорії» tile that opens the
//      full-list sheet ([showAllCategoriesSheet]). Populated from the live
//      `approvedCategoriesProvider`; single-select. Tapping a category reveals
//      its bookable SERVICES as chips in a recessed [ServiceChipDrawer] below
//      (multi-select, second level — Variant A «Рейка + послуги»).
//   5. «Вартість послуги» — single-thumb price slider with a live «до N грн»
//      readout (collapses to «будь-яка» at the ceiling).
//   6. Sticky «Показати майстрів» CTA → pushes /search/results with the
//      assembled [SearchFilters] in `extra`.
//
// The screen assembles [SearchFilters] only; it never calls the search
// repository (that is the results screen's job — phase 13.x). go_router only;
// no Navigator. Every user-facing string flows through AppLocalizations except
// backend data (city / category names) and numeric prices.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../location/domain/city.dart';
import '../../location/domain/oblast.dart';
import '../../location/presentation/widgets/locality_picker_sheet.dart';
import '../../location/state/location_providers.dart';
import '../../services/data/service_repository.dart';
import '../../services/domain/service_category_option.dart';
import '../data/category_service_providers.dart';
import '../domain/category_service_option.dart';
import '../domain/search_filters.dart';
import 'state/search_filters_controller.dart';
import 'widgets/all_categories_sheet.dart';
import 'widgets/category_rail.dart';
import 'widgets/service_chip_drawer.dart';
import 'widgets/service_type_tile.dart';
import 'widgets/staggered_reveal.dart';

// Shell import only for the shared top bar — NOT a cross-feature presentation
// dependency on screens, only the reusable chrome widget.
import '../../shell/presentation/widgets/client_top_bar.dart';

/// The CLIENT Пошук (Search) filters screen — branch index 2.
class ClientSearchScreen extends ConsumerStatefulWidget {
  const ClientSearchScreen({super.key});

  @override
  ConsumerState<ClientSearchScreen> createState() => _ClientSearchScreenState();
}

class _ClientSearchScreenState extends ConsumerState<ClientSearchScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Re-hydrate the field from any surviving (keepAlive) query so a back-nav
    // from results shows what was typed.
    final String? query = ref.read(searchFiltersControllerProvider).query;
    if (query != null) {
      _searchController.text = query;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onBellTap() {
    // TODO(14.9): route to RouteNames.notifications when that screen ships.
  }

  void _onBurgerTap() => context.push(RouteNames.clientMenu);

  /// Opens the oblast → city cascade using the existing locality picker, then
  /// writes the chosen city onto the filters + its display label.
  Future<void> _pickCity() async {
    final l10n = AppLocalizations.of(context);
    final Oblast? oblast = await showLocalityPickerSheet<Oblast>(
      context: context,
      provider: oblastListProvider,
      labelOf: (Oblast o) => o.name,
      idOf: (Oblast o) => o.id,
      titleLabel: l10n.localityOblastLabel,
      onRetry: () => ref.invalidate(oblastListProvider),
    );
    if (oblast == null || !mounted) return;

    final cityProvider = cityListProvider(oblast.id);
    final City? city = await showLocalityPickerSheet<City>(
      context: context,
      provider: cityProvider,
      labelOf: (City c) => c.name,
      idOf: (City c) => c.id,
      titleLabel: l10n.searchCityLabel,
      onRetry: () => ref.invalidate(cityProvider),
    );
    if (city == null || !mounted) return;

    ref
        .read(searchFiltersControllerProvider.notifier)
        .selectCity(cityId: city.id);
    ref
        .read(searchFilterLabelsControllerProvider.notifier)
        .setCityName(city.name);
  }

  void _onShowMasters() {
    // Forward the assembled filter set to the results screen via `extra`.
    final SearchFilters filters = ref.read(searchFiltersControllerProvider);
    context.push(RouteNames.clientSearchResults, extra: filters);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      // Stable branch key carried over from the placeholder this screen
      // replaces, so the client-shell E2E branch-2 assertion keeps a
      // locale-independent target.
      key: const Key('client-branch-search'),
      backgroundColor: BrandColors.base,
      body: SafeArea(
        bottom: false,
        child: RepaintBoundary(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  VelvetSpacing.lg,
                  VelvetSpacing.sm,
                  VelvetSpacing.lg,
                  0,
                ),
                child: ClientTopBar(
                  onBell: _onBellTap,
                  onBurger: _onBurgerTap,
                  bellSemanticLabel: l10n.homeHubNotificationsLabel,
                  burgerSemanticLabel: l10n.settingsHubMenuButton,
                  bellKey: const Key('search_bell_button'),
                  burgerKey: const Key('btn-menu-search'),
                ),
              ),
              Expanded(
                child: _SearchFiltersBody(
                  l10n: l10n,
                  searchController: _searchController,
                  onPickCity: _pickCity,
                ),
              ),
              // Sticky CTA pinned below the scrollable body.
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    VelvetSpacing.lg,
                    VelvetSpacing.sm,
                    VelvetSpacing.lg,
                    VelvetSpacing.md,
                  ),
                  child: NeumorphicButton(
                    key: const Key('search_show_masters_cta'),
                    label: l10n.searchCtaShowMasters,
                    icon: Icons.search_rounded,
                    onPressed: _onShowMasters,
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

// ---------------------------------------------------------------------------
// Body — scrollable filter sections.
// ---------------------------------------------------------------------------

class _SearchFiltersBody extends ConsumerWidget {
  const _SearchFiltersBody({
    required this.l10n,
    required this.searchController,
    required this.onPickCity,
  });

  final AppLocalizations l10n;
  final TextEditingController searchController;
  final VoidCallback onPickCity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No broad watch here: the body shell never needs to rebuild on a filter
    // change. Each section below self-watches only the slice it renders, so a
    // slider drag rebuilds just [_PriceSection], a category tap rebuilds just
    // [_CategorySection], and a city pick rebuilds just [_CitySelectRow].
    //
    // Variant A («Рейка + послуги») staggered fade-up entrance: the surface
    // assembles itself on mount rather than snapping in flat. Each [reveal]
    // slice mirrors the approved preview's start/end intervals exactly.
    return SearchStaggeredReveal(
      builder: (BuildContext context, SearchRevealFn reveal) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.sm,
            VelvetSpacing.lg,
            VelvetSpacing.xl,
          ),
          children: <Widget>[
            // ── Pill search field ──────────────────────────────────────────
            reveal(
              start: 0.0,
              end: 0.4,
              child: _SearchField(
                controller: searchController,
                hintText: l10n.searchFieldHint,
                onChanged: (String value) => ref
                    .read(searchFiltersControllerProvider.notifier)
                    .setQuery(value),
              ),
            ),
            const SizedBox(height: VelvetSpacing.lg),

            // ── Місто ───────────────────────────────────────────────────────
            reveal(
              start: 0.1,
              end: 0.5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _SectionLabel(text: l10n.searchCityLabel),
                  const SizedBox(height: VelvetSpacing.sm),
                  _CitySelectRow(onTap: onPickCity),
                ],
              ),
            ),
            const SizedBox(height: VelvetSpacing.lg),

            // ── Категорія (rail) + Послуги (drawer) — Variant A ─────────────
            _CategorySection(reveal: reveal),
            const SizedBox(height: VelvetSpacing.lg),

            // ── Вартість послуги ────────────────────────────────────────────
            const _PriceSection(),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Pill search field (recessed inset, leading magnifier).
// ---------------------------------------------------------------------------

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  static final TextStyle _hintStyle = VelvetText.input().copyWith(
    color: BrandColors.placeholder,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    return NeumorphicInset(
      radius: 28,
      child: SizedBox(
        height: VelvetSizes.field,
        child: Row(
          children: <Widget>[
            const SizedBox(width: VelvetSpacing.md + 2),
            const Icon(
              Icons.search_rounded,
              color: BrandColors.muted,
              size: 21,
            ),
            const SizedBox(width: VelvetSpacing.sm),
            Expanded(
              child: TextField(
                key: const Key('search_query_field'),
                controller: controller,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: VelvetText.input(),
                cursorColor: BrandColors.accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: hintText,
                  hintStyle: _hintStyle,
                ),
              ),
            ),
            const SizedBox(width: VelvetSpacing.md),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section label (Comfortaa, left-inset to align with the field corners).
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(text, style: VelvetText.label()),
    );
  }
}

// ---------------------------------------------------------------------------
// Місто — recessed select row showing the chosen city + a chevron.
// ---------------------------------------------------------------------------

class _CitySelectRow extends ConsumerWidget {
  const _CitySelectRow({required this.onTap});

  final VoidCallback onTap;

  static final TextStyle _placeholderStyle = VelvetText.input().copyWith(
    color: BrandColors.placeholder,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch only the city-label slice — so this row rebuilds on a city pick but
    // NOT on a price drag or category tap.
    final String? cityName = ref.watch(
      searchFilterLabelsControllerProvider.select(
        (SearchFilterLabels f) => f.cityName,
      ),
    );
    final bool hasSelection = cityName != null;
    final String value =
        cityName ?? AppLocalizations.of(context).searchCityPlaceholder;

    return Semantics(
      button: true,
      label: value,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: NeumorphicInset(
          child: SizedBox(
            height: VelvetSizes.field,
            child: Row(
              children: <Widget>[
                const SizedBox(width: VelvetSpacing.md),
                const Icon(
                  Icons.location_on_outlined,
                  color: BrandColors.muted,
                  size: 20,
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Expanded(
                  child: Text(
                    value,
                    key: const Key('search_city_value'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: hasSelection
                        ? VelvetText.input()
                        : _placeholderStyle,
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: BrandColors.textSecondary,
                  size: 24,
                ),
                const SizedBox(width: VelvetSpacing.md),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Категорія (rail) + Послуги (drawer) — Variant A «Рейка + послуги».
//
// First level: a fixed-height (92 dp) horizontal rail of the popular categories
// ending in a «Всі категорії» tile that opens the full-list sheet. The rail
// width (96 dp tiles) is sized so the last visible tile is partially clipped —
// the "scroll for more" cue from the approved preview.
//
// Second level: tapping a category reveals its bookable services as selectable
// chips in a recessed [ServiceChipDrawer], wrapped in an [AnimatedSize] so the
// drawer slides open/closed (240 ms easeOutCubic) exactly as in the preview.
// ---------------------------------------------------------------------------

/// How many categories surface up front in the rail before «Всі категорії».
/// The live taxonomy has no `popular` flag (unlike the preview's mock catalog),
/// so the first [_kRailPopularCount] approved categories are surfaced and the
/// full list lives behind the «Всі категорії» sheet — preserving Variant A's
/// "fewer icons up front, with a path to the full list" move.
const int _kRailPopularCount = 6;

class _CategorySection extends ConsumerWidget {
  const _CategorySection({required this.reveal});

  final SearchRevealFn reveal;

  Future<void> _openAllCategories(
    BuildContext context,
    WidgetRef ref,
    List<ServiceCategoryOption> categories,
    String? selectedKey,
  ) async {
    final ServiceCategoryOption? picked = await showAllCategoriesSheet(
      context,
      categories: categories,
      selectedKey: selectedKey,
    );
    if (picked == null) return;
    _select(ref, picked);
  }

  /// Single-selects [category]: sets the filter key + display label. (The
  /// sheet always selects — it never toggles off — matching the preview.)
  void _select(WidgetRef ref, ServiceCategoryOption category) {
    final String? current = ref.read(
      searchFiltersControllerProvider.select(
        (SearchFilters f) => f.categoryKey,
      ),
    );
    if (current != category.name) {
      ref
          .read(searchFiltersControllerProvider.notifier)
          .toggleServiceType(category.name);
      ref
          .read(searchFilterLabelsControllerProvider.notifier)
          .setCategoryName(category.displayName);
      // Category changed → clear the second-level service selection.
      ref.read(searchServiceSelectionControllerProvider.notifier).clear();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Watch only the selected-category slice for the rail highlight — so a
    // price drag does NOT rebuild the rail or drawer.
    final String? selectedKey = ref.watch(
      searchFiltersControllerProvider.select(
        (SearchFilters f) => f.categoryKey,
      ),
    );
    final categoriesAsync = ref.watch(approvedCategoriesProvider);

    return categoriesAsync.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          reveal(
            start: 0.2,
            end: 0.7,
            child: _SectionLabel(text: l10n.searchCategoryLabel),
          ),
          const SizedBox(height: VelvetSpacing.sm),
          reveal(start: 0.25, end: 0.8, child: const _RailSkeleton()),
        ],
      ),
      error: (Object e, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionLabel(text: l10n.searchCategoryLabel),
          const SizedBox(height: VelvetSpacing.sm),
          _GridError(
            message: l10n.searchCategoriesLoadError,
            onRetry: () => ref.invalidate(approvedCategoriesProvider),
          ),
        ],
      ),
      data: (List<ServiceCategoryOption> categories) {
        if (categories.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SectionLabel(text: l10n.searchCategoryLabel),
              const SizedBox(height: VelvetSpacing.sm),
              _GridEmpty(message: l10n.searchCategoriesEmpty),
            ],
          );
        }

        final List<ServiceCategoryOption> railCategories = categories
            .take(_kRailPopularCount)
            .toList(growable: false);

        // Resolve the selected category once here (this branch already holds
        // both `selectedKey` and the list) so the drawer slot doesn't re-scan
        // the list on every rebuild — including each frame of its 240ms
        // open/close animation.
        ServiceCategoryOption? selectedCategory;
        if (selectedKey != null) {
          for (final ServiceCategoryOption c in categories) {
            if (c.name == selectedKey) {
              selectedCategory = c;
              break;
            }
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            reveal(
              start: 0.2,
              end: 0.7,
              child: _SectionLabel(text: l10n.searchCategoryLabel),
            ),
            const SizedBox(height: VelvetSpacing.sm),

            // Fixed-height rail — scrolls sideways, never grows the page. The
            // partially-clipped trailing tile signals "scroll for more".
            reveal(
              start: 0.25,
              end: 0.8,
              child: SizedBox(
                height: 92,
                child: ListView(
                  key: const Key('search_category_rail'),
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  children: <Widget>[
                    for (final ServiceCategoryOption c
                        in railCategories) ...<Widget>[
                      CategoryRailTile(
                        key: Key('search_service_type_${c.name}'),
                        icon: serviceTypeIcon(c.name),
                        label: c.displayName,
                        selected: selectedKey == c.name,
                        onTap: () => _toggle(ref, c, selectedKey),
                      ),
                      const SizedBox(width: VelvetSpacing.sm + 2),
                    ],
                    CategoryRailMoreTile(
                      key: const Key('search_all_categories_tile'),
                      label: l10n.searchAllCategories,
                      semanticLabel: l10n.searchAllCategoriesSheetTitle,
                      onTap: () => _openAllCategories(
                        context,
                        ref,
                        categories,
                        selectedKey,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Service drawer (second level). AnimatedSize slides it open/closed.
            _ServiceDrawerSlot(category: selectedCategory),
          ],
        );
      },
    );
  }

  /// Rail tap: toggles the category (tapping the active one collapses the
  /// drawer), mirroring the filter + label + clearing the service selection.
  void _toggle(
    WidgetRef ref,
    ServiceCategoryOption category,
    String? selectedKey,
  ) {
    final bool willSelect = selectedKey != category.name;
    ref
        .read(searchFiltersControllerProvider.notifier)
        .toggleServiceType(category.name);
    // Mirror the human-readable label for any chrome that shows the active
    // category; cleared when the tile is deselected.
    ref
        .read(searchFilterLabelsControllerProvider.notifier)
        .setCategoryName(willSelect ? category.displayName : null);
    // The parent category changed (selected, deselected, or switched) → clear
    // the second-level service selection so it never leaks across categories.
    ref.read(searchServiceSelectionControllerProvider.notifier).clear();
  }
}

/// The animated slot beneath the rail that opens the service-chip drawer for
/// the selected category. Collapsed (zero-height) when nothing is selected.
class _ServiceDrawerSlot extends ConsumerWidget {
  const _ServiceDrawerSlot({required this.category});

  /// The already-resolved selected category (resolved once in the parent), or
  /// `null` when nothing is selected — the drawer collapses to zero height.
  final ServiceCategoryOption? category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    Widget content = const SizedBox(width: double.infinity);
    {
      final ServiceCategoryOption? category = this.category;
      if (category != null) {
        final ServiceCategoryOption resolved = category;
        final AsyncValue<List<CategoryServiceOption>> servicesAsync = ref.watch(
          categoryServiceOptionsProvider(resolved.name),
        );
        final String drawerLabel = l10n.searchServicesDrawerLabel(
          resolved.displayName,
        );
        content = servicesAsync.when(
          loading: () => Padding(
            padding: const EdgeInsets.only(top: VelvetSpacing.lg),
            child: _ServiceDrawerSkeleton(label: drawerLabel),
          ),
          error: (Object e, _) => Padding(
            padding: const EdgeInsets.only(top: VelvetSpacing.lg),
            child: _GridError(
              message: l10n.searchServicesLoadError,
              onRetry: () =>
                  ref.invalidate(categoryServiceOptionsProvider(resolved.name)),
            ),
          ),
          data: (List<CategoryServiceOption> services) {
            // Only render the drawer when the category actually has services —
            // an empty list would otherwise show an empty well.
            if (services.isEmpty) {
              return const SizedBox(width: double.infinity);
            }
            final Set<String> selectedServices = ref.watch(
              searchServiceSelectionControllerProvider,
            );
            return Padding(
              padding: const EdgeInsets.only(top: VelvetSpacing.lg),
              child: ServiceChipDrawer(
                label: drawerLabel,
                services: services,
                selectedKeys: selectedServices,
                onToggle: (String key) => ref
                    .read(searchServiceSelectionControllerProvider.notifier)
                    .toggle(key),
              ),
            );
          },
        );
      }
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: content,
    );
  }
}

/// Loading placeholder for the service-chip drawer — the labelled recessed well
/// with a centred spinner, so the drawer's reveal animation has stable chrome
/// while the per-category service types load.
class _ServiceDrawerSkeleton extends StatelessWidget {
  const _ServiceDrawerSkeleton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(label, style: VelvetText.label()),
        ),
        const SizedBox(height: VelvetSpacing.sm),
        const NeumorphicInset(
          radius: VelvetRadii.card,
          child: Padding(
            padding: EdgeInsets.all(VelvetSpacing.md),
            child: Center(
              child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: BrandColors.accent,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Loading placeholder shaped like the rail — a row of muted raised pills.
class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton();

  static final BoxDecoration _pill = BoxDecoration(
    color: BrandColors.faint.withValues(alpha: 0.3),
    borderRadius: BorderRadius.circular(VelvetRadii.card),
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        children: <Widget>[
          for (int i = 0; i < 5; i++) ...<Widget>[
            Container(height: 84, width: 96, decoration: _pill),
            const SizedBox(width: VelvetSpacing.sm + 2),
          ],
        ],
      ),
    );
  }
}

class _GridError extends StatelessWidget {
  const _GridError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          message,
          style: VelvetText.body().copyWith(color: BrandColors.muted),
        ),
        const SizedBox(height: VelvetSpacing.sm),
        TextButton(
          key: const Key('search_categories_retry'),
          onPressed: onRetry,
          style: TextButton.styleFrom(foregroundColor: BrandColors.accentDeep),
          child: Text(l10n.retryLabel),
        ),
      ],
    );
  }
}

class _GridEmpty extends StatelessWidget {
  const _GridEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: VelvetText.body().copyWith(color: BrandColors.muted),
    );
  }
}

// ---------------------------------------------------------------------------
// Вартість послуги — two-thumb price range slider + live readout + axis labels
// + paired MIN/MAX numeric input fields.
//
// The RangeSlider, the readout, and the two text fields are bidirectionally
// synced through [SearchFiltersController]: a drag writes both bounds atomically
// via `setPriceRange`, a field edit writes its bound via `setMinPrice` /
// `setMaxPrice`, and the controller is the single source of truth that flows
// back into the slider thumbs and (guarded against cursor jumps) the field text.
//
// Semantics carried over from the controller:
//   • minPrice == null  → no lower bound (left thumb at 0,    empty MIN field)
//   • maxPrice == null  → no upper bound (right thumb at ceil, empty MAX field)
//   • the controller enforces min <= max, so the UI can never emit a 400-able
//     inverted pair.
// ---------------------------------------------------------------------------

class _PriceSection extends ConsumerStatefulWidget {
  const _PriceSection();

  @override
  ConsumerState<_PriceSection> createState() => _PriceSectionState();
}

class _PriceSectionState extends ConsumerState<_PriceSection> {
  static final TextStyle _readoutStyle = VelvetText.bodyStrong().copyWith(
    fontSize: 14,
    color: BrandColors.accentDeep,
  );
  static final TextStyle _endLabelStyle = VelvetText.body().copyWith(
    fontSize: 12,
    color: BrandColors.muted,
  );

  // Digits-only + cap length at 4 chars (max meaningful value is the 5000
  // ceiling; the controller clamps the parsed value to the ceiling anyway).
  static final List<TextInputFormatter> _priceFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(4),
  ];

  final TextEditingController _minController = TextEditingController();
  final TextEditingController _maxController = TextEditingController();

  // Guards the controller→field write so we never stomp the user's caret while
  // they are actively editing a field (and never recurse field→controller→field).
  bool _syncingFromState = false;

  @override
  void initState() {
    super.initState();
    // Hydrate the fields from any surviving (keepAlive) price selection so a
    // back-nav from results shows the previously entered bounds.
    final SearchFilters filters = ref.read(searchFiltersControllerProvider);
    _minController.text = _format(filters.minPrice);
    _maxController.text = _format(filters.maxPrice);
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  /// Renders a bound as field text — null (no bound) becomes an empty field.
  static String _format(double? value) =>
      value == null ? '' : value.round().toString();

  /// Reflects the authoritative controller bounds back into the field text,
  /// but ONLY when the value actually differs from what the field already shows
  /// (so typing "30" never gets rewritten to "30" mid-keystroke, and the caret
  /// is preserved). Wrapped in [_syncingFromState] so the resulting programmatic
  /// edit does not loop back through the onChanged handlers.
  void _syncFieldsFromState(double? minPrice, double? maxPrice) {
    final String minText = _format(minPrice);
    final String maxText = _format(maxPrice);
    if (_minController.text == minText && _maxController.text == maxText) {
      return;
    }
    _syncingFromState = true;
    if (_minController.text != minText) _minController.text = minText;
    if (_maxController.text != maxText) _maxController.text = maxText;
    _syncingFromState = false;
  }

  void _onMinChanged(String raw) {
    if (_syncingFromState) return;
    final double? parsed = raw.isEmpty ? null : double.tryParse(raw);
    ref.read(searchFiltersControllerProvider.notifier).setMinPrice(parsed);
  }

  void _onMaxChanged(String raw) {
    if (_syncingFromState) return;
    final double? parsed = raw.isEmpty ? null : double.tryParse(raw);
    ref.read(searchFiltersControllerProvider.notifier).setMaxPrice(parsed);
  }

  void _onRangeChanged(RangeValues values) {
    ref
        .read(searchFiltersControllerProvider.notifier)
        .setPriceRange(min: values.start, max: values.end);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Watch only the price slice — so a slider drag / field edit rebuilds ONLY
    // this section, not the category grid or city row.
    final ({double? min, double? max}) price = ref.watch(
      searchFiltersControllerProvider.select(
        (SearchFilters f) => (min: f.minPrice, max: f.maxPrice),
      ),
    );
    final double? minPrice = price.min;
    final double? maxPrice = price.max;

    // null bounds map to the rail extremes: left thumb at 0, right at ceiling.
    final RangeValues sliderValues = RangeValues(
      minPrice ?? 0,
      maxPrice ?? kSearchPriceCeiling,
    );

    final String readout = _readoutText(l10n, minPrice, maxPrice);

    // Push the authoritative bounds into the fields after this frame's build,
    // so a slider drag updates the MIN/MAX text (without fighting the caret).
    _syncFieldsFromState(minPrice, maxPrice);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            _SectionLabel(text: l10n.searchPriceLabel),
            Flexible(
              child: Text(
                readout,
                key: const Key('search_price_readout'),
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _readoutStyle,
              ),
            ),
          ],
        ),
        const SizedBox(height: VelvetSpacing.xs),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 5,
            activeTrackColor: BrandColors.accent,
            inactiveTrackColor: BrandColors.shadowDarkCard,
            thumbColor: BrandColors.accentDeep,
            overlayColor: BrandColors.accent.withValues(alpha: 0.16),
            rangeThumbShape: const RoundRangeSliderThumbShape(
              enabledThumbRadius: 11,
            ),
          ),
          child: RangeSlider(
            key: const Key('search_price_slider'),
            values: sliderValues,
            min: 0,
            max: kSearchPriceCeiling,
            divisions: kSearchPriceDivisions,
            onChanged: _onRangeChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(l10n.searchPriceMin, style: _endLabelStyle),
              Text(l10n.searchPriceMax, style: _endLabelStyle),
            ],
          ),
        ),
        const SizedBox(height: VelvetSpacing.md),
        // Paired MIN / MAX numeric wells — two labelled fields split evenly.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _PriceField(
                fieldKey: const Key('search_price_min_field'),
                label: l10n.searchPriceMinFieldLabel,
                hintText: l10n.searchPriceMinFieldHint,
                suffix: l10n.searchPriceCurrencySuffix,
                controller: _minController,
                formatters: _priceFormatters,
                onChanged: _onMinChanged,
              ),
            ),
            const SizedBox(width: VelvetSpacing.md),
            Expanded(
              child: _PriceField(
                fieldKey: const Key('search_price_max_field'),
                label: l10n.searchPriceMaxFieldLabel,
                hintText: l10n.searchPriceMaxFieldHint,
                suffix: l10n.searchPriceCurrencySuffix,
                controller: _maxController,
                formatters: _priceFormatters,
                onChanged: _onMaxChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Builds the live price readout from the current bounds:
  ///   both set   → «від X до Y грн»
  ///   max only   → «до Y грн»
  ///   min only   → «від X грн»
  ///   neither    → «будь-яка»
  String _readoutText(
    AppLocalizations l10n,
    double? minPrice,
    double? maxPrice,
  ) {
    if (minPrice != null && maxPrice != null) {
      return l10n.searchPriceRange(minPrice.round(), maxPrice.round());
    }
    if (maxPrice != null) {
      return l10n.searchPriceUpTo(maxPrice.round());
    }
    if (minPrice != null) {
      return l10n.searchPriceFrom(minPrice.round());
    }
    return l10n.searchPriceAny;
  }
}

/// One compact numeric price well (the MIN or MAX field). A labelled recessed
/// inset that reuses the screen's existing field chrome, with an inline «грн»
/// suffix so it reads as a unit rather than a bare number.
class _PriceField extends StatelessWidget {
  const _PriceField({
    required this.fieldKey,
    required this.label,
    required this.hintText,
    required this.suffix,
    required this.controller,
    required this.formatters,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final String hintText;
  final String suffix;
  final TextEditingController controller;
  final List<TextInputFormatter> formatters;
  final ValueChanged<String> onChanged;

  static final TextStyle _hintStyle = VelvetText.input().copyWith(
    color: BrandColors.placeholder,
    fontWeight: FontWeight.w600,
  );
  static final TextStyle _suffixStyle = VelvetText.input().copyWith(
    color: BrandColors.muted,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(label, style: VelvetText.label()),
        ),
        const SizedBox(height: VelvetSpacing.sm),
        NeumorphicInset(
          child: SizedBox(
            height: VelvetSizes.field,
            child: Row(
              children: <Widget>[
                const SizedBox(width: VelvetSpacing.md),
                Expanded(
                  child: TextField(
                    key: fieldKey,
                    controller: controller,
                    onChanged: onChanged,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: formatters,
                    style: VelvetText.input(),
                    cursorColor: BrandColors.accent,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: hintText,
                      hintStyle: _hintStyle,
                    ),
                  ),
                ),
                const SizedBox(width: VelvetSpacing.xs),
                Text(suffix, style: _suffixStyle),
                const SizedBox(width: VelvetSpacing.md),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
