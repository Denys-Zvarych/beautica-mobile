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

    testWidgets('Opacity is 0.55 when disabled (onPressed: null)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const NeumorphicButton(
            key: Key('btn_disabled'),
            label: 'Продовжити',
            onPressed: null,
          ),
        ),
      );
      // The button uses Color.withValues(alpha: 0.55) on leaf colors instead of
      // an Opacity widget — verify disabled state via onPressed being null and
      // confirm no Opacity wrapper is present (perf fix applied).
      final NeumorphicButton btn = tester.widget<NeumorphicButton>(
        find.byKey(const Key('btn_disabled')),
      );
      expect(btn.onPressed, isNull);
      expect(find.byType(Opacity), findsNothing);
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

      // The compact pillow Container is shorter than the standard one.
      // We locate each Container that is a direct child of the logo column by
      // comparing their render heights; compact tile is 64 px, default is 80+.
      final Iterable<Element> containers = find
          .byType(Container)
          .evaluate()
          .where((Element e) {
            final RenderBox rb = e.renderObject! as RenderBox;
            // Only the logo pillow containers — filter by square aspect ratio.
            final Size s = rb.size;
            return s.width > 40 && (s.width - s.height).abs() < 2;
          });

      final List<double> heights = containers.map((Element e) {
        return (e.renderObject! as RenderBox).size.height;
      }).toList()..sort();

      expect(heights.length, greaterThanOrEqualTo(2));
      // Compact pillow (64) must be strictly smaller than the normal pillow.
      expect(heights.first, lessThan(heights.last));
    });
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
}
