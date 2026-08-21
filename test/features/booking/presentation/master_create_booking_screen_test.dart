// Phase 247 (part 2) — Widget tests for MasterCreateBookingScreen.
//
// Covers the acceptance criteria from the phase brief:
//   1. Each step's advance rule / disabled state (client Next; service tap
//      auto-advance; dateTime auto-advance on slot pick).
//   2. A malformed phone blocks Next with a field error and never reaches
//      the repository.
//   3. An empty slot list renders the designed empty state, not a spinner.
//   4. A submit failure (409) keeps the user on `confirm` and does NOT
//      advance to `done`.
//   5. `done` blocks the back gesture (PopScope(canPop: false)) and hides
//      the header + step indicator.
//
// Strategy mirrors `booking_confirm_test.dart` / `master_schedule_page_test
// .dart`: a test-local GoRouter (needed because the client step's back
// button and the done step's «Готово» both call `context.pop()`), hand-
// written fakes for `SlotRepository` / `BookingRepository` (no mocktail —
// matches this feature's existing convention), and simple `AsyncNotifier`
// subclass overrides for `masterProfileProvider` / `servicesListProvider`
// (both `keepAlive: true`, so a plain function override cannot target them —
// mirrors `services_list_pre_expand_test.dart`'s `_StubServicesList`).

import 'dart:async';

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_partition.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart';
import 'package:beautica_mobile/features/booking/domain/working_day.dart';
import 'package:beautica_mobile/features/booking/presentation/master_create_booking_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_top_bar.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_category_list.dart'
    show CategorySection, ServiceCard;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart'
    show formatSlotTimeRange;
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:dio/dio.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_wizard_steps.dart'
    show ServiceStep;
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const Master _kMaster = Master(
  id: 'master-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  reviewCount: 0,
  type: MasterType.independentMaster,
);

const MasterService _kService = MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Манікюр',
  durationMinutes: 60,
  priceMin: 500,
  priceDisplay: '500 ₴',
  category: 'NAILS',
);

// PHASE 253 — two more single-category fixture services, for the multi-select
// tests below (three services marked, order preserved, cap enforced).
const MasterService _kService2 = MasterService(
  id: 'svc-2',
  serviceDefId: 'def-2',
  name: 'Педикюр',
  durationMinutes: 45,
  priceMin: 400,
  priceDisplay: '400 ₴',
  category: 'NAILS',
);
const MasterService _kService3 = MasterService(
  id: 'svc-3',
  serviceDefId: 'def-3',
  name: 'Покриття гель-лак',
  durationMinutes: 30,
  priceMin: 300,
  priceDisplay: '300 ₴',
  category: 'NAILS',
);

/// [n] fixture services in ONE category, for the `maxServicesPerVisit` cap
/// test — mirrors `service_selector_sheet_test.dart`'s `_manyServices`.
List<MasterService> _manyServices(int n) => <MasterService>[
  for (int i = 0; i < n; i++)
    MasterService(
      id: 'svc-cap-$i',
      serviceDefId: 'def-cap-$i',
      name: 'Послуга $i',
      durationMinutes: 30,
      priceMin: 100,
      priceDisplay: '100 ₴',
      category: 'NAILS',
    ),
];

// "Today" pinned to a Kyiv mid-day instant — no cross-midnight ambiguity —
// mirrors `master_schedule_page_test.dart`'s Kyiv-anchoring pattern.
// future-date-ok: fixed clock-override instant; the exact day is the fixture's identity, never now-relative.
final DateTime _kNow = DateTime.utc(2026, 8, 10, 9); // 12:00 Kyiv, Aug 10.
// future-date-ok: fixed twin of _kNow — the same clock-override day, see above.
final DateTime _kSlotStart = DateTime.utc(2026, 8, 10, 10); // 13:00 Kyiv.
final BookingSlot _kSlot = BookingSlot(
  startAt: _kSlotStart,
  endAt: _kSlotStart.add(const Duration(minutes: 60)),
  available: true,
);
// A SECOND bookable slot on the same fixture day — exists so a test can pick
// one slot and then RE-pick another (audit-fix cycle 1, FINDING 1). Same
// afternoon bucket as [_kSlot] (13:00 / 15:00 Kyiv, both `< 17`), so both
// chips render in one group and neither tap needs a scroll.
// future-date-ok: fixed twin of _kNow — the same clock-override day, see above.
final DateTime _kSlotLateStart = DateTime.utc(2026, 8, 10, 12); // 15:00 Kyiv.
final BookingSlot _kSlotLate = BookingSlot(
  startAt: _kSlotLateStart,
  endAt: _kSlotLateStart.add(const Duration(minutes: 60)),
  available: true,
);

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeMasterProfile extends MasterProfile {
  @override
  Future<Master> build() async => _kMaster;
}

/// mobile-qa gap fix — the wizard's OWN top-level `masterProfileProvider`
/// error state (`master-create-booking-master-error`, with its retry
/// button) had zero coverage: every other test in this file overrides
/// `masterProfileProvider` with `_FakeMasterProfile` (always succeeds), so
/// the `masterAsync.when(error: ...)` branch in `MasterCreateBookingScreen
/// .build` was never reached. Mirrors `master_profile_screen_test.dart`'s
/// `retry — screen wiring` group: a fixed `AsyncError` override, not a
/// stateful fail-then-succeed notifier, so the assertions are exact.
class _FailingMasterProfile extends MasterProfile {
  @override
  Future<Master> build() async => throw const NetworkFailure();
}

/// A `masterProfileProvider` override whose `build()` never resolves —
/// isolates the LOADING branch (`master-create-booking-loading`) from the
/// error/data branches. Deliberately never completes; the test pumps a
/// bounded number of frames rather than `pumpAndSettle`.
class _ForeverLoadingMasterProfile extends MasterProfile {
  @override
  Future<Master> build() => Completer<Master>().future;
}

class _FakeServicesList extends ServicesList {
  _FakeServicesList([this._services = const <MasterService>[_kService]]);

  final List<MasterService> _services;

  @override
  Future<List<MasterService>> build() async => _services;
}

/// mobile-qa gap fix — `_ServiceStep`'s OWN loading/error states
/// (`master-create-booking-service-loading` /
/// `master-create-booking-service-error`, distinct from the wizard's
/// top-level `masterProfileProvider` states) had zero coverage. Mirrors
/// `_ForeverLoadingMasterProfile` / `_FailingMasterProfile` below, one layer
/// down the provider chain.
class _ForeverLoadingServicesList extends ServicesList {
  @override
  Future<List<MasterService>> build() =>
      Completer<List<MasterService>>().future;
}

class _FailingServicesList extends ServicesList {
  @override
  Future<List<MasterService>> build() async => throw const NetworkFailure();
}

/// Counts `acquire`/`release` so a test can prove the wizard actually touches
/// the app-wide screen-protection manager.
///
/// mobile-security finding (2026-08-20): NOTHING asserted that
/// `MasterCreateBookingScreen.initState` acquires it, so deleting that line
/// left the whole suite green — while this wizard is a HEAVY third-party PII
/// surface (a walk-in guest's full name and phone number, typed by the master
/// and re-displayed on the confirm and done steps). The task-switcher snapshot
/// of that data is exactly what the retained app-switcher blur exists to stop
/// here. (It is NOT a screenshot or screen-recording block — that was removed
/// app-wide on 2026-08-20 by product decision; see the header of
/// `lib/core/security/screen_protection.dart`. The `reason:` strings on this
/// group's expects still say FLAG_SECURE and are stale for the same reason,
/// left untouched because they are assertion arguments, not comments.)
class _CountingScreenProtection extends ScreenProtectionManager {
  int acquires = 0;
  int releases = 0;

  @override
  void acquire() => acquires++;

  @override
  void release() => releases++;
}

/// Reports every requested date as working (isolating the assertions from
/// the calendar's own past-day gate) and returns [slotsToReturn] verbatim —
/// mirrors `master_schedule_page_test.dart`'s
/// `_AlwaysWorkingCountingSlotRepository`.
class _FakeSlotRepository implements SlotRepository {
  _FakeSlotRepository({this.slotsToReturn = const <BookingSlot>[]});

