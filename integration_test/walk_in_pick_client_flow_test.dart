// M553 (BOOK-79) — walk-in booking: pick an existing client, end to end,
// through the REAL router wiring, picker sheet, list / card repositories and
// the staff-booking wire request (fake backend).
//
// What only this tier proves (the widget tier stubs the launcher):
//   • the ROUTE binds the picker to the role's scope (D1): an independent
//     master lists `GET /masters/me/clients`; a salon owner lists
//     `GET /salons/{salonId}/clients` of the salon being booked, with no
//     `masterId` narrowing; the card is read from that same scope;
//   • the pick reaches the wire request as a plain walk-in guest
//     `{name, surname, phone}` (D2) — no client id anywhere in the body;
//   • a SALON_MASTER never gets the control: `/salon/bookings/new` is not
//     reachable for the role, so no picker can render;
//   • «×» clears the hint chip only (D3 — the fields keep their text) and a
//     field edited after the pick wins on the wire.
//
// The fake list endpoint does not scope rows by caller (the server does,
// B550 D1); this file pins the ENDPOINT the app calls for each role instead —
// with a SECOND salon wired too, so a wrong salon id is served and recorded
// (never a silent 404). The fake filters `q` by display name; the phone
// search test opts into `clientSearchMatchesPhone` (B550 phone matching).
//
// QA 2026-11-25 adds: owner MASTER MODE (`/owner/master/bookings/new`) and
// SALON_ADMIN scopes; digits typed in the search reach the wire as `q`; and
// the prefill edge cases end to end (surname only, blank names, a non-E.164
// phone, fields editable after a pick).
//
// CLOCK: the harness pins `clockProvider` to `kFixedNow`; `_kyivToday` derives
// from that SAME clock (`project_test_clock_coherence_invariant`).
//
// Standalone run (one file per invocation):
//   flutter test integration_test/walk_in_pick_client_flow_test.dart -d flutter-tester

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/core/media/beautica_image.dart'
    show debugMediaCacheManager;
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart'
    show NeumorphicButton;
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_create_booking_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/walk_in_guest_step_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/walk_in_service_step_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_wizard_steps.dart'
    show ClientStep;
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/features/clients/application/client_list_controller.dart'
    show kClientSearchDebounce;
import 'package:beautica_mobile/features/clients/presentation/widgets/client_list_view.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_picker_sheet.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_bookings_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/fake_media_cache.dart';
import '../test/helpers/pump_app.dart';
import '../test/helpers/rendered_image_url.dart';
import 'support/app_harness.dart';
import 'support/fake_backend.dart';

final DateTime _kyivToday = kyivToday(() => kFixedNow);

const String _kMePath = '/api/v1/masters/me/clients';
const String _kOwnerSalonPath =
    '/api/v1/salons/${FakeBackend.kOwnerSalonId}/clients';

// Named constants, never literals at a `find.text` call site
// (`scripts/forbid_cyrillic_finder.sh`).
const String _kGuestFirst = 'Ірина';
const String _kGuestLast = 'Коваль';
const String _kGuestPhone = '+380671234567';
const String _kGuestPhoneShown = '+380 67 123 45 67';
const String _kRegFirst = 'Оксана';
const String _kRegLast = 'Мельник';
const String _kRegPhone = '+380501112233';
const String _kSearch = 'Ірин';
const String _kGuestInitials = 'ІК';

// 2026-11-25 — the picked client's display-only photo + ★ (CLI-80 card →
// `ClientPrefill` → `WalkInGuest`, never on the wire).
const String _kPickedAvatar = 'https://media.test/avatars/picked-client.png';
const double _kPickedRating = 4.5;
const int _kPickedRatingCount = 3;

/// Digits of [_kGuestPhone] as a provider types them (B550 phone search).
const String _kPhoneSearch = '067123';

const String _kAdminSalonId = 'salon-admin-1';
const String _kAdminSalonPath = '/api/v1/salons/$_kAdminSalonId/clients';

