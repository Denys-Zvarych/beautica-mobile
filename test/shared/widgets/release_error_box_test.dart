// ReleaseErrorBox + installReleaseErrorWidget (REL-18, Bug 1 mitigation) —
// the release-only replacement for Flutter's fill-the-parent grey
// ErrorWidget: compact, bounded under unbounded constraints, never paints
// the exception or stack text, icon-only above MaterialApp, and the
// installer leaves ErrorWidget.builder alone outside release.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/release_error_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

const String _secret = 'SECRET_TOKEN_/home/dev/beautica/lib/x.dart';

class _Throws extends StatelessWidget {
  const _Throws();

  @override
  Widget build(BuildContext context) => throw StateError(_secret);
}

Future<void> _pumpThrowingColumn(WidgetTester tester) => tester.pumpApp(
  const Scaffold(
    body: Column(
      children: <Widget>[
        _Throws(),
        Text('below', key: Key('below')),
      ],
    ),
  ),
);

void main() {
  late ErrorWidgetBuilder original;

  setUp(() => original = ErrorWidget.builder);
  tearDown(() => ErrorWidget.builder = original);

  final String errUnknown = lookupAppLocalizations(
    const Locale('uk'),
  ).errUnknown;

  testWidgets('a build throw inside an unbounded Column paints a compact box '
      'with errUnknown and none of the exception text', (tester) async {
    installReleaseErrorWidget(releaseMode: true);
    // Restored in-body: the binding verifies ErrorWidget.builder before
    // tearDown runs.
    try {
      await _pumpThrowingColumn(tester);
    } finally {
      ErrorWidget.builder = original;
    }
    expect(tester.takeException(), isA<StateError>());

    final Finder box = find.byKey(ReleaseErrorBox.boxKey);
    expect(box, findsOneWidget);
    expect(find.text(errUnknown), findsOneWidget);
    expect(tester.getSize(box).height, lessThan(80));
    expect(
      tester.getTopLeft(find.byKey(const Key('below'))).dy,
      lessThan(120),
      reason: 'the sibling below is not pushed off-screen',
    );
    expect(find.textContaining('SECRET'), findsNothing);
    expect(find.textContaining('StateError'), findsNothing);
    expect(find.textContaining('/home/'), findsNothing);
  });

  testWidgets('above MaterialApp (no Localizations / Directionality) it '
      'falls back to the icon alone', (tester) async {
    await tester.pumpWidget(const Center(child: ReleaseErrorBox()));

    expect(tester.takeException(), isNull);
    expect(find.byKey(ReleaseErrorBox.boxKey), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('under tight constraints the painted box stays compact (the '
      'rest of the slot is not filled)', (tester) async {
    await tester.pumpApp(
      const Center(
        child: SizedBox(width: 300, height: 400, child: ReleaseErrorBox()),
      ),
    );

    final Size painted = tester.getSize(find.byKey(ReleaseErrorBox.boxKey));
    expect(painted.height, lessThan(80));
    expect(painted.width, lessThanOrEqualTo(300));
  });

  test('installReleaseErrorWidget is a no-op when not release', () {
    installReleaseErrorWidget(releaseMode: false);
    expect(identical(ErrorWidget.builder, original), isTrue);
  });

  test('installReleaseErrorWidget(release) builds a ReleaseErrorBox for any '
      'details', () {
    installReleaseErrorWidget(releaseMode: true);
    expect(identical(ErrorWidget.builder, original), isFalse);
    final Widget w = ErrorWidget.builder(
      FlutterErrorDetails(exception: StateError(_secret)),
    );
    expect(w, isA<ReleaseErrorBox>());
  });
}
