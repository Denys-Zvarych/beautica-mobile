// Shared "add to calendar" action — opens the OS/native calendar's
// "new event" sheet pre-filled from a booking.
//
// One cross-platform code path behind every «Додати в календар» affordance
// (My Bookings detail, booking success, home-hub next-appointment card). On
// Android it fires the platform default-calendar INSERT intent (which lets the
// user pick whichever calendar app they use — Google, Samsung, etc.); on iOS it
// hands the event to EventKit. So the "Google" vs "Apple" variants on the home
// hub both route here — the OS, not the app, owns the destination.
//
// Fire-and-forget: no provider state, no return value (per the backlog note —
// this is a one-shot action, not a stateful flow).
//
// TIMEZONE: booking instants are canonical UTC on the wire and in the model.
// add_2_calendar transmits the ABSOLUTE instant (millisecondsSinceEpoch) and
// the OS calendar renders it in the event's `timeZone`. We pin
// [kBeauticaTimeZoneName] (Europe/Kyiv) — the exact same salon-market anchor
// `shared/time/time_zones.dart` uses for on-screen display — so the calendar
// entry reads at the SAME wall-clock the booking screens show, on ANY device
// timezone. This delegates to the app's single timezone convention rather than
// introducing a divergent conversion.

import 'dart:developer';

import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/material.dart';

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';

/// Opens the native calendar's "new event" sheet pre-filled with [title],
/// [location], [start] and [end].
///
/// [start]/[end] are the booking's canonical-UTC instants — pass them straight
/// through (the OS renders them in Europe/Kyiv, see the file header). Shows a
/// localized SnackBar when no calendar app is available or the platform call
/// throws — the ONLY user-feedback path this action has.
Future<void> addBookingToCalendar({
  required BuildContext context,
  required String title,
  required DateTime start,
  required DateTime end,
  String? location,
}) async {
  // Resolve the messenger + copy BEFORE the first await so nothing reads
  // `context` across the async gap except the `mounted` guard below.
  final AppLocalizations l10n = AppLocalizations.of(context);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

  final Event event = Event(
    title: title,
    location: location,
    startDate: start,
    endDate: end,
    timeZone: kBeauticaTimeZoneName,
  );

  bool added = false;
  try {
    added = await Add2Calendar.addEvent2Cal(event);
  } catch (error, stackTrace) {
    // ActivityNotFoundException (no calendar app) surfaces as a
    // PlatformException here; any other native failure lands here too.
    log(
      'add-to-calendar failed',
      name: 'shared.calendar',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }

  // Success — the OS sheet is now on screen; nothing more to do.
  if (added) return;
  if (!context.mounted) return;

  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(l10n.bookingAddToCalendarError)));
}
