// Phase 403 (9.8, D3) — portfolioProvider(PortfolioOwner): the salon read
// stays on SalonRepository (unchanged transport), the master read goes to
// MediaUploadRepository; 5-minute keepAlive cache; invalidation refetches;
// the master branch rebuilds on an account switch; salonPortfolioProvider is
// a delegate of the salon branch.

import 'dart:async';
import 'dart:io';

import 'package:beautica_mobile/core/media/portfolio/portfolio_notifier.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_owner.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart';
import 'package:beautica_mobile/core/media/upload/upload_task.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_portfolio_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_salon_repository.dart';

const PortfolioPhoto _salonPhoto = PortfolioPhoto(
  id: 's-1',
  url: 'https://m.test/salon.jpg',
);
const PortfolioPhoto _masterPhoto = PortfolioPhoto(
  id: 'm-1',
  url: 'https://m.test/master.jpg',
);

class _Salons extends FakeSalonRepository {
  _Salons()
    : super(
        salon: const Salon(id: 'salon-1', name: 'Салон'),
      );

  final List<String> portfolioReads = <String>[];

  /// When set, the NEXT read parks on it (taken once, then cleared).
  Completer<List<PortfolioPhoto>>? heldRead;

  @override
  Future<List<PortfolioPhoto>> getSalonPortfolio(String salonId) async {
    portfolioReads.add(salonId);
    final Completer<List<PortfolioPhoto>>? held = heldRead;
    heldRead = null;
    if (held != null) return held.future;
    return const <PortfolioPhoto>[_salonPhoto];
  }
}

class _Uploads implements MediaUploadRepository {
  final List<String> masterReads = <String>[];

  @override
  Future<List<PortfolioPhoto>> getMasterPortfolio(String masterId) async {
    masterReads.add(masterId);
    return const <PortfolioPhoto>[_masterPhoto];
  }

  @override
  UploadTask<PortfolioPhoto> uploadPortfolioPhoto(
    PortfolioOwner owner,
    File file,
  ) => throw UnimplementedError();

  @override
  Future<void> deletePortfolioPhoto(PortfolioOwner owner, String mediaId) =>
      throw UnimplementedError();

  @override
  UploadTask<String> uploadAvatar(File file) => throw UnimplementedError();

  @override
  Future<void> deleteAvatar() => throw UnimplementedError();

  @override
  UploadTask<String> uploadSalonImage(
    String salonId,
    SalonImageSlot slot,
    File file,
  ) => throw UnimplementedError();

  @override
  Future<void> deleteSalonImage(String salonId, SalonImageSlot slot) =>
      throw UnimplementedError();
}

class _Auth extends AuthNotifier {
  @override
  Future<AuthSession> build() async => _session('user-1');

  void switchTo(String id) => state = AsyncData<AuthSession>(_session(id));

  static AuthSession _session(String id) => AuthSession.authenticated(
    user: User(
      id: id,
      email: '$id@beautica.ua',
      role: UserRole.independentMaster,
    ),
    accessToken: 't',
  );
}

