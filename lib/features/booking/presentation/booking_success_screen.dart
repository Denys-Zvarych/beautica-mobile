// BookingSuccessScreen: the independent-master booking flow's post-submit
// celebration, shown after every appointment's `POST /bookings` succeeds.
//
// MULTI-SERVICE (the multi-service booking rework): the flow now books N
// services with a SEPARATE time each, so the recap LISTS one card per confirmed
// appointment (a shared address card, then per-appointment date/time + service
// + price, then a grand total when N > 1) — mirrors the salon success screen's
// per-appointment recap, keyed by SERVICE. The shared celebration structure
// (PopScope, animated badge, staggered reveal, pinned footer) lives in
// `widgets/booking_success_scaffold.dart`.
//
// Reached ONLY via `BookingConfirmScreen`'s `pushReplacement` once EVERY
// appointment succeeded (partial failures keep the client on the confirm
// screen), so the recap here is always the full, confirmed set. The scaffold's
// `PopScope(canPop: false)` blocks back — the pinned «На головну» is the only
// way forward.
//
// SEC: the recap renders the INDEPENDENT master's address
// (street/buildingNo/city/locationNote — a solo master's may be a HOME
// address), so this screen acquires the app-wide screenshot guard in
// `initState`. Do not remove in a future audit pass.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/calendar/add_to_calendar.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';
import 'package:beautica_mobile/shared/formatters/street_city_line.dart';

import '../domain/booking_success_args.dart';
import 'widgets/booking_recap.dart';
import 'widgets/booking_success_scaffold.dart';
import 'widgets/booking_summary_cards.dart';
import 'widgets/calendar_button.dart';
import 'widgets/labelled_row.dart';

/// Booking flow — the post-submit celebration screen (N confirmed appointments).
class BookingSuccessScreen extends ConsumerStatefulWidget {
  const BookingSuccessScreen({super.key, required this.args});

  final BookingSuccessArgs args;

  @override
  ConsumerState<BookingSuccessScreen> createState() =>
      _BookingSuccessScreenState();
}

class _BookingSuccessScreenState extends ConsumerState<BookingSuccessScreen> {
  late final ScreenProtectionManager _screenProtection;

  // `widget.args` never changes for this screen's lifetime, so the flattened
  // grand-total selection list is computed once here.
  late final List<BookingSelection> _allSelections = widget.args.appointments
      .map(
        (BookingSuccessAppointment a) => BookingSelection(
          name: a.service.name,
          price: ServicePriceDisplay.format(a.service),
          duration: DurationMinutes.format(a.service.durationMinutes),
          durationMinutes: a.service.durationMinutes,
          priceMin: a.service.priceMin,
          priceMax: a.service.priceMax,
        ),
      )
      .toList();

  @override
  void initState() {
    super.initState();
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final List<BookingSuccessAppointment> appointments =
        widget.args.appointments;
    final master = widget.args.master;

    final String? addressLine = formatStreetCityLine(
      street: master.street,
      buildingNo: master.buildingNo,
      city: master.city,
    );
    final String? addressDetail =
        (master.locationNote?.trim().isNotEmpty ?? false)
        ? master.locationNote!.trim()
        : null;

    final bool isReschedule = widget.args.isReschedule;

    return BookingSuccessScaffold(
      title: isReschedule
          ? l10n.bookingRescheduleSuccessTitle
          : l10n.bookingSuccessTitle,
      subline: isReschedule
          ? l10n.bookingRescheduleSuccessSubline
          : l10n.bookingSuccessSubline,
      actions: <Widget>[
        SuccessSecondaryButton(
          buttonKey: const Key('booking-success-home-cta'),
          label: l10n.bookingSuccessHomeCta,
          icon: Icons.home_outlined,
          onPressed: () => context.go(RouteNames.clientHome),
        ),
      ],
      belowRecap: CalendarButton(onTap: () => _onAddToCalendar(context)),
      recapCards: <Widget>[
        NeumorphicCard(
          key: const Key('booking-success-address-card'),
          showBorder: true,
          padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
          child: LabelledRow(
            label: l10n.bookingAddressLabel,
            value: addressLine ?? l10n.bookingAddressUnknown,
            detail: addressDetail,
            compactText: true,
          ),
        ),
        for (int i = 0; i < appointments.length; i++)
          BookingSummaryCards(
            key: ValueKey<String>(
              'booking-success-appt-${appointments[i].service.id}-$i',
            ),
            showAddress: false,
            dateLabel: formatFullDate(appointments[i].start),
            timeLabel: formatTimeRange(
              appointments[i].start,
              appointments[i].service.durationMinutes,
            ),
            singleSelection: _allSelections[i],
            dense: true,
            showBorder: true,
            compactText: true,
          ),
        if (appointments.length > 1)
          NeumorphicCard(
            key: const Key('booking-success-grand-total-card'),
            showBorder: true,
            padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
            child: BookingRecap(
              selections: _allSelections,
              totalOnly: true,
              dense: true,
              compactText: true,
            ),
          ),
      ],
    );
  }

  /// Opens the OS calendar's "new event" sheet for the just-confirmed booking.
  ///
  /// A booking is always ≥1 appointment; the single `belowRecap` button adds
  /// the FIRST one. The native INSERT sheet is one-event-per-invocation, so a
  /// multi-service booking (N>1) intentionally seeds only the first appointment
  /// rather than firing N stacked OS sheets — the client can add the rest from
  /// «Мої записи» per booking.
  Future<void> _onAddToCalendar(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final master = widget.args.master;
    final BookingSuccessAppointment first = widget.args.appointments.first;

    // Same street/buildingNo/city join the recap's address card renders.
    final String? location = formatStreetCityLine(
      street: master.street,
      buildingNo: master.buildingNo,
      city: master.city,
    );
    final String provider = '${master.firstName} ${master.lastName}'.trim();
    final DateTime end = first.start.add(
      Duration(minutes: first.service.durationMinutes),
    );

    return addBookingToCalendar(
      context: context,
      title: l10n.bookingCalendarEventTitle(first.service.name, provider),
      location: location,
      start: first.start,
      end: end,
    );
  }
}
