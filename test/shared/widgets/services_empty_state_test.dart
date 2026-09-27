// Widget tests for `ServicesEmptyState`
// (lib/shared/widgets/services_empty_state.dart).
//
// mobile-qa (2026-09-26, Phase 355 gap-closure) — this widget was PROMOTED
// (REUSE-FIRST) from the private `_EmptyState` in
// `features/services/presentation/services_list_screen.dart` so
// `SalonMasterProfileScreen`'s embedded «Послуги» tab could reuse it with a
// DIFFERENT (read-only, "ask the owner/admin") body. Both call sites are
// covered end to end through their own screens
// (`services_list_screen_test.dart`, `salon_master_profile_screen_test.dart`,
// plus the E2E flows), but neither proves the widget's OWN contract in
// isolation — that title/body always render verbatim, and that the CTA is
// present-or-absent strictly per `onCreate`, never merely per `createLabel`.
// A regression here (e.g. the CTA rendering whenever `createLabel` is
// non-null, ignoring `onCreate`) would still pass both screen-level test
// files, because both of THEIR call sites happen to pass `onCreate` and
// `createLabel` together or neither at all.
//
// Isolation: no Riverpod providers, no MaterialApp l10n — the widget takes
// plain constructor strings, matching how every call site passes
// already-resolved l10n copy down.

import 'package:beautica_mobile/shared/widgets/services_empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('ServicesEmptyState — title/body always render', () {
    testWidgets('renders the supplied title and body verbatim', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ServicesEmptyState(
            title: 'Послуг ще немає',
            body:
                'Попросіть власника або адміністратора салону додати вам '
                'послуги.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // i18n-finder-ok: this widget takes plain caller-supplied strings, not
      // an AppLocalizations lookup — the literal here is the TEST'S OWN
      // fixture data, not app UI copy sourced from l10n, so it cannot break
      // when a locale ships.
      expect(find.text('Послуг ще немає'), findsOneWidget);
      // i18n-finder-ok: see above.
      expect(
        find.text(
          'Попросіть власника або адміністратора салону додати вам послуги.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'a DIFFERENT body string (the writable "add your first service" '
      'copy) renders in place of the read-only hint — the widget never '
      'hardcodes either audience\'s wording',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const ServicesEmptyState(
              title: 'Послуг ще немає',
              body:
                  'Додайте свою першу послугу, щоб клієнти могли її '
                  'забронювати.',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // i18n-finder-ok: caller-supplied fixture string, not app l10n copy
        // — see the header comment on this file's first `expect(find.text`.
        expect(
          find.text(
            'Додайте свою першу послугу, щоб клієнти могли її забронювати.',
          ),
          findsOneWidget,
        );
        // i18n-finder-ok: see above.
        expect(
          find.text(
            'Попросіть власника або адміністратора салону додати вам '
            'послуги.',
          ),
          findsNothing,
        );
      },
    );
  });

  group('ServicesEmptyState — CTA present-or-absent strictly per onCreate', () {
    testWidgets(
      'onCreate omitted (null, the read-only viewer) — NO CTA button, '
      'regardless of createLabel',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const ServicesEmptyState(
              title: 'Послуг ще немає',
              body: 'Ask the owner/admin.',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('btn-create-service-empty')), findsNothing);
      },
    );

    testWidgets(
      'onCreate supplied — the CTA renders with createLabel and fires '
      'onCreate exactly once when tapped',
      (tester) async {
        int taps = 0;
        await tester.pumpWidget(
          _wrap(
            ServicesEmptyState(
              title: 'Послуг ще немає',
              body: 'Додайте свою першу послугу.',
              onCreate: () => taps++,
              createLabel: 'Додати послугу',
            ),
          ),
        );
        await tester.pumpAndSettle();

        final Finder cta = find.byKey(const Key('btn-create-service-empty'));
        expect(cta, findsOneWidget);
        // i18n-finder-ok: caller-supplied fixture string, not app l10n copy
        // — see the header comment on this file's first `expect(find.text`.
        expect(find.text('Додати послугу'), findsOneWidget);

        await tester.tap(cta);
        await tester.pumpAndSettle();
        expect(taps, 1);
      },
    );

    test('onCreate supplied with createLabel omitted asserts — the '
        'constructor contract, not a silently blank button', () {
      expect(
        () => ServicesEmptyState(
          title: 'Послуг ще немає',
          body: 'Додайте свою першу послугу.',
          onCreate: () {},
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
