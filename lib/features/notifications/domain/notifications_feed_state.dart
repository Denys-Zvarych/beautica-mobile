// Phase 363 — state of the paged notification feed.
//
// Pure Dart. One instance per signed-in user; never keyed to a salon.

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/errors/failures.dart';
import 'app_notification.dart';

part 'notifications_feed_state.freezed.dart';

/// Page size requested from `GET /notifications`.
const int kNotificationsPageSize = 20;

@freezed
abstract class NotificationsFeedState with _$NotificationsFeedState {
  const factory NotificationsFeedState({
    /// Every loaded row, newest first (page order is preserved).
    required List<AppNotification> items,

    /// Zero-based index of the NEXT page to request.
    required int nextPage,

    /// Whether the backend has more pages after the last loaded one.
    required bool hasMore,

    /// A next-page request is in flight. Guards against a second one (the
    /// footer can be rebuilt many times while it is visible).
    @Default(false) bool loadingMore,

    /// The last next-page failure, or `null`. While non-null the feed does NOT
    /// request again by itself — the footer's retry / cooldown clears it — so a
    /// failing page can never turn a visible footer into a request loop.
    Failure? loadMoreFailure,

    /// When a rate-limited next page may be requested again (`Retry-After`
    /// added to the clock at the moment of the failure), or `null`. An ABSOLUTE
    /// instant, so a footer that scrolls away and is rebuilt keeps counting
    /// down from where it was instead of restarting the window.
    DateTime? loadMoreRetryNotBefore,

    /// The signed-in user these rows belong to (`null` while signed out). A
    /// user switch rebuilds the feed but Riverpod keeps the previous value on
    /// screen while the new one loads; the screen and every action ignore a
    /// state whose owner is not the CURRENT user, so the previous user's rows
    /// are never shown or actionable.
    String? ownerUserId,
  }) = _NotificationsFeedState;

  const NotificationsFeedState._();

  /// Unread rows among those loaded.
  int get unreadLoaded => items.where((AppNotification n) => !n.read).length;

  /// Timestamp of the newest loaded row; the `upTo` of a mark-all-read.
  DateTime? get newestCreatedAt {
    DateTime? newest;
    for (final AppNotification n in items) {
      if (newest == null || n.createdAt.isAfter(newest)) newest = n.createdAt;
    }
    return newest;
  }
}
