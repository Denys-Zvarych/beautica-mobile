// Phase 21.5 QA gap-closure (mobile-qa) — widget tests for
// [SalonStaffProfileScreen].
//
// Before this file: `grep -rln "SalonStaffProfileScreen"` matched only the
// production source and the router — ZERO test files. This screen renders
// TWO structurally different bodies from the SAME data source depending on
// [SalonStaffMember.role]:
//   • MASTER — identity card + RoleChip + stats row (rating/reviews/
//     services/experience) + bio + ServiceCategoryCardList + phone contact.
//   • ADMIN  — identity card + RoleChip + phone contact ONLY. The admin
//     contract is largely ABSENCE (no stats, no bio, no categories), so
//     every admin case below asserts absence explicitly rather than only
//     asserting what IS present — a screen that silently regressed to
//     always rendering the master body would otherwise pass every
//     "admin renders SOMETHING" style check.
//
// Strategy: override [salonStaffMemberProfileProvider] directly (a plain
// FutureProvider family — `.overrideWith((ref) async => data)`, the SAME
// pattern `public_master_profile_screen_test.dart` uses for its own sibling
// family provider) with the desired [SalonStaffMemberProfileData]. No router
// needed — this screen takes `salonId`/`memberId` as constructor params and
// does no in-body navigation of its own (the ContactTile's phone tap is a
// documented no-op — see the screen's own header doc).
//
// `approvedCategoriesProvider` is stubbed to an empty list for every case —
// same "real Dio call hangs pumpAndSettle" footgun
// `public_master_profile_screen_test.dart` documents; the master-role tests
// below assert on category KEYS/counts, never on resolved category display
// labels, so the empty stub costs nothing.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:beautica_mobile/features/salon/application/salon_staff_member_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_staff_profile_screen.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _kSalonId = 'salon-1';
const String _kMasterId = 'staff-master-1';
const String _kAdminId = 'staff-admin-1';

const _masterMember = SalonStaffMember(
  userId: _kMasterId,
  masterId: 'master-row-1',
  role: SalonStaffRole.master,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  professionalTitle: 'Майстер манікюру',
  phoneNumber: '+380671112233',
  bio: 'Досвідчений майстер з 5-річним стажем роботи.',
  avgRating: 4.8,
  reviewCount: 32,
  // Deliberately DIFFERENT from `_masterServices.length` (2) — the services
  // stat tile must read `services.length`, not this field (mobile-qa
  // fixture-drift-avoidance: a matching value here could pass for the wrong
  // reason).
  serviceCount: 99,
);

/// A master entry with NO bio and NO services — proves both sections are
/// OMITTED (not rendered empty) when the data is genuinely absent, mirroring
/// how the production screen treats them as optional, not always-present.
const _masterMemberNoExtras = SalonStaffMember(
  userId: _kMasterId,
  masterId: 'master-row-1',
  role: SalonStaffRole.master,
  firstName: 'Марія',
  lastName: 'Іванова',
  avgRating: 4.2,
  reviewCount: 5,
);

const _adminMember = SalonStaffMember(
  userId: _kAdminId,
  role: SalonStaffRole.admin,
  firstName: 'Ірина',
  lastName: 'Ковальська',
  phoneNumber: '+380509998877',
);

const List<MasterService> _masterServices = <MasterService>[
  MasterService(
    id: 'svc-1',
    serviceDefId: 'def-1',
    name: 'Манікюр з покриттям',
    durationMinutes: 90,
    priceMin: 500,
    priceDisplay: '500 ₴',
    category: 'NAILS',
  ),
  MasterService(
    id: 'svc-2',
    serviceDefId: 'def-2',
    name: 'Корекція брів',
    durationMinutes: 30,
    priceMin: 250,
    priceDisplay: '250 ₴',
    category: 'BROWS',
  ),
];

// ---------------------------------------------------------------------------
// Overrides
// ---------------------------------------------------------------------------

List<Object> _overrides(
  String memberId,
  FutureOr<SalonStaffMemberProfileData> Function(Ref ref) create,
) => <Object>[
  salonStaffMemberProfileProvider(_kSalonId, memberId).overrideWith(create),
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[],
  ),
];

