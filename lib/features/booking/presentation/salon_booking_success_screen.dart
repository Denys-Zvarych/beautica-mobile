// Phase 14.18 — SalonBookingSuccessScreen: salon booking flow step 4b, the
// post-submit celebration. Mirrors the independent-master
// `BookingSuccessScreen` (`booking_success_screen.dart`) — animated success
// badge → "Записано!" headline → reassuring subline → the booking recap →
// a single pinned "На головну" — extended to LIST every created appointment
// via the SAME generalized `BookingSummaryCards` the independent success
// screen uses (`BookingSummaryCards.fromSchedule` — see that widget's file
// header), one per master, plus a shared salon-address card.
//
// The shared celebration structure lives in
// `widgets/booking_success_scaffold.dart` (composed by both success screens);
// this screen just supplies its copy and its recap cards.
//
// PAGER REWORK (owner decision, 2026-08-23): the flat stack of N
// per-appointment recap cards is now an [AppointmentPager]
// (`widgets/appointment_pager.dart`) — one master's card on screen at a
// time, via [BookingSuccessScaffold.pagedRecap] (an additive scaffold slot
// added for this screen; the independent success screen and «Деталі
// запису» both leave it null and render byte-identically to before). The
// visit-wide grand total («Разом за візит») is REMOVED — each master's own
// «Разом» subtotal is the only total on this screen now. The shared
// salon-address card stays OUTSIDE the pager, in [BookingSuccessScaffold
// .recapCards] (non-paged, same staggered reveal as before) — it is
// identical for every appointment (all N masters work at the SAME salon).
//
// «Додати в календар» (owner-reported fix, superseding the 2026-08-23
// decision above): ONE [CalendarButton] per MASTER, covering that master's
// WHOLE visit (every assigned service, back-to-back, one contiguous
// arrival) — mirroring the independent-master success screen's
// `_onAddToCalendar` (`booking_success_screen.dart`), which is the
// authority this screen now copies. The earlier "ONE per BOOKING" design
// (1 service = 1 booking = 1 button) was wrong: a master's services in one
// appointment run back-to-back as a SINGLE arrival, so they belong in ONE
// OS calendar event, not N overlapping ones. `BookingSummaryCards
// .fromSchedule` now carries the SAME `trailingAction` passthrough
// [BookingSummaryCards.fromMaster] already had — REUSE-FIRST forbids the
// bespoke `_SalonCalendarActionsCard`/`_CalendarActionRow` pair that used to
// live here (deleted) once the shared slot could carry the button instead.
//
// Reached ONLY via `SalonBookingConfirmScreen`'s `pushReplacement` once EVERY
// appointment's `POST /bookings` succeeded (partial failures keep the client
// on the confirm screen), so the recap here is always the full, confirmed
// set. The scaffold's `PopScope(canPop: false)` blocks back like the
// independent success screen — the pinned "На головну" is the only way
// forward.
//
// The salon's ADDRESS is a secondary read via
// `publicSalonProfileProvider(salonId)` — see `salon_booking_confirm_screen
// .dart`'s file header DATA SOURCE note for the full rationale (5-minute
// keepAlive cache, never blocks/errors this screen).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart'
    show ServicePriceType;
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/calendar/add_to_calendar.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';
import 'package:beautica_mobile/shared/formatters/street_city_line.dart';

import '../domain/salon_booking_confirm_args.dart';
import '../domain/salon_master_schedule.dart';
import 'widgets/appointment_pager.dart';
import 'widgets/booking_success_scaffold.dart';
import 'widgets/booking_summary_cards.dart';
import 'widgets/calendar_button.dart';
import 'widgets/labelled_row.dart';
import 'widgets/salon_avatar_gradients.dart';
import 'widgets/section_rule.dart';

/// Salon booking flow step 4b — the confirmed N-appointment recap.
///
/// `ConsumerStatefulWidget` (rather than the original `ConsumerWidget`) so it
/// can acquire the app-wide [ScreenProtectionManager] for its lifetime — see
/// [_SalonBookingSuccessScreenState.initState]. This mirrors the ONLY
/// acquire-idiom this codebase has for that manager (every other PII screen —
/// `PublicSalonProfileScreen`, `SalonBookingConfirmScreen`, etc. — is also a
/// `ConsumerStatefulWidget` acquiring in `initState`/releasing in `dispose`).
class SalonBookingSuccessScreen extends ConsumerStatefulWidget {
  const SalonBookingSuccessScreen({super.key, required this.args});

  final SalonBookingSuccessArgs args;

