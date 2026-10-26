// Phase 409 QA — contract: `.github/workflows/release-aab.yml` (the signed Play
// upload AAB) keeps the security and release shape the phase decided, and the
// manifest / permission allow-list stay coherent with it.
//
// Why a structural test: the workflow only runs on a `mobile-v*` tag or a
// manual dispatch, so a regression (a `pull_request` trigger, an unpinned
// action, `${{ github.ref_name }}` spliced into a shell, a keystore inside an
// artifact glob, a verify step moved after the upload) would be invisible on
// every PR and first surface on the release run itself — with the upload key
// loaded. These checks run on every PR in milliseconds.
//
// `package:yaml` is only a transitive dependency here, so (like the sibling
// `test/ci/*` tests) this parses the file textually: indentation-scoped blocks,
// list items (`- `) as steps, `|` block scalars. Every detector is pure
// (`String` in, violations out) and is ALSO run against a mutated in-memory
// copy of the real file, so a broken detector cannot pass silently (M14/M16).
//
// Decisions pinned (phase-409-R.2-aab-release-pipeline.md):
//   D3  triggers = push tags mobile-v* + workflow_dispatch(dry_run=true);
//       no pull_request / pull_request_target; permissions contents: read.
//   D4  `guard` has no environment and no secrets.
//   D5  `build` needs guard + environment ci-trusted-secrets; keystore in
//       $RUNNER_TEMP, removed in an always() step; REQUIRE_RELEASE_SIGNING=1,
//       never ALLOW_DEBUG_SIGNED_RELEASE.
//   D6  one appbundle build, no --build-number/--build-name, `# 411:` hooks.
//   D7  verify_release_aab.sh runs after the build and before the AAB upload.
//   D10 AD_ID stripped; allow-list entries unique, each with a `# why`.
//   D11 no artifact path can reach the keystore.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String kWorkflow = '.github/workflows/release-aab.yml';
const String kManifest = 'android/app/src/main/AndroidManifest.xml';
const String kAllowList = 'android/release-permissions.allow';

// ---------------------------------------------------------------------------
// Minimal indentation-scoped YAML reader.
// ---------------------------------------------------------------------------

int _indent(String l) => l.length - l.trimLeft().length;

bool _isNoise(String l) => l.trim().isEmpty || l.trim().startsWith('#');

String _stripComment(String v) => v.replaceFirst(RegExp(r'\s+#.*$'), '').trim();

String _unquote(String v) => v.replaceAll(RegExp('''^['"]|['"]\$'''), '');

/// Indices of the lines nested under the key line at [idx].
List<int> _children(List<String> lines, int idx) {
  final int base = _indent(lines[idx]);
  final List<int> out = <int>[];
  for (int i = idx + 1; i < lines.length; i++) {
    if (!_isNoise(lines[i]) && _indent(lines[i]) <= base) break;
    out.add(i);
  }
  return out;
}

/// Index of `key:` at exactly [indent], searching [within] (all lines if null).
int _findKey(
  List<String> lines,
  String key,
  int indent, {
  Iterable<int>? within,
}) {
  final RegExp re = RegExp('^${RegExp.escape(key)}\\s*:(\\s|\$)');
  for (final int i
      in within ?? List<int>.generate(lines.length, (int i) => i)) {
    final String l = lines[i];
    if (!_isNoise(l) && _indent(l) == indent && re.hasMatch(l.trimLeft())) {
      return i;
    }
  }
  return -1;
}

/// Inline value of the key line at [idx] (comment stripped).
String _inline(String line) =>
    _stripComment(line.substring(line.indexOf(':') + 1));

/// Keys directly under the key line at [idx].
List<String> _childKeys(List<String> lines, int idx) {
  final List<int> kids = _children(
    lines,
    idx,
  ).where((int i) => !_isNoise(lines[i])).toList();
  if (kids.isEmpty) return <String>[];
  final int ind = _indent(lines[kids.first]);
  return kids
      .where((int i) => _indent(lines[i]) == ind)
      .map((int i) => lines[i].trimLeft().split(':').first.trim())
      .toList();
}

class WorkflowStep {
  WorkflowStep(this.start, this.lines, this.fieldIndent);

  /// 0-based line index of the `- ` line in the whole file.
  final int start;

  /// The step's lines with the leading `- ` blanked to spaces.
  final List<String> lines;
  final int fieldIndent;

