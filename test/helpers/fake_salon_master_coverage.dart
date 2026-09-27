// Test-only `SalonMasterServiceCoverage` stand-in (Phase 266).
//
// `salonMasterServiceCoverageProvider` became a class-based `AsyncNotifier`
// family (see `salon_master_coverage_notifier.dart`'s file header — the
// conversion exists purely so D4's per-service retry has somewhere to live).
// Overriding a class-based provider means supplying a NOTIFIER, not a
// closure returning a value the way the old function provider's
// `overrideWith((ref, args) async => value)` did. This is the ONE fake
// notifier every coverage-consuming test in the suite reuses (REUSE-FIRST),
// rather than each test file hand-rolling its own
// `class _Fixed... extends SalonMasterServiceCoverage`.
//
// `retryService` is DELIBERATELY not overridden here — it is inherited
// straight from the real [SalonMasterServiceCoverage], so a widget test that
// exercises D4's retry button (`salon_master_selection_screen_test.dart`)
// gets the REAL merge logic, reading through whatever `salonRepositoryProvider`
// override that test already supplies. Only the INITIAL [build] is faked.
//
// Phase 266, audit cycle 3, finding #2 — because [build] is OVERRIDDEN (not
// called through), the real `build()`'s own `ref.onDispose(cancelCooldown
// Timers)` registration never runs for this fake. A failed `retryService`
// call still arms a REAL [Timer] via the inherited `_armCooldownExpiry`, so
// without registering the same cleanup here, a widget test that exercises a
// failing retry leaves a pending [Timer] at teardown — `flutter_test` fails
// any test torn down with one still pending. [build] below registers
// [SalonMasterServiceCoverage.cancelCooldownTimers] itself, the exact method
// the real `build()` uses, so the two paths can never drift.

import 'dart:async';

import 'package:beautica_mobile/features/booking/application/salon_master_coverage_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_args.dart';

/// Overrides `salonMasterServiceCoverageProvider` (the whole family, or one
/// `salonMasterServiceCoverageProvider(args)` member) to resolve [build] via
/// [resolve] instead of issuing any real `getBookableMasters` calls.
///
/// ```dart
/// salonMasterServiceCoverageProvider(args).overrideWith(
///   () => FakeSalonMasterServiceCoverage(
///     () => (
///       byMaster: _stubCoverage,
///       degradedServiceIds: const <String>{},
///       retryingServiceIds: const <String>{},
///       retryCooldownUntil: const <String, DateTime>{},
///     ),
///   ),
/// ),
/// ```
///
/// Prefer [salonCoverageOf] over hand-rolling the record literal above — it
/// fills the two Phase-266-audit-cycle-1 retry-tracking fields with their
/// shared empty instances for you.
class FakeSalonMasterServiceCoverage extends SalonMasterServiceCoverage {
  FakeSalonMasterServiceCoverage(this._resolve);

  /// Resolves the same way every `build()` call for this fake would.
  /// [FutureOr] so a fixture can return a value synchronously-wrapped OR
  /// hand back a caller-owned `Future` (e.g. a never-completed `Completer`,
  /// to pin the provider in its loading state for a test).
  final FutureOr<SalonCoverage> Function() _resolve;

  @override
  Future<SalonCoverage> build(SalonBookingMasterSelectionArgs args) async {
    // See the file header, Phase 266 audit cycle 3 note — reproduces the
    // real `build()`'s cooldown-timer disposal since overriding `build`
    // means this class's own body never runs.
    ref.onDispose(cancelCooldownTimers);
    return _resolve();
  }
}

/// Convenience wrapper for the common case: a fixed coverage MAP with an
/// EMPTY degraded set and no retry in flight/cooling down — every
/// pre-Phase-266 fixture's shape, so existing `Map<String, Map<String,
/// String>>` fixtures across the suite need no reshaping, just this one
/// extra wrap at the override call site.
SalonCoverage salonCoverageOf(Map<String, Map<String, String>> byMaster) => (
  byMaster: byMaster,
  degradedServiceIds: const <String>{},
  retryingServiceIds: const <String>{},
  retryCooldownUntil: const <String, DateTime>{},
);
