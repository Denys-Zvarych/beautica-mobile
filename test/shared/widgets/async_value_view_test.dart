// Phase 1.5 — Widget tests for `AsyncValueViewX.view()`.
//
// The extension wraps `AsyncValue.when` and provides three default branches:
//   • loading  → `LoadingSkeleton`
//   • data     → caller's widget builder
//   • error    → `ErrorState` (wraps non-Failure errors in `UnknownFailure`)
//
// Tests verify the correct branch widget is rendered for each AsyncValue
// state, that the `data` builder receives the resolved value, and that the
// automatic `UnknownFailure` wrapping fires for raw exceptions.
//
// Isolation: uses a hand-rolled `Notifier<AsyncValue<String>>` whose state
// is pushed from outside the widget tree via `container.read(…).set(…)`.
// No mocking library required — all dependencies are either project widgets
// (ErrorState, LoadingSkeleton) or Flutter framework types.
//
// Note: `test/` is excluded from `no_raw_ui_strings` — raw string literals
// used in `find.text` and data-binding assertions are acceptable here.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/async_value_view.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/loading_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// Test-only Notifier — exposes a `set` method so tests can push any
// AsyncValue<String> state into the provider from outside the widget tree.
// ---------------------------------------------------------------------------

class _AsyncStringNotifier extends Notifier<AsyncValue<String>> {
  @override
  AsyncValue<String> build() => const AsyncValue<String>.loading();

  void set(AsyncValue<String> value) => state = value;
}

final _asyncStringProvider =
    NotifierProvider<_AsyncStringNotifier, AsyncValue<String>>(
      _AsyncStringNotifier.new,
    );

// ---------------------------------------------------------------------------
// Widget under test — calls `asyncValue.view(data: ...)` and renders the
// result. Accepts an optional custom `error:` builder for override tests.
// ---------------------------------------------------------------------------

class _TestWidget extends ConsumerWidget {
  const _TestWidget({this.customError});

  final Widget Function(Object e, StackTrace st)? customError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncValue = ref.watch(_asyncStringProvider);
    return asyncValue.view(
      data: (value) => Text(value, key: const Key('data_text')),
      error: customError,
    );
  }
}

// ---------------------------------------------------------------------------
// Helper — wraps [child] with ProviderScope + MaterialApp (UA locale).
// ---------------------------------------------------------------------------

Widget _wrap(Widget child) => ProviderScope(
  retry: beauticaProviderRetry,
  child: MaterialApp(
    locale: const Locale('uk', 'UA'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AsyncValueViewX.view() — loading state', () {
    testWidgets('renders LoadingSkeleton when AsyncValue is loading', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const _TestWidget()));
      // Do NOT pumpAndSettle — LoadingSkeleton's repeating animation never settles.
      await tester.pump();

      expect(find.byType(LoadingSkeleton), findsOneWidget);
      expect(find.byKey(const Key('data_text')), findsNothing);
    });

    testWidgets('custom loading widget overrides default LoadingSkeleton', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          retry: beauticaProviderRetry,
          child: MaterialApp(
            locale: const Locale('uk', 'UA'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  const AsyncValue<String> loading =
                      AsyncValue<String>.loading();
                  return loading.view(
                    data: (v) => Text(v),
                    loading: const SizedBox(key: Key('custom_loading')),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('custom_loading')), findsOneWidget);
      expect(find.byType(LoadingSkeleton), findsNothing);
    });
  });

  group('AsyncValueViewX.view() — data state', () {
    testWidgets('renders data widget with resolved value', (tester) async {
      await tester.pumpWidget(_wrap(const _TestWidget()));
      await tester.pump();

      // Push the data state via the container.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(_TestWidget)),
      );
      container
          .read(_asyncStringProvider.notifier)
          .set(const AsyncValue<String>.data('Манікюр'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('data_text')), findsOneWidget);
      expect(find.text('Манікюр'), findsOneWidget);
      expect(find.byType(LoadingSkeleton), findsNothing);
      expect(find.byType(ErrorState), findsNothing);
    });

    testWidgets('data builder receives the exact resolved value', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const _TestWidget()));
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(_TestWidget)),
      );
      container
          .read(_asyncStringProvider.notifier)
          .set(const AsyncValue<String>.data('Педикюр'));
      await tester.pumpAndSettle();

      final textWidget = tester.widget<Text>(
        find.byKey(const Key('data_text')),
      );
      expect(textWidget.data, 'Педикюр');
    });
  });

  group('AsyncValueViewX.view() — error state', () {
    testWidgets(
      'renders ErrorState with NetworkFailure when error is a Failure',
      (tester) async {
        await tester.pumpWidget(_wrap(const _TestWidget()));
        await tester.pump();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(_TestWidget)),
        );
        container
            .read(_asyncStringProvider.notifier)
            .set(
              const AsyncValue<String>.error(
                NetworkFailure(),
                StackTrace.empty,
              ),
            );
        await tester.pumpAndSettle();

        expect(find.byType(ErrorState), findsOneWidget);
        expect(find.byKey(const Key('data_text')), findsNothing);
      },
    );

    testWidgets(
      'wraps raw non-Failure exception in UnknownFailure and renders ErrorState',
      (tester) async {
        await tester.pumpWidget(_wrap(const _TestWidget()));
        await tester.pump();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(_TestWidget)),
        );
        container
            .read(_asyncStringProvider.notifier)
            .set(
              AsyncValue<String>.error(
                Exception('socket closed'),
                StackTrace.empty,
              ),
            );
        await tester.pumpAndSettle();

        expect(find.byType(ErrorState), findsOneWidget);

        final l10n = AppLocalizations.of(
          tester.element(find.byType(ErrorState)),
        );
        // UnknownFailure maps to errUnknown.
        expect(find.text(l10n.errUnknown), findsOneWidget);
      },
    );

    testWidgets('custom error builder overrides default ErrorState', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _TestWidget(
            customError: (e, st) => const SizedBox(key: Key('custom_error')),
          ),
        ),
      );
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(_TestWidget)),
      );
      container
          .read(_asyncStringProvider.notifier)
          .set(
            const AsyncValue<String>.error(
              ServerFailure(statusCode: 503),
              StackTrace.empty,
            ),
          );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('custom_error')), findsOneWidget);
      expect(find.byType(ErrorState), findsNothing);
    });
  });
}