  int _keyIdx(String key) => _findKey(lines, key, fieldIndent);

  bool has(String key) => _keyIdx(key) >= 0;

  /// Scalar value; a `|`/`>` block or nested mapping is joined with `\n`.
  String? field(String key) {
    final int i = _keyIdx(key);
    if (i < 0) return null;
    final String v = _inline(lines[i]);
    if (v.isEmpty || RegExp(r'^[|>][-+]?$').hasMatch(v)) {
      return _children(lines, i).map((int j) => lines[j].trim()).join('\n');
    }
    return v;
  }

  /// `key: value` pairs nested under [key] (e.g. a step's `env:`).
  Map<String, String> mapping(String key) {
    final int i = _keyIdx(key);
    final Map<String, String> out = <String, String>{};
    if (i < 0) return out;
    for (final int j in _children(lines, i)) {
      if (_isNoise(lines[j]) || !lines[j].contains(':')) continue;
      final String t = lines[j].trimLeft();
      out[t.split(':').first.trim()] = _unquote(_inline(t));
    }
    return out;
  }
}

class Workflow {
  Workflow(this.text) : lines = text.split('\n');

  final String text;
  final List<String> lines;

  int top(String key) => _findKey(lines, key, 0);

  /// Job name → index of its key line.
  Map<String, int> get jobs {
    final int j = top('jobs');
    final Map<String, int> out = <String, int>{};
    if (j < 0) return out;
    final List<int> kids = _children(lines, j);
    for (final int i in kids) {
      if (!_isNoise(lines[i]) && _indent(lines[i]) == 2) {
        out[lines[i].trim().split(':').first] = i;
      }
    }
    return out;
  }

  /// Inline value of a job-level `key:` (indent 4), or null when absent.
  String? jobField(String job, String key) {
    final int? j = jobs[job];
    if (j == null) return null;
    final int i = _findKey(lines, key, 4, within: _children(lines, j));
    return i < 0 ? null : _inline(lines[i]);
  }

  List<WorkflowStep> steps(String job) {
    final int? j = jobs[job];
    if (j == null) return <WorkflowStep>[];
    final int s = _findKey(lines, 'steps', 4, within: _children(lines, j));
    if (s < 0) return <WorkflowStep>[];
    final List<int> kids = _children(lines, s);
    final List<WorkflowStep> out = <WorkflowStep>[];
    int? cur;
    int dash = -1;
    void flush(int end) {
      final int? first = cur;
      if (first == null) return;
      final List<String> body = <String>[];
      for (int i = first; i < end; i++) {
        body.add(i == first ? lines[i].replaceFirst('- ', '  ') : lines[i]);
      }
      out.add(WorkflowStep(first, body, dash + 2));
    }

    for (final int i in kids) {
      final String l = lines[i];
      if (!_isNoise(l) && l.trimLeft().startsWith('- ')) {
        if (dash < 0) dash = _indent(l);
        if (_indent(l) == dash) {
          flush(i);
          cur = i;
        }
      }
    }
    flush(kids.isEmpty ? s + 1 : kids.last + 1);
    return out;
  }

  Iterable<WorkflowStep> get allSteps =>
      jobs.keys.expand((String job) => steps(job));
}

// ---------------------------------------------------------------------------
// Detectors. Each returns human-readable violations; empty == compliant.
// ---------------------------------------------------------------------------

