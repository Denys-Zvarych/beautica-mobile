// Phase 415 — BookingLinkCard in-flight dim (pixel probe) + additive defaults.
//
// The `busy` Share/Copy dim is gated here by real pixels (dim_probe), as the
// `forbid_unclassified_layer_dim.sh` `dim-gated:` marker requires. Layer:
// Widget.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking_links/domain/booking_link.dart';
import 'package:beautica_mobile/features/booking_links/presentation/widgets/booking_link_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/dim_probe.dart';
import '../../../../helpers/pump_app.dart';

const BookingLink _master = BookingLink(
  kind: BookingLinkKind.master,
  slug: 'olena-koval-x7k2',
  url: 'https://beautica.app/book/olena-koval-x7k2',
  displayName: 'Олена Коваль',
  bookable: true,
);

const BookingLink _revoked = BookingLink(
  kind: BookingLinkKind.master,
  slug: null,
  url: null,
  displayName: 'Олена Коваль',
  bookable: false,
  status: BookingLinkStatus.revoked,
);

Future<void> _pumpCard(
  WidgetTester tester, {
  BookingLink link = _master,
  bool busy = false,
  VoidCallback? onRegenerate,
  Future<bool> Function()? onCopy,
  VoidCallback? onShare,
}) async {
  await tester.pumpApp(
    RepaintBoundary(
      child: ColoredBox(
        color: BrandColors.base,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: BookingLinkCard(
            link: link,
            onCopy: onCopy ?? () async => true,
            onShare: onShare ?? () {},
            onRegenerate: onRegenerate,
            busy: busy,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  const Key share = Key('btn-booking-link-share-olena-koval-x7k2');

  testWidgets('defaults: no regenerate glyph, actions undimmed', (
    tester,
  ) async {
    await _pumpCard(tester);

    expect(
      find.byKey(const Key('btn-booking-link-regenerate-olena-koval-x7k2')),
      findsNothing,
    );
    // One stable subtree (no remount on toggle): idle = full opacity and
    // taps pass through.
    final Finder dim = find.ancestor(
      of: find.byKey(share),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(dim.first).opacity, 1);
    final Finder gate = find.ancestor(
      of: find.byKey(share),
      matching: find.byType(IgnorePointer),
    );
    expect(tester.widget<IgnorePointer>(gate.first).ignoring, isFalse);
  });

  testWidgets('busy: Share composites to 0.5 of its resting pixels', (
    tester,
  ) async {
    await expectRegionDimRatio(
      tester: tester,
      target: find.byKey(share),
      pumpFull: () => _pumpCard(tester, onRegenerate: () {}),
      pumpDimmed: () => _pumpCard(tester, onRegenerate: () {}, busy: true),
      ground: BrandColors.base,
      expected: 0.5,
    );
  });

  const Key regen = Key('btn-booking-link-regenerate-olena-koval-x7k2');
  const Key spinner = Key('booking-link-busy-olena-koval-x7k2');
  const Key copy = Key('btn-booking-link-copy-olena-koval-x7k2');

  testWidgets('onRegenerate set → glyph shown with its semantic label; tap '
      'fires once', (tester) async {
    int taps = 0;
    await _pumpCard(tester, onRegenerate: () => taps++);

    expect(find.byKey(regen), findsOneWidget);
    expect(find.byKey(spinner), findsNothing);
    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(BookingLinkCard)),
    );
    expect(find.bySemanticsLabel(l10n.bookingLinkRegenerate), findsWidgets);
    await tester.tap(find.byKey(regen));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('busy → spinner replaces the glyph; Share / Copy taps are '
      'swallowed', (tester) async {
    int regenTaps = 0;
    int shares = 0;
    int copies = 0;
    await _pumpCard(
      tester,
      busy: true,
      onRegenerate: () => regenTaps++,
      onShare: () => shares++,
      onCopy: () async {
        copies++;
        return true;
      },
    );

    expect(find.byKey(spinner), findsOneWidget);
    expect(find.byKey(regen), findsNothing);
    final Finder dim = find.ancestor(
      of: find.byKey(share),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(dim.first).opacity, 0.5);
    await tester.tap(find.byKey(share), warnIfMissed: false);
    await tester.tap(find.byKey(copy), warnIfMissed: false);
    await tester.tap(find.byKey(spinner), warnIfMissed: false);
    await tester.pump();

    expect(shares, 0);
    expect(copies, 0);
    expect(regenTaps, 0);
  });

  testWidgets('idle (control for the busy test) → Share / Copy taps land', (
    tester,
  ) async {
    int shares = 0;
    int copies = 0;
    await _pumpCard(
      tester,
      onRegenerate: () {},
      onShare: () => shares++,
      onCopy: () async {
        copies++;
        return true;
      },
    );

    await tester.tap(find.byKey(share));
    await tester.tap(find.byKey(copy));
    await tester.pump();

    expect(shares, 1);
    expect(copies, 1);
    await tester.pump(BookingLinkCard.copiedDwell);
  });

  group('revoked link', () {
    const Key recreate = Key('btn-booking-link-recreate-revoked-master');

    testWidgets('revoked state, no URL / Share / Copy / header glyph; CTA '
        'calls onRegenerate', (tester) async {
      int taps = 0;
      await _pumpCard(tester, link: _revoked, onRegenerate: () => taps++);

      expect(
        find.byKey(const Key('booking-link-revoked-revoked-master')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('booking-link-url-revoked-master')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('btn-booking-link-share-revoked-master')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('btn-booking-link-regenerate-revoked-master')),
        findsNothing,
      );
      await tester.tap(find.byKey(recreate));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('onRegenerate null → the CTA is disabled', (tester) async {
      await _pumpCard(tester, link: _revoked);

      final NeumorphicButton cta = tester.widget<NeumorphicButton>(
        find.descendant(
          of: find.byKey(recreate),
          matching: find.byType(NeumorphicButton),
        ),
      );
      expect(cta.onPressed, isNull);
    });

    testWidgets('busy → the CTA shows its loading state, taps blocked', (
      tester,
    ) async {
      int taps = 0;
      await _pumpCard(
        tester,
        link: _revoked,
        busy: true,
        onRegenerate: () => taps++,
      );

      final NeumorphicButton cta = tester.widget<NeumorphicButton>(
        find.descendant(
          of: find.byKey(recreate),
          matching: find.byType(NeumorphicButton),
        ),
      );
      expect(cta.loading, isTrue);
      await tester.tap(find.byKey(recreate), warnIfMissed: false);
      await tester.pump();

      expect(taps, 0);
    });
  });
}
