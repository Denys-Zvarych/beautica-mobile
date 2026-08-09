// Pins that `scripts/verify_guards.sh` — the local all-guards runner every
// future verification chain now leans on — cannot silently degrade into a
// false "All guards passed.".
//
// THE HOLE THIS CLOSES
// ---------------------
// `verify_guards.sh` discovers its guard set with a single glob:
// `find "$here" -maxdepth 1 -type f -name 'forbid_*.sh' | sort`. That glob is
// the runner's entire notion of "what must pass". If it silently stops
// matching everything (a `scripts/` reorg, a guard renamed off the
// `forbid_*.sh` pattern, a typo in the glob during a future edit), the
// runner does not error loudly — it reports a summary over whatever subset
// it still sees, and "Passed: N/N" reads exactly like a clean run even
// though N shrank. That is a false-PASS across the WHOLE gate suite, worse
// than not having a local runner at all, because a clean local run is
// exactly the signal a developer uses to decide a push is safe.
//
// This file pins three properties end-to-end, by actually invoking the
// script as a subprocess — see "WHY SUBPROCESS, NOT SOURCE-TEXT" below for
// why that was chosen over grepping the script's source:
//   1. `--list` enumerates EXACTLY the `scripts/forbid_*.sh` files present on
//      disk today — a guard added tomorrow is covered automatically, one
//      silently dropped (by rename or glob drift) fails this test.
//   2. A failing guard makes the runner exit non-zero, names the failing
//      guard, and — critically — does not abort early: a LATER guard in
//      sorted order still runs and is reported PASS, matching the runner's
//      own "keep going past failures" contract (see its file header).
//   3. Zero discovered guards is a hard, non-zero-exit error — never a
//      silently "successful" empty run.
//
// WHY SUBPROCESS, NOT SOURCE-TEXT
// --------------------------------
// An earlier draft of this idea considered asserting on the script's source
// (e.g. `contains('exit 1')` near the discovery-empty branch, or
// `contains('failed+=')`). That is weak: it proves the string exists
// somewhere in the file, not that the script actually behaves that way when
// run — a refactor could keep the string and break the logic (or vice
// versa), and the test would not notice either way. `--list` and the
// pass/fail contract are also both externally OBSERVABLE behaviour, not
// implementation detail, so pinning them via real invocation is not
// over-fitting to internals the way asserting on internal variable names or
// control flow would be.
//
// The failure-propagation and zero-discovery cases (2 and 3) are exercised
// against a FIXTURE copy of the runner in an isolated temp directory with
// synthetic `forbid_*.sh` siblings — never against the real `scripts/`
// directory. Running the real guards to force a failure would mean either
// sabotaging a real gate (defeats the purpose of every other meta-test in
// this directory) or asserting on a guard's CURRENT pass/fail state, which
// is orthogonal to what this file is pinning (the RUNNER's behaviour, not
// any individual guard's correctness). Case 1 (discovery) is the only one
// run against the real `scripts/` directory, because that is the one thing
// that must be verified about THIS repo's actual guard set, not a stand-in.
//
// 2026-08-03: written alongside `scripts/verify_guards.sh` itself.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final File _runnerScript = File('scripts/verify_guards.sh');
final Directory _scriptsDir = Directory('scripts');

/// Every `scripts/forbid_*.sh` basename present on disk right now, sorted —
/// independently re-derived here (not imported from anywhere) so this test
/// cannot accidentally share a bug with the runner's own `discover_guards`.
List<String> _forbidGuardsOnDisk() =>
    _scriptsDir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.startsWith('forbid_') && name.endsWith('.sh'))
        .toList()
      ..sort();

/// Parses the indented `  name.sh` lines out of `verify_guards.sh --list`'s
/// `Discovered N guard(s):` output.
List<String> _parseListOutput(String stdout) =>
    stdout
        .split('\n')
        .where((line) => line.startsWith('  ') && line.trim().endsWith('.sh'))
        .map((line) => line.trim())
        .toList()
      ..sort();

/// Builds an isolated fixture directory containing a COPY of the real
/// `verify_guards.sh` plus the given synthetic guard scripts (name -> body),
/// each written executable-content-only (the real runner invokes guards via
/// `bash "$g"`, so no execute bit is required). Returns the directory; the
/// caller is responsible for deleting it (`addTearDown`).
Directory _buildFixture(Map<String, String> guardBodies) {
  final Directory dir = Directory.systemTemp.createTempSync(
    'verify_guards_meta_test_',
  );
  File(
    '${dir.path}/verify_guards.sh',
  ).writeAsStringSync(_runnerScript.readAsStringSync());
  guardBodies.forEach((name, body) {
    File('${dir.path}/$name').writeAsStringSync(body);
  });
  return dir;
}

ProcessResult _runFixtureRunner(Directory dir, [List<String> args = const []]) {
  return Process.runSync('bash', <String>[
    '${dir.path}/verify_guards.sh',
    ...args,
  ]);
}

