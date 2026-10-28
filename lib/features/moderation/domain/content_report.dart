// Phase 424 — content reports (Google Play UGC policy), the domain side of
// backend phase 395 `POST /api/v1/reports`.
//
// Mirrors the 395 contract exactly:
//   request  { targetType, targetId, reason, comment? }
//   response { id, status, createdAt }   (201 new / 200 idempotent repeat)
// Errors: 400 validation / self-report, 404 target not visible (same body as a
// missing id), 429 rate limit (20 reports / 24 h per user).
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'content_report.freezed.dart';

/// What is being reported — backend 395 D1 `ReportTargetType`.
enum ReportTargetType {
  review('REVIEW'),
  clientReview('CLIENT_REVIEW'),
  portfolioPhoto('PORTFOLIO_PHOTO'),
  masterProfile('MASTER_PROFILE'),
  salonProfile('SALON_PROFILE'),
  clientProfile('CLIENT_PROFILE');

  const ReportTargetType(this.wireName);

  /// The backend enum constant.
  final String wireName;
}

/// Why it is being reported — backend 395 D3 `ReportReason`, in sheet order.
enum ReportReason {
  spam('SPAM'),
  offensive('OFFENSIVE'),
  harassment('HARASSMENT'),
  falseInfo('FALSE_INFO'),
  sexualContent('SEXUAL_CONTENT'),
  other('OTHER');

  const ReportReason(this.wireName);

  /// The backend enum constant.
  final String wireName;

  /// `OTHER` requires a comment (backend 395 D3).
  bool get requiresComment => this == ReportReason.other;
}

/// Backend 395 D3 — the comment is at most this many characters.
const int kReportCommentMaxLength = 500;

/// Backend 395 D3 — an `OTHER` report needs a comment of at least this many
/// (trimmed) characters.
const int kReportOtherCommentMinLength = 5;

/// `POST /api/v1/reports` body.
@freezed
abstract class ContentReportRequest with _$ContentReportRequest {
  const factory ContentReportRequest({
    required ReportTargetType targetType,
    required String targetId,
    required ReportReason reason,

    /// Trimmed; `null` when the user wrote nothing.
    String? comment,
  }) = _ContentReportRequest;

  const ContentReportRequest._();

  /// The free-text comment is user-written and may carry PII, so it never
  /// reaches logs or error reports through `toString()`.
  @override
  String toString() =>
      'ContentReportRequest(targetType: $targetType, targetId: $targetId, '
      'reason: $reason, comment: ${comment == null ? 'null' : '<redacted>'})';
}

/// `POST /api/v1/reports` response payload.
@freezed
abstract class ContentReport with _$ContentReport {
  const factory ContentReport({
    required String id,

    /// Backend `ReportStatus` constant (`OPEN` on create).
    required String status,
    required DateTime createdAt,
  }) = _ContentReport;
}
