// Phase 364 — notification tap → the right EXISTING screen for the viewer's role.
//
// [routeFor] is the pure mapping (no context, no providers); [openNotification]
// is the ONE call site's navigation half (the row tap in `NotificationsScreen`,
// which marks the row read first).
//
// NO NEW SCREENS. Every destination reuses an existing screen, and every one is
// reached with `context.push` (never `go`, never `Navigator`) so back returns to
// the feed — for EVERY role. The CLIENT's `/bookings/:id` (+ `review`) lives
// inside the client `StatefulShellRoute`, which a push from this root-level
// feed would duplicate (go_router asserts), so the CLIENT uses the feed-scoped
// alias routes `RouteNames.notificationBookingDetail` / `…Review`.
//
// ACTIVE SALON: an owner's item for salon B opens `salonStaffBookingDetail`
// directly. Nothing here — and nothing `BookingDetailScreen` reads — is an
// "active salon" selection (there is none), so the owner's place in salon A is
// untouched. The one thing the detail wants to know is which salon's board dots
// to drop after a decline / complete / reschedule; that is `target.salonId`,
// carried on `extra` exactly as the board does (see the route's builder).
// The exception is [SalonTeamTarget]: «Команда» lives INSIDE salon B's shell,
// so that one navigates into salon B on purpose.
//
// MULTI-SERVICE VISIT: a visit's notification targets its earliest booking; the
// detail of that booking renders the whole visit. There is no appointment route.

import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/routing/role_home.dart';

import '../domain/app_notification.dart';

const String _logName = 'feature.notifications.navigation';

bool _verifyInFlight = false;

/// Id of the notification whose ownership check is in flight (`null` when
/// idle or when the caller supplied none). Lets a second tap tell «same item
/// again» (dropped) from «a different item» (routed to its own destination).
String? _verifyInFlightId;

/// Bumped by every [openNotificationTarget] call that is NOT a same-id
/// duplicate dropped during a verify. A tap that finds it changed after its
/// wait knows another notification tap ran meanwhile («latest tap wins»).
int _tapGeneration = 0;

/// Resets the module-level navigation state. Tests only: the statics outlive a
/// test, so a verify left pending by one test would leak into the next.
@visibleForTesting
void resetNotificationNavigationStateForTest() {
  _verifyInFlight = false;
  _verifyInFlightId = null;
  _tapGeneration = 0;
}

/// Query marker appended to a booking-detail push that comes from the feed.
/// Route builders turn it into `BookingDetailScreen.onUnavailable`
/// ([notificationUnavailableHandler]).
const String kFromNotificationQuery = 'from';
const String kFromNotificationValue = 'notification';

/// Phase 391 — the salon whose «Відгуки» tab a `REVIEW_RECEIVED` tap opens:
/// non-null only for [AppNotificationType.reviewReceived] on a [BookingTarget]
/// with a non-empty `salonId`, for an owner or admin. Otherwise `null`.
String? _salonReviewsSalonId(
  NotificationTarget target,
  UserRole? role,
  AppNotificationType? type,
) {
  if (type != AppNotificationType.reviewReceived) return null;
  if (role != UserRole.salonOwner && role != UserRole.salonAdmin) return null;
  if (target is! BookingTarget) return null;
  final String? salonId = target.salonId;
  // A whitespace-only id is as good as missing -> booking-detail fallback.
  return (salonId == null || salonId.trim().isEmpty) ? null : salonId;
}

/// How long an owner's REVIEW_RECEIVED tap waits for `mySalonsProvider` to
/// resolve before falling back to the booking detail (phase 391, audit L1).
const Duration kSalonOwnershipVerifyTimeout = Duration(seconds: 5);

/// Phase 391 (audit L1, defence in depth): an OWNER's salon-reviews landing is
/// only entered for a salon `mySalonsProvider` confirms they own. Cold push
/// taps otherwise reach the shell while the list is unresolved (the guard
/// admits), flashing foreign-salon errors. `false` on a list without the id,
/// an error, or a timeout; never throws. Admins are checked by the route guard
/// against `User.salonId`, so they pass here.
Future<bool> _salonOwnershipVerified(
  BuildContext context,
  UserRole? role,
  String salonId,
  Duration timeout,
) async {
  if (role != UserRole.salonOwner) return true;
  try {
    final ProviderContainer container = ProviderScope.containerOf(context);
    final List<Salon> salons = await container
        .read(mySalonsProvider.future)
        .timeout(timeout);
    return salons.any((Salon s) => s.id == salonId);
  } on Object catch (e) {
    log(
      'salon ownership check failed: ${e.runtimeType}',
      name: _logName,
      level: 900,
    );
    return false;
  }
}

