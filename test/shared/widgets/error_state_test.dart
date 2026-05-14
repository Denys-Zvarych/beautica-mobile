// Phase 1.5 — Widget tests for `ErrorState`.
//
// Verifies that:
//   1. ErrorState renders the localised failure message from `failure.userMessage`.
//   2. The retry button (Key: 'error_state_retry_button') is shown only when
//      `onRetry` is supplied and fires the callback exactly once when tapped.
//   3. When `onRetry` is null the retry button is absent.
//   4. The error icon (Icons.error_outline) is always present.
//
// Isolation: no Riverpod providers are involved — `ErrorState` is a pure
// `StatelessWidget` that only needs `AppLocalizations` in the tree.
// All tests use a `MaterialApp` wrapper with the UA locale delegate.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps [child] in a [MaterialApp] configured with UA locale and
/// [AppLocalizations] delegates so that `AppLocalizations.of(ctx)` resolves
/// correctly inside the widget under test.
Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('uk', 'UA'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('ErrorState — message rendering', () {
    testWidgets('renders NetworkFailure user message', (tester) async {
      await tester.pumpWidget(
        _wrap(const ErrorState(failure: NetworkFailure())),
      );
      await tester.pumpAndSettle();

      // Resolve the expected UA string from a live BuildContext.
      final l10n = AppLocalizations.of(tester.element(find.byType(ErrorState)));
      expect(find.text(l10n.errNetwork), findsOneWidget);
    });

    testWidgets('renders NotFoundFailure user message', (tester) async {
      await tester.pumpWidget(
        _wrap(const ErrorState(failure: NotFoundFailure())),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(tester.element(find.byType(ErrorState)));
      expect(find.text(l10n.errNotFound), findsOneWidget);
    });

    testWidgets('renders ServerFailure user message', (tester) async {
      await tester.pumpWidget(
        _wrap(const ErrorState(failure: ServerFailure(statusCode: 500))),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(tester.element(find.byType(ErrorState)));
      expect(find.text(l10n.errServer), findsOneWidget);
    });

    testWidgets('renders UnknownFailure user message', (tester) async {
      await tester.pumpWidget(
        _wrap(const ErrorState(failure: UnknownFailure())),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(tester.element(find.byType(ErrorState)));
      expect(find.text(l10n.errUnknown), findsOneWidget);
    });

    testWidgets('error icon is always rendered', (tester) async {
      await tester.pumpWidget(
        _wrap(const ErrorState(failure: NetworkFailure())),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });

  group('ErrorState — retry button', () {
    testWidgets('retry button absent when onRetry is null', (tester) async {
      await tester.pumpWidget(
        _wrap(const ErrorState(failure: NetworkFailure())),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('error_state_retry_button')), findsNothing);
    });

    testWidgets('retry button present when onRetry is provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(ErrorState(failure: const NetworkFailure(), onRetry: () {})),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('error_state_retry_button')), findsOneWidget);
    });

    testWidgets('tapping retry button invokes onRetry exactly once', (
      tester,
    ) async {
      var callCount = 0;

      await tester.pumpWidget(
        _wrap(
          ErrorState(
            failure: const NetworkFailure(),
            onRetry: () => callCount++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('error_state_retry_button')));
      await tester.pump();

      expect(callCount, 1);
    });

    testWidgets('retry button label is localised retryLabel', (tester) async {
      await tester.pumpWidget(
        _wrap(ErrorState(failure: const ServerFailure(), onRetry: () {})),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(tester.element(find.byType(ErrorState)));
      // Assert the button carries the UA label, not a hardcoded English string.
      expect(find.text(l10n.retryLabel), findsOneWidget);
    });
  });
}
