// Phase 369 audit (MASVS-AUTH LOW, defence in depth) — `applySalonImageUrl`'s
// fallback: whenever a cached salon provider's `patchImage` declines (not a
// SETTLED AsyncData — loading, refreshing, or an error carrying a stale
// value — or, for the hub list, a settled list without this salon), the sink
// INVALIDATES it so the server's answer replaces the stale snapshot. It used
// to invalidate `mySalonsProvider` only when `.value == null`, so a stale
// refreshing / errored list (which still HAS a value) was neither patched nor
// refetched-by-us.
//
// Pure Dart — no widget tree. The sink needs a `Ref`, so a tiny test-only
// notifier hands its own `ref` to [applySalonImageUrl].

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart'
    show SalonImageSlot;
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_image_patch.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

class _MockSalonRepository extends Mock implements SalonRepository {}

const String _kSalonId = 'salon-1';
const String _kLogo = 'https://cdn.beautica.ua/salons/salon-1/logo.webp';

const _owner = User(
  id: 'owner-1',
  email: 'owner@beautica.ua',
  role: UserRole.salonOwner,
);

const _salon = Salon(id: _kSalonId, name: 'Салон «Вельвет»');
const _otherSalon = Salon(id: 'salon-2', name: 'Студія');

class _StubAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() => Future.value(
    const AuthSession.authenticated(user: _owner, accessToken: 'tok'),
  );
}

/// Test-only sink host: exposes its own `Ref` to [applySalonImageUrl].
class _Sink extends Notifier<int> {
  @override
  int build() => 0;

  void apply(SalonImageSlot slot, String? url) =>
      applySalonImageUrl(ref, _kSalonId, slot, url);
}

final _sinkProvider = NotifierProvider<_Sink, int>(_Sink.new);

void main() {
  late _MockSalonRepository repo;

  setUp(() {
    repo = _MockSalonRepository();
    when(
      () => repo.getSalonStaff(_kSalonId),
    ).thenAnswer((_) async => const <SalonStaffMember>[]);
  });

  Future<ProviderContainer> makeContainer() async {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        authProvider.overrideWith(_StubAuth.new),
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        salonRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);
    return container;
  }

  group('settledValueOrNull', () {
    test('AsyncData -> value; AsyncLoading / AsyncError -> null', () {
      expect(settledValueOrNull(const AsyncData<int>(1)), 1);
      expect(settledValueOrNull(const AsyncLoading<int>()), isNull);
      expect(
        settledValueOrNull(const AsyncError<int>('boom', StackTrace.empty)),
        isNull,
      );
    });
  });

  group('applySalonImageUrl — mySalonsProvider', () {
    Future<ProviderContainer> settledHub(List<Salon> list) async {
      when(() => repo.getMySalons()).thenAnswer((_) async => list);
      final container = await makeContainer();
      final sub = container.listen(mySalonsProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(mySalonsProvider.future);
      clearInteractions(repo);
      return container;
    }

    test('settled list WITH the salon: patched in place, no refetch', () async {
      final container = await settledHub(const <Salon>[_salon]);

      container.read(_sinkProvider.notifier).apply(SalonImageSlot.logo, _kLogo);
      await pumpEventQueue();

      expect(container.read(mySalonsProvider).value?.single.avatarUrl, _kLogo);
      verifyNever(() => repo.getMySalons());
    });

    test('settled list WITHOUT the salon: refetched', () async {
      final container = await settledHub(const <Salon>[_otherSalon]);

      container.read(_sinkProvider.notifier).apply(SalonImageSlot.logo, _kLogo);
      await pumpEventQueue();

      verify(() => repo.getMySalons()).called(1);
    });

    test('refreshing with a stale list: not patched, refetched — and the '
        "server's answer (not the stale list) is what resolves", () async {
      final container = await settledHub(const <Salon>[_salon]);
      final Completer<List<Salon>> pending = Completer<List<Salon>>();
      when(() => repo.getMySalons()).thenAnswer((_) => pending.future);
      container.invalidate(mySalonsProvider);
      container.read(mySalonsProvider);
      clearInteractions(repo);

      container.read(_sinkProvider.notifier).apply(SalonImageSlot.logo, _kLogo);
      container.read(mySalonsProvider);
      await pumpEventQueue();

      expect(container.read(mySalonsProvider).isLoading, isTrue);
      verify(() => repo.getMySalons()).called(1);
    });

    test('errored with a stale list: not patched, refetched', () async {
      final container = await settledHub(const <Salon>[_salon]);
      when(
        () => repo.getMySalons(),
      ).thenAnswer((_) async => throw const NetworkFailure());
      container.invalidate(mySalonsProvider);
      container.read(mySalonsProvider);
      await pumpEventQueue();
      expect(container.read(mySalonsProvider), isA<AsyncError<List<Salon>>>());
      when(() => repo.getMySalons()).thenAnswer((_) async => [_salon]);
      clearInteractions(repo);

      container.read(_sinkProvider.notifier).apply(SalonImageSlot.logo, _kLogo);
      await container.read(mySalonsProvider.future);

      verify(() => repo.getMySalons()).called(1);
      final state = container.read(mySalonsProvider);
      expect(state, isA<AsyncData<List<Salon>>>());
      expect(state.value?.single.avatarUrl, isNull, reason: 'server answer');
    });
  });

  group('applySalonImageUrl — salonManagementProfileProvider', () {
    final manage = salonManagementProfileProvider(_kSalonId);

    test('errored with a stale snapshot: not patched, refetched', () async {
      when(() => repo.getSalonById(_kSalonId)).thenAnswer((_) async => _salon);
      final container = await makeContainer();
      final sub = container.listen(manage, (_, _) {});
      addTearDown(sub.close);
      await container.read(manage.future);

      when(
        () => repo.getSalonById(_kSalonId),
      ).thenAnswer((_) async => throw const NetworkFailure());
      container.invalidate(manage);
      container.read(manage);
      await pumpEventQueue();
      expect(container.read(manage), isA<AsyncError<Object?>>());
      when(() => repo.getSalonById(_kSalonId)).thenAnswer((_) async => _salon);
      clearInteractions(repo);

      container.read(_sinkProvider.notifier).apply(SalonImageSlot.logo, _kLogo);
      await container.read(manage.future);

      verify(() => repo.getSalonById(_kSalonId)).called(1);
      expect(container.read(manage).value?.$1.avatarUrl, isNull);
    });
  });
}
