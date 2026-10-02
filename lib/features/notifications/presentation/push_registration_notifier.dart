// Phase 067 — FCM token registration (Android only).
//
// One keepAlive notifier, built eagerly at app start (see `BeauticaApp`).
// Locked rules:
//  * Watches ONLY the settled user id (`authUserIdOrNull`), never a bare
//    `authProvider` — a silent token refresh must not rebuild this.
//  * Nothing runs unless `pushAvailableProvider` resolves `true`.
//  * The system permission prompt is shown ONCE per device (flag survives
//    logout); a denial is the user's choice — never re-asked, no banner. The
//    token is registered regardless (harmless; a later grant just works).
//  * Registration is an idempotent upsert, re-sent on every authenticated app
//    start and on every `onTokenRefresh`. Failures are swallowed (D3).
//  * [unregisterForLogout] runs BEFORE the session is cleared: DELETE the
//    token and `deleteToken()` (concurrently) so the next account gets a fresh
//    one. The WHOLE cleanup is bounded by [kPushLogoutBudget]; an in-flight
//    register POST is CANCELLED (never awaited); a forced logout (access token
//    already dead) skips the DELETE. Any remainder past the bound is guarded by
//    a session epoch so it can never touch the NEXT user's registration.
//  * A DELETE is NEVER sent without a live session: it is skipped when the
//    session epoch moved (user switch) or auth is already wiped (Bearer-less).
//  * A persisted `pushRevokePending` flag (survives the logout wipe) is set
//    before any revoke cleanup and cleared only when `deleteToken()` succeeds.
//    Every start (signed in OR out) that finds it set retries `deleteToken()`
//    BEFORE any `getToken()`, so an offline / timed-out logout cannot leave the
//    device bound to the previous user.
//  * The FCM token is NEVER logged (nor put in analytics).

import 'dart:async';
import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/push/firebase_messaging_provider.dart';
import '../../../core/push/notification_tray_provider.dart';
import '../../../core/push/push_available_provider.dart';
import '../../../core/push/push_session_hooks.dart';
import '../../../core/storage/secure_storage_provider.dart';
import '../../auth/domain/auth_session.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../data/device_token_repository.dart';
import '../domain/push_registration_state.dart';

part 'push_registration_notifier.g.dart';

/// Upper bound for a single stand-alone DELETE / `deleteToken()` (revoke tail,
/// superseded `_start`).
const Duration kPushUnregisterTimeout = Duration(seconds: 5);

/// ONE overall bound on all push work performed inside a logout — logout never
/// waits longer than this on push, however many steps hang.
const Duration kPushLogoutBudget = Duration(seconds: 3);

@Riverpod(keepAlive: true)
class PushRegistration extends _$PushRegistration {
  StreamSubscription<String>? _refreshSub;
  String? _token;
  int _generation = 0;

  /// Bumped ONLY when a build starts for an authenticated user (login / user
  /// switch). Unlike [_generation] it does not move on the wipe-to-anonymous
  /// rebuild, so a logout tail can tell "the session it serves ended" (fine to
  /// finish) from "a NEXT user signed in" (must abort).
  int _sessionEpoch = 0;

  /// Cancel handles of the in-flight register POSTs (start or token refresh).
  /// Logout / user switch cancels them instead of awaiting them.
  final Set<CancelToken> _registerCancels = <CancelToken>{};

  /// The token a logout already DELETEd — `_start` must not DELETE it twice.
  String? _unregisteredByLogout;

  @override
  PushRegistrationState build() {
    // Hand auth the logout / local-revoke entry points (idempotent: the same
    // notifier instance survives rebuilds). AuthNotifier cannot read this
    // provider — it would close a dependency cycle — so it goes through the
    // dependency-free coordinator.
    ref.read(pushSessionHooksProvider)
      ..onLogout = unregisterForLogout
      ..onLocalRevoke = revokeLocal;
    // Identity PLUS "cold-start auth still resolving": loading -> unauthenticated
    // keeps userId null, so the loading bit is what re-runs build() (and the
    // anonymous revoke retry) once auth settles.
    final (String? userId, bool authResolving) = ref.watch(
      authProvider.select(
        (AsyncValue<AuthSession> a) =>
            (authUserIdOrNull(a), a.isLoading && !a.hasValue),
      ),
    );
    final int generation = ++_generation;
    ref.onDispose(() {
      unawaited(_refreshSub?.cancel());
      _refreshSub = null;
      // Invalidate in-flight work NOW: a rebuild is lazy, so without this a
      // continuation woken by the cancel below would still look current.
      _generation++;
      _cancelRegisters();
    });
    _token = null;
    if (userId == null) {
      // While auth is still resolving the user may turn out signed in, whose
      // `_start` reads the flag itself — skip the read (one read per cold start).
      if (!authResolving) {
        unawaited(_retryPendingRevokeWhenAnonymous(generation));
      }
      return const PushRegistrationState.idle();
    }
    _sessionEpoch++;
    unawaited(_start(generation));
    return const PushRegistrationState.idle();
  }

