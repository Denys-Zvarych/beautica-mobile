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
/// native splash on screen while the engine starts up. [SplashScreen.initState]
/// calls [FlutterNativeSplash.remove] on the first Flutter frame so the
/// Phase 2.10 animation picks up seamlessly.
Future<void> main() async {
  // Required before accessing any binding instance from main() — without it
  // SchedulerBinding.instance below hangs on Mali-G52 / this Flutter combo.
  // Phase 2.15: capture the binding so it can be passed to FlutterNativeSplash.
  final binding = WidgetsFlutterBinding.ensureInitialized();

  // Phase 2.15 — preserve the native splash through Flutter engine startup.
  // The native splash (warm taupe #E6DDD0 bg + Beautica B mark) remains visible
  // until SplashScreen.initState calls FlutterNativeSplash.remove(). This
  // eliminates the blank white frame / "F" flutter logo that would otherwise
  // appear between the OS launch window and the first Flutter frame.
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  GoogleFonts.config.allowRuntimeFetching = kDebugMode;

  // 2026-05-20 — Portrait-only orientation lock for the whole app.
  // The Android manifest and iOS Info.plist also lock orientation
  // (defense-in-depth — defends against OS-level forced-rotation
  // accessibility settings). This Dart call additionally pins the engine's
  // preferred orientation list so any in-app orientation change request
  // (e.g. from a third-party plugin) cannot accidentally rotate the UI.
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);

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
