// Injectable wall-clock seam.
//
// Production code that needs the current instant must read [clockProvider]
// instead of calling [DateTime.now] directly, so widget/unit tests can pin
// "now" to a fixed value and stay deterministic under randomized ordering.
//
// The provider exposes a zero-argument `DateTime Function()` (a *getter* of the
// current instant) rather than a bare [DateTime], so each read returns a fresh
// value — a single provider read does not freeze time for the lifetime of the
// build. In production it resolves to [DateTime.now]; tests override it with a
// fixed closure:
//
//   ProviderScope(overrides: [
//     clockProvider.overrideWithValue(() => DateTime.utc(2026, 6, 14, 12)),
//   ]);
//
// ALWAYS pin the injected instant with `DateTime.utc(...)` — or, when the test
// needs a specific device zone, `tz.TZDateTime(tz.getLocation('Asia/Tokyo'), …)`.
// A bare local `DateTime(2026, 6, 14, 12)` resolves its underlying instant
// through the HOST PROCESS's own `TZ`, so what the test actually pins differs
// between the dev VM (Europe/Kyiv), CI (UTC) and any other machine. Because the
// dev VM's zone IS the market zone, such a fixture is indistinguishable from a
// correct one locally and silently stops discriminating. This has shipped three
// times (Phase 225 audit cycles 4 and 5; 2026-08-02).
// Enforced by scripts/forbid_host_local_instant_anchor.sh.
//
// Consumers call it like `ref.watch(clockProvider)()` (widgets) or
// `ref.read(clockProvider)()` (one-shot reads inside notifier actions).

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'clock_provider.g.dart';

/// Provides the application clock as a `DateTime Function()`.
///
/// Defaults to [DateTime.now]. Override in tests with a fixed closure to make
/// any code that reads "now" through this provider deterministic.
@Riverpod(keepAlive: true)
DateTime Function() clock(Ref ref) => DateTime.now;