List<String> triggerViolations(String text) {
  final Workflow w = Workflow(text);
  final List<String> v = <String>[];
  final int on = w.top('on');
  if (on < 0) return <String>['no top-level `on:`'];
  if (_inline(w.lines[on]).isNotEmpty) {
    v.add('`on:` has an inline value (${_inline(w.lines[on])})');
  }
  final List<String> events = _childKeys(w.lines, on);
  if (events.join(',') != 'push,workflow_dispatch') {
    v.add('events must be exactly push + workflow_dispatch, got $events');
  }
  for (int i = 0; i < w.lines.length; i++) {
    if (!_isNoise(w.lines[i]) &&
        RegExp(r'\bpull_request(_target)?\b').hasMatch(w.lines[i])) {
      v.add('line ${i + 1}: pull_request trigger (fork reachability)');
    }
  }
  final int push = _findKey(w.lines, 'push', 2, within: _children(w.lines, on));
  if (push >= 0) {
    final List<String> pk = _childKeys(w.lines, push);
    if (pk.join(',') != 'tags') v.add('push must filter only `tags`, got $pk');
    final int tags = _findKey(
      w.lines,
      'tags',
      4,
      within: _children(w.lines, push),
    );
    if (tags >= 0) {
      String t = _inline(w.lines[tags]);
      if (t.isEmpty) {
        t = _children(w.lines, tags)
            .where((int i) => !_isNoise(w.lines[i]))
            .map((int i) => w.lines[i].trim().replaceFirst('- ', ''))
            .join(',');
      }
      final String norm = t
          .replaceAll(RegExp(r'[\[\]\s]'), '')
          .split(',')
          .map(_unquote)
          .join(',');
      if (norm != 'mobile-v*') v.add('push.tags must be [mobile-v*], got $t');
    }
  }
  final int wd = _findKey(
    w.lines,
    'workflow_dispatch',
    2,
    within: _children(w.lines, on),
  );
  if (wd >= 0) {
    final int dr = _findKey(
      w.lines,
      'dry_run',
      6,
      within: _children(w.lines, wd),
    );
    final int def = dr < 0
        ? -1
        : _findKey(w.lines, 'default', 8, within: _children(w.lines, dr));
    if (def < 0 || _inline(w.lines[def]) != 'true') {
      v.add('workflow_dispatch input dry_run must default to true (D3)');
    }
  }
  return v;
}

List<String> permissionViolations(String text) {
  final Workflow w = Workflow(text);
  final List<String> v = <String>[];
  List<String> grants(int idx) => _children(w.lines, idx)
      .where((int i) => !_isNoise(w.lines[i]))
      .map((int i) => w.lines[i].trim().replaceAll(RegExp(r'\s+'), ' '))
      .toList();
  final int p = w.top('permissions');
  if (p < 0) {
    v.add('no top-level permissions');
  } else if (_inline(w.lines[p]).isNotEmpty ||
      grants(p).join('|') != 'contents: read') {
    v.add(
      'top-level permissions must be exactly `contents: read`, '
      'got ${_inline(w.lines[p])}${grants(p)}',
    );
  }
  w.jobs.forEach((String job, int j) {
    final int jp = _findKey(
      w.lines,
      'permissions',
      4,
      within: _children(w.lines, j),
    );
    if (jp >= 0 &&
        (_inline(w.lines[jp]).isNotEmpty ||
            grants(jp).join('|') != 'contents: read')) {
      v.add(
        'job $job permissions widen beyond `contents: read`: '
        '${_inline(w.lines[jp])}${grants(jp)}',
      );
    }
  });
  return v;
}

List<String> jobTopologyViolations(String text) {
  final Workflow w = Workflow(text);
  final List<String> v = <String>[];
  if (!w.jobs.containsKey('guard')) v.add('no `guard` job');
  if (!w.jobs.containsKey('build')) v.add('no `build` job');
  if (w.jobField('guard', 'environment') != null) {
    v.add('guard must have NO environment (D4: bad tag fails pre-secrets)');
  }
  final int? g = w.jobs['guard'];
  if (g != null) {
    for (final int i in _children(w.lines, g)) {
      if (!_isNoise(w.lines[i]) && w.lines[i].contains('secrets.')) {
        v.add('guard line ${i + 1} references a secret');
      }
    }
  }
  final String needs = (w.jobField('build', 'needs') ?? '').replaceAll(
    RegExp(r'[\[\]\s]'),
    '',
  );
  if (needs != 'guard') v.add('build must have `needs: guard`, got "$needs"');
  if (w.jobField('build', 'environment') != 'ci-trusted-secrets') {
    v.add(
      'build must have `environment: ci-trusted-secrets`, got '
      '"${w.jobField('build', 'environment')}"',
    );
  }
  for (final String job in w.jobs.keys) {
    if (job != 'build' && w.jobField(job, 'environment') != null) {
      v.add('job $job names an environment; only build may');
    }
  }
  return v;
}

final RegExp _pinned = RegExp(r'^[\w.-]+/[\w./-]+@[0-9a-f]{40}$');

List<String> pinViolations(String text) {
  final List<String> lines = text.split('\n');
  final List<String> v = <String>[];
  for (int i = 0; i < lines.length; i++) {
    final RegExpMatch? m = RegExp(
      r'^\s*(?:-\s+)?uses:\s*(.*)$',
    ).firstMatch(lines[i]);
    if (m == null || _isNoise(lines[i])) continue;
    final String ref = _unquote(_stripComment(m.group(1)!));
    if (ref.startsWith('./')) continue; // local composite action
    if (!_pinned.hasMatch(ref)) v.add('line ${i + 1}: `$ref` not SHA-pinned');
  }
  return v;
}

