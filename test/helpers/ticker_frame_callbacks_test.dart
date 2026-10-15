// Pins [kProviderScopeFrameCallbacks]: the ticker-count assertions in the
// jank / off-screen-shimmer tests subtract it, so a Riverpod upgrade that
// changes how many frame callbacks a ProviderScope parks must fail HERE, by
// name, rather than shift those assertions silently.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ticker_frame_callbacks.dart';

void main() {
  testWidgets('a ticker-free tree under ONE ProviderScope parks exactly '
      'kProviderScopeFrameCallbacks frame callbacks', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SizedBox()));
    await tester.pump();
    await tester.pump();

    expect(tester.binding.transientCallbackCount, kProviderScopeFrameCallbacks);
    expect(tickerFrameCallbacks(tester), 0);
    // The parked callback must never REQUEST a frame on its own, or every
    // pumpAndSettle under a ProviderScope would hang.
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('without a ProviderScope there is nothing to subtract', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(tester.binding.transientCallbackCount, 0);
  });
}
