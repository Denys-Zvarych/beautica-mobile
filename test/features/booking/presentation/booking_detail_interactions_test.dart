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
//   • «Додати в календар» → fires the `add_2_calendar` platform INSERT (channel
//     mocked) with this booking's service·provider title, venue location and
//     instants; present on CONFIRMED only; carries no client note / PII. (This
//     replaces the earlier "deliberate no-op" assertion — track 14.x shipped
//     the add_2_calendar dependency, so the button is now live.);
//   • the note show-more / show-less toggle → expands and collapses.
//
// Finders are key-first; all copy is asserted through l10n, never a raw
// Cyrillic literal (CI no-raw-string gate). Fixed `pump(Duration)` waits are
// banned — the SnackBar assertion uses the bounded [PumpUntil.pumpUntilFound]
// helper instead.

import 'dart:async';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_display_x.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/calendar_button.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

// The add_2_calendar plugin's platform boundary — intercepted so tapping
// «Додати в календар» never opens a real OS calendar sheet.
const MethodChannel _kCalendarChannel = MethodChannel('add_2_calendar');

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
  String? clientComment,
  String? clientCancellationNote,
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
    clientComment: clientComment,
    providerComment: providerComment,
    clientCancellationNote: clientCancellationNote,
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
  // «Додати в календар» → wires the CONFIRMED booking to the OS calendar
  //
  // Track 14.x shipped `add_2_calendar`, so this button is NO LONGER a no-op
  // (the earlier "deliberate no-op" assertion is retired). Tapping it must fire
  // the plugin's `add2Cal` platform method with THIS booking's title / venue /
  // instants — mocked at the channel boundary so no real OS sheet opens.
  //
  // RELOCATION (change #4): the calendar trigger MOVED from the scroll-body
  // `CalendarButton` pill (`Key('booking-add-calendar')`, still used by the
  // success screens + home hub) to a HEADER icon `_CalendarIconButton`
  // (`Key('booking-detail-add-calendar')`) via the scaffold's `headerTrailing`
  // slot. Same `_onAddToCalendar` handler — the tests below fire the header
  // key, and the old body pill is asserted ABSENT in the `relocation` group.
  // -------------------------------------------------------------------------

  group('add-to-calendar (wires to add_2_calendar)', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_kCalendarChannel, (MethodCall call) async {
            calls.add(call);
            return true; // pretend a calendar app opened
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_kCalendarChannel, null);
    });

    testWidgets(
      'tapping «Додати в календар» on a CONFIRMED booking invokes add2Cal with '
      'the service·provider title, venue location and booking instants',
      (tester) async {
        final Booking booking = _booking(status: BookingStatus.confirmed);
        await _pumpDetail(tester, booking);
        final AppLocalizations l10n = _l10n(tester);

        final Finder calendar = find.byKey(
          const Key('booking-detail-add-calendar'),
        );
        expect(calendar, findsOneWidget);

        await tester.ensureVisible(calendar);
        await tester.pumpAndSettle();
        await tester.tap(calendar);
        await tester.pumpAndSettle();

        expect(calls, hasLength(1), reason: 'add2Cal must have fired once');
        final Map<Object?, Object?> args =
            calls.single.arguments as Map<Object?, Object?>;
        expect(calls.single.method, 'add2Cal');
        // Independent-master booking → provider is the master's name.
        expect(
          args['title'],
          l10n.bookingCalendarEventTitle(
            booking.serviceName,
            booking.masterName,
          ),
        );
        expect(args['location'], booking.addressLine);
        expect(args['startDate'], booking.startAt.millisecondsSinceEpoch);
        expect(args['endDate'], booking.endAt.millisecondsSinceEpoch);

        // Success path: no error SnackBar.
        expect(find.text(l10n.bookingAddToCalendarError), findsNothing);
      },
    );

    testWidgets(
      'a SALON booking titles the Event with the SALON name, not the master '
      '(provider = salonName ?? masterName)',
      (tester) async {
        // The detail call site's provider is `booking.salonName ?? masterName`.
        // Every other add-to-calendar test drives the independent-master path
        // (salonName == null → masterName); this pins the salon branch of the
        // ternary so a refactor can't silently drop the salon name from the
        // Event title.
        const String salonName = 'Салон «Вельвет»';
        final Booking booking = _booking(
          status: BookingStatus.confirmed,
          salonName: salonName,
        );
        await _pumpDetail(tester, booking);
        final AppLocalizations l10n = _l10n(tester);

        final Finder calendar = find.byKey(
          const Key('booking-detail-add-calendar'),
        );
        await tester.ensureVisible(calendar);
        await tester.pumpAndSettle();
        await tester.tap(calendar);
        await tester.pumpAndSettle();

        final Map<Object?, Object?> args =
            calls.single.arguments as Map<Object?, Object?>;
        expect(
          args['title'],
          l10n.bookingCalendarEventTitle(booking.serviceName, salonName),
        );
        // The master's name must NOT be the provider on a salon booking.
        expect(
          args['title'],
          isNot(
            l10n.bookingCalendarEventTitle(
              booking.serviceName,
              booking.masterName,
            ),
          ),
          reason: 'salonName wins the provider slot when present',
        );
      },
    );

    testWidgets(
      'the calendar Event carries the STRUCTURED facts (service / provider / '
      'date-time / address / price / status) and NO free-text note or PII '
      '(change #3)',
      (tester) async {
        // A CONFIRMED booking that DOES carry every free-text note the model
        // holds — none may surface in the calendar payload (privacy boundary),
        // yet the structured facts MUST (the description is now non-null).
        const String secretClientNote = 'СЕКРЕТНА КЛІЄНТСЬКА НОТАТКА 555-77';
        const String secretProviderNote = 'ВНУТРІШНЯ НОТАТКА МАЙСТРА xyz';
        const String secretCancelNote = 'ПРИЧИНА СКАСУВАННЯ qwerty';
        final Booking booking = _booking(
          status: BookingStatus.confirmed,
          clientComment: secretClientNote,
          providerComment: secretProviderNote,
          clientCancellationNote: secretCancelNote,
        );
        await _pumpDetail(tester, booking);
        final AppLocalizations l10n = _l10n(tester);

        final Finder calendar = find.byKey(
          const Key('booking-detail-add-calendar'),
        );
        await tester.ensureVisible(calendar);
        await tester.pumpAndSettle();
        await tester.tap(calendar);
        await tester.pumpAndSettle();

        final Map<Object?, Object?> args =
            calls.single.arguments as Map<Object?, Object?>;

        // The structured description is now POPULATED (change #3 reversed the
        // old "desc stays null" premise). Assert every label line is present
        // via its l10n key — never a raw Cyrillic literal.
        final String desc = args['desc'] as String;
        expect(desc, isNotEmpty);
        for (final String label in <String>[
          l10n.bookingCalendarNoteService,
          l10n.bookingCalendarNoteMaster, // independent-master booking
          l10n.bookingCalendarNoteDateTime,
          l10n.bookingCalendarNoteAddress,
          l10n.bookingCalendarNotePrice,
          l10n.bookingCalendarNoteStatus,
        ]) {
          expect(
            desc.contains(label),
            isTrue,
            reason: 'structured description must carry the «$label» line',
          );
        }
        // And the real values behind those labels.
        expect(desc.contains(booking.serviceName), isTrue);
        expect(desc.contains(booking.masterName), isTrue);
        expect(desc.contains(booking.addressLine!), isTrue);
        expect(desc.contains(l10n.bookingStatusConfirmed), isTrue);

        // NONE of the three free-text notes may ride into ANY Event field —
        // there is no builder parameter that can carry them (privacy guard).
        final String payload = args.values.map((Object? v) => '$v').join('|');
        for (final String secret in <String>[
          secretClientNote,
          secretProviderNote,
          secretCancelNote,
        ]) {
          expect(
            payload.contains(secret),
            isFalse,
            reason: 'free-text note must not leak into any Event field',
          );
        }
      },
    );

    testWidgets('is ABSENT on a COMPLETED booking (CONFIRMED-only)', (
      tester,
    ) async {
      await _pumpDetail(tester, _booking(status: BookingStatus.completed));

      expect(
        find.byKey(const Key('booking-detail-add-calendar')),
        findsNothing,
      );
      expect(calls, isEmpty);
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

  // -------------------------------------------------------------------------
  // Change #1 — the back affordance holds a FIXED Y across loading → data.
  //
  // The loading/error skeleton's top inset was changed `xs`→`lg` to match the
  // loaded scaffold's, so `Key('booking-detail-back')` does not jump down mid
  // page-open. Pump with a DEFERRED provider (Completer-backed → loading branch
  // first), capture the back button's top-left `dy` on the loading frame,
  // complete the future, settle, and assert the SAME `dy` on the loaded frame.
  // Pure geometry — Impeller-independent, no golden.
  // -------------------------------------------------------------------------

  group('back-arrow invariant Y (loading → data)', () {
    testWidgets(
      'the back affordance keeps the same top Y from the loading skeleton to '
      'the loaded body',
      (tester) async {
        final Booking booking = _booking(status: BookingStatus.confirmed);
        final Completer<Booking> gate = Completer<Booking>();
        final _MockBookingRepository repo = _MockBookingRepository();

        await tester.pumpApp(
          BookingDetailScreen(bookingId: booking.id),
          overrides: <Object>[
            screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
            bookingRepositoryProvider.overrideWithValue(repo),
            // Deferred: the detail future never resolves until we complete the
            // gate, so the first pump renders the loading skeleton.
            bookingDetailProvider(
              booking.id,
            ).overrideWith((ref) => gate.future),
          ],
        );
        await tester.pump(); // loading frame

        final Finder back = find.byKey(const Key('booking-detail-back'));
        expect(back, findsOneWidget, reason: 'skeleton shows the back arrow');
        final double loadingDy = tester.getTopLeft(back).dy;

        // Resolve → the body swaps in.
        gate.complete(booking);
        await tester.pumpAndSettle();

        // The loaded body is now up (its footer cancel button only exists on
        // the populated screen, never the skeleton).
        expect(find.byKey(const Key('booking-detail-cancel')), findsOneWidget);
        final double loadedDy = tester
            .getTopLeft(find.byKey(const Key('booking-detail-back')))
            .dy;

        expect(
          loadedDy,
          loadingDy,
          reason:
              'the back arrow must not jump down when the skeleton swaps to the '
              'loaded body (loading inset lg == scaffold inset lg)',
        );
      },
    );

    testWidgets(
      'the back affordance keeps the same top Y from the ERROR skeleton to the '
      'loaded body (error inset lg == scaffold inset lg)',
      (tester) async {
        // The `_DetailError` skeleton got the SAME xs→lg top-inset fix as
        // `_DetailLoading`. A fake that FAILS the first build and succeeds the
        // second lets us render the error skeleton, then retry into data —
        // proving the back arrow's Y holds across error→data too.
        final Booking booking = _booking(status: BookingStatus.confirmed);
        int builds = 0;
        final _MockBookingRepository repo = _MockBookingRepository();

        await tester.pumpApp(
          BookingDetailScreen(bookingId: booking.id),
          overrides: <Object>[
            screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
            bookingRepositoryProvider.overrideWithValue(repo),
            bookingDetailProvider(booking.id).overrideWith((ref) async {
              builds++;
              if (builds == 1) throw Exception('load failed');
              return booking;
            }),
          ],
          // Disable Riverpod's default failed-build backoff retry so the error
          // state stays put (and leaves no pending Timer) until we tap retry.
          retry: (_, _) => null,
        );
        await tester.pumpAndSettle();

        // Error frame — the skeleton shows the back arrow and the retry button.
        final Finder back = find.byKey(const Key('booking-detail-back'));
        expect(back, findsOneWidget, reason: 'error skeleton shows back arrow');
        expect(
          find.byKey(const Key('booking-detail-error-retry')),
          findsOneWidget,
        );
        final double errorDy = tester.getTopLeft(back).dy;

        // Retry → `ref.invalidate` re-resolves the provider to data.
        await tester.tap(find.byKey(const Key('booking-detail-error-retry')));
        await tester.pumpAndSettle();

        // The loaded body is now up (its footer cancel button only exists on
        // the populated screen, never the error skeleton).
        expect(find.byKey(const Key('booking-detail-cancel')), findsOneWidget);
        final double loadedDy = tester
            .getTopLeft(find.byKey(const Key('booking-detail-back')))
            .dy;

        expect(
          loadedDy,
          errorDy,
          reason:
              'the back arrow must not jump down when the error skeleton retries '
              'into the loaded body (error inset lg == scaffold inset lg)',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Change #4 — «Додати в календар» relocated from the scroll-body pill to a
  // header icon, and the footer collapsed to the 2-button stack.
  // -------------------------------------------------------------------------

  group('calendar trigger relocation (header, not body pill)', () {
    testWidgets(
      'on a CONFIRMED booking the calendar icon is in the HEADER, the body pill '
      'is gone, and the footer is exactly Перенести + Скасувати',
      (tester) async {
        await _pumpDetail(tester, _booking(status: BookingStatus.confirmed));

        // The header icon is present…
        expect(
          find.byKey(const Key('booking-detail-add-calendar')),
          findsOneWidget,
        );
        // …and it is a matched pair with the back button in the same header row
        // (shares its top Y — a sanity check that it lives in the header, not
        // the body).
        expect(
          tester
              .getTopLeft(find.byKey(const Key('booking-detail-add-calendar')))
              .dy,
          tester.getTopLeft(find.byKey(const Key('booking-detail-back'))).dy,
        );

        // The old scroll-body `CalendarButton` pill is ABSENT on this surface.
        expect(find.byType(CalendarButton), findsNothing);

        // The footer is the clean two-button stack — nothing more, nothing
        // less.
        expect(
          find.byKey(const Key('booking-detail-reschedule')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('booking-detail-cancel')), findsOneWidget);
      },
    );

    testWidgets('tapping the header calendar icon fires _onAddToCalendar', (
      tester,
    ) async {
      final List<MethodCall> calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_kCalendarChannel, (MethodCall call) async {
            calls.add(call);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_kCalendarChannel, null),
      );

      await _pumpDetail(tester, _booking(status: BookingStatus.confirmed));

      await tester.tap(find.byKey(const Key('booking-detail-add-calendar')));
      await tester.pumpAndSettle();

      expect(calls, hasLength(1));
      expect(calls.single.method, 'add2Cal');
    });

    testWidgets(
      'on a non-CONFIRMED booking the header calendar icon is ABSENT',
      (tester) async {
        await _pumpDetail(tester, _booking(status: BookingStatus.completed));

        expect(
          find.byKey(const Key('booking-detail-add-calendar')),
          findsNothing,
        );
        expect(find.byType(CalendarButton), findsNothing);
      },
    );
  });
}
