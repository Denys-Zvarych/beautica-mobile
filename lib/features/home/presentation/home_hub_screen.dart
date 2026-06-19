// Phase 13.7 — CLIENT Головна (Home Hub) screen.
//
// Post-login landing: bottom-nav tab index 0 for CLIENT role.
// Acquires ScreenProtectionManager in initState (PII: name, phone, city).
//
// Layout (scrollable ListView of cards, staggered reveal):
//   1. Top bar: beautica wordmark | bell | burger
//   2. Profile block
//   3. Stat pills (IntrinsicHeight-wrapped — CRITICAL render bug prevention)
//   4. Quick-links row (IntrinsicHeight-wrapped)
//   5. Next appointment (empty state while backend 19.3 ships)
//   6. Favourite masters rail (empty state while backend 19.1 ships)
//   7. BEAUTY TIMELINE rail (empty state while backend 19.5 ships)
//
// Each section is a separate widget built from its own AsyncValue so that
// one failing card cannot blank the whole screen.
//
// l10n gate: every user-facing Ukrainian string goes through AppLocalizations
// EXCEPT the two locked brand literals:
//   • "BEAUTY PASSPORT" in PassportPreviewCard
//   • "BEAUTY TIMELINE" in BeautyTimelineSection
// Those are intentionally untranslated per the locked product decision.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/security/screen_protection.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../application/home_hub_notifier.dart';
import '../domain/home_hub_models.dart';
import 'widgets/beauty_timeline_section.dart';
import 'widgets/favorite_masters_card.dart';
import 'widgets/home_profile_card.dart';
import 'widgets/hub_widgets.dart';
import 'widgets/next_appointment_card.dart';
import 'widgets/passport_preview_card.dart';
import 'widgets/quick_links_card.dart';

/// The CLIENT Головна (Home Hub) — Phase 13.7.
class HomeHubScreen extends ConsumerStatefulWidget {
  const HomeHubScreen({super.key});

  @override
  ConsumerState<HomeHubScreen> createState() => _HomeHubScreenState();
}

class _HomeHubScreenState extends ConsumerState<HomeHubScreen> {
  // Riverpod 3.x rule: never call ref inside dispose().
  // The _protection field is a late final backed by ref.read(...).
  // Accessing it in initState() eagerly runs the lazy initializer while
  // ref is valid; the cached manager reference is then safe to call in
  // dispose() without touching ref again.
  late final ScreenProtectionManager _protection = ref.read(
    screenProtectionProvider,
  );

  @override
  void initState() {
    super.initState();
    // CRITICAL-4: Home Hub shows name / phone / city — acquire screen
    // protection so FLAG_SECURE / iOS app-switcher blur is active while
    // this screen is mounted.
    //
    // Accessing _protection here (not ref.read directly) forces the lazy
    // initializer to run now, while ref is valid. dispose() then only
    // reads the cached field — ref is never touched during dispose().
    _protection.acquire();
    if (kDebugMode) {
      log(
        'HomeHubScreen mounted — screen protection acquired',
        name: 'feature.home',
        level: 800,
      );
    }
  }

  @override
  void dispose() {
    // _protection was initialised in initState — safe to call here.
    // ref is NOT accessed (Riverpod 3.x rule obeyed).
    _protection.release();
    if (kDebugMode) {
      log(
        'HomeHubScreen disposed — screen protection released',
        name: 'feature.home',
        level: 800,
      );
    }
    super.dispose();
  }

  void _onBellTap() {
    // Phase 14.9 not yet shipped — placeholder navigation.
    // TODO(14.9): route to RouteNames.notifications when that screen ships.
    if (kDebugMode) {
      log(
        'notifications tapped — placeholder',
        name: 'feature.home',
        level: 700,
      );
    }
  }

