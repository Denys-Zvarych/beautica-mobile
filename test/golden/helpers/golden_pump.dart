// Phase 17.4 — Shared pumping helpers for alchemist goldens.
//
// Alchemist's [goldenTest] API:
//   • [builder]: returns the widget to golden-test, wrapped in
//     [GoldenTestGroup] / [GoldenTestScenario].
//   • [pumpWidget]: optional override — receives (tester, alchemistWidget)
//     where [alchemistWidget] is alchemist's internal [FlutterGoldenTestWrapper]
//     around the builder result. The default pumps it via [tester.pumpWidget];
//     we override it to wrap the tree in [ProviderScope] + [MaterialApp] with
//     UK l10n and a constrained viewport.
//   • [constraints]: size passed to the OverflowBox inside
//     FlutterGoldenTestWrapper — determines the capture width/height.
//   • [textScaleFactor]: forwarded to platformDispatcher (via alchemist).
//
// The [goldenPumpWidget] function returned here is a [PumpWidget] that:
//   1. Sets tester.view.physicalSize to [width] × [kGoldenHeight] dp.
//   2. Wraps alchemist's widget in ProviderScope + MaterialApp with UK locale
//      and [AppLocalizations] delegates, so our screens can call
//      [AppLocalizations.of(context)].
//   3. Calls pumpAndSettle so providers resolve and animations settle.
//
// Overflow handling:
//   Every cell runs with overflow detection ACTIVE — a new RenderFlex overflow
//   on any goldened screen fails the test. The two screens that previously
//   overflowed at 320 dp / textScale 1.3 (login sign-up row, master-profile nav
//   bar + categories header) were fixed in production code, so no per-cell
//   suppression remains.
//
// Usage:
// ```dart
// goldenTest(
//   'login 360dp x1.0',
//   fileName: 'login_360_1x',
//   constraints: BoxConstraints.tight(Size(360, 900)),
//   textScaleFactor: 1.0,
//   pumpWidget: goldenPumpWidget(overrides: [...], width: 360),
//   builder: () => const LoginScreen(),
// );
// ```

// Imports (must precede exports — Dart directive ordering rule).
import 'package:alchemist/alchemist.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Exports — re-export alchemist symbols + flutter layout types so callers
// only need to import this file.
export 'package:alchemist/alchemist.dart'
    show
        goldenTest,
        GoldenTestGroup,
        GoldenTestScenario,
        onlyPumpAndSettle,
        pumpOnce;
export 'package:flutter/material.dart' show BoxConstraints, Size;
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// The three phone widths covered by the Phase 17.4 matrix (logical pixels).
const List<double> kGoldenWidths = <double>[320, 360, 414];

/// The two text scale factors covered by the Phase 17.4 matrix.
const List<double> kGoldenTextScales = <double>[1.0, 1.3];

/// Golden viewport height — tall so Scaffolds never clip vertically.
const double kGoldenHeight = 900.0;

/// Fixed single-frame advance for non-settling (perpetual-spinner) loading
/// goldens. Small enough that the [CircularProgressIndicator] is captured at a
/// deterministic, byte-stable rotation phase. (CI mode obscures text but not the
/// spinner, so the phase must be fixed across runs.)
const Duration kLoadingPumpFrame = Duration(milliseconds: 16);

// ---------------------------------------------------------------------------
// goldenPumpWidget
// ---------------------------------------------------------------------------

/// Returns an alchemist [PumpWidget] that:
///   1. Constrains the viewport to [width] × [kGoldenHeight] dp.
///   2. Wraps [alchemistWidget] in [ProviderScope] + [MaterialApp] with
///      [AppLocalizations] and UK locale so `AppLocalizations.of(context)`
///      resolves inside screens.
///
/// Every cell runs with overflow detection ACTIVE — a new RenderFlex overflow
/// on a goldened screen WILL fail the golden test.
///
/// [overrides] is the Riverpod provider override list for this golden scenario.
/// Pass provider overrides directly (e.g.
/// `myProvider.overrideWithValue(fake)`); the list is cast to the internal
/// [Override] type via [ProviderScope.overrides], mirroring the pattern in
/// `test/helpers/pump_app.dart`.
///
/// The [width] is also used in the [goldenTest]'s [constraints] parameter
/// to tell alchemist the capture width.
///
/// [settle] controls quiescence. The default `true` calls [pumpAndSettle] so
/// providers resolve and entrance animations finish. Set it to `false` for a
/// state that renders a perpetual animation (e.g. an `AsyncLoading` screen with
/// a [CircularProgressIndicator]) — [pumpAndSettle] would otherwise time out on
/// the spinner that never settles. With `settle: false` we pump a single frame
/// plus one fixed [kLoadingPumpFrame] step so the spinner is captured at a
/// deterministic phase.
PumpWidget goldenPumpWidget({
  // List<Object> mirrors pump_app.dart — flutter_riverpod 3.x does not
  // re-export the `Override` sealed class, so we accept Object and let
  // ProviderScope.overrides cast internally.
  List<Object> overrides = const <Object>[],
  required double width,
  bool settle = true,
}) {
  return (WidgetTester tester, Widget alchemistWidget) async {
    // Step 1 — set physical viewport so layout matches [width] logical pixels.
    tester.view.physicalSize = Size(width, kGoldenHeight);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Step 2 — pump: ProviderScope → MaterialApp (UK locale + l10n) →
    // alchemistWidget (FlutterGoldenTestWrapper → scene).
    await tester.pumpWidget(
      ProviderScope(
        retry: beauticaProviderRetry,
        // Cast mirrors pump_app.dart — ProviderScope.overrides accepts
        // List<Override>; callers pass plain override expressions without
        // needing to import the sealed Override type.
        // ignore: avoid_dynamic_calls
        overrides: overrides.cast(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          home: alchemistWidget,
        ),
      ),
    );

    // Step 3 — quiesce. For terminal states (data/error) pumpAndSettle lets
    // providers resolve and entrance animations finish. For a perpetual-spinner
    // loading state, pumpAndSettle would time out, so pump a fixed frame to
    // capture the spinner at a deterministic phase instead.
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(kLoadingPumpFrame);
    }
  };
}

// ---------------------------------------------------------------------------
// widthScaleSuffix
// ---------------------------------------------------------------------------

/// Encodes a (width, textScale) pair as a filename-safe suffix.
///
///   widthScaleSuffix(360, 1.0)  → '360_1x'
///   widthScaleSuffix(414, 1.3)  → '414_1_3x'
String widthScaleSuffix(double width, double scale) {
  final w = width.toInt().toString();
  final s = scale == scale.floorToDouble()
      ? '${scale.toInt()}x'
      : '${scale.toString().replaceAll('.', '_')}x';
  return '${w}_$s';
}
