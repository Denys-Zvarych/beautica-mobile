// Regression tests for `SalonMasterStrip`
// (`lib/features/booking/presentation/widgets/salon_master_strip.dart`) after
// the `MasterStripShell` extraction.
//
// The shell refactor lifted the common frame out of both strips. The salon
// strip INTENTIONALLY keeps its two salon-specific slots — the services line
// (the services THIS master performs) and the summed-duration pill — and does
// NOT carry a professional title (`SalonMasterSchedule` has no title field).
// This pins that the salon composition survived the refactor: services line +
// duration pill both still render, driven off the schedule's real data.

import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_avatar_badge.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip_shell.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/salon_master_strip.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart'
    show ServicePriceType;
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const _kManicure = SalonCatalogService(
  id: 'svc-mani',
  name: 'Манікюр з покриттям',
  durationLabel: '1 год 30 хв',
  priceDisplay: '500 грн',
  durationMinutes: 90,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
);

const _kHaircut = SalonCatalogService(
  id: 'svc-cut',
  name: 'Стрижка',
  durationLabel: '1 год',
  priceDisplay: '450 грн',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 450,
);

// Two assigned services → summed duration = 90 + 60 = 150 min.
const _kSchedule = SalonMasterSchedule(
  masterId: 'master-kyiv-1',
  firstName: 'Ірина',
  lastName: 'Бондаренко',
  type: MasterType.salonMaster,
  services: <SalonCatalogService>[_kManicure, _kHaircut],
  primaryServiceAssignmentId: 'assign-1',
);

const List<Color> _kAvatarGradient = <Color>[
  Color(0xFFD8BE9C),
  Color(0xFF6A4A28),
];

void main() {
  group('SalonMasterStrip — shell-refactor regression', () {
    testWidgets(
      'still renders its services line and summed-duration pill through the '
      'shared MasterStripShell',
      (tester) async {
        await tester.pumpApp(
          const Center(
            child: SalonMasterStrip(
              schedule: _kSchedule,
              avatarGradient: _kAvatarGradient,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Composes the shared shell (not a fork).
        expect(find.byType(MasterStripShell), findsOneWidget);
        expect(find.byType(MasterAvatarBadge), findsOneWidget);

        final Finder strip = find.byType(SalonMasterStrip);

        // Services line — the joined names of THIS master's assigned services,
        // with its leading check glyph. i18n-finder-ok: service names are
        // fixture domain data, not UI copy.
        expect(
          find.descendant(
            of: strip,
            matching: find.text('Манікюр з покриттям · Стрижка'),
          ),
          findsOneWidget,
          reason:
              'the salon strip must keep showing the services this master '
              'performs after the shell extraction.',
        );
        expect(
          find.descendant(
            of: strip,
            matching: find.byIcon(Icons.check_circle_outline_rounded),
          ),
          findsOneWidget,
          reason: 'the services line keeps its leading check glyph.',
        );

        // Duration pill — the summed appointment length (150 min → "2 год 30
        // хв"), with its schedule glyph. Computed via the same formatter the
        // widget uses, so the assertion tracks the format, not a hardcode.
        final String durationLabel = DurationMinutes.format(
          _kSchedule.summedDurationMinutes,
        );
        expect(durationLabel, '2 год 30 хв'); // sanity-pin the fixture math
        expect(
          find.descendant(of: strip, matching: find.text(durationLabel)),
          findsOneWidget,
          reason: 'the salon strip must keep its summed-duration pill.',
        );
        expect(
          find.descendant(
            of: strip,
            matching: find.byIcon(Icons.schedule_rounded),
          ),
          findsOneWidget,
          reason: 'the duration pill keeps its schedule glyph.',
        );
      },
    );
  });
}
