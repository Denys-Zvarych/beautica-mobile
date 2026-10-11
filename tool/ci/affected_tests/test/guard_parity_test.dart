import 'dart:io';

import 'package:affected_tests/affected_tests.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// 398 R1 — guard ⊆ rules parity.
///
/// The `plan` job's `is_forced` shell guard (`.github/workflows/pr-validate.yml`)
/// forces FULL independently of the selector. For the replay to predict what
/// CI actually does, every path the guard forces must also classify as FULL
/// in rules.yaml (and `scripts/perf/*`, which the guard exempts, must not).
/// The direction is one-way: rules.yaml may force FULL for more paths than
/// the guard (fail-safe), never fewer.

/// One `case` arm of `is_forced`: shell glob patterns -> return code.
final class GuardArm {
  GuardArm(this.patterns, this.forced);
  final List<String> patterns;
  final bool forced;
}

/// Shell `case` glob -> anchored RegExp (`*` and `?` match `/` too, as in
/// `case`; bracket expressions are not used by the guard and are rejected).
RegExp caseGlob(String pattern) {
  if (pattern.contains('[')) {
    throw FormatException('bracket glob not supported: $pattern');
  }
  final b = StringBuffer('^');
  for (final ch in pattern.split('')) {
    b.write(switch (ch) {
      '*' => '.*',
      '?' => '.',
      _ => RegExp.escape(ch),
    });
  }
  return RegExp('${b}\$');
}

/// Parses the single `is_forced() { case "$1" in … esac; return 1; }` body.
List<GuardArm> parseIsForced(String workflow) {
  final lines = workflow.split('\n');
  final starts = [
    for (var i = 0; i < lines.length; i++)
      if (RegExp(r'^\s*is_forced\(\) \{\s*$').hasMatch(lines[i])) i,
  ];
  if (starts.length != 1) {
    throw StateError(
      'expected exactly 1 is_forced() in the workflow, '
      'found ${starts.length}',
    );
  }
  final arms = <GuardArm>[];
  final arm = RegExp(r'^\s*(.+?)\)\s*return ([01])\s*;;\s*$');
  for (var i = starts.single + 1; i < lines.length; i++) {
    final l = lines[i];
    if (RegExp(r'^\s*esac\s*$').hasMatch(l)) break;
    if (RegExp(r'^\s*case "\$1" in\s*$').hasMatch(l)) continue;
    final m = arm.firstMatch(l);
    if (m == null) throw FormatException('unparsed is_forced line: "$l"');
    arms.add(
      GuardArm([for (final s in m[1]!.split('|')) s.trim()], m[2] == '0'),
    );
  }
  return arms;
}

/// The guard's verdict for [path]: first matching arm wins; no match => false.
bool guardForces(List<GuardArm> arms, String path) {
  for (final a in arms) {
    if (a.patterns.any((g) => caseGlob(g).hasMatch(path))) return a.forced;
  }
  return false;
}

/// Concrete sample paths for one guard pattern.
List<String> samples(String pattern) => pattern.contains('*')
    ? [
        pattern.replaceAll('*', 'zz_parity.txt'),
        pattern.replaceAll('*', 'zz/parity_test.dart'),
        pattern.replaceAll('*', 'zz/deep/parity.dart'),
      ]
    : [pattern];

