// mobile-qa re-audit (cycle 2, 2026-09-05) — the ONE `authRedirect` arm this
// phase converted to the strict `resolvedAuth` read, and the only one of the
// nine reads in that function where a stale role is a WRONG DESTINATION rather
// than a conservative bounce.
//
// WHAT CHANGED
// ---------------------------------------------------------------------------
// `auth_redirect.dart:200-203` added:
//
//     final Authenticated? resolvedAuth =
//         session is AsyncData<AuthSession> && session.value is Authenticated
//             ? session.value as Authenticated
//             : null;
//
// and rewired exactly one gate (`auth_redirect.dart:233`) — "an authenticated
// user sitting on an unauth-only route or /splash → forward to their role
// home" — from the loose `isAuthenticated` (`session.value is Authenticated`,
// which an `AsyncError`/`AsyncLoading(retrying: true)` carrying a PREVIOUS
// account's `AsyncData` satisfies) onto it.
//
// The other eight `.value` reads in the file are deliberately left loose, and
// that is documented at `auth_redirect.dart:170-193`: they are all fail-CLOSED
// bounces, so hardening them would convert a bounce into an ADMIT on
// `/master/*`, `/staff/*`, `/salon/*`, `/schedule`, `/client/*` and
// `/services` — strictly worse. Do not "finish the sweep".
//
// WHY IT WAS UNPINNED
// ---------------------------------------------------------------------------
// `auth_redirect_test.dart` has exactly one `AsyncError` case (line 270), and
// it is a VALUE-LESS error — `.value` is null, so it falls into the
// unauthenticated branch and never reaches this arm at all. No test anywhere
// fed `authRedirect` an error carrying a stale session, so reverting
// `resolvedAuth` back to `isAuthenticated` here changed no test's outcome.
//
// THE BUG THE ARM PREVENTS
// ---------------------------------------------------------------------------
// Account A (CLIENT) is signed in; a token refresh or `/users/me` re-read
// fails, so `authProvider` goes `AsyncError` while Riverpod's
// `copyWithPrevious` keeps A's session on `.value`. A visitor now on `/login`
// — the sign-in screen for account B — is FORWARDED into A's role home
// (`/home`) before ever entering a credential. Unresolved must mean "no
// forward": leave them on `/login`, and let the next settled emission decide.
//
// MUTATION-VERIFIED (2026-09-05) — replacing `resolvedAuth != null` at
// `auth_redirect.dart:233` with `isAuthenticated` (and the body's
// `resolvedAuth.user.role` with `(session.value! as Authenticated).user.role`)
// turns the two stale tests below RED with `/home` in place of `null`;
// restoring turns them GREEN. The settled control test stays green under both,
// which is the point of including it.

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/routing/auth_redirect.dart';
import 'package:beautica_mobile/routing/role_home.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The PREVIOUS account. CLIENT because `roleHomePath(client)` is
/// [RouteNames.clientHome] — a destination visibly different from both
/// `/login` and `/splash`, so the buggy read and the fixed read cannot be
/// confused for one another.
const User _previousAccount = User(
  id: 'u-client-prev',
  email: 'previous@beautica.test',
  role: UserRole.client,
  firstName: 'Попередній',
  lastName: 'Акаунт',
);

const AuthSession _previousSession = AuthSession.authenticated(
  user: _previousAccount,
  accessToken: 'stale-token',
);

/// `AsyncError` still carrying the settled previous account on `.value` — the
/// state Riverpod produces when a post-settle refresh fails.
///
/// `copyWithPrevious` is `@internal` to riverpod and used deliberately, exactly
/// as `salon_shell_screen_test.dart:1073` and
/// `salon_management_profile_screen_test.dart:1019` already do: it is the only
/// public-API-reachable way to build this shape for a PURE function, which has
/// no notifier to drive.
AsyncValue<AuthSession> _staleErrorSession() {
  final AsyncError<AuthSession> error = AsyncError<AuthSession>(
    const NetworkFailure(),
    StackTrace.current,
  );
  // ignore: invalid_use_of_internal_member
  return error.copyWithPrevious(const AsyncData<AuthSession>(_previousSession));
}

void main() {
  setUp(
    // Past the splash gate, so `/splash` is decided by the arm under test
    // rather than parked by `_minSplashDuration`.
    () => AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 30)),
    ),
  );
  tearDown(AppStartTime.resetForTest);

  group('the role-home FORWARD arm acts on a RESOLVED session only', () {
    test('the fixture really is an AsyncError carrying a stale Authenticated '
        'session', () {
      final AsyncValue<AuthSession> stale = _staleErrorSession();

      expect(
        stale,
        isA<AsyncError<AuthSession>>(),
        reason:
            'the terminal error SUBTYPE, not merely `hasError` — a mid-retry '
            'AsyncLoading reports hasError == true too.',
      );
      expect(
        stale.value,
        isA<Authenticated>(),
        reason:
            'and the previous account must still be attached. If this were '
            'null the guard would bounce to /login for a DIFFERENT reason and '
            'both tests below would pass on the buggy code too.',
      );
      expect(
        (stale.value! as Authenticated).user.role,
        UserRole.client,
        reason:
            'the stale role must have a role home that is neither /login nor '
            '/splash, or the buggy forward would be invisible.',
      );
      expect(
        roleHomePath(UserRole.client),
        RouteNames.clientHome,
        reason:
            'sanity on the destination the bug produces — asserted so a future '
            'change to roleHomePath cannot quietly make these tests vacuous.',
      );
    });

    test('a visitor on /login during a stale AsyncError is NOT forwarded into '
        'the previous account\'s role home', () {
      expect(
        authRedirectForLocation(_staleErrorSession(), RouteNames.login),
        isNull,
        reason:
            'this arm FORWARDS on the role rather than fencing on it, so an '
            'unresolved session must mean "no forward". A returned '
            '${RouteNames.clientHome} here is the loose `isAuthenticated` read '
            'sending someone who came to sign in as account B straight into '
            'account A\'s home.',
      );
    });

    test('and neither is one parked on /splash', () {
      expect(
        authRedirectForLocation(_staleErrorSession(), RouteNames.splash),
        isNull,
        reason:
            'the splash gate has elapsed, so this is the same forward arm — '
            'a stale role must not choose the cold-start landing either.',
      );
    });

    test('but a SETTLED session on /login still forwards — the arm is not '
        'simply dead', () {
      expect(
        authRedirectForLocation(
          const AsyncData<AuthSession>(_previousSession),
          RouteNames.login,
        ),
        RouteNames.clientHome,
        reason:
            'the control. Without it, deleting the forward arm outright would '
            'leave the two tests above green.',
      );
    });
  });
}