/// Strict: no `${{ … }}` at all inside a `run:` body. Expressions are
/// substituted into the script BEFORE the shell parses it, so even a comment
/// is live. Values reach shells through `env:` only.
List<String> injectionViolations(String text) {
  final List<String> v = <String>[];
  for (final WorkflowStep s in Workflow(text).allSteps) {
    final String? run = s.field('run');
    if (run == null) continue;
    for (final RegExpMatch m in RegExp(r'\$\{\{[^}]*\}\}').allMatches(run)) {
      v.add('step at line ${s.start + 1}: `${m.group(0)}` inside run:');
    }
  }
  return v;
}

bool _isAlways(String? cond) =>
    cond != null &&
    RegExp(r'^(\$\{\{\s*)?always\(\)(\s*\}\})?$').hasMatch(_unquote(cond));

List<String> keystoreViolations(String text) {
  final Workflow w = Workflow(text);
  final List<String> v = <String>[];
  final List<WorkflowStep> steps = w.steps('build');
  final List<int> cleanup = <int>[
    for (int i = 0; i < steps.length; i++)
      if (RegExp(r'\brm\b.*upload\.jks').hasMatch(steps[i].field('run') ?? ''))
        i,
  ];
  if (cleanup.length != 1) {
    v.add(
      'expected exactly one keystore cleanup step, found ${cleanup.length}',
    );
  } else {
    final WorkflowStep c = steps[cleanup.single];
    if (!_isAlways(c.field('if'))) {
      v.add('keystore cleanup must be `if: always()`, got "${c.field('if')}"');
    }
    if (cleanup.single != steps.length - 1) {
      v.add('keystore cleanup must be the last build step');
    }
  }
  final List<String> lines = w.lines;
  for (int i = 0; i < lines.length; i++) {
    if (_isNoise(lines[i])) continue;
    final int all = RegExp(r'upload\.jks').allMatches(lines[i]).length;
    final int safe = RegExp(
      r'(\$RUNNER_TEMP|\$\{RUNNER_TEMP\}|runner\.temp\s*\}\})/upload\.jks',
    ).allMatches(lines[i]).length;
    if (safe < all) {
      v.add('line ${i + 1}: keystore path outside \$RUNNER_TEMP');
    }
  }
  return v;
}

final RegExp _secretPath = RegExp(
  r'jks|keystore|key\.properties|RUNNER_TEMP|runner\.temp',
  caseSensitive: false,
);

List<String> artifactPathViolations(String text) {
  final List<String> v = <String>[];
  for (final WorkflowStep s in Workflow(text).allSteps) {
    if (!(s.field('uses') ?? '').startsWith('actions/upload-artifact@')) {
      continue;
    }
    for (final String p in _withField(
      s,
    ).split('\n').map((String e) => e.trim())) {
      if (p.isEmpty) continue;
      if (_secretPath.hasMatch(p) ||
          RegExp(r'^(\.|\./|\*+|\*\*/\*|/.*|~.*)$').hasMatch(p)) {
        v.add('artifact at line ${s.start + 1}: path `$p` can reach secrets');
      }
    }
  }
  return v;
}

String _withField(WorkflowStep s) {
  final int i = _findKey(s.lines, 'with', s.fieldIndent);
  if (i < 0) return '';
  final int p = _findKey(
    s.lines,
    'path',
    s.fieldIndent + 2,
    within: _children(s.lines, i),
  );
  if (p < 0) return '';
  final String inl = _inline(s.lines[p]);
  if (inl.isNotEmpty && !RegExp(r'^[|>][-+]?$').hasMatch(inl)) return inl;
  return _children(s.lines, p).map((int j) => s.lines[j]).join('\n');
}

