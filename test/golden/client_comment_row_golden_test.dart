// M572 — pixel lock for the compact «Коментарі» row on «Рейтинг клієнта»
// (CLI-102) and the «Видалити оцінку й коментар?» confirm.
//
// NEW baselines (no existing image moved by this file):
//   • client_comment_row_own_360_1x        — own: month + «Ваш коментар» tag + «⋮»
//   • client_comment_row_other_360_1x      — another provider: stars + month + «⋮»
//   • client_comment_row_long_collapsed_360_1x — 3-line clamp + «Ще»
//   • client_comment_row_long_expanded_360_1x  — after «Ще»: full text, no link
//   • client_comment_row_reported_360_1x   — already reported: no «⋮», same height
//   • client_comment_delete_dialog_360_1x  — the confirm (destructive tone)
//
// Preview parity: `docs/signup-designs/ClientCommentCard/` at 360 dp, 1.0×
// (own / other row 92 dp, one-line row 74 dp). The own row is the one whose
// card shadows must not be clipped by the collapse wrapper: every capture
// leaves a gutter around the card, so a clipped shadow shows as a hard edge.

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/domain/client_review_comment.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/delete_client_rating_dialog.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/rating_body.dart';
import 'package:beautica_mobile/features/moderation/data/content_report_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/review_card.dart';
import 'package:alchemist/alchemist.dart' show PumpAction;
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' show WidgetTester, find;

import '../features/moderation/support/fake_content_report_repository.dart';
import '../helpers/fakes/fake_notification_repository.dart' show FixedRoleAuth;
import 'helpers/golden_pump.dart';

const double _width = 360;
const Size _rowCapture = Size(_width, 220);

const ClientListScope _scope = ClientListScope.me();
const ClientRef _client = ClientRef.registered('u1');

class _Comments implements ClientCommentsRepository {
  const _Comments(this.items);

  final List<ClientReviewComment> items;

  @override
  Future<void> deleteOwnReview(String reviewId) async {}

  @override
  Future<PageResponse<ClientReviewComment>> getComments(
    ClientListScope scope,
    ClientRef client, {
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) async => PageResponse<ClientReviewComment>(
    items: items,
    page: 0,
    totalPages: 1,
    totalElements: items.length,
  );
}

const String _longText =
    'Двічі скасувала запис за годину до візиту, попереджайте про '
    'передоплату. Також запізнилась на двадцять хвилин без дзвінка, '
    'тож наступний клієнт чекав. Радимо узгоджувати час заздалегідь '
    'і нагадувати про візит за день.';

ClientReviewComment _comment({
  String id = 'r1',
  int stars = 5,
  String text = 'Приходить вчасно, приємна в спілкуванні.',
  bool own = false,
}) => ClientReviewComment(
  reviewId: id,
  visitYear: 2026,
  visitMonth: 11,
  stars: stars,
  comment: text,
  own: own,
);

List<Object> _overrides(
  ClientReviewComment c, {
  Set<ReportedTarget> reported = const <ReportedTarget>{},
}) => <Object>[
  authProvider.overrideWith(() => FixedRoleAuth(UserRole.independentMaster)),
  clientCommentsRepositoryProvider.overrideWithValue(
    _Comments(<ClientReviewComment>[c]),
  ),
  contentReportRepositoryProvider.overrideWithValue(
    FakeContentReportRepository(preReported: reported),
  ),
];

/// The production sliver in a scroll view with the screen's 16 dp gutters.
Widget _rows() => const Padding(
  padding: EdgeInsets.symmetric(horizontal: 16),
  child: CustomScrollView(
    slivers: <Widget>[ClientCommentsSliver(scope: _scope, client: _client)],
  ),
);

Future<void> _expandThenSettle(WidgetTester tester) async {
  await onlyPumpAndSettle(tester);
  await tester.tap(
    find.byKey(ReviewCard.expandKey(ClientCommentsSliver.keyPrefix, 'r1')),
  );
  await tester.pumpAndSettle();
}

void main() {
  void row(
    String name,
    ClientReviewComment c, {
    Set<ReportedTarget> reported = const <ReportedTarget>{},
    PumpAction pumpBeforeTest = onlyPumpAndSettle,
    double scale = 1.0,
  }) => goldenTest(
    'client comment row — $name ($scale×)',
    fileName: 'client_comment_row_${name}_360_${scale == 1.0 ? '1x' : '1_3x'}',
    constraints: BoxConstraints.tight(
      scale == 1.0 ? _rowCapture : const Size(_width, 300),
    ),
    textScaleFactor: scale,
    pumpBeforeTest: pumpBeforeTest,
    pumpWidget: goldenPumpWidget(
      width: _width,
      overrides: _overrides(c, reported: reported),
    ),
    builder: _rows,
  );

  row('own', _comment(own: true));
  row('other', _comment(stars: 2));
  row('long_collapsed', _comment(stars: 2, text: _longText));
  row(
    'long_expanded',
    _comment(stars: 2, text: _longText),
    pumpBeforeTest: _expandThenSettle,
  );
  // 1.3× text scale (the M571 preview measures it too).
  row('own', _comment(own: true), scale: 1.3);
  row('long_collapsed', _comment(stars: 2, text: _longText), scale: 1.3);
  row(
    'long_expanded',
    _comment(stars: 2, text: _longText),
    pumpBeforeTest: _expandThenSettle,
    scale: 1.3,
  );
  row(
    'reported',
    _comment(stars: 2),
    reported: <ReportedTarget>{(type: ReportTargetType.clientReview, id: 'r1')},
  );

  goldenTest(
    'client comment — delete confirm',
    fileName: 'client_comment_delete_dialog_360_1x',
    constraints: BoxConstraints.tight(const Size(_width, kGoldenHeight)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: _width),
    builder: () => const Align(
      alignment: Alignment.topCenter,
      child: DeleteClientRatingDialog(),
    ),
  );
}
