// Regression — Ранок/День/Вечір slot-group HEADINGS were bucketed on the raw
// UTC hour while the chip label beside them rendered the KYIV wall-clock.
//
// THE BUG THAT SHIPPED
// --------------------
// `BookingSlot.startAt` is a canonical UTC instant (the generated built_value
// client ends `Iso8601DateTimeSerializer.deserialize` in `.toUtc()`). Both
// pickers bucketed on `s.startAt.hour` — the UTC hour — while rendering
// `formatSlotTime(s.startAt)` → `toBeauticaTime(...)`, the Kyiv wall-clock.
// The two disagree by the Kyiv offset (+3 summer / +2 winter), so a master
// working 13:00–15:00 Kyiv got chips correctly labelled `13:00 13:30 14:00`
// filed under the heading «Ранок». Wrong on EVERY device, Kyiv ones included —
// this is not a device-zone leak.
//
// Fixed to `toBeauticaTime(s.startAt).hour` at both call sites:
//   • `slot_picker_screen.dart`             `_SlotsSectionState._bucketsFor`
//   • `widgets/master_schedule_page.dart`   `_MasterSchedulePageState._bucketSlots`
// Boundaries unchanged: `< 12` morning, `< 17` afternoon, else evening.
//
// WHY NOTHING CAUGHT IT — the three gaps this file closes
// --------------------------------------------------------
//   1. Nothing in the corpus referenced `SlotGroup`, `bookingMorningLabel` /
//      `bookingAfternoonLabel` / `bookingEveningLabel`, so the
//      `if (morning.isNotEmpty)` heading branches and the `hour < 12` /
//      `hour < 17` boundaries were entirely unexercised.
//   2. Nothing asserted a slot chip's RENDERED LABEL. Every picker assertion
//      went through `find.byWidgetPredicate((w) => w is SlotChip && …)` or the
//      raw-UTC-ISO `Key`, so label-vs-heading COHERENCE — the whole content of
//      this bug — had no pin anywhere.
//   3. A fixture trap masked it: slot fixtures built with a bare local
//      `DateTime(...)` have a `.hour` that coincidentally AGREES with their
//      Kyiv label on the Kyiv dev VM, so they stayed green either way.
//
// THE FIXTURE RULE THIS FILE FOLLOWS (do not copy a local `DateTime(...)`)
// ------------------------------------------------------------------------
// Every slot instant below is a hard-coded `DateTime.utc(...)` literal and
// every expected chip label is a hard-coded Kyiv wall-clock string. Neither
// side is derived from the other, and neither is derived from `tz` — so no
// assertion can be satisfied by the same conversion it is meant to police,
// and none of them changes value when the host `TZ` changes. Deriving the
// instant from a `tz.TZDateTime(beauticaZone, …)` would have been
// self-referential (`toBeauticaTime` proving `toBeauticaTime`); building it
// with a bare `DateTime(...)` would have been gap 3 all over again.
//
// CLOCK COHERENCE (M15): `clockProvider` is pinned to a fixed UTC instant on
// the SAME Kyiv day the slot fixtures sit on, so the calendar the test taps and
// the fixture it asserts against read one clock. Never a pinned fixture against
// a live app clock, or vice versa.
//
// BOTH BOUNDARIES, BOTH SEASONS. Each of the two cut points is pinned with a
// PAIR — one instant just below it (which must NOT move: the control) and one
// exactly on it (which must move up a bucket) — in a summer month (UTC+3) and
// a winter month (UTC+2). A summer-only file would leave the winter shift
// unpinned; a boundary without its control would not prove the boundary is
// still at 12/17 rather than merely somewhere.
//
// PRE-FIX BEHAVIOUR OF EVERY FIXTURE BELOW (`s.startAt.hour`, the old code):
//
//   season  UTC       Kyiv    correct bucket   pre-fix bucket     verdict
//   ------  --------  ------  ---------------  -----------------  --------
//   summer  08:59     11:59   morning          8  → morning       control
//   summer  09:00     12:00   afternoon        9  → morning       RED
//   summer  10:00     13:00   afternoon        10 → morning       RED
//   summer  13:59     16:59   afternoon        13 → afternoon     control
//   summer  14:00     17:00   evening          14 → afternoon     RED
//   winter  09:59     11:59   morning          9  → morning       control
//   winter  10:00     12:00   afternoon        10 → morning       RED
//   winter  14:59     16:59   afternoon        14 → afternoon     control
//   winter  15:00     17:00   evening          15 → afternoon     RED
//
// Chip `Key`s deliberately stay on the raw UTC ISO string (identity, not
// display), so this file never locates a chip by key — it locates it by its
// RENDERED LABEL and reads the label off its enclosing [SlotGroup]. Headings
// are compared against `AppLocalizations` values, never the Cyrillic literal
// (mobile-qa M2 / `forbid_cyrillic_finder.sh`).

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/domain/working_day.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_time_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_schedule_page.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Fixture instants — hard-coded UTC, with their hard-coded Kyiv rendering.
// ---------------------------------------------------------------------------

