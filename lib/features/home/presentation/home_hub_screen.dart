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

import 'dart:async';
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
import '../../../shared/calendar/add_to_calendar.dart';
import '../../booking/application/booking_reschedule_in_flight_notifier.dart';
import '../../booking/presentation/reschedule_navigation.dart';
import '../../rating/application/my_rating_notifier.dart';
import '../../rating/domain/client_rating.dart';
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
    // Drives the «Перенести» spinner while the shared reschedule navigation
    // loads its seeding GETs — `_HomeHubBody` is stateless, so a provider flag
    // (not local State) is the right mechanism.
    final bool rescheduleLoading = ref.watch(bookingRescheduleInFlightProvider);

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
                    rescheduleLoading: rescheduleLoading,
                    onReschedule: () {
                      // Route into the SAME reschedule flow the «Деталі запису»
                      // screen uses — the card only has the booking id, so the
                      // shared helper loads the rest (master + booked service)
                      // before seeding the slot picker.
                      if (appt != null) {
                        unawaited(
                          startBookingReschedule(
                            context: context,
                            ref: ref,
                            bookingId: appt.id,
                          ),
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
                    // Both variants share ONE code path: add_2_calendar opens
                    // the OS default-calendar sheet, so the OS — not the app —
                    // picks Google vs Apple vs any other calendar app.
                    onAddToGoogleCalendar: () {
                      if (appt != null) {
                        unawaited(
                          _addNextAppointmentToCalendar(context, l10n, appt),
                        );
                      }
                    },
                    onAddToAppleCalendar: () {
                      if (appt != null) {
                        unawaited(
                          _addNextAppointmentToCalendar(context, l10n, appt),
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

/// Adds the home-hub next appointment to the OS calendar via the shared
/// [addBookingToCalendar] path (opens the platform default-calendar sheet).
///
/// NOTE: the `NextAppointment` payload (backend 19.3) exposes only `startsAt` —
/// no duration/end — so the event is seeded with a 1-hour default block. When
/// that DTO surfaces `durationMinutes`/`endAt`, pass the real end here.
Future<void> _addNextAppointmentToCalendar(
  BuildContext context,
  AppLocalizations l10n,
  NextAppointment appt,
) {
  // Structured facts only — NO free-text notes reach the calendar (the
  // `NextAppointment` DTO carries none anyway). The limited DTO exposes just
  // service, master, the pre-formatted date/time strings the card renders, and
  // a location — no duration/end (hence the 1-hour default block above), no
  // price, no definite status. Omit the fields it lacks rather than emit empty
  // labels; the builder skips any null/blank value.
  final String? location = appt.location.isEmpty ? null : appt.location;
  final String? description = buildCalendarDescription(
    l10n: l10n,
    service: appt.service,
    provider: appt.masterName,
    providerRole: CalendarProviderRole.master,
    dateTime: '${appt.dateLabel}, ${appt.timeLabel}',
    address: location,
  );
  return addBookingToCalendar(
    context: context,
    title: l10n.bookingCalendarEventTitle(appt.service, appt.masterName),
    location: location,
    start: appt.startsAt,
    end: appt.startsAt.add(const Duration(hours: 1)),
    description: description,
  );
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
    // Source the pill from the AUTHORITATIVE rating provider — the same
    // `GET /users/me/rating` loader that backs `MyRatingScreen` (the detail
    // window opened by tapping this pill). The profile summary's `clientRating`
    // slice is unpopulated and renders "—", so the two used to disagree; reading
    // `myRatingProvider` here keeps home and detail in lock-step on the real
    // number. It is `keepAlive`-cached (5-min TTL) — the same in-flight/cached
    // call the detail screen makes, so this adds no repeated network cost.
    //
    // Watching it directly also de-couples this row from profile edits (name /
    // photo / city), so it no longer rebuilds on those — narrower than the old
    // shared-provider `.select`. All three AsyncValue states stay distinct so
    // the `error:` branch below keeps its graceful "—" fallback (never a
    // perpetual skeleton).
    final AsyncValue<ClientRating> ratingAsync = ref.watch(myRatingProvider);

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
            // Seamless reload: keep showing the last-known real number across a
            // recompute instead of flashing the skeleton. Riverpod retains the
            // previous `.value` through a reload/refresh, and `.when` surfaces it
            // via `data(...)` when a value exists — `skipLoadingOnRefresh` is
            // already true by default (so `ref.invalidate(myRatingProvider)` is
            // seamless); `skipLoadingOnReload: true` extends the same to a
            // dependency-triggered rebuild. The skeleton therefore shows ONLY on
            // the true COLD load (no cached value yet — `keepAlive` holds the
            // value for 5 min, so a back-nav within the window never re-skeletons).
            // Crucially the value rendered during a reload is myRatingProvider's
            // OWN authoritative number, never the profile `clientRating` slice or
            // a hardcoded "—", so this cannot resurrect the stale-number bug.
            // `skipError` stays false → the error branch keeps its graceful "—".
            child: ratingAsync.when(
              skipLoadingOnReload: true,
              data: (ClientRating rating) => MyRatingStatCard(
                clientRating: rating.avgRating,
                onTap: onRating,
              ),
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

/// One section's reveal animations, built once per distinct interval.
///
/// [opacity] is a `CurvedAnimation` and OWNS a status listener on the parent
/// controller — it must be disposed. [position] is only a `Tween.animate(...)`
/// view over it and needs no disposal of its own.
class _RevealAnimations {
  const _RevealAnimations({required this.opacity, required this.position});

  final CurvedAnimation opacity;
  final Animation<Offset> position;
}

class _StaggeredRevealState extends State<_StaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  // PERF: `_reveal` is invoked once per section on EVERY build of the hub's
  // ListView, and `_HomeHubBody` watches four providers — so allocating a fresh
  // `CurvedAnimation` per call leaked a listener on each one. `CurvedAnimation`'s
  // constructor calls `parent.addStatusListener(...)` and ONLY its `dispose()`
  // removes it, so undisposed instances accumulated on `_controller` for the
  // whole lifetime of the screen. Building each distinct `(start, end)` interval
  // exactly once — and disposing every cached one in `dispose()` — keeps the
  // listener set bounded AND properly torn down. Keyed on the interval record:
  // Dart records have structural equality, so identical bounds reuse one entry.
  final Map<(double, double), _RevealAnimations> _revealCache =
      <(double, double), _RevealAnimations>{};

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
    // Each cached CurvedAnimation still holds a status listener on _controller —
    // dispose them BEFORE the controller so every listener is removed.
    for (final _RevealAnimations anims in _revealCache.values) {
      anims.opacity.dispose();
    }
    _revealCache.clear();
    _controller.dispose();
    super.dispose();
  }

  Widget _reveal({
    required double start,
    required double end,
    required Widget child,
  }) {
    // Lazily memoized per interval — see the `_revealCache` comment above for
    // why re-allocating these on every build is a listener leak.
    final _RevealAnimations anims = _revealCache.putIfAbsent((start, end), () {
      final CurvedAnimation opacity = CurvedAnimation(
        parent: _controller,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      );
      return _RevealAnimations(
        opacity: opacity,
        position: Tween<Offset>(
          begin: const Offset(0, 0.35),
          end: Offset.zero,
        ).animate(opacity),
      );
    });
    return FadeTransition(
      opacity: anims.opacity,
      child: SlideTransition(position: anims.position, child: child),
    );
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _reveal);
}
