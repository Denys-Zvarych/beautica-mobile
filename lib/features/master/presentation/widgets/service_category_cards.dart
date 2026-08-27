// Shared service-category cards — extracted from `master_profile_screen.dart`
// (Phase 4.2's `_ProfileCategoriesSection` / `_ProfileCategoryCard`) so the
// SAME grouped-by-category summary list can be rendered by both:
//   • [MasterProfileScreen] (owner) — `interactive: true`. Tapping a card
//     pushes `/services?expandCategory=<slug>`, the master's OWN
//     service-management screen (`RouteNames.services`).
//   • `PublicMasterProfileScreen` (client browsing another master) —
//     `interactive: false`. `RouteNames.services` is scoped to the
//     AUTHENTICATED master (there is no `masterId`-parameterised equivalent a
//     client could be sent to), so cards render as plain, non-tappable
//     summary tiles: no forward chevron, no press feedback, no navigation.
//
// `interactive` is a REQUIRED named parameter (mobile-security LOW fix —
// no `= true` default) precisely so a future client-facing call site can't
// silently fail open by omitting it: the compiler forces every call site to
// state its intent explicitly.
//
// [ServiceCategoryCardList] groups the given [MasterService]s by
// `category` (uppercased slug; empty/null → the `_none` "uncategorized"
// bucket) and renders one [ServiceCategoryCard] per non-empty bucket, with
// the same identity-equality memoization the original `_rebuild` used (skips
// the grouping/card-list recompute unless `services` or the resolved
// [approvedCategoriesProvider] value changes by reference — P-H2 pattern).
//
// Category labels are resolved via [approvedCategoriesProvider], which is
// CLIENT-safe (sourced from `categoryRequestApiProvider`, not the master-only
// `masterProfileProvider`) — safe to watch from a CLIENT session.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/category_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/category_slug.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

/// Renders one [ServiceCategoryCard] per non-empty category bucket of
/// [services]. Returns an empty [SizedBox] when [services] is empty — callers
/// that need a different empty-state affordance (e.g. the owner's "add
/// services" CTA) handle that themselves and only mount this list once they
/// know it is non-empty.
class ServiceCategoryCardList extends ConsumerStatefulWidget {
  const ServiceCategoryCardList({
    super.key,
    required this.services,
    required this.keyPrefix,
    required this.interactive,
  });

  /// The master's services (already resolved — this widget does no fetching
  /// of its own beyond the category-label lookup).
  final List<MasterService> services;

  /// Prefix for each card's `Key`, e.g. `'profile-category'` (owner) or
  /// `'public-master-profile-category'` (client). The full key is
  /// `'$keyPrefix-$slug'` (or `'$keyPrefix-_none'` for uncategorized).
  final String keyPrefix;

  /// Whether cards navigate on tap (owner) or render as static, read-only
  /// summary tiles (client viewing another master).
  final bool interactive;

  @override
  ConsumerState<ServiceCategoryCardList> createState() =>
      _ServiceCategoryCardListState();
}

class _ServiceCategoryCardListState
    extends ConsumerState<ServiceCategoryCardList> {
  // Identity-equality cache fields — recompute only when references change.
  List<MasterService>? _cachedServices;
  List<ServiceCategoryOption>? _cachedCategories;
  List<Widget>? _cachedCards;

  void _rebuild(
    List<MasterService> services,
    List<ServiceCategoryOption>? categories,
    AppLocalizations l10n,
  ) {
    if (_cachedCards != null &&
        identical(_cachedServices, services) &&
        identical(_cachedCategories, categories)) {
      // Cache hit — no recompute needed.
      return;
    }

    // --- bucket grouping ---
    final Map<String, List<MasterService>> buckets =
        <String, List<MasterService>>{};
    for (final MasterService s in services) {
      final String key = (s.category ?? '').trim().toUpperCase();
      (buckets[key] ??= <MasterService>[]).add(s);
    }

    // --- label resolver ---
    String resolveLabel(String slug) {
      if (slug.isEmpty) return l10n.serviceCategoryUncategorized;
      if (categories != null) {
        for (final ServiceCategoryOption opt in categories) {
          if (categorySlugMatches(slug, opt.name)) return opt.displayName;
        }
      }
      return humanizeCategorySlug(slug);
    }

    // --- card list ---
    final List<Widget> cards = <Widget>[];
    var first = true;
    for (final MapEntry<String, List<MasterService>> entry in buckets.entries) {
      if (!first) cards.add(const SizedBox(height: VelvetSpacing.sm));
      first = false;
      final String resolvedLabel = resolveLabel(entry.key);
      final String slugKey = entry.key.isEmpty ? '_none' : entry.key;
      cards.add(
        ServiceCategoryCard(
          key: Key('${widget.keyPrefix}-$slugKey'),
          label: resolvedLabel,
          count: entry.value.length,
          // Pass the raw slug so the card's own live BuildContext drives
          // navigation — never bake a BuildContext into a cached closure.
          slug: entry.key.isEmpty ? null : entry.key,
          interactive: widget.interactive,
          semanticLabel: widget.interactive
              ? l10n.masterProfileCategorySemantics(
                  resolvedLabel,
                  entry.value.length,
                )
              : l10n.publicMasterProfileCategorySemantics(
                  resolvedLabel,
                  entry.value.length,
                ),
        ),
      );
    }

    // --- store results ---
    _cachedServices = services;
    _cachedCategories = categories;
    _cachedCards = cards;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.services.isEmpty) return const SizedBox.shrink();

    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<ServiceCategoryOption>> categoriesAsync = ref.watch(
      approvedCategoriesProvider,
    );
    _rebuild(widget.services, categoriesAsync.value, l10n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _cachedCards!,
    );
  }
}