  bool _current(int generation) => ref.mounted && generation == _generation;

  Future<void> _start(int generation) async {
    // The session this start serves (build() bumped the epoch just before the
    // call). The user id is bound too: a rebuild is lazy, so a continuation can
    // wake after a user switch but BEFORE the new build bumps the epoch.
    final int epoch = _sessionEpoch;
    final String? sessionUser = authUserIdOrNull(ref.read(authProvider));
    try {
      final bool available = await ref.read(pushAvailableProvider.future);
      if (!_current(generation)) return;
      if (!available) {
        state = const PushRegistrationState.unavailable();
        return;
      }
      // An owed revocation (offline / timed-out logout) is settled BEFORE any
      // getToken(), so the previous user's token is gone first.
      await _retryPendingRevoke(generation);
      if (!_current(generation)) return;
      final FirebaseMessaging messaging = ref.read(firebaseMessagingProvider);
      final bool denied = await _resolvePermissionDenied(messaging);
      if (!_current(generation)) return;

      final String? token = await messaging.getToken();
      if (!_current(generation) || token == null || token.isEmpty) return;
      _token = token;
      await _register(token, generation);
      if (!_current(generation)) {
        // Superseded (logout / user switch) while the POST was in flight: the
        // binding may now exist server-side — best-effort drop it.
        if (token != _unregisteredByLogout) {
          await _unregisterQuietly(
            token,
            canSend: () => _canSendDelete(epoch, sessionUser),
          );
        }
        return;
      }
      if (token == _unregisteredByLogout) _unregisteredByLogout = null;

      await _refreshSub?.cancel();
      if (!_current(generation)) return;
      _refreshSub = messaging.onTokenRefresh.listen((String fresh) {
        if (!_current(generation) || fresh.isEmpty) return;
        _token = fresh;
        unawaited(_register(fresh, generation));
      });
      state = denied
          ? const PushRegistrationState.permissionDenied()
          : const PushRegistrationState.registered();
    } on Object catch (e) {
      _logFailure('start', e);
    }
  }

  /// Asks for the notification permission at most once per device. Returns
  /// `true` when the user has (ever) declined it.
  Future<bool> _resolvePermissionDenied(FirebaseMessaging messaging) async {
    try {
      final storage = ref.read(secureStorageProvider);
      final NotificationSettings settings;
      if (await storage.readPushPermissionAsked()) {
        settings = await messaging.getNotificationSettings();
      } else {
        // Persist BEFORE showing the dialog: a kill mid-dialog must not
        // re-ask on the next launch.
        await storage.writePushPermissionAsked();
        settings = await messaging.requestPermission();
      }
      return settings.authorizationStatus == AuthorizationStatus.denied;
    } on Object catch (e) {
      _logFailure('permission', e);
      return false;
    }
  }

  /// Cancellable register POST. Ignored (never sent) when [generation] is
  /// already stale; cancelled by logout / user switch while in flight.
  Future<void> _register(String token, int generation) async {
    if (!_current(generation)) return;
    final CancelToken cancel = CancelToken();
    _registerCancels.add(cancel);
    try {
      await ref
          .read(deviceTokenRepositoryProvider)
          .register(token, cancelToken: cancel);
    } on DeviceTokenRegisterCancelled {
      // Our own cancel (logout / user switch) — intentional, not a failure.
    } on Object catch (e) {
      _logFailure('register', e);
    } finally {
      _registerCancels.remove(cancel);
    }
  }

  void _cancelRegisters() {
    for (final CancelToken c in _registerCancels.toList()) {
      if (!c.isCancelled) c.cancel('push session ended');
    }
    _registerCancels.clear();
  }

  /// True only while [epoch] is still the live session AND the signed-in user
  /// is still [user] — a DELETE must carry that user's Bearer: never the NEXT
  /// user's, never none (auth wiped).
  bool _canSendDelete(int epoch, String? user) =>
      ref.mounted &&
      user != null &&
      epoch == _sessionEpoch &&
      authUserIdOrNull(ref.read(authProvider)) == user;

  /// Bounded, never-throwing DELETE of [token]. [canSend] is re-evaluated right
  /// before the request goes out; `false` skips it.
  Future<void> _unregisterQuietly(
    String token, {
    bool Function()? canSend,
  }) async {
    try {
      if (!ref.mounted) return;
      if (canSend != null && !canSend()) return;
      await ref
          .read(deviceTokenRepositoryProvider)
          .unregister(token)
          .timeout(kPushUnregisterTimeout);
    } on Object catch (e) {
      _logFailure('unregister', e);
    }
  }

