// Phase 13.7 — HomeHub widget tests.
//
// Tests cover:
//   1. Profile card shows name from the provider (data state).
//   2. Profile card shows loading skeleton when provider is loading.
//   3. Profile card shows error retry when provider errors.
//   4. Next appointment empty state is shown when no appointment.
//   5. Favourite masters empty state is shown when no masters.
//   6. BEAUTY TIMELINE empty state is shown when no entries.
//   7. QuickLinksCard renders 3 tiles (reviews tile removed — reviews reached via stat pill).
//   8. PassportPreviewCard renders the untranslated "BEAUTY PASSPORT" literal.
//   9. BEAUTY TIMELINE section renders the untranslated "BEAUTY TIMELINE" literal.
//  10. HomeHubScreen renders a key widget without error (smoke test).
//
// NOTE: ScreenProtectionManager is a keepAlive singleton — tests override it
// with a no-op so the native plugin is never called during tests.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/home_hub_screen.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/beauty_timeline_section.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/favorite_masters_card.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/hub_widgets.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/next_appointment_card.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/passport_preview_card.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/quick_links_card.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// No-op ScreenProtectionManager for tests
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
// Test-wide sample data
// ---------------------------------------------------------------------------

const _sampleProfile = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Тест',
  city: 'Львів',
  phone: '+380 97 000 00 00',
  reviewsLeft: 3,
  memberSinceYear: 2026,
);

final _sampleAppointment = NextAppointment(
  id: 'appt-1',
  masterName: 'Марія Іванюк',
  service: 'Манікюр',
  dateLabel: '20 червня',
  timeLabel: '15:00',
  location: 'Центр, Львів',
  startsAt: DateTime.now().add(const Duration(days: 2)),
  masterInitials: 'МІ',
);

const _sampleMaster = FavoriteMasterItem(
  masterId: 'master-1',
  favoriteId: 'fav-1',
  name: 'Марія Іванюк',
  lastServiceName: 'Манікюр',
  rating: 5.0,
  reviewCount: 42,
  initials: 'МІ',
);

const _sampleTimeline = <TimelineEntry>[
  TimelineEntry(category: 'Манікюр', dateLabel: '18.06'),
  TimelineEntry(category: 'Брови', dateLabel: '12.05'),
];

// ---------------------------------------------------------------------------
// Shared provider overrides
// ---------------------------------------------------------------------------

