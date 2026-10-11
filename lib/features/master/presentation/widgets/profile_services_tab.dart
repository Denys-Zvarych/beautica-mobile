import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import 'service_category_cards.dart';

/// The «Послуги» tab body of a master's own profile: the section header +
/// the shared [ServiceCategoryCardList] (interactive: true — tapping a card
/// navigates to `/services?expandCategory=<slug>`, the owner's own service-
/// management screen). Category-label resolution lives in
/// [ServiceCategoryCardList] itself, via `approvedCategoriesProvider`.
///
/// Data-agnostic: the caller supplies [services]; every destination is an
/// optional override whose `null` default keeps the independent master's
/// behaviour.
class ProfileServicesTab extends StatelessWidget {
  const ProfileServicesTab({
    super.key,
    required this.services,
    this.keyPrefix = 'profile-category',
    this.onAllServices,
    this.onAddServices,
    this.onCategoryTap,
  });

  final AsyncValue<List<MasterService>> services;
  final String keyPrefix;

  /// «Усі послуги» link. `null` → `context.push(RouteNames.services)`.
  final VoidCallback? onAllServices;

  /// Empty-state CTA. `null` → `context.push(RouteNames.serviceSetup)`.
  final VoidCallback? onAddServices;

  /// Category card tap. `null` → [ServiceCategoryCardList] default.
  ///
  /// [slug] is the raw backend category slug (untrusted). A caller building a
  /// route from it MUST use `Uri(queryParameters: ...)` (as the default does),
  /// never string interpolation.
  final void Function(BuildContext context, String? slug)? onCategoryTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Section header — a single right-aligned "all services" link. Omitted
    // entirely in the zero-services empty state, where the single
    // "Додати послуги" CTA is the only call to action.
    final Widget header = _AllServicesLink(
      label: l10n.masterAllServices,
      onTap: onAllServices ?? () => context.push(RouteNames.services),
    );

    return services.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          header,
          const SkeletonShimmerScope(
            child: Column(
              children: <Widget>[
                SkeletonBlock(
                  width: double.infinity,
                  height: 56,
                  radius: VelvetRadii.card,
                ),
                SizedBox(height: VelvetSpacing.sm),
                SkeletonBlock(
                  width: double.infinity,
                  height: 56,
                  radius: VelvetRadii.card,
                ),
              ],
            ),
          ),
        ],
      ),
      error: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          header,
          Padding(
            padding: const EdgeInsets.only(top: VelvetSpacing.xs),
            child: Text(l10n.errUnknown, style: VelvetText.feedbackMutedXs),
          ),
        ],
      ),
      data: (List<MasterService> items) {
        // Zero-services empty state: a single primary CTA that opens the
        // first-time bulk service-setup flow — the SAME entry point the
        // services-list empty state uses (RouteNames.serviceSetup). The
        // section header and "all services" link are intentionally dropped
        // here so the CTA stands alone.
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: VelvetSpacing.xs),
            child: SizedBox(
              width: double.infinity,
              child: NeumorphicButton(
                key: const Key('btn-master-add-services'),
                label: l10n.masterAddServices,
                icon: Icons.add_rounded,
                onPressed:
                    onAddServices ??
                    () => context.push(RouteNames.serviceSetup),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            header,
            ServiceCategoryCardList(
              services: items,
              keyPrefix: keyPrefix,
              interactive: true,
              onCategoryTap: onCategoryTap,
            ),
          ],
        );
      },
    );
  }
}

/// Right-aligned «Усі послуги» header link of [ProfileServicesTab].
class _AllServicesLink extends StatelessWidget {
  const _AllServicesLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          GestureDetector(
            key: const Key('profile-services-all-link'),
            onTap: onTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(label, style: VelvetText.link()),
                const SizedBox(width: 2),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 12,
                  color: BrandColors.accentDeep,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
