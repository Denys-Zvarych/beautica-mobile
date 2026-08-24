// Phase 23.x — BookableMasterAssignment: the (masterId, masterServiceId) pair
// returned by `GET /salons/{salonId}/services/{serviceDefId}/masters`
// (`SalonRepository.getBookableMasters`).
//
// Backs the salon booking flow's master-assignment step
// (`salon_master_coverage_notifier.dart`), which used to reconstruct
// master<->service coverage by fanning `GET /masters/{id}/services` out over
// the ENTIRE salon roster. The new endpoint is scoped server-side to exactly
// the masters who are active, actively assigned to the requested service, AND
// schedule-usable — a scheduleless master (the calendar-all-dates-disabled
// bug) is simply absent from the response, so it can never reach this type.
//
// Deliberately NOT a full display DTO: `SalonMasterSelectionScreen` still
// sources master display data (name/avatar/rating) from
// `publicSalonProfileProvider`'s roster — see that screen's file header,
// "DATA — per-master service coverage gap". This type carries only the two
// ids the coverage map actually needs: [masterId] for eligibility, and
// [masterServiceId] — the master's OWN `MasterServiceAssignment` id for the
// service, the id the slot-availability endpoint requires (see
// `salon_master_schedule.dart`'s `orderedMasterServiceIds`).
//
// Pure Dart: no Flutter imports anywhere in this file.

/// One master bookable for a single service, and their per-master
/// assignment id for it.
typedef BookableMasterAssignment = ({String masterId, String masterServiceId});
