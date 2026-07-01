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
import '../../../l10n/app_localizations.dart';
import '../../../routing/app_router.dart';
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // The top bar (wordmark · bell · burger) is hosted by ClientShell — this
    // screen is just the branch body. The shell owns the single SafeArea(top)
    // too, so the body must NOT re-wrap one.
    return _HomeHubBody(l10n: l10n);
  }
}

// ---------------------------------------------------------------------------
// Body — ConsumerWidget so it can watch the async providers independently
// ---------------------------------------------------------------------------

class _HomeHubBody extends ConsumerWidget {
  const _HomeHubBody({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch each card's data independently — one AsyncError must not blank all.
    // NOTE: clientProfileProvider is intentionally NOT watched here. The profile
    // card and the rating stat pill consume it inside their own leaf widgets
    // (_ProfileSection / _StatPillsRow), so a profile edit rebuilds only those
    // leaves — not this whole body — and the rating pill uses a `.select` slice
    // so it only rebuilds when the rating itself changes.
    final nextApptAsync = ref.watch(nextAppointmentProvider);
    final favoritesAsync = ref.watch(favoriteMastersProvider);
    final timelineAsync = ref.watch(beautyTimelineProvider);

    return RepaintBoundary(
      child: _StaggeredReveal(
        builder: (BuildContext context, _RevealFn reveal) {
          return ListView(
            // Top inset matches the gap the on-screen bar used to leave above
            // the profile block: the shell-owned ClientTopBar sits directly
            // above this body, so the first card needs a `lg` breathing gap
            // (the old bar reveal + its trailing `lg` SizedBox collapsed to
            // this single top pad). Bottom keeps the page's `lg` end inset.
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.lg,
              VelvetSpacing.lg,
              VelvetSpacing.lg,
              VelvetSpacing.lg,
            ),
            children: <Widget>[
              // (Top bar removed — now persistent chrome owned by ClientShell.)

              // 2. Profile block
              reveal(start: 0.05, end: 0.46, child: const _ProfileSection()),
              const SizedBox(height: VelvetSpacing.lg),

              // 3. Stat pills (IntrinsicHeight — CRITICAL render bug prevention)
              reveal(
                start: 0.11,
                end: 0.52,
                child: _StatPillsRow(
                  // Passport is shell branch [kClientPassportBranch]. Hop the
                  // branch (not `context.push`) so the page AND the bottom-nav
                  // selection stay in sync — a plain push stacks Passport on the
                  // Home branch and leaves the Home tile filled.
                  onPassport: () => StatefulNavigationShell.of(
                    context,
                  ).goBranch(kClientPassportBranch),
                  // Rating lives OUTSIDE the shell — a normal push is correct.
                  onRating: () => context.push(RouteNames.myRating),
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
// Profile block — leaf consumer so a profile edit rebuilds only this card,
// not the whole _HomeHubBody. Needs the full ClientProfileSummary.
// ---------------------------------------------------------------------------

class _ProfileSection extends ConsumerWidget {
  const _ProfileSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<ClientProfileSummary> profileAsync = ref.watch(
      clientProfileProvider,
    );
    return profileAsync.when(
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
    );
  }
}

// ---------------------------------------------------------------------------
// Stat pills row — wraps passport + reviews tiles in IntrinsicHeight
// ---------------------------------------------------------------------------

class _StatPillsRow extends ConsumerWidget {
  const _StatPillsRow({required this.onPassport, required this.onRating});

  final VoidCallback onPassport;
  final VoidCallback onRating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Narrow `.select` — this row only needs the rating slice, so it rebuilds
    // only when clientRating changes (not on name / photo / city edits). This
    // de-dupes the previous full-provider watch shared with the profile card.
    // Project to the rating slice while PRESERVING the error state. `whenData`
    // would collapse an error into AsyncLoading and leave the `error:` branch
    // below as dead code (perpetual skeleton on profile-load failure); `map`
    // keeps all three states distinct so the graceful "—" fallback renders.
    final AsyncValue<double?> ratingAsync = ref.watch(
      clientProfileProvider.select(
        (AsyncValue<ClientProfileSummary> v) => v.map(
          data: (AsyncData<ClientProfileSummary> d) =>
              AsyncData<double?>(d.value.clientRating),
          error: (AsyncError<ClientProfileSummary> e) =>
              AsyncError<double?>(e.error, e.stackTrace),
          loading: (AsyncLoading<ClientProfileSummary> l) =>
              const AsyncLoading<double?>(),
        ),
      ),
    );

    // CRITICAL: IntrinsicHeight bounds the stretch Row so CrossAxisAlignment.stretch
    // is well-defined inside the ListView. Without it the cross axis is unbounded
    // and the Row silently produces an unpaintable sliver on Flutter web.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 3 : 2 width split — BEAUTY PASSPORT is the primary CTA so it reads
          // visibly wider; the rating pill (shorter content) takes the narrower
          // 2-share. Heights stay equal via IntrinsicHeight + stretch above.
          Expanded(flex: 3, child: PassportPreviewCard(onTap: onPassport)),
          const SizedBox(width: VelvetSpacing.md - 4),
          Expanded(
            flex: 2,
            child: ratingAsync.when(
              data: (double? rating) =>
                  MyRatingStatCard(clientRating: rating, onTap: onRating),
              loading: () => const _StatPillSkeleton(),
              error: (Object e, StackTrace st) =>
                  MyRatingStatCard(clientRating: null, onTap: onRating),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading skeletons
// ---------------------------------------------------------------------------

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  // Hoisted — withValues inside build() allocates a Color on every frame.
  static final BoxDecoration _avatarDecoration = BoxDecoration(
    color: BrandColors.faint.withValues(alpha: 0.3),
    shape: BoxShape.circle,
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(height: 96, width: 96, decoration: _avatarDecoration),
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

  // Hoisted — withValues inside build() allocates a Color on every frame.
  static final BoxDecoration _decoration = BoxDecoration(
    color: BrandColors.faint.withValues(alpha: 0.25),
    borderRadius: BorderRadius.circular(18),
  );

  @override
  Widget build(BuildContext context) {
    return Container(height: 64, decoration: _decoration);
  }
}

class _SectionSkeleton extends StatelessWidget {
  const _SectionSkeleton();

  // Hoisted — withValues inside build() allocates a Color on every frame.
  static final BoxDecoration _blockDecoration = BoxDecoration(
    color: BrandColors.faint.withValues(alpha: 0.25),
    borderRadius: BorderRadius.circular(20),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SkeletonBar(width: 140, height: 14),
        const SizedBox(height: VelvetSpacing.md),
        Container(height: 80, decoration: _blockDecoration),
      ],
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, required this.height});

  final double width;
  final double height;

  // Hoisted — withValues inside build() allocates a Color on every frame.
  // BorderRadius.circular(8) is the same for all sizes so one decoration covers all.
  static final BoxDecoration _decoration = BoxDecoration(
    color: BrandColors.faint.withValues(alpha: 0.3),
    borderRadius: BorderRadius.circular(8),
  );

  @override
  Widget build(BuildContext context) {
    return Container(width: width, height: height, decoration: _decoration);
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
