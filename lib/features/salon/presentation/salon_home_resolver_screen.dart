// Phase 21.8 — Salon Home Resolver.
//
// `RouteNames.salonHome` (`/salons/home`) — the SHARED `SALON_OWNER`/
// `SALON_ADMIN` landing (`roleHomePath`). A transient stopover, never a
// destination the viewer lingers on: it resolves which salon's shell to
// enter and forwards there.
//
//   * `SALON_ADMIN` — `session.user.salonId` is read SYNCHRONOUSLY (no
//     provider at all — an admin belongs to exactly one salon, already known
//     from the JWT-derived profile).
//   * `SALON_OWNER` — watches `mySalonsProvider` (`GET /salons/mine`) and
//     picks the primary salon (falling back to the first salon when no row
//     is marked primary, or when several are — bad data must still resolve
//     to SOME salon, never crash the landing).
//
// Navigation happens from a `postFrame` callback, NEVER a go_router
// `redirect:` — `redirect:` is synchronous and must never await the network
// (mirrors `salonManageGuard`'s own doc in `app_router.dart`). Gates on the
// CONCRETE `AsyncData`/`AsyncError` subtypes, exactly like
// `app_router.dart`'s `salonManageGuard` owner arm, so a `copyWithPrevious`
// stale `.value` riding a later `AsyncLoading`/`AsyncError` (e.g. mid-retry,
// or right after a cross-account login on the same device) is never read as
// if it were a genuinely resolved list.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:go_router/go_router.dart';

import '../application/my_salons_notifier.dart';
import '../domain/salon.dart';

/// Resolves the `SALON_OWNER`/`SALON_ADMIN` shared landing to a specific
/// salon's shell screen (`RouteNames.salonShell`) — or, for the zero-salons
/// edge case, back to the My Salons hub — and forwards there.
class SalonHomeResolverScreen extends ConsumerWidget {
  const SalonHomeResolverScreen({super.key});

  void _goToShell(BuildContext context, String salonId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) context.go(RouteNames.salonShell(salonId));
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<AuthSession> authAsync = ref.watch(authProvider);
    // mobile-qa MEDIUM (2026-09-05) — concrete-subtype gate, the SAME
    // discipline `app_router.dart`'s `resolvedSession()` applies and the same
    // one the `mySalonsProvider` read below already applied. A bare
    // `authAsync.value` is not "the current session": `copyWithPrevious` keeps
    // the PREVIOUS account's `AsyncData` attached to a later `AsyncError` /
    // `AsyncLoading(retrying: true)`, and `salonHomeGuard` now deliberately
    // ADMITS an unresolved session — so a stale `SALON_ADMIN` would reach this
    // build, read that account's `user.salonId` and forward straight into
    // ANOTHER salon's shell. Unresolved therefore reads as "no session yet",
    // which falls into the skeleton below and re-resolves on the next
    // `authProvider` emission (this is a `ref.watch`).
    final AuthSession? session = authAsync is AsyncData<AuthSession>
        ? authAsync.value
        : null;

