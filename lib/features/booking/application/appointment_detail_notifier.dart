// MO-8 [mobile-security MEDIUM, fixed] — this provider itself is still LIVE
// (`reschedule_navigation.dart` watches it for the single-booking reschedule
// flow — do not remove it). What is NOT ROUTED any more is its ORIGINAL
// consumer pair, `VisitDetailScreen`/`AppointmentReviewScreen`: their shared
// GoRoute was unregistered from `app_router.dart` (see `visit_detail_screen.
// dart`'s header for the full finding) while both screens — and this
// provider — are INTENTIONALLY RETAINED.
//
// MO-5 — «Деталі запису» (VISIT) data source.
//
// The visit analogue of `booking_detail_notifier.dart`: a plain family
// FutureProvider fetching `GET /appointments/{appointmentId}` (the enriched
// [Appointment] — ordered items, summed totals, mutually-visible notes,
// `canReview`, locality). There is no client-owned mutation here beyond the
// visit cancel, which invalidates this provider (and the affected
// `myBookingsProvider` tabs) so the screen re-fetches the fresh server state and
// re-renders in place — see `visit_detail_screen.dart`'s cancel handler.
//
// autoDispose (the default for a `@riverpod` function) — the cache drops once
// nothing watches it (the visit detail screen is popped).

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/booking_providers.dart';
import '../domain/appointment.dart';

part 'appointment_detail_notifier.g.dart';

/// The enriched detail for one multi-service visit.
@riverpod
Future<Appointment> appointmentDetail(Ref ref, String appointmentId) {
  return ref.watch(appointmentRepositoryProvider).getAppointment(appointmentId);
}
