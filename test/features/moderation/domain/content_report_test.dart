import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContentReportRequest.toString', () {
    const secret = 'Call me on +380671234567, Olena Petrenko';

    test('never contains the comment text', () {
      const request = ContentReportRequest(
        targetType: ReportTargetType.review,
        targetId: 'review-42',
        reason: ReportReason.other,
        comment: secret,
      );

      final text = request.toString();

      expect(text, isNot(contains(secret)));
      expect(text, isNot(contains('+380671234567')));
      expect(text, contains('comment: <redacted>'));
      expect(text, contains('targetId: review-42'));
      expect(text, contains('ReportReason.other'));
      expect(text, contains('ReportTargetType.review'));
    });

    test('prints null when there is no comment', () {
      const request = ContentReportRequest(
        targetType: ReportTargetType.portfolioPhoto,
        targetId: 'photo-7',
        reason: ReportReason.spam,
      );

      expect(request.toString(), contains('comment: null'));
      expect(request.toString(), isNot(contains('<redacted>')));
    });

    test('equality still covers the comment', () {
      const a = ContentReportRequest(
        targetType: ReportTargetType.review,
        targetId: 'r',
        reason: ReportReason.other,
        comment: 'first comment',
      );
      const b = ContentReportRequest(
        targetType: ReportTargetType.review,
        targetId: 'r',
        reason: ReportReason.other,
        comment: 'second comment',
      );

      expect(a, isNot(equals(b)));
      expect(a.copyWith(comment: 'second comment'), equals(b));
    });
  });
}
