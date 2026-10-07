// Phase 361 — test double that pins the GLOBAL unread count to zero.
//
// Every header now mounts the live notification bell, which watches
// `hasUnreadNotificationsProvider` -> `unreadNotificationsProvider`. For an
// authenticated test session the REAL notifier starts a 60 s periodic poll
// timer, which a test that owns its `ProviderContainer` (disposed in
// `addTearDown`, i.e. AFTER the pending-timer invariant check) leaks.
//
// `pumpApp` / `pumpRoutedApp` (helpers/pump_app.dart) PREPEND
// [kNoUnreadOverride] by default, so a test that mounts a header through them
// needs nothing. A test can still pin a live/specific count: passing its own
// `unreadNotificationsProvider` override suppresses the default (see
// [withDefaultNoUnread]; a double override would trip Riverpod's assert).
// A test that builds its OWN `ProviderContainer` should use
// `makeTestContainer` (helpers/test_container.dart), which applies this
// default AND the zero `salonManagementProfileCacheWindowProvider` default
// (phase 384); a raw container must add [kNoUnreadOverride] itself.

import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';

class ZeroUnreadNotifications extends UnreadNotifications {
  @override
  FutureOr<int> build() => 0;
}

/// Pins `unreadNotificationsProvider` to a fixed 0 (no timer, no fetch).
final Object kNoUnreadOverride = unreadNotificationsProvider.overrideWith(
  ZeroUnreadNotifications.new,
);

/// Prepends [kNoUnreadOverride] to [overrides] UNLESS the caller already
/// overrides `unreadNotificationsProvider` (Riverpod asserts on a provider
/// overridden twice in one container). Used by `pumpApp` / `pumpRoutedApp`.
List<Object> withDefaultNoUnread(List<Object> overrides) {
  final bool callerOverrides = overrides.any(
    (Object o) => o is Override && o.origin == unreadNotificationsProvider,
  );
  return callerOverrides
      ? overrides
      : <Object>[kNoUnreadOverride, ...overrides];
}