/// Summer Kyiv day (EEST, UTC+3) the summer fixtures and the summer pinned
/// clock both sit on.
// Re-anchoring this to `DateTime.now()` would move the expected '13:00' with
// it and assert nothing. Nothing in this file reads `isPast`.
// future-date-ok: a fixed UTC instant whose KYIV rendering is the assertion.
final DateTime kSummerClock = DateTime.utc(2026, 7, 20, 9); // 12:00 Kyiv

/// Winter Kyiv day (EET, UTC+2) — the offset is +2 here, so a summer-only
/// suite would leave this shift unpinned.
// Same rationale as [kSummerClock] — a fixed instant whose Kyiv rendering IS
// the assertion.
// future-date-ok: fixed UTC instant, Kyiv rendering asserted as a literal.
final DateTime kWinterClock = DateTime.utc(2027, 1, 15, 10); // 12:00 Kyiv

/// A 30-minute bookable slot starting at the UTC instant [startUtc].
///
/// `endAt` is never rendered by either picker (only `startAt` reaches
/// `formatSlotTime`), so it is derived — nothing asserts against it.
BookingSlot slotAt(DateTime startUtc) => BookingSlot(
  startAt: startUtc,
  endAt: startUtc.add(const Duration(minutes: 30)),
  available: true,
);

// Summer (UTC+3) ------------------------------------------------------------
// future-date-ok: fixed UTC instant, Kyiv rendering asserted as a literal.
final BookingSlot sKyiv1159 = slotAt(DateTime.utc(2026, 7, 20, 8, 59));
// future-date-ok: fixed UTC instant, Kyiv rendering asserted as a literal.
final BookingSlot sKyiv1200 = slotAt(DateTime.utc(2026, 7, 20, 9));
// future-date-ok: fixed UTC instant, Kyiv rendering asserted as a literal.
final BookingSlot sKyiv1300 = slotAt(DateTime.utc(2026, 7, 20, 10));
// future-date-ok: fixed UTC instant, Kyiv rendering asserted as a literal.
final BookingSlot sKyiv1330 = slotAt(DateTime.utc(2026, 7, 20, 10, 30));
// future-date-ok: fixed UTC instant, Kyiv rendering asserted as a literal.
final BookingSlot sKyiv1400 = slotAt(DateTime.utc(2026, 7, 20, 11));
// future-date-ok: fixed UTC instant, Kyiv rendering asserted as a literal.
final BookingSlot sKyiv1659 = slotAt(DateTime.utc(2026, 7, 20, 13, 59));
// future-date-ok: fixed UTC instant, Kyiv rendering asserted as a literal.
final BookingSlot sKyiv1700 = slotAt(DateTime.utc(2026, 7, 20, 14));
// future-date-ok: fixed UTC instant, Kyiv rendering asserted as a literal.
final BookingSlot sKyiv0900 = slotAt(DateTime.utc(2026, 7, 20, 6));
// future-date-ok: fixed UTC instant, Kyiv rendering asserted as a literal.
final BookingSlot sKyiv1900 = slotAt(DateTime.utc(2026, 7, 20, 16));

