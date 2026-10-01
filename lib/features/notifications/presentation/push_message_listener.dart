// Phase 068 — foreground FCM message handling (Android only).
//
// Locked rules:
//  * Foreground = SILENT refresh, no banner: the bell dot is the cue. Feed
//    alive (screen open) -> `NotificationsFeed.refreshFromPush()` (quiet head
//    merge; it already nudges the unread count); otherwise
//    `UnreadNotifications.refreshAfterPush()` and the feed provider is NOT
//    created.
//  * TRAILING DEBOUNCE ([kPushRefreshDebounce]) with a MAX WAIT
//    ([kPushRefreshMaxWait]): a burst of N pushes triggers ONE refresh, but a
//    sustained stream (each push < debounce after the last) cannot starve the
//    refresh past the max wait counted from the burst's FIRST push. Both timers
//    are cancelled on dispose / logout / user switch.
//  * Subscribes ONLY while [PushRegistration] is `registered` — that single
//    gate covers push-unavailable, signed-out, still-registering AND
//    permission-denied (a denied device must not process push payloads).
//  * Background / killed: Android renders the `notification` part itself; no
//    Dart handler (no `onBackgroundMessage`). Resume refresh is the unread
//    notifier's own.
//  * The payload is parsed defensively (`pushTapFromData`); a malformed one is
//    ignored. Nothing from the payload is logged.
//  * The subscription is cancelled on logout / user switch / dispose.

import 'dart:async';
import 'dart:developer';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/push/firebase_messaging_provider.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../data/notification_mapper.dart';
import '../domain/push_registration_state.dart';
import 'notifications_feed_notifier.dart';
import 'push_registration_notifier.dart';
import 'unread_notifications_notifier.dart';

part 'push_message_listener.g.dart';

/// Quiet period after the LAST push before the single refresh fires.
const Duration kPushRefreshDebounce = Duration(milliseconds: 1500);

/// Longest a burst may defer its refresh, counted from the burst's first push.
const Duration kPushRefreshMaxWait = Duration(seconds: 5);

@Riverpod(keepAlive: true)
void pushMessageListener(Ref ref) {
  final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
  final bool registered = ref.watch(
    pushRegistrationProvider.select(
      (PushRegistrationState s) => s is PushRegistered,
    ),
  );
  if (userId == null || !registered) return;

  Timer? debounce;
  Timer? maxWait;
  void flush() {
    debounce?.cancel();
    maxWait?.cancel();
    debounce = null;
    maxWait = null;
    _flush(ref);
  }

  final StreamSubscription<RemoteMessage> sub = ref
      .read(firebaseForegroundMessagesProvider)()
      .listen((RemoteMessage m) {
        if (!ref.mounted) return;
        try {
          if (NotificationMapper.pushTapFromData(m.data) == null) return;
          debounce?.cancel();
          debounce = Timer(kPushRefreshDebounce, flush);
          // First push of a burst starts the max-wait clock; later ones don't.
          maxWait ??= Timer(kPushRefreshMaxWait, flush);
        } on Object catch (e) {
          _logFailure(e);
        }
      }, onError: (Object e) => _logFailure(e));
  ref.onDispose(() {
    debounce?.cancel();
    maxWait?.cancel();
    unawaited(sub.cancel());
  });
}

void _flush(Ref ref) {
  if (!ref.mounted) return;
  try {
    final Future<void> refresh = ref.exists(notificationsFeedProvider)
        ? ref.read(notificationsFeedProvider.notifier).refreshFromPush()
        : ref.read(unreadNotificationsProvider.notifier).refreshAfterPush();
    unawaited(refresh.catchError(_logFailure));
  } on Object catch (e) {
    _logFailure(e);
  }
}

// Type only — never the payload.
void _logFailure(Object e) => log(
  'push message handling failed: ${e.runtimeType}',
  name: 'feature.notifications.push',
  level: 900,
);
