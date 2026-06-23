// Phase 13.7 — PassportPreviewCard ELLIPSIS-TRUNCATION regression guard.
//
// THE BUG
// -------
// The BEAUTY PASSPORT preview pill lives in a Row of two Expanded pills
// (_StatPillsRow in home_hub_screen.dart). At that narrow half-width the long
// Ukrainian subtitle "Твій б'юті-паспорт у Beautica" — and, at textScale 1.3,
// even the "BEAUTY PASSPORT" title — overflowed the text column and got
// ELLIPSIS-CUT (the old code used Text(maxLines: 2, overflow: ellipsis)). Users
// saw "Твій б'юті-паспорт у Beau…" instead of the full brand line.
//
// THE FIX UNDER TEST (passport_preview_card.dart)
// -----------------------------------------------
//   • _subtitleStyle fontSize 11 → 10.
//   • BOTH the title Text('BEAUTY PASSPORT') and the subtitle
//     Text(l10n.homeHubPassportSubtitle) are each wrapped in
//     FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft),
//     maxLines: 2. FittedBox.scaleDown lays the paragraph out at its NATURAL
//     size (so didExceedMaxLines is false) and shrinks the painted result to
//     fit — the string can therefore never be ellipsis-cut.
//
// HOW TRUNCATION IS CAUGHT
// ------------------------
// A RenderParagraph that had to drop content to fit reports
// `didExceedMaxLines == true` (that is the signal Flutter uses to draw the
// ellipsis). Under the FittedBox fix the paragraph lays out unconstrained, so
// didExceedMaxLines is false. Each matrix cell asserts:
//   1. the full string is present via find.text (no glyphs dropped), AND
//   2. didExceedMaxLines == false on BOTH the title and subtitle paragraphs.
// Removing either FittedBox (or restoring fontSize 11 + ellipsis) flips
// didExceedMaxLines to true at the narrow / large-font cells → test FAILS.
//
// GEOMETRY — REPLICATING THE ON-SCREEN HALF-WIDTH
// -----------------------------------------------
// _StatPillsRow geometry (home_hub_screen.dart):
//   • screen horizontal padding = VelvetSpacing.lg (24) each side  → 48 total
//   • gap between the two pills  = VelvetSpacing.md - 4 (12)
//   ⇒ each pill width = (deviceWidth - 48 - 12) / 2 = (deviceWidth - 60) / 2
// We reproduce that EXACT layout: pump the full surface at the device width,
// then wrap the card in Padding(horizontal: 24) + Row[ Expanded(card),
// SizedBox(width:12), Expanded(SizedBox) ] so the card receives precisely its
// real on-screen half-width — no hand-computed magic number.

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/passport_preview_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

// The full Ukrainian subtitle that must never be ellipsis-cut.
const String _kSubtitleUk = "Твій б'юті-паспорт у Beautica";
// The untranslated brand title (locked product decision).
const String _kTitle = 'BEAUTY PASSPORT';
// The full Ukrainian "Мій рейтинг" label that must never be ellipsis-cut at the
// rating pill's narrower 2-share width.
const String _kMyRatingUk = 'Мій рейтинг';

// The narrow-width / large-font matrix the pill regressed on.
//   • 320dp — smallest supported phone (worst horizontal squeeze).
//   • 360dp — common budget-Android width.
const List<double> _matrixWidths = <double>[320, 360];
//   • 1.0 — baseline.
//   • 1.3 — the app's text-scale clamp ceiling (worst in-bounds case). At this
//     cell it was the TITLE ("PASSPORT" no longer one line) that previously
//     exceeded, so we assert the title too — not just the subtitle.
const List<double> _matrixScales = <double>[1.0, 1.3];

/// Wraps [card] so it receives EXACTLY its on-screen half-width: the real outer
/// horizontal padding (VelvetSpacing.lg each side) + the real inter-pill gap
/// (VelvetSpacing.md - 4) + a sibling Expanded, mirroring _StatPillsRow.
Widget _halfWidthPill(Widget card) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
    child: Align(
      alignment: Alignment.topCenter,
      child: Row(
        children: <Widget>[
          Expanded(child: card),
          const SizedBox(width: VelvetSpacing.md - 4),
          const Expanded(child: SizedBox.shrink()),
        ],
      ),
    ),
  );
}

