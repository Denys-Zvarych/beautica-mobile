import 'package:beautica_mobile/routing/app_link_replay.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

class _SignOutAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(id: 'u1', email: 'u@b.c', role: UserRole.client),
    accessToken: 't',
  );

  void signOut() =>
      state = const AsyncData<AuthSession>(AuthSession.unauthenticated());
}

final Provider<void> _wire = Provider<void>((ref) {
  attachAppLinkReplay(
    ref,
    GoRouter(
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const SizedBox()),
      ],
    ),
  );
});

/// Pins the cold-start App Link holder (`lib/routing/app_link_replay.dart`):
/// only `/bookings/{id}` and `/bookings/{id}/review` on the app's own hosts are
/// ever held, the host/query are stripped, and a held path is consumed once.
void main() {
  group('appLinkReplayPath allow-list', () {
    test('accepts the emailed review + booking links on both flavor hosts', () {
      expect(
        appLinkReplayPath(
          Uri.parse('https://beautica.app/bookings/b-1/review'),
        ),
        RouteNames.bookingReview('b-1'),
      );
      expect(
        appLinkReplayPath(
          Uri.parse('https://staging.beautica.app/bookings/b-1'),
        ),
        RouteNames.bookingDetail('b-1'),
      );
    });

    test('accepts a path-only route and strips query + fragment', () {
      expect(
        appLinkReplayPath(Uri.parse('/bookings/b-1/review?utm=x#top')),
        RouteNames.bookingReview('b-1'),
      );
      expect(
        appLinkReplayPath(
          Uri.parse('https://beautica.app/bookings/b-1?utm_source=email'),
        ),
        RouteNames.bookingDetail('b-1'),
      );
    });

    for (final String rejected in <String>[
      'https://evil.example/bookings/b-1/review', // foreign host
      'https://beautica.app.evil.example/bookings/b-1', // look-alike host
      'http://beautica.app/bookings/b-1', // not https
      'https://beautica.app:8443/bookings/b-1', // explicit port
      'https://user@beautica.app/bookings/b-1', // userinfo
      'myapp://beautica.app/bookings/b-1', // custom scheme
      'https://beautica.app/r/some-token', // guest web-only review
      'https://beautica.app/c/some-token', // guest cancel
      'https://beautica.app/invite/accept?token=t', // not a replayed path
      '/bookings', // list, no id
      '/bookings/', // empty id
      '/bookings/b-1/cancel', // unknown child
      '/bookings/b-1/review/extra', // too deep
      '/bookings/b%2F1/review', // encoded slash in id
      '/bookings/..%2Fadmin', // traversal-shaped id
      '/master/bookings/b-1', // other subtree
      '/settings',
    ]) {
      test('rejects $rejected', () {
        expect(appLinkReplayPath(Uri.parse(rejected)), isNull);
      });
    }
  });

  group('PendingAppLinkHolder', () {
    test('holds an allow-listed link and is consumed exactly once', () {
      final PendingAppLinkHolder holder = PendingAppLinkHolder();
      expect(
        holder.hold(Uri.parse('https://beautica.app/bookings/b-1/review')),
        isTrue,
      );
      expect(holder.peek, RouteNames.bookingReview('b-1'));
      expect(holder.take(), RouteNames.bookingReview('b-1'));
      expect(holder.take(), isNull, reason: 'consume-on-read');
      expect(holder.peek, isNull);
    });

    test('ignores a non-allow-listed link and keeps the earlier one', () {
      final PendingAppLinkHolder holder = PendingAppLinkHolder()
        ..hold(Uri.parse('/bookings/b-1'));
      expect(holder.hold(Uri.parse('https://beautica.app/r/tok')), isFalse);
      expect(holder.take(), RouteNames.bookingDetail('b-1'));
    });

    test('a later allow-listed link replaces the earlier one', () {
      final PendingAppLinkHolder holder = PendingAppLinkHolder()
        ..hold(Uri.parse('/bookings/b-1'))
        ..hold(Uri.parse('/bookings/b-2/review'));
      expect(holder.take(), RouteNames.bookingReview('b-2'));
    });
  });

  group('holdAppLinkIfDeferred', () {
    final Uri link = Uri.parse('https://beautica.app/bookings/b-1/review');

    for (final String deferred in <String>[
      RouteNames.splash,
      RouteNames.login,
    ]) {
      test('holds when the redirect defers to $deferred, target unchanged', () {
        final PendingAppLinkHolder holder = PendingAppLinkHolder();
        expect(holdAppLinkIfDeferred(holder, link, deferred), deferred);
        expect(holder.peek, RouteNames.bookingReview('b-1'));
      });
    }

    for (final String? other in <String?>[null, RouteNames.clientHome]) {
      test('does not hold when the redirect target is $other', () {
        final PendingAppLinkHolder holder = PendingAppLinkHolder();
        expect(holdAppLinkIfDeferred(holder, link, other), other);
        expect(holder.peek, isNull);
      });
    }
  });

  group('isValidBookingIdSegment', () {
    test('accepts a uuid and short ids', () {
      expect(
        isValidBookingIdSegment('3f2b8c1e-0a4d-4e6b-9c1d-7a5e2f9b0c11'),
        isTrue,
      );
      expect(isValidBookingIdSegment('b-1'), isTrue);
      expect(isValidBookingIdSegment('a' * 64), isTrue);
    });

    for (final String bad in <String>[
      '',
      '..',
      '../x',
      '..%2F..%2Fx',
      'a%2Fb',
      'a/b',
      'a b',
      'a' * 65,
    ]) {
      test('rejects "$bad"', () {
        expect(isValidBookingIdSegment(bad), isFalse);
      });
    }
  });

  group('PendingAppLinkHolder expiry + clear', () {
    test('expires after 10 minutes (injectable clock)', () {
      DateTime now = DateTime.utc(2026, 11, 14, 12);
      final PendingAppLinkHolder holder = PendingAppLinkHolder(clock: () => now)
        ..hold(Uri.parse('/bookings/b-1'));
      now = now.add(kAppLinkHoldTtl - const Duration(seconds: 1));
      expect(holder.peek, RouteNames.bookingDetail('b-1'));
      now = now.add(const Duration(seconds: 1));
      expect(holder.peek, isNull);
      expect(holder.take(), isNull);
    });

    test('a fresh hold restarts the window', () {
      DateTime now = DateTime.utc(2026, 11, 14, 12);
      final PendingAppLinkHolder holder = PendingAppLinkHolder(clock: () => now)
        ..hold(Uri.parse('/bookings/b-1'));
      now = now.add(const Duration(minutes: 9));
      holder.hold(Uri.parse('/bookings/b-2'));
      now = now.add(const Duration(minutes: 9));
      expect(holder.take(), RouteNames.bookingDetail('b-2'));
    });

    test('clear() drops the held link', () {
      final PendingAppLinkHolder holder = PendingAppLinkHolder()
        ..hold(Uri.parse('/bookings/b-1'))
        ..clear();
      expect(holder.peek, isNull);
    });
  });

  test(
    'sign-out clears the held link (Authenticated -> Unauthenticated)',
    () async {
      final ProviderContainer container = ProviderContainer(
        overrides: [authProvider.overrideWith(_SignOutAuth.new)],
      );
      addTearDown(container.dispose);
      await container.read(authProvider.future);
      container.read(_wire);
      final PendingAppLinkHolder holder = container.read(pendingAppLinkProvider)
        ..hold(Uri.parse('/bookings/b-1'));
      expect(holder.peek, isNotNull);

      (container.read(authProvider.notifier) as _SignOutAuth).signOut();
      await Future<void>.delayed(Duration.zero);
      expect(holder.peek, isNull);
    },
  );
}
