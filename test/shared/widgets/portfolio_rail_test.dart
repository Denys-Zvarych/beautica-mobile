// Widget tests for `PortfolioRail` / `PortfolioTile`
// (lib/shared/widgets/portfolio_rail.dart).
//
// Written 2026-09-01 by mobile-qa alongside the shared-widget promotion that
// turned two hand-duplicated private portfolio rails (in
// `master_profile_screen.dart` and `public_master_profile_screen.dart`) plus
// a brand-new third consumer (`salon_management_profile_screen.dart`) into
// this single shared widget. Screen-level tests already pin PRESENCE of the
// rail per consumer (`public-master-profile-portfolio` key absence/presence
// by master type, `salon-manage-portfolio` position — see
// `salon_management_profile_screen_test.dart`), but until this file existed
// nothing tested the widget's OWN contract in isolation:
//
//   1. The `onSeeAll` fork — the ONE behavioural divergence the promotion
//      had to preserve between the master's own editable profile (link
//      visible) and the read-only public master / salon screens (link
//      omitted). Nothing pinned this at the widget level, so a future "always
//      show the link" edit would silently change two of the three consumers
//      with no test going red.
//   2. The tile's Semantics contract — `image: true`, NOT `button: true`.
//      This was a `mobile-security` fix in the same chain that produced this
//      widget (the tile press-flash reads as a photo, not an actionable
//      control, since tapping currently does nothing). Read via
//      `tester.getSemantics(...).getSemanticsData().flagsCollection`, never
//      a constructor field.
//   3. Tile count + the `index % 6` gradient wrap — proven BEHAVIOURALLY
//      (tile 0's rendered gradient colors == tile 6's, and != tile 1's)
//      rather than against hard-coded palette constants, so the test survives
//      a future palette change and still catches a broken modulus.
//
// Isolation: `PortfolioRail`/`PortfolioTile` take no Riverpod providers —
// plain constructor args, `AppLocalizations.of(context)` only. Every test
// pumps via the shared `pumpApp` helper (installs the overflow guard,
// configures l10n).

import 'dart:io';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_edit_controller.dart'
    show PendingPortfolioUpload;
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart'
    show UploadNetworkFailure, kPortfolioMaxPhotos;
import 'package:beautica_mobile/core/widgets/upload_state_overlay.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// UA copy resolved from the ARB (no Cyrillic literals in finders).
final AppLocalizations _l10n = lookupAppLocalizations(const Locale('uk'));

