// Phase 14.2 — Widget tests for BookingConfirmScreen + BookingSuccessScreen.
//
// Both screens are covered in ONE file, mirroring the Phase 14.1 precedent
// (`slot_picker_test.dart` covers SlotDateScreen + SlotTimeScreen together)
// since these two screens are the two halves of a single "confirm → success"
// step and share the exact same fixtures.
//
// Covers the phase doc's acceptance criteria:
//   1. The "Записатись" CTA calls `BookingRepository.createBooking` with a
//      fresh UUID v4 idempotency key.
//   2. A 409 (ConflictFailure) shows a SnackBar, does NOT navigate away, and
//      the confirm screen stays fully interactive.
//   3. A retry after a failure generates a NEW idempotency key (never reused).
//   4. Success navigates (pushReplacement) to /booking/success.
//   5. BookingSuccessScreen blocks back navigation (PopScope(canPop: false)).
//
// Strategy: mounts a test-local GoRouter with `/booking/confirm` and
// `/booking/success` (mirroring `slot_picker_test.dart`'s `_router()`
// pattern), overriding `publicMasterProfileProvider` (hand-fixture, no real
// Dio call) and `bookingRepositoryProvider` with a hand-written fake — no
// mocktail, matching the `_FakeSlotRepository` precedent in this same
// feature's Phase 14.1 test file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_success_args.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:beautica_mobile/features/booking/domain/working_day.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_summary_cards.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _kMaster = Master(
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

const _kService = MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Манікюр з покриттям',
  durationMinutes: 90,
  priceMin: 500,
  priceDisplay: '500 грн',
  category: 'NAILS',
);

BookingConfirmArgs _confirmArgs() => BookingConfirmArgs(
  masterId: _kMaster.id,
  serviceId: _kService.id,
  startAt: DateTime(2026, 7, 20, 14),
);

Booking _bookingFixture() => Booking(
  id: 'booking-1',
  masterId: _kMaster.id,
  masterFirstName: _kMaster.firstName,
  masterLastName: _kMaster.lastName,
  masterType: 'INDEPENDENT_MASTER',
  serviceId: _kService.id,
  serviceName: _kService.name,
  durationMinutes: _kService.durationMinutes,
  price: _kService.priceMin,
  startAt: DateTime(2026, 7, 20, 14),
  endAt: DateTime(2026, 7, 20, 15, 30),
  status: BookingStatus.pending,
  canReview: false,
);

/// Records every [createBooking] call (request + resulting idempotency key)
/// so the "fresh key per submit" criterion can be asserted directly, and
/// either returns [bookingToReturn] or throws [errorToThrow] when set —
/// mirrors `slot_picker_test.dart`'s `_FakeSlotRepository`.
class _FakeBookingRepository implements BookingRepository {
  _FakeBookingRepository({this.bookingToReturn, this.errorToThrow});

  Booking? bookingToReturn;
  Object? errorToThrow;
  final List<CreateBookingRequest> requests = <CreateBookingRequest>[];

  @override
  Future<Booking> createBooking(CreateBookingRequest req) async {
    requests.add(req);
    final Object? err = errorToThrow;
    if (err != null) throw err;
    return bookingToReturn!;
  }

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required BookingStatus? status,
    required int page,
    int size = kBookingsPageSize,
  }) => throw UnimplementedError();

  @override
  Future<Booking> getBookingById(String id) => throw UnimplementedError();

  @override
  Future<void> cancelBooking(String id, {String? reason}) =>
      throw UnimplementedError();

  @override
  Future<Booking> rescheduleBooking(String id, DateTime newStartAt) =>
      throw UnimplementedError();
}

/// mobile-qa Part 2 — minimal fake [SlotRepository] for the real
/// Date→Time→Confirm push-chain test below. Always resolves every requested
/// day as working (mirrors `slot_picker_test.dart`'s `_FakeSlotRepository`
/// default), and always returns the SAME fixed [slotsToReturn] list
/// regardless of which date was tapped — this test only cares about the
/// navigation/Hero chain, not slot-fetch fixture variety, so it deliberately
/// skips that file's richer gating/error knobs.
class _FakeChainSlotRepository implements SlotRepository {
  _FakeChainSlotRepository(this.slotsToReturn);

  final List<BookingSlot> slotsToReturn;

