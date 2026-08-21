// Phase 257 (D3) — the `master-strip-<id>` Hero chain pin.
//
// WHY A GOLDEN IS NOT ENOUGH. `MasterStrip` is `Hero`-tagged
// `master-strip-<masterId>` and FLIES across three screens of the client
// booking flow — date → time → confirm (`slot_picker_screen.dart:311` and
// `:669`; `booking_confirm_screen.dart:453`, via
// `booking_summary_cards.dart`'s `masterCard` slot). A golden photographs a
// SETTLED frame and would not notice a stranded flight: drop the `Hero` wrapper
// on any one of the three and every golden in
// `test/golden/booking_slot_flow_golden_test.dart` still passes byte-for-byte,
// because the card itself renders identically — only the transition between
// screens breaks.
//
// So this file pins the chain structurally, alongside those baselines and
// authored at the same time, while the numbers above are still the SHIPPED
// ones: each of the three screens must expose EXACTLY ONE `Hero` carrying the
// tag `master-strip-<masterId>`. Track A's phases (and phase 277 in
// particular, which reworks the strip) are the ones this earns its keep
// against.
//
// EXACTLY ONE, not "at least one", is load-bearing twice over. Zero means the
// flight is stranded — the two independently-laid-out cards swap at mismatched
// y-offsets the instant the push settles (the jank this Hero was added to fix;
// see `slot_picker_test.dart`'s "identical vertical offset" test for the
// padding half of the same fix). Two on ONE screen is a hard framework error:
// Flutter asserts on duplicate Hero tags within a single subtree, so a refactor
// that promotes the strip and leaves the old call site behind fails here rather
// than at runtime on a real device.
//
// MUTATION-CHECKED. Deleting the `Hero` wrapper at
// `slot_picker_screen.dart:311` turns the SlotDateScreen case RED (verified
// 2026-08-21, then reverted). The assertion is load-bearing, not decorative.
//
// The three screens are mounted one per test with the SAME fixtures the
// golden file uses; nothing here navigates, because the tag's presence on each
// screen — not the flight itself — is what a refactor silently removes.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/booking/application/slot_picker_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/working_day.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Fixtures — same values as `test/golden/booking_slot_flow_golden_test.dart`.
// ---------------------------------------------------------------------------

const Master _kMaster = Master(
  id: 'master-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  city: 'Київ',
  street: 'вул. Хрещатик',
  buildingNo: '22',
  avgRating: 4.8,
  reviewCount: 47,
  type: MasterType.independentMaster,
);

const MasterService _kService = MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Манікюр з покриттям',
  durationMinutes: 90,
  priceMin: 500,
  priceDisplay: '500 ₴',
  category: 'NAILS',
);

const List<MasterService> _kServices = <MasterService>[_kService];

/// The expected tag. Composed from the fixture id the SAME way production
/// composes it, never hand-spelled — a test that hardcoded the literal would
/// keep passing if the interpolation source changed.
final String _kHeroTag = 'master-strip-${_kMaster.id}';

// The app clock and every fixture below hang off this ONE value (mobile-qa M15
// — one clock per test, never two).
// future-date-ok: fixed clock-override instant; the exact day is the fixture's identity, never now-relative.
final DateTime _kNow = DateTime.utc(2026, 8, 10, 9); // 12:00 Kyiv, Aug 10.
// future-date-ok: fixed twin of _kNow — 13:00 Kyiv on the same day.
final DateTime _kStartAt = DateTime.utc(2026, 8, 10, 10);

final BookingSlot _kSlot = BookingSlot(
  startAt: _kStartAt,
  endAt: _kStartAt.add(const Duration(minutes: 90)),
  available: true,
);

BookingSlotPickerArgs _slotArgs() => const BookingSlotPickerArgs(
  masterId: 'master-1',
  master: _kMaster,
  services: _kServices,
);

BookingConfirmArgs _confirmArgs() => BookingConfirmArgs(
  masterId: _kMaster.id,
  master: _kMaster,
  services: _kServices,
  startAt: _kStartAt,
  idempotencyKey: '11111111-1111-4111-8111-111111111111',
);

class _FakeSlotRepository implements SlotRepository {
  const _FakeSlotRepository();

