// In-memory [ContentReportRepository] that enforces the backend 395 contract
// the sheet depends on, so widget/notifier tests exercise real semantics:
//   • D3 — `OTHER` needs a trimmed comment of >= 5 chars; comment <= 500
//     → ValidationFailure (400).
//   • D4 — one open report per target: a repeat returns the SAME report
//     (idempotent 200), never a second row.
//   • D6 — [rateLimit] reports per instance, then ServerFailure(429).
//   • [hiddenTargetIds] → NotFoundFailure (404, target not visible).
// [nextFailure] forces the next call to throw (then clears); [nextError]
// does the same with a NON-`Failure` object (a mapper bug, a TypeError).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/moderation/data/content_report_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';

final class FakeContentReportRepository implements ContentReportRepository {
  FakeContentReportRepository({
    this.rateLimit = 20,
    Set<String>? hiddenTargetIds,
    DateTime? now,
  }) : hiddenTargetIds = hiddenTargetIds ?? <String>{},
       _now = now ?? DateTime.utc(2026, 10, 28, 12);

  final int rateLimit;
  final Set<String> hiddenTargetIds;
  final DateTime _now;

  /// Every request received, in order (including rejected ones).
  final List<ContentReportRequest> requests = <ContentReportRequest>[];

  /// Thrown (once) by the next [create].
  Failure? nextFailure;

  /// Thrown (once) by the next [create] — a non-[Failure] escape (LOW-3).
  Object? nextError;

  /// When set, [create] waits for it — lets a test observe the sending state.
  Completer<void>? gate;

  final Map<(ReportTargetType, String), ContentReport> _open =
      <(ReportTargetType, String), ContentReport>{};
  int _accepted = 0;

  /// Distinct reports stored.
  int get storedCount => _open.length;

  @override
  Future<ContentReport> create(ContentReportRequest request) async {
    requests.add(request);
    final Completer<void>? g = gate;
    if (g != null) await g.future;
    final Object? raw = nextError;
    if (raw != null) {
      nextError = null;
      throw raw;
    }
    final Failure? forced = nextFailure;
    if (forced != null) {
      nextFailure = null;
      throw forced;
    }
    final String comment = request.comment?.trim() ?? '';
    if (comment.length > kReportCommentMaxLength ||
        (request.reason.requiresComment &&
            comment.length < kReportOtherCommentMinLength)) {
      throw const ValidationFailure(fieldErrors: <String, String>{});
    }
    if (hiddenTargetIds.contains(request.targetId)) {
      throw const NotFoundFailure();
    }
    final (ReportTargetType, String) key = (
      request.targetType,
      request.targetId,
    );
    final ContentReport? existing = _open[key];
    if (existing != null) return existing;
    if (_accepted >= rateLimit) throw const ServerFailure(statusCode: 429);
    _accepted++;
    final ContentReport created = ContentReport(
      id: 'report-${_open.length + 1}',
      status: 'OPEN',
      createdAt: _now,
    );
    _open[key] = created;
    return created;
  }
}
