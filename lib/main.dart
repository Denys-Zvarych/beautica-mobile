import 'dart:async';

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
/// native splash on screen while the engine starts up. Two [FlutterNativeSplash.remove]
/// call sites exist (both idempotent, whichever fires first wins):
///   1. [main] (here, after [runApp]) — safety net for the returning-user
///      bypass path where go_router skips `/splash` entirely and
///      [SplashScreen.initState] never runs. Without this call the native
///      overlay would never be released.
///   2. [SplashScreen.initState] — primary call site for cold-start new-user
///      path where `/splash` is mounted. Moved from addPostFrameCallback to
///      initState in the release-AOT fix (Phase 2.15+): in release mode the
///      auth provider resolves before the first Flutter frame, go_router
///      redirects while [SplashScreen] is still initializing, and a
///      postFrameCallback fires too late (mounted == false → forward() skipped).
///
/// MP-STARTUP-THEME: [velvetTheme()] is computed once and stored here. The
/// [MaterialApp.router] widget re-builds on every [authProvider] state change
/// (via [AuthRefreshNotifier] → [GoRouter.refreshListenable]). Without memoization,
/// [GoogleFonts.nunitoTextTheme()] allocates a new [TextTheme] on every rebuild.
/// This is a P1 frame-budget issue on auth transitions, not a cold-start issue.
final ThemeData _appTheme = velvetTheme();

Future<void> main() async {
  // Required before accessing any binding instance from main() — without it
  // SchedulerBinding.instance below hangs on Mali-G52 / this Flutter combo.
  // Phase 2.15: capture the binding so it can be passed to FlutterNativeSplash.
  final binding = WidgetsFlutterBinding.ensureInitialized();

  // Splash timing is recorded in SplashScreen.initState — see
  // lib/features/auth/presentation/splash_screen.dart. The gate must measure
  // from the moment Flutter's surface becomes visible, not from Dart VM entry,
  // because native splash + Dart VM init can take >1s on Android 12 cold starts.

  // Phase 2.15 — preserve the native splash through Flutter engine startup.
  // The native splash (warm taupe #E6DDD0 bg + Beautica B mark) remains visible
  // until FlutterNativeSplash.remove() is called below (after runApp). This
  // eliminates the blank white frame / "F" flutter logo that would otherwise
  // appear between the OS launch window and the first Flutter frame.
  // Phase 2.15 fix: remove() is called synchronously after runApp() (not in
  // SplashScreen.initState) because the F4 auth-redirect design bypasses /splash
  // on cold start, so SplashScreen.initState never fires.
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  // Fonts are bundled as assets under assets/fonts/ (Comfortaa + Nunito variants).
  // Runtime fetching disabled in ALL modes so release APKs render the wordmark
  // without a network round-trip and debug builds stay consistent.
  // google_fonts automatically prefers the bundled asset when the file is declared
  // in pubspec.yaml and the TTF exists in assets/fonts/.
  GoogleFonts.config.allowRuntimeFetching = false;

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
      theme: _appTheme,
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
