// Phase 379 (24.1b) — pixel coverage for the SALON_OWNER's «master mode»
// profile: [OwnerOwnProfileScreen] mounted exactly as the
// `RouteNames.ownerMasterProfile` route mounts it — the independent-master
// [VelvetBottomNavBar] («Профіль» active) plus the top-left labelled «‹ Салон»
// back pill (phase 378's `ProfileScaffold.backLabel`).
//
// No golden rendered [OwnerOwnProfileScreen] before this file, so there is no
// existing owner-profile baseline that could move; the defaults-unchanged
// proof is the widget test's `defaults (embedded: …)` cases plus the
// unchanged phase 378 `velvet_top_bar_*` goldens.
//
// Matrix: {320, 360, 414} dp × {textScale 1.0, 1.3} = 6 golden PNGs.

import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/application/owner_own_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/presentation/owner_own_profile_screen.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';

import '../helpers/no_unread_notifications.dart';
import 'helpers/golden_pump.dart';

const User _owner = User(
  id: 'u-owner',
  email: 'owner@beautica.test',
  role: UserRole.salonOwner,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  phoneNumber: '+380 97 000 00 00',
  professionalTitle: 'Топ-майстер',
  hasMasterProfile: true,
);

const Master _master = Master(
  id: 'm-owner',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  bio: 'Працюю з 2015 року.',
  avgRating: 4.8,
  reviewCount: 12,
  type: MasterType.salonOwner,
);

const List<MasterService> _services = <MasterService>[
  MasterService(
    id: 's-1',
    serviceDefId: 'd-1',
    name: 'Манікюр',
    durationMinutes: 60,
    priceMin: 500,
    priceDisplay: '500 ₴',
    category: 'NAILS',
  ),
];

/// Visible label of the back pill. A test-local constant (not a `find.text`
/// literal) — the l10n value of `ownerMasterModeBack`.
const String _kBackLabel = 'Салон';

List<Object> _overrides() => withDefaultNoUnread(<Object>[
  ownerOwnProfileProvider.overrideWith(
    (ref) async => (owner: _owner, master: (_master, _services)),
  ),
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[
      ServiceCategoryOption(name: 'NAILS', displayName: 'Нігті'),
    ],
  ),
]);

void main() {
  for (final double width in kGoldenWidths) {
    for (final double scale in kGoldenTextScales) {
      final String suffix = widthScaleSuffix(width, scale);

      goldenTest(
        'owner_master_mode_profile $suffix',
        fileName: 'owner_master_mode_profile_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(overrides: _overrides(), width: width),
        builder: () => OwnerOwnProfileScreen(
          embedded: true,
          bottomNavBar: const VelvetBottomNavBar(
            activeIndex: 3,
            profileRoute: RouteNames.ownerMasterProfile,
          ),
          backLabel: _kBackLabel,
          onBack: () {},
        ),
      );
    }
  }
}
