// mobile-qa gap-fix — SelectedServicesShelf had NO test file at all (flagged
// by both mobile-build-verifier and mobile-security): the widget extracted
// out of `BookingSummaryBar` (see that file's header) so
// `SalonMasterSelectionScreen`'s `_AssignConfirmBar` and `SalonTimeScreen`'s
// `ScheduleConfirmBar` could pin the exact same expand/collapse selected-
// services shelf above their own progress-counter + CTA content had its own
// expand/collapse/remove/overflow/empty behaviour completely unpinned —
// `booking_summary_bar_test.dart` only exercised it indirectly through
// `BookingSummaryBar`'s composition.
//
// Covers, directly on [SelectedServicesShelf] (not through a host bar):
//   1. Collapsed by default.
//   2. Expand reveals every selected service's name + price.
//   3. Re-tapping the toggle collapses again.
//   4. `onRemove: null` (the masters/time screens' read-only contract) renders
//      NO remove affordance at all — a real safety property: removing a
//      service after masters/times have already been assigned to it would
//      invalidate that downstream assignment.
//   5. `onRemove` provided renders the affordance and fires it with the
//      correct service.
//   6. A long/hostile service name is ellipsized (`maxLines: 1`) without a
//      RenderFlex overflow — asserted at a narrow stress width via
//      `pump_app.dart`'s built-in overflow guard (any overflow auto-fails the
//      test, no manual assertion needed).
//   7. Zero selected services renders the muted "0 послуг" count label and no
//      itemized entries, without crashing.

import 'package:beautica_mobile/features/booking/presentation/widgets/selected_services_shelf.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_count_label.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const _kManicure = MasterService(
  id: 'svc-mani',
  serviceDefId: 'def-mani',
  name: 'Манікюр з покриттям',
  durationMinutes: 90,
  priceMin: 500,
  priceDisplay: '500 ₴',
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
  priceDisplay: 'від 200 до 600 ₴',
  category: 'PEDICURE',
);

/// A hostile, unbroken (no spaces) service name — long enough to force
/// truncation at any realistic card width, and with no whitespace for the
/// text layout engine to soft-wrap on instead of eliding.
const String _kHostileName =
    'Комплексна процедура догляду за шкірою обличчя та шиї '
    'з використанням преміальної косметики та масажем декольте';

const _kHostileService = MasterService(
  id: 'svc-hostile',
  serviceDefId: 'def-hostile',
  name: _kHostileName,
  durationMinutes: 45,
  priceMin: 1200,
  priceDisplay: '1200 ₴',
  category: 'FACE',
);

const Key _toggleKey = Key('booking-summary-expand-toggle');
const Key _expandedListKey = Key('booking-summary-expanded-list');

Key _removeKeyFor(MasterService service) =>
    Key('booking-summary-remove-${service.id}');

Widget _shelf({
  List<MasterService> services = const <MasterService>[_kManicure],
  void Function(MasterService service)? onRemove,
  String? Function(MasterService service)? chosenLabelFor,
}) {
  return Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SelectedServicesShelf(
        services: services,
        onRemove: onRemove,
        chosenLabelFor: chosenLabelFor,
      ),
    ),
  );
}

/// Scopes a finder to the shelf's OWN itemized `expanded-list` subtree, so an
/// assertion proves the name/price landed in the ITEMIZED LIST specifically —
/// not merely somewhere in the pumped tree (the toggle row above the list
/// renders its own label + count text, and every HOST bar composing this
/// widget renders more text still). The unscoped variant is the latent trap
/// that DID bite on `salon_master_selection_screen_test.dart`, where each
/// master row's `covers: ...service names...` subtitle draws from the SAME
/// fixture names and made a bare `find.text` match two widgets.
Finder _inShelf(Finder matching) =>
    find.descendant(of: find.byKey(_expandedListKey), matching: matching);

