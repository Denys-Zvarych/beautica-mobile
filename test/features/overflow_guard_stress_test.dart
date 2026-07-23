// Phase 17.2 — narrow-width + extreme-text-scale overflow stress tests.
//
// These tests carry NO manual `expect(takeException(), isNull)`: the overflow
// guard (installed via pumpApp + flutter_test_config.dart) records ANY
// `RenderFlex overflowed` error and fails the test in tearDown. A test that
// pumps a widget at a stress size/scale and finishes without the guard firing
// has, by construction, proven the layout is overflow-free there. A regression
// that reintroduces an overflow fails the matching pump.
//
// The named backlog offenders covered here:
//   • service_form.dart  — horizontal RenderFlex overflow at ~320 dp width.
//   • pricing_field.dart — mode-toggle label Row overflow under extreme text
//     scale / narrow widths (both FIXED and RANGE bodies).
//   • schedule week-strip + weekday-pill widgets — at narrow widths.
//
// Stress matrix: width ∈ {320, 360}, textScale ∈ {1.0, 1.3, 2.0}. 320 dp is the
// smallest supported phone; textScale 2.0 is the OS "largest" accessibility
// setting. The cross-product is the worst realistic case a user can produce.
//
// SETTLING: these pumps use bounded `pump(Duration)` rather than
// `pumpAndSettle`. The form/toggle carry implicit animations (AnimatedAlign /
// AnimatedSize), and an offender that genuinely overflows re-reports each frame
// — `pumpAndSettle` would never quiesce in that case. A fixed pump advances the
// animations enough to lay out at the target size and lets the guard record any
// overflow without risking a non-settling hang.
//
// Isolation: ServiceForm pumps with a mocked ServiceRepository so
// approvedCategoriesProvider resolves offline. Each offender is wrapped in a
// Scaffold (Material ancestor required by the TextFields). UK l10n. Controllers
// disposed via addTearDown.

import 'package:beautica_mobile/features/schedule/presentation/widgets/schedule_widgets.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/pricing_field.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Fakes for the ServiceForm pump (category provider resolves offline).
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

class _FakeMasterServiceCreate extends Fake implements MasterServiceCreate {}

/// Loaded service used to drive the edit-mode form (also exercises the dirty
/// marker + range-mode pricing wells — the densest horizontal layout).
///
/// `priceDisplay` mirrors the raw server-formatted string
/// (beautica-backend's `PriceDisplayFormatter` now emits " ₴", matching the
/// mobile client's own formatters); RANGE mode never renders this field (it
/// rebuilds the label from priceMin/priceMax), so it is not asserted here.
const _kRangeService = MasterService(
  id: 'svc-stress',
  serviceDefId: 'def-stress',
  name: 'Манікюр комбінований',
  durationMinutes: 90,
  priceType: ServicePriceType.range,
  priceMin: 500,
  priceMax: 800,
  priceDisplay: '500–800 ₴',
  category: 'MANICURE',
);

/// The stress matrix dimensions.
const List<double> _widths = <double>[320, 360];
const List<double> _scales = <double>[1.0, 1.3, 2.0];

/// Wraps an offender in the Material ancestor its TextFields/InkWells need. The
/// stress width is applied by pumpApp's `width` knob (an Align+SizedBox around
/// this), so the Scaffold here only supplies Material — not sizing.
Widget _framed(Widget child) => Scaffold(body: child);

