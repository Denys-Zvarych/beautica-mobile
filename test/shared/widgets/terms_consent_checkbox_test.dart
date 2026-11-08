// Phase 443 — TermsConsentCheckbox: toggle, link tap does not toggle,
// >= 48 dp target, semantics.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/terms_consent_checkbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _MockUrlLauncher extends Mock
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {}

/// Stateful host so the widget behaves as it does on a real screen.
class _Host extends StatefulWidget {
  const _Host({required this.changes, this.enabled = true});

  final List<bool> changes;
  final bool enabled;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool _value = false;

  @override
  Widget build(BuildContext context) => TermsConsentCheckbox(
    idPrefix: 'tc',
    value: _value,
    enabled: widget.enabled,
    onChanged: (bool v) {
      widget.changes.add(v);
      setState(() => _value = v);
    },
  );
}

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('uk'),
  home: Scaffold(
    body: Center(child: SizedBox(width: 360, child: child)),
  ),
);

const ValueKey<String> _box = ValueKey<String>('tc_terms_checkbox');
const ValueKey<String> _row = ValueKey<String>('tc_terms_row');
const ValueKey<String> _line = ValueKey<String>('tc_terms_line');

/// A fresh growable sink — a const list would throw on `add`.
List<bool> _sink() => <bool>[];

bool? _value(WidgetTester tester) =>
    tester.widget<Checkbox>(find.byKey(_box)).value;

void main() {
  final AppLocalizations l10n = lookupAppLocalizations(const Locale('uk'));

  late _MockUrlLauncher launcher;
  late UrlLauncherPlatform originalPlatform;

  setUpAll(() => registerFallbackValue(const LaunchOptions()));

  setUp(() {
    originalPlatform = UrlLauncherPlatform.instance;
    launcher = _MockUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
    when(() => launcher.launchUrl(any(), any())).thenAnswer((_) async => true);
  });

  tearDown(() => UrlLauncherPlatform.instance = originalPlatform);

  testWidgets('renders the acceptance statement with both link labels', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Host(changes: _sink())));

    final RichText rich = tester.widget<RichText>(
      find.descendant(of: find.byKey(_line), matching: find.byType(RichText)),
    );
    expect(
      rich.text.toPlainText(),
      '${l10n.registerTermsPrefix} ${l10n.registerTermsTerms}'
      '${l10n.registerTermsConjunction}${l10n.registerTermsPrivacy}',
    );
    expect(_value(tester), isFalse);
  });

  testWidgets('tapping the box toggles on, then off', (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(_app(_Host(changes: changes)));

    await tester.tap(find.byKey(_box));
    await tester.pump();
    expect(_value(tester), isTrue);

    await tester.tap(find.byKey(_box));
    await tester.pump();
    expect(_value(tester), isFalse);
    expect(changes, <bool>[true, false]);
  });

  testWidgets('tapping the plain label text (not a link) toggles the box', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(_app(_Host(changes: changes)));

    await tester.tapOnText(
      find.textRange.ofSubstring(
        l10n.registerTermsPrefix,
        descendentOf: find.byKey(_line),
      ),
    );
    await tester.pump();

    expect(changes, <bool>[true]);
    expect(_value(tester), isTrue);
  });

  for (final (String name, String Function() label, String url)
      in <(String, String Function(), String)>[
        ('terms', () => l10n.registerTermsTerms, 'https://beautica.app/terms'),
        (
          'privacy',
          () => l10n.registerTermsPrivacy,
          'https://beautica.app/privacy',
        ),
      ]) {
    testWidgets('$name link opens $url externally and does NOT toggle', (
      tester,
    ) async {
      final changes = <bool>[];
      await tester.pumpWidget(_app(_Host(changes: changes)));

      await tester.tapOnText(
        find.textRange.ofSubstring(label(), descendentOf: find.byKey(_line)),
      );
      await tester.pumpAndSettle();

      final List<dynamic> captured = verify(
        () => launcher.launchUrl(captureAny(), captureAny()),
      ).captured;
      expect(captured, hasLength(2), reason: 'exactly one launch');
      expect(captured[0], url);
      expect(
        (captured[1] as LaunchOptions).mode,
        PreferredLaunchMode.externalApplication,
      );
      expect(changes, isEmpty, reason: 'a link tap must not toggle the box');
      expect(_value(tester), isFalse);
    });
  }

  testWidgets('the row and the box are at least 48 dp tall', (tester) async {
    await tester.pumpWidget(_app(_Host(changes: _sink())));

    expect(tester.getSize(find.byKey(_row)).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(find.byKey(_box)).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(find.byKey(_box)).width, greaterThanOrEqualTo(48));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });

  testWidgets('semantics: labelled checkbox exposes checked state', (
    tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(_Host(changes: _sink())));

    expect(
      tester.getSemantics(find.byKey(_box)),
      matchesSemantics(
        label: l10n.termsConsentCheckboxLabel,
        hasCheckedState: true,
        isChecked: false,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );

    await tester.tap(find.byKey(_box));
    await tester.pump();
    expect(
      tester.getSemantics(find.byKey(_box)),
      matchesSemantics(
        label: l10n.termsConsentCheckboxLabel,
        hasCheckedState: true,
        isChecked: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('enabled: false blocks toggling via box and row', (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(_app(_Host(changes: changes, enabled: false)));

    await tester.tap(find.byKey(_box), warnIfMissed: false);
    await tester.tap(find.byKey(_row), warnIfMissed: false);
    await tester.pump();

    expect(changes, isEmpty);
    expect(_value(tester), isFalse);
  });
}
