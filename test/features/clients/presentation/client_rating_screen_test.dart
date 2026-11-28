// M510 — «Рейтинг клієнта» (CLI-60): average, count, the 5→1 bars matching the
// distribution and the privacy note — NO «Ваші оцінки» section and no
// own-ratings read (CLI-D07, 2026-11-21), and NO comment text, ever (REV-D10).
// MOD-39 — the header avatar carries the CLIENT_PROFILE viewer report for a
// registered client.
// M545 (CLI-60, REV-44, MOD-41) — the anonymous «Коментарі» section: hidden
// when empty, the shared ReviewCard row with no author, «Ваш коментар» on
// own, the visit month, load more on scroll, inline retry, «⋮» report.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/clients/application/client_list_controller.dart';
import 'package:beautica_mobile/features/booking/application/pending_booking_actions_count.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_card.dart';
import 'package:beautica_mobile/features/clients/domain/client_review_comment.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/domain/client_visit.dart';
import 'package:beautica_mobile/features/clients/presentation/client_rating_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_avatar.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/delete_client_rating_dialog.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/rating_body.dart';
import 'package:beautica_mobile/features/moderation/data/content_report_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/report_sheet.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/review_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/public_profile_skeleton.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_notification_repository.dart';
import '../../moderation/support/fake_content_report_repository.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/route_pump.dart';

const ClientListScope _scope = ClientListScope.me();
const ClientRef _client = ClientRef.registered('u-1');

/// A comment the backend must never send; if any code path ever rendered a
/// field like it, this string would show.
const String _secretComment = 'ВЛАСНИЙ КОМЕНТАР ПРО КЛІЄНТА';

class _Repo implements ClientRepository {
  _Repo({required this.card});

  final ClientCard card;

  int cardCalls = 0;
  int listCalls = 0;

  /// When set, the card request throws it.
  Failure? cardFailure;

  /// When set, the card request waits on this (cold-open ordering tests).
  Completer<void>? cardGate;

  @override
  Future<ClientCard> getCard(
    ClientListScope scope,
    ClientRef client, {
    CancelToken? cancelToken,
  }) async {
    cardCalls++;
    final Completer<void>? gate = cardGate;
    if (gate != null) await gate.future;
    final Failure? f = cardFailure;
    if (f != null) throw f;
    return card;
  }

