// Phase 13.5 — Public master profile loader (client-facing).
//
// A `@riverpod` family keyed on the target [masterId]. It loads the master's
// public detail and active services in PARALLEL ([Future.wait]) and returns
// both as a record so the screen renders the identity card, the stats row
// (services count), and the booking shelf from a single AsyncValue.
//
// CLIENT-safety: both reads go through providers that depend ONLY on the Dio
// stack — [masterRepositoryProvider] (Dio + generated MasterControllerApi) and
// [publicServiceRepositoryProvider] (the public, path-parameterised services
// endpoint). Neither drags in the master-only [masterProfileProvider], so a
// CLIENT session never fires `GET /masters/me` (which 403s + triggers Riverpod's
// retry storm).
//
// Cache: autoDispose by default, but [ref.keepAlive] holds the result for a
// 5-minute TTL so pushing into the profile and swiping back does not refetch,
// while a stale profile eventually refreshes on the next view. The TTL timer is
// cancelled on dispose so no [Timer] leaks (mobile-perf MP pattern).

// Prefixed: `dart:async`'s non-generic [async.AsyncError] (carried by the
// records `.wait` [async.ParallelWaitError]) must NOT be confused with Riverpod's
// generic `AsyncError<T>`, which `riverpod_annotation` brings unprefixed into
// scope. Mis-resolving the two would make the unwrap's record type-check below
// fail at runtime and silently re-throw the wrapper.
import 'dart:async' as async;

// `ProviderListenable.select` (used below to narrow the `authProvider` watch to
// the identity-bearing slice via [authUserIdOrNull]) is not part of
// `riverpod_annotation`'s show-list — same reason `bookings_day_notifier.dart`
// reaches for the full package.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/presentation/auth_notifier.dart';
import '../../services/data/service_repository.dart';
import '../../services/domain/master_service.dart';
import '../data/master_repository.dart';
import '../domain/master.dart';

part 'public_master_profile_notifier.g.dart';

/// The data the public master profile screen renders: the master's public
/// detail paired with its active services (used for the services stat tile,
/// the read-only service-categories section, and the future Phase 14.1
/// service selection).
typedef PublicMasterProfileData = (Master master, List<MasterService> services);

/// Loads the public profile + active services for [masterId] in parallel.
///
/// Generated provider name: `publicMasterProfileProvider` (a family — call it
/// with the target master id, e.g. `publicMasterProfileProvider(masterId)`).
@riverpod
Future<PublicMasterProfileData> publicMasterProfile(
  Ref ref,
  String masterId,
) async {
  // Auth-boundary eviction (mobile-perf MP + mobile-security): watch the
  // session so this keepAlive family is torn down on a logout / session change
  // (logout → login), mirroring the self-clearing pattern every per-session
  // keepAlive provider uses (favoriteToggleProvider, the services providers).
  // The data here is public, so there is no cross-account bleed — but tying the
  // cache lifetime to the session keeps a stale 5-minute entry from surviving a
  // re-login. When the session flips the watched value changes, the kept-alive
  // link from the previous compute is closed on dispose and the family rebuilds.
  //
  // NARROWED to the user id (mobile-perf LOW, 2026-09-01) — "the session
  // flips" above IS a change of signed-in identity (including → null on
  // logout). A bare `ref.watch(authProvider)` also fired on every silent token
  // refresh, discarding a live 5-minute cache entry and refetching
  // `GET /masters/{id}` + `GET /masters/{id}/services` mid-scroll. Nothing in
  // this body reads any other part of the session.
  ref.watch(authProvider.select(authUserIdOrNull));

  // 5-minute cache window. Keep the link alive across the push/pop of the
  // profile, then close it so a stale profile eventually refetches. The timer
  // is cancelled on dispose so it can never fire after the provider is gone.
  final link = ref.keepAlive();
  final async.Timer timer = async.Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);

  final MasterRepository masterRepo = ref.read(masterRepositoryProvider);
  final ServiceRepository serviceRepo = ref.read(
    publicServiceRepositoryProvider,
  );

  // Load both in parallel — neither read depends on the other. The records
  // `.wait` extension wraps ANY failing future in a [ParallelWaitError], which
  // would mask the typed [Failure] and force the screen's error branch to render
  // a generic UnknownFailure for every backend error. We therefore UNWRAP it
  // below and rethrow the underlying typed [Failure] so the screen surfaces the
  // specific network-/server-error copy. The parallel load is preserved (the two
  // reads still race; only the error mapping changes).
  try {
    final (Master master, List<MasterService> services) = await (
      masterRepo.getMasterById(masterId),
      serviceRepo.getMasterServices(masterId),
    ).wait;

    // The FULL services list is loaded (not just its `.length`) deliberately:
    // the record is reused as-is by the Phase 14.1 service-selection / slot-
    // picker flow, so it is retained rather than reduced to a count here.
    return (master, services);
  } on async.ParallelWaitError<
    (Master?, List<MasterService>?),
    (async.AsyncError?, async.AsyncError?)
  > catch (error, stackTrace) {
    // `errors` is a 2-tuple of the per-future AsyncError? — exactly one entry is
    // non-null per failed read. Rethrow the first underlying error (a typed
    // Failure) with its ORIGINAL stack trace so the screen's `e is Failure`
    // branch matches and the correct localized copy renders.
    final (async.AsyncError? masterError, async.AsyncError? servicesError) =
        error.errors;
    final async.AsyncError? firstError = masterError ?? servicesError;
    if (firstError != null) {
      Error.throwWithStackTrace(firstError.error, firstError.stackTrace);
    }
    // Defensive: no underlying error to unwrap (should never happen) — rethrow
    // the wrapper as-is so the failure is never silently swallowed.
    Error.throwWithStackTrace(error, stackTrace);
  }
}