  @override
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required String serviceId,
    required DateTime date,
    CancelToken? cancelToken,
  }) async => slotsToReturn;

  @override
  Future<List<WorkingDay>> getWorkingDays({
    required String masterId,
    required DateTime from,
    required DateTime to,
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

/// mobile-qa Part 2 — router mirroring `app_router.dart`'s REAL nesting for
/// the full booking flow: `bookingSlots` → nested `time` → (pushed)
/// `bookingConfirm` → (pushed) `bookingSuccess`, all rendering the REAL
/// production screens (unlike `slot_picker_test.dart`'s `_router()`, which
/// stubs `bookingConfirm` as plain text). Closes the gap the build-verifier
/// flagged: every existing test either drives Date→Time (real push, stub
/// confirm) or mounts `BookingConfirmScreen` directly at the router's initial
/// location (no real push from Time) — this router lets a single test drive
/// the REAL push all the way from Date through to Confirm, exercising the
/// 3rd leg of the `master-strip-<id>` Hero chain end-to-end.
GoRouter _slotToConfirmRouter() => GoRouter(
  // A dummy `/root` initial location — mirrors `_router()` above (and
  // production, where `bookingSlots` is always PUSHED with a
  // `BookingSlotPickerArgs` extra, never used as the router's own initial
  // location). Building `bookingSlots` as the initial location would
  // null-check-crash on `state.extra!` before the test ever gets to call
  // `router.push(...)` with real args.
  initialLocation: '/root',
  routes: <RouteBase>[
    GoRoute(
      path: '/root',
      builder: (context, state) => const SizedBox.shrink(),
    ),
    GoRoute(
      path: RouteNames.bookingSlots,
      builder: (context, state) =>
          SlotDateScreen(args: state.extra! as BookingSlotPickerArgs),
      routes: <RouteBase>[
        GoRoute(
          path: 'time',
          builder: (context, state) =>
              SlotTimeScreen(args: state.extra! as BookingSlotPickerArgs),
        ),
      ],
    ),
    GoRoute(
      path: RouteNames.bookingConfirm,
      builder: (context, state) =>
          BookingConfirmScreen(args: state.extra! as BookingConfirmArgs),
    ),
    GoRoute(
      path: RouteNames.bookingSuccess,
      builder: (context, state) =>
          BookingSuccessScreen(args: state.extra! as BookingSuccessArgs),
    ),
  ],
);

/// Test-local router mirroring `app_router.dart`'s bookingConfirm →
/// bookingSuccess shape, rendering the REAL production screens.
///
/// A dummy `/root` initial location is registered UNDERNEATH both booking
/// routes (mirroring how, in the real app, `/booking/confirm` is always
/// PUSHED on top of the slot picker, never the router's own initial
/// location) so `context.pop()` from the confirm screen's back button has
/// somewhere to land, and so the initial pump never has to build a booking
/// route's `state.extra!` before a test has supplied one — both booking
/// routes are only ever reached via an explicit `router.push(...)` call.
/// [RouteNames.clientHome] is registered as a bare stub destination so the
/// success screen's «На головну» `context.go(...)` call resolves to a real
/// route instead of throwing (go_router has no matching-route fallback).
/// [RouteNames.clientBookings] is also registered — the success screen no
/// longer navigates there itself (its «Мої записи» CTA was removed, see
/// `booking_success_screen.dart`'s file header DEVIATION note), but the
/// stub is kept anyway since the route mirrors `app_router.dart`'s real
/// shape and stays harmless dead weight rather than a thing worth pruning.
GoRouter _router() => GoRouter(
  initialLocation: '/root',
  routes: <RouteBase>[
    GoRoute(
      path: '/root',
      builder: (context, state) => const SizedBox.shrink(),
    ),
    GoRoute(
      path: RouteNames.clientBookings,
      builder: (context, state) => const SizedBox.shrink(),
    ),
    GoRoute(
      path: RouteNames.clientHome,
      builder: (context, state) => const SizedBox.shrink(),
    ),
    GoRoute(
      path: RouteNames.bookingConfirm,
      builder: (context, state) =>
          BookingConfirmScreen(args: state.extra! as BookingConfirmArgs),
    ),
    GoRoute(
      path: RouteNames.bookingSuccess,
      builder: (context, state) =>
          BookingSuccessScreen(args: state.extra! as BookingSuccessArgs),
    ),
  ],
);

/// Reads the router's CURRENT top-of-stack location. `GoRouter.push()`
/// (unlike `.go()`) does not update `currentConfiguration.uri` the same way
/// (it deliberately preserves the underlying "URL" for a stacked/modal-style
/// push — confirmed empirically: `matches` correctly grows while `.uri`
/// stays put), so this reads the LAST entry of `.matches` instead, which
/// reflects the actual top-of-stack screen for both `.go()` and `.push()`.
String locationOf(GoRouter router) =>
    router.routerDelegate.currentConfiguration.matches.last.matchedLocation;

void main() {
  group('BookingConfirmScreen', () {
    Future<GoRouter> pump(
      WidgetTester tester,
      _FakeBookingRepository fake,
    ) async {
      final GoRouter router = _router();
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          bookingRepositoryProvider.overrideWith((_) => fake),
          publicMasterProfileProvider(
            _kMaster.id,
          ).overrideWith((ref) => (_kMaster, const <MasterService>[_kService])),
        ],
      );
      unawaited(router.push(RouteNames.bookingConfirm, extra: _confirmArgs()));
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('renders the master + service summary once data resolves', (
      tester,
    ) async {
      final fake = _FakeBookingRepository(bookingToReturn: _bookingFixture());
      await pump(tester, fake);

      expect(find.byType(BookingConfirmScreen), findsOneWidget);
      // i18n-finder-ok: master name is fixture data (_kMaster), not translated UI copy.
      expect(find.text('Олена Ковальчук'), findsOneWidget);
      // i18n-finder-ok: service name is fixture data (_kService), not translated UI copy.
      expect(find.text('Манікюр з покриттям'), findsOneWidget);
    });

    // mobile-qa regression — `bookingConfirmScreenTitle`'s Ukrainian ARB
    // value has flip-flopped between "Підтвердження запису" and
    // "Підтвердження" (`lib/l10n/app_uk.arb`); either variant looks like a
    // superficially reasonable Ukrainian title, so a change here would
    // otherwise slip past review unnoticed. Pins the EXACT locked literal —
    // a deliberate, narrow exception to the "find by Key, not translated
    // string" convention (mobile-qa's own M2 guidance), because the whole
    // point of this test is to catch the ARB value itself silently
    // reverting: asserting via `l10n.bookingConfirmScreenTitle` would just
    // re-read whatever the ARB currently says and could never fail.
    testWidgets(
      'renders the exact locked Ukrainian title "Підтвердження" in the top '
      'bar',
      (tester) async {
        final fake = _FakeBookingRepository(bookingToReturn: _bookingFixture());
        await pump(tester, fake);

        // (see the comment above for why this intentionally pins the raw
        // ARB literal instead of a Key/AppLocalizations lookup)
        // i18n-finder-ok: intentional ARB-lock exception, literal ARB value under test.
        expect(find.text('Підтвердження'), findsOneWidget);
      },
    );

    // mobile-qa Part 1 — `BookingSummaryCards`'s master card was migrated
    // from a deleted bespoke `_MasterHeader` to the SAME `MasterStrip(
    // showRole: true, showRating: true)` used by the Step 2a/2b slot-picker
    // screens (`booking_summary_cards.dart`), but nothing asserted the actual
    // role/rating CONTENT rendered by this screen's card — only the master's
    // name (see the test above). Scoped to the `MasterStrip` descendant so a
    // coincidental match elsewhere on screen can't false-pass this.
    testWidgets(
      'shows the master\'s role label and ★rating(reviewCount) inside the '
      'master card',
      (tester) async {
        final fake = _FakeBookingRepository(bookingToReturn: _bookingFixture());
        await pump(tester, fake);

        final Finder masterStrip = find.byType(MasterStrip);
        expect(masterStrip, findsOneWidget);

        final l10n = AppLocalizations.of(tester.element(masterStrip));
        final String roleLabel = masterRoleLabel(_kMaster.type, l10n);
        expect(
          find.descendant(of: masterStrip, matching: find.text(roleLabel)),
          findsOneWidget,
          reason:
              'showRole:true must render masterRoleLabel(type, l10n) — for '
              'this fixture (independentMaster) that is '
              'l10n.masterRoleIndependent',
        );

        final String ratingLabel = _kMaster.avgRating.toStringAsFixed(1);
        expect(
          find.descendant(of: masterStrip, matching: find.text(ratingLabel)),
          findsOneWidget,
          reason: 'showRating:true must render avgRating.toStringAsFixed(1)',
        );

        expect(
          find.descendant(
            of: masterStrip,
            matching: find.text('(${_kMaster.reviewCount})'),
          ),
          findsOneWidget,
          reason:
              'reviewCount (47) is > 0 for this fixture, so the parenthetical '
              'review-count suffix must render alongside the rating',
        );
      },
    );

    // mobile-qa regression — the success screen's details card opts into
    // `NeumorphicCard.showBorder` (its card fill matches the surrounding
    // background); the confirm screen's own card sits on a different
    // background and must stay unaffected. Pin the confirm-side default here
    // so a future shared-default change can't silently opt this screen in
    // too.
    //
    // Also pins `compactText` (a SEPARATE flag from `showBorder`, added
    // alongside the same fix — see `BookingSummaryCards.compactText`'s doc):
    // the confirm screen must stay at the roomier default text size too,
    // confirming the isolation the dev agent verified manually.
    testWidgets(
      "BookingSummaryCards' showBorder and compactText are NOT set on the "
      'confirm screen',
      (tester) async {
        final fake = _FakeBookingRepository(bookingToReturn: _bookingFixture());
        await pump(tester, fake);

        final BookingSummaryCards cards = tester.widget<BookingSummaryCards>(
          find.byType(BookingSummaryCards),
        );
        expect(
          cards.showBorder,
          isFalse,
          reason:
              "BookingConfirmScreen's BookingSummaryCards call site must "
              'leave showBorder at its default (false) — only the success '
              'screen opts in.',
        );
        expect(
          cards.compactText,
          isFalse,
          reason:
              "BookingConfirmScreen's BookingSummaryCards call site must "
              'leave compactText at its default (false) — only the success '
              'screen opts in.',
        );
      },
    );

    testWidgets(
      '«Записатись» calls createBooking with a fresh UUID v4 idempotency key '
      'and navigates to /booking/success on success',
      (tester) async {
        final fake = _FakeBookingRepository(bookingToReturn: _bookingFixture());
        final router = await pump(tester, fake);

        await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
        await tester.pumpAndSettle();

        expect(fake.requests, hasLength(1));
        final CreateBookingRequest sent = fake.requests.single;
        expect(sent.masterId, _kMaster.id);
        expect(sent.serviceId, _kService.id);
        // A syntactically valid UUID v4: 8-4-4-4-12 hex groups.
        expect(
          sent.idempotencyKey,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        );

        expect(locationOf(router), equals(RouteNames.bookingSuccess));
        expect(find.byType(BookingSuccessScreen), findsOneWidget);
      },
    );

    testWidgets(
      'a 409 conflict shows a SnackBar, does not navigate away, and the '
      'screen stays interactive for a retry',
      (tester) async {
        final fake = _FakeBookingRepository(
          bookingToReturn: _bookingFixture(),
          errorToThrow: const ConflictFailure(),
        );
        final router = await pump(tester, fake);

        await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
        await tester.pumpAndSettle();

        // Still on the confirm screen — no crash, no navigation.
        expect(locationOf(router), equals(RouteNames.bookingConfirm));
        expect(find.byType(BookingConfirmScreen), findsOneWidget);
        expect(find.byType(SnackBar), findsOneWidget);

        final l10n = AppLocalizations.of(
          tester.element(find.byType(BookingConfirmScreen)),
        );
        expect(find.text(l10n.errConflict), findsOneWidget);

        // The comment field is still editable — the screen never got stuck
        // mid-submit.
        await tester.enterText(
          find.byKey(const Key('booking-confirm-comment-field')),
          'Будь ласка, без запізнень',
        );
        await tester.pump();
        // i18n-finder-ok: arbitrary test-entered text (round-trip check), not translated UI copy.
        expect(find.text('Будь ласка, без запізнень'), findsOneWidget);

        // Retry with a fresh key — a DIFFERENT key than the failed attempt.
        fake.errorToThrow = null;
        await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
        await tester.pumpAndSettle();

        expect(fake.requests, hasLength(2));
        expect(
          fake.requests[1].idempotencyKey,
          isNot(equals(fake.requests[0].idempotencyKey)),
        );
        expect(locationOf(router), equals(RouteNames.bookingSuccess));
      },
    );

    testWidgets('an empty comment is sent as null, a non-empty comment is '
        'trimmed and forwarded', (tester) async {
      final fake = _FakeBookingRepository(bookingToReturn: _bookingFixture());
      await pump(tester, fake);

      await tester.enterText(
        find.byKey(const Key('booking-confirm-comment-field')),
        '  Прошу зателефонувати заздалегідь  ',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
      await tester.pumpAndSettle();

      expect(
        fake.requests.single.clientComment,
        'Прошу зателефонувати заздалегідь',
      );
    });

    testWidgets('the back button pops without submitting a booking', (
      tester,
    ) async {
      final fake = _FakeBookingRepository(bookingToReturn: _bookingFixture());
      await pump(tester, fake);

      await tester.tap(find.byKey(const Key('booking-confirm-back')));
      await tester.pumpAndSettle();

      expect(fake.requests, isEmpty);
    });
  });

  group('BookingSuccessScreen', () {
    BookingSuccessArgs successArgs() => BookingSuccessArgs(
      master: _kMaster,
      service: _kService,
      start: DateTime(2026, 7, 20, 14),
    );

    Future<GoRouter> pump(WidgetTester tester) async {
      final GoRouter router = _router();
      await tester.pumpRoutedApp(router);
      router.go(RouteNames.bookingSuccess, extra: successArgs());
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('renders the recap WITHOUT the master card', (tester) async {
      await pump(tester);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(BookingSuccessScreen)),
      );
      expect(find.text(l10n.bookingSuccessTitle), findsOneWidget);
      // i18n-finder-ok: service name is fixture data (_kService), not translated UI copy.
      expect(find.text('Манікюр з покриттям'), findsOneWidget);
      // The master's NAME (only shown on the master card) must be absent —
      // `showMasterCard: false` per the design.
      // i18n-finder-ok: master name is fixture data (_kMaster), not translated UI copy.
      expect(find.text('Олена Ковальчук'), findsNothing);

      // mobile-qa Part 3 — explicit widget-type assertion (not just the
      // absent-name proxy above): `BookingSummaryCards(showMasterCard:
      // false)` must render NO `MasterStrip` at all on this screen, unaffected
      // by the confirm screen's card now sharing the exact same widget.
      expect(find.byType(MasterStrip), findsNothing);
    });

    // mobile-qa Part 4 — the 112dp gradient-circle `_SuccessCheckBadge` was
    // replaced by a real 80dp `Lottie.asset('assets/lottie/success.json')`
    // animation (`_SuccessLottieBadge`), with a `frameBuilder` placeholder
    // shown while the composition decodes asynchronously
    // (`_SuccessBadgePlaceholder`). Both new private classes are
    // library-private (can't be `find.byType`'d directly from this test
    // file), so this asserts via the PUBLIC `Lottie` widget type instead —
    // proving the real animation is mounted, not merely "something renders
    // where the old badge used to be".
    //
    // The existing tests in this group already pump this screen via
    // `pumpAndSettle()` only, which would already fail on an uncaught
    // exception from a broken `frameBuilder` — but none of them ever
    // advances by a SINGLE frame first, so the `frameBuilder(composition:
    // null)` branch (the actual placeholder path, before the async decode
    // resolves) was never explicitly exercised or asserted on. This closes
    // that gap: pump exactly once (guaranteed to land before the
    // asset-decode microtask can possibly resolve), assert nothing throws,
    // then let `pumpAndSettle` finish the load and assert the real `Lottie`
    // widget is what's mounted at rest.
    testWidgets('renders the real Lottie success badge, and the frameBuilder '
        'placeholder path does not crash before the composition loads', (
      tester,
    ) async {
      final GoRouter router = _router();
      await tester.pumpRoutedApp(router);
      router.go(RouteNames.bookingSuccess, extra: successArgs());
      // One frame to let go_router's redirect/rebuild actually mount
      // BookingSuccessScreen (mirrors this file's other tests, which all
      // use pumpAndSettle for the same `.go()` call).
      await tester.pump();

      // A SECOND, immediate frame — still before the asset's async JSON
      // decode has any real chance to resolve — is the earliest point the
      // `frameBuilder(composition: null)` placeholder branch is guaranteed
      // to have rendered at least once.
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason:
            'the frameBuilder placeholder path (composition still null) '
            'must not throw or crash the widget tree',
      );
      expect(find.byType(BookingSuccessScreen), findsOneWidget);

      // Let the composition finish loading and every staggered reveal
      // animation settle.
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason:
            'the swap from placeholder to the real animation must not '
            'hang or throw once the composition resolves',
      );

      expect(
        find.byType(Lottie),
        findsOneWidget,
        reason:
            'BookingSuccessScreen must mount a real Lottie widget for its '
            'success badge — not the old gradient-circle '
            '`_SuccessCheckBadge` shape it replaced',
      );

      // The 80dp badge size is a locked, deliberate deviation from the
      // approved preview's 112dp slot (see the screen's file header) — not
      // an arbitrary implementation detail. Pin the rendered size so a
      // future accidental edit to `_SuccessLottieBadge._size` (which is
      // library-private and can't be asserted on directly) doesn't silently
      // drift this product decision without any test noticing.
      expect(
        tester.getSize(find.byType(Lottie)),
        const Size(80, 80),
        reason:
            'the success badge must render at the locked 80dp size, not '
            'the approved preview\'s 112dp slot',
      );
    });

    // mobile-qa regression — Part 3: the success screen's details card is
    // the ONE call site that opts into `NeumorphicCard.showBorder` (its card
    // fill exactly matches `Scaffold.backgroundColor`, so the extruded
    // shadow alone doesn't read as a distinct shape — see
    // `booking_success_screen.dart`'s comment at the `BookingSummaryCards`
    // call site). Distinguishes this screen's wiring from the confirm
    // screen's (asserted separately, above, as `isFalse`).
    //
    // Also pins `compactText: true` — the success screen's second, DELIBERATELY
    // SEPARATE opt-in (shrinks the recap's text a further notch on top of
    // `dense`'s spacing tightening — see `BookingSummaryCards.compactText`'s
    // doc for why it's not folded into `dense`), confirming the confirm
    // screen stays isolated from BOTH new flags, not just `showBorder`.
    testWidgets(
      "BookingSummaryCards' showBorder and compactText are wired to true on "
      'the success screen',
      (tester) async {
        await pump(tester);

        final BookingSummaryCards cards = tester.widget<BookingSummaryCards>(
          find.byType(BookingSummaryCards),
        );
        expect(
          cards.showBorder,
          isTrue,
          reason:
              "BookingSuccessScreen's BookingSummaryCards call site must "
              'pass showBorder: true — its card sits on the same '
              'BrandColors.base as the Scaffold background.',
        );
        expect(
          cards.compactText,
          isTrue,
          reason:
              "BookingSuccessScreen's BookingSummaryCards call site must "
              'pass compactText: true alongside showBorder: true and '
              'dense: true.',
        );
      },
    );

    // mobile-qa regression — Part 3 (subline): `bookingSuccessSubline`
    // dropped from the shared VelvetText.body() default size down to an
    // explicit `fontSize: 13`. Pin the rendered TextStyle so a future revert
    // (or an accidental copy-paste of a different body style) is caught.
    testWidgets('subline text renders at fontSize: 13', (tester) async {
      await pump(tester);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(BookingSuccessScreen)),
      );
      final Text subline = tester.widget<Text>(
        find.text(l10n.bookingSuccessSubline),
      );
      expect(
        subline.style?.fontSize,
        13.0,
        reason:
            'bookingSuccessSubline must render at fontSize: 13, not the '
            'shared VelvetText.body() default.',
      );
    });

    // mobile-qa regression — Part 4: the Lottie badge's controller duration
    // is deliberately stretched to 1.4x the raw composition duration once
    // `onLoaded` fires (see `_SuccessLottieBadge.onLoaded`'s comment — "do
    // not fix this back to 1x"). The raw duration is computed independently
    // here straight from the asset's frame-rate / in-point / out-point (NOT
    // by re-deriving it through the same `LottieComposition` the widget
    // itself loads), so this doesn't just re-assert the source file's own
    // arithmetic against itself.
    testWidgets(
      'lottie controller duration is stretched to 1.4x the raw composition '
      'duration',
      (tester) async {
        await pump(tester);

        final Lottie lottie = tester.widget<Lottie>(find.byType(Lottie));
        // `Lottie.controller` is typed `Animation<double>?`, but the screen
        // always passes its own `AnimationController` (`_lottieController`,
        // whose `.duration` is what `onLoaded` stretches) — cast to reach it.
        final AnimationController? actualController =
            lottie.controller as AnimationController?;
        final Duration? actualDuration = actualController?.duration;
        expect(actualDuration, isNotNull);

        // `File.readAsString()` performs REAL disk I/O — `testWidgets` runs
        // the test body in flutter_test's fake-async zone, which never drains
        // the real event loop, so a bare `await` here hangs until the
        // per-test timeout (confirmed empirically: this previously hung for
        // the full 10 minutes). `runAsync` briefly switches to the real zone
        // so the I/O future actually resolves.
        final String? raw = await tester.runAsync(
          () => File('assets/lottie/success.json').readAsString(),
        );
        expect(raw, isNotNull);
        final Map<String, dynamic> json =
            jsonDecode(raw!) as Map<String, dynamic>;
        final double frameRate = (json['fr'] as num).toDouble();
        final double inPoint = (json['ip'] as num).toDouble();
        final double outPoint = (json['op'] as num).toDouble();
        final double rawDurationMs = (outPoint - inPoint) / frameRate * 1000;
        final double expectedStretchedMs = rawDurationMs * 1.4;

        expect(
          actualDuration!.inMicroseconds / 1000,
          closeTo(expectedStretchedMs, 5),
          reason:
              'onLoaded must set controller.duration = composition.duration '
              '* 1.4 — expected ~${expectedStretchedMs.toStringAsFixed(1)}ms '
              '(raw ~${rawDurationMs.toStringAsFixed(1)}ms x1.4), got '
              '${(actualDuration.inMicroseconds / 1000).toStringAsFixed(1)}ms.',
        );
        // Sanity: definitely NOT left at the raw (1x) duration — a regression
        // that dropped the `* 1.4` stretch would still pass a loose
        // "duration is set" check but must fail this one.
        expect(
          (actualDuration.inMicroseconds / 1000 - rawDurationMs).abs(),
          greaterThan(100),
          reason:
              'controller.duration must be measurably slower than the raw '
              'composition duration, not left at 1x.',
        );
      },
    );

    testWidgets('blocks back navigation (PopScope canPop: false)', (
      tester,
    ) async {
      await pump(tester);

      final PopScope popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
    });

    // mobile-qa regression (widget removal) — the preview shipped a second
    // pinned action («Мої записи» → RouteNames.clientBookings) alongside «На
    // головну»; it was removed at explicit user request (see
    // `booking_success_screen.dart`'s file header DEVIATION note).
    // `RouteNames.clientBookings` itself stays reachable from other entry
    // points (bottom nav / QuickLinksCard), so this only pins THIS screen's
    // surface: the old key is gone for good, and «На головну» is now the
    // screen's sole CTA — not just "no test happens to tap the old button
    // anymore."
    testWidgets(
      '«Мої записи» CTA was removed — «На головну» is the sole pinned CTA',
      (tester) async {
        await pump(tester);

        expect(
          find.byKey(const Key('booking-success-my-bookings-cta')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('booking-success-home-cta')),
          findsOneWidget,
        );
      },
    );

    testWidgets('«На головну» navigates to /home', (tester) async {
      final router = await pump(tester);

      await tester.tap(find.byKey(const Key('booking-success-home-cta')));
      await tester.pumpAndSettle();

      expect(locationOf(router), equals(RouteNames.clientHome));
    });
  });

  // mobile-qa Part 2 — build-verifier gap-fix: no existing test drove a REAL
  // Navigator push all the way from `SlotTimeScreen` into
  // `BookingConfirmScreen` (`slot_picker_test.dart`'s Date→Time push always
  // lands on a plain-text confirm STUB; this file's own confirm-screen tests
  // above mount `BookingConfirmScreen` directly at the router's initial
  // location, never via a push from Time). That gap matters here because
  // `BookingSummaryCards`'s master card is now wrapped in
  // `Hero(tag: 'master-strip-${master.id}')` on all THREE screens
  // (`SlotDateScreen`/`SlotTimeScreen` already were; `BookingConfirmScreen` is
  // the new 3rd leg) — safe by tag-adjacency reasoning (each push transition
  // only involves the two ROUTES actually participating in that flight, so a
  // 3-screen chain is no different from the already-covered 2-screen one),
  // but never exercised end-to-end. This test drives the real push chain and
  // pins BOTH halves of the acceptance bar: no Hero-tag-collision error
  // surfaces, and `MasterStrip` lands at the identical vertical offset on
  // all three screens (extending `slot_picker_test.dart`'s existing 2-screen
  // offset-parity test to the 3rd leg).
  group('Date → Time → Confirm real push chain (mobile-qa Part 2)', () {
    testWidgets(
      'pushing all the way from SlotDateScreen through SlotTimeScreen to a '
      'REAL BookingConfirmScreen renders the 3rd Hero leg with no '
      'tag-collision error, and MasterStrip stays at the same vertical '
      'offset on all three screens',
      (tester) async {
        final BookingSlot slot = BookingSlot(
          startAt: DateTime(2026, 7, 20, 10),
          endAt: DateTime(2026, 7, 20, 11),
          available: true,
        );
        final fakeSlots = _FakeChainSlotRepository(<BookingSlot>[slot]);
        const fakeProfile = (_kMaster, <MasterService>[_kService]);
        final router = _slotToConfirmRouter();
        final args = BookingSlotPickerArgs(
          masterId: _kMaster.id,
          master: _kMaster,
          services: const <MasterService>[_kService],
        );

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            slotRepositoryProvider.overrideWith((_) => fakeSlots),
            publicMasterProfileProvider(
              _kMaster.id,
            ).overrideWith((ref) => fakeProfile),
          ],
        );
        unawaited(router.push(RouteNames.bookingSlots, extra: args));
        await tester.pumpAndSettle();

        expect(find.byType(SlotDateScreen), findsOneWidget);
        final double dateOffset = tester
            .getTopLeft(
              find.descendant(
                of: find.byType(SlotDateScreen),
                matching: find.byType(MasterStrip),
              ),
            )
            .dy;

        // Leg 1: Date → Time (real push, mirrors `pumpTimeScreen` in
        // `slot_picker_test.dart`).
        final DateTime today = DateTime.now();
        await tester.tap(find.byKey(Key('booking-calendar-day-${today.day}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('booking-summary-cta')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(SlotTimeScreen), findsOneWidget);
        final double timeOffset = tester
            .getTopLeft(
              find.descendant(
                of: find.byType(SlotTimeScreen),
                matching: find.byType(MasterStrip),
              ),
            )
            .dy;

        // Leg 2: Time → Confirm — the NEW 3rd leg under test. Real push (via
        // the time screen's «Підтвердити» CTA), landing on the REAL
        // `BookingConfirmScreen` (not a stub).
        final Finder availableChip = find.byWidgetPredicate(
          (Widget w) => w is SlotChip && w.available,
        );
        expect(availableChip, findsOneWidget);
        await tester.tap(availableChip);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('booking-summary-cta')));
        await tester.pumpAndSettle();

        // No Hero-tag-collision (or any other) exception was thrown by the
        // push/flight — `pumpAndSettle` alone would already fail the test on
        // an unhandled `FlutterError`, but asserting `takeException()`
        // directly makes the "no collision" acceptance criterion explicit
        // rather than incidental.
        expect(tester.takeException(), isNull);

        expect(
          find.byType(BookingConfirmScreen),
          findsOneWidget,
          reason:
              'the CTA must have performed a REAL push to the real '
              'BookingConfirmScreen, not a stub',
        );
        final Finder confirmMasterStrip = find.descendant(
          of: find.byType(BookingConfirmScreen),
          matching: find.byType(MasterStrip),
        );
        expect(
          confirmMasterStrip,
          findsOneWidget,
          reason:
              'BookingConfirmScreen must render its own Hero-wrapped '
              'MasterStrip — the 3rd leg of the master-strip-<id> chain',
        );
        final double confirmOffset = tester.getTopLeft(confirmMasterStrip).dy;

        expect(
          confirmOffset,
          closeTo(timeOffset, 0.5),
          reason:
              'MasterStrip must land at the identical vertical offset on '
              'SlotTimeScreen and BookingConfirmScreen so the shared Hero '
              'never visibly jumps once the 2nd push transition settles — '
              'mirrors slot_picker_test.dart\'s Date/Time offset-parity '
              'assertion, extended to the 3rd screen.',
        );
        expect(confirmOffset, closeTo(dateOffset, 0.5));
      },
    );
  });
}