  @override
  Future<PageResponse<ClientVisit>> getVisits(
    ClientListScope scope,
    ClientRef client, {
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<PageResponse<ClientSummary>> list(
    ClientListScope scope, {
    String? q,
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) async {
    listCalls++;
    return PageResponse<ClientSummary>(
      items: const <ClientSummary>[],
      page: page,
      totalPages: 1,
      totalElements: 0,
    );
  }

  @override
  Future<void> removeFromList(ClientListScope scope, ClientRef client) =>
      throw UnimplementedError();

  @override
  Future<void> restoreToList(ClientListScope scope, ClientRef client) =>
      throw UnimplementedError();
}

/// M545 — the comments seam: [all] served in pages of [kClientPageSize];
/// a page listed in [failPages] throws a [NetworkFailure] once.
class _Comments implements ClientCommentsRepository {
  final List<String> deleted = <String>[];
  Object? deleteError;

  @override
  Future<void> deleteOwnReview(String reviewId) async {
    deleted.add(reviewId);
    final Object? e = deleteError;
    // The server's truth after the call: gone on success AND on a 404.
    if (e == null || e is NotFoundFailure) {
      all = all
          .where((ClientReviewComment c) => c.reviewId != reviewId)
          .toList();
    }
    if (e != null) throw e;
  }

  _Comments([this.all = const <ClientReviewComment>[], this.serveSize]);

  List<ClientReviewComment> all;

  /// Overrides the requested page size (a short page that fits the viewport).
  final int? serveSize;
  final Set<int> failPages = <int>{};
  final List<int> pages = <int>[];

  @override
  Future<PageResponse<ClientReviewComment>> getComments(
    ClientListScope scope,
    ClientRef client, {
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) async {
    pages.add(page);
    if (failPages.remove(page)) throw const NetworkFailure();
    size = serveSize ?? size;
    final int from = page * size;
    final int to = (from + size).clamp(0, all.length);
    return PageResponse<ClientReviewComment>(
      items: from >= all.length
          ? const <ClientReviewComment>[]
          : all.sublist(from, to),
      page: page,
      totalPages: (all.length / size).ceil(),
      totalElements: all.length,
    );
  }
}

ClientReviewComment _comment(int i, {bool own = false, int stars = 4}) =>
    ClientReviewComment(
      reviewId: 'r-$i',
      visitYear: 2026,
      visitMonth: 11,
      stars: stars,
      comment: 'Коментар $i',
      own: own,
    );

const ClientCard _rated = ClientCard(
  ref: _client,
  displayName: 'Оксана Мельник',
  ratingAvg: 4.9,
  ratingCount: 12,
  ratingDistribution: <int>[10, 2, 0, 0, 0],
);

Future<_Repo> _pump(
  WidgetTester tester,
  _Repo repo, {
  double width = 360,
  double? textScale,
  bool settle = true,
  ClientRef client = _client,
  UserRole role = UserRole.independentMaster,
  _Comments? comments,
  FakeContentReportRepository? reports,
  void Function(GoRouter router)? onRouter,
  List<Object> extraOverrides = const <Object>[],
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (textScale != null) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            ClientRatingScreen(scope: _scope, client: client),
      ),
      GoRoute(
        path: '/away',
        builder: (BuildContext context, GoRouterState state) =>
            const SizedBox.shrink(),
      ),
    ],
  );
  addTearDown(router.dispose);
  onRouter?.call(router);
  await tester.pumpRoutedApp(
    router,
    overrides: <Object>[
      clientRepositoryProvider.overrideWithValue(repo),
      clientCommentsRepositoryProvider.overrideWithValue(
        comments ?? _Comments(),
      ),
      contentReportRepositoryProvider.overrideWithValue(
        reports ?? FakeContentReportRepository(),
      ),
      authProvider.overrideWith(() => FixedRoleAuth(role)),
      ...extraOverrides,
    ],
    retry: (_, _) => null,
  );
  if (!settle) return repo;
  await tester.pump();
  await pumpUntilGone(tester, find.byType(CircularProgressIndicator));
  await tester.pumpAndSettle();
  return repo;
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ClientRatingScreen)));

/// The fill fraction a distribution bar settled at (its gradient child's
/// widthFactor), 0 when empty.
double _fill(WidgetTester tester, int stars) {
  final Finder f = find.descendant(
    of: find.byKey(RatingBody.barKey(stars)),
    matching: find.byType(FractionallySizedBox),
  );
  return tester.widget<FractionallySizedBox>(f).widthFactor!;
}

