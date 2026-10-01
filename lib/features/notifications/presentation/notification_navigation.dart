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
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/routing/role_home.dart';

import '../domain/app_notification.dart';

const String _logName = 'feature.notifications.navigation';

/// Query marker appended to a booking-detail push that comes from the feed.
/// Route builders turn it into `BookingDetailScreen.onUnavailable`
/// ([notificationUnavailableHandler]).
const String kFromNotificationQuery = 'from';
const String kFromNotificationValue = 'notification';

/// The route a tap on a notification with [target] opens for [role]; `null`
/// when there is nowhere to go (a mark-read-only item, a combination the
/// audience never receives, or no signed-in role).
String? routeFor(NotificationTarget target, UserRole? role) {
  if (role == null) return null;
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
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final String? route = routeFor(target, role);
  if (route == null) {
    if (fallbackRoute != null) await _pushFallback(context, fallbackRoute);
    return;
  }
  await _push(context, target, route, l10n, fallbackRoute: fallbackRoute);
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
}) async {
  String location = route;
  Object? extra;
  switch (target) {
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
