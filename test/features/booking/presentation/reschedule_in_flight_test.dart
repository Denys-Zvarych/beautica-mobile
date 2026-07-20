// mobile-qa (track 24.x booking auto-confirm — perf-LOW in-flight fix) —
// coverage for the CLIENT reschedule "navigation in-flight" guard.
//
// The fix added `bookingRescheduleInFlightProvider` (an autoDispose bool
// Notifier) plus a spinner/disabled state on BOTH reschedule triggers and an
// early-return re-entrancy guard inside `startBookingReschedule`. It was
// re-scored by mobile-perf only and shipped WITHOUT a dedicated test. This
// suite pins the three behaviours the fix owns:
//
//   (a) BUTTON REFLECTS THE FLAG — while a reschedule navigation is in-flight,
//       BOTH surfaces swap their label for a spinner and stop firing:
//         • the «Деталі запису» «Перенести» `NeumorphicButton`
//           (key `booking-detail-reschedule`, driven by a watched provider);
//         • the Home-Hub «Найближчий запис» `HubFilledButton`
//           (key `next_appt_reschedule_button`, driven by `rescheduleLoading`).
//   (b) RE-ENTRANCY — a second trigger fired while the first is still loading
//       its seeding GETs early-returns: NO second slot-picker is pushed.
//   (c) end() CLEARS THE FLAG — on a successful push AND on every early
//       short-circuit (non-confirmed / error), so a later attempt works.
//
// Finders are key-first; every asserted string goes through l10n (CI
// no-raw-Cyrillic gate). "Did / did not navigate" is a POSITIVE assertion
// against a real `GoRouter` slot-picker stub counted with `skipOffstage: false`
// (a second push would leave a second stub in the navigator stack), never the
// mere absence of an exception.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_reschedule_in_flight_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/reschedule_navigation.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/next_appointment_card.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

const String _bookingId = 'booking-1';
const String _masterId = 'master-aaa';
const String _serviceId = 'pub-assign-1';

const Master _master = Master(
  id: _masterId,
  firstName: 'Софія',
  lastName: 'Бондар',
  avgRating: 4.9,
  reviewCount: 24,
  type: MasterType.independentMaster,
);

const MasterService _bookedService = MasterService(
  id: _serviceId,
  serviceDefId: 'pub-svc-1',
  name: 'Манікюр з покриттям',
  durationMinutes: 90,
  priceMin: 650,
  priceDisplay: '650 ₴',
  category: 'NAILS',
);

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

Booking _booking({required BookingStatus status}) {
  final DateTime start = futureBookingStart();
  return Booking(
    id: _bookingId,
    masterId: _masterId,
    masterFirstName: 'Софія',
    masterLastName: 'Бондар',
    masterType: 'INDEPENDENT_MASTER',
    serviceId: _serviceId,
    serviceName: 'Манікюр з покриттям',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: status,
    canReview: false,
  );
}

/// True iff the [buttonKey]'s inner content is a spinner (loading), not a label.
bool _isSpinning(Key buttonKey) => find
    .descendant(
      of: find.byKey(buttonKey),
      matching: find.byType(CircularProgressIndicator),
    )
    .evaluate()
    .isNotEmpty;

