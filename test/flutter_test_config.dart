// Global test harness — auto-discovered by `flutter test` (the framework runs
// the `testExecutable` in any `flutter_test_config.dart` on the path to a test
// file, before that file's `main`).
//
// Responsibilities:
//   1. Pin `GoogleFonts.config.allowRuntimeFetching = false` for the whole
//      suite. The static has no suite-wide setter elsewhere, so under
//      randomized ordering a render/golden test that runs after one which left
//      fetching at its default (`true`) could intermittently attempt a runtime
//      fetch and flake. Pinning it once here removes that nondeterminism and
//      keeps font resolution offline.
//   2. Register the bundled Comfortaa / Nunito TTFs suite-wide via the
//      low-level [ui.loadFontFromList] so EVERY test renders identical real
//      glyphs regardless of ordering. The engine font collection is shared
//      across the whole test process; registering once, up-front, before any
//      test renders text, is the only way to make golden + font-metric layout
//      tests deterministic — a per-suite `setUpAll` loader is NOT enough,
//      because an earlier file rendering `GoogleFonts.*` text first warms the
//      shared collection into an ordering-dependent state. `loadFontFromList`
//      (vs `FontLoader.load`) does NOT broadcast
//      `PaintingBinding.systemFonts.notifyListeners()`.
//   3. Install an [HttpOverrides] that throws on any real socket, so an
//      un-mocked network call fails loudly in the offending test instead of
//      silently leaking a Timer (the dominant flake mode this phase targets).
//   4. Install the Phase 17.2 overflow guard suite-wide so ANY `RenderFlex`
//      overflow fails the offending test. It chains to the default presenter
//      (it does NOT touch `HttpOverrides`/font setup above), so the 17.1
//      no-network net and font determinism are preserved.
//   5. Phase 17.4 — Install the Alchemist config suite-wide so every
//      `goldenTest(...)` call uses a fixed path resolver (pointing at
//      `test/golden/goldens/`) and CI-only rendering (platform goldens are
//      disabled to prevent host-OS font-rendering drift). We intentionally
//      skip Alchemist's own `loadFonts()` (which fires via
//      `goldenTestAdapter.setUp`) because: (a) we already loaded fonts above
//      via `ui.loadFontFromList` which does NOT broadcast
//      `systemFonts.notifyListeners()`, and (b) Alchemist's `FontLoader.load`
//      path DOES broadcast, which triggers the same deactivated-subtree
//      re-render deadlock that step (2) was designed to avoid. Because CI
//      golden mode sets `obscureText: true` (text → coloured blocks), the
//      actual font loaded by Alchemist is irrelevant for comparison stability.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:alchemist/alchemist.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'helpers/overflow_guard.dart';