    if (session is! Authenticated) {
      // mobile-security LOW (2026-09-05) — `AsyncLoading` and `AsyncError` are
      // NOT the same unresolved state, so they do not share a body.
      //
      //   * `AsyncError` — terminal until something re-runs the provider. The
      //     skeleton would spin forever with no affordance, so render
      //     [ErrorState] with a retry that invalidates `authProvider`, exactly
      //     as the `mySalonsProvider` arm below does for its own error.
      //   * everything else (`AsyncLoading`, or a settled
      //     `AsyncData(Unauthenticated)` in the window before the global
      //     `authRedirect` bounces it to /login) — genuinely "not known yet";
      //     hold the skeleton rather than crash on a null user.
      //
      // Neither arm dispatches. A stale `Authenticated` riding an `AsyncError`
      // via `copyWithPrevious` was already excluded by the concrete-subtype
      // gate above, and stays excluded here — the retry affordance replaces an
      // indefinite spinner, it does NOT relax that gate.
      //
      // Defence in depth plus re-entrancy: nothing in `lib/` invalidates
      // `authProvider` from a healthy session (the only two
      // `ref.invalidate(authProvider)` sites are this arm's own retry and
      // `master_received_reviews_screen.dart:90`, both already-unresolved
      // arms), and a cold-start `build()` rejection is bounced to `/login` by
      // `auth_redirect.dart:250` before this screen mounts. What this arm must
      // handle is its OWN retry re-failing — `ref.invalidate` re-runs
      // `build()`, whose pre-`try` secure-storage statements
      // (`auth_notifier.dart:261-262` and `:287`) sit outside the
      // `:291`-`:335` catch-all and forward to the platform channel unguarded
      // — so it renders the error again instead of spinning. Riverpod's
      // auto-retry is live on this provider too
      // — `auth_notifier.g.dart:45` `retry: null` means INHERIT, and
      // `main.dart:138` installs `beauticaProviderRetry` on the root
      // container, which hands a non-`Failure` error to
      // `ProviderContainer.defaultRetry` (`failure_retry_policy.dart:135-145`).
      if (authAsync is AsyncError<AuthSession>) {
        final Object error = authAsync.error;
        return Scaffold(
          backgroundColor: BrandColors.base,
          body: SafeArea(
            child: ErrorState(
              failure: error is Failure ? error : UnknownFailure(cause: error),
              onRetry: () => ref.invalidate(authProvider),
            ),
          ),
        );
      }
      return _LoadingBody(
        semanticLabel: l10n.salonHomeResolverLoadingSemantics,
      );
    }

    if (session.user.role == UserRole.salonAdmin) {
      final String? salonId = session.user.salonId;
      if (salonId == null) {
        // Never a blank screen — a JWT-authenticated admin with no bound
        // salon is a data problem, not a "still loading" state.
        return const Scaffold(
          backgroundColor: BrandColors.base,
          body: SafeArea(child: ErrorState(failure: UnknownFailure())),
        );
      }
      _goToShell(context, salonId);
      return _LoadingBody(
        semanticLabel: l10n.salonHomeResolverLoadingSemantics,
      );
    }

    // SALON_OWNER.
    final AsyncValue<List<Salon>> mySalonsAsync = ref.watch(mySalonsProvider);

    if (mySalonsAsync is AsyncError<List<Salon>>) {
      final Object error = mySalonsAsync.error;
      return Scaffold(
        backgroundColor: BrandColors.base,
        body: SafeArea(
          child: ErrorState(
            failure: error is Failure ? error : UnknownFailure(cause: error),
            onRetry: () => ref.invalidate(mySalonsProvider),
          ),
        ),
      );
    }

    // Concrete-subtype gate (mirrors `app_router.dart`'s `salonManageGuard`
    // owner arm) — a stale `.value` riding a still-`AsyncLoading` state is
    // never treated as resolved.
    final List<Salon>? salons = mySalonsAsync is AsyncData<List<Salon>>
        ? mySalonsAsync.value
        : null;

    if (salons == null) {
      return _LoadingBody(
        semanticLabel: l10n.salonHomeResolverLoadingSemantics,
      );
    }

    if (salons.isEmpty) {
      // No salon to enter — the My Salons hub owns «+ Додати салон» and a
      // tested empty state; land there instead of a shell with no salonId.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(RouteNames.mySalons);
      });
      return _LoadingBody(
        semanticLabel: l10n.salonHomeResolverLoadingSemantics,
      );
    }

    // `firstWhere` — NEVER `singleWhere`, which throws on the "several
    // isPrimary == true" bad-data case. `orElse` covers "isPrimary all
    // null/false": both fall back to the first salon in the list.
    final Salon primary = salons.firstWhere(
      (Salon s) => s.isPrimary == true,
      orElse: () => salons.first,
    );
    _goToShell(context, primary.id);
    return _LoadingBody(semanticLabel: l10n.salonHomeResolverLoadingSemantics);
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody({required this.semanticLabel});

  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('salon-home-resolver-loading'),
      backgroundColor: BrandColors.base,
      body: SafeArea(
        child: Semantics(
          label: semanticLabel,
          child: const SkeletonShimmerScope(
            child: Center(
              child: SkeletonBlock(
                width: 220,
                height: 120,
                radius: VelvetRadii.card,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
