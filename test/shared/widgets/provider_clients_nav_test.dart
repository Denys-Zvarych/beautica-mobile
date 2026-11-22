// M509 — the 5th «Клієнти» tab on BOTH provider bars.
//
//   SalonBottomNav.ownerAdminItems   Салон 0 · Записи 1 · Команда 2 · Клієнти 3 · Профіль 4
//   VelvetBottomNavBar               Послуги 0 · Записи 1 · Графік 2 · Клієнти 3 · Профіль 4
//
// Pins: the order + the index constants other code reads, the 48 dp tap
// targets with no label truncation at 360 / 414 px and text 1.3× (D4), and —
// for the master bar — where tapping «Клієнти» goes in each context (the
// route override: INDEPENDENT_MASTER default, SALON_MASTER `/staff/clients`,
// owner master mode `/owner/master/clients`) and that «Профіль» (index 4)
// still lands on its own route. The salon shell's tab selection + the owner
// «Профіль» → master mode jump live in `salon_shell_screen_test.dart`.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/pump_app.dart';

AppLocalizations _l10n(WidgetTester tester, Type of) =>
    AppLocalizations.of(tester.element(find.byType(of)));

GoRouter _router(Widget bar) => GoRouter(
  initialLocation: '/host',
  routes: <RouteBase>[
    GoRoute(
      path: '/host',
      builder: (_, _) =>
          Scaffold(body: const SizedBox(), bottomNavigationBar: bar),
    ),
    for (final String path in <String>[
      RouteNames.masterClients,
      RouteNames.salonMasterClients,
      RouteNames.ownerMasterClients,
      RouteNames.masterProfile,
      RouteNames.salonMasterProfile,
      RouteNames.ownerMasterProfile,
    ])
      GoRoute(
        path: path,
        builder: (_, _) => Scaffold(body: Text('at $path')),
      ),
  ],
);

String _location(GoRouter router) => router
    .routerDelegate
    .currentConfiguration
    .uri
    .toString(); // router-location-ok: tabs are reached by `go` (no imperative push)

