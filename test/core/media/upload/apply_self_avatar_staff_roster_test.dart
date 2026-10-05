// Team-tab fix (2026-10-05) — `applySelfAvatarUrl` also patches the viewer's
// OWN row in every cached «Команда» roster (`salonManagementProfileProvider`).
//
// Before: only the session `User` and `masterProfileProvider` were patched, so
// the owner-master's / admin's own staff card stayed on the old photo for as
// long as the shell kept the roster alive (its only rebuild key is the user
// id). These tests pin: patched in place when settled (no second
// `GET …/staff`), refetched when unsettled or when the viewer is absent, the
// owner's salon set taken from `mySalonsProvider` only when it exists, the
// admin's from the session, and a client building NOTHING salon-side.
//
// Pure Dart — the sink needs a `Ref`, so a tiny test-only notifier hands its
// own `ref` to [applySelfAvatarUrl] (same harness as
// `salon_image_patch_test.dart`).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/media/upload/upload_target_binding.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_staff_member_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

class _MockSalonRepository extends Mock implements SalonRepository {}

const String _kSalonId = 'salon-1';
const String _kOld = 'https://cdn.beautica.ua/users/old.webp';
const String _kNew = 'https://cdn.beautica.ua/users/new.webp';

const User _owner = User(
  id: 'owner-1',
  email: 'owner@beautica.ua',
  role: UserRole.salonOwner,
);
const User _admin = User(
  id: 'admin-1',
  email: 'admin@beautica.ua',
  role: UserRole.salonAdmin,
  salonId: _kSalonId,
);
const User _client = User(
  id: 'client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
);

const Salon _salon = Salon(id: _kSalonId, name: 'Салон «Вельвет»');

const SalonStaffMember _ownerRow = SalonStaffMember(
  userId: 'owner-1',
  masterId: 'm-owner',
  role: SalonStaffRole.master,
  firstName: 'Олена',
  lastName: 'Власниця',
  avatarUrl: _kOld,
);
const SalonStaffMember _adminRow = SalonStaffMember(
  userId: 'admin-1',
  role: SalonStaffRole.admin,
  firstName: 'Ірина',
  lastName: 'Адмін',
  avatarUrl: _kOld,
);
const SalonStaffMember _otherRow = SalonStaffMember(
  userId: 'other-1',
  masterId: 'm-other',
  role: SalonStaffRole.master,
  firstName: 'Марта',
  lastName: 'Майстриня',
  avatarUrl: _kOld,
);

const List<SalonStaffMember> _roster = <SalonStaffMember>[
  _ownerRow,
  _adminRow,
  _otherRow,
];

class _StubAuth extends AuthNotifier {
  _StubAuth(this._user);
  final User _user;

  @override
  Future<AuthSession> build() =>
      Future.value(AuthSession.authenticated(user: _user, accessToken: 'tok'));

  /// A post-settle refresh that FAILED: `AsyncError` still carrying the
  /// settled session on `.value` — the shape the STRICT role selector exists
  /// to reject (`copyWithPrevious` is `@internal`; used deliberately, as in
  /// `auth_redirect_stale_role_forward_test.dart`).
  void markStale() {
    final AsyncError<AuthSession> failed = AsyncError<AuthSession>(
      StateError('refresh failed'),
      StackTrace.current,
    );
    // ignore: invalid_use_of_internal_member
    state = failed.copyWithPrevious(state);
  }
}

/// Test-only sink host: exposes its own `Ref` to [applySelfAvatarUrl].
class _Sink extends Notifier<int> {
  @override
  int build() => 0;

  void apply(String? url) => applySelfAvatarUrl(ref, url);
}

final _sinkProvider = NotifierProvider<_Sink, int>(_Sink.new);

SalonStaffMember _row(ProviderContainer c, String userId) => c
    .read(salonManagementProfileProvider(_kSalonId))
    .requireValue
    .$2
    .firstWhere((SalonStaffMember m) => m.userId == userId);

