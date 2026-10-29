// Phase 425 — block / unblock a client from a booking (backend 397).
//
// Returns a [BlockWriteResult]: [BlockWriteDone] on success, [BlockWriteFailed]
// with the typed [Failure] for the caller's snack, or [BlockWriteInProgress]
// when another write is already in flight (the call did NOTHING — the caller
// shows nothing; security MEDIUM: an ignored call must never read as a
// success). On success it refreshes the booking's detail (its `clientBlocked`
// flag drives «Заблокувати» / «Розблокувати») and the block list (D6). When a
// NEW block auto-cancelled future visits (phase 398, `cancelledBookings > 0`)
// it also drops the provider-side calendar / salon board / archive through
// `invalidateBookingViewsAfterBulkCancel`; a repeat block (count 0) adds no
// request. Discovery, search and favourites are deliberately untouched: a
// block never hides a provider.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/booking/application/booking_calendar_invalidation.dart';
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
  const BlockWriteDone({this.cancelledBookings = 0});

  /// Phase 398 — future visits a NEW block auto-cancelled (backend
  /// `BlockResponse.cancelledBookings`). Always 0 for an unblock or a repeat
  /// block.
  final int cancelledBookings;
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
  /// [BlockWriteDone.cancelledBookings] carries how many future visits the
  /// block auto-cancelled (phase 398). [salonId] is the salon board this
  /// detail was opened from (`null` on every non-salon mount) — forwarded to
  /// the calendar fan-out so the board's list and rail dots drop too.
  Future<BlockWriteResult> block(String bookingId, {String? salonId}) => _run(
    bookingId,
    (repo) async => (await repo.block(bookingId)).cancelledBookings,
    salonId: salonId,
  );

  /// Unblocks the client of [bookingId] with ONE `DELETE /blocks/{blockId}` —
  /// [blockId] is the booking detail's `clientBlockId`. Refreshes that
  /// booking's detail and the block list.
  Future<BlockWriteResult> unblock({
    required String bookingId,
    required String blockId,
  }) => _run(bookingId, (repo) async {
    await repo.unblock(blockId);
    return 0;
  });

  /// Phase 426 — unblocks [blockId] straight from the «Заблоковані клієнти»
  /// list, which already holds the block id (`DELETE /blocks/{blockId}`).
  /// Refreshes the list and every open booking detail (their
  /// `clientBlocked` flag may have been this block).
  Future<BlockWriteResult> unblockById(String blockId) =>
      _run(null, (repo) async {
        await repo.unblock(blockId);
        return 0;
      });

  Future<BlockWriteResult> _run(
    String? bookingId,
    Future<int> Function(ClientBlockRepository repo) write, {
    String? salonId,
  }) async {
    if (state) return const BlockWriteInProgress();
    state = true;
    final int cancelledBookings;
    try {
      cancelledBookings = await write(ref.read(clientBlockRepositoryProvider));
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
    if (cancelledBookings > 0) {
      // Phase 398 — the server cancelled this client's other future visits;
      // only their count comes back, so drop every live provider-side booking
      // view (the shared fan-out the walk-in create already uses). Gated so a
      // repeat block (count 0) costs nothing. cycle-safe: none of those
      // providers watches this controller.
      invalidateBookingViewsAfterBulkCancel(ref, salonId: salonId);
    }
    return BlockWriteDone(cancelledBookings: cancelledBookings);
  }
}
