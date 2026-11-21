// 2026-11-21 (user) — report / block left «Деталі запису»: the provider
// reaches them through the client strip → client card → «⋯». The ONE helper
// the UGC flows share for that route (fixture + taps), so they never drift.

import 'package:beautica_mobile/features/booking/presentation/widgets/booking_client_strip.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

/// The client card's «⋯».
final Finder clientCardMore = find.byKey(ClientCardScreen.moreKey);

/// Seeds the card of `booking-1`'s client (registered: its newest visit IS
/// `booking-1`, the card's anchor; guest: keyed by `booking-1` itself) and
/// wires the card routes. Call BEFORE boot, after the booking fields are set.
void seedClientCardForBooking1(FakeBackend fb) {
  final bool guest = fb.bookingClientIsGuest;
  // `wireClientCard` serves `…/users/{id}` only for a `u-` id (anything else
  // is routed as a guest), so the registered client gets a `u-` id here.
  if (!guest && !fb.bookingRegisteredClientId.startsWith('u-')) {
    fb.bookingRegisteredClientId = 'u-${fb.bookingRegisteredClientId}';
  }
  final String id = guest ? 'booking-1' : fb.bookingRegisteredClientId;
  fb.clientCards[id] = <String, dynamic>{
    'kind': guest ? 'GUEST' : 'REGISTERED',
    if (guest) 'guestBookingId': id else 'userId': id,
    'displayName': '${fb.clientFirstName} ${fb.clientLastName}',
    'blocked': fb.bookingClientBlockId != null,
    'ratingCount': 0,
    'ratingDistribution': <Map<String, int>>[],
  };
  fb.clientVisits[id] = <Map<String, dynamic>>[
    <String, dynamic>{
      'visitKey': 'v-booking-1',
      'startsAt': fb.bookingStartsAt,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'bookingId': 'booking-1',
          'serviceName': 'Манікюр',
          'status': 'CONFIRMED',
          'startsAt': fb.bookingStartsAt,
          'priceAtBooking': 650,
        },
      ],
    },
  ];
  fb.wireClientCard(
    salonIds: <String>{'salon-owner-1', ?fb.bookingSalonId}.toList(),
  );
}

/// «Деталі запису»'s client strip carries NO «⋯» any more (every role).
void expectNoStripMore() => expect(
  find.descendant(
    of: find.byKey(BookingClientStrip.defaultShellKey),
    matching: find.byIcon(Icons.more_horiz_rounded),
  ),
  findsNothing,
);

/// From «Деталі запису» (or an already open card): opens the client card
/// through the strip, then taps its «⋯». The caller settles / asserts.
Future<void> openClientCardMore(WidgetTester tester) async {
  if (find.byType(ClientCardScreen).evaluate().isEmpty) {
    expectNoStripMore();
    await AppHarness.tapVisible(
      tester,
      find.byKey(BookingClientStrip.defaultShellKey),
    );
    await AppHarness.pumpUntilFound(tester, find.byType(ClientCardScreen));
  }
  await AppHarness.pumpUntilFound(tester, clientCardMore);
  await AppHarness.tapVisible(tester, clientCardMore);
}

/// From «Деталі запису»: opens the client card through the strip (no «⋯»
/// tap) — for the cases that assert the card offers NO «⋯».
Future<void> openClientCard(WidgetTester tester) async {
  expectNoStripMore();
  await AppHarness.tapVisible(
    tester,
    find.byKey(BookingClientStrip.defaultShellKey),
  );
  await AppHarness.pumpUntilFound(tester, find.byKey(ClientCardScreen.nameKey));
  await AppHarness.settle(tester);
}
