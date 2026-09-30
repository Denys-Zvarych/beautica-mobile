import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for NotificationsApi
void main() {
  final instance = BeauticaApi().getNotificationsApi();

  group(NotificationsApi, () {
    // The recipient's own notification feed, newest first
    //
    //Future<PageResponseNotificationResponse> listFeed({ int page, int size }) async
    test('test listFeed', () async {
      // TODO
    });

    // Marks every still-unread item created at or before the given cutoff (default: now) read
    //
    //Future<ApiResponseMarkAllReadResponse> markAllRead({ MarkAllReadRequest markAllReadRequest }) async
    test('test markAllRead', () async {
      // TODO
    });

    // Marks one item read — idempotent; 404 for a missing or foreign id (never 403)
    //
    //Future markRead(String id) async
    test('test markRead', () async {
      // TODO
    });

    // The bell red-dot count, capped at 99
    //
    //Future<ApiResponseUnreadCountResponse> unreadCount() async
    test('test unreadCount', () async {
      // TODO
    });
  });
}
