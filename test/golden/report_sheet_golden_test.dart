// Phase 424 goldens — the UgcSafety report surfaces, NEW masters:
//   • report_sheet_idle       — title, «Відгук від …» subtitle, six reasons,
//                               3-line comment well, disabled CTA.
//   • report_sheet_rate_limited — the same sheet with the 429 VelvetBanner.
//   • review_card_with_more   — ReviewCard(onMore:) «⋮» variant. The DEFAULT
//                               card is pinned by the host goldens
//                               (master/salon profile reviews tabs).
//
// SEED / REFRESH: `flutter test --update-goldens
// test/golden/report_sheet_golden_test.dart`.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/moderation/application/report_notifier.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/report_sheet.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/review_card.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

const double _kWidth = 360;

/// Starts in the 429 error state, as after a rate-limited submit.
class _RateLimitedController extends ReportController {
  @override
  ReportSubmitState build() => const ReportSubmitError(
    ReportErrorKind.rateLimited,
    ServerFailure(statusCode: 429),
  );
}

Widget _sheet() => const Align(
  alignment: Alignment.bottomCenter,
  child: ReportSheet(
    targetType: ReportTargetType.review,
    targetId: 'review-1',
    subject: 'Відгук від Олена К.',
  ),
);

void main() {
  goldenTest(
    'ReportSheet idle',
    fileName: 'report_sheet_idle',
    constraints: BoxConstraints.tight(const Size(_kWidth, kGoldenHeight)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: _kWidth),
    builder: _sheet,
  );

  goldenTest(
    'ReportSheet 429 banner',
    fileName: 'report_sheet_rate_limited',
    constraints: BoxConstraints.tight(const Size(_kWidth, kGoldenHeight)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(
      width: _kWidth,
      overrides: <Object>[
        reportControllerProvider.overrideWith(_RateLimitedController.new),
      ],
    ),
    builder: _sheet,
  );

  goldenTest(
    'ReviewCard with onMore',
    fileName: 'review_card_with_more',
    constraints: BoxConstraints.tight(const Size(_kWidth, 240)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: _kWidth),
    builder: () => Padding(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topCenter,
        child: ReviewCard(
          data: ReviewCardData(
            id: 'r-olena',
            clientDisplayName: 'Олена К.',
            rating: 1,
            comment: 'Купуйте крем у нашому магазині, знижка 50%!',
            createdAt: DateTime.utc(2020, 1, 1),
            serviceName: 'Педикюр',
          ),
          keyPrefix: 'golden-review',
          serviceName: 'Педикюр',
          onMore: () {},
        ),
      ),
    ),
  );
}
