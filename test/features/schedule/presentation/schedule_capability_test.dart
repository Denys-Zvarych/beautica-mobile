// Tests for [scheduleEditableProvider] (lib/features/schedule/presentation/
// schedule_capability.dart).
//
// mobile-security MEDIUM, phase 309–311 track (2026-09-06): before this
// file, NOTHING drove `scheduleEditableProvider` through an `AsyncError` or
// a stale-value `AsyncLoading` — the provider used the lenient `.value` read,
// which Riverpod 3's automatic `copyWithPrevious` (every `Notifier`/
// `AsyncNotifier` state transition, `riverpod-3.2.1/.../element.dart:66`)
// can keep pointing at a PREVIOUS settled `Authenticated` session across a
// later `AsyncLoading`/`AsyncError`. `scheduleEditable` is the write-gate for
// every schedule-mutation affordance across `MasterScheduleScreen`,
// `WeeklyTemplateEditorScreen`, `DayHoursSheet` and `ApplyScheduleSheet`, so
// that leniency is a real hazard: it can keep granting edit access after the
// session it was granted for is no longer definitely valid.
//
// The fix routes through `authUserRoleSettledOrNull` (auth_notifier.dart) —
// the concrete-subtype gate (`session is AsyncData<AuthSession>`), not
// `.value`.
//
// Phase 312, D8 — [scheduleEditableProvider] became MEMBERSHIP-AWARE: it now
// takes a [ScheduleScope] and, for SALON_OWNER/SALON_ADMIN, additionally
// proves the viewed master belongs to a salon the caller manages, instead of
// returning an unconditional `true` for that role pair. THIS FILE'S SECOND
// GROUP is the per-role-AND-per-membership matrix the phase's test-scope
// section requires: "owner of the master's salon → true; owner of a
// DIFFERENT salon → false; admin of the master's salon → true; admin
// elsewhere → false; the master themselves → false. A role-only matrix is
// the bug, not the test."
//
// Test matrix:
//   GROUP 1 — copyWithPrevious hardening (own scope):
//     1. AsyncError carrying a copyWithPrevious-attached previous
//        Authenticated(independentMaster) → false.
//     2. AsyncLoading with the same stale previous value → false.
//   GROUP 2 — settled-session role mapping (own scope):
//     3. AsyncData(Authenticated(independentMaster)) → true.
//     4. AsyncData(Authenticated(salonMaster)) → false.
//     5. AsyncData(Authenticated(client)) → false.
//     6. Unauthenticated → false.
//   GROUP 3 — owner/admin membership matrix (salonMaster scope, D8):
//     7. owner of the master's salon → true.
//     8. owner of a DIFFERENT salon → false.
//     9. admin of the master's salon → true.
//    10. admin of a DIFFERENT salon → false.
//    11. the master (SALON_MASTER role) themselves, viewing a salonMaster
//        scope naming their own masterId → false (the role switch alone
//        already excludes SALON_MASTER, but this pins the required case
//        explicitly rather than relying on that being incidental).
//    12. the viewed masterId is NOT on the resolved roster (a stray/foreign
//        id under a salon the owner genuinely manages) → false.
//    13. mySalonsProvider unresolved (AsyncLoading) for an owner → false —
//        deliberately the OPPOSITE of `salonManageGuard`'s route-guard
//        admit-while-unresolved fallback: this is the WRITE-GATE, so it
//        fails closed instead.
//    14. scope is `ScheduleScope.own` for an owner/admin session (should
//        never be constructed — `own_schedule_scope.dart`'s OQ-4 refusal —
//        but pinned here as a fail-closed backstop) → false.

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
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_capability.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _fakeAccessToken = 'test-access-token';

const String _kSalonId = 'salon-cap-1';
const String _kOtherSalonId = 'salon-cap-2';
const String _kMasterId = 'master-cap-1';

const _kSalon = Salon(id: _kSalonId, name: 'Capability Test Salon');
const _kOtherSalon = Salon(id: _kOtherSalonId, name: 'A Different Salon');

const _kMasterMember = SalonStaffMember(
  userId: 'user-cap-master-1',
  masterId: _kMasterId,
  role: SalonStaffRole.master,
  firstName: 'Тест',
  lastName: 'Майстер',
);

