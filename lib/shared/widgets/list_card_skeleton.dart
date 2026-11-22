// Loading skeleton for a list of identity cards — three shimmering
// [NeumorphicCard] rows (48 dp avatar disc + a 140 / 100 dp text-bar pair) in
// the geometry of the cards that replace them, so nothing jumps when data
// lands.
//
// PROMOTED (M509) from the private `_LoadingBody` / `_LoadingCard` in
// `features/moderation/presentation/blocked_clients_screen.dart` so the
// «Клієнти» tab loads with the SAME skeleton as «Заблоковані клієнти»
// (REUSE-FIRST: one widget, both screens). The blocked-clients screen renders
// byte-identically — it passes its existing `loadingKey` as the widget key.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

/// Three stacked [ListCardSkeletonCard]s under one shimmer scope.
class ListCardSkeleton extends StatelessWidget {
  const ListCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeletonShimmerScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ListCardSkeletonCard(),
          SizedBox(height: VelvetSpacing.md),
          ListCardSkeletonCard(),
          SizedBox(height: VelvetSpacing.md),
          ListCardSkeletonCard(),
        ],
      ),
    );
  }
}

/// One skeleton card: avatar disc + two text bars.
class ListCardSkeletonCard extends StatelessWidget {
  const ListCardSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const NeumorphicCard(
      child: Row(
        children: <Widget>[
          SkeletonBlock(width: 48, height: 48, circle: true),
          SizedBox(width: VelvetSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SkeletonBlock(width: 140, height: 14),
                SizedBox(height: VelvetSpacing.sm),
                SkeletonBlock(width: 100, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
