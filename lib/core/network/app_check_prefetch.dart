// Phone-first hardening (AUTH-D27 d, perf P2) — one prefetched LIMITED-USE
// App Check token, so an SMS send does not wait on attestation.
//
// A limited-use token is single-use by contract (the backend refuses a
// replayed `jti`), so:
//   * [AppCheckTokenPrefetcher.prefetch] starts AT MOST one fetch, when a
//     phone / code step opens; a second call while one is pending or fresh is
//     a no-op;
//   * [AppCheckTokenPrefetcher.take] hands the prefetched token to exactly
//     ONE request and forgets it — a second send always fetches fresh;
//   * a prefetched token older than [kAppCheckPrefetchMaxAge], or a prefetch
//     that produced nothing, falls back to an on-demand fetch (still capped by
//     `kAppCheckTokenTimeout` inside the fetcher).
//
// The production fetcher is `appCheckToken` (dio_provider.dart).

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../push/push_available_provider.dart';
import '../time/clock_provider.dart';
import 'app_check_interceptor.dart';
import 'dio_provider.dart';

part 'app_check_prefetch.g.dart';

/// How long a prefetched limited-use token is used. Firebase limited-use
/// tokens live ~5 minutes; 3 keeps a margin for the request's own flight.
const Duration kAppCheckPrefetchMaxAge = Duration(minutes: 3);

/// The single-use prefetch slot (see the file header).
final class AppCheckTokenPrefetcher {
  AppCheckTokenPrefetcher({
    required AppCheckTokenSource fetch,
    required bool Function() canPrefetch,
    required DateTime Function() clock,
    this.maxAge = kAppCheckPrefetchMaxAge,
  }) : _fetch = fetch,
       _canPrefetch = canPrefetch,
       _clock = clock;

  final AppCheckTokenSource _fetch;

  /// `false` while Firebase is not known to be up: a prefetch would only
  /// wait on initialisation for nothing.
  final bool Function() _canPrefetch;
  final DateTime Function() _clock;
  final Duration maxAge;

  Future<String?>? _pending;
  DateTime? _startedAt;

  /// Whether the current [_pending] has completed, and its result.
  bool _done = false;
  String? _doneToken;

  bool get _fresh {
    final DateTime? at = _startedAt;
    // instant-ok: token age is an absolute-instant difference.
    return at != null && _clock().difference(at) < maxAge;
  }

  /// Starts one background fetch unless one is already pending or fresh.
  void prefetch() {
    if (_pending != null && _fresh) return;
    if (!_canPrefetch()) return;
    _startedAt = _clock();
    _done = false;
    _doneToken = null;
    // The fetcher never throws (it maps errors to null); the guard keeps an
    // unexpected throw from surfacing as an unhandled async error.
    final Future<String?> pending = _guardedFetch();
    _pending = pending;
    unawaited(
      pending.then((String? token) {
        // Only the slot's CURRENT fetch records its outcome.
        if (identical(_pending, pending)) {
          _done = true;
          _doneToken = token;
        }
      }),
    );
  }

  Future<String?> _guardedFetch() async {
    try {
      return await _fetch();
    } on Object {
      return null;
    }
  }

  /// The token for ONE request. The slot is emptied either way (never
  /// reused):
  ///  * a fresh prefetch already DONE with a token → that token;
  ///  * a fresh prefetch already DONE without one (failed / null) → a fresh
  ///    fetch;
  ///  * a fresh prefetch still IN FLIGHT → awaited, and its result is final:
  ///    `null` goes out as `null` (the capped fetch already spent its ~5 s
  ///    budget; a second fetch would double the worst case);
  ///  * no prefetch, or a stale one → a fresh fetch.
  Future<String?> take() async {
    final Future<String?>? pending = _pending;
    final bool fresh = _fresh;
    final bool done = _done;
    final String? doneToken = _doneToken;
    _pending = null;
    _startedAt = null;
    _done = false;
    _doneToken = null;
    if (pending == null || !fresh) return _fetch();
    if (done) {
      return (doneToken != null && doneToken.isNotEmpty) ? doneToken : _fetch();
    }
    final String? token = await pending;
    return (token != null && token.isNotEmpty) ? token : null;
  }
}

/// The app's prefetch slot; the authenticated Dio's App Check interceptor
/// [AppCheckTokenPrefetcher.take]s from it, phone / code steps
/// [AppCheckTokenPrefetcher.prefetch] into it.
@Riverpod(keepAlive: true)
AppCheckTokenPrefetcher appCheckTokenPrefetcher(Ref ref) =>
    AppCheckTokenPrefetcher(
      fetch: () => appCheckToken(
        firebaseReady: () => ref.read(pushAvailableProvider.future),
      ),
      // Only once Firebase has already come up (main.dart starts it after
      // runApp). `exists` first: reading the provider would START the init.
      canPrefetch: () =>
          ref.exists(pushAvailableProvider) &&
          ref.read(pushAvailableProvider).value == true,
      clock: ref.read(clockProvider),
    );