/// A resolved roster for [_kSalonId] containing [_kMasterMember] — the
/// "the viewed master IS on this salon's roster" fixture (fact 2).
const _kRosterWithMaster = (_kSalon, <SalonStaffMember>[_kMasterMember]);

/// A DIFFERENT master on [_kSalonId]'s roster — present so test 12's roster
/// is non-empty (an EMPTY roster would make `roster.any(...)` trivially
/// `false` regardless of whether the masterId comparison itself is real,
/// which would make a mutation that bypasses that comparison — matching on
/// role alone — invisible to the test).
const _kDecoyMasterMember = SalonStaffMember(
  userId: 'user-cap-decoy-1',
  masterId: 'master-cap-decoy',
  role: SalonStaffRole.master,
  firstName: 'Інший',
  lastName: 'Майстер',
);

/// A resolved roster for [_kSalonId] that does NOT contain [_kMasterId] —
/// test 12 (a stray/foreign masterId under a genuinely-managed salon) —
/// but DOES contain a DIFFERENT master, so the masterId comparison itself
/// is genuinely exercised (see [_kDecoyMasterMember]'s doc).
const _kRosterWithoutMaster = (
  _kSalon,
  <SalonStaffMember>[_kDecoyMasterMember],
);

User _userWith(UserRole role, {String? salonId}) => User(
  id: 'u-${role.name}',
  email: '${role.name}@beautica.ua',
  role: role,
  firstName: 'Тест',
  lastName: 'Юзер',
  salonId: salonId,
);

const ScheduleScope _ownScope = ScheduleScope.own(masterId: 'own-master-1');
const ScheduleScope _viewedMasterScope = ScheduleScope.salonMaster(
  salonId: _kSalonId,
  masterId: _kMasterId,
);

// ---------------------------------------------------------------------------
// AuthNotifier stubs
// ---------------------------------------------------------------------------

/// Resolves immediately to a fixed [AsyncValue<AuthSession>] — mirrors
/// `auth_selectors_test.dart`'s `_FixedAuthNotifier`.
class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);

  final AsyncValue<AuthSession> _fixed;

  @override
  Future<AuthSession> build() async {
    state = _fixed;
    return _fixed.value ?? const AuthSession.unauthenticated();
  }
}

/// Resolves immediately to an [Authenticated] session for [user].
class _AuthenticatedAs extends AuthNotifier {
  _AuthenticatedAs(this.user);
  final User user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: user, accessToken: _fakeAccessToken);
}

/// Settles to an [Authenticated] session for [user], then exposes
/// [forceError]/[forceLoading] to drive a REAL post-settle state transition
/// from the test body — same pattern as `auth_selectors_test.dart`'s
/// `_TransitionableAuthNotifier`, promoted here would be premature (single
/// consumer today); kept local per REUSE-FIRST's "additive, not speculative"
/// guidance.
class _TransitionableAuthNotifier extends AuthNotifier {
  _TransitionableAuthNotifier(this.user);
  final User user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: user, accessToken: _fakeAccessToken);

  /// The SAME `state = AsyncError(e, st)` shape production `AuthNotifier`
  /// uses (e.g. `auth_notifier.dart`'s `verifyEmail` catch block). Riverpod's
  /// own `asyncTransition` carries the previous settled `.value` FORWARD
  /// onto the resulting `AsyncError`.
  void forceError(Object error) {
    state = AsyncError<AuthSession>(error, StackTrace.current);
  }

  /// The mid-retry `AsyncLoading` shape: calling this immediately after
  /// [forceError] carries the PRIOR error's stale value forward too (same
  /// `asyncTransition` mechanism, via `onLoading`).
  void forceLoading() {
    state = const AsyncLoading<AuthSession>();
  }
}

// ---------------------------------------------------------------------------
// Salon-membership stubs (Phase 312, D8)
// ---------------------------------------------------------------------------

/// [MySalons] stub resolving IMMEDIATELY to [salons].
class _SettledMySalons extends MySalons {
  _SettledMySalons(this.salons);
  final List<Salon> salons;

  @override
  Future<List<Salon>> build() async => salons;
}

/// [MySalons] stub that NEVER settles — pins test 13's "unresolved →
/// fail-closed" case without a real Completer leaking across tests (the
/// container is disposed in `addTearDown` before anything could resolve it).
class _UnresolvedMySalons extends MySalons {
  @override
  Future<List<Salon>> build() => Completer<List<Salon>>().future;
}

