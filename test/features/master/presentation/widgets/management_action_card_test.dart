// Phase 325 QA gap-closure — behavioural coverage for [ManagementActionCard]
// itself.
//
// `salon_staff_profile_screen_test.dart`'s "renders DISABLED (never
// omitted)..." case (Phase 318, carried into 325) already taps the disabled
// services row and asserts no navigation occurred — but that screen's own
// call site ALSO neutralises `onTap` at the source
// (`onTap: !hasMasterId ? () {} : () => context.push(...)`), so tapping the
// row proves the ternary, not the card's own `AbsorbPointer` gate. Deleting
// `AbsorbPointer` from `management_action_card.dart` leaves that screen test
// green, because the callback it taps into was already a no-op regardless.
//
// This file closes that gap at the component boundary: it wires a REAL,
// observable `onTap` (a counter, never a no-op) directly to the card, so a
// removed `AbsorbPointer` — or a broken `inert` computation — is the ONLY
// thing that can make these assertions fail.
//
// MUTATION RECORD (mobile-qa, 2026-09-12 — `cp` backup, both restored
// byte-identically):
//   • `management_action_card.dart:86` `absorbing: inert` → `absorbing:
//     false` → RED on both "disabled" and "loading" cases below (counter
//     incremented when it must not have).
//   • `management_action_card.dart:80` `final bool inert = widget.loading ||
//     !widget.enabled` → `final bool inert = false` → same RED (this is the
//     same code path as above; recorded together).

import 'package:beautica_mobile/features/master/presentation/widgets/management_action_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

Widget _card({
  required VoidCallback onTap,
  bool enabled = true,
  bool loading = false,
  bool emphasis = false,
}) => Material(
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 160,
      child: ManagementActionCard(
        key: const Key('probe-card'),
        icon: Icons.design_services_rounded,
        // Locale-neutral test literals — this component takes `label`/
        // `value` as plain strings from its caller (no AppLocalizations
        // dependency of its own), so real Ukrainian copy here would just
        // trip `forbid_cyrillic_finder.sh` for no behavioural reason.
        label: 'Probe Label',
        value: 'Probe Value',
        enabled: enabled,
        loading: loading,
        emphasis: emphasis,
        onTap: onTap,
      ),
    ),
  ),
);

void main() {
  testWidgets('enabled, not loading — tap invokes onTap', (tester) async {
    int calls = 0;
    await tester.pumpApp(_card(onTap: () => calls++));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('probe-card')));
    await tester.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets('enabled: false — tap does NOT invoke onTap (AbsorbPointer gate, '
      'mutation-critical: catches a deleted AbsorbPointer that a screen-level '
      "test using a no-op onTap can't)", (tester) async {
    int calls = 0;
    await tester.pumpApp(_card(onTap: () => calls++, enabled: false));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('probe-card')));
    await tester.pumpAndSettle();

    expect(
      calls,
      0,
      reason:
          'a disabled card must absorb the tap before it ever reaches '
          'onTap — this test wires a REAL callback, so only the '
          "widget's own inert-gating (AbsorbPointer + the `inert` "
          'computation), not a caller-side no-op, can make this pass',
    );
  });

  testWidgets('loading: true — tap does NOT invoke onTap (same inert gate as '
      'enabled: false)', (tester) async {
    // `CircularProgressIndicator` is indeterminate — it animates forever,
    // so `pumpAndSettle` here would time out. A bounded `pump` is correct,
    // not a workaround (`AnimatedScale`'s own 120ms transition is well
    // within it).
    int calls = 0;
    await tester.pumpApp(_card(onTap: () => calls++, loading: true));
    // fixed-wait-ok: the indeterminate CircularProgressIndicator never
    // settles — a bounded pump past AnimatedScale's 120ms transition is the
    // correct wait, not a stand-in for pumpUntilCondition.
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const Key('probe-card')));
    // fixed-wait-ok: same indeterminate-animation reason as above.
    await tester.pump(const Duration(milliseconds: 200));

    expect(calls, 0);
  });

  testWidgets('loading: true renders the spinner, not the chevron', (
    tester,
  ) async {
    await tester.pumpApp(_card(onTap: () {}, loading: true));
    // fixed-wait-ok: the indeterminate CircularProgressIndicator never
    // settles, so pumpAndSettle would time out; a bounded pump is correct.
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(const ValueKey<String>('management_action_card_loading')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });

  testWidgets('loading: false (default) renders the chevron, not the '
      'spinner', (tester) async {
    await tester.pumpApp(_card(onTap: () {}));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('management_action_card_loading')),
      findsNothing,
    );
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
  });

  testWidgets('renders the label and value text passed in', (tester) async {
    await tester.pumpApp(_card(onTap: () {}));
    await tester.pumpAndSettle();

    expect(find.text('Probe Label'), findsOneWidget);
    expect(find.text('Probe Value'), findsOneWidget);
  });
}
