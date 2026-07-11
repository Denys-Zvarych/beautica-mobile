// Phase 14.18 — SalonBookingSuccessScreen: salon booking flow step 4b, the
// post-submit celebration. Mirrors the independent-master
// `BookingSuccessScreen` (`booking_success_screen.dart`) — animated success
// badge → "Записано!" headline → reassuring subline → the booking recap →
// a single pinned "На головну" — extended to LIST every created appointment
// (one `SalonAppointmentCard` per master) instead of a single recap.
//
// The shared celebration structure lives in
// `widgets/booking_success_scaffold.dart` (composed by both success screens);
// this screen just supplies its copy and its N-card recap. The scaffold wraps
// each recap card in the same staggered reveal.
//
// Reached ONLY via `SalonBookingConfirmScreen`'s `pushReplacement` once EVERY
// appointment's `POST /bookings` succeeded (partial failures keep the client
// on the confirm screen), so the recap here is always the full, confirmed
// set. The scaffold's `PopScope(canPop: false)` blocks back like the
// independent success screen — the pinned "На головну" is the only way forward.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import '../domain/salon_booking_confirm_args.dart';
import 'widgets/booking_success_scaffold.dart';
import 'widgets/salon_appointment_card.dart';
import 'widgets/salon_avatar_gradients.dart';

/// Salon booking flow step 4b — the confirmed N-appointment recap.
class SalonBookingSuccessScreen extends StatelessWidget {
  const SalonBookingSuccessScreen({super.key, required this.args});

  final SalonBookingSuccessArgs args;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final List<SalonBookingAppointment> appointments = args.appointments;
    return BookingSuccessScaffold(
      title: l10n.salonBookingSuccessTitle,
      subline: l10n.salonBookingSuccessSubline,
      homeButtonKey: const Key('salon-success-home-cta'),
      onHome: () => context.go(RouteNames.clientHome),
      homeGap: VelvetSpacing.sm,
      recapCards: <Widget>[
        for (int i = 0; i < appointments.length; i++)
          SalonAppointmentCard(
            key: ValueKey<String>(
              'salon-success-appt-${appointments[i].schedule.masterId}',
            ),
            appointment: appointments[i],
            avatarGradient: salonAvatarGradient(i),
          ),
      ],
    );
  }
}
