// Phase 413 — booking links providers (D3 / D4).
//
// [bookingLinksProvider] loads the caller's links; [bookingLinksVisibleProvider]
// is the single answer to "may the share entry point be shown?" that phase
// 414's settings row watches. Any error (CLIENT 403, network, broken payload)
// and any in-flight load read as NOT visible: settings never shows a broken or
// spinning row.
//
// Session scoping: watches ONLY the settled user id through the shared
// [authUserIdOrNull] selector — never a bare `authProvider` (a silent token
// refresh would otherwise refetch). Logout / login / account switch re-key the
// provider, so one account's links are never served to the next.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/presentation/auth_notifier.dart';
import '../data/booking_links_repository.dart';
import '../domain/booking_link.dart';

part 'booking_links_provider.g.dart';

/// The caller's booking links; [BookingLinks.hidden] when signed out.
@riverpod
Future<BookingLinks> bookingLinks(Ref ref) async {
  final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
  if (userId == null) return BookingLinks.hidden;
  return ref.watch(bookingLinksRepositoryProvider).getMine();
}

/// Whether the booking-links entry point may be shown (D4): only a settled,
/// error-free load with `shareEnabled` and at least one link.
@riverpod
bool bookingLinksVisible(Ref ref) {
  final AsyncValue<BookingLinks> links = ref.watch(bookingLinksProvider);
  if (links.hasError || links.isLoading) return false;
  return links.value?.isVisible ?? false;
}
