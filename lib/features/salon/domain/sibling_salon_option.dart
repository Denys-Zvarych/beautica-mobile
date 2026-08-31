// Phase 21.6 — one selectable row of the rotate-admin destination picker.
//
// The domain shape of `GET /salons/{salonId}/sibling-salons` (backend Phase
// 21.3b): the ACTIVE salons sharing this salon's owner, minus the salon in
// the path. Reachable by a `SALON_OWNER` and by an assigned `SALON_ADMIN`,
// which is precisely why it is NOT `SalonResponse`: an admin sits inside the
// trust boundary of exactly ONE salon, so the backend deliberately narrowed
// the payload to id + name + short address rather than handing them the
// owner's whole portfolio (description / phone / instagram / avatar / legacy
// address / isPrimary / ownerId). See `SiblingSalonOption.java`'s own
// Javadoc.
//
// This model mirrors that narrowness ON PURPOSE. It is deliberately NOT
// [Salon]: widening it back out here would re-open, in the mobile type
// system, exactly the disclosure the backend closed, and would let a caller
// read fields this endpoint never sends as though they were merely empty.
// [MoveAdminSalonScreen] converts an option into a display-only [Salon] at
// the point it renders one — an explicit, local, one-line adaptation rather
// than a repository that lies about what it fetched.
//
// [street] / [buildingNo] are the Phase 10.6 structured address and are the
// ONLY address surface here — they are what tells two same-named branches
// apart. Both are nullable: a salon persisted before Phase 10.6 may carry
// neither, so a renderer must fall back to [name] alone. There is no
// locality (city/oblast) on this payload at all.
//
// Pure Dart: no Flutter imports in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'sibling_salon_option.freezed.dart';

/// A salon offered as a rotate-admin destination.
@freezed
abstract class SiblingSalonOption with _$SiblingSalonOption {
  const factory SiblingSalonOption({
    /// The destination salon's UUID — sent verbatim as
    /// `RotateAdminRequest.destinationSalonId` to
    /// `PATCH /salons/{salonId}/admins/{userId}/salon`.
    required String id,

    /// Salon display name.
    required String name,

    /// Street of the structured address, or `null` for a pre-Phase-10.6 row.
    String? street,

    /// Building number of the structured address, or `null` for a
    /// pre-Phase-10.6 row.
    String? buildingNo,
  }) = _SiblingSalonOption;
}
