// Phase 264 — Widget tests for WalkInGuestStepScreen, the first screen of
// the routed walk-in chain (`/master/bookings/new`).
//
// Covers the phase doc's "Guest step" test cases (6-9):
//   6. should_disableNextCta_when_phoneIsInvalid
//   7. should_mintWalkInGuest_when_nextTapped
//   8. should_preserveTypedText_when_poppedBackFromServiceStep — the
//      back-navigation-survival pin (D5). MUTATION-VERIFIED: flipping the
//      screen's `context.push` to `context.pushReplacement` sends this RED
//      (see the file header's own note in `walk_in_guest_step_screen.dart`).
//   9. should_notRenderStepIndicator_when_guestStepShown (brief decision 4).
//
// Plus one case re-homed from the retired wizard's own "client step" group:
// the header back-chevron pops the whole screen (`master_create_booking
// _screen_test.dart`'s "the header back-chevron pops the whole wizard").
//
// Strategy mirrors `master_create_booking_screen_test.dart`'s former
// client-step group: a test-local bare GoRouter (no auth guard — this widget
// is tested in isolation) with a stub destination screen standing in for
// [WalkInServiceStepScreen] (irrelevant to what this screen itself must
// prove — its own provider wiring is covered by
// `walk_in_service_step_screen_test.dart`).

import 'dart:async';

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart'
    show WalkInGuest;
import 'package:beautica_mobile/features/booking/presentation/walk_in_guest_step_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_wizard_steps.dart'
    show StepIndicator;
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

const String _kFirstName = 'Марина';
const String _kLastName = 'Кравчук';
const String _kPhone = '0501234567';

/// Captures every `extra` pushed to [RouteNames.masterBookingNewServices].
final List<Object?> _pushedExtras = <Object?>[];

GoRouter _router() {
  _pushedExtras.clear();
  return GoRouter(
    initialLocation: '/root',
    routes: <RouteBase>[
      GoRoute(
        path: '/root',
        builder: (context, state) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: RouteNames.masterBookingNew,
        builder: (context, state) => const WalkInGuestStepScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'services',
            builder: (context, state) {
              _pushedExtras.add(state.extra);
              return Scaffold(
                body: TextButton(
                  key: const Key('stub-services-back'),
                  onPressed: () => context.pop(),
                  child: const Text('back'),
                ),
              );
            },
          ),
        ],
      ),
    ],
  );
}

Future<GoRouter> _pump(WidgetTester tester) async {
  final GoRouter router = _router();
  await tester.pumpRoutedApp(router);
  unawaited(router.push(RouteNames.masterBookingNew));
  await tester.pumpAndSettle();
  return router;
}

Future<void> _enter(WidgetTester tester, Key key, String text) async {
  await tester.enterText(find.byKey(key), text);
  await tester.pump();
}

void main() {
  testWidgets(
    'should_disableNextCta_when_phoneIsInvalid — an invalid phone keeps the '
    '«Далі» CTA disabled even with both names filled',
    (tester) async {
      await _pump(tester);
      await _enter(
        tester,
        const Key('master-create-booking-first-name'),
        _kFirstName,
      );
      await _enter(
        tester,
        const Key('master-create-booking-last-name'),
        _kLastName,
      );
      await _enter(
        tester,
        const Key('master-create-booking-phone'),
        '123', // too short to normalise
      );

      final NeumorphicButton button = tester.widget<NeumorphicButton>(
        find.byKey(const Key('master-create-booking-client-next')),
      );
      expect(button.onPressed, isNull);
    },
  );

  testWidgets(
    'should_mintWalkInGuest_when_nextTapped — «Далі» pushes the services '
    'route with a WalkInGuest carrying the normalised E.164 phone',
    (tester) async {
      await _pump(tester);
      await _enter(
        tester,
        const Key('master-create-booking-first-name'),
        _kFirstName,
      );
      await _enter(
        tester,
        const Key('master-create-booking-last-name'),
        _kLastName,
      );
      await _enter(tester, const Key('master-create-booking-phone'), _kPhone);
      await tester.tap(
        find.byKey(const Key('master-create-booking-client-next')),
      );
      await tester.pumpAndSettle();

      expect(_pushedExtras, hasLength(1));
      final WalkInGuest guest = _pushedExtras.single! as WalkInGuest;
      expect(guest.name, _kFirstName);
      expect(guest.surname, _kLastName);
      expect(guest.phone, '+380501234567');
    },
  );

  testWidgets(
    'should_preserveTypedText_when_poppedBackFromServiceStep — D5: the '
    'guest step is pushed (never go/pushReplacement), so its State stays '
    'mounted underneath and a pop back restores the typed fields',
    (tester) async {
      await _pump(tester);
      await _enter(
        tester,
        const Key('master-create-booking-first-name'),
        _kFirstName,
      );
      await _enter(
        tester,
        const Key('master-create-booking-last-name'),
        _kLastName,
      );
      await _enter(tester, const Key('master-create-booking-phone'), _kPhone);
      await tester.tap(
        find.byKey(const Key('master-create-booking-client-next')),
      );
      await tester.pumpAndSettle();

      // Now on the stub services screen — pop back.
      await tester.tap(find.byKey(const Key('stub-services-back')));
      await tester.pumpAndSettle();

      final Finder firstNameField = find.byKey(
        const Key('master-create-booking-first-name'),
      );
      expect(firstNameField, findsOneWidget);
      final TextField tf = tester.widget<TextField>(
        find.descendant(of: firstNameField, matching: find.byType(TextField)),
      );
      expect(tf.controller!.text, _kFirstName);
    },
  );

  testWidgets('should_notRenderStepIndicator_when_guestStepShown — the 4-dot '
      'indicator is dropped from the routed walk-in chain (brief decision 4)', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byType(StepIndicator), findsNothing);
  });

  // Re-homed from the retired wizard's own "client step" group: "the header
  // back-chevron pops the whole wizard".
  testWidgets('the header back-chevron pops the whole screen', (tester) async {
    final GoRouter router = await _pump(tester);
    expect(find.byType(WalkInGuestStepScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('walk-in-guest-back')));
    await tester.pumpAndSettle();

    expect(find.byType(WalkInGuestStepScreen), findsNothing);
    // Read AFTER a full pop back to the stack ROOT (`/root`, a plain
    // `builder:` GoRoute reached at `initialLocation`, never pushed) — the
    // `ImperativeRouteMatch` exclusion only bites a read taken while a
    // PUSHED match is still on the stack; nothing pushed remains here.
    // router-location-ok: pop-back-to-root read, no ImperativeRouteMatch left on the stack
    expect(router.routerDelegate.currentConfiguration.uri.path, '/root');
  });
}
