// Guards the `_VelvetSnackOverlay` single-slot invariant against the
// same-tick pre-emption race (mobile-perf HIGH finding on the VelvetSnack
// migration): two `showVelvetSnack` calls issued back-to-back inside one
// synchronous handler must never both mount — the second must pre-empt the
// first, per `velvet_snack_host.dart`'s own "no queue, ever... the two never
// overlap" guarantee.
//
// Before the fix, `_current` was only assigned inside
// `_VelvetSnackScopeState.initState`, which doesn't run until the `Overlay`'s
// deferred rebuild — a frame after `show()` returns. Two synchronous `show()`
// calls therefore both read `_current == null`, both skipped the pre-empt
// path, and both called `overlay.insert(entry)`, mounting two overlapping
// `VelvetSnack`s. This test fires exactly that pattern and asserts exactly
// one `VelvetSnack` is mounted afterwards.

import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/velvet_snack_matchers.dart';

/// Fires two `showVelvetSnack` calls from a single synchronous `onPressed`
/// handler — the same shape as two `ref.listen` callbacks reacting to one
/// state change, or a handler that shows a "saving…" info snack immediately
/// followed by a success snack once a synchronous precondition already holds.
class _FireTwoSnacksButton extends StatelessWidget {
  const _FireTwoSnacksButton();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const Key('fire-two-snacks-button'),
          onPressed: () {
            showVelvetSnack(
              context,
              message: 'First snack',
              variant: VelvetSnackVariant.info,
            );
            showVelvetSnack(
              context,
              message: 'Second snack',
              variant: VelvetSnackVariant.success,
            );
          },
          child: const Text('fire'),
        ),
      ),
    );
  }
}

void main() {
  testWidgets(
    'two showVelvetSnack calls in the same synchronous tick mount exactly '
    'one VelvetSnack — the second pre-empts the first',
    (WidgetTester tester) async {
      await tester.pumpApp(const _FireTwoSnacksButton());

      await tester.tap(find.byKey(const Key('fire-two-snacks-button')));
      // Let the overlay's deferred rebuild (and any pre-empt microtask
      // chain) actually build the widget tree.
      await tester.pump();

      // The single-slot invariant: exactly one VelvetSnack is ever mounted,
      // never two overlapping ones.
      expect(find.byType(VelvetSnack), findsOneWidget);

      // It must be the LATER call that wins the slot — matching every other
      // pre-emption path in this component (a new snack always replaces
      // whatever is currently showing, never the other way round).
      expect(find.text('Second snack'), findsOneWidget);
      expect(find.text('First snack'), findsNothing);

      // Drain the winning snack's full lifecycle so no Timer/AnimationController
      // leaks past the test.
      await pumpPastVelvetSnack(tester);
    },
  );
}