void main() {
  group('loading state', () {
    testWidgets('shows skeleton blocks while loading, no identity yet', (
      tester,
    ) async {
      await tester.pumpApp(
        const SalonStaffProfileScreen(salonId: _kSalonId, memberId: _kMasterId),
        overrides: _overrides(
          _kMasterId,
          (ref) => Completer<SalonStaffMemberProfileData>().future,
        ),
      );

      expect(find.byType(SkeletonBlock), findsWidgets);
      expect(find.byKey(const Key('salon-staff-profile-name')), findsNothing);
    });
  });

  group('error state', () {
    testWidgets('renders ErrorState, and retry re-invokes the provider', (
      tester,
    ) async {
      var attempt = 0;
      await tester.pumpApp(
        const SalonStaffProfileScreen(salonId: _kSalonId, memberId: _kMasterId),
        overrides: _overrides(_kMasterId, (ref) {
          attempt++;
          if (attempt == 1) throw const ServerFailure(statusCode: 500);
          return (_masterMember, _masterServices);
        }),
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.byKey(const Key('error_state_retry_button')), findsOneWidget);
      expect(find.byKey(const Key('salon-staff-profile-name')), findsNothing);

      await tester.tap(find.byKey(const Key('error_state_retry_button')));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsNothing);
      expect(find.byKey(const Key('salon-staff-profile-name')), findsOneWidget);
    });
  });

  // ── Gap 1 (build-verifier FAIL) — MASTER branch: stats + bio + categories
  // + phone must ALL be present. ─────────────────────────────────────────
  group('MASTER role — full render', () {
    testWidgets(
      'renders identity, RoleChip, full stats row, bio, service categories '
      'and phone contact',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpApp(
          const SalonStaffProfileScreen(
            salonId: _kSalonId,
            memberId: _kMasterId,
          ),
          overrides: _overrides(
            _kMasterId,
            (ref) async => (_masterMember, _masterServices),
          ),
        );
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(find.text(l10n.salonStaffProfileMasterTitle), findsOneWidget);

        // Identity.
        final Finder nameFinder = find.byKey(
          const Key('salon-staff-profile-name'),
        );
        expect(nameFinder, findsOneWidget);
        expect(tester.widget<Text>(nameFinder).data, 'Олена Ковальчук');

        final Finder roleChipFinder = find.byKey(
          const Key('salon-staff-profile-role-chip'),
        );
        expect(roleChipFinder, findsOneWidget);
        expect(
          tester.widget<RoleChip>(roleChipFinder).label,
          'Майстер манікюру',
          reason:
              "a master's OWN professionalTitle wins over the generic "
              'salon-master label',
        );

        // Stats row — all four tiles present, rating/reviews reflect the
        // fixture, services reflect `services.length` (2), NOT
        // `member.serviceCount` (99, deliberately mismatched — see fixture
        // doc).
        expect(
          tester
              .widget<Text>(
                find.byKey(const Key('salon-staff-profile-rating-value')),
              )
              .data,
          '4.8',
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const Key('salon-staff-profile-reviews-value')),
              )
              .data,
          '32',
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const Key('salon-staff-profile-services-value')),
              )
              .data,
          '2',
          reason:
              'must read services.length (the real fetched list), not the '
              'roster entry\'s own serviceCount field',
        );

        // Bio.
        expect(
          find.byKey(const Key('salon-staff-profile-bio')),
          findsOneWidget,
        );
        expect(
          // i18n-finder-ok: member.bio is fixture data, not UI copy.
          find.text('Досвідчений майстер з 5-річним стажем роботи.'),
          findsOneWidget,
        );

        // Service categories — one card per category bucket.
        expect(
          find.byKey(const Key('salon-staff-profile-service-categories')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('staff-profile-category-NAILS')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('staff-profile-category-BROWS')),
          findsOneWidget,
        );

        // Phone contact.
        final Finder phoneFinder = find.byKey(
          const Key('salon-staff-profile-contact-phone'),
        );
        expect(phoneFinder, findsOneWidget);
        expect(tester.widget<ContactTile>(phoneFinder).value, '+380671112233');
      },
    );

    testWidgets('falls back to the generic salon-master role label when no own '
        'professionalTitle is set', (tester) async {
      const noTitle = SalonStaffMember(
        userId: _kMasterId,
        masterId: 'master-row-1',
        role: SalonStaffRole.master,
        firstName: 'Марія',
        lastName: 'Іванова',
      );
      await tester.pumpApp(
        const SalonStaffProfileScreen(salonId: _kSalonId, memberId: _kMasterId),
        overrides: _overrides(
          _kMasterId,
          (ref) async => (noTitle, const <MasterService>[]),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
      expect(
        tester
            .widget<RoleChip>(
              find.byKey(const Key('salon-staff-profile-role-chip')),
            )
            .label,
        l10n.masterRoleSalonMaster,
      );
    });

    testWidgets(
      'omits bio and service-categories sections entirely when the master '
      'has neither — never renders them empty',
      (tester) async {
        await tester.pumpApp(
          const SalonStaffProfileScreen(
            salonId: _kSalonId,
            memberId: _kMasterId,
          ),
          overrides: _overrides(
            _kMasterId,
            (ref) async => (_masterMemberNoExtras, const <MasterService>[]),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('salon-staff-profile-bio')), findsNothing);
        expect(
          find.byKey(const Key('salon-staff-profile-service-categories')),
          findsNothing,
        );
        // The services stat tile still renders (part of the stats row) —
        // an empty catalogue shows the em-dash placeholder (matches the
        // rating/reviews tiles' own zero-state), not a literal '0'.
        expect(
          tester
              .widget<Text>(
                find.byKey(const Key('salon-staff-profile-services-value')),
              )
              .data,
          '—',
        );
      },
    );
  });

  // ── Gap 1 (build-verifier FAIL) — ADMIN branch: the contract is largely
  // ABSENCE. Every negative assertion here is asserted explicitly, never
  // inferred from "the master case passed". ──────────────────────────────
  group('ADMIN role — restricted render', () {
    testWidgets(
      'renders ONLY identity + RoleChip("Адміністратор") + phone — stats, '
      'bio and service-categories are ALL absent',
      (tester) async {
        await tester.pumpApp(
          const SalonStaffProfileScreen(
            salonId: _kSalonId,
            memberId: _kAdminId,
          ),
          overrides: _overrides(
            _kAdminId,
            (ref) async => (_adminMember, const <MasterService>[]),
          ),
        );
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(find.text(l10n.salonStaffProfileAdminTitle), findsOneWidget);

        // Identity present.
        final Finder nameFinder = find.byKey(
          const Key('salon-staff-profile-name'),
        );
        expect(nameFinder, findsOneWidget);
        expect(tester.widget<Text>(nameFinder).data, 'Ірина Ковальська');

        final Finder roleChipFinder = find.byKey(
          const Key('salon-staff-profile-role-chip'),
        );
        expect(roleChipFinder, findsOneWidget);
        expect(
          tester.widget<RoleChip>(roleChipFinder).label,
          l10n.salonStaffRoleAdmin,
        );

        // Stats row — ALL four value keys absent (not just zeroed).
        expect(
          find.byKey(const Key('salon-staff-profile-rating-value')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('salon-staff-profile-reviews-value')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('salon-staff-profile-services-value')),
          findsNothing,
        );

        // Bio absent.
        expect(find.byKey(const Key('salon-staff-profile-bio')), findsNothing);

        // Service categories absent.
        expect(
          find.byKey(const Key('salon-staff-profile-service-categories')),
          findsNothing,
        );

        // Phone contact IS present.
        final Finder phoneFinder = find.byKey(
          const Key('salon-staff-profile-contact-phone'),
        );
        expect(phoneFinder, findsOneWidget);
        expect(tester.widget<ContactTile>(phoneFinder).value, '+380509998877');
      },
    );

    testWidgets('an admin entry carrying a non-null avgRating/reviewCount/bio '
        '(a malformed backend response) STILL suppresses every master-only '
        'section — the role gate, not the data, decides', (tester) async {
      // Deliberately contract-violating fixture (SalonStaffMember's own
      // header doc says bio/avgRating are ALWAYS null for an admin) — pins
      // that the screen's `isAdmin` gate is unconditional, not merely
      // "happens to look right because the fixture cooperates".
      const contaminatedAdmin = SalonStaffMember(
        userId: _kAdminId,
        role: SalonStaffRole.admin,
        firstName: 'Ірина',
        lastName: 'Ковальська',
        phoneNumber: '+380509998877',
        bio: 'Це не має відображатися.',
        avgRating: 4.9,
        reviewCount: 10,
      );
      await tester.pumpApp(
        const SalonStaffProfileScreen(salonId: _kSalonId, memberId: _kAdminId),
        overrides: _overrides(
          _kAdminId,
          (ref) async => (contaminatedAdmin, _masterServices),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-staff-profile-rating-value')),
        findsNothing,
      );
      expect(find.byKey(const Key('salon-staff-profile-bio')), findsNothing);
      expect(
        find.byKey(const Key('salon-staff-profile-service-categories')),
        findsNothing,
      );
      // i18n-finder-ok: contaminatedAdmin.bio is fixture data, not UI copy.
      expect(find.text('Це не має відображатися.'), findsNothing);
    });
  });
}
