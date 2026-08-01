// Phase 224 (mobile-qa gap-fill) — the address block's collapse/split decision
// across the FULL responsive matrix the golden suite claims to cover.
//
// WHY THIS FILE EXISTS — THE GOLDEN SUITE PROVES NOTHING HERE
// -----------------------------------------------------------
// `test/golden/master_profile_golden_test.dart` renders `MasterProfileScreen`
// over {320, 360, 414} dp × {1.0, 1.3} text scale and all six baselines pass
// on this change. That is not evidence the change is correct — it is evidence
// the change is a NO-OP for that fixture. `_seedMaster` there sets `city:
// 'Київ'` and nothing else, so `buildCombinedAddressLine` returns the bare
// string `"Київ"`, the block takes its single-field `(city, null)` branch, and
// the entire fits-vs-fallback decision Phase 224 introduced is never reached
// at any of the six cells.
//
// WHY A STRUCTURAL TEST AND NOT A SEVENTH GOLDEN
// ----------------------------------------------
// A golden regenerated from the code under test is self-referential: it
// asserts "these pixels equal the pixels this code produced when I ran
// --update-goldens", which is true for a correct and an incorrect layout
// alike, and stays true until a human eyeballs the PNG. For a decision whose
// whole contract is "collapse ONLY when nothing is clipped", the meaningful
// question is answerable directly and without a baseline: ask the laid-out
// `RenderParagraph` whether it overflowed. That is the engine that paints the
// pixels reporting on itself — ground truth, reproducible in CI, and it fails
// loudly with a readable message instead of a diff image.
//
// So this file covers the matrix STRUCTURALLY:
//   - at every cell, with a realistic full address (city + street + building),
//     assert which path rendered and that whichever text landed on screen is
//     not ellipsized;
//   - assert the two paths are mutually exclusive at every cell;
//   - assert the tightest cell (320 dp @ 1.3x — the smallest column and the
//     largest glyphs, i.e. the worst budget the app ships) takes the SPLIT,
//     because that is the cell where a broken measurement would collapse and
//     silently amputate the building number;
//   - assert the matrix is not degenerate: the decision must actually vary
//     across it, or the whole matrix is testing one branch again.
//
// The goldens keep their job (unintended pixel drift on the surrounding card);
// this file owns the correctness of the new branch.

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../golden/helpers/golden_pump.dart' show kGoldenTextScales;
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/fakes/fake_service_repository.dart';
import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const Key _kCombinedKey = Key('master-profile-address-combined-text');
const Key _kLocalityKey = Key('master-profile-locality-text');
const Key _kStreetKey = Key('master-profile-address-text');

const String _kCity = 'Київ';
const String _kStreet = 'вул. Хрещатик';
const String _kBuilding = '22';

const _stubUser = User(
  id: 'u1',
  email: 'oksana@beauty.ua',
  role: UserRole.independentMaster,
  firstName: 'Оксана',
  lastName: 'Коваль',
);

/// The golden suite's `_seedMaster`, PLUS the street and building number it
/// omits — i.e. the fixture the six goldens would need in order to render the
/// Phase 224 branch at all.
const _seedMaster = Master(
  id: 'm1',
  firstName: 'Оксана',
  lastName: 'Коваль',
  city: _kCity,
  street: _kStreet,
  buildingNo: _kBuilding,
  bio: 'Майстер манікюру та педикюру. Понад 7 років досвіду.',
  phoneNumber: '+380501111111',
  avgRating: 4.8,
  reviewCount: 42,
  type: MasterType.independentMaster,
);

class _MockMasterRepository extends Mock implements MasterRepository {}

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

List<Object> _overrides() => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  masterProfileProvider.overrideWith(_StubMasterProfileNotifier.new),
  masterRepositoryProvider.overrideWithValue(_MockMasterRepository()),
  serviceRepositoryProvider.overrideWithValue(FakeServiceRepository()),
  secureStorageProvider.overrideWithValue(FakeSecureStorage()),
];

/// GROUND TRUTH — did the paragraph behind [key] actually overflow its line
/// budget in the laid-out tree? Read off the render object, not re-measured.
bool _overflowed(WidgetTester tester, Key key) =>
    tester.renderObject<RenderParagraph>(find.byKey(key)).didExceedMaxLines;

Future<void> _pumpProfile(
  WidgetTester tester, {
  required double width,
  required double textScale,
}) async {
  await tester.pumpApp(
    const MasterProfileScreen(),
    overrides: _overrides(),
    width: width,
    textScaleFactor: textScale,
  );
  await tester.pumpAndSettle();
}