// OUTER EDGES of the Kyiv day (see the `'the outer edges of the Kyiv day'`
// test). Note the DATE shift on the first one: Kyiv midnight on 2026-07-20 is
// the PREVIOUS UTC calendar day at 21:00Z, which is precisely why it is worth
// pinning — it is the one fixture in this file whose UTC hour (21) is not
// merely offset from its Kyiv hour (0) but wraps past both the 12 and the 17
// cut points, landing in the WRONG bucket at the far end of the list rather
// than one bucket early.
// future-date-ok: fixed UTC instant, Kyiv rendering asserted as a literal.
final BookingSlot sKyiv0000 = slotAt(DateTime.utc(2026, 7, 19, 21));
// future-date-ok: fixed UTC instant, Kyiv rendering asserted as a literal.
final BookingSlot sKyiv2359 = slotAt(DateTime.utc(2026, 7, 20, 20, 59));

// Winter (UTC+2) ------------------------------------------------------------
// future-date-ok: fixed UTC instant, Kyiv rendering asserted as a literal.
final BookingSlot wKyiv1159 = slotAt(DateTime.utc(2027, 1, 15, 9, 59));
// future-date-ok: fixed UTC instant, Kyiv rendering asserted as a literal.
final BookingSlot wKyiv1200 = slotAt(DateTime.utc(2027, 1, 15, 10));
// future-date-ok: fixed UTC instant, Kyiv rendering asserted as a literal.
final BookingSlot wKyiv1659 = slotAt(DateTime.utc(2027, 1, 15, 14, 59));
// future-date-ok: fixed UTC instant, Kyiv rendering asserted as a literal.
final BookingSlot wKyiv1700 = slotAt(DateTime.utc(2027, 1, 15, 15));

// ---------------------------------------------------------------------------
// Shared fake repository — every requested day is working, and the SAME
// pre-seeded slot list answers whichever date the picker asks for.
// ---------------------------------------------------------------------------

class FakeSlotRepository implements SlotRepository {
  FakeSlotRepository(this.slots);

  final List<BookingSlot> slots;

  @override
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
    CancelToken? cancelToken,
  }) async => slots;

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
}

// ---------------------------------------------------------------------------
// Assertion helpers — locate a chip by its RENDERED LABEL, read the heading
// off its enclosing SlotGroup.
// ---------------------------------------------------------------------------

/// The `label` of every [SlotGroup] currently rendered, in render order.
///
/// Reading the widget's own `label` field (rather than `find.text`) keeps the
/// assertion off Cyrillic literals AND lets an EMPTY-bucket case be expressed
/// as an exact list — which is what pins the `if (bucket.isNotEmpty)` heading
/// branches.
List<String> renderedGroupLabels(WidgetTester tester) => tester
    .widgetList<SlotGroup>(find.byType(SlotGroup))
    .map((SlotGroup g) => g.label)
    .toList(growable: false);

/// The heading the chip labelled [time] is filed under.
///
/// Fails loudly when no chip carries that label — which is itself half the
/// contract: the chip must READ the Kyiv wall-clock, not the UTC one.
String headingOfChip(WidgetTester tester, String time) {
  final Finder chip = find.descendant(
    of: find.byType(SlotGroup),
    matching: find.text(time),
  );
  expect(
    chip,
    findsOneWidget,
    reason:
        'expected exactly one slot chip rendering the Kyiv wall-clock "$time"',
  );
  final Finder group = find.ancestor(
    of: chip,
    matching: find.byType(SlotGroup),
  );
  expect(group, findsOneWidget);
  return tester.widget<SlotGroup>(group).label;
}

// ---------------------------------------------------------------------------
// Harness A — the independent-master picker (SlotDateScreen → SlotTimeScreen)
// ---------------------------------------------------------------------------

