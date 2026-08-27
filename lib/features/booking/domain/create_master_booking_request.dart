// Phase 246 — Master «Новий запис» data layer: [CreateMasterBookingRequest].
//
// The PROVIDER-side write payload for `POST /api/v1/masters/{masterId}/
// bookings` (backend Phase 22.4, `docs/backend-phases/
// phase-171-22.4-staff-booking-endpoint-and-authz.md`, amendment A4).
//
// Distinct from `create_booking_request.dart`'s [CreateBookingRequest] — that
// one is the authenticated CLIENT's own self-booking write (`POST
// /bookings`). This one is issued by the PROVIDER (an independent master
// booking themselves, or a salon owner/admin booking one of their masters —
// see `AuthorizationService.canBookForMaster`) on behalf of a WALK-IN guest
// who has no app account.
//
// ## Walk-in only (mirrors backend amendment A4)
//
// There is deliberately **no** `existingClientId` field. Backend Phase 22.3
// (linking a walk-in to an existing app client) is still deferred — see
// `docs/backend-phases/phase-170-22.3-staff-booking-client-resolution.md`.
// When it ships, it arrives as a new OPTIONAL field on both this model and the
// generated wire `CreateStaffBookingRequest` — additive, non-breaking.
//
// ## No `clientComment` field — deviation from the phase-246 doc's table
//
// The phase doc's field table lists an optional `clientComment`, mirroring
// amendment A4's PROSE (`String clientComment?`). The OpenAPI snapshot
// actually regenerated from a real backend boot for this phase
// (`tool/openapi/api-spec.json`, backend `dev` merge `33da87b`) shows the
// ACTUAL shipped `CreateStaffBookingRequest` schema carries exactly THREE
// properties: `masterServiceId`, `startsAt`, `guest` — no `clientComment`
// anywhere (verified directly against the schema's `properties`/`required`
// lists). The wire contract is ground truth over a doc's prose table; a field
// this repository cannot transmit has no business existing on the domain
// model it feeds. Add it back the moment a backend phase actually ships it on
// the wire — see `HttpBookingRepository.createMasterBooking`'s doc.
//
// ## Phase 252 — `masterServiceId` (scalar) → `masterServiceIds` (ordered list)
//
// The backend contract for `POST /api/v1/masters/{masterId}/bookings` became
// visit-shaped (backend track 22.8–22.16, `263afe5`): the request now carries
// an ORDERED, non-empty `masterServiceIds` array (`maxItems: 10`, mirroring
// `MAX_SERVICES_PER_VISIT`), and the 201 response is the full
// `AppointmentDetailResponse` (one visit header + N chained bookings) rather
// than a single lean `BookingResponse` — see `HttpBookingRepository
// .createMasterBooking`'s doc for the response-side change.
//
// [masterServiceIds] preserves this exact order and DUPLICATES are legal (the
// same service twice is a valid visit) — mirrors the CLIENT multi-service
// analogue, `CreateAppointmentRequest.masterServiceIds`
// (`create_appointment_request.dart`). Never sort or de-duplicate it anywhere
// on this request's path.
//
// ## Emptiness/cap validation lives in the REPOSITORY, not here
//
// The backend caps this list at 10 (`maxServicesPerVisit`,
// `data/slot_repository.dart:41`) and rejects an empty one. The obvious place
// to fail fast on both is right here, at construction — but
// `maxServicesPerVisit` lives in a `data/` file that imports
// `package:flutter/foundation.dart` (for `kDebugMode`), and this file is pure
// Dart with no Flutter dependency, deliberately (see the file's closing
// paragraph) — `domain/` never imports `data/` of the same feature (the
// layering is one-directional: `data/` → `domain/`, never the reverse).
// Duplicating the cap as a second walk-in-specific constant would drift from
// the canonical one the phase doc explicitly forbids introducing. So the
// guard lives at `HttpBookingRepository.createMasterBooking`'s wire boundary
// instead — BEFORE the HTTP call, using the SAME canonical
// `maxServicesPerVisit` (a `data/`→`data/` import, which is legal) — which
// gives the identical practical guarantee the phase doc's rationale asks for
// ("a malformed request cannot reach the wire and come back as an opaque
// 400"), without breaking this file's pure-Dart contract. See that method's
// doc for the exact guard.
//
// ## Why plain `freezed`, not `freezed` + `json_serializable`
//
// The phase doc's model section says "freezed + json_serializable", matching
// this repo's GENERAL local-serialization convention (`CLAUDE.md`). But nothing
// on this request's actual path ever calls `.toJson()`/`.fromJson()`: the
// repository builds the generated built_value wire object directly from the
// fields (mirrors [CreateBookingRequest] / `CreateAppointmentRequest` in this
// exact directory — both pure `freezed`, no JSON, for the identical reason:
// one-shot write payloads consumed only by their own repository method, never
// serialized to a JSON string anywhere in `lib/`). Adding a `.g.dart` for a
// `toJson()`/`fromJson()` pair nothing calls would be dead codegen weight
// diverging from this feature's own two closest precedents. Follows them.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'create_master_booking_request.freezed.dart';

