// Phase 424 — ReportController: idle → sending → sent | error, with the D4
// failure classification (429 → rateLimited, everything else → generic).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/moderation/application/report_notifier.dart';
import 'package:beautica_mobile/features/moderation/data/content_report_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_content_report_repository.dart';

const ContentReportRequest _req = ContentReportRequest(
  targetType: ReportTargetType.review,
  targetId: 'review-1',
  reason: ReportReason.spam,
);

(ProviderContainer, FakeContentReportRepository) _container() {
  final FakeContentReportRepository repo = FakeContentReportRepository();
  final ProviderContainer c = ProviderContainer(
    overrides: [contentReportRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  // Keep the auto-dispose controller alive for the test's duration.
  c.listen(reportControllerProvider, (_, _) {});
  return (c, repo);
}

void main() {
  test('starts idle', () {
    final (ProviderContainer c, _) = _container();
    expect(c.read(reportControllerProvider), isA<ReportSubmitIdle>());
  });

  test('sending while in flight, then sent with the report', () async {
    final (ProviderContainer c, FakeContentReportRepository repo) =
        _container();
    repo.gate = Completer<void>();
    final Future<void> f = c
        .read(reportControllerProvider.notifier)
        .submit(_req);
    expect(c.read(reportControllerProvider), isA<ReportSubmitSending>());

    // A second submit while sending is ignored.
    await c.read(reportControllerProvider.notifier).submit(_req);
    expect(repo.requests, hasLength(1));

    repo.gate?.complete();
    await f;
    final ReportSubmitState s = c.read(reportControllerProvider);
    expect(s, isA<ReportSubmitSent>());
    expect((s as ReportSubmitSent).report.status, 'OPEN');
    expect(repo.requests.single, _req);
  });

  test('429 → error(rateLimited)', () async {
    final (ProviderContainer c, FakeContentReportRepository repo) =
        _container();
    repo.nextFailure = const ServerFailure(statusCode: 429);
    await c.read(reportControllerProvider.notifier).submit(_req);
    final ReportSubmitState s = c.read(reportControllerProvider);
    expect(s, isA<ReportSubmitError>());
    expect((s as ReportSubmitError).kind, ReportErrorKind.rateLimited);
  });

  test('404 / 5xx / network → error(generic)', () async {
    for (final Failure f in <Failure>[
      const NotFoundFailure(),
      const ServerFailure(statusCode: 500),
      const NetworkFailure(),
    ]) {
      final (ProviderContainer c, FakeContentReportRepository repo) =
          _container();
      repo.nextFailure = f;
      await c.read(reportControllerProvider.notifier).submit(_req);
      final ReportSubmitState s = c.read(reportControllerProvider);
      expect(
        (s as ReportSubmitError).kind,
        ReportErrorKind.generic,
        reason: '$f',
      );
      expect(s.failure, same(f));
    }
  });

  // Security LOW-3: a throw that is NOT a `Failure` (mapper bug, TypeError)
  // must still end the submit — never leave the sheet on its spinner.
  test('non-Failure throw → error(generic) wrapping UnknownFailure', () async {
    final (ProviderContainer c, FakeContentReportRepository repo) =
        _container();
    final StateError cause = StateError('mapper bug');
    repo.nextError = cause;
    await c.read(reportControllerProvider.notifier).submit(_req);
    final ReportSubmitState s = c.read(reportControllerProvider);
    expect(s, isA<ReportSubmitError>());
    expect((s as ReportSubmitError).kind, ReportErrorKind.generic);
    expect(s.failure, isA<UnknownFailure>());
    expect(s.failure.cause, same(cause));
  });

  test('reset clears an error back to idle; no-op otherwise', () async {
    final (ProviderContainer c, FakeContentReportRepository repo) =
        _container();
    c.read(reportControllerProvider.notifier).reset();
    expect(c.read(reportControllerProvider), isA<ReportSubmitIdle>());
    repo.nextFailure = const NotFoundFailure();
    await c.read(reportControllerProvider.notifier).submit(_req);
    c.read(reportControllerProvider.notifier).reset();
    expect(c.read(reportControllerProvider), isA<ReportSubmitIdle>());
  });

  test('reportErrorKindOf: only status 429 is rate limited', () {
    expect(
      reportErrorKindOf(const ServerFailure(statusCode: 429)),
      ReportErrorKind.rateLimited,
    );
    expect(
      reportErrorKindOf(const ServerFailure(statusCode: 503)),
      ReportErrorKind.generic,
    );
    expect(reportErrorKindOf(const ServerFailure()), ReportErrorKind.generic);
  });
}
