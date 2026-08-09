// Phase 7.2 — `bookingViewerRoleProvider` MUST FAIL CLOSED.
//
// WHY THIS FILE EXISTS (mobile-qa, Phase 7.2/7.6 audit)
// -----------------------------------------------------
// `booking_detail_provider_view_test.dart` pins the two HAPPY branches: an
// INDEPENDENT_MASTER session resolves to `provider`, a CLIENT session to
// `client`. Neither of those is the branch that can hurt anyone.
//
// The dangerous case is the INDETERMINATE session — still loading, signed out,
// errored, or carrying a role this build does not know. `booking_viewer_role
// .dart`'s header commits to resolving every one of those onto the CLIENT
// branch ("Guessing 'provider' from an indeterminate session would hand
// provider affordances to whoever is looking"), and NOTHING pinned that. A
// refactor of the `switch` — swapping the `_ => client` default for a
// `_ => provider`, or widening the guard clause — would keep both existing
// tests green while handing the provider footer (Phase 7.3: decline /
// mark-no-show, both destructive and both writing a note the client reads) to
// an unauthenticated viewer on a deep link.
//
// This test asserts the DEFAULT arm, which is the whole security property.
//
// The provider is read through a bare `ProviderContainer` rather than a pumped
// screen: the derivation is pure, and a container is the only way to express
// the loading/error sessions at all (a widget test cannot easily hold
// `authProvider` in flight).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_viewer_role.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

/// Resolves `build()` to [session].
class _StubAuth extends AuthNotifier {
  _StubAuth(this._session);

  final AuthSession _session;

  @override
  Future<AuthSession> build() async => _session;
}

/// Never resolves — the session is still LOADING. This is the state the app is
/// in for the whole cold-start window, which is exactly when a deep link to
/// `/master/bookings/:id` lands.
class _PendingAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() => Completer<AuthSession>().future;
}

/// `build()` throws — a refresh-token failure, a malformed stored session.
class _FailingAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() async => throw StateError('session unavailable');
}

ProviderContainer _containerWith(AuthNotifier Function() auth) {
  final ProviderContainer container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: [authProvider.overrideWith(auth)],
  );
  addTearDown(container.dispose);
  return container;
}

User _user(UserRole role) => User(id: 'u1', email: 'u@e.com', role: role);

Future<BookingViewerRole> _resolve(ProviderContainer container) async {
  // Let `authProvider`'s async build settle before reading the derived value,
  // so a `provider` answer here cannot be an artefact of reading too early.
  await container
      .read(authProvider.future)
      .then<void>((_) {}, onError: (Object _) {});
  return container.read(bookingViewerRoleProvider);
}

void main() {
  group('bookingViewerRoleProvider fails CLOSED', () {
    test('an UNAUTHENTICATED session resolves to the CLIENT view, never the '
        'provider view', () async {
      final ProviderContainer container = _containerWith(
        () => _StubAuth(const AuthSession.unauthenticated()),
      );

      final BookingViewerRole viewer = await _resolve(container);

      expect(
        viewer,
        BookingViewerRole.client,
        reason:
            'a signed-out viewer must never be handed the provider branch — '
            'Phase 7.3 fills that footer with destructive actions',
      );
      expect(viewer.isProvider, isFalse);
    });

    test('a session still LOADING resolves to the CLIENT view', () async {
      final ProviderContainer container = _containerWith(_PendingAuth.new);

      // Deliberately NOT awaited — the whole point is that the session has not
      // resolved yet. `.value` is null here.
      expect(container.read(authProvider).value, isNull);

      expect(
        container.read(bookingViewerRoleProvider),
        BookingViewerRole.client,
        reason:
            'the cold-start window is exactly when a deep link arrives; an '
            'unresolved session must not read as "provider"',
      );
    });

    test('an ERRORED session resolves to the CLIENT view', () async {
      final ProviderContainer container = _containerWith(_FailingAuth.new);

      final BookingViewerRole viewer = await _resolve(container);

      expect(
        container.read(authProvider).hasError,
        isTrue,
        reason: 'guard: the fixture must actually be in the error state',
      );
      expect(viewer, BookingViewerRole.client);
    });

    test('a CLIENT session resolves to the CLIENT view', () async {
      final ProviderContainer container = _containerWith(
        () => _StubAuth(
          AuthSession.authenticated(
            user: _user(UserRole.client),
            accessToken: 't',
          ),
        ),
      );

      expect(await _resolve(container), BookingViewerRole.client);
    });
  });

  group('bookingViewerRoleProvider admits every PROVIDER-side role', () {
    // Only `independentMaster` can reach the screen today; the salon roles are
    // listed in the switch so the provider view lights up when those shells
    // ship rather than silently degrading to the client footer. Pinned so a
    // "dead branch" cleanup does not quietly remove them.
    const Map<UserRole, BookingViewerRole> expected =
        <UserRole, BookingViewerRole>{
          UserRole.independentMaster: BookingViewerRole.provider,
          UserRole.salonMaster: BookingViewerRole.provider,
          UserRole.salonAdmin: BookingViewerRole.provider,
          UserRole.salonOwner: BookingViewerRole.provider,
          UserRole.client: BookingViewerRole.client,
        };

    // Exhaustive by construction: a NEW `UserRole` added to the enum without a
    // decision recorded here fails this test rather than silently defaulting.
    test('the mapping covers every UserRole in the enum', () {
      expect(
        expected.keys.toSet(),
        UserRole.values.toSet(),
        reason:
            'a new UserRole was added — decide explicitly whether it is a '
            'provider-side role and add it to this table',
      );
    });

    for (final MapEntry<UserRole, BookingViewerRole> entry
        in expected.entries) {
      test('${entry.key.name} → ${entry.value.name}', () async {
        final ProviderContainer container = _containerWith(
          () => _StubAuth(
            AuthSession.authenticated(user: _user(entry.key), accessToken: 't'),
          ),
        );

        expect(await _resolve(container), entry.value);
      });
    }
  });
}
