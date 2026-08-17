#!/usr/bin/env bash
# CLIENT branch-root chrome gate (2026-06-24 wordmark-jump safeguard).
#
# THE FRAGILITY THIS GUARDS
# -------------------------
# The CLIENT shell is a `StatefulShellRoute` whose branch roots
# (HomeHub / Favorites / Search / Bookings / Passport) all sit BELOW a single
# shared chrome: `ClientTopBar` (the brand wordmark + notification bell) and
# `ClientBottomNav`, both mounted ONCE by `ClientShell`. If a branch-root
# screen instead constructs its OWN `Scaffold(appBar: …)` or a bare `AppBar(`
# — or any bespoke header that is not the shared `ClientTopBar` — the wordmark
# is re-laid-out per branch and "jumps" a few pixels when the user hops tabs
# (different SafeArea / padding / status-bar handling per screen). A widget
# test now asserts the wordmark stays pixel-stable across branch hops; THIS
# gate prevents the regression at source so the test never has to catch it.
#
# THE RULE
# --------
# A CLIENT branch-root screen file MUST NOT introduce an `AppBar` (whether via
# `Scaffold(appBar:`, a bare `AppBar(`, or `SliverAppBar(`). Per-screen top
# chrome must reuse the shared `ClientTopBar`. A legitimate exception (e.g. a
# branch that genuinely needs its own bar AND has been reviewed for the jump)
# is unblocked with a `// client-chrome-ok: <reason>` comment on the same line
# or the line directly above — never by weakening the regex.
#
# SCOPE
# -----
# The known CLIENT `StatefulShellBranch` root screen files, enumerated below
# (ROOTS). These are the files wired as branch roots in
# `lib/routing/app_router.dart`. When a new branch root is added, append its
# file here so the gate keeps covering the whole shell. Generated `*.g.dart`
# is never a screen file, so no exclusion is needed.
#
# This is the CI hard-gate (run from `.github/workflows/pr-validate.yml`); it
# can also be run locally before pushing.
# Self-test:  ./scripts/forbid_client_branch_appbar.sh --self-test

set -euo pipefail

# ---------------------------------------------------------------------------
# CLIENT branch-root screen files — the StatefulShellBranch roots mounted by
# ClientShell in lib/routing/app_router.dart. ClientShell itself owns the
# shared ClientTopBar + ClientBottomNav, so it is intentionally NOT a root
# here (it is the chrome, not a branch).
# ---------------------------------------------------------------------------
ROOTS=(
  "lib/features/home/presentation/home_hub_screen.dart"            # HomeHubScreen
  "lib/features/shell/presentation/branch_placeholders.dart"      # ClientFavoritesPlaceholderScreen + ClientBookingsPlaceholderScreen
  "lib/features/discovery/presentation/search_filters_screen.dart" # ClientSearchScreen
  "lib/features/passport/presentation/passport_screen.dart"       # PassportScreen
)

# Match: a Scaffold appBar slot, a bare AppBar(...) constructor, or a
# SliverAppBar(...). `appBar:` covers `Scaffold(appBar:` across line breaks;
# the bare `AppBar(` / `SliverAppBar(` cover a header built outside a Scaffold
# slot. `[(]` is the literal call-paren in POSIX ERE.
pattern='(appBar:|(Sliver)?AppBar[(])'
# Annotation: `// client-chrome-ok:` (any leading whitespace before the `//`).
annotation='[/][/][[:space:]]*client-chrome-ok:'

# ---------------------------------------------------------------------------
# scan_file <path>
#   Emits "<path>:<line>:<text>" for each un-annotated AppBar offender.
#   Comment detection mirrors the other forbid_*.sh gates: a match is treated
#   as commented-out only when the line's FIRST non-space token is `//`, or a
#   `//` precedes the match in string-stripped text (so a `//` inside a string
#   literal cannot mask a real AppBar). The `// client-chrome-ok:` allow-list
#   runs on the ORIGINAL (un-stripped) text.
# ---------------------------------------------------------------------------
scan_file() {
  awk -v file="$1" -v pat="$pattern" -v ann="$annotation" '
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
    {
      if ($0 ~ pat) {
        # (1a) Genuine comment line? First non-space token is `//`.
        firsttok = $0
        sub(/^[[:space:]]+/, "", firsttok)
        if (firsttok ~ /^[/][/]/) { prev = $0; next }
        # (1b) `//` comment after CODE masking the match? Test string-free text.
        codeonly = strip_strings($0)
        where = match(codeonly, pat)
        if (where > 0) {
          before = substr(codeonly, 1, where - 1)
          if (before ~ /[/][/]/) { prev = $0; next }
        }
        # (2) Annotated client-chrome-ok on this line or the line directly above.
        if ($0 ~ ann) { prev = $0; next }
        if (prev ~ ann) { prev = $0; next }
        printf "%s:%d:%s\n", file, NR, $0
      }
      prev = $0
    }
  ' "$1"
}

# ---------------------------------------------------------------------------
# Self-test mode: assert the gate flags a raw AppBar and passes an annotated
# one, then exit. Pure bash + awk, no extra dependency.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  printf '%s\n' \
    "    return Scaffold(appBar: AppBar(title: Text('x')), body: b);" \
    "    return const AppBar();" \
    "    // client-chrome-ok: legacy detail page, reviewed for jump" \
    "    return Scaffold(appBar: AppBar());" \
    "    return Scaffold(body: ClientTopBar());" \
    > "$tmp"
  out="$(scan_file "$tmp")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"
  if [ "$flagged" -ne 2 ]; then
    echo "SELF-TEST FAIL: expected 2 offenders, got $flagged"
    printf '%s\n' "$out"
    exit 1
  fi
  echo "SELF-TEST PASS: 2 raw AppBars flagged, annotated + ClientTopBar lines clean"
  echo "SELF-TEST OK: forbid_client_branch_appbar.sh"
  exit 0
fi

offenders="$(
  for f in "${ROOTS[@]}"; do
    [ -f "$f" ] || continue
    scan_file "$f"
  done
)"

if [ -n "$offenders" ]; then
  echo "AppBar / bespoke top chrome found in a CLIENT branch-root screen:"
  echo "$offenders"
  echo
  echo "CLIENT branch roots sit below the shared ClientTopBar mounted ONCE by"
  echo "ClientShell. A per-screen Scaffold(appBar:)/AppBar()/SliverAppBar()"
  echo "re-lays-out the wordmark and makes it jump on tab hop. Reuse the shared"
  echo "ClientTopBar instead. If this bar is genuinely required and reviewed for"
  echo "the jump, annotate it:"
  echo "    // client-chrome-ok: <why this bespoke bar is needed and jump-safe>"
  echo "    appBar: AppBar(...),"
  exit 1
fi

exit 0
