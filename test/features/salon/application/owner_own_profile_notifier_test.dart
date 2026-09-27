// Phase 21.14 audit-fix cycle 1 — unit tests for [ownerOwnProfileProvider]
// (`owner_own_profile_notifier.dart`).
//
// These pin the two mobile-perf findings the loader carried, and they pin them
// by OBSERVING THE ORDER OF WORK, not by reading the final value — the final
// value was already correct under the bug.
//
//   P1 (MEDIUM) — `/users/me` and `/masters/me` are INDEPENDENT, but the
//     `masterProfileProvider` watch sat AFTER the `await` on the `/users/me`
//     future. Two defects in one line: `ref.watch` after a suspension point is
//     unsafe in an async provider body (the in-repo rule stated at
//     `home_hub_notifier.dart:70-73`), and the two round trips were serialized
//     for no gain — the `hasMasterProfile` gate only carries information in
//     the `false` state, and `true`/`null` both fetch `/masters/me` anyway.
//     PINNED BY: `_GatedClientEditProfile` parks `/users/me` on a Completer;
//     the master read must ALREADY have started while it is still parked.
//
//   P4 (LOW) — `approvedCategoriesProvider` was first touched from
//     `ServiceCategoryCardList.build()`, i.e. a 4th hop starting only after
//     the loaded body's first paint, so the category labels visibly swapped
//     from `humanizeCategorySlug` to the real names and the section relayouted
//     under the user. It is now warmed by the loader.
//
//   P4b (LOW, audit-fix cycle 2, 2026-09-01) — that warm-start was
//     UNCONDITIONAL, so the `hasMasterProfile == false` arm (which renders no
//     service-categories section at all) paid for a third request no card
//     would ever consume. The `ref.read(...).ignore()` now sits BELOW the
//     `false` early return.
//     PINNED BY the pair below, and both halves are needed: the warm-start
//     must still lead `ServiceCategoryCardList.build()` by at least one round
//     trip in the `true`/`null` states (pinned inside a window where the
//     catalogue read — the loader's LAST hop — is still parked), and it must
//     not happen at all in the `false` state. Deleting the read outright
//     passes the second test; moving it back above the early return passes
//     the first.
//
// TRAP (documented in `owner_own_profile_screen_test.dart` too):
// `approvedCategoriesProvider` bypasses `serviceRepositoryProvider` entirely
// (it reads `categoryRequestApiProvider` directly), so it is overridden
// DIRECTLY here — overriding the repository would not intercept it.
//
// The `hasMasterProfile` tri-state is pinned alongside, because the parallel
// hoist is only correct if the `false` arm still renders the section ABSENT.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/owner_own_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const User _owner = User(
  id: 'u-1',
  email: 'owner@beautica.test',
  role: UserRole.salonOwner,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  hasMasterProfile: true,
);

const User _ownerNoMaster = User(
  id: 'u-1',
  email: 'owner@beautica.test',
  role: UserRole.salonOwner,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  hasMasterProfile: false,
);

const Master _master = Master(
  id: 'master-row-7',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  reviewCount: 0,
  type: MasterType.salonOwner,
);

const List<MasterService> _services = <MasterService>[
  MasterService(
    id: 's-1',
    serviceDefId: 'd-1',
    name: 'Манікюр',
    durationMinutes: 60,
    priceMin: 500,
    priceDisplay: '500 ₴',
    category: 'NAILS',
  ),
];

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

/// `/users/me` parked on a [Completer] the test controls, so every assertion
/// about "what has already started" is made inside a window the test opens.
class _GatedClientEditProfile extends ClientEditProfile {
  _GatedClientEditProfile(this.gate);

  final Completer<User> gate;

  @override
  Future<User> build() => gate.future;
}

/// `/users/me` resolving immediately, for the arms that do not need the gate.
class _SettledClientEditProfile extends ClientEditProfile {
  _SettledClientEditProfile(this.user);

  final User user;

  @override
  Future<User> build() async => user;
}

/// `/masters/me` that RECORDS whether its build ran — the whole point of the
/// P1 pin.
class _RecordingMasterProfile extends MasterProfile {
  _RecordingMasterProfile(this.log, {this.throws});

  final List<String> log;
  final Object? throws;

