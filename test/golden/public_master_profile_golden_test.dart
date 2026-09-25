// Phase 351 — First pixel coverage for PublicMasterProfileScreen (there was
// no public-master golden at all before this phase —
// `service_category_cards_golden_test.dart:14-17` documents the gap). These
// are NOT the acceptance evidence for the new visual result — acceptance is
// the Qase manual run (phase doc "Acceptance" section). They exist purely as
// a drift guard from here on.
//
// Matrix: {320, 360, 414} dp × {textScale 1.0, 1.3}, five scenarios:
//   • independent × About  (tab 0, default — bio + portfolio + Instagram)
//   • independent × Services (tab 1 — category cards)
//   • independent × Reviews (tab 2 — MasterReviewsBody inline)
//   • salon master × About with bio (no portfolio/Instagram — gated off)
//   • salon master × About empty (muted publicMasterAboutEmpty text)

import 'package:alchemist/alchemist.dart' show PumpWidget;
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_review_summary_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_reviews_notifier.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_profile_screen.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _kMasterId = 'master-1';

const _stubUser = User(
  id: 'client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Клієнт',
  lastName: 'Тест',
);

const _independentMaster = Master(
  id: _kMasterId,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  city: 'Київ',
  bio: 'Майстер манікюру з 7-річним досвідом.',
  avgRating: 4.8,
  reviewCount: 12,
  type: MasterType.independentMaster,
  instagram: '@olena_nails',
);

const _services = <MasterService>[
  MasterService(
    id: 'svc-1',
    serviceDefId: 'def-1',
    name: 'Манікюр з покриттям',
    durationMinutes: 90,
    priceMin: 500,
    priceDisplay: '500 ₴',
    category: 'MANICURE',
  ),
];

const _salonMasterWithBio = Master(
  id: _kMasterId,
  firstName: 'Марта',
  lastName: 'Дворак',
  bio: 'Працюю з клієнтами вже 5 років.',
  avgRating: 4.6,
  reviewCount: 8,
  type: MasterType.salonMaster,
);

const _salonMasterNoBio = Master(
  id: _kMasterId,
  firstName: 'Марта',
  lastName: 'Дворак',
  avgRating: null,
  reviewCount: 0,
  type: MasterType.salonMaster,
);

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: _stubUser,
    accessToken: 'test-token',
  );
}

List<Object> _overrides({required PublicMasterProfileData data}) => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  publicMasterProfileProvider(_kMasterId).overrideWith((ref) async => data),
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[],
  ),
  masterReviewSummaryProvider(_kMasterId).overrideWith(
    (ref) async => const MasterReviewSummary(
      avgRating: 4.8,
      reviewCount: 1,
      distribution: <int>[0, 0, 0, 0, 1],
    ),
  ),
  masterReviewsProvider(_kMasterId, MasterReviewSort.newest).overrideWith(
    (ref) async => <MasterReviewItem>[
      MasterReviewItem(
        id: 'rev-1',
        clientDisplayName: 'Ірина П.',
        rating: 5,
        comment: 'Дуже задоволена!',
        createdAt: DateTime(2026, 6, 1),
      ),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Custom pumpWidget — settle, then (for Services/Reviews) tap the tab.
// ---------------------------------------------------------------------------

PumpWidget _pumpTab({
  required double width,
  required PublicMasterProfileData data,
  int? tapTabIndex,
}) {
  final PumpWidget base = goldenPumpWidget(
    overrides: _overrides(data: data),
    width: width,
  );
  if (tapTabIndex == null) return base;
  return (WidgetTester tester, Widget alchemistWidget) async {
    await base(tester, alchemistWidget);
    await tester.tap(find.byKey(Key('public-master-profile-tab-$tapTabIndex')));
    await tester.pumpAndSettle();
  };
}

// ---------------------------------------------------------------------------
// Goldens
// ---------------------------------------------------------------------------

void main() {
  for (final width in kGoldenWidths) {
    for (final scale in kGoldenTextScales) {
      final suffix = widthScaleSuffix(width, scale);

      goldenTest(
        'public_master_profile independent About $suffix',
        fileName: 'public_master_profile_independent_about_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: _pumpTab(
          width: width,
          data: (_independentMaster, _services),
        ),
        builder: () => const PublicMasterProfileScreen(masterId: _kMasterId),
      );

      goldenTest(
        'public_master_profile independent Services $suffix',
        fileName: 'public_master_profile_independent_services_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: _pumpTab(
          width: width,
          data: (_independentMaster, _services),
          tapTabIndex: 1,
        ),
        builder: () => const PublicMasterProfileScreen(masterId: _kMasterId),
      );

      goldenTest(
        'public_master_profile independent Reviews $suffix',
        fileName: 'public_master_profile_independent_reviews_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: _pumpTab(
          width: width,
          data: (_independentMaster, _services),
          tapTabIndex: 2,
        ),
        builder: () => const PublicMasterProfileScreen(masterId: _kMasterId),
      );

      goldenTest(
        'public_master_profile salon master About (bio) $suffix',
        fileName: 'public_master_profile_salon_about_bio_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: _pumpTab(
          width: width,
          data: (_salonMasterWithBio, const <MasterService>[]),
        ),
        builder: () => const PublicMasterProfileScreen(masterId: _kMasterId),
      );

      goldenTest(
        'public_master_profile salon master About (empty) $suffix',
        fileName: 'public_master_profile_salon_about_empty_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: _pumpTab(
          width: width,
          data: (_salonMasterNoBio, const <MasterService>[]),
        ),
        builder: () => const PublicMasterProfileScreen(masterId: _kMasterId),
      );
    }
  }
}
