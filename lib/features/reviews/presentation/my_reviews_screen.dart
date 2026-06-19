// Phase 13.7 — My reviews screen (minimal placeholder for quick-link target).
//
// Quick-link from the Home Hub's "Мої відгуки" tile → /reviews/me.
// Backend `GET /reviews/me` is not yet shipped (backend 19.x).
// When it lands, replace the empty state with a real AsyncNotifier + ListView.
//
// TODO(backend-reviews-me): wire GET /reviews/me when endpoint ships.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/presentation/widgets/hub_widgets.dart';

// Pre-composed title style — avoids per-build copyWith allocation.
final TextStyle _titleStyle = VelvetText.heading().copyWith(fontSize: 18);

/// My Reviews screen — CLIENT's written reviews list.
class MyReviewsScreen extends StatelessWidget {
  const MyReviewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: BrandColors.base,
      appBar: AppBar(
        backgroundColor: BrandColors.base,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          key: const Key('my_reviews_back_button'),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: BrandColors.accentDeep,
            size: 20,
          ),
          onPressed: () => context.pop(),
        ),
        title: Text(l10n.myReviewsTitle, style: _titleStyle),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
          ),
          child: HubFlatCard(
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.md,
              vertical: VelvetSpacing.xl,
            ),
            child: HubEmptyState(
              icon: Icons.rate_review_outlined,
              // TODO(backend-reviews-me): replace with real review list
              message: l10n.myReviewsEmpty,
            ),
          ),
        ),
      ),
    );
  }
}
