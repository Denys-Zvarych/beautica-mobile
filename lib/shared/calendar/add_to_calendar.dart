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

/// Which provider label prefixes the «Виконавець» line in the calendar-note
/// block — a salon booking names the SALON, an independent-master booking
/// names the MASTER, and a source that cannot tell them apart falls back to
/// the neutral «Виконавець».
enum CalendarProviderRole { master, salon, provider }

/// Builds the OS calendar event's **description/notes** block from a booking's
/// STRUCTURED FACTS only — service, provider, date/time, address, price,
/// status. Each supplied, non-empty field becomes one `Label: value` line;
/// null/blank fields are skipped (no dangling labels). Returns `null` when
/// nothing was supplied, so the caller leaves `Event.description` unset.
///
/// PRIVACY BOUNDARY (user-confirmed): this builder deliberately accepts NO
/// free-text notes — not `clientComment`, not `providerComment`, not
/// `clientCancellationNote`. Those sync to the calendar provider's cloud, so
/// they are kept off the calendar by construction: there is no parameter that
/// can carry them here. Do NOT add one.
String? buildCalendarDescription({
  required AppLocalizations l10n,
  String? service,
  String? provider,
  CalendarProviderRole providerRole = CalendarProviderRole.provider,
  String? dateTime,
  String? address,
  String? price,
  String? status,
}) {
  final List<String> lines = <String>[];

  void add(String label, String? value) {
    final String? trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    lines.add('$label $trimmed');
  }

  add(l10n.bookingCalendarNoteService, service);
  if (provider != null && provider.trim().isNotEmpty) {
    final String providerLabel = switch (providerRole) {
      CalendarProviderRole.master => l10n.bookingCalendarNoteMaster,
      CalendarProviderRole.salon => l10n.bookingCalendarNoteSalon,
      CalendarProviderRole.provider => l10n.bookingCalendarNoteProvider,
    };
    add(providerLabel, provider);
  }
  add(l10n.bookingCalendarNoteDateTime, dateTime);
  add(l10n.bookingCalendarNoteAddress, address);
  add(l10n.bookingCalendarNotePrice, price);
  add(l10n.bookingCalendarNoteStatus, status);

  return lines.isEmpty ? null : lines.join('\n');
}

/// Opens the native calendar's "new event" sheet pre-filled with [title],
/// [location], [start], [end] and an optional structured-facts [description].
///
/// [start]/[end] are the booking's canonical-UTC instants — pass them straight
/// through (the OS renders them in Europe/Kyiv, see the file header).
/// [description] is a pre-built notes block from [buildCalendarDescription] —
/// each call site owns which structured facts it has to contribute, and it
/// carries STRUCTURED FACTS ONLY (never free-text notes/comments — see that
/// builder's privacy note). Shows a localized SnackBar when no calendar app is
/// available or the platform call throws — the ONLY user-feedback path this
/// action has.
Future<void> addBookingToCalendar({
  required BuildContext context,
  required String title,
  required DateTime start,
  required DateTime end,
  String? location,
  String? description,
}) async {
  // Resolve the messenger + copy BEFORE the first await so nothing reads
  // `context` across the async gap except the `mounted` guard below.
  final AppLocalizations l10n = AppLocalizations.of(context);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

  final Event event = Event(
    title: title,
    description: description,
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
