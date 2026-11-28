// M545 (CLI-60, REV-44 / REV-D10 / REV-13, MOD-41) — E2E: the anonymous
// provider comments about a client on «Рейтинг клієнта».
//
//   (a) SALON_OWNER: «Клієнти» → registered card → rating chip → «Коментарі»
//       lists every comment anonymously (no avatar, no author), with the visit
//       month; the viewer's own row says «Ваш коментар» and has a «⋮» (delete);
//   (b) the «⋮» on another provider's comment → report sheet → the request is
//       {CLIENT_REVIEW, that comment's reviewId};
//   (c) no comments → the section is hidden (the read DID happen);
//   (d) 25 comments → scrolling to the end requests page 1 exactly once and
//       renders the last row;
//   (e) INDEPENDENT_MASTER: a GUEST card reads `/masters/me/clients/guests/
//       {id}/comments` and lists the comment;
//   (f) REV-13: a CLIENT on «Мій рейтинг» never calls any `/comments` path;
//   (g) M572 / REV-45 / REV-43: INDEPENDENT_MASTER deletes the OWN comment →
//       confirm → the row leaves, «Оцінку видалено» shows, the average and
//       count move (also after re-opening the screen), the booking detail
//       offers «Залишити відгук про клієнта» again and re-rating succeeds.
//
// REAL router, REAL `HttpClientRepository` + generated models over the stubbed
// Dio (`FakeBackend.wireClientCard` serves `…/comments`); only the report seam
// is the contract-enforcing `FakeContentReportRepository`, as in
// `ugc_report_content_flow_test.dart`. Every request path is captured by a
// test-local interceptor on `fb.dio`, so (f) sees a stray `/comments` call
// even on a path the fake never routes.
//
// FINDERS: keys; texts only for fixture data or values built from the app's
// own l10n / `formatCommentVisitMonth`.
//
// NO PATROL FLOW: no OS permission dialog, deep link, notification, WebView or
// biometric (mobile-qa explicit statement).
//
// Runs headless: `flutter test integration_test/client_rating_comments_flow_test.dart
// -d flutter-tester`.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_client_feedback_screen.dart';
import 'package:beautica_mobile/features/clients/domain/client_review_comment.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/client_rating_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/clients_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/delete_client_rating_dialog.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/rating_body.dart';
import 'package:beautica_mobile/features/moderation/data/content_report_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/report_sheet.dart';
import 'package:beautica_mobile/features/rating/presentation/my_rating_screen.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/review_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/features/moderation/support/fake_content_report_repository.dart';
import '../test/helpers/overflow_guard.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('uk'));

const String _kSalonId = 'salon-owner-1';
const String _kUser = 'u-oksana';
const String _kGuest = 'b-guest-comments';

/// A B565 `ClientReviewCommentResponse` row.
Map<String, dynamic> _row(
  String id, {
  bool own = false,
  int stars = 4,
  String month = '2026-05',
}) => <String, dynamic>{
  'reviewId': id,
  'visitMonth': month,
  'stars': stars,
  'comment': 'Текст $id',
  'own': own,
};

Map<String, dynamic> _card(String id, {required bool guest}) =>
    <String, dynamic>{
      'kind': guest ? 'GUEST' : 'REGISTERED',
      if (guest) 'guestBookingId': id else 'userId': id,
      'displayName': 'Оксана Мельник',
      'phone': '+380671234567',
      'blocked': false,
      'ratingAvg': 4.5,
      'ratingCount': 2,
      'ratingDistribution': <Map<String, int>>[
        <String, int>{'rating': 5, 'count': 1},
        <String, int>{'rating': 4, 'count': 1},
      ],
    };

/// One client row + card for [id] with [comments], then wires the routes.
void _seed(
  FakeBackend fb,
  String id, {
  required bool guest,
  List<Map<String, dynamic>> comments = const <Map<String, dynamic>>[],
}) {
  fb.clientRows
    ..clear()
    ..add(<String, dynamic>{
      'kind': guest ? 'GUEST' : 'REGISTERED',
      if (guest) 'guestBookingId': id else 'userId': id,
      'displayName': 'Оксана Мельник',
      'lastVisitAt': '2026-06-01T10:00:00Z',
      'completedVisits': 2,
      'ratingAvg': 4.5,
      'ratingCount': 2,
      'blocked': false,
    });
  fb.clientCards
    ..clear()
    ..[id] = _card(id, guest: guest);
  fb.clientVisits
    ..clear()
    ..[id] = <Map<String, dynamic>>[];
  fb.clientComments
    ..clear()
    ..[id] = comments;
  fb.wireClientCard();
}

