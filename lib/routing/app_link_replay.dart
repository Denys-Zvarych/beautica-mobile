import 'dart:async';
import 'dart:developer';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/time/clock_provider.dart';
import '../features/auth/domain/auth_session.dart';
import '../features/auth/presentation/auth_notifier.dart';
import 'auth_redirect.dart';
import 'deferred_navigation.dart';
import 'route_names.dart';

part 'app_link_replay.g.dart';

// Cold-start App Link replay (2026-11-14, docs/specs/website.md WEB-12/13).
//
// An emailed `https://beautica.app/bookings/{id}/review` tap almost always
// COLD-starts the app. go_router receives the link as its initial location,
// but the session is still restoring, so [authRedirect] parks it on /splash
// (or /login when signed out) and the target is lost. This file keeps it:
//
//   1. CAPTURE — [holdAppLinkIfDeferred] wraps the router's top-level redirect.
//      When the redirect defers an allow-listed App Link path to /splash or
//      /login, the validated path is held in [PendingAppLinkHolder].
//   2. REPLAY — [attachAppLinkReplay] watches the router + session exactly like
//      `push_tap_dispatcher.dart`: once a signed-in session has settled and
//      the router has left the [holdsDeferredNavigation] screens, the held
//      path is TAKEN (consumed once) and opened, provided [authRedirect] would
//      admit the role there. A role the route does not admit (e.g. a master
//      on the CLIENT-only `/bookings`) stays on its home and the link is
//      dropped.
//
// Additive only: no redirect decision changes. Only `/bookings/{id}` and
// `/bookings/{id}/review` are ever held (the paths the manifest claims), never
// an arbitrary URL; the guest web-only `/r/`, `/c/`, `/book/` are not claimed
// and not held.

/// Hosts an App Link may arrive on (AndroidManifest `${appLinkHost}` per
/// flavor: prod `beautica.app`, staging `staging.beautica.app`).
const Set<String> kAppLinkHosts = <String>{
  'beautica.app',
  'staging.beautica.app',
};

final RegExp _idSegment = RegExp(r'^[A-Za-z0-9-]{1,64}$');

/// Whether [id] is a safe id path segment (UUID-shaped: `[A-Za-z0-9-]`, 1-64
/// chars).
///
/// go_router DECODES path params (`..%2F..%2Fx` -> `../../x`) and the generated
/// client interpolates ids into the API path unencoded, so every route that
/// takes an id param (`:bookingId`, `:salonId`, `:masterId`, `:memberId`,
/// `:serviceId`, `:id`) must gate on this before building its screen.
bool isValidIdSegment(String id) => _idSegment.hasMatch(id);

/// Booking-named alias of [isValidIdSegment] (same rule).
bool isValidBookingIdSegment(String id) => isValidIdSegment(id);

/// The in-app path to replay for an App Link [uri], or `null` when it is not an
/// allow-listed booking link.
///
/// Accepts a path-only route or an `https` URL on [kAppLinkHosts]; the host,
/// query and fragment are stripped. Only `/bookings/{id}` and
/// `/bookings/{id}/review` (a UUID-shaped id) are recognised.
String? appLinkReplayPath(Uri uri) {
  if (uri.hasScheme || uri.hasAuthority) {
    if (uri.scheme != 'https' || !kAppLinkHosts.contains(uri.host)) {
      return null;
    }
    if (uri.hasPort || uri.userInfo.isNotEmpty) return null;
  }
  final List<String> segments = uri.pathSegments;
  final bool isBookings =
      segments.length >= 2 &&
      '/${segments[0]}' == RouteNames.clientBookings &&
      isValidBookingIdSegment(segments[1]);
  if (!isBookings) return null;
  final String id = segments[1];
  return switch (segments.length) {
    2 => RouteNames.bookingDetail(id),
    3 when segments[2] == 'review' => RouteNames.bookingReview(id),
    _ => null,
  };
}

/// How long a held link stays replayable.
const Duration kAppLinkHoldTtl = Duration(minutes: 10);