  @override
  Future<Master> build() async {
    log.add('masters/me');
    final Object? failure = throws;
    if (failure != null) throw failure;
    return _master;
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue('');
  });

  ProviderContainer makeContainer({
    required ClientEditProfile Function() owner,
    required List<String> log,
    ServiceRepository? serviceRepo,
    Object? masterThrows,
  }) {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        clientEditProfileProvider.overrideWith(owner),
        // `masterProfileProvider` is the LEAF data dep of the provider under
        // test — the loader's only job with it is to await its future, and
        // this stub exists precisely to record WHEN that build runs (the P1
        // pin). The edge it would otherwise close, masterProfile →
        // authProvider, is exercised for real by
        // `master_profile_notifier_test.dart` (including its own narrowed-
        // watch pins) and by `provider_cycle_guard_test.dart`; nothing here
        // invokes a cyclic teardown entrypoint.
        // cycle-stub-ok: leaf data dep of the notifier under test (see above).
        masterProfileProvider.overrideWith(
          () => _RecordingMasterProfile(log, throws: masterThrows),
        ),
        // DIRECT override — this provider bypasses serviceRepositoryProvider.
        approvedCategoriesProvider.overrideWith((Ref ref) async {
          log.add('categories/approved');
          return const <ServiceCategoryOption>[];
        }),
        if (serviceRepo != null)
          publicServiceRepositoryProvider.overrideWithValue(serviceRepo),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Keeps [ownerOwnProfileProvider] SUBSCRIBED for the life of the test.
  ///
  /// It is `autoDispose` (`@riverpod`), so a bare `container.read(...future)`
  /// disposes the element the moment the read returns — and the loader's own
  /// post-await `ref.read(publicServiceRepositoryProvider)` then throws
  /// "Cannot use the Ref ... after it has been disposed". In the app a widget
  /// is always watching it; this listener is that widget.
  Future<OwnerOwnProfileData> readOwnerProfile(ProviderContainer container) {
    final sub = container.listen(ownerOwnProfileProvider, (_, _) {});
    addTearDown(sub.close);
    return container.read(ownerOwnProfileProvider.future);
  }

  _MockServiceRepository makeServiceRepo(List<String> log) {
    final repo = _MockServiceRepository();
    when(() => repo.getMasterServices(any())).thenAnswer((_) async {
      log.add('masters/{id}/services');
      return _services;
    });
    return repo;
  }

  group('ownerOwnProfile — parallel fan-out (P1 / P4)', () {
    test('GET /masters/me starts WHILE GET /users/me is still in flight — the '
        'two independent reads are not serialized', () async {
      final List<String> log = <String>[];
      final Completer<User> gate = Completer<User>();
      final container = makeContainer(
        owner: () => _GatedClientEditProfile(gate),
        log: log,
        serviceRepo: makeServiceRepo(log),
      );

      final Future<OwnerOwnProfileData> pending = readOwnerProfile(container);
      // Let the loader body run up to its first suspension point. `/users/me`
      // is still parked on `gate` for the whole of this window.
      await pumpEventQueue();

      expect(
        gate.isCompleted,
        isFalse,
        reason:
            'sanity: the window this test asserts inside must still be open — '
            'otherwise "already started" proves nothing.',
      );
      expect(
        log,
        contains('masters/me'),
        reason:
            'GET /masters/me must be started BEFORE GET /users/me resolves. If '
            'the masterProfileProvider watch is moved back below the await, '
            'this list is still empty here — and the watch is additionally an '
            'unsafe post-suspension ref.watch.',
      );

      gate.complete(_owner);
      final OwnerOwnProfileData data = await pending;
      expect(data.master?.$1, _master);
      expect(data.master?.$2, _services);
      // The 2→3 hop IS a real dependency (the catalogue endpoint is keyed on
      // Master.id), so it must still come last.
      expect(log.last, 'masters/{id}/services');
    });

    test('approvedCategoriesProvider is warmed by the loader, at least one '
        'round trip ahead of the category cards\' build()', () async {
      final List<String> log = <String>[];
      // Park the loader's LAST hop (`GET /masters/{id}/services`) so the
      // assertion window below is a window the loader is still inside. The
      // cards only build after this future resolves, so "already started here"
      // is exactly "≥1 round trip ahead of ServiceCategoryCardList.build()".
      final Completer<List<MasterService>> catalogueGate =
          Completer<List<MasterService>>();
      final repo = _MockServiceRepository();
      when(() => repo.getMasterServices(any())).thenAnswer((_) {
        log.add('masters/{id}/services');
        return catalogueGate.future;
      });

      final container = makeContainer(
        owner: () => _SettledClientEditProfile(_owner),
        log: log,
        serviceRepo: repo,
      );

      final Future<OwnerOwnProfileData> pending = readOwnerProfile(container);
      await pumpEventQueue();

      expect(
        catalogueGate.isCompleted,
        isFalse,
        reason:
            'sanity: the window this test asserts inside must still be open — '
            'otherwise "already started" proves nothing.',
      );
      expect(
        log,
        contains('categories/approved'),
        reason:
            'GET /service-categories/approved must be kicked off by the LOADER '
            'while the catalogue read is still in flight. Left to '
            'ServiceCategoryCardList.build() it is a hop that only starts '
            'after the loaded body first paints, so the labels swap from '
            'humanizeCategorySlug to the real names and the section relayouts '
            'under the user. (Since the 2026-09-01 P4b fix it starts BELOW the '
            'hasMasterProfile early return rather than at the top of the body '
            '— still ahead of this gate, which is the property that matters.)',
      );

      catalogueGate.complete(_services);
      await pending;
    });
  });

  group('ownerOwnProfile — the hasMasterProfile tri-state survives the '
      'parallel hoist', () {
    test('hasMasterProfile == false renders the section ABSENT and never '
        'reaches the catalogue read', () async {
      final List<String> log = <String>[];
      final repo = makeServiceRepo(log);
      final container = makeContainer(
        owner: () => _SettledClientEditProfile(_ownerNoMaster),
        log: log,
        serviceRepo: repo,
      );

      final OwnerOwnProfileData data = await readOwnerProfile(container);

      expect(data.owner, _ownerNoMaster);
      expect(data.master, isNull);
      // The PROBE is now speculative (it is started in parallel, before the
      // gate value is known) — but its RESULT must be discarded, and the
      // catalogue read keyed on it must never happen.
      verifyNever(() => repo.getMasterServices(any()));
    });

    test('hasMasterProfile == false does NOT warm approvedCategoriesProvider '
        '(P4b — no card will ever consume it)', () async {
      final List<String> log = <String>[];
      final repo = makeServiceRepo(log);
      final container = makeContainer(
        owner: () => _SettledClientEditProfile(_ownerNoMaster),
        log: log,
        serviceRepo: repo,
      );

      final OwnerOwnProfileData data = await readOwnerProfile(container);
      // Let anything the loader started speculatively land before asserting,
      // so a late warm-start cannot hide behind the await above.
      await pumpEventQueue();

      expect(data.master, isNull);
      expect(
        log,
        isNot(contains('categories/approved')),
        reason:
            'the false arm renders the service-categories section as ABSENT, '
            'so the category labels have no consumer — warming them here is a '
            'third request bought for nothing. The warm-start must sit BELOW '
            'this early return.',
      );
      expect(
        log,
        contains('masters/me'),
        reason:
            'sanity: the loader really did run its speculative parallel fan-'
            'out in this arm, so the assertion above is about the warm-start '
            'position and not about the loader having short-circuited early.',
      );
    });

    test('a /masters/me failure degrades the section to ABSENT instead of '
        'erroring the whole tab', () async {
      final List<String> log = <String>[];
      final container = makeContainer(
        owner: () => _SettledClientEditProfile(_owner),
        log: log,
        masterThrows: const NotFoundFailure(),
        serviceRepo: makeServiceRepo(log),
      );

      final OwnerOwnProfileData data = await readOwnerProfile(container);

      expect(data.owner, _owner);
      expect(
        data.master,
        isNull,
        reason:
            'Only the /users/me read may error this provider. The rejected '
            'master future is folded to null at creation — which is also what '
            'keeps the `false` arm above from leaving it unawaited (an '
            'unawaited rejected Future is an unhandled zone error).',
      );
    });
  });
}