/// The route a tap on a notification with [target] opens for [role]; `null`
/// when there is nowhere to go (a mark-read-only item, a combination the
/// audience never receives, or no signed-in role).
///
/// [type] (phase 391, optional): a `REVIEW_RECEIVED` booking item for an
/// owner/admin opens the booking's salon on «Відгуки»
/// (`salonShell(id, openReviews: true)`) instead of the booking detail.
String? routeFor(
  NotificationTarget target,
  UserRole? role, {
  AppNotificationType? type,
}) {
  if (role == null) return null;
  final String? reviewsSalonId = _salonReviewsSalonId(target, role, type);
  if (reviewsSalonId != null) {
    return RouteNames.salonShell(reviewsSalonId, openReviews: true);
  }
  return switch (target) {
    BookingTarget(:final String bookingId) => switch (role) {
      UserRole.client => RouteNames.notificationBookingDetail(bookingId),
      UserRole.independentMaster => RouteNames.masterBookingDetail(bookingId),
      UserRole.salonOwner ||
      UserRole.salonAdmin => RouteNames.salonStaffBookingDetail(bookingId),
      UserRole.salonMaster => RouteNames.salonMasterBookingDetail(bookingId),
    },
    BookingReviewTarget(:final String bookingId) =>
      role == UserRole.client
          ? RouteNames.notificationBookingReview(bookingId)
          : null,
    SalonTeamTarget(:final String salonId) => switch (role) {
      UserRole.salonOwner ||
      UserRole.salonAdmin => RouteNames.salonShell(salonId, openTeam: true),
      _ => null,
    },
    NoTarget() => null,
  };
}

/// Whether [type] is about a booking or its review (BOOKING_* / REVIEW_*) —
/// the only types for which «Запис більше недоступний» makes sense.
bool isBookingNotificationType(AppNotificationType type) => switch (type) {
  AppNotificationType.bookingCreated ||
  AppNotificationType.bookingCancelledByClient ||
  AppNotificationType.bookingDeclined ||
  AppNotificationType.bookingNotCompleted ||
  AppNotificationType.bookingRescheduled ||
  AppNotificationType.reviewRequested ||
  AppNotificationType.bookingCancelledSalonClosed ||
  AppNotificationType.bookingCancelledMasterRemoved ||
  AppNotificationType.reviewReceived => true,
  AppNotificationType.inviteAccepted || AppNotificationType.unknown => false,
};

/// Whether [item] is a booking-type item known up front to lead nowhere: its
/// target came back empty, or its booking target's params were nulled by the
/// backend (the viewer lost access). An unknown / non-booking type with
/// [NoTarget] is NOT unavailable — it is simply mark-read-only.
bool isNotificationUnavailable(AppNotification item) =>
    isBookingNotificationType(item.type) &&
    (item.target is NoTarget ||
        (item.target is BookingTarget &&
            item.params == NotificationParams.empty));