void main() {
  late _Salons salons;
  late _Uploads uploads;
  late ProviderContainer container;

  setUp(() async {
    salons = _Salons();
    uploads = _Uploads();
    container = ProviderContainer(
      overrides: [
        salonRepositoryProvider.overrideWithValue(salons),
        mediaUploadRepositoryProvider.overrideWithValue(uploads),
        authProvider.overrideWith(_Auth.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);
  });

  const PortfolioOwner salon = PortfolioOwner.salon('salon-1');
  const PortfolioOwner master = PortfolioOwner.masterSelf('master-1');

  test('salon → SalonRepository.getSalonPortfolio, never the master '
      'read', () async {
    expect(
      await container.read(portfolioProvider(salon).future),
      <PortfolioPhoto>[_salonPhoto],
    );
    expect(salons.portfolioReads, <String>['salon-1']);
    expect(uploads.masterReads, isEmpty);
  });

  test('master → MediaUploadRepository.getMasterPortfolio, never the salon '
      'read', () async {
    expect(
      await container.read(portfolioProvider(master).future),
      <PortfolioPhoto>[_masterPhoto],
    );
    expect(uploads.masterReads, <String>['master-1']);
    expect(salons.portfolioReads, isEmpty);
  });

  test('cached within the TTL after the last listener leaves (no '
      'refetch)', () async {
    final ProviderSubscription<AsyncValue<List<PortfolioPhoto>>> sub = container
        .listen(portfolioProvider(salon), (_, _) {});
    await container.read(portfolioProvider(salon).future);
    sub.close();
    await Future<void>.delayed(Duration.zero);
    await container.read(portfolioProvider(salon).future);
    expect(salons.portfolioReads, hasLength(1));
  });

  test('invalidate → refetch', () async {
    container.listen(portfolioProvider(master), (_, _) {});
    await container.read(portfolioProvider(master).future);
    container.invalidate(portfolioProvider(master));
    await container.read(portfolioProvider(master).future);
    expect(uploads.masterReads, hasLength(2));
  });

  test('the master portfolio rebuilds on an account switch', () async {
    container.listen(portfolioProvider(master), (_, _) {});
    await container.read(portfolioProvider(master).future);
    (container.read(authProvider.notifier) as _Auth).switchTo('user-2');
    await container.read(portfolioProvider(master).future);
    expect(uploads.masterReads, hasLength(2));
  });

  test('owners are value-keyed: equal owners share one cache entry, salon '
      'and master never do', () async {
    container.listen(portfolioProvider(salon), (_, _) {});
    await container.read(portfolioProvider(salon).future);
    await container.read(
      portfolioProvider(const PortfolioOwner.salon('salon-1')).future,
    );
    expect(salons.portfolioReads, hasLength(1));
    expect(
      const PortfolioOwner.salon('x'),
      isNot(const PortfolioOwner.masterSelf('x')),
    );
  });

  group('local patches (prependLocal / removeLocal)', () {
    const PortfolioPhoto newer = PortfolioPhoto(
      id: 's-2',
      url: 'https://m.test/newer.jpg',
    );

    test('while the read is still LOADING, both refuse (false) and leave '
        'the state alone — the caller must invalidate instead', () async {
      final Completer<List<PortfolioPhoto>> held =
          Completer<List<PortfolioPhoto>>();
      salons.heldRead = held;
      container.listen(portfolioProvider(salon), (_, _) {});
      final PortfolioNotifier n = container.read(
        portfolioProvider(salon).notifier,
      );

      expect(n.prependLocal(newer), isFalse);
      expect(n.removeLocal('s-1'), isFalse);
      expect(container.read(portfolioProvider(salon)).isLoading, isTrue);

      held.complete(const <PortfolioPhoto>[_salonPhoto]);
      expect(
        await container.read(portfolioProvider(salon).future),
        const <PortfolioPhoto>[_salonPhoto],
      );
    });

    test('prependLocal puts the photo FIRST and is idempotent on id', () async {
      container.listen(portfolioProvider(salon), (_, _) {});
      await container.read(portfolioProvider(salon).future);
      final PortfolioNotifier n = container.read(
        portfolioProvider(salon).notifier,
      );

      expect(n.prependLocal(newer), isTrue);
      expect(n.prependLocal(newer), isTrue);

      expect(
        container.read(portfolioProvider(salon)).value,
        const <PortfolioPhoto>[newer, _salonPhoto],
      );
    });

    test('removeLocal of an unknown id is a patched no-op (true, list '
        'unchanged)', () async {
      container.listen(portfolioProvider(salon), (_, _) {});
      await container.read(portfolioProvider(salon).future);
      final PortfolioNotifier n = container.read(
        portfolioProvider(salon).notifier,
      );

      expect(n.removeLocal('nope'), isTrue);
      expect(
        container.read(portfolioProvider(salon)).value,
        const <PortfolioPhoto>[_salonPhoto],
      );
      expect(salons.portfolioReads, hasLength(1), reason: 'no refetch');
    });
  });

  group('salonPortfolioProvider (D3 delegate)', () {
    test('serves the shared salon branch', () async {
      expect(
        await container.read(salonPortfolioProvider('salon-1').future),
        <PortfolioPhoto>[_salonPhoto],
      );
      expect(salons.portfolioReads, <String>['salon-1']);
    });

    test('invalidating the shared provider reaches the delegate', () async {
      container.listen(salonPortfolioProvider('salon-1'), (_, _) {});
      await container.read(salonPortfolioProvider('salon-1').future);
      container.invalidate(portfolioProvider(salon));
      await container.read(salonPortfolioProvider('salon-1').future);
      expect(salons.portfolioReads, hasLength(2));
    });
  });
}
