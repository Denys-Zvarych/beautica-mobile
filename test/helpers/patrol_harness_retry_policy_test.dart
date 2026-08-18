// STRUCTURAL GUARD — pins `PatrolHarness.boot` to the PRODUCTION retry
// predicate.
//
// THE RATCHET FAMILY
// ------------------
// Three harnesses build a `ProviderScope` on behalf of tests, and all three
// must install `beauticaProviderRetry` — the predicate `main.dart` installs on
// the production root scope. Reverting any of them to `null` falls through to
// `ProviderContainer.defaultRetry`, Riverpod's blanket 10-attempt / ~38 s
// backoff that retries EVERY `Failure`, and the whole tier below it silently
// starts validating a policy production removed. Nothing goes red; that is the
// danger.
//
//   * `test/helpers/pump_app.dart`                     → pinned BEHAVIOURALLY
//     by `pump_app_retry_policy_test.dart`.
//   * `integration_test/support/app_harness.dart`      → pinned BEHAVIOURALLY
//     by `integration_test/harness_retry_policy_flow_test.dart`.
//   * `integration_test/patrol/support/patrol_harness.dart` → this file.
//
// WHY THIS ONE IS STRUCTURAL AND NOT BEHAVIOURAL
// ----------------------------------------------
// `PatrolHarness.boot` takes a `PatrolIntegrationTester`. That type is only
// constructed by patrol's own `patrolTest(...)` runner, which requires
// `patrol_cli` driving a real Android device or emulator — the Windows-host
// emulator in this project's setup. `flutter test` (and `-d flutter-tester`)
// enumerate no `patrolTest` bodies at all, so there is no seam through which a
// plain test can boot this harness and observe the resulting container's retry
// policy.
//
// The honest options were: (a) leave the patrol tier unratcheted, (b) add a
// production seam that exists only so a non-patrol test can call the patrol
// boot path, or (c) assert the source shape. (a) is the gap this task exists to
// close; (b) makes the harness lie about how it is used. So: (c), stated
// plainly rather than dressed up.
//
// Precedent for the technique and for saying so out loud:
// `test/core/security/screen_protection_android_exemption_test.dart` and
// `test/build_guards/add_2_calendar_version_pin_test.dart`.
//
// WHAT THIS TEST CANNOT DO
// ------------------------
// It asserts SHAPE, not behaviour. It proves the argument is written at the
// only `ProviderScope` the patrol harness builds and that it names the
// production predicate; it does not prove Riverpod honoured it at runtime on a
// device. The two behavioural files above carry that proof for their tiers, and
// the predicate itself is covered by
// `test/core/errors/failure_retry_policy_test.dart`. Treat this as a tripwire
// on a known regression, not as coverage of the patrol tier.
//
// FALSIFIABILITY
// --------------
// Change `retry: beauticaProviderRetry` in `patrol_harness.dart` to
// `retry: null` (or delete the argument) and the assertions below fail.
// Verified by mutation, not by inspection.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _sourcePath =
    'integration_test/patrol/support/patrol_harness.dart';

/// The argument this guard exists to keep, verbatim.
const String _requiredArgument = 'retry: beauticaProviderRetry';

/// Strips `//` line comments and `/* … */` block comments.
///
/// MANDATORY before any structural assertion: the guarded file DOCUMENTS its
/// own boot policy in prose, and this test's own subject string could plausibly
/// appear in a comment there. Matching against raw source would let a commented
/// -out argument satisfy the guard.
String _stripComments(String source) {
  final StringBuffer out = StringBuffer();
  bool inLine = false;
  bool inBlock = false;
  for (int i = 0; i < source.length; i++) {
    final String c = source[i];
    final String next = i + 1 < source.length ? source[i + 1] : '';
    if (inLine) {
      if (c == '\n') {
        inLine = false;
        out.write(c);
      }
      continue;
    }
    if (inBlock) {
      if (c == '*' && next == '/') {
        inBlock = false;
        i++;
      }
      continue;
    }
    if (c == '/' && next == '/') {
      inLine = true;
      i++;
      continue;
    }
    if (c == '/' && next == '*') {
      inBlock = true;
      i++;
      continue;
    }
    out.write(c);
  }
  return out.toString();
}

