// Phase 2.2 — Dio singleton provider.
// Phase 2.7 — RefreshInterceptor added to the chain. It runs BEFORE
//             ErrorMapperInterceptor — see ORDER IS LOAD-BEARING below; it was
//             registered after the mapper until 2026-08-07, which made it
//             unreachable. Do not restore that order.
// Phase MEDIUM-3 — iOS cert-pinning (mobile-security 2026-05-27).
//
// This is the single [Dio] instance used for all authenticated API calls.
// Do NOT call `Dio()` anywhere in lib/features/ — always use
// `ref.watch(dioProvider)` or `ref.read(dioProvider)`.
//
// Interceptor order (matters!):
//   1. AuthInterceptor           — attaches Bearer token to outgoing requests.
//   2. LoggingInterceptor        — logs traffic; debug builds only.
//   3. ClockSkewWarningInterceptor — debug-only device/server clock-skew log
//      (2026-08-02) — diagnostics only, see that file's header; no code path
//      trusts or applies the value.
//   4. RefreshInterceptor        — handles 401 retry with silent token refresh.
//   5. ErrorMapperInterceptor    — converts DioException → typed Failure.
//
// ORDER IS LOAD-BEARING — RefreshInterceptor MUST precede ErrorMapperInterceptor
// (mobile-security 2026-08-07). ErrorMapperInterceptor terminates the error flow
// with `handler.reject(...)`, which sets `InterceptorResultType.reject`; dio's
// `errorInterceptorWrapper` (dio_mixin.dart ~:450-460) forwards to the NEXT error
// interceptor only for `next` / `rejectCallFollowing`. With the mapper first,
// `RefreshInterceptor.onError` was unreachable for EVERY endpoint in the app:
// silent 401 refresh never fired and the logout-on-refresh-failure branch was
// dead code (reproduced with a 2-interceptor harness: mapperRan=true,
// refreshRan=false). RefreshInterceptor therefore branches on the RAW
// DioException (`err.response?.statusCode == 401`) and always hands control on
// with `handler.next(...)`, never `reject`, so callers still receive typed
// Failures from the mapper behind it. Do not reorder these two.
//
// A separate [refreshDioProvider] with NO interceptors is used by
// [RefreshInterceptor] for POST /auth/refresh to avoid circular requests.
//
// Cert-pinning architecture (MEDIUM-3):
//   [initCertPinning] is called from main() before runApp(). It loads the
//   pinned root PEMs ([_pinnedRootCertAssets]) from the Flutter asset bundle
//   and constructs a [SecurityContext] that trusts ONLY those roots. The
//   context is cached in [_cachedSecurityContext]. When [dioProvider] builds
//   the Dio instance it reads the cached context and wires
//   [IOHttpClientAdapter] so every TLS connection is verified against them.
//
//   This approach keeps [dioProvider] synchronous (no call-site API change)
//   while guaranteeing the pin is in effect before the first network call.
//   On Android this supplements network_security_config.xml (belt-and-suspenders)
//   and MUST list the same certificates as that file's <trust-anchors>.
//   On iOS this is the only pin (no OS-level equivalent to Android's config).
//
// ---------------------------------------------------------------------------
// WHY THIS PINS ROOTS AND NOT AN INTERMEDIATE  (mobile-security MEDIUM #6,
// assessed 2026-07-22 — read before "tightening" this to a leaf/intermediate)
// ---------------------------------------------------------------------------
// The weakness is real and acknowledged: a root anchor is satisfied by ANY
// certificate Let's Encrypt issues for the host, so an attacker who can pass
// LE domain validation (DNS or BGP hijack) defeats it. The reason it is not
// tightened is that a tighter pin cannot be made both correct and operable
// here. Three independent blockers, each sufficient on its own:
//
// 1. dart:io CANNOT express an SPKI pin set. [SecurityContext] takes trust
//    ANCHORS, not pins. The only other hook, [HttpClient.badCertificateCallback],
//    fires ONLY after validation has already failed (it relaxes, it cannot add
//    a check) and receives just the LEAF [X509Certificate]. That class exposes
//    only der/pem/sha1/subject/issuer/startValidity/endValidity — there is no
//    publicKey, no subjectPublicKeyInfo, no sha256 and no chain accessor
//    (verified by compile probe, 2026-07-22). So the intermediate's SPKI is
//    simply not reachable from Dart. Android's <pin-set> COULD express it,
//    which means an intermediate pin would be enforced on Android only — the
//    two enforcement points could not agree, which is exactly the "false sense
//    of security" the finding warns about, plus a brick risk on both.
//
// 2. We do not own the certificate. The host is served by Railway's PLATFORM
//    WILDCARD `CN=*.up.railway.app` — one shared cert for all Railway
//    customers. Issuer selection is Railway's operational choice, changed
//    without notice to us and with no contract or announcement channel. A
//    pinned intermediate set is a bet on a third party's private CA decisions.
//
// 3. There is no rotation process to hang a pin set on. No remote config, no
//    forced-update gate, no store presence yet, and nobody subscribed to LE /
//    Railway CA-rotation notices. A pin set is only as safe as the process
//    that refreshes it before it expires; that process does not exist. Adding
//    the pin without it converts a theoretical MITM risk into a certain
//    total-outage-in-90-days risk.
//
// If pinning is ever tightened, ALL of these must be resolved first — see the
// Pre-release checklist row in docs/mobile-phases/mobile-backlog.md.
//
// NOTE — the PUBLIC MEDIA path (avatars / portfolio photos from Cloudflare R2)
// deliberately does NOT use this pinned context. It uses the system trust
// store on purpose — see the ADR header in `core/media/beautica_image.dart`
// for why pinning the R2 origin would brick every avatar on a silent
// Cloudflare CA rotation. Do NOT "fix the asymmetry" by pinning media too.
//
// ---------------------------------------------------------------------------
// WHY TWO ROOTS  (this is the part that was actually broken)
// ---------------------------------------------------------------------------
// Live chain, captured 2026-07-22:
//
//     leaf *.up.railway.app
//       <- Let's Encrypt YE1   (intermediate, exp 2028-09-02)
//       <- ISRG Root YE        (intermediate, exp 2032-09-02)
//       <- ISRG Root X2        (CROSS-SIGNED BY ISRG Root X1)
//
// The chain roots at X2, NOT X1. Pinning X1 alone validated it only because
// Railway/LE still serve the X1 cross-sign of X2 as the final chain element —
// a server-side choice, not ours. Dropping it is the expected direction (X2 is
// natively trusted on modern OSes, so chains get shortened), and the moment it
// happens an X1-only anchor FAILS CLOSED: every shipped build loses all
// connectivity, unfixable without an emergency store release.
//
// Verified with `openssl verify -no-CApath -no-CAstore` against the live chain:
//   X1 only,  cross-sign removed -> "unable to get local issuer certificate"
//   X1 + X2,  cross-sign removed -> OK
//   X1 + X2,  chain as served     -> OK
//
// Trusting both roots is STRICTLY WIDENING — it accepts everything the X1-only
// anchor accepted plus the shortened chain — so it cannot regress connectivity.

