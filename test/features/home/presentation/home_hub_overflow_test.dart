// Phase 13.7 — HomeHub OVERFLOW regression tests.
//
// THE BUG
// -------
// The home-hub rails (BEAUTY TIMELINE, Favourite masters) and the next-
// appointment action column overflowed (yellow/black RenderFlex stripes) on
// devices with a large accessibility font scale and/or a narrow width. It
// shipped because EVERY existing home test pumps at the default 800x600 surface
// with textScale 1.0 and never varies either — so no test ever exercised the
// large-font / narrow-width layout the bug lived in.
//
// THE FIX UNDER TEST
// ------------------
//   • App-root text-scale clamp at maxScaleFactor: 1.3 in main.dart.
//   • Scale-aware rail heights in beauty_timeline_section.dart and
//     favorite_masters_card.dart (_scaledTextHeadroom adds the scaled-text
//     delta on top of the fixed medallion/avatar height).
//   • next_appointment_card.dart action column → Flexible + ConstrainedBox.
//   • hub_widgets.dart button labels → FittedBox(scaleDown) + maxLines:1.
//   • passport_preview_card.dart pill → TextOverflow.ellipsis.
//
// CLAMP NOTE — WHY WE PUMP UNCLAMPED AT 1.3
// -----------------------------------------
// main.dart applies the 1.3 clamp inside its MaterialApp.router builder. These
// tests pump the screen DIRECTLY (via pumpApp), bypassing that builder, and
// apply TextScaler.linear(1.3) WITHOUT re-clamping. That is deliberate: it
// proves the rail heights THEMSELVES tolerate 1.3 (the widget-level fix), not
// merely that the global clamp keeps the input ≤ 1.3. 1.3 is the worst in-bounds
// case the clamp can ever feed the widgets, so an unclamped 1.3 pump is exactly
// the ceiling the rails must survive. (The rail headroom reads the ambient,
// unclamped MediaQuery.textScalerOf scale, so it self-adapts to 1.3 with no
// reliance on the root clamp.)
//
// HOW OVERFLOW IS CAUGHT
// ----------------------
// A RenderFlex overflow surfaces as a thrown FlutterError during layout. Each
// matrix cell asserts `tester.takeException()` is null after pumping — zero
// overflow. The suite-wide overflow guard (test/helpers/overflow_guard.dart)
// is a second, automatic net that also fails the test in tearDown if any
// overflow was recorded.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/home_hub_screen.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/beauty_timeline_section.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/favorite_masters_card.dart';
import 'package:beautica_mobile/features/rating/application/my_rating_notifier.dart';
import 'package:beautica_mobile/features/rating/domain/client_rating.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// No-op ScreenProtectionManager for tests (native plugin must not be called).
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
// POPULATED fixtures — the bug only manifests when the rails actually render
// nodes (empty states never overflow). Long-ish labels mimic real data that
// grows under large text scale.
// ---------------------------------------------------------------------------

const _sampleProfile = ClientProfileSummary(
  firstName: 'Олександра',
  lastName: 'Коваленко-Тест',
  city: 'Львів',
  phone: '+380 97 000 00 00',
  clientRating: 4.7,
  memberSinceYear: 2026,
);

// Long-ish master/service/salon names mimic real data that grows under large
// text scale — the same reasoning as [_sampleAppointment]'s old NextAppointment
// fixture, now a full [Booking] since the Home Hub renders the SAME shared
// `BookingCard` widget «Мої записи» uses (locked decision).
final DateTime _apptStart = DateTime.now().add(const Duration(days: 2));
final _sampleAppointment = Booking(
  id: 'appt-1',
  masterId: 'master-appt-1',
  masterFirstName: 'Марія',
  masterLastName: 'Іванюк-Петренко',
  masterType: 'SALON_MASTER',
  salonName: 'Центр краси «Дорошенка»',
  serviceId: 'svc-appt-1',
  serviceName: 'Манікюр з покриттям гель-лак',
  durationMinutes: 60,
  price: 650,
  startAt: _apptStart,
  endAt: _apptStart.add(const Duration(hours: 1)),
  status: BookingStatus.confirmed,
  canReview: false,
);

const _sampleMasters = <FavoriteMasterItem>[
  FavoriteMasterItem(
    masterId: 'master-1',
    favoriteId: 'fav-1',
    name: 'Марія Іванюк-Петренко',
    lastServiceName: 'Манікюр з покриттям',
    rating: 5.0,
    reviewCount: 142,
    initials: 'МІ',
  ),
  FavoriteMasterItem(
    masterId: 'master-2',
    favoriteId: 'fav-2',
    name: 'Богдана Сидоренко',
    lastServiceName: 'Брови та ламінування',
    rating: 4.9,
    reviewCount: 88,
    initials: 'БС',
  ),
];

