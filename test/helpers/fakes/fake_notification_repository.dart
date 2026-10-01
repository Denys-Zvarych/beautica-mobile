// Phase 363 — scriptable [NotificationRepository] for the feed tests.
//
// Pages are served from [pages] by index. Every mutating call records its
// arguments, and each can be held open ([markReadGate] / [markAllGate]) so a
// test can assert the OPTIMISTIC state before the response, or failed with
// [markReadError] / [markAllError].

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/notifications/data/notification_repository.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FakeNotificationRepository implements NotificationRepository {
  FakeNotificationRepository({
    this.pages = const <NotificationPage>[],
    this.unread = 0,
  });

  List<NotificationPage> pages;

  /// What `GET /unread-count` answers.
  int unread;

  /// Every `fetchPage` call, as the requested page index.
  final List<int> fetchedPages = <int>[];
  int unreadCountCalls = 0;
  final List<String> markedRead = <String>[];
  final List<DateTime?> markAllUpTo = <DateTime?>[];

  /// While non-null, `fetchPage` for any page awaits it first.
  Completer<void>? pageGate;

  /// Throws on the n-th (zero-based) `fetchPage` call that has an entry.
  final Map<int, Object> fetchErrors = <int, Object>{};
  int _fetchCalls = 0;

  /// Holds the n-th (zero-based) `fetchPage` call open until completed.
  final Map<int, Completer<void>> fetchGates = <int, Completer<void>>{};

  /// Per-id overrides of [markReadGate] / [markReadError] (checked first), so
  /// two rows can be given different outcomes in one test.
  final Map<String, Completer<void>> markReadGatesById =
      <String, Completer<void>>{};
  final Map<String, Object> markReadErrorsById = <String, Object>{};

  Completer<void>? markReadGate;
  Object? markReadError;
  Completer<void>? markAllGate;
  Object? markAllError;

  @override
  Future<NotificationPage> fetchPage({
    required int page,
    required int size,
  }) async {
    final int call = _fetchCalls++;
    fetchedPages.add(page);
    await pageGate?.future;
    await fetchGates[call]?.future;
    final Object? error = fetchErrors[call];
    if (error != null) throw error;
    if (page >= pages.length) {
      return NotificationPage(
        items: const <AppNotification>[],
        page: page,
        size: size,
        totalElements: 0,
        totalPages: page,
      );
    }
    return pages[page];
  }

  @override
  Future<int> unreadCount() async {
    unreadCountCalls++;
    return unread;
  }

  @override
  Future<void> markRead(String id) async {
    markedRead.add(id);
    await (markReadGatesById[id] ?? markReadGate)?.future;
    final Object? error = markReadErrorsById[id] ?? markReadError;
    if (error != null) throw error;
  }

  @override
  Future<int> markAllRead({DateTime? upTo}) async {
    markAllUpTo.add(upTo);
    await markAllGate?.future;
    final Object? error = markAllError;
    if (error != null) throw error;
    return 0;
  }
}

/// A one-page response.
NotificationPage onePage(List<AppNotification> items) => NotificationPage(
  items: items,
  page: 0,
  size: 20,
  totalElements: items.length,
  totalPages: 1,
);

/// Page [index] of [total] pages holding [items].
NotificationPage pageOf(int index, int total, List<AppNotification> items) =>
    NotificationPage(
      items: items,
      page: index,
      size: 20,
      totalElements: items.length * total,
      totalPages: total,
    );

/// A feed row. `createdAt` defaults to a fixed instant; override it for
/// day-group tests.
AppNotification notif(
  String id, {
  AppNotificationType type = AppNotificationType.bookingCreated,
  bool read = false,
  DateTime? createdAt,
  NotificationTarget target = const NotificationTarget.booking(bookingId: 'b1'),
  NotificationParams? params,
}) => AppNotification(
  id: id,
  type: type,
  createdAt: createdAt ?? DateTime.utc(2026, 9, 30, 11, 40),
  read: read,
  target: target,
  params:
      params ??
      NotificationParams(
        counterpartName: 'Олена Коваль',
        serviceName: 'Манікюр',
        serviceCount: 1,
        startsAt: DateTime.utc(2026, 10, 3, 11, 30),
      ),
);

/// A settled signed-in session for [role] (user id `u1`). `switchSalon` swaps
/// the user's `salonId` while keeping the same user, which is what «switching
/// the active salon» does to the session — the feed must not notice.
class FixedRoleAuth extends AuthNotifier {
  FixedRoleAuth(this.role, {this.salonId});

  final UserRole role;
  final String? salonId;

  @override
  Future<AuthSession> build() async => AuthSession.authenticated(
    user: User(id: 'u1', email: 'u@b.c', role: role, salonId: salonId),
    accessToken: 'tkn',
  );

  /// Switches the session to ANOTHER user (same role) — what a logout + login
  /// as someone else does to everything that watches the user id.
  void switchUser(String userId) {
    final AuthSession? current = state.value;
    if (current is! Authenticated) return;
    state = AsyncData<AuthSession>(
      AuthSession.authenticated(
        user: current.user.copyWith(id: userId),
        accessToken: current.accessToken,
      ),
    );
  }

  void switchSalon(String id) {
    final AuthSession? current = state.value;
    if (current is! Authenticated) return;
    state = AsyncData<AuthSession>(
      AuthSession.authenticated(
        user: current.user.copyWith(salonId: id),
        accessToken: current.accessToken,
      ),
    );
  }
}

/// A count notifier that records every mutation with the user id it was made
/// for, instead of polling anything.
class RecordingUnread extends UnreadNotifications {
  RecordingUnread(this.initial);

  final int initial;
  final List<String> calls = <String>[];
  int refreshCalls = 0;

  @override
  FutureOr<int> build() => initial;

  /// Emits [value] as-is without recording a mutation.
  void emit(AsyncValue<int> value) => state = value;

  /// A poll in flight: `isLoading`, with the SAME count still readable.
  void emitRefreshing() {
    // ignore: invalid_use_of_internal_member, what Riverpod does to a refresh
    state = const AsyncLoading<int>().copyWithPrevious(state);
  }

  @override
  void setCount(int count, {required String forUserId}) {
    calls.add('set:$count:$forUserId');
    state = AsyncData<int>(count < 0 ? 0 : count);
  }

  @override
  void decrement({required String forUserId}) {
    calls.add('dec:$forUserId');
    final int now = state.value ?? 0;
    state = AsyncData<int>(now > 0 ? now - 1 : 0);
  }

  @override
  void increment({required String forUserId, int by = 1}) {
    calls.add('inc:$by:$forUserId');
    state = AsyncData<int>((state.value ?? 0) + by);
  }

  @override
  Future<void> refresh() async {
    refreshCalls++;
  }
}
