#!/usr/bin/env bash
# Scoped-services `dependencies:` cascade gate (phase 317, D2 option (a)).
#
# THE BUG CLASS
# -------------
# Phase 317 points the three services screens at a salon master by installing
# ONE `ProviderScope(overrides: [serviceTargetProvider.overrideWithValue(...)])`
# over the `/salons/:salonId/manage/staff/:memberId/services**` subtree.
# Riverpod 3 does NOT inherit scope transitively: an override only reaches a
# provider that has declared its way down to the overridden one via
# `dependencies:`. So the whole chain carries an explicit declaration —
# `serviceTarget` → `serviceRepository` → `masterServiceCatalog` →
# `ServicesList` → `serviceById` / `serviceTypes` / `serviceSetup`.
#
# A provider added to that chain LATER that forgets its `dependencies:` list
# does not crash. It resolves to the ROOT container, where `serviceTarget` is
# `null` — i.e. it silently serves the OPERATOR'S OWN catalogue under the salon
# master's heading, and a delete taken from that root-resolved repository
# dispatches `DELETE /services/{id}` against the SHARED salon service
# definition instead of phase 316's unassign. That is data loss, in the exact
# shape phase 316 exists to prevent.
#
# WHY GREP AND NOT THE FRAMEWORK
# -------------------------------
# Riverpod's own "The provider X depends on Y, which may be scoped. Yet Y is
# not part of X's dependencies list" assert is `kDebugMode`-gated
# (`riverpod-3.1.0/.../element.dart:922`). It fires only in a debug build AND
# only on a code path something actually executes. In a release AOT build it is
# compiled out entirely and the miss is SILENT. `riverpod_lint` — which would
# have caught this statically — was removed on 2026-08-18 when `custom_lint`
# was archived. So on today's tree the ONLY enforcement is "whichever test
# happens to run the path", which is not enforcement at all for a provider
# nobody wrote a test for yet.
#
# THE FOUR RULES THIS GATE ENFORCES
# ----------------------------------
# Scanned: every `*.dart` under `lib/` except generated `*.g.dart` /
# `*.freezed.dart`. Annotations are collapsed across physical lines first, so a
# multi-line `@Riverpod(\n  keepAlive: true,\n  dependencies: [...],\n)` is read
# whole. Comment lines and string literals are stripped from the body before
# matching, so prose about a provider never trips the gate.
#
#   UNDECLARED  — an `@riverpod` / `@Riverpod(...)` declaration whose BODY names
#                 a provider on the scoped chain (`SCOPED_PROVIDERS` below) and
#                 whose annotation carries NO `dependencies:` list at all.
#
#   UNRELATED   — (audit cycle 2, evasion 1) the same, except a `dependencies:`
#                 list IS present and its contents never reach the scoped chain:
#                 `@Riverpod(dependencies: [somethingUnrelated])` over a body
#                 reading `serviceRepositoryProvider`. Riverpod treats that
#                 EXACTLY like no declaration — the element still resolves to
#                 root inside the salon scope — so the old "has a list, fine"
#                 test was a hole you could walk through. The check is an
#                 INTERSECTION against the accepted declaration tokens derived
#                 from `SCOPED_PROVIDERS` (see below), NOT a completeness check:
#                 a list that is incomplete but RELATED (e.g. `ServicesList`
#                 declaring only `[masterServiceCatalog]`) is fine, because
#                 codegen expands the closure. Only a list that never reaches
#                 the chain is genuinely release-silent.
#
#   HANDWRITTEN — (evasion 2) a hand-rolled, non-codegen provider
#                 (`final p = Provider((ref) => ref.watch(serviceRepository
#                 Provider));`) whose initializer names a scoped provider. It
#                 carries no annotation, so the three checks above never even
#                 look at it, and a hand-rolled provider cannot declare
#                 `dependencies:` in the form codegen expands — it is scoped
#                 only if constructed with an explicit `dependencies:` argument
#                 nobody in this repo writes. Zero such providers exist in
#                 `lib/` today; the house rule is `@riverpod` codegen only
#                 (CLAUDE.md / ARCHITECTURE-mobile.md), so this check keeps the
#                 count at zero for the services chain specifically. Anchored on
#                 the CLOSED SET of riverpod constructor names, so a FAMILY READ
#                 that merely ends in `Provider(` — `cityListProvider(oblast.id)`
#                 — is not mistaken for a construction.
#
#   DRIFT       — (evasion 3) `SCOPED_PROVIDERS` used to be a hand-maintained
#                 list with nothing checking it, so a provider correctly ADDED
#                 to the cascade tomorrow silently failed to enrol, and the NEXT
#                 provider to read it went unflagged forever. It is now
#                 self-checking from SOURCE: any declaration whose
#                 `dependencies:` list intersects the accepted tokens IS by
#                 definition forked by phase 317's scope, so its own generated
#                 provider name MUST appear in `SCOPED_PROVIDERS`. Deliberately
#                 derived from the annotation rather than from the generated
#                 `$allTransitiveDependencies` metadata (e.g.
#                 `services_list_notifier.g.dart:79-90`): `**/*.g.dart` is
#                 gitignored (`.gitignore:66`), so a `.g.dart`-reading gate is
#                 only as good as whether CI happened to run build_runner before
#                 this step — a dependency this gate must not have.
#
# WHAT IT STILL DELIBERATELY DOES NOT DO — read this before trusting it
# ---------------------------------------------------------------------
#   • It does NOT check that a RELATED `dependencies:` list is COMPLETE. A
#     provider watching `serviceRepositoryProvider` and `serviceByIdProvider`
#     while declaring only `[serviceRepository]` passes here. That case is NOT
#     release-silent — riverpod's debug assert throws on a plain root read, so
#     any test touching the path goes red loudly. This gate exists for the
#     cases that are silent in release, and that is not one of them.
#   • It does NOT resolve TRANSITIVITY through a non-scoped intermediary. A
#     provider declaring `[somethingUnrelated]` where `somethingUnrelated`
#     itself reaches the chain is reported as UNRELATED. That shape does not
#     exist today and would be wrong anyway — riverpod's closure needs the
#     intermediary itself declared and enrolled, which DRIFT would then demand.
#   • It does NOT look at WIDGETS. A `ConsumerWidget` / `ConsumerState` that
#     reads a scoped provider needs no declaration — the widget resolves
#     against its own `ProviderScope` ancestor by construction. Every current
#     reader of these providers outside the chain is exactly that
#     (`service_edit_screen.dart`, `service_form.dart`, `service_setup_screen
#     .dart`, `services_list_screen.dart`, `category_request_dialog.dart`,
#     `service_type_suggestion_dialog.dart`, `master_archive_screen.dart`,
#     `bookings_discovery_view.dart`, `booking_wizard_steps.dart`,
#     `master_profile_screen.dart`), and none of them is flagged: they carry no
#     `@riverpod` annotation, so this gate never even looks at them.
#   • It does NOT flag a provider that merely SITS in a file alongside the
#     chain — e.g. `approvedCategories` (`service_repository.dart`), which
#     sources `categoryRequestApiProvider` directly and correctly declares
#     nothing.
#   • It does NOT read `test/`. A test may legitimately hand-roll a provider or
#     override a scoped one at the root: a unit test's `ProviderContainer` IS
#     the root and is disposed in `addTearDown` (phase 317 acceptance criteria).
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing, and auto-discovered by `scripts/verify_guards.sh`.
# Self-test:  ./scripts/forbid_undeclared_scoped_service_dep.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

