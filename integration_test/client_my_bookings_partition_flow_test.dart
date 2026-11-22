// Phase 227 — «Мої записи» cutover to the backend's server-side `partition`
// (Phase 28.2/29.3). E2E: this is the ONLY test in the tree that proves the
// headline behaviour fix against a fake backend that actually IMPLEMENTS the
// partition semantics, plus the negative control for the rollout safety
// valve.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// `my_bookings_notifier_test.dart` and `my_bookings_screen_test.dart` are
// both mocked at the REPOSITORY boundary — a mock just returns whatever list
// the test hands it, regardless of what `partition` value was actually sent.
// They prove the CLIENT sends the right request and renders whatever comes
// back; neither can prove the RECLASSIFICATION itself, because neither has a
// backend that computes partition membership from a status+time predicate.
// The dev's own "sanity-check RED" (revert `partition:` in the notifier,
// watch a widget test fail) is weaker than it looks: removing `partition`
// makes the mocktail stub stop matching (`MissingStubError`), so the screen
// renders its error state and an unrelated anti-vacuity assertion fires
// first. That is coupling to "partition is on the wire", not proof of "an
// elapsed CONFIRMED booking is now classified as PAST".
//
// This file closes that gap with a `FakeBackend` extended
// (`integration_test/support/fake_backend.dart`,
// `[FakeBackend.backendSupportsPartition]` / `[FakeBackend._partitionOf]`)
// to implement the actual backend Phase 28.1/28.2 predicate:
//   - `CANCELLED`/`DECLINED` → CANCELLED
//   - `CONFIRMED` with `endsAt` on/after "now" → UPCOMING
//   - `CONFIRMED` elapsed, or `COMPLETED`/`NOT_COMPLETED` → PAST
// (see `docs/backend-phases/phase-217-28.2-bookings-me-partition-param.md`).
//
// Test 1 drives the real journey end-to-end: land on «Мої записи» → Майбутні
// shows only the genuinely-upcoming row → tap Минулі → the elapsed CONFIRMED
// row is there → tap it → the detail screen renders the read-only rebook
// affordances (existing `booking_detail_screen.dart:619` `isPast` branch —
// this file changes NOTHING about that screen).
//
// Test 2 is the negative control the phase doc calls for by name: "a test
// asserts that dropping `status` from the request makes an old-backend fake
// return an unfiltered list, so the reviewer can see what the valve is
// protecting against." The real `MyBookingsNotifier` never omits `status`
// (that is the whole point of the valve), so this test drives
// `BookingRepository.getMyBookings` DIRECTLY — the one legitimate way to
// construct the hypothetical "partition-only client" the valve defends
// against — and contrasts three scenarios against the SAME 4-row fixture:
//   (a) modern backend, partition-only request → correctly scoped (valve
//       irrelevant — a modern backend needs no defending).
//   (b) OLD backend, partition-only request → the ENTIRE unfiltered dataset
//       comes back. This is the catastrophe.
//   (c) OLD backend, BOTH params (what the real app always sends) → safely
//       degrades to legacy `status`-only filtering — imperfect (the old
//       elapsed-CONFIRMED-stuck-in-Майбутні bug is back) but never wrong.
//
// KEY POLICY (AppHarness): all TAPS are key-based; Ukrainian text appears in
// CONTENT ASSERTIONS only, and status copy is asserted through l10n.
//
// This runs headless — `flutter test
// integration_test/client_my_bookings_partition_flow_test.dart -d
// flutter-tester` needs no emulator. Per the harness convention, run this
// file ALONE — batching two integration files in one `flutter test`
// invocation kills the second with a bogus "log reader failed".

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/booking_partition.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_tab.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_review_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/features/notifications/presentation/notifications_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  AppLocalizations l10nOf(WidgetTester tester, Type screen) =>
      AppLocalizations.of(tester.element(find.byType(screen)));

  // A far-future / far-past pair of fixed instants — deterministic
  // regardless of the runner's wall clock or `TZ` (mirrors
  // `client_elapsed_booking_readonly_flow_test.dart`'s identical reasoning:
  // `FakeBackend`'s partition classification, like `BookingDisplayX.isPast`,
  // compares against the REAL device clock, so only a genuinely far instant
  // on either side is safe).
  const String elapsedStartsAt = '2020-01-01T10:00:00Z';
  const String elapsedEndsAt = '2020-01-01T11:30:00Z';
  // future-date-ok: deliberately far-future twin of elapsedStartsAt above — the pair proves the partition boundary deterministically on BOTH sides regardless of runner wall clock/TZ, per the comment above; a now-relative offset would not be symmetric with the fixed 2020 past instant.
  final DateTime futureStartsAt = DateTime.utc(2035, 1, 1, 10);

  testWidgets(
    'CLIENT «Мої записи»: an elapsed CONFIRMED booking is served under '
    'Минулі (not Майбутні) by a partition-aware fake backend, and opening it '
    'renders the existing read-only detail branch — the headline Phase 227 '
    'fix, proven end-to-end',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;

      // `booking-1` reuses the pre-registered literal detail route
      // (`GET /api/v1/bookings/booking-1` → `_seededBookingJson()`, driven by
      // the mutable `bookingStartsAt`/`bookingEndsAt`/`bookingStatus`
      // fields) — the established convention this codebase already uses
      // whenever a dataset-seeded row's DETAIL also needs to be opened (see
      // `master_bookings_flow_test.dart`). Both the dataset row (drives the
      // LIST/partition classification) and these mutable fields (drive the
      // DETAIL) are set to the SAME elapsed window so list and detail agree.
      fb.bookingStartsAt = elapsedStartsAt;
      fb.bookingEndsAt = elapsedEndsAt;
      // bookingStatus defaults to 'CONFIRMED' — left as-is.

      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'booking-1',
          status: 'CONFIRMED',
          startsAt: DateTime.parse(elapsedStartsAt),
          duration: const Duration(minutes: 90),
        ),
        fb.datasetBookingRow(
          id: 'future1',
          status: 'CONFIRMED',
          startsAt: futureStartsAt,
        ),
      ]);

      final GoRouter router = await AppHarness.boot(tester, fb);

      // Cold start → /login.
      expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
      await AppHarness.loginAs(tester, fb, UserRole.client);

      // Open the Записи branch (bottom-nav tile 3).
      await tester.tap(find.byKey(const Key('client-nav-tile-3')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.clientBookings);
      expect(find.byType(MyBookingsScreen), findsOneWidget);

      // ── Майбутні shows ONLY the genuinely-upcoming row. ───────────────────
      final Finder upcomingList = find.byKey(
        const ValueKey<String>('my-bookings-list-upcoming'),
      );
      expect(
        find.descendant(
          of: upcomingList,
          matching: find.byKey(const ValueKey<String>('service-future1')),
        ),
        findsOneWidget,
        reason:
            'anti-vacuity: Майбутні must genuinely render the future row, or '
            'the exclusion assertion below is meaningless',
      );
      expect(
        find.descendant(
          of: upcomingList,
          matching: find.byKey(const ValueKey<String>('service-booking-1')),
        ),
        findsNothing,
        reason:
            'the headline regression this phase closes: an elapsed '
            'CONFIRMED booking must no longer be classified as Майбутні by '
            'the (partition-aware) backend',
      );
      expect(
        find.byType(BookingCard),
        findsOneWidget,
        reason:
            'exactly one row — the elapsed booking is not merely hidden '
            'client-side, the SERVER never returned it for this partition',
      );

      // ── Tap Минулі: the elapsed CONFIRMED row is there. ───────────────────
      await tester.tap(find.byKey(const ValueKey<BookingTab>(BookingTab.past)));
      await AppHarness.settle(tester);

      final Finder pastList = find.byKey(
        const ValueKey<String>('my-bookings-list-past'),
      );
      expect(
        find.descendant(
          of: pastList,
          matching: find.byKey(const ValueKey<String>('service-booking-1')),
        ),
        findsOneWidget,
        reason:
            'the elapsed CONFIRMED booking must now be served under '
            'partition=PAST',
      );
      expect(
        find.descendant(
          of: pastList,
          matching: find.byKey(const ValueKey<String>('service-future1')),
        ),
        findsNothing,
        reason: 'the future booking must not leak into Минулі',
      );

      // ── Open its detail. ───────────────────────────────────────────────────
      await tester.tap(find.byType(BookingCard));
      await AppHarness.settle(tester);
      // `/bookings/:bookingId` is a child GoRoute pushed INSIDE the client
      // shell's bookings branch — the pushed-leaf resolver, never plain
      // `expectLocation` (see `client_elapsed_booking_readonly_flow_test.dart`'s
      // identical comment / the shell-nested-push contract test).
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.bookingDetail('booking-1'),
      );
      expect(find.byType(BookingDetailScreen), findsOneWidget);

      // ── Read-only: the existing `isPast` branch — no new branch added to
      //    `booking_detail_screen.dart` in this phase. ───────────────────────
      expect(
        find.byKey(const Key('booking-detail-reschedule')),
        findsNothing,
        reason: 'an elapsed booking cannot be rescheduled',
      );
      expect(
        find.byKey(const Key('booking-detail-cancel')),
        findsNothing,
        reason: 'an elapsed booking cannot be cancelled',
      );
      expect(
        find.byKey(const Key('booking-detail-add-calendar')),
        findsNothing,
        reason: 'adding a past event to the calendar is pointless',
      );

      final AppLocalizations detailL10n = l10nOf(tester, BookingDetailScreen);
      expect(
        find.text(detailL10n.bookingDetailRebookCta),
        findsOneWidget,
        reason:
            'only «Записатись знову» is offered — the read-only elapsed '
            'branch',
      );

      // Opening the read-only detail must not have mutated anything.
      expect(fb.bookingStatus, 'CONFIRMED');
      expect(fb.cancelBookingCalls, 0);
      expect(fb.rescheduleBookingCalls, 0);
    },
  );

  // ==========================================================================
  // M528 / B527 (CLI-63) — attached website LINK + walk-in STAFF bookings
  // ==========================================================================
  // A link or walk-in booking made with the client's verified phone is the
  // client's own: listed in «Записи» beside APP bookings, opened, cancelled
  // like one. The wire carries no source today, so each row also carries a
  // `bookingSource` key the decoder must tolerate. The LINK row is
  // `booking-1` so its DETAIL is served by the seeded literal route (same
  // convention as the first test), its window kept equal to the list row.
  testWidgets(
    'CLIENT «Записи»: a mixed APP / LINK / STAFF page renders every row in '
    'Майбутні and Минулі; the LINK booking opens its detail and cancels like '
    'an APP booking (M528)',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      fb.bookingStartsAt = futureStartsAt.toIso8601String();
      fb.bookingEndsAt = futureStartsAt
          .add(const Duration(minutes: 90))
          .toIso8601String();

      Map<String, dynamic> row(
        String id,
        String status,
        DateTime start,
        String? source,
      ) => <String, dynamic>{
        ...fb.datasetBookingRow(
          id: id,
          status: status,
          startsAt: start,
          duration: const Duration(minutes: 90),
        ),
        'clientId': 'client-1',
        'bookingSource': ?source,
      };

      final DateTime elapsed = DateTime.parse(elapsedStartsAt);
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        row('app-up', 'CONFIRMED', futureStartsAt, null),
        row('booking-1', 'CONFIRMED', futureStartsAt, 'LINK'),
        row('staff-up', 'CONFIRMED', futureStartsAt, 'STAFF'),
        row('app-past', 'COMPLETED', elapsed, null),
        row('link-past', 'COMPLETED', elapsed, 'LINK'),
        row('staff-past', 'COMPLETED', elapsed, 'STAFF'),
      ]);

      final GoRouter router = await AppHarness.boot(tester, fb);
      expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
      await AppHarness.loginAs(tester, fb, UserRole.client);

      await tester.tap(find.byKey(const Key('client-nav-tile-3')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.clientBookings);

      final Finder upcomingList = find.byKey(
        const ValueKey<String>('my-bookings-list-upcoming'),
      );
      for (final String id in <String>['app-up', 'booking-1', 'staff-up']) {
        expect(
          find.descendant(
            of: upcomingList,
            matching: find.byKey(ValueKey<String>('service-$id')),
          ),
          findsOneWidget,
          reason: '$id must render under Майбутні',
        );
      }

      await tester.tap(find.byKey(const ValueKey<BookingTab>(BookingTab.past)));
      await AppHarness.settle(tester);
      final Finder pastList = find.byKey(
        const ValueKey<String>('my-bookings-list-past'),
      );
      for (final String id in <String>['app-past', 'link-past', 'staff-past']) {
        expect(
          find.descendant(
            of: pastList,
            matching: find.byKey(ValueKey<String>('service-$id')),
          ),
          findsOneWidget,
          reason: '$id must render under Минулі',
        );
      }

      // ── Back to Майбутні, open the LINK booking. ─────────────────────────
      await tester.tap(
        find.byKey(const ValueKey<BookingTab>(BookingTab.upcoming)),
      );
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const ValueKey<String>('service-booking-1')));
      await AppHarness.settle(tester);
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.bookingDetail('booking-1'),
      );
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(
        find.textContaining('LINK'),
        findsNothing,
        reason: 'no source label',
      );
      // The app's only source-like copy («Запис за посиланням») must not
      // render on the client's detail of an attached booking either.
      expect(
        find.text(
          l10nOf(tester, BookingDetailScreen).bookingDetailGuestBookingLabel,
        ),
        findsNothing,
        reason: 'no «Запис за посиланням» label for the client',
      );

      // ── Cancel it like an APP booking. ───────────────────────────────────
      await tester.tap(find.byKey(const Key('booking-detail-cancel')));
      await AppHarness.settle(tester);
      expect(find.byKey(const Key('cancel-booking-dialog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('cancel-booking-note-field')),
        'Не встигаю.',
      );
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('cancel-booking-confirm')));
      await AppHarness.settle(tester);

      expect(fb.cancelBookingCalls, 1);
      expect(fb.bookingStatus, 'CANCELLED');
      final AppLocalizations detailL10n = l10nOf(tester, BookingDetailScreen);
      expect(find.text(detailL10n.bookingStatusCancelled), findsWidgets);
    },
  );

  // M528 — shared row builder for the three flows below: a dataset row with
  // the client's id and an optional `bookingSource` (absent = APP).
  Map<String, dynamic> attachedRow(
    FakeBackend fb,
    String id,
    String status,
    DateTime start,
    String? source,
  ) => <String, dynamic>{
    ...fb.datasetBookingRow(
      id: id,
      status: status,
      startsAt: start,
      duration: const Duration(minutes: 90),
    ),
    'clientId': 'client-1',
    'bookingSource': ?source,
  };

  // M528 — Головна «Найближчий запис»: the nearest upcoming booking is an
  // attached LINK booking (an APP and a STAFF one start later), so the card
  // must render it and open its detail. RED WHEN the home card's source
  // (`nextAppointmentProvider`) drops or filters the attached row.
  testWidgets(
    'CLIENT Головна: «Найближчий запис» shows an attached LINK booking that is '
    'the nearest upcoming one, and tapping it opens its detail (M528)',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      fb.bookingStartsAt = futureStartsAt.toIso8601String();
      fb.bookingEndsAt = futureStartsAt
          .add(const Duration(minutes: 90))
          .toIso8601String();
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        attachedRow(
          fb,
          'staff-later',
          'CONFIRMED',
          futureStartsAt.add(const Duration(days: 2)),
          'STAFF',
        ),
        attachedRow(fb, 'booking-1', 'CONFIRMED', futureStartsAt, 'LINK'),
        attachedRow(
          fb,
          'app-later',
          'CONFIRMED',
          futureStartsAt.add(const Duration(days: 1)),
          null,
        ),
      ]);

      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await AppHarness.settle(tester);

      expect(
        find.byKey(const Key('next_appointment_populated')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('next-appointment-booking-booking-1'),
        ),
        findsOneWidget,
        reason: 'the nearest upcoming booking is the attached LINK one',
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>('next-appointment-booking-booking-1'),
        ),
      );
      await AppHarness.settle(tester);
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.bookingDetail('booking-1'),
      );
      expect(find.byType(BookingDetailScreen), findsOneWidget);
    },
  );

  // M528 — review on an attached past booking: the CTA is gated on the
  // server's `canReview` alone, so a COMPLETED LINK booking with
  // `canReview: true` is reviewed exactly like an APP one. RED WHEN the
  // detail's `canReview` gate is bypassed/inverted or the review POST
  // carries another booking id.
  testWidgets(
    'CLIENT «Записи» → Минулі: a COMPLETED attached LINK booking with server '
    'canReview offers «Залишити відгук» and the review posts for it (M528)',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..bookingStartsAt = elapsedStartsAt
        ..bookingEndsAt = elapsedEndsAt
        ..bookingStatus = 'COMPLETED'
        ..bookingCanReview = true;
      final DateTime elapsed = DateTime.parse(elapsedStartsAt);
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        attachedRow(fb, 'booking-1', 'COMPLETED', elapsed, 'LINK'),
        attachedRow(fb, 'staff-past', 'COMPLETED', elapsed, 'STAFF'),
      ]);

      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.tap(find.byKey(const Key('client-nav-tile-3')));
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const ValueKey<BookingTab>(BookingTab.past)));
      await AppHarness.settle(tester);

      await tester.tap(find.byKey(const ValueKey<String>('service-booking-1')));
      await AppHarness.settle(tester);
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.bookingDetail('booking-1'),
      );
      final Finder leaveReview = find.byKey(
        const Key('booking-detail-leave-review'),
      );
      expect(leaveReview, findsOneWidget);

      await tester.tap(leaveReview);
      await AppHarness.settle(tester);
      expect(find.byType(LeaveReviewScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('review-star-5')));
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('leave-review-submit')));
      await AppHarness.settle(tester);

      expect(fb.createReviewCalls, 1, reason: 'exactly one POST /reviews');
      expect(fb.lastReviewBookingId, 'booking-1');
      expect(fb.lastReviewRating, 5);
      expect(fb.bookingCanReview, isFalse);
      await AppHarness.pumpUntilGone(tester, leaveReview);
      expect(leaveReview, findsNothing, reason: 'no second review offered');
      await pumpPastVelvetSnack(tester);
    },
  );

  // M528 / NTF-67 — the client's feed item for a booking a provider created
  // (link / walk-in attached by phone) reads «Вас записано», not the
  // provider's «Новий запис», and opens the booking detail on the
  // feed-scoped route. RED WHEN the client title arm is dropped or the
  // client BookingTarget route is removed.
  testWidgets(
    'CLIENT feed: a BOOKING_CREATED item reads «Вас записано» and opens the '
    'booking detail (M528, NTF-67)',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final String id = fb.seedNotification(
        type: 'BOOKING_CREATED',
        bookingId: FakeBackend.kNotificationBookingId,
      );

      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('home_hub_bell_button')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.notifications);

      final Finder tile = find.byKey(Key('notification-tile-$id'));
      final AppLocalizations l10n = l10nOf(tester, NotificationsScreen);
      expect(
        find.descendant(
          of: tile,
          matching: find.text(l10n.notificationTitleBookingCreatedClient),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile,
          matching: find.text(l10n.notificationTitleBookingCreated),
        ),
        findsNothing,
      );

      await tester.tap(tile);
      await AppHarness.settle(tester);
      AppHarness.expectLocation(
        router,
        RouteNames.notificationBookingDetail(
          FakeBackend.kNotificationBookingId,
        ),
      );
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(fb.notificationMarkedReadIds, <String>[id]);
    },
  );

  // ==========================================================================
  // Negative control — THE ROLLOUT SAFETY VALVE
  // ==========================================================================
  testWidgets(
    'THE ROLLOUT SAFETY VALVE: an old backend silently drops `partition`; a '
    'request carrying `partition` WITHOUT `status` then returns the '
    'unfiltered whole history — the failure the valve exists to prevent — '
    'while the real app (which always sends BOTH) degrades only to the '
    'pre-227 status-only filter, never to "no filter at all"',
    (tester) async {
      // past-date-ok: deliberately far-past twin of `future` below — the PAIR is the assertion (it proves the partition boundary on both sides regardless of runner wall clock/TZ), so a `kFixedNow`-anchored offset would not be symmetric with the fixed 2035 future instant. Safe from the 2026-08-17 hang shape: this row feeds the client's «Мої записи» LIST, which has no per-day timeline whose extent it could stretch.
      final DateTime past = DateTime.utc(2000, 1, 1, 10);
      // future-date-ok: deliberately far-future twin of `past` above — proves the partition boundary deterministically on both sides regardless of runner wall clock/TZ; a now-relative offset would not be symmetric with the fixed 2000 past instant.
      final DateTime future = DateTime.utc(2035, 1, 1, 10);

      final fb = FakeBackend()..currentRole = UserRole.client;
      // A 4-row fixture spanning all three partitions, so "unfiltered" is
      // legible as a concrete, countable difference — not just "more than
      // expected".
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'v-upcoming',
          status: 'CONFIRMED',
          startsAt: future,
        ),
        fb.datasetBookingRow(
          id: 'v-elapsed',
          status: 'CONFIRMED',
          startsAt: past,
        ),
        fb.datasetBookingRow(
          id: 'v-completed',
          status: 'COMPLETED',
          startsAt: past,
        ),
        fb.datasetBookingRow(
          id: 'v-cancelled',
          status: 'CANCELLED',
          startsAt: past,
        ),
      ]);

      final GoRouter router = await AppHarness.boot(tester, fb);
      expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
      await AppHarness.loginAs(tester, fb, UserRole.client);

      // Reach the bookings screen just to get a mounted-widget handle on the
      // real container — no list assertions here, this test drives the
      // repository directly (see file header for why: the real notifier
      // never constructs the "partition-only" request this test needs to).
      await tester.tap(find.byKey(const Key('client-nav-tile-3')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.clientBookings);

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MyBookingsScreen)),
      );
      final repo = container.read(bookingRepositoryProvider);

      // ── (a) Modern backend + partition-only request → correctly scoped. ──
      // The valve is irrelevant here: a Phase-28.2 backend needs no
      // defending. Included as the control's control.
      fb.backendSupportsPartition = true;
      final onValveModern = await repo.getMyBookings(
        statuses: const <BookingStatus>{},
        partition: BookingPartition.upcoming,
        sort: BookingSort.oldest,
        page: 0,
      );
      expect(
        onValveModern.items.map((b) => b.id).toSet(),
        <String>{'v-upcoming'},
        reason:
            'a modern backend classifies correctly even without `status` on '
            'the wire — the valve exists for the OLD-backend case below',
      );

      // ── (b) OLD backend + partition-ONLY request → THE CATASTROPHE. ──────
      // Mirrors Spring silently dropping the unrecognised `partition` key;
      // with `status` also absent (empty `statuses`), NO filter applies at
      // all. This is exactly the hypothetical the phase doc warns about: "a
      // client that sends only `partition`... sends, effectively, no filter
      // at all."
      fb.backendSupportsPartition = false;
      final offValveOldBackend = await repo.getMyBookings(
        statuses: const <BookingStatus>{},
        partition: BookingPartition.upcoming,
        sort: BookingSort.oldest,
        page: 0,
      );
      expect(
        offValveOldBackend.items.length,
        4,
        reason:
            'THE FAILURE: with no `status` to fall back on, an old backend '
            'returns the caller\'s ENTIRE booking history — cancelled '
            'visits from 2000 rendering as "upcoming" — with no error and '
            'no signal',
      );
      expect(
        offValveOldBackend.items.map((b) => b.id).toSet(),
        <String>{'v-upcoming', 'v-elapsed', 'v-completed', 'v-cancelled'},
        reason: 'every status, on both sides of "now" — genuinely unfiltered',
      );

      // ── (c) OLD backend + BOTH params (what the real app always sends) →
      //        safe degradation, not a catastrophe. ────────────────────────
      // Still an old backend (`backendSupportsPartition` unchanged from (b)).
      // This is `BookingTab.upcoming`'s real request shape — `partition`
      // AND its legacy `status` set together.
      final safeDegradation = await repo.getMyBookings(
        statuses: BookingTab.upcoming.statuses,
        partition: BookingPartition.upcoming,
        sort: BookingSort.oldest,
        page: 0,
      );
      expect(
        safeDegradation.items.map((b) => b.id).toSet(),
        <String>{'v-upcoming', 'v-elapsed'},
        reason:
            'THE VALVE WORKING: `status=CONFIRMED` alone still filters '
            'correctly on the old backend — cancelled/completed rows never '
            'leak in. The elapsed CONFIRMED row DOES still show (the '
            'pre-227 bug this whole track exists to fix), but that is a '
            'reversion to a KNOWN, harmless legacy behaviour — not the '
            'unbounded-history leak in (b). This is the observable '
            'difference "sending both" buys, made concrete.',
      );
    },
  );
}
