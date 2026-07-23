// Phase 13.8 — BEAUTY PASSPORT page OVERFLOW regression guard.
//
// WHY THIS FILE EXISTS
// --------------------
// PassportScreen is an INTENTIONALLY single-screen, NON-scrolling layout: a
// `Column` (top bar → profile block → BEAUTY PASSPORT card as an `Expanded`
// hero). That makes it the most overflow-prone client page on:
//   • short phones (320×568) where the fixed chrome eats the viewport and the
//     `Expanded` hero is squeezed toward — or past — zero height,
//   • large accessibility text scale (1.3–1.5) where the profile lines, the
//     card's three columns, the chips and the footer all grow.
//
// The hero ITSELF wraps its content in a `SingleChildScrollView` safety valve
// (passport_screen.dart `_PassportHero`), so vertical growth INSIDE the card is
// absorbed. The residual risks this matrix exercises are therefore:
//   1. the top-level Column: fixed chrome (top bar + profile block + gaps) that,
//      under large text scale, leaves the `Expanded` a NEGATIVE height → the
//      classic "BOTTOM OVERFLOWED" stripe,
//   2. the card's 3-column `IntrinsicHeight`/`Row` (passport_table.dart): chips
//      + ruled hairlines that can overflow on the RIGHT when labels/chips grow.
//
// HOW OVERFLOW IS CAUGHT
// ----------------------
// The suite-wide overflow guard (test/helpers/overflow_guard.dart) records the
// first RenderFlex overflow and fails the test in tearDown. Each cell ALSO
// asserts `tester.takeException()` is null as a second, explicit net.
//
// SURFACE SIZING NOTE — WHY NOT pumpApp(width:)
// ---------------------------------------------
// `pumpApp(width:)` forces the surface HEIGHT to 2400 (it is built to hunt
// HORIZONTAL overflow without a vertical false-positive). A non-scrolling page's
// primary failure mode is VERTICAL, so this file sets `view.physicalSize`
// explicitly to a REALISTIC device height per cell — otherwise a 2400-tall
// surface gives the `Expanded` hero enormous slack and no short-phone cell ever
// reproduces the squeeze. We still install the overflow guard manually.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/passport/application/passport_notifier.dart';
import 'package:beautica_mobile/features/passport/domain/passport.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/overflow_guard.dart';

// ---------------------------------------------------------------------------
// No-op ScreenProtectionManager (the native FLAG_SECURE plugin must not fire).
// ---------------------------------------------------------------------------

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}

  @override
  void release() {}

  @override
  void reset() {}
}

// ---------------------------------------------------------------------------
// Fixtures. The POPULATED passport carries the MAX content the UI shows so the
// columns are at their tallest and the chips at their longest:
//   • top-3 procedures, top-3 districts (rank-ordered),
//   • a budget band (drives the budget chip),
//   • a non-zero reviews count + a member-since year (footer).
// Long-ish Ukrainian labels mimic real derived data that grows under text scale.
// ---------------------------------------------------------------------------

const _sampleProfile = ClientProfileSummary(
  firstName: 'Олександра',
  lastName: 'Коваленко-Тестівська',
  city: 'Львів',
  phone: '+380 97 000 00 00',
  clientRating: 4.7,
  memberSinceYear: 2024,
);

const _populatedPassport = Passport(
  favoriteProcedures: <String>[
    'Манікюр гель-лак',
    'Брови ламінування',
    'Косметологія обличчя',
  ],
  favoriteDistricts: <String>['Центр', 'Сихів', 'Залізничний'],
  budget: BudgetBand(avg: 650, min: 400, max: 800),
  bookingsConsidered: 12,
  reviewsLeft: 8,
  memberSinceYear: 2024,
);

final Passport _emptyPassport = Passport.empty();

List<Object> _overrides(Passport passport) => <Object>[
  screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
  clientProfileProvider.overrideWith((ref) async => _sampleProfile),
  passportProvider.overrideWith((ref) async => passport),
];

// ---------------------------------------------------------------------------
// Realistic viewport matrix (logical px). textScale is applied via MediaQuery
// override so chips/labels grow exactly as on an accessibility device.
// ---------------------------------------------------------------------------

class _Viewport {
  const _Viewport(this.label, this.width, this.height, this.scale);
  final String label;
  final double width;
  final double height;
  final double scale;
}