# ---------------------------------------------------------------------------
# The scoped chain. Every provider whose element is forked by phase 317's
# `ProviderScope`. Adding a provider to the cascade means adding its generated
# provider name HERE too — and since audit cycle 2 that is ENFORCED, not
# merely documented: the DRIFT check fails the build on a declaration that
# joins the cascade without enrolling here.
#
# `serviceTargetProvider` is the overridden root; the other six are the
# transitive watchers phase 317 declared (D2's forced option (a)).
#
# The ACCEPTED DECLARATION TOKENS used by the UNRELATED and DRIFT checks are
# DERIVED from this list, never written out separately: for `fooBarProvider`
# they are `fooBar` (function-based codegen) and `FooBar` (class-based codegen,
# where the `dependencies:` entry is the CLASS name — `[ServicesList]`, not
# `[servicesList]`, which fails codegen outright). One list, no second place to
# forget.
# ---------------------------------------------------------------------------
SCOPED_PROVIDERS='serviceTargetProvider serviceRepositoryProvider masterServiceCatalogProvider servicesListProvider serviceByIdProvider serviceTypesProvider serviceSetupProvider'

# ---------------------------------------------------------------------------
# scan <scoped-names-csv> <accepted-tokens-csv> <file...>
#   ONE awk process over every file given. Emits
#   "<file>:<line>:<CODE>:<detail>" for each violation, where CODE is one of
#   UNDECLARED / UNRELATED / HANDWRITTEN / DRIFT.
# ---------------------------------------------------------------------------
scan() {
  local names_csv="$1"
  local accepted_csv="$2"
  shift 2
  awk -v names="$names_csv" -v accepted="$accepted_csv" '
    BEGIN {
      nnames = split(names, scoped, ",")
      naccepted = split(accepted, acceptedList, ",")
      for (i = 1; i <= naccepted; i++) acceptedSet[acceptedList[i]] = 1
      for (i = 1; i <= nnames; i++) scopedSet[scoped[i]] = 1
      # The CLOSED SET of riverpod provider constructor names. Anchored with a
      # word boundary so `cityListProvider(` — a FAMILY READ, not a
      # construction — cannot match, and so `ProviderScope(` /
      # `ProviderContainer(` cannot either (they are not followed by `(`).
      ctorPat = "(^|[^A-Za-z0-9_$])(Provider|StateProvider|StateNotifierProvider|ChangeNotifierProvider|FutureProvider|StreamProvider|NotifierProvider|AsyncNotifierProvider|StreamNotifierProvider)([.](autoDispose|family))*[[:space:]]*(<[^(]*>)?[[:space:]]*[(]"
    }

    # Removes string literals so a provider name inside a quoted string (a
    # `reason:` message, a log line) can never be mistaken for a reference.
    function strip_strings(s,   out, c, i, q, esc) {
      out = ""; q = ""; esc = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q != "") {
          if (esc) { esc = 0; continue }
          if (c == "\\") { esc = 1; continue }
          if (c == q) { q = "" }
          continue
        }
        if (c == "\"" || c == "'"'"'") { q = c; continue }
        out = out c
      }
      return out
    }
    # Drops a trailing `// ...` comment from an otherwise-code line. Whole-line
    # comments are skipped by the caller; this catches the tail case.
    function strip_trailing_comment(s,   p) {
      p = index(s, "//")
      if (p > 0) return substr(s, 1, p - 1)
      return s
    }
    function paren_delta(s,   i, c, d) {
      d = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "(") d++
        else if (c == ")") d--
      }
      return d
    }
    function brace_delta(s,   i, c, d) {
      d = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "{") d++
        else if (c == "}") d--
      }
      return d
    }
    function names_scoped(s,   i, nm, pat) {
      for (i = 1; i <= nnames; i++) {
        nm = scoped[i]
        pat = "(^|[^A-Za-z0-9_$])" nm "([^A-Za-z0-9_$]|$)"
        if (s ~ pat) return nm
      }
      return ""
    }
    # The contents of the annotation`s `dependencies: [...]` list, or "" when
    # no such list is present. `\x01` marks "absent" so an EMPTY list
    # (`dependencies: []`, which serviceTarget itself carries) stays
    # distinguishable from no list at all.
    function deps_list(a,   m) {
      if (a !~ /dependencies[[:space:]]*:/) return "\x01"
      if (match(a, /dependencies[[:space:]]*:[[:space:]]*\[[^]]*\]/) == 0) {
        return "\x01"
      }
      m = substr(a, RSTART, RLENGTH)
      sub(/^[^[]*\[/, "", m)
      sub(/\]$/, "", m)
      return m
    }
    # Does the declared list name any provider on the scoped chain?
    function deps_reach_chain(d,   n, parts, i, tok) {
      n = split(d, parts, ",")
      for (i = 1; i <= n; i++) {
        tok = parts[i]
        gsub(/[^A-Za-z0-9_$]/, "", tok)
        if (tok != "" && (tok in acceptedSet)) return tok
      }
      return ""
    }
    function lcfirst(s) { return tolower(substr(s, 1, 1)) substr(s, 2) }
    # The generated provider name for the accumulated declaration: a class
    # `ServicesList` generates `servicesListProvider`, a function
    # `serviceById` generates `serviceByIdProvider`.
    function decl_provider_name(b,   m, nm, p, i, c) {
      if (match(b, /(^|[^A-Za-z0-9_$])class[[:space:]]+[A-Za-z0-9_$]+/)) {
        m = substr(b, RSTART, RLENGTH)
        sub(/^.*class[[:space:]]+/, "", m)
        return lcfirst(m) "Provider"
      }
      p = index(b, "(")
      if (p == 0) return ""
      nm = ""
      for (i = p - 1; i >= 1; i--) {
        c = substr(b, i, 1)
        if (c ~ /[A-Za-z0-9_$]/) { nm = c nm; continue }
        break
      }
      if (nm == "") return ""
      return nm "Provider"
    }

    # Emits every violation the accumulated annotated declaration carries.
    function flush(   hit, deps, reached, pname) {
      hit = names_scoped(body)
      deps = deps_list(ann)
      reached = (deps == "\x01") ? "" : deps_reach_chain(deps)

      if (hit != "") {
        if (deps == "\x01") {
          printf "%s:%d:UNDECLARED:%s\n", file, annline, hit
        } else if (reached == "") {
          printf "%s:%d:UNRELATED:%s\n", file, annline, hit
        }
      }
      if (reached != "") {
        pname = decl_provider_name(body)
        if (pname != "" && !(pname in scopedSet)) {
          printf "%s:%d:DRIFT:%s\n", file, annline, pname
        }
      }
    }

    # Emits a violation for a hand-rolled provider whose initializer names a
    # scoped provider.
    function flush_handrolled(   hit) {
      hit = names_scoped(hand)
      if (hit != "") printf "%s:%d:HANDWRITTEN:%s\n", file, handline, hit
    }

    FNR == 1 {
      if (state == 2) flush()
      else if (state == 3) flush_handrolled()
      file = FILENAME; state = 0; ann = ""; body = ""
      annline = 0; depth = 0; started = 0
      hand = ""; handline = 0; hdepth = 0
    }

    {
      raw = $0
      trimmed = raw
      sub(/^[[:space:]]+/, "", trimmed)
      is_comment = (trimmed ~ /^[/][/]/)

      if (state == 0) {
        if (is_comment) next
        if (trimmed ~ /^@[Rr]iverpod([^A-Za-z0-9_]|$)/) {
          ann = strip_trailing_comment(strip_strings(raw))
          annline = FNR
          d = paren_delta(ann)
          while (d > 0 && (getline nxt) > 0) {
            nxt = strip_trailing_comment(strip_strings(nxt))
            ann = ann " " nxt
            d += paren_delta(nxt)
          }
          state = 2; body = ""; depth = 0; started = 0
          next
        }
        code = strip_trailing_comment(strip_strings(raw))
        if (code ~ /(=|=>)[[:space:]]*/ && code ~ ctorPat) {
          hand = code; handline = FNR
          hdepth = paren_delta(code) + brace_delta(code)
          if (hdepth <= 0 && code ~ /;[[:space:]]*$/) {
            flush_handrolled(); hand = ""
          } else {
            state = 3
          }
        }
        next
      }

      if (state == 3) {
        # Accumulating a hand-rolled provider statement until its terminating
        # `;` at depth 0.
        if (is_comment) next
        code = strip_trailing_comment(strip_strings(raw))
        hand = hand " " code
        hdepth += paren_delta(code) + brace_delta(code)
        if (hdepth <= 0 && code ~ /;[[:space:]]*$/) {
          flush_handrolled(); state = 0; hand = ""
        }
        next
      }

      # state 2 — accumulating the annotated declaration.
      if (is_comment) next
      code = strip_trailing_comment(strip_strings(raw))
      body = body " " code
      if (code ~ /[{]/) started = 1
      depth += brace_delta(code)
      if (started && depth <= 0) { flush(); state = 0; next }
      if (!started && depth == 0 && code ~ /;[[:space:]]*$/) {
        flush(); state = 0; next
      }
    }

    END {
      if (state == 2) flush()
      else if (state == 3) flush_handrolled()
    }
  ' "$@"
}

