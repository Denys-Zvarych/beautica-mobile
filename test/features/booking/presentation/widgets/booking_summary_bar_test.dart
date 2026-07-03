// Widget tests for the shared BookingSummaryBar's collapse/expand affordance.
//
// The itemized selected-service list used to always render (up to a 188px
// internal scroll), which became visually oversized once several services
// were selected. It is now hidden by default behind a tap-to-expand toggle
// on the label row, while the "Разом" total row + primary CTA always stay
// visible/tappable regardless of the toggle state — this file pins exactly
// that contract for the ONE shared widget reused by ServiceSelectorSheet,
// SlotDateScreen/SlotTimeScreen, and SalonServiceSelectionScreen (see those
// screens' own test files for the toggle wired into a full screen).

import 'package:beautica_mobile/features/booking/presentation/widgets/booking_summary_bar.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const _kManicure = MasterService(
  id: 'svc-mani',
  serviceDefId: 'def-mani',
  name: 'Манікюр з покриттям',
  durationMinutes: 90,
  priceMin: 500,
  priceDisplay: '500 грн',
  category: 'MANICURE',
);

const _kPedicure = MasterService(
  id: 'svc-pedi',
  serviceDefId: 'def-pedi',
  name: 'Педикюр з покриттям',
  durationMinutes: 120,
  priceType: ServicePriceType.range,
  priceMin: 200,
  priceMax: 600,
  priceDisplay: 'від 200 до 600 грн',
  category: 'PEDICURE',
);

const Key _toggleKey = Key('booking-summary-expand-toggle');
const Key _ctaKey = Key('booking-summary-cta');

Widget _bar({
  List<MasterService> services = const <MasterService>[_kManicure],
  bool enabled = true,
  VoidCallback? onAction,
}) {
  return Scaffold(
    body: Align(
      alignment: Alignment.bottomCenter,
      child: BookingSummaryBar(
        services: services,
        ctaLabel: 'Далі',
        ctaIcon: Icons.arrow_forward_rounded,
        enabled: enabled,
        onAction: onAction ?? () {},
      ),
    ),
  );
}

