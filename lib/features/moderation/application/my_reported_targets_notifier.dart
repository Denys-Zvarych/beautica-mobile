// Phase 428 add-on — "report once, ever": the targets the signed-in user has
// already reported, so every «⋮» report entry can hide for them.
//
// Loaded ONCE per session from backend 415 `GET /api/v1/reports/mine`
// (keepAlive), keyed on the user id: a logout → login re-runs [build] and the
// next account starts from its own server set. A successful submit adds the
// target locally ([MyReportedTargets.markReported], called by
// `ReportController`), so the «⋮» disappears at once, without a refetch.
//
// Fail OPEN: if the read fails the set is empty and «⋮» stays visible — the
// backend already makes a repeat report idempotent (395 D4: one open report
// per target, the same report is returned), so a visible «⋮» can never create
// a duplicate; a hidden one on a transient error would wrongly withhold it.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/moderation/data/content_report_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';

part 'my_reported_targets_notifier.g.dart';

/// The signed-in user's reported targets (empty when signed out).
@Riverpod(keepAlive: true)
class MyReportedTargets extends _$MyReportedTargets {
  /// Targets reported in THIS session ([markReported]); merged into every
  /// [build] result so a submit that lands while the first read is still in
  /// flight is never overwritten by that (older) read.
  final Set<ReportedTarget> _localAdds = <ReportedTarget>{};

  /// The user [_localAdds] belongs to — a different user clears them.
  String? _localAddsUserId;

  @override
  Future<Set<ReportedTarget>> build() async {
    // Narrowed to the user id: a silent token refresh must not refetch.
    final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
    if (userId != _localAddsUserId) {
      _localAdds.clear();
      _localAddsUserId = userId;
    }
    // No session → nothing fetched (local adds are cleared on any user
    // change above, so this is empty for a real sign-out).
    if (userId == null) return <ReportedTarget>{..._localAdds};
    try {
      final Set<ReportedTarget> fetched = await ref
          .read(contentReportRepositoryProvider)
          .mine();
      return <ReportedTarget>{...fetched, ..._localAdds};
    } catch (e) {
      if (kDebugMode) {
        log(
          'reports/mine failed (${e.runtimeType}) — report entries stay visible',
          name: 'feature.moderation.reported',
          level: 900,
        );
      }
      return <ReportedTarget>{..._localAdds};
    }
  }

  /// Adds [type]/[id] locally after a successful report submit.
  void markReported(ReportTargetType type, String id) {
    final ReportedTarget target = (type: type, id: id);
    _localAdds.add(target);
    final Set<ReportedTarget> current = state.value ?? const <ReportedTarget>{};
    if (current.contains(target)) return;
    state = AsyncData<Set<ReportedTarget>>(<ReportedTarget>{
      ...current,
      target,
    });
  }
}

/// The reported set for a `build` method (empty while loading / on error).
/// Call from a widget's `build`, never from a lazy item builder.
Set<ReportedTarget> watchReportedTargets(WidgetRef ref) =>
    ref.watch(myReportedTargetsProvider).value ?? const <ReportedTarget>{};

/// Whether [type]/[id] is already reported — rebuilds only when that answer
/// changes.
bool watchIsReported(WidgetRef ref, ReportTargetType type, String id) =>
    ref.watch(
      myReportedTargetsProvider.select(
        (AsyncValue<Set<ReportedTarget>> s) =>
            s.value?.contains((type: type, id: id)) ?? false,
      ),
    );
