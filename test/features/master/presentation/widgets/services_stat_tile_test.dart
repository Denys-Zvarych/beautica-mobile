// Widget tests for [ServicesStatTile] — the «Послуги» stat tile shared by the
// master's OWN profile (`master_profile_screen.dart`) and the client-facing
// PUBLIC profile (`public_master_profile_screen.dart`).
//
// Why this file exists
// -------------------
// The tile owns a three-way value decision (empty / unresolved / failed) that
// was previously duplicated — and DIVERGENT — across the two screens. The two
// screen test files exercise it only INDIRECTLY, and between them they can
// reach just three of the five reachable input combinations:
//
//   • own profile     → (0, false) (null, false) (null, true) (n, false)
//   • public profile  → (0, false) (n, false)                     [hasError
//                        is hard-wired `false` at that call site]
//
// Nothing anywhere pins `hasError: true` WITH a non-null count — the branch
// that proves the error glyph takes PRECEDENCE over a stale count rather than
// racing it. A future caller that keeps the last-known count while surfacing a
// failed refresh hits exactly that combination, and today it would ship
// unverified. This file covers the full truth table at the unit that owns it,
// so the screen tests stay about screen wiring.
//
// Strategy: pure widget tests — no providers, no network, no repositories.
// [pumpApp] supplies the l10n delegates the tile needs for its caption.

import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/services_stat_tile.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

/// The key every case below hangs its value assertion on. Deliberately NOT one
/// of the two production keys — the tile must honour whatever key the caller
/// hands it, which is the mechanism both screens rely on to keep their own
/// distinct handles.
const Key _kValueKey = Key('services-stat-tile-value');

/// Reads the rendered value [Text] — the actual pixels' string, not a
/// constructor argument.
String? _renderedValue(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_kValueKey)).data;

Future<void> _pumpTile(
  WidgetTester tester, {
  required int? count,
  bool hasError = false,
}) async {
  await tester.pumpApp(
    ServicesStatTile(count: count, hasError: hasError, valueKey: _kValueKey),
  );
  await tester.pumpAndSettle();
}

void main() {
  // ── Value truth table ─────────────────────────────────────────────────────

  group('ServicesStatTile — value', () {
    // THE behaviour the change was requested for: a master with no services
    // must read «—», not «0». A bare zero read as a hard, slightly punitive
    // fact about the master; the dash matches the rating/reviews tiles that
    // sit beside it on the same row and already use it for their zero-state.
    testWidgets('an empty catalogue (count 0) renders the em-dash, not "0"', (
      tester,
    ) async {
      await _pumpTile(tester, count: 0);

      expect(
        _renderedValue(tester),
        '—',
        reason:
            'zero services must render the em-dash placeholder — a bare "0" '
            'is the exact regression this widget was extracted to prevent',
      );
      expect(
        find.text('0'),
        findsNothing,
        reason:
            'no "0" may survive anywhere in the tile for an empty catalogue',
      );
    });

    testWidgets('an unresolved catalogue (count null) renders the em-dash', (
      tester,
    ) async {
      await _pumpTile(tester, count: null);

      expect(
        _renderedValue(tester),
        '—',
        reason:
            'an in-flight load renders the same placeholder as an empty '
            'catalogue — the tile deliberately does not distinguish them',
      );
    });

    testWidgets('a resolved non-zero count renders the number itself', (
      tester,
    ) async {
      await _pumpTile(tester, count: 7);

      expect(_renderedValue(tester), '7');
    });

    // Boundary: 1 is the smallest count that must NOT collapse onto the dash.
    // Guards a fix written as `count <= 1` or `count < 2` instead of `== 0`.
    testWidgets('a count of exactly 1 renders "1", not the em-dash', (
      tester,
    ) async {
      await _pumpTile(tester, count: 1);

      expect(
        _renderedValue(tester),
        '1',
        reason:
            'only ZERO collapses onto the dash — the smallest non-empty '
            'catalogue must still show its count',
      );
    });

    // ── hasError precedence ────────────────────────────────────────────────
    //
    // The failed-load glyph is deliberately '?' and NOT '—': if a suppressed
    // or failed GET /services rendered the empty-state dash, a master with a
    // populated catalogue would silently read as "has no services" with no UI
    // signal at all. These two cases pin that separation.

    testWidgets('a failed load renders "?", never the empty-state dash', (
      tester,
    ) async {
      await _pumpTile(tester, count: null, hasError: true);

      expect(
        _renderedValue(tester),
        '?',
        reason:
            'a catalogue that could not be fetched must stay distinguishable '
            'from one that is genuinely empty',
      );
    });

    // The combination NEITHER screen can currently produce, and therefore the
    // one no other test in the repo covers: hasError beside a stale count.
    // Documents that the error glyph WINS — a caller that keeps the last-known
    // count while a refresh fails must not present it as still-true.
    testWidgets('hasError takes precedence over a non-null count', (
      tester,
    ) async {
      await _pumpTile(tester, count: 5, hasError: true);

      expect(
        _renderedValue(tester),
        '?',
        reason:
            'hasError outranks count — a stale number must not be presented '
            'as a fresh one after a failed load',
      );
      expect(find.text('5'), findsNothing);
    });

    testWidgets('hasError takes precedence over a zero count', (tester) async {
      await _pumpTile(tester, count: 0, hasError: true);

      expect(
        _renderedValue(tester),
        '?',
        reason:
            'a failed load reported alongside a zero count is still a FAILURE, '
            'not an empty catalogue',
      );
    });
  });

  // ── Tile wiring ───────────────────────────────────────────────────────────

  group('ServicesStatTile — wiring', () {
    testWidgets('renders the services icon and the localised caption', (
      tester,
    ) async {
      await _pumpTile(tester, count: 3);

      expect(
        find.byIcon(Icons.design_services_outlined),
        findsOneWidget,
        reason: 'the tile owns its icon so both screens cannot drift apart',
      );

      // Caption resolved from the tree — no raw Ukrainian literal (M2/M11).
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(ServicesStatTile)),
      );
      expect(find.text(l10n.masterServicesLabel), findsOneWidget);
    });

    testWidgets('delegates rendering to the shared StatTile', (tester) async {
      await _pumpTile(tester, count: 3);

      expect(
        find.byType(StatTile),
        findsOneWidget,
        reason:
            'the tile must stay a thin wrapper over the StatTile its three '
            'row-siblings (bookings/rating/reviews) also use, so a shared '
            'style change reaches all four',
      );
    });

    testWidgets('places the caller-supplied valueKey on the value Text', (
      tester,
    ) async {
      // A key OTHER than the shared `_kValueKey` — proves the key is genuinely
      // passed through rather than hard-coded inside the tile, which is what
      // lets the two screens keep distinct test handles.
      const Key callerKey = Key('caller-owned-services-value');

      await tester.pumpApp(
        const ServicesStatTile(count: 2, valueKey: callerKey),
      );
      await tester.pumpAndSettle();

      final Finder valueText = find.byKey(callerKey);
      expect(valueText, findsOneWidget);
      expect(tester.widget<Text>(valueText).data, '2');
    });

    testWidgets('hasError defaults to false', (tester) async {
      // The public profile relies on this default — it never passes hasError.
      await tester.pumpApp(
        const ServicesStatTile(count: 4, valueKey: _kValueKey),
      );
      await tester.pumpAndSettle();

      expect(
        _renderedValue(tester),
        '4',
        reason:
            'omitting hasError must mean "resolved", not "failed" — the public '
            'profile call site depends on this default',
      );
    });
  });
}
