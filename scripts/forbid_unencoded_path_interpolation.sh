#!/usr/bin/env bash
# Hand-built API path interpolation gate (mobile-security S-L2, 2026-09-17).
#
# THE INVARIANT THIS ENFORCES
# ---------------------------
# `lib/core/network/path_segment.dart` states — correctly, since the 2026-09-17
# correction — that the GENERATED Dio client does no path encoding whatsoever:
# `api/lib/src/api_util.dart`'s `encodeQueryParameter` returns a `String` input
# verbatim, so every generated path param is interpolated raw. What makes those
# call sites safe is the PROVENANCE of their ids (server-issued UUIDs already
# matched by an ownership / roster / route gate), never the client.
#
# Nothing enforced that. This gate does, for the half that IS mechanically
# checkable: every HAND-BUILT `/api/v1/…` path literal in `lib/` must route
# each interpolated id through `encodePathSegment` (`lib/core/network/
# path_segment.dart`) — the one encoder that BOTH percent-encodes and REJECTS
# the dot-segments `Uri.encodeComponent` leaves verbatim for Dio's
# `Uri.parse(url).normalizePath()` to collapse (RFC 3986 §5.2.4). Measured, in
# that file's own doc: `masters/../services/..` degenerates to
# `/api/v1/salons/S/`, one slash from the delete-the-whole-salon endpoint, on
# the authenticated Dio that carries the bearer token.
#
# It CANNOT enforce provenance on generated call sites — that is a code-review
# obligation and the path_segment.dart doc says so. Do not read a green run
# here as "every path param in the app is safe". Read it as exactly this, and
# no wider:
#
#   No `/api/v1/…` STRING LITERAL under `lib/` (minus `lib/api/`), nor any
#   Dart adjacent-string-literal continuation of one, interpolates a value
#   that the same file never routed through `encodePathSegment`.
#
# What that sentence deliberately does NOT cover, so nobody reads more into a
# green run than it earns:
#   • PROVENANCE at generated call sites (above) — unenforceable here.
#   • A path assembled by `+` concatenation, by `StringBuffer`, or from a
#     prefix held in a variable, where no single literal carries `/api/v1/`.
#     No such shape exists in `lib/` today (every hand-built path is one
#     literal, or one `dart format`-wrapped run of adjacent literals), and if
#     one is introduced this gate will not see it.
#   • Encoding CORRECTNESS. The gate proves the call happened, not that its
#     argument was the id actually interpolated.
#
# MULTI-LINE, and why that is not a detail (2026-09-17)
# ----------------------------------------------------
# The first revision of this gate scanned ONE LINE AT A TIME and bailed on
# `index($0, "/api/v1/") == 0`. `dart format` breaks a path past 80 columns
# into ADJACENT STRING LITERALS on consecutive lines, which puts the
# `/api/v1/` prefix and the `$id` on DIFFERENT lines — and that is the shape
# the very fix this gate was written to lock in uses at
# `location_repository.dart:96` and `:107`. The gate reported OK on it. It
# could not have re-detected a regression at two of the six sites it is
# credited with fixing, and the claim above was false as written.
#
# The scan walks STRING LITERALS, not lines (rewritten 2026-09-17, audit
# cycle 3, findings G1/G2/G3). Each physical line is tokenised into its string
# literals; two literals belong to the same path expression when NOTHING but
# whitespace separates them, which is Dart's own adjacent-string-literal
# concatenation rule and the single stop rule the walker needs. The separator
# is carried ACROSS the line break, so the comma that closes a wrapped path
# lands in the next literal's gap and the `mapper:` / `queryParameters:`
# argument beneath it — with its own unrelated `$` — is never dragged in.
# Every literal of an active run is judged, and the violation is reported on
# the PHYSICAL line that carries the `$`.
#
# Three things the line-oriented predecessor got wrong, all fixed here and all
# now sentinelled:
#
#   G1 — AN INTERPOSED COMMENT ENDED THE RUN. `dart format` PRESERVES
#        comments, so a `//` line between two adjacent literals is a
#        format-stable shape; the old rule needed `tail[last]` and
#        `lead[last+1]` to both be quotes, so a comment terminated the group
#        and the continuation then failed the head's own `/api/v1/` test and
#        was never judged at all — an unencoded id hid behind one comment.
#        A comment line is now TRANSPARENT to a run. Sentinel: `bad.dart` f.
#
#   G2 — `judge()` SCANNED THE WHOLE PHYSICAL LINE, so an unrelated `$` that
#        merely shared a line with an already-encoded path was reported as a
#        violation. It is now scoped to the literal body. This was the more
#        important of the two: a guard that cries wolf gets disabled, which
#        is worse than the hole G1 closes. Sentinel: `good.dart` h.
#
#   G3 — HALF THE STOP RULE HAD NO SENTINEL. Deleting the line-tail/comma
#        check left `--self-test` green, in the fixture AND against the real
#        repo, because in both existing stop-rule sentinels the following
#        line happened to start on an identifier and the other half stopped
#        the run anyway. `good.dart` g is the shape where only the closing
#        gap can stop it: a path literal that closes on a comma with the next
#        line BEGINNING on a quote.
#
# Both directions are pinned in `--self-test`: `bad.dart` d/e/f are the
# violating wrapped shapes (one `$name`, one `${expr}`, one behind a comment),
# `good.dart` d is the wrapped ENCODED shape, and `good.dart` e/f/g/h are the
# quiet sentinels — stop rule, stop rule, carried-gap stop rule, and the
# same-line unrelated `$`.
#
# WHAT IT FLAGS
# -------------
#   PASS A — `Uri.encodeComponent` appearing INSIDE an `/api/v1/…` path
#   literal. This is the shape the finding named: four sites
#   (`salon_repository.dart` ×2, `master_repository.dart` ×2) reached for the
#   bare encoder, which silently lets `..`/`.` through. `Uri.encodeComponent`
#   elsewhere is untouched — `routing/route_names.dart` uses it for go_router
#   LOCATIONS, which never reach Dio and have no normalizePath step.
#
#   PASS B — a `$name` / `${expr}` interpolation inside an `/api/v1/…` path
#   literal whose value the file never proved encoded. "Proved encoded" means
#   one of exactly two spellings:
#       • inline           — `${encodePathSegment(id, 'id', logTag: _tag)}`
#       • pre-encoded local — `final x = encodePathSegment(...);` … `'…/$x/…'`
#   The second is the dominant shape in this repo — the encode is written
#   ABOVE the `try` at every site — so a gate that only accepted the inline
#   form would have been useless. (That placement is STYLISTIC, not
#   load-bearing: every hardened site opens with `on Failure { rethrow; }`, so
#   the encode throws before any request is issued wherever it is written. See
#   finding D1, 2026-09-17. The gate does not care either way — it accepts
#   both spellings.)
#
# WHY NO ALLOW-LIST FILE
# ----------------------
# Deliberate. A line-pinned allow-list is exactly what rotted for
# `.keepalive_family_invalidation_allow` (read its header: rows carrying four
# generations of "line renumbered from …" scars). Both accepted spellings above
# are derivable from the file's own text, so there is nothing legitimate left to
# exempt — if this gate fires, the fix is `encodePathSegment`, not a new row.
#
# SCOPE
# -----
# `lib/`, minus `lib/api/` (generated — regenerated wholesale by
# `scripts/regenerate_api.sh`; a finding there is fixed in the backend's
# OpenAPI spec, never by hand-editing the output).
#
# Usage:
#   ./scripts/forbid_unencoded_path_interpolation.sh
#   ./scripts/forbid_unencoded_path_interpolation.sh --self-test