void main() {
  group('SalonBottomNav.ownerAdminItems', () {
    testWidgets('5 items; the index constants point at the right labels', (
      tester,
    ) async {
      await tester.pumpApp(
        SalonBottomNav(
          currentIndex: 0,
          onSelect: (_) {},
          items: const <SalonNavItem>[],
        ),
      );
      final AppLocalizations l10n = _l10n(tester, SalonBottomNav);
      final List<SalonNavItem> items = SalonBottomNav.ownerAdminItems(l10n);

      expect(items.map((SalonNavItem i) => i.label), <String>[
        l10n.salonShellTabSalon,
        l10n.salonShellTabBookings,
        l10n.salonShellTabTeam,
        l10n.providerNavClients,
        l10n.salonShellTabProfile,
      ]);
      expect(items[kSalonTeamNavTab].label, l10n.salonShellTabTeam);
      expect(items[kSalonBookingsNavTab].label, l10n.salonShellTabBookings);
      expect(items[kSalonClientsNavTab].label, l10n.providerNavClients);
      expect(items[kSalonProfileNavTab].label, l10n.salonShellTabProfile);
      expect(kSalonClientsNavTab, 3);
      expect(kSalonProfileNavTab, 4);
      // The approved glyph: `contacts`, not the «Команда» crowd icon.
      expect(items[kSalonClientsNavTab].icon, Icons.contacts_outlined);
      expect(items[kSalonClientsNavTab].activeIcon, Icons.contacts_rounded);
    });

    for (final double width in <double>[360, 414]) {
      for (final double scale in <double>[1.0, 1.3]) {
        testWidgets('5 tiles keep 48 dp targets, no overflow at $width px × '
            '$scale', (tester) async {
          await tester.pumpApp(
            Builder(
              builder: (BuildContext context) => Scaffold(
                body: const SizedBox(),
                bottomNavigationBar: SalonBottomNav(
                  currentIndex: 3,
                  onSelect: (_) {},
                  items: SalonBottomNav.ownerAdminItems(
                    AppLocalizations.of(context),
                  ),
                ),
              ),
            ),
            width: width,
            height: 800,
            textScaleFactor: scale,
          );
          for (int i = 0; i < 5; i++) {
            final Size size = tester.getSize(
              find.byKey(Key('salon-nav-tile-$i')),
            );
            expect(size.width, greaterThanOrEqualTo(48), reason: 'tile $i');
            expect(size.height, greaterThanOrEqualTo(48), reason: 'tile $i');
          }
          // Every label is a full, untruncated word.
          final AppLocalizations l10n = _l10n(tester, SalonBottomNav);
          for (final String label in <String>[
            l10n.salonShellTabSalon,
            l10n.salonShellTabBookings,
            l10n.salonShellTabTeam,
            l10n.providerNavClients,
            l10n.salonShellTabProfile,
          ]) {
            expect(find.text(label), findsOneWidget);
          }
        });
      }
    }
  });

  group('VelvetBottomNavBar', () {
    testWidgets('5 tiles in order; «Клієнти» is 3 and «Профіль» is 4', (
      tester,
    ) async {
      await tester.pumpApp(
        const Scaffold(
          body: SizedBox(),
          bottomNavigationBar: VelvetBottomNavBar(activeIndex: 3),
        ),
      );
      final AppLocalizations l10n = _l10n(tester, VelvetBottomNavBar);
      for (int i = 0; i < 5; i++) {
        expect(find.byKey(Key('master-nav-tile-$i')), findsOneWidget);
      }
      expect(find.byKey(const Key('master-nav-tile-5')), findsNothing);
      expect(kMasterClientsNavTab, 3);
      expect(kMasterProfileNavTab, 4);

      String labelAt(int i) => tester
          .widget<Semantics>(
            find
                .descendant(
                  of: find.byKey(Key('master-nav-tile-$i')),
                  matching: find.byType(Semantics),
                )
                .first,
          )
          .properties
          .label!;
      expect(
        <String>[for (int i = 0; i < 5; i++) labelAt(i)],
        <String>[
          l10n.masterNavTabServices,
          l10n.masterNavTabBookings,
          l10n.masterNavTabSchedule,
          l10n.providerNavClients,
          l10n.masterNavTabProfile,
        ],
      );
      // activeIndex 3 highlights «Клієнти» with the filled glyph.
      expect(find.byIcon(Icons.contacts_rounded), findsOneWidget);
      expect(find.byIcon(Icons.contacts_outlined), findsNothing);
    });

    for (final double width in <double>[360, 414]) {
      for (final double scale in <double>[1.0, 1.3]) {
        testWidgets('5 tiles keep 48 dp targets and every label, no overflow '
            'at $width px × $scale', (tester) async {
          await tester.pumpApp(
            const Scaffold(
              body: SizedBox(),
              bottomNavigationBar: VelvetBottomNavBar(activeIndex: 3),
            ),
            width: width,
            height: 800,
            textScaleFactor: scale,
          );
          final AppLocalizations l10n = _l10n(tester, VelvetBottomNavBar);
          for (int i = 0; i < 5; i++) {
            final Size size = tester.getSize(
              find.byKey(Key('master-nav-tile-$i')),
            );
            expect(size.width, greaterThanOrEqualTo(48), reason: 'tile $i');
            expect(size.height, greaterThanOrEqualTo(48), reason: 'tile $i');
          }
          for (final String label in <String>[
            l10n.masterNavTabServices,
            l10n.masterNavTabBookings,
            l10n.masterNavTabSchedule,
            l10n.providerNavClients,
            l10n.masterNavTabProfile,
          ]) {
            expect(find.text(label), findsOneWidget);
          }
        });
      }
    }

    Future<GoRouter> pumpBar(WidgetTester tester, Widget bar) async {
      final GoRouter router = _router(bar);
      await tester.pumpRoutedApp(router);
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('INDEPENDENT_MASTER: «Клієнти» → /master/clients', (
      tester,
    ) async {
      final GoRouter r = await pumpBar(
        tester,
        const VelvetBottomNavBar(activeIndex: 0),
      );
      await tester.tap(find.byKey(const Key('master-nav-tile-3')));
      await tester.pumpAndSettle();
      expect(_location(r), RouteNames.masterClients);
    });

    testWidgets('SALON_MASTER: the clientsRoute override → /staff/clients', (
      tester,
    ) async {
      final GoRouter r = await pumpBar(
        tester,
        const VelvetBottomNavBar(
          activeIndex: 0,
          clientsRoute: RouteNames.salonMasterClients,
        ),
      );
      await tester.tap(find.byKey(const Key('master-nav-tile-3')));
      await tester.pumpAndSettle();
      expect(_location(r), RouteNames.salonMasterClients);
    });

    testWidgets('owner master mode: the override → /owner/master/clients', (
      tester,
    ) async {
      final GoRouter r = await pumpBar(
        tester,
        const VelvetBottomNavBar(
          activeIndex: 0,
          profileRoute: RouteNames.ownerMasterProfile,
          clientsRoute: RouteNames.ownerMasterClients,
        ),
      );
      await tester.tap(find.byKey(const Key('master-nav-tile-3')));
      await tester.pumpAndSettle();
      expect(_location(r), RouteNames.ownerMasterClients);
    });

    testWidgets('«Профіль» (index 4) still lands on its own route per '
        'context — nothing was left on the old index 3', (tester) async {
      for (final (Widget bar, String expected) in <(Widget, String)>[
        (const VelvetBottomNavBar(activeIndex: 0), RouteNames.masterProfile),
        (
          const VelvetBottomNavBar(
            activeIndex: 0,
            profileRoute: RouteNames.salonMasterProfile,
          ),
          RouteNames.salonMasterProfile,
        ),
        (
          const VelvetBottomNavBar(
            activeIndex: 0,
            profileRoute: RouteNames.ownerMasterProfile,
          ),
          RouteNames.ownerMasterProfile,
        ),
      ]) {
        final GoRouter r = await pumpBar(tester, bar);
        await tester.tap(find.byKey(const Key('master-nav-tile-4')));
        await tester.pumpAndSettle();
        expect(_location(r), expected);
      }
    });

    testWidgets('tapping the ACTIVE «Клієнти» tile is a no-op', (tester) async {
      final GoRouter r = await pumpBar(
        tester,
        const VelvetBottomNavBar(activeIndex: 3),
      );
      await tester.tap(find.byKey(const Key('master-nav-tile-3')));
      await tester.pumpAndSettle();
      expect(_location(r), '/host');
    });
  });
}
