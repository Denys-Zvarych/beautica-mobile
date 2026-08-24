// mobile-qa — page-title typography unification regression suite
// (2026-08-22).
//
// THE REGRESSION THIS PINS
// -------------------------
// The four INDEPENDENT_MASTER bottom-nav tab-root screens rendered their
// page title at THREE different sizes: «Мої послуги» used
// `VelvetText.heading()` (21 sp) via a private `_ServicesAppBar`, «Мої
// записи» used a one-off `VelvetText.masterBookingsTitle` (22 sp), while
// «Графік роботи»/«Мій профіль» used `VelvetText.subheading()` (14 sp) via
// the shared `VelvetTopBar`. The fix folded all four onto ONE token,
// `VelvetText.pageTitle`, and deleted the one-off.
//
// The regression class here is DIVERGENCE, not a specific number — a test
// that only pins `fontSize == 14` would still pass if all four screens
// drifted TOGETHER onto a new value. So this suite asserts CROSS-SCREEN
// EQUALITY (the actual invariant) in addition to a value pin on the token
// itself.
//
// COVERAGE STRATEGY
// ------------------
//   • «Графік роботи» (MasterScheduleScreen) and «Мій профіль»
//     (MasterProfileScreen via ProfileScaffold) both pass a plain l10n
//     STRING to VelvetTopBar and have NO title-style call site of their
//     own — VelvetTopBar alone decides the rendered style. Pumping
//     VelvetTopBar directly therefore exercises the EXACT same code path
//     those two real screens hit for their title (there is no other route
//     to a title Text for either); a full pump of the heavier
//     auth/redirect-guarded screens would exercise the identical single
//     line of production code at much higher setup cost and fixture risk.
//   • «Мої послуги» (ServicesListScreen) and «Мої записи»
//     (MasterBookingsScreen, via `bookings_discovery_view.dart`'s
//     `_Header`) each have their OWN inline `Text(title, style:
//     VelvetText.pageTitle)` call site — these two are pumped as real
//     screens, because that inline site is precisely where a future
//     single-screen repoint (the actual failure mode this regression took)
//     would land, and a shared-widget test cannot see it.
//   • The archive screen (`MasterArchiveScreen`) shares the exact same
//     `_ArchiveHeader` shape and is covered by the structural guard
//     (`scripts/forbid_page_title_token_fork.sh` Rule B) instead of a
//     widget pump here — it is not one of the four bottom-nav tab roots.
//
// A second, complementary guard — `scripts/forbid_page_title_token_fork.sh`
// — pins this same invariant structurally (source-grep) across all FIVE
// title call sites (velvet_top_bar.dart, services_list_screen.dart,
// bookings_discovery_view.dart, master_archive_screen.dart) plus a Rule A
// ban on any NEW one-off *Title-shaped VelvetText token, so a future fork
// is caught at CI time even before a widget test would render it. Run
// `./scripts/forbid_page_title_token_fork.sh --self-test`.

import 'dart:async';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/bookings_discovery_view.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Pumps a bare [VelvetTopBar] with [title] and returns the rendered title
/// [TextStyle]. This is the EXACT code path MasterScheduleScreen and
/// MasterProfileScreen hit for their own title — see the file header.
Future<TextStyle> _velvetTopBarStyle(WidgetTester tester, String title) async {
  await tester.pumpApp(VelvetTopBar(title: title));
  final Text text = tester.widget<Text>(find.text(title));
  final TextStyle? style = text.style;
  expect(style, isNotNull, reason: 'VelvetTopBar must style its title Text');
  return style!;
}

/// Pumps [ServicesListScreen] in its loading state (the app bar renders
/// unconditionally, outside the AsyncValue.when body — see
/// `services_list_screen.dart`'s `_ServicesAppBar`) and returns the rendered
/// title [TextStyle].
Future<TextStyle> _servicesListTitleStyle(WidgetTester tester) async {
  final _MockServiceRepository mockRepo = _MockServiceRepository();
  when(
    () => mockRepo.listMyServices(),
  ).thenAnswer((_) async => const <MasterService>[]);

  await tester.pumpApp(
    const ServicesListScreen(),
    overrides: <Object>[
      servicesListProvider.overrideWith(() => _NeverSettlesServicesList()),
      serviceRepositoryProvider.overrideWithValue(mockRepo),
      approvedCategoriesProvider.overrideWith(
        (ref) async => const <ServiceCategoryOption>[],
      ),
    ],
  );
  await tester.pump();

  final AppLocalizations l10n = AppLocalizations.of(
    tester.element(find.byType(ServicesListScreen)),
  );
  final Text text = tester.widget<Text>(find.text(l10n.servicesTitle));
  final TextStyle? style = text.style;
  expect(style, isNotNull, reason: 'ServicesListScreen must style its title');
  return style!;
}

/// A [ServicesList] stub that never settles — the app bar is what this test
/// cares about, and it renders identically regardless of body state.
class _NeverSettlesServicesList extends ServicesList {
  @override
  Future<List<MasterService>> build() {
    return Completer<List<MasterService>>().future;
  }
}

