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

import 'package:beautica_api/beautica_api.dart' show UpdateSalonRequest;
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
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
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
  // MUTATION-VERIFIED (2026-08-28) — removing either
  // `ref.invalidate(mySalonsProvider)` call in
  // `salon_management_profile_notifier.dart` turns its matching test below
  // RED (`counter.value` stays 1 instead of advancing to 2); restoring it
  // turns both back GREEN with a clean `git diff`.
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

    test('a successful deleteSalon() invalidates mySalonsProvider so the hub '
        'refetches on its next read', () async {
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

      await container.read(mySalonsProvider.future);
      expect(
        counter.value,
        2,
        reason:
            'deleteSalon() must invalidate mySalonsProvider — without it '
            'the hub keeps listing the deleted salon for the rest of the '
            'session',
      );
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
}