  @override
  ConsumerState<SalonBookingSuccessScreen> createState() =>
      _SalonBookingSuccessScreenState();
}

class _SalonBookingSuccessScreenState
    extends ConsumerState<SalonBookingSuccessScreen> {
  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x
  // throws on a post-dispose `ref` read).
  late final ScreenProtectionManager _screenProtection;

  /// Re-entry guard for the OS calendar INSERT intent — same rationale as
  /// `booking_success_screen.dart`'s `_calendarInFlight` (on Android,
  /// `Add2Calendar.addEvent2Cal` resolves as soon as `startActivity`
  /// returns, not when the sheet is dismissed, so a same-gesture double-tap
  /// could stack two platform activities). Keyed per APPOINTMENT
  /// (`appointmentIndex`, one entry per master — FIX 3 collapsed this
  /// screen to one `CalendarButton` per master) rather than a single bool,
  /// since this screen can show several masters' buttons at once (paged, but
  /// still separately keyed defensively) — a tap on one master's button must
  /// never block a DIFFERENT master's button.
  final Set<String> _calendarInFlight = <String>{};

  @override
  void initState() {
    super.initState();
    // SEC: this screen renders the salon's address (PII: street/buildingNo/
    // city + free-text locationNote) — guard against screenshots /
    // app-switcher snapshots while it is mounted. Mirrors the INTENTIONAL
    // PRODUCT DECISION on `PublicSalonProfileScreen` — do not remove in a
    // future audit pass.
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    super.dispose();
  }

  /// Opens the OS calendar's "new event" sheet for ONE master's WHOLE
  /// appointment — every assigned service, back-to-back, from
  /// `appointment.startAt` to `appointment.startAt + summed duration`
  /// ([SalonBookingAppointment.durationMinutes], i.e.
  /// `schedule.summedDurationMinutes`) — mirroring
  /// `booking_success_screen.dart`'s `_onAddToCalendar` (the independent
  /// flow's authority for this rework, see the file header). Never one
  /// event per service: the services in one appointment are a single
  /// contiguous arrival.
  Future<void> _addToCalendar({
    required BuildContext context,
    required String guardKey,
    required SalonBookingAppointment appointment,
    required String? salonAddressLine,
    required String? salonNameResolved,
  }) async {
    if (_calendarInFlight.contains(guardKey)) return;
    _calendarInFlight.add(guardKey);
    try {
      final l10n = AppLocalizations.of(context);
      final SalonMasterSchedule schedule = appointment.schedule;
      final DateTime start = appointment.startAt;
      final DateTime end = start.add(
        Duration(minutes: appointment.durationMinutes),
      );
      final String masterName = '${schedule.firstName} ${schedule.lastName}'
          .trim();
      // A salon booking names the SALON; falls back to the master when the
      // secondary salon-profile read hasn't resolved yet — mirrors
      // `booking_detail_screen.dart`'s `_onAddToCalendar` precedent
      // (`provider = booking.salonName ?? booking.masterName`).
      final String provider = salonNameResolved ?? masterName;
      final String serviceLabel = schedule.services
          .map((SalonCatalogService s) => s.name)
          .join(', ');
      // Typed price/duration fields, never a re-parsed display string — same
      // `formatBookingTotalsFromTerms` term-mapping as `_AssignConfirmBar
      // ._totals` (`salon_master_selection_screen.dart`), the established
      // precedent for summing this exact [SalonCatalogService] shape.
      final String priceLabel = formatBookingTotalsFromTerms(
        schedule.services.map((SalonCatalogService s) {
          final double lo = s.priceMin ?? 0;
          return (
            min: lo,
            max: s.priceType == ServicePriceType.range
                ? (s.priceMax ?? lo)
                : lo,
            minutes: s.durationMinutes ?? 0,
          );
        }),
      ).priceLabel;

      // Structured facts only — NO free-text note fields reach the calendar
      // (see `buildCalendarDescription`'s own privacy boundary doc). A salon
      // appointment is auto-approved CONFIRMED at submit time (domain rules).
      final String? description = buildCalendarDescription(
        l10n: l10n,
        service: serviceLabel,
        provider: provider,
        providerRole: CalendarProviderRole.salon,
        dateTime:
            '${formatFullDate(start)}, '
            '${formatTimeRange(start, appointment.durationMinutes)}',
        address: salonAddressLine,
        price: priceLabel,
        status: l10n.bookingStatusConfirmed,
      );

      await addBookingToCalendar(
        context: context,
        title: l10n.bookingCalendarEventTitle(serviceLabel, provider),
        location: salonAddressLine,
        start: start,
        end: end,
        description: description,
      );
    } finally {
      _calendarInFlight.remove(guardKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final List<SalonBookingAppointment> appointments = widget.args.appointments;

    // Secondary read — never blocks or errors the whole screen. Scoped via
    // `select` to just the resolved salon so a still-loading/resolving family
    // instance rebuilds only this read, not the whole celebration screen —
    // mobile-perf MEDIUM, Phase 14.18 audit. See
    // `salon_booking_confirm_screen.dart`'s file header DATA SOURCE note.
    final Salon? salon = ref.watch(
      publicSalonProfileProvider(
        widget.args.salonId,
      ).select((AsyncValue<PublicSalonProfileData> v) => v.value?.$1),
    );
    final String? addressLine = salon == null
        ? null
        : formatStreetCityLine(
            street: salon.street,
            buildingNo: salon.buildingNo,
            city: salon.city,
          );
    final String? addressDetail =
        (salon?.locationNote?.trim().isNotEmpty ?? false)
        ? salon!.locationNote!.trim()
        : null;
    // Confirms WHERE the booking was made — same secondary
    // `publicSalonProfileProvider` salon the address block reads (no extra
    // fetch). Null while loading/failed → the card renders address alone.
    final String? salonName = (salon?.name.trim().isNotEmpty ?? false)
        ? salon!.name.trim()
        : null;

    return BookingSuccessScaffold(
      title: l10n.salonBookingSuccessTitle,
      subline: l10n.salonBookingSuccessSubline,
      actions: <Widget>[
        SuccessSecondaryButton(
          buttonKey: const Key('salon-success-home-cta'),
          label: l10n.bookingSuccessHomeCta,
          icon: Icons.home_outlined,
          onPressed: () => context.go(RouteNames.clientHome),
        ),
      ],
      homeGap: VelvetSpacing.sm,
      // Non-paged — identical for every appointment (all N masters work at
      // the SAME salon), shown ONCE above the pager.
      recapCards: <Widget>[
        NeumorphicCard(
          key: const Key('salon-success-address-card'),
          showBorder: true,
          padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // «Салон» identity line above the address — confirms which salon
              // this booking was made with. Dense/compact rhythm matches the
              // rest of the success recap; same composition as the confirm
              // screen and «Деталі запису».
              if (salonName != null) ...<Widget>[
                LabelledRow(
                  key: const Key('salon-success-salon-name'),
                  label: l10n.bookingSalonLabel,
                  value: salonName,
                  compactText: true,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SectionRule(dense: true),
              ],
              LabelledRow(
                label: l10n.bookingAddressLabel,
                value: addressLine ?? l10n.bookingAddressUnknown,
                detail: addressDetail,
                compactText: true,
              ),
            ],
          ),
        ),
      ],
      // PAGED — one master's confirmed recap, with its OWN «Додати в
      // календар» button mounted INSIDE the shared card via
      // `BookingSummaryCards.fromSchedule`'s `trailingAction` (FIX 3 — see
      // the file header). No visit-wide total: each card's own «Разом»
      // (inside `BookingSummaryCards.fromSchedule`, via `BookingRecap`) is
      // the only total shown.
      pagedRecap: AppointmentPager(
        // Test-support key — mirrors the confirm screen's identical key
        // (`salon_booking_confirm_screen.dart`), enabling
        // `pager_drag.dart`'s hand-driven swipe recipe here too.
        key: const Key('appointment-pager'),
        count: appointments.length,
        pageBuilder: (BuildContext context, int i) {
          final SalonBookingAppointment appointment = appointments[i];
          return BookingSummaryCards.fromSchedule(
            key: ValueKey<String>(
              'salon-success-appt-${appointment.schedule.masterId}',
            ),
            schedule: appointment.schedule,
            start: appointment.startAt,
            avatarGradient: salonAvatarGradient(i),
            dense: true,
            showBorder: true,
            compactText: true,
            // ONE button for this master's WHOLE visit (every assigned
            // service, back-to-back) — see `_addToCalendar`'s doc. Keyed per
            // appointment index, mirroring `_calendarInFlight`'s guard key.
            trailingAction: CalendarButton(
              buttonKey: Key('salon-success-add-calendar-$i'),
              semanticsLabel: l10n.bookingAddCalendarSemantics,
              onTap: () => _addToCalendar(
                context: context,
                guardKey: 'salon-success-add-calendar-$i',
                appointment: appointment,
                salonAddressLine: addressLine,
                salonNameResolved: salonName,
              ),
            ),
          );
        },
      ),
    );
  }
}