# ---------------------------------------------------------------------------
# accepted_tokens
#   Derives the `dependencies:` entry spellings from SCOPED_PROVIDERS: for
#   `fooBarProvider` both `fooBar` and `FooBar`.
# ---------------------------------------------------------------------------
accepted_tokens() {
  local p base out=''
  for p in $SCOPED_PROVIDERS; do
    base="${p%Provider}"
    [ -z "$base" ] && continue
    out="$out,$base,$(printf '%s' "${base:0:1}" | tr '[:lower:]' '[:upper:]')${base:1}"
  done
  printf '%s' "${out#,}"
}

# ---------------------------------------------------------------------------
# run_gate <tree_root>
#   Emits offenders on stdout; nothing on a clean tree.
# ---------------------------------------------------------------------------
run_gate() {
  local tree_root="$1"

  local -a files=()
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    files+=("$f")
  done < <(
    find "$tree_root/lib" -type f -name '*.dart' \
      ! -name '*.g.dart' ! -name '*.freezed.dart' 2>/dev/null | sort
  )

  [ "${#files[@]}" -eq 0 ] && return 0

  local names_csv
  names_csv="$(printf '%s' "$SCOPED_PROVIDERS" | tr ' ' ',')"

  scan "$names_csv" "$(accepted_tokens)" "${files[@]}"
}