const List<_Viewport> _matrix = <_Viewport>[
  // Small phone — iPhone SE 1st gen / small Android. Worst case for a no-scroll
  // page: least vertical room for the fixed chrome + the hero.
  _Viewport('small-phone 320x568', 320, 568, 1.0),
  // Compact low-end Android.
  _Viewport('compact 360x640', 360, 640, 1.0),
  // Baseline modern phone.
  _Viewport('baseline 390x844', 390, 844, 1.0),
  // Large accessibility text scale on the baseline phone — chips/labels/profile
  // lines all grow; the fixed chrome can squeeze the Expanded hero negative.
  _Viewport('baseline 390x844 @1.3x', 390, 844, 1.3),
  _Viewport('baseline 390x844 @1.5x', 390, 844, 1.5),
];

// ---------------------------------------------------------------------------
// EXTREME-but-SAFE matrix — cells proven overflow-free. These are PERMANENT
// guards: if a future change reintroduces a top-bar overflow at any of these
// realistic-or-extreme cells, the suite goes red.
//
// FIX HISTORY (2026-06-22): the `_TopBar` Row (passport_screen.dart:499 —
// wordmark + Spacer + bell + burger) previously overflowed on the RIGHT at
// large text scale because the `beautica` wordmark `Text` grew with text scale
// while the fixed-size bell + burger could not yield space. The wordmark is now
// wrapped in `Flexible(child: Text(..., overflow: ellipsis, maxLines: 1))`, so
// it ellipsizes (and ultimately collapses to nothing) before the Row overflows.
// The four cells that USED to overflow are now safe and have moved here:
//   • 360x640 @2.0x  — Android "largest font" on the most common Android width.
//   • 320x568 @1.5x  — iPhone-SE-class width at a moderate a11y scale.
//   • 280x653 @1.3x  — split-screen + large font.
//   • 270x844 @1.0x  — sub-floor ultra-narrow portrait.
//
// The boundary sweep AFTER the fix proves the top bar is now overflow-free at
// every reachable config and well beyond — safe down to 240x844 @3.0x and
// 200x844 @3.0x. Residual overflow only appears at absurd, unreachable widths
// (≤160px @ ≥4.0x), where the fixed bell + burger + gaps alone exceed the
// surface (the wordmark is already fully ellipsized to zero) and the offending
// widget is no longer the top bar — i.e. there is no longer a reachable
// top-bar overflow boundary to document, so the EXPECTED-OVERFLOW probe matrix
// was removed.
// ---------------------------------------------------------------------------
const List<_Viewport> _extremeSafeMatrix = <_Viewport>[
  // ── Previously-overflowing cells, now fixed by the Flexible+ellipsis wrap. ──
  _Viewport('360x640 @2.0x (a11y largest font, common width)', 360, 640, 2.0),
  _Viewport('320x568 @1.5x (iPhone-SE-class a11y)', 320, 568, 1.5),
  _Viewport('280x653 @1.3x (split-screen + large font)', 280, 653, 1.3),
  _Viewport('270x844 @1.0x (sub-floor ultra-narrow)', 270, 844, 1.0),
  // ── Pre-existing safe guards. ──
  // 2.0× ("largest font" Android a11y) on the baseline-WIDTH phone.
  _Viewport('baseline 390x844 @2.0x (a11y largest font)', 390, 844, 2.0),
  // Ultra-narrow split-screen / old Android at 1.0×.
  _Viewport('ultra-narrow 280x653 @1.0x', 280, 653, 1.0),
  // Short / landscape-ish surfaces at 1.0× — exercise the vertical squeeze of
  // the no-scroll Column directly. Wide enough that the top bar never overflows;
  // the hero's SingleChildScrollView absorbs the vertical squeeze, so PASS.
  _Viewport('landscape-ish 640x360 @1.0x', 640, 360, 1.0),
  _Viewport('landscape-ish 720x360 @1.0x', 720, 360, 1.0),
  // Beyond-reachable extreme — proves the Flexible wrap holds far past any real
  // device. The wordmark ellipsizes to zero; the bell + burger still fit.
  _Viewport('beyond-reach 240x844 @3.0x (top bar still safe)', 240, 844, 3.0),
  _Viewport('beyond-reach 200x844 @3.0x (top bar still safe)', 200, 844, 3.0),
];

