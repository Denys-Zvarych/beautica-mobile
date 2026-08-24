// Phase 257 — Visual regression tripwire for the CLIENT slot/confirm/success
// flow (`/booking/slots`, `/booking/slots/time`, `/booking/confirm`,
// `/booking/success`).
//
// AUTHORED BEFORE TRACK A (phases 258-266) TOUCHES ANY OF THESE SCREENS.
// Until this file landed, NO golden covered ANY of the four client
// `/booking/...` route screens, so a refactor that rewires them onto shared
// leaves could change their rendering and the whole suite would stay green.
// Track A's correctness claim is "the render is byte-identical"; these
// baselines are what makes that claim checkable at all. After Track A moves
// the private leaves, this file MUST pass UNMODIFIED and WITHOUT
// `--update-goldens`.
//
// D4 (phase brief): this phase ADDS baselines, it re-blesses none. The 7 PNGs
// of `bookings_month_calendar_panel_golden_test.dart`, the 30 of
// `master_create_booking_wizard_golden_test.dart` and the 3 of
// `master_strip_shell_golden_test.dart` (which carries a byte-identical parity
// assertion between its inert and tappable rest baselines) are untouched.
//
// TEN CELLS (phase brief D2), one screenshot per cell per matrix entry:
//   • `slot-date`           — SlotDateScreen, working days resolved, no day
//                             selected (the «Далі» CTA therefore disabled).
//   • `slot-date-error`     — `workingDaysProvider` in error →
//                             `_WorkingDaysErrorBody`'s centred message +
//                             «Спробувати ще раз».
//   • `slot-time`           — SlotTimeScreen with slots resolved into ALL
//                             THREE Ранок/День/Вечір buckets and the 13:00
//                             Kyiv chip selected (so the CTA's chosen-window
//                             line renders too).
//   • `slot-time-empty`     — slots resolve to `[]` → `_NoSlotsEmptyState`
//                             (the fully-booked working day).
//   • `confirm`             — BookingConfirmScreen, resolved master, CREATE
//                             path: «Коментар для майстра» visible.
//   • `confirm-reschedule`  — `rescheduleBookingId != null`: CTA swaps to
//                             `bookingRescheduleSubmitCta` and the comment
//                             field is GONE.
//   • `confirm-error`       — a failed submit → `_SubmitErrorBanner` pinned
//                             above the CTA. Driven through the REAL CTA tap,
//                             because `_failure` is private screen state with
//                             no other way in.
//   • `confirm-loading`     — `publicMasterProfileProvider` unresolved →
//                             `_LoadingBody`'s skeleton shimmer.
//   • `success`             — BookingSuccessScreen, create variant.
//   • `success-reschedule`  — `BookingSuccessArgs.isReschedule == true`.
//
// The four error / empty / loading cells are the ones that matter most:
// Track A's promotions (261, 262, 263) touch exactly those states and nothing
// else in the repo renders them.
//
// PHASE 265 D6 — four ADDITIVE walk-in cells, deferred here by Phase 260 D6
// until the routed walk-in chain went live (Phase 264):
//   • `slot-date-walkin`  — SlotDateScreen, `hideMasterIdentity: true`.
//   • `slot-time-walkin`  — SlotTimeScreen, `hideMasterIdentity: true`.
//   • `confirm-walkin`    — BookingConfirmScreen, a [WalkInGuest] seed: no
//                           master card, no address block, no comment field.
//   • `success-walkin`    — BookingSuccessScreen, `isWalkIn: true`.
// The original 10 cells / 60 PNGs are byte-identical and untouched by this
// addition — see this phase's own D6 for the generation discipline
// (scoped `--update-goldens`, then a full re-run WITHOUT the flag, then
// `git status` on the goldens directory: exactly 24 additions, zero
// modifications).
//
// AUDIT-FIX CYCLE 2 (FIX 1, 2026-08-21) — a 15th, purely ADDITIVE cell:
//   • `success-walkin-guest` — BookingSuccessScreen, `isWalkIn: true` PLUS a
//                               non-null `guest`, pinning the restored
//                               guest-identity card
//                               (`booking-success-guest-card`). The
//                               pre-existing `success-walkin` cell keeps its
//                               `guest: null` seed and therefore renders NO
//                               card — its six baselines are byte-identical
//                               before/after this addition (sha256-verified,
//                               scoped with `--plain-name`).
//
// Matrix: 15 cells x {320, 360, 414} dp x {textScale 1.0, 1.3} = 90 PNGs.
//
// WHAT `success-reschedule` DOES AND DOES NOT PIN — stated, not papered over.
// The whole suite runs in alchemist CI mode (`obscureText: true`, set in
// `test/flutter_test_config.dart`), which paints every text run as a block
// sized to its PARAGRAPH, not its glyphs. Measured on the generated baselines:
// the title/subline region of `success` and `success-reschedule` is
// byte-identical, so this cell pins the reschedule variant's LAYOUT (a
// single-service recap) but CANNOT pin its copy branch
// (`bookingRescheduleSuccessTitle` / `bookingRescheduleSuccessSubline`). That
// copy is already pinned by `integration_test/client_reschedule_flow_test.dart`
// (`:368`), which asserts the localized title directly — do not "fix" this cell
// by disabling `obscureText`, which would make every golden in this directory
// host-font-dependent. `confirm-reschedule` has no such gap: its CTA-label and
// absent-comment-field deltas are both visible (measured — the footer diff
// bbox is non-empty).
//
// ---------------------------------------------------------------------------
// WHY THE CELLS ARE SEEDED RATHER THAN TAPPED THROUGH
// ---------------------------------------------------------------------------
// `master_create_booking_wizard_golden_test.dart` drives its five steps by
// tapping, and it can: that wizard is ONE screen whose steps swap inside a
// single route, so every step stays inside the subtree alchemist photographs.
// This flow is FOUR separate `go_router` routes. Alchemist captures
// `find.byKey(FlutterGoldenTestAdapter.rootKey)` — the wrapper it mounts AT the
// route — so a screen reached by pushing a SECOND route is not reliably inside
// the captured render object. Each cell therefore mounts its own screen
// directly and seeds the state that screen reads:
//   • `slotPickerProvider.overrideWithValue(...)` for the time screen (the
//     generated provider exposes that override natively — see
//     `slot_picker_notifier.g.dart`), and
//   • `publicMasterProfileProvider(id).overrideWith(...)` for the confirm
//     screen.
// `confirm-error` is the ONE exception: `_failure` is private `State` with no
// provider seam, so that cell taps the real «Записатись» CTA against a
// repository that throws. That is a genuine drive, not a seed.
//
// ---------------------------------------------------------------------------
// CLOCK — BOTH SIDES PINNED (mobile-qa M15)
// ---------------------------------------------------------------------------
// `clockProvider` is pinned to [_kNow] and EVERY fixture in this file is
// derived from that same instant or is a fixed UTC instant read only for
// display. Nothing here reads the host clock, so the fixture clock and the app
// clock are the same clock — the invariant M15 names. The calendar's "today"
// ring, its past-day gate and the working-days window the fake answers all
// hang off [_kNow], which is why `TZ=UTC` and `TZ=Europe/Kyiv` produce
// byte-identical PNGs (verified both ways before these baselines were
// committed).
//
// ---------------------------------------------------------------------------
// ANIMATIONS
// ---------------------------------------------------------------------------
// The pump wraps the router content in a `MediaQuery` with
// `disableAnimations: true`. That is not cosmetic: `BookingSuccessScaffold`
// runs a 1350 ms staggered entrance AND a Lottie badge, and
// `disableAnimations` is the scaffold's own documented "jump to the resting
// state" path (`booking_success_scaffold.dart`'s `didChangeDependencies`), the
// same one `booking_success_scaffold_test.dart` uses for determinism. Applied
// to every cell uniformly so no cell can drift on entrance timing; the resting
// state is what `pumpAndSettle` would have reached anyway.
//
// The success cells additionally WARM `sharedLottieCache` before pumping. The
// badge's composition loads asynchronously and `Lottie`'s `frameBuilder` paints
// a static `StatusMedallion` placeholder until it lands — so an un-warmed cache
// would let the SAME cell photograph either the placeholder or the final Lottie
// frame depending on I/O timing. Warming it makes the composition available on
// the first frame, and `disableAnimations` pins the controller to its last
// frame, so the badge is byte-stable.
//
// `confirm-loading` is the only cell that cannot settle: `SkeletonShimmerScope`
// drives `repeat(reverse: true)` forever. It uses `pumpBeforeTest: pumpOnce` +
// `settle: false`, exactly as `calendar_working_hours_golden_test.dart`'s
// LOADING cells do, so the shimmer is captured at a fixed phase.