set -euo pipefail

self="$(basename "$0")"
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"

# ---------------------------------------------------------------------------
# scan_root <root> <lib-subdir>
#   Prints one `path:line: <reason>` per violation found under
#   <root>/<lib-subdir>. Exits 0 always — the CALLER decides what a hit means
#   (a violation in normal mode, the expected outcome in the self-test).
#
# The whole check is one awk program so the "variables this file proved
# encoded" set and the literal scan share a single pass per file.
# ---------------------------------------------------------------------------
scan_root() {
  local root="$1" sub="$2"
  local dir="$root/$sub"
  [ -d "$dir" ] || return 0

  # Pre-filter with grep so awk only opens the handful of files that can
  # possibly hold a hand-built path, then run awk ONE FILE AT A TIME with a
  # plain `END` block. Deliberately NOT gawk's `ENDFILE` over an xargs batch:
  # `ENDFILE` is a gawk extension and Ubuntu's default awk is mawk, where the
  # bare word evaluates to an unset variable — the whole verdict block would
  # be dead and this gate would exit 0 having checked nothing. That is the
  # exact silent-gap failure mode verify_guards.sh's sentinel contract exists
  # to catch, so it is avoided by construction rather than asserted around.
  local f relpath
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    relpath="${f#"$root"/}"
    awk -v RELPATH="$relpath" -v Q="'" '
    # ---- judge ONE STRING LITERAL of a path expression ----------------------
    # [text] is the LITERAL BODY, never the physical line. Scoping it to the
    # literal is the whole point (2026-09-17, cycle-3 finding G2): a
    # whole-line scan flags an unrelated dollar that merely SHARES a line with
    # an already-encoded path, e.g. a queryParameters map beside it on one
    # line — and a guard that cries wolf gets disabled, which is strictly
    # worse than the blind spot G1 closes. Pinned by good.dart h.
    #
    # [lno] is still the PHYSICAL line, so a violation is reported where the
    # dollar actually is rather than on the run head.
    function judge(lno, text,    rest, p, close_at, expr, name, tok) {
      if (index(text, "Uri.encodeComponent") > 0) {
        printf "%s:%d: PASS A - bare Uri.encodeComponent in an /api/v1/ path literal; it does NOT escape \".\", so \"..\" survives into Dio normalizePath(). Use encodePathSegment(value, \"name\", logTag: _tag).\n", RELPATH, lno
        return
      }

      rest = text
      while ((p = index(rest, "$")) > 0) {
        rest = substr(rest, p + 1)
        if (substr(rest, 1, 1) == "{") {
          close_at = index(rest, "}")
          expr = (close_at > 1) ? substr(rest, 2, close_at - 2) : rest
          # Inline, the sanctioned spelling.
          if (expr ~ /^[ \t]*encodePathSegment\(/) continue
          # Otherwise the whole expression must BE a proven-encoded local:
          # `${a.b}` and `${f(x)}` are never one, so both fall through on
          # purpose.
          if (expr ~ /^[A-Za-z0-9_]+[ \t]*$/) {
            name = expr
            sub(/[ \t]+$/, "", name)
            if (name in encoded) continue
          }
          printf "%s:%d: PASS B - \"${%s}\" is interpolated into an /api/v1/ path literal but this file never routes it through encodePathSegment.\n", RELPATH, lno, expr
        } else {
          split(rest, tok, /[^A-Za-z0-9_]+/)
          name = tok[1]
          if (name == "") continue
          if (name in encoded) continue
          printf "%s:%d: PASS B - \"$%s\" is interpolated into an /api/v1/ path literal but this file never routes it through encodePathSegment.\n", RELPATH, lno, name
        }
      }
    }

    # ---- collect: names this file assigns from encodePathSegment ----------
    # Matches `final x =`, `final String x =`, `var x =`, `x =` — the leading
    # keyword is optional because only the NAME immediately left of the `=`
    # matters.
    /=[ \t]*encodePathSegment\(/ {
      head = $0
      sub(/=[ \t]*encodePathSegment\(.*$/, "", head)
      sub(/[^A-Za-z0-9_$]+$/, "", head)
      n = split(head, parts, /[^A-Za-z0-9_$]+/)
      if (n > 0 && parts[n] != "") encoded[parts[n]] = 1
    }

    # ---- tokenise one physical line into its STRING LITERALS ---------------
    # Fills lits[1..n] with each literal BODY (the text between the quotes,
    # dollar-brace interpolations left intact) and gaps[1..n] with whatever
    # separated it from the literal before — CARRY-IN included, so the comma
    # that CLOSES a wrapped path on the line above is seen as part of the gap
    # on the line below. Sets the global CARRY to the trailing text after the
    # last literal, for the next line to inherit.
    #
    # Quote-aware in the ONE way Dart requires: a dollar-brace interpolation
    # may itself contain string literals using the SAME quote character —
    # the sanctioned inline encodePathSegment spelling in this repo does
    # exactly that — so a closing quote only counts at brace depth 0.
    function scanline(text, carry, lits, gaps,
                      n, L, j, c, q, ch, body, depth, gap) {
      n = 0; gap = carry; L = length(text); j = 1
      while (j <= L) {
        c = substr(text, j, 1)
        if (c == Q || c == "\"") {
          q = c; j++; body = ""; depth = 0
          while (j <= L) {
            ch = substr(text, j, 1)
            if (ch == "\\") {
              body = body ch substr(text, j + 1, 1); j += 2; continue
            }
            if (depth == 0 && ch == q) { j++; break }
            if (ch == "$" && substr(text, j + 1, 1) == "{") {
              depth++; body = body "${"; j += 2; continue
            }
            if (depth > 0 && ch == "{") depth++
            if (depth > 0 && ch == "}") depth--
            body = body ch
            j++
          }
          n++; lits[n] = body; gaps[n] = gap; gap = ""
        } else {
          gap = gap c; j++
        }
      }
      CARRY = gap
      return n
    }

    # ---- buffer: EVERY line, plus whether it is a comment ------------------
    # Buffered rather than judged in place for two reasons. (1) The `encoded`
    # set is only complete at EOF — a `final x = encodePathSegment(...)` may
    # sit below its own use site, or in another method entirely, and file
    # order must not change the verdict. (2) A path literal is not a line:
    # `dart format` breaks one past 80 columns into ADJACENT STRING LITERALS
    # on consecutive lines, which is how `location_repository.dart` writes
    # both of its cascade reads. A line-at-a-time scan cannot see a `/api/v1/`
    # prefix and a `$id` that landed on different lines — it reported OK on
    # exactly that shape until 2026-09-17.
    {
      raw[FNR] = $0

      stripped = $0
      sub(/^[ \t]*/, "", stripped)
      # Comment lines (`//`, `///`, and the ` * ` of a block comment) describe
      # the shapes rather than issuing them — path_segment.dart s own doc
      # quotes `/api/v1/bookings/salon/$salonId` verbatim as the example of
      # what NOT to do, and must not be flagged for saying so.
      iscomment[FNR] = ((stripped ~ /^\/\//) || (stripped ~ /^\*/))

      nlines = FNR
    }

    END {
      # Walk each path expression as a RUN OF ADJACENT STRING LITERALS, not as
      # a run of lines (2026-09-17, cycle-3 findings G1/G2/G3). Two literals
      # belong to the same run when NOTHING but whitespace separates them —
      # which is Dart own adjacent-string-literal concatenation rule, and is
      # the single stop rule: the comma that closes a wrapped path lands in
      # the NEXT literal gap (carried across the line break by CARRY), so the
      # mapper: / queryParameters: argument beneath it, with its own unrelated
      # dollar, is never dragged in. good.dart e/f/g are its sentinels — g
      # specifically fails if that carried gap stops being consulted, which
      # the previous line-tail rule had no sentinel for at all.
      #
      # A COMMENT LINE IS TRANSPARENT to a run. dart format PRESERVES
      # comments, so a // line between two adjacent literals is a
      # format-stable shape; the previous rule terminated the group on it, and
      # the continuation then failed the head /api/v1/ test and was never
      # judged at all. bad.dart f is that sentinel.
      for (i = 1; i <= nlines; i++) {
        # Already judged as the continuation of an earlier run — never open a
        # second run on it, or a `$` on a shared line is reported twice.
        if (consumed[i]) continue
        if (iscomment[i]) continue
        if (index(raw[i], "/api/v1/") == 0) continue

        active = 0; CARRY = ""; j = i
        while (j <= nlines) {
          if (iscomment[j]) { consumed[j] = 1; j++; continue }
          n = scanline(raw[j], CARRY, lits, gaps)
          # No literal on this line means no adjacent literal to continue
          # into — the expression is over.
          if (n == 0) break
          lineactive = 0
          for (k = 1; k <= n; k++) {
            # Still inside the run only if whitespace alone separated this
            # literal from the last one. Otherwise the run ended, and this
            # literal opens a new one only if it carries /api/v1/ itself.
            if (!(active && gaps[k] ~ /^[ \t]*$/))
              active = (index(lits[k], "/api/v1/") > 0)
            if (active) { judge(j, lits[k]); lineactive = 1 }
          }
          if (j > i && lineactive) consumed[j] = 1
          if (!active) break
          j++
        }
      }
    }
    ' "$f"
  done < <(
    grep -rl --include='*.dart' -e '/api/v1/' "$dir" 2>/dev/null |
      grep -v "^$dir/api/" |
      sort
  )
}

# ---------------------------------------------------------------------------
# --self-test: prove the checker BOTH fires on each violating shape AND stays
# quiet on each sanctioned one. Exit 0 from a check that silently did nothing
# is precisely the failure mode verify_guards.sh's sentinel contract exists to
# catch, so both directions are asserted.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/lib/features/x/data" "$tmp/lib/api/src"

  cat >"$tmp/lib/features/x/data/bad.dart" <<'DART'
final class Bad {
  Future<void> a(String salonId) =>
      _dio.get<Object?>('/api/v1/salons/${Uri.encodeComponent(salonId)}/masters');
  Future<void> b(String cityId) =>
      _dio.get<Object?>('/api/v1/locations/cities/$cityId/districts');
  Future<void> c(Target t) =>
      _dio.get<Object?>('/api/v1/salons/${t.salonId}/services');

  // SENTINEL (2026-09-17) — the shape the line-at-a-time scan was blind to.
  // `dart format` wraps a path past 80 columns into ADJACENT STRING LITERALS,
  // so the `/api/v1/` prefix and the `$id` land on DIFFERENT lines. The
  // original scan short-circuited on `index($0, "/api/v1/") == 0` and never
  // saw line 12 at all, reporting OK on the exact shape the fix it was
  // written to guard uses at `location_repository.dart:96` and `:107`.
  Future<void> d(String oblastId) => _fetchList(
    path:
        '/api/v1/locations/oblasts/'
        '$oblastId'
        '/cities',
  );

  // SENTINEL — the `${expr}` half of the same wrap.
  Future<void> e(Target t) => _fetchList(
    path:
        '/api/v1/locations/cities/'
        '${t.cityId}'
        '/districts',
  );

  // SENTINEL (G1, 2026-09-17) — `dart format` PRESERVES comments, so a `//`
  // line sitting between two adjacent string literals is a FORMAT-STABLE
  // shape. The line-tail/line-lead grouper this replaced terminated the group
  // on it; the continuation below then failed the head's own `/api/v1/` test
  // and was never judged at all, so an unencoded id hid behind one comment.
  // A comment line is now transparent to a run.
  Future<void> f(String cityId) => _fetchList(
    path:
        '/api/v1/locations/cities/'
        // an interposed comment must NOT end the adjacent-literal run
        '$cityId'
        '/districts',
  );
}
DART

  cat >"$tmp/lib/features/x/data/good.dart" <<'DART'
/// Doc comments quoting the bad shape must NOT fire:
/// `/api/v1/bookings/salon/$salonId` was interpolating a raw segment.
final class Good {
  Future<void> a(String salonId) => _dio.get<Object?>(
        '/api/v1/bookings/salon/${encodePathSegment(salonId, 'salonId', logTag: _tag)}',
      );
  Future<void> b(String rawId) async {
    final segment = encodePathSegment(rawId, 'rawId', logTag: _tag);
    await _dio.get<Object?>('/api/v1/bookings/salon/$segment/booked-days');
  }
  Future<void> c(String rawId) async {
    // The encode is HOISTED BELOW its use site on purpose — a file-order
    // dependency would make this gate's verdict depend on formatting.
    await _dio.get<Object?>('/api/v1/salons/$later/masters');
    final later = encodePathSegment(rawId, 'rawId', logTag: _tag);
  }

  // SENTINEL — the wrapped-path shape, encoded INLINE. This is verbatim how
  // `location_repository.dart` and `service_repository.dart:684-685` spell it
  // after `dart format`, and the multi-line grouper must stay quiet on it.
  Future<void> d(String oblastId) => _fetchList(
    path:
        '/api/v1/locations/oblasts/'
        '${encodePathSegment(oblastId, 'oblastId', logTag: _tag)}'
        '/cities',
  );

  // SENTINEL — the grouper must STOP at the line that closes the path
  // expression. `'/oblasts',` ends on a comma, so the `$raw` in the NEXT
  // argument is a different expression entirely and must not be dragged in.
  Future<void> e(String raw) => _fetchList(
    path:
        '/api/v1/locations/'
        '/oblasts',
    operation: 'fetch-$raw',
  );

  // SENTINEL — same stop rule, single-line head: a path literal that closes
  // on its own line never absorbs the quoted argument beneath it.
  Future<void> f(String raw) => _dio.get<Object?>(
        '/api/v1/locations/oblasts',
        queryParameters: <String, Object?>{'q': '$raw'},
      );

  // SENTINEL (G3, 2026-09-17) — THE HALF OF THE STOP RULE THAT HAD NONE.
  // The path literal closes on a COMMA and the very next line BEGINS on a
  // quote, so only the closing-gap half of the adjacency rule can stop the
  // run here. `e` and `f` above do not cover it: in both, the following line
  // starts on an identifier, so the run stops for the other reason and
  // removing the gap check left --self-test green — in the fixture AND
  // against the real repo. Stop consulting the carried gap and `$raw` below
  // is judged as part of the path, which reddens `assert_miss good.dart`.
  Future<void> g(String raw) => _dio.post<Object?>(
        '/api/v1/locations/oblasts',
        '$raw',
      );

  // SENTINEL (G2, 2026-09-17) — AN UNRELATED `$` ON THE SAME PHYSICAL LINE.
  // `judge()` is scoped to the string LITERAL, not the line, so `$r` here —
  // a query value, not a path segment — must stay quiet while the encoded
  // `$seg` beside it passes. A whole-line scan reported `$r` as a PASS B
  // violation, and a guard that cries wolf gets disabled, which is worse
  // than any blind spot it closes. Format-stable: the call line is 76 cols.
  Future<void> h(String rawId, String r) async {
    final seg = encodePathSegment(rawId, 'rawId', logTag: _tag);
    await _dio.get<Object?>('/api/v1/x/$seg', queryParameters: {'q': '$r'});
  }
}
DART

  # Generated output is out of scope and must stay out of scope.
  cat >"$tmp/lib/api/src/generated.dart" <<'DART'
final r = '/api/v1/salons/${salonId}/masters';
DART

  out="$(scan_root "$tmp" lib)"

  fails=0
  assert_hit() {
    if ! grep -q -- "$1" <<< "$out"; then
      echo "SELF-TEST FAIL: expected a hit matching '$1'" >&2
      fails=1
    fi
  }
  assert_miss() {
    if grep -q -- "$1" <<< "$out"; then
      echo "SELF-TEST FAIL: unexpected hit matching '$1'" >&2
      fails=1
    fi
  }

  assert_hit 'bad.dart:3: PASS A'
  assert_hit 'bad.dart:5: PASS B'
  assert_hit 'bad.dart:7: PASS B'
  # Multi-line sentinels: the violation is reported on the PHYSICAL line that
  # carries the `$`, not on the group head, so a dev jumps straight to it.
  assert_hit 'bad.dart:18: PASS B - "\$oblastId"'
  assert_hit 'bad.dart:26: PASS B - "\${t.cityId}"'
  # G1 — an interposed `//` line must NOT end the adjacent-literal run.
  # Remove the comment-transparency branch in END and this one goes silent.
  assert_hit 'bad.dart:40: PASS B - "\$cityId"'
  # Covers the G3 (`good.dart` g) and G2 (`good.dart` h) sentinels too: both
  # are quiet shapes, so the single file-wide miss is exactly the assertion
  # they need.
  assert_miss 'good.dart'
  assert_miss 'lib/api/'

  if [ "$fails" -ne 0 ]; then
    echo "--- checker output was: ---" >&2
    printf '%s\n' "$out" >&2
    exit 1
  fi

  echo "SELF-TEST OK: $self"
  exit 0
fi

violations="$(scan_root "$repo" lib)"

if [ -n "$violations" ]; then
  echo "FAIL: hand-built /api/v1/ path literal(s) interpolating an id this file never routed through encodePathSegment."
  echo
  printf '%s\n' "$violations"
  echo
  echo "Fix: import 'package:beautica_mobile/core/network/path_segment.dart' (or the"
  echo "relative path) and wrap the id — encodePathSegment(id, 'id', logTag: _tag) —"
  echo "either inline in the literal or hoisted to a local ABOVE the request."
  echo
  echo "Uri.encodeComponent is NOT a substitute: it does not escape '.', so a bare"
  echo "'..' survives into Dio's Uri.parse(url).normalizePath(), which collapses"
  echo "dot-segments and retargets the request on the bearer-token-carrying Dio."
  echo "See lib/core/network/path_segment.dart."
  exit 1
fi

echo "OK: every hand-built /api/v1/ path literal in lib/ encodes its interpolated ids."
exit 0