/// Pumps [PassportScreen] at an EXACT device viewport (width AND height) with
/// the given text scale, then settles the passport/profile futures.
Future<void> _pumpPassport(
  WidgetTester tester, {
  required _Viewport vp,
  required Passport passport,
}) async {
  installOverflowGuard();

  tester.view.physicalSize = Size(vp.width, vp.height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(passport).cast(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(vp.width, vp.height),
            textScaler: TextScaler.linear(vp.scale),
          ),
          child: const PassportScreen(),
        ),
      ),
    ),
  );

  // Resolve the profile + passport futures so the hero lays out at final height.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('PassportScreen overflow matrix — POPULATED (max content)', () {
    for (final _Viewport vp in _matrix) {
      testWidgets('no overflow at ${vp.label} (populated)', (tester) async {
        await _pumpPassport(tester, vp: vp, passport: _populatedPassport);

        expect(
          find.byKey(const Key('client-branch-passport')),
          findsOneWidget,
          reason: 'PassportScreen must render (sanity)',
        );
        expect(
          tester.takeException(),
          isNull,
          reason:
              'PassportScreen (populated, max content) must not overflow at '
              '${vp.label} — non-scrolling Column hero squeeze / 3-column card.',
        );
      });
    }
  });

  group('PassportScreen overflow matrix — EMPTY variant', () {
    for (final _Viewport vp in _matrix) {
      testWidgets('no overflow at ${vp.label} (empty)', (tester) async {
        await _pumpPassport(tester, vp: vp, passport: _emptyPassport);

        expect(
          find.byKey(const Key('passport_find_master_button')),
          findsOneWidget,
          reason: 'empty-passport CTA must render (sanity)',
        );
        expect(
          tester.takeException(),
          isNull,
          reason:
              'PassportScreen (empty variant) must not overflow at ${vp.label}.',
        );
      });
    }
  });

  // -------------------------------------------------------------------------
  // EXTREME-but-SAFE cells — permanent guards. POPULATED + EMPTY both proven
  // overflow-free by the 2026-06-22 boundary sweep. They must STAY green.
  // -------------------------------------------------------------------------
  group('PassportScreen overflow matrix — EXTREME (safe) POPULATED', () {
    for (final _Viewport vp in _extremeSafeMatrix) {
      testWidgets('no overflow at ${vp.label} (populated)', (tester) async {
        await _pumpPassport(tester, vp: vp, passport: _populatedPassport);

        expect(
          find.byKey(const Key('client-branch-passport')),
          findsOneWidget,
          reason: 'PassportScreen must render (sanity) at ${vp.label}',
        );
        expect(
          tester.takeException(),
          isNull,
          reason:
              'PassportScreen (populated) must stay overflow-free at the '
              'extreme-but-safe cell ${vp.label} — top bar / hero squeeze.',
        );
      });
    }
  });

  group('PassportScreen overflow matrix — EXTREME (safe) EMPTY', () {
    for (final _Viewport vp in _extremeSafeMatrix) {
      testWidgets('no overflow at ${vp.label} (empty)', (tester) async {
        await _pumpPassport(tester, vp: vp, passport: _emptyPassport);

        expect(
          find.byKey(const Key('passport_find_master_button')),
          findsOneWidget,
          reason: 'empty-passport CTA must render (sanity) at ${vp.label}',
        );
        expect(
          tester.takeException(),
          isNull,
          reason:
              'PassportScreen (empty) must stay overflow-free at the '
              'extreme-but-safe cell ${vp.label}.',
        );
      });
    }
  });

  // -------------------------------------------------------------------------
  // NOTE: the former EXPECTED-OVERFLOW boundary probe group was removed in the
  // 2026-06-22 fix. The `beautica` wordmark is now wrapped in
  // `Flexible(child: Text(..., overflow: ellipsis))`, so the `_TopBar` Row no
  // longer overflows at any reachable config (or even far beyond — see the
  // beyond-reach cells in `_extremeSafeMatrix`). There is therefore no longer a
  // reachable top-bar overflow boundary to document as an executable
  // expectation; the safe-matrix assertions above are the regression guard.
  // -------------------------------------------------------------------------
}
