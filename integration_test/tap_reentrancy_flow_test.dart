// E2E — TAP RE-ENTRANCY: three taps in one burst open ONE route / send ONE
// request, on the five highest-risk surfaces of the app.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ---------------------------------------
// The «+ Додати послуги» bug: on a real device the frame scheduler wedged
// (flutter_riverpod 3.1.0, fixed by the 3.3.1 upgrade) while taps kept being
// delivered. Every queued tap reached its handler before any rebuild could
// disable the button, so each one pushed its own copy of the setup page.
// The app-wide hardening that followed (`core/navigation/single_flight.dart`'s
// `pushOnce` / `showDialogOnce`, `NeumorphicButton.onPressedAsync`, and local
// `_submitInFlight`-style guards) is proven per-widget by the widget tier; this
// file proves it survives the REAL router, shell, providers and fake backend.
//
// HOW THE "NO FRAME BETWEEN TAPS" CONDITION IS MADE REAL
// ------------------------------------------------------
// `await tester.tap(...)` three times is NOT enough: every `await` yields to
// the event loop, and the live integration binding may draw a frame in the
// gap, which is exactly the rebuild that would mask a missing guard. So
// [_rapidTaps] dispatches all three down/up pairs SYNCHRONOUSLY through
// `binding.handlePointerEventForSource` in one Dart turn: no frame, no
// microtask, no timer can run between them. That is the wedged-scheduler
// condition the device hit, reproduced deterministically.
//
// Every flow ENTERS its screen the way a user does — bottom-nav taps, cards,
// CTAs — never `router.go` / `router.push` straight to the screen under test.
// Route counts use `skipOffstage: false`, because a duplicate push stacks a
// second copy UNDER the visible one, where a default finder cannot see it.
// Request counts are read from `FakeBackend`'s recorded calls (and, on the two
// client/salon visit paths that have no fake `POST /appointments` route — the
// generated client's real-Dio timer leak, see
// `independent_multi_service_booking_flow_test.dart` — from the same
// hand-written `AppointmentRepository` fake those flows use).
//
// FALSIFIED (mobile-qa, 2026-10-15): reverting the guards behind flows 1 and 2
// turns them red — see the QA report for the recorded mutations. EXCEPTION:
// flow 2a's «Записатись» step is deliberately NOT a screen-guard pin — phase
// 262 D5 (user-locked) keeps the client-create path guard-free, so it pins the
// idempotency-key contract the server dedupes on instead.

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_appointment_request.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_review_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_time_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_tab_bar.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/master_result_card.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_screen.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/fake_media_cache.dart';
import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';

/// Pointer ids for [_rapidTaps] — far above the ids `WidgetTester` hands out,
/// so a burst never collides with a gesture the tester itself has open.
int _nextPointer = 90000;

/// Delivers [count] complete taps to [finder]'s centre in ONE synchronous
/// burst. There is no `await` inside: no frame, microtask or timer can run
/// between the taps, so every tap reaches the SAME, not-yet-rebuilt widget —
/// the condition a wedged frame scheduler produces on a device. A guard that
/// relies on a rebuild (`loading: true`, `onPressed: null`, the new route
/// covering the button) cannot drop taps 2 and 3 here; only a synchronous
/// guard can.
void _rapidTaps(WidgetTester tester, Finder finder, {int count = 3}) {
  final Finder target = finder.hitTestable();
  expect(
    target,
    findsOneWidget,
    reason: 'the burst target must be on screen and hit-testable: $finder',
  );
  final Offset centre = tester.getCenter(target);
  for (int i = 0; i < count; i++) {
    final int pointer = _nextPointer++;
    tester.binding.handlePointerEventForSource(
      PointerDownEvent(pointer: pointer, position: centre),
      source: TestBindingEventSource.test,
    );
    tester.binding.handlePointerEventForSource(
      PointerUpEvent(pointer: pointer, position: centre),
      source: TestBindingEventSource.test,
    );
  }
}