import 'dart:developer';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../config/app_config.dart';
import 'auth_interceptor.dart';
import 'clock_skew_warning_interceptor.dart';
import 'error_mapper_interceptor.dart';
import 'logging_interceptor.dart';
import 'refresh_interceptor.dart';

part 'dio_provider.g.dart';

// ---------------------------------------------------------------------------
// Cert-pinning initialisation — called once from main() before runApp().
// ---------------------------------------------------------------------------

/// The pinned trust anchors, in chain-validation preference order.
///
/// Both are required — see the "WHY TWO ROOTS" analysis in the file header.
/// These MUST stay byte-identical to the `@raw/` copies referenced by
/// `android/app/src/main/res/xml/network_security_config.xml`; the two
/// enforcement points are only meaningful if they agree.
const List<String> _pinnedRootCertAssets = <String>[
  'assets/certs/isrg_root_x1.pem',
  'assets/certs/isrg_root_x2.pem',
];

/// Cached [SecurityContext] built from [_pinnedRootCertAssets].
///
/// `null` until [initCertPinning] completes. If [initCertPinning] fails in
/// a non-debug build the exception propagates and prevents app startup,
/// ensuring the app never runs without pinning in production.
SecurityContext? _cachedSecurityContext;

/// Loads the pinned root PEMs from the Flutter asset bundle and caches a
/// [SecurityContext] that trusts only those roots.
///
/// MUST be awaited before [runApp]. The cached context is read by
/// [dioProvider] when it constructs the [IOHttpClientAdapter].
///
/// Every asset in [_pinnedRootCertAssets] must load — a partially-populated
/// anchor set is treated as a failure rather than silently shipping a weaker
/// pin than intended.
///
/// In debug builds a cert-loading failure is logged and the app continues
/// with system-trust fallback (acceptable for local dev against non-pinned
/// backends). In release builds the exception is rethrown — fail-closed is
/// the correct behaviour.
Future<void> initCertPinning() async {
  try {
    final SecurityContext context = SecurityContext(withTrustedRoots: false);
    for (final String asset in _pinnedRootCertAssets) {
      final ByteData pemBytes = await rootBundle.load(asset);
      context.setTrustedCertificatesBytes(pemBytes.buffer.asUint8List());
    }
    _cachedSecurityContext = context;
    log(
      'Cert-pinning initialised with ${_pinnedRootCertAssets.length} trust '
      'anchors: ${_pinnedRootCertAssets.join(', ')}',
      name: 'network.cert',
      level: 800,
    );
  } catch (e, st) {
    log(
      'Cert-pinning setup failed — anchors requested: '
      '${_pinnedRootCertAssets.join(', ')}',
      name: 'network.cert',
      level: 1000,
      error: e,
      stackTrace: st,
    );
    if (!kDebugMode) {
      // Fail closed in release mode — never silently degrade to system trust.
      rethrow;
    }
    // Debug mode: fall back to system trust so local dev against non-pinned
    // backends still works.
  }
}

