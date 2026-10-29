// Phase 424 (Step 2.7 Rule 3b) — fake-backed E2E: reporting user content
// through the REAL router + screens + review/portfolio repositories. Only the
// report seam (`contentReportRepositoryProvider`) is overridden — with the
// contract-enforcing `FakeContentReportRepository` — so the journeys assert
// the exact request without depending on the HTTP repository (pinned on its
// own by `http_content_report_repository_test.dart`).
//
//   • CLIENT REVIEW on «Деталі запису»: the PROVIDER reports the client's
//     review of them; the request carries the review id off the wire, never
//     the booking id the card is keyed by.
//
//   • REVIEW: a CLIENT opens a public master profile → «Відгуки» tab → «⋮» on
//     a review → the sheet names THAT reviewer; «Інше» refuses an empty
//     comment (nothing sent); with a comment the request carries
//     {REVIEW, review id, OTHER, comment}; the sheet closes, the success snack
//     shows, the profile is still there.
//   • 429: the same journey against an exhausted rate limit → the
//     rate-limited banner, sheet stays open, no success snack.
//   • PHOTO: the public master's portfolio viewer → flag → the sheet opens
//     ABOVE the viewer with the photo subject; the request carries
//     {PORTFOLIO_PHOTO, the SHOWN photo's id}; the viewer stays open after.
//   • D3 negative: the master's OWN editor rail opens the viewer with no flag.
//
// Runs headless: `flutter test integration_test/ugc_report_content_flow_test.dart
// -d flutter-tester`.

import 'dart:async';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/client_review_section.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_profile_screen.dart';
import 'package:beautica_mobile/features/moderation/application/my_reported_targets_notifier.dart';
import 'package:beautica_mobile/features/moderation/data/content_report_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/report_sheet.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/review_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_photo_viewer.dart';
import 'package:beautica_mobile/shared/widgets/velvet_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/features/moderation/support/fake_content_report_repository.dart';
import '../test/helpers/fake_media_cache.dart';
import '../test/helpers/overflow_guard.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('uk'));

/// `FakeBackend._publicMasterReviews[0]` — master-aaa's newest public review.
const String _kReviewId = 'pub-r1';
const String _kReviewer = 'Марія Т.';

final Finder _sheet = find.byType(ReportSheet);
final Finder _banner = find.byKey(ReportSheet.bannerKey);
final Finder _viewer = find.byType(PortfolioPhotoViewer);

Finder _tile(String id) => find.byKey(Key('portfolio-photo-$id'));

/// The review's «⋮» tap target (the key sits on the hit target, so this tap
/// runs under `e2e_boot_policy`'s fatal hit-test warning).
final Finder _more = find.byKey(
  ReviewCard.moreKey('master-review', _kReviewId),
);

Future<GoRouter> _bootClientOnPublicMaster(
  WidgetTester tester,
  FakeBackend fb,
  FakeContentReportRepository repo,
) async {
  final GoRouter router = await AppHarness.boot(
    tester,
    fb,
    extraOverrides: <Object>[
      contentReportRepositoryProvider.overrideWithValue(repo),
    ],
  );
  await AppHarness.loginAs(tester, fb, UserRole.client);
  await AppHarness.settle(tester);
  unawaited(router.push(RouteNames.masterPublicProfile('master-aaa')));
  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(const Key('public-master-profile-about-tab')),
  );
  await AppHarness.settle(tester);
  expect(find.byType(PublicMasterProfileScreen), findsOneWidget);
  return router;
}

/// «Відгуки» tab → the review's «⋮» → the sheet for THAT review.
Future<void> _openReviewSheet(WidgetTester tester) async {
  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('public-master-profile-tab-2')),
  );
  await AppHarness.settle(tester);
  await AppHarness.pumpUntilFound(tester, _more);
  await AppHarness.tapVisible(tester, _more);
  await AppHarness.settle(tester);
  expect(_sheet, findsOneWidget);
  expect(
    find.descendant(
      of: _sheet,
      matching: find.text(_l10n.reportSubjectReview(_kReviewer)),
    ),
    findsOneWidget,
    reason: 'the sheet names the reviewer of the tapped review',
  );
}

Future<void> _pick(WidgetTester tester, ReportReason reason) async {
  await AppHarness.tapVisible(
    tester,
    find.byKey(ReportSheet.reasonKey(reason)),
  );
  await AppHarness.settle(tester);
}

