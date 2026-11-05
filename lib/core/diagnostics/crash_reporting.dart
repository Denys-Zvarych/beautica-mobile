// Phase 410 (R.3) — crash reporting with sentry_flutter.
//
// D3  `initCrashReporting()` is called from `main()` right after
//     `ensureInitialized()` and the synchronous `EnvGuard.assertConsistent()`
//     (phase 408 pins it first), before `assertSecureUrl`, so later startup
//     failures are caught; as `await SentryFlutter.init(configure)` WITHOUT
//     `appRunner` and WITHOUT `runZonedGuarded` (no zone mismatch;
//     `PlatformDispatcher.onError` covers async). The SDK installs
//     `FlutterError.onError` (framework/build errors — the red/grey
//     ErrorWidget) and `PlatformDispatcher.instance.onError` (uncaught async /
//     isolate-root errors), each CHAINING the previous handler;
//     [_ensureGlobalHandlers] installs a chained fallback for either one the
//     SDK did not.
//     Gate [shouldEnableCrashReporting]: release/profile only, DSN non-empty,
//     `BEAUTICA_ENV ∈ {staging, prod}` (raw dart-define — the AppConfig
//     default does NOT count), https and not loopback/RFC 1918. Otherwise the
//     SDK is never initialised (mirrors backend 371 `rule sentry-local`).
// D4  Privacy-first options (see [_configure]); `scripts/forbid_sentry_pii_
//     options.sh` keeps the PII switches off in `lib/`. `tracesSampleRate` is
//     left UNSET (null): 0 still enables the SDK's tracing integrations.
// D6  `beforeSend` / `beforeBreadcrumb` = `crash_scrubber.dart`.
// D7  [CrashReporting.navigatorObservers] — one `SentryNavigatorObserver`
//     only when the gate passed; an empty list otherwise.
// D8  Opt-out: checked in `beforeSend` (immediate); switching off also
//     closes the SDK so native crashes stop too, switching on re-initialises
//     it with a fresh install ID.
//
// DSN and release come ONLY from `--dart-define=BEAUTICA_SENTRY_DSN=…` /
// `--dart-define=BEAUTICA_RELEASE=…` passed by CI (phase 411) — never from
// `config/env/*.json` (secret-free files), never from `scripts/deploy_apk*.sh`.

import 'dart:async';
import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/app_config.dart';
import '../errors/failures.dart';
import '../network/request_id_interceptor.dart' show sentRequestIdOf;
import 'crash_scrubber.dart';
import 'install_id.dart';

const String _dsnDefine = String.fromEnvironment('BEAUTICA_SENTRY_DSN');
// Raw, NO default: `AppConfig.env` defaults to `staging`, which must not
// switch reporting on for a build that never declared its environment.
const String _envDefine = String.fromEnvironment('BEAUTICA_ENV');
const String _releaseDefine = String.fromEnvironment('BEAUTICA_RELEASE');
const bool _crashSmokeDefine = bool.fromEnvironment('BEAUTICA_CRASH_SMOKE');

/// Environments that report. `local` / unset never do.
const Set<String> kCrashReportingEnvs = <String>{'staging', 'prod'};

/// Phase 410 D3 gate. Pure — every input is a parameter so the matrix test
/// can drive it; production passes the baked constants.
bool shouldEnableCrashReporting({
  required bool isDebug,
  required String dsn,
  required String env,
  required String baseUrl,
}) {
  if (isDebug) return false;
  if (dsn.trim().isEmpty) return false;
  if (!kCrashReportingEnvs.contains(env)) return false;
  if (!baseUrl.startsWith('https://')) return false;
  if (AppConfig.isPrivateOrLoopbackUrl(baseUrl)) return false;
  return true;
}

/// Build-time Sentry configuration.
@immutable
final class CrashReportingConfig {
  const CrashReportingConfig({
    required this.dsn,
    required this.env,
    this.release = '',
  });

  /// The baked `--dart-define`s.
  static const CrashReportingConfig fromEnvironment = CrashReportingConfig(
    dsn: _dsnDefine,
    env: _envDefine,
    release: _releaseDefine,
  );

  final String dsn;
  final String env;

  /// `beautica-mobile@<version>+<build>` (CI, identical to 411's
  /// `SENTRY_RELEASE`); empty → the SDK's own default.
  final String release;

  /// The `<build>` part of [release], or `null`.
  String? get dist {
    final int plus = release.lastIndexOf('+');
    if (plus < 0 || plus == release.length - 1) return null;
    return release.substring(plus + 1);
  }
}