/// Opens [item]'s destination for [role]. A booking-type item known to be gone
/// (or whose navigation throws) shows «Запис більше недоступний» and stays on
/// the feed; any other item without a route stays silent. The caller marks the
/// row read BEFORE calling this, and that stays in force whatever happens here.
///
/// The returned future completes when the pushed route is popped (or at once
/// when nothing is pushed). It is NOT an in-flight guard — it may never
/// complete if a `go()` replaces the stack; callers must not await it for
/// re-entrancy control.
Future<void> openNotification({
  required BuildContext context,
  required AppNotification item,
  required UserRole? role,
  Duration salonVerifyTimeout = kSalonOwnershipVerifyTimeout,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  if (isNotificationUnavailable(item)) {
    showWarningSnack(context, l10n.notificationsBookingUnavailable);
    return;
  }
  await openNotificationTarget(
    context: context,
    target: item.target,
    role: role,
    type: item.type,
    notificationId: item.id,
    salonVerifyTimeout: salonVerifyTimeout,
  );
}

/// The target-only half of [openNotification] (phase 069): opens [target]'s
/// destination for [role]. Shared by the feed row tap and the push tap, so both
/// reach the same screens through the same code.
///
/// When [routeFor] yields no route (a [NoTarget], a type the audience never
/// receives, no role): silent by default (a feed row), but a non-null
/// [fallbackRoute] is pushed instead (the push tap sends the user to the feed).
/// The same fallback applies when pushing the destination throws.
Future<void> openNotificationTarget({
  required BuildContext context,
  required NotificationTarget target,
  required UserRole? role,
  String? fallbackRoute,
  AppNotificationType? type,
  String? notificationId,
  Duration salonVerifyTimeout = kSalonOwnershipVerifyTimeout,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  AppNotificationType? routeType = type;
  final String? reviewsSalonId = _salonReviewsSalonId(target, role, type);
  final bool droppedDuplicate =
      reviewsSalonId != null &&
      _verifyInFlight &&
      (notificationId == null || notificationId == _verifyInFlightId);
  if (!droppedDuplicate) _tapGeneration++;
  final int generationAtTap = _tapGeneration;
  if (reviewsSalonId != null) {
    if (_verifyInFlight) {
      // The feed's `_opening` guard clears next frame; the verification can
      // outlive it. The SAME item again is dropped (it is already on its way);
      // a DIFFERENT item (its tap was already marked read) must not vanish:
      // it goes straight to its own non-salon destination.
      if (notificationId == null || notificationId == _verifyInFlightId) return;
      final String? own = fallbackRoute ?? routeFor(target, role);
      if (own != null) await _pushFallback(context, own);
      return;
    }
    _verifyInFlight = true;
    _verifyInFlightId = notificationId;
    // Where the user is BEFORE the wait: if they went elsewhere meanwhile, the
    // delayed push would land on top of the new screen.
    final String? locationBefore = _currentLocation(context);
    final bool verified;
    try {
      verified = await _salonOwnershipVerified(
        context,
        role,
        reviewsSalonId,
        salonVerifyTimeout,
      );
    } finally {
      _verifyInFlight = false;
      _verifyInFlightId = null;
    }
    // The context may be gone after the await: navigate nowhere then.
    if (!context.mounted) return;
    if (_currentLocation(context) != locationBefore) {
      // LATEST TAP WINS: if another notification tap ran during the wait, it
      // owns the user's destination and this push is skipped (a stale push
      // would land on top of it). Likewise any user-driven navigation.
      // Exception: an APP-driven settle (cold start: splash -> role home /
      // salon-shell resolver) with no other tap is not the user navigating;
      // the tap is already marked read, so dropping it would lose it. Then
      // fall through and push the intended route (or the fallback below).
      if (_tapGeneration != generationAtTap) return;
      // ...and only when the tap itself STARTED at a pre-settle startup
      // location. A tap from inside the running app (`/notifications`, a
      // booking page) that sees ANY change is the user navigating.
      if (!_isStartupLocation(locationBefore)) return;
      if (!_isAppSettledLanding(context, role)) return;
    }
    // The session may have changed during the wait (logout, role switch):
    // never push a salon route for a viewer who is no longer that role.
    final UserRole? roleNow = authUserRoleOrNull(
      ProviderScope.containerOf(context).read(authProvider),
    );
    if (roleNow != role) return;
    // Unverified -> today's booking-detail route (never an unverified salon).
    if (!verified) routeType = null;
  }
  final String? route = routeFor(target, role, type: routeType);
  if (route == null) {
    if (fallbackRoute != null) await _pushFallback(context, fallbackRoute);
    return;
  }
  await _push(
    context,
    target,
    route,
    l10n,
    fallbackRoute: fallbackRoute,
    reviewsRoute: _salonReviewsSalonId(target, role, routeType) != null,
  );
}

/// A fingerprint of where the user is: the current URI plus the depth of the
/// match stack (an imperative `push` deepens the stack without always changing
/// the URI). Equal before and after a wait -> the user did not navigate.
String? _currentLocation(BuildContext context) {
  try {
    final RouteMatchList config = GoRouter.of(
      context,
    ).routerDelegate.currentConfiguration;
    return '${config.uri}|${config.matches.length}';
  } on Object {
    return null;
  }
}

final RegExp _salonShellRoot = RegExp(r'^/salons/[^/]+/shell$');

/// Whether a [_currentLocation] fingerprint is a pre-settle startup location
/// (the router's `initialLocation` splash, or `/`): somewhere the app passes
/// through before settling, never a place the user navigated to from inside
/// the running app. `app_router.dart` starts at [RouteNames.splash] and
/// redirects from there; no other startup route exists for an authenticated tap.
bool _isStartupLocation(String? fingerprint) {
  if (fingerprint == null) return false;
  final String path = fingerprint.split('|').first.split('?').first;
  return path == RouteNames.splash || path == RouteNames.home;
}

/// Whether the current location is a place the APP (not the user) lands on at
/// cold start: splash, `/`, the viewer's role home, or ANY bare
/// `/salons/<id>/shell` (no query: `?tab=` means a deliberate deep link). The
/// shell match does not check the id is the resolver's target; that is
/// acceptable because the caller only reaches this check when the tap STARTED
/// from a startup location ([_isStartupLocation]) with no other tap since, so
/// a bare shell here can only be the `/salons/home` resolver's forward.
bool _isAppSettledLanding(BuildContext context, UserRole? role) {
  if (role == null) return false;
  try {
    final Uri uri = GoRouter.of(
      context,
    ).routerDelegate.currentConfiguration.uri;
    final String path = uri.path;
    if (path == RouteNames.splash ||
        path == RouteNames.home ||
        path == roleHomePath(role)) {
      return true;
    }
    return !uri.hasQuery && _salonShellRoot.hasMatch(path);
  } on Object {
    return false;
  }
}

Future<void> _pushFallback(BuildContext context, String fallbackRoute) async {
  try {
    await GoRouter.of(context).push<Object?>(fallbackRoute);
  } catch (e) {
    log(
      'fallback navigation failed: ${e.runtimeType}',
      name: _logName,
      level: 1000,
    );
  }
}

Future<void> _push(
  BuildContext context,
  NotificationTarget target,
  String route,
  AppLocalizations l10n, {
  String? fallbackRoute,
  bool reviewsRoute = false,
}) async {
  String location = route;
  Object? extra;
  switch (target) {
    case BookingTarget() when reviewsRoute:
      // Phase 391 — the salon shell route carries `?tab=reviews`; decorating
      // it with `?from=notification` would clobber that query.
      break;
    case SalonTeamTarget():
      // «Команда» of salon B rides on the route itself (an optional query the
      // shell consumes ONCE on its first frame) — no provider state is
      // written, so nothing can outlive the shell or leak to another user.
      break;
    case BookingTarget(:final String? salonId):
      location = Uri.parse(route)
          .replace(
            queryParameters: <String, String>{
              kFromNotificationQuery: kFromNotificationValue,
            },
          )
          .toString();
      // Only the salon board mount reads it (`extra` = the booking's salon, for
      // the board dot set). Harmless on every other mount.
      if (salonId != null && salonId.isNotEmpty) extra = salonId;
    case BookingReviewTarget() || NoTarget():
      break;
  }
  try {
    final GoRouter router = GoRouter.of(context);
    await router.push<Object?>(location, extra: extra);
  } catch (e) {
    log('navigation failed: ${e.runtimeType}', name: _logName, level: 1000);
    if (fallbackRoute != null) {
      if (context.mounted) await _pushFallback(context, fallbackRoute);
      return;
    }
    if (context.mounted) {
      showWarningSnack(context, l10n.notificationsBookingUnavailable);
    }
  }
}

/// `BookingDetailScreen.onUnavailable` for a route builder: non-null only when
/// the push came from the feed ([kFromNotificationQuery]); then it shows
/// «Запис більше недоступний» and pops back to the feed. `null` for every other
/// entry, which keeps the screen's normal error state.
VoidCallback? notificationUnavailableHandler(
  BuildContext context,
  GoRouterState state,
) {
  if (state.uri.queryParameters[kFromNotificationQuery] !=
      kFromNotificationValue) {
    return null;
  }
  return () {
    if (!context.mounted) return;
    // Snack first: the overlay host outlives the pop (show_velvet_snack.dart).
    showWarningSnack(
      context,
      AppLocalizations.of(context).notificationsBookingUnavailable,
    );
    if (context.canPop()) {
      context.pop();
    } else {
      // Nothing under this route (cold entry): go to the viewer's home instead
      // of stranding the user on the skeleton.
      final UserRole? role = authUserRoleOrNull(
        ProviderScope.containerOf(context).read(authProvider),
      );
      context.go(role == null ? RouteNames.login : roleHomePath(role));
    }
  };
}
