// Phase 267 — SalonServiceBooking: the unit the salon multi-service booking
// flow revolves around (D1). ONE selected catalogue service, its assigned
// master, its own date+time, and its own idempotency key — never a shared
// visit header. This is what delivers the locked product rule: 1 service =
// 1 booking = its own cancel/reschedule/complete/feedback (see
// `project_completion_is_per_service.md`).
//
// [SalonServiceBooking.toCreateBookingRequest] is what THIS entity maps to,
// 1:1, at submit time (Phase 277): a `CreateBookingRequest{masterId,
// serviceId, startAt, idempotencyKey, clientComment}` — and therefore a
// `bookings` row with `appointment_id = NULL`, which the backend explicitly
// supports (`Booking.java:337-345`, "a legacy single-service booking has no
// appointment").
//
// D2 — TWO ID SPACES, NEVER CONFLATED
// -------------------------------------
// [serviceDefId] is the salon-catalogue `ServiceDefinition` id (selected in
// step 1; keys `salonMasterServiceCoverageProvider`'s coverage map —
// `salon_master_coverage_notifier.dart:174`). [masterServiceId] is the
// per-master `MasterServiceAssignment` id — what
// `GET /masters/{id}/slots?serviceId=...` and `POST /bookings` actually
// require. `POST /bookings` resolves via
// `findByMasterIdAndIdWithGraph(masterId, masterServiceId)` and throws a
// **404 "Master service not found"** on a mismatch (`BookingService.java:
// 2024-2027`) — an error the client can do nothing about. Both fields are
// carried explicitly, populated together at assignment time (see
// `SalonBookingDraft.assignMaster`, which is the only place either is
// written), and [toCreateBookingRequest] sends [masterServiceId], never
// [serviceDefId] — see `salon_service_booking_test.dart`'s
// `should_carryTheAssignmentIdNotTheDefinitionId_when_buildingTheCreateRequest`.
//
// [master]/[masterId]/[masterServiceId]/[startAt]/[durationMinutes] are all
// null until assigned/scheduled — this phase never populates them (no screen
// is wired to this entity yet; see Phases 268-269 and 273-275).
// [idempotencyKey] is likewise always null here — Phase 276 owns minting and
// the regeneration rules; do NOT mint one in this phase.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../master/domain/master.dart';
import '../../salon/domain/salon_master_summary.dart';
import '../../salon/domain/salon_service_catalog.dart';
import '../../services/domain/master_service.dart';
import 'create_booking_request.dart';

part 'salon_service_booking.freezed.dart';

/// One selected salon-catalogue service's full draft state for the salon
/// multi-service booking flow — see the file header for D1/D2.
@freezed
abstract class SalonServiceBooking with _$SalonServiceBooking {
  const factory SalonServiceBooking({
    /// What the client picked in step 1 — display-only (name/price/duration
    /// label), never the id source for the wire (see [serviceDefId]).
    required SalonCatalogService service,

    /// The salon-catalogue `ServiceDefinition` id — the coverage map's INNER
    /// key. NEVER sent as `CreateBookingRequest.serviceId` — see the file
    /// header's D2 note and [masterServiceId].
    required String serviceDefId,

    /// Assigned in step 2. Always moves together with [masterServiceId] —
    /// see [SalonBookingDraft.assignMaster] (the only writer).
    String? masterId,

    /// The per-master `MasterServiceAssignment` id — what the wire actually
    /// needs. Always moves together with [masterId]. See the file header's
    /// D2 note.
    String? masterServiceId,

    /// Identity for rendering (name/title/rating) — null until assigned.
    SalonMasterSummary? master,

    /// Picked in the schedule hub (Phase 275). Null until scheduled.
    DateTime? startAt,

    /// From the assignment (the `MasterServiceAssignment`'s own duration) —
    /// fixes the appointment window length. Null until assigned.
    int? durationMinutes,

    /// Minted once, Phase 276. ALWAYS null in and before this phase — do not
    /// mint here.
    String? idempotencyKey,
  }) = _SalonServiceBooking;

  const SalonServiceBooking._();

  /// [startAt] + [durationMinutes], or `null` while either is unset. Avoids
  /// `!` (project null-safety convention) via local-variable narrowing
  /// instead of the doc's own literal `startAt!.add(...)` spelling — same
  /// computation, no bang.
  DateTime? get endAt {
    final DateTime? start = startAt;
    final int? duration = durationMinutes;
    if (start == null || duration == null) return null;
    return start.add(Duration(minutes: duration));
  }