  Future<bool>? _deleteTokenInFlight;

  /// Bounded, never-throwing `deleteToken()` so the next account gets a fresh
  /// FCM token. Concurrent callers share ONE call. Clears the persisted
  /// revoke-pending flag ONLY on success. Returns whether it succeeded.
  Future<bool> _deleteLocalToken() => _deleteTokenInFlight ??=
      _doDeleteLocalToken().whenComplete(() => _deleteTokenInFlight = null);

  // Known benign race: a late `clearPushRevokePending()` (tail past the logout
  // budget) can be overwritten by deleteAll's restore of the flag it read
  // earlier. Cost: ONE redundant, idempotent deleteToken on the next start,
  // which then clears the flag. A "fix" (skipping the restore) would risk
  // losing a genuinely owed revocation, so the race is left in place.
  Future<bool> _doDeleteLocalToken() async {
    try {
      await ref
          .read(firebaseMessagingProvider)
          .deleteToken()
          .timeout(kPushUnregisterTimeout);
    } on Object catch (e) {
      _logFailure('deleteToken', e);
      return false;
    }
    try {
      await ref.read(secureStorageProvider).clearPushRevokePending();
    } on Object catch (e) {
      _logFailure('clearRevokePending', e);
    }
    return true;
  }

  /// Persists "a revocation is owed" BEFORE cleanup starts. Never throws.
  Future<void> _markRevokePending() async {
    try {
      await ref.read(secureStorageProvider).writePushRevokePending();
    } on Object catch (e) {
      _logFailure('markRevokePending', e);
    }
  }

  /// If a revocation is owed, runs `deleteToken()` (bounded) now. Never throws.
  /// Caller has already established that push is available.
  Future<void> _retryPendingRevoke(int generation) async {
    try {
      if (!await ref.read(secureStorageProvider).readPushRevokePending()) {
        return;
      }
      if (!_current(generation)) return;
      await _deleteLocalToken();
    } on Object catch (e) {
      _logFailure('retryRevoke', e);
    }
  }

  /// Signed-out start: settle an owed revocation too (the previous user's
  /// logout may have failed offline). Push availability is only awaited when
  /// the flag is actually set, so a normal signed-out launch costs one read.
  Future<void> _retryPendingRevokeWhenAnonymous(int generation) async {
    try {
      if (!await ref.read(secureStorageProvider).readPushRevokePending()) {
        return;
      }
      if (!_current(generation)) return;
      final bool available = await ref.read(pushAvailableProvider.future);
      if (!_current(generation) || !available) return;
      await _retryPendingRevoke(generation);
    } on Object catch (e) {
      _logFailure('retryRevoke', e);
    }
  }

  /// Local-only revocation for auth wipes that are NOT a normal logout (expired
  /// / rejected refresh token at cold start): no access token exists, so no
  /// backend call — just `deleteToken()` (when push is available) so the device
  /// stops receiving the previous user's pushes. Never throws.
  ///
  /// Invariant: an owed revoke either completes or leaves the persisted flag
  /// set; it is skipped ONLY when a NEXT user is authenticated (epoch moved or
  /// a user is signed in). The build [_generation] is deliberately NOT checked:
  /// the loading -> unauthenticated settle rebuilds push (new generation) while
  /// this call is still awaiting availability, and aborting there would drop the
  /// revoke without a flag.
  Future<void> revokeLocal() async {
    final int epoch = _sessionEpoch;
    bool stale() =>
        !ref.mounted ||
        epoch != _sessionEpoch ||
        authUserIdOrNull(ref.read(authProvider)) != null;
    try {
      if (stale()) return;
      // Audit L1: clear the previous user's tray entries (never throws).
      unawaited(_clearTray());
      // FIRST await: persist the owed revocation before anything that can stall
      // (availability resolves slowly at cold start). Harmless when push turns
      // out to be unavailable: every retry path gates on availability itself.
      await _markRevokePending();
      if (stale()) return;
      final bool available = await ref.read(pushAvailableProvider.future);
      if (!available || stale()) return;
      final StreamSubscription<String>? sub = _refreshSub;
      _refreshSub = null;
      _token = null;
      try {
        await sub?.cancel();
      } on Object catch (e) {
        _logFailure('cancelRefresh', e);
      }
      if (stale()) return;
      // The anonymous rebuild's retry may already have settled the flag while
      // we waited — deleteToken exactly once.
      if (await ref.read(secureStorageProvider).readPushRevokePending()) {
        if (stale()) return;
        await _deleteLocalToken();
      }
      if (!stale()) state = const PushRegistrationState.idle();
    } on Object catch (e) {
      _logFailure('revokeLocal', e);
    }
  }

