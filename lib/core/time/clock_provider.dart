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
//     clockProvider.overrideWithValue(() => DateTime(2026, 6, 14, 12)),
//   ]);
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
