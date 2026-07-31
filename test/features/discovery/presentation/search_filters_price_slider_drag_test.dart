// Widget-tier PIN on the price slider's pixel → value mapping.
//
// WHY THIS FILE EXISTS
// --------------------
// `integration_test/client_search_flow_test.dart` drags the price slider's MAX
// thumb by computing an ABSOLUTE target x from the value it wants:
//
//     trackLeft  = sliderRect.left  + 24          // RoundSliderOverlayShape r
//     trackWidth = sliderRect.width - 2 * 24
//     targetX    = trackLeft + (targetMax / kSearchPriceCeiling) * trackWidth
//
// It has to: `_RenderRangeSlider._handleDragUpdate` derives the new value from
// `_getValueFromGlobalPosition(details.globalPosition)` — the ABSOLUTE final
// pointer x — so a relative `Offset(-160, 0)` drag carries no meaning at all
// (it originally landed the max on 15500 instead of the intended <5000).
//
// That formula bakes in a GEOMETRY ASSUMPTION: the track is inset from the
// widget rect by exactly 24 logical px per side, which is the DEFAULT
// `RoundSliderOverlayShape` radius — a value `_PriceSection`'s local
// `SliderThemeData` never sets, and therefore inherits. The moment someone adds
// `overlayShape:` or `padding:` to that theme (or the ambient
// `ThemeData.sliderTheme` grows one), the inset shifts, every computed targetX
// slides, and the failure resurfaces at the SLOWEST tier as an unreadable
// off-by-4500-₴ assertion inside a multi-minute E2E flow.
//
// So the mapping is pinned HERE, at the fastest tier, where a break names
// itself. If this file goes red, do NOT patch the E2E's magic 24 — fix the
// theme, or update BOTH this pin and
// `integration_test/client_search_flow_test.dart`'s drag block together.
//
// WHY TWO TARGETS, AND WHY SNAP-BOUNDARY BRACKETS
// -----------------------------------------------
// A single target cannot distinguish a correct mapping from a constant-offset
// one: any single (x → value) pair is satisfiable by infinitely many
// (inset, scale) pairs. Two well-separated targets pin the LINE — both its
// intercept (the inset) and its slope (the track width).
//
// But targeting the CENTRE of a division is a BLUNT instrument, and this was
// measured, not assumed. `kSearchPriceDivisions` quantises the rail into 500-₴
// steps, so a drag aimed at a division centre tolerates ±250 ₴ of drift before
// it snaps anywhere else — about ±10 px at this surface size. An early draft of
// this file pinned only division centres, and a deliberate mutation of the
// inset constant from 24 → 12 STILL PASSED all of it: the snapping swallowed
// the 12-px error whole (the 3000 target actually landed on 2791, which rounds
// straight back to 3000). A pin that a 50 % geometry error walks through is not
// a pin.
//
// So the precision work is done by BRACKET tests that straddle a division
// BOUNDARY instead. Aiming ±[_kBracketEpsilon] ₴ either side of the 3250 ₴
// edge (the 3000 ↔ 3500 boundary) forces the snap to resolve DOWN on one side
// and UP on the other, which bounds the mapping error to ±50 ₴ ≈ ±2 px — 5×
// tighter than a division centre. The division-centre tests are kept as the
// readable statement of intent; the brackets are what holds the line.
//
// MEASURED RESOLUTION (mutation matrix over `_kSliderOverlayInset`, baseline 24)
//   12 → RED   16 → RED   20 → RED   22 → green
//   26 → green  28 → RED   32 → RED   48 → RED
// i.e. every inset drift of ≥ 4 px is caught; ±2 px is below the snapping
// floor and is knowingly out of reach — pushing epsilon lower would start
// trading real detection for flake risk. Every realistic theme edit
// (`overlayRadius: 12/16/20/32`, or `padding: EdgeInsets.zero` dropping the
// full 24) lands in the RED band. The baseline was re-run 3× consecutively
// green before this bound was recorded.
//
// House patterns mirrored from the sibling search_filters_price_fields_test.dart:
// plain `MaterialApp home:` (no router), a tall surface so the price section is
// on-screen and hit-testable, key-based finders only.

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/search_filters_screen.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/overflow_guard.dart';
import '../../../helpers/slider_geometry.dart';

