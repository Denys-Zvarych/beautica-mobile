// Phase 408 QA — ledger: every command that BUILDS or LAUNCHES the app's real
// `main()` (flutter build apk|appbundle, flutter run, patrol build|test) in
// `.github/workflows/*.yml` and `scripts/perf/*.sh` must pass `--flavor X`
// together with `--dart-define-from-file=config/env/X.json`.
//
// Why: lib/core/config/env_guard.dart kills a profile/release launch whose
// flavor and baked env disagree (or whose env is missing), so a call site that
// forgets either one only fails on a device, long after the PR is green.
//
// Deliberately OUT of scope: `flutter drive` / `flutter test integration_test`.
// Those boot AppHarness / BeauticaApp, never `main()` (grep integration_test/
// for `main.dart`: only `BeauticaApp` is imported), so the guard cannot fire and
// a rule there would cry wolf (pubspec `default-flavor: staging` keeps their
// gradle build working).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _cmd = RegExp(
  r'(?:^|[\s;&|(])(flutter\s+build\s+(?:apk|appbundle)|flutter\s+run|'
  r'patrol\s+build|patrol\s+test)(?=\s)',
);

/// Joins `\` continuations, drops comment / `name:` / `echo` lines.
List<MapEntry<int, String>> logicalLines(String text) {
  final List<MapEntry<int, String>> out = <MapEntry<int, String>>[];
  final List<String> raw = text.split('\n');
  final StringBuffer buf = StringBuffer();
  int start = 0;
  for (int i = 0; i < raw.length; i++) {
    final String l = raw[i];
    if (buf.isEmpty) start = i + 1;
    if (l.trimRight().endsWith('\\')) {
      buf.write('${l.trimRight().replaceFirst(RegExp(r'\\$'), '')} ');
      continue;
    }
    buf.write(l);
    out.add(MapEntry<int, String>(start, buf.toString()));
    buf.clear();
  }
  return out;
}

/// Returns `<line>: <reason>` for every non-conforming invocation.
List<String> violations(String text, {String file = 'f'}) {
  final List<String> v = <String>[];
  for (final MapEntry<int, String> e in logicalLines(text)) {
    final String t = e.value.trim();
    if (t.startsWith('#') ||
        t.startsWith('- name:') ||
        t.startsWith('name:') ||
        t.startsWith('echo')) {
      continue;
    }
    final RegExpMatch? m = _cmd.firstMatch(t);
    if (m == null) continue;
    final String where = '$file:${e.key} [${m.group(1)}]';
    final String? flavor = RegExp(r'--flavor[ =](\w+)').firstMatch(t)?.group(1);
    final String? defFile = RegExp(
      r'''--dart-define-from-file[ =]["']?([^\s"']+)''',
    ).firstMatch(t)?.group(1);
    if (flavor == null) {
      v.add('$where: missing --flavor');
    }
    if (defFile == null) {
      v.add('$where: missing --dart-define-from-file');
    }
    if (flavor != null && defFile != null) {
      if (defFile != 'config/env/$flavor.json') {
        v.add('$where: flavor "$flavor" paired with "$defFile"');
      }
      if (flavor != 'staging' && flavor != 'prod') {
        v.add('$where: unknown flavor "$flavor"');
      }
    }
  }
  return v;
}

List<File> _files(String dir, String ext) =>
    Directory(dir)
        .listSync()
        .whereType<File>()
        .where((File f) => f.path.endsWith(ext))
        .toList()
      ..sort((File a, File b) => a.path.compareTo(b.path));

int _count(Iterable<File> files) => files
    .expand((File f) => logicalLines(f.readAsStringSync()))
    .where((MapEntry<int, String> e) {
      final String t = e.value.trim();
      return !t.startsWith('#') &&
          !t.startsWith('- name:') &&
          !t.startsWith('name:') &&
          !t.startsWith('echo') &&
          _cmd.hasMatch(t);
    })
    .length;

void main() {
  group('scanner self-test (it can fail)', () {
    test('flags a missing flavor and a missing define file', () {
      expect(violations('flutter build apk --release'), hasLength(2));
    });
    test('flags flavor/define-file mismatch', () {
      final List<String> v = violations(
        'flutter build apk --flavor prod '
        '--dart-define-from-file=config/env/staging.json',
      );
      expect(v.single, contains('paired with'));
    });
    test('accepts a conforming line, incl. continuation + patrol + quotes', () {
      expect(
        violations(
          'flutter build appbundle --flavor prod \\\n'
          '  --dart-define-from-file=config/env/prod.json\n'
          'patrol test --target x --flavor staging '
          '--dart-define-from-file="config/env/staging.json" --verbose',
        ),
        isEmpty,
      );
    });
    test('ignores comments, step names and echo text', () {
      expect(
        violations(
          '# flutter run --profile\n'
          '- name: Forbid slashes in patrol test names\n'
          'echo "flutter build apk failed"',
        ),
        isEmpty,
      );
    });
    test('reports the 1-based line of the offender', () {
      expect(
        violations('ok\nflutter run --profile\n').first,
        startsWith('f:2'),
      );
    });
  });

  group('CI workflows', () {
    final List<File> wf = _files('.github/workflows', '.yml');

    test('scanner finds the build/patrol invocations (not vacuous)', () {
      final String all = wf.map((File f) => f.readAsStringSync()).join('\n');
      expect(_count(wf), greaterThanOrEqualTo(5));
      expect(all, contains('flutter build apk'));
      expect(all, contains('patrol build'));
      expect(all, contains('patrol test'));
    });

    for (final File f in wf) {
      test('${f.uri.pathSegments.last}: flavor + matching define file', () {
        expect(violations(f.readAsStringSync(), file: f.path), isEmpty);
      });
    }
  });

  group('scripts/perf', () {
    final List<File> sh = _files('scripts/perf', '.sh');

    test('scanner finds the build/run invocations (not vacuous)', () {
      expect(_count(sh), greaterThanOrEqualTo(3));
    });

    for (final File f in sh) {
      final String name = f.uri.pathSegments.last;
      test('$name: flavor + matching define file', () {
        expect(violations(f.readAsStringSync(), file: f.path), isEmpty);
      });
    }
  });
}
