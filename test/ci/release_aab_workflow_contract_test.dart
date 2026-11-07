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
//   D6  one appbundle build, no --build-number/--build-name.
//   D7  verify_release_aab.sh runs after the build and before the AAB upload.
//   D10 AD_ID stripped; allow-list entries unique, each with a `# why`.
//   D11 no artifact path can reach the keystore or google-services.json.
//   D13 google-services.json is injected from a required secret (env only),
//       jq-checked for a com.beautica.app client, proven inside the built AAB
//       (google_app_id) before verify, and deleted in an always() step.
//
// Phase 423 (phase-423-play-auto-upload.md) — automatic Play Internal upload:
//   D3  job `play-upload` needs build + release-notes, runs only on a mobile-v* tag
//       push (never workflow_dispatch), environment ci-trusted-secrets, no checkout,
//       no keystore / key / google-services secret.
//   D4  `id-token: write` only in play-upload (next to contents: read).
//   D5  build exposes `aab_sha256`; play-upload re-hashes the downloaded AAB before
//       the upload, blocking (no if / continue-on-error).
//   D6  status comes from vars.BEAUTICA_PLAY_RELEASE_STATUS after a draft|completed
//       validation step.
//   D7  r0adkll inputs: tracks internal, whatsNewDirectory, mappingFile; no
//       debugSymbols / changesNotSentForReview / userFraction / inAppUpdatePriority;
//       no continue-on-error anywhere in the job.
//   D2  exactly ONE credential form: keyless WIF (google-github-actions/auth with
//       cleanup_credentials not false) XOR serviceAccountJsonPlainText from secret
//       BEAUTICA_PLAY_SERVICE_ACCOUNT_JSON (fallback; never inside a run:).
//   D10 job `release-notes` needs guard, no environment, no secrets, no id-token,
//       runs scripts/check_release_notes.sh (dispatch mode on a dry run) and uploads
//       release-notes/ as artifact `release-notes`.
//
// Phase 411 (phase-411-R.4-crash-symbol-upload.md) — Sentry symbolication, in
// [sentry411Violations] (replaces 409's `# 411:` hook markers):
//   D1  the build runs --obfuscate --split-debug-info=build/symbols, saves the
//       obfuscation map, and passes BEAUTICA_SENTRY_DSN / BEAUTICA_RELEASE as
//       dart-defines from env (DSN = secrets.BEAUTICA_SENTRY_DSN_PROD).
//   D2  a preflight step before the build requires both Sentry secrets and
//       writes `check_release_version.sh sentry-release` into $GITHUB_ENV; job
//       env SENTRY_ORG=beautica, SENTRY_PROJECT=beautica-mobile.
//   D4  the build step env carries secrets.SENTRY_AUTH_TOKEN (Gradle R8 upload).
//   D3/D7 `dart run sentry_dart_plugin` runs after the symbols artifact upload,
//       blocking (no if / continue-on-error), and checks the plugin's
//       `failed=0` summary (the plugin itself exits 0 on a failed map upload).
//   A4  no DSN / sntrys_ token literal in the workflow, pubspec, Gradle files;
//       config/env/*.json carry no Sentry key; pubspec `sentry:` has no auth_token.
import 'dart:io';

