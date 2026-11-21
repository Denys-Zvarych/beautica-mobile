// Warm-start App Link hardening: a decoded `:bookingId` that is not a plain
// `[A-Za-z0-9-]` segment must render the shared not-found ErrorState and never
// build BookingDetailScreen / LeaveReviewScreen (which would hit the API with
// the id interpolated unencoded into the path).

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/client_rating_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_client_feedback_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_review_screen.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_notification_repository.dart' show FixedRoleAuth;
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/test_container.dart';

Widget _leaf(GoRouter router, BuildContext context, String location) {
  final RouteMatchList match = router.configuration.findMatch(
    Uri.parse(location),
  );
  expect(match.isError, isFalse, reason: '$location must be registered');
  final GoRouterWidgetBuilder? builder = match.last.route.builder;
  return builder!(
    context,
    router.configuration.buildTopLevelGoRouterState(match),
  );
}

/// Every route taking `:bookingId` and the screen a valid id must build.
/// Exposed to the ledger below: a new route must be added here AND guarded.
final Map<String, Type> _guardedRoutes = <String, Type>{
  '/bookings/b-1': BookingDetailScreen,
  '/bookings/b-1/review': LeaveReviewScreen,
  '/notifications/bookings/b-1': BookingDetailScreen,
  '/notifications/bookings/b-1/review': LeaveReviewScreen,
  '/master/bookings/b-1': BookingDetailScreen,
  '/master/bookings/b-1/review': LeaveClientFeedbackScreen,
  '/salon/bookings/b-1': BookingDetailScreen,
  '/salon/bookings/b-1/review': LeaveClientFeedbackScreen,
  '/staff/bookings/b-1': BookingDetailScreen,
  '/staff/bookings/b-1/review': LeaveClientFeedbackScreen,
  '/salons/s-1/clients/guest/b-1': ClientCardScreen,
  '/salons/s-1/clients/guest/b-1/rating': ClientRatingScreen,
  '/master/clients/guest/b-1': ClientCardScreen,
  '/master/clients/guest/b-1/rating': ClientRatingScreen,
  '/staff/clients/guest/b-1': ClientCardScreen,
  '/staff/clients/guest/b-1/rating': ClientRatingScreen,
};

/// Every non-booking route taking an id path param. `{x}` placeholders are
/// the guarded params; a new id route must be added here AND guarded.
const List<String> _idRoutes = <String>[
  '/masters/{masterId}',
  '/masters/{masterId}/reviews',
  '/salons/{salonId}',
  '/salons/{salonId}/manage',
  '/salons/{salonId}/manage/settings',
  '/salons/{salonId}/manage/invite',
  '/salons/{salonId}/pending-invites',
  '/salons/{salonId}/manage/staff/{memberId}',
  '/salons/{salonId}/manage/staff/{memberId}/settings',
  '/salons/{salonId}/manage/staff/{memberId}/move',
  '/salons/{salonId}/manage/staff/{memberId}/schedule',
  '/salons/{salonId}/manage/staff/{memberId}/services',
  '/salons/{salonId}/manage/staff/{memberId}/services/setup',
  '/salons/{salonId}/manage/staff/{memberId}/services/{serviceId}/edit',
  '/salons/{salonId}/manage/settings/profile-edit',
  '/salons/{salonId}/manage/settings/address-edit',
  '/salons/{salonId}/manage/settings/contacts-edit',
  '/salons/{salonId}/shell',
  '/owner/master/services/{serviceId}/edit',
  '/services/{id}/edit',
  '/salons/{salonId}/clients/user/{userId}',
  '/salons/{salonId}/clients/user/{userId}/rating',
  '/salons/{salonId}/clients/guest/b-1',
  '/salons/{salonId}/clients/guest/b-1/rating',
  '/master/clients/user/{userId}',
  '/master/clients/user/{userId}/rating',
  '/staff/clients/user/{userId}',
  '/staff/clients/user/{userId}/rating',
];

bool _isInvalidIdScaffold(Widget w) =>
    w is Scaffold &&
    w.body is ErrorState &&
    w.body?.key == const Key('path_id_invalid_error');

