// M553 (BOOK-79) — ClientStep's additive client picker.
//
// The picker launcher is injected ([ClientStep.onPickClient]); the route binds
// it to the role's scope (covered by
// `integration_test/walk_in_pick_client_flow_test.dart`). Here it is a stub
// returning a canned [ClientPrefill], so the step's own behaviour is pinned:
//   • no launcher → no control (the step renders exactly as before);
//   • pick → the three fields are filled, «Далі» enabled;
//   • a part the client lacks leaves its field EMPTY (stale text cleared);
//   • «×» clears the hint chip only — the fields keep their text (D3);
//   • editing after a pick keeps the edited value;
//   • a dismissed sheet changes nothing.

import 'dart:async';

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_wizard_steps.dart';
import 'package:beautica_mobile/features/clients/domain/client_prefill.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const Key _first = Key('master-create-booking-first-name');
const Key _last = Key('master-create-booking-last-name');
const Key _phone = Key('master-create-booking-phone');
const Key _next = Key('master-create-booking-client-next');

class _Harness {
  final TextEditingController first = TextEditingController();
  final TextEditingController last = TextEditingController();
  final TextEditingController phone = TextEditingController();
  int pickCalls = 0;

  void dispose() {
    first.dispose();
    last.dispose();
    phone.dispose();
  }
}

Future<_Harness> _pump(
  WidgetTester tester, {
  Future<ClientPrefill?> Function()? pick,
}) async {
  final _Harness h = _Harness();
  addTearDown(h.dispose);
  final Future<ClientPrefill?> Function()? stub = pick;
  await tester.pumpApp(
    Scaffold(
      body: ClientStep(
        firstNameCtrl: h.first,
        lastNameCtrl: h.last,
        phoneCtrl: h.phone,
        onNext: () {},
        onPickClient: stub == null
            ? null
            : (BuildContext _) {
                h.pickCalls++;
                return stub();
              },
      ),
    ),
  );
  return h;
}

bool _nextEnabled(WidgetTester tester) =>
    tester.widget<NeumorphicButton>(find.byKey(_next)).onPressed != null;

Future<void> _tapPick(WidgetTester tester) async {
  await tester.tap(find.byKey(ClientStep.pickClientKey));
  await tester.pump();
}

