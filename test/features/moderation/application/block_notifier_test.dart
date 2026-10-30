// Phase 425 — ClientBlockController: block / unblock through the repository,
// failure classification, D6 (refresh ONLY the booking detail + the block
// list on success), the single-DELETE unblock, and the in-flight guard
// (security MEDIUM: a call ignored while another write is in flight returns
// [BlockWriteInProgress], never a success).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/application/salon_board_refresh_gate.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/moderation/application/block_notifier.dart';
import 'package:beautica_mobile/features/moderation/application/blocked_list_notifier.dart';
import 'package:beautica_mobile/features/moderation/data/block_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/client_block.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_client_block_repository.dart';

Booking _booking(String id) => Booking(
  id: id,
  masterId: 'm1',
  masterFirstName: 'Марія',
  masterLastName: 'Іванюк',
  masterType: 'INDEPENDENT_MASTER',
  serviceId: 's1',
  serviceName: 'Манікюр',
  durationMinutes: 60,
  price: 500,
  startAt: DateTime.utc(2030, 1, 1, 10),
  endAt: DateTime.utc(2030, 1, 1, 11),
  status: BookingStatus.confirmed,
  canReview: false,
);

class _Harness {
  _Harness(this.repo) {
    container = ProviderContainer(
      overrides: <Object>[
        clientBlockRepositoryProvider.overrideWithValue(repo),
        bookedDaysProvider.overrideWith((ref) async {
          bookedDaysBuilds++;
          return <DateTime>{};
        }),
        bookingDetailProvider('b1').overrideWith((ref) async {
          detailBuilds['b1'] = (detailBuilds['b1'] ?? 0) + 1;
          return _booking('b1');
        }),
        bookingDetailProvider('b2').overrideWith((ref) async {
          detailBuilds['b2'] = (detailBuilds['b2'] ?? 0) + 1;
          return _booking('b2');
        }),
      ].cast(),
    );
    // Keep the watched providers alive so an invalidate is observable as a
    // rebuild.
    container.listen(bookingDetailProvider('b1'), (_, _) {});
    container.listen(bookingDetailProvider('b2'), (_, _) {});
    container.listen(blockedClientsProvider, (_, _) {});
    // The master's rail dots — a calendar view the bulk-cancel fan-out drops.
    container.listen(bookedDaysProvider, (_, _) {});
  }

  int bookedDaysBuilds = 0;

  final ClientBlockRepository repo;
  late final ProviderContainer container;
  final Map<String, int> detailBuilds = <String, int>{};

  ClientBlockController get notifier =>
      container.read(clientBlockControllerProvider.notifier);

  Future<void> settle() async {
    await container.read(bookingDetailProvider('b1').future);
    await container.read(bookingDetailProvider('b2').future);
    await container.read(bookedDaysProvider.future);
    await container
        .read(blockedClientsProvider.future)
        .catchError((Object _) => const <ClientBlock>[]);
  }
}