void main() {
  setUpAll(() => registerFallbackValue(BookingStatus.confirmed));

  // ═════════════════════════════════════════════════════════════════════════
  // (a) The button reflects the in-flight flag — «Деталі запису» surface.
  // ═════════════════════════════════════════════════════════════════════════
  group('booking-detail «Перенести» reflects the in-flight flag', () {
    const Key kReschedule = Key('booking-detail-reschedule');

    List<Object> overrides(_MockBookingRepository repo) => <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingRepositoryProvider.overrideWithValue(repo),
      bookingDetailProvider(
        _bookingId,
      ).overrideWith((ref) async => _booking(status: BookingStatus.confirmed)),
    ];

    testWidgets(
      'idle → the button shows its label; flag set → spinner, no label',
      (tester) async {
        await tester.pumpApp(
          const BookingDetailScreen(bookingId: _bookingId),
          overrides: overrides(_MockBookingRepository()),
        );
        await tester.pumpAndSettle();

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(BookingDetailScreen)),
        );

        // Idle: the CONFIRMED reschedule CTA renders its label, no spinner.
        expect(find.byKey(kReschedule), findsOneWidget);
        expect(find.text(l10n.bookingDetailRescheduleCta), findsOneWidget);
        expect(_isSpinning(kReschedule), isFalse);

        // Flip the shared flag exactly as `startBookingReschedule` does at the
        // top of its seeding window — the screen watches it, so it rebuilds.
        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(BookingDetailScreen)),
        );
        container.read(bookingRescheduleInFlightProvider.notifier).begin();
        await tester.pump();

        // In-flight: the label is swapped for a spinner (button is disabled).
        expect(_isSpinning(kReschedule), isTrue);
        expect(find.text(l10n.bookingDetailRescheduleCta), findsNothing);
      },
    );

    testWidgets(
      'while in-flight the button is disabled (Semantics.enabled == false)',
      (tester) async {
        await tester.pumpApp(
          const BookingDetailScreen(bookingId: _bookingId),
          overrides: overrides(_MockBookingRepository()),
        );
        await tester.pumpAndSettle();

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(BookingDetailScreen)),
        );
        container.read(bookingRescheduleInFlightProvider.notifier).begin();
        await tester.pump();

        // A disabled NeumorphicButton reports `enabled: false` to a11y — this
        // is the same gate that nulls its tap handler, so a re-tap is inert.
        final Semantics semantics = tester.widget<Semantics>(
          find
              .descendant(
                of: find.byKey(kReschedule),
                matching: find.byType(Semantics),
              )
              .first,
        );
        expect(semantics.properties.enabled, isFalse);
      },
    );
  });

  // ═════════════════════════════════════════════════════════════════════════
  // (a) The button reflects the in-flight flag — Home-Hub «Найближчий запис».
  // ═════════════════════════════════════════════════════════════════════════
  group('home-hub «Перенести» reflects rescheduleLoading', () {
    const Key kReschedule = Key('next_appt_reschedule_button');

    final NextAppointment appointment = NextAppointment(
      id: _bookingId,
      masterName: 'Софія Бондар',
      service: 'Манікюр',
      dateLabel: '20 липня',
      timeLabel: '15:00',
      location: 'Центр, Львів',
      startsAt: futureBookingStart(),
      masterInitials: 'СБ',
    );

    Future<void> pumpCard(
      WidgetTester tester, {
      required bool loading,
      required VoidCallback onReschedule,
    }) => tester.pumpApp(
      NextAppointmentCard(
        appointment: appointment,
        onReschedule: onReschedule,
        onCancel: () {},
        onAddToGoogleCalendar: () {},
        onAddToAppleCalendar: () {},
        rescheduleLoading: loading,
      ),
    );

    testWidgets('loading == false → label shown and a tap fires onReschedule', (
      tester,
    ) async {
      bool tapped = false;
      await pumpCard(tester, loading: false, onReschedule: () => tapped = true);

      expect(_isSpinning(kReschedule), isFalse);
      await tester.tap(find.byKey(kReschedule));
      expect(tapped, isTrue);
    });

    testWidgets('loading == true → spinner shown and a tap is ignored', (
      tester,
    ) async {
      bool tapped = false;
      await pumpCard(tester, loading: true, onReschedule: () => tapped = true);

      // Spinner replaces the label…
      expect(_isSpinning(kReschedule), isTrue);
      // …and the button ignores taps while loading (no double navigation).
      await tester.tap(find.byKey(kReschedule));
      expect(tapped, isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // (b)+(c) The re-entrancy guard + end() clearing, driven through the real
  // `startBookingReschedule` helper inside a GoRouter.
  // ═════════════════════════════════════════════════════════════════════════
  group('startBookingReschedule in-flight guard', () {
    // Counts slot-picker instances currently in the navigator stack (offstage
    // included) — a second push leaves a second stub, so 1 ⇒ single navigation.
    int slotStubCount() => find
        .byKey(const Key('slots_stub'), skipOffstage: false)
        .evaluate()
        .length;

    /// Pumps a `/start` launcher whose button WATCHES the in-flight flag (like
    /// both real triggers) and drives [startBookingReschedule] on tap. Returns
    /// the [ProviderContainer] so a test can read the flag after the run.
    Future<ProviderContainer> pump(
      WidgetTester tester, {
      required Future<Booking> Function() detail,
      List<MasterService> services = const <MasterService>[_bookedService],
    }) async {
      final GoRouter router = GoRouter(
        initialLocation: '/start',
        routes: <RouteBase>[
          GoRoute(
            path: '/start',
            builder: (BuildContext context, _) => Scaffold(
              body: Consumer(
                builder: (BuildContext context, WidgetRef ref, _) {
                  // Watch (not read) so the autoDispose provider stays alive
                  // across the seeding awaits — exactly as the real buttons do.
                  final bool loading = ref.watch(
                    bookingRescheduleInFlightProvider,
                  );
                  return TextButton(
                    key: const Key('go'),
                    onPressed: () => startBookingReschedule(
                      context: context,
                      ref: ref,
                      bookingId: _bookingId,
                    ),
                    child: Text(loading ? 'loading' : 'go'),
                  );
                },
              ),
            ),
          ),
          GoRoute(
            path: RouteNames.bookingSlots,
            builder: (_, _) => const Scaffold(key: Key('slots_stub')),
          ),
        ],
      );

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          bookingDetailProvider(_bookingId).overrideWith((ref) => detail()),
          publicMasterProfileProvider(
            _masterId,
          ).overrideWith((ref) async => (_master, services)),
        ],
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(
        tester.element(find.byKey(const Key('go'))),
      );
    }

    testWidgets(
      'a second tap fired while the first is still loading is ignored — only '
      'one slot picker is pushed',
      (tester) async {
        // Gate the first booking-detail load so the seeding window stays open
        // across the second tap.
        final Completer<Booking> gate = Completer<Booking>();
        final ProviderContainer container = await pump(
          tester,
          detail: () => gate.future,
        );

        // 1st tap: begins the in-flight window, then suspends on the gate.
        await tester.tap(find.byKey(const Key('go')));
        await tester.pump();
        expect(container.read(bookingRescheduleInFlightProvider), isTrue);

        // 2nd tap DURING the window: the re-entrancy guard must early-return.
        await tester.tap(find.byKey(const Key('go')));
        await tester.pump();

        // Release the gate and let the (single) chain finish.
        gate.complete(_booking(status: BookingStatus.confirmed));
        await tester.pumpAndSettle();

        // Exactly one slot picker — a leaked second push would leave two stubs.
        expect(slotStubCount(), 1);
        // end() cleared the flag in `finally` after the push.
        expect(container.read(bookingRescheduleInFlightProvider), isFalse);
      },
    );

    testWidgets(
      'end() clears the flag on a successful push (a later attempt is free to '
      'run)',
      (tester) async {
        final ProviderContainer container = await pump(
          tester,
          detail: () async => _booking(status: BookingStatus.confirmed),
        );

        await tester.tap(find.byKey(const Key('go')));
        await tester.pumpAndSettle();

        expect(slotStubCount(), 1);
        expect(container.read(bookingRescheduleInFlightProvider), isFalse);
      },
    );

    testWidgets(
      'end() clears the flag on the non-confirmed short-circuit (the early '
      '`return` inside `try` still runs the `finally`)',
      (tester) async {
        final ProviderContainer container = await pump(
          tester,
          detail: () async => _booking(status: BookingStatus.declined),
        );

        await tester.tap(find.byKey(const Key('go')));
        await tester.pumpAndSettle();

        // No navigation, and the flag is NOT latched — a later reschedule
        // attempt from this surface is free to run.
        expect(slotStubCount(), 0);
        expect(container.read(bookingRescheduleInFlightProvider), isFalse);
      },
    );

    testWidgets('end() clears the flag on a load-error short-circuit', (
      tester,
    ) async {
      final ProviderContainer container = await pump(
        tester,
        detail: () async => throw const ServerFailure(statusCode: 500),
      );

      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();

      expect(slotStubCount(), 0);
      expect(container.read(bookingRescheduleInFlightProvider), isFalse);
    });
  });
}
