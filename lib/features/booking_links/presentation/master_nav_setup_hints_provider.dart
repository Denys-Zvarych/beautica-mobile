// 2026-10-30 — setup-hint dots on the master bottom nav («Послуги» tile 0,
// «Графік» tile 2).
//
// REUSE-FIRST: no new fetch and no second readiness rule. This is the phase
// 416 «Посилання для запису» MASTER-link readiness answer
// ([bookingLinkSetupHintsProvider] with [BookingLinkKind.master]) — the same
// "no ACTIVE service" / "no bookable day in 180 days" verdict the link card
// already shows — re-exposed for the nav, gated to INDEPENDENT_MASTER. One rule, two
// surfaces: a fix to the readiness rule lands on both.
//
// Inherited behaviour (see that provider's header): loading, any error and
// the first build after an account switch read as "nothing missing", so the
// dots never flicker in on a guess; a re-fetch after a save keeps the previous
// answer until it settles. A services create/edit invalidates
// `masterServiceCatalogProvider`, and a weekly save / override write refreshes
// every live `effectiveScheduleProvider` window of the scope, so each dot
// clears on its own.
//
// Schedule rule = the backend's bookability (any working day in the next
// 180 Kyiv days, overrides first) — owned by the upstream provider.
//
// ROLE GATE runs FIRST, before the upstream is touched: SALON_OWNER (incl.
// owner master mode), SALON_ADMIN, SALON_MASTER and CLIENT get
// [BookingLinkSetupHints.none] and never read the independent-master
// catalogue / own-schedule providers through here. Narrowed selectors only —
// never a bare `authProvider` watch (`project_bare_auth_watch_destroys_state`).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/domain/user_role.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../domain/booking_link.dart';
import 'booking_link_setup_hints_provider.dart';

part 'master_nav_setup_hints_provider.g.dart';

/// Which master-nav setup dots show. [BookingLinkSetupHints.none] for every
/// role but INDEPENDENT_MASTER and for an unresolved session.
///
/// `dependencies:` is required by
/// `scripts/forbid_undeclared_scoped_service_dep.sh`: the upstream reads the
/// scoped services chain, so this reader declares its way down to it.
@Riverpod(dependencies: [BookingLinkSetupHintsNotifier])
BookingLinkSetupHints masterNavSetupHints(Ref ref) {
  // ── Session gates — ALL run before any upstream read ──────────────────────
  // Narrowed selectors only (never a bare `authProvider` watch). Both read
  // `session.value`, so an `Unauthenticated` session — logout flips to it
  // synchronously, in the same turn as its schedule sweeps — yields `null`
  // here, and this provider returns before touching the upstream. That keeps
  // the logout sweep's invalidations from being re-read through the nav with
  // the outgoing scope (perf LOW, cycle 1: a wasted request that 401s).
  final UserRole? role = ref.watch(authProvider.select(authUserRoleOrNull));
  if (role != UserRole.independentMaster) return BookingLinkSetupHints.none;
  final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
  if (userId == null || userId.isEmpty) return BookingLinkSetupHints.none;

  // The account-switch identity gate (settled profile id == own-scope id)
  // lives in the upstream's master branch, so the booking-links card gets it
  // too — see `BookingLinkSetupHintsNotifier._masterNoSchedule`.
  return ref.watch(
    bookingLinkSetupHintsProvider(BookingLinkKind.master, '', userId),
  );
}
