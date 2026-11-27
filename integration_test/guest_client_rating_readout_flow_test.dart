// M548 (REV-D04 / REV-D10, CLI-43 / CLI-47 / CLI-48 as modified by B546) —
// E2E: a GUEST client is rated by phone and the provider surfaces show the
// server's values, never a client-side "guest ⇒ unrated" shortcut.
//
//   (a) SALON_OWNER: «Клієнти» → guest card → chip «★ 4,3 · 3 оцінки» (no
//       «Ще немає оцінок») → the chip IS a link → «Рейтинг клієнта» shows the
//       guest's average and count;
//   (b) INDEPENDENT_MASTER: the same card read through `/masters/me/clients`;
//   (c) the «Клієнти» list row of a rated guest shows the same ★ number.
//
// REAL router, REAL `HttpClientRepository` and generated models over the
// stubbed Dio (`FakeBackend.wireClientList` / `wireClientCard`); only the
// transport is faked, so the DTO → domain mapping is what is under test.
//
// FINDERS: keys; the one text value per assertion is built from the app's own
// `formatClientRatingAvg` + `l10n.clientRatingCount`, never a Cyrillic literal.
//
// NO PATROL FLOW: no OS permission dialog, deep link, notification, WebView or
// biometric (mobile-qa explicit statement).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/client_rating_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/clients_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_card_text.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/rating_body.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/rating_readout.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// The owner's default landing salon (`FakeBackend.mySalons`).
const String _kSalonId = 'salon-owner-1';

/// The guest's booking id — the guest card's identity (`…/guests/{id}`).
const String _kGuest = 'b-guest-rated';

/// The guest's cross-provider rating (by phone, REV-D04).
const double _kAvg = 4.3;
const int _kCount = 3;

/// One rated guest row + its card (phone, 3 ratings, one past visit).
void _seedRatedGuest(FakeBackend fb) {
  fb.clientRows
    ..clear()
    ..add(<String, dynamic>{
      'kind': 'GUEST',
      'guestBookingId': _kGuest,
      'displayName': 'Гостя Рейтинг',
      'lastVisitAt': '2026-06-01T10:00:00Z',
      'completedVisits': 3,
      'ratingAvg': _kAvg,
      'ratingCount': _kCount,
      'blocked': false,
    });
  fb.clientCards
    ..clear()
    ..[_kGuest] = <String, dynamic>{
      'kind': 'GUEST',
      'guestBookingId': _kGuest,
      'displayName': 'Гостя Рейтинг',
      'phone': '+380501119988',
      'blocked': false,
      'ratingAvg': _kAvg,
      'ratingCount': _kCount,
      'ratingDistribution': <Map<String, int>>[
        <String, int>{'rating': 5, 'count': 1},
        <String, int>{'rating': 4, 'count': 2},
      ],
    };
  fb.clientVisits
    ..clear()
    ..[_kGuest] = <Map<String, dynamic>>[
      <String, dynamic>{
        'visitKey': 'v-gr1',
        'startsAt': '2026-06-01T10:00:00Z',
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'bookingId': 'bk-gr1',
            'serviceName': 'Манікюр',
            'status': 'COMPLETED',
            'startsAt': '2026-06-01T10:00:00Z',
            'priceAtBooking': 650,
          },
        ],
      },
    ];
  fb.wireClientCard();
}

Finder _row(String id) => find.byKey(Key('client-row-$id'));

/// Opens the «Клієнти» tab via [tileKey] and waits for the list.
Future<void> _openClients(WidgetTester tester, String tileKey) async {
  await AppHarness.tapVisible(tester, find.byKey(Key(tileKey)));
  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(ClientsScreen.listKey),
    timeout: const Duration(seconds: 20),
  );
  await AppHarness.settle(tester);
}

/// Boots as [role], opens «Клієнти» and returns the router.
Future<GoRouter> _bootToClients(
  WidgetTester tester,
  FakeBackend fb,
  UserRole role,
  String tileKey,
) async {
  final GoRouter router = await AppHarness.boot(tester, fb);
  await AppHarness.loginAs(tester, fb, role);
  await AppHarness.settle(tester);
  await _openClients(tester, tileKey);
  return router;
}

/// Card → chip readout is the server's rating → chip opens «Рейтинг клієнта»
/// at [cardPath]`/rating` with the same average and count.
Future<void> _expectRatedGuestCard(
  WidgetTester tester,
  GoRouter router,
  String cardPath,
) async {
  await AppHarness.tapVisible(tester, _row(_kGuest));
  await AppHarness.pumpUntilFound(tester, find.byKey(ClientCardScreen.nameKey));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, cardPath);

  final AppLocalizations l10n = AppLocalizations.of(
    tester.element(find.byType(ClientCardScreen)),
  );
  final Finder chip = find.byKey(ClientCardScreen.ratingChipKey);
  expect(chip, findsOneWidget);
  expect(
    find.descendant(of: chip, matching: find.byKey(RatingReadout.emptyKey)),
    findsNothing,
    reason: 'REV-D04: a rated guest is not shown as unrated',
  );
  expect(
    find.descendant(
      of: chip,
      matching: find.text(
        '${formatClientRatingAvg(_kAvg)} · ${l10n.clientRatingCount(_kCount)}',
      ),
    ),
    findsOneWidget,
  );

  // A rated chip is a link (CLI-48): the guest's rating page opens.
  await AppHarness.tapVisible(tester, chip);
  await AppHarness.pumpUntilFound(tester, find.byKey(RatingBody.averageKey));
  expect(find.byType(ClientRatingScreen), findsOneWidget);
  AppHarness.expectLocation(router, '$cardPath/rating');
  expect(
    tester.widget<Text>(find.byKey(RatingBody.averageKey)).data,
    formatClientRatingAvg(_kAvg),
  );
  expect(
    tester.widget<Text>(find.byKey(RatingBody.countKey)).data,
    l10n.clientRatingCount(_kCount),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('(a) SALON_OWNER: a rated guest card shows the server rating '
      '(number · count), and the chip opens «Рейтинг клієнта»', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..wireClientList();
      _seedRatedGuest(fb);
      final GoRouter router = await _bootToClients(
        tester,
        fb,
        UserRole.salonOwner,
        'salon-nav-tile-3',
      );

      await _expectRatedGuestCard(
        tester,
        router,
        '/salons/$_kSalonId/clients/guest/$_kGuest',
      );
    });
  });

  testWidgets('(b) INDEPENDENT_MASTER: a rated guest card shows the server '
      'rating (number · count), and the chip opens «Рейтинг клієнта»', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()..wireClientList();
      _seedRatedGuest(fb);
      final GoRouter router = await _bootToClients(
        tester,
        fb,
        UserRole.independentMaster,
        'master-nav-tile-3',
      );

      await _expectRatedGuestCard(
        tester,
        router,
        '/master/clients/guest/$_kGuest',
      );
    });
  });

  testWidgets('(c) SALON_OWNER: the «Клієнти» row of a rated guest shows the '
      'server ★ number (CLI-47 as modified by B546)', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..wireClientList();
      _seedRatedGuest(fb);
      await _bootToClients(tester, fb, UserRole.salonOwner, 'salon-nav-tile-3');

      expect(_row(_kGuest), findsOneWidget);
      expect(
        find.descendant(of: _row(_kGuest), matching: find.text('$_kAvg')),
        findsOneWidget,
        reason: 'REV-D04: the row readout is the server value for a guest too',
      );
    });
  });
}