  void _onBurgerTap() {
    // Phase 14.10 (client settings) not yet shipped — placeholder.
    // TODO(14.10): route to RouteNames.clientSettings when that screen ships.
    if (kDebugMode) {
      log('burger menu tapped — placeholder', name: 'feature.home', level: 700);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        bottom: false,
        child: _HomeHubBody(
          l10n: l10n,
          onBellTap: _onBellTap,
          onBurgerTap: _onBurgerTap,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — ConsumerWidget so it can watch the async providers independently
// ---------------------------------------------------------------------------

class _HomeHubBody extends ConsumerWidget {
  const _HomeHubBody({
    required this.l10n,
    required this.onBellTap,
    required this.onBurgerTap,
  });

  final AppLocalizations l10n;
  final VoidCallback onBellTap;
  final VoidCallback onBurgerTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch each card's data independently — one AsyncError must not blank all.
    final profileAsync = ref.watch(clientProfileProvider);
    final nextApptAsync = ref.watch(nextAppointmentProvider);
    final favoritesAsync = ref.watch(favoriteMastersProvider);
    final timelineAsync = ref.watch(beautyTimelineProvider);

    return RepaintBoundary(
      child: _StaggeredReveal(
        builder: (BuildContext context, _RevealFn reveal) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.lg,
              VelvetSpacing.sm,
              VelvetSpacing.lg,
              VelvetSpacing.lg,
            ),
            children: <Widget>[
              // 1. Top bar
              reveal(
                start: 0.0,
                end: 0.4,
                child: _TopBar(onBell: onBellTap, onBurger: onBurgerTap),
              ),
              const SizedBox(height: VelvetSpacing.lg),

              // 2. Profile block
              reveal(
                start: 0.05,
                end: 0.46,
                child: profileAsync.when(
                  data: (ClientProfileSummary p) => HomeProfileCard(
                    profile: p,
                    onCamera: () {
                      if (kDebugMode) {
                        log(
                          'change photo tapped — placeholder',
                          name: 'feature.home',
                          level: 700,
                        );
                      }
                    },
                    onLocation: () {
                      if (kDebugMode) {
                        log(
                          'location tapped — placeholder',
                          name: 'feature.home',
                          level: 700,
                        );
                      }
                    },
                  ),
                  loading: () => const _ProfileSkeleton(),
                  error: (Object e, _) => _CardErrorState(
                    message: l10n.homeHubProfileLoadError,
                    onRetry: () => ref.invalidate(clientProfileProvider),
                  ),
                ),
              ),
              const SizedBox(height: VelvetSpacing.lg),

              // 3. Stat pills (IntrinsicHeight — CRITICAL render bug prevention)
              reveal(
                start: 0.11,
                end: 0.52,
                child: _StatPillsRow(
                  profileAsync: profileAsync,
                  onPassport: () => context.push(RouteNames.clientPassport),
                  onReviews: () => context.push(RouteNames.myReviews),
                ),
              ),
              const SizedBox(height: VelvetSpacing.md),

              // 4. Quick-links
              reveal(start: 0.17, end: 0.58, child: const QuickLinksCard()),
              const SizedBox(height: VelvetSpacing.lg),

              // 5. Next appointment
              reveal(
                start: 0.23,
                end: 0.64,
                child: nextApptAsync.when(
                  data: (NextAppointment? appt) => NextAppointmentCard(
                    appointment: appt,
                    onReschedule: () {
                      // TODO(14.8): route to reschedule screen
                      if (kDebugMode) {
                        log(
                          'reschedule tapped — placeholder',
                          name: 'feature.home',
                          level: 700,
                        );
                      }
                    },
                    onCancel: () {
                      // TODO(14.5): route to cancel screen
                      if (kDebugMode) {
                        log(
                          'cancel tapped — placeholder',
                          name: 'feature.home',
                          level: 700,
                        );
                      }
                    },
                    onAddToGoogleCalendar: () {
                      // TODO(14.4): add-to-calendar helper
                      if (kDebugMode) {
                        log(
                          'add to google cal — placeholder',
                          name: 'feature.home',
                          level: 700,
                        );
                      }
                    },
                    onAddToAppleCalendar: () {
                      if (kDebugMode) {
                        log(
                          'add to apple cal — placeholder',
                          name: 'feature.home',
                          level: 700,
                        );
                      }
                    },
                  ),
                  loading: () => const _SectionSkeleton(),
                  error: (Object e, _) => _CardErrorState(
                    message: l10n.homeHubNextApptLoadError,
                    onRetry: () => ref.invalidate(nextAppointmentProvider),
                  ),
                ),
              ),
              const SizedBox(height: VelvetSpacing.lg),

              // 6. Favourite masters
              reveal(
                start: 0.29,
                end: 0.70,
                child: favoritesAsync.when(
                  data: (List<FavoriteMasterItem> masters) =>
                      FavoriteMastersCard(
                        masters: masters,
                        totalCount: masters.length,
                      ),
                  loading: () => const _SectionSkeleton(),
                  error: (Object e, _) => _CardErrorState(
                    message: l10n.homeHubFavoritesLoadError,
                    onRetry: () => ref.invalidate(favoriteMastersProvider),
                  ),
                ),
              ),
              const SizedBox(height: VelvetSpacing.lg),

              // 7. BEAUTY TIMELINE
              reveal(
                start: 0.35,
                end: 0.78,
                child: timelineAsync.when(
                  data: (List<TimelineEntry> entries) => BeautyTimelineSection(
                    entries: entries,
                    onSeeAll: () {
                      // TODO(13.9): route to timeline page
                      if (kDebugMode) {
                        log(
                          'timeline see-all — placeholder',
                          name: 'feature.home',
                          level: 700,
                        );
                      }
                    },
                  ),
                  loading: () => const _SectionSkeleton(),
                  error: (Object e, _) => _CardErrorState(
                    message: l10n.homeHubTimelineLoadError,
                    onRetry: () => ref.invalidate(beautyTimelineProvider),
                  ),
                ),
              ),
              const SizedBox(height: VelvetSpacing.lg),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stat pills row — wraps passport + reviews tiles in IntrinsicHeight
// ---------------------------------------------------------------------------

class _StatPillsRow extends StatelessWidget {
  const _StatPillsRow({
    required this.profileAsync,
    required this.onPassport,
    required this.onReviews,
  });

  final AsyncValue<ClientProfileSummary> profileAsync;
  final VoidCallback onPassport;
  final VoidCallback onReviews;

  @override
  Widget build(BuildContext context) {
    // CRITICAL: IntrinsicHeight bounds the stretch Row so CrossAxisAlignment.stretch
    // is well-defined inside the ListView. Without it the cross axis is unbounded
    // and the Row silently produces an unpaintable sliver on Flutter web.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: PassportPreviewCard(onTap: onPassport)),
          const SizedBox(width: VelvetSpacing.md - 4),
          Expanded(
            child: profileAsync.when(
              data: (ClientProfileSummary p) => ReviewsStatCard(
                reviewsLeft: p.reviewsLeft,
                memberSinceYear: p.memberSinceYear,
                onTap: onReviews,
              ),
              loading: () => const _StatPillSkeleton(),
              error: (Object e, StackTrace st) => ReviewsStatCard(
                reviewsLeft: 0,
                memberSinceYear: DateTime.now().year,
                onTap: onReviews,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBell, required this.onBurger});

  final VoidCallback onBell;
  final VoidCallback onBurger;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        // beautica wordmark — intentionally lowercase (brand decision)
        Text(
          // ignore: avoid_hardcoded_strings — brand wordmark, NOT translated
          'beautica',
          style: VelvetText.wordmark(),
        ),
        const Spacer(),
        _BellButton(
          key: const Key('home_hub_bell_button'),
          onTap: onBell,
          semanticLabel: l10n.homeHubNotificationsLabel,
        ),
        const SizedBox(width: VelvetSpacing.sm + 4),
        _PlainIconButton(
          key: const Key('home_hub_menu_button'),
          icon: Icons.menu_rounded,
          semanticLabel: l10n.homeHubMenuLabel,
          onTap: onBurger,
        ),
      ],
    );
  }
}

class _PlainIconButton extends StatelessWidget {
  const _PlainIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 24, color: BrandColors.textSecondary),
        ),
      ),
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({
    super.key,
    required this.onTap,
    required this.semanticLabel,
  });

  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              const Icon(
                Icons.notifications_none_rounded,
                size: 24,
                color: BrandColors.textSecondary,
              ),
              Positioned(
                right: 0,
                top: 1,
                child: Container(
                  height: 8,
                  width: 8,
                  decoration: BoxDecoration(
                    color: BrandColors.accentDeep,
                    shape: BoxShape.circle,
                    border: Border.all(color: BrandColors.base, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading skeletons
// ---------------------------------------------------------------------------

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          height: 96,
          width: 96,
          decoration: BoxDecoration(
            color: BrandColors.faint.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: VelvetSpacing.md),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SkeletonBar(width: 140, height: 20),
              SizedBox(height: VelvetSpacing.sm),
              _SkeletonBar(width: 100, height: 14),
              SizedBox(height: VelvetSpacing.sm - 2),
              _SkeletonBar(width: 120, height: 14),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatPillSkeleton extends StatelessWidget {
  const _StatPillSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: BrandColors.faint.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(18),
      ),
    );
  }
}

class _SectionSkeleton extends StatelessWidget {
  const _SectionSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SkeletonBar(width: 140, height: 14),
        const SizedBox(height: VelvetSpacing.md),
        Container(
          height: 80,
          decoration: BoxDecoration(
            color: BrandColors.faint.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ],
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: BrandColors.faint.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Per-card error state (inline — does not blank the whole screen)
// ---------------------------------------------------------------------------

class _CardErrorState extends StatelessWidget {
  const _CardErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HubFlatCard(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md,
        vertical: VelvetSpacing.md,
      ),
      child: HubEmptyState(
        icon: Icons.error_outline_rounded,
        message: message,
        ctaLabel: l10n.retryLabel,
        onCta: onRetry,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Staggered reveal (ported from branch_placeholders.dart, same as preview's
// StaggeredReveal, but ticker-gated for the StatefulShellRoute IndexedStack)
// ---------------------------------------------------------------------------

typedef _RevealFn =
    Widget Function({
      required double start,
      required double end,
      required Widget child,
    });

class _StaggeredReveal extends StatefulWidget {
  const _StaggeredReveal({required this.builder});

  final Widget Function(BuildContext context, _RevealFn reveal) builder;

  @override
  State<_StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<_StaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && TickerMode.valuesOf(context).enabled) {
      _started = true;
      // Post-frame so initial paint is not lost at 0.0 opacity.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final bool animationsDisabled =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        if (animationsDisabled) {
          _controller.value = 1.0;
        } else {
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _reveal({
    required double start,
    required double end,
    required Widget child,
  }) {
    final Animation<double> curved = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.35),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _reveal);
}
