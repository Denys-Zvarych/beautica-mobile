#!/usr/bin/env bash
# Raw-push gate (2026-10-15, "one tap fires twice" sweep).
#
# THE BUG CLASS
# -------------
# A tap handler that runs `context.push(...)` is disabled only by a REBUILD
# (a `loading:` flag, a null `onPressed`, the new route covering the button).
# Taps landing in the same frame — a fast double-tap, or taps queued while the
# UI thread stalled — each push their own copy. On the booking flow that was
# a stack of confirm screens, each with its own idempotency key.
#
# THE RULE
# --------
# Under lib/features/, screen navigation pushes go through the single-flight
# helper (lib/core/navigation/single_flight.dart):
#     context.pushOnce(location, extra: …)      not   context.push(…)
#     context.pushNamedOnce(name, …)            not   context.pushNamed(…)
#     runOnce(context, () => Navigator…push(…)) not   Navigator.of(context).push(…)
# Flagged: any `.push(` / `.push<…>(` / `.pushNamed(` member call — on
# `context`, `GoRouter.of(…)`, a router variable, `Navigator.of(…)`, or a
# continuation line starting with `.push(` — plus a static `Navigator.push(`.
# `pushReplacement`, `pushOnce`, `pushNamedOnce` are not matched. Comments
# and string contents are ignored (token-aware blanking, python3).
#
# ALLOW-LIST (line-numbered, fingerprinted)
# -----------------------------------------
# scripts/.raw_push_allow lists justified exceptions — sites that already
# carry their own synchronous single-flight guard — one per line as
#     <path>:<line>:<fingerprint>
# The fingerprint is a substring that must appear on that exact line. An
# entry whose line no longer holds its fingerprint, or no longer holds a raw
# push, FAILS the gate as STALE: line-numbered allow-lists silently drift
# when code above them grows, and a drifted entry that still lands on SOME
# push would quietly excuse the wrong call. Renumber by inspection.
#
# Usage:
#   ./scripts/forbid_raw_push.sh              scan lib/features/
#   ./scripts/forbid_raw_push.sh --self-test  prove it fails on planted violations

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"

