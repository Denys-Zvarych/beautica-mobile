import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/config/app_config.dart';
import 'core/errors/failure_retry_policy.dart';
import 'core/icons/beautica_asset_icons.dart';
import 'core/network/dio_provider.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'routing/app_router.dart';
import 'shared/time/time_zones.dart';

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

  // MS-SECURE-URL: throws StateError in release/profile mode if
  // BEAUTICA_BASE_URL is not HTTPS (or a loopback/private-LAN address).
  // Called here — before runApp — so a misconfigured prod deploy fails fast
  // at process startup rather than on the first lazy provider read.
  // The dioProvider also calls this guard, but that fires lazily; this call
  // ensures the guard runs unconditionally on every startup path.
  AppConfig.assertSecureUrl();

  // Load the IANA timezone database and pin the Beautica market zone
  // (Europe/Kyiv) BEFORE any booking/slot formatter runs. Booking instants are
  // canonical UTC; every wall-clock the user sees is converted to Kyiv
  // (DST-aware) via shared/time/time_zones.dart. Synchronous + cheap; must
  // complete before the first frame so the slot picker never reads the zone
  // uninitialised.
  initBeauticaTimeZones();

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

  // Pre-warm every (family, weight) tuple VelvetText actually consumes so the
  // first frame of any screen paints with the bundled glyphs and never the
  // system fallback. Without this, screens that are the first to render a
  // given (family, weight) — login + role-selection — show a one-frame
  // system-font → Nunito swap (visible as a "text flicker"). The native
  // splash is preserved above, so users see solid warm-taupe while these
  // four FontLoader.load() futures complete (~ms on a modern device).
  //
  // If you add a new (family, weight) tuple to VelvetText, add it here too,
  // or the first screen to use it will flicker on cold entry.
  GoogleFonts.comfortaa(fontWeight: FontWeight.w600); // VelvetText.subheading
  GoogleFonts.comfortaa(
    fontWeight: FontWeight.w700,
  ); // wordmark / heading / cta
  GoogleFonts.nunito(fontWeight: FontWeight.w400); // nunitoTextTheme default
  GoogleFonts.nunito(fontWeight: FontWeight.w600); // body / input
  GoogleFonts.nunito(
    fontWeight: FontWeight.w700,
  ); // bodyStrong / label / link / feedback
  GoogleFonts.nunito(
    fontWeight: FontWeight.w800,
  ); // pill / field accent / form caption
  await GoogleFonts.pendingFonts();

  // L3 (mobile-perf, MP11 pattern): warm the flutter_svg cache for the
  // shared notification bell so its first paint (Головна AND the Beauty
  // Passport top bar) does NOT decode + rasterise the SVG on the UI thread.
  // SvgPicture keys its PictureCache on the asset path, so a pre-seeded entry
  // is a guaranteed hit on the first real render. Fire-and-forget: a miss
  // simply falls back to a one-time on-render decode, so this never blocks
  // startup — hence no `await`.
  unawaited(_warmSharedSvgs());

  // MEDIUM-3 (mobile-security 2026-05-27): pre-load ISRG Root X1 cert for
  // Dio IOHttpClientAdapter cert-pinning. Must complete before runApp so
  // the SecurityContext is cached before any provider reads dioProvider.
  await initCertPinning();

  // `retry:` installs the app-wide retry predicate on the ROOT container, so
  // it governs every provider at once. Riverpod's own default retries ANY
  // error that is not an `Error`/`ProviderException` ten times over ~38 s —
  // and a `Failure` is neither, so a 404 or a decode breakdown used to hold
  // the screen in `AsyncLoading` for the whole 38 s instead of rendering its
  // error state. See `core/errors/failure_retry_policy.dart`.
  runApp(
    const ProviderScope(retry: beauticaProviderRetry, child: BeauticaApp()),
  );

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

/// Pre-seeds the flutter_svg [PictureCache] for the SVGs shared across the
/// first screens a CLIENT lands on, so their first paint is a cache hit rather
/// than an on-the-UI-thread decode. Currently just the notification bell
/// ([BeauticaAssetIcons.notificationPlain]) reused by Головна and the Beauty
/// Passport top bar (L3). Add further high-traffic SVGs here as needed.
Future<void> _warmSharedSvgs() async {
  const List<String> assets = <String>[BeauticaAssetIcons.notificationPlain];
  for (final String asset in assets) {
    final SvgAssetLoader loader = SvgAssetLoader(asset);
    await svg.cache.putIfAbsent(
      loader.cacheKey(null),
      () => loader.loadBytes(null),
    );
  }
}

/// `BeauticaApp` needs no explicit mount point for `VelvetSnack`
/// (`lib/shared/feedback/`): `showVelvetSnack` resolves
/// `Overlay.of(context, rootOverlay: true)`, which is the `Overlay` the root
/// `Navigator` below creates on the very first frame and never rebuilds —
/// every route, shell tab, dialog and bottom sheet mounted under
/// `MaterialApp.router` already has it as an ancestor. See
/// `velvet_snack_host.dart`'s file-level doc for the full rationale
/// (including why a snack fired immediately before a route pop survives it).
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
      // Overflow-hardening: clamp the OS accessibility font scale app-wide.
      // Unbounded system font scaling (up to 2.0+ on some devices) overflows
      // the fixed-height home rails and other dense layouts. Bounding it at
      // 1.3 keeps accessibility headroom while staying within the design's
      // tolerance. Applied at the MaterialApp.router builder so it wraps every
      // route. No existing builder was present, so this introduces one.
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      // Phase 1.4 — go_router, managed by Riverpod, replaces the home: param.
      routerConfig: router,
    );
  }
}