  @override
  Future<List<WorkingDay>> getWorkingDays({
    required String masterId,
    required DateTime from,
    required DateTime to,
    List<String>? serviceIds,
    CancelToken? cancelToken,
  }) async {
    final List<WorkingDay> days = <WorkingDay>[];
    for (
      DateTime d = from;
      !d.isAfter(to);
      d = d.add(const Duration(days: 1))
    ) {
      days.add(WorkingDay(date: d, working: true));
    }
    return days;
  }

  @override
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
    CancelToken? cancelToken,
  }) async => <BookingSlot>[_kSlot];
}

/// Matches a [Hero] carrying [_kHeroTag], wherever in the tree it sits.
final Finder _masterStripHero = find.byWidgetPredicate(
  (Widget w) => w is Hero && w.tag == _kHeroTag,
  description: 'Hero(tag: "$_kHeroTag")',
);

GoRouter _router(Widget screen) => GoRouter(
  initialLocation: '/hero-chain',
  routes: <RouteBase>[
    GoRoute(
      path: '/hero-chain',
      builder: (BuildContext context, GoRouterState state) => screen,
    ),
    GoRoute(
      path: RouteNames.clientHome,
      builder: (BuildContext context, GoRouterState state) =>
          const SizedBox.shrink(),
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  List<Object> extraOverrides = const <Object>[],
}) async {
  await tester.pumpRoutedApp(
    _router(screen),
    overrides: <Object>[
      clockProvider.overrideWithValue(() => _kNow),
      slotRepositoryProvider.overrideWith((_) => const _FakeSlotRepository()),
      ...extraOverrides,
    ],
  );
  await tester.pumpAndSettle();
}

void main() {
  group('master-strip Hero chain (date → time → confirm)', () {
    testWidgets(
      'SlotDateScreen exposes exactly one Hero tagged master-strip-<masterId>',
      (tester) async {
        await _pump(tester, SlotDateScreen(args: _slotArgs()));

        expect(find.byType(MasterStrip), findsOneWidget);
        expect(
          _masterStripHero,
          findsOneWidget,
          reason:
              'SlotDateScreen is the Hero SOURCE of the flight into «Час» — '
              'without this tag the card is stranded and the two screens\' '
              'independently-laid-out strips swap at mismatched y-offsets the '
              'instant the push settles.',
        );
        expect(
          find.descendant(
            of: _masterStripHero,
            matching: find.byType(MasterStrip),
          ),
          findsOneWidget,
          reason: 'the tagged Hero must wrap the MasterStrip itself',
        );
      },
    );

    testWidgets(
      'SlotTimeScreen exposes exactly one Hero tagged master-strip-<masterId>, '
      'with the SAME tag as the date screen',
      (tester) async {
        await _pump(
          tester,
          SlotTimeScreen(args: _slotArgs()),
          extraOverrides: <Object>[
            // Seeded rather than tapped through: this screen post-frame-pops
            // itself when `selectedDate` is null (the broken-flow guard), and
            // the Hero tag — not the navigation — is what a refactor removes.
            slotPickerProvider.overrideWithValue(
              SlotPickerState(
                selectedDate: DateTime.utc(_kNow.year, _kNow.month, _kNow.day),
                selectedSlot: _kSlot,
                slots: AsyncData<List<BookingSlot>>(<BookingSlot>[_kSlot]),
              ),
            ),
          ],
        );

        expect(find.byType(MasterStrip), findsOneWidget);
        expect(
          _masterStripHero,
          findsOneWidget,
          reason:
              'SlotTimeScreen is the middle link — it is both the destination '
              'of the date screen\'s flight and the source of the confirm '
              'screen\'s.',
        );
      },
    );

    testWidgets('BookingConfirmScreen exposes exactly one Hero tagged '
        'master-strip-<masterId>', (tester) async {
      await _pump(
        tester,
        BookingConfirmScreen(args: _confirmArgs()),
        extraOverrides: <Object>[
          publicMasterProfileProvider(
            _kMaster.id,
          ).overrideWith((ref) => (_kMaster, _kServices)),
        ],
      );

      expect(find.byType(MasterStrip), findsOneWidget);
      expect(
        _masterStripHero,
        findsOneWidget,
        reason:
            'BookingConfirmScreen is the flight\'s terminus — the strip is '
            'rendered through BookingSummaryCards\' masterCard slot, which a '
            'promotion refactor is exactly the kind of change that drops the '
            'Hero wrapper on the way past.',
      );
    });
  });
}