/// Logs a rejected server certificate, then REJECTS it.
///
/// [HttpClient.badCertificateCallback] fires only after chain validation has
/// already failed against [_cachedSecurityContext] — i.e. exactly on a pin
/// miss. Returning `false` preserves fail-closed behaviour (this never accepts
/// anything the pin rejected); the callback exists purely so the failure is
/// LOUD and DIAGNOSABLE.
///
/// Without it a pin miss surfaces only as a generic [DioException] →
/// `NetworkFailure`, indistinguishable from "no internet" — which is how a
/// CA-rotation outage would otherwise be misdiagnosed for days. The leaf's
/// issuer is the single most useful datum when that happens: an unexpected
/// issuer CN means the chain moved and [_pinnedRootCertAssets] is stale.
///
/// Only the leaf is available here — dart:io exposes no chain accessor — so
/// this cannot itself perform intermediate pinning (see the file header).
bool _logRejectedCertificate(X509Certificate cert, String host, int port) {
  log(
    'TLS PIN MISS — certificate for $host:$port rejected by the pinned trust '
    'anchors. subject=${cert.subject.trim()} issuer=${cert.issuer.trim()} '
    'validity=${cert.startValidity.toIso8601String()}..'
    '${cert.endValidity.toIso8601String()}. If the issuer changed, the CA '
    'chain rotated and _pinnedRootCertAssets (plus the matching @raw/ copies '
    'in network_security_config.xml) must be updated and a release shipped.',
    name: 'network.cert',
    level: 1000,
  );
  // NEVER accept. This is a diagnostic hook, not a bypass.
  return false;
}

// ---------------------------------------------------------------------------
// Authenticated Dio provider
// ---------------------------------------------------------------------------

/// Authenticated [Dio] client wired with the full interceptor chain.
///
/// Kept alive for the lifetime of the app — a single instance is reused
/// across all API calls. The interceptors hold a [Ref] reference and read
/// providers lazily, so there is no circular dependency at construction time.
///
/// The [IOHttpClientAdapter] is configured with the [SecurityContext] cached
/// by [initCertPinning] (called from main() before runApp). On platforms where
/// [IOHttpClientAdapter] is not available (web) the adapter is left as-is.
@Riverpod(keepAlive: true)
Dio dio(Ref ref) {
  // Throws in release builds if BEAUTICA_BASE_URL is not HTTPS.
  AppConfig.assertSecureUrl();

  final d = Dio(
    BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      // sendTimeout guards the request-write phase (a stalled upload / slow
      // request body). Without it a hung send never fires a DioException and a
      // dependent provider (e.g. serviceTypesProvider) would spin forever — the
      // root cause of the "Тип послуги loads forever" report. A send timeout
      // maps through ServiceRepository._mapDioException → NetworkFailure → the
      // dropdown's retryable error state.
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );

  d.interceptors.addAll([
    AuthInterceptor(ref),
    if (kDebugMode) LoggingInterceptor(),
    if (kDebugMode) ClockSkewWarningInterceptor(),
    // Order is load-bearing — see the header. RefreshInterceptor must run
    // BEFORE ErrorMapperInterceptor, whose `handler.reject` ends the error flow.
    RefreshInterceptor(ref, d),
    ErrorMapperInterceptor(),
  ]);

  // Wire cert-pinning via IOHttpClientAdapter when the cached SecurityContext
  // is available. On web (where dart:io is absent) this is a no-op.
  final sc = _cachedSecurityContext;
  if (sc != null) {
    d.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpClient(context: sc)
        // Diagnostic only — always returns false. See
        // [_logRejectedCertificate]; a pin miss must be identifiable in
        // logs rather than blending into generic network failures.
        ..badCertificateCallback = _logRejectedCertificate,
    );
  }

  return d;
}
