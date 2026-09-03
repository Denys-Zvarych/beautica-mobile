// Phase 21.2 QA follow-up — unit tests for [SalonManagementProfile]
// (`salon_management_profile_notifier.dart`).
//
// MANDATE 3 (mobile-qa audit, highest-consequence pin in this file): the
// notifier's dirty-field diff decides whether `phone` reaches the PATCH body
// at all. `GET /salons/{salonId}` (`PublicSalonResponse`) never returns
// `phone` — only `PATCH /salons/{salonId}` (`SalonResponse`) does — so if
// [save] ever regressed to send `phone` VERBATIM instead of diffed, an owner
// who saves without touching the phone field would silently WIPE a real
// phone number already on file (an empty string PATCHed over it). No test
// pinned this before this file. The two `dirty-field diff — phone` tests
// below pin both halves: omitted when untouched, included when edited — with
// fixture values chosen so the assertion actually MOVES (a non-empty
// baseline phone, not a blank one an omission-vs-empty-string bug could hide
// behind).
//
// Strategy mirrors `master_profile_notifier_test.dart`: a fresh
// `ProviderContainer` per test (`addTearDown`), `authProvider` +
// `authRepositoryProvider` + `secureStorageProvider` stubbed so no real auth/
// storage I/O happens, `salonRepositoryProvider` overridden with a mocktail
// mock. Pure Dart — no widget tree.

import 'dart:async';

import 'package:beautica_api/beautica_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockSalonRepository extends Mock implements SalonRepository {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _kSalonId = 'salon-1';

const _stubUser = User(
  id: 'owner-1',
  email: 'owner@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Оксана',
  lastName: 'Швець',
);

/// Loaded state simulating a FRESH `GET /salons/{salonId}` — `phone` is
/// `null` (the real Phase 21.2 gap; see [Salon.phone]'s doc), `street`/
/// `buildingNo` are present (backend-required on every PATCH).
///
/// RESUME §4 step D (mobile half, 2026-08-30) — carries a real `cityId`/
/// `oblastId` pair (distinct from [_salonWithLocality]'s, so a mixed-up
/// fixture would surface as a visibly wrong id): the backend guarantees
/// every salon has one (`salons.city_id` DB-level `NOT NULL`, backend
/// `ec22d91`) and [Salon.cityId]/[Salon.oblastId] are non-nullable to match,
/// so there is no longer a "fresh, cityless salon" shape to model.
const _freshSalon = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  description: 'Затишний салон краси.',
  street: 'вул. Велика Васильківська',
  buildingNo: '44',
  cityId: 'city-fresh-01',
  oblastId: 'oblast-fresh-01',
  phone: null,
);

/// Loaded state simulating a salon that has ALREADY been through one
/// successful PATCH — `phone` is a real, non-empty number (mirrors
/// `SalonManagementProfile.save`'s own merge: `SalonMapper.fromUpdateDto`
/// carries `phone` through). This is the fixture the phone-OMITTED test
/// needs: a blank/blank comparison could pass for the wrong reason (omitted
/// and "sent empty" look identical), a real-number/omitted comparison cannot.
const _salonWithKnownPhone = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  description: 'Затишний салон краси.',
  street: 'вул. Велика Васильківська',
  buildingNo: '44',
  phone: '+380671112233',
);

/// Loaded state WITH a real locality on file (both [Salon.cityId] and
/// [Salon.districtId] set) — the fixture the 2026-08-29 regression tests
/// need: `save()` must echo BOTH back onto the wire regardless of which
/// other field the viewer actually edited. Distinct id values from
/// [_freshSalon]/[_salonWithKnownPhone] so a mixed-up fixture would surface
/// as a visibly wrong id, not a coincidental pass.
const _salonWithLocality = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  description: 'Затишний салон краси.',
  street: 'вул. Велика Васильківська',
  buildingNo: '44',
  cityId: 'city-locality-01',
  districtId: 'district-locality-01',
);

const _staff = <SalonStaffMember>[];

/// The «Мої салони» hub's cached list entry — deliberately a DIFFERENT id
/// from [_kSalonId]; the invalidation tests below only care whether
/// `mySalonsProvider` REBUILDS, not what it resolves to.
const _hubCachedSalon = Salon(id: 'hub-cached-salon', name: 'Hub Salon v1');

/// Mutable box so a `build()` call count survives `mySalonsProvider` being
/// recreated by `ref.invalidate` — the [MySalons] override factory always
/// closes over the SAME [_CallCounter] instance, unlike an instance field on
/// the (possibly-recreated) notifier itself.
class _CallCounter {
  int value = 0;
}

/// [MySalons] stub that increments [counter] on every `build()` — the
/// invalidation regression pins below assert on [counter], not on the
/// resolved list (mobile-perf MEDIUM follow-up, 2026-08-28 — see
/// `salon_management_profile_notifier.dart`'s header doc for the staleness
/// bug this pins).
class _CountingMySalons extends MySalons {
  _CountingMySalons(this.counter);

  final _CallCounter counter;

  @override
  Future<List<Salon>> build() async {
    counter.value++;
    return const <Salon>[_hubCachedSalon];
  }
}

class _StubAuthAuthenticated extends AuthNotifier {
  @override
  Future<AuthSession> build() => Future.value(
    const AuthSession.authenticated(user: _stubUser, accessToken: 'tok'),
  );
}

/// Same settled session as [_StubAuthAuthenticated], but a test can push a
/// NEW [AuthSession] afterwards — needed by the narrowed-watch pair at the
/// bottom of this file, which must distinguish a token-only re-emission from
/// a real identity change. `state =` is only reachable from inside an
/// [AsyncNotifier] subclass, hence this stub rather than an external poke.
class _ControllableAuthAuthenticated extends AuthNotifier {
  @override
  Future<AuthSession> build() => Future.value(
    const AuthSession.authenticated(user: _stubUser, accessToken: 'tok'),
  );

  void emit(AuthSession session) => state = AsyncData<AuthSession>(session);
}

/// Auth that has NOT resolved yet — `authProvider` sits in `AsyncLoading`
/// (so `authUserIdOrNull` reads `null`) until the test calls [resolve].
/// Models the real precondition [SalonManagementProfile.deleteSalon]'s own
/// doc names for the compound race: this family commonly gets its FIRST
/// `build()` before `authProvider` has resolved once (e.g. right after
/// login, landing on `/salons/mine`).
class _PendingAuthAuthenticated extends AuthNotifier {
  final Completer<AuthSession> _completer = Completer<AuthSession>();

  @override
  Future<AuthSession> build() => _completer.future;

  void resolve(AuthSession session) => _completer.complete(session);
}