/// The CTA by its label (the button's AnimatedScale root swallows
/// tap-by-key); scrolls it into the 800x600 viewport first.
Future<void> _submit(WidgetTester tester) async {
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

  testWidgets('CLIENT reports a public master review as «Інше»: an empty '
      'comment is refused, a real one is sent as {REVIEW, id, OTHER, '
      'comment}; the sheet closes with the success snack', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    final FakeContentReportRepository repo = FakeContentReportRepository();
    final GoRouter router = await _bootClientOnPublicMaster(tester, fb, repo);
    await _openReviewSheet(tester);

    await _pick(tester, ReportReason.other);
    expect(find.text(_l10n.reportCommentLabelRequired), findsOneWidget);
    await _submit(tester);
    expect(repo.requests, isEmpty, reason: '«Інше» without a comment');
    expect(find.text(_l10n.reportCommentRequiredError), findsOneWidget);
    expect(_sheet, findsOneWidget);

    await tester.enterText(
      find.byKey(ReportSheet.commentFieldKey),
      'Відгук не про цього майстра',
    );
    await AppHarness.settle(tester);
    await _submit(tester);

    expect(
      repo.requests.single,
      const ContentReportRequest(
        targetType: ReportTargetType.review,
        targetId: _kReviewId,
        reason: ReportReason.other,
        comment: 'Відгук не про цього майстра',
      ),
    );
    expect(repo.storedCount, 1);
    expect(_sheet, findsNothing);
    expect(
      find.descendant(
        of: find.byType(VelvetSnack),
        matching: find.text(_l10n.reportSent),
      ),
      findsOneWidget,
    );
    expect(find.byType(PublicMasterProfileScreen), findsOneWidget);
    AppHarness.expectLocation(
      router,
      RouteNames.masterPublicProfile('master-aaa'),
    );
    await pumpPastVelvetSnack(tester);
  }, timeout: const Timeout(Duration(seconds: 90)));

  // Phase 428 add-on — report once, ever: after a report the review's «⋮» is
  // gone, and stays gone when the reported set is re-read from the server
  // (the provider restarted, as on the next app start).
  testWidgets('CLIENT reports a review → its «⋮» disappears, and stays gone '
      'after the reported set reloads from GET /reports/mine', (tester) async {
    // RED WHEN the review list stops honouring the reported set, or the
    // submit stops marking it, or `GET /reports/mine` stops being read.
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    final FakeContentReportRepository repo = FakeContentReportRepository();
    await _bootClientOnPublicMaster(tester, fb, repo);
    await _openReviewSheet(tester);
    await _pick(tester, ReportReason.spam);
    await _submit(tester);
    expect(repo.requests, hasLength(1));
    expect(_sheet, findsNothing);
    await pumpPastVelvetSnack(tester);

    expect(_more, findsNothing, reason: 'hidden at once after the submit');
    expect(
      find.byKey(const Key('master-review-$_kReviewId')),
      findsOneWidget,
      reason: 'the review itself still renders',
    );

    // «Restart»: drop the session's set; it is re-read from the server.
    final int readsBefore = repo.mineCalls;
    ProviderScope.containerOf(
      tester.element(find.byType(PublicMasterProfileScreen)),
    ).invalidate(myReportedTargetsProvider);
    await AppHarness.pumpUntilCondition(
      tester,
      () => repo.mineCalls > readsBefore,
      description: 'GET /reports/mine to be re-read',
    );
    await AppHarness.settle(tester);

    expect(_more, findsNothing, reason: 'still hidden from the server set');
    expect(find.byKey(const Key('master-review-$_kReviewId')), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('429 (rate limit exhausted): the rate-limited banner shows, the '
      'sheet stays open, no success snack', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    final FakeContentReportRepository repo = FakeContentReportRepository(
      rateLimit: 0,
    );
    await _bootClientOnPublicMaster(tester, fb, repo);
    await _openReviewSheet(tester);

    await _pick(tester, ReportReason.spam);
    await _submit(tester);

    expect(repo.requests, hasLength(1));
    expect(repo.storedCount, 0);
    expect(_sheet, findsOneWidget);
    expect(_banner, findsOneWidget);
    expect(
      tester.widget<VelvetBanner>(_banner).message,
      _l10n.reportErrRateLimited,
    );
    expect(find.text(_l10n.reportErrRateLimited), findsOneWidget);
    expect(find.byType(VelvetSnack), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 90)));

  // Phase 424 D2 — the PROVIDER reports the client's review of them from
  // «Деталі запису». Drives the REAL `GET /bookings/{id}` → `BookingMapper`
  // (review id off the wire) → `ClientReviewSection(reportable: true)` chain;
  // the widget tier stubs `bookingDetailProvider` and cannot see the mapper.
  testWidgets('INDEPENDENT_MASTER reports the client\'s review on «Деталі '
      'запису»: the request is {REVIEW, the REVIEW id off the wire — never '
      'the booking id}', (tester) async {
    const String reviewId = 'client-authored-review-9';
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster
      ..bookingStatus = 'COMPLETED'
      ..bookingReviewByClient = <String, Object?>{
        'id': reviewId,
        'rating': 1,
        'comment': 'Майстер запізнився на годину.',
      };
    final FakeContentReportRepository repo = FakeContentReportRepository();
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      extraOverrides: <Object>[
        contentReportRepositoryProvider.overrideWithValue(repo),
      ],
    );
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
    unawaited(router.push(RouteNames.masterBookingDetail('booking-1')));
    await AppHarness.settle(tester);
    expect(find.byType(BookingDetailScreen), findsOneWidget);

    // The card (and its «⋮») is keyed by the BOOKING id; the report target is
    // the review's own id — the two must not be conflated.
    final Finder more = find.byKey(
      ReviewCard.moreKey(ClientReviewSection.keyPrefix, 'booking-1'),
    );
    await AppHarness.pumpUntilFound(tester, more);
    await AppHarness.tapVisible(tester, more);
    await AppHarness.settle(tester);
    expect(_sheet, findsOneWidget);
    expect(
      find.descendant(
        of: _sheet,
        matching: find.text(
          _l10n.reportSubjectReview(
            '${fb.clientFirstName} ${fb.clientLastName}',
          ),
        ),
      ),
      findsOneWidget,
    );

    await _pick(tester, ReportReason.offensive);
    await _submit(tester);

    expect(
      repo.requests.single,
      const ContentReportRequest(
        targetType: ReportTargetType.review,
        targetId: reviewId,
        reason: ReportReason.offensive,
      ),
    );
    expect(_sheet, findsNothing);
    expect(find.text(_l10n.reportSent), findsOneWidget);
    expect(find.byType(BookingDetailScreen), findsOneWidget);
    await pumpPastVelvetSnack(tester);
  }, timeout: const Timeout(Duration(seconds: 90)));

  group('portfolio photo', () {
    setUp(() {
      MediaConfig.debugAllowedHosts = <String>{'media.test'};
      debugMediaCacheManager = FakeMediaCacheManager(mediaLoaded);
    });
    tearDown(() {
      debugMediaCacheManager = null;
      MediaConfig.debugAllowedHosts = null;
    });

    testWidgets('CLIENT flags the SHOWN photo in the public master\'s viewer: '
        'the sheet opens above it with the photo subject; the request is '
        '{PORTFOLIO_PHOTO, shown id}; the viewer stays open', (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend(wirePortfolio: true)
          ..currentRole = UserRole.client;
        fb.publicMasterPortfolioRows
          ..add(fb.portfolioRow('MASTER', 'master-aaa')) // pf-1
          ..add(fb.portfolioRow('MASTER', 'master-aaa')); // pf-2
        final FakeContentReportRepository repo = FakeContentReportRepository();
        await _bootClientOnPublicMaster(tester, fb, repo);

        await tester.scrollUntilVisible(
          _tile('pf-2'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await AppHarness.settle(tester);
        await tester.tap(_tile('pf-2'));
        await AppHarness.settle(tester);
        expect(_viewer, findsOneWidget);
        expect(
          find.byKey(PortfolioPhotoViewer.pageKey('pf-2')).hitTestable(),
          findsOneWidget,
        );

        await tester.tap(find.byKey(PortfolioPhotoViewer.reportKey));
        await AppHarness.settle(tester);
        expect(_sheet.hitTestable(), findsOneWidget, reason: 'above viewer');
        expect(
          find.descendant(
            of: _sheet,
            matching: find.text(_l10n.reportSubjectPortfolioPhoto),
          ),
          findsOneWidget,
        );

        await _pick(tester, ReportReason.sexualContent);
        await _submit(tester);

        expect(
          repo.requests.single,
          const ContentReportRequest(
            targetType: ReportTargetType.portfolioPhoto,
            targetId: 'pf-2',
            reason: ReportReason.sexualContent,
          ),
        );
        expect(_sheet, findsNothing);
        expect(find.text(_l10n.reportSent), findsOneWidget);
        expect(_viewer, findsOneWidget, reason: 'reporting does not close it');
        await pumpPastVelvetSnack(tester);
      });
    }, timeout: const Timeout(Duration(seconds: 90)));

    testWidgets('D3 — INDEPENDENT_MASTER\'s OWN editor rail opens the viewer '
        'with NO report flag', (tester) async {
      final FakeBackend fb = FakeBackend(
        masterRowId: 'master-aaa',
        wirePortfolio: true,
      )..currentRole = UserRole.independentMaster;
      fb.masterPortfolioRows.add(fb.portfolioRow('MASTER', 'master-aaa'));
      await AppHarness.boot(
        tester,
        fb,
        extraOverrides: <Object>[
          contentReportRepositoryProvider.overrideWithValue(
            FakeContentReportRepository(),
          ),
        ],
      );
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await AppHarness.pumpUntilFound(tester, find.byType(MasterProfileScreen));
      await AppHarness.settle(tester);
      await tester.scrollUntilVisible(
        _tile('pf-1'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await AppHarness.settle(tester);
      // Body tap (bottom-left), clear of the top-right delete badge.
      await tester.tapAt(
        tester.getBottomLeft(_tile('pf-1')) + const Offset(12, -12),
      );
      await AppHarness.settle(tester);

      expect(_viewer, findsOneWidget);
      expect(find.byKey(PortfolioPhotoViewer.closeKey), findsOneWidget);
      expect(find.byKey(PortfolioPhotoViewer.reportKey), findsNothing);
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
