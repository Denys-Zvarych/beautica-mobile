// Phase 239 — [WishlistRow], the full-width «Усі збережені» entry.
//
// WHAT IS ACTUALLY UNDER TEST HERE: THE «NO TRUNCATION» CONTRACT
// ---------------------------------------------------------------------------
// `wishlist_row.dart`'s header makes two MEASURED claims and forbids one fix:
//
//   1. the name column is 186 dp at 360 dp and 146 dp at 320 dp — wide enough
//      that «Анастасія Мельниченко» renders on ONE line at both, which is the
//      whole reason the row keeps its leading avatar;
//   2. the duration/price pair sits in a `Wrap`, so a wide band drops to a
//      SECOND RUN rather than clipping;
//   3. and the one fix this redesign forbids is an ellipsis — the service name
//      and the master name carry no `maxLines` and no `TextOverflow`.
//
// A claim of that shape decays silently. Nothing about an added `maxLines: 1`
// looks wrong in a diff, and on the dev machine's fixtures the row would keep
// rendering identically right up until a real master's name arrived. So all
// three are pinned.
//
// ## THE ROW IS PUMPED INSIDE THE PAGE'S OWN HORIZONTAL PADDING
//
// `wishlist_screen.dart` lays the rows out in a `ListView` with
// `VelvetSpacing.lg` (24 dp) of padding on each side, so at a 360 dp device the
// card is 312 dp wide, NOT 360. Pumping the row bare would hand it 48 dp of
// room it never has in production and would inflate the name column to 250 dp —
// enough to make a one-line assertion pass for the wrong reason. [_pumpRow]
// reproduces the real inset, and `_kNameColumn360` below re-derives the
// header's own 186 dp from the constants so a token change that quietly
// narrows the column shows up as a failing arithmetic pin rather than as a
// wrapped name nobody notices.
//
// Layer: Widget. No providers — [WishlistRow] is a `StatelessWidget` taking a
// domain entry and two callbacks, so a `ProviderScope` override would be
// theatre.

import 'package:beautica_mobile/core/theme/app_spacing.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/price_tag.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/hub_widgets.dart';
import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

/// The header's own worked example — a real-length Ukrainian display name.
const String _kLongMasterName = 'Анастасія Мельниченко';

/// The page's horizontal inset, both sides (`wishlist_screen.dart`'s ListView).
const double _kPageInset = VelvetSpacing.lg;

/// The name column's width at a 360 dp device, re-derived from the constants
/// the layout is actually built from:
///
///   360  device
///   −48  page inset (24 each side)          → 312 card
///   −24  HubFlatCard padding (12 each side) → 288 content
///   −38  avatar                             (`WishlistRow._kAvatar`)
///   −12  avatar → text gap                  (`AppSpacing.sm`)
///   −4   text → heart gap                   (`VelvetSpacing.xs`)
///   −48  heart TAP TARGET, not the painted heart — a mobile-security a11y
///        fix grew `WishlistHeartButton`'s hit box from its 32dp painted
///        `target` to a 48dp square (`wishlist_heart_button.dart`'s
///        `_kMinTapExtent`), and that invisible margin costs this column
///        real width same as the painted icon used to.
///   =186
///
/// This is what the SERVICE name (the column's direct child) is laid out in.
/// (Was 202 before the heart's tap-target fix; the header comment above and
/// the two `162`/`146` narrow-width figures below moved with it.)
const double _kNameColumn360 = 186;

/// The MASTER name gets 18 dp less than [_kNameColumn360]: it sits after the
/// inline person glyph (`WishlistRow._kMetaGlyph`, 14) and its
/// `AppSpacing.xxs` (4) gap inside the same column. Named rather than inlined
/// so the two widths read as one derivation — the header's "202 dp column"
/// claim and the narrower strip the attribution line actually gets.
/// (14 is `WishlistRow._kMetaGlyph`, private to that file — mirrored here
/// rather than exported, because a widget does not owe a test a public
/// constant.)
const double _kMasterNameColumn360 = _kNameColumn360 - 14 - AppSpacing.xxs;