/// Settles to [salons], then exposes [forceError] to drive a REAL
/// `copyWithPrevious`-carrying transition from the test body — same idiom
/// `_TransitionableAuthNotifier` above uses for `authProvider`. Test 15 uses
/// this to prove the owner arm gates on the concrete `AsyncData` SUBTYPE,
/// never a lenient `.value != null` read: a `.value != null` check would
/// still see the STALE pre-error salon list and wrongly admit.
class _TransitionableMySalons extends MySalons {
  _TransitionableMySalons(this.salons);
  final List<Salon> salons;

  @override
  Future<List<Salon>> build() async => salons;

  void forceError(Object error) {
    state = AsyncError<List<Salon>>(error, StackTrace.current);
  }
}

/// [SalonManagementProfile] stub resolving IMMEDIATELY to [data] for
/// whichever `salonId` is requested — every test in GROUP 3 only ever
/// resolves one salon, so a fixed value (ignoring the family key) is
/// sufficient and mirrors `salon_manage_route_guard_test.dart`'s
/// `_SettledSalonManagementProfile` precedent.
class _FixedRoster extends SalonManagementProfile {
  _FixedRoster(this.data);
  final SalonManagementProfileData data;

  @override
  Future<SalonManagementProfileData> build(String salonId) async => data;
}

/// Settles to [data], then exposes [forceError]/[forceLoading] to drive a
/// REAL `copyWithPrevious`-carrying transition from the test body — same
/// idiom as `_TransitionableMySalons` above, mirrored onto fact 2's provider
/// (`salonManagementProfileProvider`) rather than fact 1's
/// (`mySalonsProvider`). Fact 1 already has this hardening (tests 1/2 for
/// `authProvider`, test 15 for `mySalonsProvider`); fact 2's own
/// `rosterAsync is! AsyncData<...>` gate
/// (`schedule_capability.dart:140`) had none before this.
class _TransitionableRoster extends SalonManagementProfile {
  _TransitionableRoster(this.data);
  final SalonManagementProfileData data;

  @override
  Future<SalonManagementProfileData> build(String salonId) async => data;

  void forceError(Object error) {
    state = AsyncError<SalonManagementProfileData>(error, StackTrace.current);
  }

  void forceLoading() {
    state = const AsyncLoading<SalonManagementProfileData>();
  }
}