/// A raised neumorphic card representing a category under which services are
/// configured. Visually identical to `_CategorySection`'s header pillow on the
/// services list screen: same tokens, same typography, same count badge — but
/// without a disclosure chevron or collapsible body.
///
/// Leads with a 20dp category glyph from the shared [categoryIconFor]
/// resolver, tinted [BrandColors.accentDeep] — except the uncategorized
/// (`slug == null`) card, which renders an empty same-size slot instead of a
/// glyph (see the [slug] doc and the build-method comment for why: the
/// resolver never returns null and would otherwise mislabel that bucket with
/// the cosmetology icon).
///
/// When [interactive] is `true` (the owner's own profile), tapping navigates
/// to the services list with the matching category pre-expanded
/// (`expandCategory` query parameter) — using the card's own live
/// [BuildContext] so cached widget instances never call `context.push` on a
/// stale context from an earlier frame.
///
/// When [interactive] is `false` (a client viewing another master's public
/// profile), the card renders as a static summary tile: no forward chevron,
/// no press-scale feedback, no tap handler — `RouteNames.services` is scoped
/// to the authenticated master and has no meaning for a client browsing
/// someone else's profile.
class ServiceCategoryCard extends StatefulWidget {
  const ServiceCategoryCard({
    super.key,
    required this.label,
    required this.count,
    required this.semanticLabel,
    // Null means "uncategorized" — navigates to /services with no query param.
    this.slug,
    required this.interactive,
  });

  final String label;
  final int count;
  final String semanticLabel;
  final String? slug;
  final bool interactive;

  @override
  State<ServiceCategoryCard> createState() => _ServiceCategoryCardState();
}

class _ServiceCategoryCardState extends State<ServiceCategoryCard> {
  bool _pressed = false;

  // Hoisted to avoid a per-build TextStyle allocation.
  static final TextStyle _cardStyle = VelvetText.subheading16;

  // Leading category glyph. Smaller than the rail's 36dp and the timeline
  // medallion's 48dp — this is a compact list row, not a tile/medallion.
  // Legibility of the (now uniformly thin-stroke, ~0.5/24 unit) icon set at
  // this size was verified by rendering the real card (several category
  // slugs, incl. the null/uncategorized case) to a PNG and inspecting it —
  // strokes stay crisp against the warm-taupe base at 20dp.
  //
  // Measured fact (mobile-qa, corrects an earlier "row did not get taller"
  // claim): this 20dp icon — not the label — now sets the `Row`'s cross-axis
  // extent, since it is taller than the ~19dp `subheading16` text line it
  // sits beside. The card grew 39dp → 40dp at default text scale. Harmless
  // (both consumers sit inside a `SingleChildScrollView`, no overflow at any
  // matrix cell), but the 1dp is real — don't cite the old "unchanged" figure.
  static const double _iconSize = 20;

  @override
  Widget build(BuildContext context) {
    final String? iconAsset = categoryIconOrNullFor(categoryKey: widget.slug);
    final Widget card = AnimatedScale(
      scale: _pressed ? 0.99 : 1.0,
      duration: const Duration(milliseconds: 110),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.md,
          vertical: VelvetSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: BrandColors.base,
          borderRadius: BorderRadius.circular(VelvetRadii.card),
          boxShadow: _pressed ? null : VelvetShadows.extrudedCard,
        ),
        child: Row(
          children: <Widget>[
            // Leading category glyph. `slug == null` means "uncategorized"
            // (see the constructor doc) — [categoryIconOrNullFor] resolves
            // that to `null` too, rather than falling back to
            // [categoryIconFor]'s cosmetology glyph, which would mislabel a
            // bucket that isn't cosmetology at all. So the uncategorized
            // card renders NO icon (an empty same-size slot, keeping every
            // card's label left edge aligned) rather than resolving a glyph
            // for it.
            SizedBox(
              width: _iconSize,
              height: _iconSize,
              child: iconAsset == null
                  ? null
                  : AppIcon(
                      iconAsset,
                      size: _iconSize,
                      color: BrandColors.accentDeep,
                    ),
            ),
            const SizedBox(width: VelvetSpacing.sm),
            Expanded(
              child: Text(
                widget.label,
                style: _cardStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: VelvetSpacing.sm),
            ServiceCategoryCountBadge(count: widget.count),
            if (widget.interactive) ...<Widget>[
              const SizedBox(width: VelvetSpacing.sm),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: BrandColors.accent,
                size: 16,
              ),
            ],
          ],
        ),
      ),
    );

    if (!widget.interactive) {
      // Read-only: no button semantics, no gesture handling.
      return Semantics(label: widget.semanticLabel, child: card);
    }

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          final String? slug = widget.slug;
          context.push(
            Uri(
              path: RouteNames.services,
              queryParameters: slug == null
                  ? null
                  : <String, String>{'expandCategory': slug},
            ).toString(),
          );
        },
        child: card,
      ),
    );
  }
}

/// A small recessed count badge shown on a [ServiceCategoryCard].
class ServiceCategoryCountBadge extends StatelessWidget {
  const ServiceCategoryCountBadge({super.key, required this.count});

  final int count;

  // Hoisted to avoid per-build allocation.
  static final TextStyle _style = VelvetText.pillSm;

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
