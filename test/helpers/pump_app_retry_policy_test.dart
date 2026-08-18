// Pins the shared widget harness to the PRODUCTION retry predicate.
//
// WHY THIS FILE EXISTS
// --------------------
// `main.dart` installs `beauticaProviderRetry` on the root `ProviderScope`, so
// the shipped app stops on the first deterministic `Failure` and renders its
// error branch. `test/helpers/pump_app.dart` used to build its own
// `ProviderScope` with `retry: null`, which falls through to
// `ProviderContainer.defaultRetry` — Riverpod's blanket 10-attempt / ~38 s
// backoff that retries EVERY `Failure` (a `Failure` is neither an `Error` nor a
// `ProviderException`, the only two shapes that default refuses).
//
// So ~2 800 widget tests were exercising precisely the policy production had
// removed. Nothing was red; that is the danger. A deterministic error that a
// real user meets as an error screen was quietly retried away in test, and the
// divergence is invisible in any individual test's output — it only shows up as
// a bug report from the field.
//
// The predicate itself is covered in `test/core/errors/failure_retry_policy_test.dart`
// (including a bare-container negative control proving it is load-bearing).
// What THAT file cannot catch is the harness silently drifting back to the
// default, because a wrong default still leaves every test green. This file is
// that ratchet: it asserts the DEFAULT — no `retry:` argument passed, exactly
// how all ~116 `pumpApp` call sites invoke it.
//
// Falsifiability: change either default in `pump_app.dart` back to `null` and
// both tests below fail — the probe stays on its `loading` branch (Riverpod is
// mid-backoff) instead of reaching `error`.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'pump_app.dart';

/// Counts how many times the failing provider actually built, so "no retry was
/// scheduled" is asserted directly rather than inferred from the rendered text.
int _builds = 0;

final _failingProvider = FutureProvider<int>((ref) async {
  _builds++;
  // Deterministic by construction: a 404 cannot become a 200 on attempt 2.
  throw const NotFoundFailure();
});

/// Renders which `AsyncValue` branch the element is sitting in.
class _Probe extends ConsumerWidget {
  const _Probe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: ref
          .watch(_failingProvider)
          .when(
            data: (int v) => Text('data:$v'),
            loading: () => const Text('loading'),
            error: (Object e, _) => const Text('error'),
          ),
    );
  }
}

void main() {
  setUp(() => _builds = 0);

  testWidgets(
    'pumpApp defaults to the production predicate — a deterministic Failure '
    'surfaces the error branch on the FIRST attempt, not after a hidden backoff',
    (WidgetTester tester) async {
      // NOTE: deliberately no `retry:` argument — the default is what is under
      // test. Passing one here would make this file assert nothing.
      await tester.pumpApp(const _Probe());
      await tester.pump(); // let the rejected future propagate

      expect(
        find.text('error'),
        findsOneWidget,
        reason:
            'pumpApp must install beauticaProviderRetry by default, so a '
            'deterministic Failure renders the error branch immediately — the '
            'same thing the shipped app does. Finding "loading" here means the '
            'harness fell back to ProviderContainer.defaultRetry and the whole '
            'widget suite is validating a retry policy production dropped.',
      );
      expect(find.text('loading'), findsNothing);
      expect(
        _builds,
        1,
        reason: 'no retry attempt may have been scheduled for a 404',
      );
    },
  );

  testWidgets(
    'pumpRoutedApp defaults to the production predicate too (same guarantee '
    'for the router-hosted call sites)',
    (WidgetTester tester) async {
      final GoRouter router = GoRouter(
        initialLocation: '/',
        routes: <RouteBase>[
          GoRoute(path: '/', builder: (_, _) => const _Probe()),
        ],
      );

      await tester.pumpRoutedApp(router);
      await tester.pump();

      expect(find.text('error'), findsOneWidget);
      expect(find.text('loading'), findsNothing);
      expect(_builds, 1);
    },
  );
}
