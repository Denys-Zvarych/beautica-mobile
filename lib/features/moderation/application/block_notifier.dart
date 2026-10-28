// Phase 425 — block / unblock a client from a booking (backend 397).
//
// Returns a [BlockWriteResult]: [BlockWriteDone] on success, [BlockWriteFailed]
// with the typed [Failure] for the caller's snack, or [BlockWriteInProgress]
// when another write is already in flight (the call did NOTHING — the caller
// shows nothing; security MEDIUM: an ignored call must never read as a
// success). On success it refreshes ONLY the
// booking's detail (its `clientBlocked` flag drives «Заблокувати» /
// «Розблокувати») and the block list (D6). Discovery, search and favourites
// are deliberately untouched: a block never hides a provider.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/moderation/application/blocked_list_notifier.dart';
import 'package:beautica_mobile/features/moderation/data/block_repository.dart';

part 'block_notifier.g.dart';

/// Outcome of one block / unblock call.
sealed class BlockWriteResult {
  const BlockWriteResult();
}

/// The write reached the server and succeeded.
final class BlockWriteDone extends BlockWriteResult {
  const BlockWriteDone();
}

/// The write failed with [failure].
final class BlockWriteFailed extends BlockWriteResult {
  const BlockWriteFailed(this.failure);

  final Failure failure;
}

/// Another write was already in flight, so this call sent nothing and changed
/// nothing. Never a success: the caller shows no snack at all.
final class BlockWriteInProgress extends BlockWriteResult {
  const BlockWriteInProgress();
}

/// Drives block / unblock. State = a write is in flight (double-tap guard).
@Riverpod(keepAlive: true)
class ClientBlockController extends _$ClientBlockController {
  @override
  bool build() => false;

  /// Blocks the client of [bookingId] (`POST /blocks`).
  Future<BlockWriteResult> block(String bookingId) =>
      _run(bookingId, (repo) async {
        await repo.block(bookingId);
      });

  /// Unblocks the client of [bookingId] with ONE `DELETE /blocks/{blockId}` —
  /// [blockId] is the booking detail's `clientBlockId`. Refreshes that
  /// booking's detail and the block list.
  Future<BlockWriteResult> unblock({
    required String bookingId,
    required String blockId,
  }) => _run(bookingId, (repo) => repo.unblock(blockId));

  /// Phase 426 — unblocks [blockId] straight from the «Заблоковані клієнти»
  /// list, which already holds the block id (`DELETE /blocks/{blockId}`).
  /// Refreshes the list and every open booking detail (their
  /// `clientBlocked` flag may have been this block).
  Future<BlockWriteResult> unblockById(String blockId) =>
      _run(null, (repo) => repo.unblock(blockId));

  Future<BlockWriteResult> _run(
    String? bookingId,
    Future<void> Function(ClientBlockRepository repo) write,
  ) async {
    if (state) return const BlockWriteInProgress();
    state = true;
    try {
      await write(ref.read(clientBlockRepositoryProvider));
    } on Failure catch (e) {
      state = false;
      return BlockWriteFailed(e);
    } catch (e) {
      state = false;
      return BlockWriteFailed(UnknownFailure(cause: e));
    }
    state = false;
    // cycle-safe: bookingDetailProvider and blockedClientsProvider never
    // watch clientBlockControllerProvider (no back-edge, no cycle).
    if (bookingId != null) {
      // cycle-safe: bookingDetailProvider never watches this controller.
      ref.invalidate(bookingDetailProvider(bookingId));
    } else {
      // cycle-safe: same reasoning as above, for the whole (autoDispose)
      // family — the list knows no booking id.
      ref.invalidate(bookingDetailProvider);
    }
    // cycle-safe: see above — blockedClientsProvider watches only the
    // repository.
    ref.invalidate(blockedClientsProvider);
    return const BlockWriteDone();
  }
}