import 'dart:async';

import 'package:alchemist/alchemist.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart' show AssetLottie;

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/booking/application/slot_picker_notifier.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_success_args.dart';
import 'package:beautica_mobile/features/booking/domain/create_appointment_request.dart';
import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart'
    show WalkInGuest;
import 'package:beautica_mobile/features/booking/domain/working_day.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Fixtures — deliberately the SAME values `slot_picker_test.dart` /
// `booking_confirm_test.dart` already use, so any drift between the widget
// tests and these baselines would itself be a bug.
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

const MasterService _kService2 = MasterService(
  id: 'svc-2',
  serviceDefId: 'def-2',
  name: 'Педикюр',
  durationMinutes: 60,
  priceMin: 400,
  priceDisplay: '400 ₴',
  category: 'NAILS',
);

/// The CREATE path's ordered visit selection (MO-3 books N services as ONE
/// visit). The RESCHEDULE path is single-service BY CONTRACT
/// (`booking_confirm_args.dart`: "[services] then holds exactly one element"),
/// so the two reschedule cells below carry [_kService] alone — that is the
/// production shape, not a fixture shortcut.
const List<MasterService> _kVisit = <MasterService>[_kService, _kService2];
const List<MasterService> _kSingle = <MasterService>[_kService];

/// The pinned "now". 09:00 UTC on Aug 10 2026 == 12:00 Kyiv (EEST, UTC+3), so
/// the calendar renders August 2026 with the 10th as "today".
// future-date-ok: fixed clock-override instant; the exact day is the fixture's identity, never now-relative.
final DateTime _kNow = DateTime.utc(2026, 8, 10, 9);

