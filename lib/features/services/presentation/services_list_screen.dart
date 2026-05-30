// Phase 5.2 — Services List Screen.
//
// The INDEPENDENT_MASTER's "Мої послуги" catalogue. Three AsyncValue states:
//   • loading → three [_SkeletonCard] widgets (shimmer sweep)
//   • data    → if empty: [_EmptyState]; else [ListView.builder] of [_ServiceCard]
//   • error   → [ErrorState] with retry
//
// A neumorphic extended FAB (hidden in the empty state: the empty state has its
// own primary CTA) sits bottom-right via [Scaffold.floatingActionButton].
//
// Pull-to-refresh via [RefreshIndicator] delegates to
// [ServicesListNotifier.refresh].
//
// Design source: `docs/signup-designs/ServiceListScreen/lib/screens/service_list_screen.dart`
// and `service_widgets.dart` — transcribed 1:1; local state / Navigator
// replaced by Riverpod notifier + go_router.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:screen_protector/screen_protector.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/currency_uah.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';

import 'services_list_notifier.dart';

export 'services_list_notifier.dart' show servicesListProvider;

/// The INDEPENDENT_MASTER's services catalogue screen.
///
/// Handles all three [AsyncValue] states (loading / data / error).
/// Pull-to-refresh triggers [ServicesListNotifier.refresh].
///
/// Converted to [ConsumerStatefulWidget] to manage the [ScreenProtector]
/// lifecycle (SEC MEDIUM-1): screenshot suppression is enabled in release
/// builds on entry and lifted on exit, matching the project-wide pattern
/// used by [MasterProfileScreen].
class ServicesListScreen extends ConsumerStatefulWidget {
  const ServicesListScreen({super.key});

  @override
  ConsumerState<ServicesListScreen> createState() => _ServicesListScreenState();
}

class _ServicesListScreenState extends ConsumerState<ServicesListScreen> {
  @override
  void initState() {
    super.initState();
    if (!kDebugMode) ScreenProtector.preventScreenshotOn();
  }

  @override
  void dispose() {
    if (!kDebugMode) ScreenProtector.preventScreenshotOff();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final asyncServices = ref.watch(servicesListProvider);

    return Scaffold(
      backgroundColor: BrandColors.base,
      appBar: _ServicesAppBar(title: l10n.servicesTitle),
      floatingActionButton: asyncServices.maybeWhen(
        data: (list) => list.isEmpty
            ? null
            : _NeumorphicExtendedFab(
                key: const Key('btn-create-service'),
                label: l10n.servicesAdd,
                onTap: () => context.push(RouteNames.serviceCreate),
              ),
        orElse: () => null,
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(servicesListProvider.notifier).refresh(),
        color: BrandColors.accentDeep,
        backgroundColor: BrandColors.base,
        child: asyncServices.when(
          loading: () => const _LoadingBody(),
          error: (e, _) {
            log(
              'ServicesListScreen: async error — $e',
              name: 'feature.services.presentation',
              level: 900,
            );
            final failure = e is Failure ? e : UnknownFailure(cause: e);
            return _errorScrollable(
              ErrorState(
                key: const Key('services_error_state'),
                failure: failure,
                onRetry: () => ref.invalidate(servicesListProvider),
              ),
            );
          },
          data: (list) {
            if (list.isEmpty) return const _EmptyState();
            return _LoadedBody(services: list);
          },
        ),
      ),
    );
  }

  /// Wraps [child] in a [SingleChildScrollView] with [AlwaysScrollableScrollPhysics]
  /// so [RefreshIndicator] can still be triggered even on the error state, which
  /// might not have enough content to scroll naturally.
  Widget _errorScrollable(Widget child) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(height: 400, child: child),
    );
  }
}

// ---------------------------------------------------------------------------
// App bar
// ---------------------------------------------------------------------------

class _ServicesAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ServicesAppBar({required this.title});

  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: BrandColors.base,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      title: Text(title, style: VelvetText.heading()),
    );
  }
}

// ---------------------------------------------------------------------------
// Loaded body
// ---------------------------------------------------------------------------

