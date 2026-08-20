// Phase 14.3 — «МОЇ ЗАПИСИ» loading + error states. The empty state lives in
// `bookings_empty_state.dart`; all three render inside an
// `AlwaysScrollableScrollPhysics` ListView so pull-to-refresh keeps working
// no matter which state is showing.

import 'dart:async';

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

/// The panel shell BOTH centred notices on this surface are built from —
/// [MyBookingsErrorState] and [MyBookingsSlowLoadNotice].
///
/// Extracted (not forked) when the slow-load escape hatch was added, so the
/// two read as one component with two messages rather than two hand-copied
/// columns that drift apart. Geometry is byte-for-byte what
/// [MyBookingsErrorState] shipped before the extraction — `Center` >
/// `ConstrainedBox(320)` > `Padding(lg)` > `Column`[icon 48 muted, `md` gap,
/// centred body, `lg` gap, full-width [NeumorphicButton]] — so the error
/// state's goldens are unchanged by construction.
class _MyBookingsNoticePanel extends StatelessWidget {
  const _MyBookingsNoticePanel({
    super.key,
    required this.icon,
    required this.message,
    required this.actionKey,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final Key actionKey;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(VelvetSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 48, color: BrandColors.muted),
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
                  key: actionKey,
                  label: actionLabel,
                  icon: Icons.refresh_rounded,
                  onPressed: onAction,
                ),
              ),
            ],
          ),
        ),
      ),
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

    return _MyBookingsNoticePanel(
      key: const Key('my_bookings_error'),
      icon: Icons.cloud_off_rounded,
      message: message,
      actionKey: const Key('my_bookings_error_retry'),
      actionLabel: l10n.retryLabel,
      onAction: onRetry,
    );
  }
}

/// How long a fetch may stay pending before [MyBookingsSlowLoadNotice] offers
/// the master a way out.
///
/// Eight seconds, chosen against the two clocks that actually bound a stuck
/// day fetch: `dioProvider`'s `connectTimeout` (15 s) / `receiveTimeout`
/// (30 s), and `beauticaProviderRetry`'s bounded re-attempt. Both are longer
/// than any healthy round trip on this screen, so 8 s lands well clear of a
/// normal load and well inside the first attempt's own timeout — the master
/// sees an escape hatch before the platform has even given up once.
const Duration kMyBookingsSlowLoadThreshold = Duration(seconds: 8);

/// The escape hatch layered ON TOP of [BookingsSkeleton] when a day fetch is
/// still pending after [kMyBookingsSlowLoadThreshold].
///
/// ## The defect this exists for
///
/// `bookingsDayProvider` parked in `AsyncLoading` renders the skeleton and
/// NOTHING else: no message, no action, no timer. `AsyncValue.when` routes
/// `AsyncLoading(retrying: true)` to `loading:` as well, so a transient
/// failure being re-attempted looks identical to a first attempt — the
/// master watched an indefinite shimmer after creating a walk-in booking,
/// with no way to ask for the fetch again short of leaving the screen. The
/// `error:` branch has always had a retry button; `loading:` had none.
///
/// ## Why this is NOT "show an error after 8 seconds"
///
/// The fetch is genuinely still in flight and may still succeed — turning it
/// into an `AsyncError` would be a lie, and would throw away an in-flight
/// response that is about to land. This widget changes no state at all: the
/// skeleton keeps shimmering above it, the provider keeps loading, and the
/// notice simply offers `onRetry` (an `invalidate`, which restarts the
/// request from a fresh attempt counter). Copy and iconography say "still
/// working", not "broken" — an hourglass, not a severed cloud.
///
/// ## Why it cannot flash on a fast load
///
/// The widget renders `SizedBox.shrink()` — zero-size, no paint — until its
/// [Timer] fires at [delay]. A load that resolves before then replaces the
/// whole `loading:` subtree, [dispose] cancels the timer, and the notice is
/// never made visible. There is no build in which it is briefly laid out and
/// then removed, so no layout shift and no flash exists to debounce. The
/// entry animation is deliberately driven off the `_elapsed` flag rather
/// than off mount for the same reason.
class MyBookingsSlowLoadNotice extends StatefulWidget {
  const MyBookingsSlowLoadNotice({
    super.key,
    required this.onRetry,
    this.delay = kMyBookingsSlowLoadThreshold,
  });

  final VoidCallback onRetry;

  /// Overridable so widget tests can drive the threshold without a real
  /// 8-second `pump`. Production always takes the default.
  final Duration delay;

  @override
  State<MyBookingsSlowLoadNotice> createState() =>
      _MyBookingsSlowLoadNoticeState();
}

class _MyBookingsSlowLoadNoticeState extends State<MyBookingsSlowLoadNotice> {
  Timer? _timer;
  bool _elapsed = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (!mounted) return;
      setState(() => _elapsed = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_elapsed) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final Widget panel = _MyBookingsNoticePanel(
      icon: Icons.hourglass_bottom_rounded,
      message: l10n.bookingsStillLoadingBody,
      actionKey: const Key('my_bookings_slow_load_retry'),
      actionLabel: l10n.retryLabel,
      onAction: widget.onRetry,
    );

    // Reduced motion: no rise, no fade — the panel is simply there. Honoured
    // rather than shortened; a vestibular-sensitive user asked for none.
    if (MediaQuery.disableAnimationsOf(context)) {
      return KeyedSubtree(
        key: const Key('my_bookings_slow_load'),
        child: panel,
      );
    }

    // A single settle-in: 8dp rise + fade over 260ms. It arrives ONCE, from
    // `_elapsed` flipping — `TweenAnimationBuilder` runs its tween on first
    // build with a non-null `duration`, and every later rebuild sees the same
    // `end: 1`, so a parent rebuild (a retry re-entering `loading:`) does not
    // replay it.
    return TweenAnimationBuilder<double>(
      key: const Key('my_bookings_slow_load'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double t, Widget? child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * VelvetSpacing.sm),
          child: child,
        ),
      ),
      child: panel,
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