/// Three slot instants, one per Ранок/День/Вечір bucket. `_SlotsSection` buckets
/// on `toBeauticaTime(startAt).hour` (KYIV wall clock, never UTC — see
/// `slot_picker_screen.dart`'s `_bucketsFor` header), so in August these land at
/// 09:00 / 13:00 / 18:00 Kyiv respectively: hour < 12, 12..16, >= 17.
// future-date-ok: fixed twin of _kNow — 09:00 Kyiv on the same clock-override day.
final DateTime _kMorning = DateTime.utc(2026, 8, 10, 6);
// future-date-ok: fixed twin of _kNow — 13:00 Kyiv on the same clock-override day.
final DateTime _kAfternoon = DateTime.utc(2026, 8, 10, 10);
// future-date-ok: fixed twin of _kNow — 18:00 Kyiv on the same clock-override day.
final DateTime _kEvening = DateTime.utc(2026, 8, 10, 15);

/// The visit's summed duration — 90 + 60. Every window label on the confirm /
/// success recap is `startAt` → `startAt + this`.
const int _kVisitMinutes = 150;

BookingSlot _slot(DateTime startAt) => BookingSlot(
  startAt: startAt,
  endAt: startAt.add(const Duration(minutes: _kVisitMinutes)),
  available: true,
);

/// All three buckets populated, two chips each, so the golden pins the GROUP
/// layout (heading + wrap) and not merely "a chip rendered".
final List<BookingSlot> _kSlots = <BookingSlot>[
  _slot(_kMorning),
  _slot(_kMorning.add(const Duration(minutes: 30))),
  _slot(_kAfternoon),
  _slot(_kAfternoon.add(const Duration(minutes: 30))),
  _slot(_kEvening),
  _slot(_kEvening.add(const Duration(minutes: 30))),
];