void main() {
  group('block — cancelledBookings (phase 398)', () {
    test(
      'a new block carries the auto-cancelled count; a repeat carries 0',
      () async {
        final FakeClientBlockRepository repo = FakeClientBlockRepository()
          ..cancelOnNewBlock = 4;
        final _Harness h = _Harness(repo);
        addTearDown(h.container.dispose);
        await h.settle();

        final BlockWriteResult first = await h.notifier.block('b1');
        final BlockWriteResult repeat = await h.notifier.block('b1');

        expect((first as BlockWriteDone).cancelledBookings, 4);
        expect((repeat as BlockWriteDone).cancelledBookings, 0);
      },
    );

    test('count > 0 drops the provider-side calendar views; a repeat block '
        '(count 0) drops none', () async {
      final FakeClientBlockRepository repo = FakeClientBlockRepository()
        ..cancelOnNewBlock = 2;
      final _Harness h = _Harness(repo);
      addTearDown(h.container.dispose);
      await h.settle();
      expect(h.bookedDaysBuilds, 1);

      await h.notifier.block('b1');
      await h.settle();
      expect(h.bookedDaysBuilds, 2, reason: 'rail dots refetched once');

      await h.notifier.block('b1');
      await h.settle();
      expect(h.bookedDaysBuilds, 2, reason: 'repeat block adds no request');
    });

    test('a plain block (count 0) leaves the calendar views alone', () async {
      final _Harness h = _Harness(FakeClientBlockRepository());
      addTearDown(h.container.dispose);
      await h.settle();

      await h.notifier.block('b1');
      await h.settle();

      expect(h.bookedDaysBuilds, 1);
    });

    test('salonId reaches the salon-board half of the fan-out only when '
        'count > 0', () async {
      final _Harness cancelled = _Harness(
        FakeClientBlockRepository()..cancelOnNewBlock = 1,
      );
      addTearDown(cancelled.container.dispose);
      await cancelled.notifier.block('b1', salonId: 's1');
      // The board tab is not selected (shell default), so the board refresh
      // is deferred onto the gate rather than dropped.
      expect(
        cancelled.container.read(salonBoardRefreshGateProvider).takeStale('s1'),
        isTrue,
      );

      final _Harness none = _Harness(FakeClientBlockRepository());
      addTearDown(none.container.dispose);
      await none.notifier.block('b1', salonId: 's1');
      expect(
        none.container.read(salonBoardRefreshGateProvider).takeStale('s1'),
        isFalse,
      );
    });
  });

  group('block', () {
    test('stores the block, returns null and refreshes the booking detail '
        'and the block list only', () async {
      final FakeClientBlockRepository repo = FakeClientBlockRepository();
      final _Harness h = _Harness(repo);
      addTearDown(h.container.dispose);
      await h.settle();
      final int listCallsBefore = repo.calls.where((c) => c == 'list').length;

      final BlockWriteResult result = await h.notifier.block('b1');
      await h.settle();

      expect(result, isA<BlockWriteDone>());
      expect((result as BlockWriteDone).cancelledBookings, 0);
      expect(repo.stored, hasLength(1));
      expect(h.detailBuilds['b1'], 2, reason: 'b1 detail invalidated');
      expect(h.detailBuilds['b2'], 1, reason: 'other bookings untouched');
      expect(
        repo.calls.where((c) => c == 'list').length,
        listCallsBefore + 1,
        reason: 'block list refreshed',
      );
      expect(h.container.read(clientBlockControllerProvider), isFalse);
    });

    test('a repeat block is idempotent (one stored row)', () async {
      final FakeClientBlockRepository repo = FakeClientBlockRepository();
      final _Harness h = _Harness(repo);
      addTearDown(h.container.dispose);
      await h.notifier.block('b1');
      await h.notifier.block('b1');
      expect(repo.stored, hasLength(1));
    });

    test('a STAFF walk-in surfaces the 400 ValidationFailure and refreshes '
        'nothing', () async {
      final FakeClientBlockRepository repo = FakeClientBlockRepository(
        staffBookingIds: <String>{'b1'},
      );
      final _Harness h = _Harness(repo);
      addTearDown(h.container.dispose);
      await h.settle();

      final BlockWriteResult result = await h.notifier.block('b1');
      await h.settle();

      expect(_failureOf(result), isA<ValidationFailure>());
      expect(repo.stored, isEmpty);
      expect(h.detailBuilds['b1'], 1);
      expect(h.container.read(clientBlockControllerProvider), isFalse);
    });

    test('a non-Failure throw still lands as UnknownFailure', () async {
      final _Harness h = _Harness(_ThrowingRepository());
      addTearDown(h.container.dispose);
      expect(_failureOf(await h.notifier.block('b1')), isA<UnknownFailure>());
      expect(h.container.read(clientBlockControllerProvider), isFalse);
    });
  });

  group('unblock', () {
    test('sends ONE DELETE for the booking detail\'s clientBlockId (no POST) '
        'and refreshes detail + list', () async {
      final FakeClientBlockRepository repo = FakeClientBlockRepository();
      final _Harness h = _Harness(repo);
      addTearDown(h.container.dispose);
      await h.notifier.block('b1');
      await h.settle();
      final int buildsBefore = h.detailBuilds['b1'] ?? 0;
      repo.calls.clear();

      final BlockWriteResult result = await h.notifier.unblock(
        bookingId: 'b1',
        blockId: 'block-1',
      );
      await h.settle();

      expect(result, isA<BlockWriteDone>());
      expect(repo.stored, isEmpty);
      expect(repo.calls.where((String c) => c.startsWith('unblock:')), <String>[
        'unblock:block-1',
      ]);
      expect(repo.calls.where((String c) => c.startsWith('block:')), isEmpty);
      expect(h.detailBuilds['b1'], buildsBefore + 1);
      expect(h.detailBuilds['b2'], 1);
    });

    test('a failing DELETE returns the failure and keeps the block', () async {
      final FakeClientBlockRepository repo = FakeClientBlockRepository();
      await repo.block('b1');
      final _Harness h = _Harness(_FailOnUnblock(repo));
      addTearDown(h.container.dispose);

      expect(
        _failureOf(
          await h.notifier.unblock(bookingId: 'b1', blockId: 'block-1'),
        ),
        isA<NetworkFailure>(),
      );
      expect(repo.stored, hasLength(1));
    });
  });

  group('in-flight guard (security MEDIUM)', () {
    test('a second call while the first is in flight returns '
        'BlockWriteInProgress — not success — and sends nothing', () async {
      final _GatedRepository repo = _GatedRepository();
      final _Harness h = _Harness(repo);
      addTearDown(h.container.dispose);
      await h.settle();

      final Future<BlockWriteResult> first = h.notifier.block('b1');
      expect(h.container.read(clientBlockControllerProvider), isTrue);

      final BlockWriteResult second = await h.notifier.block('b2');
      expect(second, isA<BlockWriteInProgress>());
      expect(second, isNot(isA<BlockWriteDone>()));
      final BlockWriteResult third = await h.notifier.unblockById('x');
      expect(third, isA<BlockWriteInProgress>());
      expect(repo.calls, <String>[
        'block:b1',
      ], reason: 'only the first call ran');

      repo.gate.complete();
      expect(await first, isA<BlockWriteDone>());
      expect(h.container.read(clientBlockControllerProvider), isFalse);
    });
  });

  group('app-wide repository', () {
    test('is the HTTP implementation over the generated client', () {
      final ProviderContainer container = ProviderContainer(
        overrides: <Object>[dioProvider.overrideWithValue(Dio())].cast(),
      );
      addTearDown(container.dispose);
      expect(
        container.read(clientBlockRepositoryProvider),
        isA<HttpClientBlockRepository>(),
      );
    });
  });

  group('unblockById (phase 426 list)', () {
    test('DELETEs the block id only (no POST), refreshes the list and the '
        'booking details', () async {
      final FakeClientBlockRepository repo = FakeClientBlockRepository(
        seeded: <ClientBlock>[
          ClientBlock(
            id: 'blk-9',
            kind: ClientBlockKind.guest,
            displayName: 'Ірина С.',
            maskedPhone: '+380 •• ••• 12 34',
            createdAt: DateTime.utc(2026, 10, 3),
          ),
        ],
      );
      final _Harness h = _Harness(repo);
      addTearDown(h.container.dispose);
      await h.settle();
      repo.calls.clear();
      final Map<String, int> before = Map<String, int>.of(h.detailBuilds);

      expect(await h.notifier.unblockById('blk-9'), isA<BlockWriteDone>());
      await h.settle();

      expect(repo.calls.first, 'unblock:blk-9');
      expect(repo.calls.where((String c) => c.startsWith('block:')), isEmpty);
      expect(repo.calls, contains('list'));
      expect(await h.container.read(blockedClientsProvider.future), isEmpty);
      expect(h.detailBuilds['b1'], (before['b1'] ?? 0) + 1);
      expect(h.detailBuilds['b2'], (before['b2'] ?? 0) + 1);
    });

    test('a failure is returned typed and nothing is refreshed', () async {
      final FakeClientBlockRepository repo = FakeClientBlockRepository();
      final _Harness h = _Harness(repo);
      addTearDown(h.container.dispose);
      await h.settle();
      repo
        ..calls.clear()
        ..nextFailure = const NetworkFailure();

      expect(
        _failureOf(await h.notifier.unblockById('blk-9')),
        isA<NetworkFailure>(),
      );
      expect(repo.calls, <String>['unblock:blk-9']);
      expect(h.container.read(clientBlockControllerProvider), isFalse);
    });
  });
}

