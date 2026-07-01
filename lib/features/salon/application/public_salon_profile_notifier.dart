// Phase 13.6 — Public salon profile loader (client-facing).
//
// A `@riverpod` family keyed on the target [salonId]. Loads the salon's
// public detail and its masters rail in PARALLEL ([Future.wait]) and returns
// both as a record so the screen renders the cover/hero card and the
// "Майстри" tab from a single AsyncValue. The "Послуги" and "Відгуки" tabs
// are backed by their OWN separate providers (see
// `salon_service_catalog_notifier.dart` / `salon_review_summary_notifier.dart`
// / `salon_reviews_notifier.dart`) rather than being folded into this one, so
// each tab can load/retry/error independently.
//
// Cache: autoDispose by default, but [ref.keepAlive] holds the result for a
// 5-minute TTL so pushing into the profile and swiping back does not refetch,
// mirroring [publicMasterProfileProvider]'s TTL pattern exactly.

// Prefixed: `dart:async`'s non-generic [async.AsyncError] (carried by the
// records `.wait` [async.ParallelWaitError]) must NOT be confused with Riverpod's
// generic `AsyncError<T>`, which `riverpod_annotation` brings unprefixed into
// scope. Mis-resolving the two would make the unwrap's record type-check below
// fail at runtime and silently re-throw the wrapper.
import 'dart:async' as async;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/presentation/auth_notifier.dart';
import '../data/salon_repository.dart';
import '../domain/salon.dart';
import '../domain/salon_master_summary.dart';

part 'public_salon_profile_notifier.g.dart';

/// The data the public salon profile screen's hero + "Майстри" tab render:
/// the salon's public detail paired with its masters rail.
typedef PublicSalonProfileData = (
  Salon salon,
  List<SalonMasterSummary> masters,
);

/// Loads the public profile + masters rail for [salonId] in parallel.
///
/// Generated provider name: `publicSalonProfileProvider` (a family — call it
/// with the target salon id, e.g. `publicSalonProfileProvider(salonId)`).
@riverpod
Future<PublicSalonProfileData> publicSalonProfile(
  Ref ref,
  String salonId,
) async {
  // Auth-boundary eviction (mobile-perf MP + mobile-security): watch the
  // session so this keepAlive family is torn down on a logout / session change
  // (logout → login), mirroring [publicMasterProfileProvider].
  ref.watch(authProvider);

  // 5-minute cache window. Keep the link alive across the push/pop of the
  // profile, then close it so a stale profile eventually refetches. The timer
  // is cancelled on dispose so it can never fire after the provider is gone.
  final link = ref.keepAlive();
  final async.Timer timer = async.Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);

  final SalonRepository repo = ref.read(salonRepositoryProvider);

  // Load both in parallel — neither read depends on the other. See
  // [publicMasterProfileProvider] for the rationale behind unwrapping
  // [async.ParallelWaitError] instead of letting the screen see a generic
  // wrapper error.
  try {
    final (Salon salon, List<SalonMasterSummary> masters) = await (
      repo.getSalonById(salonId),
      repo.getSalonMasters(salonId),
    ).wait;
    return (salon, masters);
  } on async.ParallelWaitError<
    (Salon?, List<SalonMasterSummary>?),
    (async.AsyncError?, async.AsyncError?)
  > catch (error, stackTrace) {
    final (async.AsyncError? salonError, async.AsyncError? mastersError) =
        error.errors;
    final async.AsyncError? firstError = salonError ?? mastersError;
    if (firstError != null) {
      Error.throwWithStackTrace(firstError.error, firstError.stackTrace);
    }
    // Defensive: no underlying error to unwrap (should never happen) — rethrow
    // the wrapper as-is so the failure is never silently swallowed.
    Error.throwWithStackTrace(error, stackTrace);
  }
}
