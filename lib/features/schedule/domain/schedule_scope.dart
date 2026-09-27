// Phase 312 — ScheduleScope: the schedule feature's viewer-scope union.
//
// Every schedule provider family (`scheduleRepositoryProvider`,
// `weeklyScheduleProvider`, `effectiveScheduleProvider`, `overridesProvider`,
// `overridesRevisionProvider`) and every schedule screen/editor now takes a
// [ScheduleScope] instead of implicitly resolving "me":
//
//   • [ScheduleScope.own]         — the CALLER's own master row. Covers both
//     the INDEPENDENT_MASTER editing their own schedule at `/schedule` and a
//     SALON_MASTER's read-only self-view at `/staff/schedule` (phase 309).
//     Resolved by `own_schedule_scope.dart`'s `ownScheduleScopeProvider` —
//     screens/editors default their additive `scope` param to `null`, which
//     resolves through that provider.
//   • [ScheduleScope.salonMaster] — a SALON_OWNER/SALON_ADMIN viewing (and,
//     per phase 312 D2, editing) a chosen master on their own salon's
//     roster. Never constructed for the viewer's OWN row — see
//     `own_schedule_scope.dart`'s doc and OQ-4
//     (`project_owner_as_master_multisalon_blocked`).
//
// Deliberately carries no `.of()` normaliser and no companion
// `forbid_raw_schedule_scope.sh` guard (unlike `BookingsDayQuery`, this
// track's analogue): `BookingsDayQuery` needs both only because it also
// carries a `DateTime` that must be canonicalised to a Kyiv calendar day.
// `ScheduleScope` carries two already-opaque UUID strings with nothing to
// normalise — see the phase 312 architect plan, D7. Do not cargo-cult the
// gate onto this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'schedule_scope.freezed.dart';

/// The viewer-scope key every schedule provider family is keyed on.
@freezed
sealed class ScheduleScope with _$ScheduleScope {
  /// The caller's own master row. [masterId] is `''` while unresolved
  /// (loading, or a role `own_schedule_scope.dart` deliberately never
  /// resolves via `masterProfileProvider` — SALON_OWNER/SALON_ADMIN/CLIENT) —
  /// every downstream repository already fails closed on an empty id
  /// ([UnauthorizedFailure] — `schedule_repository.dart`'s
  /// `_assertAuthenticated`), unchanged from before this phase.
  const factory ScheduleScope.own({required String masterId}) =
      OwnScheduleScope;

  /// A SALON_OWNER/SALON_ADMIN viewing (and editing — D2) [masterId] on
  /// their [salonId]'s roster. Never constructed for the viewer's own row.
  const factory ScheduleScope.salonMaster({
    required String salonId,
    required String masterId,
  }) = SalonMasterScheduleScope;

  const ScheduleScope._();

  /// The Master-row UUID every provider family in this feature actually
  /// keys its network calls on, regardless of which scope shape produced it.
  @override
  String get masterId => switch (this) {
    OwnScheduleScope(:final masterId) => masterId,
    SalonMasterScheduleScope(:final masterId) => masterId,
  };
}