void main() {
  group('itemized list — collapsed by default', () {
    testWidgets('with a single service selected, the item is hidden until '
        'the toggle is tapped', (tester) async {
      await tester.pumpApp(_bar());
      await tester.pumpAndSettle();

      // i18n-finder-ok: fixture service name (test data), not app UI copy.
      expect(find.text(_kManicure.name), findsNothing);

      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();

      expect(find.text(_kManicure.name), findsOneWidget);
    });

    testWidgets('with multiple services selected, all items stay hidden '
        'until expanded', (tester) async {
      await tester.pumpApp(
        _bar(services: const <MasterService>[_kManicure, _kPedicure]),
      );
      await tester.pumpAndSettle();

      expect(find.text(_kManicure.name), findsNothing);
      expect(find.text(_kPedicure.name), findsNothing);

      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();

      expect(find.text(_kManicure.name), findsOneWidget);
      expect(find.text(_kPedicure.name), findsOneWidget);
    });

    testWidgets('tapping the toggle again re-collapses the list', (
      tester,
    ) async {
      await tester.pumpApp(_bar());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();
      expect(find.text(_kManicure.name), findsOneWidget);

      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();
      expect(find.text(_kManicure.name), findsNothing);
    });
  });

  group('total row + CTA always visible', () {
    testWidgets('the "Разом" total row is visible while collapsed and '
        'stays visible once expanded', (tester) async {
      await tester.pumpApp(_bar());
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(BookingSummaryBar)),
      );
      expect(find.text(l10n.bookingTotalLabel), findsOneWidget);

      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();

      expect(find.text(l10n.bookingTotalLabel), findsOneWidget);
    });

    testWidgets('the CTA fires onAction while collapsed', (tester) async {
      int taps = 0;
      await tester.pumpApp(_bar(onAction: () => taps++));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_ctaKey));
      await tester.pumpAndSettle();

      expect(taps, 1);
    });

    testWidgets('the CTA still fires onAction once expanded', (tester) async {
      int taps = 0;
      await tester.pumpApp(_bar(onAction: () => taps++));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_ctaKey));
      await tester.pumpAndSettle();

      expect(taps, 1);
    });
  });

  group('toggle affordance — chevron + semantics', () {
    testWidgets('the expand/collapse semantics label flips with state', (
      tester,
    ) async {
      await tester.pumpApp(_bar());
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(BookingSummaryBar)),
      );
      // The toggle row's Text children (section label + count) merge into
      // the ancestor Semantics node's announced label (Flutter's default
      // semantics-merging behaviour for non-boundary descendants), so match
      // by substring rather than exact string equality.
      Finder byLabelContaining(String needle) =>
          find.bySemanticsLabel(RegExp(RegExp.escape(needle)));

      expect(byLabelContaining(l10n.bookingSummaryExpandLabel), findsOneWidget);
      expect(byLabelContaining(l10n.bookingSummaryCollapseLabel), findsNothing);

      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();

      expect(
        byLabelContaining(l10n.bookingSummaryCollapseLabel),
        findsOneWidget,
      );
      expect(byLabelContaining(l10n.bookingSummaryExpandLabel), findsNothing);
    });

    testWidgets('the chevron icon rotates between collapsed and expanded', (
      tester,
    ) async {
      await tester.pumpApp(_bar());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
      AnimatedRotation rotation = tester.widget<AnimatedRotation>(
        find.byType(AnimatedRotation),
      );
      expect(rotation.turns, 0.0);

      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();

      rotation = tester.widget<AnimatedRotation>(find.byType(AnimatedRotation));
      expect(rotation.turns, 0.5);
    });
  });

  // mobile-perf re-audit follow-up: "No test asserts the rebuild-avoidance
  // itself (e.g., build-count tracking or widget-instance identity across
  // taps)... coverage is purely behavioral." The widget's own file header
  // documents that the expand/collapse state is scoped to a narrow
  // `ValueListenableBuilder` specifically so `_TotalRow`/`_ChosenWindow`/the
  // CTA never rebuild on a toggle tap. This pins that actual benefit, not
  // just the collapsed/expanded visible behaviour already covered above.
  //
  // TECHNIQUE — reuses the `debugPrintRebuildDirtyWidgets` proxy already
  // established in `salon_master_selection_screen_test.dart` for the same
  // class of claim (checked first: no test in this codebase asserts scoped
  // rebuilds any other way, and `_expandedNotifier`/`_BookingSummaryBarState`
  // are private to the source file, so no build-count field or widget
  // identity is reachable from this test file). `_TotalRow` carries no `Key`,
  // but `Element.toStringShort()` still renders its (private) runtimeType
  // name even without one, so matching the literal class name in the log is
  // enough to detect whether it rebuilt. One single-frame `tester.pump()`
  // (not `pumpAndSettle`, which would blur the 200/220ms
  // AnimatedRotation/AnimatedSize transition frames together) is captured
  // right after the tap.
  group('mobile-perf — rebuild scoping', () {
    testWidgets(
      'tapping the toggle rebuilds only the ValueListenableBuilder subtree — '
      "_TotalRow and the CTA never appear in that frame's rebuild log",
      (tester) async {
        await tester.pumpApp(_bar());
        await tester.pumpAndSettle();

        final List<String> rebuiltLines = <String>[];
        final DebugPrintCallback previousDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) rebuiltLines.add(message);
        };
        debugPrintRebuildDirtyWidgets = true;
        addTearDown(() {
          debugPrintRebuildDirtyWidgets = false;
          debugPrint = previousDebugPrint;
        });

        await tester.tap(find.byKey(_toggleKey));
        await tester.pump();

        debugPrintRebuildDirtyWidgets = false;
        debugPrint = previousDebugPrint;

        final bool toggleRowRebuilt = rebuiltLines.any(
          (String l) => l.contains('booking-summary-expand-toggle'),
        );
        final bool totalRowRebuilt = rebuiltLines.any(
          (String l) => l.contains('_TotalRow'),
        );
        final bool ctaRebuilt = rebuiltLines.any(
          (String l) => l.contains('booking-summary-cta'),
        );

        expect(
          toggleRowRebuilt,
          isTrue,
          reason:
              'the toggle subtree must rebuild to flip the chevron/reveal the '
              'list — if this is false the proxy technique itself is broken, '
              'not proving isolation',
        );
        expect(
          totalRowRebuilt,
          isFalse,
          reason:
              'a regression back to a plain setState-driven bool (or a '
              'ValueListenableBuilder wrapping the WHOLE `_populatedChildren` '
              'list instead of just the toggle row) would rebuild _TotalRow '
              'on every toggle tap and fail this assertion',
        );
        expect(
          ctaRebuilt,
          isFalse,
          reason:
              'the same regression would also rebuild the CTA button '
              'unnecessarily on every toggle tap',
        );

        await tester.pumpAndSettle();
      },
    );
  });
}
