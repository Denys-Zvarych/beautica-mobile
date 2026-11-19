// M515 audit (perf LOW) — the current-password field drives only the CTA:
// a password keystroke must not rebuild the step (and with it the OTP cells).

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/presentation/widgets/otp_code_field.dart';
import 'package:beautica_mobile/features/auth/presentation/widgets/phone_code_step.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const ValueKey<String> _kCode = ValueKey<String>('phone_code_input');
const ValueKey<String> _kPassword = ValueKey<String>(
  'phone_code_current_password',
);
const ValueKey<String> _kSubmit = ValueKey<String>('phone_code_submit');

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
      home: PhoneCodeStep(
        description: 'code',
        showBack: false,
        requireCurrentPassword: true,
        onConfirm: (String code, String password) async {},
        onResend: () async => null,
      ),
    ),
  );
  await tester.pump();
}

bool _ctaEnabled(WidgetTester tester) =>
    tester.widget<NeumorphicButton>(find.byKey(_kSubmit)).onPressedAsync !=
    null;

Finder _cellDigit(String digit) =>
    find.descendant(of: find.byType(OtpCodeField), matching: find.text(digit));

void main() {
  // Device bug (PR #182): PhoneCodeStep placed OtpCodeField bare, so typed
  // digits were captured (CTA enabled) but the cells never redrew.
  testWidgets('typed digits appear in the code cells', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: PhoneCodeStep(
          description: 'code',
          showBack: false,
          onConfirm: (String code, String password) async {},
          onResend: () async => null,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(_kCode));
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '12',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    expect(_cellDigit('1'), findsOneWidget);
    expect(_cellDigit('2'), findsOneWidget);
    expect(_ctaEnabled(tester), isFalse, reason: 'code incomplete');

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '123456',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump();
    for (final String digit in <String>['1', '2', '3', '4', '5', '6']) {
      expect(_cellDigit(digit), findsOneWidget, reason: 'cell $digit');
    }
    expect(_ctaEnabled(tester), isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('typing the password does not rebuild the code cells', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await tester.enterText(find.byKey(_kCode), '123456');
    await tester.pump();
    final OtpCodeField before = tester.widget<OtpCodeField>(
      find.byType(OtpCodeField),
    );

    await tester.enterText(find.byKey(_kPassword), 'secret');
    await tester.pump();

    // A step-level setState would hand OtpCodeField a NEW widget instance.
    expect(
      identical(tester.widget<OtpCodeField>(find.byType(OtpCodeField)), before),
      isTrue,
    );

    // Unmount so the resend cooldown Timer is cancelled by dispose.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('CTA enables only with a full code AND a password', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await tester.enterText(find.byKey(_kCode), '123456');
    await tester.pump();
    expect(_ctaEnabled(tester), isFalse, reason: 'password still empty');

    await tester.enterText(find.byKey(_kPassword), 's');
    await tester.pump();
    expect(_ctaEnabled(tester), isTrue);

    await tester.enterText(find.byKey(_kPassword), '');
    await tester.pump();
    expect(_ctaEnabled(tester), isFalse, reason: 'password cleared');

    await tester.pumpWidget(const SizedBox());
  });
}
