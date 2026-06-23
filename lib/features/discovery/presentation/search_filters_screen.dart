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
//   4. «Вид послуги» — a 4-column grid of [ServiceTypeTile]s, populated from the
//      live `approvedCategoriesProvider`. Single-select.
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
import '../domain/search_filters.dart';
import 'state/search_filters_controller.dart';
import 'widgets/service_type_tile.dart';

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
    // [_ServiceTypeGrid], and a city pick rebuilds just [_CitySelectRow].
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.lg,
        VelvetSpacing.lg,
        VelvetSpacing.xl,
      ),
      children: <Widget>[
        // ── Pill search field ──────────────────────────────────────────────
        _SearchField(
          controller: searchController,
          hintText: l10n.searchFieldHint,
          onChanged: (String value) => ref
              .read(searchFiltersControllerProvider.notifier)
              .setQuery(value),
        ),
        const SizedBox(height: VelvetSpacing.lg),

        // ── Місто ──────────────────────────────────────────────────────────
        _SectionLabel(text: l10n.searchCityLabel),
        const SizedBox(height: VelvetSpacing.sm),
        _CitySelectRow(onTap: onPickCity),
        const SizedBox(height: VelvetSpacing.lg),

        // ── Вид послуги ─────────────────────────────────────────────────────
        _SectionLabel(text: l10n.searchServiceTypeLabel),
        const SizedBox(height: VelvetSpacing.md),
        const _ServiceTypeGrid(),
        const SizedBox(height: VelvetSpacing.lg),

        // ── Вартість послуги ────────────────────────────────────────────────
        const _PriceSection(),
      ],
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
// Вид послуги — 4-column grid populated from approvedCategoriesProvider.
// ---------------------------------------------------------------------------

class _ServiceTypeGrid extends ConsumerWidget {
  const _ServiceTypeGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Watch only the selected-category slice for the tile highlight — so a
    // price drag does NOT rebuild this grid or its tiles.
    final String? selectedKey = ref.watch(
      searchFiltersControllerProvider.select(
        (SearchFilters f) => f.categoryKey,
      ),
    );
    final categoriesAsync = ref.watch(approvedCategoriesProvider);

    return categoriesAsync.when(
      loading: () => const _GridSkeleton(),
      error: (Object e, _) => _GridError(
        message: l10n.searchCategoriesLoadError,
        onRetry: () => ref.invalidate(approvedCategoriesProvider),
      ),
      data: (List<ServiceCategoryOption> categories) {
        if (categories.isEmpty) {
          return _GridEmpty(message: l10n.searchCategoriesEmpty);
        }
        return GridView.count(
          key: const Key('search_service_type_grid'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: VelvetSpacing.md,
          crossAxisSpacing: VelvetSpacing.sm,
          childAspectRatio: 0.95,
          children: <Widget>[
            for (final ServiceCategoryOption category in categories)
              ServiceTypeTile(
                key: Key('search_service_type_${category.name}'),
                icon: serviceTypeIcon(category.name),
                label: category.displayName,
                selected: selectedKey == category.name,
                onTap: () {
                  ref
                      .read(searchFiltersControllerProvider.notifier)
                      .toggleServiceType(category.name);
                  // Mirror the human-readable label for any chrome that shows
                  // the active category; cleared when the tile is deselected.
                  final bool willSelect = selectedKey != category.name;
                  ref
                      .read(searchFilterLabelsControllerProvider.notifier)
                      .setCategoryName(
                        willSelect ? category.displayName : null,
                      );
                },
              ),
          ],
        );
      },
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  static final BoxDecoration _circle = BoxDecoration(
    color: BrandColors.faint.withValues(alpha: 0.3),
    shape: BoxShape.circle,
  );

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: VelvetSpacing.md,
      crossAxisSpacing: VelvetSpacing.sm,
      childAspectRatio: 0.95,
      children: <Widget>[
        for (int i = 0; i < 8; i++)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(height: 66, width: 66, decoration: _circle),
            ],
          ),
      ],
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
// Вартість послуги — single-thumb price slider + readout + end labels.
// ---------------------------------------------------------------------------

class _PriceSection extends ConsumerWidget {
  const _PriceSection();

  static final TextStyle _readoutStyle = VelvetText.bodyStrong().copyWith(
    fontSize: 14,
    color: BrandColors.accentDeep,
  );
  static final TextStyle _endLabelStyle = VelvetText.body().copyWith(
    fontSize: 12,
    color: BrandColors.muted,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Watch only the price-ceiling slice — so a slider drag rebuilds ONLY this
    // section, not the category grid or city row.
    final double? maxPrice = ref.watch(
      searchFiltersControllerProvider.select((SearchFilters f) => f.maxPrice),
    );
    // null maxPrice → "будь-яка" → slider sits at the ceiling.
    final double sliderValue = maxPrice ?? kSearchPriceCeiling;
    final String readout = maxPrice == null
        ? l10n.searchPriceAny
        : l10n.searchPriceUpTo(maxPrice.round());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            _SectionLabel(text: l10n.searchPriceLabel),
            Text(
              readout,
              key: const Key('search_price_readout'),
              style: _readoutStyle,
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
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
          ),
          child: Slider(
            key: const Key('search_price_slider'),
            value: sliderValue,
            min: 0,
            max: kSearchPriceCeiling,
            divisions: kSearchPriceDivisions,
            onChanged: (double v) => ref
                .read(searchFiltersControllerProvider.notifier)
                .setMaxPrice(v),
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
      ],
    );
  }
}
