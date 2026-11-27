// Shared seeds, finders and helpers for the «Клієнти» tab E2E flows
// (`clients_tab_flow_test.dart` — tab / list; `clients_card_flow_test.dart` —
// card states + cross-screen freshness). Split out of the single
// clients_tab flow file (>180 s) with no assertion changes.

import 'package:beautica_mobile/features/clients/application/client_list_controller.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/clients_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_list_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'app_harness.dart';

/// The owner's default landing salon (`FakeBackend.mySalons`).
const String kClientsSalonId = 'salon-owner-1';

/// Owner master mode: the owner's own `masters` ROW id (≠ the session user
/// id, so a request built off the wrong id cannot match).
const String kClientsOwnerMasterRowId = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';

const String kClientsMasterPath = '/api/v1/masters/me/clients';

/// CLI-73 — the two salon masters who served `u-oksana` (A: the upcoming
/// visit, B: the past one).
const String kClientsMasterA = 'b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
const String kClientsMasterB = 'c2eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
const String kClientsSalonPath = '/api/v1/salons/$kClientsSalonId/clients';

/// 25 rows → page 0 holds 20, page 1 holds 5. Row 0 is the rated registered
/// client, row 1 a guest, the rest unrated registered clients.
void seedClientsRoster(FakeBackend fb) {
  fb.clientRows
    ..clear()
    ..add(<String, dynamic>{
      'kind': 'REGISTERED',
      'userId': 'u-oksana',
      'displayName': 'Оксана Мельник',
      'lastVisitAt': '2026-06-07T10:00:00Z',
      'nextVisitAt': '2026-06-20T12:00:00Z',
      'completedVisits': 9,
      'ratingAvg': 4.9,
      'ratingCount': 12,
      'blocked': false,
    })
    ..add(<String, dynamic>{
      'kind': 'GUEST',
      'guestBookingId': 'b-iryna',
      'displayName': 'Ірина Коваль',
      'lastVisitAt': '2026-06-01T10:00:00Z',
      'completedVisits': 2,
      'ratingCount': 0,
      'blocked': false,
    });
  for (int i = 2; i < 25; i++) {
    fb.clientRows.add(<String, dynamic>{
      'kind': 'REGISTERED',
      'userId': 'u-$i',
      'displayName': 'Клієнтка Номер$i',
      'lastVisitAt':
          '2026-05-${((i % 27) + 1).toString().padLeft(2, '0')}T10:00:00Z',
      'completedVisits': 1,
      'ratingCount': 0,
      'blocked': false,
    });
  }
}

/// The rated client's upcoming visit — on the app's pinned clock ([kFixedNow]
/// = 2026-06-14), never the host clock (M15: one clock per test).
const String kClientsNextVisitAt = '2026-06-20T12:00:00Z';

/// M510 — the card data behind the two rows the flows open: the rated
/// registered client (phone, 12 ratings, an upcoming visit, one own rating)
/// and the guest (phone, no ratings, one past visit). [more] adds entries
/// before the routes are wired.
/// The registered card's photo (allow-listed in test (a) only).
const String kClientsOksanaPhoto = 'https://media.test/avatars/u-oksana.jpg';

void seedClientCards(
  FakeBackend fb, {
  void Function()? more,
  List<String> salonIds = const <String>[kClientsSalonId],
}) {
  fb.clientCards
    ..clear()
    ..['u-oksana'] = <String, dynamic>{
      'kind': 'REGISTERED',
      'userId': 'u-oksana',
      'displayName': 'Оксана Мельник',
      'phone': '+380671234567',
      'blocked': false,
      'ratingAvg': 4.9,
      'ratingCount': 12,
      'ratingDistribution': <Map<String, int>>[
        <String, int>{'rating': 5, 'count': 10},
        <String, int>{'rating': 4, 'count': 2},
        <String, int>{'rating': 3, 'count': 0},
        <String, int>{'rating': 2, 'count': 0},
        <String, int>{'rating': 1, 'count': 0},
      ],
      'nextVisitAt': kClientsNextVisitAt,
      // CLI-73 — salon-wide, most recent first. Realistic: the owner's own
      // master row is part of the salon-wide list too.
      'servedByMasters': <Map<String, dynamic>>[
        <String, dynamic>{'masterId': kClientsMasterA, 'name': 'Олена Шевчук'},
        <String, dynamic>{'masterId': kClientsMasterB, 'name': 'Марта Бондар'},
        <String, dynamic>{
          'masterId': kClientsOwnerMasterRowId,
          'name': 'Власниця Салону',
        },
      ],
    }
    ..['b-iryna'] = <String, dynamic>{
      'kind': 'GUEST',
      'guestBookingId': 'b-iryna',
      'displayName': 'Ірина Коваль',
      'phone': '+380501112233',
      'blocked': false,
      'ratingCount': 0,
      'ratingDistribution': <Map<String, int>>[],
    };
  Map<String, dynamic> visit(
    String key,
    String at,
    String status, {
    String? masterId,
  }) => <String, dynamic>{
    'visitKey': key,
    'startsAt': at,
    'items': <Map<String, dynamic>>[
      <String, dynamic>{
        'bookingId': 'bk-$key',
        'serviceName': 'Манікюр',
        'status': status,
        'startsAt': at,
        'priceAtBooking': 650,
        'masterId': ?masterId,
      },
    ],
  };
  fb.clientVisits
    ..clear()
    ..['u-oksana'] = <Map<String, dynamic>>[
      visit(
        'v-next',
        kClientsNextVisitAt,
        'CONFIRMED',
        masterId: kClientsMasterA,
      ),
      visit(
        'v-past',
        '2026-06-07T10:00:00Z',
        'COMPLETED',
        masterId: kClientsMasterB,
      ),
    ]
    ..['b-iryna'] = <Map<String, dynamic>>[
      visit('v-g1', '2026-06-01T10:00:00Z', 'COMPLETED'),
    ];
  more?.call();
  fb.wireClientCard(salonIds: salonIds);
}