const Master kMaster = Master(
  id: 'master-1',
  firstName: 'Olena',
  lastName: 'Kovalchuk',
  avgRating: 4.8,
  reviewCount: 12,
  type: MasterType.independentMaster,
);

const MasterService kService = MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Manicure',
  durationMinutes: 60,
  priceMin: 500,
  priceDisplay: '500',
  category: 'MANICURE',
);

GoRouter independentRouter() => GoRouter(
  initialLocation: RouteNames.bookingSlots,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.bookingSlots,
      builder: (BuildContext context, GoRouterState state) =>
          const SlotDateScreen(
            args: BookingSlotPickerArgs(
              masterId: 'master-1',
              master: kMaster,
              services: <MasterService>[kService],
            ),
          ),
      routes: <RouteBase>[
        GoRoute(
          path: 'time',
          builder: (BuildContext context, GoRouterState state) =>
              SlotTimeScreen(args: state.extra! as BookingSlotPickerArgs),
        ),
      ],
    ),
  ],
);

/// Pumps [SlotTimeScreen] with [slots] seeded, on a clock pinned to [clock].
///
/// The tapped day is derived from the SAME pinned instant the app is on
/// (`kyivToday(() => clock)`), never from the host clock — mixing the two is
/// the M15 trap that silently taps a past, untappable cell.
Future<AppLocalizations> pumpIndependentTimeScreen(
  WidgetTester tester, {
  required DateTime clock,
  required List<BookingSlot> slots,
}) async {
  await tester.pumpRoutedApp(
    independentRouter(),
    overrides: <Object>[
      slotRepositoryProvider.overrideWith((_) => FakeSlotRepository(slots)),
      clockProvider.overrideWithValue(() => clock),
    ],
  );
  await tester.pumpAndSettle();

  await tester.tapCalendarDay(kyivToday(() => clock).day);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('booking-summary-cta')));
  await tester.pumpAndSettle();

  expect(find.byType(SlotTimeScreen), findsOneWidget);
  return AppLocalizations.of(tester.element(find.byType(SlotTimeScreen)));
}

// ---------------------------------------------------------------------------
// Harness B — the salon step-3 picker (SalonTimeScreen → MasterSchedulePage)
// ---------------------------------------------------------------------------

const SalonCatalogService kSalonService = SalonCatalogService(
  id: 'svc-1',
  name: 'Manicure',
  durationLabel: '1h',
  priceDisplay: '500',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
);

const SalonMasterSchedule kVisit = SalonMasterSchedule(
  masterId: 'm2',
  firstName: 'Sofia',
  lastName: 'Melnyk',
  type: MasterType.salonMaster,
  avgRating: 5.0,
  reviewCount: 3,
  services: <SalonCatalogService>[kSalonService],
  orderedMasterServiceIds: <String>['assign-m2-svc1'],
);

GoRouter salonRouter() => GoRouter(
  initialLocation: RouteNames.salonBookingTime,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.salonBookingTime,
      builder: (BuildContext context, GoRouterState state) =>
          const SalonTimeScreen(
            args: SalonBookingTimeArgs(salonId: 'salon-1', visit: kVisit),
          ),
    ),
  ],
);

