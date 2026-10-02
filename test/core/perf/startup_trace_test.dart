import 'package:beautica_mobile/core/perf/startup_trace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final List<String> events = <String>[];
  setUp(() {
    events.clear();
    StartupTrace.debugRecorder = (String name, bool started) =>
        events.add('${started ? '+' : '-'}$name');
  });
  tearDown(() => StartupTrace.debugRecorder = null);

  group('boot:<name> events', () {
    test('sync emits boot:<name> start, body, finish in order', () {
      StartupTrace.sync<void>(StartupSlice.timezones, () {
        events.add('body');
      });
      expect(events, <String>['+boot:timezones', 'body', '-boot:timezones']);
    });

    test('sync finishes the slice when the body throws', () {
      expect(
        () => StartupTrace.sync<void>(
          StartupSlice.container,
          () => throw StateError('boom'),
        ),
        throwsStateError,
      );
      expect(events, <String>['+boot:container', '-boot:container']);
    });

    test('async emits boot:<name> around the awaited body', () async {
      await StartupTrace.async<void>(StartupSlice.fonts, () async {
        await Future<void>.delayed(Duration.zero);
        events.add('body');
      });
      expect(events, <String>['+boot:fonts', 'body', '-boot:fonts']);
    });

    test('async finishes the slice when the body throws', () async {
      await StartupTrace.async<void>(
        StartupSlice.certPinning,
        () async => throw StateError('boom'),
      ).then((_) {}, onError: (_) {});
      expect(events, <String>['+boot:certPinning', '-boot:certPinning']);
    });
  });

  group('StartupTrace.sync', () {
    test('returns the body value', () {
      expect(StartupTrace.sync<int>(StartupSlice.timezones, () => 42), 42);
    });

    test('rethrows the body exception', () {
      expect(
        () => StartupTrace.sync<void>(
          StartupSlice.container,
          () => throw StateError('boom'),
        ),
        throwsStateError,
      );
    });
  });

  group('StartupTrace.async', () {
    test('returns the body value', () async {
      final int v = await StartupTrace.async<int>(
        StartupSlice.fonts,
        () async => 7,
      );
      expect(v, 7);
    });

    test('rethrows the body exception and still completes', () async {
      await expectLater(
        StartupTrace.async<void>(
          StartupSlice.certPinning,
          () async => throw StateError('boom'),
        ).timeout(const Duration(seconds: 5)),
        throwsStateError,
      );
    });

    test('a later call still works after a throwing body', () async {
      await StartupTrace.async<void>(
        StartupSlice.fonts,
        () async => throw StateError('x'),
      ).then((_) {}, onError: (_) {});
      expect(
        await StartupTrace.async<String>(StartupSlice.fonts, () async => 'ok'),
        'ok',
      );
    });
  });

  test('slice names are the four boot steps', () {
    expect(
      <String>[
        StartupSlice.timezones,
        StartupSlice.fonts,
        StartupSlice.certPinning,
        StartupSlice.container,
      ],
      <String>['timezones', 'fonts', 'certPinning', 'container'],
    );
  });
}