  /// Builds this entry's `POST /bookings` payload. Requires the entry to
  /// already be fully assigned ([masterId] + [masterServiceId]), scheduled
  /// ([startAt]), and keyed ([idempotencyKey]) — throws a [StateError]
  /// rather than silently sending a partial/wrong request. Callers (Phase
  /// 277) validate/assemble before calling this.
  ///
  /// D2: sends [masterServiceId] as `serviceId` — NEVER [serviceDefId]. See
  /// the file header.
  CreateBookingRequest toCreateBookingRequest({String? clientComment}) {
    final String? assignedMasterId = masterId;
    final String? assignedMasterServiceId = masterServiceId;
    final DateTime? scheduledAt = startAt;
    final String? key = idempotencyKey;
    if (assignedMasterId == null ||
        assignedMasterServiceId == null ||
        scheduledAt == null ||
        key == null) {
      throw StateError(
        'SalonServiceBooking.toCreateBookingRequest called before this '
        'entry was fully assigned (masterId+masterServiceId), scheduled '
        '(startAt), and keyed (idempotencyKey). serviceDefId=$serviceDefId',
      );
    }
    return CreateBookingRequest(
      masterId: assignedMasterId,
      // D2 — the WIRE needs the per-master ASSIGNMENT id, never the
      // salon-catalogue serviceDefId. Sending serviceDefId 404s server-side
      // ("Master service not found") — see BookingService.java:2024-2027.
      serviceId: assignedMasterServiceId,
      startAt: scheduledAt,
      idempotencyKey: key,
      clientComment: clientComment,
    );
  }

  /// Phase 275 (D2) — this entry's [MasterService] view, for feeding
  /// `BookingSlotPickerArgs.services` when the schedule hub opens the
  /// picker for THIS entry (`salon_schedule_hub_screen.dart`). Requires the
  /// entry to already be ASSIGNED ([masterServiceId] non-null) — mirrors
  /// [toCreateBookingRequest]'s own guard, and for the same reason: the
  /// wire (here, the slot-availability fetch) needs the per-master
  /// ASSIGNMENT id, never [serviceDefId] — see the file header's D2 note.
  /// By the time the hub renders a row every entry is already assigned
  /// (assignment happens in step 2, before the hub is ever reached — see
  /// phase-275 D1), so this should never actually throw on a live screen.
  MasterService get asMasterService {
    final String? assignedMasterServiceId = masterServiceId;
    if (assignedMasterServiceId == null) {
      throw StateError(
        'SalonServiceBooking.asMasterService called before this entry was '
        'assigned a master (masterServiceId). serviceDefId=$serviceDefId',
      );
    }
    return MasterService(
      id: assignedMasterServiceId,
      serviceDefId: serviceDefId,
      name: service.name,
      category: service.category,
      durationMinutes: durationMinutes ?? service.durationMinutes ?? 0,
      priceType: service.priceType ?? ServicePriceType.fixed,
      priceMin: service.priceMin ?? 0,
      priceMax: service.priceMax,
      priceDisplay: service.priceDisplay,
    );
  }

  /// Phase 275 (D2) — this entry's assigned master as a [Master] domain
  /// entity, for feeding `BookingSlotPickerArgs.master` — typed to the
  /// independent-flow's [Master], not the salon catalogue's lighter
  /// [SalonMasterSummary] this entry actually carries. Requires [master] to
  /// be non-null (same precondition as [asMasterService]). Only the fields
  /// [SalonMasterSummary] actually carries are populated; every other
  /// [Master] field (city, working hours, …) is left at its default — the
  /// slot-picker screens never read them, only identity + rating for
  /// [MasterStrip].
  Master get asMaster {
    final SalonMasterSummary? assignedMaster = master;
    if (assignedMaster == null) {
      throw StateError(
        'SalonServiceBooking.asMaster called before this entry was '
        'assigned a master. serviceDefId=$serviceDefId',
      );
    }
    return Master(
      id: assignedMaster.masterId,
      firstName: assignedMaster.firstName,
      lastName: assignedMaster.lastName,
      avatarUrl: assignedMaster.avatarUrl,
      avgRating: assignedMaster.avgRating,
      reviewCount: assignedMaster.reviewCount,
      type: assignedMaster.type,
      professionalTitle: assignedMaster.professionalTitle,
    );
  }
}
