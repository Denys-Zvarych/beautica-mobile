import 'rules.dart';
import 'selection.dart';

/// `unit selection X/Y > P% -> full` (selection.dart, step 8).
final _threshold = RegExp(r'^unit selection (\d+)/(\d+) > (\d+)% -> full$');

/// Why [s] is FULL, as one replay-table cell (398 R2); `''` when not full.
///
/// * `full_glob <glob>[, <glob>…]`: a changed path hit `full_globs` /
///   `full_before_none` (the workflow's `is_forced` side of the decision);
/// * `>P% (S%)`: the unit selection exceeded `full_threshold`, S = its share;
/// * `fail-safe <rule> <path>`: anything else that forced FULL (unknown path,
///   non-.dart file under a graph root, unresolvable golden PNG / ARB delta).
String fullReason(Selection s, Rules rules) {
  if (s.mode != Mode.full) return '';
  final globSources = {
    for (final g in [...rules.fullBeforeNone, ...rules.full]) g.source,
  };
  final globs = <String>[];
  final failSafes = <String>[];
  String? threshold;
  for (final r in s.reasons) {
    final m = _threshold.firstMatch(r.rule);
    if (m != null) {
      final share = int.parse(m[1]!) / int.parse(m[2]!) * 100;
      threshold = '>${m[3]}% (${share.toStringAsFixed(1)}%)';
      continue;
    }
    if (!r.rule.startsWith('full: ')) continue;
    final what = r.rule.substring('full: '.length);
    if (globSources.contains(what)) {
      if (!globs.contains(what)) globs.add(what);
    } else {
      failSafes.add('fail-safe $what ${r.path}');
    }
  }
  return [
    if (globs.isNotEmpty) 'full_glob ${globs.join(', ')}',
    if (threshold != null) threshold,
    ...failSafes,
  ].join('; ');
}

/// Replay table header; [replayRow] emits exactly one cell per column.
const replayHeader =
    '| commit | files | mode | unit | golden | tz | flows | full reason | subject |\n'
    '|---|---|---|---|---|---|---|---|---|';

/// One replay-table row for [commit].
String replayRow({
  required String commit,
  required int files,
  required Selection s,
  required int totalUnit,
  required Rules rules,
  required String subject,
}) {
  final unit = s.mode == Mode.full ? 'FULL' : '${s.unit.length}/$totalUnit';
  final subj = subject.length > 60 ? subject.substring(0, 60) : subject;
  String cell(String v) => v.replaceAll('|', r'\|');
  return '| ${commit.length > 8 ? commit.substring(0, 8) : commit} | $files '
      '| ${s.mode.name} | $unit | ${s.golden.length} | ${s.tzSweep.length} '
      '| ${s.integration.length} | ${cell(fullReason(s, rules))} | ${cell(subj)} |';
}
