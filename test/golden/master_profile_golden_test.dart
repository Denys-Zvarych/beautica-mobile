// Phase 17.4 + Phase 351 — Visual regression goldens for MasterProfileScreen.
//
// MasterProfileScreen is the primary home screen for INDEPENDENT_MASTER role.
// It has a staggered entrance animation (4 sections, 1100 ms controller,
// Phase 351 D14) and renders the identity card, 4 stat cards (bookings /
// rating / services / reviews), the «Про майстра» / «Послуги» / «Відгуки»
// tab bar, and the active tab body.
//
// Matrix: {320, 360, 414} dp × {textScale 1.0, 1.3} × {About, Services,
// Reviews tab} = 18 golden PNGs. Replaces the pre-351 6-PNG DATA-only matrix
// (the old 6-section stacked layout has no tabs to vary against).
//
// Clock: MasterProfileScreen shows no date — no clock override needed.
//
// Strategy:
//   • Override [masterProfileProvider] with [_StubMasterProfileNotifier]
//     resolving immediately to the seed master.
//   • Override [authProvider] with [_StubAuthNotifier].
//   • Override [masterRepositoryProvider] with a mock (MasterProfileScreen reads
//     through the repository for some edge cases).
//   • Override [serviceRepositoryProvider] with [FakeServiceRepository]
//     (services section resolves to empty — no network needed).
//   • Override [masterReviewSummaryProvider]/[masterReviewsProvider] so the
//     «Відгуки» tab (the same [MasterReviewsBody] the deleted standalone «Мої
//     відгуки» screen used to render) resolves without a real network read.
//   • Override [secureStorageProvider] with [FakeSecureStorage].
//   • [pumpWidget] uses [goldenPumpWidget] for ProviderScope + l10n.
//   • pumpAndSettle lets the animation controller quiesce; a Services/Reviews
//     cell then taps the matching tab.

import 'package:alchemist/alchemist.dart' show PumpWidget;
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_review_summary_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_reviews_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/fakes/fake_service_repository.dart';
import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockMasterRepository extends Mock implements MasterRepository {}

// ---------------------------------------------------------------------------
// Stub notifiers
// ---------------------------------------------------------------------------

const _stubUser = User(
  id: 'u1',
  email: 'oksana@beauty.ua',
  role: UserRole.independentMaster,
  firstName: 'Оксана',
  lastName: 'Коваль',
);

// Master with default workingHours (empty list via freezed @Default).
//
// Phase 224 (mobile-qa gap-fill) — `street` + `buildingNo` were ADDED here.
// Before that this fixture carried `city` alone, so `MasterAddressBlock` took
// its single-field branch at all six cells and the collapse-vs-split decision
// Phase 224 introduced was never rendered into ANY baseline: the six goldens
// passing on that change proved it was a no-op for this fixture, not that the
// new layout was right. With a full address the matrix now actually renders
// both branches (it splits at 320dp, collapses at the wider cells).
//
// THESE BASELINES ARE NOT THE ACCEPTANCE EVIDENCE FOR THAT LAYOUT.
// A golden regenerated from the code under test is self-referential. The
// correctness of what these PNGs now contain was established INDEPENDENTLY,
// before they were regenerated, by
// `test/features/master/presentation/master_profile_address_matrix_test.dart`
// — which pumps this same screen at these same six cells and asserts, off the
// laid-out `RenderParagraph`, which path rendered and that nothing on screen
// is ellipsized. These baselines' job from here is unintended pixel DRIFT,
// nothing more.
const _seedMaster = Master(
  id: 'm1',
  firstName: 'Оксана',
  lastName: 'Коваль',
  city: 'Київ',
  street: 'вул. Хрещатик',
  buildingNo: '22',
  bio: 'Майстер манікюру та педикюру. Понад 7 років досвіду.',
  phoneNumber: '+380501111111',
  avgRating: 4.8,
  reviewCount: 42,
  type: MasterType.independentMaster,
);

class _StubMasterProfileNotifier extends MasterProfile {
  @override
  Future<Master> build() async => _seedMaster;
}

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: _stubUser,
    accessToken: 'test-token',
  );
}

// ---------------------------------------------------------------------------
// Override factory
// ---------------------------------------------------------------------------

List<Object> _overrides() {
  final repo = _MockMasterRepository();
  return <Object>[
    authProvider.overrideWith(_StubAuthNotifier.new),
    masterProfileProvider.overrideWith(_StubMasterProfileNotifier.new),
    masterRepositoryProvider.overrideWithValue(repo),
    serviceRepositoryProvider.overrideWithValue(FakeServiceRepository()),
    secureStorageProvider.overrideWithValue(FakeSecureStorage()),
    masterReviewSummaryProvider(_seedMaster.id).overrideWith(
      (ref) async => MasterReviewSummary(
        avgRating: _seedMaster.avgRating,
        reviewCount: _seedMaster.reviewCount,
        distribution: const <int>[2, 4, 6, 10, 20],
      ),
    ),
    masterReviewsProvider(_seedMaster.id, MasterReviewSort.newest).overrideWith(
      (ref) async => <MasterReviewItem>[
        MasterReviewItem(
          id: 'rev-1',
          clientDisplayName: 'Ірина П.',
          rating: 5,
          comment: 'Дуже задоволена результатом!',
          createdAt: DateTime(2026, 6, 1),
        ),
      ],
    ),
  ];
}

// ---------------------------------------------------------------------------
// Custom pumpWidget — settle, then (for Services/Reviews) tap the tab.
// ---------------------------------------------------------------------------

PumpWidget _pumpTab({required double width, int? tapTabIndex}) {
  final PumpWidget base = goldenPumpWidget(
    overrides: _overrides(),
    width: width,
  );
  if (tapTabIndex == null) return base;
  return (WidgetTester tester, Widget alchemistWidget) async {
    await base(tester, alchemistWidget);
    await tester.tap(find.byKey(Key('master-profile-tab-$tapTabIndex')));
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
        'master_profile About $suffix',
        fileName: 'master_profile_about_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: _pumpTab(width: width),
        builder: () => const MasterProfileScreen(),
      );

      goldenTest(
        'master_profile Services $suffix',
        fileName: 'master_profile_services_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: _pumpTab(width: width, tapTabIndex: 1),
        builder: () => const MasterProfileScreen(),
      );

      goldenTest(
        'master_profile Reviews $suffix',
        fileName: 'master_profile_reviews_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: _pumpTab(width: width, tapTabIndex: 2),
        builder: () => const MasterProfileScreen(),
      );
    }
  }
}