/// Every request as `<path> page=<n>`, captured before the fake answers.
List<String> _recordRequests(FakeBackend fb) {
  final List<String> log = <String>[];
  fb.dio.interceptors.insert(
    0,
    InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        log.add('${o.path} page=${o.queryParameters['page']}');
        h.next(o);
      },
    ),
  );
  return log;
}

Iterable<String> _commentCalls(List<String> log) =>
    log.where((String l) => l.contains('/comments'));

Finder _comment(String id) =>
    find.byKey(Key('${ClientCommentsSliver.keyPrefix}-$id'));
Finder _more(String id) =>
    find.byKey(ReviewCard.moreKey(ClientCommentsSliver.keyPrefix, id));

/// Non-empty texts inside [row], in paint order.
List<String> _texts(WidgetTester tester, Finder row) => <String>[
  for (final Text t in tester.widgetList<Text>(
    find.descendant(of: row, matching: find.byType(Text)),
  ))
    if ((t.data ?? '').isNotEmpty) t.data!,
];

String _month(int year, int month) => formatCommentVisitMonth(
  _l10n,
  ClientReviewComment(
    reviewId: 'x',
    visitYear: year,
    visitMonth: month,
    stars: 1,
    comment: 'x',
  ),
);

/// Boots as [role], opens «Клієнти» → the only row → its card → rating chip.
Future<GoRouter> _openRating(
  WidgetTester tester,
  FakeBackend fb,
  UserRole role,
  String tileKey,
  String id, {
  FakeContentReportRepository? reports,
}) async {
  final GoRouter router = await AppHarness.boot(
    tester,
    fb,
    extraOverrides: <Object>[
      contentReportRepositoryProvider.overrideWithValue(
        reports ?? FakeContentReportRepository(),
      ),
    ],
  );
  await AppHarness.loginAs(tester, fb, role);
  await AppHarness.settle(tester);
  await AppHarness.tapVisible(tester, find.byKey(Key(tileKey)));
  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(ClientsScreen.listKey),
    timeout: const Duration(seconds: 20),
  );
  await AppHarness.settle(tester);
  await AppHarness.tapVisible(tester, find.byKey(Key('client-row-$id')));
  await AppHarness.pumpUntilFound(tester, find.byKey(ClientCardScreen.nameKey));
  await AppHarness.settle(tester);
  await AppHarness.tapVisible(
    tester,
    find.byKey(ClientCardScreen.ratingChipKey),
  );
  await AppHarness.pumpUntilFound(tester, find.byKey(RatingBody.averageKey));
  await AppHarness.settle(tester);
  expect(find.byType(ClientRatingScreen), findsOneWidget);
  return router;
}