void main() {
  testWidgets('no launcher → no picker control, no chip', (tester) async {
    await _pump(tester);
    expect(find.byKey(ClientStep.pickClientKey), findsNothing);
    expect(find.byKey(ClientStep.pickedChipKey), findsNothing);
    expect(find.byKey(_first), findsOneWidget);
  });

  testWidgets('the picker link has a >= 48x48 dp hit area and meets the '
      'Android tap-target guideline', (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pump(tester, pick: () async => null);
    final Size size = tester.getSize(find.byKey(ClientStep.pickClientKey));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('the picker is a full-width button between the intro and the '
      'first field (2026-11-25: the heading link did not read as a button)', (
    tester,
  ) async {
    await _pump(tester, pick: () async => null);
    final Finder button = find.byKey(ClientStep.pickClientKey);
    expect(button, findsOneWidget);
    expect(
      find.descendant(
        of: button,
        matching: find.byIcon(Icons.person_search_rounded),
      ),
      findsOneWidget,
    );
    final Rect rect = tester.getRect(button);
    final Rect first = tester.getRect(find.byKey(_first));
    // Full width: the same horizontal extent as the form fields.
    expect((rect.width - first.width).abs(), lessThanOrEqualTo(1));
    expect(rect.bottom, lessThanOrEqualTo(first.top));
  });

  testWidgets('pick → name, surname and masked phone filled; Next enabled; '
      'chip shows the name', (tester) async {
    final _Harness h = await _pump(
      tester,
      pick: () async => const ClientPrefill(
        firstName: 'Оксана',
        lastName: 'Мельник',
        phone: '+380671234567',
      ),
    );
    expect(
      find.text(lookupAppLocalizations(const Locale('uk')).walkInPickClientCta),
      findsOneWidget,
    );
    expect(_nextEnabled(tester), isFalse);

    await _tapPick(tester);

    expect(h.pickCalls, 1);
    expect(h.first.text, 'Оксана');
    expect(h.last.text, 'Мельник');
    expect(h.phone.text, '+380 67 123 45 67');
    expect(toE164UaPhone(h.phone.text), '+380671234567');
    expect(_nextEnabled(tester), isTrue);
    expect(
      find.descendant(
        of: find.byKey(ClientStep.pickedChipKey),
        // i18n-finder-ok: the picked client's name is data, not UI copy
        matching: find.text('Оксана Мельник'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('registered client without phone → names filled, phone EMPTY '
      '(stale text cleared), Next disabled until typed', (tester) async {
    final _Harness h = await _pump(
      tester,
      pick: () async =>
          const ClientPrefill(firstName: 'Марта', lastName: 'Бойко'),
    );
    await tester.enterText(find.byKey(_phone), '0501234567');
    await tester.pump();

    await _tapPick(tester);

    expect(h.first.text, 'Марта');
    expect(h.last.text, 'Бойко');
    expect(h.phone.text, isEmpty);
    expect(_nextEnabled(tester), isFalse);

    await tester.enterText(find.byKey(_phone), '0501234567');
    await tester.pump();
    expect(_nextEnabled(tester), isTrue);
  });

  testWidgets('a client without a surname leaves the surname field empty', (
    tester,
  ) async {
    final _Harness h = await _pump(
      tester,
      pick: () async =>
          const ClientPrefill(firstName: 'Ірина', phone: '+380631234567'),
    );
    await tester.enterText(find.byKey(_last), 'Стара');
    await tester.pump();

    await _tapPick(tester);

    expect(h.first.text, 'Ірина');
    expect(h.last.text, isEmpty);
    expect(_nextEnabled(tester), isFalse);
    expect(
      find.descendant(
        of: find.byKey(ClientStep.pickedChipKey),
        // i18n-finder-ok: the picked client's name is data, not UI copy
        matching: find.text('Ірина'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('«×» clears the chip only — the fields keep their text (D3)', (
    tester,
  ) async {
    final _Harness h = await _pump(
      tester,
      pick: () async => const ClientPrefill(
        firstName: 'Оксана',
        lastName: 'Мельник',
        phone: '+380671234567',
      ),
    );
    await _tapPick(tester);
    expect(find.byKey(ClientStep.pickedChipKey), findsOneWidget);

    await tester.tap(find.byKey(ClientStep.clearPickKey));
    await tester.pump();

    expect(find.byKey(ClientStep.pickedChipKey), findsNothing);
    expect(find.byKey(ClientStep.pickClientKey), findsOneWidget);
    expect(h.first.text, 'Оксана');
    expect(h.last.text, 'Мельник');
    expect(h.phone.text, '+380 67 123 45 67');
    expect(_nextEnabled(tester), isTrue);
  });

  testWidgets('edit after pick keeps the edited value', (tester) async {
    final _Harness h = await _pump(
      tester,
      pick: () async => const ClientPrefill(
        firstName: 'Оксана',
        lastName: 'Мельник',
        phone: '+380671234567',
      ),
    );
    await _tapPick(tester);

    await tester.enterText(find.byKey(_phone), '0509998877');
    await tester.pump();
    await tester.enterText(find.byKey(_first), 'Ксеня');
    await tester.pump();

    expect(toE164UaPhone(h.phone.text), '+380509998877');
    expect(h.first.text, 'Ксеня');
    expect(h.last.text, 'Мельник');
    expect(_nextEnabled(tester), isTrue);
  });

  testWidgets('dismissed sheet (null) changes nothing; no chip', (
    tester,
  ) async {
    final _Harness h = await _pump(tester, pick: () async => null);
    await tester.enterText(find.byKey(_first), 'Вручну');
    await tester.pump();

    await _tapPick(tester);

    expect(h.pickCalls, 1);
    expect(h.first.text, 'Вручну');
    expect(find.byKey(ClientStep.pickedChipKey), findsNothing);
  });

  testWidgets('a second tap while the sheet is open is ignored', (
    tester,
  ) async {
    final Completer<ClientPrefill?> sheet = Completer<ClientPrefill?>();
    final _Harness h = await _pump(tester, pick: () => sheet.future);

    await _tapPick(tester);
    await _tapPick(tester);
    expect(h.pickCalls, 1);

    sheet.complete(null);
    await tester.pump();
    await _tapPick(tester);
    expect(h.pickCalls, 2);
  });

  group('walkInGuestFrom', () {
    const ClientPrefill picked = ClientPrefill(
      firstName: 'Оксана',
      lastName: 'Мельник',
      phone: '+380671234567',
      avatarUrl: 'https://media.example/a.jpg',
      rating: 4.5,
      ratingCount: 3,
    );

    test(
      'carries the picked photo + rating while the identity is unchanged',
      () {
        final guest = walkInGuestFrom(
          firstName: 'Оксана',
          lastName: 'Мельник',
          phone: '+380671234567',
          picked: picked,
        );
        expect(guest.avatarUrl, 'https://media.example/a.jpg');
        expect(guest.rating, 4.5);
        expect(guest.ratingCount, 3);
      },
    );

    test('drops them once a field was edited', () {
      for (final (String f, String l, String p) in <(String, String, String)>[
        ('Олена', 'Мельник', '+380671234567'),
        ('Оксана', 'Коваль', '+380671234567'),
        ('Оксана', 'Мельник', '+380671234568'),
      ]) {
        final guest = walkInGuestFrom(
          firstName: f,
          lastName: l,
          phone: p,
          picked: picked,
        );
        expect(guest.avatarUrl, isNull);
        expect(guest.rating, isNull);
        expect(guest.ratingCount, 0);
        expect((guest.name, guest.surname, guest.phone), (f, l, p));
      }
    });

    test('a hand-typed guest (no pick) has no photo or rating', () {
      final guest = walkInGuestFrom(
        firstName: 'Оксана',
        lastName: 'Мельник',
        phone: '+380671234567',
      );
      expect(guest.avatarUrl, isNull);
      expect(guest.rating, isNull);
    });
  });
}
