// M545 — one anonymous provider comment about a client (B565
// `ClientReviewCommentResponse`, REV-44 / REV-D10).
//
// Anonymous by contract: the wire carries no author, salon, master, service or
// exact date, and neither does this type. [own] marks the viewer's own comment
// («Ваш коментар»), which is never reportable.
//
// PII: [comment] is provider-authored free text about a person, so it never
// reaches logs or error reports through `toString()`.
//
// Pure Dart: no Flutter imports.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'client_review_comment.freezed.dart';

@freezed
abstract class ClientReviewComment with _$ClientReviewComment {
  const factory ClientReviewComment({
    required String reviewId,

    /// Kyiv visit year (from the wire's `YYYY-MM`).
    required int visitYear,

    /// Kyiv visit month, 1..12.
    required int visitMonth,

    /// 1..5.
    required int stars,

    /// Non-blank comment text (REV-44 sends only non-blank ones).
    required String comment,

    /// The viewer's own comment (REV-44 `own`).
    @Default(false) bool own,
  }) = _ClientReviewComment;

  const ClientReviewComment._();

  @override
  String toString() =>
      'ClientReviewComment(reviewId: $reviewId, visit: $visitYear-$visitMonth, '
      'stars: $stars, own: $own, comment: <redacted>)';
}

/// Parses a REV-44 `YYYY-MM` visit month, or `null` when it is not one.
({int year, int month})? parseVisitMonth(String? raw) {
  final RegExpMatch? m = RegExp(
    r'^(\d{4})-(\d{2})$',
  ).firstMatch(raw?.trim() ?? '');
  final int? year = int.tryParse(m?.group(1) ?? '');
  final int? month = int.tryParse(m?.group(2) ?? '');
  if (year == null || month == null || month < 1 || month > 12) return null;
  return (year: year, month: month);
}