/// How much narrower every column is at the 320 dp floor (40 dp of device).
const double _k320Delta = 40;

WishlistService _entry({
  String serviceName = 'Нарощування вій — класика 2D',
  String masterName = _kLongMasterName,
  int durationMinutes = 60,
  String priceDisplay = '800 ₴',
  bool isRangePrice = false,
  double? priceMin,
  double? priceMax,
}) => WishlistService(
  masterServiceId: 'ms-1',
  masterId: 'm-1',
  serviceName: serviceName,
  masterName: masterName,
  durationMinutes: durationMinutes,
  priceDisplay: priceDisplay,
  isRangePrice: isRangePrice,
  priceMin: priceMin,
  priceMax: priceMax,
);

/// Phase F — a SALON-sourced entry: no master chosen, no `masterServiceId` /
/// `masterId` at all.
WishlistService _salonEntry({
  String serviceName = 'Ламінування вій',
  String? salonName = 'Салон краси «Оксамит»',
  String? salonAvatarUrl,
  String priceDisplay = 'від 600 до 900 ₴',
}) => WishlistService(
  sourceType: WishlistSourceType.salon,
  salonId: 'salon-1',
  salonName: salonName,
  salonAvatarUrl: salonAvatarUrl,
  serviceDefId: 'def-1',
  serviceName: serviceName,
  durationMinutes: 60,
  priceDisplay: priceDisplay,
);

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Pumps one [WishlistRow] at [width] logical px, inside the page's real
/// horizontal inset and top-aligned so the row keeps its intrinsic height
/// instead of being stretched by the 2400 dp test viewport.
Future<void> _pumpRow(
  WidgetTester tester,
  WishlistService item, {
  double width = 360,
  double textScaleFactor = 1.0,
}) async {
  await tester.pumpApp(
    Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kPageInset),
        child: WishlistRow(item: item, onBook: () {}, onUnfavourite: () {}),
      ),
    ),
    width: width,
    textScaleFactor: textScaleFactor,
  );
  await tester.pumpAndSettle();
}

/// The [RenderParagraph] backing a [Text] located by its fixture data.
///
/// The row's names carry no `Key` — they are the row's content, not controls —
/// so the fixture string is the only handle. Those strings are DATA a test
/// authored, not UI copy the app localises, which is why the `find.text`
/// annotations below are honest rather than a way around the gate.
RenderParagraph _paragraph(WidgetTester tester, Finder finder) =>
    tester.renderObject<RenderParagraph>(finder);

/// Lines the paragraph actually laid out.
///
/// [RenderParagraph] exposes no line count, so its own span + style + textScaler
/// are re-laid-out in a [TextPainter] (which does expose
/// [TextPainter.computeLineMetrics]) at the width the paragraph was given.
int _lineCount(RenderParagraph p) {
  final TextPainter painter = TextPainter(
    text: p.text,
    textAlign: p.textAlign,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    maxLines: p.maxLines,
  )..layout(maxWidth: p.constraints.maxWidth);
  final int lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
}

/// Every [Text] the row renders, so the truncation audit cannot be scoped to
/// whichever one the author remembered.
Iterable<Text> _texts(WidgetTester tester) => tester.widgetList<Text>(
  find.descendant(of: find.byType(WishlistRow), matching: find.byType(Text)),
);

