// Regression tests for [NextAppointmentCard] — guards the location-marker swap.
//
// The populated next-appointment card's location `_MetaRow` previously rendered
// a Material `Icon(Icons.location_on_rounded)`. It now renders an inline
// `AppIcon(BeauticaAssetIcons.locationMarker)` sized 14 px and tinted
// [BrandColors.accent] to match the glyph it replaced. This site had NO prior
// location-icon assertion (Rule 3).
//
// Red-against-revert reasoning: the predicate
//   w is AppIcon && w.asset == BeauticaAssetIcons.locationMarker
// finds 0 if reverted to `Icon(Icons.location_on_rounded)` (Icon is not AppIcon)
// or a wrong/missing asset is used → the test fails. With the swap it finds
// exactly the location row's icon → passes.
//
// Layer: Widget. The populated card does no context.push at build (router calls
// are inside button onTap callbacks, not triggered here), so it is pumped on a
// plain MaterialApp. The other `_MetaRow` (master name) keeps its Material
// person Icon, so the location-marker predicate is unambiguous.

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/next_appointment_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

final _appointment = NextAppointment(
  id: 'bk-1',
  masterName: 'Ірина М.',
  service: 'Манікюр',
  dateLabel: 'Пʼятниця, 27 червня',
  timeLabel: '14:00',
  location: 'Львів, вул. Грушевського 1',
  startsAt: DateTime.now().add(const Duration(days: 2)),
  endsAt: DateTime.now().add(const Duration(days: 2, hours: 1)),
  masterInitials: 'ІМ',
);

Future<void> _pumpCard(WidgetTester tester, {NextAppointment? appointment}) {
  return tester.pumpApp(
    NextAppointmentCard(
      appointment: appointment,
      onReschedule: () {},
      onCancel: () {},
      onAddToGoogleCalendar: () {},
      onAddToAppleCalendar: () {},
    ),
  );
}

Finder _locationMarker() => find.byWidgetPredicate(
  (w) => w is AppIcon && w.asset == BeauticaAssetIcons.locationMarker,
);

AppIcon _locationMarkerWidget(WidgetTester tester) =>
    tester.widget<AppIcon>(_locationMarker());

void main() {
  group('NextAppointmentCard location marker', () {
    testWidgets('renders the locationMarker AppIcon on the location row', (
      tester,
    ) async {
      await _pumpCard(tester, appointment: _appointment);

      expect(
        find.byKey(const Key('next_appointment_populated')),
        findsOneWidget,
      );
      expect(_locationMarker(), findsOneWidget);
    });

    testWidgets(
      'the Material location_on Icon is NOT rendered (revert guard)',
      (tester) async {
        await _pumpCard(tester, appointment: _appointment);

        expect(
          find.byWidgetPredicate(
            (w) => w is Icon && w.icon == Icons.location_on_rounded,
          ),
          findsNothing,
        );
      },
    );

    testWidgets('location marker keeps the 14px / accent tint and size', (
      tester,
    ) async {
      await _pumpCard(tester, appointment: _appointment);

      final icon = _locationMarkerWidget(tester);
      expect(icon.size, 14, reason: 'next-appt marker must stay 14px');
      expect(
        icon.color,
        BrandColors.accent,
        reason: 'next-appt marker must stay BrandColors.accent',
      );
    });

    testWidgets('empty state renders no location marker', (tester) async {
      await _pumpCard(tester, appointment: null);

      expect(find.byKey(const Key('next_appointment_empty')), findsOneWidget);
      expect(_locationMarker(), findsNothing);
    });
  });
}
