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
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_category_list.dart'
    show CategorySection, ServiceCard;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

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
class _FakeBookingRepository implements BookingRepository {
  _FakeBookingRepository({this.errorToThrow});

  Object? errorToThrow;
  final List<(String, CreateMasterBookingRequest)> calls =
      <(String, CreateMasterBookingRequest)>[];

  @override
  Future<Booking> createMasterBooking(
    String masterId,
    CreateMasterBookingRequest request,
  ) async {
    calls.add((masterId, request));
    final Object? err = errorToThrow;
    if (err != null) throw err;
    return Booking(
      id: 'booking-1',
      masterId: masterId,
      masterFirstName: _kMaster.firstName,
      masterLastName: _kMaster.lastName,
      masterType: 'INDEPENDENT_MASTER',
      serviceId: request.masterServiceId,
      serviceName: _kService.name,
      durationMinutes: _kService.durationMinutes,
      price: _kService.priceMin,
      startAt: request.startsAt,
      endAt: request.startsAt.add(Duration(minutes: _kService.durationMinutes)),
      status: BookingStatus.confirmed,
      canReview: false,
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
    ],
  );
  unawaited(router.push(RouteNames.masterBookingNew));
  await tester.pumpAndSettle();
  return router;
}

/// Fills the client step with valid data and taps «Далі» — the shared first
/// leg of every test that needs to reach a later step.
Future<void> _fillClientStepAndAdvance(WidgetTester tester) async {
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
  await tester.tap(find.byKey(const Key('master-create-booking-client-next')));
  await tester.pumpAndSettle();
}

/// Taps the (only) fixture service card — auto-advances to `dateTime`.
Future<void> _pickService(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('mcb_service_card_svc-1')));
  await tester.pumpAndSettle();
}

/// Picks Aug 10 (== [_kNow]'s Kyiv "today") on the calendar.
Future<void> _pickDate(WidgetTester tester) async {
  await tester.tapCalendarDay(10);
  await tester.pumpAndSettle();
}

/// Taps the [_kSlot] chip — auto-advances to `confirm`.
Future<void> _pickSlot(WidgetTester tester) async {
  await tester.tap(
    find.byKey(Key('salon-slot-chip-${_kSlot.startAt.toIso8601String()}')),
  );
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
    testWidgets('tapping a service auto-advances to dateTime', (tester) async {
      await _pump(tester);
      await _fillClientStepAndAdvance(tester);

      expect(find.byKey(const Key('mcb_service_card_svc-1')), findsOneWidget);
      await _pickService(tester);

      expect(
        find.byKey(const Key('booking-month-calendar')),
        findsOneWidget,
        reason: 'picking the service must land on the dateTime step',
      );
    });

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

    testWidgets('picking a date then a slot auto-advances to confirm', (
      tester,
    ) async {
      final fakeSlots = _FakeSlotRepository(
        slotsToReturn: <BookingSlot>[_kSlot],
      );
      await _pump(tester, slotRepository: fakeSlots);
      await _fillClientStepAndAdvance(tester);
      await _pickService(tester);
      await _pickDate(tester);
      await _pickSlot(tester);

      expect(
        find.byKey(const Key('master-create-booking-confirm-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('master-create-booking-submit-cta')),
        findsOneWidget,
      );
    });
  });

  group('MasterCreateBookingScreen — confirm step', () {
    testWidgets(
      'a 409 conflict keeps the user on confirm with an actionable message '
      'and does NOT advance to done',
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
      },
    );

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
        expect(sent.masterServiceId, _kService.id);
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
  });
}
