// Phase 359 — NotificationsRateLimitedFailure.userMessage (uk locale):
// null / non-positive → the countdown-free variant; N seconds → the counted one.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<({String message, AppLocalizations l10n})> _resolve(
  WidgetTester tester,
  Failure failure,
) async {
  late String message;
  late AppLocalizations l10n;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('uk', 'UA'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (ctx) {
          l10n = AppLocalizations.of(ctx);
          message = failure.userMessage(ctx);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (message: message, l10n: l10n);
}

void main() {
  group('NotificationsRateLimitedFailure.userMessage (uk)', () {
    testWidgets('should_showCountdown_when_retryAfterPositive', (tester) async {
      final r = await _resolve(
        tester,
        const NotificationsRateLimitedFailure(retryAfterSeconds: 30),
      );
      expect(r.message, r.l10n.notificationsErrRateLimited(30));
      expect(r.message, contains('30'));
    });

    testWidgets('should_showNoWaitVariant_when_retryAfterNull', (tester) async {
      final r = await _resolve(tester, const NotificationsRateLimitedFailure());
      expect(r.message, r.l10n.notificationsErrRateLimitedNoWait);
      expect(r.message, isNot(matches(RegExp(r'\d'))));
    });

    testWidgets('should_showNoWaitVariant_when_retryAfterZeroOrNegative', (
      tester,
    ) async {
      for (final s in <int>[0, -5]) {
        final r = await _resolve(
          tester,
          NotificationsRateLimitedFailure(retryAfterSeconds: s),
        );
        expect(r.message, r.l10n.notificationsErrRateLimitedNoWait);
      }
    });

    testWidgets('should_showNoWaitVariant_when_retryAfterAboveUxCeiling', (
      tester,
    ) async {
      final r = await _resolve(
        tester,
        const NotificationsRateLimitedFailure(retryAfterSeconds: 3600),
      );
      expect(r.message, r.l10n.notificationsErrRateLimitedNoWait);
    });
  });
}
