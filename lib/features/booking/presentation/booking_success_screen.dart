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
// «ДОДАТИ В КАЛЕНДАР» — ONE PER APPOINTMENT: the OS calendar's INSERT sheet
// takes exactly one event per invocation, so the old single page-level pill
// below the recap could only ever seed the FIRST of N services.
// Each appointment card now carries its own compact `CalendarButton`
// (`BookingSummaryCards.trailingAction`) and the page-level pill is gone —
// including for N == 1, so there is one rule and one layout to maintain
// rather than "bottom button when N == 1, per-card buttons otherwise".
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
import 'package:beautica_mobile/features/services/domain/master_service.dart';
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

  /// Re-entry guard for the OS calendar INSERT intent, shared by ALL N
  /// per-appointment buttons.
  ///
  /// The trigger went from one page-level pill to one button per appointment
  /// card, so a same-gesture double-tap — or a tap that lands on an ADJACENT
  /// card while the first is still going out — used to fire two INSERT intents
  /// for two different events. This drops the second: one pending request at a
  /// time, later taps ignored until it resolves.
  ///
  /// Scope, precisely: on Android `Add2Calendar.addEvent2Cal` resolves as soon
  /// as `startActivity` returns, NOT when the user dismisses the OS sheet, so
  /// the flag is true only for the channel round trip. It closes the
  /// double-fire window it was raised for (the gated-`Completer` test in
  /// `booking_success_calendar_test.dart` proves it bites) — it makes no
  /// promise about the activity stack once the sheet is up.
  ///
  /// Deliberately NOT `setState`-driven: nothing on screen is painted from it,
  /// so flipping it must not rebuild N recap cards.
  bool _calendarInFlight = false;

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
            // Each appointment exports ITSELF. The OS INSERT sheet is one
            // event per invocation, so a single page-level button could only
            // ever seed one of N — see `_onAddToCalendar`.
            trailingAction: CalendarButton(
              buttonKey: ValueKey<String>(
                'booking-success-add-calendar-'
                '${appointments[i].service.id}-$i',
              ),
              semanticsLabel: l10n.bookingAddCalendarServiceSemantics(
                appointments[i].service.name,
              ),
              onTap: () => _onAddToCalendar(context, appointments[i]),
            ),
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

  /// Opens the OS calendar's "new event" sheet for [appointment] — the ONE
  /// confirmed appointment whose recap card carries the tapped button.
  ///
  /// The native INSERT sheet is one-event-per-invocation, so a multi-service
  /// booking cannot be exported by a single control. Rather than have one
  /// button silently seed only the first appointment (its behaviour before the
  /// multi-service rework), EVERY appointment card carries its own — including
  /// when there is just one, so there is a single rule and a single layout.
  /// Nothing here may read `appointments.first`.
  ///
  /// Guarded by [_calendarInFlight]: while one INSERT intent is pending, taps
  /// on the OTHER cards (and repeat taps on this one) are dropped rather than
  /// stacking a second platform activity.
  Future<void> _onAddToCalendar(
    BuildContext context,
    BookingSuccessAppointment appointment,
  ) async {
    if (_calendarInFlight) return;
    _calendarInFlight = true;
    try {
      final l10n = AppLocalizations.of(context);
      final master = widget.args.master;
      final MasterService service = appointment.service;

      // Same street/buildingNo/city join the recap's address card renders (the
      // address is the master's, shared by every appointment).
      final String? location = formatStreetCityLine(
        street: master.street,
        buildingNo: master.buildingNo,
        city: master.city,
      );
      final String provider = '${master.firstName} ${master.lastName}'.trim();
      final DateTime end = appointment.start.add(
        Duration(minutes: service.durationMinutes),
      );

      // Structured facts only — NO free-text note fields reach the calendar.
      // Date+time and price reuse the exact strings this appointment's own
      // recap card renders. A just-submitted booking is auto-approved CONFIRMED
      // (see domain rules), so the status line is the confirmed label.
      final String? description = buildCalendarDescription(
        l10n: l10n,
        service: service.name,
        provider: provider,
        providerRole: CalendarProviderRole.master,
        dateTime:
            '${formatFullDate(appointment.start)}, '
            '${formatTimeRange(appointment.start, service.durationMinutes)}',
        address: location,
        price: ServicePriceDisplay.format(service),
        status: l10n.bookingStatusConfirmed,
      );

      await addBookingToCalendar(
        context: context,
        title: l10n.bookingCalendarEventTitle(service.name, provider),
        location: location,
        start: appointment.start,
        end: end,
        description: description,
      );
    } finally {
      _calendarInFlight = false;
    }
  }
}