List<String> verifyOrderViolations(String text) {
  final List<WorkflowStep> steps = Workflow(text).steps('build');
  final List<String> v = <String>[];
  int idx(bool Function(WorkflowStep) f) => steps.indexWhere(f);
  final int build = idx(
    (WorkflowStep s) =>
        RegExp(r'flutter\s+build\s+appbundle').hasMatch(s.field('run') ?? ''),
  );
  final int verify = idx(
    (WorkflowStep s) => RegExp(
      r'(^|\s)\./scripts/verify_release_aab\.sh\s',
    ).hasMatch(s.field('run') ?? ''),
  );
  final int upload = idx(
    (WorkflowStep s) =>
        (s.field('uses') ?? '').startsWith('actions/upload-artifact@') &&
        RegExp(r'aab$').hasMatch(_withName(s)),
  );
  if (build < 0) v.add('no `flutter build appbundle` step');
  if (verify < 0) v.add('no step runs ./scripts/verify_release_aab.sh');
  if (upload < 0) v.add('no AAB upload-artifact step');
  if (build >= 0 && verify >= 0 && verify <= build) {
    v.add('verify must run AFTER the build');
  }
  if (verify >= 0 && upload >= 0 && upload <= verify) {
    v.add('the AAB must be uploaded only AFTER verify passes');
  }
  if (verify >= 0) {
    final WorkflowStep s = steps[verify];
    if (s.has('if')) v.add('verify step must not be conditional (`if:`)');
    if (s.has('continue-on-error')) {
      v.add('verify step must not continue-on-error');
    }
  }
  return v;
}

String _withName(WorkflowStep s) {
  final int i = _findKey(s.lines, 'with', s.fieldIndent);
  if (i < 0) return '';
  final int n = _findKey(
    s.lines,
    'name',
    s.fieldIndent + 2,
    within: _children(s.lines, i),
  );
  return n < 0 ? '' : _inline(s.lines[n]);
}

List<String> hook411Violations(String text) {
  final Workflow w = Workflow(text);
  final List<WorkflowStep> steps = w.steps('build');
  final int b = steps.indexWhere(
    (WorkflowStep s) =>
        RegExp(r'flutter\s+build\s+appbundle').hasMatch(s.field('run') ?? ''),
  );
  final int ver = steps.indexWhere(
    (WorkflowStep s) =>
        (s.field('run') ?? '').contains('verify_release_aab.sh'),
  );
  if (b < 1 || ver < 0) return <String>['cannot locate build/verify steps'];
  final List<int> marks = <int>[
    for (int i = 0; i < w.lines.length; i++)
      if (w.lines[i].trimLeft().startsWith('# 411:')) i,
  ];
  final List<String> v = <String>[];
  if (!marks.any((int m) => m > steps[b - 1].start && m < steps[b].start)) {
    v.add('no `# 411:` hook directly above the build step');
  }
  if (!marks.any((int m) => m > steps[b].start && m < steps[ver].start)) {
    v.add('no `# 411:` hook between the build and verify steps');
  }
  return v;
}

List<String> signingViolations(String text) {
  final Workflow w = Workflow(text);
  final List<String> v = <String>[];
  final List<WorkflowStep> builds = w.allSteps
      .where(
        (WorkflowStep s) => RegExp(
          r'flutter\s+build\s+appbundle',
        ).hasMatch(s.field('run') ?? ''),
      )
      .toList();
  if (builds.length != 1) {
    v.add('expected exactly one appbundle build, found ${builds.length}');
    return v;
  }
  final Map<String, String> env = builds.single.mapping('env');
  if (env['BEAUTICA_REQUIRE_RELEASE_SIGNING'] != '1') {
    v.add('build env must set BEAUTICA_REQUIRE_RELEASE_SIGNING: \'1\'');
  }
  for (int i = 0; i < w.lines.length; i++) {
    final String l = w.lines[i];
    if (_isNoise(l)) continue;
    final RegExpMatch? m = RegExp(
      r'BEAUTICA_ALLOW_DEBUG_SIGNED_RELEASE\s*[:=]\s*(.*)$',
    ).firstMatch(l);
    if (m != null && _unquote(_stripComment(m.group(1)!)).isNotEmpty) {
      v.add(
        'line ${i + 1}: BEAUTICA_ALLOW_DEBUG_SIGNED_RELEASE must stay empty',
      );
    }
    if (RegExp(r'--build-(number|name)\b').hasMatch(l)) {
      v.add('line ${i + 1}: --build-number/--build-name (§ 6.1 V2)');
    }
  }
  return v;
}

// --- Manifest + allow-list -------------------------------------------------

String _stripXmlComments(String xml) =>
    xml.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

