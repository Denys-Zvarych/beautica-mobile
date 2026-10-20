// Phase 413 — booking links providers (D3 / D4).
//
// [bookingLinksProvider] loads the caller's links; [bookingLinksVisibleProvider]
// is the single answer to "may the share entry point be shown?" that phase
// 414's settings row watches. Any error (CLIENT 403, network, broken payload)
// and a first in-flight load read as NOT visible: settings never shows a broken
// or spinning row.
//
// Session scoping: watches ONLY the settled user id through the shared
// [authUserIdOrNull] selector — never a bare `authProvider` (a silent token
// refresh would otherwise refetch). Logout / login / account switch re-key the
// provider, so one account's links are never served to the next.
//
// Phase 414 — role scoping (user decision 2026-10-20): the loaded links are
// narrowed by [scopeBookingLinksToRole] — INDEPENDENT_MASTER keeps its MASTER
// link only, SALON_OWNER / SALON_ADMIN keep SALON links only, every other
// role gets nothing — so the rule holds whatever the server returns. The role
// is read through the narrowed [authUserRoleOrNull] selector (stable across a
// token refresh, like the user id). A role that may not see links never
// reaches the backend at all.
//
// Phase 414 perf — the fetch lives in [bookingLinksForAccountProvider], keyed
// by (user id, role) and cached for [bookingLinksCacheTtl] after its last
// listener leaves, so reopening the hub does not refetch. A different account
// is a different instance (no value → hidden while it loads); logout or an
// account switch closes the previous instance's cache at once.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/domain/user_role.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../data/booking_links_repository.dart';
import '../domain/booking_link.dart';
import '../domain/booking_link_access.dart';

part 'booking_links_provider.g.dart';

/// How long a successful load stays cached after its last listener leaves.
const Duration bookingLinksCacheTtl = Duration(seconds: 60);

/// The links of account [userId] acting as [role], already role-scoped.
///
/// Success only: pinned for [bookingLinksCacheTtl] once unlistened (the timer
/// is cancelled when a listener comes back, and on dispose; it starts at once
/// when the last listener already left during the fetch). A failure is not
/// pinned, so the next open retries. A fetch that settles after the session
/// stopped being ([userId], [role]) reads as hidden and is not pinned. Closed
/// immediately when the signed-in user stops being [userId].
@riverpod
Future<BookingLinks> bookingLinksForAccount(
  Ref ref,
  String userId,
  UserRole role,
) async {
  if (!bookingLinksAllowedFor(role)) return BookingLinks.hidden;

  // The listener hooks go in BEFORE the fetch: a last listener leaving while
  // it is in flight must still be seen, or the pin below would never expire.
  bool listened = true;
  KeepAliveLink? keepAlive;
  Timer? ttl;
  void stopTtl() {
    ttl?.cancel();
    ttl = null;
  }

  void startTtl() {
    stopTtl();
    final KeepAliveLink? link = keepAlive;
    if (link != null) ttl = Timer(bookingLinksCacheTtl, link.close);
  }

  ref.onCancel(() {
    listened = false;
    startTtl();
  });
  ref.onResume(() {
    listened = true;
    stopTtl();
  });
  ref.onDispose(stopTtl);

  final BookingLinks links = await ref
      .watch(bookingLinksRepositoryProvider)
      .getMine();
  final BookingLinks scoped = scopeBookingLinksToRole(links, role);
  if (!ref.mounted) return scoped;

  // Logout / account or role switch while the fetch was in flight: the
  // response belongs to a session that is gone — neither shown nor pinned.
  if (ref.read(authProvider.select(authUserIdOrNull)) != userId ||
      ref.read(authProvider.select(authUserRoleOrNull)) != role) {
    return BookingLinks.hidden;
  }

  final KeepAliveLink link = ref.keepAlive();
  keepAlive = link;
  if (!listened) startTtl();
  ref.listen<String?>(authProvider.select(authUserIdOrNull), (_, String? next) {
    if (next != userId) {
      stopTtl();
      link.close();
    }
  });
  return scoped;
}

/// The caller's booking links; [BookingLinks.hidden] when signed out or when
/// the role may not see links (no backend call in either case).
@riverpod
Future<BookingLinks> bookingLinks(Ref ref) async {
  final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
  if (userId == null) return BookingLinks.hidden;
  final UserRole? role = ref.watch(authProvider.select(authUserRoleOrNull));
  if (role == null || !bookingLinksAllowedFor(role)) return BookingLinks.hidden;
  return ref.watch(bookingLinksForAccountProvider(userId, role).future);
}

/// Whether the booking-links entry point may be shown (D4): only an
/// error-free load with `shareEnabled` and at least one link. A refresh that
/// still holds this account's value keeps the row (no blink); a first load —
/// including the first load after an account switch, which is a fresh
/// [bookingLinksForAccountProvider] instance — reads as hidden.
@riverpod
bool bookingLinksVisible(Ref ref) {
  final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
  if (userId == null) return false;
  final UserRole? role = ref.watch(authProvider.select(authUserRoleOrNull));
  if (role == null || !bookingLinksAllowedFor(role)) return false;
  final AsyncValue<BookingLinks> links = ref.watch(
    bookingLinksForAccountProvider(userId, role),
  );
  if (links.hasError || (links.isLoading && !links.hasValue)) return false;
  return links.value?.isVisible ?? false;
}