/// Returns the parenthesised argument list that starts at the first `(` at or
/// after [from], matched by paren counting.
String _argumentListAt(String source, int from) {
  final int open = source.indexOf('(', from);
  expect(
    open,
    isNot(-1),
    reason: 'expected an opening paren after index $from',
  );
  int depth = 0;
  for (int i = open; i < source.length; i++) {
    final String c = source[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return source.substring(open + 1, i);
    }
  }
  fail('unbalanced parens starting at index $open in $_sourcePath');
}

void main() {
  late String rawSource;
  late String source;

  setUpAll(() {
    final File file = File(_sourcePath);
    // `flutter test` runs with the package directory as CWD, so this relative
    // path is stable locally and in CI.
    expect(
      file.existsSync(),
      isTrue,
      reason:
          '$_sourcePath must exist — if the patrol harness moved, this guard '
          'moved with it or the patrol tier lost its ratchet entirely',
    );
    rawSource = file.readAsStringSync();
    source = _stripComments(rawSource);
  });

  test('PatrolHarness.boot builds exactly ONE ProviderScope — the assumption '
      'every assertion below rests on', () {
    // A second scope would mean this guard checks one of them and says
    // nothing about the other, so the guard degrades silently. Fail loudly
    // instead and force whoever added it to extend the assertions.
    final int scopes = 'ProviderScope('.allMatches(source).length;
    expect(
      scopes,
      1,
      reason:
          'expected a single ProviderScope in $_sourcePath; found $scopes. '
          'Extend this guard to cover each one before adding another.',
    );
  });

  test('the ProviderScope installs the production retry predicate', () {
    final int scopeAt = source.indexOf('ProviderScope(');
    expect(scopeAt, isNot(-1));

    final String args = _argumentListAt(source, scopeAt);

    // Negative control: if the extraction ever returns something degenerate,
    // a `contains` assertion below could pass or fail for the wrong reason.
    expect(
      args,
      contains('child:'),
      reason:
          'the extracted ProviderScope argument list looks wrong — the guard '
          'would then be asserting on the wrong span of source',
    );

    expect(
      args,
      contains(_requiredArgument),
      reason:
          'PatrolHarness.boot must pass `$_requiredArgument` to its '
          'ProviderScope. Without it the scope inherits '
          'ProviderContainer.defaultRetry — Riverpod\'s blanket 10-attempt / '
          '~38 s backoff — and every patrol flow starts exercising a retry '
          'policy production removed, while staying green.',
    );
  });

  test('no ProviderScope in the patrol harness disables retry outright', () {
    expect(
      source,
      isNot(contains('retry: null')),
      reason:
          '`retry: null` is NOT "no retry" — it falls through to '
          'ProviderContainer.defaultRetry, which is the blanket-backoff '
          'behaviour this ratchet exists to keep out. A test that genuinely '
          'needs retry disabled passes `(_, _) => null`.',
    );
  });

  test('the harness still imports the predicate it is asserted to use', () {
    expect(
      source,
      contains('core/errors/failure_retry_policy.dart'),
      reason:
          'a `retry: beauticaProviderRetry` that resolves to some other '
          'local symbol would satisfy the string match above; requiring the '
          'import pins it to the production predicate',
    );
  });

  test('the rationale comment survives in the guarded file', () {
    // The structural assertions say WHAT; this keeps the WHY next to the code,
    // so the next reader does not "simplify" the argument away.
    expect(
      rawSource,
      contains('SHARED BOOT POLICY'),
      reason:
          'the boot-policy rationale header must stay in $_sourcePath — it is '
          'the only thing that explains why the retry argument is not optional',
    );
  });
}
