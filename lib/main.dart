import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'routing/app_router.dart';

/// Beautica mobile entry point.
///
/// Phase 1.1 — wires [ProviderScope] (Riverpod root) and the VelvetTouch
/// Material 3 theme factory ([velvetTheme]) seeded from [BrandColors.seed].
/// Light-only: the neumorphic design language requires a single warm-taupe
/// base and is incompatible with a dark-mode surface.
/// Phase 1.4 — replaced [MaterialApp] with [MaterialApp.router] wired to
/// [appRouterProvider] via [ConsumerWidget]; the app boots to
/// [RouteNames.splash].
/// Phase 2.15 — [FlutterNativeSplash.preserve] keeps the branded warm-taupe
/// native splash on screen while the engine starts up. [FlutterNativeSplash.remove]
/// is called synchronously in [main] after [runApp] (not in [SplashScreen.initState])
/// because the F4 auth-redirect design bypasses `/splash` on cold start —
/// [SplashScreen.initState] would never fire, leaving [deferFirstFrame] unreleased.
/// [SplashScreen.initState] retains a redundant [remove] call as an idempotent
/// safety net for the cases where `/splash` is navigated to directly.
Future<void> main() async {
  // Required before accessing any binding instance from main() — without it
  // SchedulerBinding.instance below hangs on Mali-G52 / this Flutter combo.
  // Phase 2.15: capture the binding so it can be passed to FlutterNativeSplash.
  final binding = WidgetsFlutterBinding.ensureInitialized();

  // Phase 2.15 — preserve the native splash through Flutter engine startup.
  // The native splash (warm taupe #E6DDD0 bg + Beautica B mark) remains visible
  // until FlutterNativeSplash.remove() is called below (after runApp). This
  // eliminates the blank white frame / "F" flutter logo that would otherwise
  // appear between the OS launch window and the first Flutter frame.
  // Phase 2.15 fix: remove() is called synchronously after runApp() (not in
  // SplashScreen.initState) because the F4 auth-redirect design bypasses /splash
  // on cold start, so SplashScreen.initState never fires.
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  GoogleFonts.config.allowRuntimeFetching = kDebugMode;

  runApp(const ProviderScope(child: BeauticaApp()));

  // Phase 2.15 fix — release the native splash so the first Flutter frame
  // can render. Must be called after runApp() and synchronously (not in a
  // postFrameCallback) because deferFirstFrame() prevents any frame from
  // scheduling until allowFirstFrame() is called.
  // SplashScreen.initState also calls remove() as a safety net (idempotent).
  FlutterNativeSplash.remove();

  // P1-STARTUP-1 (perf MEDIUM, Phase 2.20 audit): moved from before runApp().
  // The Android manifest and iOS Info.plist lock orientation at OS level
  // (defence-in-depth). This Dart call additionally pins the preferred
  // orientation for runtime requests (e.g. from third-party plugins).
  // Fire-and-forget: the lock takes effect within one frame, not at launch,
  // so awaiting here would add a blocking platform-channel round-trip
  // (5–20 ms) to the cold-start critical path for no user-visible benefit.
  unawaited(
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]),
  );
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
      theme: velvetTheme(),
      themeMode: ThemeMode.light,
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