void main() {
  testWidgets('invalid id path param -> not-found, valid -> real screen', (
    tester,
  ) async {
    final ProviderContainer container = makeTestContainer(
      overrides: <Object>[
        authProvider.overrideWith(() => FixedRoleAuth(UserRole.client)),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
      ],
    );
    final GoRouter router = container.read(appRouterProvider);
    addTearDown(router.dispose);
    await tester.pumpWidget(const SizedBox(key: Key('ctx')));
    final BuildContext context = tester.element(find.byKey(const Key('ctx')));

    for (final String template in _idRoutes) {
      final List<String> params = RegExp(
        r'\{(\w+)\}',
      ).allMatches(template).map((RegExpMatch m) => m.group(1)!).toList();
      String fill(String? bad) => template.replaceAllMapped(
        RegExp(r'\{(\w+)\}'),
        (Match m) => m.group(1) == bad ? '..%2F..%2Fx' : 'id-1',
      );

      expect(
        _isInvalidIdScaffold(_leaf(router, context, fill(null))),
        isFalse,
        reason: 'valid ids must build the real screen: ${fill(null)}',
      );
      for (final String bad in params) {
        expect(
          _isInvalidIdScaffold(_leaf(router, context, fill(bad))),
          isTrue,
          reason: 'bad :$bad must render not-found: ${fill(bad)}',
        );
      }
    }
  });

  test('ledger: id path params are read only through the guards', () {
    final String src = File('lib/routing/app_router.dart').readAsStringSync();
    final String code = src
        .split('\n')
        .where((String l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    // Raw reads outside the guard helpers. Allow-list (non-building uses):
    //  - salonId x5: salonManageGuard (admin + owner compare), the owner-only
    //    form guard compare, and the weekly/copy redirects that rebuild the
    //    already-guarded schedule entry route's path;
    //  - memberId x2: the same two redirects.
    // `[name]` (pathIdsGuarded) and `['bookingId']` (bookingIdGuarded) are the
    // helpers themselves.
    final Map<String, int> raw = <String, int>{};
    for (final RegExpMatch m in RegExp(
      r"pathParameters\[(?:'(\w+)'|(\w+))\]",
    ).allMatches(code)) {
      final String k = m.group(1) ?? '<${m.group(2)}>';
      raw[k] = (raw[k] ?? 0) + 1;
    }
    expect(raw, <String, int>{
      'salonId': 5,
      'memberId': 2,
      'bookingId': 1,
      '<name>': 1,
    }, reason: 'new raw pathParameters read: use pathIdsGuarded');

    // Every dynamic param declared in a route path is a known id param.
    final Set<String> declared = RegExp(
      r"path:[^,]*?'[^']*:(\w+)",
      dotAll: true,
    ).allMatches(code).map((RegExpMatch m) => m.group(1)!).toSet();
    expect(
      declared.difference(<String>{
        'bookingId',
        'masterId',
        'salonId',
        'memberId',
        'serviceId',
        'userId',
        'id',
      }),
      isEmpty,
      reason: 'new path param: guard it or allow-list it as a non-id',
    );

    expect(
      'pathIdsGuarded('.allMatches(code).length - 1,
      _idRoutes.length + 1, // +1: the ShellRoute builder (no own leaf entry)
      reason: 'extend _idRoutes',
    );
  });

  testWidgets('invalid :bookingId -> not-found, valid -> real screen', (
    tester,
  ) async {
    final ProviderContainer container = makeTestContainer(
      overrides: <Object>[
        authProvider.overrideWith(() => FixedRoleAuth(UserRole.client)),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
      ],
    );
    final GoRouter router = container.read(appRouterProvider);
    addTearDown(router.dispose);
    await tester.pumpWidget(const SizedBox(key: Key('ctx')));
    final BuildContext context = tester.element(find.byKey(const Key('ctx')));

    for (final MapEntry<String, Type> e in _guardedRoutes.entries) {
      final String bad = e.key.replaceFirst('b-1', '..%2F..%2Fx');
      final Widget w = _leaf(router, context, bad);
      expect(w, isNot(isA<BookingDetailScreen>()), reason: bad);
      expect(w, isNot(isA<LeaveReviewScreen>()), reason: bad);
      expect(w, isNot(isA<LeaveClientFeedbackScreen>()), reason: bad);
      expect(w, isA<Scaffold>(), reason: bad);
      expect((w as Scaffold).body, isA<ErrorState>(), reason: bad);

      expect(_leaf(router, context, e.key).runtimeType, e.value, reason: e.key);
    }
  });

  test('ledger: every :bookingId route is behind bookingIdGuarded', () {
    final String src = File('lib/routing/app_router.dart').readAsStringSync();
    // Raw reads are legal only inside bookingIdGuarded itself.
    expect(
      "pathParameters['bookingId']".allMatches(src).length,
      1,
      reason: 'read :bookingId outside bookingIdGuarded',
    );
    // Declared `:bookingId` route paths vs guarded builders (- 1 = the decl).
    // `:bookingId` paths plus the two nested `path: 'review'` children.
    final int declared = RegExp(
      r"path: '(?:[^']*:bookingId[^']*|review)'",
    ).allMatches(src).length;
    final int guarded = 'bookingIdGuarded('.allMatches(src).length - 1;
    expect(guarded, declared, reason: 'unguarded :bookingId route');
    expect(guarded, _guardedRoutes.length, reason: 'extend _guardedRoutes');
  });
}
