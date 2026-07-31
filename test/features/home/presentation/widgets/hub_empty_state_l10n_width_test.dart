// Regression test — home-hub empty-state card width must be INDEPENDENT of the
// l10n message copy.
//
// Companion to `hub_empty_state_width_test.dart`. That file pins the widths
// with the REAL ARB strings; this one pins the *invariant behind* them.
//
// The original bug was caused purely by string length: the section widgets'
// outer `Column(crossAxisAlignment: CrossAxisAlignment.start)` hands children
// LOOSE width constraints, so an unpinned `HubFlatCard` shrinks to its widest
// child — the message `Text`. `homeHubTimelineEmpty` is one short line, so its
// card rendered ~233dp inside a 312dp row while the long two-line
// `homeHubFavoriteMastersEmpty` filled the full 312dp.
//
// Asserting only against today's ARB values would therefore leave the real
// hazard uncovered: a future copy edit (a shorter Ukrainian string, a shorter
// English string, a new locale) would resurrect the bug while the existing
// tests stayed green. These tests swap the messages out from under the
// production widgets via a stub `AppLocalizations` and assert the rendered
// width does not move — a one-word message and a 200-character message must
// both produce exactly the full content width.
//
// All three home-hub empty states are covered, not just the two that regressed.
// Honest scope note on the third one: «Наступний запис» sits directly above the
// other two, shares the identical `Column(start)` + `HubFlatCard` structure, and
// so carries the same latent hazard — but it does NOT shrink today even without
// its `SizedBox`, because `HubEmptyState`'s CTA (`HubFilledButton` → aligned
// `Container`) already expands to the loose max. Its assertions here therefore
// pin the CROSS-CARD ALIGNMENT invariant the user actually reported (all three
// empty cards line up), not the copy-length hazard; they would keep passing if
// its `SizedBox` were removed while the CTA stayed. The copy-length regression
// itself is guarded by the favourites and timeline entries, which do go red.
//
// Layer: Widget. None of the three sections reads a provider at build time.

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/beauty_timeline_section.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/favorite_masters_card.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/next_appointment_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/overflow_guard.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

void _noop() {}

/// Surface + padding mirror `home_hub_screen.dart`'s ListView, which pads
/// `VelvetSpacing.lg` on both sides.
const double _surface = 360;
const double _contentWidth = _surface - VelvetSpacing.lg * 2;

/// Deliberately extreme copy. The point is the RANGE: if either value can move
/// the rendered card width, the loose-constraint bug is back.
const String _shortMessage = 'Ok';
const String _longMessage =
    'This deliberately verbose empty-state message exists only to prove that a '
    'very long line of copy cannot make the card any wider than the content '
    'row it lives in, just as a two-character message cannot make it narrower.';

/// Keys of the three home-hub empty-state cards, in on-screen order.
const List<String> _cardKeys = <String>[
  'next_appointment_empty_card',
  'favorite_masters_empty',
  'timeline_empty',
];

/// [AppLocalizations] with the three home-hub empty-state messages swapped for
/// a caller-supplied string. Everything else falls through to the real Ukrainian
/// translations, so the widgets render exactly as they do in production.
class _StubMessages extends AppLocalizationsUk {
  _StubMessages(this.message);

  final String message;

  @override
  String get homeHubTimelineEmpty => message;

  @override
  String get homeHubFavoriteMastersEmpty => message;

  @override
  String get homeHubNoUpcomingAppointments => message;
}

/// Delegate that wins over the generated one: `Localizations` loads only the
/// FIRST delegate registered for a given type, so prepending this to
/// [AppLocalizations.localizationsDelegates] replaces it.
class _StubMessagesDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _StubMessagesDelegate(this.message);

  final String message;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(_StubMessages(message));

  @override
  bool shouldReload(_StubMessagesDelegate old) => old.message != message;
}