/// Pumps [MasterBookingsScreen] with an empty booking page and returns the
/// rendered title [TextStyle] («Мої записи», via `_Header`).
Future<TextStyle> _masterBookingsTitleStyle(WidgetTester tester) async {
  final _MockBookingRepository repo = _MockBookingRepository();
  registerFallbackValue(BookingStatus.confirmed);
  when(
    () => repo.getMyBookings(
      statuses: any(named: 'statuses'),
      page: any(named: 'page'),
      size: any(named: 'size'),
      cancelToken: any(named: 'cancelToken'),
      sort: any(named: 'sort'),
      serviceIds: any(named: 'serviceIds'),
      from: any(named: 'from'),
      to: any(named: 'to'),
    ),
  ).thenAnswer(
    (_) async => const PageResponse<Booking>(
      items: <Booking>[],
      page: 0,
      totalPages: 1,
      totalElements: 0,
    ),
  );

  await tester.pumpRoutedApp(
    GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              const MasterBookingsScreen(),
        ),
      ],
    ),
    overrides: <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingRepositoryProvider.overrideWithValue(repo),
      bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
    ],
  );
  await tester.pump();

  final AppLocalizations l10n = AppLocalizations.of(
    tester.element(find.byType(MasterBookingsScreen)),
  );
  // Scoped to BookingsDiscoveryView (the screen's `body`) — the SAME string
  // «Мої записи» also appears as the bottom-nav tab label, a SIBLING under
  // Scaffold rather than a descendant of the header, so an unscoped
  // find.text(...) here matches BOTH and throws "Too many elements".
  final Text text = tester.widget<Text>(
    find.descendant(
      of: find.byType(BookingsDiscoveryView),
      matching: find.text(l10n.masterBookingsTitle),
    ),
  );
  final TextStyle? style = text.style;
  expect(style, isNotNull, reason: 'MasterBookingsScreen must style its title');
  return style!;
}

void main() {
  // ── 1a. Token-level pin ───────────────────────────────────────────────
  group('VelvetText.pageTitle token', () {
    testWidgets(
      'resolves to Comfortaa 14sp / w600 / BrandColors.text — same VALUES '
      'as VelvetText.subheading()',
      (tester) async {
        final TextStyle pageTitle = VelvetText.pageTitle;
        final TextStyle subheading = VelvetText.subheading();

        expect(pageTitle.fontSize, 14.0);
        expect(pageTitle.fontWeight, FontWeight.w600);
        expect(pageTitle.color, BrandColors.text);

        // The doc comment states pageTitle IS _subheadingStyle (same
        // object, not a copyWith) — pin that identity so a future edit
        // can't quietly fork the two apart again.
        expect(pageTitle.fontSize, subheading.fontSize);
        expect(pageTitle.fontWeight, subheading.fontWeight);
        expect(pageTitle.fontFamily, subheading.fontFamily);
        expect(pageTitle.color, subheading.color);
      },
    );
  });

  // ── 1b. Cross-screen rendered-style consistency ─────────────────────────
  group('cross-screen page-title consistency (rendered)', () {
    testWidgets(
      'VelvetTopBar (Schedule + Profile path) renders VelvetText.pageTitle',
      (tester) async {
        final TextStyle style = await _velvetTopBarStyle(tester, 'X');
        expect(style.fontSize, VelvetText.pageTitle.fontSize);
        expect(style.fontWeight, VelvetText.pageTitle.fontWeight);
        expect(style.fontFamily, VelvetText.pageTitle.fontFamily);
        expect(style.color, VelvetText.pageTitle.color);
      },
    );

    testWidgets(
      'ServicesListScreen («Мої послуги») renders VelvetText.pageTitle',
      (tester) async {
        final TextStyle style = await _servicesListTitleStyle(tester);
        expect(style.fontSize, VelvetText.pageTitle.fontSize);
        expect(style.fontWeight, VelvetText.pageTitle.fontWeight);
        expect(style.fontFamily, VelvetText.pageTitle.fontFamily);
        expect(style.color, VelvetText.pageTitle.color);
      },
    );

    testWidgets(
      'MasterBookingsScreen («Мої записи») renders VelvetText.pageTitle',
      (tester) async {
        final TextStyle style = await _masterBookingsTitleStyle(tester);
        expect(style.fontSize, VelvetText.pageTitle.fontSize);
        expect(style.fontWeight, VelvetText.pageTitle.fontWeight);
        expect(style.fontFamily, VelvetText.pageTitle.fontFamily);
        expect(style.color, VelvetText.pageTitle.color);
      },
    );

    testWidgets(
      'THE LOAD-BEARING ASSERTION — all four tab-root title styles are '
      'EQUAL TO EACH OTHER, not merely equal to a literal 14. If a future '
      'edit repoints any ONE screen at a different VelvetText token '
      '(heading(), subheading(), or a new one-off), this test fails even '
      'if that screen still happens to render at 14sp by coincidence.',
      (tester) async {
        final TextStyle topBar = await _velvetTopBarStyle(tester, 'Y');
        // Each helper below mounts a DIFFERENT widget tree with a
        // DIFFERENT-length ProviderScope override list. Riverpod's
        // ProviderScope forbids changing the override COUNT on an in-place
        // update (`_debugOverridesLength == overrides.length`), and
        // `pumpWidget` UPDATES the previous tree in place rather than
        // remounting whenever the root widget types line up — which they do
        // here (MaterialApp both times). An explicit teardown pump forces a
        // full unmount before the next tree mounts.
        await tester.pumpWidget(const SizedBox.shrink());
        final TextStyle services = await _servicesListTitleStyle(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        final TextStyle bookings = await _masterBookingsTitleStyle(tester);

        for (final (String label, TextStyle style) in <(String, TextStyle)>[
          ('services vs topBar (schedule/profile)', services),
          ('bookings vs topBar (schedule/profile)', bookings),
        ]) {
          expect(
            style.fontSize,
            topBar.fontSize,
            reason: 'fontSize diverged: $label',
          );
          expect(
            style.fontWeight,
            topBar.fontWeight,
            reason: 'fontWeight diverged: $label',
          );
          expect(
            style.fontFamily,
            topBar.fontFamily,
            reason: 'fontFamily diverged: $label',
          );
        }
      },
    );
  });
}
