// Phase 424 — the in-memory ContentReportRepository fake honours the backend
// 395 contract the report sheet relies on (D3 validation, D4 idempotency,
// D6 rate limit, D2 404). The production HTTP implementation is covered by
// http_content_report_repository_test.dart.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_content_report_repository.dart';

ContentReportRequest _req({
  String targetId = 'review-1',
  ReportTargetType type = ReportTargetType.review,
  ReportReason reason = ReportReason.spam,
  String? comment,
}) => ContentReportRequest(
  targetType: type,
  targetId: targetId,
  reason: reason,
  comment: comment,
);

void main() {
  group('FakeContentReportRepository', () {
    test('creates an OPEN report and records the request', () async {
      final FakeContentReportRepository repo = FakeContentReportRepository();
      final ContentReport r = await repo.create(_req());
      expect(r.status, 'OPEN');
      expect(repo.requests.single.targetId, 'review-1');
      expect(repo.storedCount, 1);
    });

    test('D4 — a repeat for the same target returns the SAME report', () async {
      final FakeContentReportRepository repo = FakeContentReportRepository();
      final ContentReport first = await repo.create(_req());
      final ContentReport again = await repo.create(
        _req(reason: ReportReason.offensive),
      );
      expect(again, first);
      expect(repo.storedCount, 1);
    });

    test(
      'D4 — the same id under another target type is a new report',
      () async {
        final FakeContentReportRepository repo = FakeContentReportRepository();
        await repo.create(_req(targetId: 'x'));
        await repo.create(
          _req(targetId: 'x', type: ReportTargetType.portfolioPhoto),
        );
        expect(repo.storedCount, 2);
      },
    );

    test('D3 — OTHER needs >= 5 trimmed chars', () async {
      final FakeContentReportRepository repo = FakeContentReportRepository();
      await expectLater(
        repo.create(_req(reason: ReportReason.other, comment: '  abcd  ')),
        throwsA(isA<ValidationFailure>()),
      );
      final ContentReport ok = await repo.create(
        _req(reason: ReportReason.other, comment: 'abcde'),
      );
      expect(ok.status, 'OPEN');
    });

    test('D3 — a comment over 500 chars is rejected', () async {
      final FakeContentReportRepository repo = FakeContentReportRepository();
      await expectLater(
        repo.create(_req(comment: 'a' * (kReportCommentMaxLength + 1))),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('D2 — a hidden target is 404', () async {
      final FakeContentReportRepository repo = FakeContentReportRepository(
        hiddenTargetIds: <String>{'gone'},
      );
      await expectLater(
        repo.create(_req(targetId: 'gone')),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test(
      'D6 — past the limit → ServerFailure(429); a repeat still 200',
      () async {
        final FakeContentReportRepository repo = FakeContentReportRepository(
          rateLimit: 2,
        );
        await repo.create(_req(targetId: 'a'));
        await repo.create(_req(targetId: 'b'));
        await expectLater(
          repo.create(_req(targetId: 'c')),
          throwsA(
            isA<ServerFailure>().having((f) => f.statusCode, 'status', 429),
          ),
        );
        // Idempotent repeat is not a new report, so it is not rate limited.
        expect((await repo.create(_req(targetId: 'a'))).id, 'report-1');
      },
    );

    test('nextFailure is thrown once, then cleared', () async {
      final FakeContentReportRepository repo = FakeContentReportRepository()
        ..nextFailure = const NetworkFailure();
      await expectLater(repo.create(_req()), throwsA(isA<NetworkFailure>()));
      expect((await repo.create(_req())).status, 'OPEN');
    });
  });
}