void main() {
  testWidgets('cold open reads the card only (CLI-60: no own-ratings read '
      'exists on the repository any more)', (tester) async {
    final Completer<void> gate = Completer<void>();
    final _Repo repo = _Repo(card: _rated)..cardGate = gate;
    await _pump(tester, repo, settle: false);
    await tester.pump();
    expect(repo.cardCalls, 1);
    gate.complete();
    await pumpUntilGone(tester, find.byType(CircularProgressIndicator));
    await tester.pumpAndSettle();
    expect(find.byKey(ClientRatingScreen.nameKey), findsOneWidget);
  });

  testWidgets('average, count, five bars matching the distribution', (
    tester,
  ) async {
    await _pump(tester, _Repo(card: _rated));
    expect(tester.widget<Text>(find.byKey(RatingBody.averageKey)).data, '4,9');
    expect(
      tester.widget<Text>(find.byKey(RatingBody.countKey)).data,
      _l10n(tester).clientRatingCount(12),
    );
    // 5→1 → 10, 2, 0, 0, 0 of 12.
    expect(_fill(tester, 5), closeTo(10 / 12, 1e-9));
    expect(_fill(tester, 4), closeTo(2 / 12, 1e-9));
    for (final int s in <int>[3, 2, 1]) {
      expect(_fill(tester, s), 0);
    }
    // The fill is actually PAINTED (a child-less box has no height).
    final Finder fill5 = find.descendant(
      of: find.byKey(RatingBody.barKey(5)),
      matching: find.byType(FractionallySizedBox),
    );
    expect(tester.getSize(fill5).height, greaterThan(0));
    expect(tester.getSize(fill5).width, greaterThan(0));
    for (final int s in <int>[5, 4, 3, 2, 1]) {
      expect(find.byKey(RatingBody.barKey(s)), findsOneWidget);
    }
    // i18n-finder-ok: asserts the exact data value
    expect(find.text('Оксана Мельник'), findsOneWidget);
  });

  // M548 / REV-D04 — a guest is rated by phone and shows the server's own
  // values; there is no client-side "guest ⇒ unrated" shortcut.
  testWidgets('a rated guest shows the backend average, count and bars', (
    tester,
  ) async {
    const ClientRef guest = ClientRef.guest('b-1');
    await _pump(
      tester,
      _Repo(
        card: const ClientCard(
          ref: guest,
          ratingAvg: 4.3,
          ratingCount: 3,
          ratingDistribution: <int>[2, 0, 1, 0, 0],
        ),
      ),
      client: guest,
    );
    expect(tester.widget<Text>(find.byKey(RatingBody.averageKey)).data, '4,3');
    expect(
      tester.widget<Text>(find.byKey(RatingBody.countKey)).data,
      _l10n(tester).clientRatingCount(3),
    );
    expect(_fill(tester, 5), closeTo(2 / 3, 1e-9));
    expect(_fill(tester, 3), closeTo(1 / 3, 1e-9));
  });

  testWidgets('no «Ваші оцінки» section (CLI-60, CLI-D07)', (tester) async {
    await _pump(tester, _Repo(card: _rated));
    // i18n-finder-ok: the removed section's heading must not render
    expect(find.text('Ваші оцінки'), findsNothing);
    // i18n-finder-ok: nor its removed empty line
    expect(find.text('Ви ще не оцінювали цього клієнта.'), findsNothing);
    // Summary card + privacy note only: nothing scrolls past the note.
    expect(find.byKey(RatingBody.privacyNoteKey), findsOneWidget);
  });

  testWidgets('MOD-39: registered client avatar carries the viewer report', (
    tester,
  ) async {
    await _pump(tester, _Repo(card: _rated));
    expect(
      tester.widget<ClientAvatar>(find.byType(ClientAvatar)).previewReport,
      isNotNull,
    );
  });

  testWidgets('MOD-39: a guest avatar carries no viewer report', (
    tester,
  ) async {
    const ClientRef guest = ClientRef.guest('b-1');
    await _pump(
      tester,
      _Repo(
        card: const ClientCard(ref: guest, displayName: 'Гостя'),
      ),
      client: guest,
    );
    expect(
      tester.widget<ClientAvatar>(find.byType(ClientAvatar)).previewReport,
      isNull,
    );
  });

  testWidgets('the privacy note is shown and no comment text appears', (
    tester,
  ) async {
    await _pump(tester, _Repo(card: _rated));
    expect(find.byKey(RatingBody.privacyNoteKey), findsOneWidget);
    expect(find.text(_l10n(tester).clientRatingPrivacyNote), findsOneWidget);
    expect(find.textContaining(_secretComment), findsNothing);
  });

  testWidgets('unrated client: «—», no count, zero bars', (tester) async {
    await _pump(
      tester,
      _Repo(
        card: const ClientCard(ref: _client, displayName: 'Ірина'),
      ),
    );
    expect(tester.widget<Text>(find.byKey(RatingBody.averageKey)).data, '—');
    expect(
      tester.widget<Text>(find.byKey(RatingBody.countKey)).data,
      _l10n(tester).clientRatingEmpty,
    );
    for (final int s in <int>[5, 4, 3, 2, 1]) {
      expect(_fill(tester, s), 0);
    }
  });

  testWidgets('loading → the profile skeleton, then the readout', (
    tester,
  ) async {
    final Completer<void> gate = Completer<void>();
    await _pump(tester, _Repo(card: _rated)..cardGate = gate, settle: false);
    await tester.pump();
    expect(find.byType(PublicProfileSkeleton), findsOneWidget);
    expect(find.byKey(RatingBody.averageKey), findsNothing);
    gate.complete();
    await pumpUntilGone(tester, find.byType(PublicProfileSkeleton));
    await tester.pumpAndSettle();
    expect(find.byKey(RatingBody.averageKey), findsOneWidget);
  });

  testWidgets('404 → «Клієнта не знайдено», no retry, no readout', (
    tester,
  ) async {
    await _pump(
      tester,
      _Repo(card: _rated)..cardFailure = const NotFoundFailure(),
    );
    expect(find.byKey(ClientRatingScreen.notFoundKey), findsOneWidget);
    expect(find.text(_l10n(tester).clientNotFound), findsOneWidget);
    expect(find.byKey(const Key('error_state_retry_button')), findsNothing);
    expect(find.byKey(RatingBody.averageKey), findsNothing);
    expect(find.byKey(ClientRatingScreen.backKey), findsOneWidget);
  });

  testWidgets('another card failure → retry that reloads the page', (
    tester,
  ) async {
    final _Repo repo = _Repo(card: _rated)
      ..cardFailure = const NetworkFailure();
    await _pump(tester, repo);
    expect(find.byKey(ClientRatingScreen.notFoundKey), findsNothing);
    expect(find.byKey(RatingBody.averageKey), findsNothing);
    repo.cardFailure = null;
    await tester.tap(find.byKey(const Key('error_state_retry_button')));
    await pumpUntilGone(tester, find.byType(PublicProfileSkeleton));
    await tester.pumpAndSettle();
    expect(repo.cardCalls, 2);
    expect(tester.widget<Text>(find.byKey(RatingBody.averageKey)).data, '4,9');
  });

  for (final double width in <double>[360, 414]) {
    for (final double scale in <double>[1.0, 1.3]) {
      testWidgets('layout ${width.toInt()} px × text $scale', (tester) async {
        await _pump(
          tester,
          _Repo(card: _rated),
          width: width,
          textScale: scale,
        );
        expect(find.byKey(RatingBody.averageKey), findsOneWidget);
      });
    }
  }

  group('M545 comments', () {
    Finder row(int i) => find.byKey(Key('client-comment-r-$i'));
    Finder more(int i) =>
        find.byKey(ReviewCard.moreKey(ClientCommentsSliver.keyPrefix, 'r-$i'));

    testWidgets('E1: no comments → the section is hidden', (tester) async {
      final _Comments comments = _Comments();
      await _pump(tester, _Repo(card: _rated), comments: comments);
      expect(comments.pages, <int>[0]);
      expect(find.byKey(ClientCommentsSliver.titleKey), findsNothing);
      expect(find.byType(ReviewCard), findsNothing);
      expect(find.byKey(RatingBody.privacyNoteKey), findsOneWidget);
    });

    testWidgets('the note reads the M545 text (CLI-60)', (tester) async {
      await _pump(tester, _Repo(card: _rated));
      expect(
        tester.widget<Text>(find.byKey(RatingBody.privacyNoteKey)).data,
        // i18n-finder-ok: the locked CLI-60 wording
        'Клієнт не бачить ці коментарі. Автор не показується.',
      );
    });

    testWidgets('one comment: stars, month, text — no author, avatar or date', (
      tester,
    ) async {
      await _pump(
        tester,
        _Repo(card: _rated),
        comments: _Comments(<ClientReviewComment>[_comment(1, stars: 3)]),
      );
      expect(find.byKey(ClientCommentsSliver.titleKey), findsOneWidget);
      expect(row(1), findsOneWidget);
      // i18n-finder-ok: the comment's own text
      expect(find.text('Коментар 1'), findsOneWidget);
      // i18n-finder-ok: the visit month, intl `LLLL y` in uk
      expect(find.text('листопад 2026'), findsOneWidget);
      expect(
        tester
            .widget<ReviewStarRow>(
              find.descendant(of: row(1), matching: find.byType(ReviewStarRow)),
            )
            .rating,
        3,
      );
      expect(find.byType(ReviewAvatar), findsNothing);
      expect(find.text(_l10n(tester).clientRatingOwnComment), findsNothing);
      // The name slot is empty: no author text anywhere in the row.
      final Iterable<String?> texts = tester
          .widgetList<Text>(
            find.descendant(of: row(1), matching: find.byType(Text)),
          )
          .map((Text t) => t.data);
      expect(texts.where((String? t) => t != null && t.isNotEmpty), <String>[
        'листопад 2026', // i18n-finder-ok: month
        'Коментар 1', // i18n-finder-ok: text
      ]);
      expect(more(1), findsOneWidget);
    });

    testWidgets('E3: own comment → «Ваш коментар» tag and a «⋮» (M572)', (
      tester,
    ) async {
      await _pump(
        tester,
        _Repo(card: _rated),
        comments: _Comments(<ClientReviewComment>[
          _comment(1, own: true),
          _comment(2),
        ]),
      );
      expect(
        find.descendant(
          of: row(1),
          matching: find.text(_l10n(tester).clientRatingOwnComment),
        ),
        findsOneWidget,
      );
      expect(more(1), findsOneWidget);
      expect(more(2), findsOneWidget);
    });

    testWidgets('«⋮» opens the report sheet for CLIENT_REVIEW + the review id '
        '(MOD-41)', (tester) async {
      await _pump(
        tester,
        _Repo(card: _rated),
        comments: _Comments(<ClientReviewComment>[_comment(7)]),
      );
      await tester.tap(more(7));
      await tester.pumpAndSettle();
      final ReportSheet sheet = tester.widget<ReportSheet>(
        find.byType(ReportSheet),
      );
      expect(sheet.targetType, ReportTargetType.clientReview);
      expect(sheet.targetId, 'r-7');
    });

    testWidgets('an already-reported comment shows no «⋮»', (tester) async {
      await _pump(
        tester,
        _Repo(card: _rated),
        comments: _Comments(<ClientReviewComment>[_comment(1), _comment(2)]),
        reports: FakeContentReportRepository(
          preReported: <ReportedTarget>{
            (type: ReportTargetType.clientReview, id: 'r-1'),
          },
        ),
      );
      expect(more(1), findsNothing);
      expect(more(2), findsOneWidget);
    });

    // ---- M572 (CLI-102, REV-45): delete own rating ------------------------

    Finder confirm() => find.byKey(DeleteClientRatingDialog.confirmKey);

    testWidgets('own «⋮» → confirm → deleteOwnReview, row gone, snack', (
      tester,
    ) async {
      final _Comments comments = _Comments(<ClientReviewComment>[
        _comment(1, own: true),
        _comment(2),
      ]);
      await _pump(tester, _Repo(card: _rated), comments: comments);
      await tester.tap(more(1));
      await tester.pumpAndSettle();
      expect(find.byType(DeleteClientRatingDialog), findsOneWidget);
      expect(find.text(_l10n(tester).clientRatingDeleteBody), findsOneWidget);
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(comments.deleted, <String>['r-1']);
      expect(row(1), findsNothing);
      expect(row(2), findsOneWidget);
      expect(find.text(_l10n(tester).clientRatingDeleted), findsOneWidget);
    });

    testWidgets('an own row at rest has no ClipRect (its shadows are never '
        'clipped)', (tester) async {
      await _pump(
        tester,
        _Repo(card: _rated),
        comments: _Comments(<ClientReviewComment>[_comment(1, own: true)]),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('client-comment-row-r-1')),
          matching: find.byType(ClipRect),
        ),
        findsNothing,
      );
    });

    testWidgets('cancel → no delete call, row stays', (tester) async {
      final _Comments comments = _Comments(<ClientReviewComment>[
        _comment(1, own: true),
      ]);
      await _pump(tester, _Repo(card: _rated), comments: comments);
      await tester.tap(more(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(DeleteClientRatingDialog.cancelKey));
      await tester.pumpAndSettle();
      expect(comments.deleted, isEmpty);
      expect(row(1), findsOneWidget);
    });

    testWidgets('delete failure → the row comes back + an error snack', (
      tester,
    ) async {
      final _Comments comments = _Comments(<ClientReviewComment>[
        _comment(1, own: true),
        _comment(2),
      ])..deleteError = const NetworkFailure();
      await _pump(tester, _Repo(card: _rated), comments: comments);
      await tester.tap(more(1));
      await tester.pumpAndSettle();
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(comments.deleted, <String>['r-1']);
      expect(row(1), findsOneWidget);
      expect(find.text(_l10n(tester).clientRatingDeleted), findsNothing);
      expect(
        find.text(
          const NetworkFailure().userMessage(
            tester.element(find.byType(ClientRatingScreen)),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('404 → the row stays dropped, no success snack', (
      tester,
    ) async {
      final _Comments comments = _Comments(<ClientReviewComment>[
        _comment(1, own: true),
        _comment(2),
      ])..deleteError = const NotFoundFailure();
      await _pump(tester, _Repo(card: _rated), comments: comments);
      await tester.tap(more(1));
      await tester.pumpAndSettle();
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(row(1), findsNothing);
      expect(find.text(_l10n(tester).clientRatingDeleted), findsNothing);
    });

    testWidgets('reduced motion: the row leaves at once, no collapse timer', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final _Comments comments = _Comments(<ClientReviewComment>[
        _comment(1, own: true),
        _comment(2),
      ]);
      await _pump(tester, _Repo(card: _rated), comments: comments);
      await tester.tap(more(1));
      await tester.pumpAndSettle();
      await tester.tap(confirm());
      await tester.pump();
      await tester.pump();
      expect(row(1), findsNothing);
      expect(row(2), findsOneWidget);
    });

    testWidgets('the row collapses out (still mounted mid-collapse), then '
        'leaves', (tester) async {
      final _Comments comments = _Comments(<ClientReviewComment>[
        _comment(1, own: true),
        _comment(2),
      ]);
      await _pump(tester, _Repo(card: _rated), comments: comments);
      await tester.tap(more(1));
      await tester.pumpAndSettle();
      await tester.tap(confirm());
      await tester.pump(); // dialog closes, call resolves
      // fixed-wait-ok: a sample at the collapse's midpoint (140 of 280 ms) IS
      // the assertion — the row must still be mounted while it collapses.
      await tester.pump(const Duration(milliseconds: 140));
      expect(
        find.byKey(const ValueKey<String>('client-comment-row-r-1')),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('client-comment-row-r-1')),
        findsNothing,
      );
    });

    List<Object> countingOverrides(Map<String, int> builds) => <Object>[
      pendingBookingActionsCountProvider.overrideWith((ref, scope) async {
        builds['pending'] = (builds['pending'] ?? 0) + 1;
        return 0;
      }),
      bookingDetailProvider.overrideWith((ref, id) async {
        builds['detail'] = (builds['detail'] ?? 0) + 1;
        throw const NotFoundFailure();
      }),
    ];

    testWidgets('success re-reads card, list, pending count and booking '
        'detail — NOT the comments', (tester) async {
      final Map<String, int> builds = <String, int>{};
      final _Comments comments = _Comments(<ClientReviewComment>[
        _comment(1, own: true),
        _comment(2),
      ]);
      final _Repo repo = _Repo(card: _rated);
      await _pump(
        tester,
        repo,
        comments: comments,
        extraOverrides: countingOverrides(builds),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(ClientRatingScreen)),
        listen: false,
      );
      final List<ProviderSubscription<Object?>> subs =
          <ProviderSubscription<Object?>>[
            container.listen(
              pendingBookingActionsCountProvider(
                const PendingActionsScope.me(asMaster: true),
              ),
              (_, _) {},
            ),
            container.listen(bookingDetailProvider('b-1'), (_, _) {}),
            container.listen(clientListControllerProvider(_scope), (_, _) {}),
          ];
      addTearDown(() {
        for (final ProviderSubscription<Object?> sub in subs) {
          sub.close();
        }
      });
      await tester.pumpAndSettle();
      final int cardBefore = repo.cardCalls;
      final int pendingBefore = builds['pending'] ?? 0;
      final int detailBefore = builds['detail'] ?? 0;
      final int listBefore = repo.listCalls;

      await tester.tap(more(1));
      await tester.pumpAndSettle();
      await tester.tap(confirm());
      await tester.pumpAndSettle();

      expect(row(1), findsNothing);
      expect(repo.cardCalls, cardBefore + 1);
      expect(builds['pending'], pendingBefore + 1);
      expect(builds['detail'], detailBefore + 1);
      expect(repo.listCalls, listBefore + 1);
      expect(comments.pages, <int>[0]); // never refetched
    });

    testWidgets('the invalidations still happen when the screen is popped '
        'mid-collapse', (tester) async {
      final Map<String, int> builds = <String, int>{};
      late GoRouter router;
      final _Comments comments = _Comments(<ClientReviewComment>[
        _comment(1, own: true),
      ]);
      final _Repo repo = _Repo(card: _rated);
      await _pump(
        tester,
        repo,
        comments: comments,
        onRouter: (GoRouter r) => router = r,
        extraOverrides: countingOverrides(builds),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(ClientRatingScreen)),
        listen: false,
      );
      final ProviderSubscription<Object?> sub = container.listen(
        bookingDetailProvider('b-1'),
        (_, _) {},
      );
      addTearDown(sub.close);
      await tester.pumpAndSettle();
      final int cardBefore = repo.cardCalls;
      final int detailBefore = builds['detail'] ?? 0;

      await tester.tap(more(1));
      await tester.pumpAndSettle();
      await tester.tap(confirm());
      await tester.pump(); // the call resolves, the collapse starts
      router.go('/away'); // the screen leaves mid-collapse
      await tester.pumpAndSettle();

      expect(find.byType(ClientRatingScreen), findsNothing);
      expect(builds['detail'], detailBefore + 1);
      expect(comments.deleted, <String>['r-1']);
      // The card re-read happened although the screen left mid-collapse.
      expect(repo.cardCalls, cardBefore + 1);
    });

    testWidgets('an EXPANDED own comment stays expanded once the collapse '
        'starts (no re-clamp)', (tester) async {
      final String long = List<String>.filled(40, 'довгий').join(' ');
      await _pump(
        tester,
        _Repo(card: _rated),
        comments: _Comments(<ClientReviewComment>[
          ClientReviewComment(
            reviewId: 'r-1',
            visitYear: 2026,
            visitMonth: 11,
            stars: 5,
            comment: long,
            own: true,
          ),
        ]),
      );
      final Finder expand = find.byKey(
        ReviewCard.expandKey(ClientCommentsSliver.keyPrefix, 'r-1'),
      );
      final Finder text = find.byKey(
        ReviewCard.textKey(ClientCommentsSliver.keyPrefix, 'r-1'),
      );
      await tester.tap(expand);
      await tester.pumpAndSettle();
      expect(expand, findsNothing);

      await tester.tap(more(1));
      await tester.pumpAndSettle();
      await tester.tap(confirm());
      await tester.pump(); // the call resolves, the collapse starts
      // fixed-wait-ok: a sample early in the 280 ms collapse IS the assertion
      // — the row is mid-collapse and must not have re-clamped.
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        find.byKey(const ValueKey<String>('client-comment-row-r-1')),
        findsOneWidget,
      );
      expect(expand, findsNothing);
      expect(
        tester
            .widget<Text>(
              find.descendant(of: text, matching: find.byType(Text)).first,
            )
            .maxLines,
        isNull,
      );
    });

    testWidgets('a non-own row never offers delete (report sheet only)', (
      tester,
    ) async {
      final _Comments comments = _Comments(<ClientReviewComment>[_comment(3)]);
      await _pump(tester, _Repo(card: _rated), comments: comments);
      await tester.tap(more(3));
      await tester.pumpAndSettle();
      expect(find.byType(DeleteClientRatingDialog), findsNothing);
      expect(find.byType(ReportSheet), findsOneWidget);
      expect(comments.deleted, isEmpty);
    });

    testWidgets('a long comment clamps at 3 lines; «Ще» expands in place', (
      tester,
    ) async {
      final String long = List<String>.filled(40, 'довгий').join(' ');
      await _pump(
        tester,
        _Repo(card: _rated),
        comments: _Comments(<ClientReviewComment>[
          ClientReviewComment(
            reviewId: 'r-9',
            visitYear: 2026,
            visitMonth: 11,
            stars: 5,
            comment: long,
            own: false,
          ),
        ]),
      );
      final Finder expand = find.byKey(
        ReviewCard.expandKey(ClientCommentsSliver.keyPrefix, 'r-9'),
      );
      expect(expand, findsOneWidget);
      await tester.tap(expand);
      await tester.pumpAndSettle();
      expect(expand, findsNothing);
    });

    testWidgets('25 comments: page 2 loads on scroll', (tester) async {
      final _Comments comments = _Comments(<ClientReviewComment>[
        for (int i = 1; i <= 25; i++) _comment(i),
      ]);
      await _pump(tester, _Repo(card: _rated), comments: comments);
      expect(comments.pages, <int>[0]);
      await tester.dragUntilVisible(
        row(25),
        find.byType(Scrollable).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(comments.pages, <int>[0, 1]);
      expect(row(25), findsOneWidget);
    });

    testWidgets('page_0_that_fits_the_viewport_still_loads_page_1', (
      tester,
    ) async {
      final _Comments comments = _Comments(<ClientReviewComment>[
        _comment(1),
        _comment(2),
      ], 1);
      await _pump(tester, _Repo(card: _rated), comments: comments);
      // No scroll gesture: page 0 (one row) fits, so page 1 is requested
      // post-frame; page 1 is the last, so nothing more follows.
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .maxScrollExtent,
        0,
      );
      expect(comments.pages, <int>[0, 1]);
      expect(row(1), findsOneWidget);
      expect(row(2), findsOneWidget);
    });

    testWidgets('page 0 error → inline retry that reloads', (tester) async {
      final _Comments comments = _Comments(<ClientReviewComment>[_comment(1)])
        ..failPages.add(0);
      await _pump(tester, _Repo(card: _rated), comments: comments);
      expect(find.byKey(ClientCommentsSliver.retryKey), findsOneWidget);
      expect(row(1), findsNothing);
      await tester.tap(find.byKey(ClientCommentsSliver.retryKey));
      await tester.pumpAndSettle();
      expect(find.byKey(ClientCommentsSliver.retryKey), findsNothing);
      expect(row(1), findsOneWidget);
    });

    testWidgets('E5: page 2 error keeps the rows, retry appends', (
      tester,
    ) async {
      final _Comments comments = _Comments(<ClientReviewComment>[
        for (int i = 1; i <= 25; i++) _comment(i),
      ])..failPages.add(1);
      await _pump(tester, _Repo(card: _rated), comments: comments);
      final Finder retryMore = find.byKey(ClientCommentsSliver.retryMoreKey);
      await tester.dragUntilVisible(
        retryMore,
        find.byType(Scrollable).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(row(20), findsOneWidget);
      await tester.tap(retryMore);
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        row(25),
        find.byType(Scrollable).first,
        const Offset(0, -400),
      );
      expect(comments.pages, <int>[0, 1, 1]);
      expect(row(25), findsOneWidget);
    });
  });
}
