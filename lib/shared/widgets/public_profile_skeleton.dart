// The public-profile loading placeholder: identity card, three stat tiles,
// tab bar, tab body.
//
// PROMOTED (REUSE-FIRST, M510) from the private `_PublicProfileSkeleton` in
// `features/master/presentation/public_master_profile_screen.dart`; the client
// card reuses it. The body is the ORIGINAL moved verbatim; the only addition is
// the optional, defaulted [showTabs], so the public profile renders exactly as
// before (`test/golden/` public-profile loading golden).

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

class PublicProfileSkeleton extends StatelessWidget {
  const PublicProfileSkeleton({super.key, this.showTabs = true});

  /// `false` drops the tab-bar placeholder and the gap under it (the client
  /// card has no tabs). `true` — every pre-existing caller — is unchanged.
  final bool showTabs;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmerScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Identity card.
          const NeumorphicCard(
            color: Color(0xFFEDE4D5),
            padding: EdgeInsets.all(VelvetSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                SkeletonBlock(width: 80, height: 80, circle: true),
                SizedBox(width: VelvetSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SkeletonBlock(width: 140, height: 16),
                      SizedBox(height: VelvetSpacing.xs + 2),
                      SkeletonBlock(width: 100, height: 24, radius: 999),
                      SizedBox(height: VelvetSpacing.xs),
                      SkeletonBlock(width: 160, height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: VelvetSpacing.xl),
          // Stat cards placeholder — 3 equal tiles (rating / services / reviews).
          const Row(
            children: <Widget>[
              Expanded(
                child: SkeletonBlock(
                  width: double.infinity,
                  height: 96,
                  radius: VelvetRadii.field + 2,
                ),
              ),
              SizedBox(width: VelvetSpacing.sm),
              Expanded(
                child: SkeletonBlock(
                  width: double.infinity,
                  height: 96,
                  radius: VelvetRadii.field + 2,
                ),
              ),
              SizedBox(width: VelvetSpacing.sm),
              Expanded(
                child: SkeletonBlock(
                  width: double.infinity,
                  height: 96,
                  radius: VelvetRadii.field + 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: VelvetSpacing.lg),
          if (showTabs) ...const <Widget>[
            // Tab bar placeholder.
            SkeletonBlock(width: double.infinity, height: 44),
            SizedBox(height: VelvetSpacing.lg),
          ],
          // Tab body placeholder.
          const SkeletonBlock(
            width: double.infinity,
            height: 160,
            radius: VelvetRadii.card,
          ),
        ],
      ),
    );
  }
}
