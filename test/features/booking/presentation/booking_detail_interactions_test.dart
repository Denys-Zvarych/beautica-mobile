// QA (track 14.x booking) — INTERACTION-coverage suite for
// [BookingDetailScreen].
//
// booking_detail_screen_test.dart proves the state machine (headline / subline
// / action-set / price / note-direction by status) and the cancel wiring.
// This suite closes the remaining INTERACTIVE-element gaps the verification
// pass found — every one is a tap the state suite only asserted the PRESENCE
// of, never fired:
//   • the back affordance → context.pop();
//   • «Перенести» → pushes the slot picker seeded to reschedule this booking;
//   • «Записатись знову» → context.push('/masters/:id');
//   • «Додати в календар» → a DELIBERATE, documented no-op (present on
//     CONFIRMED, absent otherwise, and — this is the point — tapping it changes
//     NOTHING: no nav, no SnackBar, no throw. Pins it as intentionally inert,
//     not a silently-dead button);
//   • the note show-more / show-less toggle → expands and collapses.
//
// Finders are key-first; all copy is asserted through l10n, never a raw
// Cyrillic literal (CI no-raw-string gate). Fixed `pump(Duration)` waits are
// banned — the SnackBar assertion uses the bounded [PumpUntil.pumpUntilFound]
// helper instead.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

// A provider note long enough to overflow InboundNote's 6-line clamp at the
// default 800px test width, so the show-more/show-less toggle is actually
// offered. A test FIXTURE, not app copy — never asserted via find.text.
final String _longProviderNote =
    'Майстер захворів, мусимо перенести запис на пізніше. ' * 60;

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

Booking _booking({
  String id = 'b1',
  required BookingStatus status,
  String? salonName,
  String? providerComment,
}) {
  final DateTime start = DateTime.utc(2026, 7, 20, 15);
  return Booking(
    id: id,
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterAvatarUrl: null,
    masterType: salonName != null ? 'SALON_MASTER' : 'INDEPENDENT_MASTER',
    salonName: salonName,
    serviceId: 's1',
    serviceName: 'Манікюр з покриттям',
    categoryName: 'Манікюр',
    cityLabel: 'Львів',
    districtLabel: null,
    street: 'вул. Городоцька',
    buildingNo: '12',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: status,
    canReview: false,
    clientComment: null,
    providerComment: providerComment,
    clientCancellationNote: null,
    masterProfessionalTitle: 'Майстриня манікюру',
    locationNote: null,
  );
}

List<Object> _overrides(Booking booking, _MockBookingRepository repo) =>
    <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingRepositoryProvider.overrideWithValue(repo),
      bookingDetailProvider(booking.id).overrideWith((ref) async => booking),
    ];

