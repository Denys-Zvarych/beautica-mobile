// Tests for [canManageSalonProvider]
// (lib/features/salon/application/salon_manage_capability.dart).
//
// Phase 322 (D1/D2/D4) — this predicate is the ONE salon-scoped "can this
// viewer manage this salon" gate every widened service-management affordance
// (`_SalonManageServicesListRoute`/`_SalonManageServiceEditRoute` in
// `app_router.dart`) reads. It is a PROMOTION of `schedule_capability.dart`'s
// former private `_managesSalon` — see `schedule_capability_test.dart`'s own
// GROUP 3 for that predicate's ORIGINAL matrix (kept, unedited, proving the
// promotion changed nothing observable there). This file pins the phase's
// required five-row role matrix directly against the promoted provider:
//
//   1. SALON_OWNER of this salon                  → true.
//   2. SALON_ADMIN of this salon                   → true (identical).
//   3. SALON_ADMIN of a DIFFERENT salon             → false (D4 — the salon
//      scoping, not a bare role check).
//   4. SALON_MASTER                                 → false (D3).
//   5. CLIENT                                       → false.
//
// Plus the fail-closed edge cases [schedule_capability_test.dart] already
// established for the ORIGINAL `_managesSalon` and which this promotion must
// preserve: an owner whose `mySalonsProvider` has not resolved yet, and an
// owner whose `mySalonsProvider` carries a stale value forward onto a later
// `AsyncError` (`copyWithPrevious`).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_manage_capability.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Fixtures — mirrors `schedule_capability_test.dart`'s exact shape (same
// GROUP 3 fixtures this predicate was promoted out of), REUSE-FIRST inside
// this file's own scope rather than importing the sibling test file's
// private helpers (test files do not export across files in this repo's
// convention — `salon_manage_route_guard_test.dart` and
// `schedule_capability_test.dart` both keep their own local copies of this
// exact shape).
// ---------------------------------------------------------------------------

const _fakeAccessToken = 'test-access-token';

const String _kSalonId = 'salon-cap-1';
const String _kOtherSalonId = 'salon-cap-2';

const _kSalon = Salon(id: _kSalonId, name: 'Capability Test Salon');

User _userWith(UserRole role, {String? salonId}) => User(
  id: 'u-${role.name}',
  email: '${role.name}@beautica.ua',
  role: role,
  firstName: 'Тест',
  lastName: 'Юзер',
  salonId: salonId,
);

/// Resolves immediately to an [Authenticated] session for [user].
class _AuthenticatedAs extends AuthNotifier {
  _AuthenticatedAs(this.user);
  final User user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: user, accessToken: _fakeAccessToken);
}

/// [MySalons] stub resolving IMMEDIATELY to [salons].
class _SettledMySalons extends MySalons {
  _SettledMySalons(this.salons);
  final List<Salon> salons;

  @override
  Future<List<Salon>> build() async => salons;
}

/// [MySalons] stub that NEVER settles — the "owner, mySalonsProvider still
/// unresolved → fail closed" edge case.
class _UnresolvedMySalons extends MySalons {
  @override
  Future<List<Salon>> build() => Completer<List<Salon>>().future;
}

/// Settles to [salons], then exposes [forceError] to drive a REAL
/// `copyWithPrevious`-carrying transition from the test body.
class _TransitionableMySalons extends MySalons {
  _TransitionableMySalons(this.salons);
  final List<Salon> salons;

  @override
  Future<List<Salon>> build() async => salons;

  void forceError(Object error) {
    state = AsyncError<List<Salon>>(error, StackTrace.current);
  }
}

