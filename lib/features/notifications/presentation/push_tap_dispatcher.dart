// Phase 069 — PushTapDispatcher: pending push tap -> mark read -> open.
//
// A root-level, UI-less provider (mounted once in `BeauticaApp`). It reacts to
// three things — the pending tap, the auth phase, and router location changes —
// and dispatches the tap when ALL hold:
//  * the session is RESOLVED and authenticated (anonymous: the notifier already
//    dropped the tap — a signed-out tap is never replayed after another login);
//  * the router is past splash and the auth / registration screens (a cold-start
//    tap waits for the splash redirect to land the user on their home);
//  * the root navigator is mounted.
//
// Dispatch = consume the tap ONCE, mark it read fire-and-forget (navigation
// never waits on it; a failure / 404 is ignored), then
// `openNotificationTarget` — the very code a feed-row tap uses — with the feed
// as the fallback when the target leads nowhere.
//
// The role comes from the auth state, as the feed screen does. Target screens
// enforce access themselves (a push for another account's booking lands on the
// existing «Запис більше недоступний» handling), so nothing is decided from the
// payload. Nothing from the payload is logged.

import 'dart:async';
import 'dart:developer';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../routing/app_router.dart';
import '../../../routing/route_names.dart';
import '../../auth/domain/auth_session.dart';
import '../../auth/domain/user_role.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../data/notification_repository.dart';
import '../domain/push_tap.dart';
import 'notification_navigation.dart';
import 'notifications_feed_notifier.dart';
import 'pending_push_tap_notifier.dart';
import 'unread_notifications_notifier.dart';

part 'push_tap_dispatcher.g.dart';

/// Locations a tap must wait out: the splash and the pre-session screens.
bool _holdsPushTap(String location) =>
    location == RouteNames.splash ||
    location == RouteNames.login ||
    location == RouteNames.verification ||
    location == RouteNames.register ||
    location.startsWith('${RouteNames.register}/');

@Riverpod(keepAlive: true)
void pushTapDispatcher(Ref ref) {
  final GoRouter router = ref.watch(appRouterProvider);
  bool scheduled = false;

  void attempt() {
    scheduled = false;
    if (!ref.mounted) return;
    if (ref.read(pendingPushTapProvider) == null) return;
    final AsyncValue<AuthSession> auth = ref.read(authProvider);
    final PushAuthPhase phase = pushAuthPhaseOf(auth);
    if (!phase.$1) return; // session still resolving: hold
    if (phase.$2 == null) {
      ref.read(pendingPushTapProvider.notifier).take(); // anonymous: drop
      return;
    }
    final String location = router.routerDelegate.currentConfiguration.uri.path;
    if (_holdsPushTap(location)) return;
    final BuildContext? context =
        router.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      // Navigator not mounted yet: retry after the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ref.mounted) attempt();
      });
      return;
    }
    final PushTap? tap = ref.read(pendingPushTapProvider.notifier).take();
    if (tap == null) return;
    unawaited(_markRead(ref, tap.notificationId));
    final UserRole? role = authUserRoleOrNull(auth);
    // Audit perf #2: let the just-reached home finish its first frame before the
    // destination is pushed on top of it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ref.mounted) return;
      final BuildContext? ctx =
          router.routerDelegate.navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      unawaited(
        openNotificationTarget(
          context: ctx,
          target: tap.target,
          role: role,
          fallbackRoute: RouteNames.notifications,
        ),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  // Never dispatch synchronously from inside a notification (router listeners
  // can fire mid-build): hop to a microtask once per burst.
  void schedule() {
    if (scheduled) return;
    scheduled = true;
    scheduleMicrotask(attempt);
  }

  ref.listen<PushTap?>(pendingPushTapProvider, (_, _) => schedule());
  ref.listen<PushAuthPhase>(
    authProvider.select(pushAuthPhaseOf),
    (_, _) => schedule(),
  );
  router.routerDelegate.addListener(schedule);
  ref.onDispose(() => router.routerDelegate.removeListener(schedule));
  schedule();
}

/// D3: the same `NotificationsFeed.markRead` the feed screen uses when the feed
/// is alive AND holds the row (so row + dot update consistently); otherwise the
/// repository call. Then one coalesced unread-count refresh. Fire-and-forget:
/// every failure (including a 404) is swallowed.
Future<void> _markRead(Ref ref, String id) async {
  try {
    final bool inFeed =
        ref.exists(notificationsFeedProvider) &&
        (ref
                .read(notificationsFeedProvider)
                .value
                ?.items
                .any((n) => n.id == id) ??
            false);
    if (inFeed) {
      // The feed's markRead already decrements the unread count optimistically.
      await ref.read(notificationsFeedProvider.notifier).markRead(id);
    } else {
      await ref.read(notificationRepositoryProvider).markRead(id);
      if (ref.mounted) {
        await ref.read(unreadNotificationsProvider.notifier).refresh();
      }
    }
  } on Object catch (e) {
    log(
      'push tap mark-read failed: ${e.runtimeType}',
      name: 'feature.notifications.push',
      level: 900,
    );
  }
}