import 'package:beautica_mobile/core/diagnostics/crash_reporting.dart';
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
    // 423 D4: only play-upload may (and must) add id-token: write.
    final String want = job == kPlayJob
        ? 'contents: read|id-token: write'
        : 'contents: read';
    if (job == kPlayJob && jp < 0) {
      v.add('job $job must declare `contents: read` + `id-token: write`');
    }
    if (jp >= 0 &&
        (_inline(w.lines[jp]).isNotEmpty || grants(jp).join('|') != want)) {
      v.add(
        'job $job permissions must be exactly `${want.replaceAll('|', ' + ')}`: '
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
  // 423: the WIF attribute condition pins environment ci-trusted-secrets.
  if (w.jobs.containsKey(kPlayJob) &&
      w.jobField(kPlayJob, 'environment') != 'ci-trusted-secrets') {
    v.add('$kPlayJob must have `environment: ci-trusted-secrets`');
  }
  for (final String job in w.jobs.keys) {
    if (job != 'build' &&
        job != kPlayJob &&
        w.jobField(job, 'environment') != null) {
      v.add('job $job names an environment; only build and $kPlayJob may');
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
  r'jks|keystore|key\.properties|RUNNER_TEMP|runner\.temp|google-services|'
  r'^android(/|$)|^build/?$|^build/app/?$|generated/res/process.*GoogleServices',
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

const String _dsnSecret = 'BEAUTICA_SENTRY_DSN_PROD';
const String _sentryTokenSecret = 'SENTRY_AUTH_TOKEN';

bool _blocking(WorkflowStep s) => !s.has('if') && !s.has('continue-on-error');

List<String> sentry411Violations(String text) {
  final Workflow w = Workflow(text);
  final List<String> v = <String>[];
  final List<WorkflowStep> steps = w.steps('build');
  const String dsnRef = '\${{ secrets.$_dsnSecret }}';
  const String tokenRef = '\${{ secrets.$_sentryTokenSecret }}';
  final int b = steps.indexWhere(
    (WorkflowStep s) =>
        RegExp(r'flutter\s+build\s+appbundle').hasMatch(s.field('run') ?? ''),
  );
  final int pre = steps.indexWhere(
    (WorkflowStep s) => RegExp(
      r'\./scripts/check_release_version\.sh\s+sentry-release\b',
    ).hasMatch(s.field('run') ?? ''),
  );
  final int symbols = steps.indexWhere(
    (WorkflowStep s) =>
        (s.field('uses') ?? '').startsWith('actions/upload-artifact@') &&
        RegExp(r'symbols$').hasMatch(_withName(s)),
  );
  final int up = steps.indexWhere(
    (WorkflowStep s) => RegExp(
      r'(^|\s)dart\s+run\s+sentry_dart_plugin\b',
    ).hasMatch(s.field('run') ?? ''),
  );
  if (b < 0) return <String>['no `flutter build appbundle` step'];

  // Job env (D2 / step 3).
  final int? j = w.jobs['build'];
  final int je = j == null
      ? -1
      : _findKey(w.lines, 'env', 4, within: _children(w.lines, j));
  final Map<String, String> jobEnv = <String, String>{
    if (je >= 0)
      for (final int i in _children(w.lines, je))
        if (!_isNoise(w.lines[i]) && w.lines[i].contains(':'))
          w.lines[i].trimLeft().split(':').first.trim(): _unquote(
            _inline(w.lines[i].trimLeft()),
          ),
  };
  if (jobEnv['SENTRY_ORG'] != 'beautica') {
    v.add('build job env must set SENTRY_ORG: beautica');
  }
  if (jobEnv['SENTRY_PROJECT'] != 'beautica-mobile') {
    v.add('build job env must set SENTRY_PROJECT: beautica-mobile');
  }

  // D1 / D4: the build step.
  final WorkflowStep build = steps[b];
  final String run = build.field('run') ?? '';
  final Map<String, String> env = build.mapping('env');
  if (env['BEAUTICA_SENTRY_DSN'] != dsnRef) {
    v.add('build env BEAUTICA_SENTRY_DSN must be $dsnRef');
  }
  if (env[_sentryTokenSecret] != tokenRef) {
    v.add(
      'build env $_sentryTokenSecret must be $tokenRef (R8 mapping upload)',
    );
  }
  for (final String flag in <String>[
    '--obfuscate',
    '--split-debug-info=build/symbols',
    '--extra-gen-snapshot-options=--save-obfuscation-map=build/app/obfuscation.map.json',
    '--dart-define=BEAUTICA_SENTRY_DSN="\$BEAUTICA_SENTRY_DSN"',
    '--dart-define=BEAUTICA_RELEASE="\$SENTRY_RELEASE"',
  ]) {
    if (!run.contains(flag)) v.add('build command lacks `$flag`');
  }

  // D2: preflight before the build.
  if (pre < 0) {
    v.add('no step writes `check_release_version.sh sentry-release` output');
  } else {
    final WorkflowStep p = steps[pre];
    final Map<String, String> pe = p.mapping('env');
    if (pre >= b) v.add('sentry-release step must run BEFORE the build');
    if (!_blocking(p)) v.add('sentry-release step must be unconditional');
    if (!(p.field('run') ?? '').contains(r'$GITHUB_ENV')) {
      v.add('sentry-release output must be appended to \$GITHUB_ENV');
    }
    if (pe['BEAUTICA_SENTRY_DSN'] != dsnRef ||
        pe[_sentryTokenSecret] != tokenRef) {
      v.add('preflight must check both $_dsnSecret and $_sentryTokenSecret');
    }
  }

  // D3 / D7: the Dart symbol upload.
  if (up < 0) {
    v.add('no `dart run sentry_dart_plugin` step');
  } else {
    final WorkflowStep u = steps[up];
    final String ur = u.field('run') ?? '';
    if (up <= b) v.add('sentry_dart_plugin must run AFTER the build');
    if (symbols < 0 || up <= symbols) {
      v.add(
        'sentry_dart_plugin must run AFTER the symbols artifact upload (D7)',
      );
    }
    if (!_blocking(u)) v.add('sentry_dart_plugin step must be blocking');
    if (u.mapping('env')[_sentryTokenSecret] != tokenRef) {
      v.add('sentry_dart_plugin step env must carry $tokenRef');
    }
    if (!ur.contains('pipefail')) {
      v.add('sentry_dart_plugin pipe needs pipefail');
    }
    if (!ur.contains('failed=0')) {
      v.add('sentry_dart_plugin output must be checked for `failed=0`');
    }
  }

  // A4: a Sentry secret is never echoed and no build-job shell traces (xtrace
  // would print the expanded DSN / token of every command).
  final RegExp secretVar = RegExp(
    r'\$\{?(BEAUTICA_SENTRY_DSN|SENTRY_AUTH_TOKEN)\b',
  );
  for (final WorkflowStep s in steps) {
    final String r = s.field('run') ?? '';
    if (RegExp(r'\bset\s+(-[a-zA-Z]*x|-o\s+xtrace)').hasMatch(r)) {
      v.add('step at line ${s.start + 1}: shell tracing in the build job');
    }
    for (final String l in r.split('\n')) {
      if (RegExp(r'\b(echo|printf|cat|printenv|tee)\b').hasMatch(l) &&
          secretVar.hasMatch(l)) {
        v.add('step at line ${s.start + 1}: prints a Sentry secret: `$l`');
      }
    }
  }

  // A4: no literal DSN / token anywhere in the file.
  for (int i = 0; i < w.lines.length; i++) {
    final String l = w.lines[i];
    if (RegExp(r'https://[0-9a-f]{16,}@|sntrys_').hasMatch(l)) {
      v.add('line ${i + 1}: literal Sentry DSN / token');
    }
    if (!_isNoise(l) && RegExp(r'\bSENTRY_URL\b|de\.sentry\.io').hasMatch(l)) {
      v.add('line ${i + 1}: region comes from the org token, not SENTRY_URL');
    }
  }
  return v;
}

/// A4 on the non-workflow files: pubspec, Gradle, config/env/*.json.
List<String> sentrySecretFileViolations(Map<String, String> files) {
  final List<String> v = <String>[];
  files.forEach((String path, String text) {
    if (RegExp(r'sntrys_|https://[0-9a-f]{16,}@').hasMatch(text)) {
      v.add('$path: literal Sentry token / DSN');
    }
    if (RegExp(r'^\s*auth_token\s*:', multiLine: true).hasMatch(text)) {
      v.add('$path: auth_token key (env only)');
    }
    if (path.startsWith('config/env/') && text.contains('SENTRY')) {
      v.add('$path: Sentry key in a committed env file (dart-define only)');
    }
  });
  return v;
}

/// Body of the first `name {` block (brace-matched), or null.
String? _kotlinBlock(String text, String name) {
  final RegExpMatch? m = RegExp(
    '^\\s*${RegExp.escape(name)}\\s*\\{',
    multiLine: true,
  ).firstMatch(text);
  if (m == null) return null;
  int depth = 0;
  for (int i = m.end - 1; i < text.length; i++) {
    if (text[i] == '{') depth++;
    if (text[i] == '}' && --depth == 0) return text.substring(m.end, i);
  }
  return null;
}

String _stripLineComments(String t) => t
    .split('\n')
    .map((String l) => l.contains('//') ? l.substring(0, l.indexOf('//')) : l)
    .join('\n');

/// 411 D4: the Sentry Android Gradle plugin is exact-pinned, applied, and used
/// ONLY for the R8 mapping (upload armed by SENTRY_AUTH_TOKEN alone); every
/// other feature (auto-install, bytecode tracing, source/native uploads,
/// telemetry, size/distribution/snapshots, runtime optimizations) is off.
List<String> sentryGradleViolations(String app, String settings) {
  final List<String> v = <String>[];
  final String s = _stripLineComments(settings);
  if (!RegExp(
    r'id\("io\.sentry\.android\.gradle"\)\s+version\s+"\d+\.\d+\.\d+"\s+apply\s+false',
  ).hasMatch(s)) {
    v.add('settings.gradle.kts: io.sentry.android.gradle not exact-pinned');
  }
  final String a = _stripLineComments(app);
  final String plugins = _kotlinBlock(a, 'plugins') ?? '';
  if (!plugins.contains('id("io.sentry.android.gradle")')) {
    v.add('app/build.gradle.kts: Sentry Gradle plugin not applied');
  }
  final String? block = _kotlinBlock(a, 'sentry');
  if (block == null) return <String>[...v, 'no `sentry { }` block'];
  // Each property set exactly once, to exactly this value.
  const Map<String, String> props = <String, String>{
    'org': '"beautica"',
    'projectName': '"beautica-mobile"',
    'includeProguardMapping': 'true',
    'autoUploadProguardMapping':
        '!System.getenv("SENTRY_AUTH_TOKEN").isNullOrBlank()',
    'uploadNativeSymbols': 'false',
    'includeNativeSources': 'false',
    'includeSourceContext': 'false',
    'includeDependenciesReport': 'false',
    'telemetry': 'false',
  };
  props.forEach((String k, String want) {
    final List<String> got = RegExp(
      '(^|[^.\\w])$k\\.set\\((.*)\\)\\s*\$',
      multiLine: true,
    ).allMatches(block).map((RegExpMatch m) => m.group(2)!.trim()).toList();
    if (got.length != 1 || got.single != want) {
      v.add('sentry { $k.set($want) } expected once, got $got');
    }
  });
  for (final String sub in <String>[
    'autoInstallation',
    'tracingInstrumentation',
    'sizeAnalysis',
    'distribution',
    'snapshots',
    'runtimeOptimizations',
  ]) {
    final String body = (_kotlinBlock(block, sub) ?? '').trim();
    if (body != 'enabled.set(false)') {
      v.add('sentry { $sub { enabled.set(false) } } expected, got "$body"');
    }
  }
  if (RegExp(r'\b(authToken|url)\s*\.set|\bauthToken\s*=').hasMatch(block)) {
    v.add('sentry { } must not set authToken / url (env + org token only)');
  }
  return v;
}

/// 411 D2/D3: pubspec pins sentry_dart_plugin exactly; its `sentry:` block
/// uploads ONLY debug symbols + the obfuscation map (paths = the build's
/// flags) and takes release / dist / auth / url from env (never the file).
List<String> sentryPubspecViolations(String pubspec) {
  final List<String> v = <String>[];
  final RegExpMatch? pin = RegExp(
    r'^  sentry_dart_plugin:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec);
  if (pin == null || !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(pin.group(1)!)) {
    v.add('sentry_dart_plugin must be exact-pinned, got ${pin?.group(1)}');
  }
  final List<String> lines = pubspec.split('\n');
  final int top = lines.indexWhere(
    (String l) => RegExp(r'^sentry:\s*$').hasMatch(l),
  );
  if (top < 0) return <String>[...v, 'no top-level `sentry:` block'];
  final Map<String, String> cfg = <String, String>{};
  for (int i = top + 1; i < lines.length; i++) {
    final String l = lines[i];
    if (l.trim().isEmpty || l.trimLeft().startsWith('#')) continue;
    if (!l.startsWith(' ')) break;
    final int c = l.indexOf(':');
    if (c < 0) continue;
    cfg[l.substring(0, c).trim()] = _unquote(_stripComment(l.substring(c + 1)));
  }
  const Map<String, String> want = <String, String>{
    'org': 'beautica',
    'project': 'beautica-mobile',
    'upload_debug_symbols': 'true',
    'upload_sources': 'false',
    'upload_source_maps': 'false',
    'symbols_path': 'build/symbols',
    'dart_symbol_map_path': 'build/app/obfuscation.map.json',
    'commits': 'false',
  };
  want.forEach((String k, String val) {
    if (cfg[k] != val) v.add('pubspec sentry.$k must be $val, got ${cfg[k]}');
  });
  for (final String k in cfg.keys) {
    if (!want.containsKey(k)) {
      v.add('pubspec sentry.$k not allowed (release/dist/auth/url from env)');
    }
  }
  return v;
}

/// Runs a workflow `run:` body the way the runner does (`bash -e`), with
/// [env] only, from the package root. Returns exit code + combined output.
({int code, String out}) runStep(
  String script,
  Directory tmp,
  Map<String, String> env, {
  String? pathPrefix,
}) {
  final File f = File('${tmp.path}/step.sh')..writeAsStringSync(script);
  final ProcessResult r = Process.runSync(
    'bash',
    <String>['--noprofile', '--norc', '-e', f.path],
    environment: <String, String>{
      'PATH':
          '${pathPrefix == null ? '' : '$pathPrefix:'}'
          '${Platform.environment['PATH']}',
      'HOME': Platform.environment['HOME'] ?? tmp.path,
      'RUNNER_TEMP': tmp.path,
      ...env,
    },
    includeParentEnvironment: false,
  );
  return (code: r.exitCode, out: '${r.stdout}${r.stderr}');
}

/// Runs the "Upload Dart symbols to Sentry" step body against a fake `dart`
/// that prints [log] and exits [exit].
({int code, String out}) runUploadStep(String script, String log, int exit) {
  final Directory tmp = Directory.systemTemp.createTempSync('sdp411_');
  try {
    final Directory bin = Directory('${tmp.path}/bin')..createSync();
    File('${tmp.path}/fake.log').writeAsStringSync(log);
    final File dart = File('${bin.path}/dart')
      ..writeAsStringSync(
        '#!/usr/bin/env bash\ncat "\$FAKE_LOG"\nexit "\$FAKE_EXIT"\n',
      );
    Process.runSync('chmod', <String>['+x', dart.path]);
    return runStep(script, tmp, <String, String>{
      'FAKE_LOG': '${tmp.path}/fake.log',
      'FAKE_EXIT': '$exit',
      'SENTRY_AUTH_TOKEN': 'sntrys_FAKE_TOKEN_411',
      'SENTRY_RELEASE': 'beautica-mobile@1.2.3+45',
      'SENTRY_DIST': '45',
    }, pathPrefix: bin.path);
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

String _sdpLine(String s) => '\n\x1b[38;5;9m$s\x1b[0m\n';
String sdpSummary(int a, int s, int f) => _sdpLine(
  'Dart symbol map upload summary: attempted=$a, succeeded=$s, failed=$f',
);
String sdpFailedLine() => _sdpLine(
  'Dart symbol map upload failed for "build/symbols/app.android-arm64.symbols".',
);

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

// --- D13 Firebase config ----------------------------------------------------

const String _gsSecret = 'BEAUTICA_GOOGLE_SERVICES_JSON_BASE64';
const String _gsPath = 'android/app/google-services.json';
const String _gsGenerated = 'build/app/generated/res/process*GoogleServices';

bool _isAppbundleBuild(WorkflowStep s) =>
    RegExp(r'flutter\s+build\s+appbundle').hasMatch(s.field('run') ?? '');

List<String> firebaseInjectViolations(String text) {
  final Workflow w = Workflow(text);
  final List<String> v = <String>[];
  final List<WorkflowStep> steps = w.steps('build');
  for (int i = 0; i < w.lines.length; i++) {
    final String l = w.lines[i];
    if (_isNoise(l) || !l.contains('secrets.$_gsSecret')) continue;
    if (!RegExp(
      '^\\s+[A-Z][A-Z0-9_]*:\\s*\\\$\\{\\{\\s*secrets\\.$_gsSecret\\s*\\}\\}\\s*\$',
    ).hasMatch(l)) {
      v.add('line ${i + 1}: $_gsSecret must reach the shell only via env:');
    }
  }
  final List<int> inject = <int>[
    for (int i = 0; i < steps.length; i++)
      if (steps[i]
          .mapping('env')
          .values
          .any((String e) => RegExp('secrets\\.$_gsSecret\\b').hasMatch(e)))
        i,
  ];
  if (inject.length != 1) {
    v.add(
      'expected exactly one step reading $_gsSecret, found ${inject.length}',
    );
    return v;
  }
  final WorkflowStep s = steps[inject.single];
  final String key = s
      .mapping('env')
      .entries
      .firstWhere((MapEntry<String, String> e) => e.value.contains(_gsSecret))
      .key;
  final String run = s.field('run') ?? '';
  if (s.has('if')) v.add('inject step must not be conditional (`if:`)');
  if (s.has('continue-on-error')) {
    v.add('inject step must not continue-on-error');
  }
  final RegExpMatch? req = RegExp(
    'if \\[ -z "\\\$$key" \\]; then\\necho "::error::[^\\n]*"\\nexit 1\\nfi',
  ).firstMatch(run);
  final int umask = run.indexOf('umask 077');
  final int decode = run.indexOf('base64 --decode > "\$gs"');
  if (req == null) {
    v.add('missing secret is not a hard ::error:: + exit 1');
  }
  if (!run.contains('gs=$_gsPath')) v.add('json must be decoded into $_gsPath');
  if (decode < 0) v.add('secret is not base64-decoded into \$gs');
  if (umask < 0 || (decode >= 0 && umask > decode)) {
    v.add('umask 077 must precede the decode');
  }
  if (req != null && decode >= 0 && req.start > decode) {
    v.add('required-secret check must precede the decode');
  }
  if (!RegExp(
    r'if ! jq -e \. "\$gs"[^\n]*; then\n(rm -f "\$gs"\n)?echo "::error::[^\n]*"\nexit 1',
  ).hasMatch(run)) {
    v.add('malformed JSON is not rejected with ::error:: + exit 1');
  }
  if (!RegExp(
    r'if ! jq -e --arg pkg com\.beautica\.app \\\n'
    r"'any\(\.client\[\]\?; \.client_info\.android_client_info\.package_name == \$pkg\)' \\\n"
    r'"\$gs" > /dev/null; then\n(rm -f "\$gs"\n)?'
    r'echo "::error::[^\n]*com\.beautica\.app[^\n]*"\nexit 1',
  ).hasMatch(run)) {
    v.add('no exact jq package_name == com.beautica.app check with exit 1');
  }
  if (RegExp(
    r'\b(cat|head|tail|less)\b[^\n]*\$gs|jq\s+(-r\s+)?\.\s+"\$gs"\s*$',
  ).hasMatch(run)) {
    v.add('inject step prints the json content');
  }
  final int setup = steps.indexWhere(
    (WorkflowStep e) =>
        (e.field('uses') ?? '') == './.github/actions/flutter-setup',
  );
  final int build = steps.indexWhere(_isAppbundleBuild);
  if (setup < 0 || inject.single < setup) {
    v.add('inject must run after Flutter setup');
  }
  if (build < 0 || inject.single > build) {
    v.add('inject must run before the appbundle build');
  }
  return v;
}

List<String> firebaseAabCheckViolations(String text) {
  final List<WorkflowStep> steps = Workflow(text).steps('build');
  final List<String> v = <String>[];
  final int resolve = steps.indexWhere(
    (WorkflowStep s) => s.field('id') == 'aab',
  );
  final int verify = steps.indexWhere(
    (WorkflowStep s) =>
        (s.field('run') ?? '').contains('verify_release_aab.sh'),
  );
  final int check = steps.indexWhere(
    (WorkflowStep s) => RegExp(
      r'grep -aq google_app_id "\$res"',
    ).hasMatch(s.field('run') ?? ''),
  );
  if (check < 0) {
    v.add('no step checks the AAB for google_app_id');
    return v;
  }
  final WorkflowStep s = steps[check];
  final String run = s.field('run') ?? '';
  if (s.mapping('env')['AAB_PATH'] != r'${{ steps.aab.outputs.path }}') {
    v.add('AAB check must take AAB_PATH from steps.aab.outputs.path via env:');
  }
  if (!run.contains(r'unzip -p "$AAB_PATH" base/resources.pb > "$res"')) {
    v.add('AAB check must read base/resources.pb of \$AAB_PATH');
  }
  if (!RegExp(
    r'echo "::error::AAB built WITHOUT Firebase config \(google-services plugin skipped\)"\nexit 1',
  ).hasMatch(run)) {
    v.add('missing google_app_id is not ::error:: + exit 1');
  }
  if (s.has('if')) v.add('AAB check must not be conditional (`if:`)');
  if (s.has('continue-on-error')) v.add('AAB check must not continue-on-error');
  if (resolve < 0 || check < resolve) {
    v.add('AAB check must run after "Resolve AAB path"');
  }
  if (verify < 0 || check > verify) {
    v.add('AAB check must run before verify_release_aab.sh');
  }
  return v;
}

List<String> firebaseCleanupViolations(String text) {
  final List<WorkflowStep> steps = Workflow(text).steps('build');
  final List<String> v = <String>[];
  bool isCleanup(WorkflowStep s) =>
      RegExp(r'^rm -r?f\s').hasMatch(s.field('run') ?? '');
  final List<int> cleanup = <int>[
    for (int i = 0; i < steps.length; i++)
      if (RegExp(
        '^rm -r?f\\s.*${RegExp.escape(_gsPath)}',
      ).hasMatch(steps[i].field('run') ?? ''))
        i,
  ];
  if (cleanup.length != 1) {
    v.add(
      'expected exactly one $_gsPath cleanup step, found ${cleanup.length}',
    );
    return v;
  }
  final WorkflowStep c = steps[cleanup.single];
  if (!_isAlways(c.field('if'))) {
    v.add('$_gsPath cleanup must be `if: always()`, got "${c.field('if')}"');
  }
  // Plugin-generated values (google_app_id, API key) must go too (security LOW).
  if (!RegExp(
    '^rm -rf\\s+"?${RegExp.escape(_gsPath)}"?\\s+${RegExp.escape(_gsGenerated)}\$',
  ).hasMatch(c.field('run') ?? '')) {
    v.add('cleanup must be `rm -rf $_gsPath $_gsGenerated`');
  }
  for (int i = cleanup.single + 1; i < steps.length; i++) {
    if (!isCleanup(steps[i]) || !_isAlways(steps[i].field('if'))) {
      v.add('$_gsPath cleanup must sit in the trailing always() cleanup steps');
    }
  }
  return v;
}

// --- 423 Play upload + release notes ----------------------------------------

const String kPlayJob = 'play-upload';
const String kNotesJob = 'release-notes';
const String _playJsonSecret = 'BEAUTICA_PLAY_SERVICE_ACCOUNT_JSON';
const List<String> _playIfClauses = <String>[
  "github.event_name == 'push'",
  "github.ref_type == 'tag'",
  "startsWith(github.ref, 'refs/tags/mobile-v')",
];

String _expr(String? v) => (v ?? '')
    .replaceFirst(RegExp(r'^\$\{\{\s*'), '')
    .replaceFirst(RegExp(r'\s*\}\}$'), '')
    .trim();

/// Live (non-comment) line indices of a job's body.
List<int> _jobBody(Workflow w, String job) {
  final int? j = w.jobs[job];
  return j == null
      ? <int>[]
      : _children(w.lines, j).where((int i) => !_isNoise(w.lines[i])).toList();
}

bool _uses(WorkflowStep s, String action) =>
    (s.field('uses') ?? '').startsWith('$action@');

List<String> playUploadViolations(String text) {
  final Workflow w = Workflow(text);
  final List<String> v = <String>[];
  if (!w.jobs.containsKey(kPlayJob)) return <String>['no `$kPlayJob` job'];

  final Set<String> needs = (w.jobField(kPlayJob, 'needs') ?? '')
      .replaceAll(RegExp(r'[\[\]\s]'), '')
      .split(',')
      .where((String e) => e.isNotEmpty)
      .toSet();
  if (needs.length != 2 || !needs.containsAll(<String>['build', kNotesJob])) {
    v.add('$kPlayJob must have `needs: [build, $kNotesJob]`, got $needs');
  }

  // D3: tag push only. Every clause present, joined by && and nothing else.
  final String cond = _expr(w.jobField(kPlayJob, 'if'));
  String residue = cond;
  for (final String c in _playIfClauses) {
    if (!cond.contains(c)) v.add('$kPlayJob `if:` lacks `$c` (D3)');
    residue = residue.replaceFirst(c, '');
  }
  if (residue.replaceAll('&&', '').trim().isNotEmpty) {
    v.add('$kPlayJob `if:` must be only the D3 tag-push clauses, got "$cond"');
  }

  final List<int> body = _jobBody(w, kPlayJob);
  for (final int i in body) {
    final String l = w.lines[i];
    if (RegExp(
      r'BEAUTICA_(KEYSTORE|KEY_|GOOGLE_SERVICES)|upload\.jks',
    ).hasMatch(l)) {
      v.add('$kPlayJob line ${i + 1} touches the keystore/key/google-services');
    }
    for (final RegExpMatch m in RegExp(r'secrets\.(\w+)').allMatches(l)) {
      if (m.group(1) != _playJsonSecret) {
        v.add('$kPlayJob line ${i + 1} references secrets.${m.group(1)}');
      }
    }
    if (RegExp(r'^\s*continue-on-error\s*:').hasMatch(l)) {
      v.add('$kPlayJob line ${i + 1}: continue-on-error (D7)');
    }
  }

  final List<WorkflowStep> steps = w.steps(kPlayJob);
  for (final WorkflowStep s in steps) {
    final String uses = s.field('uses') ?? '';
    if (uses.startsWith('actions/checkout@') || uses.startsWith('./')) {
      v.add(
        '$kPlayJob step at line ${s.start + 1} checks out / runs repo code',
      );
    }
    if ((s.field('run') ?? '').contains(_playJsonSecret)) {
      v.add('$kPlayJob step at line ${s.start + 1}: $_playJsonSecret in run:');
    }
  }
  for (final String art in <String>['aab', 'symbols', kNotesJob]) {
    if (!steps.any(
      (WorkflowStep s) =>
          _uses(s, 'actions/download-artifact') &&
          s.mapping('with')['name'] == art,
    )) {
      v.add('$kPlayJob does not download artifact `$art`');
    }
  }

  final List<int> uploads = <int>[
    for (int i = 0; i < steps.length; i++)
      if (_uses(steps[i], 'r0adkll/upload-google-play')) i,
  ];
  if (uploads.length != 1) {
    v.add('expected exactly one r0adkll upload step, found ${uploads.length}');
    return v;
  }
  final int up = uploads.single;
  final WorkflowStep upload = steps[up];
  final Map<String, String> wi = upload.mapping('with');
  if (upload.has('if')) v.add('upload step must not be conditional');
  if (wi['packageName'] != 'com.beautica.app') {
    v.add('packageName must be com.beautica.app, got ${wi['packageName']}');
  }
  if (wi['tracks'] != 'internal') {
    v.add('tracks must be exactly `internal`, got "${wi['tracks']}"');
  }
  if (_expr(wi['status']) != 'vars.BEAUTICA_PLAY_RELEASE_STATUS') {
    v.add('status must come from vars.BEAUTICA_PLAY_RELEASE_STATUS (D6)');
  }
  if (_expr(wi['releaseName']) != 'github.ref_name') {
    v.add('releaseName must be github.ref_name');
  }
  for (final String k in <String>['whatsNewDirectory', 'mappingFile']) {
    if ((wi[k] ?? '').isEmpty) v.add('upload step lacks `$k` (D7/D8)');
  }
  for (final String k in <String>[
    'track',
    'debugSymbols',
    'changesNotSentForReview',
    'userFraction',
    'inAppUpdatePriority',
  ]) {
    if (wi.containsKey(k)) v.add('upload step must not set `$k` (D7)');
  }

  // D6: draft|completed validation of the same variable, before the upload.
  final int status = steps.indexWhere((WorkflowStep s) {
    final MapEntry<String, String>? e = s
        .mapping('env')
        .entries
        .where(
          (MapEntry<String, String> e) =>
              _expr(e.value) == 'vars.BEAUTICA_PLAY_RELEASE_STATUS',
        )
        .firstOrNull;
    final String run = s.field('run') ?? '';
    return e != null &&
        RegExp(
          'case "\\\$${e.key}" in\n'
          r'draft \| completed\)\n[^\n]*\n\*\)\n[^\n]*::error::[^\n]*\nexit 1 ;;',
        ).hasMatch(run);
  });
  if (status < 0) {
    v.add(
      'no draft|completed validation step for BEAUTICA_PLAY_RELEASE_STATUS',
    );
  } else if (status > up) {
    v.add('status validation must run before the upload');
  }

  // D5: sha256 of the downloaded AAB == build's verified hash, before upload.
  final int sha = steps.indexWhere((WorkflowStep s) {
    final MapEntry<String, String>? e = s
        .mapping('env')
        .entries
        .where(
          (MapEntry<String, String> e) =>
              _expr(e.value) == 'needs.build.outputs.aab_sha256',
        )
        .firstOrNull;
    final String run = s.field('run') ?? '';
    return e != null &&
        run.contains('sha256sum') &&
        RegExp(
          'if \\[ "\\\$actual" != "\\\$${e.key}" \\]; then\n'
          r'echo "::error::[^\n]*"\nexit 1',
        ).hasMatch(run);
  });
  if (sha < 0) {
    v.add(
      'no step compares the AAB sha256 with needs.build.outputs.aab_sha256',
    );
  } else {
    final WorkflowStep s = steps[sha];
    if (sha > up) v.add('sha256 check must run before the upload');
    if (s.has('if')) v.add('sha256 check must not be conditional');
    if (s.has('continue-on-error')) {
      v.add('sha256 check must not continue-on-error');
    }
    final String? id = s.field('id');
    if (id == null || _expr(wi['releaseFiles']) != 'steps.$id.outputs.path') {
      v.add(
        'releaseFiles must be the sha256-checked AAB (steps.<id>.outputs.path)',
      );
    }
  }
  final int? b = w.jobs['build'];
  final int bo = b == null
      ? -1
      : _findKey(w.lines, 'outputs', 4, within: _children(w.lines, b));
  final int bs = bo < 0
      ? -1
      : _findKey(w.lines, 'aab_sha256', 6, within: _children(w.lines, bo));
  if (bs < 0 || _expr(_inline(w.lines[bs])) != 'steps.aab.outputs.sha256') {
    v.add('build must expose outputs.aab_sha256 = steps.aab.outputs.sha256');
  }
  final WorkflowStep? resolve = w
      .steps('build')
      .where((WorkflowStep s) => s.field('id') == 'aab')
      .firstOrNull;
  if (resolve == null ||
      !RegExp(
        r'echo "sha256=\$\(sha256sum "\$aab" \| cut -d . . -f 1\)" >> "\$GITHUB_OUTPUT"',
      ).hasMatch(resolve.field('run') ?? '')) {
    v.add('build step `aab` must write its sha256sum to \$GITHUB_OUTPUT');
  }

  // D2: exactly one credential form.
  final List<int> auths = <int>[
    for (int i = 0; i < steps.length; i++)
      if (_uses(steps[i], 'google-github-actions/auth')) i,
  ];
  final bool keyForm =
      _expr(wi['serviceAccountJsonPlainText']) == 'secrets.$_playJsonSecret';
  if (auths.length > 1) v.add('more than one google-github-actions/auth step');
  if ((auths.isNotEmpty) == keyForm) {
    v.add(
      'exactly one credential form required: WIF auth step XOR '
      'serviceAccountJsonPlainText from secrets.$_playJsonSecret',
    );
  }
  if (wi.containsKey('serviceAccountJsonPlainText') && !keyForm) {
    v.add('serviceAccountJsonPlainText must be secrets.$_playJsonSecret');
  }
  if (auths.length == 1) {
    final WorkflowStep a = steps[auths.single];
    final Map<String, String> aw = a.mapping('with');
    if (auths.single > up) v.add('auth must run before the upload');
    if (_expr(aw['workload_identity_provider']) !=
        'vars.BEAUTICA_PLAY_WIF_PROVIDER') {
      v.add(
        'auth workload_identity_provider must be vars.BEAUTICA_PLAY_WIF_PROVIDER',
      );
    }
    if (_expr(aw['service_account']) != 'vars.BEAUTICA_PLAY_SA_EMAIL') {
      v.add('auth service_account must be vars.BEAUTICA_PLAY_SA_EMAIL');
    }
    if (aw.containsKey('credentials_json')) {
      v.add('auth must be keyless (no credentials_json)');
    }
    if (aw['create_credentials_file'] == 'false') {
      v.add('auth must create the credentials file');
    }
    if (aw['cleanup_credentials'] == 'false') {
      v.add('auth cleanup_credentials must not be false');
    }
    final String? id = a.field('id');
    if (id == null ||
        _expr(wi['serviceAccountJson']) !=
            'steps.$id.outputs.credentials_file_path') {
      v.add('serviceAccountJson must be the auth step credentials_file_path');
    }
  } else if (keyForm && wi.containsKey('serviceAccountJson')) {
    v.add('key form must not also set serviceAccountJson');
  }
  return v;
}

List<String> releaseNotesJobViolations(String text) {
  final Workflow w = Workflow(text);
  final List<String> v = <String>[];
  if (!w.jobs.containsKey(kNotesJob)) return <String>['no `$kNotesJob` job'];
  final String needs = (w.jobField(kNotesJob, 'needs') ?? '').replaceAll(
    RegExp(r'[\[\]\s]'),
    '',
  );
  if (needs != 'guard') v.add('$kNotesJob must have `needs: guard`');
  if (w.jobField(kNotesJob, 'environment') != null) {
    v.add('$kNotesJob must have NO environment (D10a: secret-free)');
  }
  for (final int i in _jobBody(w, kNotesJob)) {
    if (w.lines[i].contains('secrets.')) {
      v.add('$kNotesJob line ${i + 1} references a secret');
    }
    if (w.lines[i].contains('id-token')) {
      v.add('$kNotesJob line ${i + 1} grants id-token');
    }
  }
  final List<WorkflowStep> steps = w.steps(kNotesJob);
  final WorkflowStep? co = steps
      .where((WorkflowStep s) => _uses(s, 'actions/checkout'))
      .firstOrNull;
  if (co == null || co.mapping('with')['fetch-depth'] != '0') {
    v.add('$kNotesJob must check out with fetch-depth: 0 (previous-tag rule)');
  }
  final int check = steps.indexWhere(
    (WorkflowStep s) => RegExp(
      r'^\./scripts/check_release_notes\.sh "\$NOTES_MODE"$',
    ).hasMatch(s.field('run') ?? ''),
  );
  if (check < 0) {
    v.add(
      '$kNotesJob does not run ./scripts/check_release_notes.sh "\$NOTES_MODE"',
    );
  } else {
    final WorkflowStep s = steps[check];
    if (_expr(s.mapping('env')['NOTES_MODE']) !=
        "(github.event_name == 'workflow_dispatch' && inputs.dry_run) "
            "&& 'dispatch' || 'tag'") {
      v.add('NOTES_MODE must be dispatch on a dry run and tag otherwise');
    }
    if (s.has('if')) v.add('notes check must not be conditional');
    if (s.has('continue-on-error')) {
      v.add('notes check must not continue-on-error');
    }
  }
  final int up = steps.indexWhere(
    (WorkflowStep s) =>
        _uses(s, 'actions/upload-artifact') &&
        RegExp('$kNotesJob\$').hasMatch(_withName(s)),
  );
  if (up < 0) {
    v.add('$kNotesJob does not upload artifact `$kNotesJob`');
  } else {
    // Security LOW: only the checked file may reach Play's whatsNewDirectory.
    if (_withField(steps[up]).trim() != 'release-notes/whatsnew-uk') {
      v.add('release-notes artifact path must be release-notes/whatsnew-uk');
    }
    if (check >= 0 && up < check) v.add('notes uploaded before the check');
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
    test('permissions are contents: read (top level and per job); '
        'id-token: write only in play-upload', () {
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
    test('411: Sentry dart-defines, release string, symbol upload wired', () {
      expect(sentry411Violations(wf), isEmpty);
    });
    test('411 D4: Sentry Gradle plugin pinned, R8 mapping only, rest off', () {
      expect(
        sentryGradleViolations(
          _read('android/app/build.gradle.kts'),
          _read('android/settings.gradle.kts'),
        ),
        isEmpty,
      );
    });
    test('411 D3: sentry_dart_plugin pinned; pubspec uploads symbols only', () {
      expect(sentryPubspecViolations(_read('pubspec.yaml')), isEmpty);
    });
    test('411 A4: no Sentry token/DSN in pubspec, Gradle or config/env', () {
      final Map<String, String> files = <String, String>{
        for (final String f in <String>[
          'pubspec.yaml',
          'android/app/build.gradle.kts',
          'android/settings.gradle.kts',
          ...Directory(
            'config/env',
          ).listSync().whereType<File>().map((File f) => f.path),
        ])
          f: _read(f),
      };
      expect(files.keys, contains('config/env/prod.json'));
      expect(sentrySecretFileViolations(files), isEmpty);
    });
    test('release signing is enforced; no version overrides', () {
      expect(signingViolations(wf), isEmpty);
    });
    test('D13: google-services.json injected from a required env secret, '
        'jq-checked for com.beautica.app, between setup and build', () {
      expect(firebaseInjectViolations(wf), isEmpty);
    });
    test('D13: built AAB is checked for google_app_id after resolve, '
        'before verify', () {
      expect(firebaseAabCheckViolations(wf), isEmpty);
    });
    test('D13: google-services.json removed in a trailing always() step', () {
      expect(firebaseCleanupViolations(wf), isEmpty);
    });
    test('423: play-upload needs build + release-notes, tag push only, no '
        'checkout/keystore, sha256 + status checks before an internal '
        'upload, exactly one credential form', () {
      expect(playUploadViolations(wf), isEmpty);
    });
    test(
      '423: release-notes is secret-free, needs guard, runs '
      'check_release_notes.sh and uploads release-notes/whatsnew-uk only',
      () {
        expect(releaseNotesJobViolations(wf), isEmpty);
      },
    );
    test('423: the real file uses the keyless WIF form', () {
      expect(wf, contains('uses: google-github-actions/auth@'));
      expect(wf, isNot(contains('serviceAccountJsonPlainText')));
    });
    test('423: release-notes/whatsnew-uk exists (Play locale uk)', () {
      expect(File('release-notes/whatsnew-uk').existsSync(), isTrue);
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
          '        if: always()\n        run: rm -f "\$RUNNER_TEMP',
          '        run: rm -f "\$RUNNER_TEMP',
        ),
      );
    });
    test('keystore: cleanup runs only on success()', () {
      red(
        keystoreViolations,
        mutate(
          wf,
          '        if: always()\n        run: rm -f "\$RUNNER_TEMP',
          '        if: success()\n        run: rm -f "\$RUNNER_TEMP',
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
    test('411: DSN dart-define dropped from the build', () {
      red(
        sentry411Violations,
        mutate(
          wf,
          '            --dart-define=BEAUTICA_SENTRY_DSN="\$BEAUTICA_SENTRY_DSN" \\\n',
          '',
        ),
      );
    });
    test('411: build DSN switched to the staging secret', () {
      red(
        sentry411Violations,
        mutate(
          wf,
          '        env:\n          BEAUTICA_SENTRY_DSN: \${{ secrets.BEAUTICA_SENTRY_DSN_PROD }}\n          SENTRY_AUTH_TOKEN: \${{ secrets.SENTRY_AUTH_TOKEN }}\n          BEAUTICA_KEYSTORE_PATH',
          '        env:\n          BEAUTICA_SENTRY_DSN: \${{ secrets.BEAUTICA_SENTRY_DSN_STAGING }}\n          SENTRY_AUTH_TOKEN: \${{ secrets.SENTRY_AUTH_TOKEN }}\n          BEAUTICA_KEYSTORE_PATH',
        ),
      );
    });
    test('411: token dropped from the build step (no R8 upload)', () {
      red(
        sentry411Violations,
        mutate(
          wf,
          '          SENTRY_AUTH_TOKEN: \${{ secrets.SENTRY_AUTH_TOKEN }}\n          BEAUTICA_KEYSTORE_PATH',
          '          BEAUTICA_KEYSTORE_PATH',
        ),
      );
    });
    test('411: SENTRY_ORG removed from the job env', () {
      red(sentry411Violations, mutate(wf, '      SENTRY_ORG: beautica\n', ''));
    });
    test('411: sentry_dart_plugin made non-blocking', () {
      red(
        sentry411Violations,
        mutate(
          wf,
          '      - name: Upload Dart symbols to Sentry\n',
          '      - name: Upload Dart symbols to Sentry\n        continue-on-error: true\n',
        ),
      );
    });
    test('411: sentry_dart_plugin step removed', () {
      red(
        sentry411Violations,
        mutate(wf, 'dart run sentry_dart_plugin 2>&1', 'true 2>&1'),
      );
    });
    test('411: failed=0 summary check removed', () {
      red(sentry411Violations, wf.replaceAll('failed=0', 'failed=[0-9]+'));
    });
    test('411: sentry-release preflight removed', () {
      final String noPre = mutate(
        wf,
        './scripts/check_release_version.sh sentry-release',
        'true',
      );
      red(sentry411Violations, noPre);
    });
    test('411: literal DSN pasted into the workflow', () {
      red(
        sentry411Violations,
        mutate(
          wf,
          '      SENTRY_PROJECT: beautica-mobile\n',
          '      SENTRY_PROJECT: beautica-mobile\n      DSN: https://0123456789abcdef0123@o1.ingest.de.sentry.io/2\n',
        ),
      );
    });
    test('411 A4: DSN echoed in the preflight', () {
      red(
        sentry411Violations,
        mutate(
          wf,
          '          ./scripts/check_release_version.sh sentry-release >',
          '          echo "dsn=\$BEAUTICA_SENTRY_DSN"\n'
              '          ./scripts/check_release_version.sh sentry-release >',
        ),
      );
    });
    test('411 A4: set -x added to the symbol upload step', () {
      red(
        sentry411Violations,
        mutate(
          wf,
          '          set -o pipefail\n',
          '          set -xo pipefail\n',
        ),
      );
    });
    final String gradle = _read('android/app/build.gradle.kts');
    final String settings = _read('android/settings.gradle.kts');
    void redGradle(String app, [String? s]) =>
        expect(sentryGradleViolations(app, s ?? settings), isNotEmpty);
    test('411 D4: Gradle telemetry switched on', () {
      redGradle(mutate(gradle, 'telemetry.set(false)', 'telemetry.set(true)'));
    });
    test('411 D4: Gradle mapping upload no longer gated on the token', () {
      redGradle(
        mutate(
          gradle,
          'autoUploadProguardMapping.set(!System.getenv("SENTRY_AUTH_TOKEN").isNullOrBlank())',
          'autoUploadProguardMapping.set(true)',
        ),
      );
    });
    test('411 D4: Gradle runtimeOptimizations block enabled', () {
      final String rt = gradle.substring(
        gradle.indexOf('runtimeOptimizations {'),
      );
      redGradle(
        gradle.replaceFirst(
          rt,
          rt.replaceFirst('enabled.set(false)', 'enabled.set(true)'),
        ),
      );
    });
    test('411 D4: Gradle source context re-enabled by a later override', () {
      redGradle(
        mutate(
          gradle,
          '    telemetry.set(false)\n',
          '    telemetry.set(false)\n    includeSourceContext.set(true)\n',
        ),
      );
    });
    test('411 D4: Gradle authToken hard-coded', () {
      redGradle(
        mutate(
          gradle,
          '    telemetry.set(false)\n',
          '    telemetry.set(false)\n    authToken.set(System.getenv("X"))\n',
        ),
      );
    });
    test('411 D4: Gradle plugin version made dynamic', () {
      redGradle(gradle, mutate(settings, 'version "6.23.0"', 'version "6.+"'));
    });
    test('411 D4: Gradle plugin no longer applied to :app', () {
      redGradle(
        mutate(
          gradle,
          '    id("io.sentry.android.gradle")\n',
          '    // id("io.sentry.android.gradle")\n',
        ),
      );
    });
    final String pub = _read('pubspec.yaml');
    void redPub(String p) => expect(sentryPubspecViolations(p), isNotEmpty);
    test('411 D3: pubspec uploads sources', () {
      redPub(mutate(pub, '  upload_sources: false', '  upload_sources: true'));
    });
    test('411 D3: pubspec pins a release (diverges from the app)', () {
      redPub(
        mutate(pub, '  commits: false\n', '  commits: false\n  release: x\n'),
      );
    });
    test('411 D3: pubspec symbols path drifts from --split-debug-info', () {
      redPub(
        mutate(
          pub,
          '  symbols_path: build/symbols',
          '  symbols_path: build/sym',
        ),
      );
    });
    test('411 D3: sentry_dart_plugin caret-pinned', () {
      redPub(
        mutate(
          pub,
          '  sentry_dart_plugin: 3.4.0',
          '  sentry_dart_plugin: ^3.4.0',
        ),
      );
    });
    test('411 A4: token / auth_token / Sentry key in config/env flagged', () {
      expect(
        sentrySecretFileViolations(<String, String>{
          'pubspec.yaml': 'sentry:\n  auth_token: x\n',
        }),
        isNotEmpty,
      );
      expect(
        sentrySecretFileViolations(<String, String>{
          'android/app/build.gradle.kts': 'authToken.set("sntrys_abc")',
        }),
        isNotEmpty,
      );
      expect(
        sentrySecretFileViolations(<String, String>{
          'config/env/prod.json': '{"BEAUTICA_SENTRY_DSN": ""}',
        }),
        isNotEmpty,
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
    // --- D13 Firebase config ---------------------------------------------
    const String gsEnv =
        '          GOOGLE_SERVICES_JSON_BASE64: '
        r'${{ secrets.BEAUTICA_GOOGLE_SERVICES_JSON_BASE64 }}'
        '\n';
    const String gsRequired =
        '          if [ -z "\$GOOGLE_SERVICES_JSON_BASE64" ]; then\n'
        '            echo "::error::secret BEAUTICA_GOOGLE_SERVICES_JSON_BASE64 '
        'is not set in environment ci-trusted-secrets"\n'
        '            exit 1\n'
        '          fi\n';
    String injectStep() {
      final int a = wf.indexOf(
        '      # D13: Firebase config for the prod AAB.',
      );
      final int b = wf.indexOf('      - name: Decode upload keystore');
      expect(a, greaterThanOrEqualTo(0));
      expect(b, greaterThan(a));
      return wf.substring(a, b);
    }

    test('firebase: secret interpolated directly into run:', () {
      final String m = mutate(
        mutate(wf, gsEnv, ''),
        r'''printf '%s' "$GOOGLE_SERVICES_JSON_BASE64"''',
        r'''printf '%s' "${{ secrets.BEAUTICA_GOOGLE_SERVICES_JSON_BASE64 }}"''',
      );
      red(firebaseInjectViolations, m);
      red(injectionViolations, m);
    });
    test('firebase: secret also referenced in a second env', () {
      red(
        firebaseInjectViolations,
        mutate(
          wf,
          "          BEAUTICA_REQUIRE_RELEASE_SIGNING: '1'\n",
          "          BEAUTICA_REQUIRE_RELEASE_SIGNING: '1'\n$gsEnv",
        ),
      );
    });
    test('firebase: required-secret check removed', () {
      red(firebaseInjectViolations, mutate(wf, gsRequired, ''));
    });
    test('firebase: missing secret only warns (no exit 1)', () {
      red(
        firebaseInjectViolations,
        mutate(
          wf,
          gsRequired,
          gsRequired.replaceFirst('            exit 1\n', ''),
        ),
      );
    });
    test('firebase: inject step made conditional on non-dry runs', () {
      red(
        firebaseInjectViolations,
        mutate(
          wf,
          '      - name: Inject google-services.json (Firebase push)\n',
          '      - name: Inject google-services.json (Firebase push)\n'
              "        if: env.DRY_RUN != 'true'\n",
        ),
      );
    });
    test('firebase: umask 077 removed from the inject step', () {
      red(
        firebaseInjectViolations,
        mutate(
          wf,
          '          umask 077\n          gs=android/app/google-services.json\n',
          '          gs=android/app/google-services.json\n',
        ),
      );
    });
    test('firebase: decoded into the wrong path', () {
      red(
        firebaseInjectViolations,
        mutate(
          wf,
          'gs=android/app/google-services.json',
          'gs=google-services.json',
        ),
      );
    });
    test('firebase: malformed-JSON check removed', () {
      red(
        firebaseInjectViolations,
        mutate(
          wf,
          'if ! jq -e . "\$gs" > /dev/null 2>&1; then',
          'if false; then',
        ),
      );
    });
    test('firebase: package check removed', () {
      red(
        firebaseInjectViolations,
        mutate(
          wf,
          "'any(.client[]?; .client_info.android_client_info.package_name == \$pkg)'",
          "'.client'",
        ),
      );
    });
    test('firebase: package check loosened to a prefix match', () {
      red(
        firebaseInjectViolations,
        mutate(
          wf,
          '.package_name == \$pkg)',
          '.package_name | startswith(\$pkg))',
        ),
      );
    });
    test('firebase: package check targets the staging id', () {
      red(
        firebaseInjectViolations,
        mutate(
          wf,
          'jq -e --arg pkg com.beautica.app \\',
          'jq -e --arg pkg com.beautica.app.staging \\',
        ),
      );
    });
    test('firebase: json content printed', () {
      red(
        firebaseInjectViolations,
        mutate(
          wf,
          '          echo "google-services.json injected',
          '          cat "\$gs"\n          echo "google-services.json injected',
        ),
      );
    });
    test('firebase: inject moved after the appbundle build', () {
      final String step = injectStep();
      final String without = mutate(wf, step, '');
      red(
        firebaseInjectViolations,
        mutate(
          without,
          '      # A dry-run AAB is renamed',
          '$step      # A dry-run AAB is renamed',
        ),
      );
    });
    test('firebase: inject moved before Flutter setup', () {
      final String step = injectStep();
      final String without = mutate(wf, step, '');
      red(
        firebaseInjectViolations,
        mutate(
          without,
          '      - name: Set up Flutter, pub get, codegen\n',
          '$step      - name: Set up Flutter, pub get, codegen\n',
        ),
      );
    });
    test('firebase: AAB google_app_id check removed', () {
      red(
        firebaseAabCheckViolations,
        mutate(
          wf,
          'grep -aq google_app_id "\$res"',
          'grep -aq anything "\$res"',
        ),
      );
    });
    test('firebase: AAB check failure does not exit 1', () {
      red(
        firebaseAabCheckViolations,
        mutate(
          wf,
          '(google-services plugin skipped)"\n            exit 1\n',
          '(google-services plugin skipped)"\n',
        ),
      );
    });
    test('firebase: AAB check made non-blocking', () {
      red(
        firebaseAabCheckViolations,
        mutate(
          wf,
          '      - name: Verify AAB carries Firebase config\n',
          '      - name: Verify AAB carries Firebase config\n'
              '        continue-on-error: true\n',
        ),
      );
    });
    test('firebase: AAB check reads a hard-coded path, not steps.aab', () {
      red(
        firebaseAabCheckViolations,
        mutate(
          wf,
          '          AAB_PATH: \${{ steps.aab.outputs.path }}\n        run: |\n'
              '          res=',
          '          AAB_PATH: build/app.aab\n        run: |\n          res=',
        ),
      );
    });
    test('firebase: AAB check inspects the wrong module', () {
      red(
        firebaseAabCheckViolations,
        mutate(
          wf,
          'unzip -p "\$AAB_PATH" base/resources.pb',
          'unzip -p "\$AAB_PATH" feature/resources.pb',
        ),
      );
    });
    test('firebase: AAB check moved after verify_release_aab.sh', () {
      red(
        firebaseAabCheckViolations,
        mutate(
          wf,
          '      - name: Verify AAB carries Firebase config\n',
          '      - name: Early verify\n'
              r'        run: ./scripts/verify_release_aab.sh "$AAB_PATH"'
              '\n\n      - name: Verify AAB carries Firebase config\n',
        ),
      );
    });
    test('firebase: AAB check moved before Resolve AAB path', () {
      red(firebaseAabCheckViolations, mutate(wf, '        id: aab\n', ''));
    });
    test('firebase: json cleanup loses if: always()', () {
      red(
        firebaseCleanupViolations,
        mutate(
          wf,
          '        if: always()\n        run: rm -rf android/app/google-services.json build/app/generated/res/process*GoogleServices',
          '        run: rm -rf android/app/google-services.json build/app/generated/res/process*GoogleServices',
        ),
      );
    });
    test('firebase: json cleanup removed', () {
      red(
        firebaseCleanupViolations,
        mutate(
          wf,
          '      - name: Remove google-services.json\n'
              '        if: always()\n'
              '        run: rm -rf android/app/google-services.json build/app/generated/res/process*GoogleServices\n\n',
          '',
        ),
      );
    });
    test('firebase: json cleanup moved before the uploads', () {
      const String cleanup =
          '      - name: Remove google-services.json\n'
          '        if: always()\n'
          '        run: rm -rf android/app/google-services.json build/app/generated/res/process*GoogleServices\n\n';
      red(
        firebaseCleanupViolations,
        mutate(
          mutate(wf, cleanup, ''),
          '      - name: Upload AAB\n',
          '$cleanup      - name: Upload AAB\n',
        ),
      );
    });
    test('artifact: google-services.json added to the symbols list', () {
      red(
        artifactPathViolations,
        mutate(
          wf,
          '            build/symbols/\n',
          '            build/symbols/\n            android/app/google-services.json\n',
        ),
      );
    });
    test('firebase: generated GoogleServices values cleanup removed', () {
      red(
        firebaseCleanupViolations,
        mutate(
          wf,
          'run: rm -rf android/app/google-services.json '
              'build/app/generated/res/process*GoogleServices',
          'run: rm -rf android/app/google-services.json',
        ),
      );
    });
    test('artifact: build/app/ added to the symbols list', () {
      red(
        artifactPathViolations,
        mutate(
          wf,
          '            build/symbols/\n',
          '            build/symbols/\n            build/app/\n',
        ),
      );
    });
    test('artifact: generated GoogleServices values dir uploaded', () {
      red(
        artifactPathViolations,
        mutate(
          wf,
          '            build/symbols/\n',
          '            build/symbols/\n'
              '            build/app/generated/res/processProdReleaseGoogleServices/\n',
        ),
      );
    });
    test('artifact: android/ tree uploaded', () {
      red(
        artifactPathViolations,
        mutate(wf, 'path: build/release-manifest.xml', 'path: android/app/'),
      );
    });
    // --- 423 Play upload + release notes ----------------------------------
    const String playIf =
        "    if: github.event_name == 'push' && github.ref_type == 'tag' && "
        "startsWith(github.ref, 'refs/tags/mobile-v')\n";
    String stepText(String text, String name) {
      final int a = text.indexOf('      - name: $name\n');
      expect(a, greaterThanOrEqualTo(0), reason: 'step missing: $name');
      final int b = text.indexOf('\n\n', a);
      return text.substring(a, b < 0 ? text.length : b + 2);
    }

    const String shaStep = 'Verify AAB sha256 and mapping';
    const String statusStep = 'Validate release status';
    const String authStep =
        'Authenticate to Google Cloud (Workload Identity Federation)';
    const String uploadStep = 'Upload to Play Internal testing';
    const String authWith = '          create_credentials_file: true\n';
    const String saJsonLine =
        r'          serviceAccountJson: ${{ steps.gcp-auth.outputs.credentials_file_path }}'
        '\n';
    const String keyLine =
        r'          serviceAccountJsonPlainText: ${{ secrets.BEAUTICA_PLAY_SERVICE_ACCOUNT_JSON }}'
        '\n';
    String keyForm() =>
        mutate(mutate(wf, stepText(wf, authStep), ''), saJsonLine, keyLine);

    test(
      'play: key fallback form (no auth step) is also accepted (D2/D11)',
      () {
        expect(playUploadViolations(keyForm()), isEmpty);
      },
    );
    test('play: if removed', () {
      red(playUploadViolations, mutate(wf, playIf, ''));
    });
    test('play: if mutated to always()', () {
      red(playUploadViolations, mutate(wf, playIf, '    if: always()\n'));
    });
    test('play: event_name == push clause dropped', () {
      red(
        playUploadViolations,
        mutate(wf, "if: github.event_name == 'push' && ", 'if: '),
      );
    });
    test('play: workflow_dispatch OR-ed into the if', () {
      red(
        playUploadViolations,
        mutate(
          wf,
          "if: github.event_name == 'push' && ",
          "if: github.event_name == 'workflow_dispatch' || "
              "github.event_name == 'push' && ",
        ),
      );
    });
    test('permissions: id-token: write added to build', () {
      red(
        permissionViolations,
        mutate(
          wf,
          '    permissions:\n      contents: read\n    # 423 D5',
          '    permissions:\n      contents: read\n      id-token: write\n'
              '    # 423 D5',
        ),
      );
    });
    test('permissions: id-token: write added to guard', () {
      red(
        permissionViolations,
        mutate(
          wf,
          '    timeout-minutes: 5\n    permissions:\n      contents: read\n',
          '    timeout-minutes: 5\n    permissions:\n      contents: read\n'
              '      id-token: write\n',
        ),
      );
    });
    test('permissions: id-token: write dropped from play-upload', () {
      red(
        permissionViolations,
        mutate(
          wf,
          '      contents: read\n      id-token: write\n',
          '      contents: read\n',
        ),
      );
    });
    test('play: keystore secret referenced in play-upload', () {
      red(
        playUploadViolations,
        mutate(
          wf,
          '          PLAY_DIR: \${{ runner.temp }}/play\n',
          '          PLAY_DIR: \${{ runner.temp }}/play\n'
              '          K: \${{ secrets.BEAUTICA_KEYSTORE_BASE64 }}\n',
        ),
      );
    });
    test('play: actions/checkout added to play-upload', () {
      red(
        playUploadViolations,
        mutate(
          wf,
          '      - name: Download AAB\n',
          '      - name: Checkout\n'
              '        uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4\n\n'
              '      - name: Download AAB\n',
        ),
      );
    });
    test('pin: r0adkll on @v1', () {
      red(
        pinViolations,
        mutate(
          wf,
          'r0adkll/upload-google-play@e738b9dd8f2476ea806d921b64aacd24f34515a5',
          'r0adkll/upload-google-play@v1',
        ),
      );
    });
    test('pin: auth on @v3', () {
      red(
        pinViolations,
        mutate(
          wf,
          'google-github-actions/auth@7c6bc770dae815cd3e89ee6cdf493a5fab2cc093',
          'google-github-actions/auth@v3',
        ),
      );
    });
    test('play: tracks: production', () {
      red(
        playUploadViolations,
        mutate(wf, 'tracks: internal', 'tracks: production'),
      );
    });
    test('play: tracks: alpha', () {
      red(
        playUploadViolations,
        mutate(wf, 'tracks: internal', 'tracks: alpha'),
      );
    });
    test('play: status: completed hardcoded', () {
      red(
        playUploadViolations,
        mutate(
          wf,
          '          status: \${{ vars.BEAUTICA_PLAY_RELEASE_STATUS }}\n',
          '          status: completed\n',
        ),
      );
    });
    test('play: status-validation step removed', () {
      red(playUploadViolations, mutate(wf, stepText(wf, statusStep), ''));
    });
    test('play: status validation lets inProgress through', () {
      red(
        playUploadViolations,
        mutate(wf, 'draft | completed)', 'draft | completed | inProgress)'),
      );
    });
    test('play: whatsNewDirectory removed', () {
      red(
        playUploadViolations,
        mutate(
          wf,
          '          whatsNewDirectory: \${{ runner.temp }}/play/release-notes\n',
          '',
        ),
      );
    });
    test('play: mappingFile removed', () {
      red(
        playUploadViolations,
        mutate(
          wf,
          '          mappingFile: \${{ steps.aab.outputs.mapping }}\n',
          '',
        ),
      );
    });
    test('play: debugSymbols added', () {
      red(
        playUploadViolations,
        mutate(
          wf,
          '          tracks: internal\n',
          '          tracks: internal\n          debugSymbols: x.zip\n',
        ),
      );
    });
    test('play: sha256 step removed', () {
      red(playUploadViolations, mutate(wf, stepText(wf, shaStep), ''));
    });
    test('play: sha256 step made continue-on-error', () {
      red(
        playUploadViolations,
        mutate(
          wf,
          '      - name: $shaStep\n',
          '      - name: $shaStep\n        continue-on-error: true\n',
        ),
      );
    });
    test('play: sha256 mismatch no longer exits 1', () {
      red(
        playUploadViolations,
        mutate(
          wf,
          '!= verified build \$EXPECTED_SHA256"\n            exit 1\n',
          '!= verified build \$EXPECTED_SHA256"\n',
        ),
      );
    });
    test('play: sha256 step moved after the upload', () {
      final String step = stepText(wf, shaStep);
      red(playUploadViolations, '${mutate(wf, step, '')}\n$step');
    });
    test('play: build no longer exposes aab_sha256', () {
      red(
        playUploadViolations,
        mutate(wf, '      aab_sha256: \${{ steps.aab.outputs.sha256 }}\n', ''),
      );
    });
    test('play: build step aab stops hashing the AAB', () {
      red(
        playUploadViolations,
        mutate(
          wf,
          '          echo "sha256=\$(sha256sum "\$aab" | cut -d \' \' -f 1)" >> "\$GITHUB_OUTPUT"\n',
          '',
        ),
      );
    });
    test('play: releaseFiles bypasses the checked AAB', () {
      red(
        playUploadViolations,
        mutate(
          wf,
          'releaseFiles: \${{ steps.aab.outputs.path }}',
          'releaseFiles: \${{ runner.temp }}/play/aab/*.aab',
        ),
      );
    });
    test('play: continue-on-error: true on the upload', () {
      red(
        playUploadViolations,
        mutate(
          wf,
          '      - name: $uploadStep\n',
          '      - name: $uploadStep\n        continue-on-error: true\n',
        ),
      );
    });
    test('play: needs: build dropped', () {
      red(
        playUploadViolations,
        mutate(wf, 'needs: [build, release-notes]', 'needs: [release-notes]'),
      );
    });
    test('play: release-notes artifact not downloaded', () {
      red(
        playUploadViolations,
        mutate(wf, stepText(wf, 'Download release notes'), ''),
      );
    });
    test('play: environment dropped from play-upload', () {
      red(
        jobTopologyViolations,
        mutate(
          wf,
          '    runs-on: ubuntu-24.04\n    environment: ci-trusted-secrets\n'
              '    timeout-minutes: 20\n',
          '    runs-on: ubuntu-24.04\n    timeout-minutes: 20\n',
        ),
      );
    });
    test('notes: environment added to release-notes', () {
      final String m = mutate(
        wf,
        '    timeout-minutes: 10\n',
        '    timeout-minutes: 10\n    environment: ci-trusted-secrets\n',
      );
      red(releaseNotesJobViolations, m);
      red(jobTopologyViolations, m);
    });
    test('notes: secret referenced in release-notes', () {
      red(
        releaseNotesJobViolations,
        mutate(
          wf,
          "          NOTES_MODE: \${{ (github.event_name == 'workflow_dispatch' && inputs.dry_run) && 'dispatch' || 'tag' }}\n",
          "          NOTES_MODE: \${{ (github.event_name == 'workflow_dispatch' && inputs.dry_run) && 'dispatch' || 'tag' }}\n"
              '          T: \${{ secrets.GITHUB_TOKEN }}\n',
        ),
      );
    });
    test('notes: dry-run mode no longer dispatch (stale notes would fail)', () {
      red(
        releaseNotesJobViolations,
        mutate(wf, "&& 'dispatch' || 'tag'", "&& 'tag' || 'tag'"),
      );
    });
    test('notes: shallow checkout (previous tag unreachable)', () {
      red(
        releaseNotesJobViolations,
        mutate(
          wf,
          '      - name: Checkout (full history + tags for the previous-tag rule)\n'
              '        uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4\n'
              '        with:\n          fetch-depth: 0\n',
          '      - name: Checkout (full history + tags for the previous-tag rule)\n'
              '        uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4\n'
              '        with:\n          fetch-depth: 1\n',
        ),
      );
    });
    test('notes: check made non-blocking', () {
      red(
        releaseNotesJobViolations,
        mutate(
          wf,
          '      - name: Check release notes\n',
          '      - name: Check release notes\n        continue-on-error: true\n',
        ),
      );
    });
    test('notes: artifact path widened back to the release-notes/ dir', () {
      red(
        releaseNotesJobViolations,
        mutate(
          wf,
          'path: release-notes/whatsnew-uk\n',
          'path: release-notes/\n',
        ),
      );
    });
    test('notes: artifact path widened to a glob', () {
      red(
        releaseNotesJobViolations,
        mutate(
          wf,
          'path: release-notes/whatsnew-uk\n',
          'path: release-notes/whatsnew-*\n',
        ),
      );
    });
    test('notes: artifact not uploaded', () {
      red(
        releaseNotesJobViolations,
        mutate(wf, stepText(wf, 'Upload release notes'), ''),
      );
    });
    test('play: cleanup_credentials: false', () {
      red(
        playUploadViolations,
        mutate(wf, authWith, '$authWith          cleanup_credentials: false\n'),
      );
    });
    test('play: both credential forms present', () {
      red(playUploadViolations, mutate(wf, saJsonLine, '$saJsonLine$keyLine'));
    });
    test('play: neither credential form present', () {
      red(playUploadViolations, mutate(wf, stepText(wf, authStep), ''));
    });
    test('play: auth switched to a JSON key', () {
      red(
        playUploadViolations,
        mutate(
          wf,
          authWith,
          '$authWith          credentials_json: \${{ secrets.BEAUTICA_PLAY_SERVICE_ACCOUNT_JSON }}\n',
        ),
      );
    });
    test('play: JSON secret interpolated inside a run:', () {
      final String m = mutate(
        keyForm(),
        '              echo "Play release status: \$RELEASE_STATUS" ;;\n',
        '              echo "Play release status: \$RELEASE_STATUS" ;;\n'
            '              echo "\${{ secrets.BEAUTICA_PLAY_SERVICE_ACCOUNT_JSON }}" > k.json ;;\n',
      );
      red(playUploadViolations, m);
      red(injectionViolations, m);
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

  // 411: the two Sentry shell steps EXECUTED (bash -e, like the runner), so the
  // fail-fast and `failed=0` logic is pinned by behaviour, not by substrings.
  group('411 Sentry steps behave (executed)', () {
    String stepRun(String name) => Workflow(wf)
        .steps('build')
        .firstWhere((WorkflowStep s) => s.field('name') == name)
        .field('run')!;
    late String up;
    late String pre;
    setUpAll(() {
      up = stepRun('Upload Dart symbols to Sentry');
      pre = stepRun('Check Sentry secrets + compute release');
    });

    const String dsn = 'https://feedc0de411secret@o1.ingest.de.sentry.io/2';
    const String token = 'sntrys_PREFLIGHT_TOKEN_411';
    ({int code, String out, String genv}) runPre(
      String script,
      String d,
      String t,
    ) {
      final Directory tmp = Directory.systemTemp.createTempSync('pre411_');
      try {
        final File genv = File('${tmp.path}/github_env')..createSync();
        final ({int code, String out}) r = runStep(
          script,
          tmp,
          <String, String>{
            'BEAUTICA_SENTRY_DSN': d,
            'SENTRY_AUTH_TOKEN': t,
            'GITHUB_ENV': genv.path,
          },
        );
        return (code: r.code, out: r.out, genv: genv.readAsStringSync());
      } finally {
        tmp.deleteSync(recursive: true);
      }
    }

    group('Upload Dart symbols to Sentry', () {
      test('complete upload (coloured plugin output) passes', () {
        final ({int code, String out}) r = runUploadStep(
          up,
          sdpSummary(1, 1, 0),
          0,
        );
        expect(r.code, 0, reason: r.out);
        expect(r.out, isNot(contains('sntrys_FAKE_TOKEN_411')));
      });
      test('plugin exits 0 but summary says failed=1 -> step fails', () {
        final String log = sdpFailedLine() + sdpSummary(1, 0, 1);
        expect(runUploadStep(up, log, 0).code, isNot(0));
      });
      test('failed=1 summary alone (no error line) -> step fails', () {
        expect(runUploadStep(up, sdpSummary(1, 0, 1), 0).code, isNot(0));
      });
      test('swallowed failure line with a clean summary -> step fails', () {
        final String log = sdpFailedLine() + sdpSummary(1, 1, 0);
        expect(runUploadStep(up, log, 0).code, isNot(0));
      });
      test('no summary at all (map step skipped) -> step fails', () {
        expect(runUploadStep(up, '\nnothing to upload\n', 0).code, isNot(0));
      });
      test('attempted=0 -> step fails', () {
        expect(runUploadStep(up, sdpSummary(0, 0, 0), 0).code, isNot(0));
      });
      test('attempted != succeeded with failed=0 -> step fails', () {
        expect(runUploadStep(up, sdpSummary(2, 1, 0), 0).code, isNot(0));
      });
      test('plugin exits non-zero (sentry-cli error) -> step fails', () {
        expect(runUploadStep(up, sdpSummary(1, 1, 0), 1).code, isNot(0));
      });
    });

    group('Check Sentry secrets + compute release', () {
      test('both set -> release + dist in GITHUB_ENV; secrets never printed; '
          'dist equals what crash_reporting.dart derives', () {
        final ({int code, String out, String genv}) r = runPre(pre, dsn, token);
        expect(r.code, 0, reason: r.out);
        final String ver = RegExp(
          r'^version:\s*(\S+)',
          multiLine: true,
        ).firstMatch(_read('pubspec.yaml'))!.group(1)!;
        final String build = ver.split('+').last;
        expect(
          r.genv,
          'SENTRY_RELEASE=beautica-mobile@$ver\nSENTRY_DIST=$build\n',
        );
        expect(r.out, isNot(contains('feedc0de411secret')));
        expect(r.out, isNot(contains(token)));
        final CrashReportingConfig app = CrashReportingConfig(
          dsn: '',
          env: 'prod',
          release: 'beautica-mobile@$ver',
        );
        expect(app.dist, build);
      });
      test('missing DSN -> fails before anything reaches GITHUB_ENV', () {
        final ({int code, String out, String genv}) r = runPre(pre, '', token);
        expect(r.code, isNot(0));
        expect(r.out, contains('::error::secret BEAUTICA_SENTRY_DSN_PROD'));
        expect(r.genv, isEmpty);
      });
      test('non-https DSN -> fails without printing it', () {
        final ({int code, String out, String genv}) r = runPre(
          pre,
          'http://leakme411@host/1',
          token,
        );
        expect(r.code, isNot(0));
        expect(r.out, isNot(contains('leakme411')));
        expect(r.genv, isEmpty);
      });
      test('missing SENTRY_AUTH_TOKEN -> fails', () {
        final ({int code, String out, String genv}) r = runPre(pre, dsn, '');
        expect(r.code, isNot(0));
        expect(r.out, contains('::error::secret SENTRY_AUTH_TOKEN'));
        expect(r.genv, isEmpty);
      });
    });

    // Each executed case must be load-bearing: weaken the real step and the
    // matching bad input now PASSES, so the case above would go red.
    group('executed cases fail on weakened steps', () {
      test('no failed-line grep: swallowed failure gets through', () {
        final int a = up.indexOf("if grep -qE '^(Dart symbol map upload");
        final int b = up.indexOf('fi\n', a) + 3;
        expect(a, greaterThan(0));
        final String weak = up.replaceRange(a, b, '');
        final String log = sdpFailedLine() + sdpSummary(1, 1, 0);
        expect(runUploadStep(weak, log, 0).code, 0);
      });
      test('no failed=0 anchor: failed=1 summary gets through', () {
        final String weak = mutate(up, r"failed=0$'", r"failed=[0-9]+$'");
        expect(runUploadStep(weak, sdpSummary(1, 1, 1), 0).code, 0);
      });
      test('no pipefail: a non-zero plugin exit gets through', () {
        final String weak = mutate(up, 'set -o pipefail\n', '');
        expect(runUploadStep(weak, sdpSummary(1, 1, 0), 1).code, 0);
      });
      test('no attempted>=1 check: attempted=0 gets through', () {
        final String weak = mutate(
          up,
          ' || [ "\${BASH_REMATCH[1]}" -lt 1 ]',
          '',
        );
        expect(runUploadStep(weak, sdpSummary(0, 0, 0), 0).code, 0);
      });
      test('no attempted==succeeded check: 2/1/0 gets through', () {
        final int a = up.indexOf('|| [ "\${BASH_REMATCH[1]}" != ');
        expect(a, greaterThan(0));
        final String weak = up.replaceRange(a, up.indexOf('; then', a), '');
        expect(runUploadStep(weak, sdpSummary(2, 1, 0), 0).code, 0);
      });
      test('no ANSI stripping: a coloured failure line gets through', () {
        final String weak = mutate(
          up,
          "sed -E 's/\\x1b\\[[0-9;]*m//g' \"\$log\"",
          'cat "\$log"',
        );
        final String log = sdpFailedLine() + sdpSummary(1, 1, 0);
        expect(runUploadStep(weak, log, 0).code, 0);
      });
      test('no token exit: an empty SENTRY_AUTH_TOKEN gets through', () {
        final String weak = mutate(
          pre,
          'SENTRY_AUTH_TOKEN is not set in environment ci-trusted-secrets"\nexit 1',
          'SENTRY_AUTH_TOKEN is not set in environment ci-trusted-secrets"',
        );
        expect(runPre(weak, dsn, '').code, 0);
      });
      test('DSN echoed: the no-print assertion catches it', () {
        final String weak = mutate(
          pre,
          'case "\$BEAUTICA_SENTRY_DSN" in',
          'echo "\$BEAUTICA_SENTRY_DSN"\ncase "\$BEAUTICA_SENTRY_DSN" in',
        );
        expect(runPre(weak, dsn, token).out, contains('feedc0de411secret'));
      });
    });
  });
}
