// BookingSuccessScreen: the independent-master booking flow's post-submit
// celebration, shown after the single `POST /appointments` succeeds.
//
// MO-3 (single-visit rework): the flow now books the whole selection as ONE
// visit with ONE start time (services run back-to-back), so the recap is a
// SINGLE card — the shared master identity + address, the ordered service list
// under ONE visit window (`startAt` → `startAt + summed duration`), and the
// «Разом» total — with ONE «Додати в календар» pill that exports the whole
// arrival as a single OS calendar event (not one card/event per service, which
// the pre-MO-3 N-appointment recap needed).
//
// Reached ONLY via `BookingConfirmScreen`'s `pushReplacement` once the visit was
// created (a failed submit keeps the client on the confirm screen). The
// scaffold's `PopScope(canPop: false)` blocks back — the pinned «На головну» is
// the only way forward.
//
// SEC: the recap renders the INDEPENDENT master's address (street/buildingNo/
// city/locationNote — a solo master's may be a HOME address), so this screen
// acquires the app-wide screenshot guard in `initState`. Do not remove in a
// future audit pass.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/calendar/add_to_calendar.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';
import 'package:beautica_mobile/shared/formatters/street_city_line.dart';

import '../domain/booking_success_args.dart';
import 'widgets/booking_recap.dart';
import 'widgets/booking_success_scaffold.dart';
import 'widgets/booking_summary_cards.dart';
import 'widgets/calendar_button.dart';

/// Booking flow — the post-submit celebration screen (one confirmed visit).
class BookingSuccessScreen extends ConsumerStatefulWidget {
  const BookingSuccessScreen({super.key, required this.args});

  final BookingSuccessArgs args;

  @override
  ConsumerState<BookingSuccessScreen> createState() =>
      _BookingSuccessScreenState();
}

class _BookingSuccessScreenState extends ConsumerState<BookingSuccessScreen> {
  late final ScreenProtectionManager _screenProtection;

  /// Re-entry guard for the OS calendar INSERT intent. On Android
  /// `Add2Calendar.addEvent2Cal` resolves as soon as `startActivity` returns
  /// (not when the sheet is dismissed), so a same-gesture double-tap could fire
  /// two INSERT intents; this drops the second until the first resolves.
  /// Deliberately NOT `setState`-driven — nothing on screen is painted from it.
  bool _calendarInFlight = false;

  // `widget.args` never changes for this screen's lifetime, so the visit's
  // selections + summed duration are computed once.
  late final List<BookingSelection> _selections = widget.args.services
      .map(
        (MasterService s) => BookingSelection(
          name: s.name,
          price: ServicePriceDisplay.format(s),
          duration: DurationMinutes.format(s.durationMinutes),
          durationMinutes: s.durationMinutes,
          priceMin: s.priceMin,
          priceMax: s.priceMax,
        ),
      )
      .toList();

  late final int _totalDurationMinutes = widget.args.services.fold<int>(
    0,
    (int sum, MasterService s) => sum + s.durationMinutes,
  );

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
    final master = widget.args.master;
    final DateTime startAt = widget.args.startAt;

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
        // ONE visit recap: the shared address, the single window, the ordered
        // service list + «Разом» total, with the whole-visit calendar export as
        // the card's trailing action. No master card — the celebration badge +
        // title already establish "you're booked", matching the pre-MO-3
        // success recap (which likewise omitted the identity card).
        BookingSummaryCards(
          key: const Key('booking-success-visit-card'),
          showBorder: true,
          compactText: true,
          dense: true,
          addressLine: addressLine,
          addressDetail: addressDetail,
          dateLabel: formatFullDate(startAt),
          timeLabel: formatTimeRange(startAt, _totalDurationMinutes),
          selections: _selections,
          trailingAction: CalendarButton(
            buttonKey: const Key('booking-success-add-calendar'),
            semanticsLabel: l10n.bookingAddCalendarSemantics,
            onTap: () => _onAddToCalendar(context),
          ),
        ),
      ],
    );
  }

  /// Opens the OS calendar's "new event" sheet for the WHOLE visit — one event
  /// spanning `startAt` → `startAt + summed duration`, since the services are a
  /// single back-to-back arrival. Guarded by [_calendarInFlight] against a
  /// double-tap stacking two platform activities.
  Future<void> _onAddToCalendar(BuildContext context) async {
    if (_calendarInFlight) return;
    _calendarInFlight = true;
    try {
      final l10n = AppLocalizations.of(context);
      final master = widget.args.master;
      final DateTime startAt = widget.args.startAt;
      final DateTime end = startAt.add(
        Duration(minutes: _totalDurationMinutes),
      );

      final String? location = formatStreetCityLine(
        street: master.street,
        buildingNo: master.buildingNo,
        city: master.city,
      );
      final String provider = '${master.firstName} ${master.lastName}'.trim();
      final String serviceLabel = widget.args.services
          .map((MasterService s) => s.name)
          .join(', ');
      final String priceLabel = formatBookingTotalsFromTerms(
        widget.args.services.map(
          (MasterService s) => (
            min: s.priceMin,
            max: s.priceType == ServicePriceType.range
                ? (s.priceMax ?? s.priceMin)
                : s.priceMin,
            minutes: s.durationMinutes,
          ),
        ),
      ).priceLabel;

      // Structured facts only — NO free-text note fields reach the calendar. A
      // just-submitted visit is auto-approved CONFIRMED (see domain rules).
      final String? description = buildCalendarDescription(
        l10n: l10n,
        service: serviceLabel,
        provider: provider,
        providerRole: CalendarProviderRole.master,
        dateTime:
            '${formatFullDate(startAt)}, '
            '${formatTimeRange(startAt, _totalDurationMinutes)}',
        address: location,
        price: priceLabel,
        status: l10n.bookingStatusConfirmed,
      );

      await addBookingToCalendar(
        context: context,
        title: l10n.bookingCalendarEventTitle(serviceLabel, provider),
        location: location,
        start: startAt,
        end: end,
        description: description,
      );
    } finally {
      _calendarInFlight = false;
    }
  }
}
