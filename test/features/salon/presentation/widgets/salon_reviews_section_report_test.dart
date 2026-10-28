// Phase 424 D2 — `SalonReviewsSection.reportable`: each salon review card's
// «⋮» opens the report sheet for THAT review (targetType REVIEW, its id, the
// masked reviewer name as subtitle); the default renders no affordance; the
// viewer's OWN review (`authoredByViewer`) never offers it.

import 'package:beautica_mobile/features/moderation/data/content_report_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/report_sheet.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/review_card.dart';
import 'package:beautica_mobile/features/salon/application/salon_review_summary_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_reviews_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon_review.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_reviews_section.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';
import '../../../../helpers/velvet_snack_matchers.dart';
import '../../../moderation/support/fake_content_report_repository.dart';

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('uk'));

const String _kSalonId = 'salon-1';

final SalonReviewItem _first = SalonReviewItem(
  id: 'sr-1',
  masterId: 'm-1',
  masterName: 'Master One',
  clientDisplayName: 'Olena K.',
  rating: 5,
  comment: 'Great',
  createdAt: DateTime.utc(2026, 6, 1),
);
final SalonReviewItem _second = SalonReviewItem(
  id: 'sr-2',
  masterId: 'm-1',
  masterName: 'Master One',
  clientDisplayName: 'Iryna P.',
  rating: 2,
  comment: 'Meh',
  createdAt: DateTime.utc(2026, 5, 1),
);

List<Object> _overrides(
  FakeContentReportRepository repo, {
  List<SalonReviewItem>? reviews,
}) => <Object>[
  salonReviewSummaryProvider(_kSalonId).overrideWith(
    (ref) => const SalonReviewSummary(
      avgRating: 3.5,
      reviewCount: 2,
      distribution: <int>[1, 0, 0, 1, 0],
    ),
  ),
  salonReviewsProvider(
    _kSalonId,
    SalonReviewSort.newest,
  ).overrideWith((ref) => reviews ?? <SalonReviewItem>[_first, _second]),
  contentReportRepositoryProvider.overrideWithValue(repo),
];

/// The «⋮» tap target of review [id] (the key sits on the hit target).
Finder _more(String id) => find.byKey(ReviewCard.moreKey('salon-review', id));

void main() {
  testWidgets('default (false) → no «⋮» on any salon review card', (
    tester,
  ) async {
    await tester.pumpApp(
      const SalonReviewsSection(salonId: _kSalonId),
      overrides: _overrides(FakeContentReportRepository()),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('salon-review-sr-1')), findsOneWidget);
    expect(find.byKey(const Key('salon-review-sr-2')), findsOneWidget);
    expect(find.byType(ReviewMoreButton), findsNothing);
  });

  testWidgets('true → the SECOND card\'s «⋮» reports the second review '
      '(its id + reviewer subtitle), never the first', (tester) async {
    final FakeContentReportRepository repo = FakeContentReportRepository();
    await tester.pumpApp(
      const SalonReviewsSection(salonId: _kSalonId, reportable: true),
      overrides: _overrides(repo),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ReviewMoreButton), findsNWidgets(2));

    await tester.tap(_more('sr-2'));
    await tester.pumpAndSettle();
    expect(find.byType(ReportSheet), findsOneWidget);
    expect(
      find.text(_l10n.reportSubjectReview(_second.clientDisplayName)),
      findsOneWidget,
    );
    expect(
      find.text(_l10n.reportSubjectReview(_first.clientDisplayName)),
      findsNothing,
    );

    await tester.tap(find.byKey(ReportSheet.reasonKey(ReportReason.falseInfo)));
    await tester.pump();
    await tester.ensureVisible(find.byKey(ReportSheet.submitKey));
    await tester.tap(find.text(_l10n.reportSubmit));
    await tester.pumpAndSettle();

    expect(
      repo.requests.single,
      const ContentReportRequest(
        targetType: ReportTargetType.review,
        targetId: 'sr-2',
        reason: ReportReason.falseInfo,
      ),
    );
    expect(find.byType(ReportSheet), findsNothing);
    expect(find.text(_l10n.reportSent), findsOneWidget);
    await pumpPastVelvetSnack(tester);
  });

  testWidgets('authoredByViewer → that card has no «⋮»; the other card keeps '
      'it', (tester) async {
    await tester.pumpApp(
      const SalonReviewsSection(salonId: _kSalonId, reportable: true),
      overrides: _overrides(
        FakeContentReportRepository(),
        reviews: <SalonReviewItem>[
          _first.copyWith(authoredByViewer: true),
          _second,
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('salon-review-sr-1')), findsOneWidget);
    expect(_more('sr-1'), findsNothing);
    expect(_more('sr-2'), findsOneWidget);
    expect(find.byType(ReviewMoreButton), findsOneWidget);
  });
}