/// A STABLE idempotency key — in production minted once by
/// `SlotTimeScreen._confirm`. Fixed here so the confirm cells never depend on
/// a UUID draw (it is not rendered, but a fixture that varies per run is a
/// latent golden flake).
const String _kIdemKey = '11111111-1111-4111-8111-111111111111';

BookingSlotPickerArgs _slotArgs() => const BookingSlotPickerArgs(
  masterId: 'master-1',
  master: _kMaster,
  services: _kVisit,
);

/// Phase 265 D6 — the routed walk-in chain's seed shape: [WalkInGuest] +
/// `hideMasterIdentity: true`. Mirrors `walk_in_service_step_screen.dart`'s
/// own `_onNext` construction.
const WalkInGuest _kWalkInGuest = WalkInGuest(
  name: 'Ірина',
  surname: 'Шевченко',
  phone: '+380501234567',
);

BookingSlotPickerArgs _slotArgsWalkIn() => const BookingSlotPickerArgs(
  masterId: 'master-1',
  master: _kMaster,
  services: _kVisit,
  guest: _kWalkInGuest,
  hideMasterIdentity: true,
);

BookingConfirmArgs _confirmArgs({String? rescheduleBookingId}) =>
    BookingConfirmArgs(
      masterId: _kMaster.id,
      master: _kMaster,
      services: rescheduleBookingId == null ? _kVisit : _kSingle,
      startAt: _kAfternoon,
      idempotencyKey: _kIdemKey,
      rescheduleBookingId: rescheduleBookingId,
    );

BookingConfirmArgs _confirmArgsWalkIn() => BookingConfirmArgs(
  masterId: _kMaster.id,
  master: _kMaster,
  services: _kVisit,
  startAt: _kAfternoon,
  idempotencyKey: _kIdemKey,
  guest: _kWalkInGuest,
  hideMasterIdentity: true,
);

BookingSuccessArgs _successArgs({required bool isReschedule}) =>
    BookingSuccessArgs(
      master: _kMaster,
      services: isReschedule ? _kSingle : _kVisit,
      startAt: _kAfternoon,
      isReschedule: isReschedule,
    );

BookingSuccessArgs _successArgsWalkIn() => BookingSuccessArgs(
  master: _kMaster,
  services: _kVisit,
  startAt: _kAfternoon,
  isWalkIn: true,
);

/// Audit-fix cycle 2 (FIX 1) — the SAME walk-in success seed as
/// [_successArgsWalkIn], plus the [WalkInGuest] the terminal done screen now
/// needs to render its restored guest-identity card. Kept as a SEPARATE
/// fixture (not an optional param folded into [_successArgsWalkIn]) so the
/// pre-existing `success-walkin` cell's construction is untouched byte-for-
/// byte and its six baselines cannot move.
BookingSuccessArgs _successArgsWalkInGuest() => BookingSuccessArgs(
  master: _kMaster,
  services: _kVisit,
  startAt: _kAfternoon,
  isWalkIn: true,
  guest: _kWalkInGuest,
);

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Answers the working-days window with "every requested day is working", or
/// throws [workingDaysError] when set.
///
/// The window is whatever `SlotDateScreen` asks for, which it derives from the
/// PINNED clock — so the fixture and the screen agree by construction, with no
/// second "now" anywhere (mobile-qa M15).
class _FakeSlotRepository implements SlotRepository {
  const _FakeSlotRepository({this.workingDaysError});

  final Object? workingDaysError;