// ---------------------------------------------------------------------------
// The geometry constant under pin.
//
// SHARED, not hand-copied: `integration_test/client_search_flow_test.dart`'s
// price-drag block imports the SAME [kSliderOverlayInset] from
// `test/helpers/slider_geometry.dart` (integration_test/ already imports this
// directory in ~20 flows), so the two tiers cannot drift apart. See that file
// for why the value is a hard-coded literal rather than derived from
// `SliderThemeData` — deriving it would make this pin tautological.
//
// The local alias keeps the rest of this file (and the mutation matrix in the
// header) reading exactly as before; mutate the shared constant to re-run it.
// ---------------------------------------------------------------------------
const double _kSliderOverlayInset = kSliderOverlayInset;

/// One division of the price rail: `kSearchPriceCeiling / kSearchPriceDivisions`
/// = 500 ₴. A drag snaps to the nearest multiple of this.
const double _kDivisionStep = kSearchPriceCeiling / kSearchPriceDivisions;

/// How far either side of a division BOUNDARY the bracket tests aim.
///
/// This is the resolution of the whole pin: a mapping error larger than this
/// flips at least one bracket to the wrong division and the file goes red. At
/// the 900-px test surface 50 ₴ is ≈ 2 px of track — well above floating-point
/// noise (the baseline was verified green 3× consecutively) yet 5× tighter
/// than the ±250 ₴ (≈ ±10 px) slack a division-CENTRE target tolerates. See the
/// mutation matrix in the file header for the measured detection band.
const double _kBracketEpsilon = 50;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _testUser = User(
  id: 'u-client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Дмитро',
  lastName: 'Клієнт',
);

const _authenticated = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _testUser, accessToken: 'tok'),
);

const _categories = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'NAILS', displayName: 'Манікюр'),
];

class _FixedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    state = _authenticated;
    return const AuthSession.authenticated(user: _testUser, accessToken: 'tok');
  }
}

/// Pumps [ClientSearchScreen] with the category provider resolved on a tall
/// surface, so the price slider is on-screen and hit-testable for a real drag.
Future<void> _pumpScreen(WidgetTester tester) async {
  installOverflowGuard();

  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FixedAuthNotifier.new),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        approvedCategoriesProvider.overrideWith((ref) async => _categories),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('uk'),
        home: ClientSearchScreen(),
      ),
    ),
  );
}

SearchFilters _filters(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(ClientSearchScreen)),
).read(searchFiltersControllerProvider);

final Finder _sliderFinder = find.byKey(const Key('search_price_slider'));

/// Maps a price [value] to the absolute x the MAX thumb must be released on —
/// the exact formula `integration_test/client_search_flow_test.dart` uses.
///
/// When [inset] is overridden the mapping is deliberately WRONG; the negative
/// control uses that to prove the real inset is load-bearing.
double _targetXFor(
  WidgetTester tester,
  double value, {
  double inset = _kSliderOverlayInset,
}) {
  final Rect rect = tester.getRect(_sliderFinder);
  final double trackLeft = rect.left + inset;
  final double trackWidth = rect.width - 2 * inset;
  return trackLeft + (value / kSearchPriceCeiling) * trackWidth;
}

/// Drags the MAX thumb so the pointer is RELEASED on absolute x [targetX].
///
/// Starts near the right edge, not the widget centre: a fresh [RangeSlider] has
/// both thumbs at the extremes, so a centre-started drag is exactly equidistant
/// from either thumb — an ambiguous tie that can grab the MIN thumb instead.
Future<void> _dragMaxThumbTo(WidgetTester tester, double targetX) async {
  final Rect rect = tester.getRect(_sliderFinder);
  final Offset dragStart = Offset(rect.right - 16, rect.center.dy);
  await tester.dragFrom(dragStart, Offset(targetX - dragStart.dx, 0));
  await tester.pumpAndSettle();
}