class _LoadedBody extends StatelessWidget {
  const _LoadedBody({required this.services});

  final List<MasterService> services;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.md,
        VelvetSpacing.lg,
        // Bottom padding so the last card clears the floating FAB.
        VelvetSpacing.xxl + VelvetSpacing.xl,
      ),
      itemCount: services.length + 1,
      separatorBuilder: (context, idx) =>
          const SizedBox(height: VelvetSpacing.md),
      itemBuilder: (BuildContext context, int i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: VelvetSpacing.xs),
            child: Text(
              _activeServicesLabel(l10n, services.length),
              style: VelvetText.label(),
            ),
          );
        }
        final service = services[i - 1];
        return _ServiceCard(
          key: Key('service_card_${service.id}'),
          service: service,
          appearDelay: Duration(milliseconds: 90 * (i - 1)),
        );
      },
    );
  }

  /// Formats the count sub-heading.
  ///
  /// Full localisation for plural forms is deferred until the l10n team approves
  /// Ukrainian plural copy; for now a simple Ukrainian string is used inline
  /// (will migrate to ARB once copy is approved — backlog LOW).
  String _activeServicesLabel(AppLocalizations l10n, int count) =>
      '$count ${_serviceWordUk(count)}';

  String _serviceWordUk(int n) {
    if (n % 100 >= 11 && n % 100 <= 14) return 'послуг';
    switch (n % 10) {
      case 1:
        return 'послуга';
      case 2:
      case 3:
      case 4:
        return 'послуги';
      default:
        return 'послуг';
    }
  }
}

// ---------------------------------------------------------------------------
// Service card
// ---------------------------------------------------------------------------

/// A tappable service card. Extrudes at rest; depresses (scale 0.99, shadow
/// removed) on press for tactile "tap-to-edit" affordance.
///
/// Entrance animation: staggered fade + rise driven by [appearDelay].
class _ServiceCard extends StatefulWidget {
  const _ServiceCard({
    super.key,
    required this.service,
    this.appearDelay = Duration.zero,
  });

  final MasterService service;
  final Duration appearDelay;

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _appear;

  // PERF MEDIUM-1: CurvedAnimation moved from build() to initState() so a
  // new instance is not allocated on every frame. Typed as CurvedAnimation
  // (not Animation<double>) so dispose() is accessible.
  late final CurvedAnimation _curve;

