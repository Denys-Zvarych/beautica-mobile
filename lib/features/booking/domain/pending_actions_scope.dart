// Phase 393 (24.7a) — [PendingActionsScope]: which archive a pending-actions
// count belongs to. Each variant mirrors the list endpoint the matching
// archive already calls.
//
// Deliberately NO variant for SALON_MASTER: backend 357 answers 403 for that
// role and the badge never builds a scope for it.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'pending_actions_scope.freezed.dart';

@freezed
sealed class PendingActionsScope with _$PendingActionsScope {
  /// `GET /bookings/me/pending-actions/count?asMaster=` — independent master
  /// (`asMaster: false`) and owner master mode (`asMaster: true`).
  const factory PendingActionsScope.me({required bool asMaster}) =
      PendingActionsScopeMe;

  /// `GET /bookings/salon/{salonId}/pending-actions/count` — salon
  /// owner/admin board.
  const factory PendingActionsScope.salon(String salonId) =
      PendingActionsScopeSalon;
}