/// Pumps [MasterSchedulePage]'s TIME phase (inside the real
/// [SalonTimeScreen]) with [slots] seeded, on a clock pinned to [clock].
Future<AppLocalizations> pumpSalonTimePhase(
  WidgetTester tester, {
  required DateTime clock,
  required List<BookingSlot> slots,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpRoutedApp(
    salonRouter(),
    overrides: <Object>[
      screenProtectionProvider.overrideWithValue(ScreenProtectionManager()),
      slotRepositoryProvider.overrideWith((_) => FakeSlotRepository(slots)),
      clockProvider.overrideWithValue(() => clock),
    ],
  );
  await tester.pumpAndSettle();

  await tester.tapCalendarDay(kyivToday(() => clock).day);
  await tester.pumpAndSettle();

  expect(find.byType(MasterSchedulePage), findsOneWidget);
  return AppLocalizations.of(tester.element(find.byType(MasterSchedulePage)));
}

// ---------------------------------------------------------------------------

void main() {
  // Both pickers carry the IDENTICAL bucketing code (`_bucketsFor` /
  // `_bucketSlots`) and the bug shipped in both, so the whole battery runs
  // against each — a shared body parameterised by its pump helper, not a
  // half-covered copy.
  for (final (
        String tier,
        Future<AppLocalizations> Function(
          WidgetTester, {
          required DateTime clock,
          required List<BookingSlot> slots,
        })
        pump,
      )
      in <
        (
          String,
          Future<AppLocalizations> Function(
            WidgetTester, {
            required DateTime clock,
            required List<BookingSlot> slots,
          }),
        )
      >[
        ('SlotTimeScreen', pumpIndependentTimeScreen),
        ('MasterSchedulePage', pumpSalonTimePhase),
      ]) {
    group('$tier — slot group headings follow the Kyiv wall-clock', () {
      // ── THE HEADLINE CASE ───────────────────────────────────────────────
      // 10:00Z is 13:00 Kyiv. The chip reads 13:00; the pre-fix code read
      // `.hour == 10` and filed it under «Ранок» — a chip labelled 13:00
      // sitting under the heading "Morning". This is the exact shape the user
      // reported.
      testWidgets(
        'a 10:00Z slot renders the chip "13:00" AND files it under the '
        'AFTERNOON heading — never MORNING (the shipped bug)',
        (WidgetTester tester) async {
          final AppLocalizations l10n = await pump(
            tester,
            clock: kSummerClock,
            slots: <BookingSlot>[sKyiv1300],
          );

          expect(
            headingOfChip(tester, '13:00'),
            l10n.bookingAfternoonLabel,
            reason:
                '10:00Z is 13:00 Kyiv. Bucketing on the raw UTC hour (10) '
                'files it under «Ранок» while the chip beside the heading '
                'reads 13:00 — the exact incoherence that shipped.',
          );
          expect(
            renderedGroupLabels(tester),
            <String>[l10n.bookingAfternoonLabel],
            reason:
                'the MORNING heading must not render at all — its bucket is '
                'empty once the Kyiv hour is used',
          );
        },
      );

      // ── BOUNDARY PAIR 1 — morning → afternoon, SUMMER (UTC+3) ───────────
      testWidgets(
        'summer 12:00 cut point: Kyiv 11:59 stays MORNING, Kyiv 12:00 moves '
        'to AFTERNOON',
        (WidgetTester tester) async {
          final AppLocalizations l10n = await pump(
            tester,
            clock: kSummerClock,
            slots: <BookingSlot>[sKyiv1159, sKyiv1200],
          );

          // Control — 08:59Z buckets to morning on BOTH versions. Its job is
          // to prove the boundary is still exactly 12, not merely "higher".
          expect(headingOfChip(tester, '11:59'), l10n.bookingMorningLabel);
          // Discriminating — 09:00Z is Kyiv 12:00; the old code read hour 9.
          expect(
            headingOfChip(tester, '12:00'),
            l10n.bookingAfternoonLabel,
            reason: '09:00Z is Kyiv 12:00 — the first afternoon slot',
          );
          expect(renderedGroupLabels(tester), <String>[
            l10n.bookingMorningLabel,
            l10n.bookingAfternoonLabel,
          ]);
        },
      );

      // ── BOUNDARY PAIR 2 — afternoon → evening, SUMMER (UTC+3) ───────────
      testWidgets(
        'summer 17:00 cut point: Kyiv 16:59 stays AFTERNOON, Kyiv 17:00 moves '
        'to EVENING',
        (WidgetTester tester) async {
          final AppLocalizations l10n = await pump(
            tester,
            clock: kSummerClock,
            slots: <BookingSlot>[sKyiv1659, sKyiv1700],
          );

          expect(headingOfChip(tester, '16:59'), l10n.bookingAfternoonLabel);
          expect(
            headingOfChip(tester, '17:00'),
            l10n.bookingEveningLabel,
            reason: '14:00Z is Kyiv 17:00 — the first evening slot',
          );
          expect(renderedGroupLabels(tester), <String>[
            l10n.bookingAfternoonLabel,
            l10n.bookingEveningLabel,
          ]);
        },
      );

      // ── BOUNDARY PAIR 3 — morning → afternoon, WINTER (UTC+2) ───────────
      // The offset is +2 here, so the UTC instants differ from the summer
      // pair above by an hour while the KYIV wall clock is identical. A
      // summer-only file leaves this shift completely unpinned.
      testWidgets(
        'winter 12:00 cut point: Kyiv 11:59 stays MORNING, Kyiv 12:00 moves '
        'to AFTERNOON (offset is +2, not +3)',
        (WidgetTester tester) async {
          final AppLocalizations l10n = await pump(
            tester,
            clock: kWinterClock,
            slots: <BookingSlot>[wKyiv1159, wKyiv1200],
          );

          expect(headingOfChip(tester, '11:59'), l10n.bookingMorningLabel);
          expect(
            headingOfChip(tester, '12:00'),
            l10n.bookingAfternoonLabel,
            reason: '10:00Z is Kyiv 12:00 in JANUARY (EET, +2)',
          );
          expect(renderedGroupLabels(tester), <String>[
            l10n.bookingMorningLabel,
            l10n.bookingAfternoonLabel,
          ]);
        },
      );

      // ── BOUNDARY PAIR 4 — afternoon → evening, WINTER (UTC+2) ───────────
      testWidgets(
        'winter 17:00 cut point: Kyiv 16:59 stays AFTERNOON, Kyiv 17:00 moves '
        'to EVENING (offset is +2, not +3)',
        (WidgetTester tester) async {
          final AppLocalizations l10n = await pump(
            tester,
            clock: kWinterClock,
            slots: <BookingSlot>[wKyiv1659, wKyiv1700],
          );

          expect(headingOfChip(tester, '16:59'), l10n.bookingAfternoonLabel);
          expect(
            headingOfChip(tester, '17:00'),
            l10n.bookingEveningLabel,
            reason: '15:00Z is Kyiv 17:00 in JANUARY (EET, +2)',
          );
          expect(renderedGroupLabels(tester), <String>[
            l10n.bookingAfternoonLabel,
            l10n.bookingEveningLabel,
          ]);
        },
      );

      // ── THE OUTER EDGES OF THE DAY ──────────────────────────────────────
      // The four boundary pairs above pin the two INTERIOR cut points (12 and
      // 17). This pins the two ENDS of the range, which the earlier round left
      // untested on the judgement that "no plausible off-by-one could
      // misclassify them". That judgement was wrong for the 00:00 end, and a
      // judgement is not a pin either way:
      //
      //   Kyiv 00:00 on 2026-07-20 is 2026-07-19 21:00Z — a DIFFERENT UTC
      //   calendar day. The pre-fix `s.startAt.hour` reads 21, which is `>= 17`
      //   and files Kyiv MIDNIGHT under «Вечір» — the far end of the list from
      //   where it belongs, not one bucket over. This case is RED pre-fix.
      //
      //   Kyiv 23:59 is 20:59Z; hour 20 is also `>= 17`, so this end buckets to
      //   EVENING on BOTH versions. It is the CONTROL: it proves the fix did
      //   not simply shift everything down a bucket (a `hour - 3` style
      //   "correction" would move 23:59 out of evening and fail here while the
      //   discriminating cases above still passed).
      //
      // Both are expressed as UTC instants with hard-coded Kyiv labels, the
      // same fixture rule the whole file follows.
      testWidgets(
        'the outer edges of the Kyiv day: 00:00 is MORNING (not evening, as '
        'the raw 21:00Z hour claimed) and 23:59 is EVENING',
        (WidgetTester tester) async {
          final AppLocalizations l10n = await pump(
            tester,
            clock: kSummerClock,
            slots: <BookingSlot>[sKyiv0000, sKyiv2359],
          );

          expect(
            headingOfChip(tester, '00:00'),
            l10n.bookingMorningLabel,
            reason:
                'Kyiv midnight is 21:00Z on the PREVIOUS UTC day — the pre-fix '
                'raw hour (21) is >= 17 and filed the first slot of the day '
                'under «Вечір», at the opposite end of the list',
          );
          expect(
            headingOfChip(tester, '23:59'),
            l10n.bookingEveningLabel,
            reason:
                'the control end — 20:59Z buckets to evening either way, so a '
                'fix that merely shifted every bucket down would fail HERE',
          );
          expect(
            renderedGroupLabels(tester),
            <String>[l10n.bookingMorningLabel, l10n.bookingEveningLabel],
            reason:
                'exactly two headings — pre-fix BOTH edges collapsed into a '
                'single «Вечір» group',
          );
        },
      );

      // ── EMPTY BUCKETS RENDER NO HEADING ─────────────────────────────────
      // A morning slot and an evening slot with nothing in between: the
      // `if (afternoon.isNotEmpty)` branch must suppress its heading entirely
      // rather than render an empty «День» rule. Expressed as an EXACT list so
      // a stray heading is a failure, not a silent extra.
      testWidgets(
        'an empty bucket renders NO heading — morning + evening only, no '
        'afternoon rule between them',
        (WidgetTester tester) async {
          final AppLocalizations l10n = await pump(
            tester,
            clock: kSummerClock,
            slots: <BookingSlot>[sKyiv0900, sKyiv1900],
          );

          expect(headingOfChip(tester, '09:00'), l10n.bookingMorningLabel);
          expect(headingOfChip(tester, '19:00'), l10n.bookingEveningLabel);
          expect(
            renderedGroupLabels(tester),
            <String>[l10n.bookingMorningLabel, l10n.bookingEveningLabel],
            reason:
                'exactly two headings — the empty afternoon bucket must not '
                'render its label or its divider rule',
          );
        },
      );

      // ── THE USER'S ACTUAL SCENARIO ──────────────────────────────────────
      // A master whose ENTIRE working window is 13:00–15:00 Kyiv. On the
      // backend's fixed 30-minute grid that is three bookable starts. Pre-fix
      // this whole day rendered under «Ранок».
      //
      // The 13:30 chip is load-bearing beyond the heading: every pre-existing
      // picker fixture starts on the hour, and `13:30` appeared only as an
      // `endAt`, which is never rendered — so a half-hour START had no label
      // assertion anywhere in the corpus until this line.
      testWidgets(
        'a 13:00-15:00 Kyiv working day renders exactly 13:00 / 13:30 / 14:00, '
        'all under ONE afternoon heading',
        (WidgetTester tester) async {
          final AppLocalizations l10n = await pump(
            tester,
            clock: kSummerClock,
            slots: <BookingSlot>[sKyiv1300, sKyiv1330, sKyiv1400],
          );

          // The full rendered chip set, in order — not just "at least one".
          final List<String> chipLabels = tester
              .widgetList<SlotChip>(find.byType(SlotChip))
              .map((SlotChip c) => c.time)
              .toList(growable: false);
          expect(
            chipLabels,
            <String>['13:00', '13:30', '14:00'],
            reason:
                'the three 30-minute starts of a 13:00-15:00 Kyiv window, '
                'rendered at the Kyiv wall-clock',
          );

          for (final String label in chipLabels) {
            expect(
              headingOfChip(tester, label),
              l10n.bookingAfternoonLabel,
              reason:
                  'every slot of a 13:00-15:00 Kyiv day is afternoon; pre-fix '
                  'the UTC hours (10, 10, 11) filed the WHOLE day under '
                  '«Ранок»',
            );
          }
          expect(renderedGroupLabels(tester), <String>[
            l10n.bookingAfternoonLabel,
          ]);
        },
      );
    });
  }
}