  @override
  void initState() {
    super.initState();
    _appear = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _curve = CurvedAnimation(parent: _appear, curve: Curves.easeOutCubic);
    if (widget.appearDelay == Duration.zero) {
      _appear.forward();
    } else {
      Future<void>.delayed(widget.appearDelay, () {
        if (mounted) _appear.forward();
      });
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _appear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MasterService s = widget.service;
    final durationLabel = DurationMinutes.format(s.durationMinutes);
    final priceLabel = CurrencyUah.format(s.price);

    return AnimatedBuilder(
      animation: _curve,
      builder: (BuildContext context, Widget? child) {
        return Opacity(
          opacity: _curve.value,
          child: Transform.translate(
            offset: Offset(0, (1 - _curve.value) * 18),
            child: child,
          ),
        );
      },
      child: Semantics(
        button: true,
        label: '${s.name}. $durationLabel, $priceLabel. Редагувати',
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) {
            setState(() => _pressed = false);
            context.push(RouteNames.serviceEdit(s.id));
          },
          child: AnimatedScale(
            scale: _pressed ? 0.99 : 1.0,
            duration: const Duration(milliseconds: 110),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: BrandColors.base,
                borderRadius: BorderRadius.circular(VelvetRadii.card),
                boxShadow: _pressed ? null : VelvetShadows.extrudedCard,
              ),
              padding: const EdgeInsets.all(VelvetSpacing.lg),
              child: Row(
                children: <Widget>[
                  _PhotoThumbnail(key: Key('thumb_${s.id}')),
                  const SizedBox(width: VelvetSpacing.md),
                  Expanded(
                    child: _ServiceInfo(
                      name: s.name,
                      durationLabel: durationLabel,
                      priceLabel: priceLabel,
                    ),
                  ),
                  const SizedBox(width: VelvetSpacing.md),
                  const _EditButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Photo thumbnail (no-photo placeholder — service photo deferred to Phase 9.x)
// ---------------------------------------------------------------------------

/// 72×72 recessed inset well with a centred camel spa icon.
///
/// When actual photo upload is implemented (Phase 9.x), this widget will
/// accept a `photoUrl` and render an [Image.network] inside the same
/// 72×72 rounded [ClipRRect]. Until then, every service shows the icon
/// placeholder so depth always comes from shadows, never a flat grey box.
class _PhotoThumbnail extends StatelessWidget {
  const _PhotoThumbnail({super.key});

  static const double _size = 72;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _size,
      width: _size,
      child: NeumorphicInset(
        radius: VelvetRadii.field,
        child: Center(
          child: Icon(
            Icons.spa_rounded,
            size: 28,
            color: BrandColors.accent.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Service info (name + pills)
// ---------------------------------------------------------------------------

class _ServiceInfo extends StatelessWidget {
  const _ServiceInfo({
    required this.name,
    required this.durationLabel,
    required this.priceLabel,
  });

  final String name;
  final String durationLabel;
  final String priceLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          name,
          style: VelvetText.cardTitle(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: VelvetSpacing.md),
        Wrap(
          spacing: VelvetSpacing.sm,
          runSpacing: VelvetSpacing.sm,
          children: <Widget>[
            _DurationPill(value: durationLabel),
            _PricePill(value: priceLabel),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Inset pills
// ---------------------------------------------------------------------------

/// Inset pill carrying a leading icon + short label value.
///
/// The recessed well + camel glyph is the VelvetTouch treatment for secondary
/// data — depth reads as carved into the card rather than raised above it.
class _DurationPill extends StatelessWidget {
  const _DurationPill({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return _Pill(icon: Icons.schedule_rounded, value: value);
  }
}

class _PricePill extends StatelessWidget {
  const _PricePill({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return _Pill(icon: Icons.sell_rounded, value: value);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return NeumorphicInset(
      radius: VelvetRadii.pill,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.md - 2,
          vertical: VelvetSpacing.sm - 1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: BrandColors.accent),
            const SizedBox(width: VelvetSpacing.xs + 2),
            Text(value, style: VelvetText.pill()),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trailing edit button
// ---------------------------------------------------------------------------

/// 40×40 neumorphic raised pillow with the edit icon. Signals tap-to-edit.
class _EditButton extends StatelessWidget {
  const _EditButton();

  // Hoisted: VelvetRadii.field is a compile-time constant.
  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(VelvetRadii.field),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      width: 40,
      decoration: const BoxDecoration(
        color: BrandColors.base,
        borderRadius: _radius,
        boxShadow: VelvetShadows.extrudedSmall,
      ),
      child: const Icon(
        Icons.edit_outlined,
        color: BrandColors.accent,
        size: 22,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading body — three shimmer skeleton cards
// ---------------------------------------------------------------------------

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    const List<double> titleWidths = <double>[0.62, 0.45, 0.54];
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.md,
        VelvetSpacing.lg,
        VelvetSpacing.lg,
      ),
      children: <Widget>[
        for (int i = 0; i < titleWidths.length; i++) ...<Widget>[
          _SkeletonCard(
            key: Key('skeleton_card_$i'),
            titleWidthFactor: titleWidths[i],
          ),
          const SizedBox(height: VelvetSpacing.md),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton card
// ---------------------------------------------------------------------------

/// A raised neumorphic card whose content areas are replaced by shimmering
/// inset bars — depth preserved (never flat grey) so the loading state reads
/// on-brand. One [AnimationController] per card (each card is independent).
class _SkeletonCard extends StatefulWidget {
  const _SkeletonCard({super.key, this.titleWidthFactor = 0.62});

  final double titleWidthFactor;

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NeumorphicCard(
      child: Row(
        children: <Widget>[
          _ShimmerBar(
            controller: _shimmer,
            height: 72,
            width: 72,
            radius: VelvetRadii.field,
          ),
          const SizedBox(width: VelvetSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _ShimmerBar(
                  controller: _shimmer,
                  height: 16,
                  widthFactor: widget.titleWidthFactor,
                  radius: 6,
                ),
                const SizedBox(height: VelvetSpacing.md),
                Row(
                  children: <Widget>[
                    _ShimmerBar(
                      controller: _shimmer,
                      height: 26,
                      width: 78,
                      radius: VelvetRadii.pill,
                    ),
                    const SizedBox(width: VelvetSpacing.sm),
                    _ShimmerBar(
                      controller: _shimmer,
                      height: 26,
                      width: 92,
                      radius: VelvetRadii.pill,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: VelvetSpacing.md),
          _ShimmerBar(
            controller: _shimmer,
            height: 40,
            width: 40,
            radius: VelvetRadii.field,
          ),
        ],
      ),
    );
  }
}

/// A single recessed bar with a travelling camel highlight sweep.
class _ShimmerBar extends StatelessWidget {
  const _ShimmerBar({
    required this.controller,
    required this.height,
    required this.radius,
    this.width,
    this.widthFactor,
  });

  final AnimationController controller;
  final double height;
  final double radius;
  final double? width;
  final double? widthFactor;

  @override
  Widget build(BuildContext context) {
    final Widget bar = AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        final double t = controller.value;
        final double pos = -1.3 + t * 2.6;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: BrandColors.shadowDarkCard.withValues(alpha: 0.55),
            gradient: LinearGradient(
              begin: Alignment(pos - 0.6, 0),
              end: Alignment(pos + 0.6, 0),
              colors: <Color>[
                BrandColors.shadowDarkCard.withValues(alpha: 0.0),
                BrandColors.accent.withValues(alpha: 0.35),
                BrandColors.shadowDarkCard.withValues(alpha: 0.0),
              ],
              stops: const <double>[0.0, 0.5, 1.0],
            ),
          ),
          child: SizedBox(height: height),
        );
      },
    );

    if (widthFactor != null) {
      return FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widthFactor,
        child: bar,
      );
    }
    return SizedBox(width: width, child: bar);
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

/// Vertically centred empty-state: recessed camel medallion + headline +
/// supporting text + single primary CTA. The empty state does NOT show the
/// FAB — the inline CTA is the only first-run path so intent is unmistakable.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(VelvetSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              height: 104,
              width: 104,
              child: NeumorphicInset(
                // Circular inset medallion — same carved-in treatment as the
                // empty-state in the approved preview.
                radius: 52,
                child: Center(
                  child: Icon(
                    Icons.spa_rounded,
                    size: 44,
                    color: BrandColors.accent.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
            const SizedBox(height: VelvetSpacing.xl),
            Text(
              l10n.servicesEmpty,
              style: VelvetText.heading().copyWith(fontSize: 22),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VelvetSpacing.sm),
            Text(
              l10n.servicesEmptyBody,
              style: VelvetText.body(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VelvetSpacing.xl),
            SizedBox(
              width: 240,
              child: NeumorphicButton(
                key: const Key('btn-create-service-empty'),
                label: l10n.servicesAdd,
                icon: Icons.add_rounded,
                onPressed: () => context.push(RouteNames.serviceCreate),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Neumorphic extended FAB
// ---------------------------------------------------------------------------

/// A hand-built neumorphic extended FAB — camel/mocha gradient pill that
/// depresses on press. Material's [FloatingActionButton.extended] cannot
/// render the paired soft-UI shadows, so this widget replicates the approved
/// preview's approach exactly.
class _NeumorphicExtendedFab extends StatefulWidget {
  const _NeumorphicExtendedFab({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  State<_NeumorphicExtendedFab> createState() => _NeumorphicExtendedFabState();
}

class _NeumorphicExtendedFabState extends State<_NeumorphicExtendedFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  BrandColors.accentLatte,
                  BrandColors.accentDeep,
                ],
              ),
              borderRadius: BorderRadius.circular(VelvetRadii.pill),
              boxShadow: _pressed ? null : VelvetShadows.extrudedButtonAccent,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.add_rounded,
                  color: BrandColors.white,
                  size: 22,
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Text(widget.label, style: VelvetText.cta()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
