// Phase 428 add-on — test double that pins the user's reported-target set
// (`myReportedTargetsProvider`, backend 415 `GET /reports/mine`) to EMPTY.
//
// Every reportable surface (review lists, profiles, the photo viewer, the
// booking-detail client strip) now watches that keepAlive provider to hide its
// «⋮» report entry. Left real, it would fire a Dio request from every widget
// test that renders such a surface. `pumpApp` / `pumpRoutedApp` /
// `makeTestContainer` PREPEND [kNoReportedTargetsOverride] by default, so no
// existing test changes.
//
// The default steps aside when the caller overrides `myReportedTargetsProvider`
// itself, OR overrides `contentReportRepositoryProvider` — a test wiring a fake
// report repository gets the REAL notifier reading that fake's `mine()`.

import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:beautica_mobile/features/moderation/application/my_reported_targets_notifier.dart';
import 'package:beautica_mobile/features/moderation/data/content_report_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';

/// No targets reported yet; [markReported] still works (inherited).
class NoReportedTargets extends MyReportedTargets {
  @override
  Future<Set<ReportedTarget>> build() async => const <ReportedTarget>{};
}

/// Pins `myReportedTargetsProvider` to an empty set (no fetch).
final Object kNoReportedTargetsOverride = myReportedTargetsProvider
    .overrideWith(NoReportedTargets.new);

/// Prepends [kNoReportedTargetsOverride] UNLESS the caller overrides
/// `myReportedTargetsProvider` or `contentReportRepositoryProvider`.
List<Object> withDefaultNoReportedTargets(List<Object> overrides) {
  final bool callerOwnsIt = overrides.any(
    (Object o) =>
        o is Override &&
        (o.origin == myReportedTargetsProvider ||
            o.origin == contentReportRepositoryProvider),
  );
  return callerOwnsIt
      ? overrides
      : <Object>[kNoReportedTargetsOverride, ...overrides];
}

/// A user who has ALREADY reported [targets] (what `GET /reports/mine` would
/// return); [markReported] still adds on top.
class SeededReportedTargets extends MyReportedTargets {
  SeededReportedTargets(this.targets);

  final Set<ReportedTarget> targets;

  @override
  Future<Set<ReportedTarget>> build() async => targets;
}

/// Overrides `myReportedTargetsProvider` with [targets] already reported.
/// Suppresses the empty default (see [withDefaultNoReportedTargets]).
Object reportedTargetsOverride(Set<ReportedTarget> targets) =>
    myReportedTargetsProvider.overrideWith(
      () => SeededReportedTargets(targets),
    );
