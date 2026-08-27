// Phase 267 — unit tests for [SalonBookingDraft] (D2-D6, H-1, P-1, P-2).
//
// Pure-Dart provider units: no widget tree. Each test builds a FRESH
// [ProviderContainer] (disposed in addTearDown) so keepAlive state never
// leaks between cases. The notifier holds no Dio and no repository.
//
// H-1 (mobile-security HIGH, 2026-08-22): [SalonBookingDraft.build] now
// `ref.watch`es the authenticated identity (see the notifier's file header),
// so EVERY container in this file must override `authProvider` with a
// settable stub — a bare `ProviderContainer()` would otherwise construct the
// REAL `AuthNotifier`, which touches `SecureStorage` (unoverridden in a pure
// unit test) the instant the identity slice is read. `_boot` centralises
// that; `_make` is the thin synchronous-shaped wrapper the pre-H-1 tests
// already used, now backed by a default authenticated session so none of
// their bodies had to change shape.
//
// D2 fixture note: [_serviceDefIdNails] and [_masterServiceIdNails] are
// deliberately VISIBLY DISTINCT literal strings, not two random UUIDs that
// merely happen to differ — see `salon_service_booking_test.dart`'s matching
// note.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/salon_booking_draft_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/salon_service_booking.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const String _salonId = 'salon-1';
const String _serviceDefIdNails = 'svcdef-nails-001';
const String _masterServiceIdNails = 'msvc-anna-nails-001';

const String _serviceDefIdBrows = 'svcdef-brows-002';
const String _masterServiceIdBrows = 'msvc-anna-brows-002';

const SalonCatalogService _nailsService = SalonCatalogService(
  id: _serviceDefIdNails,
  name: 'Манікюр класичний',
  durationLabel: '1 год',
  priceDisplay: '500 ₴',
);

const SalonCatalogService _browsService = SalonCatalogService(
  id: _serviceDefIdBrows,
  name: 'Корекція брів',
  durationLabel: '30 хв',
  priceDisplay: '300 ₴',
);

const SalonMasterSummary _master = SalonMasterSummary(
  masterId: 'master-anna-1',
  firstName: 'Анна',
  lastName: 'Коваль',
  type: MasterType.salonMaster,
);

const User _clientA = User(
  id: 'user-a',
  email: 'a@example.com',
  role: UserRole.client,
);

const User _clientB = User(
  id: 'user-b',
  email: 'b@example.com',
  role: UserRole.client,
);

AsyncValue<AuthSession> _sessionFor(User user, {String token = 'tok-1'}) =>
    AsyncData<AuthSession>(
      AuthSession.authenticated(user: user, accessToken: token),
    );

const AsyncValue<AuthSession> _loggedOut = AsyncData<AuthSession>(
  AuthSession.unauthenticated(),
);

/// [AuthNotifier] stub whose session can be flipped mid-test — the only way
/// to drive a real logout / account switch / silent token refresh through
/// the ordinary Riverpod cascade rather than simulating one. Mirrors
/// `client_review_signal_provider_test.dart`'s identical fixture, which
/// covers the same `keepAlive` + `authProvider.select(id)` shape.
class _SettableAuthNotifier extends AuthNotifier {
  _SettableAuthNotifier(this._initial);

  final AsyncValue<AuthSession> _initial;

  @override
  Future<AuthSession> build() async {
    return _initial.value ?? const AuthSession.unauthenticated();
  }

  void emit(AsyncValue<AuthSession> next) => state = next;
}

/// Builds a container with a flippable auth session and returns it plus the
/// stub notifier. Defaults to an authenticated session (`_clientA`) so
/// pre-H-1 test bodies — which never cared about auth — still get one
/// without having to name it.
Future<(ProviderContainer, _SettableAuthNotifier)> _boot([
  AsyncValue<AuthSession>? initial,
]) async {
  late _SettableAuthNotifier auth;
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() {
        auth = _SettableAuthNotifier(initial ?? _sessionFor(_clientA));
        return auth;
      }),
    ],
  );
  addTearDown(container.dispose);
  // Settle `build()`'s future so a later `emit` is not overwritten by the
  // notifier's own initial resolution.
  await container.read(authProvider.future);
  return (container, auth);
}

