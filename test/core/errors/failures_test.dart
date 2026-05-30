// Phase 1.5 — Unit tests for the `Failure` sealed hierarchy.
//
// Strategy: pump a minimal `MaterialApp` with `AppLocalizations` configured
// for the Ukrainian locale, then call `failure.userMessage(ctx)` from inside
// a `Builder` that captures the live `BuildContext`. This tests the exact
// string that the UI would display without depending on any Riverpod or Dio
// infrastructure.
//
// Test count: 6 `testWidgets` (one per concrete `Failure` subtype) + 1 unit
// test for `ValidationFailure.fieldErrors` storage.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a `MaterialApp` with UA locale + `AppLocalizations` delegates and
/// returns the `AppLocalizations` instance resolved inside the widget tree.
///
/// The pump also triggers the test to process any pending timers/microtasks
/// so localization loading completes before the caller uses the returned
/// instance.
Future<AppLocalizations> _pumpAndGetL10n(WidgetTester tester) async {
  late AppLocalizations captured;

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('uk', 'UA'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (ctx) {
          captured = AppLocalizations.of(ctx);
          return const SizedBox.shrink();
        },
      ),
    ),
  );

  // Let the localizations delegate complete its `SynchronousFuture` load.
  await tester.pumpAndSettle();

  return captured;
}

/// Pumps the widget tree and resolves [failure.userMessage] inside the live
/// `BuildContext`. Returns the resolved string.
Future<String> _resolveMessage(WidgetTester tester, Failure failure) async {
  late String resolved;

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('uk', 'UA'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (ctx) {
          resolved = failure.userMessage(ctx);
          return const SizedBox.shrink();
        },
      ),
    ),
  );

  await tester.pumpAndSettle();

  return resolved;
}

void main() {
  group('Failure.userMessage — Ukrainian locale', () {
    testWidgets('NetworkFailure returns errNetwork', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      final msg = await _resolveMessage(tester, const NetworkFailure());
      expect(msg, equals(l10n.errNetwork));
    });

    testWidgets('NotFoundFailure returns errNotFound', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      final msg = await _resolveMessage(tester, const NotFoundFailure());
      expect(msg, equals(l10n.errNotFound));
    });

    testWidgets('UnauthorizedFailure returns errUnauthorized', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      final msg = await _resolveMessage(tester, const UnauthorizedFailure());
      expect(msg, equals(l10n.errUnauthorized));
    });

    testWidgets('ValidationFailure returns errValidation', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      final msg = await _resolveMessage(
        tester,
        const ValidationFailure(fieldErrors: {'email': 'Invalid format'}),
      );
      expect(msg, equals(l10n.errValidation));
    });

    testWidgets('ServerFailure returns errServer', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      final msg = await _resolveMessage(
        tester,
        const ServerFailure(statusCode: 503),
      );
      expect(msg, equals(l10n.errServer));
    });

    testWidgets('UnknownFailure returns errUnknown', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      final msg = await _resolveMessage(tester, const UnknownFailure());
      expect(msg, equals(l10n.errUnknown));
    });
  });

  group('ValidationFailure — fieldErrors storage', () {
    test('stores fieldErrors map correctly', () {
      const failure = ValidationFailure(
        fieldErrors: {
          'email': 'Must be a valid email address',
          'phone': 'Phone number is required',
        },
      );

      expect(failure.fieldErrors['email'], 'Must be a valid email address');
      expect(failure.fieldErrors['phone'], 'Phone number is required');
      expect(failure.fieldErrors, hasLength(2));
    });

    test('fieldErrors is empty when no field errors supplied', () {
      const failure = ValidationFailure(fieldErrors: {});
      expect(failure.fieldErrors, isEmpty);
    });
  });

  group('ProviderMissingCityFailure.userMessage', () {
    testWidgets('returns verificationErrProviderMissingCity l10n string', (
      tester,
    ) async {
      final l10n = await _pumpAndGetL10n(tester);
      final msg = await _resolveMessage(
        tester,
        const ProviderMissingCityFailure(),
      );
      expect(
        msg,
        equals(l10n.verificationErrProviderMissingCity),
        reason:
            'ProviderMissingCityFailure.userMessage must return the '
            'verificationErrProviderMissingCity l10n key so the UI shows the '
            '"go back to step 3" recovery message.',
      );
    });

    test('cause is nullable and defaults to null', () {
      const failure = ProviderMissingCityFailure();
      expect(failure.cause, isNull);
    });

    test('cause is preserved when supplied', () {
      final underlying = Exception('draft cleared');
      final failure = ProviderMissingCityFailure(cause: underlying);
      expect(failure.cause, same(underlying));
    });
  });

  group('Failure — cause storage', () {
    test('cause is preserved on NetworkFailure', () {
      final underlying = Exception('socket closed');
      final failure = NetworkFailure(cause: underlying);
      expect(failure.cause, same(underlying));
    });

    test('ServerFailure stores statusCode', () {
      const failure = ServerFailure(statusCode: 502);
      expect(failure.statusCode, 502);
    });

    test('ServerFailure statusCode is nullable', () {
      const failure = ServerFailure();
      expect(failure.statusCode, isNull);
    });
  });
}
