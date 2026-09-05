// Phase 21.1 — My Salons Hub loader.
//
// A single-call notifier backing `MySalonsScreen`: loads the authenticated
// SALON_OWNER's full salon list via `SalonRepository.getMySalons()` (`GET
// /salons/mine`).
//
// Unlike `public_salon_profile_notifier.dart` (which loads a salon + its
// masters rail in PARALLEL via a record `.wait` and must therefore unwrap
// `ParallelWaitError` — see that file's header), this provider makes exactly
// ONE repository call, so there is nothing to unwrap: a thrown [Failure]
// propagates to the `AsyncValue.error` branch untouched, already carrying
// the real cause.
//
// mobile-perf HIGH follow-up (2026-08-28) — promoted from a bare `autoDispose`
// `@riverpod` function to `@Riverpod(keepAlive: true)`, mirroring
// `master_profile_notifier.dart`'s exact shape. `salonManageGuard`'s
// `SALON_OWNER` arm (`app_router.dart`) reads this provider's value
// synchronously inside a `redirect:` callback via `ref.read` — under
// `autoDispose`, that bare read INITIALIZED the provider (firing a real `GET
// /salons/mine`) and then immediately DISPOSED it (zero consumers), so every
// hub→manage→settings navigation — and every `authProvider` re-emission (a
// 401 refresh) while parked on either route — refired the fetch from
// scratch, contradicting the guard's own "ALREADY-RESOLVED value" comment.
// `keepAlive: true` makes that comment true: once resolved (from the hub
// visit, or from the guard's own first read on a direct deep link), the
// value survives every subsequent navigation for the rest of the session.
//
// Auth-boundary eviction — like [MasterProfile], `build()` watches
// [authProvider] (narrowed to the signed-in user id via [authUserIdOrNull] —
// see the NARROWED note in `build()`) and throws [UnauthorizedFailure] once
// that id is null. This is NOT a manual `ref.invalidate(...)` wired
// into `AuthNotifier.logout()` — see that method's own NOTE on why a manual
// invalidation from inside `logout()` would close a dependency cycle
// (`CircularDependencyError`, debug/test only) for any provider that itself
// watches `authProvider`. Instead, the auth-provider watch means Riverpod's
// ordinary dependency cascade rebuilds this notifier the instant `authProvider`
// flips away from `Authenticated` — on logout AND on login as a DIFFERENT
// account — so a keepAlive singleton never leaks one owner's salon list past
// a session boundary into the next signed-in user.

// `ProviderListenable.select` (used below to narrow the `authProvider` watch to
// the identity-bearing slice via [authUserIdOrNull]) is not part of
// `riverpod_annotation`'s show-list — same reason `bookings_day_notifier.dart`
// reaches for the full package.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/failures.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../data/salon_repository.dart';
import '../domain/salon.dart';

part 'my_salons_notifier.g.dart';

/// Loads and caches the authenticated `SALON_OWNER`'s full salon list.
///
/// Generated provider name: `mySalonsProvider`.
@Riverpod(keepAlive: true)
class MySalons extends _$MySalons {
  @override
  Future<List<Salon>> build() {
    // NARROWED with `.select` (mobile-perf MEDIUM, 2026-09-01) — this used to
    // watch the whole `AsyncValue<AuthSession>`. `AuthNotifier.setAccessToken`
    // re-emits `Authenticated` with a new accessToken on EVERY silent token
    // refresh, and because this is a `keepAlive` provider the salon shell keeps
    // it subscribed for the whole session (`salon_shell_screen.dart` reads it
    // as its ownership source), so an un-narrowed watch refired
    // `GET /salons/mine` on every refresh while the owner just sat in the
    // shell. Only the signed-in IDENTITY can invalidate this list.
    //
    // Same fix, same shared selector, as `master_profile_notifier.dart` and
    // `client_edit_profile_notifier.dart` — see [authUserIdOrNull]'s own doc
    // for why there is one definition rather than seven copies.
    //
    // `null` still means "not authenticated": a logout flips the selected
    // value from the user id to null, rebuilding this provider into the
    // [UnauthorizedFailure] branch exactly as the un-narrowed watch did, so
    // the auth-boundary eviction described in this file's header is intact.
    final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
    if (userId == null) {
      throw const UnauthorizedFailure();
    }
    return ref.read(salonRepositoryProvider).getMySalons();
  }
}