# ---------------------------------------------------------------------------
# Self-test mode.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/lib/probe"

  # 1 — DECLARED, single-line annotation. Must NOT be flagged.
  # 2 — UNDECLARED `@riverpod` reading masterServiceCatalogProvider. FLAG.
  cat > "$tmp/lib/probe/probe_a.dart" <<'EOF'
@Riverpod(keepAlive: true, dependencies: [serviceTarget])
ServiceRepository serviceRepository(Ref ref) {
  return HttpServiceRepository(target: ref.watch(serviceTargetProvider));
}

@riverpod
Future<int> probeUndeclared(Ref ref) async {
  final catalog = await ref.watch(masterServiceCatalogProvider.future);
  return catalog.length;
}
EOF

  # 3 — UNDECLARED `@Riverpod(keepAlive: true)` with a MULTILINE `ref.watch(`.
  #     FLAG. A single-line grep would miss exactly this shape.
  # 4 — DECLARED across MULTIPLE physical lines. Must NOT be flagged.
  # 5 — a provider naming a scoped provider only in PROSE and in a STRING.
  #     Must NOT be flagged.
  cat > "$tmp/lib/probe/probe_b.dart" <<'EOF'
@Riverpod(keepAlive: true)
Future<int> probeMultilineWatch(Ref ref) async {
  final list = await ref.watch(
    servicesListProvider.future,
  );
  return list.length;
}

