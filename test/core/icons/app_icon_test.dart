// AppIcon widget tests + BeauticaAssetIcons unit tests.
//
// Strategy: assert on the widget configuration (size, colorFilter,
// semanticsLabel, bytesLoader asset path) rather than decoding actual SVG
// bytes. SvgPicture.asset defers decoding to the engine; configuration
// assertions are synchronous and deterministic across host environments.
//
// Widget tests pump inside a minimal MaterialApp so IconTheme lookups resolve.
// Pure unit tests (no widget tree) use plain test() rather than testWidgets.
//
// All tests use BeauticaAssetIcons.homeOutline as the canonical smoke-test
// asset (replacing the retired sampleStar placeholder).

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
    test('homeOutline resolves to the registered asset path', () {
      // Regression guard: if the constant moves the test fails immediately,
      // alerting the developer that pubspec.yaml and widget references need
      // updating. Plain test() — no widget tree needed.
      expect(BeauticaAssetIcons.homeOutline, 'assets/icons/home_outline.svg');
    });

    test('homeFilled resolves to the registered asset path', () {
      expect(BeauticaAssetIcons.homeFilled, 'assets/icons/home_filled.svg');
    });

    // New icons added in Phase 13.7 SVG migration.
    test('searchOutline resolves to the registered asset path', () {
      expect(
        BeauticaAssetIcons.searchOutline,
        'assets/icons/search_outline.svg',
      );
    });
    test('searchFilled resolves to the registered asset path', () {
      expect(BeauticaAssetIcons.searchFilled, 'assets/icons/search_filled.svg');
    });
    test('heartOutline resolves to the registered asset path', () {
      expect(BeauticaAssetIcons.heartOutline, 'assets/icons/heart_outline.svg');
    });
    test('heartFilled resolves to the registered asset path', () {
      expect(BeauticaAssetIcons.heartFilled, 'assets/icons/heart_filled.svg');
    });
    test('noteOutline resolves to the registered asset path', () {
      expect(BeauticaAssetIcons.noteOutline, 'assets/icons/note_outline.svg');
    });
    test('noteFilled resolves to the registered asset path', () {
      expect(BeauticaAssetIcons.noteFilled, 'assets/icons/note_filled.svg');
    });
    test('passportOutline resolves to the registered asset path', () {
      expect(
        BeauticaAssetIcons.passportOutline,
        'assets/icons/passport_outline.svg',
      );
    });
    test('passportFilled resolves to the registered asset path', () {
      expect(
        BeauticaAssetIcons.passportFilled,
        'assets/icons/passport_filled.svg',
      );
    });
    test('notificationOutline resolves to the registered asset path', () {
      expect(
        BeauticaAssetIcons.notificationOutline,
        'assets/icons/notification_outline.svg',
      );
    });
    test('notificationFilled resolves to the registered asset path', () {
      expect(
        BeauticaAssetIcons.notificationFilled,
        'assets/icons/notification_filled.svg',
      );
    });
    // Bell two-SVG state-swap assets (notification-bell migration).
    test('notificationPlain resolves to the registered asset path', () {
      expect(
        BeauticaAssetIcons.notificationPlain,
        'assets/icons/notification_plain.svg',
      );
    });
    test('notificationUnread resolves to the registered asset path', () {
      expect(
        BeauticaAssetIcons.notificationUnread,
        'assets/icons/notification_unread.svg',
      );
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
          BeauticaAssetIcons.homeOutline,
          key: Key('icon_home_outline'),
        ),
      );

      expect(find.byKey(const Key('icon_home_outline')), findsOneWidget);
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets('is a StatelessWidget (const-constructable contract)', (
      tester,
    ) async {
      await _pump(tester, const AppIcon(BeauticaAssetIcons.homeOutline));

      expect(find.byType(AppIcon), findsOneWidget);
      // AppIcon must be a StatelessWidget — callers depend on the const
      // constructor being available for zero-rebuild icon slots.
      expect(tester.widget(find.byType(AppIcon)), isA<StatelessWidget>());
    });

    // --- Asset path forwarding ------------------------------------------------

    testWidgets('forwards the asset path to SvgPicture loader', (tester) async {
      const path = BeauticaAssetIcons.homeOutline;
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
      await _pump(tester, const AppIcon(BeauticaAssetIcons.homeOutline));

      final svg = _svg(tester);
      expect(svg.width, 24.0);
      expect(svg.height, 24.0);
    });

    testWidgets('custom size is forwarded to both width and height', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppIcon(BeauticaAssetIcons.homeOutline, size: 48.0),
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
        const AppIcon(BeauticaAssetIcons.homeOutline, color: tintColor),
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
                child: Center(child: AppIcon(BeauticaAssetIcons.homeOutline)),
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
            child: AppIcon(BeauticaAssetIcons.homeOutline),
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

    // --- multicolor flag (the bell's red-dot mechanism) ----------------------
    //
    // The unread bell SVG is two-tone (brown bell + vermilion dot). It MUST be
    // rendered with `multicolor: true` so AppIcon emits NO colorFilter — the
    // default srcIn flatten would repaint the red dot to a single colour and
    // defeat the whole two-SVG swap. These tests pin that contract directly on
    // AppIcon (the home_hub widget test only asserts the flag value; here we
    // verify the flag's *effect* on the rendered SvgPicture).

    testWidgets(
      'multicolor:true forces colorFilter null even when color is non-null',
      (tester) async {
        // Both multicolor AND an explicit color set: multicolor wins, so the
        // SVG keeps its own palette (the red dot survives).
        await _pump(
          tester,
          const AppIcon(
            BeauticaAssetIcons.notificationUnread,
            color: Color(0xFFB89A7A), // would normally flatten via srcIn
            multicolor: true,
          ),
        );

        expect(
          _svg(tester).colorFilter,
          isNull,
          reason:
              'multicolor:true must suppress the srcIn ColorFilter so a '
              'two-tone SVG keeps its baked palette (the bell red dot).',
        );
      },
    );

    testWidgets(
      'multicolor:true forces colorFilter null even under an ambient IconTheme',
      (tester) async {
        // Guard the inheritance path too: an ambient IconTheme colour must NOT
        // sneak a ColorFilter back in when multicolor is set.
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: IconTheme(
                data: IconThemeData(color: Color(0xFF6A4A28)),
                child: Center(
                  child: AppIcon(
                    BeauticaAssetIcons.notificationUnread,
                    multicolor: true,
                  ),
                ),
              ),
            ),
          ),
        );

        expect(
          _svg(tester).colorFilter,
          isNull,
          reason:
              'multicolor must win over IconTheme inheritance — no srcIn filter '
              'may be applied to the two-tone unread bell.',
        );
      },
    );

    testWidgets(
      'multicolor:false (default) with explicit color still produces a srcIn '
      'filter — the monochrome idle-bell path',
      (tester) async {
        // The idle/plain bell takes this path: monochrome flatten to a single
        // tint. This is the contrast case to the multicolor tests above.
        const tint = Color(0xFF8A8077); // BrandColors.textSecondary-ish
        await _pump(
          tester,
          const AppIcon(BeauticaAssetIcons.notificationPlain, color: tint),
        );

        expect(
          _svg(tester).colorFilter,
          equals(const ColorFilter.mode(tint, BlendMode.srcIn)),
          reason:
              'multicolor:false is the monochrome path — an explicit color must '
              'still flatten via srcIn (this is how the idle bell is tinted).',
        );
      },
    );

    // --- Semantics -----------------------------------------------------------

    testWidgets('semanticLabel is forwarded to SvgPicture.semanticsLabel', (
      tester,
    ) async {
      const label = 'Home icon';

      await _pump(
        tester,
        const AppIcon(BeauticaAssetIcons.homeOutline, semanticLabel: label),
      );

      expect(_svg(tester).semanticsLabel, label);
    });

    testWidgets(
      'null semanticLabel is forwarded as null — icon is decorative',
      (tester) async {
        await _pump(tester, const AppIcon(BeauticaAssetIcons.homeOutline));

        expect(_svg(tester).semanticsLabel, isNull);
      },
    );
  });
}
