// Shared «Видалити салон» confirm → delete → feedback flow.
//
// PROMOTED (REUSE-FIRST, Phase 21.13) out of
// `SalonSettingsScreen._deleteSalon()` (Phase 21.2) — that screen's own
// private method duplicated this exact confirm→call→snack→navigate sequence
// and the shared account-level `SettingsScreen`'s owner-only
// `showDeleteSalon` row needed the identical behaviour. Rather than copy the
// ~20-line method a second time, it is promoted here so every delete entry
// point invokes this one function — currently the account settings hub's
// `row-delete-salon` ([SettingsScreen]) and the «Мої салони» hub's
// swipe-to-delete ([MySalonsScreen]/`SalonHubCard`'s `Dismissible`); do not
// fork this function for a new entry point — thread a new call site onto it
// instead.
//
// Phase 291 — [DeleteSalonDialog]'s body no longer claims a reversible
// soft-deactivate (that description was stale and false; see backend Phases
// 295, 269): this function now derives `isLastSalon` once, from
// `mySalonsProvider`, and passes it to the dialog so the last-salon variant
// renders for all three entry points with no per-caller branch.
//
// Shows [DeleteSalonDialog]; on confirm, calls
// `salonManagementProfileProvider(salonId).notifier.deleteSalon()`
// (`DELETE /salons/{salonId}` — owner-only, enforced server-side; hard-
// deletes staff, cancels future bookings with client notification, and
// permanently purges the salon's photos from R2); on success shows a
// success snack and navigates to
// [RouteNames.mySalons] («Мої салони») — the same landing for EVERY delete
// entry point, with no per-caller branch (locked product decision,
// superseding the phase-290 draft's proposed "last salon → logout to
// /login" branch, which is not implemented: deleting your last salon still
// lands on the hub's empty state, not a logout). Unauthenticated (session
// already gone by the time the delete round-trips) falls back to
// [RouteNames.login]; on failure shows an error snack and leaves the caller
// on the current screen.
//
// mobile-qa CRITICAL fix (swipe-to-delete audit, 2026-09-03) — THIS
// function, not `SalonManagementProfile.deleteSalon()`, invalidates
// `mySalonsProvider` on success. It used to live in the notifier, using the
// notifier's OWN `ref` — but that `ref` belongs to
// `salonManagementProfileProvider(salonId)`, an autoDispose family element
// `MySalonsScreen`'s swipe-to-delete never watches; a real (non-instant)
// `DELETE` round trip reliably disposed it mid-await (measured: even
// `ref.keepAlive()` inside the notifier didn't survive, because
// `SalonManagementProfile.build()` watches `authProvider.select(...)`, and
// `authProvider` resolving mid-await invalidates the unwatched element,
// which unconditionally clears every `KeepAliveLink` before re-checking
// whether to dispose — see `SalonManagementProfile.deleteSalon()`'s own doc
// for the full mechanism), throwing `UnmountedRefException` on the very
// next `ref.invalidate` call inside the notifier.
//
// mobile-security MEDIUM / mobile-perf LOW correction (2026-09-03) — the
// PRIOR version of this doc (and of the code below) invalidated via THIS
// function's own `WidgetRef` bound to the calling screen, gated behind the
// SAME `context.mounted` check the success snack/navigation use. That is a
// *narrower* re-run of the exact bug this function exists to fix: if the
// caller's widget unmounts while `deleteSalon()` is awaited (the user
// navigates away mid-delete), `context.mounted` goes false and the function
// returned BEFORE reaching the invalidate line — even though the `DELETE`
// had already succeeded server-side. Because `mySalonsProvider` is
// `@Riverpod(keepAlive: true)`, the deleted salon then kept rendering on
// «Мої салони» for the rest of the session. Fix: `ProviderScope.containerOf
// (context, listen: false)` is captured right after the `showDialog` await,
// while `context.mounted` is guaranteed true (just checked on the line
// above) — a `ProviderContainer` is a plain Dart handle with no tie to any
// widget's lifecycle, so holding it across the `deleteSalon()` await and
// invalidating through it afterwards is safe and unconditional, regardless
// of whether `context`/this function's `ref` are still usable by then. The
// success snack and the `context.go` navigation still need a live
// `BuildContext` to show/route through, so those stay behind the
// `context.mounted` check below — only the invalidation escapes it, and it
// escapes it for all three callers (`SettingsScreen`, `SalonSettingsScreen`,
// `MySalonsScreen`'s swipe path) identically, with no per-caller branch.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';