/// A salon the caller does NOT book for — wired so a wrong id is recorded.
const String _kOtherSalonId = 'salon-other-9';
const String _kOwnerMasterRowId = 'master-row-owner-1';

// Prefill edge-case clients (seeded only with `edges: true`).
const String _kSurnameOnly = 'Шевчук';
const String _kSurnameOnlyPhone = '+380931112233';
const String _kSurnameOnlyPhoneShown = '+380 93 111 22 33';
const String _kTypedFirst = 'Ганна';
const String _kNamelessPhone = '+380505556677';
const String _kNamelessPhoneShown = '+380 50 555 66 77';
const String _kNoE164First = 'Марта';
const String _kNoE164Last = 'Бойко';

const Key _first = Key('master-create-booking-first-name');
const Key _last = Key('master-create-booking-last-name');
const Key _phone = Key('master-create-booking-phone');
const Key _next = Key('master-create-booking-client-next');

/// A guest (`b-iryna`, the search target) and a registered client
/// (`u-oksana`, BLOCKED — still pickable, D5). Cards carry the B550 name
/// parts. Served on the `me` scope and on every salon in [salonIds].
///
/// [edges] adds three prefill edge cases: `b-shevchuk` (surname only),
/// `b-nameless` (blank name parts, no display name, E.164 phone) and
/// `u-noe164` (names, phone NOT E.164).
void _seedClients(
  FakeBackend fb, {
  List<String> salonIds = const <String>[
    FakeBackend.kOwnerSalonId,
    _kOtherSalonId,
  ],
  bool edges = false,
}) {
  fb
    ..wireClientList(salonIds: salonIds)
    ..clientRows.addAll(<Map<String, dynamic>>[
      <String, dynamic>{
        'kind': 'REGISTERED',
        'userId': 'u-oksana',
        'displayName': '$_kRegFirst $_kRegLast',
        'lastVisitAt': '2026-06-07T10:00:00Z',
        'completedVisits': 3,
        'ratingCount': 0,
        'blocked': true,
      },
      <String, dynamic>{
        'kind': 'GUEST',
        'guestBookingId': 'b-iryna',
        'displayName': '$_kGuestFirst $_kGuestLast',
        'lastVisitAt': '2026-06-01T10:00:00Z',
        'completedVisits': 2,
        'ratingCount': 0,
        'blocked': false,
      },
    ])
    ..clientCards['u-oksana'] = <String, dynamic>{
      'kind': 'REGISTERED',
      'userId': 'u-oksana',
      'displayName': '$_kRegFirst $_kRegLast',
      'firstName': _kRegFirst,
      'lastName': _kRegLast,
      'phone': _kRegPhone,
      'blocked': true,
      'ratingCount': 0,
      'ratingDistribution': <Map<String, int>>[],
    }
    ..clientCards['b-iryna'] = <String, dynamic>{
      'kind': 'GUEST',
      'guestBookingId': 'b-iryna',
      'displayName': '$_kGuestFirst $_kGuestLast',
      'firstName': _kGuestFirst,
      'lastName': _kGuestLast,
      'phone': _kGuestPhone,
      'blocked': false,
      'ratingCount': 0,
      'ratingDistribution': <Map<String, int>>[],
    };
  if (edges) {
    fb
      ..clientRows.addAll(<Map<String, dynamic>>[
        _guestRow('b-shevchuk', _kSurnameOnly),
        _guestRow('b-nameless', 'Гість'),
        <String, dynamic>{
          'kind': 'REGISTERED',
          'userId': 'u-noe164',
          'displayName': '$_kNoE164First $_kNoE164Last',
          'lastVisitAt': '2026-05-01T10:00:00Z',
          'completedVisits': 1,
          'ratingCount': 0,
          'blocked': false,
        },
      ])
      ..clientCards['b-shevchuk'] = _card(
        'GUEST',
        'b-shevchuk',
        displayName: _kSurnameOnly,
        lastName: _kSurnameOnly,
        phone: _kSurnameOnlyPhone,
      )
      // Blank parts and NO display name: nothing to put in either name field.
      ..clientCards['b-nameless'] = _card(
        'GUEST',
        'b-nameless',
        firstName: '  ',
        lastName: '',
        phone: _kNamelessPhone,
      )
      // A registered client whose phone is not E.164 → never prefilled.
      ..clientCards['u-noe164'] = _card(
        'REGISTERED',
        'u-noe164',
        displayName: '$_kNoE164First $_kNoE164Last',
        firstName: _kNoE164First,
        lastName: _kNoE164Last,
        phone: '0501234567',
      );
  }
  fb.wireClientCard(salonIds: salonIds);
}