List<String> manifestAdIdViolations(String xml) {
  final String live = _stripXmlComments(xml);
  final List<String> v = <String>[];
  if (!RegExp(
    r'<manifest\b[^>]*xmlns:tools="http://schemas\.android\.com/tools"',
  ).hasMatch(live)) {
    v.add('root <manifest> must declare xmlns:tools');
  }
  final Iterable<String> adId = RegExp(r'<uses-permission\b[^>]*>')
      .allMatches(live)
      .map((RegExpMatch m) => m.group(0)!)
      .where(
        (String t) => t.contains(
          'android:name="com.google.android.gms.permission.AD_ID"',
        ),
      );
  if (adId.length != 1 || !adId.single.contains('tools:node="remove"')) {
    v.add(
      'expected exactly one AD_ID <uses-permission … tools:node="remove"/>, '
      'got ${adId.toList()}',
    );
  }
  return v;
}

List<String> allowListViolations(String text) {
  final List<String> v = <String>[];
  final Set<String> seen = <String>{};
  final List<String> lines = text.split('\n');
  for (int i = 0; i < lines.length; i++) {
    final String l = lines[i].trim();
    if (l.isEmpty || l.startsWith('#')) continue;
    final RegExpMatch? m = RegExp(
      r'^([A-Za-z][\w.]*\.[A-Z][A-Z0-9_]*)\s+#\s*(\S.*)$',
    ).firstMatch(l);
    if (m == null) {
      v.add('line ${i + 1}: `$l` is not `<permission>  # why`');
      continue;
    }
    if (!seen.add(m.group(1)!)) v.add('line ${i + 1}: duplicate ${m.group(1)}');
    if (m.group(1)!.endsWith('.AD_ID')) v.add('line ${i + 1}: AD_ID allowed');
  }
  if (seen.isEmpty) v.add('allow-list has no entries');
  return v;
}

// ---------------------------------------------------------------------------

String _read(String p) => File(p).readAsStringSync();

/// Applies a text mutation and fails loudly if it did not change anything,
/// so a mutation probe can never be vacuous.
String mutate(String text, String from, String to) {
  expect(text, contains(from), reason: 'mutation anchor missing: $from');
  return text.replaceFirst(from, to);
}