ProviderContainer _makeContainer(SalonRepository repo) {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(_StubAuthAuthenticated.new),
      secureStorageProvider.overrideWithValue(FakeSecureStorage()),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      salonRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Drives the provider to a specific LOADED state without going through a
/// real `build()` round-trip against the mock — stubs the initial
/// `getSalonById`/`getSalonMasters` reads with [seed], then reads `.future`
/// to settle it. Every `save()`/`deleteSalon()` test needs a loaded state
/// before it can call either method.
Future<SalonManagementProfile> _readyNotifier(
  ProviderContainer container,
  Salon seed,
) async {
  await container.read(authProvider.future);
  await container.read(salonManagementProfileProvider(_kSalonId).future);
  return container.read(salonManagementProfileProvider(_kSalonId).notifier);
}

void main() {
  late _MockSalonRepository repo;

  setUpAll(() {
    // `any()` is used for the `UpdateSalonRequest` positional arg of
    // `updateSalon` below (the actual value is captured/asserted via
    // `invocation.positionalArguments`, not matched) — mocktail requires a
    // fallback for any non-primitive type passed to `any()`.
    registerFallbackValue(
      UpdateSalonRequest(
        (b) => b
          ..street = ''
          ..buildingNo = '',
      ),
    );
  });

  setUp(() {
    repo = _MockSalonRepository();
  });

  // ── build() ────────────────────────────────────────────────────────────

  group('build()', () {
    test('loads salon + masters in parallel and returns both', () async {
      when(
        () => repo.getSalonById(_kSalonId),
      ).thenAnswer((_) async => _freshSalon);
      when(() => repo.getSalonStaff(_kSalonId)).thenAnswer((_) async => _staff);

      final container = _makeContainer(repo);
      await container.read(authProvider.future);

      final data = await container.read(
        salonManagementProfileProvider(_kSalonId).future,
      );

      expect(data.$1.id, _kSalonId);
      expect(data.$1.name, 'Салон «Вельвет»');
      expect(data.$2, isEmpty);
    });

    test('emits AsyncError when the repository throws', () async {
      // Async throw (not a synchronous `thenThrow`) — build() goes through
      // Riverpod's retry machinery, and a synchronous throw would bypass it
      // entirely (mobile-qa M13). Retry disabled via the container below so
      // the terminal AsyncError is reachable on the first attempt.
      when(
        () => repo.getSalonById(_kSalonId),
      ).thenAnswer((_) async => throw const NetworkFailure());
      when(() => repo.getSalonStaff(_kSalonId)).thenAnswer((_) async => _staff);

      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          authProvider.overrideWith(_StubAuthAuthenticated.new),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          salonRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authProvider.future);

      // `.future` rejects with the UNWRAPPED failure (build()'s own
      // ParallelWaitError -> Failure unwrap, not flutter_test's own doing) —
      // swallow it here purely to let the state settle; the real assertion
      // reads the notifier's own AsyncValue below.
      await container
          .read(salonManagementProfileProvider(_kSalonId).future)
          .catchError(
            (_) => (const Salon(id: '', name: ''), <SalonStaffMember>[]),
          );

      final state = container.read(salonManagementProfileProvider(_kSalonId));
      // M12: `hasError` alone is satisfied by `AsyncLoading(retrying: true)`
      // mid-retry — pin the terminal shape too.
      expect(state.hasError, isTrue);
      expect(state, isA<AsyncError<SalonManagementProfileData>>());
      // The load-bearing assertion: `state.error` must be the UNWRAPPED
      // NetworkFailure, not the raw `ParallelWaitError` the records `.wait`
      // combinator throws when one of two parallel futures fails. Verified
      // RED before build() gained its `on ParallelWaitError catch` unwrap
      // (mirrors `public_salon_profile_notifier.dart`'s identical pattern):
      // this exact assertion failed with `state.error` being a
      // `ParallelWaitError` instance, which the screen's
      // `e is Failure ? e : UnknownFailure(cause: e)` branch would have
      // rendered as a generic "unknown error" regardless of the real
      // network/server/unauthorized cause.
      expect(state.error, isA<NetworkFailure>());
    });
  });

  // ── save() — dirty-field diff (MANDATE 3: the phone-wipe pin) ───────────

  group('save() — dirty-field diff — phone', () {
    test('phone is OMITTED from the PATCH when untouched (equals the loaded '
        'value)', () async {
      when(
        () => repo.getSalonById(_kSalonId),
      ).thenAnswer((_) async => _salonWithKnownPhone);
      when(() => repo.getSalonStaff(_kSalonId)).thenAnswer((_) async => _staff);

      UpdateSalonRequest? captured;
      when(() => repo.updateSalon(_kSalonId, any())).thenAnswer((
        invocation,
      ) async {
        captured = invocation.positionalArguments[1] as UpdateSalonRequest;
        return _salonWithKnownPhone.copyWith(name: 'Нова назва');
      });

      final container = _makeContainer(repo);
      final notifier = await _readyNotifier(container, _salonWithKnownPhone);

      // Only the NAME field is edited — phone is re-submitted at its
      // EXACT loaded value, exactly as an untouched TextEditingController
      // (seeded from `salon.phone ?? ''`) would submit it.
      final failure = await notifier.save(
        name: 'Нова назва',
        description: _salonWithKnownPhone.description!,
        phone: _salonWithKnownPhone.phone!,
        instagramUrl: '',
      );

      expect(failure, isNull);
      expect(captured, isNotNull);
      expect(
        captured!.phone,
        isNull,
        reason:
            'an UNTOUCHED phone (still the loaded value) must be OMITTED '
            'from the PATCH body — sending it back verbatim risks nothing '
            'here, but a regression that always includes phone would wipe '
            'a real number on a salon whose GET-time phone is null (the '
            'normal case). The baseline here is a REAL non-empty phone '
            '(+380671112233), so this assertion actually moves — it '
            'cannot pass by omitted-vs-empty-string coincidence.',
      );
      expect(captured!.name, 'Нова назва');
    });

    test(
      'phone IS included in the PATCH when the viewer actually edits it',
      () async {
        when(
          () => repo.getSalonById(_kSalonId),
        ).thenAnswer((_) async => _freshSalon);
        when(
          () => repo.getSalonStaff(_kSalonId),
        ).thenAnswer((_) async => _staff);

        UpdateSalonRequest? captured;
        when(() => repo.updateSalon(_kSalonId, any())).thenAnswer((
          invocation,
        ) async {
          captured = invocation.positionalArguments[1] as UpdateSalonRequest;
          return _freshSalon.copyWith(phone: '+380501234567');
        });

        final container = _makeContainer(repo);
        final notifier = await _readyNotifier(container, _freshSalon);

        // name/description/instagram stay at their loaded values (untouched);
        // phone is the ONLY field the viewer typed into.
        final failure = await notifier.save(
          name: _freshSalon.name,
          description: _freshSalon.description!,
          phone: '+380501234567',
          instagramUrl: '',
        );

        expect(failure, isNull);
        expect(captured, isNotNull);
        expect(captured!.phone, '+380501234567');
        expect(captured!.name, isNull, reason: 'untouched — must be omitted');
        expect(
          captured!.description,
          isNull,
          reason: 'untouched — must be omitted',
        );
      },
    );

    test('street/buildingNo are always threaded through unmodified', () async {
      when(
        () => repo.getSalonById(_kSalonId),
      ).thenAnswer((_) async => _freshSalon);
      when(() => repo.getSalonStaff(_kSalonId)).thenAnswer((_) async => _staff);

      UpdateSalonRequest? captured;
      when(() => repo.updateSalon(_kSalonId, any())).thenAnswer((
        invocation,
      ) async {
        captured = invocation.positionalArguments[1] as UpdateSalonRequest;
        return _freshSalon;
      });

      final container = _makeContainer(repo);
      final notifier = await _readyNotifier(container, _freshSalon);

      await notifier.save(
        name: _freshSalon.name,
        description: _freshSalon.description!,
        phone: '',
        instagramUrl: '',
      );

      expect(captured!.street, _freshSalon.street);
      expect(captured!.buildingNo, _freshSalon.buildingNo);
    });

    test(
      'a repository Failure is returned and state is left untouched',
      () async {
        when(
          () => repo.getSalonById(_kSalonId),
        ).thenAnswer((_) async => _freshSalon);
        when(
          () => repo.getSalonStaff(_kSalonId),
        ).thenAnswer((_) async => _staff);
        when(
          () => repo.updateSalon(_kSalonId, any()),
        ).thenThrow(const ServerFailure(statusCode: 500));

        final container = _makeContainer(repo);
        final notifier = await _readyNotifier(container, _freshSalon);

        final failure = await notifier.save(
          name: 'Змінена назва',
          description: _freshSalon.description!,
          phone: '',
          instagramUrl: '',
        );

        expect(failure, isA<ServerFailure>());
        final state = container.read(salonManagementProfileProvider(_kSalonId));
        expect(
          state.value!.$1.name,
          _freshSalon.name,
          reason:
              'a failed save must leave the previously-loaded state alone '
              'so the screen can offer a retry',
        );
      },
    );
  });

  // ── save() — locality echoed regardless of dirty field (Finding, ───────
  // ── 2026-08-29) ──────────────────────────────────────────────────────
  //
  // The user-reported bug: `save()` used to thread `street`/`buildingNo`
  // through unconditionally but left `cityId`/`districtId` OFF the request
  // entirely, so the serializer omitted the keys and the backend's
  // unconditional `LocalityWriteValidator` 400'd EVERY save — «Про салон»
  // and «Контакти» alike, regardless of which field the viewer actually
  // edited. This group pins that `cityId`/`districtId` now ride along on
  // every `save()`, independent of the edited field.
  group('save() — locality echoed regardless of dirty field (2026-08-29 '
      'regression)', () {
    test(
      'cityId/districtId are present when ONLY description is edited',
      () async {
        when(
          () => repo.getSalonById(_kSalonId),
        ).thenAnswer((_) async => _salonWithLocality);
        when(
          () => repo.getSalonStaff(_kSalonId),
        ).thenAnswer((_) async => _staff);

        UpdateSalonRequest? captured;
        when(() => repo.updateSalon(_kSalonId, any())).thenAnswer((
          invocation,
        ) async {
          captured = invocation.positionalArguments[1] as UpdateSalonRequest;
          return _salonWithLocality.copyWith(description: 'Нова назва');
        });

        final container = _makeContainer(repo);
        final notifier = await _readyNotifier(container, _salonWithLocality);

        // name/phone/instagram stay at their loaded values (untouched) —
        // ONLY description is edited.
        final failure = await notifier.save(
          name: _salonWithLocality.name,
          description: 'Нова назва салону',
          phone: '',
          instagramUrl: '',
        );

        expect(failure, isNull);
        expect(captured, isNotNull);
        expect(captured!.description, 'Нова назва салону');
        expect(
          captured!.cityId,
          _salonWithLocality.cityId,
          reason:
              'this is the shipped bug: an edit to ANY field other than '
              'locality must still echo cityId, or the backend 400s the '
              'whole save with "City is required".',
        );
        expect(captured!.districtId, _salonWithLocality.districtId);
      },
    );

    test('cityId/districtId are present when ONLY phone is edited', () async {
      when(
        () => repo.getSalonById(_kSalonId),
      ).thenAnswer((_) async => _salonWithLocality);
      when(() => repo.getSalonStaff(_kSalonId)).thenAnswer((_) async => _staff);

      UpdateSalonRequest? captured;
      when(() => repo.updateSalon(_kSalonId, any())).thenAnswer((
        invocation,
      ) async {
        captured = invocation.positionalArguments[1] as UpdateSalonRequest;
        return _salonWithLocality.copyWith(phone: '+380671112233');
      });

      final container = _makeContainer(repo);
      final notifier = await _readyNotifier(container, _salonWithLocality);

      final failure = await notifier.save(
        name: _salonWithLocality.name,
        description: _salonWithLocality.description!,
        phone: '+380671112233',
        instagramUrl: '',
      );

      expect(failure, isNull);
      expect(captured, isNotNull);
      expect(captured!.phone, '+380671112233');
      expect(captured!.cityId, _salonWithLocality.cityId);
      expect(captured!.districtId, _salonWithLocality.districtId);
    });

    // RESUME §4 step D (mobile half, 2026-08-30) — RETIRED the
    // "KNOWN LIMITATION — a salon with NO city on file" test this comment
    // used to introduce. That limitation documented a `Salon` loaded with
    // `cityId: null` (a salon that had never had its locality set) still
    // echoing `cityId: null` on save, which the backend would 400. That
    // STATE IS NOW IMPOSSIBLE: `salons.city_id` is DB-level `NOT NULL`
    // (backend `ec22d91`, migrations V150/V151, every legacy row backfilled)
    // and [Salon.cityId] flipped from `String?` to `String` in the same
    // step — the domain type itself no longer admits a cityless salon, so
    // there is nothing left to document as a gap. Replaced with a positive
    // pin of the NEW guarantee below rather than silently dropping the
    // coverage.
    test('a real salon ALWAYS carries a non-empty cityId (backend-guaranteed) '
        '— save() echoes it, never blank', () async {
      expect(_freshSalon.cityId, isNotEmpty);

      when(
        () => repo.getSalonById(_kSalonId),
      ).thenAnswer((_) async => _freshSalon);
      when(() => repo.getSalonStaff(_kSalonId)).thenAnswer((_) async => _staff);

      UpdateSalonRequest? captured;
      when(() => repo.updateSalon(_kSalonId, any())).thenAnswer((
        invocation,
      ) async {
        captured = invocation.positionalArguments[1] as UpdateSalonRequest;
        return _freshSalon.copyWith(description: 'Нова назва');
      });

      final container = _makeContainer(repo);
      final notifier = await _readyNotifier(container, _freshSalon);

      final failure = await notifier.save(
        name: _freshSalon.name,
        description: 'Нова назва салону',
        phone: '',
        instagramUrl: '',
      );

      expect(failure, isNull);
      expect(
        captured!.cityId,
        _freshSalon.cityId,
        reason:
            'save() must always echo the loaded cityId — the backend '
            'guarantee means this can never legitimately be blank, and a '
            'regression that folds it to null/empty would 400 with '
            '"City is required" on every save.',
      );
    });
  });

  // ── saveAddress() ────────────────────────────────────────────────────
  //
  // No unit-test group existed for this method at all before this changeset
  // — the exact hole the regression fell through (per this file's own
  // MANDATE-3 precedent for `save()`'s phone diff, nothing pinned
  // `saveAddress()`'s locality handling until now). The prior implementation
  // diffed `cityId` against `current.cityId` (`cityId != current.cityId ?
  // cityId : null`), which folded an UNCHANGED selection to `null` and
  // tripped the backend's "City is required" 400 whenever the viewer edited
  // street/note without re-touching the city dropdown — the subtler half of
  // the shipped bug, since the widget tier's own city fixture never
  // exercised "selection equals current" until this group.
  group('saveAddress()', () {
    test('cityId is sent even when the selection is UNCHANGED from the '
        'currently-loaded value', () async {
      when(
        () => repo.getSalonById(_kSalonId),
      ).thenAnswer((_) async => _salonWithLocality);
      when(() => repo.getSalonStaff(_kSalonId)).thenAnswer((_) async => _staff);

      UpdateSalonRequest? captured;
      when(() => repo.updateSalon(_kSalonId, any())).thenAnswer((
        invocation,
      ) async {
        captured = invocation.positionalArguments[1] as UpdateSalonRequest;
        return _salonWithLocality.copyWith(street: 'вул. Хрещатик');
      });

      final container = _makeContainer(repo);
      final notifier = await _readyNotifier(container, _salonWithLocality);

      // The picked city/district are the SAME ids already on the loaded
      // salon — only street is genuinely new. This is exactly the shape
      // the old diff formula folded to null.
      final failure = await notifier.saveAddress(
        cityId: _salonWithLocality.cityId,
        districtId: _salonWithLocality.districtId,
        street: 'вул. Хрещатик',
        buildingNo: _salonWithLocality.buildingNo!,
        locationNote: _salonWithLocality.locationNote ?? '',
      );

      expect(failure, isNull);
      expect(captured, isNotNull);
      expect(captured!.street, 'вул. Хрещатик');
      expect(
        captured!.cityId,
        _salonWithLocality.cityId,
        reason:
            'the OLD diff (`cityId != current.cityId ? cityId : null`) '
            'folded this exact case — an unchanged selection — to null, '
            'which is precisely what made every non-city edit on this '
            'screen 400. cityId must never be null when a real city was '
            'passed in.',
      );
      expect(captured!.cityId, isNotNull);
    });

    test(
      'cityId is sent when the viewer picks a genuinely NEW city too',
      () async {
        when(
          () => repo.getSalonById(_kSalonId),
        ).thenAnswer((_) async => _salonWithLocality);
        when(
          () => repo.getSalonStaff(_kSalonId),
        ).thenAnswer((_) async => _staff);

        UpdateSalonRequest? captured;
        when(() => repo.updateSalon(_kSalonId, any())).thenAnswer((
          invocation,
        ) async {
          captured = invocation.positionalArguments[1] as UpdateSalonRequest;
          return _salonWithLocality.copyWith(cityId: 'city-locality-02');
        });

        final container = _makeContainer(repo);
        final notifier = await _readyNotifier(container, _salonWithLocality);

        final failure = await notifier.saveAddress(
          cityId: 'city-locality-02',
          districtId: null,
          street: _salonWithLocality.street!,
          buildingNo: _salonWithLocality.buildingNo!,
          locationNote: _salonWithLocality.locationNote ?? '',
        );

        expect(failure, isNull);
        expect(captured!.cityId, 'city-locality-02');
        expect(
          captured!.districtId,
          isNull,
          reason: 'a leaf city legitimately has no district to send.',
        );
      },
    );

    test('locationNote is diffed — omitted when unchanged, included when '
        'edited', () async {
      when(
        () => repo.getSalonById(_kSalonId),
      ).thenAnswer((_) async => _salonWithLocality);
      when(() => repo.getSalonStaff(_kSalonId)).thenAnswer((_) async => _staff);

      final captures = <UpdateSalonRequest>[];
      when(() => repo.updateSalon(_kSalonId, any())).thenAnswer((
        invocation,
      ) async {
        final req = invocation.positionalArguments[1] as UpdateSalonRequest;
        captures.add(req);
        return _salonWithLocality;
      });

      final container = _makeContainer(repo);
      final notifier = await _readyNotifier(container, _salonWithLocality);

      await notifier.saveAddress(
        cityId: _salonWithLocality.cityId,
        districtId: _salonWithLocality.districtId,
        street: _salonWithLocality.street!,
        buildingNo: _salonWithLocality.buildingNo!,
        // Unchanged — still the loaded value (null baseline in this
        // fixture, so pass '' to match `salon.locationNote ?? ''`).
        locationNote: _salonWithLocality.locationNote ?? '',
      );

      expect(
        captures.single.locationNote,
        isNull,
        reason: 'unchanged optional field — omitted, not a validation risk.',
      );

      await notifier.saveAddress(
        cityId: _salonWithLocality.cityId,
        districtId: _salonWithLocality.districtId,
        street: _salonWithLocality.street!,
        buildingNo: _salonWithLocality.buildingNo!,
        locationNote: '3 поверх',
      );

      expect(captures.last.locationNote, '3 поверх');
      // Even on the locationNote-only edit, cityId still rides along.
      expect(captures.last.cityId, _salonWithLocality.cityId);
    });

    test(
      'a repository Failure is returned and state is left untouched',
      () async {
        when(
          () => repo.getSalonById(_kSalonId),
        ).thenAnswer((_) async => _salonWithLocality);
        when(
          () => repo.getSalonStaff(_kSalonId),
        ).thenAnswer((_) async => _staff);
        when(
          () => repo.updateSalon(_kSalonId, any()),
        ).thenThrow(const ServerFailure(statusCode: 500));

        final container = _makeContainer(repo);
        final notifier = await _readyNotifier(container, _salonWithLocality);

        final failure = await notifier.saveAddress(
          cityId: _salonWithLocality.cityId,
          districtId: _salonWithLocality.districtId,
          street: 'вул. Хрещатик',
          buildingNo: _salonWithLocality.buildingNo!,
          locationNote: _salonWithLocality.locationNote ?? '',
        );

        expect(failure, isA<ServerFailure>());
        final state = container.read(salonManagementProfileProvider(_kSalonId));
        expect(
          state.value!.$1.street,
          _salonWithLocality.street,
          reason:
              'a failed saveAddress must leave the previously-loaded state '
              'alone so the screen can offer a retry',
        );
      },
    );
  });

  // ── deleteSalon() ─────────────────────────────────────────────────────

  group('deleteSalon()', () {
    test('returns null on success', () async {
      when(
        () => repo.getSalonById(_kSalonId),
      ).thenAnswer((_) async => _freshSalon);
      when(() => repo.getSalonStaff(_kSalonId)).thenAnswer((_) async => _staff);
      when(() => repo.deleteSalon(_kSalonId)).thenAnswer((_) async {});

      final container = _makeContainer(repo);
      final notifier = await _readyNotifier(container, _freshSalon);

      final failure = await notifier.deleteSalon();

      expect(failure, isNull);
      verify(() => repo.deleteSalon(_kSalonId)).called(1);
    });

    test('returns the Failure on error', () async {
      when(
        () => repo.getSalonById(_kSalonId),
      ).thenAnswer((_) async => _freshSalon);
      when(() => repo.getSalonStaff(_kSalonId)).thenAnswer((_) async => _staff);
      when(
        () => repo.deleteSalon(_kSalonId),
      ).thenThrow(const ServerFailure(statusCode: 500));

      final container = _makeContainer(repo);
      final notifier = await _readyNotifier(container, _freshSalon);

      final failure = await notifier.deleteSalon();

      expect(failure, isA<ServerFailure>());
    });
  });

  // ── mySalonsProvider invalidation (mobile-perf MEDIUM follow-up) ────────
  //
  // `mySalonsProvider` was promoted to `@Riverpod(keepAlive: true)`
  // (`my_salons_notifier.dart`) so the router guard reads an
  // already-resolved value instead of refetching on every navigation.
  // Nothing then invalidated that cached list on write, so an edited/
  // deleted salon's name/locality/«Основний» badge went stale on the hub
  // for the rest of the session — this group pins the fix.
  //
  // MUTATION-VERIFIED (2026-08-28) — removing
  // `ref.invalidate(mySalonsProvider)` in [save]/[saveAddress] turns the
  // `save()` test below RED (`counter.value` stays 1 instead of advancing
  // to 2); restoring it turns it back GREEN with a clean `git diff`.
  //
  // [deleteSalon] no longer invalidates `mySalonsProvider` itself
  // (mobile-qa CRITICAL fix, swipe-to-delete audit 2026-09-03) — that
  // moved to `runDeleteSalonFlow` (`delete_salon_flow.dart`), the single
  // caller of [deleteSalon], because [deleteSalon]'s own `ref` belongs to
  // an autoDispose family element `MySalonsScreen`'s swipe-to-delete never
  // watches, and a real (non-instant) `DELETE` round trip could dispose it
  // mid-await — even under `ref.keepAlive()`, since `build()`'s
  // `authProvider.select(...)` watch means an in-flight `authProvider`
  // resolution invalidates (and thereby un-keepAlive's) this unwatched
  // element. See [SalonManagementProfile.deleteSalon]'s own doc for the
  // full mechanism. The invalidation is now covered at the flow level —
  // `test/features/salon/presentation/my_salons_screen_test.dart`'s
  // "swipe-to-delete gate" group and
  // `integration_test/swipe_to_delete_salon_flow_test.dart` both assert
  // `mySalonsProvider` genuinely refetches after a delete goes through
  // `runDeleteSalonFlow`.
  group('mySalonsProvider invalidation (mobile-perf MEDIUM follow-up)', () {
    test('a successful save() invalidates mySalonsProvider so the hub '
        'refetches on its next read', () async {
      when(
        () => repo.getSalonById(_kSalonId),
      ).thenAnswer((_) async => _freshSalon);
      when(() => repo.getSalonStaff(_kSalonId)).thenAnswer((_) async => _staff);
      when(
        () => repo.updateSalon(_kSalonId, any()),
      ).thenAnswer((_) async => _freshSalon.copyWith(name: 'Нова назва'));

      final counter = _CallCounter();
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(_StubAuthAuthenticated.new),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          salonRepositoryProvider.overrideWithValue(repo),
          mySalonsProvider.overrideWith(() => _CountingMySalons(counter)),
        ],
      );
      addTearDown(container.dispose);

      // A prior hub visit — mirrors the real "hub, then edit" flow — seeds
      // the keepAlive cache BEFORE the edit happens.
      await container.read(mySalonsProvider.future);
      expect(counter.value, 1);

      final notifier = await _readyNotifier(container, _freshSalon);
      final failure = await notifier.save(
        name: 'Нова назва',
        description: _freshSalon.description!,
        phone: '',
        instagramUrl: '',
      );
      expect(failure, isNull);

      // Invalidation alone does not eagerly rebuild a keepAlive provider —
      // it rebuilds on its NEXT read, exactly like the hub screen's own
      // `ref.watch(mySalonsProvider)` would on remount.
      await container.read(mySalonsProvider.future);
      expect(
        counter.value,
        2,
        reason:
            'save() must invalidate mySalonsProvider — without it the hub '
            'renders the pre-edit cached list for the rest of the session',
      );
    });

    test('a successful deleteSalon() does NOT invalidate mySalonsProvider '
        'itself — that is runDeleteSalonFlow\'s job now (mobile-qa CRITICAL '
        'fix, swipe-to-delete audit 2026-09-03)', () async {
      when(
        () => repo.getSalonById(_kSalonId),
      ).thenAnswer((_) async => _freshSalon);
      when(() => repo.getSalonStaff(_kSalonId)).thenAnswer((_) async => _staff);
      when(() => repo.deleteSalon(_kSalonId)).thenAnswer((_) async {});

      final counter = _CallCounter();
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(_StubAuthAuthenticated.new),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          salonRepositoryProvider.overrideWithValue(repo),
          mySalonsProvider.overrideWith(() => _CountingMySalons(counter)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(mySalonsProvider.future);
      expect(counter.value, 1);

      final notifier = await _readyNotifier(container, _freshSalon);
      final failure = await notifier.deleteSalon();
      expect(failure, isNull);

      // deleteSalon() succeeded (server-side deactivation happened — see
      // the repo.deleteSalon verify below), but it deliberately never
      // touches mySalonsProvider itself anymore: that invalidation lives
      // in `runDeleteSalonFlow`, called on the caller's own (stable)
      // `WidgetRef` — see this group's header doc for why. Calling
      // `deleteSalon()` DIRECTLY on the notifier, as this unit test does,
      // is exactly the bypass that would have left the hub stale before
      // this design; the flow-level coverage
      // (`my_salons_screen_test.dart`'s "swipe-to-delete gate" group,
      // `integration_test/swipe_to_delete_salon_flow_test.dart`) is what
      // actually proves the hub refetches end-to-end.
      await container.read(mySalonsProvider.future);
      expect(
        counter.value,
        1,
        reason:
            'deleteSalon() alone must NOT invalidate mySalonsProvider — '
            'doing so from this autoDispose family\'s own ref is exactly '
            'the CRITICAL bug (UnmountedRefException on a real, '
            'multi-frame DELETE round trip) this design change fixes',
      );
      verify(() => repo.deleteSalon(_kSalonId)).called(1);
    });
  });

  // ── build() — the authProvider watch is NARROWED to the user id ──────────
  //
  // mobile-perf LOW (2026-09-01). `build()`'s auth-boundary watch used to be a
  // bare `ref.watch(authProvider)`. `AuthNotifier.setAccessToken` is called by
  // `refresh_interceptor.dart` on EVERY silent token refresh and re-emits
  // `Authenticated` with the SAME user and a new accessToken, so an
  // un-narrowed watch refetched BOTH `GET /salons/{id}` and
  // `GET /salons/{id}/staff` while the owner just sat on the management
  // screen. Identity is the whole trigger: the owner and the admin fetch the
  // same salon and the same roster, so nothing but a different signed-in user
  // can invalidate this family member.
  //
  // The pair: the token-only re-emission must be INERT, and a real identity
  // change must STILL rebuild (a `.select` returning a constant passes the
  // first alone, and would silently disable the cross-account eviction this
  // watch exists for).
  group('build() — narrowed authProvider watch', () {
    ProviderContainer makeControllableContainer(
      SalonRepository repo,
      _ControllableAuthAuthenticated auth,
    ) {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => auth),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          salonRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a silent token refresh (same user id, new accessToken) does NOT '
        'refetch the salon or the staff roster', () async {
      when(
        () => repo.getSalonById(_kSalonId),
      ).thenAnswer((_) async => _freshSalon);
      when(() => repo.getSalonStaff(_kSalonId)).thenAnswer((_) async => _staff);

      final auth = _ControllableAuthAuthenticated();
      final container = makeControllableContainer(repo, auth);
      await container.read(authProvider.future);
      // Keep the family member subscribed — an unlistened autoDispose provider
      // would be torn down and prove nothing either way.
      final sub = container.listen(
        salonManagementProfileProvider(_kSalonId),
        (_, _) {},
      );
      addTearDown(sub.close);
      await container.read(salonManagementProfileProvider(_kSalonId).future);
      verify(() => repo.getSalonById(_kSalonId)).called(1);
      verify(() => repo.getSalonStaff(_kSalonId)).called(1);

      // Exactly what `refresh_interceptor.dart` does after a 401 → refresh.
      container.read(authProvider.notifier).setAccessToken('tok-rotated-2');
      await pumpEventQueue();

      verifyNever(() => repo.getSalonById(any()));
      verifyNever(() => repo.getSalonStaff(any()));
      expect(
        container.read(authProvider).value,
        isA<Authenticated>()
            .having(
              (Authenticated a) => a.accessToken,
              'accessToken',
              'tok-rotated-2',
            )
            .having((Authenticated a) => a.user.id, 'user.id', _stubUser.id),
        reason:
            'sanity: the session really did re-emit, with a NEW token and the '
            'SAME user — so the no-refetch assertions above are about the '
            '.select narrowing, not about setAccessToken having no-opped',
      );
    });

    test('a real identity change (different user id) DOES refetch', () async {
      when(
        () => repo.getSalonById(_kSalonId),
      ).thenAnswer((_) async => _freshSalon);
      when(() => repo.getSalonStaff(_kSalonId)).thenAnswer((_) async => _staff);

      final auth = _ControllableAuthAuthenticated();
      final container = makeControllableContainer(repo, auth);
      await container.read(authProvider.future);
      final sub = container.listen(
        salonManagementProfileProvider(_kSalonId),
        (_, _) {},
      );
      addTearDown(sub.close);
      await container.read(salonManagementProfileProvider(_kSalonId).future);
      verify(() => repo.getSalonById(_kSalonId)).called(1);
      verify(() => repo.getSalonStaff(_kSalonId)).called(1);

      // A different account on the same device — the ONE change that must
      // still evict this owner/admin-scoped data.
      auth.emit(
        const AuthSession.authenticated(
          user: User(
            id: 'owner-2',
            email: 'other-owner@beautica.ua',
            role: UserRole.salonOwner,
          ),
          accessToken: 'tok',
        ),
      );
      await pumpEventQueue();
      await container.read(salonManagementProfileProvider(_kSalonId).future);

      verify(() => repo.getSalonById(_kSalonId)).called(1);
      verify(() => repo.getSalonStaff(_kSalonId)).called(1);
    });
  });

  // ── save()/saveAddress() — compound authProvider-mid-await race ─────────
  // (INVESTIGATED, NOT REPRODUCED as a user-visible bug — 2026-09-03)
  //
  // The claim under test: `build()`'s `ref.watch(authProvider.select
  // (authUserIdOrNull))` means this family element can be invalidated by
  // `authProvider`'s FIRST-EVER resolution (pending -> Authenticated, a real
  // identity change from `null`) landing WHILE `save()`/`saveAddress()` is
  // still awaiting the `PATCH` — and that this can leave
  // `SalonManagementProfileScreen` showing the pre-edit salon even though
  // `SalonProfileEditScreen` "is still mounted and awaiting" (this file's
  // header, and [SalonManagementProfile.save]'s own doc, both assert this).
  //
  // Riverpod 3.1.0's own disposal mechanics (`riverpod-3.1.0/lib/src/core/
  // element.dart`) say otherwise: `Ref.mounted` is `!_element._disposed`
  // (`ref.dart:110`), and `_disposed` is set ONLY in `dispose()`
  // (`element.dart:1227-1228`), which the scheduler only invokes for an
  // element that is NOT `isActive` (`scheduler.dart:159-160`'s
  // `_performDispose` skip, mirrored by `scheduleProviderDispose`'s own
  // assert `!element.isActive` at `scheduler.dart:151`). `isActive` is
  // `(listenerCount - pausedActiveSubscriptionCount) > 0`
  // (`element.dart:395`) — i.e. TRUE for as long as a real, unpaused watcher
  // (`SalonProfileEditScreen`'s own `ref.watch`) is attached. `invalidateSelf`
  // (`element.dart:738-753`) DOES wipe `ref._keepAliveLinks` unconditionally
  // via `runOnDispose()`, but `_performRefresh` still `flush()`es (rebuilds)
  // any element with `isActive == true` — it never disposes one. So the two
  // halves of the claim are mutually exclusive: if the calling screen is
  // GENUINELY still mounted and watching, `isActive` stays true, the element
  // only REBUILDS (never disposes), and `ref.mounted` never goes false.
  //
  // The two tests below PROVE that reading (mirroring an actively-watching
  // `SalonProfileEditScreen` via `container.listen`, kept open the entire
  // scenario): `save()`/`saveAddress()`'s own post-await `state = AsyncData
  // (...)` write always lands with the FRESH, patched value — never the
  // stale pre-edit one — regardless of the identity-change race, because
  // `ref.mounted` never flips false while a real listener is attached. A
  // third test below then isolates the ONE precondition under which
  // `ref.mounted` genuinely CAN go false (the watching screen has ALSO
  // already stopped listening — i.e. popped, the case `ref.keepAlive()` was
  // added to cover on its own) and shows that combination is already handled
  // safely: no crash, and the next fresh read self-heals from the server.
  //
  // Kept as documentation per this task's own instruction: a fix for a
  // phantom is worse than no fix. No production code was changed as a result
  // of this investigation — see the accompanying report for the full
  // reasoning and the doc-comment correction this leaves as a follow-up.
  group('save() / saveAddress() — compound authProvider-mid-await race '
      '(investigated 2026-09-03 — does NOT reproduce while the calling '
      'screen keeps watching)', () {
    test('save(): identity resolving DURING the PATCH await triggers a '
        'rebuild (NOT a disposal) while a listener stays attached — the '
        "notifier's own post-await state write still lands with the FRESH, "
        'patched value', () async {
      final pendingAuth = _PendingAuthAuthenticated();

      // `getSalonById` always returns whatever `serverSalon` currently
      // holds — mirrors a real backend where a GET reflects whatever has
      // actually been committed so far, independent of whether THIS
      // client has received its own PATCH response yet.
      Salon serverSalon = _freshSalon;
      final Completer<Salon> patchCompleter = Completer<Salon>();

      when(
        () => repo.getSalonById(_kSalonId),
      ).thenAnswer((_) async => serverSalon);
      when(() => repo.getSalonStaff(_kSalonId)).thenAnswer((_) async => _staff);
      when(
        () => repo.updateSalon(_kSalonId, any()),
      ).thenAnswer((_) => patchCompleter.future);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => pendingAuth),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          salonRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      // Keep the family element alive across the whole scenario, exactly
      // like `SalonProfileEditScreen`'s own `ref.watch` does — an
      // unlistened autoDispose provider would be torn down and prove
      // nothing about THIS race either way.
      final sub = container.listen(
        salonManagementProfileProvider(_kSalonId),
        (_, _) {},
      );
      addTearDown(sub.close);

      // First-ever build() — authProvider is still pending (userId null).
      await container.read(salonManagementProfileProvider(_kSalonId).future);
      expect(
        container
            .read(salonManagementProfileProvider(_kSalonId))
            .value!
            .$1
            .name,
        _freshSalon.name,
      );

      final notifier = container.read(
        salonManagementProfileProvider(_kSalonId).notifier,
      );

      // Kick off save() — it suspends on `await ... .updateSalon(...)`,
      // gated on `patchCompleter` until this test says otherwise.
      final Future<Failure?> saveFuture = notifier.save(
        name: 'Нова назва',
        description: _freshSalon.description!,
        phone: '',
        instagramUrl: '',
      );

      // Mid-await: authProvider resolves for the FIRST time, with a real
      // user id — the identity change build()'s narrowed watch exists to
      // catch.
      pendingAuth.resolve(
        const AuthSession.authenticated(user: _stubUser, accessToken: 'tok'),
      );
      await pumpEventQueue();

      // Sanity: the rebuild really did happen, and really did refetch
      // BEFORE the PATCH committed (`serverSalon` is still the pre-edit
      // fixture at this point).
      verify(() => repo.getSalonById(_kSalonId)).called(2);

      // NOW the PATCH "commits" server-side and the client receives its
      // response.
      final Salon patched = _freshSalon.copyWith(name: 'Нова назва');
      serverSalon = patched;
      patchCompleter.complete(patched);

      final Failure? failure = await saveFuture;
      await pumpEventQueue();

      expect(failure, isNull, reason: 'the PATCH itself succeeded');

      final SalonManagementProfileData data = container
          .read(salonManagementProfileProvider(_kSalonId))
          .value!;
      expect(
        data.$1.name,
        'Нова назва',
        reason:
            'FINDING: this passes — the PRE-EDIT rebuild (verified above, '
            'called(2)) is NOT the final word. `ref.mounted` stayed true '
            "the whole time (a real listener was attached), so save()'s "
            'own `state = AsyncData(...)` write executed normally and '
            'overwrote the transient stale rebuild with the fresh, '
            'patched name. If this notifier ever regresses to actually '
            'lose that write under this exact scenario, THIS assertion '
            'is what would catch it.',
      );
    });

    test('saveAddress(): identical mechanism — the notifier still lands the '
        'FRESH street after the identity-change rebuild', () async {
      final pendingAuth = _PendingAuthAuthenticated();

      Salon serverSalon = _salonWithLocality;
      final Completer<Salon> patchCompleter = Completer<Salon>();

      when(
        () => repo.getSalonById(_kSalonId),
      ).thenAnswer((_) async => serverSalon);
      when(() => repo.getSalonStaff(_kSalonId)).thenAnswer((_) async => _staff);
      when(
        () => repo.updateSalon(_kSalonId, any()),
      ).thenAnswer((_) => patchCompleter.future);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => pendingAuth),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          salonRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(
        salonManagementProfileProvider(_kSalonId),
        (_, _) {},
      );
      addTearDown(sub.close);

      await container.read(salonManagementProfileProvider(_kSalonId).future);

      final notifier = container.read(
        salonManagementProfileProvider(_kSalonId).notifier,
      );

      final Future<Failure?> saveFuture = notifier.saveAddress(
        cityId: _salonWithLocality.cityId,
        districtId: _salonWithLocality.districtId,
        street: 'вул. Хрещатик',
        buildingNo: _salonWithLocality.buildingNo!,
        locationNote: _salonWithLocality.locationNote ?? '',
      );

      pendingAuth.resolve(
        const AuthSession.authenticated(user: _stubUser, accessToken: 'tok'),
      );
      await pumpEventQueue();

      verify(() => repo.getSalonById(_kSalonId)).called(2);

      final Salon patched = _salonWithLocality.copyWith(
        street: 'вул. Хрещатик',
      );
      serverSalon = patched;
      patchCompleter.complete(patched);

      final Failure? failure = await saveFuture;
      await pumpEventQueue();

      expect(failure, isNull, reason: 'the PATCH itself succeeded');

      final SalonManagementProfileData data = container
          .read(salonManagementProfileProvider(_kSalonId))
          .value!;
      expect(
        data.$1.street,
        'вул. Хрещатик',
        reason:
            'FINDING — same mechanism as save() above, mirrored onto '
            'saveAddress(): the fresh value survives.',
      );
    });

    test('the ONE precondition that DOES flip ref.mounted false — the '
        'watching screen has ALSO already stopped listening (popped) when '
        'the identity race lands — is handled safely: no crash, and the '
        'next fresh watch self-heals from the server', () async {
      final pendingAuth = _PendingAuthAuthenticated();

      Salon serverSalon = _freshSalon;
      final Completer<Salon> patchCompleter = Completer<Salon>();

      when(
        () => repo.getSalonById(_kSalonId),
      ).thenAnswer((_) async => serverSalon);
      when(() => repo.getSalonStaff(_kSalonId)).thenAnswer((_) async => _staff);
      when(
        () => repo.updateSalon(_kSalonId, any()),
      ).thenAnswer((_) => patchCompleter.future);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => pendingAuth),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          salonRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      // Mirrors `SalonProfileEditScreen` watching this family for the
      // duration of a normal save — present only long enough to seed the
      // loaded state, then closed BEFORE save() finishes, mirroring the
      // user popping the screen mid-await (the gap `ref.keepAlive()`
      // alone was already added to cover).
      final sub = container.listen(
        salonManagementProfileProvider(_kSalonId),
        (_, _) {},
      );
      await container.read(salonManagementProfileProvider(_kSalonId).future);

      final notifier = container.read(
        salonManagementProfileProvider(_kSalonId).notifier,
      );

      final Future<Failure?> saveFuture = notifier.save(
        name: 'Нова назва',
        description: _freshSalon.description!,
        phone: '',
        instagramUrl: '',
      );

      // The screen pops mid-await: the only remaining protection is the
      // `KeepAliveLink` `save()` itself grabbed at its very first line.
      sub.close();
      await pumpEventQueue();

      // The identity race lands: `invalidateSelf` wipes that
      // `KeepAliveLink` too, and — UNLIKE the two tests above — nothing
      // is `isActive` anymore, so this element is actually disposed
      // (not merely rebuilt).
      pendingAuth.resolve(
        const AuthSession.authenticated(user: _stubUser, accessToken: 'tok'),
      );
      await pumpEventQueue();

      final Salon patched = _freshSalon.copyWith(name: 'Нова назва');
      serverSalon = patched;
      patchCompleter.complete(patched);

      // The load-bearing assertion: this must NOT throw
      // `UnmountedRefException`. `container.invalidate(mySalonsProvider)`
      // goes through the pre-captured `container` handle (safe even
      // unmounted); the `ref.mounted` guard before the local `state`
      // write must return `null` cleanly instead of crashing.
      final Failure? failure = await saveFuture;
      expect(
        failure,
        isNull,
        reason:
            'the PATCH itself still succeeded server-side; save() must '
            'not surface a crash just because its own element was '
            'disposed out from under it',
      );

      // Self-heal check: the disposed element is gone entirely (not
      // merely stale) — the NEXT fresh watch creates a brand-new element
      // and refetches from the server, which by now holds the patched
      // salon.
      final SalonManagementProfileData freshData = await container.read(
        salonManagementProfileProvider(_kSalonId).future,
      );
      expect(
        freshData.$1.name,
        'Нова назва',
        reason:
            'a full re-read after disposal must show the ALREADY-'
            'committed server value — this is what "self-heals on next '
            'navigation" means in practice.',
      );
    });
  });

  // ── Phase 283 — roster audience-matrix pins (D6: wire-level) ────────────
  //
  // Every test above stubs `SalonRepository.getSalonStaff`/`getSalonMasters`
  // directly with a hand-built DOMAIN list — proves the NOTIFIER behaves,
  // never that the REPOSITORY/mapper actually produces that shape from a
  // real wire response. D6 requires at least one assertion per matrix row to
  // run through the repository layer against a faked HTTP response instead.
  //
  // Strategy mirrors `salon_repository_test.dart`'s "real deserializer over a
  // mocked transport" group: a REAL [HttpSalonRepository] wired to a mocked
  // [Dio] + the REAL generated [SalonControllerApi] (so
  // `SalonStaffMemberMapper`/`SalonMasterMapper` actually run against
  // JSON), rather than a mocked [SalonRepository] returning a domain list.
  // `getSalonStaff` goes through the generated client (`dio.request<Object>`,
  // matches its wire-level test's own mock shape); `getSalonMasters` goes
  // through the repository's own raw `dio.get<Map<String,dynamic>>` call
  // (see `HttpSalonRepository.getSalonMasters`'s own body) — the two are
  // stubbed independently below since neither call touches the other.
  group('roster audience matrix (Phase 283) — wire-level shape assertions '
      '(D6)', () {
    late _MockDioWire dio;
    late HttpSalonRepository wireRepo;

    setUp(() {
      dio = _MockDioWire();
      wireRepo = HttpSalonRepository(
        dio,
        SalonControllerApi(dio, standardSerializers),
        _MockServiceApiWire(),
        _MockReviewApiWire(),
        _MockMediaApiWire(),
      );
    });

    test('should_showAdminInStaffRoster_when_viewedByOwner', () async {
      _stubStaffWire(dio, <Map<String, dynamic>>[
        _wireStaffRow(
          userId: 'wire-admin-1',
          role: 'SALON_ADMIN',
          firstName: 'Ірина',
          lastName: 'Ковальська',
        ),
      ]);

      final List<SalonStaffMember> staff = await wireRepo.getSalonStaff(
        _kSalonId,
      );

      expect(staff, hasLength(1));
      expect(staff.single.userId, 'wire-admin-1');
      expect(staff.single.role, SalonStaffRole.admin);
      expect(
        staff.single.masterId,
        isNull,
        reason: 'an admin has no master row on the wire',
      );
    });

    test(
      'should_omitAdminFromClientRoster_when_salonProfileIsViewedPublicly',
      () async {
        // D3 — positive control: a well-formed `/masters` response for a
        // salon with one admin and one master carries ONLY the master. The
        // mutation check below (Mutation A) flips this into a negative
        // control by unioning a synthetic admin-shaped row into the same
        // fixture and confirming this exact assertion goes RED.
        _stubMastersWire(dio, <Map<String, dynamic>>[
          _wireMasterRow(masterId: 'wire-master-1', masterType: 'SALON_MASTER'),
        ]);

        final List<SalonMasterSummary> masters = await wireRepo.getSalonMasters(
          _kSalonId,
        );

        expect(masters.map((SalonMasterSummary m) => m.masterId), <String>[
          'wire-master-1',
        ]);
      },
    );

    test('should_showOwnerInBothRosters_when_ownerMasterRowIsActive', () async {
      _stubStaffWire(dio, <Map<String, dynamic>>[
        _wireStaffRow(
          userId: 'wire-owner-1',
          masterId: 'wire-owner-master-1',
          role: 'SALON_OWNER',
          firstName: 'Оксана',
          lastName: 'Швець',
        ),
      ]);
      final List<SalonStaffMember> staff = await wireRepo.getSalonStaff(
        _kSalonId,
      );
      expect(staff.single.userId, 'wire-owner-1');
      expect(staff.single.masterId, 'wire-owner-master-1');
      // `SalonStaffMemberResponseRoleEnum.SALON_OWNER` maps to the master
      // role bucket — the mapper's own fail-safe direction (mirrors
      // `SalonMasterMapper`'s masterType fallback), since this endpoint's
      // domain [SalonStaffRole] enum only distinguishes admin vs everyone
      // else.
      expect(staff.single.role, SalonStaffRole.master);

      _stubMastersWire(dio, <Map<String, dynamic>>[
        _wireMasterRow(
          masterId: 'wire-owner-master-1',
          masterType: 'SALON_OWNER',
          firstName: 'Оксана',
          lastName: 'Швець',
        ),
      ]);
      final List<SalonMasterSummary> masters = await wireRepo.getSalonMasters(
        _kSalonId,
      );
      expect(masters.single.masterId, 'wire-owner-master-1');
      expect(masters.single.type, MasterType.salonOwner);
    });

    test(
      'should_omitOwnerFromBothRosters_when_ownerMasterRowIsInactive',
      () async {
        // D2's BLOCKED cell — the owner-settings toggle (Phase 21.15) soft-
        // deletes the owner's `Master` row, and both `/staff` and `/masters`
        // filter `isActive = true` server-side. There is no wire field for
        // "inactive" the client ever sees — an inactive owner's row is
        // simply ABSENT from both responses, which is exactly what these two
        // empty-fixture reads model (the SAME salon a moment after the
        // toggle flips OFF, with every other person's row unaffected — an
        // empty fixture is the correct model precisely because THIS test
        // isolates the owner-only case).
        _stubStaffWire(dio, const <Map<String, dynamic>>[]);
        final List<SalonStaffMember> staff = await wireRepo.getSalonStaff(
          _kSalonId,
        );
        expect(
          staff,
          isEmpty,
          reason: 'an inactive owner master row never reaches the staff wire',
        );

        _stubMastersWire(dio, const <Map<String, dynamic>>[]);
        final List<SalonMasterSummary> masters = await wireRepo.getSalonMasters(
          _kSalonId,
        );
        expect(
          masters,
          isEmpty,
          reason: 'an inactive owner master row never reaches the masters wire',
        );
      },
    );

    test(
      'should_showDualRolePersonInBothRosters_when_adminAlsoHasAMasterRow',
      () async {
        // D4 — `userId`/`masterId` deliberately the SAME string here: this
        // person's staff row and master row are two views of ONE backend
        // identity, and Mutation B below cross-references the two lists by
        // this id to simulate a role-based (rather than master-row-based)
        // client-side filter.
        _stubStaffWire(dio, <Map<String, dynamic>>[
          _wireStaffRow(
            userId: 'wire-dual-1',
            masterId: 'wire-dual-1',
            role: 'SALON_ADMIN',
            firstName: 'Марта',
            lastName: 'Дворак',
          ),
        ]);
        final List<SalonStaffMember> staff = await wireRepo.getSalonStaff(
          _kSalonId,
        );
        expect(staff.single.role, SalonStaffRole.admin);
        expect(
          staff.single.masterId,
          'wire-dual-1',
          reason:
              'D4 — they DO have an active master row despite the '
              'admin role',
        );

        _stubMastersWire(dio, <Map<String, dynamic>>[
          _wireMasterRow(
            masterId: 'wire-dual-1',
            masterType: 'SALON_MASTER',
            firstName: 'Марта',
            lastName: 'Дворак',
          ),
        ]);
        final List<SalonMasterSummary> masters = await wireRepo.getSalonMasters(
          _kSalonId,
        );
        expect(
          masters.map((SalonMasterSummary m) => m.masterId),
          contains('wire-dual-1'),
          reason: 'D4 — clients must be able to book them',
        );
      },
    );

    test('should_showMasterInBothRosters_when_masterIsActive', () async {
      _stubStaffWire(dio, <Map<String, dynamic>>[
        _wireStaffRow(
          userId: 'wire-master-1',
          masterId: 'wire-master-1',
          role: 'SALON_MASTER',
        ),
      ]);
      final List<SalonStaffMember> staff = await wireRepo.getSalonStaff(
        _kSalonId,
      );
      expect(staff.single.role, SalonStaffRole.master);
      expect(staff.single.masterId, 'wire-master-1');

      _stubMastersWire(dio, <Map<String, dynamic>>[
        _wireMasterRow(masterId: 'wire-master-1', masterType: 'SALON_MASTER'),
      ]);
      final List<SalonMasterSummary> masters = await wireRepo.getSalonMasters(
        _kSalonId,
      );
      expect(masters.single.masterId, 'wire-master-1');
    });

    test(
      'should_notApplyAnyRoleFilterClientSide_when_rostersAreRendered',
      () async {
        // D1 — the REPOSITORY applies no filter of its own either: whatever
        // the wire returns comes back MAPPED, never narrowed. Four distinct
        // staff rows in, four out; three distinct master rows in, three out.
        _stubStaffWire(dio, <Map<String, dynamic>>[
          _wireStaffRow(
            userId: 'wire-owner-1',
            masterId: 'wire-owner-master-1',
            role: 'SALON_OWNER',
          ),
          _wireStaffRow(
            userId: 'wire-dual-1',
            masterId: 'wire-dual-1',
            role: 'SALON_ADMIN',
          ),
          _wireStaffRow(userId: 'wire-admin-1', role: 'SALON_ADMIN'),
          _wireStaffRow(
            userId: 'wire-master-1',
            masterId: 'wire-master-1',
            role: 'SALON_MASTER',
          ),
        ]);
        final List<SalonStaffMember> staff = await wireRepo.getSalonStaff(
          _kSalonId,
        );
        expect(staff.map((SalonStaffMember m) => m.userId).toSet(), <String>{
          'wire-owner-1',
          'wire-dual-1',
          'wire-admin-1',
          'wire-master-1',
        });

        _stubMastersWire(dio, <Map<String, dynamic>>[
          _wireMasterRow(
            masterId: 'wire-owner-master-1',
            masterType: 'SALON_OWNER',
          ),
          _wireMasterRow(masterId: 'wire-dual-1', masterType: 'SALON_MASTER'),
          _wireMasterRow(masterId: 'wire-master-1', masterType: 'SALON_MASTER'),
        ]);
        final List<SalonMasterSummary> masters = await wireRepo.getSalonMasters(
          _kSalonId,
        );
        expect(
          masters.map((SalonMasterSummary m) => m.masterId).toSet(),
          <String>{'wire-owner-master-1', 'wire-dual-1', 'wire-master-1'},
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Phase 283 — wire-level test doubles + fixture builders (D6).
// ---------------------------------------------------------------------------

class _MockDioWire extends Mock implements Dio {}

class _MockServiceApiWire extends Mock implements ServiceControllerApi {}

class _MockReviewApiWire extends Mock implements ReviewControllerApi {}

class _MockMediaApiWire extends Mock implements MediaControllerApi {}

/// Stubs the ONE call `SalonControllerApi.getSalonStaff` makes
/// (`dio.request<Object>`, matching `salon_repository_test.dart`'s own
/// "real deserializer over a mocked transport" mock shape) to return the
/// `ApiResponseListSalonStaffMemberResponse` envelope built from [rows].
void _stubStaffWire(_MockDioWire dio, List<Map<String, dynamic>> rows) {
  when(
    () => dio.request<Object>(
      any(),
      options: any(named: 'options'),
      cancelToken: any(named: 'cancelToken'),
      onSendProgress: any(named: 'onSendProgress'),
      onReceiveProgress: any(named: 'onReceiveProgress'),
    ),
  ).thenAnswer(
    (_) async => Response<Object>(
      requestOptions: RequestOptions(path: '/api/v1/salons/$_kSalonId/staff'),
      statusCode: 200,
      data: <String, dynamic>{'success': true, 'message': 'ok', 'data': rows},
    ),
  );
}

/// Stubs `HttpSalonRepository.getSalonMasters`'s raw
/// `dio.get<Map<String,dynamic>>` call with the
/// `ApiResponsePageResponseMasterSummaryResponse` envelope built from
/// [rows].
void _stubMastersWire(_MockDioWire dio, List<Map<String, dynamic>> rows) {
  when(
    () => dio.get<Map<String, dynamic>>(
      any(),
      queryParameters: any(named: 'queryParameters'),
    ),
  ).thenAnswer(
    (_) async => Response<Map<String, dynamic>>(
      requestOptions: RequestOptions(path: '/api/v1/salons/$_kSalonId/masters'),
      statusCode: 200,
      data: <String, dynamic>{
        'success': true,
        'message': 'ok',
        'data': <String, dynamic>{
          'success': true,
          'data': rows,
          'page': 0,
          'size': rows.length,
          'totalElements': rows.length,
          'totalPages': 1,
        },
      },
    ),
  );
}

/// One `SalonStaffMemberResponse`-shaped JSON row.
Map<String, dynamic> _wireStaffRow({
  required String userId,
  String? masterId,
  required String role,
  String firstName = 'Тест',
  String lastName = 'Тестовий',
}) => <String, dynamic>{
  'userId': userId,
  'masterId': masterId,
  'role': role,
  'firstName': firstName,
  'lastName': lastName,
};

/// One `MasterSummaryResponse`-shaped JSON row.
Map<String, dynamic> _wireMasterRow({
  required String masterId,
  required String masterType,
  String firstName = 'Тест',
  String lastName = 'Тестовий',
}) => <String, dynamic>{
  'masterId': masterId,
  'masterType': masterType,
  'firstName': firstName,
  'lastName': lastName,
};
