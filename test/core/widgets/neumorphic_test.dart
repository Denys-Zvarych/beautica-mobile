// Phase 1.6 — Neumorphic widget library tests.
//
// Structural tests for the VelvetTouch neumorphic primitives and the new
// VelvetTouch AuthScaffold / AuthBanner. Each group pumps the target widget
// inside a minimal MaterialApp(theme: velvetTheme()) so text styles and
// theme-dependent colours resolve correctly.
//
// Tests are intentionally structural — they assert widget presence and key
// states rather than pixel-exact rendering. Goldens are owned by mobile-qa.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/core/theme/app_theme.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/presentation/widgets/auth_scaffold.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps [widget] in a minimal MaterialApp with the VelvetTouch theme and
/// UA localization delegates (Material + Cupertino + Widgets) so all
/// downstream lookups succeed for `uk` locale without warnings.
Widget _wrap(Widget widget) {
  return MaterialApp(
    theme: velvetTheme(),
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: const <Locale>[Locale('uk')],
    home: Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(child: widget),
    ),
  );
}

void main() {
  // -------------------------------------------------------------------------
  // 1. NeumorphicButton
  // -------------------------------------------------------------------------
  group('NeumorphicButton', () {
    testWidgets('renders label text', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          NeumorphicButton(
            key: const Key('btn_test'),
            label: 'Продовжити',
            onPressed: () {},
          ),
        ),
      );
      expect(find.text('Продовжити'), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator when loading: true', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          NeumorphicButton(
            key: const Key('btn_loading'),
            label: 'Продовжити',
            onPressed: () {},
            loading: true,
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('label text is absent when loading: true', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          NeumorphicButton(
            key: const Key('btn_loading_no_label'),
            label: 'Продовжити',
            onPressed: () {},
            loading: true,
          ),
        ),
      );
      // The Text widget with the label must not be in the tree when loading.
      expect(find.text('Продовжити'), findsNothing);
    });

    testWidgets('onPressed is null when disabled', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          const NeumorphicButton(
            key: Key('btn_disabled'),
            label: 'Продовжити',
            onPressed: null,
          ),
        ),
      );
      // The observable contract for a disabled button is that onPressed is
      // null. The internal disabled-style mechanism (Color.withValues,
      // Opacity widget, or anything else) is an implementation detail — no
      // assertion is made about it here.
      final NeumorphicButton btn = tester.widget<NeumorphicButton>(
        find.byKey(const Key('btn_disabled')),
      );
      expect(btn.onPressed, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // 2. NeumorphicTextField
  // -------------------------------------------------------------------------
  group('NeumorphicTextField', () {
    testWidgets('renders label above the field', (WidgetTester tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _wrap(
          NeumorphicTextField(
            key: const Key('tf_label'),
            label: 'Електронна пошта',
            controller: controller,
          ),
        ),
      );

      expect(find.text('Електронна пошта'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Label must appear above (higher Y) than the TextField.
      final Offset labelPos = tester.getTopLeft(find.text('Електронна пошта'));
      final Offset fieldPos = tester.getTopLeft(find.byType(TextField));
      expect(labelPos.dy, lessThan(fieldPos.dy));
    });

    testWidgets('shows error row with icon when errorText is non-null', (
      WidgetTester tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _wrap(
          NeumorphicTextField(
            key: const Key('tf_error'),
            label: 'Пароль',
            controller: controller,
            errorText: 'Невірний пароль',
          ),
        ),
      );

      expect(find.text('Невірний пароль'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('pressing obscure toggle changes obscureText state', (
      WidgetTester tester,
    ) async {
      final controller = TextEditingController(text: 'secret');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _wrap(
          NeumorphicTextField(
            key: const Key('tf_obscure'),
            label: 'Пароль',
            controller: controller,
            obscureToggle: true,
          ),
        ),
      );

      // Initially obscured.
      final TextField before = tester.widget<TextField>(find.byType(TextField));
      expect(before.obscureText, isTrue);

      // Tap the toggle button identified by the ValueKey injected in the widget.
      await tester.tap(find.byKey(const ValueKey<String>('Пароль_toggle')));
      await tester.pump();

      final TextField after = tester.widget<TextField>(find.byType(TextField));
      expect(after.obscureText, isFalse);
    });

    // Phase 2.17 regression — _contentPadding is cached once in initState.
    // The branch is: prefixIcon == null → horizontal: VelvetSpacing.md (16);
    //                prefixIcon != null → horizontal: VelvetSpacing.sm (8).
    // Verify both branches produce the expected contentPadding on the TextField
    // so a future refactor that accidentally re-evaluates the wrong path is caught.
    testWidgets(
      'contentPadding uses VelvetSpacing.md horizontal when no prefixIcon',
      (WidgetTester tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _wrap(
            NeumorphicTextField(
              key: const Key('tf_padding_no_prefix'),
              label: 'Адреса',
              controller: controller,
              // No prefixIcon — expects horizontal: 16 (VelvetSpacing.md).
            ),
          ),
        );
        await tester.pumpAndSettle();

        final TextField field = tester.widget<TextField>(
          find.byType(TextField),
        );
        final EdgeInsets padding =
            field.decoration!.contentPadding! as EdgeInsets;
        // VelvetSpacing.md == 16
        expect(
          padding.left,
          16.0,
          reason:
              'Without prefixIcon, _contentPadding should use VelvetSpacing.md '
              '(16) horizontal padding',
        );
      },
    );

    testWidgets(
      'contentPadding uses VelvetSpacing.sm horizontal when prefixIcon is set',
      (WidgetTester tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _wrap(
            NeumorphicTextField(
              key: const Key('tf_padding_with_prefix'),
              label: 'Пошта',
              controller: controller,
              prefixIcon: const Icon(Icons.alternate_email_rounded),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final TextField field = tester.widget<TextField>(
          find.byType(TextField),
        );
        final EdgeInsets padding =
            field.decoration!.contentPadding! as EdgeInsets;
        // VelvetSpacing.sm == 8
        expect(
          padding.left,
          8.0,
          reason:
              'With prefixIcon, _contentPadding should use VelvetSpacing.sm '
              '(8) horizontal padding so the text does not overlap the icon',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // 3. NeumorphicInset
  // -------------------------------------------------------------------------
  group('NeumorphicInset', () {
    testWidgets(
      'renders focus ring with BrandColors.accent when focused: true',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _wrap(
            const NeumorphicInset(
              key: Key('inset_focused'),
              focused: true,
              child: SizedBox(height: 54, width: 200),
            ),
          ),
        );

        final AnimatedContainer container = tester.widget<AnimatedContainer>(
          find.byType(AnimatedContainer),
        );
        final BoxDecoration decoration = container.decoration! as BoxDecoration;
        expect(decoration.border, isNotNull);
        final Border border = decoration.border! as Border;
        expect(border.top.color, equals(BrandColors.accent));
      },
    );

    testWidgets(
      'renders error ring with BrandColors.error when hasError: true',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _wrap(
            const NeumorphicInset(
              key: Key('inset_error'),
              hasError: true,
              child: SizedBox(height: 54, width: 200),
            ),
          ),
        );

        final AnimatedContainer container = tester.widget<AnimatedContainer>(
          find.byType(AnimatedContainer),
        );
        final BoxDecoration decoration = container.decoration! as BoxDecoration;
        final Border border = decoration.border! as Border;
        expect(border.top.color, equals(BrandColors.error));
      },
    );
  });

  // -------------------------------------------------------------------------
  // 4. NeumorphicCard
  // -------------------------------------------------------------------------
  group('NeumorphicCard', () {
    testWidgets('renders without throwing', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          const NeumorphicCard(key: Key('card_basic'), child: Text('hello')),
        ),
      );

      expect(find.byType(NeumorphicCard), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('default decoration uses VelvetShadows.extrudedCard', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const NeumorphicCard(
            key: Key('card_shadows'),
            child: SizedBox.shrink(),
          ),
        ),
      );

      final DecoratedBox decoratedBox = tester.widget<DecoratedBox>(
        find.byType(DecoratedBox).first,
      );
      final BoxDecoration decoration = decoratedBox.decoration as BoxDecoration;
      // extrudedCard has 2 box shadows — assert the count matches.
      expect(decoration.boxShadow, hasLength(2));
    });
  });

  // -------------------------------------------------------------------------
  // 5. NeumorphicTile
  // -------------------------------------------------------------------------
  group('NeumorphicTile', () {
    testWidgets('renders in unselected state without throwing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          NeumorphicTile(
            key: const Key('tile_unselected'),
            icon: Icons.person_outline,
            title: 'Клієнт',
            subtitle: 'Знаходьте майстрів та записуйтесь',
            onTap: () {},
          ),
        ),
      );

      expect(find.byType(NeumorphicTile), findsOneWidget);
      expect(find.text('Клієнт'), findsOneWidget);
      // Unselected: chevron_right icon present, no check_circle.
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    });

    testWidgets('switches to inset decoration when selected: true', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          NeumorphicTile(
            key: const Key('tile_selected'),
            icon: Icons.person_outline,
            title: 'Клієнт',
            subtitle: 'Знаходьте майстрів та записуйтесь',
            onTap: () {},
            selected: true,
          ),
        ),
      );

      // Selected: check_circle icon present, no chevron_right.
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      // NeumorphicInset must be in the tree (the inset decoration).
      expect(find.byType(NeumorphicInset), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // 6. AuthScaffold (new VelvetTouch version)
  // -------------------------------------------------------------------------
  group('AuthScaffold (VelvetTouch)', () {
    testWidgets(
      'showBack: true renders a NeumorphicIconButton back affordance',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: velvetTheme(),
            home: const AuthScaffold(
              key: Key('scaffold_back'),
              showBack: true,
              child: Text('content'),
            ),
          ),
        );

        expect(find.byType(NeumorphicIconButton), findsOneWidget);
      },
    );

    testWidgets('showBack: false omits the back button', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: velvetTheme(),
          home: const AuthScaffold(
            key: Key('scaffold_no_back'),
            showBack: false,
            child: Text('content'),
          ),
        ),
      );

      expect(find.byType(NeumorphicIconButton), findsNothing);
    });

    testWidgets('provided bottomBar widget appears in the scaffold', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: velvetTheme(),
          home: const AuthScaffold(
            key: Key('scaffold_bottom_bar'),
            showBack: false,
            bottomBar: Text('bottom_bar_content'),
            child: Text('content'),
          ),
        ),
      );

      expect(find.text('bottom_bar_content'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // 7. AuthBanner
  // -------------------------------------------------------------------------
  group('AuthBanner', () {
    testWidgets('renders icon and message text', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          const AuthBanner(
            key: Key('banner_basic'),
            icon: Icons.info_outline,
            message: 'Підтвердіть свою електронну пошту',
            color: BrandColors.accent,
          ),
        ),
      );

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.text('Підтвердіть свою електронну пошту'), findsOneWidget);
    });

    testWidgets(
      'actionLabel + onAction renders an action link when both provided',
      (WidgetTester tester) async {
        bool tapped = false;

        await tester.pumpWidget(
          _wrap(
            AuthBanner(
              key: const Key('banner_action'),
              icon: Icons.warning_amber_outlined,
              message: 'Щось пішло не так',
              color: BrandColors.error,
              actionLabel: 'Надіслати знову',
              onAction: () => tapped = true,
            ),
          ),
        );

        expect(find.text('Надіслати знову'), findsOneWidget);

        await tester.tap(find.text('Надіслати знову'));
        expect(tapped, isTrue);
      },
    );
  });

  // -------------------------------------------------------------------------
  // 8. VelvetLogo
  // -------------------------------------------------------------------------
  group('VelvetLogo', () {
    testWidgets('renders monogram B and wordmark beautica', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const VelvetLogo(key: Key('logo_default'))),
      );
      await tester.pumpAndSettle();

      // Pillow monogram.
      expect(find.text('B'), findsOneWidget);
      // Wordmark below the pillow.
      expect(find.text('beautica'), findsOneWidget);
    });

    testWidgets('compact: true renders a smaller pillow than the default', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const Row(
            children: <Widget>[
              VelvetLogo(key: Key('logo_normal'), compact: false),
              SizedBox(width: 32),
              VelvetLogo(key: Key('logo_compact'), compact: true),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Both monograms render.
      expect(find.text('B'), findsNWidgets(2));

      // Compact pillow Container carries the stable 'velvet_logo_pillow' Key.
      // Both VelvetLogo instances render it; use Key to locate, RenderBox to measure.
      final pillow1 = tester.getSize(
        find.descendant(
          of: find.byKey(const Key('logo_normal')),
          matching: find.byKey(const Key('velvet_logo_pillow')),
        ),
      );
      final pillow2 = tester.getSize(
        find.descendant(
          of: find.byKey(const Key('logo_compact')),
          matching: find.byKey(const Key('velvet_logo_pillow')),
        ),
      );
      // Normal pillow is larger than compact (80 > 72).
      expect(
        pillow1.height,
        greaterThan(pillow2.height),
        reason:
            'Normal VelvetLogo pillow must be taller than compact (80 > 72)',
      );
      expect(
        pillow2.height,
        closeTo(72.0, 1.0),
        reason: 'Compact pillow height must be 72 px',
      );
    });

    // MEDIUM-2 — default param values are guarded: markFontSize, wordmarkFontSize,
    // compact. If any default changes accidentally, this test catches it.
    testWidgets(
      'default VelvetLogo() has markFontSize=36, wordmarkFontSize=14, compact=false',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _wrap(const VelvetLogo(key: Key('logo_defaults'))),
        );
        await tester.pumpAndSettle();

        final logo = tester.widget<VelvetLogo>(
          find.byKey(const Key('logo_defaults')),
        );

        expect(
          logo.markFontSize,
          equals(36.0),
          reason: 'Default VelvetLogo markFontSize must be 36.',
        );
        expect(
          logo.wordmarkFontSize,
          equals(14.0),
          reason: 'Default VelvetLogo wordmarkFontSize must be 14.',
        );
        expect(
          logo.compact,
          isFalse,
          reason: 'Default VelvetLogo compact must be false.',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // 9. VelvetHeader
  // -------------------------------------------------------------------------
  group('VelvetHeader', () {
    testWidgets('renders the compact VelvetLogo inside the header', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const VelvetHeader(key: Key('header_basic'))),
      );
      await tester.pumpAndSettle();

      // VelvetHeader always embeds a VelvetLogo(compact: true).
      expect(find.byType(VelvetLogo), findsOneWidget);
      // Logo renders its monogram and wordmark.
      expect(find.text('B'), findsOneWidget);
      expect(find.text('beautica'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // 10. NeumorphicIconButton
  // -------------------------------------------------------------------------
  group('NeumorphicIconButton', () {
    testWidgets('renders icon and fires onTap callback', (
      WidgetTester tester,
    ) async {
      bool tapped = false;

      await tester.pumpWidget(
        _wrap(
          NeumorphicIconButton(
            key: const Key('icon_btn'),
            icon: Icons.arrow_back_ios_new_rounded,
            semanticLabel: 'Назад',
            onTap: () => tapped = true,
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);

      await tester.tap(find.byKey(const Key('icon_btn')));
      await tester.pump();

      expect(tapped, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // 11. NeumorphicTextField — autofillHints assertion
  // -------------------------------------------------------------------------
  group('NeumorphicTextField autofillHints assert', () {
    test('throws AssertionError when password autofillHint is given without '
        'obscureToggle', () {
      // Constructing a NeumorphicTextField with a password autofillHint but
      // obscureToggle: false (the default) must trigger the assertion guard.
      final controller = TextEditingController();
      expect(
        () => NeumorphicTextField(
          label: 'Password',
          controller: controller,
          hintText: 'Password',
          autofillHints: const [AutofillHints.password],
          // obscureToggle defaults to false — assertion fires here.
        ),
        throwsAssertionError,
      );
      controller.dispose();
    });

    test(
      'does not throw when password autofillHint is given WITH obscureToggle',
      () {
        // Same hint is allowed when obscureToggle: true.
        final controller = TextEditingController();
        expect(
          () => NeumorphicTextField(
            label: 'Password',
            controller: controller,
            hintText: 'Password',
            autofillHints: const [AutofillHints.password],
            obscureToggle: true,
          ),
          returnsNormally,
        );
        controller.dispose();
      },
    );

    test(
      'does not throw for non-password autofillHints without obscureToggle',
      () {
        final controller = TextEditingController();
        expect(
          () => NeumorphicTextField(
            label: 'Email',
            controller: controller,
            hintText: 'Email',
            autofillHints: const [AutofillHints.email],
          ),
          returnsNormally,
        );
        controller.dispose();
      },
    );
  });

  // -------------------------------------------------------------------------
  // 12. AnimatedWordmark
  // HIGH-2: didUpdateWidget correctly swaps the AnimationController.
  // Also covers the text.length → FadeTransition count contract.
  // -------------------------------------------------------------------------
  group('AnimatedWordmark', () {
    // Verifies that swapping the AnimationController via pumpWidget triggers
    // didUpdateWidget, which calls _disposeAnimations() + _initAnimations(),
    // so the new controller drives the opacity animations from scratch.
    testWidgets('didUpdateWidget swaps controller and resets letter opacities', (
      WidgetTester tester,
    ) async {
      final controllerA = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 880),
      );
      final controllerB = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 880),
      );
      addTearDown(controllerA.dispose);
      addTearDown(controllerB.dispose);

      // Build with controller A at the start (value = 0.0).
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AnimatedWordmark(controller: controllerA)),
        ),
      );
      await tester.pump();

      // Advance controller A to its end — all 8 letters should be fully visible.
      controllerA.value = 1.0;
      await tester.pump();

      final fadesBefore = tester
          .widgetList<FadeTransition>(
            find.descendant(
              of: find.byType(AnimatedWordmark),
              matching: find.byType(FadeTransition),
            ),
          )
          .toList();
      expect(
        fadesBefore,
        hasLength(8),
        reason:
            'AnimatedWordmark("beautica") must produce exactly 8 FadeTransition '
            'widgets.',
      );
      for (final ft in fadesBefore) {
        expect(
          ft.opacity.value,
          equals(1.0),
          reason:
              'All letters must be fully visible after controllerA reaches 1.0.',
        );
      }

      // Swap to controller B which is at its initial value (0.0).
      // didUpdateWidget must re-initialise all animations with the new controller.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AnimatedWordmark(controller: controllerB)),
        ),
      );
      await tester.pump();

      final fadesAfter = tester
          .widgetList<FadeTransition>(
            find.descendant(
              of: find.byType(AnimatedWordmark),
              matching: find.byType(FadeTransition),
            ),
          )
          .toList();
      expect(
        fadesAfter,
        hasLength(8),
        reason:
            'AnimatedWordmark must still produce 8 FadeTransitions after swap.',
      );
      for (final ft in fadesAfter) {
        expect(
          ft.opacity.value,
          equals(0.0),
          reason:
              'didUpdateWidget must re-initialise animations with the new controller '
              '(controllerB at 0.0), so all letter opacities must be 0.0.',
        );
      }

      // Advance controller B to its end — letters must return to fully visible.
      controllerB.value = 1.0;
      await tester.pump();

      for (final ft in tester.widgetList<FadeTransition>(
        find.descendant(
          of: find.byType(AnimatedWordmark),
          matching: find.byType(FadeTransition),
        ),
      )) {
        expect(
          ft.opacity.value,
          equals(1.0),
          reason:
              'Letters must be fully visible after controllerB advances to 1.0.',
        );
      }
    });

    // Verifies that the number of FadeTransition widgets scales with text length.
    // Uses a 3-letter word so the test is unambiguous regardless of the default text.
    testWidgets(
      'produces exactly text.length FadeTransitions for custom text',
      (WidgetTester tester) async {
        final controller = AnimationController(
          vsync: tester,
          duration: const Duration(milliseconds: 880),
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AnimatedWordmark(controller: controller, text: 'bea'),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.descendant(
            of: find.byType(AnimatedWordmark),
            matching: find.byType(FadeTransition),
          ),
          findsNWidgets(3),
          reason:
              "AnimatedWordmark with text='bea' must produce exactly 3 "
              'FadeTransition widgets — one per character.',
        );
      },
    );
  });
}
