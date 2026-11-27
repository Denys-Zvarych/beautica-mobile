// M531 (CLI-89, CLI-78, Step 2.7 Rule 3b) — E2E: the client card's
// «Наступний візит» comes from the card's `nextVisit` (B530), never from
// paging the visit history.
//
// REAL router + REAL `HttpClientRepository` over the stubbed Dio. The fake
// card route derives `nextVisit` like the server (earliest CONFIRMED booking
// after now in the read's scope, `masterId` honoured —
// `FakeBackend.wireClientCard`), so what this tier pins is the app side:
//
//   (a) E2 — the next visit sits on visits page 3 (rows come newest first):
//       the head is that booking after ONE visits request; when page 3 loads
//       on scroll, its history row is filtered out (no duplicate).
//   (b) E1 — no CONFIRMED future booking → `nextVisit` null → no head, the
//       history only (a future PENDING row stays in the history).
//   (c) E4 — a master chip re-reads the card + visits page 0 with `masterId`;
//       the head follows the chip, and «Усі майстри» brings the salon-wide
//       head back.
//
// Request-ORDER is deliberately not asserted (card and page 0 may be fetched
// in parallel); only counts and the `masterId` each read carries.
//
// CLOCK: the harness pins `clockProvider` to `kFixedNow`; every fixture date
// is an offset from that SAME clock (M15), and the fake derives `nextVisit`
// against it too.
// NO PATROL FLOW: no OS dialog, permission, deep link, notification or
// WebView is touched (mobile-qa explicit statement).
//
// Standalone run (one file per invocation):
//   flutter test integration_test/client_card_next_visit_flow_test.dart -d flutter-tester

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

const String _kMasterA = 'b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
const String _kMasterB = 'c2eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';

const String _kFarId = 'u-far';
const String _kNoNextId = 'u-none';

/// Future CONFIRMED rows for [_kFarId]: 65 → pages 0..3 at size 20, the
/// earliest (`bk-f-64`, master A) on page 3; `bk-f-63` is master B's.
const int _kFutureCount = 65;
const String _kHeadAll = 'bk-f-64';
const String _kHeadB = 'bk-f-63';

String _iso(DateTime t) => t.toUtc().toIso8601String();

Map<String, dynamic> _visit(
  String bookingId,
  DateTime at, {
  String status = 'CONFIRMED',
  String? masterId,
}) => <String, dynamic>{
  'visitKey': bookingId,
  'startsAt': _iso(at),
  'items': <Map<String, dynamic>>[
    <String, dynamic>{
      'bookingId': bookingId,
      'serviceName': 'Манікюр',
      'status': status,
      'startsAt': _iso(at),
      'priceAtBooking': 650,
      'masterId': ?masterId,
    },
  ],
};

/// Newest first, like B508: the far-future rows, then three past ones.
List<Map<String, dynamic>> _farVisits() {
  final DateTime base = DateTime.utc(
    kFixedNow.year,
    kFixedNow.month,
    kFixedNow.day,
    10,
  );
  return <Map<String, dynamic>>[
    for (int i = 0; i < _kFutureCount; i++)
      _visit(
        'bk-f-$i',
        base.add(Duration(days: _kFutureCount + 1 - i)),
        masterId: switch (i) {
          64 => _kMasterA,
          63 => _kMasterB,
          _ => null,
        },
      ),
    for (int i = 0; i < 3; i++)
      _visit(
        'bk-p-$i',
        base.subtract(Duration(days: 4 + i)),
        status: 'COMPLETED',
      ),
  ];
}

Map<String, dynamic> _card(String id, String name) => <String, dynamic>{
  'kind': 'REGISTERED',
  'userId': id,
  'displayName': name,
  'phone': '+380501112233',
  'blocked': false,
  'ratingCount': 0,
  'ratingDistribution': <Map<String, int>>[],
  'servedByMasters': <Map<String, dynamic>>[
    <String, dynamic>{'masterId': _kMasterA, 'name': 'Олена Шевчук'},
    <String, dynamic>{'masterId': _kMasterB, 'name': 'Марта Бондар'},
  ],
};

int _calls(FakeBackend fb, String kind, {String masterId = 'null'}) => fb
    .clientCardCalls
    .where(
      (String c) => c.startsWith('$kind ') && c.endsWith('masterId=$masterId'),
    )
    .length;

bool _visitsPageCalled(FakeBackend fb, int page) => fb.clientCardCalls.any(
  (String c) => c.startsWith('visits ') && c.contains(' page=$page '),
);

Finder _cardScroll() => find
    .descendant(
      of: find.byKey(ClientCardScreen.screenKey),
      matching: find.byType(CustomScrollView),
    )
    .first;

/// The head node, found INSIDE the timeline row of [bookingId].
Finder _headOf(String bookingId) => find.descendant(
  of: find.byKey(ValueKey<String>(bookingId)),
  matching: find.byKey(ClientCardScreen.nextVisitKey),
);