/// The E.164 shape the backend's `chk_bookings_guest_phone_format` DB CHECK
/// enforces on [WalkInGuest.phone] — `+` followed by 6–18 digits. Foreign
/// (non-`+380`) numbers are rejected by the backend's normalizer regardless
/// of this shape being satisfied; this is the WIRE shape check only. Exposed
/// here so Phase 247's form validator has one canonical source instead of
/// re-deriving the pattern.
const String kWalkInGuestPhonePattern = r'^\+[0-9]{6,18}$';

/// The per-field ceiling the backend enforces on [WalkInGuest.name] and
/// [WalkInGuest.surname] — `StaffClientRef.Guest.MAX_NAME_LENGTH`, itself
/// mirroring `bookings.guest_name` / `guest_surname VARCHAR(100)`.
///
/// Exposed for the same reason [kWalkInGuestPhonePattern] is: so the wizard's
/// form has ONE canonical source instead of re-deriving the number. Over-long
/// input is a clean 400 from the server, so bounding the field turns a
/// round-trip rejection into a keystroke that never lands — and bounds what
/// the confirm/done recap cards have to render for a name authored by
/// someone other than the app's own user.
const int kWalkInGuestNameMaxLength = 100;

/// Write payload for `POST /api/v1/masters/{masterId}/bookings` — creates a
/// CONFIRMED, `STAFF`-sourced walk-in booking on a master's calendar.
///
/// [masterId] itself is NOT a field here — it is a path parameter, passed
/// separately to [HttpBookingRepository.createMasterBooking] (mirrors how
/// `CreateBookingRequest` carries no `bookingId`, which is likewise a URL
/// segment, not a body field).
@freezed
abstract class CreateMasterBookingRequest with _$CreateMasterBookingRequest {
  const factory CreateMasterBookingRequest({
    /// The ordered `MasterService` (assignment) ids the master performs, back
    /// to back, in this visit — required, non-empty, capped at
    /// [maxServicesPerVisit] (`data/slot_repository.dart`). ORDER IS THE
    /// PERFORMANCE ORDER the backend chains the visit's bookings on, starting
    /// at [startsAt]; duplicates are legal (the same service twice is a valid
    /// visit) — never sort or de-duplicate. See the file header's "Phase 252"
    /// section for the emptiness/cap validation, which lives in
    /// `HttpBookingRepository.createMasterBooking`, not here.
    required List<String> masterServiceIds,

    /// The chosen appointment start.
    ///
    /// Any [DateTime] is accepted here — local, a Kyiv-wall-clock-derived
    /// `TZDateTime` (`shared/time/time_zones.dart`), or already-UTC.
    /// [HttpBookingRepository.createMasterBooking] unconditionally normalises
    /// it to UTC (`.toUtc()`) before it reaches the generated wire model —
    /// see that method's doc for why: the generated
    /// `Iso8601DateTimeSerializer` THROWS on a non-UTC `DateTime`, and
    /// forcing UTC here guarantees a non-null, unambiguous ISO-8601 offset
    /// (`Z`) on the wire regardless of the host's own timezone — closing the
    /// exact "dev VM TZ (Europe/Kyiv) masks timezone bugs" trap this phase's
    /// test gate calls out (run under `TZ=UTC`).
    required DateTime startsAt,

    /// The walk-in guest's identity — required (this pass is walk-in only;
    /// see the file header).
    required WalkInGuest guest,
  }) = _CreateMasterBookingRequest;
}

/// A walk-in (account-less) client identity for [CreateMasterBookingRequest].
/// Field-for-field mirror of the generated wire `GuestClientDto`.
///
/// Validation is NOT enforced here — mirrors this directory's existing
/// convention ([CreateBookingRequest] / `CreateAppointmentRequest` validate
/// nothing client-side either): the backend is authoritative, the UI form is
/// the UX-facing enforcement point. Documented here for Phase 247's wizard
/// form to consume directly rather than re-deriving from the backend doc:
///   - [name] / [surname]: required, ≤100 chars (`GuestClientDto` columns).
///   - [phone]: required, ≤20 chars, **E.164** — see [kWalkInGuestPhonePattern].
///     The DB CHECK `chk_bookings_guest_phone_format` rejects anything else
///     server-side; foreign (non-`+380`) numbers are rejected by design.
@freezed
abstract class WalkInGuest with _$WalkInGuest {
  const factory WalkInGuest({
    required String name,
    required String surname,
    required String phone,
  }) = _WalkInGuest;
}
