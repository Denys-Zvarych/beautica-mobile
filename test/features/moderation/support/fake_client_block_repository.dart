// In-memory [ClientBlockRepository] enforcing the backend 397 contract the
// block UI depends on:
//   • D5 — idempotent: blocking the same booking's client again returns the
//     SAME block (200), never a second row; unblocking a missing id is a
//     no-op (204).
//   • [staffBookingIds] → ValidationFailure (400, STAFF walk-in).
//   • [outOfScopeBookingIds] → NotFoundFailure (404).
// [nextFailure] forces the next call to throw (then clears).

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/moderation/data/block_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/client_block.dart';

final class FakeClientBlockRepository implements ClientBlockRepository {
  FakeClientBlockRepository({
    Set<String>? staffBookingIds,
    Set<String>? outOfScopeBookingIds,
    List<ClientBlock>? seeded,
  }) : staffBookingIds = staffBookingIds ?? <String>{},
       outOfScopeBookingIds = outOfScopeBookingIds ?? <String>{},
       _seeded = <ClientBlock>[...?seeded];

  final Set<String> staffBookingIds;
  final Set<String> outOfScopeBookingIds;

  /// Thrown (once) by the next call.
  Failure? nextFailure;

  /// Every call, in order: `block:<bookingId>`, `unblock:<blockId>`, `list`.
  final List<String> calls = <String>[];

  final Map<String, ClientBlock> _byBooking = <String, ClientBlock>{};

  /// Phase 426 — pre-existing blocks (no booking id), newest first; listed
  /// AFTER anything blocked during the test.
  final List<ClientBlock> _seeded;

  /// When set, [list] awaits it — lets a test hold the screen in loading.
  Future<void>? listGate;
  int _seq = 0;

  /// Blocks currently stored.
  List<ClientBlock> get stored => _byBooking.values.toList();

  void _maybeFail() {
    final Failure? f = nextFailure;
    if (f != null) {
      nextFailure = null;
      throw f;
    }
  }

  @override
  Future<ClientBlock> block(String bookingId) async {
    calls.add('block:$bookingId');
    _maybeFail();
    if (staffBookingIds.contains(bookingId)) {
      throw const ValidationFailure(fieldErrors: <String, String>{});
    }
    if (outOfScopeBookingIds.contains(bookingId)) {
      throw const NotFoundFailure();
    }
    return _byBooking.putIfAbsent(
      bookingId,
      () => ClientBlock(
        id: 'block-${++_seq}',
        kind: ClientBlockKind.client,
        displayName: 'Клієнт $bookingId',
        createdAt: DateTime.utc(2026, 10, 28, 12),
      ),
    );
  }

  @override
  Future<void> unblock(String blockId) async {
    calls.add('unblock:$blockId');
    _maybeFail();
    _byBooking.removeWhere((_, ClientBlock b) => b.id == blockId);
    _seeded.removeWhere((ClientBlock b) => b.id == blockId);
  }

  @override
  Future<List<ClientBlock>> list() async {
    calls.add('list');
    final Future<void>? gate = listGate;
    if (gate != null) await gate;
    _maybeFail();
    return <ClientBlock>[...stored.reversed, ..._seeded];
  }
}