Future<FakeBackend> _openCard(WidgetTester tester, String clientId) async {
  final FakeBackend fb = FakeBackend()..currentRole = UserRole.salonOwner;
  fb
    ..clientCards[_kFarId] = _card(_kFarId, 'Далека Клієнтка')
    ..clientVisits[_kFarId] = _farVisits()
    ..clientCards[_kNoNextId] = _card(_kNoNextId, 'Без Візиту')
    ..clientVisits[_kNoNextId] = <Map<String, dynamic>>[
      _visit(
        'bk-n-pending',
        kFixedNow.add(const Duration(days: 3)),
        status: 'PENDING',
      ),
      _visit(
        'bk-n-cancelled',
        kFixedNow.add(const Duration(days: 2)),
        status: 'CANCELLED',
      ),
      _visit(
        'bk-n-past',
        kFixedNow.subtract(const Duration(days: 5)),
        status: 'COMPLETED',
      ),
    ]
    ..wireClientCard();
  final GoRouter router = await AppHarness.boot(tester, fb);
  await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
  await AppHarness.settle(tester);
  unawaited(
    router.push(
      RouteNames.clientCardUser(
        RouteNames.salonClients(FakeBackend.kOwnerSalonId),
        clientId,
      ),
    ),
  );
  await AppHarness.pumpUntilFound(tester, find.byKey(ClientCardScreen.nameKey));
  await AppHarness.settle(tester);
  return fb;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('(a) E2: a next visit on page 3 heads the timeline after ONE '
      'visits request, and its history row is filtered when page 3 loads', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = await _openCard(tester, _kFarId);

      await AppHarness.pumpUntilFound(tester, _headOf(_kHeadAll));
      expect(find.byKey(ClientCardScreen.nextVisitKey), findsOneWidget);
      expect(_calls(fb, 'card'), 1);
      expect(
        _calls(fb, 'visits'),
        1,
        reason: 'no lookahead: the head comes from the card (CLI-89)',
      );
      expect(_visitsPageCalled(fb, 0), isTrue);
      expect(_visitsPageCalled(fb, 1), isFalse);

      // Page through to page 3, where the head's own row lives.
      for (int page = 1; page <= 3; page++) {
        await tester.drag(_cardScroll(), const Offset(0, -6000));
        await AppHarness.pumpUntilCondition(
          tester,
          () => _visitsPageCalled(fb, page),
          description: 'visits page $page requested on scroll',
        );
        await AppHarness.settle(tester);
      }
      // The head's neighbours on page 3 are built; the head's own booking is
      // not repeated in the history.
      await tester.drag(_cardScroll(), const Offset(0, 60000));
      await AppHarness.settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(ClientCardScreen.visitKey('bk-f-62')),
        300,
        scrollable: find
            .descendant(of: _cardScroll(), matching: find.byType(Scrollable))
            .first,
        maxScrolls: 200,
      );
      await AppHarness.settle(tester);
      expect(find.byKey(ClientCardScreen.visitKey('bk-f-62')), findsOneWidget);
      expect(find.byKey(ClientCardScreen.visitKey('bk-f-63')), findsOneWidget);
      expect(
        find.byKey(ClientCardScreen.visitKey(_kHeadAll)),
        findsNothing,
        reason: 'the head booking is never duplicated in the history',
      );
      expect(_calls(fb, 'visits'), 4);
      expect(_calls(fb, 'card'), 1, reason: 'paging never re-reads the card');

      expect(find.byKey(ClientCardScreen.visitKey('bk-p-0')), findsOneWidget);

      // Back at the top the head is still the card's visit.
      await tester.drag(_cardScroll(), const Offset(0, 60000));
      await AppHarness.settle(tester);
      expect(_headOf(_kHeadAll), findsOneWidget);
    });
  });

  testWidgets('(b) E1: no CONFIRMED future booking → no «Наступний візит», the '
      'PENDING / CANCELLED / past rows all in the history', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = await _openCard(tester, _kNoNextId);

      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientCardScreen.visitKey('bk-n-past')),
      );
      expect(find.byKey(ClientCardScreen.nextVisitKey), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('timeline-next-title')),
        findsNothing,
      );
      expect(
        find.byKey(ClientCardScreen.visitKey('bk-n-pending')),
        findsOneWidget,
      );
      expect(
        find.byKey(ClientCardScreen.visitKey('bk-n-cancelled')),
        findsOneWidget,
      );
      expect(_calls(fb, 'visits'), 1);
    });
  });

  testWidgets('(c) E4: the head follows the master chip — card + page 0 '
      're-read with masterId; «Усі майстри» restores the salon-wide head', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = await _openCard(tester, _kFarId);
      await AppHarness.pumpUntilFound(tester, _headOf(_kHeadAll));

      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientCardScreen.masterChipKey(_kMasterB)),
      );
      await AppHarness.pumpUntilFound(tester, _headOf(_kHeadB));
      expect(_headOf(_kHeadAll), findsNothing);
      expect(_calls(fb, 'card', masterId: _kMasterB), 1);
      expect(_calls(fb, 'visits', masterId: _kMasterB), 1);
      expect(find.byKey(ClientCardScreen.visitKey(_kHeadB)), findsNothing);

      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientCardScreen.masterChipKey(_kMasterA)),
      );
      await AppHarness.pumpUntilFound(tester, _headOf(_kHeadAll));
      expect(_calls(fb, 'card', masterId: _kMasterA), 1);
      expect(_calls(fb, 'visits', masterId: _kMasterA), 1);

      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientCardScreen.masterChipAllKey),
      );
      await AppHarness.pumpUntilFound(tester, _headOf(_kHeadAll));
      await AppHarness.settle(tester);
      expect(find.byKey(ClientCardScreen.nextVisitKey), findsOneWidget);
      // E4 for the chips proper: every scope read exactly one visits page.
      expect(_calls(fb, 'visits'), 1);
      expect(_calls(fb, 'visits', masterId: _kMasterB), 1);
    });
  });
}