const _sampleTimeline = <TimelineEntry>[
  TimelineEntry(category: 'Манікюр гель-лак', dateLabel: '18.06.2026'),
  TimelineEntry(category: 'Брови ламінування', dateLabel: '12.05.2026'),
  TimelineEntry(category: 'Косметологія', dateLabel: '01.04.2026'),
];

// ---------------------------------------------------------------------------
// Shared FULLY-POPULATED overrides — all four sections render real content.
// ---------------------------------------------------------------------------

List<Object> _populatedOverrides() {
  return [
    screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
    // Rating pill now sources from myRatingProvider; override it so the widget
    // test makes no real network call and leaks no keepAlive Timer.
    myRatingProvider.overrideWith((ref) async => const ClientRating()),
    clientProfileProvider.overrideWith((ref) async => _sampleProfile),
    nextAppointmentProvider.overrideWith((ref) async => _sampleAppointment),
    favoriteMastersProvider.overrideWith((ref) async => _sampleMasters),
    beautyTimelineProvider.overrideWith((ref) async => _sampleTimeline),
    unlikeFavoriteMasterProvider.overrideWith(() => UnlikeFavoriteMaster()),
  ];
}

// The matrix the bug lived in: a too-narrow surface AND a normal one, each at
// text scale 1.0 (baseline) and 1.3 (the clamp ceiling — worst in-bounds case).
const double _smallPhoneWidth = 320; // smallest supported phone
const double _normalWidth = 390; // typical modern phone (iPhone 14-class)
const List<double> _matrixWidths = <double>[_smallPhoneWidth, _normalWidth];
const List<double> _matrixScales = <double>[1.0, 1.3];

void main() {
  // ── 1. Full-screen matrix: size × textScale, assert zero overflow ─────────
  group('HomeHubScreen overflow matrix (size × textScale)', () {
    for (final double width in _matrixWidths) {
      for (final double scale in _matrixScales) {
        testWidgets(
          'no overflow at ${width.toInt()}px width × textScale $scale '
          '(populated rails)',
          (tester) async {
            await tester.pumpApp(
              const HomeHubScreen(),
              overrides: _populatedOverrides(),
              width: width,
              textScaleFactor: scale,
            );
            // Resolve the provider futures + run the stagger reveal so every
            // section is laid out at its final height.
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 1200));

            // A RenderFlex overflow throws a FlutterError during layout, which
            // takeException() returns. Null ⇒ zero overflow across this cell.
            expect(
              tester.takeException(),
              isNull,
              reason:
                  'HomeHubScreen must not overflow at '
                  '${width.toInt()}px × textScale $scale — this is the '
                  'narrow-width / large-font matrix the rails regressed on.',
            );
          },
        );
      }
    }
  });

  // ── 2. Timeline rail in isolation at the worst cell (320 × 1.3) ───────────
  group('BeautyTimelineSection rail — isolated overflow guard', () {
    testWidgets(
      'no overflow at 320px width × textScale 1.3 (unclamped, populated)',
      (tester) async {
        await tester.pumpApp(
          const BeautyTimelineSection(
            entries: _sampleTimeline,
            onSeeAll: _noop,
          ),
          width: _smallPhoneWidth,
          textScaleFactor: 1.3,
        );
        await tester.pump();

        expect(
          find.byKey(const Key('timeline_rail')),
          findsOneWidget,
          reason: 'populated rail must render its nodes (sanity)',
        );
        expect(
          tester.takeException(),
          isNull,
          reason:
              'BeautyTimelineSection node (medallion + 2 text lines) must '
              'tolerate textScale 1.3 unclamped at 320px — _scaledTextHeadroom '
              'absorbs the scaled text delta.',
        );
      },
    );
  });

  // ── 3. Favourites mini-card rail in isolation at the worst cell ───────────
  group('FavoriteMastersCard rail — isolated overflow guard', () {
    testWidgets(
      'no overflow at 320px width × textScale 1.3 (unclamped, populated)',
      (tester) async {
        await tester.pumpApp(
          const FavoriteMastersCard(masters: _sampleMasters, totalCount: 2),
          overrides: [
            unlikeFavoriteMasterProvider.overrideWith(
              () => UnlikeFavoriteMaster(),
            ),
          ],
          width: _smallPhoneWidth,
          textScaleFactor: 1.3,
        );
        await tester.pump();

        expect(
          find.byKey(const Key('favorite_masters_rail')),
          findsOneWidget,
          reason: 'populated rail must render its mini-cards (sanity)',
        );
        expect(
          tester.takeException(),
          isNull,
          reason:
              'FavoriteMastersCard mini-card (avatar + 3 text lines) must '
              'tolerate textScale 1.3 unclamped at 320px — _scaledTextHeadroom '
              'absorbs the scaled text delta.',
        );
      },
    );
  });
}

void _noop() {}
