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
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/failures.dart';
import '../data/booking_providers.dart';
import '../domain/pending_actions_scope.dart';

export '../domain/pending_actions_scope.dart';

part 'pending_booking_actions_count.g.dart';

@riverpod
Future<int> pendingBookingActionsCount(
  Ref ref,
  PendingActionsScope scope,
) async {
  // Abort the in-flight request when this autoDispose element goes away
  // (screen pop / logout), mirroring `booked_days_notifier.dart`.
  final CancelToken cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);
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