void main() {
  // -------------------------------------------------------------------------
  // 1 — the name renders whole, on one line, at the widths the header claims
  // -------------------------------------------------------------------------
  group('should_renderMasterNameOnOneLine_when_threeSixtyDp', () {
    testWidgets('«$_kLongMasterName» occupies exactly one line at 360 dp', (
      tester,
    ) async {
      await _pumpRow(tester, _entry());

      // i18n-finder-ok: a fixture master name — data the test authored, not UI
      // copy the app localises. There is no ARB key that could be used instead.
      final Finder name = find.text(_kLongMasterName);
      expect(name, findsOneWidget);

      final RenderParagraph p = _paragraph(tester, name);
      expect(
        _lineCount(p),
        1,
        reason:
            'the header justifies keeping the leading avatar on the claim that '
            'a real-length master name fits one line at 360 dp. If this now '
            'wraps, either the avatar has to go or the claim does — silently '
            'living with a two-line name is the one option the design rules '
            'out.',
      );
    });

    testWidgets('the name column really is ${_kNameColumn360.toInt()} dp', (
      tester,
    ) async {
      // Pins the MEASUREMENT the one-line claim rests on, not just its
      // consequence. Without this, a future token change could narrow the
      // column and the one-line test would still pass on a shorter fixture.
      await _pumpRow(tester, _entry());

      final RenderParagraph service = _paragraph(
        tester,
        // i18n-finder-ok: fixture service name — data the test authored.
        find.text('Нарощування вій — класика 2D'),
      );
      expect(
        service.constraints.maxWidth,
        closeTo(_kNameColumn360, 0.5),
        reason: 'the header\'s 186 dp claim is about THIS column',
      );

      // i18n-finder-ok: fixture master name — see above.
      final RenderParagraph master = _paragraph(
        tester,
        find.text(_kLongMasterName),
      );
      expect(
        master.constraints.maxWidth,
        closeTo(_kMasterNameColumn360, 0.5),
        reason:
            'the attribution line pays 18 dp for the person glyph the compact '
            'card cannot afford — that cost is the reason this row keeps it',
      );
    });

    testWidgets('it still fits at the narrowest supported width (320 dp)', (
      tester,
    ) async {
      // The header's second measurement: 146 dp of service-name column at
      // 320 dp, still enough for a real name on one line.
      await _pumpRow(tester, _entry(), width: 320);

      expect(
        _paragraph(
          tester,
          // i18n-finder-ok: fixture service name — data the test authored.
          find.text('Нарощування вій — класика 2D'),
        ).constraints.maxWidth,
        closeTo(_kNameColumn360 - _k320Delta, 0.5),
      );

      // i18n-finder-ok: fixture master name — see above.
      final RenderParagraph p = _paragraph(tester, find.text(_kLongMasterName));
      expect(
        p.constraints.maxWidth,
        closeTo(_kMasterNameColumn360 - _k320Delta, 0.5),
      );
      expect(_lineCount(p), 1);
    });

    testWidgets('a name too long for one line WRAPS — it is never clipped', (
      tester,
    ) async {
      // The control that makes the assertions above falsifiable: proves the
      // paragraph is genuinely unbounded rather than merely never asked to
      // wrap. A `maxLines: 1` row would report 1 line here too.
      const String tooLong =
          'Анастасія Мельниченко-Задорожна-Кульчицька Володимирівна';
      await _pumpRow(tester, _entry(masterName: tooLong));

      // i18n-finder-ok: fixture master name — see above.
      final RenderParagraph p = _paragraph(tester, find.text(tooLong));
      expect(
        _lineCount(p),
        greaterThan(1),
        reason:
            'an over-long name reported a single line — the paragraph is '
            'capped, which means the row truncates',
      );
      expect(p.text.toPlainText(), tooLong, reason: 'nothing was dropped');
    });
  });

  // -------------------------------------------------------------------------
  // 2 — the duration/price pair wraps instead of clipping
  // -------------------------------------------------------------------------
  group('should_wrapPriceToSecondRun_when_durationAndBandAreWide', () {
    /// «2 год 30 хв» + «12500–25000 ₴» — the widest pair the fixtures produce.
    WishlistService wide() => _entry(
      durationMinutes: 150,
      priceDisplay: 'від 12500 до 25000 ₴',
      isRangePrice: true,
      priceMin: 12500,
      priceMax: 25000,
    );

    testWidgets('the price pill drops below the duration at 320 dp', (
      tester,
    ) async {
      // 320 dp is where the pair genuinely stops fitting: the Wrap gets
      // 320 − 48 (page) − 24 (card) − 8 (gap) − 112 (fixed CTA) = 128 dp, and
      // «2 год 30 хв» + the 112 dp-capped band needs ~168.
      await _pumpRow(tester, wide(), width: 320);

      final Finder duration = find.descendant(
        of: find.byType(WishlistRow),
        // `DurationMinutes.format` output for the fixture's own 150 minutes.
        // i18n-finder-ok: a formatted data value, not a localised UI string.
        matching: find.text('2 год 30 хв'),
      );
      expect(duration, findsOneWidget);
      final Finder pill = find.byType(PriceTag);
      expect(pill, findsOneWidget);

      final Rect durationRect = tester.getRect(duration);
      final Rect pillRect = tester.getRect(pill);

      // A SECOND RUN, not merely a lower centre: the pill's top edge is at or
      // below the duration's bottom edge. Comparing top-to-top would pass on a
      // single run too (the pill is taller than the caption, so it is always
      // vertically offset within the run).
      expect(
        pillRect.top,
        greaterThanOrEqualTo(durationRect.bottom),
        reason:
            'the wide band stayed on the duration\'s run. Either the Wrap was '
            'replaced by a Row (which would clip or overflow) or the pair no '
            'longer out-measures its column — check before relaxing this.',
      );
      // …and the new run starts back at the Wrap's left edge.
      expect(pillRect.left, closeTo(durationRect.left, 0.5));
    });

    testWidgets('the same wide pair still fits ONE run at 360 dp', (
      tester,
    ) async {
      // The width sensitivity is the point: 360 dp affords the Wrap 168 dp and
      // the pair just fits. Without this the 320 dp assertion above could not
      // distinguish "too wide for the column" from "the layout always stacks".
      await _pumpRow(tester, wide());

      final Rect durationRect = tester.getRect(
        find.descendant(
          of: find.byType(WishlistRow),
          // i18n-finder-ok: formatted duration data — see above.
          matching: find.text('2 год 30 хв'),
        ),
      );
      final Rect pillRect = tester.getRect(find.byType(PriceTag));

      expect(pillRect.top, lessThan(durationRect.bottom));
      expect(pillRect.left, greaterThan(durationRect.right));
    });

    testWidgets('the wide band is NOT clipped and NOT ellipsised', (
      tester,
    ) async {
      await _pumpRow(tester, wide());

      final PriceTag pill = tester.widget<PriceTag>(find.byType(PriceTag));
      // The re-derived en-dash band, whole — the long backend form never
      // reaches the pill (phase 239's measured reason for re-formatting).
      expect(pill.price, '12500–25000 ₴');
      expect(pill.price, isNot(contains('…')));
      expect(pill.price, isNot(contains('від')));
    });

    testWidgets('a NARROW pair shares one run even at 320 dp', (tester) async {
      // The second half of the probe: at the SAME 320 dp where the wide pair
      // wraps, «45 хв» + «800 ₴» does not. So the wrap is driven by content
      // width, not by the viewport.
      await _pumpRow(tester, _entry(durationMinutes: 45), width: 320);

      final Finder duration = find.descendant(
        of: find.byType(WishlistRow),
        // `DurationMinutes.format` output for the fixture's own 45 minutes.
        // i18n-finder-ok: a formatted data value, not localised UI copy.
        matching: find.text('45 хв'),
      );
      expect(duration, findsOneWidget);

      final Rect durationRect = tester.getRect(duration);
      final Rect pillRect = tester.getRect(find.byType(PriceTag));

      expect(
        pillRect.top,
        lessThan(durationRect.bottom),
        reason:
            'a short duration and a single price must sit on ONE run — if they '
            'do not, the wrap test above cannot distinguish "too wide" from '
            '"always stacked"',
      );
      expect(pillRect.left, greaterThan(durationRect.right));
    });

    testWidgets('a priceless legacy row renders no empty pill', (tester) async {
      // `showsPrice` is false when `priceLabel` is empty; an empty recessed
      // well announcing an absent figure is the failure mode.
      await _pumpRow(tester, _entry(priceDisplay: ''));
      expect(find.byType(PriceTag), findsNothing);
    });

    testWidgets('a zero duration renders no «0 хв» label', (tester) async {
      // The mapper maps an absent wire duration to 0 precisely so it reads as
      // "not known"; «0 хв» would be a fabrication.
      await _pumpRow(tester, _entry(durationMinutes: 0));
      expect(
        _texts(tester).any((Text t) => (t.data ?? '').contains('0 хв')),
        isFalse,
      );
    });
  });

  // -------------------------------------------------------------------------
  // 3 — no maxLines, no TextOverflow anywhere in the row
  // -------------------------------------------------------------------------
  group('should_carryNoTruncation_when_rowRenders', () {
    testWidgets('the service name has no maxLines and no overflow', (
      tester,
    ) async {
      const String service = 'Нарощування вій — класика 2D';
      await _pumpRow(tester, _entry(serviceName: service));

      // i18n-finder-ok: fixture service name — data the test authored.
      final Text name = tester.widget<Text>(find.text(service));

      expect(name.maxLines, isNull, reason: 'the row anchor must never cap');
      expect(name.overflow, isNull);
      expect(name.style?.overflow, isNull, reason: 'nor via the style');
    });

    testWidgets('the master name has no maxLines and no overflow', (
      tester,
    ) async {
      await _pumpRow(tester, _entry());

      // i18n-finder-ok: fixture master name — data the test authored.
      final Text name = tester.widget<Text>(find.text(_kLongMasterName));

      expect(name.maxLines, isNull);
      expect(name.overflow, isNull);
      expect(name.style?.overflow, isNull);
    });

    testWidgets('the RENDERED paragraphs agree — nothing capped downstream', (
      tester,
    ) async {
      // Asserting the widget properties alone would miss a cap applied by an
      // ancestor `DefaultTextStyle` or by the style token itself. These are the
      // render objects that actually laid out.
      await _pumpRow(tester, _entry());

      for (final (String label, Finder f) in <(String, Finder)>[
        // i18n-finder-ok: fixture service name — data the test authored.
        ('service name', find.text('Нарощування вій — класика 2D')),
        ('master name', find.text(_kLongMasterName)),
      ]) {
        final RenderParagraph p = _paragraph(tester, f);
        expect(p.maxLines, isNull, reason: 'paragraph for the $label');
        expect(p.overflow, TextOverflow.clip, reason: 'the $label');
      }
    });

    testWidgets('no NAME is truncated at 2.0x text scale on a 320 dp phone', (
      tester,
    ) async {
      // The regime where an ellipsis would actually be reached for. The
      // pumpApp overflow guard fails the test on any RenderFlex overflow, so
      // reaching the assertions at all is half the result.
      //
      // SCOPED TO THE TWO NAMES, deliberately. The price pill DOES cap its
      // figure at one line — that is `PriceTag`'s documented
      // `Flexible → ConstrainedBox → FittedBox` chain, which SCALES DOWN rather
      // than clipping, so a pathological band stays legible and never
      // ellipsises. Sweeping every `Text` in the row would flag that as a
      // truncation and force the assertion to be weakened; naming the two
      // paragraphs the contract is actually about keeps it strict.
      await _pumpRow(tester, _entry(), width: 320, textScaleFactor: 2.0);

      for (final Finder f in <Finder>[
        // i18n-finder-ok: fixture service name — data the test authored.
        find.text('Нарощування вій — класика 2D'),
        find.text(_kLongMasterName),
      ]) {
        final Text t = tester.widget<Text>(f);
        expect(
          t.maxLines,
          isNull,
          reason: 'a name caps its lines at 2.0x: «${t.data}»',
        );
        expect(
          t.overflow,
          anyOf(isNull, TextOverflow.clip),
          reason: 'a name ellipsises at 2.0x: «${t.data}»',
        );
        expect(_paragraph(tester, f).maxLines, isNull);
      }
    });

    testWidgets('the PRICE pill scales down rather than ellipsising', (
      tester,
    ) async {
      // Stated as its own case so the exclusion above is a documented
      // difference and not an oversight: the pill's single line is fine
      // BECAUSE it never truncates — `FittedBox(fit: scaleDown)` shrinks the
      // glyphs and keeps the ceiling of the band readable.
      await _pumpRow(
        tester,
        _entry(
          priceDisplay: 'від 12500 до 25000 ₴',
          isRangePrice: true,
          priceMin: 12500,
          priceMax: 25000,
        ),
        width: 320,
      );

      // `PriceTag` renders a zero-width height anchor alongside the figure, so
      // the figure is located by its value rather than by `byType(Text)`.
      final Finder band = find.descendant(
        of: find.byType(PriceTag),
        // i18n-finder-ok: a formatted money value, identical in every locale.
        matching: find.text('12500–25000 ₴'),
      );
      final Text t = tester.widget<Text>(band);
      expect(t.overflow, isNot(TextOverflow.ellipsis));
      expect(t.data, '12500–25000 ₴', reason: 'the ceiling survives whole');
      expect(
        find.descendant(
          of: find.byType(PriceTag),
          matching: find.byType(FittedBox),
        ),
        findsWidgets,
        reason: 'the scale-down chain is what makes the 1-line cap safe',
      );
    });
  });

  // -------------------------------------------------------------------------
  // 4 — the row's two controls are individually addressable
  // -------------------------------------------------------------------------
  group('per-entry keys', () {
    testWidgets('the heart and the CTA are keyed on the masterServiceId', (
      tester,
    ) async {
      // A list of otherwise identical rows: without per-entry keys a test (or
      // an E2E) can only tap `.first`, which is order-dependent and would let a
      // reordering regression through.
      bool booked = false;
      bool unfavourited = false;
      await tester.pumpApp(
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _kPageInset),
            child: WishlistRow(
              item: _entry(),
              onBook: () => booked = true,
              onUnfavourite: () => unfavourited = true,
            ),
          ),
        ),
        width: 360,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('wishlist_row_heart_ms-1')), findsOneWidget);
      expect(find.byKey(const Key('wishlist_row_book_ms-1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('wishlist_row_book_ms-1')));
      await tester.pumpAndSettle();
      expect(booked, isTrue);

      await tester.tap(find.byKey(const Key('wishlist_row_heart_ms-1')));
      // The heart fires its callback only AFTER the pop has played
      // (`WishlistHeartButton.popDuration`), so a bare pump would read false.
      await tester.pumpAndSettle();
      expect(unfavourited, isTrue);
    });

    testWidgets('an unnamed master still renders a name and initials', (
      tester,
    ) async {
      // The mapper leaves `masterName` EMPTY rather than inventing copy; this
      // is the render site that owns the fallback, and a blank avatar would
      // read as a failed image load.
      await _pumpRow(tester, _entry(masterName: ''));

      final Iterable<String> rendered = _texts(
        tester,
      ).map((Text t) => t.data ?? '');
      expect(rendered.any((String s) => s.isNotEmpty), isTrue);
      expect(find.byType(PriceTag), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // 4.5 — mobile-perf finding: the attribution glyph was a plain (non-const)
  // `Icon(item.attributionIcon, ...)` because the glyph varies by
  // `sourceType` — one `Icon` allocation per row per build. The fix branches
  // into two `const Icon` literals (one per arm) so each stays const; this
  // pins the MASTER arm specifically. The SALON arm's glyph is already pinned
  // by `should_renderSalonAttribution_when_sourceTypeIsSalon` below (which
  // predates this fix) — pinning ONLY the arm that test doesn't cover, so
  // this is not a duplicate of it.
  // -------------------------------------------------------------------------
  group('should_renderMasterAttribution_when_sourceTypeIsMaster', () {
    testWidgets('the attribution glyph is the person, not the storefront', (
      tester,
    ) async {
      await _pumpRow(tester, _entry());

      expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.storefront_rounded), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // 5 — Phase F: a SALON-sourced row renders the salon, not a master
  // -------------------------------------------------------------------------
  group('should_renderSalonAttribution_when_sourceTypeIsSalon', () {
    testWidgets('the attribution glyph is the storefront, not the person', (
      tester,
    ) async {
      await _pumpRow(tester, _salonEntry());

      // TWO storefronts on a SALON row: the attribution line's glyph AND the
      // avatar disc's fallback glyph (no salonAvatarUrl in this fixture) both
      // draw `Icons.storefront_rounded` — that duplication is the intended
      // design, not a bug (see `avatarFallbackIcon`'s doc comment).
      expect(find.byIcon(Icons.storefront_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.person_outline_rounded), findsNothing);
    });

    testWidgets('the attribution line shows the SALON name', (tester) async {
      await _pumpRow(tester, _salonEntry(salonName: 'Салон краси «Оксамит»'));

      // i18n-finder-ok: test-authored fixture data, not localised UI copy.
      expect(find.text('Салон краси «Оксамит»'), findsOneWidget);
    });

    testWidgets('a null salonName falls back to localised copy, not a crash', (
      tester,
    ) async {
      // Mirrors the MASTER arm's `masterName`-empty fallback policy — see
      // `wishlist_entry_labels.dart`.
      await _pumpRow(tester, _salonEntry(salonName: null));

      final Iterable<String> rendered = _texts(
        tester,
      ).map((Text t) => t.data ?? '');
      expect(rendered.any((String s) => s.isNotEmpty), isTrue);
    });

    testWidgets(
      'the avatar disc falls back to the storefront glyph, not initials',
      (tester) async {
        // No salonAvatarUrl in this fixture, so HubAvatar's RemoteImage path
        // is never entered — it renders the gradient disc directly with
        // fallbackIcon, exactly as a failed/absent photo would.
        await _pumpRow(tester, _salonEntry());

        final HubAvatar avatar = tester.widget<HubAvatar>(
          find.byType(HubAvatar),
        );
        expect(avatar.fallbackIcon, Icons.storefront_rounded);
        expect(
          avatar.initials,
          isEmpty,
          reason:
              "a brand name's initials read poorly — the glyph is the "
              'signal, and avatarInitials() is empty for a SALON row so the '
              'disc never falls through to text',
        );
      },
    );

    testWidgets('the price renders priceDisplay VERBATIM, RANGE included', (
      tester,
    ) async {
      // The whole point of Phase F's price decision: a SALON row's RANGE band
      // must NOT be re-derived into the app's own en-dash form — it must
      // agree, byte-for-byte, with the salon catalogue tile the client
      // favourited it from.
      await _pumpRow(tester, _salonEntry(priceDisplay: 'від 600 до 900 ₴'));

      // i18n-finder-ok: locale-invariant backend wire string, not UI copy.
      expect(find.text('від 600 до 900 ₴'), findsOneWidget);
      expect(find.text('600–900 ₴'), findsNothing);
    });

    testWidgets('the heart and the CTA are keyed on serviceDefId', (
      tester,
    ) async {
      // `favoriteTargetId` for a SALON row is `serviceDefId`, NOT
      // `masterServiceId` (null on this arm) — a key built off the latter
      // would collide every salon row onto the same literal "null" string.
      await _pumpRow(tester, _salonEntry());

      expect(find.byKey(const Key('wishlist_row_heart_def-1')), findsOneWidget);
      expect(find.byKey(const Key('wishlist_row_book_def-1')), findsOneWidget);
    });
  });
}
