#!/usr/bin/env bash
# Page-title token single-source-of-truth gate (mobile-qa, 2026-08-22).
#
# THE REGRESSION THIS GUARDS
# --------------------------
# The four INDEPENDENT_MASTER bottom-nav tab-root screens («Мої послуги»,
# «Мої записи», «Графік роботи», «Мій профіль») rendered their page title at
# THREE different sizes before this gate existed: «Мої послуги» used
# `VelvetText.heading()` (21 sp) via a private `_ServicesAppBar`, «Мої
# записи» (and the archive screen sharing its header widget) used a one-off
# `VelvetText.masterBookingsTitle` (22 sp), while «Графік роботи»/«Мій
# профіль» used `VelvetText.subheading()` (14 sp) via the shared
# `VelvetTopBar`. The fix consolidated all of them onto ONE token,
# `VelvetText.pageTitle` (`lib/core/theme/velvet_text.dart`), and deleted the
# one-off `masterBookingsTitle`. Nothing STRUCTURAL stops the fork from
# happening again — a future edit could repoint any one of these call sites
# at `.heading()`/`.subheading()` again, or reintroduce a new one-off
# `TextStyle` token for a single screen's title. THIS gate is that
# structural ratchet.
#
# TWO RULES, BOTH GREP-SHAPED (this repo's existing scripts/forbid_*.sh
# idiom — no AST):
#
#   RULE A — no NEW "title"-shaped static token on VelvetText. A
#   `static (final )?TextStyle` field/method whose name contains "Title"
#   (case-sensitive on the capital T, so `pageTitle` itself and ordinary
#   words like `subheading` never match) anywhere in
#   `lib/core/theme/velvet_text.dart` is exactly the shape
#   `masterBookingsTitle` took — a per-screen one-off nobody meant to fork
#   the scale with. VelvetText legitimately has SIX pre-existing tokens
#   shaped this way for unrelated concerns (card titles, calendar nav
#   titles, passport section headings, ...) — baselined by name in
#   `scripts/.page_title_token_allow` (same allow-list idiom as
#   `forbid_inline_fontsize.sh`, whose ratchet also cannot start from zero
#   on this codebase). A name NOT on that list, and not `pageTitle` itself,
#   is a NEW one-off and is flagged.
#
#   RULE B — each of the FOUR known page-title call sites
#   (`velvet_top_bar.dart`, `services_list_screen.dart`,
#   `bookings_discovery_view.dart`, `master_archive_screen.dart`) must pass
#   `style: VelvetText.pageTitle` at its `title` render, not some other
#   `VelvetText.*` token. Anchored on the `title,` parameter immediately
#   followed by the `style:` line (a 2-line window, same-line or wrapped) —
#   specific enough to skip the OTHER legitimate `VelvetText.*` calls those
#   same files make for unrelated labels (e.g. `master_archive_screen.dart`
#   also legitimately calls `VelvetText.subheading()` for a section header
#   elsewhere — Rule B does not touch that line at all, only the one
#   anchored on `title,`).
#
# WHAT THIS DOES NOT CATCH (documented, not silently assumed)
# -------------------------------------------------------------
# A rename-and-refork under a name that does NOT contain "Title" (e.g. a new
# `VelvetText.screenHeading`) is invisible to Rule A, which keys on the
# substring. A FIFTH call site added for a future fifth tab-root screen is
# invisible to Rule B until this file's `title_sites` array is extended for
# it — the same "grows only when a new consumer is added" limitation
# `forbid_forked_calendar_grid.sh` documents for its own Rule C.
#
# Self-test: ./scripts/forbid_page_title_token_fork.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

velvet_text_file="lib/core/theme/velvet_text.dart"
canonical_token="pageTitle"
default_allow="$here/.page_title_token_allow"

# Rule B — every known page-title call site. Grows only when a new tab-root
# (or a screen sharing the same header widget, e.g. the archive screen)
# starts rendering a page title.
title_sites=(
  "lib/shared/widgets/velvet_top_bar.dart"
  "lib/features/services/presentation/services_list_screen.dart"
  "lib/features/booking/presentation/bookings_discovery_view.dart"
  "lib/features/booking/presentation/master_archive_screen.dart"
)

