#!/usr/bin/env bash
# Phase 076 (10.2, A2) gate — no raw network images in lib/.
#
# Every network image must go through `RemoteImage`
# (`lib/core/media/beautica_image.dart`), which wraps the provider in a
# `ResizeImage` so the decoded bitmap is bounded to the paint size (mobile-perf
# MP2). A raw `Image.network(`, `NetworkImage(` or `CachedNetworkImage(` decodes
# at the SOURCE resolution — a full-size photo per list row — and is exactly the
# jank this phase audits.
#
# Allowed ONLY in lib/core/media/beautica_image.dart (the single allow-list
# entry; there is no per-line allow-list). Comments and string contents are
# ignored, so prose such as `ResizeImage(NetworkImage(url), …)` in a doc comment
# is fine. `lib/api/` is generated and exempt. A bare
# `CachedNetworkImageProvider(` is flagged unless it is the first argument of
# `ResizeImage(` (its disk-cached provider decodes at source size too).
#
# Usage:
#   ./scripts/forbid_raw_network_image.sh              scan lib/
#   ./scripts/forbid_raw_network_image.sh --self-test  prove it fails on a planted violation

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"

ALLOWED="lib/core/media/beautica_image.dart"

# scan <root> : prints FILE:LINE:text for each raw network-image construction
# under <root>/lib, outside the allowed file and lib/api.
#
# Token-aware (python3): comments (line, doc, NESTED block) and string-literal
# contents (', ", triple-quoted, raw) are blanked first, so a `//` inside a
# string cannot truncate code and block-comment bodies need no leading `*`.
# Matching then runs over the whole file, so `Image.network` / `NetworkImage`
# with the `(` on a later line is caught. Flagged: Image.network(, NetworkImage(,
# NetworkImage.new, CachedNetworkImage(, FadeInImage.network(, and a
# CachedNetworkImageProvider( that is not the first argument of ResizeImage(.
scan() {
  local root="$1" f rel
  [ -d "$root/lib" ] || return 0
  while IFS= read -r -d '' f; do
    rel="${f#"$root"/}"
    [ "$rel" = "$ALLOWED" ] && continue
    case "$rel" in lib/api/*) continue ;; esac
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
                    break  # unterminated single-line string: resync at EOL
                else:
                    out.append(keep(src[i])); i += 1
            if src.startswith(q, i):
                out.append(" " * len(q)); i += len(q)
        else:
            out.append(c); i += 1
    return "".join(out)


code = blank(raw)
lines = raw.split("\n")
B = r"(?<![A-Za-z0-9_$])"
banned = re.compile(
    B + r"(?:Image\s*\.\s*network|NetworkImage|CachedNetworkImage|FadeInImage\s*\.\s*network)\s*(?:\.\s*new\s*)?\("
    + "|" + B + r"NetworkImage\s*\.\s*new\b")
provider = re.compile(B + r"CachedNetworkImageProvider\s*(?:\.\s*new\s*)?\(")
wrapped = re.compile(r"ResizeImage\s*\(\s*$")
hits = set()
for m in banned.finditer(code):
    hits.add(code.count("\n", 0, m.start()) + 1)
for m in provider.finditer(code):
    if not wrapped.search(code[:m.start()]):
        hits.add(code.count("\n", 0, m.start()) + 1)
for ln in sorted(hits):
    print("%s:%d:%s" % (rel, ln, lines[ln - 1].rstrip()))
PY
  done < <(find "$root/lib" -type f -name '*.dart' -print0 | sort -z)
}

if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/lib/core/media" "$tmp/lib/f"
  # Clean: allowed file, comments, provider look-alike.
  printf '%s\n' 'final a = Image.network(u);' > "$tmp/lib/core/media/beautica_image.dart"
  printf '%s\n' '/// builds ResizeImage(NetworkImage(url), …) here' \
    '// CachedNetworkImage(x) is banned' \
    '/*' ' Image.network(u) in a block body' '*/' \
    'final p = ResizeImage(CachedNetworkImageProvider(u), width: 4); // not NetworkImage(u)' > "$tmp/lib/f/clean.dart"
  if [ -n "$(scan "$tmp")" ]; then
    echo "SELF-TEST FAIL: allowed file / comments / provider flagged" >&2; exit 1
  fi
  printf '%s\n' 'Widget w() => Image.network(u);' > "$tmp/lib/f/bad1.dart"
  printf '%s\n' 'final p = NetworkImage(u);' > "$tmp/lib/f/bad2.dart"
  printf '%s\n' 'Widget w() => CachedNetworkImage(imageUrl: u);' > "$tmp/lib/f/bad3.dart"
  n="$(scan "$tmp" | wc -l)"
  if [ "$n" -ne 3 ]; then
    echo "SELF-TEST FAIL: expected 3 planted violations detected, got $n" >&2; exit 1
  fi
  echo "SELF-TEST OK: $(basename "$0")"
  exit 0
fi

hits="$(scan "$repo")"
if [ -n "$hits" ]; then
  echo "FORBIDDEN: raw network image in lib/ (decodes at source resolution):" >&2
  printf '  %s\n' "$hits" >&2
  echo "Use RemoteImage (lib/core/media/beautica_image.dart) — it bounds the decode (MP2)." >&2
  exit 1
fi
echo "forbid_raw_network_image: OK"
