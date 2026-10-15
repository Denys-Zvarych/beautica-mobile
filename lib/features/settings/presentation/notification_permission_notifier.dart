import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/push/notification_permission_provider.dart';

part 'notification_permission_notifier.g.dart';

/// The «Акаунт» → «Сповіщення» switch's source of truth: the OS permission,
/// read when the screen mounts (auto-dispose, so every visit re-reads) and on
/// [refresh] (app resumed, e.g. back from Android settings).
///
/// Every resolved reading is also remembered in
/// [lastNotificationPermissionProvider] so a revisit can show it at once.
@riverpod
class NotificationPermission extends _$NotificationPermission {
  /// Sequence of the last read STARTED (build or refresh).
  int _started = 0;

  /// Sequence of the read whose value is currently in [state].
  int _applied = 0;

  /// The one refresh in flight; concurrent [refresh] calls share it.
  Future<void>? _refreshing;

  /// The [build] read in flight; a [refresh] meanwhile joins it.
  Future<NotificationPermissionStatus>? _building;

  @override
  Future<NotificationPermissionStatus> build() async {
    final reader = ref.watch(notificationPermissionReaderProvider);
    final int seq = ++_started;
    final Future<NotificationPermissionStatus> pending = reader();
    _building = pending;
    final NotificationPermissionStatus read;
    try {
      read = await pending;
    } finally {
      if (identical(_building, pending)) _building = null;
    }
    // A refresh started after this read already wrote a NEWER value — the
    // late first read must not overwrite it.
    final NotificationPermissionStatus? newer = _applied > seq
        ? state.value
        : null;
    if (newer != null) return newer;
    _applied = seq;
    _remember(read);
    return read;
  }

  /// Re-reads the permission. Keeps the current value on screen meanwhile (no
  /// loading flash); concurrent calls share one platform read — including the
  /// [build] read still in flight, which then applies the value itself; an
  /// unchanged value writes nothing.
  Future<void> refresh() {
    final Future<NotificationPermissionStatus>? building = _building;
    if (building != null) return building.then((_) {});
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh() async {
    final int seq = ++_started;
    final NotificationPermissionStatus next = await ref.read(
      notificationPermissionReaderProvider,
    )();
    if (!ref.mounted || seq < _applied) return;
    _applied = seq;
    _remember(next);
    if (state.value == next) return;
    state = AsyncData<NotificationPermissionStatus>(next);
  }

  void _remember(NotificationPermissionStatus status) {
    if (!ref.mounted) return;
    ref.read(lastNotificationPermissionProvider.notifier).remember(status);
  }
}

/// The last permission reading seen this session (keep-alive). Lets the
/// «Сповіщення» switch show the last known state on a revisit instead of
/// flashing OFF while the fresh read runs. `null` until the first read.
@Riverpod(keepAlive: true)
class LastNotificationPermission extends _$LastNotificationPermission {
  @override
  NotificationPermissionStatus? build() => null;

  void remember(NotificationPermissionStatus status) => state = status;
}
