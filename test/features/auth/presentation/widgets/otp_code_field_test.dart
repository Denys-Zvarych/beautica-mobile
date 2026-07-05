// Beautica OTP task (Phase B1/B6) — widget tests for the shared [OtpCodeField]
// extracted from `verification_screen.dart`'s original `_OtpField`/`_OtpCell`.
//
// Covered scenarios:
//   1. Renders exactly `length` visible digit cells.
//   2. Typing 6 digits displays each digit in its own cell, in order.
//   3. Non-digit characters are filtered out (digitsOnly formatter).
//   4. Input is capped at `length` characters (LengthLimitingTextInputFormatter).
//   5. Tapping the field requests focus on the hidden TextField.
//   6. The supplied [semanticsLabel] is applied to the OTP entry as a whole.
//   7. The supplied [fieldKey] locates the hidden TextField.

import 'package:beautica_mobile/features/auth/presentation/widgets/otp_code_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _kFieldKey = ValueKey<String>('test_otp_input');

Widget _harness({
  required TextEditingController controller,
  required FocusNode focusNode,
  int length = 6,
  String semanticsLabel = 'Test OTP label',
}) {
  return MaterialApp(
    home: Scaffold(
      body: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => OtpCodeField(
          controller: controller,
          focusNode: focusNode,
          length: length,
          fieldKey: _kFieldKey,
          semanticsLabel: semanticsLabel,
        ),
      ),
    ),
  );
}

void main() {
  group('OtpCodeField', () {
    late TextEditingController controller;
    late FocusNode focusNode;

    setUp(() {
      controller = TextEditingController();
      focusNode = FocusNode();
    });

    tearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    testWidgets('1. renders exactly `length` visible digit cells', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(controller: controller, focusNode: focusNode, length: 6),
      );

      // Each cell is an AnimatedContainer (the private _OtpCell wrapper) — one
      // per digit slot, regardless of fill state.
      expect(find.byType(AnimatedContainer), findsNWidgets(6));
    });

    testWidgets('2. typing 6 digits shows each digit in its own cell', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(controller: controller, focusNode: focusNode),
      );

      await tester.enterText(find.byKey(_kFieldKey), '123456');
      await tester.pump();

      for (final digit in ['1', '2', '3', '4', '5', '6']) {
        expect(find.text(digit), findsOneWidget);
      }
    });

    testWidgets('3. non-digit characters are filtered out', (tester) async {
      await tester.pumpWidget(
        _harness(controller: controller, focusNode: focusNode),
      );

      await tester.enterText(find.byKey(_kFieldKey), 'a1b2c3');
      await tester.pump();

      expect(controller.text, '123');
    });

    testWidgets('4. input is capped at `length` characters', (tester) async {
      await tester.pumpWidget(
        _harness(controller: controller, focusNode: focusNode, length: 6),
      );

      await tester.enterText(find.byKey(_kFieldKey), '1234567890');
      await tester.pump();

      expect(controller.text.length, 6);
      expect(controller.text, '123456');
    });

    testWidgets('5. tapping the field requests focus on the hidden TextField', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(controller: controller, focusNode: focusNode),
      );

      // The hidden TextField is `autofocus: true`, so it already has focus
      // after the first pump — explicitly unfocus first so the tap's
      // `focusNode.requestFocus()` (GestureDetector.onTap) is the thing under
      // test, not the initial autofocus.
      focusNode.unfocus();
      await tester.pump();
      expect(focusNode.hasFocus, isFalse);

      await tester.tap(find.byKey(_kFieldKey));
      await tester.pump();

      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('6. semanticsLabel is applied to the OTP entry', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          controller: controller,
          focusNode: focusNode,
          semanticsLabel: 'Custom OTP semantics label',
        ),
      );

      expect(
        find.bySemanticsLabel('Custom OTP semantics label'),
        findsOneWidget,
      );
    });

    testWidgets('7. fieldKey locates the hidden TextField', (tester) async {
      await tester.pumpWidget(
        _harness(controller: controller, focusNode: focusNode),
      );

      expect(find.byKey(_kFieldKey), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(_kFieldKey)).keyboardType,
        TextInputType.number,
      );
    });
  });
}
