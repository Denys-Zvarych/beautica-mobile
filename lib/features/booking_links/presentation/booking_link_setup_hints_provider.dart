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
//     schedule  [effectiveScheduleProvider] of [ownScheduleScopeProvider]
//               over [masterReadinessRange] — the backend's bookability rule
//               (`MasterBookabilitySql` / `MasterScheduleService
//               .hasUsableSchedule`, architect ruling 2026-10-30): missing
//               unless SOME day in [todayKyiv, todayKyiv + 180) resolves to a
//               working day (overrides first, then the template valid on that
//               date). CUSTOM_HOURS overrides count; DAY_OFF overrides,
//               all-days-off / expired / starts-past-the-horizon templates do
//               not. Same family the «Графік» calendar reads — no fork; a
//               weekly save / override write already refreshes every live
//               window of it.
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
import '../../master/domain/master.dart';
import '../../master/presentation/master_profile_notifier.dart';
import '../../schedule/application/own_schedule_scope.dart';
import '../../schedule/domain/schedule_scope.dart';
import '../../schedule/domain/weekly_schedule.dart';
import '../../schedule/presentation/effective_schedule_notifier.dart';
import '../../schedule/presentation/salon_effective_schedule_notifier.dart';
import '../../schedule/presentation/schedule_range.dart';
import '../../services/data/master_service_catalog_provider.dart';
import '../../services/domain/master_service.dart';
import '../domain/booking_link.dart';

part 'booking_link_setup_hints_provider.g.dart';

/// What is still missing before a client can book.
enum BookingLinkSetupHint { schedule, services }

/// The month key the salon «Записи» board watches — reused as-is so readiness
/// shares its cache entry instead of pinning a second window.
ScheduleRange salonReadinessRange(DateTime today) => ScheduleRange.month(today);

/// The backend's bookability horizon in days (`MasterBookabilitySql
/// .HORIZON_DAYS`, = `BookingWindow.MAX_DAYS_AHEAD`).
const int kMasterReadinessHorizonDays = 180;

/// `[today, today + 180)` as an inclusive date range — the window the backend
/// checks for "has a usable schedule". [today] is a Kyiv date token
/// (`kyivToday`); day arithmetic on its calendar fields, never on an instant.
ScheduleRange masterReadinessRange(DateTime today) => ScheduleRange(
  from: today,
  to: DateTime(
    today.year,
    today.month,
    today.day + kMasterReadinessHorizonDays - 1,
  ),
);

/// A resolved day a client could book on — mirrors the backend's
/// `EffectiveDayResponse.isWorkingDay` (intervals OR discrete times).
bool _isWorkingDay(EffectiveDay d) =>
    d.intervals.isNotEmpty || d.times.isNotEmpty;

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

/// The missing prerequisites of the link of [kind] for [userId] — for a salon
/// link [salonId] is the salon, for a master link it is ignored (pass `''`).
/// [userId] only keys the family (see the header: no cross-account previous).
// `dependencies`: masterServiceCatalog is itself scoped on serviceRepository
// (see its declaration), so riverpod requires it be declared here.
@Riverpod(dependencies: [masterServiceCatalog])
class BookingLinkSetupHintsNotifier extends _$BookingLinkSetupHintsNotifier {
  /// False until the first build of THIS instance has completed.
  bool _builtOnce = false;

  /// Upstreams (by tag) this instance has itself seen SETTLED. A retained
  /// value of a refreshing upstream is reused only if it is in here — i.e.
  /// this same user's instance already read a settled value from it.
  ///
  /// `_builtOnce` alone is not enough (security, cycle 2): the instance can
  /// rebuild for an unrelated reason (e.g. the account's master profile
  /// settling) while an upstream is still RE-fetching for the new account
  /// and carrying the PREVIOUS account's value — a second build of a brand-new
  /// user's instance would then republish that value.
  final Set<String> _seenSettled = <String>{};

  /// The value to read from [v]: a settled value, or — only when
  /// [allowPrevious] (a rebuild of the same user's instance), a REFRESH is in
  /// flight AND this instance already saw [tag] settled — the previous one;
  /// null on a first load and on error.
  T? _settledOrPrevious<T>(
    String tag,
    AsyncValue<T> v, {
    required bool allowPrevious,
  }) {
    // `asData` ALSO yields the retained previous value of a refreshing
    // provider, so a loading state is decided here, explicitly.
    if (v.isLoading) {
      return allowPrevious && _seenSettled.contains(tag) ? v.value : null;
    }
    final T? value = v.asData?.value;
    if (value != null) _seenSettled.add(tag);
    return value;
  }

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

  /// The master-link schedule verdict, or `null` (no hint) when it cannot be
  /// trusted yet.
  ///
  /// IDENTITY GATE (security LOW, cycles 1–2): `ownScheduleScopeProvider`
  /// selects `masterProfileProvider`'s `.value?.id`, which RETAINS the previous
  /// account's id while the next account's profile loads (logout → login as
  /// another independent master on one device). Reading the window on that
  /// stale scope would show master A's answer to master B — on the
  /// «Посилання для запису» card and on the nav dots alike, which is why the
  /// gate lives here and not in a consumer. So the scope must equal the
  /// SETTLED profile id (`asData`: null on a reload or error; a same-user
  /// refresh keeps the same id, which is intended).
  ///
  /// The empty-scope check runs FIRST: `ownScheduleScopeProvider` resolves
  /// `''` for every role without its own master row WITHOUT touching
  /// `masterProfileProvider` (whose `GET /masters/me` 403s a SALON_ADMIN), and
  /// this keeps that property.
  bool? _masterNoSchedule({required bool allowPrevious}) {
    final ScheduleScope scope = ref.watch(ownScheduleScopeProvider);
    final String scopeMasterId = switch (scope) {
      OwnScheduleScope(:final String masterId) => masterId,
      SalonMasterScheduleScope() => '',
    };
    if (scopeMasterId.isEmpty) return null;
    final String? settledMasterId = ref.watch(
      masterProfileProvider.select(
        (AsyncValue<Master> s) => s.asData?.value.id,
      ),
    );
    if (settledMasterId != scopeMasterId) return null;
    final List<EffectiveDay>? days = _settledOrPrevious(
      'masterSchedule',
      ref.watch(
        effectiveScheduleProvider(
          scope,
          // Computed at build, not rolled at Kyiv midnight: no midnight-ticking
          // day provider exists in the app (same as [salonReadinessRange]).
          masterReadinessRange(kyivToday(ref.watch(clockProvider))),
        ),
      ),
      allowPrevious: allowPrevious,
    );
    return days == null ? null : !days.any(_isWorkingDay);
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
        // Signed out (logout flips the session in the same turn as its
        // schedule sweeps): never re-read the readiness window with the
        // outgoing — or the now-empty — own scope. Narrowed selector, never a
        // bare `authProvider` watch.
        if (ref.watch(authProvider.select(authUserIdOrNull)) == null) {
          return BookingLinkSetupHints.none;
        }
        noSchedule = _masterNoSchedule(allowPrevious: allowPrevious);
        final List<MasterService>? services = _settledOrPrevious(
          'masterServices',
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
            'mySalons',
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
          'salonSchedule',
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
          'salonServices',
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