@Riverpod(
  keepAlive: true,
  dependencies: [serviceRepository, ServicesList],
)
Future<int> servicesList(Ref ref) async {
  final repo = ref.watch(serviceRepositoryProvider);
  return repo.hashCode;
}

@riverpod
Future<int> probeProseOnly(Ref ref) async {
  // Deliberately NOT serviceRepositoryProvider — see the seam doc.
  final label = 'serviceByIdProvider';
  return label.length;
}
EOF

  # 6 — a WIDGET reading two scoped providers, with NO @riverpod anywhere in
  #     the file. Must NOT be flagged: a widget resolves against its own
  #     ProviderScope ancestor and needs no declaration.
  cat > "$tmp/lib/probe/probe_widget.dart" <<'EOF'
class ProbeScreen extends ConsumerWidget {
  const ProbeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncService = ref.watch(serviceByIdProvider('x'));
    final repository = ref.read(serviceRepositoryProvider);
    return Text('$asyncService$repository');
  }
}
EOF

  # 7 — a widget declared AFTER an annotated provider in the SAME file. The
  #     provider's body must end at its own closing brace, so the widget's
  #     scoped reads must NOT be attributed to it.
  cat > "$tmp/lib/probe/probe_mixed.dart" <<'EOF'
@riverpod
Future<int> probeHarmless(Ref ref) async {
  final api = ref.watch(categoryRequestApiProvider);
  return api.hashCode;
}

class ProbeMixedScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Text('${ref.watch(serviceTypesProvider('MANICURE'))}');
  }
}
EOF

  # 9 — EVASION 1: a `dependencies:` list that IS present but whose contents
  #     never reach the scoped chain. Riverpod treats this exactly like no
  #     declaration. FLAG as UNRELATED.
  # 10 — EVASION 3: a declaration that DOES join the cascade
  #      (`dependencies: [serviceRepository]`) but whose own generated provider
  #      name is absent from SCOPED_PROVIDERS. FLAG as DRIFT.
  cat > "$tmp/lib/probe/probe_evasions.dart" <<'EOF'
@Riverpod(keepAlive: true, dependencies: [somethingUnrelated])
Future<int> probeUnrelatedList(Ref ref) async {
  final repo = ref.watch(serviceRepositoryProvider);
  return repo.hashCode;
}