# scan <root> : prints FILE:LINE:text for each raw push under <root>/lib/features.
scan() {
  local root="$1" f rel
  [ -d "$root/lib/features" ] || return 0
  while IFS= read -r -d '' f; do
    rel="${f#"$root"/}"
    python3 - "$rel" "$f" <<'PY'
import re, sys

rel, path = sys.argv[1], sys.argv[2]
raw = open(path, encoding="utf-8", errors="replace").read().replace("\r\n", "\n")


def blank(src):
    out, i, n = [], 0, len(src)
    keep = lambda c: c if c == "\n" else " "
    while i < n:
        c = src[i]
        if src.startswith("//", i):
            while i < n and src[i] != "\n":
                out.append(" "); i += 1
        elif src.startswith("/*", i):
            depth = 0
            while i < n:
                if src.startswith("/*", i):
                    depth += 1; out.append("  "); i += 2
                elif src.startswith("*/", i):
                    depth -= 1; out.append("  "); i += 2
                    if depth == 0:
                        break
                else:
                    out.append(keep(src[i])); i += 1
        elif c in "'\"":
            is_raw = i > 0 and src[i - 1] == "r" and (i < 2 or not (src[i - 2].isalnum() or src[i - 2] in "_$"))
            q = src[i:i + 3] if src.startswith(c * 3, i) else c
            out.append(" " * len(q)); i += len(q)
            while i < n and not src.startswith(q, i):
                if src[i] == "\\" and not is_raw and i + 1 < n:
                    out.append(keep(src[i]) + keep(src[i + 1])); i += 2
                elif len(q) == 1 and src[i] == "\n":
                    break
                else:
                    out.append(keep(src[i])); i += 1
            if src.startswith(q, i):
                out.append(" " * len(q)); i += len(q)
        else:
            out.append(c); i += 1
    return "".join(out)


code = blank(raw)
lines = raw.split("\n")
# `.push(` / `.push<T>(` / `.pushNamed(` / `.pushNamed<T>(` as a member call
# (any receiver, including a continuation line), or static Navigator.push(.
banned = re.compile(
    r"\.\s*push(?:Named)?\s*(?:<[^>()]*>)?\s*\("
    r"|(?<![A-Za-z0-9_$])Navigator\s*\.\s*push(?:Named)?\s*(?:<[^>()]*>)?\s*\(")
hits = sorted({code.count("\n", 0, m.start()) + 1 for m in banned.finditer(code)})
for ln in hits:
    print("%s:%d:%s" % (rel, ln, lines[ln - 1].rstrip()))
PY
  done < <(find "$root/lib/features" -type f -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' -print0 | sort -z)
}

# check <root> <allow_file> : exit 1 on an unlisted hit or a stale entry.
check() {
  local root="$1" allow="$2"
  local hits
  hits="$(scan "$root")"
  python3 - "$root" "$allow" "$hits" <<'PY'
import os, sys

root, allow_path, hits = sys.argv[1], sys.argv[2], sys.argv[3]
hit_lines = {}
for h in filter(None, hits.split("\n")):
    path, ln, text = h.split(":", 2)
    hit_lines[(path, int(ln))] = text

entries = []
if os.path.exists(allow_path):
    for raw in open(allow_path, encoding="utf-8"):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        path, ln, fp = line.split(":", 2)
        entries.append((path, int(ln), fp.strip()))

bad = False
allowed = set()
for path, ln, fp in entries:
    full = os.path.join(root, path)
    src = open(full, encoding="utf-8").read().split("\n") if os.path.exists(full) else []
    text = src[ln - 1] if 0 < ln <= len(src) else ""
    if fp not in text or (path, ln) not in hit_lines:
        print("STALE allow-list entry %s:%d (fingerprint %r): line is now %r"
              % (path, ln, fp, text.strip()), file=sys.stderr)
        bad = True
    else:
        allowed.add((path, ln))

unlisted = [(k, v) for k, v in sorted(hit_lines.items()) if k not in allowed]
if unlisted:
    print("FORBIDDEN: raw push under lib/features/ (same-frame taps push twice):",
          file=sys.stderr)
    for (path, ln), text in unlisted:
        print("  %s:%d:%s" % (path, ln, text), file=sys.stderr)
    print("Use context.pushOnce / pushNamedOnce / runOnce "
          "(lib/core/navigation/single_flight.dart). A site with its own "
          "synchronous guard may be listed in scripts/.raw_push_allow as "
          "<path>:<line>:<fingerprint>.", file=sys.stderr)
    bad = True
sys.exit(1 if bad else 0)
PY
}

if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/lib/features/x"
  printf '%s\n' \
    "// context.push('/a') in a comment" \
    "/* Navigator.of(context).push(r) */" \
    "final s = 'context.push(x)';" \
    "void a(BuildContext context) => context.pushOnce('/a');" \
    "void b(BuildContext context) => context.pushReplacement('/a');" \
    "void c(BuildContext context) => context.pushNamedOnce('n');" \
    > "$tmp/lib/features/x/clean.dart"
  : > "$tmp/allow"
  if ! check "$tmp" "$tmp/allow" 2>/dev/null; then
    echo "SELF-TEST FAIL: clean file flagged" >&2; exit 1
  fi
  printf '%s\n' \
    "void a(BuildContext context) => context.push('/a');" \
    "void b(BuildContext context) => context.push<bool>('/a');" \
    "void c(BuildContext context) => context.pushNamed('n');" \
    "void d(BuildContext context) => GoRouter.of(context).push('/a');" \
    "void e(BuildContext context) => Navigator.of(context).push(r);" \
    "void f(BuildContext context) => Navigator.push(context, r);" \
    "void g(BuildContext context) => context" \
    "    .push('/a');" \
    > "$tmp/lib/features/x/bad.dart"
  n="$(scan "$tmp" | wc -l)"
  if [ "$n" -ne 7 ]; then
    echo "SELF-TEST FAIL: expected 7 planted violations, got $n" >&2; exit 1
  fi
  if check "$tmp" "$tmp/allow" 2>/dev/null; then
    echo "SELF-TEST FAIL: violations not rejected" >&2; exit 1
  fi
  # Allow-listing all 7 with correct fingerprints passes...
  scan "$tmp" | while IFS=: read -r p l _; do
    echo "$p:$l:push"
  done > "$tmp/allow"
  if ! check "$tmp" "$tmp/allow" 2>/dev/null; then
    echo "SELF-TEST FAIL: fingerprinted allow-list not honoured" >&2; exit 1
  fi
  # ...and a drifted entry (line moved) fails as STALE.
  printf '%s\n' "// shifted" | cat - "$tmp/lib/features/x/bad.dart" > "$tmp/b2"
  mv "$tmp/b2" "$tmp/lib/features/x/bad.dart"
  if check "$tmp" "$tmp/allow" 2>/dev/null; then
    echo "SELF-TEST FAIL: drifted allow-list entry not reported" >&2; exit 1
  fi
  echo "SELF-TEST OK: $(basename "$0")"
  exit 0
fi

if check "$repo" "$here/.raw_push_allow"; then
  echo "forbid_raw_push: OK"
else
  exit 1
fi
