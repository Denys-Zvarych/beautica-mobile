// M569 (CLI-101 / CLI-D20) — «Відгук про клієнта» heads with the ONE shared
// client strip (`BookingCounterpartyHeader` → `BookingClientStrip`), not the
// retired `ClientFeedbackCard`: photo / monogram, name, ★ for every client
// kind, the visit line as its sub-line, and a tap into the client card.

import 'dart:async';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_client_feedback_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_client_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip_shell.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

const String _bookingId = 'b-77';
const String _first = 'Олена';
const String _last = 'Ткаченко';
const String _service = 'Манікюр з покриттям';

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

Booking _booking({String? clientId, double? avg, int? count}) {
  final DateTime start = DateTime.utc(2020, 7, 14, 12);
  return Booking(
    id: _bookingId,
    masterId: 'm1',
    masterFirstName: 'Софія',
    masterLastName: 'Бондар',
    masterType: 'INDEPENDENT_MASTER',
    clientId: clientId,
    clientFirstName: _first,
    clientLastName: _last,
    clientAvgRating: avg,
    clientReviewCount: count,
    serviceId: 's1',
    serviceName: _service,
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: BookingStatus.completed,
    canReview: false,
    providerCanReviewClient: true,
  );
}

Future<GoRouter> _pump(
  WidgetTester tester,
  Booking booking, {
  String? Function(String? salonId)? clientCardBase,
}) async {
  final GoRouter router = GoRouter(
    initialLocation: '/host',
    routes: <RouteBase>[
      GoRoute(
        path: '/host',
        builder: (BuildContext context, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: '/master/bookings/:bookingId/review',
        builder: (BuildContext context, GoRouterState state) =>
            LeaveClientFeedbackScreen(
              bookingId: state.pathParameters['bookingId']!,
              clientCardBase: clientCardBase,
            ),
      ),
      GoRoute(
        path: '${RouteNames.masterClients}/:kind/:id',
        builder: (BuildContext context, GoRouterState state) =>
            Scaffold(body: Text('card-stub:${state.uri}')),
      ),
    ],
  );
  await tester.pumpRoutedApp(
    router,
    overrides: <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingDetailProvider(_bookingId).overrideWith((ref) async => booking),
    ],
  );
  unawaited(router.push(RouteNames.clientReview(_bookingId)));
  await tester.pumpAndSettle();
  return router;
}

Finder get _strip => find.byKey(BookingClientStrip.defaultShellKey);

Finder _inStrip(Finder f) => find.descendant(of: _strip, matching: f);

void main() {
  group('«Відгук про клієнта» client strip (M569)', () {
    testWidgets('a registered client: the shared strip with name, ★ and the '
        'visit sub-line', (tester) async {
      await _pump(tester, _booking(clientId: 'c1', avg: 4.8, count: 5));
      expect(_strip, findsOneWidget);
      expect(_inStrip(find.text('$_first $_last')), findsOneWidget);
      expect(_inStrip(find.text('4.8')), findsOneWidget);
      expect(_inStrip(find.textContaining(_service)), findsOneWidget);
    });

    testWidgets('a guest with a phone-keyed rating shows its ★ (CLI-101)', (
      tester,
    ) async {
      await _pump(tester, _booking(avg: 4.2, count: 3));
      expect(_inStrip(find.text('4.2')), findsOneWidget);
    });

    testWidgets('an unrated client shows «—»', (tester) async {
      await _pump(tester, _booking(clientId: 'c1'));
      expect(_inStrip(find.text(MasterStrip.noRatingLabel)), findsOneWidget);
    });

    testWidgets('tap → the USER card for a registered client; back returns '
        'to the form', (tester) async {
      final GoRouter router = await _pump(
        tester,
        _booking(clientId: 'c1'),
        clientCardBase: (_) => RouteNames.masterClients,
      );
      await tester.tap(_strip);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'card-stub:${RouteNames.clientCardUser(RouteNames.masterClients, 'c1')}',
        ),
        findsOneWidget,
      );
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(LeaveClientFeedbackScreen), findsOneWidget);
    });

    testWidgets('tap → the GUEST card keyed by this booking for a guest', (
      tester,
    ) async {
      await _pump(
        tester,
        _booking(),
        clientCardBase: (_) => RouteNames.masterClients,
      );
      await tester.tap(_strip);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'card-stub:${RouteNames.clientCardGuest(RouteNames.masterClients, _bookingId)}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('no card base → inert', (tester) async {
      await _pump(tester, _booking(clientId: 'c1'));
      expect(tester.widget<MasterStripShell>(_strip).onTap, isNull);
    });
  });
}