ProviderContainer _makeContainerFor(
  AuthNotifier notifier, {
  List<dynamic> extraOverrides = const [],
}) {
  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: [
      authProvider.overrideWith(() => notifier),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
      // ignore: avoid_dynamic_calls
      ...extraOverrides.cast(),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('canManageSalonProvider — phase 322 five-row role matrix', () {
    // -----------------------------------------------------------------
    // Row 1 — SALON_OWNER of this salon → true.
    // -----------------------------------------------------------------
    test('SALON_OWNER of this salon → true (present and functional)', () async {
      final container = _makeContainerFor(
        _AuthenticatedAs(_userWith(UserRole.salonOwner)),
        extraOverrides: [
          mySalonsProvider.overrideWith(
            () => _SettledMySalons(const <Salon>[_kSalon]),
          ),
        ],
      );
      await container.read(authProvider.future);
      await container.read(mySalonsProvider.future);

      expect(container.read(canManageSalonProvider(_kSalonId)), isTrue);
    });

    // -----------------------------------------------------------------
    // Row 2 — SALON_ADMIN of this salon → true, IDENTICAL to row 1.
    // -----------------------------------------------------------------
    test(
      'SALON_ADMIN of this salon → true — identical to the owner row',
      () async {
        final container = _makeContainerFor(
          _AuthenticatedAs(_userWith(UserRole.salonAdmin, salonId: _kSalonId)),
        );
        await container.read(authProvider.future);

        expect(container.read(canManageSalonProvider(_kSalonId)), isTrue);
      },
    );

    // -----------------------------------------------------------------
    // Row 3 — SALON_ADMIN of a DIFFERENT salon → false. THE ONE THAT
    // MATTERS (D4): a bare role check (`role == salonAdmin`) would pass
    // this admin on ANY salonId — mutation check 2 flips exactly this
    // arm's scoping and expects this row to go RED.
    // -----------------------------------------------------------------
    test('SALON_ADMIN of a DIFFERENT salon → false — a bounce, not a widening '
        '(D4)', () async {
      final container = _makeContainerFor(
        _AuthenticatedAs(
          _userWith(UserRole.salonAdmin, salonId: _kOtherSalonId),
        ),
      );
      await container.read(authProvider.future);

      expect(container.read(canManageSalonProvider(_kSalonId)), isFalse);
    });

    // -----------------------------------------------------------------
    // Row 4 — SALON_MASTER → false (D3: gains nothing).
    // -----------------------------------------------------------------
    test('SALON_MASTER → false — gains nothing (D3)', () async {
      final container = _makeContainerFor(
        _AuthenticatedAs(_userWith(UserRole.salonMaster, salonId: _kSalonId)),
      );
      await container.read(authProvider.future);

      expect(container.read(canManageSalonProvider(_kSalonId)), isFalse);
    });

    // -----------------------------------------------------------------
    // Row 5 — CLIENT → false.
    // -----------------------------------------------------------------
    test('CLIENT → false', () async {
      final container = _makeContainerFor(
        _AuthenticatedAs(_userWith(UserRole.client)),
      );
      await container.read(authProvider.future);

      expect(container.read(canManageSalonProvider(_kSalonId)), isFalse);
    });
  });

  group('canManageSalonProvider — fail-closed edge cases (preserved from '
      'the pre-promotion _managesSalon matrix)', () {
    test(
      'SALON_OWNER whose mySalonsProvider is still UNRESOLVED → false',
      () async {
        final container = _makeContainerFor(
          _AuthenticatedAs(_userWith(UserRole.salonOwner)),
          extraOverrides: [
            mySalonsProvider.overrideWith(_UnresolvedMySalons.new),
          ],
        );
        await container.read(authProvider.future);

        expect(container.read(canManageSalonProvider(_kSalonId)), isFalse);
      },
    );

    test(
      'SALON_OWNER whose mySalonsProvider TRANSITIONS to AsyncError carrying '
      'a stale (previously resolved, matching) salon list → still false',
      () async {
        final notifier = _TransitionableMySalons(const <Salon>[_kSalon]);
        final container = _makeContainerFor(
          _AuthenticatedAs(_userWith(UserRole.salonOwner)),
          extraOverrides: [mySalonsProvider.overrideWith(() => notifier)],
        );
        await container.read(authProvider.future);
        await container.read(mySalonsProvider.future);
        // Sanity: true before the transition.
        expect(container.read(canManageSalonProvider(_kSalonId)), isTrue);

        notifier.forceError(const NetworkFailure());
        final AsyncValue<List<Salon>> afterError = container.read(
          mySalonsProvider,
        );
        // Prove the trap is real: copyWithPrevious carries the stale
        // matching list forward onto the AsyncError.
        expect(afterError.hasError, isTrue);
        expect(afterError.value, const <Salon>[_kSalon]);

        expect(container.read(canManageSalonProvider(_kSalonId)), isFalse);
      },
    );
  });
}