  List<BookingSlot> slotsToReturn;
  int getMasterSlotsCallCount = 0;

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
  }) async {
    getMasterSlotsCallCount++;
    return slotsToReturn;
  }
}

/// Records every [createMasterBooking] call and either returns a fixture
/// [Booking] or throws [errorToThrow] — mirrors `booking_confirm_test.dart`'s
/// `_FakeAppointmentRepository`.
///
/// PHASE 256 — optional [hold]: when set, [createMasterBooking] awaits it
/// before resolving, so a test can keep the "network call" open long enough
/// to observe the CTA's disabled state mid-flight (`should_disableCta_when
/// _submitInFlight`). `null` (every pre-256 call site) resolves immediately,
/// unchanged.
class _FakeBookingRepository implements BookingRepository {
  _FakeBookingRepository({this.errorToThrow, this.hold, this.responseOverride});

  Object? errorToThrow;
  final Completer<void>? hold;

  /// PHASE 256 — optional full-response override, for the
  /// `should_renderServerVisitWindow_when_multiServiceVisitCreated` test:
  /// the default fixture below hardcodes a ONE-service response shaped
  /// around [_kService] regardless of what [request] actually asked for,
  /// which cannot prove "the done step renders the SERVER's window, not
  /// local state" — a test needs a response whose `endAt`/`items` genuinely
  /// DIFFER from `request.startsAt + Σ local durations`. `null` (every
  /// pre-256 call site) keeps the default fixture unchanged.
  final Appointment Function(
    String masterId,
    CreateMasterBookingRequest request,
  )?
  responseOverride;

  final List<(String, CreateMasterBookingRequest)> calls =
      <(String, CreateMasterBookingRequest)>[];

  @override
  Future<Appointment> createMasterBooking(
    String masterId,
    CreateMasterBookingRequest request,
  ) async {
    calls.add((masterId, request));
    final Completer<void>? h = hold;
    if (h != null) await h.future;
    final Object? err = errorToThrow;
    if (err != null) throw err;
    final Appointment Function(String, CreateMasterBookingRequest)? override =
        responseOverride;
    if (override != null) return override(masterId, request);
    return Appointment(
      id: 'appt-1',
      status: BookingStatus.confirmed,
      masterId: masterId,
      masterFirstName: _kMaster.firstName,
      masterLastName: _kMaster.lastName,
      masterType: 'INDEPENDENT_MASTER',
      startAt: request.startsAt,
      endAt: request.startsAt.add(Duration(minutes: _kService.durationMinutes)),
      totalDurationMinutes: _kService.durationMinutes,
      totalPrice: _kService.priceMin,
      items: <AppointmentItem>[
        AppointmentItem(
          bookingId: 'booking-1',
          masterServiceId: request.masterServiceIds.first,
          serviceName: _kService.name,
          startAt: request.startsAt,
          endAt: request.startsAt.add(
            Duration(minutes: _kService.durationMinutes),
          ),
          durationMinutes: _kService.durationMinutes,
          price: _kService.priceMin,
        ),
      ],
    );
  }

  @override
  Future<Booking> createBooking(CreateBookingRequest req) =>
      throw UnimplementedError();

  @override
  Future<List<DateTime>> getMyBookedDays({
    required DateTime from,
    required DateTime to,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<Booking> getBookingById(String id) => throw UnimplementedError();

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required Iterable<BookingStatus> statuses,
    BookingSort? sort,
    required int page,
    int size = kBookingsPageSize,
    Iterable<String>? serviceIds,
    DateTime? from,
    DateTime? to,
    BookingPartition? partition,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelBooking(String id, {String? reason}) =>
      throw UnimplementedError();

  @override
  Future<void> declineBooking(String id, {String? comment}) =>
      throw UnimplementedError();

  @override
  Future<void> completeBooking(String id) => throw UnimplementedError();

  @override
  Future<Booking> rescheduleBooking(String id, DateTime newStartAt) =>
      throw UnimplementedError();

  @override
  Future<void> createReview({
    required String bookingId,
    required int rating,
    String? comment,
  }) => throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Router + pump helper
// ---------------------------------------------------------------------------

GoRouter _router() => GoRouter(
  initialLocation: '/root',
  routes: <RouteBase>[
    GoRoute(
      path: '/root',
      builder: (context, state) => const SizedBox.shrink(),
    ),
    GoRoute(
      path: RouteNames.masterBookingNew,
      builder: (context, state) => const MasterCreateBookingScreen(),
    ),
  ],
);

Future<GoRouter> _pump(
  WidgetTester tester, {
  List<MasterService> services = const <MasterService>[_kService],
  _FakeSlotRepository? slotRepository,
  _FakeBookingRepository? bookingRepository,
  MasterProfile Function() masterProfileOverride = _FakeMasterProfile.new,
  ServicesList Function()? servicesListOverride,
  ScreenProtectionManager? screenProtection,
}) async {
  final GoRouter router = _router();
  await tester.pumpRoutedApp(
    router,
    overrides: <Object>[
      masterProfileProvider.overrideWith(masterProfileOverride),
      servicesListProvider.overrideWith(
        servicesListOverride ?? () => _FakeServicesList(services),
      ),
      approvedCategoriesProvider.overrideWith(
        (ref) async => const <ServiceCategoryOption>[],
      ),
      slotRepositoryProvider.overrideWith(
        (_) => slotRepository ?? _FakeSlotRepository(),
      ),
      bookingRepositoryProvider.overrideWith(
        (_) => bookingRepository ?? _FakeBookingRepository(),
      ),
      clockProvider.overrideWithValue(() => _kNow),
      // Only overridden when a test asks for it: the default (real, no-op on
      // the test platform channel) manager keeps every other test in this
      // file exercising the production wiring.
      if (screenProtection != null)
        screenProtectionProvider.overrideWithValue(screenProtection),
    ],
  );
  unawaited(router.push(RouteNames.masterBookingNew));
  await tester.pumpAndSettle();
  return router;
}

/// The walk-in guest [_fillClientStepAndAdvance] types in. Named constants
/// rather than inline literals so the done-step guest-card assertions can
/// check the rendered values against the SAME source the form was filled
/// from — and so those assertions interpolate instead of hard-coding a
/// Cyrillic literal (`scripts/forbid_cyrillic_finder.sh`).
const String _kGuestFirstName = 'Марина';
const String _kGuestLastName = 'Кравчук';
const String _kGuestPhone = '0501234567';

/// Fills the client step with valid data and taps «Далі» — the shared first
/// leg of every test that needs to reach a later step.
Future<void> _fillClientStepAndAdvance(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('master-create-booking-first-name')),
    _kGuestFirstName,
  );
  await tester.enterText(
    find.byKey(const Key('master-create-booking-last-name')),
    _kGuestLastName,
  );
  await tester.enterText(
    find.byKey(const Key('master-create-booking-phone')),
    _kGuestPhone,
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('master-create-booking-client-next')));
  await tester.pumpAndSettle();
}

/// Taps the (only) fixture service card, then the pinned «Далі» footer.
///
/// SELECTION NO LONGER NAVIGATES (2026-08-20 UX fix): the card tap only marks
/// the service selected — the footer is what moves to `dateTime`. Both halves
/// live here so every caller exercises the real two-step interaction.
///
/// PHASE 253 — the service step's footer is now the shared
/// [BookingSummaryBar] (key `booking-summary-cta`), NOT the bespoke
/// `master-create-booking-service-next` footer this wizard used before
/// multi-select — see `master_create_booking_screen.dart`'s widened
/// `_buildBottomBar`.
Future<void> _pickService(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('mcb_service_card_svc-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('booking-summary-cta')));
  await tester.pumpAndSettle();
}

/// Picks Aug 10 (== [_kNow]'s Kyiv "today") on the calendar, then presses the
/// pinned «Далі» footer to move to the time sub-phase — see [_pickService].
Future<void> _pickDate(WidgetTester tester) async {
  await tester.tapCalendarDay(10);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('master-create-booking-date-next')));
  await tester.pumpAndSettle();
}

