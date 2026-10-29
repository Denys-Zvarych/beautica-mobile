// Phase 424 — ReportController: idle → sending → sent | error, with the D4
// failure classification (429 → rateLimited, everything else → generic).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/moderation/application/my_reported_targets_notifier.dart';
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

/// A signed-in session, so `myReportedTargetsProvider` (phase 428) behaves as
/// in the app: a submit can only happen once the session has resolved.
/// [switchTo] flips the session (logout → login of another user).
class _SignedIn extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(id: 'u1', email: 'u1@e.com', role: UserRole.client),
    accessToken: 't',
  );

  void switchTo(String id) => state = AsyncData<AuthSession>(
    AuthSession.authenticated(
      user: User(id: id, email: '$id@e.com', role: UserRole.client),
      accessToken: 't-$id',
    ),
  );
}

(ProviderContainer, FakeContentReportRepository) _container() {
  final FakeContentReportRepository repo = FakeContentReportRepository();
  final ProviderContainer c = ProviderContainer(
    overrides: [
      contentReportRepositoryProvider.overrideWithValue(repo),
      authProvider.overrideWith(_SignedIn.new),
    ],
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

  test('phase 428 — a successful submit marks the target reported', () async {
    // RED WHEN `submit` stops calling `markReported`: the «⋮» would stay.
    final (ProviderContainer c, _) = _container();
    await c.read(authProvider.future);
    await c.read(myReportedTargetsProvider.future);
    await c.read(reportControllerProvider.notifier).submit(_req);
    await pumpEventQueue();
    expect(
      c.read(myReportedTargetsProvider).value,
      contains((type: ReportTargetType.review, id: 'review-1')),
    );
  });

  test('phase 428 — a user change while the submit is in flight marks '
      'nothing in the NEW session', () async {
    // RED WHEN the submitter check is dropped: user u1's report lands in u2's
    // reported set and hides a «⋮» u2 never used.
    final (ProviderContainer c, FakeContentReportRepository repo) =
        _container();
    await c.read(authProvider.future);
    c.listen(myReportedTargetsProvider, (_, _) {});
    await c.read(myReportedTargetsProvider.future);
    repo.gate = Completer<void>();
    final Future<void> f = c
        .read(reportControllerProvider.notifier)
        .submit(_req);

    (c.read(authProvider.notifier) as _SignedIn).switchTo('u2');
    // Let u2's set load (the fake has stored nothing yet) before the
    // in-flight create lands.
    await pumpEventQueue();
    repo.gate?.complete();
    await f;
    await pumpEventQueue();

    expect(
      c.read(myReportedTargetsProvider).value ?? const <ReportedTarget>{},
      isNot(contains((type: ReportTargetType.review, id: 'review-1'))),
    );
  });

  test('phase 428 — a FAILED submit marks nothing', () async {
    final (ProviderContainer c, FakeContentReportRepository repo) =
        _container();
    repo.nextFailure = const ServerFailure(statusCode: 503);
    await c.read(reportControllerProvider.notifier).submit(_req);
    await pumpEventQueue();
    expect(c.read(myReportedTargetsProvider).value ?? const {}, isEmpty);
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
