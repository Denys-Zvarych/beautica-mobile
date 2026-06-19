// AppIcon widget tests + BeauticaAssetIcons unit tests.
//
// Strategy: assert on the widget configuration (size, colorFilter,
// semanticsLabel, bytesLoader asset path) rather than decoding actual SVG
// bytes. SvgPicture.asset defers decoding to the engine; configuration
// assertions are synchronous and deterministic across host environments.
//
// Widget tests pump inside a minimal MaterialApp so IconTheme lookups resolve.
// Pure unit tests (no widget tree) use plain test() rather than testWidgets.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

/// Pumps [widget] inside a bare MaterialApp so IconTheme and other context
/// lookups resolve without routing or localisation infrastructure.
Future<void> _pump(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: widget)),
    ),
  );
}

/// Returns the [SvgPicture] pumped by the most-recent [_pump] call.
SvgPicture _svg(WidgetTester tester) => tester.widget(find.byType(SvgPicture));

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ─── BeauticaAssetIcons unit tests ────────────────────────────────────────

  group('BeauticaAssetIcons', () {
    test('sampleStar resolves to the registered asset path', () {
      // Regression guard: if the constant moves the test fails immediately,
      // alerting the developer that pubspec.yaml and widget references need
      // updating.  Plain test() — no widget tree needed.
      expect(BeauticaAssetIcons.sampleStar, 'assets/icons/sample_star.svg');
    });
  });

  // ─── AppIcon widget tests ─────────────────────────────────────────────────

  group('AppIcon', () {
    // --- Rendering smoke -------------------------------------------------------

    testWidgets('renders without error and contains exactly one SvgPicture', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppIcon(
          BeauticaAssetIcons.sampleStar,
          key: Key('icon_sample_star'),
        ),
      );

      expect(find.byKey(const Key('icon_sample_star')), findsOneWidget);
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets('is a StatelessWidget (const-constructable contract)', (
      tester,
    ) async {
      await _pump(tester, const AppIcon(BeauticaAssetIcons.sampleStar));

      expect(find.byType(AppIcon), findsOneWidget);
      // AppIcon must be a StatelessWidget — callers depend on the const
      // constructor being available for zero-rebuild icon slots.
      expect(tester.widget(find.byType(AppIcon)), isA<StatelessWidget>());
    });

    // --- Asset path forwarding ------------------------------------------------

    testWidgets('forwards the asset path to SvgPicture loader', (tester) async {
      const path = BeauticaAssetIcons.sampleStar;
      await _pump(tester, const AppIcon(path));

      final svg = _svg(tester);
      // SvgPicture.asset wraps the path in an SvgAssetLoader; confirm the
      // loader carries the exact path we passed in. This catches any regression
      // where AppIcon accidentally hard-codes a path in build() instead of
      // using the [asset] field.
      expect(svg.bytesLoader, isA<SvgAssetLoader>());
      expect((svg.bytesLoader as SvgAssetLoader).assetName, path);
    });

    // --- Size -----------------------------------------------------------------

    testWidgets('default size is 24 × 24 logical pixels', (tester) async {
      await _pump(tester, const AppIcon(BeauticaAssetIcons.sampleStar));

      final svg = _svg(tester);
      expect(svg.width, 24.0);
      expect(svg.height, 24.0);
    });

    testWidgets('custom size is forwarded to both width and height', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppIcon(BeauticaAssetIcons.sampleStar, size: 48.0),
      );

      final svg = _svg(tester);
      expect(svg.width, 48.0);
      expect(svg.height, 48.0);
    });

    // --- ColorFilter (explicit color) ----------------------------------------

    testWidgets('explicit color produces ColorFilter.mode(color, srcIn)', (
      tester,
    ) async {
      const tintColor = Color(0xFFB89A7A); // VelvetTouch camel accent

      await _pump(
        tester,
        const AppIcon(BeauticaAssetIcons.sampleStar, color: tintColor),
      );

      final svg = _svg(tester);
      expect(svg.colorFilter, isNotNull);
      expect(
        svg.colorFilter,
        equals(const ColorFilter.mode(tintColor, BlendMode.srcIn)),
      );
    });

    // --- ColorFilter (theme inheritance) ------------------------------------

    testWidgets(
      'null color with ambient IconTheme color forwards that color as '
      'ColorFilter',
      (tester) async {
        // MaterialApp wraps content in an IconTheme with a non-null color.
        // AppIcon must pick it up via IconTheme.of(context).color and produce
        // a ColorFilter — not leave the SvgPicture without one.
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: IconTheme(
                data: IconThemeData(color: Color(0xFF6A4A28)), // mocha seed
                child: Center(child: AppIcon(BeauticaAssetIcons.sampleStar)),
              ),
            ),
          ),
        );

        final svg = _svg(tester);
        expect(
          svg.colorFilter,
          equals(const ColorFilter.mode(Color(0xFF6A4A28), BlendMode.srcIn)),
        );
      },
    );

    testWidgets(
      'null color with bare Directionality (no IconTheme ancestor) still '
      'produces a ColorFilter via framework fallback',
      (tester) async {
        // Flutter's IconTheme.of() ALWAYS returns a non-null color — the
        // fallback IconThemeData has color = Colors.black (0xFF000000).  Even
        // with no MaterialApp or IconTheme ancestor, AppIcon will therefore
        // always produce a ColorFilter.  This test documents and locks that
        // behaviour; if the Flutter framework ever changes the fallback this
        // test will catch it.
        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: AppIcon(BeauticaAssetIcons.sampleStar),
          ),
        );

        final svg = _svg(tester);
        // Framework fallback is Colors.black.
        expect(
          svg.colorFilter,
          equals(const ColorFilter.mode(Color(0xFF000000), BlendMode.srcIn)),
        );
      },
    );

    // --- Semantics -----------------------------------------------------------

    testWidgets('semanticLabel is forwarded to SvgPicture.semanticsLabel', (
      tester,
    ) async {
      const label = 'Star icon';

      await _pump(
        tester,
        const AppIcon(BeauticaAssetIcons.sampleStar, semanticLabel: label),
      );

      expect(_svg(tester).semanticsLabel, label);
    });

    testWidgets(
      'null semanticLabel is forwarded as null — icon is decorative',
      (tester) async {
        await _pump(tester, const AppIcon(BeauticaAssetIcons.sampleStar));

        expect(_svg(tester).semanticsLabel, isNull);
      },
    );
  });
}
