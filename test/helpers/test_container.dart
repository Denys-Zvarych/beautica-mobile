// Phase 361 — THE way a test builds its own `ProviderContainer`.
//
// Every header/shell now mounts the live notification bell, whose REAL notifier
// starts a 60 s poll timer for an authenticated session. A test that owns its
// container disposes it in `addTearDown` (AFTER flutter_test's pending-timer
// invariant), so an un-overridden bell leaks that timer. [makeTestContainer]
// bakes in the zero-unread default ([withDefaultNoUnread]) so no test has to
// remember the rule; a test that passes its OWN `unreadNotificationsProvider`
// override still wins (no double override).
//
// It also installs [beauticaProviderRetry] — the production retry predicate,
// the same default `pumpApp` / `pumpRoutedApp` use — and registers
// `container.dispose` via `addTearDown`, so the caller must NOT dispose again.
//
// Guarded by `scripts/forbid_raw_container_with_header.sh`: a raw
// `ProviderContainer(` in a test that imports a header/shell widget fails CI.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

import 'no_unread_notifications.dart';

/// [overrides] is `List<Object>` — the same shape `pumpApp` takes — so callers
/// can pass plain override lists without importing Riverpod's internal type.
///
/// [retry] mirrors `pumpApp`'s knob (default [beauticaProviderRetry]); pass
/// `(_, _) => null` to disable retry for a test asserting an exact call count.
ProviderContainer makeTestContainer({
  List<Object> overrides = const <Object>[],
  Duration? Function(int retryCount, Object error)? retry =
      beauticaProviderRetry,
}) {
  final ProviderContainer container = ProviderContainer(
    overrides: withDefaultNoUnread(overrides).cast<Override>(),
    retry: retry,
  );
  addTearDown(container.dispose);
  return container;
}