void main() {
  setUpAll(() {
    expect(
      _runnerScript.existsSync(),
      isTrue,
      reason: '${_runnerScript.path} not found — run from the package root.',
    );
  });

  group('scripts/verify_guards.sh discovers every scripts/forbid_*.sh', () {
    test('--list enumerates exactly the forbid_*.sh files present on disk — '
        'no glob drift, no silent under-count', () {
      final List<String> onDisk = _forbidGuardsOnDisk();
      expect(
        onDisk,
        isNotEmpty,
        reason:
            'No scripts/forbid_*.sh files found on disk. Either every '
            'drift-prevention gate was deleted (unlikely) or this test is '
            'running from the wrong working directory.',
      );

      final ProcessResult result = Process.runSync('bash', <String>[
        _runnerScript.path,
        '--list',
      ]);

      expect(
        result.exitCode,
        0,
        reason:
            '`verify_guards.sh --list` must exit 0 regardless of guard '
            'content — it only enumerates, never runs, guards. stderr: '
            '${result.stderr}',
      );

      final List<String> listed = _parseListOutput(result.stdout as String);

      expect(
        listed,
        equals(onDisk),
        reason:
            'scripts/verify_guards.sh --list reported $listed but the '
            'actual scripts/forbid_*.sh files on disk are $onDisk. If '
            'these differ, the runner\'s discovery glob has drifted from '
            'reality — exactly the false-PASS-across-the-whole-suite risk '
            'this file exists to catch: a guard missing from the LEFT '
            'side would never run locally and nothing would say so.',
      );
    });
  });

  group('scripts/verify_guards.sh fails loudly on a real guard failure '
      '(fixture-isolated, never against the real scripts/ directory)', () {
    test('a failing guard makes the runner exit non-zero, names the guard, '
        'and does NOT stop a later guard from also running and passing', () {
      final Directory fixture = _buildFixture(<String, String>{
        // Sorted AFTER forbid_bad below (discover_guards sorts by
        // filename) — proves the runner keeps going past the earlier
        // failure rather than aborting, matching its documented
        // "keep going past failures" contract.
        'forbid_ok_after.sh': '#!/usr/bin/env bash\nexit 0\n',
        'forbid_bad.sh':
            '#!/usr/bin/env bash\n'
            "echo 'contrived fixture failure'\n"
            'exit 1\n',
      });
      addTearDown(() => fixture.deleteSync(recursive: true));

      final ProcessResult result = _runFixtureRunner(fixture);
      final String stdout = result.stdout as String;

      expect(
        result.exitCode,
        isNot(0),
        reason:
            'A failing guard must make verify_guards.sh exit non-zero. '
            'Full stdout:\n$stdout',
      );
      expect(
        stdout,
        contains('FAIL: forbid_bad.sh'),
        reason: 'The failing guard must be named as FAILED. stdout:\n$stdout',
      );
      expect(
        stdout,
        contains('contrived fixture failure'),
        reason:
            'The failing guard\'s own output must be surfaced, not '
            'swallowed. stdout:\n$stdout',
      );
      expect(
        stdout,
        contains('PASS: forbid_ok_after.sh'),
        reason:
            'A guard sorted AFTER the failing one must still have run '
            'and passed — an early-abort regression would silently '
            'stop covering every guard past the first failure, the '
            'exact CI behaviour this local runner exists to improve '
            'on. stdout:\n$stdout',
      );
      expect(
        stdout,
        contains('Passed: 1/2'),
        reason:
            'Summary count must reflect exactly one pass of two. stdout:\n$stdout',
      );
      expect(
        RegExp(r'Failed:\s*\n\s*-\s*forbid_bad\.sh').hasMatch(stdout),
        isTrue,
        reason:
            'The "Failed:" summary section must list forbid_bad.sh. stdout:\n$stdout',
      );
    });

    test('exits 0 and reports "All guards passed." when every discovered '
        'guard passes', () {
      final Directory fixture = _buildFixture(<String, String>{
        'forbid_a.sh': '#!/usr/bin/env bash\nexit 0\n',
        'forbid_b.sh': '#!/usr/bin/env bash\nexit 0\n',
      });
      addTearDown(() => fixture.deleteSync(recursive: true));

      final ProcessResult result = _runFixtureRunner(fixture);
      final String stdout = result.stdout as String;

      expect(result.exitCode, 0, reason: 'stdout:\n$stdout');
      expect(stdout, contains('Passed: 2/2'));
      expect(stdout, contains('All guards passed.'));
    });
  });

  group('scripts/verify_guards.sh treats zero-discovered guards as a hard '
      'error, never a silent pass', () {
    test('no scripts/forbid_*.sh siblings present -> non-zero exit, no '
        '"Passed: 0/0", no "All guards passed."', () {
      // Fixture with ONLY the runner copy — no forbid_*.sh siblings.
      final Directory fixture = _buildFixture(<String, String>{});
      addTearDown(() => fixture.deleteSync(recursive: true));

      final ProcessResult result = _runFixtureRunner(fixture);
      final String stdout = result.stdout as String;
      final String stderr = result.stderr as String;

      expect(
        result.exitCode,
        isNot(0),
        reason:
            'Zero discovered guards must be a hard failure, not a '
            'vacuous success. stdout:\n$stdout\nstderr:\n$stderr',
      );
      expect(
        stderr,
        contains('No scripts/forbid_*.sh guards discovered'),
        reason: 'stderr:\n$stderr',
      );
      expect(
        stdout,
        isNot(contains('Passed: 0/0')),
        reason:
            'A "Passed: 0/0" summary would read as a clean, if vacuous, '
            'run — exactly the false-PASS shape this test exists to '
            'forbid. stdout:\n$stdout',
      );
      expect(
        stdout,
        isNot(contains('All guards passed.')),
        reason: 'stdout:\n$stdout',
      );
    });

    test('--list also refuses an empty guard set — exits non-zero rather '
        'than reporting "Discovered 0 guard(s):"', () {
      final Directory fixture = _buildFixture(<String, String>{});
      addTearDown(() => fixture.deleteSync(recursive: true));

      final ProcessResult result = _runFixtureRunner(fixture, <String>[
        '--list',
      ]);

      expect(
        result.exitCode,
        isNot(0),
        reason:
            'The zero-discovery guard must fire before --list gets a '
            'chance to print a (vacuously true) empty enumeration. '
            'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
    });
  });
}