void main() {
  group('price slider — pixel → value mapping (readable intent)', () {
    // Division-CENTRE targets. These read exactly like the E2E's drag block and
    // state the intent plainly, but they are the COARSE half of this file:
    // ±250 ₴ of drift snaps back to the same answer. The bracket group below is
    // what gives the pin its teeth.

    testWidgets(
      'dragging the MAX thumb to the computed x for 3000 ₴ snaps maxPrice to '
      'exactly 3000 (lower quarter of the track)',
      (tester) async {
        await _pumpScreen(tester);
        await tester.pumpAndSettle();

        expect(
          _filters(tester).maxPrice,
          isNull,
          reason: 'precondition: the slider rests at the «будь-яка» ceiling',
        );

        await _dragMaxThumbTo(tester, _targetXFor(tester, 3000));

        expect(
          _filters(tester).maxPrice,
          3000,
          reason:
              'trackLeft = rect.left + 24 / trackWidth = rect.width - 48 is the '
              'mapping the E2E price drag depends on',
        );
      },
    );

    testWidgets(
      'dragging the MAX thumb to the computed x for 12000 ₴ snaps maxPrice to '
      'exactly 12000 (upper track — a second, well-separated target)',
      (tester) async {
        await _pumpScreen(tester);
        await tester.pumpAndSettle();

        await _dragMaxThumbTo(tester, _targetXFor(tester, 12000));

        expect(_filters(tester).maxPrice, 12000);
      },
    );
  });

  group('price slider — mapping precision (snap-boundary brackets)', () {
    // Each pair straddles a division BOUNDARY, so the snap must resolve DOWN on
    // the low side and UP on the high side. Passing both bounds the mapping
    // error to ±_kBracketEpsilon (50 ₴ ≈ 2 px) — tight enough that a 4-px
    // inset error, which the centre-targets above sail straight through, is
    // rejected. Low and high boundaries together pin the intercept AND slope.

    // 3250 ₴ = the 3000 ↔ 3500 edge (6.5 divisions).
    const double lowEdge = 3000 + _kDivisionStep / 2;
    // 12250 ₴ = the 12000 ↔ 12500 edge (24.5 divisions).
    const double highEdge = 12000 + _kDivisionStep / 2;

    testWidgets('x just BELOW the 3000/3500 division edge snaps DOWN to 3000', (
      tester,
    ) async {
      await _pumpScreen(tester);
      await tester.pumpAndSettle();

      await _dragMaxThumbTo(
        tester,
        _targetXFor(tester, lowEdge - _kBracketEpsilon),
      );

      expect(
        _filters(tester).maxPrice,
        3000,
        reason:
            'a mapping shifted UP by more than 50 ₴ would push this past the '
            '3250 ₴ edge and snap it to 3500',
      );
    });

    testWidgets('x just ABOVE the 3000/3500 division edge snaps UP to 3500', (
      tester,
    ) async {
      await _pumpScreen(tester);
      await tester.pumpAndSettle();

      await _dragMaxThumbTo(
        tester,
        _targetXFor(tester, lowEdge + _kBracketEpsilon),
      );

      expect(
        _filters(tester).maxPrice,
        3500,
        reason:
            'a mapping shifted DOWN by more than 50 ₴ would pull this back '
            'below the 3250 ₴ edge and snap it to 3000',
      );
    });

    testWidgets(
      'x just BELOW the 12000/12500 division edge snaps DOWN to 12000 (slope)',
      (tester) async {
        await _pumpScreen(tester);
        await tester.pumpAndSettle();

        await _dragMaxThumbTo(
          tester,
          _targetXFor(tester, highEdge - _kBracketEpsilon),
        );

        expect(_filters(tester).maxPrice, 12000);
      },
    );

    testWidgets(
      'x just ABOVE the 12000/12500 division edge snaps UP to 12500 (slope)',
      (tester) async {
        await _pumpScreen(tester);
        await tester.pumpAndSettle();

        await _dragMaxThumbTo(
          tester,
          _targetXFor(tester, highEdge + _kBracketEpsilon),
        );

        expect(_filters(tester).maxPrice, 12500);
      },
    );
  });

  group('price slider — the overlay inset is load-bearing', () {
    testWidgets(
      'the obvious WRONG formula (zero inset, full-width track) is rejected',
      (tester) async {
        // Negative control: proves the 24-px inset changes the outcome rather
        // than being incidentally harmless, so the brackets above are testing
        // something real. Complements — does not replace — the bracket
        // resolution, which is what catches SMALL drifts.
        await _pumpScreen(tester);
        await tester.pumpAndSettle();

        await _dragMaxThumbTo(tester, _targetXFor(tester, 3000, inset: 0));

        expect(
          _filters(tester).maxPrice,
          isNot(3000),
          reason:
              'trackLeft = rect.left / trackWidth = rect.width must land '
              'somewhere else, or the inset would carry no information at all',
        );
      },
    );
  });
}