Map<String, dynamic> _guestRow(String id, String name) => <String, dynamic>{
  'kind': 'GUEST',
  'guestBookingId': id,
  'displayName': name,
  'lastVisitAt': '2026-05-15T10:00:00Z',
  'completedVisits': 1,
  'ratingCount': 0,
  'blocked': false,
};

Map<String, dynamic> _card(
  String kind,
  String id, {
  String? displayName,
  String? firstName,
  String? lastName,
  String? phone,
}) => <String, dynamic>{
  'kind': kind,
  kind == 'GUEST' ? 'guestBookingId' : 'userId': id,
  'displayName': ?displayName,
  'firstName': ?firstName,
  'lastName': ?lastName,
  'phone': ?phone,
  'blocked': false,
  'ratingCount': 0,
  'ratingDistribution': <Map<String, int>>[],
};

/// Gives the card [id] a photo + ★ (read by the fake per request, so this
/// works after `_seedClients`).
void _ratePickedCard(FakeBackend fb, String id) {
  fb.clientCards[id] = <String, dynamic>{
    ...fb.clientCards[id]!,
    'avatarUrl': _kPickedAvatar,
    'ratingAvg': _kPickedRating,
    'ratingCount': _kPickedRatingCount,
  };
}

/// Lets `RemoteImage` build its network `Image` (allow-listed host, no I/O).
void _allowMedia() {
  MediaConfig.debugAllowedHosts = <String>{'media.test'};
  debugMediaCacheManager = FakeMediaCacheManager(mediaLoadingForever);
  addTearDown(() {
    debugMediaCacheManager = null;
    MediaConfig.debugAllowedHosts = null;
  });
}

Finder _inReadout(Finder card, String text) => find.descendant(
  of: find.descendant(of: card, matching: find.byType(MasterRatingReadout)),
  matching: find.text(text),
);

/// The review/done card shows the PICKED client: their photo and ★ readout.
void _expectPickedIdentity(WidgetTester tester, Finder card) {
  expect(card, findsOneWidget);
  expect(renderedImageUrls(tester, within: card), <String>[_kPickedAvatar]);
  expect(_inReadout(card, _kPickedRating.toStringAsFixed(1)), findsOneWidget);
  expect(_inReadout(card, '($_kPickedRatingCount)'), findsOneWidget);
}

/// The card shows a hand-typed identity: monogram, «—», no photo.
void _expectTypedIdentity(WidgetTester tester, Finder card, String initials) {
  expect(card, findsOneWidget);
  expect(renderedImageUrls(tester, within: card), isEmpty);
  expect(find.descendant(of: card, matching: find.text(initials)), findsOne);
  expect(_inReadout(card, MasterStrip.noRatingLabel), findsOneWidget);
}

bool _nextEnabled(WidgetTester tester) =>
    tester.widget<NeumorphicButton>(find.byKey(_next)).onPressed != null;

String _text(WidgetTester tester, Key key) => tester
    .widget<EditableText>(
      find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
    )
    .controller
    .text;

