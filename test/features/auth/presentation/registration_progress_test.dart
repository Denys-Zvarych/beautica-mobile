// Phase 2.16 + 2026-05-20 design refresh — Widget tests for
// [RegistrationProgress].
//
// Asserts the 4 numbered dots render with correct done/active/inactive state
// for each [RegistrationStep] value AND that the under-dot active label
// (italic Cormorant Garamond camel) is rendered exactly once — under the
// active dot — when [activeStepLabel] is non-null:
//   • account       — dot 1 active; 2/3/4 inactive
//   • details       — dot 1 done; 2 active; 3/4 inactive
//   • verification  — dots 1+2 done; 3 active; 4 inactive
//   • done          — dots 1+2+3 done; 4 active
//
// Test keys (per registration_progress.dart):
//   • Key('progress-step-N')     — one per dot column, N = 1..4
//   • Key('progress-check-N')    — present on done dots only
//   • Key('progress-active-label') — present exactly once when activeStepLabel != null

import 'package:beautica_mobile/features/auth/presentation/widgets/registration_progress.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [RegistrationProgress] inside a minimal localised app shell.
Future<void> _pumpProgress(
  WidgetTester tester,
  RegistrationStep step, {
  String? activeStepLabel,
}) async {
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
          child: RegistrationProgress(
            currentStep: step,
            activeStepLabel: activeStepLabel,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('RegistrationProgress — dot states', () {
    testWidgets('all 4 dot columns are keyed progress-step-N', (tester) async {
      await _pumpProgress(tester, RegistrationStep.account);
      expect(find.byKey(const Key('progress-step-1')), findsOneWidget);
      expect(find.byKey(const Key('progress-step-2')), findsOneWidget);
      expect(find.byKey(const Key('progress-step-3')), findsOneWidget);
      expect(find.byKey(const Key('progress-step-4')), findsOneWidget);
    });

    testWidgets(
      'currentStep=account: all four numbers (1/2/3/4) are visible (no dot '
      'is in done state yet) — no check glyphs anywhere',
      (tester) async {
        await _pumpProgress(tester, RegistrationStep.account);
        // The active and the three inactive dots all show their number;
        // when a dot is in done state the number is replaced by a glyph,
        // so the presence of all four digits proves no done state.
        expect(find.text('1'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('4'), findsOneWidget);
        expect(find.byKey(const Key('progress-check-1')), findsNothing);
        expect(find.byKey(const Key('progress-check-2')), findsNothing);
        expect(find.byKey(const Key('progress-check-3')), findsNothing);
        expect(find.byKey(const Key('progress-check-4')), findsNothing);
      },
    );

    testWidgets(
      'currentStep=details: dot 1 has a checkmark (no "1" digit); dots 2/3/4 '
      'show their numbers',
      (tester) async {
        await _pumpProgress(tester, RegistrationStep.details);
        // Dot 1 is now done — its digit is replaced by the checkmark glyph.
        expect(find.text('1'), findsNothing);
        expect(find.byKey(const Key('progress-check-1')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('progress-check-1')),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
        // The other three dots still render their numbers (and have NO
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
      'currentStep=verification: dots 1+2 are done; dot 3 active; dot 4 '
      'inactive',
      (tester) async {
        await _pumpProgress(tester, RegistrationStep.verification);
        expect(find.text('1'), findsNothing);
        expect(find.text('2'), findsNothing);
        expect(find.byKey(const Key('progress-check-1')), findsOneWidget);
        expect(find.byKey(const Key('progress-check-2')), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.byKey(const Key('progress-check-3')), findsNothing);
        expect(find.text('4'), findsOneWidget);
        expect(find.byKey(const Key('progress-check-4')), findsNothing);
      },
    );

    testWidgets('currentStep=done: dots 1+2+3 done; dot 4 active', (
      tester,
    ) async {
      await _pumpProgress(tester, RegistrationStep.done);
      expect(find.text('1'), findsNothing);
      expect(find.text('2'), findsNothing);
      expect(find.text('3'), findsNothing);
      expect(find.byKey(const Key('progress-check-1')), findsOneWidget);
      expect(find.byKey(const Key('progress-check-2')), findsOneWidget);
      expect(find.byKey(const Key('progress-check-3')), findsOneWidget);
      // Dot 4 itself is `.active` (the wizard's terminal step) — its number
      // is still painted.
      expect(find.text('4'), findsOneWidget);
      expect(find.byKey(const Key('progress-check-4')), findsNothing);
    });

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

  group('RegistrationProgress — active label', () {
    testWidgets('no label is rendered when activeStepLabel is null', (
      tester,
    ) async {
      await _pumpProgress(tester, RegistrationStep.account);
      // Without an activeStepLabel parameter, no progress-active-label key
      // should appear anywhere in the tree.
      expect(find.byKey(const Key('progress-active-label')), findsNothing);
    });

    testWidgets(
      'exactly ONE active-label widget is rendered when activeStepLabel is set',
      (tester) async {
        await _pumpProgress(
          tester,
          RegistrationStep.account,
          activeStepLabel: 'Акаунт',
        );
        expect(find.byKey(const Key('progress-active-label')), findsOneWidget);
        expect(find.text('Акаунт'), findsOneWidget);
      },
    );

    testWidgets('activeStepLabel "Профіль" renders under dot 2 (descendant of '
        'progress-step-2) when currentStep=details', (tester) async {
      await _pumpProgress(
        tester,
        RegistrationStep.details,
        activeStepLabel: 'Профіль',
      );
      expect(find.byKey(const Key('progress-active-label')), findsOneWidget);
      // The label must live inside the active dot's column — dot 2 in this
      // case. Asserts the label is a descendant of progress-step-2.
      expect(
        find.descendant(
          of: find.byKey(const Key('progress-step-2')),
          matching: find.byKey(const Key('progress-active-label')),
        ),
        findsOneWidget,
      );
      // …and is NOT a descendant of any other dot column.
      expect(
        find.descendant(
          of: find.byKey(const Key('progress-step-1')),
          matching: find.byKey(const Key('progress-active-label')),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('progress-step-3')),
          matching: find.byKey(const Key('progress-active-label')),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('progress-step-4')),
          matching: find.byKey(const Key('progress-active-label')),
        ),
        findsNothing,
      );
    });

    testWidgets(
      'activeStepLabel "Локація" also renders under dot 2 (Step 3 collapses to '
      'the same RegistrationStep.details dot)',
      (tester) async {
        await _pumpProgress(
          tester,
          RegistrationStep.details,
          activeStepLabel: 'Локація',
        );
        expect(find.text('Локація'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('progress-step-2')),
            matching: find.byKey(const Key('progress-active-label')),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('activeStepLabel "Верифікація" renders under dot 3 when '
        'currentStep=verification', (tester) async {
      await _pumpProgress(
        tester,
        RegistrationStep.verification,
        activeStepLabel: 'Верифікація',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('progress-step-3')),
          matching: find.byKey(const Key('progress-active-label')),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'activeStepLabel "Готово" renders under dot 4 when currentStep=done',
      (tester) async {
        await _pumpProgress(
          tester,
          RegistrationStep.done,
          activeStepLabel: 'Готово',
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('progress-step-4')),
            matching: find.byKey(const Key('progress-active-label')),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'active label TextStyle is italic Cormorant Garamond 14 px camel '
      '(locks the design-token contract)',
      (tester) async {
        await _pumpProgress(
          tester,
          RegistrationStep.account,
          activeStepLabel: 'Акаунт',
        );
        final labelText = tester.widget<Text>(
          find.byKey(const Key('progress-active-label')),
        );
        final style = labelText.style!;
        expect(style.fontStyle, FontStyle.italic);
        expect(style.fontSize, 14);
        expect(style.fontWeight, FontWeight.w600);
        // Brand camel #B89A7A → 0xFFB89A7A.
        expect(style.color, const Color(0xFFB89A7A));
      },
    );
  });

  group('RegistrationProgress — dot visual states', () {
    testWidgets(
      'active dot decoration carries the camel halo BoxShadow (spread 4)',
      (tester) async {
        await _pumpProgress(tester, RegistrationStep.account);
        // Dot 1 is the active one when currentStep=account.
        final decorations = tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byKey(const Key('progress-step-1')),
                matching: find.byType(DecoratedBox),
              ),
            )
            .toList();
        // Locate the circle decoration (BoxShape.circle).
        final activeDecoration = decorations
            .map((d) => d.decoration as BoxDecoration)
            .firstWhere((d) => d.shape == BoxShape.circle);
        expect(
          activeDecoration.boxShadow,
          isNotEmpty,
          reason: 'Active dot must carry a halo BoxShadow',
        );
        expect(activeDecoration.boxShadow!.first.spreadRadius, 4);
        // Halo color = camel @ 14% alpha → 0x24B89A7A.
        expect(
          activeDecoration.boxShadow!.first.color,
          const Color(0x24B89A7A),
        );
      },
    );

    testWidgets(
      'done dot CustomPaint (checkmark) is rendered as a descendant of '
      'the done dot column',
      (tester) async {
        await _pumpProgress(tester, RegistrationStep.details);
        // Dot 1 is done — check glyph descendant of progress-step-1.
        expect(
          find.descendant(
            of: find.byKey(const Key('progress-step-1')),
            matching: find.byKey(const Key('progress-check-1')),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('inactive dot carries the 1.5 px white border decoration', (
      tester,
    ) async {
      await _pumpProgress(tester, RegistrationStep.account);
      // Dot 2 is inactive when currentStep=account.
      final decorations = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byKey(const Key('progress-step-2')),
              matching: find.byType(DecoratedBox),
            ),
          )
          .toList();
      final inactiveDecoration = decorations
          .map((d) => d.decoration as BoxDecoration)
          .firstWhere((d) => d.shape == BoxShape.circle);
      expect(
        inactiveDecoration.border,
        isNotNull,
        reason: 'Inactive dot must have a border (1.5 px white 15%)',
      );
      expect(inactiveDecoration.boxShadow, isNull);
    });
  });
}
