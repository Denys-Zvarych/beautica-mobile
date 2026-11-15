import 'package:beautica_mobile/routing/deferred_navigation.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('holdsDeferredNavigation', () {
    for (final String held in <String>[
      RouteNames.splash,
      RouteNames.login,
      RouteNames.verification,
      RouteNames.register,
      '${RouteNames.register}/role',
      '${RouteNames.register}/client/step-2',
    ]) {
      test('holds the pre-session location $held', () {
        expect(holdsDeferredNavigation(held), isTrue);
      });
    }

    for (final String settled in <String>[
      RouteNames.clientHome,
      RouteNames.masterProfile,
      RouteNames.bookingReview('b-1'),
      RouteNames.bookingDetail('b-1'),
      '${RouteNames.login}/forgot',
      '${RouteNames.register}x',
      '',
    ]) {
      test('does not hold the settled location "$settled"', () {
        expect(holdsDeferredNavigation(settled), isFalse);
      });
    }
  });
}
