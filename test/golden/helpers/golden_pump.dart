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
// SVG (AppIcon / flutter_svg) decode:
//   `SvgPicture` (`vector_graphics` under the hood) decodes asynchronously via
//   `BytesLoader.loadBytes` + `decodeVectorGraphics`, and paints a blank
//   `SizedBox(width, height)` placeholder until that future resolves
//   (`vector_graphics-*/lib/src/vector_graphics.dart:538` —
//   `_VectorGraphicWidgetState.build`). `vector_graphics` ships a documented
//   fix for exactly that race — `vg.waitForPendingDecodes()` run inside
//   `tester.runAsync` (see its doc comment at
//   `vector_graphics.dart:680-706`) — so we call it below on every golden,
//   after `pumpAndSettle`, as defense-in-depth: `debugGetPendingDecodeTasks`
//   is empty for any cell with no `VectorGraphic` in the tree, so this is a
//   provably free no-op everywhere it isn't needed.
//
//   CORRECTED DIAGNOSIS (mobile-qa, 2026-08-26, Phase 110 Part 2
//   gap-closure): the beauty-timeline-rail MEDIUM finding that motivated
//   adding this call was originally attributed to this exact race — an
//   earlier chain observed that mutating the medallion `AppIcon`'s `size` to
//   an absurd value and regenerating produced a byte-identical golden PNG,
//   and read that as "the SVG never paints." Direct measurement disproved
//   that: with `waitForPendingDecodes` REMOVED, `pumpAndSettle` alone already
//   produced a fully-painted icon (confirmed by sampling non-background
//   pixels in the medallion region) — the SVG was never blank. The actual
//   cause was a layout bug two levels up, in
//   `beauty_timeline_section.dart`'s `_TimelineNode`: the fixed 64×64
//   medallion `Container` had no `alignment`, so its tight BoxConstraints
//   forced ANY child — including the `AppIcon`'s own `size:`-driven
//   `SizedBox` — to render at 64×64 regardless of the value passed. `size: 8`
//   and `size: 32` therefore produced IDENTICAL pixels, not because the icon
//   was invisible, but because both requests were silently clobbered to the
//   same 64dp. Fixed by adding `alignment: Alignment.center` to that
//   `Container` — see its comment there for the `tester.getSize()` proof.
//   `waitForPendingDecodes` is kept here anyway (see above) since it is
//   free and is the package-documented answer to a real, if not the
//   operative, failure mode for this exact widget type.
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
import 'package:flutter_svg/flutter_svg.dart' show vg;
import 'package:flutter_test/flutter_test.dart';

// Exports — re-export alchemist symbols + flutter layout types so callers
// only need to import this file.
export 'package:alchemist/alchemist.dart'
    show
        goldenTest,
        GoldenTestGroup,
        GoldenTestScenario,
        onlyPumpAndSettle,
        pumpOnce,
        // `whilePerforming:` interactions. `press` is the ONLY deterministic
        // way to golden a transient press state: it holds the gesture for a
        // FIXED duration, so the ink radius is byte-stable, where a hand-rolled
        // `startGesture` + `pumpAndSettle` would drain the splash back to rest
        // and silently capture the idle card instead.
        Interaction,
        press,
        longPress;
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

    // Step 4 — wait for any pending flutter_svg / vector_graphics decodes
    // (see the SVG decode note above), then let the resulting `setState`
    // (placeholder → decoded picture) flush into a painted frame. Skipped for
    // the non-settling spinner path — `runAsync` + `pumpAndSettle` there would
    // fight the deliberately-unsettled perpetual animation.
    if (settle) {
      await tester.runAsync(() => vg.waitForPendingDecodes());
      await tester.pumpAndSettle();
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