void main() {
  final repoRoot = p.normalize(
    p.join(Directory.current.path, '..', '..', '..'),
  );
  final wfFile = File(
    p.join(repoRoot, '.github', 'workflows', 'pr-validate.yml'),
  );
  final haveRepo = wfFile.existsSync();
  final skip = haveRepo ? false : 'not inside the beautica-mobile tree';

  group('398 R1 is_forced ⊆ rules.yaml full', () {
    late final List<GuardArm> arms;
    setUpAll(() {
      if (haveRepo) arms = parseIsForced(wfFile.readAsStringSync());
    });

    test('the guard parses into arms (extraction cannot silently shrink)', () {
      // 5 forcing arms + the scripts/perf exemption today.
      expect(arms.length, greaterThanOrEqualTo(6));
      expect(arms.where((a) => !a.forced), isNotEmpty);
      expect(
        arms.expand((a) => a.patterns),
        containsAll(['scripts/perf/*', 'test/ci/*', '.github/*']),
      );
    }, skip: skip);

    test('every sample of every guard pattern classifies like the guard', () {
      final mismatches = <String>[];
      for (final a in arms) {
        for (final pat in a.patterns) {
          for (final s in samples(pat)) {
            final forced = guardForces(arms, s);
            final full = classify(s, rules).kind == PathKind.full;
            if (forced && !full) {
              mismatches.add(
                '$s: guard forces FULL, rules say '
                '${classify(s, rules).rule}',
              );
            }
            if (!forced && full && s.startsWith('scripts/perf/')) {
              mismatches.add('$s: guard exempts it, rules force FULL');
            }
          }
        }
      }
      expect(mismatches, isEmpty);
    }, skip: skip);

    test('every tracked-tree file the guard forces classifies FULL', () {
      const skipDirs = {'.git', 'build', '.dart_tool', '.gradle', 'Pods'};
      final files = <String>[];
      void walk(Directory d) {
        for (final e in d.listSync(followLinks: false)) {
          final name = p.basename(e.path);
          if (e is Directory) {
            if (!skipDirs.contains(name)) walk(e);
          } else if (e is File) {
            files.add(
              p.posix.joinAll(p.split(p.relative(e.path, from: repoRoot))),
            );
          }
        }
      }

      walk(Directory(repoRoot));
      final forced = files.where((f) => guardForces(arms, f)).toList();
      // The tree really exercises the guard (workflows, scripts, helpers…).
      expect(forced.length, greaterThan(50));
      final mismatches = [
        for (final f in forced)
          if (classify(f, rules).kind != PathKind.full)
            '$f -> ${classify(f, rules).rule}',
      ];
      expect(mismatches, isEmpty);
      final perf = files.where((f) => f.startsWith('scripts/perf/'));
      expect(perf, isNotEmpty);
      for (final f in perf) {
        expect(guardForces(arms, f), isFalse, reason: f);
        expect(classify(f, rules).kind, isNot(PathKind.full), reason: f);
      }
    }, skip: skip);
  });

  group('401 S2: trusted/ is never a PR path', () {
    late final List<GuardArm> arms;
    setUpAll(() {
      if (haveRepo) arms = parseIsForced(wfFile.readAsStringSync());
    });

    test(
      'the guard forces FULL for trusted and trusted/*, and rules agree',
      () {
        for (final path in ['trusted', 'trusted/tool/ci/x.sh', 'trusted/a/b']) {
          expect(guardForces(arms, path), isTrue, reason: path);
          expect(classify(path, rules).kind, PathKind.full, reason: path);
        }
        expect(guardForces(arms, 'lib/trusted/a.dart'), isFalse);
      },
      skip: skip,
    );

    test(
      'is_forbidden (fail-closed, red plan) lists trusted and trusted/*',
      () {
        final wf = wfFile.readAsStringSync();
        final body = RegExp(
          r'is_forbidden\(\) \{[\s\S]*?\n\s*\}\n',
        ).firstMatch(wf)!.group(0)!;
        expect(body, contains('trusted | trusted/*'));
        // Run the real function.
        for (final (path, want) in [
          ('trusted/x', 0),
          ('trusted', 0),
          ('lib/trusted/x.dart', 1),
          ('trustedx/a', 1),
        ]) {
          final r = Process.runSync('bash', [
            '-c',
            '$body\nis_forbidden "\$1"',
            'bash',
            path,
          ]);
          expect(r.exitCode, want, reason: path);
        }
      },
      skip: skip,
    );
  });

  group('parser self-checks', () {
    test('case globs: * spans "/" like shell case', () {
      expect(caseGlob('test/ci/*').hasMatch('test/ci/a/b_test.dart'), isTrue);
      expect(caseGlob('pubspec.yaml').hasMatch('pubspec.yaml'), isTrue);
      expect(caseGlob('pubspec.yaml').hasMatch('xpubspec.yaml'), isFalse);
    });

    test('first matching arm wins (scripts/perf exemption)', () {
      final arms = parseIsForced('''
          is_forced() {
            case "\$1" in
              scripts/perf/*) return 1 ;;
              .github/* | scripts/*) return 0 ;;
            esac
            return 1
          }
''');
      expect(arms, hasLength(2));
      expect(guardForces(arms, 'scripts/perf/x.sh'), isFalse);
      expect(guardForces(arms, 'scripts/x.sh'), isTrue);
      expect(guardForces(arms, 'lib/x.dart'), isFalse);
    });

    test('an unparseable arm fails loudly, never silently drops', () {
      expect(
        () => parseIsForced('''
is_forced() {
  case "\$1" in
    foo/*) forced=1 ;;
  esac
}
'''),
        throwsFormatException,
      );
    });
  });
}