  /// Deregisters this device for the CURRENT user. Call BEFORE the session is
  /// cleared (the DELETE needs the access token). Never throws, and never
  /// takes longer than [kPushLogoutBudget].
  ///
  /// [forced]: the access token is already dead (refresh failed / account
  /// deleted) — the DELETE could only 401, so only the local `deleteToken()`
  /// runs.
  Future<void> unregisterForLogout({bool forced = false}) async {
    final String? token = _token;
    final StreamSubscription<String>? sub = _refreshSub;
    _refreshSub = null;
    _token = null;
    _generation++; // cancels a running _start / refresh listener
    final int epoch = _sessionEpoch;
    final String? sessionUser = authUserIdOrNull(ref.read(authProvider));
    // Audit L1: the previous user's tray entries must not outlive the session.
    // Fire-and-forget (the clearer never throws), so it adds nothing to the budget.
    unawaited(_clearTray());
    _cancelRegisters(); // never await an in-flight register POST
    if (token != null) _unregisteredByLogout = token;
    if (ref.mounted) state = const PushRegistrationState.idle();
    final Future<void> cleanup = _logoutCleanup(
      token,
      sub,
      forced,
      epoch,
      sessionUser,
    );
    try {
      await cleanup.timeout(kPushLogoutBudget);
    } on TimeoutException {
      // Remainder keeps running, epoch-guarded; logout moves on.
      _logFailure('logoutBudget', TimeoutException('push cleanup'));
    } on Object catch (e) {
      _logFailure('logoutCleanup', e);
    }
  }

  /// The logout-time push work. Never throws. Everything after an await
  /// re-checks [epoch] so a tail that outlives the budget cannot touch the next
  /// user's registration.
  Future<void> _logoutCleanup(
    String? knownToken,
    StreamSubscription<String>? sub,
    bool forced,
    int epoch,
    String? sessionUser,
  ) async {
    bool stale() => !ref.mounted || epoch != _sessionEpoch;
    // The DELETE needs the still-valid session: it is skipped once auth is
    // wiped (never a Bearer-less DELETE). `deleteToken()` is NOT gated on this
    // — revoking after the wipe is exactly the goal.
    bool canSend() => _canSendDelete(epoch, sessionUser);
    try {
      // FIRST await: persist the owed revocation BEFORE anything that can stall
      // (sub.cancel). If the budget expires, logout proceeds to deleteAll, whose
      // preserve-read must already see the flag — a write landing between that
      // read and the wipe would be lost. With no known token the flag is set
      // later, only once push is known to be available.
      if (knownToken != null) await _markRevokePending();
      try {
        await sub?.cancel();
      } on Object catch (e) {
        _logFailure('cancelRefresh', e);
      }
      if (knownToken != null) {
        // A stalled cancel can outlive the budget and the next login: the flag
        // is already persisted, so the next user's _start settles the revoke.
        if (stale()) return;
        // DELETE (body carries the token string) and the local deleteToken()
        // run concurrently: latency is the max of the two, not the sum.
        await Future.wait<void>(<Future<void>>[
          if (!forced) _unregisterQuietly(knownToken, canSend: canSend),
          _deleteLocalToken(),
        ]);
        return;
      }
      // Logout landed during _start (Firebase init / permission dialog / token
      // fetch): no token is known yet, but the device may already hold a
      // previous binding. Resolve it, then revoke.
      final bool available = await ref.read(pushAvailableProvider.future);
      if (!available || stale()) return;
      await _markRevokePending();
      if (stale()) return;
      final FirebaseMessaging messaging = ref.read(firebaseMessagingProvider);
      final String? token = await messaging.getToken();
      if (stale()) return;
      if (!forced && token != null && token.isNotEmpty) {
        await _unregisterQuietly(token, canSend: canSend);
        if (stale()) return;
      }
      await _deleteLocalToken();
    } on Object catch (e) {
      _logFailure('logoutCleanup', e);
    }
  }

  /// Best-effort tray clear (audit L1); never throws, whatever the seam does.
  Future<void> _clearTray() async {
    try {
      await ref.read(notificationTrayClearerProvider)();
    } on Object catch (e) {
      _logFailure('clearTray', e);
    }
  }

  // Type only — the exception text could embed the token / request body.
  void _logFailure(String op, Object e) => log(
    'push $op failed: ${e.runtimeType}',
    name: 'feature.notifications.push',
    level: 900,
  );
}
