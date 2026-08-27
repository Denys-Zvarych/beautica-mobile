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
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';

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
const _freshSalon = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  description: 'Затишний салон краси.',
  street: 'вул. Велика Васильківська',
  buildingNo: '44',
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

const _masters = <SalonMasterSummary>[];

class _StubAuthAuthenticated extends AuthNotifier {
  @override
  Future<AuthSession> build() => Future.value(
    const AuthSession.authenticated(user: _stubUser, accessToken: 'tok'),
  );
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
      when(
        () => repo.getSalonMasters(_kSalonId),
      ).thenAnswer((_) async => _masters);

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
      when(
        () => repo.getSalonMasters(_kSalonId),
      ).thenAnswer((_) async => _masters);

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
            (_) => (const Salon(id: '', name: ''), <SalonMasterSummary>[]),
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
      when(
        () => repo.getSalonMasters(_kSalonId),
      ).thenAnswer((_) async => _masters);

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
          () => repo.getSalonMasters(_kSalonId),
        ).thenAnswer((_) async => _masters);

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
      when(
        () => repo.getSalonMasters(_kSalonId),
      ).thenAnswer((_) async => _masters);

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
          () => repo.getSalonMasters(_kSalonId),
        ).thenAnswer((_) async => _masters);
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

  // ── deleteSalon() ─────────────────────────────────────────────────────

  group('deleteSalon()', () {
    test('returns null on success', () async {
      when(
        () => repo.getSalonById(_kSalonId),
      ).thenAnswer((_) async => _freshSalon);
      when(
        () => repo.getSalonMasters(_kSalonId),
      ).thenAnswer((_) async => _masters);
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
      when(
        () => repo.getSalonMasters(_kSalonId),
      ).thenAnswer((_) async => _masters);
      when(
        () => repo.deleteSalon(_kSalonId),
      ).thenThrow(const ServerFailure(statusCode: 500));

      final container = _makeContainer(repo);
      final notifier = await _readyNotifier(container, _freshSalon);

      final failure = await notifier.deleteSalon();

      expect(failure, isA<ServerFailure>());
    });
  });
}