void main() {
  // mobile-qa gap-fix (fix/ui-polish): the «Послуги та ціни» section label was
  // deleted from the PUBLIC MASTER PROFILE booking shelf, whose test now pins
  // it with `findsNothing`. The shared ARB key `publicMasterBookingSectionLabel`
  // was deliberately RETAINED because THIS shelf still renders it — but after
  // that deletion the key had no POSITIVE assertion left anywhere in the suite,
  // so deleting the key (or this label row) would have gone green. This group
  // is the surviving consumer's live guard.
  group('section label', () {
    testWidgets(
      'renders the shared «Послуги та ціни» label, collapsed and expanded',
      (tester) async {
        await tester.pumpApp(_shelf());
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Resolved via l10n, never a raw literal (M2/M11).
        expect(find.text(l10n.publicMasterBookingSectionLabel), findsOneWidget);

        // The label row is hoisted out of the ValueListenableBuilder for perf —
        // pin that the hoist keeps it rendered across an expand toggle.
        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        expect(find.text(l10n.publicMasterBookingSectionLabel), findsOneWidget);
      },
    );
  });

  group('collapsed by default', () {
    testWidgets('the itemized list is not built until the toggle is tapped', (
      tester,
    ) async {
      await tester.pumpApp(_shelf());
      await tester.pumpAndSettle();

      expect(find.byKey(_expandedListKey), findsNothing);
      // i18n-finder-ok: fixture service name (test data), not app UI copy.
      expect(find.text(_kManicure.name), findsNothing);

      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();

      expect(find.byKey(_expandedListKey), findsOneWidget);
    });
  });

  group('expand reveals every selected service', () {
    testWidgets(
      'a single selected service shows its name and price once expanded',
      (tester) async {
        await tester.pumpApp(_shelf());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        // i18n-finder-ok: fixture service name (test data), not app UI copy.
        expect(_inShelf(find.text(_kManicure.name)), findsOneWidget);
        final String price = ServicePriceDisplay.format(_kManicure);
        // i18n-finder-ok: formatted fixture price (test data), not app UI copy.
        expect(_inShelf(find.text(price)), findsOneWidget);
      },
    );

    testWidgets(
      'multiple selected services each show their own name and price once '
      'expanded',
      (tester) async {
        await tester.pumpApp(
          _shelf(services: const <MasterService>[_kManicure, _kPedicure]),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        // i18n-finder-ok: fixture service names (test data), not app UI copy.
        expect(_inShelf(find.text(_kManicure.name)), findsOneWidget);
        // i18n-finder-ok: fixture service names (test data), not app UI copy.
        expect(_inShelf(find.text(_kPedicure.name)), findsOneWidget);
        final String maniPrice = ServicePriceDisplay.format(_kManicure);
        final String pediPrice = ServicePriceDisplay.format(_kPedicure);
        // i18n-finder-ok: formatted fixture prices (test data), not app UI copy.
        expect(_inShelf(find.text(maniPrice)), findsOneWidget);
        // i18n-finder-ok: formatted fixture prices (test data), not app UI copy.
        expect(_inShelf(find.text(pediPrice)), findsOneWidget);

        // Each entry is keyed by service id (mobile-perf backlog nit fixed
        // while extracting this widget out of BookingSummaryBar).
        expect(find.byKey(ValueKey<String>(_kManicure.id)), findsOneWidget);
        expect(find.byKey(ValueKey<String>(_kPedicure.id)), findsOneWidget);
      },
    );
  });

  testWidgets('tapping the toggle a second time re-collapses the list', (
    tester,
  ) async {
    await tester.pumpApp(_shelf());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_expandedListKey), findsOneWidget);

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_expandedListKey), findsNothing);
    // i18n-finder-ok: fixture service name (test data), not app UI copy.
    expect(find.text(_kManicure.name), findsNothing);
  });

  group('remove affordance — read-only vs. removable contract', () {
    testWidgets(
      'onRemove: null (masters/time screens) renders NO remove affordance — '
      'a real safety property: removing a service after masters/times have '
      'been assigned to it would invalidate that downstream assignment',
      (tester) async {
        await tester.pumpApp(_shelf());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        expect(find.byKey(_removeKeyFor(_kManicure)), findsNothing);
        expect(find.byIcon(Icons.close_rounded), findsNothing);
      },
    );

    testWidgets(
      'onRemove provided renders the remove affordance and fires it with '
      'the correct service',
      (tester) async {
        final List<MasterService> removed = <MasterService>[];
        await tester.pumpApp(
          _shelf(onRemove: (MasterService s) => removed.add(s)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        final Finder removeButton = find.byKey(_removeKeyFor(_kManicure));
        expect(removeButton, findsOneWidget);
        expect(find.byIcon(Icons.close_rounded), findsOneWidget);

        await tester.tap(removeButton);
        await tester.pumpAndSettle();

        expect(removed, <MasterService>[_kManicure]);
      },
    );
  });

  group('hostile long service name', () {
    testWidgets(
      'a long, unbroken service name is ellipsized (maxLines: 1) without a '
      'RenderFlex overflow at a narrow stress width',
      (tester) async {
        // Narrow width (pump_app.dart's stress knob) so a non-ellipsized name
        // would genuinely overflow the row — the shared overflow guard
        // installed by `pumpApp` fails the test automatically on any
        // "RenderFlex overflowed" report, so no manual overflow assertion is
        // needed here; reaching pumpAndSettle clean IS the assertion.
        await tester.pumpApp(
          _shelf(services: const <MasterService>[_kHostileService]),
          width: 320,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        // i18n-finder-ok: fixture service name (test data), not app UI copy.
        final Finder nameFinder = _inShelf(find.text(_kHostileName));
        expect(nameFinder, findsOneWidget);
        final Text nameWidget = tester.widget<Text>(nameFinder);
        expect(
          nameWidget.maxLines,
          1,
          reason:
              'a regression that drops maxLines: 1 would let a hostile name '
              'wrap/overflow instead of eliding',
        );
        expect(nameWidget.overflow, TextOverflow.ellipsis);
      },
    );
  });

  group('empty selection', () {
    testWidgets(
      'zero selected services renders the muted "0 послуг" count label and '
      'no itemized entries, without crashing on expand',
      (tester) async {
        await tester.pumpApp(_shelf(services: const <MasterService>[]));
        await tester.pumpAndSettle();

        // Generated via the SAME shared formatter the widget itself calls —
        // not a hard-coded Cyrillic literal — so this never drifts from the
        // widget's own pluralization logic.
        final String zeroCountLabel = formatServiceCountUk(0);
        final Finder countLabel = find.text(zeroCountLabel);
        expect(countLabel, findsOneWidget);

        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        // Expanding with zero services must not crash and must render no
        // itemized entries at all — the shared `ListView.separated` with
        // itemCount: 0.
        expect(find.byKey(_expandedListKey), findsOneWidget);
        expect(find.byIcon(Icons.schedule_outlined), findsNothing);
      },
    );
  });

  // mobile-qa gap-fix — the `chosenLabelFor` callback added for the
  // independent-master `IndependentScheduleConfirmBar` (a SEPARATE date/time
  // per service, shown as a third accent line per row). The salon callers
  // (`BookingSummaryBar` / `ScheduleConfirmBar` / `_AssignConfirmBar`) pass
  // NOTHING, and MUST stay pixel-identical to their pre-callback 2-line row —
  // so this group pins BOTH sides of the branch: non-null renders + folds the
  // chosen window into the entry's own semantics; null omits it entirely.
  group('chosenLabelFor — independent chosen-window third line', () {
    // A chosen window built by the SAME formatter the independent bar feeds in
    // (`formatBookingWindow`), so NO Cyrillic date literal appears in a finder —
    // the shelf treats it as an opaque display string it never re-parses. The
    // UTC start's Europe/Kyiv wall-clock is a stable 14:00 (11:00Z + summer).
    final DateTime windowStart = DateTime.utc(2026, 7, 14, 11);
    final String chosenWindowMani = formatBookingWindow(
      windowStart,
      windowStart.add(Duration(minutes: _kManicure.durationMinutes)),
    );

    testWidgets(
      'a non-null chosenLabelFor renders the third accent line (event icon + '
      'the label) inside the service row',
      (tester) async {
        await tester.pumpApp(
          _shelf(
            chosenLabelFor: (MasterService s) =>
                s.id == _kManicure.id ? chosenWindowMani : null,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        // The camel-accent event icon marks the chosen-window line (distinct
        // from the muted `schedule_outlined` duration icon on line two).
        expect(
          _inShelf(find.byIcon(Icons.event_available_rounded)),
          findsOneWidget,
        );
        // Formatter-derived window string (not a hand-typed literal).
        expect(_inShelf(find.text(chosenWindowMani)), findsOneWidget);
      },
    );

    testWidgets(
      'the chosen window FOLDS into the entry\'s own semantics node (reusing '
      'the booking-chosen-window key) — a screen reader hears it as part of '
      'the service, not as a separate unlabelled node',
      (tester) async {
        await tester.pumpApp(
          _shelf(chosenLabelFor: (MasterService s) => chosenWindowMani),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byType(SelectedServicesShelf)),
        );
        // The exact combined label the source builds:
        //   "<name>, <duration>, <price>, <chosen-window-label> <chosen>".
        final String entryLabel = l10n.bookingServiceTileSemantics(
          _kManicure.name,
          DurationMinutes.format(_kManicure.durationMinutes),
          ServicePriceDisplay.format(_kManicure),
        );
        final String foldedLabel =
            '$entryLabel, ${l10n.bookingChosenWindowLabel} $chosenWindowMani';

        final SemanticsNode entryNode = tester.getSemantics(
          find.bySemanticsLabel(RegExp(RegExp.escape(foldedLabel))),
        );
        expect(
          entryNode.label,
          contains(l10n.bookingChosenWindowLabel),
          reason:
              'the chosen window must be folded into the entry node, not '
              'exposed as a separate unlabelled semantics stop',
        );
        expect(entryNode.label, contains(chosenWindowMani));
      },
    );

    testWidgets(
      'chosenLabelFor null (the salon callers\' contract) keeps the old 2-line '
      'row — NO third line, NO event icon — so the salon bars stay '
      'pixel-identical',
      (tester) async {
        await tester.pumpApp(_shelf());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        // Duration line (line two) still present…
        expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);
        // …but the chosen-window third line is entirely absent.
        expect(find.byIcon(Icons.event_available_rounded), findsNothing);

        // The entry's semantics carry ONLY the name/duration/price triple —
        // no folded-in chosen window (there is none).
        final l10n = AppLocalizations.of(
          tester.element(find.byType(SelectedServicesShelf)),
        );
        final String entryLabel = l10n.bookingServiceTileSemantics(
          _kManicure.name,
          DurationMinutes.format(_kManicure.durationMinutes),
          ServicePriceDisplay.format(_kManicure),
        );
        final SemanticsNode entryNode = tester.getSemantics(
          find.bySemanticsLabel(RegExp(RegExp.escape(entryLabel))),
        );
        expect(entryNode.label, isNot(contains(l10n.bookingChosenWindowLabel)));
      },
    );

    testWidgets(
      'a per-service chosenLabelFor renders a line for the SCHEDULED service '
      'only, leaving an unscheduled sibling on its 2-line row',
      (tester) async {
        await tester.pumpApp(
          _shelf(
            services: const <MasterService>[_kManicure, _kPedicure],
            // Only the manicure has a pick; the pedicure returns null.
            chosenLabelFor: (MasterService s) =>
                s.id == _kManicure.id ? chosenWindowMani : null,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        // Exactly one chosen-window line across both rows.
        expect(
          _inShelf(find.byIcon(Icons.event_available_rounded)),
          findsOneWidget,
        );
        // And it sits inside the manicure's row specifically.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('svc-mani')),
            matching: find.byIcon(Icons.event_available_rounded),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('svc-pedi')),
            matching: find.byIcon(Icons.event_available_rounded),
          ),
          findsNothing,
        );
      },
    );
  });
}