/// Taps the [_kSlot] chip, then the pinned «Далі» footer — see [_pickService].
Future<void> _pickSlot(WidgetTester tester) async {
  await tester.tap(
    find.byKey(Key('salon-slot-chip-${_kSlot.startAt.toIso8601String()}')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('master-create-booking-time-next')));
  await tester.pumpAndSettle();
}

/// Drives the whole flow from a freshly-pumped screen up to (and including)
/// landing on `confirm`.
Future<void> _driveToConfirm(WidgetTester tester) async {
  await _fillClientStepAndAdvance(tester);
  await _pickService(tester);
  await _pickDate(tester);
  await _pickSlot(tester);
}

void main() {
  group('MasterCreateBookingScreen — client step', () {
    testWidgets(
      '«Далі» is disabled until first name, last name and a valid phone are '
      'all present',
      (tester) async {
        await _pump(tester);

        NeumorphicButton nextButton() => tester.widget<NeumorphicButton>(
          find.byKey(const Key('master-create-booking-client-next')),
        );

        expect(nextButton().onPressed, isNull);

        await tester.enterText(
          find.byKey(const Key('master-create-booking-first-name')),
          'Марина',
        );
        await tester.enterText(
          find.byKey(const Key('master-create-booking-last-name')),
          'Кравчук',
        );
        await tester.pump();
        expect(nextButton().onPressed, isNull, reason: 'phone is still empty');

        await tester.enterText(
          find.byKey(const Key('master-create-booking-phone')),
          '0501234567',
        );
        await tester.pump();
        expect(nextButton().onPressed, isNotNull);
      },
    );

    testWidgets('a malformed phone shows a field error, blocks «Далі», and the '
        'booking repository is never called', (tester) async {
      final fakeBookings = _FakeBookingRepository();
      await _pump(tester, bookingRepository: fakeBookings);

      await tester.enterText(
        find.byKey(const Key('master-create-booking-first-name')),
        'Марина',
      );
      await tester.enterText(
        find.byKey(const Key('master-create-booking-last-name')),
        'Кравчук',
      );
      // Too short to resolve to 9 Ukrainian subscriber digits.
      await tester.enterText(
        find.byKey(const Key('master-create-booking-phone')),
        '12345',
      );
      await tester.pump();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(MasterCreateBookingScreen)),
      );
      final NeumorphicTextField phoneField = tester.widget<NeumorphicTextField>(
        find.byKey(const Key('master-create-booking-phone')),
      );
      expect(phoneField.errorText, l10n.errPhoneInvalid);

      final NeumorphicButton nextButton = tester.widget<NeumorphicButton>(
        find.byKey(const Key('master-create-booking-client-next')),
      );
      expect(nextButton.onPressed, isNull);

      // Still on the client step — never reached the service picker.
      expect(
        find.byKey(const Key('master-create-booking-first-name')),
        findsOneWidget,
      );
      expect(fakeBookings.calls, isEmpty);
    });

    testWidgets('the header back-chevron pops the whole wizard', (
      tester,
    ) async {
      final GoRouter router = await _pump(tester);
      await tester.tap(find.byKey(const Key('master-create-booking-back')));
      await tester.pumpAndSettle();

      expect(find.byType(MasterCreateBookingScreen), findsNothing);
      expect(
        router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
        '/root',
      );
    });
  });

  // mobile-qa gap fix — the wizard's own top-level master-profile
  // loading/error states (`masterAsync.when(...)` in
  // `MasterCreateBookingScreen.build`) had NO coverage: every other test
  // overrides `masterProfileProvider` with `_FakeMasterProfile`, which
  // resolves immediately, so the `loading` and `error` branches were dead
  // code as far as this suite could tell.
  group('MasterCreateBookingScreen — master-profile loading/error', () {
    testWidgets('renders the spinner while masterProfileProvider is loading', (
      tester,
    ) async {
      final router = _router();
      // A `Completer`-backed override that never resolves during this test —
      // pumps exactly one frame (never `pumpAndSettle`, which would hang
      // waiting on the unresolved Future) and asserts the loading key.
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          masterProfileProvider.overrideWith(_ForeverLoadingMasterProfile.new),
          servicesListProvider.overrideWith(_FakeServicesList.new),
          approvedCategoriesProvider.overrideWith(
            (ref) async => const <ServiceCategoryOption>[],
          ),
          slotRepositoryProvider.overrideWith((_) => _FakeSlotRepository()),
          bookingRepositoryProvider.overrideWith(
            (_) => _FakeBookingRepository(),
          ),
          clockProvider.overrideWithValue(() => _kNow),
        ],
      );
      unawaited(router.push(RouteNames.masterBookingNew));
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('master-create-booking-loading')),
        findsOneWidget,
      );
      expect(find.byType(ErrorState), findsNothing);
    });

    testWidgets(
      'renders ErrorState with a working retry when masterProfileProvider '
      'fails, instead of a blank/crashed screen',
      (tester) async {
        await _pump(tester, masterProfileOverride: _FailingMasterProfile.new);

        expect(
          find.byKey(const Key('master-create-booking-master-error')),
          findsOneWidget,
        );
        final retryBtn = find.byKey(const Key('error_state_retry_button'));
        expect(retryBtn, findsOneWidget);

        // Tapping retry must not throw (proves the `ref.invalidate
        // (masterProfileProvider)` wiring compiles and runs) — mirrors
        // `master_profile_screen_test.dart`'s `retry — screen wiring` group.
        await tester.tap(retryBtn);
        await tester.pumpAndSettle();

        // The override still throws on rebuild, so the same error banner is
        // expected back — the assertion is that this DIDN'T crash, and the
        // client-step form never appeared underneath a broken error state.
        expect(find.byType(ErrorState), findsOneWidget);
        expect(
          find.byKey(const Key('master-create-booking-first-name')),
          findsNothing,
        );
      },
    );
  });

  // mobile-qa gap fix — `_ServiceStep`'s own `asyncServices.when(...)`
  // loading/error branches (one provider layer below masterProfileProvider)
  // had zero coverage, same gap as the group above but for
  // `servicesListProvider`.
  group('MasterCreateBookingScreen — service step loading/error', () {
    testWidgets('renders the spinner while servicesListProvider is loading', (
      tester,
    ) async {
      // NOT `_fillClientStepAndAdvance` — its `pumpAndSettle` never returns
      // once the service step's CircularProgressIndicator starts its
      // perpetual animation (mirrors the master-profile loading test above,
      // and `master_archive_screen_test.dart`'s identical note on
      // `BookingsSkeleton`). Bounded `pump()` calls instead.
      await _pump(
        tester,
        servicesListOverride: _ForeverLoadingServicesList.new,
      );
      await tester.enterText(
        find.byKey(const Key('master-create-booking-first-name')),
        'Марина',
      );
      await tester.enterText(
        find.byKey(const Key('master-create-booking-last-name')),
        'Кравчук',
      );
      await tester.enterText(
        find.byKey(const Key('master-create-booking-phone')),
        '0501234567',
      );
      await tester.pump();
      // The loading key only exists once `_step` flips to `service` inside
      // the 220 ms `AnimatedSwitcher` cross-fade — `pumpAndSettle` can't be
      // used here (the spinner's `CircularProgressIndicator` animates
      // forever), so pump-until-condition waits exactly as long as the
      // cross-fade takes instead of guessing a fixed duration.
      expect(
        find.byKey(const Key('master-create-booking-service-loading')),
        findsNothing,
        reason:
            'sanity check — the loading key must not exist before the '
            'tap, otherwise pumpUntilFound below would gate nothing',
      );
      await tester.tap(
        find.byKey(const Key('master-create-booking-client-next')),
      );
      await tester.pumpUntilFound(
        find.byKey(const Key('master-create-booking-service-loading')),
      );

      expect(
        find.byKey(const Key('master-create-booking-service-loading')),
        findsOneWidget,
      );
      expect(find.byType(ErrorState), findsNothing);
    });

    testWidgets(
      'renders ErrorState with a working retry when servicesListProvider '
      'fails, instead of a blank/crashed picker',
      (tester) async {
        await _pump(tester, servicesListOverride: _FailingServicesList.new);
        await _fillClientStepAndAdvance(tester);

        expect(
          find.byKey(const Key('master-create-booking-service-error')),
          findsOneWidget,
        );
        final retryBtn = find.byKey(const Key('error_state_retry_button'));
        expect(retryBtn, findsOneWidget);

        // Tapping retry must not throw (`ref.invalidate(servicesListProvider)`
        // wiring).
        await tester.tap(retryBtn);
        await tester.pumpAndSettle();

        expect(find.byType(ErrorState), findsOneWidget);
        expect(find.byKey(const Key('mcb_service_card_svc-1')), findsNothing);
      },
    );
  });

  group('MasterCreateBookingScreen — service step', () {
    testWidgets('tapping a service SELECTS it without navigating; only «Далі» '
        'advances to dateTime', (tester) async {
      await _pump(tester);
      await _fillClientStepAndAdvance(tester);

      expect(find.byKey(const Key('mcb_service_card_svc-1')), findsOneWidget);

      // PHASE 253 — the CTA is now the shared BookingSummaryBar, dead until
      // something is selected (D5 of the phase doc).
      final Finder next = find.byKey(const Key('booking-summary-cta'));
      expect(next, findsOneWidget);
      expect(tester.widget<NeumorphicButton>(next).onPressed, isNull);

      await tester.tap(find.byKey(const Key('mcb_service_card_svc-1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('booking-month-calendar')),
        findsNothing,
        reason: 'a service tap must SELECT, never navigate',
      );
      expect(
        tester
            .widget<ServiceCard>(
              find.byKey(const Key('mcb_service_card_svc-1')),
            )
            .selected,
        isTrue,
        reason: 'the tapped card must render its selected state',
      );
      expect(tester.widget<NeumorphicButton>(next).onPressed, isNotNull);

      await tester.tap(next);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('booking-month-calendar')),
        findsOneWidget,
        reason: '«Далі» is what lands on the dateTime step',
      );
    });

    testWidgets(
      'PHASE 253 — tapping three services marks three cards; tapping one '
      'again unmarks it; the CTA is disabled at zero selections',
      (tester) async {
        await _pump(
          tester,
          services: const <MasterService>[_kService, _kService2, _kService3],
        );
        await _fillClientStepAndAdvance(tester);

        final Finder next = find.byKey(const Key('booking-summary-cta'));
        expect(tester.widget<NeumorphicButton>(next).onPressed, isNull);

        for (final String id in <String>['svc-1', 'svc-2', 'svc-3']) {
          await tester.tap(find.byKey(Key('mcb_service_card_$id')));
          await tester.pump();
        }

        for (final String id in <String>['svc-1', 'svc-2', 'svc-3']) {
          expect(
            tester
                .widget<ServiceCard>(find.byKey(Key('mcb_service_card_$id')))
                .selected,
            isTrue,
            reason: '$id must render selected after being tapped',
          );
        }
        expect(tester.widget<NeumorphicButton>(next).onPressed, isNotNull);

        // Untap the middle one — it alone must go back to unselected, and
        // the other two must stay selected.
        await tester.tap(find.byKey(const Key('mcb_service_card_svc-2')));
        await tester.pump();

        expect(
          tester
              .widget<ServiceCard>(
                find.byKey(const Key('mcb_service_card_svc-1')),
              )
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<ServiceCard>(
                find.byKey(const Key('mcb_service_card_svc-2')),
              )
              .selected,
          isFalse,
        );
        expect(
          tester
              .widget<ServiceCard>(
                find.byKey(const Key('mcb_service_card_svc-3')),
              )
              .selected,
          isTrue,
        );

        // Untap the remaining two — back to zero, CTA disabled again.
        await tester.tap(find.byKey(const Key('mcb_service_card_svc-1')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('mcb_service_card_svc-3')));
        await tester.pump();

        expect(tester.widget<NeumorphicButton>(next).onPressed, isNull);
      },
    );

    testWidgets(
      'PHASE 253 — the visit-selection cap: an 11th add is refused with a '
      'friendly VelvetSnack and the selection stays at maxServicesPerVisit',
      (tester) async {
        // A tall viewport so all 11 fixture cards (one shared category) are
        // laid out and tappable without scrolling — mirrors
        // `service_selector_sheet_test.dart`'s own cap test.
        tester.view.physicalSize = const Size(800, 8000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final List<MasterService> eleven = _manyServices(11);
        await _pump(tester, services: eleven);
        await _fillClientStepAndAdvance(tester);

        for (int i = 0; i < 11; i++) {
          await tester.tap(find.byKey(Key('mcb_service_card_svc-cap-$i')));
          await tester.pump();
        }

        final l10n = AppLocalizations.of(
          tester.element(find.byType(MasterCreateBookingScreen)),
        );
        expectVelvetSnack(
          l10n.bookingMaxServicesReached(maxServicesPerVisit),
          variant: VelvetSnackVariant.warning,
        );
        await pumpPastVelvetSnack(tester);

        expect(
          tester
              .widget<ServiceCard>(
                find.byKey(const Key('mcb_service_card_svc-cap-10')),
              )
              .selected,
          isFalse,
          reason: 'the 11th tap must never mark its own card selected',
        );

        int selectedCount = 0;
        for (int i = 0; i < 11; i++) {
          if (tester
              .widget<ServiceCard>(
                find.byKey(Key('mcb_service_card_svc-cap-$i')),
              )
              .selected) {
            selectedCount++;
          }
        }
        expect(selectedCount, maxServicesPerVisit);
      },
    );

    testWidgets(
      'PHASE 253 — de-selecting still works while at the cap (the guard only '
      'fires on an ADD)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 8000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final List<MasterService> eleven = _manyServices(11);
        await _pump(tester, services: eleven);
        await _fillClientStepAndAdvance(tester);

        for (int i = 0; i < 10; i++) {
          await tester.tap(find.byKey(Key('mcb_service_card_svc-cap-$i')));
          await tester.pump();
        }
        // At the cap — de-selecting one of the ten must succeed with no
        // snack at all.
        await tester.tap(find.byKey(const Key('mcb_service_card_svc-cap-0')));
        await tester.pump();

        expect(
          tester
              .widget<ServiceCard>(
                find.byKey(const Key('mcb_service_card_svc-cap-0')),
              )
              .selected,
          isFalse,
          reason: 'de-selecting at the cap must succeed',
        );
        expect(find.byType(VelvetSnack), findsNothing);

        // And re-adding it now succeeds too (back under the cap).
        await tester.tap(find.byKey(const Key('mcb_service_card_svc-cap-0')));
        await tester.pump();
        expect(
          tester
              .widget<ServiceCard>(
                find.byKey(const Key('mcb_service_card_svc-cap-0')),
              )
              .selected,
          isTrue,
        );
      },
    );

    testWidgets(
      'PHASE 253 — selection order is TAP order, not catalogue order, and '
      'survives into the BookingSummaryBar itemized shelf',
      (tester) async {
        await _pump(
          tester,
          services: const <MasterService>[_kService, _kService2, _kService3],
        );
        await _fillClientStepAndAdvance(tester);

        // Tap OUT of catalogue order: svc-3, then svc-1, then svc-2.
        // Catalogue order (by fixture list) is svc-1, svc-2, svc-3 — a
        // Set-derived or catalogue-derived order would put svc-1 first.
        for (final String id in <String>['svc-3', 'svc-1', 'svc-2']) {
          await tester.tap(find.byKey(Key('mcb_service_card_$id')));
          await tester.pump();
        }

        await tester.tap(
          find.byKey(const Key('booking-summary-expand-toggle')),
        );
        await tester.pumpAndSettle();

        final double y3 = tester
            .getTopLeft(find.byKey(const ValueKey<String>('svc-3')))
            .dy;
        final double y1 = tester
            .getTopLeft(find.byKey(const ValueKey<String>('svc-1')))
            .dy;
        final double y2 = tester
            .getTopLeft(find.byKey(const ValueKey<String>('svc-2')))
            .dy;
        expect(
          y3 < y1 && y1 < y2,
          isTrue,
          reason:
              'the itemized shelf must render in TAP order (3, 1, 2), got '
              'y3=$y3 y1=$y1 y2=$y2',
        );
      },
    );

    testWidgets(
      'PHASE 253 legacy-path pin — ServiceStep with ONLY selectedServiceId/'
      'onSelect (no multi-select params) renders and behaves exactly as '
      'before this phase',
      (tester) async {
        String? selected;
        await tester.pumpApp(
          Scaffold(
            body: ServiceStep(
              selectedServiceId: selected,
              onSelect: (MasterService s) => selected = s.id,
            ),
          ),
          overrides: <Object>[
            servicesListProvider.overrideWith(_FakeServicesList.new),
            approvedCategoriesProvider.overrideWith(
              (ref) async => const <ServiceCategoryOption>[],
            ),
          ],
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('mcb_service_card_svc-1')), findsOneWidget);
        expect(
          tester
              .widget<ServiceCard>(
                find.byKey(const Key('mcb_service_card_svc-1')),
              )
              .selected,
          isFalse,
        );

        await tester.tap(find.byKey(const Key('mcb_service_card_svc-1')));
        await tester.pump();

        expect(selected, 'svc-1', reason: 'onSelect must still fire');
      },
    );

    testWidgets(
      'an empty service list renders the empty state, not the picker',
      (tester) async {
        await _pump(tester, services: const <MasterService>[]);
        await _fillClientStepAndAdvance(tester);

        expect(
          find.byKey(const Key('master-create-booking-service-empty')),
          findsOneWidget,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );
  });

  group(
    'MasterCreateBookingScreen — service step laziness (PERF A1 mirror)',
    () {
      testWidgets(
        'a large catalog (48 services across 8 categories) does not construct '
        'every ServiceCard on first render — off-screen sections stay unbuilt',
        (tester) async {
          final List<MasterService> bigCatalog = <MasterService>[
            for (int cat = 0; cat < 8; cat++)
              for (int i = 0; i < 6; i++)
                MasterService(
                  id: 'svc-$cat-$i',
                  serviceDefId: 'def-$cat-$i',
                  name: 'Послуга $cat-$i',
                  durationMinutes: 60,
                  priceMin: 500,
                  priceDisplay: '500 ₴',
                  category: 'CAT_$cat',
                ),
          ];
          await _pump(tester, services: bigCatalog);
          await _fillClientStepAndAdvance(tester);

          final int built = find.byType(ServiceCard).evaluate().length;
          final int sections = find.byType(CategorySection).evaluate().length;
          // FALSIFICATION (PERF A1 mirror, services_list_screen.dart:337) —
          // measured, not assumed: at this 800x600 test viewport only 1 of 8
          // sections (6 of 48 ServiceCards) is ever constructed, and this
          // number is IDENTICAL before and after the `ListView.builder`
          // conversion (both measured 1 section / 6 cards via a temporary
          // `cp`-backed revert during development — see finding-1 audit
          // notes). `RenderSliverList` already defers Element mounting (and
          // therefore `ServiceCard.initState()`/`AnimationController`
          // allocation) for off-screen children under a plain
          // `ListView(children: ...)`, same as under `.builder` — the
          // Sliver's own viewport-based child management is what's lazy, not
          // the delegate type. So this assertion does NOT discriminate the
          // fix from the pre-fix code for THIS specific mechanism; it guards
          // against a worse regression (e.g. swapping the outer list for a
          // non-Sliver `SingleChildScrollView` + `Column`, which has no
          // viewport-based child management at all and WOULD build every
          // card unconditionally).
          expect(
            built,
            lessThan(bigCatalog.length),
            reason:
                'expected off-screen ServiceCards to stay unbuilt on first '
                'render; got $built built out of ${bigCatalog.length} total',
          );
          expect(built, greaterThan(0));
          expect(sections, lessThan(8));
        },
      );
    },
  );

  group('MasterCreateBookingScreen — dateTime step', () {
    testWidgets('an empty slot list renders the designed empty state, never an '
        'infinite spinner', (tester) async {
      final fakeSlots = _FakeSlotRepository(
        slotsToReturn: const <BookingSlot>[],
      );
      await _pump(tester, slotRepository: fakeSlots);
      await _fillClientStepAndAdvance(tester);
      await _pickService(tester);
      await _pickDate(tester);

      expect(fakeSlots.getMasterSlotsCallCount, 1);
      expect(
        find.byKey(const Key('salon-schedule-no-slots-empty-state')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // Still on dateTime — no slot to have picked.
      expect(
        find.byKey(const Key('master-create-booking-confirm-card')),
        findsNothing,
      );
    });

    testWidgets('neither a date nor a slot tap navigates — each «Далі» press '
        'is what advances', (tester) async {
      final fakeSlots = _FakeSlotRepository(
        slotsToReturn: <BookingSlot>[_kSlot],
      );
      await _pump(tester, slotRepository: fakeSlots);
      await _fillClientStepAndAdvance(tester);
      await _pickService(tester);

      // --- date sub-phase: CTA dead until a day is tapped ---------------
      final Finder dateNext = find.byKey(
        const Key('master-create-booking-date-next'),
      );
      expect(dateNext, findsOneWidget);
      expect(tester.widget<NeumorphicButton>(dateNext).onPressed, isNull);

      await tester.tapCalendarDay(10);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('booking-month-calendar')),
        findsOneWidget,
        reason: 'a day tap must stage the date, never flip to the time chips',
      );
      expect(tester.widget<NeumorphicButton>(dateNext).onPressed, isNotNull);

      await tester.tap(dateNext);
      await tester.pumpAndSettle();

      // --- time sub-phase: CTA dead until a slot is tapped --------------
      final Finder timeNext = find.byKey(
        const Key('master-create-booking-time-next'),
      );
      expect(timeNext, findsOneWidget);
      expect(tester.widget<NeumorphicButton>(timeNext).onPressed, isNull);

      await tester.tap(
        find.byKey(Key('salon-slot-chip-${_kSlot.startAt.toIso8601String()}')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('master-create-booking-confirm-card')),
        findsNothing,
        reason: 'a slot tap must SELECT, never navigate',
      );
      expect(tester.widget<NeumorphicButton>(timeNext).onPressed, isNotNull);

      await tester.tap(timeNext);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('master-create-booking-confirm-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('master-create-booking-submit-cta')),
        findsOneWidget,
      );
    });

    // ------------------------------------------------------------------
    // FINDING 1 (CRITICAL — audit-fix cycle 1, 2026-08-20). The wizard used
    // to mirror the provider's slot into its own `_startAt` from a
    // `ref.listen` guarded EDGE-wise (`previous?.slot == null && next.slot !=
    // null`). `SalonBookingSchedule.selectSlot` writes slot A → slot B
    // directly, never through `null`, so a RE-PICK never re-fired and the
    // wizard confirmed and submitted the FIRST slot tapped — a third party's
    // appointment written at a time the master did not choose.
    //
    // Latent until the 2026-08-20 UX fix: before it, a slot tap navigated away
    // instantly, so a second tap was unreachable. This test is what makes the
    // re-pick reachable in the suite too — every other test here picks exactly
    // one slot, which is why the whole file stayed GREEN with the bug live.
    //
    // Asserts on the SUBMITTED request, not on the confirm card's label: the
    // wire value is what actually books someone else's time.
    // ------------------------------------------------------------------
    testWidgets('re-picking a slot submits the SECOND slot — the wizard must '
        'never confirm a time the master moved away from', (tester) async {
      final fakeSlots = _FakeSlotRepository(
        slotsToReturn: <BookingSlot>[_kSlot, _kSlotLate],
      );
      final fakeBookings = _FakeBookingRepository();
      await _pump(
        tester,
        slotRepository: fakeSlots,
        bookingRepository: fakeBookings,
      );
      await _fillClientStepAndAdvance(tester);
      await _pickService(tester);
      await _pickDate(tester);

      await tester.tap(
        find.byKey(Key('salon-slot-chip-${_kSlot.startAt.toIso8601String()}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          Key('salon-slot-chip-${_kSlotLate.startAt.toIso8601String()}'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('master-create-booking-time-next')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('master-create-booking-submit-cta')),
      );
      await tester.pumpAndSettle();

      expect(fakeBookings.calls, hasLength(1));
      expect(
        fakeBookings.calls.single.$2.startsAt,
        _kSlotLate.startAt,
        reason: 'the LAST slot tapped is the one that gets booked',
      );
    });

    testWidgets('the date & time step drops the self-referential master strip '
        'and the «…для цього майстра» intro', (tester) async {
      final fakeSlots = _FakeSlotRepository(
        slotsToReturn: <BookingSlot>[_kSlot],
      );
      await _pump(tester, slotRepository: fakeSlots);
      await _fillClientStepAndAdvance(tester);
      await _pickService(tester);

      final l10n = AppLocalizations.of(
        tester.element(find.byKey(const Key('booking-month-calendar'))),
      );
      expect(find.byType(MasterStrip), findsNothing);
      expect(find.text(l10n.salonScheduleDateIntro), findsNothing);

      await tester.tap(
        find.byKey(const Key('master-create-booking-date-next')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(MasterStrip),
        findsNothing,
        reason: 'the time sub-phase must not reintroduce it either',
      );
    });
  });

  group('MasterCreateBookingScreen — confirm step', () {
    // PHASE 256 — a 422 (slot outside working hours / day-off / past time /
    // service not offered) stays the GENERIC slot-conflict copy: UNLIKE a
    // 409, it is never the master's own double-tap/retry, so the
    // "already created" wording would be actively wrong here.
    testWidgets(
      'a 422 (genuine slot-unavailable) keeps the user on confirm with the '
      'GENERIC conflict message and does NOT advance to done',
      (tester) async {
        final fakeSlots = _FakeSlotRepository(
          slotsToReturn: <BookingSlot>[_kSlot],
        );
        final fakeBookings = _FakeBookingRepository(
          errorToThrow: const ConflictFailure(),
        );
        await _pump(
          tester,
          slotRepository: fakeSlots,
          bookingRepository: fakeBookings,
        );
        await _driveToConfirm(tester);

        await tester.tap(
          find.byKey(const Key('master-create-booking-submit-cta')),
        );
        await tester.pumpAndSettle();

        expect(fakeBookings.calls, hasLength(1));
        // Never advanced — still on confirm, never reached done.
        expect(
          find.byKey(const Key('master-create-booking-confirm-card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('master-create-booking-done-cta')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('master-create-booking-submit-error')),
          findsOneWidget,
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(MasterCreateBookingScreen)),
        );
        expect(find.text(l10n.errConflict), findsOneWidget);
        // No duplicate-specific snack for THIS failure type.
        expect(find.byType(VelvetSnack), findsNothing);
      },
    );

    // PHASE 256 D1.2 — should_showAlreadyCreatedMessage_when_409. Asserts the
    // ARB key via `l10n.errMasterBookingDuplicate`, never the literal
    // Ukrainian string.
    testWidgets(
      'should_showAlreadyCreatedMessage_when_409 — a duplicate-409 keeps the '
      'user on confirm with the "already created" message AND a recoverable '
      'snack, and does NOT advance to done',
      (tester) async {
        final fakeSlots = _FakeSlotRepository(
          slotsToReturn: <BookingSlot>[_kSlot],
        );
        final fakeBookings = _FakeBookingRepository(
          errorToThrow: const MasterBookingDuplicateFailure(),
        );
        await _pump(
          tester,
          slotRepository: fakeSlots,
          bookingRepository: fakeBookings,
        );
        await _driveToConfirm(tester);

        await tester.tap(
          find.byKey(const Key('master-create-booking-submit-cta')),
        );
        await pumpVelvetSnackIn(tester);

        expect(fakeBookings.calls, hasLength(1));
        expect(
          find.byKey(const Key('master-create-booking-confirm-card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('master-create-booking-done-cta')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('master-create-booking-submit-error')),
          findsOneWidget,
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(MasterCreateBookingScreen)),
        );
        // Two renders of the SAME message: the inline banner (ConfirmStep)
        // AND the recovery snack (this screen's own `_maybeShowDuplicateSnack`).
        // `expectVelvetSnack`'s unscoped `find.text` assumes exactly ONE
        // render app-wide, so it cannot be used as-is here — assert the
        // snack's own subtree directly instead.
        expect(find.text(l10n.errMasterBookingDuplicate), findsNWidgets(2));
        final Finder snackFinder = find.byType(VelvetSnack);
        expect(snackFinder, findsOneWidget);
        expect(
          (snackFinder.evaluate().single.widget as VelvetSnack).variant,
          VelvetSnackVariant.error,
        );
        expect(
          find.descendant(
            of: snackFinder,
            matching: find.text(l10n.errMasterBookingDuplicate),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: snackFinder,
            matching: find.text(l10n.masterCreateBookingDuplicateRefreshAction),
          ),
          findsOneWidget,
        );

        await pumpPastVelvetSnack(tester, hasAction: true);
      },
    );

    // PHASE 256 — should_returnToDateTimeStep_when_refreshTappedOnConflictSnack.
    testWidgets(
      'should_returnToDateTimeStep_when_refreshTappedOnConflictSnack — the '
      "409 snack's «Оновити» returns to dateTime and genuinely re-fetches "
      'the slot list on re-pick, not a cached hit',
      (tester) async {
        final fakeSlots = _FakeSlotRepository(
          slotsToReturn: <BookingSlot>[_kSlot],
        );
        final fakeBookings = _FakeBookingRepository(
          errorToThrow: const MasterBookingDuplicateFailure(),
        );
        await _pump(
          tester,
          slotRepository: fakeSlots,
          bookingRepository: fakeBookings,
        );
        await _driveToConfirm(tester);
        final int slotFetchesBeforeSubmit = fakeSlots.getMasterSlotsCallCount;

        await tester.tap(
          find.byKey(const Key('master-create-booking-submit-cta')),
        );
        await pumpVelvetSnackIn(tester);

        await tester.tap(
          find.byKey(const ValueKey<String>('velvet_snack_action')),
        );
        await tester.pumpAndSettle();

        // Back on `dateTime`, calendar sub-phase — confirm/submit-error gone.
        expect(
          find.byKey(const Key('master-create-booking-confirm-card')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('master-create-booking-submit-error')),
          findsNothing,
        );
        expect(find.byKey(const Key('booking-month-calendar')), findsOneWidget);

        // Re-pick the SAME day + slot — a genuinely dropped cache means this
        // is a REAL second fetch, not a retained one.
        await _pickDate(tester);
        await tester.tap(
          find.byKey(
            Key('salon-slot-chip-${_kSlot.startAt.toIso8601String()}'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          fakeSlots.getMasterSlotsCallCount,
          greaterThan(slotFetchesBeforeSubmit),
          reason:
              '«Оновити» must drop the cached slot fetch, not just navigate '
              'back to a stale one',
        );
      },
    );

    // PHASE 256 — mobile-debugger finding (2026-08-21): `confirm`'s
    // `PopScope(canPop: !inTimeSubPhase)` is `true` here, so a genuine
    // system back gesture CAN pop the whole wizard while the duplicate-409
    // snack is still dwelling (6s, root overlay, independent of this
    // screen's subtree). A tap on its «Оновити» action AFTER that pop must
    // not touch `ref`/`setState` on the now-disposed screen State.
    testWidgets('should_notCrash_when_snackActionTappedAfterWizardPopped — the '
        'duplicate-409 snack survives a system-back pop of the wizard, and '
        'tapping «Оновити» afterwards is a silent no-op, not a crash', (
      tester,
    ) async {
      final fakeSlots = _FakeSlotRepository(
        slotsToReturn: <BookingSlot>[_kSlot],
      );
      final fakeBookings = _FakeBookingRepository(
        errorToThrow: const MasterBookingDuplicateFailure(),
      );
      await _pump(
        tester,
        slotRepository: fakeSlots,
        bookingRepository: fakeBookings,
      );
      await _driveToConfirm(tester);

      await tester.tap(
        find.byKey(const Key('master-create-booking-submit-cta')),
      );
      await pumpVelvetSnackIn(tester);
      expect(find.byType(VelvetSnack), findsOneWidget);

      // A genuine system back pop — `confirm`'s PopScope permits it.
      final bool handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handled, isTrue);
      expect(find.byType(MasterCreateBookingScreen), findsNothing);

      // The snack survives the pop — it lives on the app's root overlay,
      // not inside the popped screen's subtree.
      expect(find.byType(VelvetSnack), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('velvet_snack_action')),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'a disposed State must not receive ref.invalidate/ref.read/'
            'setState from the late snack-action tap',
      );

      await pumpPastVelvetSnack(tester, hasAction: true);
    });

    testWidgets(
      'a successful submit sends the normalized E.164 phone + the picked '
      'service/slot and advances to done',
      (tester) async {
        final fakeSlots = _FakeSlotRepository(
          slotsToReturn: <BookingSlot>[_kSlot],
        );
        final fakeBookings = _FakeBookingRepository();
        await _pump(
          tester,
          slotRepository: fakeSlots,
          bookingRepository: fakeBookings,
        );
        await _driveToConfirm(tester);

        await tester.tap(
          find.byKey(const Key('master-create-booking-submit-cta')),
        );
        await tester.pumpAndSettle();

        expect(fakeBookings.calls, hasLength(1));
        final (String masterId, CreateMasterBookingRequest sent) =
            fakeBookings.calls.single;
        expect(masterId, _kMaster.id);
        expect(sent.masterServiceIds, [_kService.id]);
        expect(sent.startsAt, _kSlot.startAt);
        expect(sent.guest.name, 'Марина');
        expect(sent.guest.surname, 'Кравчук');
        expect(sent.guest.phone, '+380501234567');

        expect(
          find.byKey(const Key('master-create-booking-done-cta')),
          findsOneWidget,
        );
      },
    );

    // PHASE 256 D1 — should_disableCta_when_submitInFlight. Mutation-check
    // RED by removing the `_submitting`/`isLoading` gate on
    // `_ConfirmCtaFooter` (`enabled: !busy` → `enabled: true`): this goes red
    // because `onPressed` stops going `null` mid-flight.
    testWidgets(
      'should_disableCta_when_submitInFlight — the CTA is disabled for the '
      'WHOLE outstanding submit, not just while the network call is live',
      (tester) async {
        final fakeSlots = _FakeSlotRepository(
          slotsToReturn: <BookingSlot>[_kSlot],
        );
        final hold = Completer<void>();
        final fakeBookings = _FakeBookingRepository(hold: hold);
        await _pump(
          tester,
          slotRepository: fakeSlots,
          bookingRepository: fakeBookings,
        );
        await _driveToConfirm(tester);

        final Finder cta = find.byKey(
          const Key('master-create-booking-submit-cta'),
        );
        expect(tester.widget<NeumorphicButton>(cta).onPressed, isNotNull);

        await tester.tap(cta);
        await tester.pump();

        expect(
          tester.widget<NeumorphicButton>(cta).onPressed,
          isNull,
          reason: 'the CTA must be disabled the instant a submit starts',
        );

        hold.complete();
        await tester.pumpAndSettle();

        expect(fakeBookings.calls, hasLength(1));
      },
    );

    // PHASE 256 — should_submitOnce_when_ctaDoubleTapped. EMPIRICALLY proven
    // RED before `_submitting` existed: two `tester.tap()` calls with NO
    // intervening `pump()` fired TWO real `createMasterBooking` calls,
    // because the notifier's OWN `state.isLoading` guard had already flipped
    // back to `false` (`AsyncValue.guard` resolved) by the time the second
    // tap landed — a turn BEFORE this screen's own `setState` to `done` ran.
    // See `master_create_booking_screen.dart`'s `_submitting` field doc for
    // the full mechanism this closes.
    testWidgets(
      'should_submitOnce_when_ctaDoubleTapped — two fast taps with no pump '
      'between them issue exactly ONE createMasterBooking call',
      (tester) async {
        final fakeSlots = _FakeSlotRepository(
          slotsToReturn: <BookingSlot>[_kSlot],
        );
        final fakeBookings = _FakeBookingRepository();
        await _pump(
          tester,
          slotRepository: fakeSlots,
          bookingRepository: fakeBookings,
        );
        await _driveToConfirm(tester);

        final Finder cta = find.byKey(
          const Key('master-create-booking-submit-cta'),
        );
        await tester.tap(cta);
        await tester.tap(cta);
        await tester.pumpAndSettle();

        expect(fakeBookings.calls, hasLength(1));
        expect(
          find.byKey(const Key('master-create-booking-done-cta')),
          findsOneWidget,
        );
      },
    );
  });

  group('MasterCreateBookingScreen — done step', () {
    Future<void> reachDone(WidgetTester tester) async {
      final fakeSlots = _FakeSlotRepository(
        slotsToReturn: <BookingSlot>[_kSlot],
      );
      await _pump(tester, slotRepository: fakeSlots);
      await _driveToConfirm(tester);
      await tester.tap(
        find.byKey(const Key('master-create-booking-submit-cta')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('blocks the back gesture (PopScope canPop: false)', (
      tester,
    ) async {
      await reachDone(tester);

      final PopScope popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
    });

    // mobile-qa gap fix — the test above only inspects `PopScope.canPop` as a
    // static property; it never proves an actual pop attempt is refused. A
    // regression that wired `canPop: widget.canPop` to the wrong bool, or
    // rendered the PopScope around the wrong subtree, would still pass it.
    // This drives a REAL system back-button event (mirrors
    // `client_shell_detail_pop_test.dart`'s `tester.binding.handlePopRoute()`
    // convention) and asserts the done step is still on screen afterwards —
    // MUTATION-VERIFIED: passing `canPop: true` at the `_DoneStep`→
    // `BookingSuccessScaffold` call site turns this RED (the done screen
    // pops and `master-create-booking-done-cta` disappears); reverting turns
    // it back GREEN. The property-only test above does NOT catch that same
    // mutation — it only reads a different call site's default.
    testWidgets(
      'a real system back-button press on done is refused, not just the '
      'canPop property',
      (tester) async {
        await reachDone(tester);

        expect(
          find.byKey(const Key('master-create-booking-done-cta')),
          findsOneWidget,
        );

        final bool handled = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(
          handled,
          isTrue,
          reason: 'PopScope(canPop: false) must itself consume the pop',
        );
        expect(
          find.byKey(const Key('master-create-booking-done-cta')),
          findsOneWidget,
          reason:
              'done step must still be on screen — the back press must '
              'be a no-op, not just report canPop:false',
        );
      },
    );

    testWidgets('hides the header and the step indicator', (tester) async {
      await reachDone(tester);

      expect(find.byType(BookingTopBar), findsNothing);
      expect(find.byKey(const Key('master-create-booking-back')), findsNothing);
    });

    testWidgets('the done-step copy makes no SMS/notification claim', (
      tester,
    ) async {
      await reachDone(tester);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(MasterCreateBookingScreen)),
      );
      expect(find.text(l10n.masterCreateBookingDoneSubline), findsOneWidget);
      expect(find.textContaining('SMS'), findsNothing);
      expect(find.textContaining('Сповіщення'), findsNothing);
    });

    testWidgets('«Готово» pops back to the previous screen', (tester) async {
      final GoRouter router = _router();
      final fakeSlots = _FakeSlotRepository(
        slotsToReturn: <BookingSlot>[_kSlot],
      );
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          masterProfileProvider.overrideWith(_FakeMasterProfile.new),
          servicesListProvider.overrideWith(_FakeServicesList.new),
          approvedCategoriesProvider.overrideWith(
            (ref) async => const <ServiceCategoryOption>[],
          ),
          slotRepositoryProvider.overrideWith((_) => fakeSlots),
          bookingRepositoryProvider.overrideWith(
            (_) => _FakeBookingRepository(),
          ),
          clockProvider.overrideWithValue(() => _kNow),
        ],
      );
      unawaited(router.push(RouteNames.masterBookingNew));
      await tester.pumpAndSettle();

      await _driveToConfirm(tester);
      await tester.tap(
        find.byKey(const Key('master-create-booking-submit-cta')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('master-create-booking-done-cta')));
      await tester.pumpAndSettle();

      expect(find.byType(MasterCreateBookingScreen), findsNothing);
      expect(
        router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
        '/root',
      );
    });

    // ----------------------------------------------------------------------
    // FINDING F7 (mobile-security, 2026-08-20). The done step re-displays the
    // guest card — the master's one chance to notice they typed the wrong
    // client BEFORE walking away from the screen. It shipped with no test:
    // deleting the whole `NeumorphicCard` from `_DoneStep.recapCards` left
    // every assertion in this file green.
    // ----------------------------------------------------------------------
    testWidgets('renders the guest card, carrying the name and phone the '
        'master typed, ABOVE the booking summary', (tester) async {
      await reachDone(tester);

      final Finder guestCard = find.byKey(
        const Key('master-create-booking-done-guest-card'),
      );
      expect(guestCard, findsOneWidget);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(MasterCreateBookingScreen)),
      );
      expect(
        find.descendant(
          of: guestCard,
          matching: find.text(l10n.masterCreateBookingGuestLabel),
        ),
        findsOneWidget,
      );
      // The VALUES, not just the label — this card exists to be double-checked,
      // so an empty or mis-bound one is the same defect as a missing one.
      // Interpolated rather than a Cyrillic literal (forbid_cyrillic_finder).
      expect(
        find.descendant(
          of: guestCard,
          matching: find.text('$_kGuestFirstName $_kGuestLastName'),
        ),
        findsOneWidget,
      );
      // The DISPLAYED phone, not the raw keystrokes: the field runs
      // `UaPhoneInputFormatter`, so the controller holds the formatted text
      // and that is what the card echoes. Asserting the digits survive the
      // round trip is the point — a mis-bound card would show blank or the
      // service name here.
      expect(
        find.descendant(
          of: guestCard,
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w is Text &&
                (w.data ?? '')
                    .replaceAll(RegExp(r'[^0-9]'), '')
                    .endsWith(_kGuestPhone.replaceAll(RegExp(r'[^0-9]'), '')),
          ),
        ),
        findsOneWidget,
      );

      // Guest first, booking details second — the same order [ConfirmStep]
      // uses, so the payoff screen reads as a continuation of the step the
      // master just confirmed rather than a different layout.
      final double guestY = tester.getTopLeft(guestCard).dy;
      final double summaryY = tester
          .getTopLeft(find.byKey(const Key('master-create-booking-done-card')))
          .dy;
      expect(guestY, lessThan(summaryY));
    });

    // PHASE 256 D3 — should_renderServerVisitWindow_when_multiServiceVisitCreated.
    // MUTATION-CHECK RED by rendering from local state: reverting `_DoneStep`
    // to `formatTimeRange(startAt, <local sum of durationMinutes>)` renders
    // 13:00–14:45 (the naive local sum, 60 + 45 = 105 min, no buffer) — this
    // test's fixture response deliberately adds a 15-minute buffer the local
    // selection has no way to know about, so the two render DIFFERENTLY and
    // a regression to local-state rendering is directly visible here.
    testWidgets(
      'should_renderServerVisitWindow_when_multiServiceVisitCreated — the '
      "done step's window and every service come from the SERVER response, "
      'not the local selection',
      (tester) async {
        const int bufferedTotalMinutes = 60 + 15 + 45; // svc-1 + buffer + svc-2
        final fakeSlots = _FakeSlotRepository(
          slotsToReturn: <BookingSlot>[_kSlot],
        );
        final fakeBookings = _FakeBookingRepository(
          responseOverride:
              (String masterId, CreateMasterBookingRequest request) {
                final DateTime svc1End = request.startsAt.add(
                  const Duration(minutes: 60),
                );
                final DateTime svc2Start = svc1End.add(
                  const Duration(minutes: 15),
                );
                final DateTime svc2End = svc2Start.add(
                  const Duration(minutes: 45),
                );
                return Appointment(
                  id: 'appt-multi',
                  status: BookingStatus.confirmed,
                  masterId: masterId,
                  masterFirstName: _kMaster.firstName,
                  masterLastName: _kMaster.lastName,
                  masterType: 'INDEPENDENT_MASTER',
                  startAt: request.startsAt,
                  endAt: request.startsAt.add(
                    const Duration(minutes: bufferedTotalMinutes),
                  ),
                  totalDurationMinutes: bufferedTotalMinutes,
                  totalPrice: _kService.priceMin + _kService2.priceMin,
                  items: <AppointmentItem>[
                    AppointmentItem(
                      bookingId: 'booking-1',
                      masterServiceId: _kService.id,
                      serviceName: _kService.name,
                      startAt: request.startsAt,
                      endAt: svc1End,
                      durationMinutes: _kService.durationMinutes,
                      price: _kService.priceMin,
                    ),
                    AppointmentItem(
                      bookingId: 'booking-2',
                      masterServiceId: _kService2.id,
                      serviceName: _kService2.name,
                      startAt: svc2Start,
                      endAt: svc2End,
                      durationMinutes: _kService2.durationMinutes,
                      price: _kService2.priceMin,
                    ),
                  ],
                );
              },
        );
        await _pump(
          tester,
          services: const <MasterService>[_kService, _kService2],
          slotRepository: fakeSlots,
          bookingRepository: fakeBookings,
        );
        await _fillClientStepAndAdvance(tester);
        await tester.tap(find.byKey(const Key('mcb_service_card_svc-1')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('mcb_service_card_svc-2')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('booking-summary-cta')));
        await tester.pumpAndSettle();
        await _pickDate(tester);
        await _pickSlot(tester);

        await tester.tap(
          find.byKey(const Key('master-create-booking-submit-cta')),
        );
        await tester.pumpAndSettle();

        final DateTime expectedEnd = _kSlot.startAt.add(
          const Duration(minutes: bufferedTotalMinutes),
        );
        expect(
          find.text(formatSlotTimeRange(_kSlot.startAt, expectedEnd)),
          findsOneWidget,
          reason:
              'must render the SERVER endAt (with buffer), not the naive '
              'local sum of durationMinutes',
        );
        // Every service in the visit, not just the first tap-ordered pick.
        expect(find.text(_kService.name), findsOneWidget);
        expect(find.text(_kService2.name), findsOneWidget);
      },
    );
  });

  // -------------------------------------------------------------------------
  // mobile-security, 2026-08-20 — the wizard's PII surface.
  // -------------------------------------------------------------------------
  group('MasterCreateBookingScreen — screen protection', () {
    testWidgets('acquires the app-wide screen protection on mount and releases '
        'it when the wizard is popped', (tester) async {
      final protection = _CountingScreenProtection();
      final GoRouter router = await _pump(tester, screenProtection: protection);

      expect(
        protection.acquires,
        1,
        reason:
            'the wizard collects a third party\'s full name and phone number '
            'the moment it opens — FLAG_SECURE / the app-switcher blur must be '
            'on for the WHOLE flow, from the first keystroke on the client '
            'step, not from the confirm step onward',
      );
      expect(
        protection.releases,
        0,
        reason: 'still on screen — releasing here would drop protection early',
      );

      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(MasterCreateBookingScreen), findsNothing);

      expect(
        protection.releases,
        1,
        reason:
            'the RELEASE half matters as much: a leaked acquire latches '
            'FLAG_SECURE on for the rest of the session and screenshots '
            'silently stop working app-wide',
      );
      expect(
        protection.acquires,
        1,
        reason:
            'acquired exactly once, not per '
            'step — the acquire lives in initState, not in a step builder',
      );
    });

    testWidgets('protection is still held on the DONE step, where the guest '
        'name and phone are re-displayed', (tester) async {
      final protection = _CountingScreenProtection();
      final fakeSlots = _FakeSlotRepository(
        slotsToReturn: <BookingSlot>[_kSlot],
      );
      await _pump(
        tester,
        slotRepository: fakeSlots,
        screenProtection: protection,
      );
      await _driveToConfirm(tester);
      await tester.tap(
        find.byKey(const Key('master-create-booking-submit-cta')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('master-create-booking-done-guest-card')),
        findsOneWidget,
        reason: 'sanity: the PII really is on screen at this point',
      );
      expect(protection.releases, 0);
      expect(protection.acquires, 1);
    });
  });
}
