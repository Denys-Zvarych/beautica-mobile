// Pins `AppHarness.boot` to the PRODUCTION retry predicate.
//
// WHY THIS FILE EXISTS
// --------------------
// `main.dart` installs `beauticaProviderRetry` on the root `ProviderScope`, so
// the shipped app stops on the first deterministic `Failure` and renders its
// error branch. `AppHarness.boot` used to build its scope with `retry: null`,
// which falls through to `ProviderContainer.defaultRetry` — Riverpod's blanket
// 10-attempt / ~38 s backoff that retries EVERY `Failure` (a `Failure` is
// neither an `Error` nor a `ProviderException`, the only two shapes that
// default refuses).
//
// `test/helpers/pump_app_retry_policy_test.dart` ratchets the same default for
// the WIDGET harness and explains the failure class in full. This file is the
// missing half: `AppHarness.boot` is the boot path for the ENTIRE E2E tier, and
// reverting its default to `null` restores blanket retry across every flow
// while leaving all of them green. The E2E tier is the last place that skew
// should exist — its whole claim is "this is the real app".
//
// WHAT IS ASSERTED
// ----------------
// The DEFAULT: `AppHarness.boot` is called with NO `retry:` argument, exactly
// how all of its call sites invoke it. Passing one here would make this file
// assert nothing.
//
// The probe is a locally-declared provider read through the harness's own
// container, not a screen. The container-level retry policy governs every
// provider in the scope, so the probe measures the boot policy directly instead
// of through whichever screen happens to be reachable — and it stays valid when
// the app's routes change.
//
// FALSIFIABILITY
// --------------
// Change `retry` in `integration_test/support/app_harness.dart` back to
// `Duration? Function(int, Object)? retry` with no default (`= null`) and the
// `isLoading` assertion below fails: Riverpod parks the element in a loading
// state between backoff attempts instead of surfacing `AsyncError` at once.
// Verified by mutation, not by inspection.
//
// This runs headless — `flutter test integration_test/harness_retry_policy_flow_test.dart
// -d flutter-tester` needs no emulator, because nothing here is native.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/e2e_boot_policy.dart';

/// Counts how many times the failing provider actually built, so "no retry was
/// scheduled" is asserted directly rather than inferred.
int _builds = 0;

final _failingProvider = FutureProvider<int>((ref) async {
  _builds++;
  // Deterministic by construction: a 404 cannot become a 200 on attempt 2.
  throw const NotFoundFailure();
});

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installOverflowGuard();
    _builds = 0;
  });
  tearDown(AppHarness.tearDownHarness);

  testWidgets('AppHarness.boot defaults to the production retry predicate — a '
      'deterministic Failure surfaces AsyncError on the FIRST attempt, not '
      'after a hidden ~38 s backoff', (WidgetTester tester) async {
    final FakeBackend fb = FakeBackend();

    // NOTE: deliberately no `retry:` argument — the default is what is under
    // test, and it is how every real call site invokes this.
    await AppHarness.boot(tester, fb);

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(E2eHarnessApp)),
    );

    final ProviderSubscription<AsyncValue<int>> sub = container.listen(
      _failingProvider,
      (_, _) {},
    );
    addTearDown(sub.close);

    // Let the rejected future propagate. One frame is enough when nothing is
    // being retried; a scheduled retry would still be pending here, which is
    // precisely the difference being measured.
    await tester.pump();

    final AsyncValue<int> state = container.read(_failingProvider);

    expect(
      state.isLoading,
      isFalse,
      reason:
          'AppHarness.boot must install beauticaProviderRetry by default. A '
          'still-loading element means the harness fell back to '
          'ProviderContainer.defaultRetry and the WHOLE E2E tier is '
          'validating a blanket-retry policy production removed — every flow '
          'stays green while the skew hides real error surfaces.',
    );
    expect(
      state.hasError,
      isTrue,
      reason: 'the deterministic NotFoundFailure must be surfaced, not hidden',
    );
    expect(
      state.error,
      isA<NotFoundFailure>(),
      reason: 'the original failure must reach the listener unchanged',
    );
    expect(
      _builds,
      1,
      reason: 'no retry attempt may have been scheduled for a 404',
    );
  });
}
