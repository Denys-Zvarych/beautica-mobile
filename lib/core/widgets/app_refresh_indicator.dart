// lib/core/widgets/app_refresh_indicator.dart
//
// A thin, project-wide wrapper around Material [RefreshIndicator] that applies
// the locked VelvetTouch / Warm Mocha brand tokens to the pull-to-refresh
// spinner and guarantees the child is always scrollable (so the drag gesture
// is detectable even when content is shorter than the viewport).
//
// Usage:
//
//   AppRefreshIndicator(
//     onRefresh: () async {
//       ref.invalidate(myProvider);
//       await ref.read(myProvider.future);
//     },
//     child: ListView.builder(…),
//   )
//
// For screens whose body is a non-scrolling Column, wrap the Column in a
// [SingleChildScrollView] with [AlwaysScrollableScrollPhysics] FIRST, then
// pass the [SingleChildScrollView] as the child here — [AppRefreshIndicator]
// does NOT convert a non-scrollable child to a scroll view automatically.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';

/// Brand-styled pull-to-refresh shell.
///
/// The [color] of the spinner is [BrandColors.accent] (camel `#B89A7A`).
/// The [backgroundColor] of the indicator disc is [BrandColors.base]
/// (warm taupe `#E6DDD0`), which matches every neumorphic surface on the
/// VelvetTouch design system.
///
/// Pass [child] a scrollable widget ([ListView], [GridView],
/// [SingleChildScrollView], [CustomScrollView]).  The [child]'s own physics
/// should include [AlwaysScrollableScrollPhysics] so the indicator can be
/// triggered even when content is shorter than the viewport.
///
/// [onRefresh] must return a [Future] that completes when the refresh is done;
/// the indicator spinner dismisses automatically when the future resolves.
/// Typical Riverpod pattern:
///
///   onRefresh: () async {
///     ref.invalidate(myProvider);
///     await ref.read(myProvider.future);
///   }
///
/// Riverpod 3.x note: `ref.invalidate` retains the previous `.value`
/// (seamless reload). Never gate reload-detection on `value == null` — just
/// invalidate and await the `.future`.
class AppRefreshIndicator extends StatelessWidget {
  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  /// Called when the user pulls down to refresh. Must return a [Future] that
  /// completes when the data reload is done — the spinner stays visible until
  /// the future resolves.
  final Future<void> Function() onRefresh;

  /// The scrollable body of the screen. Must be a scroll view with
  /// [AlwaysScrollableScrollPhysics] (or a physics that composes it) so that
  /// the pull gesture is always intercepted even when content underflows the
  /// viewport.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      // Camel accent — the primary interactive token for the VelvetTouch
      // design system (BrandColors.accent = #B89A7A).
      color: BrandColors.accent,
      // Warm taupe base — matches every neumorphic surface so the disc
      // does not visually jar against the page background.
      backgroundColor: BrandColors.base,
      child: child,
    );
  }
}
