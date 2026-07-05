// Phase 14.14 — WorkingDays family AsyncNotifier: calendar day-availability
// gating for the booking flow's date picker (SlotDateScreen).
//
// Keyed by [WorkingDaysQuery] (masterId + bounded date range) — masterId-
// parameterized deliberately (unlike `effectiveScheduleProvider`, which is
// hard-wired to "my own master only" via `masterProfileProvider`) so the SAME
// provider is ready to key the salon multi-master step-3 time picker later
// (still a Phase 14.13 placeholder — `SalonBookingComingSoonScreen` — NOT
// wired up yet; out of scope for this phase) without any rework. See the
// boundary note in `data/slot_repository.dart` for why this lives in the
// booking feature rather than `schedule/`.
//
// Mirrors the general SHAPE of
// `schedule/presentation/effective_schedule_notifier.dart` (a family-keyed
// AsyncNotifier resolving over a bounded date range) but deliberately WITHOUT
// that notifier's bounded-cache `keepAlive` / reactive-overrides-dependency
// machinery: those solve problems specific to the schedule editor (a
// save-refresh coherence bug against a WRITE path, plus a deliberate
// month-revisit cache for the owner's OWN schedule). This provider has no
// write path of its own — the client-side calendar only ever reads — so
// there is nothing to keep coherent with, and Riverpod's default family
// disposal (release once unwatched) is sufficient. `SlotDateScreen` keeps its
// own last-good-month cache for the loading-flash UX instead (mirroring the
// VISUAL pattern of `MasterScheduleScreen`, not its cache lifetime).

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/booking_providers.dart';
import '../domain/working_day.dart';
import '../domain/working_days_query.dart';

part 'working_days_notifier.g.dart';

/// Resolves the per-date working/non-working signal for
/// `query.masterId` across `query.from`..`query.to` (inclusive, date-only).
/// The range MUST be bounded to the backend's ~365-day span cap (mirrors
/// `/effective-schedule`); callers key this to one visible calendar month,
/// always well under that cap.
///
/// Generated provider name: `workingDaysProvider` (a family — call
/// `workingDaysProvider(query)`).
@riverpod
class WorkingDaysNotifier extends _$WorkingDaysNotifier {
  @override
  Future<List<WorkingDay>> build(WorkingDaysQuery query) async {
    // Cancel-on-supersede, mirroring `SlotPickerNotifier.loadSlots`: unlike
    // that notifier (a single long-lived instance reused across calls), this
    // is a `WorkingDaysQuery`-keyed family — rapid month-nav taps
    // (`MonthCalendar`'s chevrons, undebounced) don't reuse THIS instance,
    // they make the caller watch a NEW family member and stop watching this
    // one, so the supersession point is autoDispose tearing this instance
    // down once unwatched, not a second call into `build()`. `ref.onDispose`
    // is exactly that teardown hook — cancelling here means a superseded
    // month's request stops competing for bandwidth/queue slots with the
    // month the user actually stopped on.
    final CancelToken cancelToken = CancelToken();
    ref.onDispose(() => cancelToken.cancel());
    // `async` is deliberate (not a bare passthrough return): it ensures a
    // SYNCHRONOUS throw from the repository call (e.g. a mocktail
    // `thenThrow` in tests — real `HttpSlotRepository.getWorkingDays` never
    // throws synchronously, only via its returned Future) is captured as a
    // rejected Future rather than escaping `build()` itself, matching how
    // `EffectiveScheduleNotifier.build` is written.
    return await ref
        .watch(slotRepositoryProvider)
        .getWorkingDays(
          masterId: query.masterId,
          from: query.from,
          to: query.to,
          cancelToken: cancelToken,
        );
  }
}