// ---------------------------------------------------------------------------
// Container factories
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer(AsyncValue<AuthSession> authState) {
  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: [
      authProvider.overrideWith(() => _FixedAuthNotifier(authState)),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

// `Override` is not a publicly exported riverpod type (see
// `test/helpers/pump_app.dart`'s identical note) — [extraOverrides] is left
// untyped (`List<dynamic>`) and `.cast()` at the splice point, mirroring that
// file's precedent, so callers can pass a plain override list without
// importing the internal type.
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
  group(
    'scheduleEditableProvider — copyWithPrevious hardening (own scope)',
    () {
      // -------------------------------------------------------------------
      // Test 1 — THE ONE THAT MATTERS.
      // -------------------------------------------------------------------
      test('an Authenticated(independentMaster) session that TRANSITIONS to '
          'AsyncError resolves scheduleEditable=false — NOT the stale '
          'carried-forward role', () async {
        final notifier = _TransitionableAuthNotifier(
          _userWith(UserRole.independentMaster),
        );
        final container = _makeContainerFor(notifier);
        await container.read(authProvider.future);
        // Sanity: the settled session reads editable=true BEFORE the
        // transition — otherwise this test could pass for the wrong reason.
        expect(container.read(scheduleEditableProvider(_ownScope)), isTrue);

        notifier.forceError(const NetworkFailure());
        final AsyncValue<AuthSession> afterError = container.read(authProvider);
        // Prove the trap is real before asserting the fix: Riverpod's own
        // copyWithPrevious carries the stale Authenticated value forward
        // onto the AsyncError.
        expect(afterError.hasError, isTrue);
        expect(
          afterError.value,
          isNotNull,
          reason:
              'sanity: if .value were null here, scheduleEditable would '
              'read false for a DIFFERENT reason (no stale value to leak) '
              'and this test would not be pinning the actual bug',
        );

        expect(
          container.read(scheduleEditableProvider(_ownScope)),
          isFalse,
          reason:
              'must fail closed (read-only) on AsyncError even though '
              '.value still reports the stale '
              'Authenticated(independentMaster) session',
        );
      });

      // -------------------------------------------------------------------
      // Test 2 — the AsyncLoading(retrying) shape.
      // -------------------------------------------------------------------
      test('AsyncLoading carrying the same stale previous value resolves '
          'scheduleEditable=false', () async {
        final notifier = _TransitionableAuthNotifier(
          _userWith(UserRole.independentMaster),
        );
        final container = _makeContainerFor(notifier);
        await container.read(authProvider.future);

        notifier.forceError(const NetworkFailure());
        notifier.forceLoading();
        final AsyncValue<AuthSession> midRetry = container.read(authProvider);
        // Pin the shape itself, not just the outcome —
        // `project_asyncvalue_haserror_retrying_trap`: a test asserting only
        // `hasError`/`error` cannot distinguish this from a terminal
        // AsyncError.
        expect(midRetry, isA<AsyncLoading<AuthSession>>());
        expect(
          midRetry.value,
          isNotNull,
          reason: 'sanity: the stale value must actually be riding along',
        );

        expect(container.read(scheduleEditableProvider(_ownScope)), isFalse);
      });
    },
  );

  group(
    'scheduleEditableProvider — settled-session role mapping (own scope)',
    () {
      // -------------------------------------------------------------------
      // Test 3 — positive counterpart to test 1.
      // -------------------------------------------------------------------
      test('AsyncData(Authenticated(independentMaster)) → true', () async {
        final container = _makeContainerFor(
          _AuthenticatedAs(_userWith(UserRole.independentMaster)),
        );
        await container.read(authProvider.future);

        expect(container.read(scheduleEditableProvider(_ownScope)), isTrue);
      });

      // -------------------------------------------------------------------
      // Test 4 — required negative case.
      // -------------------------------------------------------------------
      test('AsyncData(Authenticated(salonMaster)) → false', () async {
        final container = _makeContainerFor(
          _AuthenticatedAs(_userWith(UserRole.salonMaster)),
        );
        await container.read(authProvider.future);

        expect(container.read(scheduleEditableProvider(_ownScope)), isFalse);
      });

      test('AsyncData(Authenticated(client)) → false', () async {
        final container = _makeContainerFor(
          _AuthenticatedAs(_userWith(UserRole.client)),
        );
        await container.read(authProvider.future);

        expect(container.read(scheduleEditableProvider(_ownScope)), isFalse);
      });

      test('Unauthenticated session → false', () async {
        final container = _makeContainer(
          const AsyncData<AuthSession>(AuthSession.unauthenticated()),
        );
        await container.read(authProvider.future);

        expect(container.read(scheduleEditableProvider(_ownScope)), isFalse);
      });
    },
  );

  group('scheduleEditableProvider — owner/admin membership matrix '
      '(salonMaster scope, Phase 312 D8)', () {
    // ---------------------------------------------------------------
    // Test 7 — owner of the master's salon → true.
    // ---------------------------------------------------------------
    test('SALON_OWNER managing the viewed master\'s salon → true', () async {
      final container = _makeContainerFor(
        _AuthenticatedAs(_userWith(UserRole.salonOwner)),
        extraOverrides: [
          mySalonsProvider.overrideWith(
            () => _SettledMySalons(const <Salon>[_kSalon]),
          ),
          salonManagementProfileProvider.overrideWith(
            () => _FixedRoster(_kRosterWithMaster),
          ),
        ],
      );
      await container.read(authProvider.future);
      // Settle BOTH async facts before asserting — `container.read` on the
      // sync `scheduleEditableProvider` reads whatever state these two are
      // in AT THAT INSTANT, and neither has been watched/triggered before
      // this line, so an un-awaited read would see AsyncLoading (→ false)
      // and this "→ true" case would pass for the wrong reason.
      await container.read(mySalonsProvider.future);
      await container.read(salonManagementProfileProvider(_kSalonId).future);

      expect(
        container.read(scheduleEditableProvider(_viewedMasterScope)),
        isTrue,
      );
    });

    // ---------------------------------------------------------------
    // Test 8 — owner of a DIFFERENT salon → false.
    // ---------------------------------------------------------------
    test('SALON_OWNER of a DIFFERENT salon → false', () async {
      final container = _makeContainerFor(
        _AuthenticatedAs(_userWith(UserRole.salonOwner)),
        extraOverrides: [
          // The owner's OWN salon list never contains `_kSalonId` — the
          // salon the viewed master actually belongs to.
          mySalonsProvider.overrideWith(
            () => _SettledMySalons(const <Salon>[_kOtherSalon]),
          ),
          salonManagementProfileProvider.overrideWith(
            () => _FixedRoster(_kRosterWithMaster),
          ),
        ],
      );
      await container.read(authProvider.future);
      await container.read(mySalonsProvider.future);
      // Settle fact 2 (roster membership) as well, so this test isolates
      // fact 1 (salon ownership) as the ONLY unsettled/failing condition —
      // otherwise an unawaited `salonManagementProfileProvider` reading
      // AsyncLoading would ALSO produce `false`, for the wrong reason,
      // and a bug that bypasses fact 1 entirely would slip through this
      // test undetected.
      await container.read(salonManagementProfileProvider(_kSalonId).future);

      expect(
        container.read(scheduleEditableProvider(_viewedMasterScope)),
        isFalse,
      );
    });

    // ---------------------------------------------------------------
    // Test 9 — admin of the master's salon → true.
    // ---------------------------------------------------------------
    test('SALON_ADMIN of the viewed master\'s salon → true', () async {
      final container = _makeContainerFor(
        _AuthenticatedAs(_userWith(UserRole.salonAdmin, salonId: _kSalonId)),
        extraOverrides: [
          salonManagementProfileProvider.overrideWith(
            () => _FixedRoster(_kRosterWithMaster),
          ),
        ],
      );
      await container.read(authProvider.future);
      await container.read(salonManagementProfileProvider(_kSalonId).future);

      expect(
        container.read(scheduleEditableProvider(_viewedMasterScope)),
        isTrue,
      );
    });

    // ---------------------------------------------------------------
    // Test 10 — admin of a DIFFERENT salon → false.
    // ---------------------------------------------------------------
    test('SALON_ADMIN of a DIFFERENT salon → false', () async {
      final container = _makeContainerFor(
        _AuthenticatedAs(
          _userWith(UserRole.salonAdmin, salonId: _kOtherSalonId),
        ),
        extraOverrides: [
          salonManagementProfileProvider.overrideWith(
            () => _FixedRoster(_kRosterWithMaster),
          ),
        ],
      );
      await container.read(authProvider.future);
      // Settle fact 2 (roster membership, which DOES match here) so this
      // test isolates fact 1 (salon-id equality) as the only failing
      // condition — otherwise an unawaited roster read (AsyncLoading)
      // would ALSO produce `false`, for the wrong reason.
      await container.read(salonManagementProfileProvider(_kSalonId).future);

      expect(
        container.read(scheduleEditableProvider(_viewedMasterScope)),
        isFalse,
      );
    });

    // ---------------------------------------------------------------
    // Test 11 — the master themselves (SALON_MASTER role) viewing a
    // salonMaster scope naming their own masterId → false. The role
    // switch alone already excludes SALON_MASTER regardless of scope
    // shape; this pins the phase's explicitly-required case rather than
    // leaving it merely incidental.
    // ---------------------------------------------------------------
    test('SALON_MASTER viewing a salonMaster scope naming themselves → '
        'false', () async {
      final container = _makeContainerFor(
        _AuthenticatedAs(_userWith(UserRole.salonMaster)),
        extraOverrides: [
          salonManagementProfileProvider.overrideWith(
            () => _FixedRoster(_kRosterWithMaster),
          ),
        ],
      );
      await container.read(authProvider.future);
      // Settle fact 2 (roster membership, which DOES match — the master
      // IS themselves on the roster) so this test isolates the ROLE GATE
      // itself as the only thing standing between a SALON_MASTER and
      // edit access — the scenario the phase's mutation list names
      // explicitly: "the master themselves → false".
      await container.read(salonManagementProfileProvider(_kSalonId).future);

      expect(
        container.read(scheduleEditableProvider(_viewedMasterScope)),
        isFalse,
      );
    });

    // ---------------------------------------------------------------
    // Test 12 — a masterId that is NOT on the resolved roster, even
    // though the caller genuinely manages the salon — a role-and-salon-
    // only check would wrongly admit this; the roster scan must reject
    // it.
    // ---------------------------------------------------------------
    test('owner of the salon, but the viewed masterId is not on its '
        'roster → false', () async {
      final container = _makeContainerFor(
        _AuthenticatedAs(_userWith(UserRole.salonOwner)),
        extraOverrides: [
          mySalonsProvider.overrideWith(
            () => _SettledMySalons(const <Salon>[_kSalon]),
          ),
          salonManagementProfileProvider.overrideWith(
            () => _FixedRoster(_kRosterWithoutMaster),
          ),
        ],
      );
      await container.read(authProvider.future);
      await container.read(mySalonsProvider.future);
      await container.read(salonManagementProfileProvider(_kSalonId).future);

      expect(
        container.read(scheduleEditableProvider(_viewedMasterScope)),
        isFalse,
      );
    });

    // ---------------------------------------------------------------
    // Test 13 — mySalonsProvider UNRESOLVED for an owner → false.
    // Deliberately the OPPOSITE of `salonManageGuard`'s route-guard
    // admit-while-unresolved fallback (that guard is a UX convenience;
    // this provider is the actual write-gate and must fail closed).
    // ---------------------------------------------------------------
    test(
      'SALON_OWNER with mySalonsProvider still unresolved → false',
      () async {
        final container = _makeContainerFor(
          _AuthenticatedAs(_userWith(UserRole.salonOwner)),
          extraOverrides: [
            mySalonsProvider.overrideWith(_UnresolvedMySalons.new),
            salonManagementProfileProvider.overrideWith(
              () => _FixedRoster(_kRosterWithMaster),
            ),
          ],
        );
        await container.read(authProvider.future);

        expect(
          container.read(scheduleEditableProvider(_viewedMasterScope)),
          isFalse,
        );
      },
    );

    // ---------------------------------------------------------------
    // Test 14 — an owner/admin session viewing `ScheduleScope.own`
    // (should never be constructed for these roles — OQ-4 — but must
    // fail closed as a backstop rather than crash or admit).
    // ---------------------------------------------------------------
    test('SALON_OWNER viewing ScheduleScope.own → false', () async {
      final container = _makeContainerFor(
        _AuthenticatedAs(_userWith(UserRole.salonOwner)),
        extraOverrides: [
          mySalonsProvider.overrideWith(
            () => _SettledMySalons(const <Salon>[_kSalon]),
          ),
        ],
      );
      await container.read(authProvider.future);

      expect(container.read(scheduleEditableProvider(_ownScope)), isFalse);
    });

    // ---------------------------------------------------------------
    // Test 15 — mySalonsProvider TRANSITIONS to AsyncError carrying a
    // copyWithPrevious-attached stale (previously-resolved) salon list →
    // still false. Pins the `is! AsyncData<List<Salon>>` SUBTYPE gate
    // against the exact weakening the phase's mutation list calls out:
    // "mySalonsProvider gate weakened to `.value != null` → stale-data
    // admit". A `.value != null` read would still see the pre-error
    // `[_kSalon]` list and wrongly admit; only the concrete-subtype check
    // fails closed here.
    // ---------------------------------------------------------------
    test('SALON_OWNER whose mySalonsProvider TRANSITIONS to AsyncError '
        'carrying a stale (previously resolved, matching) salon list → '
        'still false', () async {
      final notifier = _TransitionableMySalons(const <Salon>[_kSalon]);
      final container = _makeContainerFor(
        _AuthenticatedAs(_userWith(UserRole.salonOwner)),
        extraOverrides: [
          mySalonsProvider.overrideWith(() => notifier),
          salonManagementProfileProvider.overrideWith(
            () => _FixedRoster(_kRosterWithMaster),
          ),
        ],
      );
      await container.read(authProvider.future);
      await container.read(mySalonsProvider.future);
      await container.read(salonManagementProfileProvider(_kSalonId).future);
      // Sanity: editable BEFORE the transition, and the salon list is
      // genuinely a match — otherwise this test could pass for the
      // wrong reason.
      expect(
        container.read(scheduleEditableProvider(_viewedMasterScope)),
        isTrue,
      );

      notifier.forceError(const NetworkFailure());
      final AsyncValue<List<Salon>> afterError = container.read(
        mySalonsProvider,
      );
      expect(afterError.hasError, isTrue);
      expect(
        afterError.value,
        isNotNull,
        reason:
            'sanity: if .value were null here, the mutation this test '
            'exists to catch (.value != null) would ALSO read false, '
            'and this test would not be pinning anything',
      );

      expect(
        container.read(scheduleEditableProvider(_viewedMasterScope)),
        isFalse,
        reason:
            'must fail closed even though .value still reports the '
            'stale, matching salon list',
      );
    });

    // ---------------------------------------------------------------
    // Test 16 — mobile-qa gap-closure (branch QA audit): fact 2's OWN
    // `rosterAsync is! AsyncData<...>` gate (`schedule_capability.dart:140`)
    // had no equivalent to test 15's hardening. The audit mutated that gate
    // to a lenient `.value != null` read and all 15 prior tests stayed
    // green — this is the proof. Mirrors test 15's shape exactly, but
    // transitions `salonManagementProfileProvider` (fact 2) instead of
    // `mySalonsProvider` (fact 1), with fact 1 held settled and genuinely
    // matching throughout so ONLY fact 2's gate is under test.
    // ---------------------------------------------------------------
    test('SALON_OWNER whose salonManagementProfileProvider TRANSITIONS to '
        'AsyncError carrying a stale (previously resolved, matching) '
        'roster → still false', () async {
      final rosterNotifier = _TransitionableRoster(_kRosterWithMaster);
      final container = _makeContainerFor(
        _AuthenticatedAs(_userWith(UserRole.salonOwner)),
        extraOverrides: [
          mySalonsProvider.overrideWith(
            () => _SettledMySalons(const <Salon>[_kSalon]),
          ),
          salonManagementProfileProvider.overrideWith(() => rosterNotifier),
        ],
      );
      await container.read(authProvider.future);
      await container.read(mySalonsProvider.future);
      await container.read(salonManagementProfileProvider(_kSalonId).future);
      // Sanity: editable BEFORE the transition, and the roster genuinely
      // contains the viewed master — otherwise this test could pass for
      // the wrong reason.
      expect(
        container.read(scheduleEditableProvider(_viewedMasterScope)),
        isTrue,
      );

      rosterNotifier.forceError(const NetworkFailure());
      final AsyncValue<SalonManagementProfileData> afterError = container.read(
        salonManagementProfileProvider(_kSalonId),
      );
      expect(afterError.hasError, isTrue);
      expect(
        afterError.value,
        isNotNull,
        reason:
            'sanity: if .value were null here, the mutation this test '
            'exists to catch (.value != null) would ALSO read false, '
            'and this test would not be pinning anything',
      );

      expect(
        container.read(scheduleEditableProvider(_viewedMasterScope)),
        isFalse,
        reason:
            'must fail closed even though .value still reports the '
            'stale, matching roster',
      );
    });

    // ---------------------------------------------------------------
    // Test 17 — the AsyncLoading(retrying) shape of test 16, mirroring
    // GROUP 1's test 2. `AsyncLoading(retrying: true)` satisfies
    // `hasError`/carries `.value` forward too — pinning the concrete
    // subtype, not just an outcome, per
    // `project_asyncvalue_haserror_retrying_trap`.
    // ---------------------------------------------------------------
    test('SALON_OWNER whose salonManagementProfileProvider is mid-retry '
        '(AsyncLoading) carrying the same stale matching roster → still '
        'false', () async {
      final rosterNotifier = _TransitionableRoster(_kRosterWithMaster);
      final container = _makeContainerFor(
        _AuthenticatedAs(_userWith(UserRole.salonOwner)),
        extraOverrides: [
          mySalonsProvider.overrideWith(
            () => _SettledMySalons(const <Salon>[_kSalon]),
          ),
          salonManagementProfileProvider.overrideWith(() => rosterNotifier),
        ],
      );
      await container.read(authProvider.future);
      await container.read(mySalonsProvider.future);
      await container.read(salonManagementProfileProvider(_kSalonId).future);

      rosterNotifier.forceError(const NetworkFailure());
      rosterNotifier.forceLoading();
      final AsyncValue<SalonManagementProfileData> midRetry = container.read(
        salonManagementProfileProvider(_kSalonId),
      );
      expect(midRetry, isA<AsyncLoading<SalonManagementProfileData>>());
      expect(
        midRetry.value,
        isNotNull,
        reason: 'sanity: the stale roster must actually be riding along',
      );

      expect(
        container.read(scheduleEditableProvider(_viewedMasterScope)),
        isFalse,
      );
    });
  });
}
