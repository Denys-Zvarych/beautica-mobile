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
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  void Function(MasterService service)? onRemove,
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
        onRemove: onRemove,
      ),
    ),
  );
}

Key _removeKeyFor(MasterService service) =>
    Key('booking-summary-remove-${service.id}');

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

  group('per-item remove affordance', () {
    testWidgets('the remove icon is absent when onRemove is not provided', (
      tester,
    ) async {
      await tester.pumpApp(_bar());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();

      expect(find.text(_kManicure.name), findsOneWidget);
      expect(find.byKey(_removeKeyFor(_kManicure)), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets(
      'the remove icon is present and calls onRemove with the correct '
      'service when onRemove is provided',
      (tester) async {
        final List<MasterService> removed = <MasterService>[];
        await tester.pumpApp(
          _bar(onRemove: (MasterService s) => removed.add(s)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        final Finder removeButton = find.byKey(_removeKeyFor(_kManicure));
        expect(removeButton, findsOneWidget);

        await tester.tap(removeButton);
        await tester.pumpAndSettle();

        expect(removed, <MasterService>[_kManicure]);
      },
    );

    testWidgets('each selected service has its own addressable remove key when '
        'multiple services are selected', (tester) async {
      final List<MasterService> removed = <MasterService>[];
      await tester.pumpApp(
        _bar(
          services: const <MasterService>[_kManicure, _kPedicure],
          onRemove: (MasterService s) => removed.add(s),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();

      expect(find.byKey(_removeKeyFor(_kManicure)), findsOneWidget);
      expect(find.byKey(_removeKeyFor(_kPedicure)), findsOneWidget);

      await tester.tap(find.byKey(_removeKeyFor(_kPedicure)));
      await tester.pumpAndSettle();

      expect(removed, <MasterService>[_kPedicure]);
    });

    // mobile-qa audit finding: the control originally shipped with a
    // `Padding(EdgeInsets.all(6))` around the 16px glyph — ~28×28dp, below
    // BOTH Material's 48dp recommendation AND this codebase's own
    // established floor for an inline per-row remove/close affordance
    // (`attachment_tray.dart`'s 32×32 "well"; `interval_editor.dart`/
    // `day_hours_sheet.dart` go up to 38×38). Now a fixed 32×32 `SizedBox`
    // around the same 16px glyph. This pins the tappable AREA, not just the
    // visible glyph size — a regression back to bare `Padding.all(6)` would
    // shrink the render-box size this test measures even though the icon
    // itself looks identical.
    testWidgets(
      'the remove control exposes a >=32×32dp tap target, not just the '
      '16px glyph',
      (tester) async {
        await tester.pumpApp(_bar(onRemove: (MasterService s) {}));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        final Size tapTargetSize = tester.getSize(
          find.byKey(_removeKeyFor(_kManicure)),
        );
        expect(
          tapTargetSize.width,
          greaterThanOrEqualTo(32),
          reason:
              'tappable width regressed below the 32×32dp floor established '
              'by attachment_tray.dart\'s per-row remove control',
        );
        expect(
          tapTargetSize.height,
          greaterThanOrEqualTo(32),
          reason:
              'tappable height regressed below the 32×32dp floor established '
              'by attachment_tray.dart\'s per-row remove control',
        );
      },
    );

    // mobile-qa audit finding: an explicit `Semantics(button: true, label:
    // ...)` on a descendant creates its OWN semantics node rather than
    // merging into the ancestor `_SelectionEntry` Semantics' label — but
    // that was never actually pinned by a test. A screen-reader user must be
    // able to reach the remove control as a DISTINCT stop, separate from the
    // row's own name/duration/price announcement — not have everything
    // folded into one unreadable announcement.
    testWidgets(
      'the remove control exposes its own distinct button semantics node — '
      "not merged into the entry's own name/duration/price announcement",
      (tester) async {
        await tester.pumpApp(_bar(onRemove: (MasterService s) {}));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byType(BookingSummaryBar)),
        );
        // i18n-finder-ok: _kManicure.name is fixture data, mirroring the
        // exact label the source computes — not app UI copy.
        final String entryLabel = l10n.bookingServiceTileSemantics(
          _kManicure.name,
          DurationMinutes.format(_kManicure.durationMinutes),
          ServicePriceDisplay.format(_kManicure),
        );
        final String removeLabel = l10n.bookingRemoveServiceSemantics(
          _kManicure.name,
        );

        // The entry's OWN node is found via its distinctive label substring
        // (its Column's plain Text descendants also merge their own values
        // in as extra lines — normal Flutter semantics-merging behaviour,
        // same as the toggle-row test above — so this checks for
        // CONTAINMENT of `entryLabel`, not full equality).
        final SemanticsNode entryNode = tester.getSemantics(
          find.bySemanticsLabel(RegExp(RegExp.escape(entryLabel))),
        );
        expect(
          entryNode.label,
          isNot(contains(removeLabel)),
          reason:
              "the entry's own content semantics must not absorb the "
              'remove button\'s label — a regression here would fold both '
              'into one unreadable screen-reader announcement',
        );
        expect(
          entryNode.getSemanticsData().hasAction(SemanticsAction.tap),
          isFalse,
          reason:
              "the entry's own node must not inherit the remove button's "
              'tap action — that would make the ENTIRE row (not just the '
              'small "×") fire the removal on any tap',
        );

        // The remove button is a fully separate, distinctly-reachable node
        // with EXACTLY its own label (no merged-in entry content) and its
        // own tap action.
        final SemanticsNode removeNode = tester.getSemantics(
          find.byKey(_removeKeyFor(_kManicure)),
        );
        expect(removeNode.label, removeLabel);
        expect(
          removeNode.getSemanticsData().flagsCollection.isButton,
          isTrue,
          reason: 'a screen reader must announce this as a tappable button',
        );
        expect(
          removeNode.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
      },
    );
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
