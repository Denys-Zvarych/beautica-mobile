// MAS-39 — unit-level pins for the ONE shared "master card → public profile"
// callback (`master_profile_tap.dart`) every client booking screen uses.
//
// What is pinned (each assertion checks the EXACT pushed URI as a FIXED
// string — never `RouteNames.masterPublicProfile(...)`, so a mutation inside
// that helper or a dropped `fromBooking` argument goes red here):
//   * empty master id → `null` (inert card; `/masters/` matches no route);
//   * default → `/masters/<id>?fromBooking=1` (profile hides its book CTA);
//   * `fromBooking: false` («Деталі запису») → plain `/masters/<id>`;
//   * `clientMasterProfileTap` → `null` for a non-CLIENT viewer, `null` for
//     an empty id, and the booking-context URI for a CLIENT.
//
// Strategy: a real GoRouter whose `/masters/:masterId` stub renders the URI
// it received, so the test observes what the callback actually pushed.

import 'package:beautica_mobile/features/auth/presentation/auth_selectors.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_profile_tap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../../helpers/pump_app.dart';

/// Signature of the factory under test, evaluated inside a real build.
typedef _TapFactory =
    VoidCallback? Function(BuildContext context, WidgetRef ref);

/// Pumps a router whose home builds the callback via [factory] (captured in
/// [captured]) and whose `/masters/:masterId` stub prints its URI.
Future<void> _pumpHarness(
  WidgetTester tester, {
  required _TapFactory factory,
  required void Function(VoidCallback? tap) captured,
  required bool isClient,
}) async {
  final GoRouter router = GoRouter(
    initialLocation: '/home',
    routes: <RouteBase>[
      GoRoute(
        path: '/home',
        builder: (context, state) => Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              captured(factory(context, ref));
              return const Text('home');
            },
          ),
        ),
      ),
      GoRoute(
        path: '/masters/:masterId',
        builder: (context, state) =>
            Scaffold(body: Text('profile-stub:${state.uri}')),
      ),
    ],
  );
  await tester.pumpRoutedApp(
    router,
    overrides: <Object>[isClientProvider.overrideWith((ref) => isClient)],
  );
  await tester.pumpAndSettle();
}

/// Invokes [tap] and returns the URI the stub profile received.
Future<String> _pushedUri(WidgetTester tester, VoidCallback tap) async {
  tap();
  await tester.pumpAndSettle();
  final Finder stub = find.textContaining('profile-stub:');
  expect(stub, findsOneWidget, reason: 'the tap must push the profile route');
  return tester.widget<Text>(stub).data!.substring('profile-stub:'.length);
}

void main() {
  group('masterProfileTap', () {
    testWidgets('returns null for an empty master id (inert card)', (
      tester,
    ) async {
      VoidCallback? tap = () {};
      await _pumpHarness(
        tester,
        isClient: true,
        factory: (context, ref) => masterProfileTap(context, ''),
        captured: (t) => tap = t,
      );

      expect(tap, isNull);
    });

    testWidgets('pushes /masters/<id>?fromBooking=1 by default', (
      tester,
    ) async {
      VoidCallback? tap;
      await _pumpHarness(
        tester,
        isClient: true,
        factory: (context, ref) => masterProfileTap(context, 'm1'),
        captured: (t) => tap = t,
      );

      expect(await _pushedUri(tester, tap!), '/masters/m1?fromBooking=1');
    });

    testWidgets('pushes the plain /masters/<id> when fromBooking is false '
        '(«Деталі запису» keeps the book CTA)', (tester) async {
      VoidCallback? tap;
      await _pumpHarness(
        tester,
        isClient: true,
        factory: (context, ref) =>
            masterProfileTap(context, 'm1', fromBooking: false),
        captured: (t) => tap = t,
      );

      expect(await _pushedUri(tester, tap!), '/masters/m1');
    });
  });

  group('clientMasterProfileTap', () {
    testWidgets('returns null for a non-CLIENT viewer', (tester) async {
      VoidCallback? tap = () {};
      await _pumpHarness(
        tester,
        isClient: false,
        factory: (context, ref) => clientMasterProfileTap(context, ref, 'm1'),
        captured: (t) => tap = t,
      );

      expect(tap, isNull);
    });

    testWidgets('returns null for a CLIENT with an empty master id', (
      tester,
    ) async {
      VoidCallback? tap = () {};
      await _pumpHarness(
        tester,
        isClient: true,
        factory: (context, ref) => clientMasterProfileTap(context, ref, ''),
        captured: (t) => tap = t,
      );

      expect(tap, isNull);
    });

    testWidgets('pushes /masters/<id>?fromBooking=1 for a CLIENT', (
      tester,
    ) async {
      VoidCallback? tap;
      await _pumpHarness(
        tester,
        isClient: true,
        factory: (context, ref) => clientMasterProfileTap(context, ref, 'm1'),
        captured: (t) => tap = t,
      );

      expect(await _pushedUri(tester, tap!), '/masters/m1?fromBooking=1');
    });
  });
}