/// Process-wide crash-reporting state. Static because it is set up in
/// `main()` before the ProviderContainer exists and read by Sentry callbacks.
abstract final class CrashReporting {
  static bool _configured = false;
  static bool _optedIn = true;
  static bool _running = false;
  static String? _installId;
  static CrashReportingConfig? _config;
  static DiagnosticsStore? _store;
  static void Function(SentryFlutterOptions)? _debugConfigure;

  /// `true` when this build passed the gate (release/profile + DSN + env +
  /// public https URL), regardless of the user's opt-out.
  static bool get isConfigured => _configured;

  /// `true` while the SDK is initialised and the user has not opted out.
  static bool get isRunning => _running && _optedIn;

  /// The anonymous install ID currently attached to events (tests).
  @visibleForTesting
  static String? get installId => _installId;

  /// D7 — the `GoRouter(observers:)` list.
  static List<NavigatorObserver> navigatorObservers() => _configured
      ? <NavigatorObserver>[
          SentryNavigatorObserver(
            setRouteNameAsTransaction: false,
            enableAutoTransactions: false,
          ),
        ]
      : const <NavigatorObserver>[];

  /// D8 — applies the settings toggle. Off: `beforeSend` drops everything
  /// from this instant, then the SDK is closed (native crash handler too).
  /// On: a fresh install ID, then the SDK is (re)initialised. A no-op beyond
  /// the flag when the build is not configured.
  static Future<void> applyOptIn({
    required bool enabled,
    required String? freshInstallId,
  }) async {
    _optedIn = enabled;
    if (!_configured) return;
    if (!enabled) {
      if (_running) {
        _running = false;
        await Sentry.close();
      }
      return;
    }
    if (freshInstallId != null) _installId = freshInstallId;
    if (!_running) await _initSentry();
  }

  /// Resets all static state (tests only).
  @visibleForTesting
  static Future<void> debugReset() async {
    if (_running) await Sentry.close();
    _configured = false;
    _optedIn = true;
    _running = false;
    _installId = null;
    _config = null;
    _store = null;
    _debugConfigure = null;
  }

  static Future<void> _initSentry() async {
    final CrashReportingConfig? config = _config;
    if (config == null) return;
    final FlutterExceptionHandler? flutterBefore = FlutterError.onError;
    final ErrorCallback? platformBefore = PlatformDispatcher.instance.onError;
    await SentryFlutter.init((SentryFlutterOptions o) {
      _configure(o, config);
      _debugConfigure?.call(o);
    });
    _running = true;
    _ensureGlobalHandlers(flutterBefore, platformBefore);
    final String? id = _installId;
    if (id != null) {
      // Scope user too, so NATIVE crash events (which never pass the Dart
      // beforeSend) carry the same anonymous id — and nothing else.
      await Sentry.configureScope((Scope s) => s.setUser(SentryUser(id: id)));
    }
  }

  static void _configure(SentryFlutterOptions o, CrashReportingConfig c) {
    o
      ..dsn = c.dsn
      ..environment = c.env
      ..release = c.release.isEmpty ? null : c.release
      ..dist = c.dist
      ..sendDefaultPii = false
      ..attachScreenshot = false
      // Explicit OFF per D4 (the default is off too), stated so
      // scripts/forbid_sentry_pii_options.sh has a line to pin.
      // ignore: experimental_member_use
      ..attachViewHierarchy = false
      ..enableUserInteractionBreadcrumbs = false
      ..enableUserInteractionTracing = false
      ..enablePrintBreadcrumbs = false
      ..enableAutoPerformanceTracing = false
      // Unset, not 0: a 0 rate still turns the tracing integrations on.
      ..tracesSampleRate = null
      ..sampleRate = 1.0
      ..enableAutoSessionTracking = true
      ..beforeSend = _beforeSend
      ..beforeBreadcrumb = _beforeBreadcrumb;
    o.replay
      ..sessionSampleRate = 0
      ..onErrorSampleRate = 0;
  }

  static FutureOr<SentryEvent?> _beforeSend(SentryEvent event, Hint hint) {
    if (!_optedIn) return null;
    final String? requestId = crashRequestIdTag(event.throwable);
    final SentryEvent scrubbed = scrubEvent(event, installId: _installId);
    if (requestId != null) {
      scrubbed.tags = <String, String>{
        ...?scrubbed.tags,
        'request_id': requestId,
      };
    }
    return scrubbed;
  }

  static Breadcrumb? _beforeBreadcrumb(Breadcrumb? crumb, Hint hint) =>
      _optedIn ? scrubBreadcrumb(crumb) : null;

