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
// ## PHASE 256 — [submit] now RETURNS the created [Appointment]
//
// The `done` step needs the SERVER's visit (window, totals, ordered items),
// not the wizard's local selection — see `master_create_booking_screen.dart`'s
// `_DoneStep` doc. Two ways to get it there were on the table: widen `state`
// to `AsyncValue<Appointment?>`, or keep `state` exactly as `void` and have
// [submit] hand the value back as its own return. Widening `state` was
// REJECTED — it would resurrect the EXACT trap the section above documents
// (`state.value == null` on both "idle" and "submitted"), except now for a
// value type where a caller is far more likely to reach for `.value` than for
// this notifier's own `void`. So `state` stays `void`, unchanged in shape and
// meaning; [submit] separately returns `Appointment?` — non-null on success,
// `null` on the double-submit no-op AND on a mapped [Failure] (the caller
// reads `state.hasError`/`state.error` for that, exactly as before this
// phase). The screen stores the returned value in its OWN local field
// (`_createdAppointment`) rather than reading it back off this provider.
//
// ## Success invalidation
//
// Routed through `booking_calendar_invalidation.dart`'s
// `invalidateBookingViewsAfterBookingCreated`, this feature's ONE fan-out
// point for "which master-facing booking caches does this write drop?" —
// rather than enumerated inline here. That is what caught the 2026-08-20
// mobile-debugger MEDIUM: this notifier dropped `bookingsDayProvider` but not
// `bookedDaysProvider`, so a day the master had just booked carried no
// rail/month dot until that 30-minute-TTL singleton happened to refetch.
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
import '../domain/appointment.dart';
import '../domain/create_master_booking_request.dart';
import 'booking_calendar_invalidation.dart';

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
  ///
  /// Returns the server's created [Appointment] on success, `null` on the
  /// no-op AND on a mapped [Failure] — see the file header's "PHASE 256"
  /// section for why this is a return value rather than a widened `state`.
  Future<Appointment?> submit({
    required String masterId,
    required CreateMasterBookingRequest request,
  }) async {
    if (state.isLoading) return null;
    state = const AsyncLoading<void>();
    Appointment? created;
    state = await AsyncValue.guard(() async {
      created = await ref
          .read(bookingRepositoryProvider)
          .createMasterBooking(masterId, request);
      // See the file header's "Success invalidation" section for why this
      // invalidates the WHOLE `bookingsDayProvider` family rather than one
      // query member, and `booking_calendar_invalidation.dart` for why the
      // day-rail/month dot set (`bookedDaysProvider`) must drop alongside it.
      invalidateBookingViewsAfterBookingCreated(ref);
    });
    return created;
  }
}
