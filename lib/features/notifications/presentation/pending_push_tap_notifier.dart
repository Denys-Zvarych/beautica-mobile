// Phase 069 — the pending push TAP (Android only).
//
// Holds at most ONE [PushTap], filled by:
//  * `FirebaseMessaging.onMessageOpenedApp` — a tap while the app is in the
//    background;
//  * `getInitialMessage()` — the tap that LAUNCHED the app from terminated,
//    read exactly ONCE per process (a re-attach never re-reads it, so a tap can
//    never be replayed).
//
// The dispatcher (`push_tap_dispatcher.dart`) takes it once the session is
// resolved and the router is past splash / auth screens.
//
// Rules:
//  * A tap is dropped, never replayed, when the session is (or becomes)
//    ANONYMOUS, and when the signed-in user CHANGES: logout unregisters the
//    token, so such a tap is stale or belongs to another account.
//  * While the session is still resolving (cold start), the tap is HELD.
//  * Subscribes only while not anonymous; cancelled on anonymous / dispose.
//  * Nothing from the payload is logged. Permission state is irrelevant (a
//    visible notification implies it).
//  * Listens to auth; nothing here is read FROM `AuthNotifier` (067 trap).

import 'dart:async';
import 'dart:developer';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/push/firebase_messaging_provider.dart';
import '../../../core/push/push_available_provider.dart';
import '../../auth/domain/auth_session.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../data/notification_mapper.dart';
import '../domain/push_tap.dart';

part 'pending_push_tap_notifier.g.dart';

/// `(resolved, userId)`: `resolved == false` while the session is still being
/// restored (cold start); `userId == null` with `resolved == true` = anonymous.
typedef PushAuthPhase = (bool resolved, String? userId);

/// Value-comparable, so a silent token refresh does not renotify.
PushAuthPhase pushAuthPhaseOf(AsyncValue<AuthSession> s) {
  final String? id = authUserIdOrNull(s);
  final bool resolved = id != null || !s.isLoading;
  return (resolved, id);
}

@Riverpod(keepAlive: true)
class PendingPushTap extends _$PendingPushTap {
  StreamSubscription<RemoteMessage>? _sub;
  int _generation = 0;
  bool _attaching = false;
  bool _initialRead = false;
  PushAuthPhase _phase = (false, null);

  @override
  PushTap? build() {
    ref.onDispose(_detach);
    _phase = pushAuthPhaseOf(ref.read(authProvider));
    // Audit M1 (spec D6): a cold start that is already signed out forfeits the
    // launch tap for this process — a later sign-in must not inherit it.
    if (_anonymous) _initialRead = true;
    ref.listen<PushAuthPhase>(authProvider.select(pushAuthPhaseOf), (
      PushAuthPhase? prev,
      PushAuthPhase next,
    ) {
      _phase = next;
      if (_anonymous) {
        _initialRead =
            true; // audit M1: a pre-login launch tap is never replayed
        _detach();
        state = null;
        return;
      }
      final String? prevId = prev?.$2;
      if (prevId != null && next.$2 != null && prevId != next.$2) {
        state = null;
      }
      _attachIfNeeded();
    });
    _attachIfNeeded();
    return null;
  }

  /// Returns the pending tap and clears it (the dispatcher's single consume).
  PushTap? take() {
    final PushTap? tap = state;
    if (tap != null) state = null;
    return tap;
  }

  bool get _anonymous => _phase.$1 && _phase.$2 == null;

  void _attachIfNeeded() {
    if (_anonymous || _sub != null || _attaching) return;
    unawaited(_attach());
  }

  Future<void> _attach() async {
    _attaching = true;
    final int gen = ++_generation;
    try {
      final bool available = await ref.read(pushAvailableProvider.future);
      if (!available || !ref.mounted || gen != _generation) return;
      _sub = ref
          .read(firebaseOpenedAppMessagesProvider)()
          .listen(_onMessage, onError: (Object e) => _logFailure(e));
      if (_initialRead) return;
      _initialRead = true;
      final RemoteMessage? initial = await ref
          .read(firebaseMessagingProvider)
          .getInitialMessage();
      if (initial != null && ref.mounted && gen == _generation) {
        _onMessage(initial);
      }
    } on Object catch (e) {
      _logFailure(e);
    } finally {
      _attaching = false;
      // Auth flipped (anonymous -> user) while this attach was awaiting.
      if (ref.mounted && gen != _generation) _attachIfNeeded();
    }
  }

  void _onMessage(RemoteMessage m) {
    if (!ref.mounted || _anonymous) return;
    try {
      final PushTap? tap = NotificationMapper.pushTapFromData(m.data);
      if (tap != null) state = tap;
    } on Object catch (e) {
      _logFailure(e);
    }
  }

  void _detach() {
    _generation++;
    final StreamSubscription<RemoteMessage>? sub = _sub;
    _sub = null;
    if (sub != null) unawaited(sub.cancel());
  }
}

// Type only — never the payload.
void _logFailure(Object e) => log(
  'push tap handling failed: ${e.runtimeType}',
  name: 'feature.notifications.push',
  level: 900,
);