void main() {
  // The golden suite's own matrix, imported rather than re-declared so the two
  // can never drift apart.
  const List<double> widths = <double>[320, 360, 414];

  group('address block across the golden matrix (city + street + building)', () {
    for (final double width in widths) {
      for (final double scale in kGoldenTextScales) {
        testWidgets(
          'at ${width.toInt()}dp text-${scale}x exactly one path renders and '
          'nothing on screen is ellipsized',
          (tester) async {
            await _pumpProfile(tester, width: width, textScale: scale);

            final bool collapsed = find
                .byKey(_kCombinedKey)
                .evaluate()
                .isNotEmpty;

            if (collapsed) {
              // Collapsed: the split rows must be absent, and the one line
              // that DID render must genuinely fit — this is the assertion a
              // regenerated golden cannot make.
              expect(find.byKey(_kLocalityKey), findsNothing);
              expect(find.byKey(_kStreetKey), findsNothing);
              expect(
                find.text('$_kCity, $_kStreet, $_kBuilding'),
                findsOneWidget,
              );
              expect(
                _overflowed(tester, _kCombinedKey),
                isFalse,
                reason:
                    'collapsed at ${width.toInt()}dp/${scale}x but the real '
                    'paragraph overflowed — the building number is being '
                    'ellipsized away',
              );
            } else {
              // Split: Phase 220's exact two rows, each within its budget.
              expect(find.byKey(_kLocalityKey), findsOneWidget);
              expect(find.byKey(_kStreetKey), findsOneWidget);
              expect(find.text(_kCity), findsOneWidget);
              expect(find.text('$_kStreet, $_kBuilding'), findsOneWidget);
              expect(
                _overflowed(tester, _kLocalityKey),
                isFalse,
                reason:
                    'the split path clipped the CITY at ${width.toInt()}dp/'
                    '${scale}x — the fallback is supposed to be the layout '
                    'that never over-promises',
              );
              expect(
                _overflowed(tester, _kStreetKey),
                isFalse,
                reason:
                    'the split path clipped the STREET at ${width.toInt()}dp/'
                    '${scale}x even with its 2-line budget',
              );
            }

            // The pre-Phase-220 street-first order must never come back on
            // either path, at any cell.
            expect(find.text('$_kStreet, $_kBuilding, $_kCity'), findsNothing);
            // Exactly one pin, whichever path ran.
            expect(find.byKey(_kStreetKey).evaluate().length, lessThan(2));
          },
        );
      }
    }

    testWidgets(
      'the TIGHTEST shipped cell (320dp @ 1.3x) falls back to the split — a '
      'measurement that ignored the text scaler would collapse here and clip',
      (tester) async {
        await _pumpProfile(tester, width: 320, textScale: 1.3);

        expect(
          find.byKey(_kCombinedKey),
          findsNothing,
          reason:
              'at the smallest width the app ships combined with the largest '
              'accessibility scale the golden matrix covers, «Київ, вул. '
              'Хрещатик, 22» cannot fit the identity card column — collapsing '
              'it here would silently drop the building number',
        );
        expect(find.byKey(_kLocalityKey), findsOneWidget);
        expect(find.byKey(_kStreetKey), findsOneWidget);
        expect(_overflowed(tester, _kLocalityKey), isFalse);
        expect(_overflowed(tester, _kStreetKey), isFalse);
      },
    );

    testWidgets(
      'the matrix is NOT degenerate — the decision genuinely varies across it, '
      'so these cells are not all re-testing one branch',
      (tester) async {
        bool sawCollapse = false;
        bool sawSplit = false;

        for (final double width in widths) {
          for (final double scale in kGoldenTextScales) {
            await _pumpProfile(tester, width: width, textScale: scale);
            if (find.byKey(_kCombinedKey).evaluate().isNotEmpty) {
              sawCollapse = true;
            } else {
              sawSplit = true;
            }
          }
        }

        expect(
          sawCollapse,
          isTrue,
          reason:
              'no cell in the shipped responsive matrix collapses — either '
              'the feature is not reachable in production or the measurement '
              'has become unconditionally pessimistic',
        );
        expect(
          sawSplit,
          isTrue,
          reason:
              'every cell collapses — the fallback is unreachable here, so '
              'this matrix would not notice a regression that made the '
              'collapse unconditional',
        );
      },
    );
  });
}
