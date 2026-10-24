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
//     schedule  [salonEffectiveScheduleProvider] on EXACTLY the key the
//               «Записи» board watches (`ScheduleRange.month(kyivToday)`, see
//               [salonReadinessRange]) — no new key, no extra pinned window,
//               a board that is open already holds it: no master has a
//               single working day in the current month
//     services  [salonServiceCatalogProvider]: the salon catalogue is empty
//
// SALON OWNER: the owner's hint targets (`/owner/master/*`) act on the
// owner's PRIMARY salon, not on `link.salonId`. So an owner sees hints only on
// the primary-salon card (`Salon.isPrimary`, or the sole salon); other salon
// cards get none (the generic 414 note stays) and — because that check comes
// first — never read the schedule/catalogue providers: a multi-salon owner
// costs one readiness fetch pair, not N. An admin has exactly one salon.
//
// Refresh: while a value is being RE-fetched (after returning from a setup
// page) the previous answer is kept, so the generic note never flashes. A
// first load, any error, and the first build after an ACCOUNT SWITCH read as
// "nothing missing": the family is keyed by the signed-in user id, and only a
// rebuild of the SAME instance (same user) may fall back on a previous value —
// an upstream's retained previous value after an account switch belongs to
// the outgoing account and is never shown.
//
// ACCOUNT ISOLATION RELIES ON THE userId KEY, NOT on `_builtOnce` alone:
// `_builtOnce` is per Notifier instance, so it only distinguishes "first build"
// from "rebuild of this instance". A different user is a different family
// member (fresh instance, `_builtOnce == false`); `ref.invalidate` of the SAME
// user's member keeps the instance and so keeps its previous value (intended).
// Dropping `userId` from the key would silently break isolation.
//
// Schedule window (salon): the board's current-month key, so the rule is
// "no master has a working day in the current month, past days included". A
// schedule that only starts NEXT month therefore still shows the schedule
// hint until the month turns (the next-month key is not cached anywhere, and
// fetching it would add a pinned window); the hint is informational only.
//
// Loading and error read as "nothing missing" (empty list): the readiness
// check must never block, flash an error on, or reserve space in the link
// screen. `asData` (never `.value`) so an errored refresh cannot republish a
// previous account's value.

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

import '../../auth/domain/user_role.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../../salon/application/my_salons_notifier.dart';
import '../../salon/application/salon_service_catalog_notifier.dart';
import '../../salon/domain/salon.dart';
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

/// The month key the salon «Записи» board watches — reused as-is so readiness
/// shares its cache entry instead of pinning a second window.
ScheduleRange salonReadinessRange(DateTime today) => ScheduleRange.month(today);

/// Value type so an unchanged answer does not rebuild the card.
@immutable
final class BookingLinkSetupHints {
  const BookingLinkSetupHints({this.schedule = false, this.services = false});

  static const BookingLinkSetupHints none = BookingLinkSetupHints();

  final bool schedule;
  final bool services;

  bool get isEmpty => !schedule && !services;

  /// Schedule first, as the screen lists them.
  List<BookingLinkSetupHint> get missing => isEmpty
      ? const <BookingLinkSetupHint>[]
      : List<BookingLinkSetupHint>.unmodifiable(<BookingLinkSetupHint>[
          if (schedule) BookingLinkSetupHint.schedule,
          if (services) BookingLinkSetupHint.services,
        ]);

  @override
  bool operator ==(Object other) =>
      other is BookingLinkSetupHints &&
      other.schedule == schedule &&
      other.services == services;

  @override
  int get hashCode => Object.hash(schedule, services);
}

/// The value to read from [v]: a settled value, or — only when
/// [allowPrevious] (a rebuild of the same user's instance) and a REFRESH is in
/// flight — the previous one; null on a first load and on error.
T? _settledOrPrevious<T>(AsyncValue<T> v, {required bool allowPrevious}) =>
    v.isLoading
    // `asData` ALSO yields the retained previous value of a refreshing
    // provider, so a loading state is decided here, explicitly.
    ? (allowPrevious ? v.value : null)
    : v.asData?.value;

/// The missing prerequisites of the link of [kind] for [userId] — for a salon
/// link [salonId] is the salon, for a master link it is ignored (pass `''`).
/// [userId] only keys the family (see the header: no cross-account previous).
// `dependencies`: masterServiceCatalog is itself scoped on serviceRepository
// (see its declaration), so riverpod requires it be declared here.
@Riverpod(dependencies: [masterServiceCatalog])
class BookingLinkSetupHintsNotifier extends _$BookingLinkSetupHintsNotifier {
  /// False until the first build of THIS instance has completed.
  bool _builtOnce = false;

  @override
  BookingLinkSetupHints build(
    BookingLinkKind kind,
    String salonId,
    String userId,
  ) {
    final BookingLinkSetupHints result = _compute(
      kind,
      salonId,
      allowPrevious: _builtOnce,
    );
    _builtOnce = true;
    return result;
  }

  BookingLinkSetupHints _compute(
    BookingLinkKind kind,
    String salonId, {
    required bool allowPrevious,
  }) {
    final bool? noSchedule;
    final bool? noServices;
    switch (kind) {
      case BookingLinkKind.master:
        final List<WeeklySchedule>? weekly = _settledOrPrevious(
          ref.watch(
            weeklyScheduleProvider(ref.watch(ownScheduleScopeProvider)),
          ),
          allowPrevious: allowPrevious,
        );
        noSchedule = weekly?.isEmpty;
        final List<MasterService>? services = _settledOrPrevious(
          ref.watch(masterServiceCatalogProvider),
          allowPrevious: allowPrevious,
        );
        noServices = services?.every((MasterService s) => !s.isActive);
      case BookingLinkKind.salon:
        if (salonId.trim().isEmpty) return BookingLinkSetupHints.none;
        // Owner targets act on the primary salon only — see the header.
        final UserRole? role = ref.watch(
          authProvider.select(authUserRoleOrNull),
        );
        if (role == UserRole.salonOwner) {
          final List<Salon>? mine = _settledOrPrevious(
            ref.watch(mySalonsProvider),
            allowPrevious: allowPrevious,
          );
          if (mine == null) return BookingLinkSetupHints.none;
          final bool primary = mine.length == 1
              ? mine.single.id == salonId
              : mine.any(
                  (Salon s) => s.id == salonId && (s.isPrimary ?? false),
                );
          if (!primary) return BookingLinkSetupHints.none;
        }
        final Map<String, List<EffectiveDay>>? byMaster = _settledOrPrevious(
          ref.watch(
            salonEffectiveScheduleProvider(
              salonId,
              salonReadinessRange(kyivToday(ref.watch(clockProvider))),
            ),
          ),
          allowPrevious: allowPrevious,
        );
        noSchedule = byMaster?.values.every(
          (List<EffectiveDay> days) => days.every(
            (EffectiveDay d) => d.source == EffectiveSource.noSchedule,
          ),
        );
        final List<SalonServiceCategoryEntry>? catalogue = _settledOrPrevious(
          ref.watch(salonServiceCatalogProvider(salonId)),
          allowPrevious: allowPrevious,
        );
        noServices = catalogue?.every(
          (SalonServiceCategoryEntry c) => c.services.isEmpty,
        );
    }
    return BookingLinkSetupHints(
      schedule: noSchedule ?? false,
      services: noServices ?? false,
    );
  }
}
