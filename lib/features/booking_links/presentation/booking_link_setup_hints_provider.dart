// Phase 416 — readiness hints for «Посилання для запису».
//
// Answers, per link, "which of the two things a client needs before they can
// book is still missing?" — a schedule and/or at least one service. Purely
// informational: the link stays shareable either way.
//
// REUSE-FIRST: no new endpoint and no parallel fetch. Everything is derived
// from providers the setup screens themselves already use:
//
//   MASTER link (independent master — own data)
//     schedule  [weeklyScheduleProvider] of [ownScheduleScopeProvider]: no
//               weekly template at all
//     services  [masterServiceCatalogProvider]: no ACTIVE service
//
//   SALON link (owner / admin) — the salon is bookable only when at least one
//   master has services + schedule, so it is missing when
//     schedule  [salonEffectiveScheduleProvider] (the roster-complete batch
//               the «Записи» board uses) over today … +[kSalonReadinessDays]
//               days: no master has a single working day
//     services  [salonServiceCatalogProvider]: the salon catalogue is empty
//
// Loading and error read as "nothing missing" (empty list): the readiness
// check must never block, flash an error on, or reserve space in the link
// screen. `asData` (never `.value`) so an errored refresh cannot republish a
// previous account's value.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

import '../../salon/application/salon_service_catalog_notifier.dart';
import '../../salon/domain/salon_service_catalog.dart';
import '../../schedule/application/own_schedule_scope.dart';
import '../../schedule/domain/weekly_schedule.dart';
import '../../schedule/presentation/salon_effective_schedule_notifier.dart';
import '../../schedule/presentation/schedule_range.dart';
import '../../schedule/presentation/weekly_schedule_notifier.dart';
import '../../services/data/master_service_catalog_provider.dart';
import '../../services/domain/master_service.dart';
import '../domain/booking_link.dart';

part 'booking_link_setup_hints_provider.g.dart';

/// What is still missing before a client can book.
enum BookingLinkSetupHint { schedule, services }

/// How far ahead a salon's roster is scanned for a working day (≤ the 62-day
/// batch limit).
const int kSalonReadinessDays = 60;

/// The missing prerequisites of the link of [kind] — for a salon link
/// [salonId] is the salon, for a master link it is ignored (pass `''`).
/// Schedule first, as the screen lists them. Empty while unknown.
// `dependencies`: masterServiceCatalog is itself scoped on serviceRepository
// (see its declaration), so riverpod requires it be declared here.
@Riverpod(dependencies: [masterServiceCatalog])
List<BookingLinkSetupHint> bookingLinkSetupHints(
  Ref ref,
  BookingLinkKind kind,
  String salonId,
) {
  final bool? noSchedule;
  final bool? noServices;
  switch (kind) {
    case BookingLinkKind.master:
      final List<WeeklySchedule>? weekly = ref
          .watch(weeklyScheduleProvider(ref.watch(ownScheduleScopeProvider)))
          .asData
          ?.value;
      noSchedule = weekly?.isEmpty;
      final List<MasterService>? services = ref
          .watch(masterServiceCatalogProvider)
          .asData
          ?.value;
      noServices = services?.every((MasterService s) => !s.isActive);
    case BookingLinkKind.salon:
      if (salonId.trim().isEmpty) return const <BookingLinkSetupHint>[];
      final DateTime today = kyivToday(ref.watch(clockProvider));
      final Map<String, List<EffectiveDay>>? byMaster = ref
          .watch(
            salonEffectiveScheduleProvider(
              salonId,
              ScheduleRange(
                from: today,
                to: DateTime(
                  today.year,
                  today.month,
                  today.day + kSalonReadinessDays,
                ),
              ),
            ),
          )
          .asData
          ?.value;
      noSchedule = byMaster?.values.every(
        (List<EffectiveDay> days) => days.every(
          (EffectiveDay d) => d.source == EffectiveSource.noSchedule,
        ),
      );
      final List<SalonServiceCategoryEntry>? catalogue = ref
          .watch(salonServiceCatalogProvider(salonId))
          .asData
          ?.value;
      noServices = catalogue?.every(
        (SalonServiceCategoryEntry c) => c.services.isEmpty,
      );
  }
  return List<BookingLinkSetupHint>.unmodifiable(<BookingLinkSetupHint>[
    if (noSchedule ?? false) BookingLinkSetupHint.schedule,
    if (noServices ?? false) BookingLinkSetupHint.services,
  ]);
}