/// Wraps [card] so it receives EXACTLY the MyRatingStatCard's on-screen
/// 2/5-share width: the real outer horizontal padding (VelvetSpacing.lg each
/// side) + the real inter-pill gap (VelvetSpacing.md - 4) + the sibling
/// Expanded(flex: 3) the passport pill occupies, mirroring _StatPillsRow's 3:2
/// split. The card sits in the flex-2 slot so it gets precisely its 2/5 share —
/// no hand-computed magic number.
Widget _ratingSharePill(Widget card) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
    child: Align(
      alignment: Alignment.topCenter,
      child: Row(
        children: <Widget>[
          // The passport pill's 3-share — present so the rating card receives
          // only the narrower 2/5 of the row width it has on screen.
          const Expanded(flex: 3, child: SizedBox.shrink()),
          const SizedBox(width: VelvetSpacing.md - 4),
          Expanded(flex: 2, child: card),
        ],
      ),
    ),
  );
}

/// Returns the [RenderParagraph] backing the [text] finder and asserts the full
/// string survived (no glyphs dropped) and the paragraph did NOT exceed its
/// maxLines (i.e. no ellipsis was applied).
void _expectNotTruncated(
  WidgetTester tester,
  String text, {
  required String label,
}) {
  expect(
    find.text(text),
    findsOneWidget,
    reason: '$label full string must be present (no glyphs dropped): "$text"',
  );
  final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
    find.text(text),
  );
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason:
        '$label paragraph must NOT exceed maxLines — didExceedMaxLines==true '
        'means Flutter applied an ellipsis and cut "$text". The FittedBox.'
        'scaleDown fix lays the paragraph out at natural size so this stays '
        'false.',
  );
}

void main() {
  group('PassportPreviewCard — subtitle & title never ellipsis-truncated', () {
    for (final double width in _matrixWidths) {
      for (final double scale in _matrixScales) {
        testWidgets(
          'shows full UA subtitle + title untruncated at ${width.toInt()}px '
          'width × textScale $scale (half-width pill)',
          (tester) async {
            await tester.pumpApp(
              _halfWidthPill(PassportPreviewCard(onTap: () {})),
              width: width,
              textScaleFactor: scale,
            );
            await tester.pumpAndSettle();

            // Subtitle — the primary regression target.
            _expectNotTruncated(tester, _kSubtitleUk, label: 'Subtitle');
            // Title — at 320 × 1.3 this was the line that previously exceeded.
            _expectNotTruncated(tester, _kTitle, label: 'Title');

            // No overflow surfaced as a thrown FlutterError either.
            expect(
              tester.takeException(),
              isNull,
              reason:
                  'PassportPreviewCard must not overflow at '
                  '${width.toInt()}px × textScale $scale.',
            );
          },
        );
      }
    }
  });

  // MyRatingStatCard — re-balanced to the NARROWER 2-share of the 3:2 stat-pill
  // row (passport flex 3, rating flex 2). The label "Мій рейтинг" (two words)
  // and the value ("n.n" / "—") just received fontSize 10 + FittedBox.scaleDown
  // protection with ellipsis removed. This group proves BOTH the label and the
  // value render fully (no ellipsis) at the card's real 2/5 width across the
  // narrow-width × large-font matrix; reverting the protection (fontSize 11 +
  // plain Text(overflow: ellipsis), no FittedBox) flips didExceedMaxLines true.
  group('MyRatingStatCard — label & value never ellipsis-truncated', () {
    // Rated (4.7) and empty (—) value variants — both must render fully.
    const Map<String, double?> ratingCases = <String, double?>{
      'rated 4.7': 4.7,
      'empty —': null,
    };

    for (final MapEntry<String, double?> ratingCase in ratingCases.entries) {
      final String caseName = ratingCase.key;
      final double? clientRating = ratingCase.value;
      final String valueText = clientRating != null
          ? clientRating.toStringAsFixed(1)
          : '—';

      for (final double width in _matrixWidths) {
        for (final double scale in _matrixScales) {
          testWidgets('shows full UA label + value ($caseName) untruncated at '
              '${width.toInt()}px width × textScale $scale (2/5-share pill)', (
            tester,
          ) async {
            await tester.pumpApp(
              _ratingSharePill(
                MyRatingStatCard(clientRating: clientRating, onTap: () {}),
              ),
              width: width,
              textScaleFactor: scale,
            );
            await tester.pumpAndSettle();

            // Label — the primary regression target at the narrow 2-share.
            _expectNotTruncated(tester, _kMyRatingUk, label: 'Rating label');
            // Value — short, but the guard asserts it is rendered fully too.
            _expectNotTruncated(tester, valueText, label: 'Rating value');

            // No overflow surfaced as a thrown FlutterError either.
            expect(
              tester.takeException(),
              isNull,
              reason:
                  'MyRatingStatCard must not overflow at '
                  '${width.toInt()}px × textScale $scale ($caseName).',
            );
          });
        }
      }
    }
  });
}