Future<ProviderContainer> _make() async {
  final (ProviderContainer c, _) = await _boot();
  return c;
}

SalonBookingDraft _notifier(ProviderContainer c) =>
    c.read(salonBookingDraftProvider.notifier);

SalonBookingDraftState _state(ProviderContainer c) =>
    c.read(salonBookingDraftProvider);

void main() {
  group('initial state', () {
    test('starts empty with no salonId', () async {
      final c = await _make();

      expect(_state(c).salonId, isNull);
      expect(_state(c).entries, isEmpty);
    });
  });

  group('selectServices', () {
    test('seeds one unassigned entry per selected catalogue service, in '
        'order', () async {
      final c = await _make();

      _notifier(c).selectServices(
        salonId: _salonId,
        services: <SalonCatalogService>[_nailsService, _browsService],
      );

      final state = _state(c);
      expect(state.salonId, _salonId);
      expect(state.entries, hasLength(2));
      expect(state.entries[0].serviceDefId, _serviceDefIdNails);
      expect(state.entries[1].serviceDefId, _serviceDefIdBrows);
      expect(state.entries[0].masterId, isNull);
      expect(state.entries[0].masterServiceId, isNull);
    });

    test('D6: throws ArgumentError for an 11th service — never silently '
        'truncates', () async {
      final c = await _make();
      final elevenServices = List<SalonCatalogService>.generate(
        11,
        (int i) => SalonCatalogService(
          id: 'svcdef-$i',
          name: 'Service $i',
          durationLabel: '30 хв',
          priceDisplay: '100 ₴',
        ),
      );

      expect(
        () => _notifier(
          c,
        ).selectServices(salonId: _salonId, services: elevenServices),
        throwsArgumentError,
      );
    });

    test('D6: accepts exactly the cap (10 services)', () async {
      final c = await _make();
      final tenServices = List<SalonCatalogService>.generate(
        10,
        (int i) => SalonCatalogService(
          id: 'svcdef-$i',
          name: 'Service $i',
          durationLabel: '30 хв',
          priceDisplay: '100 ₴',
        ),
      );

      _notifier(c).selectServices(salonId: _salonId, services: tenServices);

      expect(_state(c).entries, hasLength(10));
    });
  });

  group('assignMaster', () {
    test(
      'should_setMasterIdAndMasterServiceIdTogether_when_aServiceIsAssigned',
      () async {
        final c = await _make();
        _notifier(c).selectServices(
          salonId: _salonId,
          services: <SalonCatalogService>[_nailsService],
        );
        // Before assignment: both null, never one of each.
        final before = _state(c).entryFor(_serviceDefIdNails)!;
        expect(before.masterId, isNull);
        expect(before.masterServiceId, isNull);

        _notifier(c).assignMaster(
          serviceDefId: _serviceDefIdNails,
          masterId: _master.masterId,
          masterServiceId: _masterServiceIdNails,
          master: _master,
          durationMinutes: 60,
        );

        final after = _state(c).entryFor(_serviceDefIdNails)!;
        expect(after.masterId, isNotNull);
        expect(after.masterServiceId, isNotNull);
        expect(after.masterId, _master.masterId);
        expect(
          after.masterServiceId,
          _masterServiceIdNails,
          reason: 'must carry the ASSIGNMENT id, not serviceDefId — D2',
        );
        expect(after.masterServiceId, isNot(_serviceDefIdNails));
        expect(after.master, _master);
        expect(after.durationMinutes, 60);
      },
    );

    test('leaves other entries untouched', () async {
      final c = await _make();
      _notifier(c).selectServices(
        salonId: _salonId,
        services: <SalonCatalogService>[_nailsService, _browsService],
      );

      _notifier(c).assignMaster(
        serviceDefId: _serviceDefIdNails,
        masterId: _master.masterId,
        masterServiceId: _masterServiceIdNails,
        master: _master,
      );

      final brows = _state(c).entryFor(_serviceDefIdBrows)!;
      expect(brows.masterId, isNull);
      expect(brows.masterServiceId, isNull);
    });

    test(
      // M-2: Phase 276 owns minting `idempotencyKey`. Neither
      // `selectServices` nor `assignMaster` may set it — pin that so a
      // future edit threading a key through `copyWith` here breaks visibly.
      'M-2: idempotencyKey stays null through selectServices -> assignMaster',
      () async {
        final c = await _make();
        _notifier(c).selectServices(
          salonId: _salonId,
          services: <SalonCatalogService>[_nailsService],
        );
        expect(_state(c).entryFor(_serviceDefIdNails)!.idempotencyKey, isNull);

        _notifier(c).assignMaster(
          serviceDefId: _serviceDefIdNails,
          masterId: _master.masterId,
          masterServiceId: _masterServiceIdNails,
          master: _master,
          durationMinutes: 60,
        );

        expect(
          _state(c).entryFor(_serviceDefIdNails)!.idempotencyKey,
          isNull,
          reason:
              'idempotencyKey minting is Phase 276 — this phase must never '
              'set it',
        );
      },
    );
  });

  group('order preservation', () {
    test(
      'should_preserveServiceOrder_when_entriesAreUpdatedIndividually',
      () async {
        final c = await _make();
        _notifier(c).selectServices(
          salonId: _salonId,
          services: <SalonCatalogService>[_nailsService, _browsService],
        );

        // Update the SECOND-listed entry first, then the first-listed one —
        // update order is the reverse of list order.
        _notifier(c).assignMaster(
          serviceDefId: _serviceDefIdBrows,
          masterId: _master.masterId,
          masterServiceId: _masterServiceIdBrows,
          master: _master,
        );
        _notifier(c).assignMaster(
          serviceDefId: _serviceDefIdNails,
          masterId: _master.masterId,
          masterServiceId: _masterServiceIdNails,
          master: _master,
        );

        final state = _state(c);
        expect(
          state.entries.map((SalonServiceBooking e) => e.serviceDefId).toList(),
          <String>[_serviceDefIdNails, _serviceDefIdBrows],
          reason:
              'insertion order must survive individual updates regardless of '
              'update order',
        );
        // And both entries did in fact get their own, distinct assignment.
        expect(
          state.entryFor(_serviceDefIdNails)!.masterServiceId,
          _masterServiceIdNails,
        );
        expect(
          state.entryFor(_serviceDefIdBrows)!.masterServiceId,
          _masterServiceIdBrows,
        );
      },
    );
  });

  group('invalidate (D4)', () {
    test('should_resetToEmpty_when_theDraftIsInvalidated', () async {
      final c = await _make();
      _notifier(c).selectServices(
        salonId: _salonId,
        services: <SalonCatalogService>[_nailsService],
      );
      _notifier(c).assignMaster(
        serviceDefId: _serviceDefIdNails,
        masterId: _master.masterId,
        masterServiceId: _masterServiceIdNails,
        master: _master,
      );
      expect(_state(c).entries, isNotEmpty);

      c.invalidate(salonBookingDraftProvider);

      final after = _state(c);
      expect(after.entries, isEmpty);
      expect(after.salonId, isNull);
    });
  });

  group('H-1 — session boundary (the PII/cross-session-leak guard)', () {
    test('a DIFFERENT account logging in resets the draft to empty — the '
        "previous session's masterId/masterServiceId/master summary/startAt "
        'and selected services must never repopulate the next client\'s '
        'booking', () async {
      final (ProviderContainer c, _SettableAuthNotifier auth) = await _boot(
        _sessionFor(_clientA),
      );
      _notifier(c).selectServices(
        salonId: _salonId,
        services: <SalonCatalogService>[_nailsService],
      );
      _notifier(c).assignMaster(
        serviceDefId: _serviceDefIdNails,
        masterId: _master.masterId,
        masterServiceId: _masterServiceIdNails,
        master: _master,
        durationMinutes: 60,
      );
      expect(
        _state(c).entries,
        isNotEmpty,
        reason: 'precondition — client A really did leave a draft behind',
      );

      auth.emit(_sessionFor(_clientB));

      final after = _state(c);
      expect(
        after.entries,
        isEmpty,
        reason:
            'THE LEAK: a keepAlive draft holding a masterId, '
            'masterServiceId, master summary and startAt must rebuild '
            'when the authenticated identity changes',
      );
      expect(after.salonId, isNull);
    });

    test('logging OUT resets the draft to empty', () async {
      final (ProviderContainer c, _SettableAuthNotifier auth) = await _boot(
        _sessionFor(_clientA),
      );
      _notifier(c).selectServices(
        salonId: _salonId,
        services: <SalonCatalogService>[_nailsService],
      );
      expect(_state(c).entries, isNotEmpty);

      auth.emit(_loggedOut);

      expect(_state(c).entries, isEmpty);
      expect(_state(c).salonId, isNull);
    });

    test('an UNCHANGED identity (same user, ordinary rebuild trigger) does NOT '
        'clear the draft — otherwise a notifier that clears on every rebuild '
        'would pass this guard for the wrong reason', () async {
      final (ProviderContainer c, _SettableAuthNotifier auth) = await _boot(
        _sessionFor(_clientA),
      );
      _notifier(c).selectServices(
        salonId: _salonId,
        services: <SalonCatalogService>[_nailsService],
      );
      expect(_state(c).entries, isNotEmpty);

      // Same user id, unrelated re-emit — nothing about the IDENTITY
      // changed.
      auth.emit(_sessionFor(_clientA));

      expect(
        _state(c).entries,
        isNotEmpty,
        reason:
            'the watch selects the identity slice only — an unchanged id '
            'must not spuriously rebuild (and reset) an in-progress draft',
      );
    });

    test('a SILENT TOKEN REFRESH (same user id, new access token) does NOT '
        'clear the draft — the watch selects the identity slice only, so an '
        "ordinary refresh mid-flow cannot wipe the client's in-progress "
        'selection', () async {
      final (ProviderContainer c, _SettableAuthNotifier auth) = await _boot(
        _sessionFor(_clientA),
      );
      _notifier(c).selectServices(
        salonId: _salonId,
        services: <SalonCatalogService>[_nailsService],
      );

      auth.emit(_sessionFor(_clientA, token: 'tok-2-refreshed'));

      expect(
        _state(c).entries,
        isNotEmpty,
        reason:
            'keeps the account-switch assertion above non-vacuous: it '
            'must be the IDENTITY that clears the draft, not any session '
            'emission',
      );
    });
  });

  group('P-1 — SalonBookingDraftState value equality', () {
    test(
      'two states with the same salonId and equal entries compare equal',
      () {
        const a = SalonBookingDraftState(
          salonId: _salonId,
          entries: <SalonServiceBooking>[
            SalonServiceBooking(
              service: _nailsService,
              serviceDefId: _serviceDefIdNails,
            ),
          ],
        );
        const b = SalonBookingDraftState(
          salonId: _salonId,
          entries: <SalonServiceBooking>[
            SalonServiceBooking(
              service: _nailsService,
              serviceDefId: _serviceDefIdNails,
            ),
          ],
        );

        expect(a, b);
        expect(a.hashCode, b.hashCode);
      },
    );

    test('a different salonId compares unequal', () {
      const a = SalonBookingDraftState(salonId: 'salon-1');
      const b = SalonBookingDraftState(salonId: 'salon-2');

      expect(a, isNot(b));
    });

    test('a different entry list length compares unequal', () {
      const a = SalonBookingDraftState(
        salonId: _salonId,
        entries: <SalonServiceBooking>[
          SalonServiceBooking(
            service: _nailsService,
            serviceDefId: _serviceDefIdNails,
          ),
        ],
      );
      const b = SalonBookingDraftState(
        salonId: _salonId,
        entries: <SalonServiceBooking>[],
      );

      expect(a, isNot(b));
    });

    test(
      'an entry differing in one field (e.g. masterId) compares unequal',
      () {
        const a = SalonBookingDraftState(
          salonId: _salonId,
          entries: <SalonServiceBooking>[
            SalonServiceBooking(
              service: _nailsService,
              serviceDefId: _serviceDefIdNails,
            ),
          ],
        );
        const b = SalonBookingDraftState(
          salonId: _salonId,
          entries: <SalonServiceBooking>[
            SalonServiceBooking(
              service: _nailsService,
              serviceDefId: _serviceDefIdNails,
              masterId: 'master-anna-1',
            ),
          ],
        );

        expect(a, isNot(b));
      },
    );

    test('entries in swapped order compare unequal — order is load-bearing for '
        "D5's wire execution sequence, not merely display (see the notifier "
        'file header + orderedMasterServiceIds)', () {
      const entryNails = SalonServiceBooking(
        service: _nailsService,
        serviceDefId: _serviceDefIdNails,
      );
      const entryBrows = SalonServiceBooking(
        service: _browsService,
        serviceDefId: _serviceDefIdBrows,
      );

      const nailsFirst = SalonBookingDraftState(
        salonId: _salonId,
        entries: <SalonServiceBooking>[entryNails, entryBrows],
      );
      const browsFirst = SalonBookingDraftState(
        salonId: _salonId,
        entries: <SalonServiceBooking>[entryBrows, entryNails],
      );

      expect(
        nailsFirst,
        isNot(browsFirst),
        reason:
            'entry order is the back-to-back execution order the wire '
            'consumes (D5) — if a future edit made equality '
            'order-insensitive, a reordered draft would compare equal, '
            "suppress the notify, and silently reschedule the client's "
            'services',
      );
      expect(
        nailsFirst.hashCode,
        isNot(browsFirst.hashCode),
        reason:
            'practical expectation given hashCode uses '
            'Object.hashAll(entries), which is order-sensitive — NOT '
            'strictly contract-required (two unequal objects may legally '
            'share a hashCode), but a collision here would flag a '
            'regression in this specific implementation',
      );

      // Same entries, SAME order: must stay equal, so the swapped-order
      // assertion above cannot pass vacuously (e.g. from an accidental
      // always-not-equal override).
      const nailsFirstAgain = SalonBookingDraftState(
        salonId: _salonId,
        entries: <SalonServiceBooking>[entryNails, entryBrows],
      );
      expect(nailsFirst, nailsFirstAgain);
    });
  });

  group('P-2 — withUpdatedEntry no-match short-circuit', () {
    test('returns the EXACT SAME instance (identical, not merely equal) when '
        'no entry matches serviceDefId', () async {
      final c = await _make();
      _notifier(c).selectServices(
        salonId: _salonId,
        services: <SalonCatalogService>[_nailsService],
      );
      final SalonBookingDraftState before = _state(c);

      final SalonBookingDraftState after = before.withUpdatedEntry(
        'svcdef-does-not-exist',
        (SalonServiceBooking entry) =>
            entry.copyWith(masterId: 'should-never-be-applied'),
      );

      expect(
        identical(before, after),
        isTrue,
        reason:
            'a defensive/stale caller for an absent serviceDefId must not '
            'allocate a new List or a new state — and must not fire a '
            'full Riverpod notify for nothing',
      );
    });

    test('a matching serviceDefId still applies the update (the short-circuit '
        'does not swallow the real case)', () async {
      final c = await _make();
      _notifier(c).selectServices(
        salonId: _salonId,
        services: <SalonCatalogService>[_nailsService],
      );

      _notifier(c).assignMaster(
        serviceDefId: _serviceDefIdNails,
        masterId: _master.masterId,
        masterServiceId: _masterServiceIdNails,
        master: _master,
      );

      expect(
        _state(c).entryFor(_serviceDefIdNails)!.masterId,
        _master.masterId,
      );
    });
  });
}