/// Advances [frames] bounded frames. Used where the destination holds a
/// never-settling animation (ServiceSetupScreen's loading shimmer) so
/// `pumpAndSettle` would hang, and where the point is to give any DUPLICATE
/// push queued by the burst every chance to land before it is counted.
Future<void> _pumpFrames(WidgetTester tester, {int frames = 10}) async {
  for (int i = 0; i < frames; i++) {
    // fixed-wait-ok: bounded frame advance past a never-settling setup-screen animation; lets any duplicate route queued by the burst land before the count.
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// How long the fake HOLDS a write in the slow-network flows — comfortably
/// longer than the re-tap rounds below (2 × ~0.6 s), so every re-tap lands
/// while the first request is still in flight.
const Duration _kHeld = Duration(seconds: 3);

/// Slow-network re-entrancy: while the first request is held by the fake,
/// taps [cta] again [rounds] times with REAL frames in between, and confirms
/// any dialog that reopens (exactly what a user would do). Returns how many
/// dialogs reopened. Asserts the CTA is genuinely on screen and tappable for
/// every re-tap — otherwise a "1 call" result could come from the button being
/// hidden, not from the guard (playbook M14).
Future<int> _retapWhileInFlight(
  WidgetTester tester, {
  required Key cta,
  required Key confirm,
  int rounds = 2,
}) async {
  int reopened = 0;
  for (int i = 0; i < rounds; i++) {
    final Finder target = find.byKey(cta).hitTestable();
    expect(
      target,
      findsOneWidget,
      reason:
          'the CTA must stay tappable while the request is in flight, or '
          'this re-tap proves nothing',
    );
    await tester.tap(target);
    await _pumpFrames(tester, frames: 3);
    final Finder reopenedConfirm = find.byKey(confirm).hitTestable();
    if (reopenedConfirm.evaluate().isNotEmpty) {
      reopened++;
      await tester.tap(reopenedConfirm);
      await _pumpFrames(tester, frames: 3);
    }
  }
  return reopened;
}

/// Counts mounted instances of [type] INCLUDING offstage ones — a duplicate
/// push stacks a copy beneath the visible route, which a default
/// (`skipOffstage: true`) finder would never see.
int _mounted(Type type) =>
    find.byType(type, skipOffstage: false).evaluate().length;

int _mountedKey(Key key) =>
    find.byKey(key, skipOffstage: false).evaluate().length;

/// Records every `createAppointment` — the client/salon visit write. Mirrors
/// the `_FakeAppointmentRepository` precedent in
/// `independent_multi_service_booking_flow_test.dart` /
/// `salon_booking_flow_test.dart` (no fake `POST /appointments` route exists).
class _RecordingAppointmentRepository implements AppointmentRepository {
  final List<CreateAppointmentRequest> requests = <CreateAppointmentRequest>[];

  int callsFor(String masterId) =>
      requests.where((r) => r.masterId == masterId).length;

  @override
  Future<Appointment> createAppointment(CreateAppointmentRequest req) async {
    requests.add(req);
    final DateTime end = req.startAt.add(const Duration(minutes: 60));
    return Appointment(
      id: 'appt-${requests.length}',
      status: BookingStatus.confirmed,
      masterId: req.masterId,
      masterFirstName: 'Софія',
      masterLastName: 'Бондар',
      masterType: 'INDEPENDENT_MASTER',
      startAt: req.startAt,
      endAt: end,
      totalDurationMinutes: 60,
      totalPrice: 500,
      items: <AppointmentItem>[
        for (final String id in req.masterServiceIds)
          AppointmentItem(
            bookingId: 'booking-$id',
            masterServiceId: id,
            serviceName: 'Послуга',
            startAt: req.startAt,
            endAt: end,
            durationMinutes: 60,
            price: 500,
          ),
      ],
    );
  }

  @override
  Future<Appointment> getAppointment(String id) => throw UnimplementedError();

  @override
  Future<Appointment> rescheduleAppointmentItem(
    String appointmentId,
    String bookingId,
    DateTime newStartAt, {
    bool allowClientOverlap = false,
  }) => throw UnimplementedError();

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

/// Publishes a 09:00–21:00 Kyiv window for [day] (Phase 244 gates the master
/// timeline behind published hours). Same two-line call as
/// `master_bookings_flow_test.dart`'s private `_seedWorkingHours`.
void _seedWorkingHours(FakeBackend fb, DateTime day) {
  fb.seedEffectiveSchedule(<Map<String, dynamic>>[
    FakeBackend.seedEffectiveScheduleDay(
      day,
      intervals: const <(String, String)>[('09:00:00', '21:00:00')],
    ),
  ]);
}

/// Client: bottom-nav search → «Показати» → drain the forced second results
/// page so later settles converge. Same chain `salon_booking_flow_test.dart`
/// and `service_preselection_flow_test.dart` drive.
Future<void> _reachSearchResults(
  WidgetTester tester, {
  bool filterClassicManicure = false,
}) async {
  await tester.tap(find.byKey(const Key('client-nav-search-center')));
  await AppHarness.settle(tester);
  if (filterClassicManicure) {
    await AppHarness.scrollFilterFieldIntoView(
      tester,
      const Key('search_service_type_NAILS'),
    );
    await tester.tap(find.byKey(const Key('search_service_type_NAILS')));
    await AppHarness.settle(tester);
    await tester.tap(
      find.byKey(const Key('search_service_chip_CLASSIC_MANICURE')),
    );
    await AppHarness.settle(tester);
  }
  await tester.tap(find.byKey(const Key('search_show_masters_cta')));
  await tester.pump();
  for (
    int i = 0;
    i < 30 && find.byKey(const Key('results_list')).evaluate().isEmpty;
    i++
  ) {
    await tester.pump();
  }
  expect(find.byKey(const Key('results_list')), findsOneWidget);
  final ScrollableState scrollable = tester.state<ScrollableState>(
    find.descendant(
      of: find.byKey(const Key('results_list')),
      matching: find.byType(Scrollable),
    ),
  );
  scrollable.position.jumpTo(scrollable.position.pixels + 1);
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await AppHarness.settle(tester);
}

/// Independent master: login → «Послуги» bottom-nav tile → «Мої послуги».
Future<void> _openMyServicesViaNav(WidgetTester tester, GoRouter router) async {
  AppHarness.expectLocation(router, RouteNames.masterProfile);
  await tester.tap(find.byKey(const Key('master-nav-tile-0')));
  await tester.pumpUntilFound(
    find.byKey(const Key('btn-create-service')).hitTestable(),
  );
  AppHarness.expectLocation(router, RouteNames.services);
  expect(find.byType(ServicesListScreen), findsOneWidget);
}

/// Independent master: «Мої записи» tile → today's timeline → booking-1 card →
/// «Деталі запису». booking-1 must be seeded on the injected clock's Kyiv day.
Future<void> _openMasterBookingDetailViaNav(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('master-nav-tile-1')));
  await AppHarness.settle(tester);
  expect(find.byType(MasterBookingsScreen), findsOneWidget);
  final Finder card = find.byKey(const Key('master-booking-card-booking-1'));
  await tester.scrollUntilVisible(
    card,
    200,
    scrollable: find
        .descendant(
          of: find.byType(BookingsTimelineGrid),
          matching: find.byType(Scrollable),
        )
        .first,
    maxScrolls: 60,
  );
  await AppHarness.settle(tester);
  await tester.tap(card);
  await AppHarness.settle(tester);
  expect(find.byType(BookingDetailScreen), findsOneWidget);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installOverflowGuard();
    MediaConfig.debugAllowedHosts = <String>{'media.test'};
    debugMediaCacheManager = FakeMediaCacheManager(mediaLoaded);
  });
  tearDown(() async {
    debugMediaCacheManager = null;
    MediaConfig.debugAllowedHosts = null;
    await AppHarness.tearDownHarness();
  });

  // ===========================================================================
  // FLOW 1 — THE REPORTED BUG. «Мої послуги» via the bottom nav → FAB ×3 →
  // exactly ONE setup screen; close → back on the list; «Зберегти» ×3 →
  // exactly ONE bulk POST.
  // ===========================================================================
  testWidgets(
    'INDEPENDENT_MASTER: «Мої послуги» FAB tapped 3x in one burst opens ONE '
    'setup screen, and «Зберегти» tapped 3x sends ONE bulk create',
    (tester) async {
      final fb = FakeBackend();
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await _openMyServicesViaNav(tester, router);

      // ── FAB ×3 → ONE ServiceSetupScreen ─────────────────────────────────
      _rapidTaps(tester, find.byKey(const Key('btn-create-service')));
      await tester.pumpUntilFound(find.byKey(const Key('btn-setup-close')));
      await _pumpFrames(tester);
      expect(
        _mounted(ServiceSetupScreen),
        1,
        reason:
            'three same-frame FAB taps must push the setup page ONCE — the '
            'shipped bug stacked one copy per tap',
      );

      // ── Close → back on «Мої послуги» ───────────────────────────────────
      await tester.tap(find.byKey(const Key('btn-setup-close')));
      await tester.pumpUntilGone(find.byKey(const Key('btn-setup-close')));
      await tester.pumpUntilFound(
        find.byKey(const Key('btn-create-service')).hitTestable(),
      );
      expect(_mounted(ServiceSetupScreen), 0);
      AppHarness.expectLocation(router, RouteNames.services);

      // ── The lock released: one more tap opens it again. ─────────────────
      await tester.tap(find.byKey(const Key('btn-create-service')));
      await tester.pumpUntilFound(find.byKey(const Key('btn-setup-close')));
      expect(_mounted(ServiceSetupScreen), 1);

      // Include the free NAILS type (the seeded `assign-typed` owns
      // type-nails-classic) and give it a valid duration + price.
      const String freeTypeId = 'type-nails-gel';
      final Finder nailsChip = find.byKey(const ValueKey<String>('cat_NAILS'));
      await tester.pumpUntilFound(nailsChip.hitTestable());
      await tester.tap(nailsChip);
      final Finder freeRow = find.byKey(const Key('setup_row_$freeTypeId'));
      await tester.pumpUntilFound(freeRow);
      final Finder freeToggle = find.byKey(
        const Key('setup_row_toggle_$freeTypeId'),
      );
      await tester.ensureVisible(freeToggle);
      await tester.pumpUntilFound(freeToggle.hitTestable());
      await tester.tap(freeToggle);
      final Finder durationField = find.descendant(
        of: freeRow,
        matching: find.byKey(const Key('service-setup-duration')),
      );
      final Finder priceField = find.descendant(
        of: freeRow,
        matching: find.byKey(const Key('pricing-fixed-amount')),
      );
      await tester.pumpUntilFound(durationField);
      await tester.enterText(durationField, '90');
      await tester.pump();
      await tester.enterText(priceField, '700');
      await tester.pump();

      // ── «Зберегти» ×3 → ONE bulk POST ───────────────────────────────────
      final Finder saveBtn = find.byKey(const Key('btn-setup-save'));
      await tester.pumpUntilFound(saveBtn.hitTestable());
      expect(fb.bulkCreateCalls, 0);
      _rapidTaps(tester, saveBtn);
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.bulkCreateCalls >= 1,
        description: 'the bulk POST to reach the fake backend',
      );
      await tester.pumpUntilGone(find.byKey(const Key('btn-setup-close')));
      await _pumpFrames(tester);
      expect(
        fb.bulkCreateCalls,
        1,
        reason:
            'three same-frame «Зберегти» taps must send ONE bulk create — '
            '`_saveInFlight` is set synchronously on the first tap',
      );
      expect(fb.lastBulkItems, hasLength(1));
      AppHarness.expectLocation(router, RouteNames.services);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ===========================================================================
  // FLOW 5a — «Запропонувати категорію» ×3 → ONE dialog; «Надіслати» ×3 →
  // ONE category request.
  // ===========================================================================
  testWidgets(
    'INDEPENDENT_MASTER: the suggest-category entry tapped 3x opens ONE dialog, '
    'and «Надіслати» tapped 3x sends ONE category request',
    (tester) async {
      // The POST is HELD (see [_kHeld]) so the cross-frame re-taps below
      // land while it is in flight.
      final fb = FakeBackend(requestCategoryDelay: _kHeld);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await _openMyServicesViaNav(tester, router);

      await tester.tap(find.byKey(const Key('btn-create-service')));
      await tester.pumpUntilFound(find.byKey(const Key('btn-setup-close')));

      // UX assertion only: the dialog is an imperative `Navigator.push`, whose
      // `_cancelActivePointers` already absorbs taps 2 and 3 of a same-frame
      // burst (measured 2026-10-15 — not pinnable against `showDialogOnce`).
      // The CALL COUNT below is what pins the submit guard.
      final Finder suggestEntry = find.byKey(
        const Key('btn-setup-request-category'),
      );
      await tester.pumpUntilFound(suggestEntry.hitTestable());
      _rapidTaps(tester, suggestEntry);
      await tester.pumpUntilFound(
        find.byKey(const Key('btn-submit-suggest-category')),
      );
      await _pumpFrames(tester);
      expect(
        _mountedKey(const Key('btn-submit-suggest-category')),
        1,
        reason: 'three same-frame taps must open the category dialog ONCE',
      );

      await tester.enterText(
        find.byKey(const Key('field-category-request-name')),
        'Масаж обличчя',
      );
      await tester.pump();

      expect(fb.requestCategoryCalls, 0);
      final Finder submit = find.byKey(
        const Key('btn-submit-suggest-category'),
      );
      // Same-frame burst — pins `NeumorphicButton.onPressedAsync`'s
      // synchronous busy flag (the rebuild-based `_submitting` gate cannot
      // bite inside one frame).
      _rapidTaps(tester, submit);
      await _pumpFrames(tester, frames: 3);
      expect(fb.requestCategoryCalls, 1);
      // Slow network: the POST is still held — tap «Надіслати» again across
      // real frames. The dialog stays open while busy, so the button is on
      // screen for every re-tap.
      for (int i = 0; i < 2; i++) {
        expect(submit.hitTestable(), findsOneWidget);
        await tester.tap(submit.hitTestable());
        await _pumpFrames(tester, frames: 3);
      }
      await tester.pumpUntilGone(
        find.byKey(const Key('btn-submit-suggest-category')),
      );
      await _pumpFrames(tester);
      expect(
        fb.requestCategoryCalls,
        1,
        reason:
            'a same-frame burst plus re-taps while the request is in flight '
            'must send ONE request',
      );
      expect(fb.lastCategoryRequestBody?['displayName'], 'Масаж обличчя');
      // The dialog closed and the setup screen underneath survived — the
      // extra taps did not pop past it.
      expect(_mounted(ServiceSetupScreen), 1);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ===========================================================================
  // FLOW 2a — CLIENT slot picker: «Далі» on the time step ×3 → ONE confirm
  // route; «Записатись» ×3 → every create carries the SAME idempotency key.
  // ===========================================================================
  testWidgets(
    'CLIENT: the time-step CTA tapped 3x opens ONE confirm screen, and '
    '«Записатись» tapped 3x sends every create with ONE idempotency key',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.client;
        final repo = _RecordingAppointmentRepository();
        final GoRouter router = await AppHarness.boot(
          tester,
          fb,
          extraOverrides: <Object>[
            appointmentRepositoryProvider.overrideWithValue(repo),
          ],
        );
        await AppHarness.loginAs(tester, fb, UserRole.client);
        await AppHarness.settle(tester);

        // search (CLASSIC_MANICURE filter → pub-assign-1 arrives pre-checked)
        // → master card → «Записатись до майстра» → catalogue.
        await _reachSearchResults(tester, filterClassicManicure: true);
        final Finder masterCard = find.ancestor(
          of: find.byKey(const Key('favorite_master_master-aaa')),
          matching: find.byType(MasterResultCard),
        );
        await tester.tap(masterCard);
        await AppHarness.settle(tester);
        await tester.tap(find.byKey(const Key('public-master-book-cta')));
        await AppHarness.settle(tester);
        AppHarness.expectShellLocation(router, RouteNames.bookingNew);

        // catalogue «Далі» → date step → today → «Далі» → time step.
        await tester.tap(find.byKey(const Key('booking-summary-cta')));
        await AppHarness.settle(tester);
        expect(find.byType(SlotDateScreen), findsOneWidget);
        await tester.tapCalendarDay(kyivToday(() => kFixedNow).day);
        await AppHarness.settle(tester);
        await tester.tap(find.byKey(const Key('booking-summary-cta')));
        await AppHarness.settle(tester);
        expect(find.byType(SlotTimeScreen), findsOneWidget);

        final Finder chip = find
            .byWidgetPredicate((Widget w) => w is SlotChip && w.available)
            .first;
        await tester.ensureVisible(chip);
        await AppHarness.settle(tester);
        await tester.tap(chip);
        await AppHarness.settle(tester);

        // ── time-step «Далі» ×3 → ONE confirm route ─────────────────────────
        _rapidTaps(tester, find.byKey(const Key('booking-summary-cta')));
        await AppHarness.settle(tester);
        expect(
          _mounted(BookingConfirmScreen),
          1,
          reason:
              'three same-frame taps must push the confirm screen ONCE — each '
              'copy mints its own idempotency key, so a stacked duplicate is a '
              'duplicate booking after «back»',
        );

        // ── «Записатись» ×3 → ONE idempotency key ───────────────────────────
        // Phase 262 D5 (user-locked): the client-create path has NO
        // screen-owned double-submit guard, so a same-frame burst may reach
        // `createAppointment` more than once. The guarantee is the key: ONE
        // confirm screen (pinned above) = ONE `idempotencyKey`, so the server
        // dedupes every repeat into the same visit.
        _rapidTaps(tester, find.byKey(const Key('booking-confirm-submit-cta')));
        await AppHarness.settle(tester);
        expect(
          repo.requests,
          isNotEmpty,
          reason: '«Записатись» must reach createAppointment at least once',
        );
        expect(
          repo.requests
              .map((CreateAppointmentRequest r) => r.idempotencyKey)
              .toSet(),
          hasLength(1),
          reason:
              'every create from one confirm screen must carry the SAME '
              'idempotency key so the server dedupes the burst',
        );
        expect(
          repo.requests.map((CreateAppointmentRequest r) => r.masterId).toSet(),
          <String>{'master-aaa'},
        );
        AppHarness.expectShellLocation(router, RouteNames.bookingSuccess);
        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ===========================================================================
  // FLOW 2b — MASTER walk-in over the same slot picker + confirm screen, with
  // the REAL `POST` on the fake backend (`createStaffBookingCalls`).
  // ===========================================================================
  testWidgets(
    'INDEPENDENT_MASTER walk-in: the time-step CTA tapped 3x opens ONE confirm '
    'screen, and «Записати» tapped 3x sends ONE staff booking',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      fb.seedManyBookingsDataset(const <Map<String, dynamic>>[]);
      fb.availableSlotUtcStarts = const <(int, int)>[(7, 0)];
      await AppHarness.boot(tester, fb);
      final DateTime today = kyivToday(() => kFixedNow);
      _seedWorkingHours(fb, today);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      // «Мої записи» → «+» → guest step → service step.
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      await tester.tap(find.byKey(const Key('master-bookings-add')));
      await AppHarness.settle(tester);
      await tester.enterText(
        find.byKey(const Key('master-create-booking-first-name')),
        'Ірина',
      );
      await tester.enterText(
        find.byKey(const Key('master-create-booking-last-name')),
        'Шевченко',
      );
      await tester.enterText(
        find.byKey(const Key('master-create-booking-phone')),
        '0501234567',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('master-create-booking-client-next')),
      );
      await AppHarness.settle(tester);
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('mcb_service_card_assign-1')),
      );
      await tester.tap(find.byKey(const Key('mcb_service_card_assign-1')));
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);

      // date → time → slot.
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(Key('booking-calendar-day-${today.day}')),
      );
      await tester.tapCalendarDay(today.day);
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);
      expect(find.byType(SlotTimeScreen), findsOneWidget);
      final Finder chip = find
          .byWidgetPredicate((Widget w) => w is SlotChip && w.available)
          .first;
      await tester.ensureVisible(chip);
      await AppHarness.settle(tester);
      await tester.tap(chip);
      await AppHarness.settle(tester);

      // ── time-step «Далі» ×3 → ONE confirm route ───────────────────────────
      _rapidTaps(tester, find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);
      expect(_mounted(BookingConfirmScreen), 1);

      // ── submit ×3 → ONE POST on the fake backend ──────────────────────────
      expect(fb.createStaffBookingCalls, 0);
      _rapidTaps(tester, find.byKey(const Key('booking-confirm-submit-cta')));
      await AppHarness.settle(tester);
      expect(
        fb.createStaffBookingCalls,
        1,
        reason: 'three same-frame submit taps must send ONE walk-in booking',
      );
      expect(fb.lastStaffBookingRequestBody?['masterServiceIds'], <String>[
        'assign-1',
      ]);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ===========================================================================
  // FLOW 3 — CLIENT salon: time-step «Підтвердити» ×3 → ONE confirm route;
  // «Записатись» ×3 → ONE `submitVisit` per appointment.
  // ===========================================================================
  testWidgets(
    'CLIENT salon booking: «Підтвердити» tapped 3x opens ONE confirm screen, '
    'and «Записатись» tapped 3x submits ONE visit per master',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.client;
        final repo = _RecordingAppointmentRepository();
        final GoRouter router = await AppHarness.boot(
          tester,
          fb,
          extraOverrides: <Object>[
            appointmentRepositoryProvider.overrideWithValue(repo),
          ],
        );
        await AppHarness.loginAs(tester, fb, UserRole.client);
        await AppHarness.settle(tester);

        await _reachSearchResults(tester);
        await tester.tap(find.byKey(const Key('salon_card_salon-xyz')));
        await AppHarness.settle(tester);
        await tester.tap(find.byKey(const Key('salon-book-cta')));
        await AppHarness.settle(tester);
        AppHarness.expectShellLocation(router, RouteNames.salonBookingServices);

        // One service → its one bookable master (master-ccc).
        await tester.tap(
          find.byKey(const Key('salon_booking_service_tile_salon-svc-shared')),
        );
        await AppHarness.settle(tester);
        await tester.tap(find.byKey(const Key('booking-summary-cta')));
        await AppHarness.settle(tester);
        AppHarness.expectShellLocation(router, RouteNames.salonBookingMasters);
        await tester.tap(
          find.byKey(const Key('salon_booking_master_row_master-ccc')),
        );
        await AppHarness.settle(tester);
        await tester.tap(find.byKey(const Key('salon-assign-confirm-cta')));
        await AppHarness.settle(tester);
        expect(find.byType(SalonTimeScreen), findsOneWidget);

        // date → «Далі» (TIME phase) → slot.
        final DateTime today = kyivToday(() => kFixedNow);
        final Finder slide = find.byKey(
          const Key('salon-schedule-page-master-ccc'),
          skipOffstage: false,
        );
        await tester.tapCalendarDay(today.day, within: slide);
        await AppHarness.settle(tester);
        await tester.tap(find.byKey(const Key('schedule-confirm-cta')));
        await AppHarness.settle(tester);
        final String morningIso = DateTime.utc(
          today.year,
          today.month,
          today.day,
          7,
        ).toIso8601String();
        final Finder slot = find.descendant(
          of: slide,
          matching: find.byKey(Key('salon-slot-chip-$morningIso')),
        );
        await tester.ensureVisible(slot);
        await AppHarness.settle(tester);
        await tester.tap(slot);
        await AppHarness.settle(tester);

        // ── «Підтвердити» ×3 → ONE confirm route ────────────────────────────
        _rapidTaps(tester, find.byKey(const Key('schedule-confirm-cta')));
        await AppHarness.settle(tester);
        AppHarness.expectShellLocation(router, RouteNames.salonBookingConfirm);
        expect(
          _mounted(SalonBookingConfirmScreen),
          1,
          reason: 'three same-frame «Підтвердити» taps must push ONE confirm',
        );
        expect(repo.requests, isEmpty);

        // ── «Записатись» ×3 → ONE submitVisit for master-ccc ────────────────
        _rapidTaps(tester, find.byKey(const Key('salon-confirm-submit-cta')));
        await AppHarness.settle(tester);
        expect(
          repo.callsFor('master-ccc'),
          1,
          reason:
              'three same-frame «Записатись» taps must submit the appointment '
              'ONCE',
        );
        expect(repo.requests, hasLength(1));
        AppHarness.expectShellLocation(router, RouteNames.salonBookingSuccess);
        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ===========================================================================
  // FLOW 4 — PROVIDER booking detail: «Завершити» / «Скасувати» on a SLOW
  // network. booking-1 is underway on the injected clock's day, so BOTH
  // actions show.
  //
  // WHAT PINS THE GUARD. The same-frame burst on the CTA / dialog confirm is a
  // UX assertion only: `Navigator.push` / `pop` call `_cancelActivePointers`,
  // which absorbs every further pointer until the next frame, so Flutter
  // itself drops taps 2 and 3 there (measured 2026-10-15: removing both
  // the close guards and `showDialogOnce` left the burst green). The per-
  // action guards `_completeInFlight` / `_declineInFlight` (each drops only a
  // repeat of its OWN action) exist for the CROSS-FRAME case: the dialog is
  // confirmed and closed, the PATCH is still in flight, and the master taps
  // the CTA again. The fake HOLDS the PATCH ([_kHeld]); [_retapWhileInFlight] re-taps
  // with real frames in between and confirms any dialog that reopens. The
  // CALL COUNT after release is the assertion that pins those guards.
  // ===========================================================================
  FakeBackend underwayBookingBackend() {
    final fb = FakeBackend(
      completeBookingDelay: _kHeld,
      declineBookingDelay: _kHeld,
    )..currentRole = UserRole.independentMaster;
    final DateTime start = kFixedNow.subtract(const Duration(hours: 1));
    fb.bookingStartsAt = start.toIso8601String();
    fb.bookingEndsAt = start.add(const Duration(hours: 4)).toIso8601String();
    return fb;
  }

  testWidgets(
    'PROVIDER: «Завершити» re-tapped while the complete is still in flight '
    'sends ONE complete (and a same-frame burst opens ONE dialog)',
    (tester) async {
      final fb = underwayBookingBackend();
      await AppHarness.boot(tester, fb);
      _seedWorkingHours(fb, kyivToday(() => kFixedNow));
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await _openMasterBookingDetailViaNav(tester);

      const Key cta = Key('booking-detail-complete');
      const Key dialog = Key('complete-booking-dialog');
      const Key confirm = Key('complete-booking-confirm');

      // UX assertion (framework-backed, see the FLOW 4 header).
      _rapidTaps(tester, find.byKey(cta));
      await _pumpFrames(tester, frames: 5);
      expect(_mountedKey(dialog), 1);

      // Confirm → the dialog closes, the PATCH is dispatched and HELD.
      _rapidTaps(tester, find.byKey(confirm));
      await _pumpFrames(tester, frames: 3);
      expect(_mountedKey(dialog), 0);
      expect(fb.completeBookingCalls, 1);

      // Slow network + impatient master: re-tap while the PATCH is held.
      final int reopened = await _retapWhileInFlight(
        tester,
        cta: cta,
        confirm: confirm,
      );

      // Release: wait for the held PATCH to land (footer goes terminal).
      await AppHarness.pumpUntilGone(
        tester,
        find.byKey(cta),
        timeout: const Duration(seconds: 15),
      );
      expect(
        fb.completeBookingCalls,
        1,
        reason:
            'a «Завершити» re-tap while the first complete is still in flight '
            'must not open a second dialog or send a second PATCH '
            '(`_completeInFlight`)',
      );
      expect(reopened, 0, reason: 'no dialog may reopen while in flight');
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  testWidgets(
    'PROVIDER: «Скасувати» re-tapped while the decline is still in flight '
    'sends ONE decline (and a same-frame burst opens ONE dialog)',
    (tester) async {
      final fb = underwayBookingBackend();
      await AppHarness.boot(tester, fb);
      _seedWorkingHours(fb, kyivToday(() => kFixedNow));
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await _openMasterBookingDetailViaNav(tester);

      const Key cta = Key('booking-detail-decline');
      const Key dialog = Key('decline-booking-dialog');
      const Key confirm = Key('decline-booking-confirm');

      // UX assertion (framework-backed, see the FLOW 4 header).
      _rapidTaps(tester, find.byKey(cta));
      await _pumpFrames(tester, frames: 5);
      expect(_mountedKey(dialog), 1);
      await tester.enterText(
        find.byKey(const Key('cancel-booking-note-field')),
        'Client rescheduled elsewhere.',
      );
      await tester.pump();

      _rapidTaps(tester, find.byKey(confirm));
      await _pumpFrames(tester, frames: 3);
      expect(_mountedKey(dialog), 0);
      expect(fb.declineBookingCalls, 1);

      final int reopened = await _retapWhileInFlight(
        tester,
        cta: cta,
        confirm: confirm,
      );

      await AppHarness.pumpUntilGone(
        tester,
        find.byKey(cta),
        timeout: const Duration(seconds: 15),
      );
      expect(
        fb.declineBookingCalls,
        1,
        reason:
            'a «Скасувати» re-tap while the first decline is still in flight '
            'must not send a second PATCH (`_declineInFlight`)',
      );
      expect(reopened, 0, reason: 'no dialog may reopen while in flight');
      expect(fb.lastDeclineComment, 'Client rescheduled elsewhere.');
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ===========================================================================
  // FLOW 5b — CLIENT leave-review: «Залишити відгук» ×3 → ONE review screen;
  // submit ×3 → ONE POST /reviews.
  // ===========================================================================
  testWidgets(
    'CLIENT: «Залишити відгук» tapped 3x opens ONE review screen, and its '
    'submit tapped 3x sends ONE review',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..bookingStatus = 'COMPLETED'
        ..bookingCanReview = true;
      await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);

      await tester.tap(find.byKey(const Key('client-nav-tile-3')));
      await AppHarness.settle(tester);
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(MyBookingsScreen)),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(MyBookingsTabBar),
          matching: find.text(l10n.myBookingsTabPast),
        ),
      );
      await AppHarness.settle(tester);
      await tester.tap(find.byType(BookingCard));
      await AppHarness.settle(tester);
      expect(find.byType(BookingDetailScreen), findsOneWidget);

      _rapidTaps(tester, find.byKey(const Key('booking-detail-leave-review')));
      await AppHarness.settle(tester);
      expect(
        _mounted(LeaveReviewScreen),
        1,
        reason: 'three same-frame taps must push the review screen ONCE',
      );

      await tester.tap(find.byKey(const ValueKey<String>('review-star-5')));
      await AppHarness.settle(tester);
      expect(fb.createReviewCalls, 0);
      _rapidTaps(tester, find.byKey(const Key('leave-review-submit')));
      await AppHarness.settle(tester);
      expect(
        fb.createReviewCalls,
        1,
        reason: 'three same-frame submit taps must send ONE review',
      );
      expect(fb.lastReviewRating, 5);
      expect(_mounted(LeaveReviewScreen), 0);
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
