// Phase 1.5 — Loading skeleton widget with pulsing animation.
//
// Deliberately avoids third-party shimmer packages so the animation stays
// inside the standard Flutter toolkit. Uses `TweenAnimationBuilder` with an
// `AnimationBehavior.preserve` implicit driver — the animation repeats by
// triggering a reverse tween rebuild in the builder callback.
//
// Three constructors are provided:
//   • `LoadingSkeleton()` — a single placeholder row (default use-case).
//   • `LoadingSkeleton.list({int rows})` — stacked rows for list screens.
//   • `LoadingSkeleton.card()` — a taller single-block card placeholder.
//
// All spacing uses `AppSpacing` tokens. The skeleton colour is derived from
// `colorScheme.surfaceContainerHighest` so it adapts correctly to light/dark.
// No user-visible strings are used — the widget is purely visual.

import 'package:beautica_mobile/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

enum _Variant { single, list, card }

/// An animated placeholder shown while async data is loading.
///
/// Pulses between 40 % and 100 % opacity using [TweenAnimationBuilder] so no
/// `AnimationController` management is required from the parent.
class LoadingSkeleton extends StatefulWidget {
  /// Default constructor — renders a single skeleton row.
  const LoadingSkeleton({super.key}) : _variant = _Variant.single, rows = 1;

  /// Named constructor for list screens — renders [rows] stacked skeleton rows.
  const LoadingSkeleton.list({super.key, this.rows = 3})
    : _variant = _Variant.list;

  /// Named constructor for card screens — renders a taller single block.
  const LoadingSkeleton.card({super.key}) : _variant = _Variant.card, rows = 1;

  final _Variant _variant;

  /// Number of skeleton rows to render (only relevant for [LoadingSkeleton.list]).
  final int rows;

  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _opacity = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;

    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, _) {
        return Opacity(
          opacity: _opacity.value,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: _buildBody(color),
          ),
        );
      },
    );
  }

  Widget _buildBody(Color color) {
    switch (widget._variant) {
      case _Variant.single:
        return _SkeletonRow(color: color);
      case _Variant.list:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(widget.rows, (i) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: i < widget.rows - 1 ? AppSpacing.sm : 0,
              ),
              child: _SkeletonRow(color: color),
            );
          }),
        );
      case _Variant.card:
        return _SkeletonCard(color: color);
    }
  }
}

/// A single skeleton row: a circle avatar placeholder + two line placeholders.
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SkeletonBox(width: 40, height: 40, color: color, borderRadius: 20),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SkeletonBox(
                height: 14,
                color: color,
                borderRadius: AppSpacing.xs,
              ),
              const SizedBox(height: AppSpacing.xs),
              _SkeletonBox(
                height: 12,
                width: 140,
                color: color,
                borderRadius: AppSpacing.xs,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A taller card-shaped skeleton placeholder used in profile / detail screens.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SkeletonBox(height: 160, color: color, borderRadius: AppSpacing.sm),
        const SizedBox(height: AppSpacing.md),
        _SkeletonBox(height: 20, color: color, borderRadius: AppSpacing.xs),
        const SizedBox(height: AppSpacing.xs),
        _SkeletonBox(
          height: 14,
          width: 200,
          color: color,
          borderRadius: AppSpacing.xs,
        ),
      ],
    );
  }
}

/// A single rounded rectangle skeleton placeholder.
class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.height,
    required this.color,
    required this.borderRadius,
    this.width,
  });

  final double? width;
  final double height;
  final Color color;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}