void main() {
  late String wf;
  late String manifest;
  late String allow;

  setUpAll(() {
    wf = _read(kWorkflow);
    manifest = _read(kManifest);
    allow = _read(kAllowList);
  });

  group('release-aab.yml contract (real file)', () {
    test('triggers are exactly push tags mobile-v* + workflow_dispatch', () {
      expect(triggerViolations(wf), isEmpty);
    });
    test('permissions are contents: read only (top level and per job)', () {
      expect(permissionViolations(wf), isEmpty);
    });
    test('guard has no environment/secrets; build needs guard + env', () {
      expect(jobTopologyViolations(wf), isEmpty);
    });
    test('every external uses: is pinned to a 40-hex SHA', () {
      expect(pinViolations(wf), isEmpty);
    });
    test('no \${{ }} expression is interpolated inside a run: block', () {
      expect(injectionViolations(wf), isEmpty);
    });
    test('keystore lives in \$RUNNER_TEMP, removed last with if: always()', () {
      expect(keystoreViolations(wf), isEmpty);
    });
    test('no upload-artifact path can reach the keystore', () {
      expect(artifactPathViolations(wf), isEmpty);
    });
    test(
      'verify_release_aab.sh runs after the build, before the AAB upload',
      () {
        expect(verifyOrderViolations(wf), isEmpty);
      },
    );
    test('# 411: hooks sit above the build step and before verify', () {
      expect(hook411Violations(wf), isEmpty);
    });
    test('release signing is enforced; no version overrides', () {
      expect(signingViolations(wf), isEmpty);
    });
  });

  group('manifest + permission allow-list (real files)', () {
    test('AD_ID is stripped with tools:node="remove"', () {
      expect(manifestAdIdViolations(manifest), isEmpty);
    });
    test('allow-list entries are unique and each carries a # why', () {
      expect(allowListViolations(allow), isEmpty);
    });
  });

  // Each detector must go RED on a realistic regression of the real file.
  group('detectors fail on mutated copies', () {
    void red(List<String> Function(String) d, String mutated) {
      expect(d(mutated), isNotEmpty);
    }

    test('trigger: pull_request added', () {
      red(triggerViolations, mutate(wf, 'on:\n', 'on:\n  pull_request:\n'));
    });
    test('trigger: pull_request_target in inline list', () {
      red(
        triggerViolations,
        mutate(wf, 'on:\n  push:', 'on: [pull_request_target]\nx:\n  push:'),
      );
    });
    test('trigger: tag glob widened', () {
      red(triggerViolations, mutate(wf, "tags: ['mobile-v*']", "tags: ['v*']"));
    });
    test('trigger: branch filter added to push', () {
      red(
        triggerViolations,
        mutate(
          wf,
          "    tags: ['mobile-v*']\n",
          "    tags: ['mobile-v*']\n    branches: [main]\n",
        ),
      );
    });
    test('trigger: dry_run default flipped to false', () {
      red(triggerViolations, mutate(wf, 'default: true', 'default: false'));
    });
    test('permissions: top-level contents: write', () {
      red(
        permissionViolations,
        mutate(
          wf,
          'permissions:\n  contents: read\n',
          'permissions:\n  contents: write\n',
        ),
      );
    });
    test('permissions: extra top-level grant', () {
      red(
        permissionViolations,
        mutate(
          wf,
          'permissions:\n  contents: read\n',
          'permissions:\n  contents: read\n  id-token: write\n',
        ),
      );
    });
    test('permissions: write-all shorthand', () {
      red(
        permissionViolations,
        mutate(
          wf,
          'permissions:\n  contents: read\n',
          'permissions: write-all\n',
        ),
      );
    });
    test('permissions: job-level widening in guard', () {
      red(
        permissionViolations,
        mutate(
          wf,
          '    timeout-minutes: 5\n    permissions:\n      contents: read\n',
          '    timeout-minutes: 5\n    permissions:\n      contents: write\n',
        ),
      );
    });
    test('topology: environment added to guard', () {
      red(
        jobTopologyViolations,
        mutate(
          wf,
          '    timeout-minutes: 5\n',
          '    timeout-minutes: 5\n    environment: ci-trusted-secrets\n',
        ),
      );
    });
    test('topology: secret referenced in guard', () {
      red(
        jobTopologyViolations,
        mutate(
          wf,
          '          GITHUB_REF: \${{ github.ref }}\n',
          '          GITHUB_REF: \${{ github.ref }}\n'
              '          K: \${{ secrets.BEAUTICA_KEY_PASSWORD }}\n',
        ),
      );
    });
    test('topology: build loses needs: guard', () {
      red(jobTopologyViolations, mutate(wf, '    needs: guard\n', ''));
    });
    test('topology: build environment renamed', () {
      red(
        jobTopologyViolations,
        mutate(wf, 'environment: ci-trusted-secrets', 'environment: prod'),
      );
    });
    test('pin: action moved to a tag', () {
      red(
        pinViolations,
        mutate(
          wf,
          'actions/setup-java@c1e323688fd81a25caa38c78aa6df2d33d3e20d9',
          'actions/setup-java@v4',
        ),
      );
    });
    test('pin: 39-hex short SHA', () {
      red(
        pinViolations,
        mutate(
          wf,
          'actions/setup-java@c1e323688fd81a25caa38c78aa6df2d33d3e20d9',
          'actions/setup-java@c1e323688fd81a25caa38c78aa6df2d33d3e20d',
        ),
      );
    });
    for (final String expr in <String>[
      r'${{ github.ref_name }}',
      r'${{ inputs.dry_run }}',
      r'${{ github.event.head_commit.message }}',
    ]) {
      test('injection: $expr spliced into run:', () {
        red(
          injectionViolations,
          mutate(
            wf,
            'run: ./scripts/check_release_version.sh tag',
            'run: ./scripts/check_release_version.sh tag "$expr"',
          ),
        );
      });
    }
    test('injection: expression inside a multi-line run: body', () {
      red(
        injectionViolations,
        mutate(
          wf,
          '          umask 077\n',
          '          umask 077\n          echo "\${{ github.ref_name }}"\n',
        ),
      );
    });
    test('keystore: cleanup loses if: always()', () {
      red(
        keystoreViolations,
        mutate(
          wf,
          '        if: always()\n        run: rm -f',
          '        run: rm -f',
        ),
      );
    });
    test('keystore: cleanup runs only on success()', () {
      red(
        keystoreViolations,
        mutate(
          wf,
          '        if: always()\n        run: rm -f',
          '        if: success()\n        run: rm -f',
        ),
      );
    });
    test('keystore: decoded into the workspace', () {
      red(
        keystoreViolations,
        mutate(wf, '> "\$RUNNER_TEMP/upload.jks"', '> "upload.jks"'),
      );
    });
    test('artifact: report path points at the keystore', () {
      red(
        artifactPathViolations,
        mutate(
          wf,
          'path: build/release-verify.txt',
          r'path: ${{ runner.temp }}/upload.jks',
        ),
      );
    });
    test('artifact: \$RUNNER_TEMP added to the symbols list', () {
      red(
        artifactPathViolations,
        mutate(
          wf,
          '            build/symbols/\n',
          '            build/symbols/\n            \$RUNNER_TEMP/\n',
        ),
      );
    });
    test('artifact: whole workspace uploaded', () {
      red(
        artifactPathViolations,
        mutate(wf, 'path: build/release-manifest.xml', 'path: .'),
      );
    });
    test('verify: script call removed', () {
      red(
        verifyOrderViolations,
        mutate(
          wf,
          'run: ./scripts/verify_release_aab.sh "\$AAB_PATH"',
          'run: echo skipped',
        ),
      );
    });
    test('verify: made non-blocking', () {
      red(
        verifyOrderViolations,
        mutate(
          wf,
          '      - name: Verify release AAB\n',
          '      - name: Verify release AAB\n        continue-on-error: true\n',
        ),
      );
    });
    test('verify: moved after the AAB upload', () {
      const String verifyStep =
          '      - name: Verify release AAB\n'
          '        env:\n'
          r'          BEAUTICA_UPLOAD_CERT_SHA256: ${{ vars.BEAUTICA_UPLOAD_CERT_SHA256 }}'
          '\n'
          r'          AAB_PATH: ${{ steps.aab.outputs.path }}'
          '\n'
          r'        run: ./scripts/verify_release_aab.sh "$AAB_PATH"'
          '\n';
      final String without = mutate(wf, verifyStep, '');
      red(
        verifyOrderViolations,
        mutate(
          without,
          '      - name: Upload symbols + mappings\n',
          '$verifyStep      - name: Upload symbols + mappings\n',
        ),
      );
    });
    test('411: hook above the build step removed', () {
      red(
        hook411Violations,
        mutate(wf, '# 411: append the Sentry', '# later: append the Sentry'),
      );
    });
    test('411: hook after the build step removed', () {
      red(
        hook411Violations,
        mutate(wf, '# 411: Sentry symbol upload', '# Sentry symbol upload'),
      );
    });
    test('signing: REQUIRE_RELEASE_SIGNING dropped', () {
      red(
        signingViolations,
        mutate(
          wf,
          "BEAUTICA_REQUIRE_RELEASE_SIGNING: '1'",
          "BEAUTICA_REQUIRE_RELEASE_SIGNING: '0'",
        ),
      );
    });
    test('signing: debug-signed release waived', () {
      red(
        signingViolations,
        mutate(
          wf,
          "BEAUTICA_ALLOW_DEBUG_SIGNED_RELEASE: ''",
          "BEAUTICA_ALLOW_DEBUG_SIGNED_RELEASE: '1'",
        ),
      );
    });
    test('signing: --build-number override added', () {
      red(
        signingViolations,
        mutate(wf, '--flavor prod \\\n', '--flavor prod --build-number=9 \\\n'),
      );
    });
    test('manifest: tools:node="remove" dropped', () {
      red(
        manifestAdIdViolations,
        mutate(manifest, ' tools:node="remove"/>', '/>'),
      );
    });
    test('manifest: AD_ID strip commented out', () {
      final String line = manifest
          .split('\n')
          .firstWhere((String l) => l.contains('permission.AD_ID'));
      red(manifestAdIdViolations, mutate(manifest, line, '<!-- $line -->'));
    });
    test('allow-list: duplicate entry', () {
      red(allowListViolations, '$allow\nandroid.permission.INTERNET  # dup\n');
    });
    test('allow-list: entry without # why', () {
      red(
        allowListViolations,
        mutate(
          allow,
          'android.permission.WAKE_LOCK  # firebase_messaging: keeps',
          'android.permission.WAKE_LOCK\n# firebase_messaging: keeps',
        ),
      );
    });
    test('allow-list: AD_ID allowed back in', () {
      red(
        allowListViolations,
        '$allow\ncom.google.android.gms.permission.AD_ID  # ads\n',
      );
    });
  });
}
