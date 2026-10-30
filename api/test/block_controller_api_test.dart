import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for BlockControllerApi
void main() {
  final instance = BeauticaApi().getBlockControllerApi();

  group(BlockControllerApi, () {
    // Block the client of a booking
    //
    // Blocks the client of a booking in the caller's scope: an independent master blocks for themselves, a salon owner/admin for the whole salon. A registered client is blocked by account only, a link guest by the phone verified at booking time; the two are never linked. Silent (the client is not notified) and idempotent: an existing block of the same client in the same scope returns 200. Shares a per-user budget with DELETE (429 with Retry-After).
    //
    //Future<ApiResponseBlockResponse> block(CreateBlockRequest createBlockRequest) async
    test('test block', () async {
      // TODO
    });

    // List blocked clients
    //
    // The caller's blocks, newest first (salon owner/admin: the salon's). At most 500 rows.
    //
    //Future<ApiResponseListBlockResponse> list() async
    test('test list', () async {
      // TODO
    });

    // Unblock a client
    //
    // Idempotent: 204 also when the block does not exist or is outside the caller's scope. Shares the per-user budget with POST (429 with Retry-After).
    //
    //Future unblock(String blockId) async
    test('test unblock', () async {
      // TODO
    });
  });
}