/// «Далі» lies wholly inside the 800x600 surface WITHOUT scrolling while no
/// client is picked (no chip) — the full-width picker button (2026-11-25)
/// still leaves the empty form above the fold.
void _expectNextOnScreen(WidgetTester tester) {
  final Rect next = tester.getRect(find.byKey(_next));
  final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(next.top, greaterThanOrEqualTo(0));
  expect(
    next.bottom,
    lessThanOrEqualTo(screen.height),
    reason: '«Далі» must be tappable without scrolling',
  );
}

/// Opens the picker, optionally searches, and picks the row [id].
/// [onResults] runs after the search settles, before the row is tapped.
Future<void> _pick(
  WidgetTester tester,
  String id, {
  String? search,
  void Function()? onResults,
}) async {
  await tester.ensureVisible(find.byKey(ClientStep.pickClientKey));
  await tester.tap(find.byKey(ClientStep.pickClientKey));
  await AppHarness.settle(tester);
  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(ClientPickerSheet.sheetKey),
  );
  final Finder row = find.byKey(Key('client-row-$id'));
  await AppHarness.pumpUntilFound(tester, row);
  if (search != null) {
    await tester.enterText(find.byKey(ClientListView.searchKey), search);
    await tester.pump();
    // `pumpAndSettle` never fires the debounce Timer — pump it explicitly.
    await tester.pump(kClientSearchDebounce);
    await tester.pump();
    await AppHarness.settle(tester);
  }
  onResults?.call();
  await tester.ensureVisible(row);
  await AppHarness.settle(tester);
  await tester.tap(row);
  await AppHarness.settle(tester);
  await AppHarness.pumpUntilGone(
    tester,
    find.byKey(ClientPickerSheet.sheetKey),
  );
}

/// IM: «Мої записи» → «+» → the guest step.
Future<GoRouter> _openMasterGuestStep(
  WidgetTester tester,
  FakeBackend fb, {
  bool edges = false,
}) async {
  fb
    ..seedManyBookingsDataset(const <Map<String, dynamic>>[])
    ..availableSlotUtcStarts = const <(int, int)>[(7, 0)];
  _seedClients(fb, edges: edges);
  final GoRouter router = await AppHarness.boot(tester, fb);
  fb.seedEffectiveSchedule(<Map<String, dynamic>>[
    FakeBackend.seedEffectiveScheduleDay(
      _kyivToday,
      intervals: const <(String, String)>[('09:00:00', '21:00:00')],
    ),
  ]);
  await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
  await tester.tap(find.byKey(const Key('master-nav-tile-1')));
  await AppHarness.settle(tester);
  await tester.tap(find.byKey(const Key('master-bookings-add')));
  await AppHarness.settle(tester);
  AppHarness.expectNestedPushLocation(router, RouteNames.masterBookingNew);
  expect(find.byType(WalkInGuestStepScreen), findsOneWidget);
  return router;
}

