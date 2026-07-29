// Regression test — home-hub empty-state cards must be the SAME width.
//
// Bug: the BEAUTY TIMELINE empty state rendered visibly narrower than the
// favourite-masters empty state on the same page. Both sections are siblings of
// the same ListView (uniform horizontal padding), so the available width was
// identical — the divergence came from INSIDE the section widgets: their outer
// `Column(crossAxisAlignment: CrossAxisAlignment.start)` hands children LOOSE
// width constraints, so an unpinned `HubFlatCard` sized itself to its widest
// child (the message `Text`). `homeHubFavoriteMastersEmpty` is a long two-line
// string that filled the row; `homeHubTimelineEmpty` is one short line, so its
// card shrank.
//
// Both cards are now wrapped in `SizedBox(width: double.infinity)`, making their
// width a function of the available content width ONLY — never of the message
// copy. This test pins that: a revert on either side goes red, and so does any
// future l10n edit that would have re-introduced a text-length dependency.
//
// Layer: Widget. Both sections read no provider at build time, so they pump
// under the default ProviderScope installed by pumpApp.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/home_hub_screen.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/beauty_timeline_section.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/favorite_masters_card.dart';
import 'package:beautica_mobile/features/rating/application/my_rating_notifier.dart';
import 'package:beautica_mobile/features/rating/domain/client_rating.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

void _noop() {}

/// No-op screen protection — the native plugin must not be called in tests.
class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}

  @override
  void release() {}

  @override
  void reset() {}
}

const ClientProfileSummary _emptyStateProfile = ClientProfileSummary(
  firstName: 'Test',
  lastName: 'Client',
  city: 'Lviv',
  phone: '+380 97 000 00 00',
  clientRating: null,
  memberSinceYear: 2026,
);

/// All three hub sections in their EMPTY state, on the real screen.
List<Object> _emptyOverrides() {
  return <Object>[
    screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
    myRatingProvider.overrideWith((ref) async => const ClientRating()),
    clientProfileProvider.overrideWith((ref) async => _emptyStateProfile),
    nextAppointmentProvider.overrideWith((ref) async => null),
    favoriteMastersProvider.overrideWith(
      (ref) async => const <FavoriteMasterItem>[],
    ),
    beautyTimelineProvider.overrideWith((ref) async => const <TimelineEntry>[]),
    unlikeFavoriteMasterProvider.overrideWith(() => UnlikeFavoriteMaster()),
  ];
}

/// Mirrors the real home-hub list: both sections as siblings of one ListView
/// with the screen's uniform `VelvetSpacing.lg` horizontal padding.
Future<void> _pumpBothSections(
  WidgetTester tester, {
  required double width,
  double? textScaleFactor,
}) {
  return tester.pumpApp(
    ListView(
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
      children: const <Widget>[
        FavoriteMastersCard(masters: <FavoriteMasterItem>[], totalCount: 0),
        SizedBox(height: VelvetSpacing.lg),
        BeautyTimelineSection(entries: <TimelineEntry>[], onSeeAll: _noop),
      ],
    ),
    width: width,
    textScaleFactor: textScaleFactor,
  );
}

double _cardWidth(WidgetTester tester, String key) =>
    tester.getSize(find.byKey(Key(key))).width;

void main() {
  group('Home-hub empty-state cards — width parity', () {
    testWidgets('timeline and favourites empty cards are the same width', (
      WidgetTester tester,
    ) async {
      await _pumpBothSections(tester, width: 360);

      expect(find.byKey(const Key('favorite_masters_empty')), findsOneWidget);
      expect(find.byKey(const Key('timeline_empty')), findsOneWidget);

      expect(
        _cardWidth(tester, 'timeline_empty'),
        _cardWidth(tester, 'favorite_masters_empty'),
        reason:
            'BEAUTY TIMELINE and favourite-masters empty states are siblings of '
            'the same padded ListView — their cards must render identically '
            'wide.',
      );
    });

    testWidgets(
      'both cards fill the full content width, not their text width',
      (WidgetTester tester) async {
        const double surface = 360;
        // ListView padding is symmetric horizontal VelvetSpacing.lg.
        const double expected = surface - VelvetSpacing.lg * 2;

        await _pumpBothSections(tester, width: surface);

        expect(
          _cardWidth(tester, 'timeline_empty'),
          expected,
          reason:
              'Card width must derive from the available content width, so a '
              'shorter message string can never shrink it.',
        );
        expect(_cardWidth(tester, 'favorite_masters_empty'), expected);
      },
    );

    testWidgets('width parity holds at 320dp / textScale 1.3 (no overflow)', (
      WidgetTester tester,
    ) async {
      // The overflow guard installed by pumpApp fails this test in tearDown on
      // any RenderFlex overflow at the stress size — no manual assertion needed.
      await _pumpBothSections(tester, width: 320, textScaleFactor: 1.3);

      expect(
        _cardWidth(tester, 'timeline_empty'),
        _cardWidth(tester, 'favorite_masters_empty'),
      );
      expect(_cardWidth(tester, 'timeline_empty'), 320 - VelvetSpacing.lg * 2);
    });
  });

  // Every test above pumps a HAND-COPIED ListView that mirrors
  // `home_hub_screen.dart`'s padding. That harness is the right tier for the
  // constraint bug itself, but it can drift: if the screen ever wraps one
  // section differently (an Align, an IntrinsicWidth, a different padding),
  // the harness would keep passing while the real page went crooked again.
  // These pump the ACTUAL HomeHubScreen so composition is covered too.
  group('Real HomeHubScreen — empty-state cards line up', () {
    testWidgets('all three empty cards render at the same width', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        const HomeHubScreen(),
        overrides: _emptyOverrides(),
        width: 360,
      );
      await tester.pumpAndSettle();

      const double expected = 360 - VelvetSpacing.lg * 2;
      expect(_cardWidth(tester, 'next_appointment_empty_card'), expected);
      expect(_cardWidth(tester, 'favorite_masters_empty'), expected);
      expect(
        _cardWidth(tester, 'timeline_empty'),
        expected,
        reason:
            'On the real screen the three empty-state cards are siblings of '
            'one padded ListView — a user seeing one narrower than the others '
            'is the exact bug reported.',
      );
    });

    testWidgets('parity survives a 320dp surface at textScale 1.3', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        const HomeHubScreen(),
        overrides: _emptyOverrides(),
        width: 320,
        textScaleFactor: 1.3,
      );
      await tester.pumpAndSettle();

      const double expected = 320 - VelvetSpacing.lg * 2;
      expect(_cardWidth(tester, 'next_appointment_empty_card'), expected);
      expect(_cardWidth(tester, 'favorite_masters_empty'), expected);
      expect(_cardWidth(tester, 'timeline_empty'), expected);
    });
  });
}