/// Non-navigating host — a plain `MaterialApp home:` via [PumpApp.pumpApp].
/// Suffices for reschedule (SnackBar), calendar (no-op) and the note toggle.
Future<_MockBookingRepository> _pumpDetail(
  WidgetTester tester,
  Booking booking,
) async {
  final _MockBookingRepository repo = _MockBookingRepository();
  await tester.pumpApp(
    BookingDetailScreen(bookingId: booking.id),
    overrides: _overrides(booking, repo),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// Routed host — a GoRouter with a `/start` launcher that PUSHES the detail
/// route (so there is something to pop back to) and a `/masters/:id` stub (the
/// rebook target). Returns the id captured by the master stub, if reached.
class _RebookProbe {
  String? masterId;
}

Future<_RebookProbe> _pumpDetailRouted(
  WidgetTester tester,
  Booking booking,
) async {
  final _MockBookingRepository repo = _MockBookingRepository();
  final _RebookProbe probe = _RebookProbe();
  final router = GoRouter(
    initialLocation: '/start',
    routes: <RouteBase>[
      GoRoute(
        path: '/start',
        builder: (BuildContext context, _) => Scaffold(
          key: const Key('start_stub'),
          body: Center(
            child: TextButton(
              key: const Key('go-detail'),
              onPressed: () =>
                  context.push('/bookings/${Uri.encodeComponent(booking.id)}'),
              child: const Text('go'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/bookings/:bookingId',
        builder: (_, _) => BookingDetailScreen(bookingId: booking.id),
      ),
      GoRoute(
        path: '/masters/:masterId',
        builder: (BuildContext context, GoRouterState state) {
          probe.masterId = state.pathParameters['masterId'];
          return const Scaffold(key: Key('master_profile_stub'));
        },
      ),
    ],
  );
  await tester.pumpRoutedApp(router, overrides: _overrides(booking, repo));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('go-detail')));
  await tester.pumpAndSettle();
  return probe;
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(BookingDetailScreen)));

// Reschedule fixtures — the master + the booked service the slot picker is
// seeded with. Ids match `_booking`'s masterId ('m1') / serviceId ('s1') so
// the shared reschedule helper resolves the service by id.
const Master _kRescheduleMaster = Master(
  id: 'm1',
  firstName: 'Марія',
  lastName: 'Іванюк',
  avgRating: 4.9,
  reviewCount: 20,
  type: MasterType.independentMaster,
);

const MasterService _kRescheduleService = MasterService(
  id: 's1',
  serviceDefId: 'def-1',
  name: 'Манікюр з покриттям',
  durationMinutes: 90,
  priceMin: 650,
  priceDisplay: '650 ₴',
  category: 'MANICURE',
);

/// Pumps the detail screen inside a router with a [RouteNames.bookingSlots]
/// stub, taps «Перенести», and returns the [BookingSlotPickerArgs] the picker
/// was seeded with (null if navigation never occurred). The
/// `publicMasterProfileProvider` is overridden so the shared helper can resolve
/// the master + booked service without a real fetch.
Future<BookingSlotPickerArgs?> _tapReschedule(
  WidgetTester tester,
  Booking booking,
) async {
  final _MockBookingRepository repo = _MockBookingRepository();
  BookingSlotPickerArgs? captured;
  final router = GoRouter(
    initialLocation: '/bookings/${Uri.encodeComponent(booking.id)}',
    routes: <RouteBase>[
      GoRoute(
        path: '/bookings/:bookingId',
        builder: (_, _) => BookingDetailScreen(bookingId: booking.id),
      ),
      GoRoute(
        path: RouteNames.bookingSlots,
        builder: (BuildContext context, GoRouterState state) {
          captured = state.extra as BookingSlotPickerArgs?;
          return const Scaffold(key: Key('slots_stub'));
        },
      ),
    ],
  );
  await tester.pumpRoutedApp(
    router,
    overrides: <Object>[
      ..._overrides(booking, repo),
      publicMasterProfileProvider(booking.masterId).overrideWith(
        (ref) async =>
            (_kRescheduleMaster, const <MasterService>[_kRescheduleService]),
      ),
    ],
  );
  await tester.pumpAndSettle();

  final l10n = _l10n(tester);
  final Finder reschedule = find.text(l10n.bookingDetailRescheduleCta);
  await tester.ensureVisible(reschedule);
  await tester.pumpAndSettle();
  await tester.tap(reschedule);
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  setUpAll(() => registerFallbackValue(BookingStatus.confirmed));

  // -------------------------------------------------------------------------
  // Back affordance → pop
  // -------------------------------------------------------------------------

  group('back button', () {
    testWidgets('tapping the back affordance pops the detail route', (
      tester,
    ) async {
      await _pumpDetailRouted(
        tester,
        _booking(status: BookingStatus.confirmed),
      );

      // We are on the detail screen (pushed from /start).
      expect(find.byKey(const Key('booking-detail-back')), findsOneWidget);
      expect(find.byKey(const Key('start_stub')), findsNothing);

      await tester.tap(find.byKey(const Key('booking-detail-back')));
      await tester.pumpAndSettle();

      // Popped back to the launcher — the detail screen is gone.
      expect(find.byKey(const Key('start_stub')), findsOneWidget);
      expect(find.byType(BookingDetailScreen), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // «Перенести» → seed the slot picker for a reschedule
  // -------------------------------------------------------------------------

  group('reschedule', () {
    testWidgets(
      'tapping «Перенести» pushes the slot picker seeded with rescheduleBookingId',
      (tester) async {
        final Booking booking = _booking(status: BookingStatus.confirmed);
        final BookingSlotPickerArgs? args = await _tapReschedule(
          tester,
          booking,
        );

        // Navigated into the picker stub, seeded to reschedule THIS booking.
        expect(find.byKey(const Key('slots_stub')), findsOneWidget);
        expect(find.byType(BookingDetailScreen), findsNothing);
        expect(args, isNotNull);
        expect(args!.rescheduleBookingId, booking.id);
        expect(args.masterId, booking.masterId);
        expect(args.services.single.id, booking.serviceId);
      },
    );
  });

  // -------------------------------------------------------------------------
  // «Записатись знову» → push the master's public profile
  // -------------------------------------------------------------------------

  group('rebook', () {
    testWidgets('tapping «Записатись знову» pushes /masters/:id', (
      tester,
    ) async {
      // COMPLETED carries the rebook action (see the screen's action table).
      final Booking booking = _booking(status: BookingStatus.completed);
      final _RebookProbe probe = await _pumpDetailRouted(tester, booking);
      final l10n = _l10n(tester);

      final Finder rebook = find.text(l10n.bookingDetailRebookCta);
      await tester.ensureVisible(rebook);
      await tester.pumpAndSettle();
      await tester.tap(rebook);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('master_profile_stub')), findsOneWidget);
      // The booking's masterId is the only rebook target the record supports.
      expect(probe.masterId, booking.masterId);
    });
  });

  // -------------------------------------------------------------------------
  // «Додати в календар» → a DELIBERATE, documented no-op
  // -------------------------------------------------------------------------

  group('add-to-calendar (deliberate no-op)', () {
    testWidgets('is present on CONFIRMED and tapping it changes NOTHING', (
      tester,
    ) async {
      await _pumpDetail(tester, _booking(status: BookingStatus.confirmed));

      final Finder calendar = find.byKey(const Key('booking-add-calendar'));
      expect(calendar, findsOneWidget);

      await tester.ensureVisible(calendar);
      await tester.pumpAndSettle();
      await tester.tap(calendar);
      await tester.pumpAndSettle();

      // The no-op is honest: no navigation off the detail screen, no SnackBar,
      // and (the test would have thrown otherwise) no exception. It is inert by
      // design until an ICS/add_2_calendar dependency lands — NOT a dead button.
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('is ABSENT on a COMPLETED booking (CONFIRMED-only)', (
      tester,
    ) async {
      await _pumpDetail(tester, _booking(status: BookingStatus.completed));

      expect(find.byKey(const Key('booking-add-calendar')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Note show-more / show-less toggle
  // -------------------------------------------------------------------------

  group('note toggle', () {
    testWidgets('a long provider note expands then collapses', (tester) async {
      // A DECLINED booking renders the provider note as a clamped InboundNote;
      // a long enough note offers the show-more/less toggle.
      await _pumpDetail(
        tester,
        _booking(
          status: BookingStatus.declined,
          providerComment: _longProviderNote,
        ),
      );
      final l10n = _l10n(tester);

      // The note lives at the foot of a scrolling recap, so the toggle can be
      // scroll-clipped (offstage) even though it is laid out — every finder
      // uses skipOffstage: false, and each tap is preceded by ensureVisible so
      // the control is on-screen when hit.
      final Finder showMore = find.text(
        l10n.bookingNoteShowMore,
        skipOffstage: false,
      );
      final Finder showLess = find.text(
        l10n.bookingNoteShowLess,
        skipOffstage: false,
      );

      // Collapsed: the toggle reads «Показати більше», never «Згорнути».
      expect(showMore, findsOneWidget);
      expect(showLess, findsNothing);

      await tester.ensureVisible(showMore);
      await tester.pumpAndSettle();
      await tester.tap(showMore);
      await tester.pumpAndSettle();

      // Expanded: the label flips to «Згорнути».
      expect(showLess, findsOneWidget);
      expect(showMore, findsNothing);

      // Collapse again — back to «Показати більше».
      await tester.ensureVisible(showLess);
      await tester.pumpAndSettle();
      await tester.tap(showLess);
      await tester.pumpAndSettle();
      expect(showMore, findsOneWidget);
    });
  });
}
