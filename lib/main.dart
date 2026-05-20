import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/perf/perf_log.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'routing/app_router.dart';

/// Beautica mobile entry point.
///
/// Phase 1.1 — wires [ProviderScope] (Riverpod root) and the Material 3
/// theme factories ([lightTheme], [darkTheme]) seeded from the brand
/// palette. Phase 1.2 adds the Manrope type scale (see `app_theme.dart`)
/// and pins [GoogleFonts.config.allowRuntimeFetching] to debug-only —
/// release builds must rely on the cached/bundled font (Phase 11 will
/// move Manrope into `assets/fonts/` for fully offline release builds).
/// Phase 1.4 — replaced [MaterialApp] with [MaterialApp.router] wired to
/// [appRouterProvider] via [ConsumerWidget]; the [_BootstrapHome] counter
/// scaffold has been removed and the app now boots to [RouteNames.splash].
void main() {
  perfLog('main:enter');
  GoogleFonts.config.allowRuntimeFetching = kDebugMode;

  // PERF instrumentation — frame timings.
  //
  // Logs any frame whose `buildDuration` or `rasterDuration` exceeds 50 ms
  // (mobile budget is 16.7 ms at 60 fps; >50 ms is jank-level slow). This
  // is the ground truth for the GPU-rasterisation gap during the login →
  // register navigation: per-frame raster of 150 ms+ confirms a Mali-G52
  // stall on the dithered bg picture; <16 ms after the AuthGradientBackground
  // RepaintBoundary + _RegBrandRow BackdropFilter removal means the fix
  // landed.
  //
  // Grep target: `adb logcat | grep BEAUTICA_PERF`. SchedulerBinding is
  // auto-created on first access, so the callback can be registered before
  // runApp() and will start receiving timings as soon as the binding ticks.
  SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
    for (final t in timings) {
      final buildMs = t.buildDuration.inMicroseconds / 1000.0;
      final rasterMs = t.rasterDuration.inMicroseconds / 1000.0;
      final totalMs = t.totalSpan.inMicroseconds / 1000.0;
      if (rasterMs > 50.0 || buildMs > 50.0) {
        perfLog(
          'frame: build=${buildMs.toStringAsFixed(1)}ms '
          'raster=${rasterMs.toStringAsFixed(1)}ms '
          'total=${totalMs.toStringAsFixed(1)}ms',
        );
      }
    }
  });

  perfLog('main:before-runApp');
  runApp(const ProviderScope(child: BeauticaApp()));
}

class BeauticaApp extends ConsumerWidget {
  const BeauticaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      // `MaterialApp.title` is evaluated at app-construction time, BEFORE the
      // `Localizations` widget is in scope, so `AppLocalizations.of(context)`
      // cannot be read there. `onGenerateTitle` is the canonical Flutter hook
      // for localized titles — it runs with a context that has the delegates
      // already attached.
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
      debugShowCheckedModeBanner: false,
      theme: lightTheme(),
      darkTheme: darkTheme(),
      themeMode: ThemeMode.system,
      // Localization wiring (Phase 1.3). Carried unchanged from MaterialApp.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Forced UA until LocaleNotifier ships (post-MVP).
      locale: const Locale('uk', 'UA'),
      // Phase 1.4 — go_router, managed by Riverpod, replaces the home: param.
      routerConfig: router,
    );
  }
}
