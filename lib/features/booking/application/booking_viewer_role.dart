// Phase 7.2 — who is LOOKING at «Деталі запису».
//
// One screen serves both sides of a booking (locked decision D5: one screen,
// role-branched, on a second route). What differs is only the perspective —
// the counterparty header and the action footer — so the screen needs to know
// which side of the booking the VIEWER is on.
//
// ## Derived from the session, never from a constructor flag
//
// The obvious shape is `BookingDetailScreen(isProviderView: true)`. It is
// wrong, for a reason that is not stylistic: a widget parameter is set by the
// CALLER, so the two routes (`/bookings/:id` and `/master/bookings/:id`) each
// assert the viewer's role independently, and a copy-pasted route registration
// silently renders the client footer — «Скасувати», «Записатись знову» — to a
// master looking at their own client's appointment. The session is the single
// place that actually knows, and it cannot be passed wrongly.
//
// ## Also NOT `booking.atSalon`
//
// `atSalon` describes the BOOKING (was it made at a salon), not the VIEWER.
// The two are independent: a client viewing a salon booking and the salon's
// own master viewing that same booking both see `atSalon == true`.
//
// ## Fails CLOSED
//
// Anything that is not a confirmed provider role resolves to the CLIENT view.
// A null/loading session, an unauthenticated one, or a role this build does
// not know all land on the client branch — which grants no provider action
// (Phase 7.3 fills the provider footer). Guessing "provider" from an
// indeterminate session would hand provider affordances to whoever is looking.

import 'package:riverpod_annotation/riverpod_annotation.dart';

// `auth_notifier.dart` lives under auth/presentation/ rather than
// auth/application/ — this relative import matches the convention every other
// feature already uses to reach `authProvider` (salon, home, master,
// favorites, discovery, schedule, and booking's own
// `pending_service_preselection_provider.dart`).
import '../../auth/domain/auth_session.dart';
import '../../auth/domain/user.dart';
import '../../auth/domain/user_role.dart';
import '../../auth/presentation/auth_notifier.dart';

part 'booking_viewer_role.g.dart';

/// Which side of a booking the current viewer is on.
enum BookingViewerRole {
  /// The person who BOOKED. Sees the master/salon as counterparty and the
  /// client action footer (reschedule / cancel / rebook / review).
  client,

  /// The person who PERFORMS the booking. Sees the client as counterparty and
  /// the provider action footer (Phase 7.3 — empty in 7.2).
  provider;

  bool get isProvider => this == BookingViewerRole.provider;
}

/// Resolves the viewer's role from the authenticated session.
///
/// Generated provider name: `bookingViewerRoleProvider`.
@riverpod
BookingViewerRole bookingViewerRole(Ref ref) {
  final AuthSession? session = ref.watch(authProvider).value;
  return switch (session) {
    // MVP ships INDEPENDENT_MASTER only. `SALON_MASTER` / `SALON_ADMIN` /
    // `SALON_OWNER` are listed so the provider view lights up for them the
    // moment those roles ship, rather than silently degrading to the client
    // footer — but note they cannot currently REACH this screen (there is no
    // salon shell yet), so today this is documentation of intent.
    Authenticated(:final User user)
        when user.role == UserRole.independentMaster ||
            user.role == UserRole.salonMaster ||
            user.role == UserRole.salonAdmin ||
            user.role == UserRole.salonOwner =>
      BookingViewerRole.provider,
    // Every other case — CLIENT, unauthenticated, still loading. Fails closed
    // onto the branch that grants no provider action; see the file header.
    _ => BookingViewerRole.client,
  };
}