void main() {
  group('PortfolioRail — onSeeAll contract', () {
    testWidgets('renders the «Всі фото» link when onSeeAll is supplied', (
      tester,
    ) async {
      int tapCount = 0;
      await tester.pumpApp(
        Scaffold(body: PortfolioRail(onSeeAll: () => tapCount++)),
      );
      await tester.pumpAndSettle();

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(PortfolioRail)),
      );
      final Finder link = find.text(l10n.masterAllPhotos);
      expect(link, findsOneWidget);

      await tester.tap(link);
      expect(
        tapCount,
        1,
        reason: 'the link must actually fire the supplied callback',
      );
    });

    testWidgets(
      'omits the «Всі фото» link entirely when onSeeAll is null — used by '
      'the read-only public master profile and the salon «Про салон» tab, '
      'neither of which has a gallery route yet',
      (tester) async {
        await tester.pumpApp(const Scaffold(body: PortfolioRail()));
        await tester.pumpAndSettle();

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(PortfolioRail)),
        );
        expect(find.text(l10n.masterAllPhotos), findsNothing);
        // The section label itself must still render — only the link is
        // conditional, not the whole header.
        expect(find.text(l10n.masterPortfolioLabel), findsOneWidget);
      },
    );
  });

  group('PortfolioRail — tile count', () {
    testWidgets('renders exactly `count` PortfolioTile widgets', (
      tester,
    ) async {
      await tester.pumpApp(const Scaffold(body: PortfolioRail(count: 4)));
      await tester.pumpAndSettle();

      expect(find.byType(PortfolioTile), findsNWidgets(4));
    });

    testWidgets('defaults to 6 tiles when count is not supplied', (
      tester,
    ) async {
      await tester.pumpApp(const Scaffold(body: PortfolioRail()));
      await tester.pumpAndSettle();

      expect(find.byType(PortfolioTile), findsNWidgets(6));
    });
  });

  group('PortfolioTile — gradient index wrap', () {
    /// The AnimatedContainer's resolved gradient colors for the tile at
    /// [index] within a pumped [PortfolioRail]. Reads the ACTUAL painted
    /// decoration the widget computed from `index % _fills.length`, not a
    /// hard-coded palette constant — so this stays valid even if the
    /// palette itself changes, and only breaks if the wrap logic breaks.
    List<Color> gradientColorsFor(WidgetTester tester, int index) {
      final Finder tileFinder = find.byWidgetPredicate(
        (Widget w) => w is PortfolioTile && w.index == index,
      );
      final AnimatedContainer container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: tileFinder,
          matching: find.byType(AnimatedContainer),
        ),
      );
      final BoxDecoration decoration = container.decoration! as BoxDecoration;
      return (decoration.gradient! as LinearGradient).colors;
    }

    testWidgets(
      'tile 6 wraps back to tile 0\'s gradient (index % 6); tile 1 differs '
      'from both',
      (tester) async {
        // 7 tiles (indices 0..6) so index 6 is reachable — production
        // callers all use the default count of 6, but the wrap only
        // becomes observable one tile past that.
        await tester.pumpApp(const Scaffold(body: PortfolioRail(count: 7)));
        await tester.pumpAndSettle();

        final List<Color> tile0 = gradientColorsFor(tester, 0);
        final List<Color> tile1 = gradientColorsFor(tester, 1);
        final List<Color> tile6 = gradientColorsFor(tester, 6);

        expect(
          tile6,
          equals(tile0),
          reason:
              '6 % 6 == 0 — the palette must wrap, not throw or repeat '
              'the last entry',
        );
        expect(
          tile1,
          isNot(equals(tile0)),
          reason:
              'sanity check that adjacent tiles are NOT accidentally '
              'identical (which would make the wrap assertion above '
              'vacuous)',
        );
      },
    );
  });

  group('PortfolioTile — semantics contract (mobile-security fix)', () {
    testWidgets('announces image: true, NOT button: true — the tile has no tap '
        'handler yet, so a screen reader must not claim it is actionable', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpApp(
        const Scaffold(
          body: PortfolioTile(key: Key('tile-under-test'), index: 0),
        ),
      );
      await tester.pumpAndSettle();

      final SemanticsData data = tester
          .getSemantics(find.byKey(const Key('tile-under-test')))
          .getSemanticsData();

      expect(data.flagsCollection.isImage, isTrue);
      expect(data.flagsCollection.isButton, isFalse);

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byKey(const Key('tile-under-test'))),
      );
      expect(data.label, l10n.masterPortfolioTileSemantics(1));

      handle.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // Phase 404 (9.9) — real photos, additively.
  // -------------------------------------------------------------------------
  const List<PortfolioPhoto> photos = <PortfolioPhoto>[
    PortfolioPhoto(id: 'p1', url: 'https://media.test/1.webp'),
    PortfolioPhoto(id: 'p2', url: 'https://media.test/2.webp'),
    PortfolioPhoto(id: 'p3', url: 'https://media.test/3.webp'),
  ];

  group('PortfolioRail — null photos (regression: unchanged path)', () {
    testWidgets('renders the 6 gradient placeholders, no RemoteImage, no '
        'empty/error line', (tester) async {
      await tester.pumpApp(const Scaffold(body: PortfolioRail()));
      await tester.pumpAndSettle();

      expect(find.byType(PortfolioTile), findsNWidgets(6));
      expect(
        tester
            .widgetList<PortfolioTile>(find.byType(PortfolioTile))
            .every((PortfolioTile t) => t.imageUrl == null),
        isTrue,
      );
      expect(find.byType(RemoteImage), findsNothing);
      expect(find.byKey(const Key('portfolio-rail-empty')), findsNothing);
      expect(find.byKey(const Key('portfolio-rail-error')), findsNothing);
    });
  });

  group('PortfolioRail — photos', () {
    testWidgets('one tile + RemoteImage per photo, in list order, keyed by '
        'photo id; `count` is ignored', (tester) async {
      await tester.pumpApp(
        const Scaffold(body: PortfolioRail(photos: photos, count: 6)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PortfolioTile), findsNWidgets(photos.length));
      expect(
        tester
            .widgetList<RemoteImage>(find.byType(RemoteImage))
            .map((RemoteImage r) => r.url),
        photos.map((PortfolioPhoto p) => p.url),
      );
      final List<double> xs = <double>[
        for (final PortfolioPhoto p in photos)
          tester.getTopLeft(find.byKey(Key('portfolio-photo-${p.id}'))).dx,
      ];
      expect(xs, orderedEquals(<double>[...xs]..sort()));
    });

    testWidgets('a real tile announces portfolioPhotoSemantics(n) as an '
        'image (D5)', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpApp(const Scaffold(body: PortfolioRail(photos: photos)));
      await tester.pumpAndSettle();

      final SemanticsData data = tester
          .getSemantics(find.byKey(const Key('portfolio-photo-p2')))
          .getSemanticsData();
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(PortfolioRail)),
      );
      expect(data.label, l10n.portfolioPhotoSemantics(2));
      expect(data.flagsCollection.isImage, isTrue);
      // Same security property as the placeholder: a real tile has no tap
      // action yet (viewer = 407), so it must not announce as a button.
      expect(data.flagsCollection.isButton, isFalse);
      handle.dispose();
    });
  });

  group('PortfolioRail — empty list', () {
    testWidgets('hideWhenEmpty renders nothing — no label, no tiles', (
      tester,
    ) async {
      await tester.pumpApp(
        const Scaffold(
          body: PortfolioRail(
            railKey: Key('rail'),
            photos: <PortfolioPhoto>[],
            hideWhenEmpty: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rail')), findsNothing);
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(PortfolioRail)),
      );
      expect(find.text(l10n.masterPortfolioLabel), findsNothing);
      expect(find.byType(PortfolioTile), findsNothing);
    });

    testWidgets('own (hideWhenEmpty false): label + empty-state line, no '
        'tiles (D3)', (tester) async {
      await tester.pumpApp(
        const Scaffold(body: PortfolioRail(photos: <PortfolioPhoto>[])),
      );
      await tester.pumpAndSettle();

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(PortfolioRail)),
      );
      expect(find.text(l10n.masterPortfolioLabel), findsOneWidget);
      expect(find.text(l10n.portfolioEmptyOwn), findsOneWidget);
      expect(find.byType(PortfolioTile), findsNothing);
    });

    testWidgets('hideWhenEmpty does NOT hide a non-empty list', (tester) async {
      await tester.pumpApp(
        const Scaffold(
          body: PortfolioRail(photos: photos, hideWhenEmpty: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PortfolioTile), findsNWidgets(3));
    });
  });

  group('PortfolioRail — onRetry (error)', () {
    testWidgets('label + error line; the link calls onRetry', (tester) async {
      var retries = 0;
      await tester.pumpApp(
        Scaffold(body: PortfolioRail(onRetry: () => retries++)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('portfolio-rail-error')), findsOneWidget);
      expect(find.byType(PortfolioTile), findsNothing);
      await tester.tap(find.byKey(const Key('portfolio-rail-retry')));
      expect(retries, 1);
    });
  });

  group('PortfolioRail.fromAsync — D2 state mapping', () {
    Future<void> pump(WidgetTester tester, Widget rail) =>
        tester.pumpApp(Scaffold(body: rail));

    testWidgets('loading → placeholders', (tester) async {
      await pump(
        tester,
        PortfolioRail.fromAsync(const AsyncLoading<List<PortfolioPhoto>>()),
      );
      expect(find.byType(PortfolioTile), findsNWidgets(6));
      expect(find.byType(RemoteImage), findsNothing);
    });

    testWidgets('data → real tiles', (tester) async {
      await pump(
        tester,
        PortfolioRail.fromAsync(const AsyncData<List<PortfolioPhoto>>(photos)),
      );
      expect(find.byType(RemoteImage), findsNWidgets(3));
    });

    testWidgets('error + onRetry → inline retry line', (tester) async {
      await pump(
        tester,
        PortfolioRail.fromAsync(
          AsyncError<List<PortfolioPhoto>>(Exception('x'), StackTrace.empty),
          onRetry: () {},
        ),
      );
      expect(find.byKey(const Key('portfolio-rail-error')), findsOneWidget);
    });

    testWidgets('error, no onRetry (public) → nothing at all', (tester) async {
      await pump(
        tester,
        PortfolioRail.fromAsync(
          AsyncError<List<PortfolioPhoto>>(Exception('x'), StackTrace.empty),
          railKey: const Key('rail'),
        ),
      );
      expect(find.byKey(const Key('rail')), findsNothing);
      expect(find.byKey(const Key('portfolio-rail-error')), findsNothing);
    });

    // mobile-qa (phase 404) — the "a value wins" half of the D2 mapping: a
    // refetch / failed refetch that still HOLDS the previous list keeps the
    // real tiles (never flips back to placeholders or the error line).
    testWidgets('refetch holding the previous list → real tiles', (
      tester,
    ) async {
      await pump(
        tester,
        PortfolioRail.fromAsync(
          // isRefresh: false keeps the runtime type AsyncLoading (the
          // default maps a data previous back to AsyncData — vacuous here).
          // `copyWithPrevious` is @internal; used deliberately, as in
          // auth_redirect_stale_role_forward_test.dart — the only way to
          // build this shape for a pure mapping with no notifier.
          // ignore: invalid_use_of_internal_member
          const AsyncLoading<List<PortfolioPhoto>>().copyWithPrevious(
            const AsyncData<List<PortfolioPhoto>>(photos),
            isRefresh: false,
          ),
        ),
      );
      expect(find.byKey(const Key('portfolio-photo-p1')), findsOneWidget);
      expect(find.byKey(const Key('portfolio-photo-p3')), findsOneWidget);
    });

    testWidgets('failed refetch holding the previous list → real tiles, no '
        'error line even with onRetry', (tester) async {
      final AsyncError<List<PortfolioPhoto>> error =
          AsyncError<List<PortfolioPhoto>>(Exception('x'), StackTrace.empty);
      final AsyncValue<List<PortfolioPhoto>> failedRefetch = error
          // ignore: invalid_use_of_internal_member
          .copyWithPrevious(const AsyncData<List<PortfolioPhoto>>(photos));
      await pump(
        tester,
        PortfolioRail.fromAsync(failedRefetch, onRetry: () {}),
      );
      expect(find.byKey(const Key('portfolio-photo-p1')), findsOneWidget);
      expect(find.byKey(const Key('portfolio-rail-error')), findsNothing);
    });

    testWidgets('data + hideWhenEmpty, empty → nothing', (tester) async {
      await pump(
        tester,
        PortfolioRail.fromAsync(
          const AsyncData<List<PortfolioPhoto>>(<PortfolioPhoto>[]),
          railKey: const Key('rail'),
          hideWhenEmpty: true,
        ),
      );
      expect(find.byKey(const Key('rail')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Phase 404 audit R1 / R2 — the real-photo rail is LAZY and CAPPED.
  // -------------------------------------------------------------------------
  group('PortfolioRail — lazy, capped real-photo list (R1/R2)', () {
    List<PortfolioPhoto> newestFirst(int n) => <PortfolioPhoto>[
      for (int i = 0; i < n; i++)
        PortfolioPhoto(id: 'n$i', url: 'https://media.test/n$i.webp'),
    ];

    testWidgets('35 photos → exactly kPortfolioMaxPhotos (30) renderable '
        'tiles, the NEWEST 30 (list head); scrolling to the end reaches n29 '
        'and never n30+', (tester) async {
      await tester.pumpApp(
        Scaffold(body: PortfolioRail(photos: newestFirst(35))),
      );
      await tester.pumpAndSettle();

      final ListView list = tester.widget<ListView>(find.byType(ListView));
      // ListView.separated → 30 tiles + 29 separators.
      expect(
        list.childrenDelegate.estimatedChildCount,
        kPortfolioMaxPhotos * 2 - 1,
      );
      expect(kPortfolioMaxPhotos, 30);
      expect(find.byKey(const Key('portfolio-photo-n0')), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(-20000, 0));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('portfolio-photo-n29')), findsOneWidget);
      for (int i = 30; i < 35; i++) {
        expect(find.byKey(Key('portfolio-photo-n$i')), findsNothing);
      }
    });

    testWidgets('at or under the cap, every photo is renderable', (
      tester,
    ) async {
      await tester.pumpApp(
        Scaffold(body: PortfolioRail(photos: newestFirst(4))),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ListView>(find.byType(ListView))
            .childrenDelegate
            .estimatedChildCount,
        4 * 2 - 1,
      );
      expect(find.byType(PortfolioTile), findsNWidgets(4));
    });

    testWidgets('lazy: off-screen tiles are NOT built until scrolled to', (
      tester,
    ) async {
      await tester.pumpApp(
        Scaffold(body: PortfolioRail(photos: newestFirst(30))),
      );
      await tester.pumpAndSettle();

      // `skipOffstage: false` — the default finder hides children a sliver
      // keeps in its cache extent, so it would also pass for a list that
      // eagerly BUILT (and started fetching) all 30 tiles off-viewport.
      final int built = find
          .byType(PortfolioTile, skipOffstage: false)
          .evaluate()
          .length;
      expect(built, greaterThan(0));
      expect(built, lessThan(30));
      expect(
        find.byKey(const Key('portfolio-photo-n29'), skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets('real tiles opt into the cover decode; the placeholder rail '
        'does not (R3 scoping)', (tester) async {
      await tester.pumpApp(const Scaffold(body: PortfolioRail(photos: photos)));
      await tester.pumpAndSettle();
      // Non-empty guards: `every` over an empty iterable is vacuously true.
      expect(find.byType(PortfolioTile), findsNWidgets(photos.length));
      expect(find.byType(RemoteImage), findsNWidgets(photos.length));
      expect(
        tester
            .widgetList<PortfolioTile>(find.byType(PortfolioTile))
            .every((PortfolioTile t) => t.decodeToCover),
        isTrue,
      );
      expect(
        tester
            .widgetList<RemoteImage>(find.byType(RemoteImage))
            .every((RemoteImage r) => r.decodeToCover),
        isTrue,
      );

      await tester.pumpApp(const Scaffold(body: PortfolioRail()));
      await tester.pumpAndSettle();
      // `any` over an empty iterable is vacuously false.
      expect(find.byType(PortfolioTile), findsNWidgets(6));
      expect(
        tester
            .widgetList<PortfolioTile>(find.byType(PortfolioTile))
            .any((PortfolioTile t) => t.decodeToCover),
        isFalse,
      );
    });
  });

  // ── Phase 405 (9.10) — editor affordances (D1/D2/D6) ─────────────────────
  group('PortfolioRail — editor affordances (phase 405)', () {
    List<PortfolioPhoto> photosOf(int n) => <PortfolioPhoto>[
      for (int i = 0; i < n; i++)
        PortfolioPhoto(id: 'p$i', url: 'https://media.test/$i.webp'),
    ];
    // A path shaped like the scratch dir (debug shape check) that does not
    // exist — the tile renders its gradient fallback, no file I/O.
    final File scratch = File('/nonexistent/media_upload/kept.jpg');
    PendingPortfolioUpload uploading([double progress = 0.4]) =>
        PendingPortfolioUpload(id: 'u1', file: scratch, progress: progress);
    PendingPortfolioUpload failed() => PendingPortfolioUpload(
      id: 'f1',
      file: scratch,
      failure: const UploadNetworkFailure(),
    );
    const Key addKey = Key('portfolio-add-tile');

    testWidgets('read-only (no editor params): no add tile, no remove badge, '
        'no pending tile, plain label', (tester) async {
      await tester.pumpApp(Scaffold(body: PortfolioRail(photos: photosOf(3))));
      await tester.pump();
      expect(find.byType(PortfolioAddTile), findsNothing);
      expect(find.byKey(const Key('portfolio-photo-delete-p0')), findsNothing);
      expect(find.byType(UploadProgressOverlay), findsNothing);
      expect(find.text(_l10n.masterPortfolioLabel), findsOneWidget);
    });

    testWidgets('P1 — inserting a pending tile (and removing it again) MOVES '
        'the existing photo tiles: same State, never rebuilt from scratch', (
      tester,
    ) async {
      final ValueNotifier<List<PendingPortfolioUpload>> pending =
          ValueNotifier<List<PendingPortfolioUpload>>(
            const <PendingPortfolioUpload>[],
          );
      addTearDown(pending.dispose);
      await tester.pumpApp(
        Scaffold(
          body: ValueListenableBuilder<List<PendingPortfolioUpload>>(
            valueListenable: pending,
            builder: (BuildContext _, List<PendingPortfolioUpload> p, _) =>
                PortfolioRail(photos: photosOf(2), onAdd: () {}, pending: p),
          ),
        ),
      );
      await tester.pump();
      const Key p0 = Key('portfolio-photo-p0');
      const Key p1 = Key('portfolio-photo-p1');
      final State<StatefulWidget> before0 = tester.state(find.byKey(p0));
      final State<StatefulWidget> before1 = tester.state(find.byKey(p1));
      final State<StatefulWidget> addBefore = tester.state(find.byKey(addKey));

      pending.value = <PendingPortfolioUpload>[uploading()];
      await tester.pump();
      expect(find.byKey(const Key('portfolio-pending-u1')), findsOneWidget);
      expect(tester.state(find.byKey(p0)), same(before0));
      expect(tester.state(find.byKey(p1)), same(before1));
      expect(tester.state(find.byKey(addKey)), same(addBefore));

      pending.value = const <PendingPortfolioUpload>[];
      await tester.pump();
      expect(find.byKey(const Key('portfolio-pending-u1')), findsNothing);
      expect(tester.state(find.byKey(p0)), same(before0));
      expect(tester.state(find.byKey(p1)), same(before1));
    });

    testWidgets('onAdd → a LEADING add tile that fires onAdd', (tester) async {
      int adds = 0;
      await tester.pumpApp(
        Scaffold(
          body: PortfolioRail(photos: photosOf(2), onAdd: () => adds++),
        ),
      );
      await tester.pump();
      expect(find.byKey(addKey), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(addKey)).dx,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('portfolio-photo-p0'))).dx,
        ),
      );
      await tester.tap(find.byKey(addKey));
      await tester.pump();
      expect(adds, 1);
    });

    testWidgets('the add tile hides at the cap — stored photos AND pending '
        'uploads count', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: PortfolioRail(
            photos: photosOf(kPortfolioMaxPhotos - 1),
            onAdd: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(addKey), findsOneWidget, reason: '29 → still room');

      await tester.pumpApp(
        Scaffold(
          body: PortfolioRail(
            photos: photosOf(kPortfolioMaxPhotos - 1),
            pending: <PendingPortfolioUpload>[failed()],
            onAdd: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(addKey), findsNothing, reason: '29 + 1 pending = 30');

      await tester.pumpApp(
        Scaffold(
          body: PortfolioRail(
            photos: photosOf(kPortfolioMaxPhotos),
            onAdd: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(addKey), findsNothing, reason: '30 stored');
    });

    testWidgets('onDelete → a remove badge on EVERY photo, firing with THAT '
        'photo', (tester) async {
      final List<PortfolioPhoto> deleted = <PortfolioPhoto>[];
      final List<PortfolioPhoto> photos = photosOf(3);
      await tester.pumpApp(
        Scaffold(
          body: PortfolioRail(photos: photos, onDelete: deleted.add),
        ),
      );
      await tester.pump();
      for (final PortfolioPhoto p in photos) {
        expect(
          find.byKey(Key('portfolio-photo-delete-${p.id}')),
          findsOneWidget,
        );
      }
      expect(find.byType(PortfolioAddTile), findsNothing);
      await tester.tap(find.byKey(const Key('portfolio-photo-delete-p1')));
      await tester.pump();
      expect(deleted, <PortfolioPhoto>[photos[1]]);
    });

    testWidgets('pending upload: progress overlay after the add tile; the add '
        'tile is inert while it uploads; no discard badge', (tester) async {
      int adds = 0;
      await tester.pumpApp(
        Scaffold(
          body: PortfolioRail(
            photos: photosOf(1),
            pending: <PendingPortfolioUpload>[uploading()],
            onAdd: () => adds++,
            onDiscardPending: (_) {},
          ),
        ),
      );
      await tester.pump();
      final Finder tile = find.byKey(const Key('portfolio-pending-u1'));
      expect(tile, findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.byType(UploadProgressOverlay)),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(tile).dx,
        greaterThan(tester.getTopLeft(find.byKey(addKey)).dx),
      );
      expect(
        tester.getTopLeft(tile).dx,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('portfolio-photo-p0'))).dx,
        ),
      );
      expect(
        find.byKey(const Key('portfolio-pending-discard-u1')),
        findsNothing,
      );
      await tester.tap(find.byKey(addKey));
      await tester.pump();
      expect(adds, 0, reason: 'one upload at a time — the tile is inert');
    });

    testWidgets('failed upload: retry overlay → onRetryPending; discard badge '
        '→ onDiscardPending; the add tile is live again', (tester) async {
      final List<String> retried = <String>[];
      final List<String> discarded = <String>[];
      int adds = 0;
      await tester.pumpApp(
        Scaffold(
          body: PortfolioRail(
            photos: photosOf(1),
            pending: <PendingPortfolioUpload>[failed()],
            onAdd: () => adds++,
            onRetryPending: (PendingPortfolioUpload p) => retried.add(p.id),
            onDiscardPending: (PendingPortfolioUpload p) => discarded.add(p.id),
          ),
        ),
      );
      await tester.pump();
      final Finder tile = find.byKey(const Key('portfolio-pending-f1'));
      expect(
        find.descendant(of: tile, matching: find.byType(UploadFailedOverlay)),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: tile,
          matching: find.byKey(const Key('upload-retry')),
        ),
      );
      await tester.pump();
      expect(retried, <String>['f1']);
      await tester.tap(find.byKey(const Key('portfolio-pending-discard-f1')));
      await tester.pump();
      expect(discarded, <String>['f1']);
      await tester.tap(find.byKey(addKey));
      await tester.pump();
      expect(adds, 1);
    });

    testWidgets('showCount → «Портфоліо · n/30» counting pending; off → the '
        'plain label', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: PortfolioRail(
            photos: photosOf(2),
            pending: <PendingPortfolioUpload>[uploading()],
            onAdd: () {},
            showCount: true,
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text(_l10n.portfolioLabelWithCount(3, kPortfolioMaxPhotos)),
        findsOneWidget,
      );
      expect(find.text(_l10n.masterPortfolioLabel), findsNothing);
    });

    testWidgets('empty portfolio + onAdd: the «Додайте перші фото» hint AND '
        'the add tile', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: PortfolioRail(photos: const <PortfolioPhoto>[], onAdd: () {}),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('portfolio-rail-empty')), findsOneWidget);
      expect(find.byKey(addKey), findsOneWidget);
    });

    testWidgets('fromAsync: editor params ride on DATA only — loading shows '
        'the placeholders, no add tile', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: PortfolioRail.fromAsync(
            AsyncData<List<PortfolioPhoto>>(photosOf(2)),
            onAdd: () {},
            onDelete: (_) {},
            showCount: true,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(addKey), findsOneWidget);
      expect(
        find.byKey(const Key('portfolio-photo-delete-p1')),
        findsOneWidget,
      );
      expect(
        find.text(_l10n.portfolioLabelWithCount(2, kPortfolioMaxPhotos)),
        findsOneWidget,
      );

      await tester.pumpApp(
        Scaffold(
          body: PortfolioRail.fromAsync(
            const AsyncLoading<List<PortfolioPhoto>>(),
            onAdd: () {},
            showCount: true,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(addKey), findsNothing);
      expect(find.byType(PortfolioTile), findsNWidgets(6));
      expect(find.text(_l10n.masterPortfolioLabel), findsOneWidget);
    });
  });
}