/// IM: guest step «Далі» → one service → today → first free slot → confirm
/// → submit. Returns the wire guest payload.
Future<Map<String, dynamic>> _submitMasterWalkIn(
  WidgetTester tester,
  FakeBackend fb, {
  bool scroll = true,
  void Function()? onConfirm,
}) async {
  if (scroll) {
    await tester.ensureVisible(find.byKey(_next));
    await AppHarness.settle(tester);
  } else {
    _expectNextOnScreen(tester);
  }
  await tester.tap(find.byKey(_next));
  await AppHarness.settle(tester);
  expect(find.byType(WalkInServiceStepScreen), findsOneWidget);

  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(const Key('mcb_service_card_assign-1')),
  );
  await tester.tap(find.byKey(const Key('mcb_service_card_assign-1')));
  await AppHarness.settle(tester);
  await tester.tap(find.byKey(const Key('booking-summary-cta')));
  await AppHarness.settle(tester);

  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(Key('booking-calendar-day-${_kyivToday.day}')),
  );
  await tester.tapCalendarDay(_kyivToday.day);
  await AppHarness.settle(tester);
  await tester.tap(find.byKey(const Key('booking-summary-cta')));
  await AppHarness.settle(tester);
  final Finder chip = find
      .byWidgetPredicate((Widget w) => w is SlotChip && w.available)
      .first;
  await AppHarness.pumpUntilFound(tester, chip);
  await tester.ensureVisible(chip);
  await AppHarness.settle(tester);
  await tester.tap(chip);
  await AppHarness.settle(tester);
  await tester.tap(find.byKey(const Key('booking-summary-cta')));
  await AppHarness.settle(tester);
  expect(find.byType(BookingConfirmScreen), findsOneWidget);
  onConfirm?.call();

  await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
  await AppHarness.settle(tester);

  expect(fb.createStaffBookingCalls, 1);
  final Map<String, dynamic> body = fb.lastStaffBookingRequestBody!;
  expect(
    body.keys.toSet(),
    <String>{'masterServiceIds', 'startsAt', 'guest'},
    reason: 'D2 — a plain walk-in: no client id field in the request',
  );
  return (body['guest'] as Map).cast<String, dynamic>();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('M553 IM: pick from OWN clients (search) → fields prefilled → '
      'the walk-in submits those values, no client id', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.independentMaster;
      await _openMasterGuestStep(tester, fb);
      expect(find.byKey(ClientStep.pickClientKey), findsOneWidget);
      _expectNextOnScreen(tester);

      await _pick(tester, 'b-iryna', search: _kSearch);

      // D1 — own list only: every list request hit `/masters/me/clients`.
      expect(fb.clientListCalls, isNotEmpty);
      expect(
        fb.clientListCalls.map((ClientListCall c) => c.path).toSet(),
        <String>{_kMePath},
      );
      expect(fb.clientListCalls.last.q, _kSearch);
      expect(
        fb.clientCardCalls.where((String c) => c.startsWith('card ')),
        <String>['card $_kMePath/guests/b-iryna page=null masterId=null'],
      );

      expect(_text(tester, _first), _kGuestFirst);
      expect(_text(tester, _last), _kGuestLast);
      expect(_text(tester, _phone), _kGuestPhoneShown);
      expect(find.byKey(ClientStep.pickedChipKey), findsOneWidget);

      final Map<String, dynamic> guest = await _submitMasterWalkIn(tester, fb);
      expect(guest, <String, dynamic>{
        'name': _kGuestFirst,
        'surname': _kGuestLast,
        'phone': _kGuestPhone,
      });
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('M553 IM: the picker is a real BUTTON; the picked client\'s '
      'photo + ★ reach the review card and the done screen, never the wire', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final semantics = tester.ensureSemantics();
      _allowMedia();
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.independentMaster;
      await _openMasterGuestStep(tester, fb);
      _ratePickedCard(fb, 'b-iryna');

      // Found by key AND exposed to a screen reader as a button.
      expect(
        tester.getSemantics(find.byKey(ClientStep.pickClientKey)),
        isSemantics(isButton: true, hasTapAction: true),
      );

      await _pick(tester, 'b-iryna');

      final Map<String, dynamic> guest = await _submitMasterWalkIn(
        tester,
        fb,
        onConfirm: () => _expectPickedIdentity(
          tester,
          find.byKey(const Key('booking-confirm-guest-card')),
        ),
      );
      // Display-only: photo + rating never on the wire (D2).
      expect(guest, <String, dynamic>{
        'name': _kGuestFirst,
        'surname': _kGuestLast,
        'phone': _kGuestPhone,
      });

      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('booking-success-guest-card')),
      );
      expect(find.byType(BookingSuccessScreen), findsOneWidget);
      _expectPickedIdentity(
        tester,
        find.byKey(const Key('booking-success-guest-card')),
      );
      semantics.dispose();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('M553 IM: «×» clears the chip only (fields stay); an edit after '
      'the pick wins on the wire', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.independentMaster;
      _allowMedia();
      await _openMasterGuestStep(tester, fb);
      _ratePickedCard(fb, 'b-iryna');

      await _pick(tester, 'b-iryna');
      expect(find.byKey(ClientStep.pickedChipKey), findsOneWidget);

      await tester.ensureVisible(find.byKey(ClientStep.clearPickKey));
      await tester.tap(find.byKey(ClientStep.clearPickKey));
      await AppHarness.settle(tester);
      expect(find.byKey(ClientStep.pickedChipKey), findsNothing);
      expect(_text(tester, _first), _kGuestFirst);
      expect(_text(tester, _last), _kGuestLast);
      expect(_text(tester, _phone), _kGuestPhoneShown);

      await tester.enterText(find.byKey(_phone), '0509998877');
      await tester.pump();

      // Chip cleared → «Далі» is tapped where it stands, no scrolling.
      // The edited phone is no longer the picked client: the review card
      // drops their photo + ★ (`walkInGuestFrom`).
      final Map<String, dynamic> guest = await _submitMasterWalkIn(
        tester,
        fb,
        scroll: false,
        onConfirm: () => _expectTypedIdentity(
          tester,
          find.byKey(const Key('booking-confirm-guest-card')),
          _kGuestInitials,
        ),
      );
      expect(guest, <String, dynamic>{
        'name': _kGuestFirst,
        'surname': _kGuestLast,
        'phone': '+380509998877',
      });
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('M553 owner: the salon wizard picks from the booked SALON\'s '
      'clients (blocked client pickable) → the walk-in carries the client\'s '
      'phone', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..salonBoardBookings = <Map<String, dynamic>>[];
      _allowMedia();
      _seedClients(fb);
      _ratePickedCard(fb, 'u-oksana');
      await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(SalonShellScreen),
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('salon-nav-tile-1')),
        timeout: const Duration(seconds: 20),
      );
      await tester.tap(find.byKey(const Key('salon-nav-tile-1')));
      await AppHarness.settle(tester);
      expect(find.byType(SalonBookingsScreen), findsOneWidget);
      await tester.tap(find.byKey(const Key('master-bookings-add')));
      await AppHarness.settle(tester);
      expect(find.byType(SalonCreateBookingScreen), findsOneWidget);
      expect(find.byKey(ClientStep.pickClientKey), findsOneWidget);
      _expectNextOnScreen(tester);

      await _pick(tester, 'u-oksana');

      // D1 — the whole salon list, never narrowed to a master row.
      expect(
        fb.clientListCalls.map((ClientListCall c) => c.path).toSet(),
        <String>{_kOwnerSalonPath},
      );
      expect(
        fb.clientListCalls.every((ClientListCall c) => c.masterId == null),
        isTrue,
      );
      expect(_text(tester, _first), _kRegFirst);
      expect(_text(tester, _last), _kRegLast);
      expect(_text(tester, _phone), '+380 50 111 22 33');

      await tester.ensureVisible(find.byKey(_next));
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(_next));
      await AppHarness.settle(tester);

      final Finder svc = find.byKey(
        const Key('mcb_service_card_${FakeBackend.kSalonWizSvcA}'),
      );
      await AppHarness.pumpUntilFound(tester, svc);
      await tester.ensureVisible(svc);
      await tester.tap(svc);
      await tester.pump();
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);

      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('salon-create-booking-date-calendar')),
      );
      await tester.tapCalendarDay(_kyivToday.day);
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('salon-create-booking-date-next')));
      await AppHarness.settle(tester);

      final Finder tile = find.byKey(
        const Key('salon-master-tile-${FakeBackend.kSalonWizardMasterFull}'),
      );
      await AppHarness.pumpUntilFound(tester, tile);
      await tester.ensureVisible(tile);
      await AppHarness.settle(tester);
      await tester.tap(tile);
      await AppHarness.settle(tester);
      final Finder chip = find
          .byWidgetPredicate((Widget w) => w is SlotChip && w.available)
          .first;
      await AppHarness.pumpUntilFound(tester, chip);
      await tester.ensureVisible(chip);
      await AppHarness.settle(tester);
      await tester.tap(chip);
      await AppHarness.settle(tester);

      final Finder submit = find.byKey(
        const Key('salon-create-booking-submit-cta'),
      );
      await AppHarness.pumpUntilFound(tester, submit);
      // The wizard's confirm step shows the picked client (photo + ★).
      _expectPickedIdentity(
        tester,
        find.byKey(const Key('master-create-booking-guest-card')),
      );
      await tester.ensureVisible(submit);
      await AppHarness.settle(tester);
      await tester.tap(submit);
      await AppHarness.settle(tester);

      expect(fb.createSalonWizardBookingCalls, 1);
      final Map<String, dynamic> body = fb.lastSalonWizardBookingRequestBody!;
      expect(
        body.keys.toSet(),
        <String>{'masterServiceIds', 'startsAt', 'guest'},
        reason: 'D2 — a plain walk-in: no client id field in the request',
      );
      expect(body['guest'], <String, dynamic>{
        'name': _kRegFirst,
        'surname': _kRegLast,
        'phone': _kRegPhone,
      });
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('M553 SALON_MASTER: the staff booking client step is not '
      'reachable — no picker control', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()..currentRole = UserRole.salonMaster;
      _seedClients(fb);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonMaster);
      await AppHarness.settle(tester);

      unawaited(
        router.push(
          RouteNames.salonStaffBookingNew,
          extra: FakeBackend.kOwnerSalonId,
        ),
      );
      await AppHarness.settle(tester);

      expect(find.byType(SalonCreateBookingScreen), findsNothing);
      expect(find.byType(ClientStep), findsNothing);
      expect(find.byKey(ClientStep.pickClientKey), findsNothing);
      expect(fb.clientListCalls, isEmpty);
      expect(canPickClients(UserRole.salonMaster), isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('M553 owner MASTER MODE: /owner/master/bookings/new picks from '
      'the owner\'s OWN salon — never /masters/me, never another salon, no '
      'masterId narrowing', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb =
          FakeBackend(
              masterRowId: _kOwnerMasterRowId,
              masterSalonId: FakeBackend.kOwnerSalonId,
              wireOwnRowSchedule: true,
              wireOwnRowServices: true,
            )
            ..currentRole = UserRole.salonOwner
            ..hasMasterProfile = true;
      fb
        ..seedManyBookingsDataset(const <Map<String, dynamic>>[])
        ..ownerMasterRowBookingIds = <String>{};
      _seedClients(fb);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);

      // Master mode: the salon shell's «Профіль» → «Записи» → «+».
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('salon-nav-tile-4')),
      );
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.ownerMasterProfile);
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('master-nav-tile-1')),
      );
      await AppHarness.settle(tester);
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(MasterBookingsScreen),
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('master-bookings-add')),
      );
      await AppHarness.settle(tester);
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.ownerMasterBookingNew,
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientStep.pickClientKey),
      );

      await _pick(tester, 'u-oksana');

      expect(
        fb.clientListCalls.map((ClientListCall c) => c.path).toSet(),
        <String>{_kOwnerSalonPath},
        reason: 'D1 — the owner\'s own salon only',
      );
      expect(
        fb.clientListCalls.every((ClientListCall c) => c.masterId == null),
        isTrue,
      );
      expect(
        fb.clientCardCalls.where((String c) => c.startsWith('card ')),
        <String>[
          'card $_kOwnerSalonPath/users/u-oksana page=null masterId=null',
        ],
      );
      expect(_text(tester, _first), _kRegFirst);
      expect(_text(tester, _last), _kRegLast);
      expect(_text(tester, _phone), '+380 50 111 22 33');
      expect(find.byKey(ClientStep.pickedChipKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('M553 SALON_ADMIN: the salon wizard picks from the ADMIN\'s '
      'salon (`salons/{salonId}/clients` of the salon being booked) — never '
      'another salon', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonAdmin
        ..salonBoardBookings = <Map<String, dynamic>>[];
      _seedClients(
        fb,
        salonIds: const <String>[_kAdminSalonId, FakeBackend.kOwnerSalonId],
      );
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonAdmin);
      await AppHarness.settle(tester);

      unawaited(
        router.push(RouteNames.salonStaffBookingNew, extra: _kAdminSalonId),
      );
      await AppHarness.settle(tester);
      expect(find.byType(SalonCreateBookingScreen), findsOneWidget);
      expect(find.byKey(ClientStep.pickClientKey), findsOneWidget);

      await _pick(tester, 'b-iryna');

      expect(
        fb.clientListCalls.map((ClientListCall c) => c.path).toSet(),
        <String>{_kAdminSalonPath},
      );
      expect(
        fb.clientCardCalls.where((String c) => c.startsWith('card ')),
        <String>[
          'card $_kAdminSalonPath/guests/b-iryna page=null masterId=null',
        ],
      );
      expect(_text(tester, _first), _kGuestFirst);
      expect(_text(tester, _last), _kGuestLast);
      expect(_text(tester, _phone), _kGuestPhoneShown);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('M553 IM: digits typed in the picker search go on the wire as '
      '`q` (B550 phone search) → the matching client is picked', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.independentMaster
        ..clientSearchMatchesPhone = true;
      await _openMasterGuestStep(tester, fb);

      await _pick(
        tester,
        'b-iryna',
        search: _kPhoneSearch,
        onResults: () {
          expect(fb.clientListCalls.last.path, _kMePath);
          expect(fb.clientListCalls.last.q, _kPhoneSearch);
          expect(fb.clientListCalls.last.page, 0);
          // The phone matched only Ірина: the other row is filtered out.
          expect(find.byKey(const Key('client-row-u-oksana')), findsNothing);
        },
      );

      expect(_text(tester, _first), _kGuestFirst);
      expect(_text(tester, _last), _kGuestLast);
      expect(_text(tester, _phone), _kGuestPhoneShown);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('M553 IM: a SURNAME-ONLY client leaves the first name EMPTY; '
      'the fields stay editable after the pick and the typed first name '
      'reaches the wire', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.independentMaster;
      await _openMasterGuestStep(tester, fb, edges: true);

      await _pick(tester, 'b-shevchuk');

      expect(_text(tester, _first), isEmpty);
      expect(_text(tester, _last), _kSurnameOnly);
      expect(_text(tester, _phone), _kSurnameOnlyPhoneShown);
      expect(find.byKey(ClientStep.pickedChipKey), findsOneWidget);
      expect(_nextEnabled(tester), isFalse);

      await tester.enterText(find.byKey(_first), _kTypedFirst);
      await tester.pump();
      expect(_text(tester, _first), _kTypedFirst);
      expect(_nextEnabled(tester), isTrue);

      final Map<String, dynamic> guest = await _submitMasterWalkIn(tester, fb);
      expect(guest, <String, dynamic>{
        'name': _kTypedFirst,
        'surname': _kSurnameOnly,
        'phone': _kSurnameOnlyPhone,
      });
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('M553 IM: blank name parts → both name fields EMPTY and no '
      'chip, the E.164 phone filled; a re-pick of a client whose phone is '
      'NOT E.164 clears that phone', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.independentMaster;
      await _openMasterGuestStep(tester, fb, edges: true);

      await _pick(tester, 'b-nameless');

      expect(_text(tester, _first), isEmpty);
      expect(_text(tester, _last), isEmpty);
      expect(_text(tester, _phone), _kNamelessPhoneShown);
      expect(find.byKey(ClientStep.pickedChipKey), findsNothing);
      expect(_nextEnabled(tester), isFalse);

      await _pick(tester, 'u-noe164');

      expect(_text(tester, _first), _kNoE164First);
      expect(_text(tester, _last), _kNoE164Last);
      expect(
        _text(tester, _phone),
        isEmpty,
        reason:
            'only an E.164 phone is prefilled; the previous pick\'s '
            'phone must not linger',
      );
      expect(_nextEnabled(tester), isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