final class _ThrowingRepository implements ClientBlockRepository {
  @override
  Future<ClientBlock> block(String bookingId) => throw StateError('boom');
  @override
  Future<void> unblock(String blockId) => throw StateError('boom');
  @override
  Future<List<ClientBlock>> list() async => const <ClientBlock>[];
}

final class _FailOnUnblock implements ClientBlockRepository {
  _FailOnUnblock(this._inner);
  final FakeClientBlockRepository _inner;
  @override
  Future<ClientBlock> block(String bookingId) => _inner.block(bookingId);
  @override
  Future<void> unblock(String blockId) async => throw const NetworkFailure();
  @override
  Future<List<ClientBlock>> list() => _inner.list();
}

Failure? _failureOf(BlockWriteResult result) => switch (result) {
  BlockWriteFailed(:final Failure failure) => failure,
  BlockWriteDone() || BlockWriteInProgress() => null,
};

/// [block] parks on [gate] so a test can call again while it is in flight.
final class _GatedRepository implements ClientBlockRepository {
  final Completer<void> gate = Completer<void>();
  final List<String> calls = <String>[];

  @override
  Future<ClientBlock> block(String bookingId) async {
    calls.add('block:$bookingId');
    await gate.future;
    return ClientBlock(
      id: 'blk-1',
      kind: ClientBlockKind.client,
      displayName: 'Клієнт',
      createdAt: DateTime.utc(2026, 10, 28),
    );
  }

  @override
  Future<void> unblock(String blockId) async => calls.add('unblock:$blockId');

  @override
  Future<List<ClientBlock>> list() async => const <ClientBlock>[];
}