/// In-memory single-slot holder for a deferred App Link path. Lives as long as
/// the app process (the router's lifetime); consumed once by [take], expired
/// after [kAppLinkHoldTtl], and cleared on sign-out ([clear]) so a link only
/// replays for the first sign-in that follows the tap.
final class PendingAppLinkHolder {
  PendingAppLinkHolder({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now; // instant-ok: absolute-instant TTL

  final DateTime Function() _clock;
  String? _path;
  DateTime? _heldAt;

  /// The held path, without consuming it (`null` once expired).
  String? get peek {
    _expireIfStale();
    return _path;
  }

  void _expireIfStale() {
    final DateTime? at = _heldAt;
    if (_path != null &&
        at != null &&
        _clock().difference(at) >= kAppLinkHoldTtl) {
      clear();
    }
  }

  /// Drops any held link.
  void clear() {
    _path = null;
    _heldAt = null;
  }

  /// Holds [uri]'s replay path if it is an allow-listed App Link. A later link
  /// replaces an earlier one (the user's latest tap wins). Returns whether it
  /// was held.
  bool hold(Uri uri) {
    final String? path = appLinkReplayPath(uri);
    if (path == null) return false;
    _path = path;
    _heldAt = _clock();
    return true;
  }

  /// Returns the held path and clears it (consume-on-read).
  String? take() {
    final String? path = peek;
    clear();
    return path;
  }
}

@Riverpod(keepAlive: true)
PendingAppLinkHolder pendingAppLink(Ref ref) =>
    PendingAppLinkHolder(clock: ref.watch(clockProvider));

/// Router redirect wrapper: returns [target] unchanged, holding [uri] first
/// when the redirect DEFERS it to /splash or /login.
String? holdAppLinkIfDeferred(
  PendingAppLinkHolder holder,
  Uri uri,
  String? target,
) {
  if (target == RouteNames.splash || target == RouteNames.login) {
    holder.hold(uri);
  }
  return target;
}

/// Wires the replay half onto [router] (called once from `appRouter`).
void attachAppLinkReplay(Ref ref, GoRouter router) {
  bool scheduled = false;

  void attempt() {
    scheduled = false;
    if (!ref.mounted) return;
    final PendingAppLinkHolder holder = ref.read(pendingAppLinkProvider);
    if (holder.peek == null) return;
    final AsyncValue<AuthSession> auth = ref.read(authProvider);
    // Strict: only a settled sign-in replays (an anonymous visitor keeps the
    // link until they sign in; a restoring session waits).
    if (auth is! AsyncData<AuthSession> || auth.value is! Authenticated) {
      return;
    }
    final String location = router.routerDelegate.currentConfiguration.uri.path;
    if (holdsDeferredNavigation(location)) return;
    final String? path = holder.take();
    if (path == null) return;
    if (!authRedirectAdmits(auth, path)) {
      log(
        'app link dropped: route not open to this role',
        name: 'routing.app_link',
        level: 800,
      );
      return;
    }
    // Post-frame, like the push-tap open: lets a same-tick post-login
    // `context.go(home)` land first, then opens the link over it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.mounted) router.go(path);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void schedule() {
    if (scheduled) return;
    scheduled = true;
    scheduleMicrotask(attempt);
  }

  ref.listen<AsyncValue<AuthSession>>(authProvider, (prev, next) {
    final bool signedOut =
        prev is AsyncData<AuthSession> &&
        prev.value is Authenticated &&
        next is AsyncData<AuthSession> &&
        next.value is Unauthenticated;
    if (signedOut) {
      // Sign-out / session loss: a link must not outlive the session it was
      // tapped in. The router's redirect to /login may re-hold the page the
      // user was on right after this, so clear again post-frame.
      final PendingAppLinkHolder holder = ref.read(pendingAppLinkProvider);
      holder.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ref.mounted) holder.clear();
      });
      WidgetsBinding.instance.ensureVisualUpdate();
      return;
    }
    schedule();
  });
  router.routerDelegate.addListener(schedule);
  ref.onDispose(() => router.routerDelegate.removeListener(schedule));
}