# ---------------------------------------------------------------------------
# scan <tree_root> <allow_file>
#   Emits one "RULE-X (...): <detail>" line per offender.
# ---------------------------------------------------------------------------
scan() {
  local tree_root="$1" allow="${2:-$default_allow}"
  local vt="$tree_root/$velvet_text_file"

  local -A ALLOW=()
  if [ -f "$allow" ]; then
    local raw stripped key
    while IFS= read -r raw; do
      stripped="${raw%%#*}"
      key="$(printf '%s' "$stripped" | tr -d '[:space:]')"
      [ -n "$key" ] && ALLOW["$key"]=1
    done < "$allow"
  fi

  # Rule A.
  if [ -f "$vt" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local name
      name="$(printf '%s' "$line" | grep -oE '[A-Za-z_][A-Za-z0-9_]*Title' | head -1)"
      if [ -n "$name" ] && [ "$name" != "$canonical_token" ] && [ -z "${ALLOW[$name]:-}" ]; then
        printf 'RULE-A (new title-shaped VelvetText token — fold into pageTitle, or baseline it in scripts/.page_title_token_allow if genuinely unrelated): %s:%s\n' \
          "$velvet_text_file" "$line"
      fi
    done < <(grep -nE 'static[[:space:]]+(final[[:space:]]+)?TextStyle[[:space:]]+[A-Za-z_][A-Za-z0-9_]*Title\b' "$vt" 2>/dev/null || true)
  fi

  # Rule B.
  local f rel match token
  for f in "${title_sites[@]}"; do
    [ -f "$tree_root/$f" ] || continue
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      token="$(printf '%s' "$match" | grep -oE 'VelvetText\.[A-Za-z_][A-Za-z0-9_]*' | sed 's/^VelvetText\.//')"
      if [ -n "$token" ] && [ "$token" != "$canonical_token" ]; then
        printf 'RULE-B (title call site not on VelvetText.pageTitle — found VelvetText.%s): %s\n' \
          "$token" "$f"
      fi
    done < <(grep -Pzo 'title,[ \t]*\n?[ \t]*style:[ \t]*VelvetText\.[A-Za-z_][A-Za-z0-9_]*' "$tree_root/$f" 2>/dev/null | tr '\0' '\n')
  done
}

# ---------------------------------------------------------------------------
# Self-test mode.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  # Isolated EMPTY allow-file — the self-test fixture's velvet_text.dart
  # never uses any of the real tree's six baselined names, so an empty list
  # keeps this run fully isolated from scripts/.page_title_token_allow.
  tmp_allow="$tmp/.page_title_token_allow"
  : > "$tmp_allow"

  # Legit velvet_text.dart — only the canonical token. Must NOT be flagged.
  mkdir -p "$tmp/$(dirname "$velvet_text_file")"
  cat > "$tmp/$velvet_text_file" <<'EOF'
abstract final class VelvetText {
  static TextStyle heading() => _headingStyle;
  static TextStyle subheading() => _subheadingStyle;
  static final TextStyle pageTitle = _subheadingStyle;
}
EOF

  # The four legit call sites — all on pageTitle. Must NOT be flagged.
  mkdir -p "$tmp/lib/shared/widgets"
  cat > "$tmp/lib/shared/widgets/velvet_top_bar.dart" <<'EOF'
Text(
  title,
  style: VelvetText.pageTitle,
)
EOF
  mkdir -p "$tmp/lib/features/services/presentation"
  cat > "$tmp/lib/features/services/presentation/services_list_screen.dart" <<'EOF'
title: Text(title, style: VelvetText.pageTitle),
Text(label, style: VelvetText.subheading()),
EOF
  mkdir -p "$tmp/lib/features/booking/presentation"
  cat > "$tmp/lib/features/booking/presentation/bookings_discovery_view.dart" <<'EOF'
Text(
  title,
  style: VelvetText.pageTitle,
)
EOF
  cat > "$tmp/lib/features/booking/presentation/master_archive_screen.dart" <<'EOF'
Text(
  title,
  style: VelvetText.pageTitle,
)
Text(label, style: VelvetText.subheading()),
EOF

  out="$(scan "$tmp" "$tmp_allow")"
  fail=0
  if [ -n "$out" ]; then
    echo "SELF-TEST FAIL: the all-canonical fixture tree flagged offenders:"
    echo "$out"
    fail=1
  fi

  # Now introduce a Rule A offender: a second title-shaped token.
  cat > "$tmp/$velvet_text_file" <<'EOF'
abstract final class VelvetText {
  static TextStyle heading() => _headingStyle;
  static TextStyle subheading() => _subheadingStyle;
  static final TextStyle pageTitle = _subheadingStyle;
  static final TextStyle masterBookingsTitle = _headingStyle.copyWith(fontSize: 22);
}
EOF
  out_a="$(scan "$tmp" "$tmp_allow")"
  if ! printf '%s\n' "$out_a" | grep -qF "RULE-A"; then
    echo "SELF-TEST FAIL: expected a RULE-A offender for the reintroduced masterBookingsTitle token"
    fail=1
  fi
  # Restore the canonical velvet_text.dart before the Rule B probe.
  cat > "$tmp/$velvet_text_file" <<'EOF'
abstract final class VelvetText {
  static TextStyle heading() => _headingStyle;
  static TextStyle subheading() => _subheadingStyle;
  static final TextStyle pageTitle = _subheadingStyle;
}
EOF

  # Now introduce a Rule B offender: services list repointed at heading().
  cat > "$tmp/lib/features/services/presentation/services_list_screen.dart" <<'EOF'
title: Text(title, style: VelvetText.heading()),
Text(label, style: VelvetText.subheading()),
EOF
  out_b="$(scan "$tmp" "$tmp_allow")"
  if ! printf '%s\n' "$out_b" | grep -qF "RULE-B (title call site not on VelvetText.pageTitle — found VelvetText.heading): lib/features/services/presentation/services_list_screen.dart"; then
    echo "SELF-TEST FAIL: expected a RULE-B offender for services_list_screen.dart repointed at heading()"
    echo "--- got ---"
    printf '%s\n' "$out_b"
    fail=1
  fi
  # The sibling subheading() line (a legitimate OTHER use) must NOT be
  # flagged by Rule B — proves the anchor is scoped to the `title,` site.
  if printf '%s\n' "$out_b" | grep -qF "VelvetText.subheading"; then
    echo "SELF-TEST FAIL: Rule B flagged an unrelated VelvetText.subheading() call — anchor is too broad"
    fail=1
  fi

  if [ "$fail" -ne 0 ]; then
    exit 1
  fi

  echo "SELF-TEST PASS: a reintroduced title-shaped VelvetText token (Rule A) and"
  echo "                a title call site repointed away from pageTitle (Rule B)"
  echo "                are both flagged; the canonical tree and unrelated"
  echo "                VelvetText.* calls in the same files are not."
  echo "SELF-TEST OK: forbid_page_title_token_fork.sh"
  exit 0
fi

# ---------------------------------------------------------------------------
# Real run over the working tree.
# ---------------------------------------------------------------------------
offenders="$(scan "$root")"

if [ -n "$offenders" ]; then
  echo "Page-title token single-source-of-truth gate failed:"
  echo "$offenders"
  echo
  echo "Every INDEPENDENT_MASTER tab-root screen title must render through"
  echo "VelvetText.pageTitle (lib/core/theme/velvet_text.dart) — the single"
  echo "token that replaced three diverged sizes (heading() 21sp, the deleted"
  echo "masterBookingsTitle 22sp, subheading() 14sp). Repoint the call site at"
  echo "VelvetText.pageTitle, or fold a new one-off token into it instead of"
  echo "adding a second title-shaped token."
  exit 1
fi

exit 0
