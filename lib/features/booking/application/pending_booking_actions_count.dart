// Phase 393 (24.7a) — `pendingBookingActionsCountProvider`: the number of
// bookings awaiting a provider action (close, or rate the client) for one
// [PendingActionsScope].
//
// autoDispose family (not keepAlive): lives while the «Записи» screen watching
// it is mounted. Freshness comes from Phase 394's invalidation points.
//
// Failure surfaces as `AsyncError` — never a fake `0`. The badge (395) renders
// only from `AsyncData`.

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
// `ProviderListenable.select` is not in riverpod_annotation's show-list.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/failures.dart';
import '../../../core/time/clock_provider.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../data/booking_providers.dart';
import '../domain/pending_actions_scope.dart';

export '../domain/pending_actions_scope.dart';

part 'pending_booking_actions_count.g.dart';

/// Phase 394 — minimum gap between a build and a `resumed`-triggered refetch.
/// Local on purpose (not coupled to the notifications constant).
const Duration kPendingActionsResumeMinGap = Duration(seconds: 15);

@riverpod
Future<int> pendingBookingActionsCount(
  Ref ref,
  PendingActionsScope scope,
) async {
  // MASVS-AUTH (phase 394 audit) — tie this element to the AUTHENTICATED
  // IDENTITY: `scope` (incl. `salonId`) is a frozen argument, so without this
  // a still-alive element could refetch with the previous user's scope after
  // a logout / account switch. NARROWED via `.select` (never a bare
  // `authProvider` watch — it would also rebuild on every token refresh).
  final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
  if (userId == null) return 0; // signed out: no request, nothing to count.

  // Abort the in-flight request when this autoDispose element goes away
  // (screen pop / logout), mirroring `booked_days_notifier.dart`.
  final CancelToken cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);

  // Phase 394 — time alone moves a booking into «needs closing» when its
  // `endsAt` passes, so refetch on app resume (no polling). Throttled against
  // this build's start; a backwards clock jump counts as "gap elapsed".
  final DateTime Function() now = ref.read(clockProvider);
  final DateTime builtAt = now();
  final AppLifecycleListener lifecycle = AppLifecycleListener(
    onResume: () {
      if (!ref.mounted) return;
      // Resume-time identity guard: signed out, or a different user than the
      // one this build captured -> never refetch with the stale scope.
      if (authUserIdOrNull(ref.read(authProvider)) != userId) return;
      final DateTime t = now();
      if (!t.isBefore(builtAt) &&
          t.difference(builtAt) < kPendingActionsResumeMinGap) {
        return;
      }
      ref.invalidateSelf();
    },
  );
  ref.onDispose(lifecycle.dispose);
  try {
    return await ref
        .read(bookingRepositoryProvider)
        .getPendingActionsCount(scope, cancelToken: cancelToken);
  } on Failure {
    // Our own cancellation (the element is already disposed) is not a
    // failure: swallow it so it neither reaches the zone as an unhandled
    // error nor becomes an error state. The value is discarded with the
    // disposed element — it is never observed, so it is not a fake `0`.
    if (cancelToken.isCancelled) return 0;
    rethrow;
  }
}
