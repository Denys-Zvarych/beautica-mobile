// Phase 246 — Master «Новий запис»: submit-state notifier.
//
// A tiny `@riverpod` `AsyncNotifier<void>` owning SUBMIT state ONLY for the
// walk-in booking write (`POST /api/v1/masters/{masterId}/bookings`, backend
// Phase 22.4). Mirrors `leave_review_notifier.dart`'s shape — `build()` is
// idle until [submit] is invoked, and the screen reads the resulting
// [AsyncValue] after awaiting it.
//
// The wizard's STEP/FIELD state (which screen, the picked service, the typed
// guest name/phone, the chosen slot) stays local to Phase 247's screen — see
// that phase's doc. This notifier only ever sees the fully-assembled
// [CreateMasterBookingRequest] the screen hands it on the final submit tap.
//
// ## Double-submit guard
//
// A walk-in booking write is NOT idempotent on the backend in this pass (no
// `Idempotency-Key` the way the CLIENT `createBooking` write carries — see
// `create_booking_request.dart`'s header). A double tap of the submit CTA
// (a slow network + an impatient re-tap, or a stray double-frame tap) would
// therefore create TWO rows on the master's calendar for the same walk-in.
// [submit] checks `state.isLoading` and no-ops on a second call while the
// first is still in flight — checked and the `AsyncLoading` written
// SYNCHRONOUSLY, before the first `await`, so a same-frame re-entrant call
// sees the guard already up (Dart's single-threaded event loop guarantees
// no interleaving can happen strictly between those two statements).
//
// ## `value == null` is NOT how this notifier detects "nothing submitted yet"
//
// It never needs to — `build()` returns `Future<void>` (unit), so
// `state.value` is `null` on BOTH "never submitted" (build's own answer) AND
// "submitted successfully" (`submit`'s `AsyncData<void>(null)`). Any future
// change to this file that tries to branch UI behaviour on `state.value ==
// null` would be indistinguishable between those two cases — use
// `state.isLoading` / `state is AsyncError` instead, exactly as [submit]'s
// own guard does. (This note exists because `ref.invalidate` retaining the
// previous `.value` is a locked Riverpod gotcha elsewhere in this codebase —
// restated here because this notifier's `void` value type makes that trap
// invisible rather than absent.)
//
// ## Success invalidation
//
// On success, invalidates the WHOLE [bookingsDayProvider] family (every
// day/query combination the master's «Мої записи» screen may have cached) —
// not one specific family member — because this notifier does not know
// which Kyiv day the screen is currently viewing, and the newly-created
// booking's day is exactly the one piece of information worth invalidating
// for. `ref.invalidate(bookingsDayProvider)` invalidates every already-built
// member; an autoDispose member with only PAUSED listeners at invalidation
// time is disposed outright and refetches on resume (Riverpod 3's
// pause-on-cover behaviour — the same mechanism the paginated notifiers in
// this feature already document), which is the correct outcome here: the
// wizard is a full-screen route, so the day list underneath it is covered
// for the whole submit, and its refetch naturally lands when the wizard
// pops back to it.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/booking_providers.dart';
import '../domain/create_master_booking_request.dart';
import 'bookings_day_notifier.dart';

part 'master_create_booking_notifier.g.dart';

/// Submits a master (or salon owner/admin) walk-in booking and refreshes the
/// affected «Мої записи» day state.
@riverpod
class MasterCreateBookingNotifier extends _$MasterCreateBookingNotifier {
  @override
  Future<void> build() async {
    // Idle until [submit] is invoked — no work on first read.
  }

  /// Creates a walk-in booking on [masterId]'s calendar via [request].
  ///
  /// Sets [AsyncLoading] while in flight, then [AsyncData] on success or
  /// [AsyncError] (carrying the mapped [Failure] —
  /// `core/errors/failures.dart`) on failure. A second call while the first
  /// is still in flight is a NO-OP — see the file header's double-submit
  /// section.
  Future<void> submit({
    required String masterId,
    required CreateMasterBookingRequest request,
  }) async {
    if (state.isLoading) return;
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(() async {
      await ref
          .read(bookingRepositoryProvider)
          .createMasterBooking(masterId, request);
      // See the file header's "Success invalidation" section for why this
      // invalidates the WHOLE family rather than one query member.
      // cycle-safe: BookingsDayNotifier.build only watches
      // bookingRepositoryProvider / clockProvider — it never watches (even
      // transitively) masterCreateBookingProvider, so there is no back-edge
      // for this to close.
      ref.invalidate(bookingsDayProvider);
    });
  }
}