Future<void> _submitReport(WidgetTester tester) async {
  await AppHarness.tapVisible(
    tester,
    find.byKey(ReportSheet.reasonKey(ReportReason.offensive)),
  );
  await AppHarness.settle(tester);
  // By label: the CTA's AnimatedScale root swallows tap-by-key.
  await tester.ensureVisible(find.byKey(ReportSheet.submitKey));
  await AppHarness.settle(tester);
  await tester.tap(
    find.descendant(
      of: find.byKey(ReportSheet.submitKey),
      matching: find.text(_l10n.reportSubmit),
    ),
  );
  await AppHarness.settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('(a)+(b) SALON_OWNER: comments listed anonymously with the '
      'visit month; own row «Ваш коментар» without «⋮»; reporting another '
      'sends {CLIENT_REVIEW, its reviewId}', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..wireClientList();
      final List<String> log = _recordRequests(fb);
      _seed(
        fb,
        _kUser,
        guest: false,
        comments: <Map<String, dynamic>>[
          _row('c-own', own: true, stars: 5, month: '2026-06'),
          _row('c-other', stars: 2),
        ],
      );
      final FakeContentReportRepository reports = FakeContentReportRepository();
      final GoRouter router = await _openRating(
        tester,
        fb,
        UserRole.salonOwner,
        'salon-nav-tile-3',
        _kUser,
        reports: reports,
      );
      AppHarness.expectLocation(
        router,
        '/salons/$_kSalonId/clients/user/$_kUser/rating',
      );

      // The salon-scoped read, page 0.
      expect(_commentCalls(log), <String>[
        '/api/v1/salons/$_kSalonId/clients/users/$_kUser/comments page=0',
      ]);

      await AppHarness.pumpUntilFound(tester, _comment('c-other'));
      expect(find.byKey(ClientCommentsSliver.titleKey), findsOneWidget);
      expect(_comment('c-own'), findsOneWidget);
      // Anonymous (REV-D10): no avatar anywhere in the section, and the
      // other provider's row carries only month + text — no author.
      expect(find.byType(ReviewAvatar), findsNothing);
      expect(_texts(tester, _comment('c-other')), <String>[
        _month(2026, 5),
        'Текст c-other', // i18n-finder-ok: fixture comment text
      ]);
      expect(_texts(tester, _comment('c-own')), <String>[
        _month(2026, 6),
        _l10n.clientRatingOwnComment,
        'Текст c-own', // i18n-finder-ok: fixture comment text
      ]);
      expect(
        tester
            .widget<ReviewStarRow>(
              find.descendant(
                of: _comment('c-other'),
                matching: find.byType(ReviewStarRow),
              ),
            )
            .rating,
        2,
      );
      // E3 / M572 — own: «⋮» (the delete flow); another provider's: «⋮».
      expect(_more('c-own'), findsOneWidget);
      expect(_more('c-other'), findsOneWidget);

      // (b) MOD-41 — report the other comment.
      await AppHarness.tapVisible(tester, _more('c-other'));
      await AppHarness.settle(tester);
      expect(find.byType(ReportSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ReportSheet),
          matching: find.text(_l10n.reportSubjectClientComment),
        ),
        findsOneWidget,
      );
      await _submitReport(tester);

      expect(
        reports.requests.single,
        const ContentReportRequest(
          targetType: ReportTargetType.clientReview,
          targetId: 'c-other',
          reason: ReportReason.offensive,
        ),
      );
      expect(find.byType(ReportSheet), findsNothing);
      // Report once, ever: the reported row loses its «⋮».
      expect(_more('c-other'), findsNothing);
    });
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('(c) E1: no comments → the section is hidden (the read '
      'happened)', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..wireClientList();
      final List<String> log = _recordRequests(fb);
      _seed(fb, _kUser, guest: false);
      await _openRating(
        tester,
        fb,
        UserRole.salonOwner,
        'salon-nav-tile-3',
        _kUser,
      );

      expect(_commentCalls(log), hasLength(1));
      expect(find.byKey(ClientCommentsSliver.titleKey), findsNothing);
      expect(find.byType(ReviewCard), findsNothing);
      expect(find.byKey(RatingBody.privacyNoteKey), findsOneWidget);
    });
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('(d) 25 comments: scrolling to the end requests page 1 once and '
      'renders the last row', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..wireClientList();
      final List<String> log = _recordRequests(fb);
      _seed(
        fb,
        _kUser,
        guest: false,
        comments: <Map<String, dynamic>>[
          for (int i = 1; i <= 25; i++) _row('c$i'),
        ],
      );
      await _openRating(
        tester,
        fb,
        UserRole.salonOwner,
        'salon-nav-tile-3',
        _kUser,
      );
      await AppHarness.pumpUntilFound(tester, _comment('c1'));

      await tester.dragUntilVisible(
        _comment('c25'),
        find
            .descendant(
              of: find.byType(ClientRatingScreen),
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, -300),
      );
      await AppHarness.settle(tester);

      expect(_comment('c25'), findsOneWidget);
      final List<String> pages = _commentCalls(
        log,
      ).map((String l) => l.split(' ').last).toList();
      expect(pages, <String>['page=0', 'page=1']);
    });
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('(e) INDEPENDENT_MASTER: a GUEST card reads the master-scoped '
      'guest comments and lists them', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()..wireClientList();
      final List<String> log = _recordRequests(fb);
      _seed(
        fb,
        _kGuest,
        guest: true,
        comments: <Map<String, dynamic>>[_row('g-1', stars: 3)],
      );
      final GoRouter router = await _openRating(
        tester,
        fb,
        UserRole.independentMaster,
        'master-nav-tile-3',
        _kGuest,
      );
      AppHarness.expectLocation(
        router,
        '/master/clients/guest/$_kGuest/rating',
      );

      expect(_commentCalls(log), <String>[
        '/api/v1/masters/me/clients/guests/$_kGuest/comments page=0',
      ]);
      await AppHarness.pumpUntilFound(tester, _comment('g-1'));
      expect(_texts(tester, _comment('g-1')), <String>[
        _month(2026, 5),
        'Текст g-1', // i18n-finder-ok: fixture comment text
      ]);
      expect(_more('g-1'), findsOneWidget);
    });
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets(
    '(f) REV-13: a CLIENT on «Мій рейтинг» never calls /comments',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend()
          ..myRatingAvgRating = 4.6
          ..myRatingReviewCount = 5;
        final List<String> log = _recordRequests(fb);
        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.client);
        await AppHarness.settle(tester);

        unawaited(router.push(RouteNames.myRating));
        await AppHarness.pumpUntilFound(tester, find.byType(MyRatingScreen));
        await AppHarness.settle(tester);

        expect(
          log.where((String l) => l.startsWith('/api/v1/users/me/rating')),
          isNotEmpty,
          reason: 'the recorder sees the screen\'s own read',
        );
        expect(_commentCalls(log), isEmpty);
        expect(find.byKey(ClientCommentsSliver.titleKey), findsNothing);
      });
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  testWidgets(
    '(g) M572 INDEPENDENT_MASTER deletes the OWN comment: row gone + snack, '
    'average/count move (also on re-open), booking detail offers «Залишити '
    'відгук про клієнта» again and re-rating succeeds',
    (tester) async {
      await mockNetworkImagesFor(() async {
        const String ownId = '11111111-1111-4111-8111-111111111111';
        const String otherId = '22222222-2222-4222-8222-222222222222';
        final FakeBackend fb = FakeBackend()
          ..currentRole = UserRole.independentMaster
          ..bookingStatus = 'COMPLETED'
          // Already rated by this provider: the CTA is absent until the delete.
          ..bookingProviderCanReviewClient = false
          ..wireClientList();
        final List<String> log = _recordRequests(fb);
        _seed(
          fb,
          _kUser,
          guest: false,
          comments: <Map<String, dynamic>>[
            _row(ownId, own: true, stars: 5, month: '2026-06'),
            _row(otherId, stars: 4),
          ],
        );
        final GoRouter router = await _openRating(
          tester,
          fb,
          UserRole.independentMaster,
          'master-nav-tile-3',
          _kUser,
        );
        await AppHarness.pumpUntilFound(tester, _comment(ownId));
        String avg() =>
            tester.widget<Text>(find.byKey(RatingBody.averageKey)).data!;
        String count() =>
            tester.widget<Text>(find.byKey(RatingBody.countKey)).data!;
        expect(avg(), '4,5');
        expect(count(), _l10n.clientRatingCount(2));

        // «⋮» → confirm → DELETE with the exact review id.
        await AppHarness.tapVisible(tester, _more(ownId));
        await AppHarness.settle(tester);
        expect(find.byType(DeleteClientRatingDialog), findsOneWidget);
        await AppHarness.tapVisible(
          tester,
          find.byKey(DeleteClientRatingDialog.confirmKey),
        );
        await AppHarness.pumpUntilGone(tester, _comment(ownId));
        await AppHarness.settle(tester);

        expect(fb.deleteClientReviewCalls, 1);
        expect(fb.lastDeletedClientReviewId, ownId);
        expectVelvetSnack(
          _l10n.clientRatingDeleted,
          variant: VelvetSnackVariant.success,
        );
        expect(_comment(otherId), findsOneWidget);
        // The readout re-read the card without the deleted rating.
        await AppHarness.pumpUntilFound(tester, find.text('4,0'));
        expect(avg(), '4,0');
        expect(count(), _l10n.clientRatingCount(1));
        await pumpPastVelvetSnack(tester);

        // Re-open the rating screen: a real reload agrees.
        final int commentReads = _commentCalls(log).length;
        await AppHarness.tapVisible(
          tester,
          find.byKey(ClientRatingScreen.backKey),
        );
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(ClientCardScreen.ratingChipKey),
        );
        await AppHarness.tapVisible(
          tester,
          find.byKey(ClientCardScreen.ratingChipKey),
        );
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(RatingBody.averageKey),
        );
        await AppHarness.pumpUntilFound(tester, _comment(otherId));
        expect(_commentCalls(log).length, greaterThan(commentReads));
        expect(avg(), '4,0');
        expect(count(), _l10n.clientRatingCount(1));
        expect(_comment(ownId), findsNothing);

        // REV-43: the booking detail offers the CTA again.
        const Key cta = Key('booking-detail-leave-client-feedback');
        unawaited(router.push(RouteNames.masterBookingDetail('booking-1')));
        await AppHarness.settle(tester);
        await AppHarness.pumpUntilFound(tester, find.byKey(cta));
        expect(find.byType(BookingDetailScreen), findsOneWidget);

        // Re-rating succeeds: a real POST /client-reviews.
        await tester.tap(find.byKey(cta));
        await AppHarness.settle(tester);
        expect(find.byType(LeaveClientFeedbackScreen), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey<String>('review-star-4')));
        await AppHarness.settle(tester);
        await tester.tap(find.byKey(const Key('leave-client-feedback-submit')));
        await AppHarness.settle(tester);
        expect(fb.createClientReviewCalls, 1);
        expect(fb.lastClientReviewBookingId, 'booking-1');
        expect(fb.lastClientReviewRating, 4);
        expect(find.byType(LeaveClientFeedbackScreen), findsNothing);
        await pumpPastVelvetSnack(tester);
      });
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );

  testWidgets(
    '(h) M572 the booking detail stays MOUNTED under the rating screen: '
    'deleting the own comment re-reads it, so «Залишити відгук про клієнта» '
    'is back on pop without a re-open',
    (tester) async {
      await mockNetworkImagesFor(() async {
        const String ownId = '33333333-3333-4333-8333-333333333333';
        const Key cta = Key('booking-detail-leave-client-feedback');
        final FakeBackend fb = FakeBackend()
          ..currentRole = UserRole.independentMaster
          ..bookingStatus = 'COMPLETED'
          ..bookingProviderCanReviewClient = false
          ..bookingRegisteredClientId = _kUser
          ..wireClientList();
        _seed(
          fb,
          _kUser,
          guest: false,
          comments: <Map<String, dynamic>>[
            _row(ownId, own: true, stars: 5, month: '2026-06'),
          ],
        );
        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
        await AppHarness.settle(tester);

        // detail (mounted, no CTA) → client strip → card → rating.
        unawaited(router.push(RouteNames.masterBookingDetail('booking-1')));
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('booking-detail-client-strip')),
        );
        await AppHarness.settle(tester);
        expect(find.byKey(cta), findsNothing);
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('booking-detail-client-strip')),
        );
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(ClientCardScreen.ratingChipKey),
        );
        await AppHarness.settle(tester);
        await AppHarness.tapVisible(
          tester,
          find.byKey(ClientCardScreen.ratingChipKey),
        );
        await AppHarness.pumpUntilFound(tester, _comment(ownId));
        // The detail is still in the tree underneath (offstage).
        expect(
          find.byType(BookingDetailScreen, skipOffstage: false),
          findsOneWidget,
        );
        final int detailReads = fb.getBookingDetailCalls;

        await AppHarness.tapVisible(tester, _more(ownId));
        await AppHarness.settle(tester);
        await AppHarness.tapVisible(
          tester,
          find.byKey(DeleteClientRatingDialog.confirmKey),
        );
        await AppHarness.pumpUntilGone(tester, _comment(ownId));
        await AppHarness.settle(tester);
        expect(fb.deleteClientReviewCalls, 1);
        await pumpPastVelvetSnack(tester);

        await AppHarness.tapVisible(
          tester,
          find.byKey(ClientRatingScreen.backKey),
        );
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(ClientCardScreen.backKey),
        );
        await AppHarness.tapVisible(
          tester,
          find.byKey(ClientCardScreen.backKey),
        );
        await AppHarness.pumpUntilGone(tester, find.byType(ClientCardScreen));

        // Back on the SAME detail instance: it re-read and offers the CTA.
        expect(find.byType(BookingDetailScreen), findsOneWidget);
        await AppHarness.pumpUntilFound(tester, find.byKey(cta));
        expect(fb.getBookingDetailCalls, greaterThan(detailReads));
      });
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );
}
