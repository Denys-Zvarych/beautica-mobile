// Phase 428 add-on — `myReportedTargetsProvider`: report once, ever.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/moderation/application/my_reported_targets_notifier.dart';
import 'package:beautica_mobile/features/moderation/data/content_report_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_content_report_repository.dart';

const ReportedTarget _r1 = (type: ReportTargetType.review, id: 'r1');
const ReportedTarget _p1 = (type: ReportTargetType.portfolioPhoto, id: 'p1');

AuthSession _session(String id) => AuthSession.authenticated(
  user: User(id: id, email: '$id@e.com', role: UserRole.client),
  accessToken: 't-$id',
);

class _MutableAuth extends AuthNotifier {
  _MutableAuth(this._initial);
  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;

  void set(AuthSession s) => state = AsyncData<AuthSession>(s);
}

Future<(ProviderContainer, FakeContentReportRepository)> _container(
  AuthSession session, {
  Set<ReportedTarget>? preReported,
}) async {
  final FakeContentReportRepository repo = FakeContentReportRepository(
    preReported: preReported,
  );
  final ProviderContainer c = ProviderContainer(
    overrides: <Object>[
      contentReportRepositoryProvider.overrideWithValue(repo),
      authProvider.overrideWith(() => _MutableAuth(session)),
    ].cast(),
  );
  addTearDown(c.dispose);
  await c.read(authProvider.future);
  return (c, repo);
}

void main() {
  test('loads GET /reports/mine ONCE per session', () async {
    final (ProviderContainer c, FakeContentReportRepository repo) =
        await _container(_session('u1'), preReported: <ReportedTarget>{_r1});

    expect(await c.read(myReportedTargetsProvider.future), <ReportedTarget>{
      _r1,
    });
    await c.read(myReportedTargetsProvider.future);
    expect(repo.mineCalls, 1);
  });

  test('signed out → empty, nothing fetched', () async {
    final (ProviderContainer c, FakeContentReportRepository repo) =
        await _container(const AuthSession.unauthenticated());
    expect(await c.read(myReportedTargetsProvider.future), isEmpty);
    expect(repo.mineCalls, 0);
  });

  test('a failed read fails OPEN (empty set, report entries stay)', () async {
    final (ProviderContainer c, FakeContentReportRepository repo) =
        await _container(_session('u1'));
    repo.nextMineFailure = const NetworkFailure();
    expect(await c.read(myReportedTargetsProvider.future), isEmpty);
  });

  test('markReported adds on top of the server set', () async {
    final (ProviderContainer c, _) = await _container(
      _session('u1'),
      preReported: <ReportedTarget>{_r1},
    );
    await c.read(myReportedTargetsProvider.future);
    c.read(myReportedTargetsProvider.notifier).markReported(_p1.type, _p1.id);
    expect(c.read(myReportedTargetsProvider).value, <ReportedTarget>{_r1, _p1});
  });

  test('markReported during the first read survives it', () async {
    // RED WHEN `build` stops merging `_localAdds`: the in-flight read lands
    // after the submit and wipes the local add.
    final (ProviderContainer c, _) = await _container(_session('u1'));
    final Future<Set<ReportedTarget>> first = c.read(
      myReportedTargetsProvider.future,
    );
    c.read(myReportedTargetsProvider.notifier).markReported(_p1.type, _p1.id);
    await first;
    await pumpEventQueue();
    expect(c.read(myReportedTargetsProvider).value, contains(_p1));
  });

  test(
    'a different user starts from THEIR server set (logout → login)',
    () async {
      final (ProviderContainer c, FakeContentReportRepository repo) =
          await _container(_session('u1'), preReported: <ReportedTarget>{_r1});
      c.listen(myReportedTargetsProvider, (_, _) {});
      await c.read(myReportedTargetsProvider.future);
      c.read(myReportedTargetsProvider.notifier).markReported(_p1.type, _p1.id);

      repo.preReported.clear();
      (c.read(authProvider.notifier) as _MutableAuth).set(_session('u2'));
      await pumpEventQueue();

      expect(await c.read(myReportedTargetsProvider.future), isEmpty);
      expect(repo.mineCalls, 2);
    },
  );
}
