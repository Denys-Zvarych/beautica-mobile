// Client-profile audit (2026-11-22) — the ONE fan-out for "a write changed
// what the provider's client views show": the «Клієнти» list rows («Наст.»,
// «Ост.», «Заблоковано»), the client card (tag, rating) and its visit
// timeline («Наступний візит», status badges).
//
// Called by every booking mutation helper in
// `booking/application/booking_calendar_invalidation.dart` (complete / decline
// / external decline / bulk cancel / create) and by the block write
// (`moderation/application/block_notifier.dart`). Whole families: none of
// those writes knows which list scope / card / chip is cached. The list and
// the visits are 30 s cache-for families — an unlistened cached member is
// dropped (re-read on its next mount), a mounted or covered one refetches
// when it is next visible. Same DROPPED-not-REFILLED contract as the booking
// helpers.
//
// Takes the caller's `invalidate` tear-off (`ref.invalidate` of a `Ref` or a
// `WidgetRef`), so one function serves both caller kinds.

import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:beautica_mobile/features/clients/application/client_card_controller.dart';
import 'package:beautica_mobile/features/clients/application/client_list_controller.dart';
import 'package:beautica_mobile/features/clients/application/client_visits_controller.dart';

/// Drops every cached client list, card and visit timeline.
void invalidateClientViews(void Function(ProviderOrFamily) invalidate) {
  invalidate(clientListControllerProvider);
  invalidate(clientCardProvider);
  invalidate(clientVisitsControllerProvider);
}