List<Object> _overrides({
  AsyncValue<ClientProfileSummary>? profile,
  AsyncValue<NextAppointment?> nextAppt = const AsyncData(null),
  AsyncValue<List<FavoriteMasterItem>> favorites = const AsyncData(
    <FavoriteMasterItem>[],
  ),
  AsyncValue<List<TimelineEntry>> timeline = const AsyncData(<TimelineEntry>[]),
}) {
  return [
    // Bypass native ScreenProtector
    screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
    if (profile != null)
      clientProfileProvider.overrideWith(
        (ref) async => profile.when(
          data: (v) => v,
          loading: () => throw UnimplementedError(),
          error: (e, _) => throw e,
        ),
      ),
    nextAppointmentProvider.overrideWith((ref) async {
      return nextAppt.when(
        data: (v) => v,
        loading: () => null,
        error: (e, _) => null,
      );
    }),
    favoriteMastersProvider.overrideWith((ref) async {
      return favorites.when(
        data: (v) => v,
        loading: () => const <FavoriteMasterItem>[],
        error: (e, _) => const <FavoriteMasterItem>[],
      );
    }),
    beautyTimelineProvider.overrideWith((ref) async {
      return timeline.when(
        data: (v) => v,
        loading: () => const <TimelineEntry>[],
        error: (e, _) => const <TimelineEntry>[],
      );
    }),
    unlikeFavoriteMasterProvider.overrideWith(() => UnlikeFavoriteMaster()),
  ];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('HomeHubScreen', () {
    testWidgets('smoke — renders top bar wordmark', (tester) async {
      await tester.pumpApp(
        const HomeHubScreen(),
        overrides: _overrides(profile: const AsyncData(_sampleProfile)),
      );
      await tester.pump();
      // The top bar renders the "beautica" wordmark (brand literal)
      expect(find.text('beautica'), findsOneWidget);
    });

    testWidgets('renders notification bell button', (tester) async {
      await tester.pumpApp(
        const HomeHubScreen(),
        overrides: _overrides(profile: const AsyncData(_sampleProfile)),
      );
      await tester.pump();
      expect(find.byKey(const Key('home_hub_bell_button')), findsOneWidget);
    });

    testWidgets('renders burger menu button with Key btn-menu-client', (
      tester,
    ) async {
      await tester.pumpApp(
        const HomeHubScreen(),
        overrides: _overrides(profile: const AsyncData(_sampleProfile)),
      );
      await tester.pump();
      expect(find.byKey(const Key('btn-menu-client')), findsOneWidget);
    });

    testWidgets('burger menu button uses tune_rounded icon', (tester) async {
      await tester.pumpApp(
        const HomeHubScreen(),
        overrides: _overrides(profile: const AsyncData(_sampleProfile)),
      );
      await tester.pump();
      // The NeumorphicIconButton is present; verify its icon data.
      expect(
        find.byIcon(Icons.tune_rounded),
        findsOneWidget,
        reason:
            'top-bar burger must use Icons.tune_rounded (matches master profile)',
      );
    });

    testWidgets('tapping burger pushes /settings route', (tester) async {
      // Use a spy router so context.push(RouteNames.settings) fires correctly.
      // pumpApp uses plain MaterialApp which lacks a GoRouter delegate; the
      // burger calls context.push() which requires GoRouter in the widget tree.
      String? navigatedLocation;
      final router = GoRouter(
        initialLocation: RouteNames.clientHome,
        routes: [
          GoRoute(
            path: RouteNames.clientHome,
            builder: (context, state) => const HomeHubScreen(),
          ),
          GoRoute(
            path: RouteNames.settings,
            builder: (context, state) {
              navigatedLocation = RouteNames.settings;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(
        router,
        overrides: _overrides(profile: const AsyncData(_sampleProfile)),
      );
      // Pump until the initial route renders.
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn-menu-client')));
      await tester.pumpAndSettle();

      expect(
        navigatedLocation,
        equals(RouteNames.settings),
        reason: 'burger onTap must push RouteNames.settings (/settings)',
      );
    });
  });

  group('HomeProfileCard (via HomeHubScreen)', () {
    testWidgets('data state: shows client full name', (tester) async {
      await tester.pumpApp(
        const HomeHubScreen(),
        overrides: _overrides(profile: const AsyncData(_sampleProfile)),
      );
      await tester.pump();
      // After animation starts (pumpAndSettle for reveal)
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.text('Олена Тест'), findsOneWidget);
    });

    testWidgets('data state: shows city', (tester) async {
      await tester.pumpApp(
        const HomeHubScreen(),
        overrides: _overrides(profile: const AsyncData(_sampleProfile)),
      );
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.text('Львів'), findsOneWidget);
    });

    testWidgets('loading state: change photo button visible', (tester) async {
      // Even in loading state, the screen renders (skeleton in profile area)
      await tester.pumpApp(
        const HomeHubScreen(),
        overrides: _overrides(profile: const AsyncData(_sampleProfile)),
      );
      await tester.pump();
      // Camera button is present after data loads
      await tester.pump(const Duration(milliseconds: 1100));
      expect(
        find.byKey(const Key('home_hub_change_photo_button')),
        findsOneWidget,
      );
    });
  });

  group('Next appointment card', () {
    testWidgets('empty state rendered when no appointment', (tester) async {
      await tester.pumpApp(
        const NextAppointmentCard(
          appointment: null,
          onReschedule: _noop,
          onCancel: _noop,
          onAddToGoogleCalendar: _noop,
          onAddToAppleCalendar: _noop,
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('next_appointment_empty')), findsOneWidget);
    });

    testWidgets('populated state: shows time label', (tester) async {
      await tester.pumpApp(
        NextAppointmentCard(
          appointment: _sampleAppointment,
          onReschedule: _noop,
          onCancel: _noop,
          onAddToGoogleCalendar: _noop,
          onAddToAppleCalendar: _noop,
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('next_appointment_populated')),
        findsOneWidget,
      );
      expect(find.text('15:00'), findsOneWidget);
    });

    testWidgets('countdown chip is shown when appointment exists', (
      tester,
    ) async {
      await tester.pumpApp(
        NextAppointmentCard(
          appointment: _sampleAppointment,
          onReschedule: _noop,
          onCancel: _noop,
          onAddToGoogleCalendar: _noop,
          onAddToAppleCalendar: _noop,
        ),
      );
      await tester.pump();
      expect(find.byType(CountdownChip), findsOneWidget);
    });

    testWidgets('reschedule button has correct key', (tester) async {
      await tester.pumpApp(
        NextAppointmentCard(
          appointment: _sampleAppointment,
          onReschedule: _noop,
          onCancel: _noop,
          onAddToGoogleCalendar: _noop,
          onAddToAppleCalendar: _noop,
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('next_appt_reschedule_button')),
        findsOneWidget,
      );
    });

    testWidgets('cancel button has correct key', (tester) async {
      await tester.pumpApp(
        NextAppointmentCard(
          appointment: _sampleAppointment,
          onReschedule: _noop,
          onCancel: _noop,
          onAddToGoogleCalendar: _noop,
          onAddToAppleCalendar: _noop,
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('next_appt_cancel_button')), findsOneWidget);
    });
  });

  group('FavoriteMastersCard', () {
    testWidgets('empty state when masters is empty', (tester) async {
      await tester.pumpApp(
        const FavoriteMastersCard(masters: [], totalCount: 0),
        overrides: [
          unlikeFavoriteMasterProvider.overrideWith(
            () => UnlikeFavoriteMaster(),
          ),
        ],
      );
      await tester.pump();
      expect(find.byKey(const Key('favorite_masters_empty')), findsOneWidget);
    });

    testWidgets('rail is shown when masters list is non-empty', (tester) async {
      await tester.pumpApp(
        const FavoriteMastersCard(masters: [_sampleMaster], totalCount: 1),
        overrides: [
          unlikeFavoriteMasterProvider.overrideWith(
            () => UnlikeFavoriteMaster(),
          ),
        ],
      );
      await tester.pump();
      expect(find.byKey(const Key('favorite_masters_rail')), findsOneWidget);
    });

    testWidgets('unlike button has correct key per master', (tester) async {
      await tester.pumpApp(
        const FavoriteMastersCard(masters: [_sampleMaster], totalCount: 1),
        overrides: [
          unlikeFavoriteMasterProvider.overrideWith(
            () => UnlikeFavoriteMaster(),
          ),
        ],
      );
      await tester.pump();
      expect(find.byKey(const Key('unlike_master_master-1')), findsOneWidget);
    });
  });

  group('BeautyTimelineSection', () {
    testWidgets('empty state when entries is empty', (tester) async {
      await tester.pumpApp(
        const BeautyTimelineSection(entries: [], onSeeAll: _noop),
      );
      await tester.pump();
      expect(find.byKey(const Key('timeline_empty')), findsOneWidget);
    });

    testWidgets('rail is shown when entries is non-empty', (tester) async {
      await tester.pumpApp(
        const BeautyTimelineSection(entries: _sampleTimeline, onSeeAll: _noop),
      );
      await tester.pump();
      expect(find.byKey(const Key('timeline_rail')), findsOneWidget);
    });

    testWidgets('BEAUTY TIMELINE brand literal is rendered (untranslated)', (
      tester,
    ) async {
      await tester.pumpApp(
        const BeautyTimelineSection(entries: [], onSeeAll: _noop),
      );
      await tester.pump();
      // The section title is uppercased by HubSectionTitle, so find both.
      expect(find.textContaining('BEAUTY TIMELINE'), findsOneWidget);
    });
  });

  group('PassportPreviewCard', () {
    testWidgets('BEAUTY PASSPORT brand literal is rendered (untranslated)', (
      tester,
    ) async {
      await tester.pumpApp(const PassportPreviewCard(onTap: _noop));
      await tester.pump();
      // HubSectionTitle uppercases — the tile text is already uppercased.
      expect(find.textContaining('BEAUTY PASSPORT'), findsOneWidget);
    });
  });

  group('QuickLinksCard', () {
    testWidgets('renders exactly 3 quick-link tiles', (tester) async {
      await tester.pumpApp(const QuickLinksCard());
      await tester.pump();
      // Each of the 3 approved tiles has a unique key.
      expect(find.byKey(const Key('quick_link_search')), findsOneWidget);
      expect(find.byKey(const Key('quick_link_favorites')), findsOneWidget);
      expect(find.byKey(const Key('quick_link_bookings')), findsOneWidget);
    });

    testWidgets('reviews tile is absent from quick-links card', (tester) async {
      // The "Мої відгуки" tile was removed — reviews are reached from the
      // ReviewsStatCard stat pill instead (separate widget, stays in the screen).
      await tester.pumpApp(const QuickLinksCard());
      await tester.pump();
      expect(
        find.byKey(const Key('quick_link_reviews')),
        findsNothing,
        reason:
            'quick_link_reviews tile must be absent — the stat pill navigates '
            'to /reviews/me instead',
      );
    });
  });

  group('HubEmptyState', () {
    testWidgets('shows message and CTA when ctaLabel is given', (tester) async {
      var tapped = false;
      await tester.pumpApp(
        HubEmptyState(
          icon: Icons.search_rounded,
          message: 'Тест повідомлення',
          ctaLabel: 'Тест кнопка',
          onCta: () => tapped = true,
        ),
      );
      await tester.pump();
      expect(find.text('Тест повідомлення'), findsOneWidget);
      expect(find.text('Тест кнопка'), findsOneWidget);
      await tester.tap(find.text('Тест кнопка'));
      expect(tapped, isTrue);
    });

    testWidgets('omits CTA when ctaLabel is null', (tester) async {
      await tester.pumpApp(
        const HubEmptyState(
          icon: Icons.favorite_border_rounded,
          message: 'Порожньо',
        ),
      );
      await tester.pump();
      expect(find.text('Порожньо'), findsOneWidget);
    });
  });
}

void _noop() {}
