// M509 — ListCardSkeleton, PROMOTED from the blocked-clients screen's private
// `_LoadingBody` / `_LoadingCard`. The blocked-clients loading render is pinned
// by `test/golden/blocked_clients_screen_golden_test.dart` (unchanged by the
// promotion); this pins the shared widget's own shape.

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/shared/widgets/list_card_skeleton.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('three skeleton cards under one shimmer scope, each with an '
      'avatar disc and two bars', (tester) async {
    await tester.pumpApp(
      const SingleChildScrollView(child: ListCardSkeleton(key: Key('probe'))),
    );
    expect(find.byKey(const Key('probe')), findsOneWidget);
    expect(find.byType(SkeletonShimmerScope), findsOneWidget);
    expect(find.byType(ListCardSkeletonCard), findsNWidgets(3));
    expect(find.byType(NeumorphicCard), findsNWidgets(3));
    // 3 × (1 disc + 2 bars).
    expect(find.byType(SkeletonBlock), findsNWidgets(9));
    await tester.pump(); // let the shimmer tick once; no exception
  });
}