  /// D3 — the pinned SDK (9.30.1) installs both handlers itself; this is the
  /// fallback should a future SDK stop doing so. Each chains the previous
  /// handler, so nothing the app (or Flutter) did before is lost.
  static void _ensureGlobalHandlers(
    FlutterExceptionHandler? flutterBefore,
    ErrorCallback? platformBefore,
  ) {
    if (FlutterError.onError == flutterBefore) {
      FlutterError.onError = (FlutterErrorDetails details) {
        unawaited(
          Sentry.captureException(details.exception, stackTrace: details.stack),
        );
        flutterBefore?.call(details);
      };
    }
    final PlatformDispatcher dispatcher = PlatformDispatcher.instance;
    if (dispatcher.onError == platformBefore) {
      dispatcher.onError = (Object error, StackTrace stack) {
        unawaited(Sentry.captureException(error, stackTrace: stack));
        return platformBefore?.call(error, stack) ?? false;
      };
    }
  }
}

/// The `request_id` tag for [throwable]: the id THIS APP generated for the
/// request behind it (never the server echo, which is attacker-shaped input
/// added after scrubbing), and only when it is our 32-lowercase-hex format.
/// `null` → no tag.
@visibleForTesting
String? crashRequestIdTag(Object? throwable) {
  final DioException? dio = switch (throwable) {
    final DioException d => d,
    Failure(cause: final DioException d) => d,
    _ => null,
  };
  return dio == null ? null : sentRequestIdOf(dio);
}

/// Phase 410 D3 entry point, called from `main()`. A no-op (no SDK, no
/// storage read) unless [shouldEnableCrashReporting] passes for the baked
/// constants.
Future<void> initCrashReporting() async {
  const CrashReportingConfig config = CrashReportingConfig.fromEnvironment;
  if (!shouldEnableCrashReporting(
    isDebug: kDebugMode,
    dsn: config.dsn,
    env: config.env,
    baseUrl: AppConfig.baseUrl,
  )) {
    return;
  }
  await startCrashReporting(config, store: const SecureDiagnosticsStore());
}

/// The gate-free half of [initCrashReporting]: reads the opt-out and install
/// ID, then initialises the SDK (unless opted out). Exposed for the init test,
/// which injects a fake transport through [debugConfigure].
@visibleForTesting
Future<void> startCrashReporting(
  CrashReportingConfig config, {
  required DiagnosticsStore store,
  void Function(SentryFlutterOptions options)? debugConfigure,
}) async {
  CrashReporting._configured = true;
  CrashReporting._config = config;
  CrashReporting._store = store;
  CrashReporting._debugConfigure = debugConfigure;
  // Both secure-storage reads run concurrently (startup path).
  final (bool optedIn, String? installId) = await (
    _readOptInSafely(store),
    _readInstallIdSafely(store),
  ).wait;
  CrashReporting._optedIn = optedIn;
  if (!optedIn) return;
  CrashReporting._installId = installId;
  try {
    await CrashReporting._initSentry();
  } on Object catch (e) {
    // Crash reporting must never take the app down with it.
    log(
      'sentry init failed: ${e.runtimeType}',
      name: 'diagnostics',
      level: 1000,
    );
  }
}

Future<bool> _readOptInSafely(DiagnosticsStore store) async {
  try {
    return await readCrashReportingOptIn(store);
  } on Object catch (e) {
    // Unreadable flag → the decided default (on). Never block startup.
    log(
      'opt-out read failed: ${e.runtimeType}',
      name: 'diagnostics',
      level: 900,
    );
    return true;
  }
}

Future<String?> _readInstallIdSafely(DiagnosticsStore store) async {
  try {
    return await InstallId(store).read();
  } on Object catch (e) {
    log(
      'install id read failed: ${e.runtimeType}',
      name: 'diagnostics',
      level: 900,
    );
    return null;
  }
}

/// Step 7 — staging-only smoke canary: with `BEAUTICA_CRASH_SMOKE=true` on a
/// configured STAGING build, throws `StateError('crash smoke canary@x.ua')`
/// 5 s after the first frame (uncaught → `PlatformDispatcher.onError`). The
/// flag is ignored for `prod` and for unconfigured builds.
void scheduleCrashSmokeIfRequested() {
  if (!_crashSmokeDefine) return;
  if (!CrashReporting.isConfigured) return;
  if (CrashReportingConfig.fromEnvironment.env != 'staging') return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Timer(const Duration(seconds: 5), () {
      throw StateError('crash smoke canary@x.ua');
    });
  });
}

/// The store [CrashReporting] was started with, or the production one.
DiagnosticsStore crashReportingStore() =>
    CrashReporting._store ?? const SecureDiagnosticsStore();
