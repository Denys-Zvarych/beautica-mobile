// Width-axis tap-target floor for `HubFilledButton` / `HubOutlineButton`
// (`lib/features/home/presentation/widgets/hub_widgets.dart`).
//
// WHY THIS FILE EXISTS
// ---------------------
// `hub_filled_button_tap_target_test.dart` / `hub_outline_button_tap_target_test
// .dart` fixed and pinned the HEIGHT axis only — deliberately:
// `_HubFilledButtonState.build`'s own doc comment records that widening the
// invisible margin on the width axis too would be "pure ceremony with no
// caller it actually protects", because every real label today renders
// comfortably over the 48dp floor on width alone (no `Padding` needed there).
//
// That claim is true today and is NOT re-litigated here — this file does not
// add a width `Padding`, and does not argue the design decision was wrong.
// What it protects against is different: the claim's truth depends entirely
// on the ACTUAL rendered length of four ARB strings, each of which is
// free-text content a translator or PM can shorten in
// `app_uk.arb`/`app_en.arb` with zero pixel awareness and zero build-time
// signal that the accessibility floor was riding on their current length.
//
// HOW THE PROBE IS CONSTRAINED — this is the part that matters
// --------------------------------------------------------------
// A first version of this file pumped each button under a bare `Center`.
// That measured 800dp (the test surface width) for EVERY label, short or
// long — vacuous, because `Center` hands the button a *loose* constraint
// with a *finite* max, and `_HubFilledButtonState.build`'s own doc comment
// already documents exactly this trap: `Container`'s internal
// `alignment: Alignment.center` makes it an `Align`, and `RenderPositionedBox`
// FILLS to any finite loose max on an unconstrained axis. A bare `Center`
// test can never observe a label-driven width regression; it would report
// 800dp right up to the moment the app itself broke some other way.
//
// `wishlist_row.dart` hits the identical trap in production and solves it the
// same way this file does: `IntrinsicWidth` (line ~352, wrapping the exact
// same `HubFilledButton`), which forces the child to report its own
// shrink-to-fit width instead of filling the incoming max. Wrapping each case
// below in `IntrinsicWidth` is therefore not an invented test-only
// constraint — it reproduces `wishlist_row.dart`'s real layout, and for
// every OTHER real call site (which let the button stretch to an ambient
// card/column that is always far wider than 48dp — `wishlist_compact_card
// .dart`, `wishlist_states.dart`, `passport_screen.dart`'s retry CTAs) the
// intrinsic width this file measures is a lower bound: those callers only
// render WIDER than what is measured here, never narrower. So this is the
// single genuinely at-risk measurement, not four redundant ones.
//
// Reading each label through `AppLocalizations` rather than hardcoding the
// current Ukrainian/English strings is the other half of the point: a copy
// edit that shrinks `wishlistBookCta` from "Book" to "Go" changes what THIS
// test measures too, because it re-resolves the string from the live
// ARB-generated getter every run — a hardcoded literal would keep measuring
// the string as it read on the day this file was written and go stale the
// moment the ARB value changed. A synthetic single-character label was
// deliberately NOT added as a permanent case: it would prove nothing a real
// caller could ever hit — see the mutation proof at the bottom of this
// comment for where that probe belongs instead (nowhere in the committed
// suite).
//
// `homeHubChangePhotoLabel` is NOT covered here: it is a `Semantics.label`
// on a bare `GestureDetector`/`Container` avatar-camera badge in
// `passport_screen.dart` (~line 516) — a DIFFERENT control that never
// constructs a `HubFilledButton` at all. `HubOutlineButton.danger` is also
// NOT covered: it has zero callers in this codebase today (`grep -rn
// 'danger:' lib/features` is empty) — a label for a caller that doesn't
// exist would be exactly the speculative case this file argues against.
// When a `danger` call site ships, add its real label to the
// `HubOutlineButton` case list below rather than inventing one now.
//
// MUTATION PROOF (repo's own idiom, not a committed case — see above): pump
// `IntrinsicWidth(child: HubFilledButton(label: 'Ой', onTap: () {}))` under
// this same harness. Measured width: 50.2dp for that two-glyph label — barely
// above the 48dp floor — and 42.4dp for a genuine one-glyph label ('O'),
// which DOES fail `greaterThanOrEqualTo(_kPlatformMinTapExtent)`. So the
// assertion is load-bearing against label length (a short-enough label makes
// it fail), not vacuously true regardless of content the way the original
// bare-`Center` version was (see above — that one measured 800dp for every
// label, including 'O'). Every real case below (narrowest today: "Book" at
// 62.3dp) has real margin above that observed failure boundary, but the
// margin is not large — a `danger` variant with a short label, or a further
// ARB shortening beyond what exists today, could plausibly cross it.
//
// Layer: Widget. No providers — both widgets are `StatefulWidget`s with no
// Riverpod dependency.