/// M510 QA — the edge cards: `u-2` is BLOCKED, rated with a
/// 25-visit history (two pages); `u-3` has routes but no card → the uniform
/// 404 (e.g. a client gone since the list loaded).
void seedEdgeClientCards(FakeBackend fb) => seedClientCards(
  fb,
  more: () {
    fb.clientCards['u-2'] = <String, dynamic>{
      'kind': 'REGISTERED',
      'userId': 'u-2',
      'displayName': 'Клієнтка Номер2',
      'phone': '+380931112233',
      'blocked': true,
      'ratingAvg': 4.0,
      'ratingCount': 2,
      'ratingDistribution': <Map<String, int>>[
        <String, int>{'rating': 4, 'count': 2},
      ],
    };
    fb.clientVisits['u-2'] = <Map<String, dynamic>>[
      for (int i = 0; i < 25; i++)
        <String, dynamic>{
          'visitKey': 'h$i',
          'startsAt': kFixedNow
              .subtract(Duration(days: 3 + i * 3))
              .toIso8601String(),
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              // `booking-1` is the fake's seeded booking-detail id.
              'bookingId': i == 0 ? 'booking-1' : 'bk-h$i',
              'serviceName': 'Педикюр',
              'status': 'COMPLETED',
              'startsAt': kFixedNow
                  .subtract(Duration(days: 3 + i * 3))
                  .toIso8601String(),
              'priceAtBooking': 700,
            },
          ],
        },
    ];
    fb.clientVisits['u-3'] = <Map<String, dynamic>>[];
  },
);

/// The card's own scroll view (the shell behind it has others).
Finder clientCardScroll() => find
    .descendant(
      of: find.byKey(ClientCardScreen.screenKey),
      matching: find.byType(CustomScrollView),
    )
    .first;

bool clientVisitsPageCalled(FakeBackend fb, int page) => fb.clientCardCalls.any(
  (String c) => c.startsWith('visits ') && c.contains(' page=$page '),
);

/// (h) — captures the card / detail `tel:` launches.
class MockClientsUrlLauncher extends Mock
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {}

Finder clientRow(String id) => find.byKey(Key('client-row-$id'));

/// Waits for the list, then drains the tab transition — mid-fade BOTH tabs'
/// bars are mounted, which makes single-bar finders ambiguous.
Future<void> waitForClientList(WidgetTester tester) async {
  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(ClientsScreen.listKey),
    timeout: const Duration(seconds: 20),
  );
  await AppHarness.settle(tester);
}

/// Types [text] into the search field and drives the debounce `Timer`.
Future<void> searchClients(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(ClientsScreen.searchKey), text);
  await tester.pump();
  await tester.pump(kClientSearchDebounce);
  await tester.pump();
}

/// Client-profile audit — a registered client [userId] whose ONLY visit is the
/// fake's seeded `booking-1` (CONFIRMED at [at], after [kFixedNow]): the list
/// row («Наст.»), the card and its timeline («Наступний візит») all carry it.
/// Inserted as the list's first row so it is on screen without scrolling.
void seedOneVisitClient(FakeBackend fb, String userId, DateTime at) {
  final String iso = at.toUtc().toIso8601String();
  fb
    ..bookingRegisteredClientId = userId
    ..bookingStartsAt = iso
    ..bookingEndsAt = at
        .add(const Duration(hours: 1))
        .toUtc()
        .toIso8601String();
  seedClientsRoster(fb);
  fb.clientRows.insert(0, <String, dynamic>{
    'kind': 'REGISTERED',
    'userId': userId,
    'displayName': 'Клієнтка Аудит',
    'lastVisitAt': '2026-06-01T10:00:00Z',
    'nextVisitAt': iso,
    'completedVisits': 1,
    'ratingCount': 0,
    'blocked': false,
  });
  seedClientCards(
    fb,
    more: () {
      fb.clientCards[userId] = <String, dynamic>{
        'kind': 'REGISTERED',
        'userId': userId,
        'displayName': 'Клієнтка Аудит',
        'blocked': false,
        'ratingCount': 0,
        'ratingDistribution': <Map<String, int>>[],
        'nextVisitAt': iso,
      };
      fb.clientVisits[userId] = <Map<String, dynamic>>[
        <String, dynamic>{
          'visitKey': 'booking-1',
          'startsAt': iso,
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'bookingId': 'booking-1',
              'serviceName': 'Манікюр',
              'status': 'CONFIRMED',
              'startsAt': iso,
              'priceAtBooking': 650,
            },
          ],
        },
      ];
    },
  );
}

/// The list row's own [ClientListRow] meta / chip under the row of [id].
Finder clientRowPart(String id, Key part) =>
    find.descendant(of: clientRow(id), matching: find.byKey(part));

/// Opens the master «Клієнти» tab (INDEPENDENT_MASTER, bar index 3).
Future<void> openMasterClients(WidgetTester tester) async {
  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('master-nav-tile-3')),
  );
  await waitForClientList(tester);
}

/// Routes on the navigator stack (pushes included).
int routerStackDepth(GoRouter router) =>
    router.routerDelegate.currentConfiguration.matches.length;
