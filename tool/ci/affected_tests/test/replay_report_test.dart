import 'dart:io';

import 'package:affected_tests/affected_tests.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// 398 R2 — the replay table carries the FULL reason per commit, so the D8
/// re-evaluation replay can be read without `--verbose` grepping.
int cells(String row) => row.split(RegExp(r'(?<!\\)\|')).length - 2;

String rowFor(Selection s, {int total = 10}) => replayRow(
  commit: '0123456789abcdef',
  files: 1,
  s: s,
  totalUnit: total,
  rules: rules,
  subject: 'subject',
);

void main() {
  test('header has a "full reason" column and rows match its width', () {
    final header = replayHeader.split('\n').first;
    expect(header, contains('| full reason |'));
    final fx = FixtureRepo({'scripts/x.sh': 'echo\n'});
    addTearDown(fx.dispose);
    final row = rowFor(fx.run('M\tscripts/x.sh\n'));
    expect(cells(row), cells(header));
  });

  test('scripts-only commit -> full_glob scripts/**', () {
    final fx = FixtureRepo({'scripts/x.sh': 'echo\n'});
    addTearDown(fx.dispose);
    final s = fx.run('M\tscripts/x.sh\n');
    expect(s.mode, Mode.full);
    expect(fullReason(s, rules), 'full_glob scripts/**');
    expect(rowFor(s), contains('| FULL | 0 | 0 | 0 | full_glob scripts/** |'));
  });

  test('several FULL globs are listed once each, in order', () {
    final fx = FixtureRepo({});
    addTearDown(fx.dispose);
    final s = fx.run(
      'M\tscripts/a.sh\nM\tscripts/b.sh\nM\t.github/workflows/pr-validate.yml\n',
    );
    expect(fullReason(s, rules), 'full_glob scripts/**, .github/workflows/**');
  });

  test('full_before_none carve-out reads as full_glob', () {
    final fx = FixtureRepo({});
    addTearDown(fx.dispose);
    final s = fx.run('M\tandroid/gradle.properties\n');
    expect(fullReason(s, rules), 'full_glob android/gradle.properties');
  });

  test('above the threshold -> >60% with its share', () {
    // 4 of 5 unit tests import lib/a.dart -> 80% > 60%.
    final fx = FixtureRepo({
      'lib/a.dart': 'int a = 1;\n',
      for (var i = 0; i < 4; i++) 'test/t${i}_test.dart': pkg('a.dart'),
      'test/other_test.dart': 'void main() {}\n',
    });
    addTearDown(fx.dispose);
    final s = fx.run('M\tlib/a.dart\n');
    expect(s.mode, Mode.full);
    expect(fullReason(s, rules), '>60% (80.0%)');
    expect(rowFor(s, total: 5), contains('| >60% (80.0%) |'));
  });

  test('unknown path -> fail-safe with rule and path', () {
    final fx = FixtureRepo({});
    addTearDown(fx.dispose);
    final s = fx.run('M\tbrand_new_dir/x.txt\n');
    expect(
      fullReason(s, rules),
      'fail-safe unknown path (fail-safe) brand_new_dir/x.txt',
    );
  });

  test('selective / none rows leave the reason cell empty', () {
    final fx = FixtureRepo({
      'lib/a.dart': 'int a = 1;\n',
      'test/a_test.dart': pkg('a.dart'),
      ...filler(5),
    });
    addTearDown(fx.dispose);
    final s = fx.run('M\tlib/a.dart\n');
    expect(s.mode, Mode.selective);
    expect(fullReason(s, rules), '');
    expect(fullReason(fx.run('M\tdocs/x.md\n'), rules), '');
    expect(rowFor(s), contains('|  | subject |'));
  });

  test('a "|" in a reason or subject cannot add a column', () {
    final fx = FixtureRepo({});
    addTearDown(fx.dispose);
    final s = fx.run('M\tbrand|new/x.txt\n');
    final row = replayRow(
      commit: 'abc',
      files: 1,
      s: s,
      totalUnit: 1,
      rules: rules,
      subject: 'a | b',
    );
    expect(cells(row), cells(replayHeader.split('\n').first));
  });

  test(
    'bin/replay.dart on a real fixture commit prints the reason column',
    () {
      final dir = Directory.systemTemp.createTempSync('replay_fx_');
      addTearDown(() => dir.deleteSync(recursive: true));
      void git(List<String> a) {
        final r = Process.runSync('git', [
          '-C',
          dir.path,
          '-c',
          'user.email=t@t',
          '-c',
          'user.name=t',
          '-c',
          'commit.gpgsign=false',
          ...a,
        ]);
        expect(r.exitCode, 0, reason: '${a.join(' ')}: ${r.stderr}');
      }

      void write(String rel, String body) => (File(
        p.join(dir.path, rel),
      )..createSync(recursive: true)).writeAsStringSync(body);
      git(['init', '-q']);
      write('lib/a.dart', 'int a = 1;\n');
      write('api/lib/x.dart', '\n');
      write('api/pubspec.yaml', 'name: beautica_api\n');
      write('test/a_test.dart', pkg('a.dart'));
      write('integration_test/x_test.dart', 'void main() {}\n');
      write('scripts/x.sh', 'echo 1\n');
      git(['add', '-A']);
      git(['commit', '-q', '-m', 'base']);
      write('scripts/x.sh', 'echo 2\n');
      git(['commit', '-q', '-am', 'scripts only']);

      final r = Process.runSync(Platform.resolvedExecutable, [
        'run',
        'bin/replay.dart',
        '--repo',
        dir.path,
        '--commit',
        'HEAD',
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final out = r.stdout as String;
      expect(out, contains('| full reason |'));
      expect(out, contains('| full_glob scripts/** | scripts only |'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
