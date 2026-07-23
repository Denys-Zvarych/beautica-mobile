// Phase 14.3 — «МОЇ ЗАПИСИ» loading + error states. The empty state lives in
// `bookings_empty_state.dart`; all three render inside an
// `AlwaysScrollableScrollPhysics` ListView so pull-to-refresh keeps working
// no matter which state is showing.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Shared padding for every state (skeleton / empty / error / real list) so
/// the layout never jumps between them.
const EdgeInsets kMyBookingsListPadding = EdgeInsets.fromLTRB(
  VelvetSpacing.lg,
  VelvetSpacing.xs,
  VelvetSpacing.lg,
  VelvetSpacing.xl,
);

/// The loading state — deliberately NOT a shimmer (a light-sweep is a
/// Material/glassmorphism idiom). Soft UI owns a truer metaphor for "not
/// here yet": the content has not risen out of the surface. A loading card
/// is a set of recessed wells in the silhouette of a real card, breathing
/// slowly; when data lands they're replaced by raised pillows.
class BookingsSkeleton extends StatefulWidget {
  const BookingsSkeleton({super.key, this.count = 3});

  final int count;

  @override
  State<BookingsSkeleton> createState() => _BookingsSkeletonState();
}

class _BookingsSkeletonState extends State<BookingsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bool disabled =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (disabled) {
        _controller.value = 1.0;
      } else {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final Animation<double> curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    return Semantics(
      label: l10n.myBookingsLoadingSemantics,
      liveRegion: true,
      child: AnimatedBuilder(
        animation: curved,
        builder: (BuildContext context, Widget? child) {
          // 0.55 → 1.0: shallow enough to feel like breathing, not blinking.
          return Opacity(opacity: 0.55 + curved.value * 0.45, child: child);
        },
        child: Column(
          children: <Widget>[
            for (int i = 0; i < widget.count; i++) ...<Widget>[
              const _SkeletonCard(),
              if (i < widget.count - 1)
                const SizedBox(height: VelvetSpacing.md),
            ],
          ],
        ),
      ),
    );
  }
}

/// One loading card — the real card's silhouette, drawn entirely in recessed
/// wells on the bare taupe base (no card shadow — nothing has risen yet).
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.circular(VelvetRadii.card),
        border: Border.all(color: BrandColors.faint.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(VelvetSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _Well(width: 62, height: 74, radius: VelvetRadii.field),
            const SizedBox(width: VelvetSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const _Well(width: 32, height: 32, radius: 16),
                      const SizedBox(width: VelvetSpacing.sm),
                      _Well(width: _fraction(context, 0.34), height: 12),
                    ],
                  ),
                  const SizedBox(height: VelvetSpacing.md),
                  _Well(width: _fraction(context, 0.52), height: 11),
                  const SizedBox(height: VelvetSpacing.sm),
                  _Well(width: _fraction(context, 0.36), height: 10),
                  const SizedBox(height: VelvetSpacing.md),
                  const _Well(width: 116, height: 24, radius: 13),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Widths are a fraction of the viewport so the placeholder lines keep the
  /// ragged, text-like rhythm of the real card at any screen size.
  double _fraction(BuildContext context, double f) =>
      MediaQuery.sizeOf(context).width * f;
}

/// A single recessed placeholder well. [radius] == half of [width]/[height]
/// renders as a circle (the shipped `NeumorphicInset` has no dedicated
/// `circle` flag — a fully-rounded square reads identically for a square
/// well).
class _Well extends StatelessWidget {
  const _Well({required this.width, required this.height, this.radius = 6});

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return NeumorphicInset(
      radius: radius,
      child: SizedBox(width: width, height: height),
    );
  }
}

/// The error state — the failure message + a retry button.
class MyBookingsErrorState extends StatelessWidget {
  const MyBookingsErrorState({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String message = error is Failure
        ? (error as Failure).userMessage(context)
        : l10n.errUnknown;

    return Center(
      key: const Key('my_bookings_error'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(VelvetSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: BrandColors.muted,
              ),
              const SizedBox(height: VelvetSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: VelvetText.body(),
              ),
              const SizedBox(height: VelvetSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: NeumorphicButton(
                  key: const Key('my_bookings_error_retry'),
                  label: l10n.retryLabel,
                  icon: Icons.refresh_rounded,
                  onPressed: onRetry,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom-of-list spinner shown while [MyBookingsNotifier.loadMore] is in
/// flight.
class MyBookingsLoadMoreSpinner extends StatelessWidget {
  const MyBookingsLoadMoreSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: Key('my_bookings_load_more_spinner'),
      padding: EdgeInsets.symmetric(vertical: VelvetSpacing.md),
      child: Center(
        child: SizedBox(
          height: 26,
          width: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: BrandColors.accent,
          ),
        ),
      ),
    );
  }
}
