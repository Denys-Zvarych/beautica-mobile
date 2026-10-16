// NotificationPermission notifier — refresh() dedup, late-read ordering,
// unchanged-value write skip, and the keep-alive last-reading cache.

import 'dart:async';

import 'package:beautica_mobile/core/push/notification_permission_provider.dart';
import 'package:beautica_mobile/features/settings/presentation/notification_permission_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _S = NotificationPermissionStatus;

/// Each read returns a fresh pending completer the test resolves by hand.
class _Reads {
  final List<Completer<_S>> pending = <Completer<_S>>[];

  Future<_S> read() {
    final Completer<_S> c = Completer<_S>();
    pending.add(c);
    return c.future;
  }
}

ProviderContainer _container(_Reads reads) {
  final ProviderContainer c = ProviderContainer(
    overrides: [
      notificationPermissionReaderProvider.overrideWithValue(reads.read),
    ],
  );
  addTearDown(c.dispose);
  // Keep the auto-dispose notifier alive for the test.
  c.listen(notificationPermissionProvider, (_, _) {});
  return c;
}

void main() {
  test('concurrent refresh() calls share ONE platform read', () async {
    final _Reads reads = _Reads();
    final ProviderContainer c = _container(reads);
    reads.pending.single.complete(_S.denied);
    await c.read(notificationPermissionProvider.future);

    final NotificationPermission n = c.read(
      notificationPermissionProvider.notifier,
    );
    final Future<void> a = n.refresh();
    final Future<void> b = n.refresh();
    expect(reads.pending.length, 2, reason: 'build + ONE refresh read');

    reads.pending.last.complete(_S.granted);
    await Future.wait(<Future<void>>[a, b]);
    expect(c.read(notificationPermissionProvider).value, _S.granted);

    // A refresh after the in-flight one settled reads again.
    unawaited(n.refresh());
    expect(reads.pending.length, 3);
    reads.pending.last.complete(_S.granted);
  });

  test(
    'a refresh during the build read joins it (one platform read)',
    () async {
      final _Reads reads = _Reads();
      final ProviderContainer c = _container(reads);

      final Future<void> refresh = c
          .read(notificationPermissionProvider.notifier)
          .refresh();
      expect(
        reads.pending.length,
        1,
        reason: 'joined the in-flight build read',
      );

      reads.pending.single.complete(_S.granted);
      await refresh;
      expect(c.read(notificationPermissionProvider).value, _S.granted);
    },
  );

  test('a late refresh read cannot overwrite a newer build read', () async {
    final _Reads reads = _Reads();
    final ProviderContainer c = _container(reads);
    reads.pending.single.complete(_S.denied);
    await c.read(notificationPermissionProvider.future);

    // Refresh starts (read A) …
    final Future<void> refresh = c
        .read(notificationPermissionProvider.notifier)
        .refresh();
    final Completer<_S> late = reads.pending.last;
    // … then the provider rebuilds (read B) and B lands first.
    c.invalidate(notificationPermissionProvider);
    final Future<_S> rebuilt = c.read(notificationPermissionProvider.future);
    reads.pending.last.complete(_S.granted);
    expect(await rebuilt, _S.granted);

    late.complete(_S.denied); // the stale reading lands last
    await refresh;
    await Future<void>.delayed(Duration.zero);

    expect(c.read(notificationPermissionProvider).value, _S.granted);
    expect(c.read(lastNotificationPermissionProvider), _S.granted);
  });

  test('an unchanged reading writes no new state', () async {
    final _Reads reads = _Reads();
    final ProviderContainer c = _container(reads);
    reads.pending.single.complete(_S.denied);
    await c.read(notificationPermissionProvider.future);

    int writes = 0;
    c.listen(notificationPermissionProvider, (_, _) => writes++);
    final Future<void> r = c
        .read(notificationPermissionProvider.notifier)
        .refresh();
    reads.pending.last.complete(_S.denied);
    await r;

    expect(writes, 0);
  });

  test('every reading is remembered in the keep-alive cache', () async {
    final _Reads reads = _Reads();
    final ProviderContainer c = _container(reads);
    expect(c.read(lastNotificationPermissionProvider), isNull);

    reads.pending.single.complete(_S.notDetermined);
    await c.read(notificationPermissionProvider.future);
    expect(c.read(lastNotificationPermissionProvider), _S.notDetermined);
  });
}