@Riverpod(dependencies: [serviceRepository])
class ProbeUnenrolled extends _$ProbeUnenrolled {
  @override
  int build() => 0;
}
EOF

  # 11 — EVASION 2: a hand-rolled, non-codegen provider reading a scoped
  #      provider. No annotation, so the annotation checks never see it.
  #      FLAG as HANDWRITTEN.
  # 12 — a FAMILY READ that merely ends in `Provider(` must NOT be mistaken
  #      for a construction, and a `ProviderScope(` must not either.
  cat > "$tmp/lib/probe/probe_handrolled.dart" <<'EOF'
final probeHandRolled = Provider<ServiceRepository>(
  (ref) => ref.watch(serviceRepositoryProvider),
);

Widget probeFamilyRead(WidgetRef ref, String id) {
  final target = cityListProvider(id);
  return ProviderScope(
    overrides: const [],
    child: Text('$target'),
  );
}
EOF

  out="$(run_gate "$tmp")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"

  fail() {
    echo "SELF-TEST FAIL: $1"
    printf '%s\n' "$out"
    exit 1
  }

  if [ "$flagged" -ne 5 ]; then
    fail "expected exactly 5 offenders (probe_a probeUndeclared,
                probe_b probeMultilineWatch, probe_evasions x2,
                probe_handrolled), got $flagged:"
  fi

  # --- the original eight assertions, unchanged in meaning ----------------
  printf '%s\n' "$out" | grep -q "probe_a.dart:6:UNDECLARED:masterServiceCatalogProvider" ||
    fail "the UNDECLARED single-line reader (probe_a.dart:6,
                probeUndeclared) was not flagged:"
  printf '%s\n' "$out" | grep -q "probe_b.dart:1:UNDECLARED:servicesListProvider" ||
    fail "the UNDECLARED MULTILINE reader (probe_b.dart:1,
                probeMultilineWatch) was not flagged — a
                'ref.watch(\n  fooProvider.future,\n)' shape is exactly what
                a single-line grep misses:"
  ! printf '%s\n' "$out" | grep -q "probe_a.dart:1:" ||
    fail "the DECLARED provider (probe_a.dart:1) was flagged:"
  ! printf '%s\n' "$out" | grep -q "probe_b.dart:9:" ||
    fail "a MULTILINE 'dependencies:' annotation was not collapsed before
                testing, so a correctly-declared provider was flagged:"
  ! printf '%s\n' "$out" | grep -q "probe_b.dart:18:" ||
    fail "a provider naming a scoped provider only in a COMMENT and a STRING
                was flagged — comments and string literals must be stripped
                before matching:"
  ! printf '%s\n' "$out" | grep -q "probe_widget.dart" ||
    fail "a WIDGET reader was flagged. A ConsumerWidget resolves against its
                own ProviderScope ancestor and needs no 'dependencies:' —
                every real reader outside the chain is one of these:"
  ! printf '%s\n' "$out" | grep -q "probe_mixed.dart" ||
    fail "a widget declared AFTER an annotated provider in the same file was
                attributed to that provider — the declaration body must end at
                its own closing brace:"

  # --- audit cycle 2: the three planted evasions -------------------------
  printf '%s\n' "$out" | grep -q "probe_evasions.dart:1:UNRELATED:serviceRepositoryProvider" ||
    fail "EVASION 1 — a 'dependencies:' list that is PRESENT but never reaches
                the scoped chain was not flagged. Riverpod treats it exactly
                like no declaration at all:"
  printf '%s\n' "$out" | grep -q "probe_evasions.dart:7:DRIFT:probeUnenrolledProvider" ||
    fail "EVASION 3 — a declaration that JOINS the cascade without enrolling
                in SCOPED_PROVIDERS was not flagged. Without this the list
                rots and the NEXT provider to read it goes unchecked:"
  ! printf '%s\n' "$out" | grep -q "probe_evasions.dart:7:UNRELATED\|probe_evasions.dart:7:UNDECLARED" ||
    fail "the DRIFT probe declares [serviceRepository], so it must NOT also be
                reported as UNRELATED/UNDECLARED — an intersecting list is a
                valid declaration:"
  printf '%s\n' "$out" | grep -q "probe_handrolled.dart:1:HANDWRITTEN:serviceRepositoryProvider" ||
    fail "EVASION 2 — a hand-rolled, non-codegen provider reading a scoped
                provider was not flagged. It carries no annotation, so nothing
                else in this gate looks at it:"
  ! printf '%s\n' "$out" | grep -q "probe_handrolled.dart:6\|probe_handrolled.dart:7\|probe_handrolled.dart:8" ||
    fail "a FAMILY READ ('cityListProvider(id)') or a 'ProviderScope(' was
                mistaken for a hand-rolled provider CONSTRUCTION — the
                constructor set must be closed and word-anchored:"
  # ANTI-VACUITY for the UNRELATED check: `probe_b`'s `servicesList` declares
  # [serviceRepository, ServicesList] and IS enrolled, so it must be silent on
  # both the UNRELATED and the DRIFT axis. Without this a gate that flagged
  # every declaration would satisfy the two positives above.
  ! printf '%s\n' "$out" | grep -q "probe_b.dart:9:DRIFT\|probe_b.dart:9:UNRELATED" ||
    fail "an ENROLLED provider with a RELATED 'dependencies:' list was flagged
                — the UNRELATED/DRIFT checks must be silent on the real chain:"

  echo "SELF-TEST PASS: an @riverpod provider that reads a scoped services"
  echo "                provider is flagged when it declares NOTHING"
  echo "                (single-line AND multiline reads) and when it declares"
  echo "                a list that never reaches the chain; a hand-rolled"
  echo "                non-codegen provider reading the chain is flagged; a"
  echo "                declaration that joins the cascade without enrolling in"
  echo "                SCOPED_PROVIDERS is flagged. Declared providers"
  echo "                (including multiline annotations), prose/string-only"
  echo "                mentions, widget readers, family reads, ProviderScope"
  echo "                and code following an annotated declaration are all"
  echo "                silent."
  echo "SELF-TEST OK: forbid_undeclared_scoped_service_dep.sh"
  exit 0