void main() {
  late _MockSalonRepository repo;
  final manage = salonManagementProfileProvider(_kSalonId);

  setUp(() {
    repo = _MockSalonRepository();
    when(() => repo.getSalonById(_kSalonId)).thenAnswer((_) async => _salon);
    when(() => repo.getSalonStaff(_kSalonId)).thenAnswer((_) async => _roster);
    when(
      () => repo.getMySalons(),
    ).thenAnswer((_) async => const <Salon>[_salon]);
  });

  Future<ProviderContainer> makeContainer(User user) async {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        authProvider.overrideWith(() => _StubAuth(user)),
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        salonRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);
    return container;
  }

  /// Keeps [manage] alive (as the shell's IndexedStack does) and settles it.
  Future<void> settleRoster(ProviderContainer c) async {
    final sub = c.listen(manage, (_, _) {});
    addTearDown(sub.close);
    await c.read(manage.future);
  }

  Future<void> settleHub(ProviderContainer c) async {
    final sub = c.listen(mySalonsProvider, (_, _) {});
    addTearDown(sub.close);
    await c.read(mySalonsProvider.future);
  }

  group('SALON_OWNER', () {
    test('settled roster with the owner: own row patched in place, '
        'nobody else touched, no second GET', () async {
      final c = await makeContainer(_owner);
      await settleHub(c);
      await settleRoster(c);
      clearInteractions(repo);

      c.read(_sinkProvider.notifier).apply(_kNew);
      await pumpEventQueue();

      expect(_row(c, 'owner-1').avatarUrl, _kNew);
      expect(_row(c, 'admin-1').avatarUrl, _kOld);
      expect(_row(c, 'other-1').avatarUrl, _kOld);
      expect(c.read(manage), isA<AsyncData<Object?>>());
      verifyNever(() => repo.getSalonStaff(any()));
      verifyNever(() => repo.getSalonById(any()));
      verifyNever(() => repo.getMySalons());
    });

    test('removal (null) is patched too', () async {
      final c = await makeContainer(_owner);
      await settleHub(c);
      await settleRoster(c);
      clearInteractions(repo);

      c.read(_sinkProvider.notifier).apply(null);
      await pumpEventQueue();

      expect(_row(c, 'owner-1').avatarUrl, isNull);
      verifyNever(() => repo.getSalonStaff(any()));
    });

    test('roster still loading: not patched, refetched — the server answer '
        'resolves', () async {
      final c = await makeContainer(_owner);
      await settleHub(c);
      final Completer<List<SalonStaffMember>> pending =
          Completer<List<SalonStaffMember>>();
      when(
        () => repo.getSalonStaff(_kSalonId),
      ).thenAnswer((_) => pending.future);
      final sub = c.listen(manage, (_, _) {});
      addTearDown(sub.close);
      expect(c.read(manage).isLoading, isTrue);
      when(() => repo.getSalonStaff(_kSalonId)).thenAnswer(
        (_) async => <SalonStaffMember>[_ownerRow.copyWith(avatarUrl: _kNew)],
      );
      clearInteractions(repo);

      c.read(_sinkProvider.notifier).apply(_kNew);
      await c.read(manage.future);

      verify(() => repo.getSalonStaff(_kSalonId)).called(1);
      expect(_row(c, 'owner-1').avatarUrl, _kNew);
    });

    test('settled roster WITHOUT the owner: refetched', () async {
      when(
        () => repo.getSalonStaff(_kSalonId),
      ).thenAnswer((_) async => const <SalonStaffMember>[_otherRow]);
      final c = await makeContainer(_owner);
      await settleHub(c);
      await settleRoster(c);
      clearInteractions(repo);

      c.read(_sinkProvider.notifier).apply(_kNew);
      await c.read(manage.future);

      verify(() => repo.getSalonStaff(_kSalonId)).called(1);
    });

    test('salons list never built: the live roster is refetched, '
        'mySalonsProvider is NOT built', () async {
      final c = await makeContainer(_owner);
      await settleRoster(c);
      clearInteractions(repo);

      c.read(_sinkProvider.notifier).apply(_kNew);
      await c.read(manage.future);

      verify(() => repo.getSalonStaff(_kSalonId)).called(1);
      expect(c.exists(mySalonsProvider), isFalse);
      verifyNever(() => repo.getMySalons());
    });

    test('roster never built: nothing is built or fetched', () async {
      final c = await makeContainer(_owner);
      await settleHub(c);
      clearInteractions(repo);

      c.read(_sinkProvider.notifier).apply(_kNew);
      await pumpEventQueue();

      expect(c.exists(manage), isFalse);
      verifyNever(() => repo.getSalonStaff(any()));
      verifyNever(() => repo.getSalonById(any()));
      verifyNever(() => repo.getMySalons());
    });
  });

  group('SALON_ADMIN', () {
    test('settled roster with the admin: own row patched in place, no GET, '
        'mySalonsProvider not built', () async {
      final c = await makeContainer(_admin);
      await settleRoster(c);
      clearInteractions(repo);

      c.read(_sinkProvider.notifier).apply(_kNew);
      await pumpEventQueue();

      expect(_row(c, 'admin-1').avatarUrl, _kNew);
      expect(_row(c, 'owner-1').avatarUrl, _kOld);
      verifyNever(() => repo.getSalonStaff(any()));
      verifyNever(() => repo.getSalonById(any()));
      expect(c.exists(mySalonsProvider), isFalse);
    });

    test('roster still loading: refetched', () async {
      final c = await makeContainer(_admin);
      final Completer<List<SalonStaffMember>> pending =
          Completer<List<SalonStaffMember>>();
      when(
        () => repo.getSalonStaff(_kSalonId),
      ).thenAnswer((_) => pending.future);
      final sub = c.listen(manage, (_, _) {});
      addTearDown(sub.close);
      when(
        () => repo.getSalonStaff(_kSalonId),
      ).thenAnswer((_) async => _roster);
      clearInteractions(repo);

      c.read(_sinkProvider.notifier).apply(_kNew);
      await c.read(manage.future);

      verify(() => repo.getSalonStaff(_kSalonId)).called(1);
    });

    test('salonStaffMemberProfileProvider (the member detail) follows the '
        'patch', () async {
      final c = await makeContainer(_admin);
      await settleRoster(c);
      final detail = salonStaffMemberProfileProvider(_kSalonId, 'admin-1');
      final sub = c.listen(detail, (_, _) {});
      addTearDown(sub.close);
      expect((await c.read(detail.future)).$1.avatarUrl, _kOld);
      clearInteractions(repo);

      c.read(_sinkProvider.notifier).apply(_kNew);
      await pumpEventQueue();

      expect((await c.read(detail.future)).$1.avatarUrl, _kNew);
      verifyNever(() => repo.getSalonStaff(any()));
    });
  });

  // «Upload binding reads the settled role» (2026-10-05): a role carried on
  // an in-flight / failed-refresh session must not steer a roster write.
  group('stale (unsettled) session', () {
    test('SALON_OWNER on a failed-refresh session: the roster is neither '
        'patched nor refetched', () async {
      final c = await makeContainer(_owner);
      await settleHub(c);
      await settleRoster(c);
      (c.read(authProvider.notifier) as _StubAuth).markStale();
      expect(c.read(authProvider), isA<AsyncError<AuthSession>>());
      clearInteractions(repo);

      c.read(_sinkProvider.notifier).apply(_kNew);
      await pumpEventQueue();

      expect(_row(c, 'owner-1').avatarUrl, _kOld);
      verifyNever(() => repo.getSalonStaff(any()));
      verifyNever(() => repo.getSalonById(any()));
    });

    test('SALON_ADMIN on a failed-refresh session: the roster is neither '
        'patched nor refetched', () async {
      final c = await makeContainer(_admin);
      await settleRoster(c);
      (c.read(authProvider.notifier) as _StubAuth).markStale();
      clearInteractions(repo);

      c.read(_sinkProvider.notifier).apply(_kNew);
      await pumpEventQueue();

      expect(_row(c, 'admin-1').avatarUrl, _kOld);
      verifyNever(() => repo.getSalonStaff(any()));
    });

    // Source fix (2026-10-05): `AuthNotifier.patchAvatarUrl` itself reads the
    // SETTLED value, so the session is never promoted — independent of the
    // read-before-patch order in `applySelfAvatarUrl`.
    test('the stale session itself is NOT promoted to settled', () async {
      final c = await makeContainer(_admin);
      (c.read(authProvider.notifier) as _StubAuth).markStale();

      expect(c.read(authProvider.notifier).patchAvatarUrl(_kNew), isFalse);
      c.read(_sinkProvider.notifier).apply(_kNew);
      await pumpEventQueue();

      final AsyncValue<AuthSession> after = c.read(authProvider);
      expect(after, isA<AsyncError<AuthSession>>());
      expect(authUserRoleSettledOrNull(after), isNull);
      expect(authUserSalonIdSettledOrNull(after), isNull);
      final AuthSession? carried = after.value;
      expect(carried, isA<Authenticated>());
      expect((carried as Authenticated).user.avatarUrl, isNot(_kNew));
    });
  });

  group('CLIENT', () {
    test('no salon provider is built, nothing is fetched', () async {
      final c = await makeContainer(_client);
      clearInteractions(repo);

      c.read(_sinkProvider.notifier).apply(_kNew);
      await pumpEventQueue();

      expect(c.exists(manage), isFalse);
      expect(c.exists(mySalonsProvider), isFalse);
      verifyZeroInteractions(repo);
      final AuthSession? s = c.read(authProvider).value;
      expect(s is Authenticated ? s.user.avatarUrl : null, _kNew);
    });
  });
}