import 'package:beautica_mobile/features/home/presentation/widgets/hub_widgets.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

/// Mirrors `hub_*_tap_target_test.dart`'s `_kPlatformMinTapExtent` — the
/// larger of Android's 48dp and iOS's 44pt tap-target floor (WCAG 2.5.5,
/// Material, HIG), re-derived from the public spec rather than imported from
/// `hub_widgets.dart`'s private `_kMinTapExtent`.
const double _kPlatformMinTapExtent = 48;

const List<Locale> _kLocales = <Locale>[Locale('uk'), Locale('en')];

void main() {
  group('HubFilledButton width floor — real ARB labels, both locales', () {
    final Map<String, String Function(AppLocalizations)> cases =
        <String, String Function(AppLocalizations)>{
          // wishlist_row.dart / wishlist_compact_card.dart via
          // bookCtaLabel() — MASTER-row arm.
          'wishlistBookCta': (l10n) => l10n.wishlistBookCta,
          // wishlist_row.dart / wishlist_compact_card.dart via
          // bookCtaLabel() — SALON-row arm.
          'wishlistChooseMasterCta': (l10n) => l10n.wishlistChooseMasterCta,
          // wishlist_states.dart + passport_screen.dart (x2) retry CTAs.
          'retryLabel': (l10n) => l10n.retryLabel,
        };

    for (final MapEntry<String, String Function(AppLocalizations)> entry
        in cases.entries) {
      for (final Locale locale in _kLocales) {
        testWidgets('${entry.key} (${locale.languageCode}) clears 48dp wide', (
          tester,
        ) async {
          late String resolvedLabel;
          await tester.pumpApp(
            Center(
              // See the file header: `IntrinsicWidth` is what makes this
              // probe non-vacuous, and mirrors `wishlist_row.dart`'s own
              // real wrapper around this exact widget.
              child: IntrinsicWidth(
                child: Builder(
                  builder: (context) {
                    resolvedLabel = entry.value(AppLocalizations.of(context));
                    return HubFilledButton(label: resolvedLabel, onTap: () {});
                  },
                ),
              ),
            ),
            locale: locale,
          );
          await tester.pumpAndSettle();

          final double width = tester
              .getRect(find.byType(HubFilledButton))
              .width;
          expect(
            width,
            greaterThanOrEqualTo(_kPlatformMinTapExtent),
            reason:
                'HubFilledButton rendering the LIVE ${entry.key} '
                '(${locale.languageCode}) string "$resolvedLabel" measured '
                '${width}dp wide at its natural (IntrinsicWidth) size — '
                'under the 48dp floor. This label used to clear it on '
                'length alone with no `Padding` protecting the width axis '
                '(see this file\'s header); either the ARB copy shrank, or '
                'the width axis now needs the same `Padding(horizontal:)` '
                'treatment the height axis already has.',
          );
        });
      }
    }
  });

  group('HubOutlineButton width floor — real ARB labels, both locales', () {
    for (final Locale locale in _kLocales) {
      testWidgets(
        'wishlistShowAll(5) (${locale.languageCode}) clears 48dp wide',
        (tester) async {
          late String resolvedLabel;
          await tester.pumpApp(
            Center(
              child: IntrinsicWidth(
                child: Builder(
                  builder: (context) {
                    // wishlist_section.dart's own call: `l10n.wishlistShowAll
                    // (visible)`. 5 mirrors `hub_outline_button_tap_target_test
                    // .dart`'s own probe label for the same reason: a
                    // plausible real remainder count, not a boundary chosen
                    // to make the assertion easy. `HubOutlineButton` has no
                    // `IntrinsicWidth` wrapper at its one real call site
                    // (`wishlist_section.dart`) because that `Column`'s
                    // ambient width is already always >48dp — this probe
                    // still applies one to measure the same worst-case
                    // natural-width lower bound as the filled-button cases.
                    resolvedLabel = AppLocalizations.of(
                      context,
                    ).wishlistShowAll(5);
                    return HubOutlineButton(label: resolvedLabel, onTap: () {});
                  },
                ),
              ),
            ),
            locale: locale,
          );
          await tester.pumpAndSettle();

          final double width = tester
              .getRect(find.byType(HubOutlineButton))
              .width;
          expect(
            width,
            greaterThanOrEqualTo(_kPlatformMinTapExtent),
            reason:
                'HubOutlineButton rendering the LIVE wishlistShowAll(5) '
                '(${locale.languageCode}) string "$resolvedLabel" measured '
                '${width}dp wide at its natural (IntrinsicWidth) size — '
                'under the 48dp floor.',
          );
        },
      );
    }
  });
}