  @override
  Future<List<WorkingDay>> getWorkingDays({
    required String masterId,
    required DateTime from,
    required DateTime to,
    List<String>? serviceIds,
    CancelToken? cancelToken,
  }) async {
    final Object? err = workingDaysError;
    // ASYNC throw, never a sync `thenThrow`-shaped one (mobile-qa M13): a
    // Dio-backed repository always fails asynchronously, and a sync throw
    // during a provider build short-circuits Riverpod's retry machinery
    // entirely. The failure below is DETERMINISTIC ([UnknownFailure]), so
    // `beauticaProviderRetry` stops it at attempt 1 either way and the cell
    // photographs a terminal `AsyncError` rather than a mid-retry frame — a
    // transient `NetworkFailure` here would instead park the cell in the
    // retry curve, which is not the state this baseline claims to pin.
    if (err != null) throw err;
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
  }) async => _kSlots;
}

/// Always fails `POST /appointments` — drives the `confirm-error` cell's real
/// CTA tap into `_SubmitErrorBanner`.
///
/// [ConflictFailure] (a 409) is deliberate: it is a DETERMINISTIC failure, so
/// nothing retries and the banner is terminal. `AppointmentSubmit.submitVisit`
/// resets its own state to `AsyncData(null)` and rethrows, so the CTA is left
/// interactive (never stuck on a spinner) — which is exactly the shipped
/// behaviour this baseline must capture.
class _FailingAppointmentRepository implements AppointmentRepository {
  const _FailingAppointmentRepository();

  @override
  Future<Appointment> createAppointment(CreateAppointmentRequest req) async {
    throw const ConflictFailure();
  }

  @override
  Future<Appointment> getAppointment(String id) => throw UnimplementedError();

  @override
  Future<Appointment> rescheduleAppointmentItem(
    String appointmentId,
    String bookingId,
    DateTime newStartAt,
  ) => throw UnimplementedError();

  @override
  Future<void> cancelAppointment(String id, {String? note}) =>
      throw UnimplementedError();

  @override
  Future<void> completeAppointment(String id) => throw UnimplementedError();

  @override
  Future<void> completeAppointmentService(
    String appointmentId,
    String bookingId,
  ) => throw UnimplementedError();

  @override
  Future<void> declineAppointment(String id, {String? comment}) =>
      throw UnimplementedError();

