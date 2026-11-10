// Audit MEDIUM (feat/duplicate-services) — `_PricingInputFieldState`
// `didUpdateWidget` / `dispose` focus-node ownership, reached through
// [PricingField.durationFocusNode].
//
// Pins, across rebuilds that swap external <-> owned nodes:
//   * no listener leak — every listener attached to an external node is
//     removed once the field stops using it (net listener count back to 0);
//   * no double dispose — the field-owned node is disposed exactly once
//     (a second `ChangeNotifier.dispose` asserts, surfacing as an exception);
//   * an external node is NEVER disposed by the field.

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/pricing_field.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts net listeners and dispose calls on a caller-owned node.
class _SpyFocusNode extends FocusNode {
  _SpyFocusNode(String label) : super(debugLabel: label);

  int listeners = 0;
  int disposeCalls = 0;

  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    super.removeListener(listener);
  }

  @override
  void dispose() {
    disposeCalls++;
    super.dispose();
  }
}

const Key _durationWell = Key('field-service-duration');

bool _isDisposed(FocusNode node) {
  try {
    ChangeNotifier.debugAssertNotDisposed(node);
    return false;
  } on FlutterError {
    return true;
  }
}

class _Harness {
  _Harness(this.tester) {
    for (final TextEditingController c in <TextEditingController>[
      fixed,
      min,
      max,
      duration,
    ]) {
      addTearDown(c.dispose);
    }
  }

  final WidgetTester tester;
  final TextEditingController fixed = TextEditingController();
  final TextEditingController min = TextEditingController();
  final TextEditingController max = TextEditingController();
  final TextEditingController duration = TextEditingController();

  /// Same tree shape every call, so the `_PricingInputField` element (and its
  /// State) is reused and only `didUpdateWidget` sees the new node.
  Future<void> pump(FocusNode? node) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: Scaffold(
          body: PricingField(
            mode: ServicePriceType.fixed,
            onModeChanged: (_) {},
            fixedController: fixed,
            minController: min,
            maxController: max,
            durationController: duration,
            durationFocusNode: node,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  }

  Future<void> unmount() async {
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  }

  /// The node the duration well's TextField is actually bound to.
  FocusNode boundNode() => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(_durationWell),
          matching: find.byType(EditableText),
        ),
      )
      .focusNode;
}

void main() {
  testWidgets(
    'external -> owned -> external: old external loses every listener, '
    'owned node is disposed once, externals are never disposed',
    (WidgetTester tester) async {
      final _SpyFocusNode a = _SpyFocusNode('A');
      final _SpyFocusNode b = _SpyFocusNode('B');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final _Harness h = _Harness(tester);

      await h.pump(a);
      expect(h.boundNode(), same(a));
      final int attached = a.listeners;
      expect(attached, greaterThan(0));

      await h.pump(null);
      final FocusNode owned = h.boundNode();
      expect(owned, isNot(same(a)));
      expect(a.listeners, 0, reason: 'listener leaked on the old external');
      expect(a.disposeCalls, 0);
      expect(_isDisposed(owned), isFalse);

      await h.pump(b);
      expect(h.boundNode(), same(b));
      expect(_isDisposed(owned), isTrue, reason: 'owned node not disposed');
      expect(b.listeners, attached);

      await h.unmount();
      expect(b.listeners, 0);
      expect(a.disposeCalls, 0);
      expect(b.disposeCalls, 0);
    },
  );

  testWidgets('owned -> external -> owned -> unmount: no double dispose', (
    WidgetTester tester,
  ) async {
    final _SpyFocusNode a = _SpyFocusNode('A');
    addTearDown(a.dispose);
    final _Harness h = _Harness(tester);

    await h.pump(null);
    final FocusNode first = h.boundNode();

    await h.pump(a);
    expect(_isDisposed(first), isTrue);

    // A stale `_ownFocus` here would dispose `first` a second time and the
    // ChangeNotifier assert would surface through takeException in pump().
    await h.pump(null);
    final FocusNode second = h.boundNode();
    expect(second, isNot(same(first)));
    expect(a.listeners, 0);

    await h.unmount();
    expect(_isDisposed(second), isTrue);
    expect(a.disposeCalls, 0);
  });

  testWidgets('external -> external swap moves the focus listener', (
    WidgetTester tester,
  ) async {
    final _SpyFocusNode a = _SpyFocusNode('A');
    final _SpyFocusNode b = _SpyFocusNode('B');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final _Harness h = _Harness(tester);

    await h.pump(a);
    final int attached = a.listeners;
    await h.pump(b);

    expect(a.listeners, 0);
    expect(b.listeners, attached);

    // The swapped-in node drives the well's focused state.
    b.requestFocus();
    await tester.pump(); // focus change applied, listener fires setState
    await tester.pump(); // the setState frame
    expect(b.hasFocus, isTrue);
    expect(
      tester.widget<NeumorphicInset>(find.byKey(_durationWell)).focused,
      isTrue,
    );
    expect(a.disposeCalls + b.disposeCalls, 0);
  });
}
