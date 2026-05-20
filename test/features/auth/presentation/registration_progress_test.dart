// Phase 2.16 — Widget tests for [RegistrationProgress].
//
// Asserts the 4 pills render with correct done/active/inactive state for
// each [RegistrationStep] value:
//   • account       — pill 1 active; 2/3/4 inactive
//   • details       — pill 1 done; 2 active; 3/4 inactive
//   • verification  — pills 1+2 done; 3 active; 4 inactive
//   • done          — pills 1+2+3 done; 4 active
//
// Tests use a TextSpan-style structural check (label.toUpperCase() text +
// the pill's number text) rather than fragile string-based RenderObject
// inspection (mobile-backlog rule §4).

import 'package:beautica_mobile/features/auth/presentation/widgets/registration_progress.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [RegistrationProgress] inside a minimal localised app shell.
Future<void> _pumpProgress(WidgetTester tester, RegistrationStep step) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
      home: Scaffold(
        body: SizedBox(
          // 375 dp screen - 16 dp ×2 AuthScaffold padding = 343 dp content area.
          // (Inside the AuthScaffold's maxWidth:400 column.)
          width: 343,
          child: RegistrationProgress(currentStep: step),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// All four pill labels (UA primary).
const _kAllLabels = ['АКАУНТ', 'ДЕТАЛІ', 'ВЕРИФІКАЦІЯ', 'ГОТОВО'];

void main() {
  group('RegistrationProgress', () {
    testWidgets('4 pill labels all render at currentStep=account', (
      tester,
    ) async {
      await _pumpProgress(tester, RegistrationStep.account);
      for (final label in _kAllLabels) {
        expect(
          find.text(label),
          findsOneWidget,
          reason: 'pill label "$label" must render uppercase',
        );
      }
    });

    testWidgets(
      'currentStep=account: all four numbers (1/2/3/4) are visible (no pill '
      'is in done state yet)',
      (tester) async {
        await _pumpProgress(tester, RegistrationStep.account);
        // The active and the three inactive pills all show their number;
        // when a pill is in done state the number is replaced by a glyph,
        // so the presence of all four digits proves no done state.
        expect(find.text('1'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('4'), findsOneWidget);
      },
    );

    testWidgets(
      'currentStep=details: pill 1 has a checkmark (no "1" digit); pills 2/3/4 '
      'show their numbers',
      (tester) async {
        await _pumpProgress(tester, RegistrationStep.details);
        // Pill 1 is now done — its digit is replaced by the checkmark glyph.
        expect(find.text('1'), findsNothing);
        // LOW-qa-2 — positive assertion: the checkmark CustomPaint is
        // actually present for pill 1.
        expect(find.byKey(const Key('progress-check-1')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('progress-check-1')),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
        // The other three pills still render their numbers (and have NO
        // checkmark key).
        expect(find.text('2'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('4'), findsOneWidget);
        expect(find.byKey(const Key('progress-check-2')), findsNothing);
        expect(find.byKey(const Key('progress-check-3')), findsNothing);
        expect(find.byKey(const Key('progress-check-4')), findsNothing);
      },
    );

    testWidgets(
      'currentStep=verification: pills 1+2 are done (no "1"/"2" digits); pill 3 '
      'active; pill 4 inactive',
      (tester) async {
        await _pumpProgress(tester, RegistrationStep.verification);
        expect(find.text('1'), findsNothing);
        expect(find.text('2'), findsNothing);
        // LOW-qa-2 — positive checkmark assertions for pills 1 + 2.
        expect(find.byKey(const Key('progress-check-1')), findsOneWidget);
        expect(find.byKey(const Key('progress-check-2')), findsOneWidget);
        // Pill 3 (verification) is active — number visible, no checkmark.
        expect(find.text('3'), findsOneWidget);
        expect(find.byKey(const Key('progress-check-3')), findsNothing);
        // Pill 4 (done) is still inactive — number visible, no checkmark.
        expect(find.text('4'), findsOneWidget);
        expect(find.byKey(const Key('progress-check-4')), findsNothing);
      },
    );

    testWidgets(
      'currentStep=done: pills 1+2+3 are done (no "1"/"2"/"3" digits); pill 4 '
      'active (number visible)',
      (tester) async {
        await _pumpProgress(tester, RegistrationStep.done);
        expect(find.text('1'), findsNothing);
        expect(find.text('2'), findsNothing);
        expect(find.text('3'), findsNothing);
        // LOW-qa-2 — positive checkmark assertions for pills 1 + 2 + 3.
        expect(find.byKey(const Key('progress-check-1')), findsOneWidget);
        expect(find.byKey(const Key('progress-check-2')), findsOneWidget);
        expect(find.byKey(const Key('progress-check-3')), findsOneWidget);
        // Pill 4 itself is `.active` (the wizard's terminal step) — its number
        // is still painted (see RegistrationStep.done semantics).
        expect(find.text('4'), findsOneWidget);
        expect(find.byKey(const Key('progress-check-4')), findsNothing);
      },
    );

    testWidgets('passing a Key bubbles up to the rendered widget', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('uk'),
          home: Scaffold(
            body: SizedBox(
              width: 343,
              child: RegistrationProgress(
                key: Key('test-progress'),
                currentStep: RegistrationStep.account,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('test-progress')), findsOneWidget);
    });
  });
}
