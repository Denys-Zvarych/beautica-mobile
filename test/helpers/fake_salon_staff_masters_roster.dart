// Test-only `SalonStaffMastersRoster` stand-in (2026-10-05 audit P2).
//
// `salonStaffMastersRosterProvider` became a class-based `AsyncNotifier`
// family so its `build` can hand back the PREVIOUS list instance when the
// projection is content-equal (see `salon_staff_masters_roster.dart`).
// Overriding a class-based provider means supplying a NOTIFIER, not the
// `overrideWith((ref, salonId) async => value)` closure the old function
// provider took. This is the ONE fake every roster-consuming test reuses
// (REUSE-FIRST) — same shape as `FakeSalonMasterServiceCoverage`.

import 'dart:async';

import 'package:beautica_mobile/features/salon/application/salon_staff_masters_roster.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';

/// Overrides `salonStaffMastersRosterProvider` (the whole family, or one
/// member) to resolve [build] via [resolve] instead of reading
/// `salonManagementProfileProvider`.
///
/// ```dart
/// salonStaffMastersRosterProvider.overrideWith(
///   () => FakeSalonStaffMastersRoster(() => <SalonMasterSummary>[_kMaster]),
/// ),
/// ```
class FakeSalonStaffMastersRoster extends SalonStaffMastersRoster {
  FakeSalonStaffMastersRoster(this._resolve);

  /// [FutureOr] so a fixture can return a value directly OR hand back a
  /// caller-owned `Future` (e.g. a never-completed `Completer`).
  final FutureOr<List<SalonMasterSummary>> Function() _resolve;

  @override
  Future<List<SalonMasterSummary>> build(String salonId) async => _resolve();
}