// The bundled font families and their backing TTF assets (declared in
// pubspec.yaml `flutter > fonts`). Registered under the real family name so
// GoogleFonts-resolved styles (which fall back to the platform family of the
// same name when runtime fetching is off) render the real glyphs.
const Map<String, List<String>> _bundledFonts = {
  'Comfortaa': [
    'assets/fonts/Comfortaa-SemiBold.ttf',
    'assets/fonts/Comfortaa-Bold.ttf',
  ],
  'Nunito': [
    'assets/fonts/Nunito-Regular.ttf',
    'assets/fonts/Nunito-SemiBold.ttf',
    'assets/fonts/Nunito-Bold.ttf',
    'assets/fonts/Nunito-ExtraBold.ttf',
  ],
};

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // (0) Load the IANA timezone database process-globally so every booking/slot
  // formatter (`shared/formatters/booking_date_labels.dart`) can convert to the
  // pinned Europe/Kyiv wall-clock. `tz.getLocation` throws if the database is
  // not initialised, so without this the formatters would throw in any test
  // that renders a booking time. Idempotent + host-independent: the pinned zone
  // means a UTC CI runner and a Kyiv dev box render identical times.
  initBeauticaTimeZones();

  // (1) Never fetch fonts over the network during tests — deterministic + offline.
  GoogleFonts.config.allowRuntimeFetching = false;

  // (2) Register real glyphs suite-wide for deterministic golden/layout renders.
  for (final entry in _bundledFonts.entries) {
    for (final asset in entry.value) {
      final bytes = await rootBundle.load(asset);
      await ui.loadFontFromList(
        bytes.buffer.asUint8List(),
        fontFamily: entry.key,
      );
    }
  }

  // (3) Drain GoogleFonts' deferred load futures up-front.
  //
  // `VelvetText.*` styles are built via `GoogleFonts.comfortaa/nunito(...)`,
  // which (a) emit a TextStyle keyed to a *variant* family name
  // (`Comfortaa_w700`) — NOT the bare `Comfortaa` family registered in step (2)
  // — and (b) queue an async `loadFontIfNecessary` into
  // `GoogleFonts.pendingFonts()` (these resolve from the bundled assets;
  // `allowRuntimeFetching = false` only forbids the network fallback). When such
  // a future completes it runs through `FontLoader.load()`, which broadcasts
  // `PaintingBinding.systemFonts.notifyListeners()`. If that broadcast lands
  // *during a test* — e.g. just after a modal sheet is popped — it dirties the
  // now-deactivated sheet subtree; the engine's diagnostic render then walks a
  // deactivated element's ancestors, throws, re-reports, and recurses forever,
  // so `pumpAndSettle` never quiesces (the apply_schedule_sheet deadlock).
  //
  // Forcing every VelvetText style to resolve now (queuing the futures) and
  // awaiting them BEFORE any test runs makes the single `systemFonts` broadcast
  // fire here, on an empty tree, instead of deferred into a test. This keeps the
  // bundled-glyph determinism from step (2) intact.
  _touchAllVelvetTextStyles();
  await GoogleFonts.pendingFonts();

  // (4) Fail loudly on any real socket — an un-mocked network call must surface
  // as a test failure, not a leaked timer.
  HttpOverrides.global = _NoNetworkHttpOverrides();

  // (5) Phase 17.2 — record every RenderFlex overflow suite-wide. Installed
  // AFTER step (4) and the binding init so it captures the default presenter as
  // its delegate (non-overflow errors still report normally). The 17.1 net
  // lives on HttpOverrides + the font collection, not on FlutterError.onError,
  // so chaining here leaves it fully intact.
  //
  // We install the RECORDER (not the full guard) here because `testExecutable`
  // runs outside any test, where `addTearDown` is invalid. Tests that pump via
  // `pumpApp`/`pumpRoutedApp` arm the failing tearDown themselves
  // (installOverflowGuard), so an overflow at the stress size fails the test.
  installOverflowRecorder();

  // (6) Phase 17.4 — Configure Alchemist suite-wide.
  //
  // Strategy:
  //   • Only CI goldens are enabled (platform goldens disabled). CI mode sets
  //     `obscureText: true` (text → coloured blocks), which is platform-agnostic
  //     — identical bytes regardless of the runner OS. This is what makes goldens
  //     byte-stable in GitHub Actions (Linux) vs local dev (also Linux here, but
  //     the gate future-proofs macOS/Windows contributors).
  //   • The CI file-path resolver writes to `goldens/<fileName>.png` (flat,
  //     no `CI/` subdirectory). Each golden test file lives under
  //     `test/golden/`, so the final path on disk is
  //     `test/golden/goldens/<name>.png` — checked into git as the master.
  //   • `renderShadows: false` keeps CI images stable between Flutter patch
  //     releases that tweak shadow blending.
  //   • We do NOT wrap testMain with runWithConfig here because
  //     `AlchemistConfig.runWithConfig` is synchronous (Zone.current) and
  //     testMain is async — the Zone would exit before tests run. Instead we
  //     rely on Alchemist's `AlchemistConfig.current()` Zone lookup which each
  //     `goldenTest` call performs at its own call site; we set the global
  //     default by running the whole testMain inside the zone.
  await AlchemistConfig.runWithConfig(
    config: const AlchemistConfig(
      platformGoldensConfig: PlatformGoldensConfig(enabled: false),
      ciGoldensConfig: CiGoldensConfig(
        enabled: true,
        obscureText: true,
        renderShadows: false,
        filePathResolver: _ciFilePathResolver,
      ),
    ),
    run: testMain,
  );
}

/// Resolves the path for a CI golden image.
///
/// Alchemist calls this with [fileName] (the test's logical name, no extension)
/// and [environmentName] ('CI'). The returned path is RELATIVE to the test
/// file that calls `goldenTest`. Golden test files live under
/// `test/golden/`, so `goldens/<fileName>.png` places the PNG at
/// `test/golden/goldens/<fileName>.png` (flat, no `CI/` subdirectory) —
/// the intended master location.
FutureOr<String> _ciFilePathResolver(String fileName, String environmentName) =>
    'goldens/$fileName.png';

/// Forces the lazy `VelvetText` static styles to build, so every backing
/// `GoogleFonts.*` call queues its load future into `GoogleFonts.pendingFonts()`
/// before [testExecutable] drains them. Touch only the family-distinct base
/// styles; the `copyWith` variants reuse the same loaded family and add no new
/// pending future. Listed explicitly (vs reflection) so a new base style is a
/// visible compile-time addition here.
void _touchAllVelvetTextStyles() {
  // Comfortaa families.
  VelvetText.wordmark();
  VelvetText.heading();
  VelvetText.subheading();
  VelvetText.cta();
  VelvetText.displayName();
  VelvetText.sectionLabel();
  VelvetText.statValue();
  VelvetText.cardTitle();
  // Nunito families.
  VelvetText.body();
  VelvetText.bodyStrong();
  VelvetText.input();
  VelvetText.label();
  VelvetText.link();
  VelvetText.statCaption();
  VelvetText.pill();
  VelvetText.feedback(const ui.Color(0xFF000000));
}

/// [HttpOverrides] that refuses to create any real [HttpClient] — every attempt
/// to open a socket throws, so an un-mocked network call fails the test loudly.
class _NoNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw UnsupportedError(
      'Real network access is disabled in tests. An un-mocked HTTP call '
      'reached the socket layer — override the relevant repository/provider '
      'with a fake instead.',
    );
  }
}
