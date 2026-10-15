import 'package:flutter_test/flutter_test.dart';

/// Frame callbacks that every mounted `ProviderScope` parks on its own,
/// independent of any `Ticker`.
///
/// flutter_riverpod >=3.3 `ProviderScope.build` registers
/// `scheduleFrameCallback(scheduleNewFrame: false, ...)` on every build, so a
/// tree under ONE scope always reports one transient callback even when no
/// animation runs. `scheduleNewFrame: false` means it never requests a frame by
/// itself (so `pumpAndSettle` is unaffected) — but a raw
/// `transientCallbackCount` read is off by one. Pinned by
/// `ticker_frame_callbacks_test.dart`, which fails loudly if a Riverpod upgrade
/// changes this number.
const int kProviderScopeFrameCallbacks = 1;

/// Frame callbacks registered by running `Ticker`s under a single
/// `ProviderScope` (what `pumpApp` / `pumpRoutedApp` mount): the raw
/// `transientCallbackCount` minus [kProviderScopeFrameCallbacks].
int tickerFrameCallbacks(WidgetTester tester) =>
    tester.binding.transientCallbackCount - kProviderScopeFrameCallbacks;