void main() {
  setUpAll(() => registerFallbackValue(_FakeMasterServiceCreate()));

  // =========================================================================
  // service_form.dart — full form at narrow widths / large text.
  // =========================================================================
  group('ServiceForm — no overflow under stress', () {
    late _MockServiceRepository repo;

    setUp(() {
      repo = _MockServiceRepository();
      when(() => repo.fetchApprovedCategories()).thenAnswer(
        (_) async => const <ServiceCategoryOption>[
          ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
          ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
        ],
      );
    });

    for (final double width in _widths) {
      for (final double scale in _scales) {
        testWidgets('create form @ ${width}dp x$scale', (tester) async {
          await tester.pumpApp(
            _framed(ServiceForm(onSubmit: (MasterServiceCreate _) async {})),
            overrides: [serviceRepositoryProvider.overrideWithValue(repo)],
            width: width,
            textScaleFactor: scale,
          );
          // Advance the category-provider microtask + any implicit animations
          // without risking a non-settling hang if an overflow re-reports.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          expect(find.byType(ServiceForm), findsOneWidget);
        });

        testWidgets('edit form (range) @ ${width}dp x$scale', (tester) async {
          await tester.pumpApp(
            _framed(
              ServiceForm(
                initial: _kRangeService,
                onSubmit: (MasterServiceCreate _) async {},
              ),
            ),
            overrides: [serviceRepositoryProvider.overrideWithValue(repo)],
            width: width,
            textScaleFactor: scale,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          expect(find.byType(ServiceForm), findsOneWidget);
        });
      }
    }
  });

  // =========================================================================
  // pricing_field.dart — mode toggle + both bodies, under stress.
  // =========================================================================
  group('PricingField — no toggle/well overflow under stress', () {
    for (final double width in _widths) {
      for (final double scale in _scales) {
        for (final ServicePriceType mode in ServicePriceType.values) {
          testWidgets('${mode.name} @ ${width}dp x$scale', (tester) async {
            final duration = TextEditingController();
            final fixed = TextEditingController();
            final min = TextEditingController();
            final max = TextEditingController();
            addTearDown(duration.dispose);
            addTearDown(fixed.dispose);
            addTearDown(min.dispose);
            addTearDown(max.dispose);

            await tester.pumpApp(
              _framed(
                PricingField(
                  mode: mode,
                  onModeChanged: (_) {},
                  fixedController: fixed,
                  minController: min,
                  maxController: max,
                  durationController: duration,
                ),
              ),
              width: width,
              textScaleFactor: scale,
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));

            // Both toggle segments must be laid out (the Row that historically
            // overflowed) — the guard would already have recorded otherwise.
            expect(
              find.byKey(const Key('pricing-toggle-fixed')),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('pricing-toggle-range')),
              findsOneWidget,
            );
          });
        }
      }
    }
  });

  // =========================================================================
  // schedule — week-strip day cell + weekday pill row, at narrow widths.
  // =========================================================================
  group('Schedule week widgets — no overflow under stress', () {
    // Ukrainian short weekday labels Пн…Нд (real strings the strip renders).
    const List<String> labels = <String>[
      'Пн',
      'Вт',
      'Ср',
      'Чт',
      'Пт',
      'Сб',
      'Нд',
    ];

    for (final double width in _widths) {
      for (final double scale in _scales) {
        testWidgets('WeekdayPillRow @ ${width}dp x$scale', (tester) async {
          await tester.pumpApp(
            _framed(
              WeekdayPillRow(
                labels: labels,
                active: const <bool>[
                  true,
                  true,
                  true,
                  true,
                  true,
                  false,
                  false,
                ],
                onTap: (_) {},
              ),
            ),
            width: width,
            textScaleFactor: scale,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
          expect(find.byType(WeekdayPillRow), findsOneWidget);
        });

        testWidgets('week strip (7 cells) @ ${width}dp x$scale', (
          tester,
        ) async {
          // The production week strip lays out seven WeekStripDay cells as
          // equal-flex siblings in one Row — the narrow-width offender. Mirror
          // that exact composition with stable two-digit day numbers.
          final Widget strip = Row(
            children: <Widget>[
              for (int i = 0; i < 7; i++)
                Expanded(
                  child: WeekStripDay(
                    weekdayLabel: labels[i],
                    day: 20 + i,
                    selected: i == 2,
                    working: i < 5,
                    inMonth: true,
                    hasOverride: i == 4,
                    onTap: () {},
                    pastSemanticLabel: 'past',
                    plainSemanticLabel: 'day',
                    past: i < 2,
                  ),
                ),
            ],
          );
          await tester.pumpApp(
            _framed(strip),
            width: width,
            textScaleFactor: scale,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
          expect(find.byType(WeekStripDay), findsNWidgets(7));
        });
      }
    }
  });
}