/// Pumps all three home-hub empty states as siblings of one padded ListView,
/// exactly as `home_hub_screen.dart` composes them.
///
/// [message] (when non-null) replaces the three empty-state strings; passing
/// null keeps the real ARB copy for [locale].
Future<void> _pumpEmptyStates(
  WidgetTester tester, {
  String? message,
  Locale locale = const Locale('uk'),
  double surface = _surface,
  double? textScaleFactor,
}) async {
  installOverflowGuard();
  tester.view.physicalSize = Size(surface, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      child: MaterialApp(
        localizationsDelegates: <LocalizationsDelegate<dynamic>>[
          if (message != null) _StubMessagesDelegate(message),
          ...AppLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: textScaleFactor == null
            ? null
            : (BuildContext context, Widget? child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
                child: child!,
              ),
        home: ListView(
          padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
          children: const <Widget>[
            NextAppointmentCard(
              appointment: null,
              onReschedule: _noop,
              onCancel: _noop,
              onAddToGoogleCalendar: _noop,
              onAddToAppleCalendar: _noop,
            ),
            SizedBox(height: VelvetSpacing.lg),
            FavoriteMastersCard(masters: <FavoriteMasterItem>[], totalCount: 0),
            SizedBox(height: VelvetSpacing.lg),
            BeautyTimelineSection(entries: <TimelineEntry>[], onSeeAll: _noop),
          ],
        ),
      ),
    ),
  );
}

/// Rendered width of every home-hub empty-state card, keyed by widget key.
Map<String, double> _cardWidths(WidgetTester tester) {
  return <String, double>{
    for (final String key in _cardKeys)
      key: tester.getSize(find.byKey(Key(key))).width,
  };
}

void main() {
  group('Home-hub empty-state width is independent of the l10n message', () {
    testWidgets('a two-character message still fills the content row', (
      WidgetTester tester,
    ) async {
      await _pumpEmptyStates(tester, message: _shortMessage);

      expect(
        _cardWidths(tester),
        <String, double>{for (final String k in _cardKeys) k: _contentWidth},
        reason:
            'An empty-state card that shrinks to its message width is the '
            'exact regression this guards: shortening any ARB string must not '
            'change how wide the card renders.',
      );
    });

    testWidgets('a 200-character message never exceeds the content row', (
      WidgetTester tester,
    ) async {
      await _pumpEmptyStates(tester, message: _longMessage);

      expect(
        _cardWidths(tester),
        <String, double>{for (final String k in _cardKeys) k: _contentWidth},
        reason:
            'Long copy must wrap inside the card, never widen it past the '
            'padded ListView content row.',
      );
    });

    testWidgets('short and long copy render byte-identical widths', (
      WidgetTester tester,
    ) async {
      await _pumpEmptyStates(tester, message: _shortMessage);
      final Map<String, double> short = _cardWidths(tester);

      await _pumpEmptyStates(tester, message: _longMessage);
      final Map<String, double> long = _cardWidths(tester);

      expect(
        short,
        long,
        reason:
            'Card width must be a function of the available content width '
            'ONLY — never of the message copy.',
      );
    });

    testWidgets('English copy renders the same widths as Ukrainian', (
      WidgetTester tester,
    ) async {
      // Real ARB strings, and the uk/en pairs differ in length — this catches a
      // locale-specific copy edit that a uk-only assertion would miss.
      await _pumpEmptyStates(tester, locale: const Locale('uk'));
      final Map<String, double> uk = _cardWidths(tester);

      await _pumpEmptyStates(tester, locale: const Locale('en'));
      final Map<String, double> en = _cardWidths(tester);

      expect(uk, <String, double>{
        for (final String k in _cardKeys) k: _contentWidth,
      });
      expect(en, uk, reason: 'Empty-state widths must not vary by locale.');
    });

    testWidgets('short copy still fills the row at 320dp / textScale 1.3', (
      WidgetTester tester,
    ) async {
      // The sibling `hub_empty_state_width_test.dart` also probes this stress
      // size, but with the REAL strings — and at 320dp/1.3 the real Ukrainian
      // timeline copy already wraps wide enough to fill the row on its own, so
      // that assertion passes even on unfixed code (verified). Driving the same
      // surface with the two-character stub makes the narrow/large-font case
      // actually load-bearing.
      const double narrowContent = 320 - VelvetSpacing.lg * 2;

      await _pumpEmptyStates(
        tester,
        message: _shortMessage,
        surface: 320,
        textScaleFactor: 1.3,
      );

      expect(_cardWidths(tester), <String, double>{
        for (final String k in _cardKeys) k: narrowContent,
      });
    });
  });
}