  @override
  Future<void> declineAppointmentService(
    String appointmentId,
    String bookingId, {
    String? comment,
  }) => throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Override sets — one per cell
// ---------------------------------------------------------------------------

List<Object> _clock() => <Object>[clockProvider.overrideWithValue(() => _kNow)];

List<Object> _slotDateOverrides({Object? workingDaysError}) => <Object>[
  ..._clock(),
  slotRepositoryProvider.overrideWith(
    (_) => _FakeSlotRepository(workingDaysError: workingDaysError),
  ),
];

/// Seeds the shared picker state the time screen reads. `selectedDate` must be
/// non-null or `SlotTimeScreen` post-frame-pops itself as a broken-flow edge
/// case (`slot_picker_screen.dart`'s `selectedDate == null` guard).
List<Object> _slotTimeOverrides({
  required List<BookingSlot> slots,
  BookingSlot? selectedSlot,
}) => <Object>[
  ..._clock(),
  slotPickerProvider.overrideWithValue(
    SlotPickerState(
      selectedDate: DateTime.utc(_kNow.year, _kNow.month, _kNow.day),
      selectedSlot: selectedSlot,
      slots: AsyncData<List<BookingSlot>>(slots),
    ),
  ),
];

List<Object> _confirmOverrides() => <Object>[
  ..._clock(),
  publicMasterProfileProvider(
    _kMaster.id,
  ).overrideWith((ref) => (_kMaster, _kVisit)),
  appointmentRepositoryProvider.overrideWith(
    (_) => const _FailingAppointmentRepository(),
  ),
];

/// The confirm screen's master read never resolves → `_LoadingBody`.
List<Object> _confirmLoadingOverrides() => <Object>[
  ..._clock(),
  publicMasterProfileProvider(
    _kMaster.id,
  ).overrideWith((ref) => Completer<PublicMasterProfileData>().future),
];

// ---------------------------------------------------------------------------
// Custom pumpWidget
// ---------------------------------------------------------------------------
//
// The shared `goldenPumpWidget` offers only a router-less `MaterialApp` with
// `home:`, and all four screens here resolve `GoRouter.of` (`BookingTopBar`'s
// back chevron, `MasterStrip.onTap` on confirm, the success screen's
// «На головну»), so — like `master_create_booking_wizard_golden_test.dart` —
// this file supplies its own `MaterialApp.router` pump.

PumpWidget _bookingPump({
  required double width,
  required List<Object> overrides,
  bool settle = true,
  bool warmLottie = false,
  Future<void> Function(WidgetTester tester)? drive,
}) {
  return (WidgetTester tester, Widget alchemistWidget) async {
    tester.view.physicalSize = Size(width, kGoldenHeight);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    if (warmLottie) {
      // See the file header: warms `sharedLottieCache` so the success badge's
      // composition is available on the first frame instead of racing the
      // `frameBuilder` placeholder.
      await AssetLottie('assets/lottie/success.json').load();
    }

    final GoRouter router = GoRouter(
      initialLocation: '/golden',
      routes: <RouteBase>[
        GoRoute(
          path: '/golden',
          builder: (BuildContext context, GoRouterState state) =>
              alchemistWidget,
        ),
        // Destinations the goldened screens can reach. None is navigated to by
        // any cell; they exist so `GoRouter` can resolve the paths those
        // screens name without throwing during route-table construction.
        GoRoute(
          path: RouteNames.clientHome,
          builder: (BuildContext context, GoRouterState state) =>
              const SizedBox.shrink(),
        ),
        GoRoute(
          path: RouteNames.bookingSuccess,
          builder: (BuildContext context, GoRouterState state) =>
              const SizedBox.shrink(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        retry: beauticaProviderRetry,
        // ignore: avoid_dynamic_calls
        overrides: overrides.cast(),
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          routerConfig: router,
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    );

    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(kLoadingPumpFrame);
    }

    if (drive != null) {
      await drive(tester);
      await tester.pumpAndSettle();
    }
  };
}

/// The `confirm-error` drive — the ONLY cell that interacts. Taps the real
/// «Записатись» CTA against [_FailingAppointmentRepository], which is the only
/// way to reach `_BookingConfirmScreenState._failure` (private `State`, no
/// provider seam).
Future<void> _driveSubmitFailure(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Cell matrix
// ---------------------------------------------------------------------------

typedef _Cell = ({
  String name,
  Widget Function() build,
  List<Object> overrides,
  bool settle,
  bool warmLottie,
  Future<void> Function(WidgetTester tester)? drive,
});

List<_Cell> _cells() => <_Cell>[
  (
    name: 'slot-date',
    build: () => SlotDateScreen(args: _slotArgs()),
    overrides: _slotDateOverrides(),
    settle: true,
    warmLottie: false,
    drive: null,
  ),
  (
    name: 'slot-date-error',
    build: () => SlotDateScreen(args: _slotArgs()),
    overrides: _slotDateOverrides(workingDaysError: const UnknownFailure()),
    settle: true,
    warmLottie: false,
    drive: null,
  ),
  (
    name: 'slot-time',
    build: () => SlotTimeScreen(args: _slotArgs()),
    overrides: _slotTimeOverrides(
      slots: _kSlots,
      selectedSlot: _slot(_kAfternoon),
    ),
    settle: true,
    warmLottie: false,
    drive: null,
  ),
  (
    name: 'slot-time-empty',
    build: () => SlotTimeScreen(args: _slotArgs()),
    overrides: _slotTimeOverrides(slots: const <BookingSlot>[]),
    settle: true,
    warmLottie: false,
    drive: null,
  ),
  (
    name: 'confirm',
    build: () => BookingConfirmScreen(args: _confirmArgs()),
    overrides: _confirmOverrides(),
    settle: true,
    warmLottie: false,
    drive: null,
  ),
  (
    name: 'confirm-reschedule',
    build: () =>
        BookingConfirmScreen(args: _confirmArgs(rescheduleBookingId: 'b-1')),
    overrides: _confirmOverrides(),
    settle: true,
    warmLottie: false,
    drive: null,
  ),
  (
    name: 'confirm-error',
    build: () => BookingConfirmScreen(args: _confirmArgs()),
    overrides: _confirmOverrides(),
    settle: true,
    warmLottie: false,
    drive: _driveSubmitFailure,
  ),
  (
    name: 'confirm-loading',
    build: () => BookingConfirmScreen(args: _confirmArgs()),
    overrides: _confirmLoadingOverrides(),
    settle: false,
    warmLottie: false,
    drive: null,
  ),
  (
    name: 'success',
    build: () => BookingSuccessScreen(args: _successArgs(isReschedule: false)),
    overrides: _clock(),
    settle: true,
    warmLottie: true,
    drive: null,
  ),
  (
    name: 'success-reschedule',
    build: () => BookingSuccessScreen(args: _successArgs(isReschedule: true)),
    overrides: _clock(),
    settle: true,
    warmLottie: true,
    drive: null,
  ),
  // ── Phase 265 D6 — the routed walk-in chain's four cells (deferred by
  // Phase 260 D6 until the chain went live in Phase 264). Existing 60 cells
  // above are byte-identical and untouched — these four are ADDITIVE.
  (
    name: 'slot-date-walkin',
    build: () => SlotDateScreen(args: _slotArgsWalkIn()),
    overrides: _slotDateOverrides(),
    settle: true,
    warmLottie: false,
    drive: null,
  ),
  (
    name: 'slot-time-walkin',
    build: () => SlotTimeScreen(args: _slotArgsWalkIn()),
    overrides: _slotTimeOverrides(
      slots: _kSlots,
      selectedSlot: _slot(_kAfternoon),
    ),
    settle: true,
    warmLottie: false,
    drive: null,
  ),
  (
    name: 'confirm-walkin',
    build: () => BookingConfirmScreen(args: _confirmArgsWalkIn()),
    overrides: _confirmOverrides(),
    settle: true,
    warmLottie: false,
    drive: null,
  ),
  (
    name: 'success-walkin',
    build: () => BookingSuccessScreen(args: _successArgsWalkIn()),
    overrides: _clock(),
    settle: true,
    warmLottie: true,
    drive: null,
  ),
  // Audit-fix cycle 2 (FIX 1) — ADDITIVE 15th cell: the walk-in done screen
  // WITH a guest, pinning the restored guest-identity card. `success-walkin`
  // above is untouched (still seeded with no `guest`, so it keeps rendering
  // with no card) — its six baselines are byte-identical before/after this
  // cell's addition.
  (
    name: 'success-walkin-guest',
    build: () => BookingSuccessScreen(args: _successArgsWalkInGuest()),
    overrides: _clock(),
    settle: true,
    warmLottie: true,
    drive: null,
  ),
];

// ---------------------------------------------------------------------------
// Goldens
// ---------------------------------------------------------------------------

void main() {
  for (final cell in _cells()) {
    for (final width in kGoldenWidths) {
      for (final scale in kGoldenTextScales) {
        final String suffix = widthScaleSuffix(width, scale);
        final String fileSlug = cell.name.replaceAll('-', '_');

        goldenTest(
          'booking_slot_flow ${cell.name} ${width.toInt()}dp text-${scale}x',
          fileName: 'booking_slot_flow_${fileSlug}_$suffix',
          constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
          textScaleFactor: scale,
          // `pumpOnce` only for the non-settling shimmer cell — alchemist's
          // default `onlyPumpAndSettle` would time out on
          // `SkeletonShimmerScope`'s perpetual `repeat(reverse: true)`.
          pumpBeforeTest: cell.settle ? onlyPumpAndSettle : pumpOnce,
          pumpWidget: _bookingPump(
            width: width,
            overrides: cell.overrides,
            settle: cell.settle,
            warmLottie: cell.warmLottie,
            drive: cell.drive,
          ),
          builder: cell.build,
        );
      }
    }
  }
}