import '../../auth/domain/auth_session.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../application/my_salons_notifier.dart';
import '../application/salon_management_profile_notifier.dart';
import '../domain/salon.dart';
import 'widgets/delete_salon_dialog.dart';

/// Runs the shared delete-salon confirm→delete→feedback flow for [salonId].
///
/// [setLoading] is invoked with `true` the instant the owner confirms (so
/// the caller can flip its own `SettingsRow(loading: ...)` flag) and with
/// `false` again only on failure — on success the screen navigates away, so
/// there is no matching "loading=false" call to make.
Future<void> runDeleteSalonFlow({
  required BuildContext context,
  required WidgetRef ref,
  required String salonId,
  required ValueChanged<bool> setLoading,
}) async {
  final l10n = AppLocalizations.of(context);

  // Concrete-subtype gate (Phase 291 D2 / D6) — mirrors
  // `salon_home_resolver_screen.dart`'s `salonManageGuard` owner arm: a
  // stale `.value` riding a still-`AsyncLoading` state must not decide this.
  // An unresolved list falls back to `false`, which is safe here — the two
  // dialog bodies differ only by one informational closing sentence, never
  // by a warning about losing the session (there is none, see D6), so
  // understating "is this your last salon" has no dangerous downstream
  // surprise.
  final AsyncValue<List<Salon>> mySalonsAsync = ref.read(mySalonsProvider);
  final bool isLastSalon =
      mySalonsAsync is AsyncData<List<Salon>> &&
      mySalonsAsync.value.length == 1;

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => DeleteSalonDialog(isLastSalon: isLastSalon),
  );
  if (confirmed != true || !context.mounted) return;

  // Captured HERE, not after the `deleteSalon()` await — `context` is
  // guaranteed mounted (just checked on the line above) and nothing async
  // has run since, so this is always a valid handle. Unlike `ref`/`context`
  // themselves, a `ProviderContainer` is not tied to this function's
  // caller's widget lifecycle, so it stays safe to invalidate through even
  // if the caller unmounts during the await below — see this file's header
  // doc (mobile-security MEDIUM / mobile-perf LOW correction, 2026-09-03).
  final ProviderContainer container = ProviderScope.containerOf(
    context,
    listen: false,
  );

  setLoading(true);
  final failure = await ref
      .read(salonManagementProfileProvider(salonId).notifier)
      .deleteSalon();

  if (failure == null) {
    // Keeps the «Мої салони» hub's cached list from going stale after a
    // delete. `mySalonsProvider` is `@Riverpod(keepAlive: true)`, so this
    // invalidation is always safe regardless of the per-salon management
    // family's own lifecycle. UNCONDITIONAL on success — deliberately NOT
    // gated behind `context.mounted` below: see this file's header doc for
    // why gating it there was itself the bug.
    container.invalidate(mySalonsProvider);
  }

  if (!context.mounted) return;

  if (failure != null) {
    setLoading(false);
    showErrorSnack(context, failure.userMessage(context));
    return;
  }

  showSuccessSnack(context, l10n.deleteSalonSuccess);
  // «Мої салони» hub, not the auth-derived role home — every delete entry
  // point lands here (locked product decision, no per-caller branch). The
  // invalidation above means the hub re-fetches the owner's remaining
  // salons the moment it (re)builds — including when the caller was
  // already ON `/salons/mine` (swipe-to-delete).
  final session = ref.read(authProvider).value;
  final String target = session is Authenticated
      ? RouteNames.mySalons
      : RouteNames.login;
  // mobile-perf LOW follow-up (swipe-to-delete audit 2026-09): skip the
  // `go` entirely when the caller is ALREADY on [target] — the swipe path
  // is already on `/salons/mine` when it lands here, so calling `context.go`
  // unconditionally re-ran `authRedirect` + `mySalonsGuard` (both cheap
  // synchronous reads, no I/O) for zero navigational effect: go_router's
  // stable page key means the State is never remounted, and the refresh is
  // already driven by `mySalonsProvider`'s invalidation above, not by this
  // `go` call. This checks the CALLER's OWN current route via
  // [GoRouterState] — not a parameter telling the flow who called it — so
  // "every delete path lands on the hub, no per-caller branch" (the locked
  // product decision this file's header documents) still holds: every path
  // still resolves the exact same [target], the only thing skipped is a
  // provably-redundant repeat `go` to the location the caller is already on.
  if (GoRouterState.of(context).matchedLocation != target) {
    context.go(target);
  }
}