fi

# ---------------------------------------------------------------------------
# Real run over the working tree.
# ---------------------------------------------------------------------------
offenders="$(run_gate "$root")"

if [ -n "$offenders" ]; then
  echo "Scoped-services 'dependencies:' cascade violation(s):"
  echo "$offenders"
  echo
  echo "Format: <file>:<line>:<CODE>:<detail>"
  echo
  echo "  UNDECLARED  — an @riverpod provider reads the scoped services chain"
  echo "                with NO 'dependencies:' list."
  echo "  UNRELATED   — it HAS a 'dependencies:' list, but nothing in that list"
  echo "                reaches the scoped chain. Riverpod treats that exactly"
  echo "                like declaring nothing."
  echo "  HANDWRITTEN — a hand-rolled, non-codegen provider reads the chain."
  echo "                Use @riverpod codegen (house rule) and declare the edge."
  echo "  DRIFT       — a declaration joined the cascade (its 'dependencies:'"
  echo "                reaches the chain) but its generated provider name is"
  echo "                missing from SCOPED_PROVIDERS in this script. Add it,"
  echo "                or the NEXT provider that reads it goes unchecked."
  echo
  echo "Riverpod 3 does not inherit scope transitively. Without a RELATED"
  echo "'dependencies:' list this provider resolves against the ROOT"
  echo "container inside phase 317's salon ProviderScope, where"
  echo "serviceTargetProvider is null — so it would render the OPERATOR's own"
  echo "catalogue under a salon master's heading, and a delete taken from it"
  echo "would dispatch DELETE /services/{id} against the SHARED salon service"
  echo "definition instead of phase 316's unassign."
  echo
  echo "Riverpod's own assert is kDebugMode-only and riverpod_lint was removed"
  echo "on 2026-08-18, so a miss is SILENT in a release AOT build."
  echo
  echo "Fix it by declaring the edge on the annotation, e.g."
  echo "    @Riverpod(keepAlive: true, dependencies: [serviceRepository])"
  echo "Use the CLASS name for a class-based provider ([ServicesList], not"
  echo "[servicesList]) — the lowercase form fails codegen. A 'ref.read' or"
  echo "'ref.listen' edge needs the declaration exactly as 'ref.watch' does:"
  echo "riverpod's transitive closure does not cover a read."
  echo
  echo "See phase-317's D2 table for the full cascade, or"
  echo "lib/features/services/data/service_repository.dart's"
  echo "'SCOPED-TARGET CONTRACT' doc comment."
  exit 1
fi

exit 0
