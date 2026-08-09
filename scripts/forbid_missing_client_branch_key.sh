#!/usr/bin/env bash
# Client shell branch-Key continuity gate (2026-07-31).
#
# THE BUG THIS GUARDS
# -------------------
# The CLIENT 5-tab shell's branch screens each expose a stable, locale-neutral
# `client-branch-<slug>` `Key`. Every shell E2E targets those keys to assert
# WHICH branch is showing (text would couple the assertions to Ukrainian copy).
# The keys were introduced by the placeholder screens in
# `lib/features/shell/presentation/branch_placeholders.dart`, and the convention
# is that when a REAL screen supersedes a placeholder it CARRIES THE KEY
# FORWARD.
#
# In the Phase 13.7 placeholder → `HomeHubScreen` migration that did not happen:
# `client-branch-home` was dropped while every sibling branch kept theirs. The
# result was two shell flows quietly red — and, worse, red for a reason that
# looked like a navigation bug rather than a missing key.
#
# The convention was written down. `passport_screen.dart:119-124` states it in
# a five-line comment, correctly, right where a reader would see it. Prose did
# not hold. That is the whole argument for this gate.
#
# WHY THE FAST TEST TIER DID NOT CATCH IT
# ---------------------------------------
# `test/features/shell/client_shell_test.dart:588` DOES assert
# `find.byKey(Key('client-branch-home'))` — but it pumps
# `ClientHomePlaceholderScreen`, the PLACEHOLDER. That assertion kept passing
# forever while the real `HomeHubScreen` shipped without the key. A grep is the
# right tool here precisely because the widget tier was structurally blind: it
# was testing the screen being replaced, not the replacement.
#
# THE RULE (derived from the router — no hand-maintained allow-list)
# ------------------------------------------------------------------
# For each of the 5 CLIENT `StatefulShellBranch`es declared in
# `lib/routing/app_router.dart`, resolve the screen widget its `GoRoute`
# actually builds:
#   * still a `*PlaceholderScreen`  → branch not yet superseded, nothing to
#     check (the placeholder carries the key by construction);
#   * a real screen                 → the file declaring that widget MUST
#     contain the `client-branch-<slug>` key literal.
#
# Deriving the mapping from the router means this gate needs no maintenance
# when a branch graduates: swap the placeholder for a real screen in
# app_router.dart and the gate starts demanding the key on the new screen the
# same day.
#
# KNOWN LIMITATION — branch → screen resolution (accepted, INFO)
# --------------------------------------------------------------
# `branch_screen` takes the FIRST `<Name>Screen` token between a branch's
# `navigatorKey:` line and the next `StatefulShellBranch(`. If a branch ever
# declares TWO screens in that span (e.g. a root plus a nested child route
# both named `*Screen`), this resolves the ROOT — which is the one that owns
# the branch key, so it is right for this gate's purpose — but a branch whose
# FIRST mentioned screen is not its root would resolve wrongly. No such branch
# exists today (verified 2026-07-31: all 5 declare exactly one screen at the
# branch root, with `/bookings`' children declared further down). If you add
# one, prefer keeping the branch-root screen first over rewriting this into a
# Dart parser.
#
# WHY THE MASTER SURFACE IS NOT COVERED (and the tripwire that revisits it)
# ------------------------------------------------------------------------
# The obvious extension — "do the same for the master tabs" — is unsound as of
# 2026-07-31, for three independent structural reasons:
#   1. The master surface is NOT a StatefulShellRoute. `app_router.dart:844-853`
#      spells this out: its four "tabs" are four FLAT top-level routes that each
#      render their own `VelvetBottomNavBar` and navigate by `context.go`. There
#      are no `StatefulShellBranch`es to enumerate and no branch navigator keys.
#   2. There are NO master placeholder screens. Every `*PlaceholderScreen` in
#      `lib/` is a CLIENT one (`ClientHome/Favorites/Search/Bookings/Passport`),
#      plus the unrelated `BookingConfirmPlaceholderScreen`. The hazard this
#      gate exists for — a real screen superseding a placeholder and dropping
#      the key it should have inherited — has no master-side instance because
#      no master screen was ever a placeholder.
#   3. There is no `master-branch-*` key convention at all. Master screens are
#      located in tests by widget TYPE and by content-level keys
#      (`master-profile-name`, …), so there is no branch key to lose.
# Enforcing a convention that does not exist would mean inventing one and then
# flagging every master screen for not following it — noise, not a gate.
#
# That reasoning is TIME-DEPENDENT, so it is enforced rather than merely
# asserted: the tripwire below fails the moment `lib/` grows a
# `master-branch-*` key literal or a `Master*PlaceholderScreen`. Either means
# the master surface has adopted the convention and THIS gate must be extended
# to cover it — the comment cannot silently rot into a lie.
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing.
# Self-test:  ./scripts/forbid_missing_client_branch_key.sh --self-test

set -euo pipefail

router='lib/routing/app_router.dart'

# slug : the k<Name>Branch constant used as the branch's navigatorKey index.
branches=(
  "home:kClientHomeBranch"
  "favorites:kClientFavoritesBranch"
  "search:kClientSearchBranch"
  "bookings:kClientBookingsBranch"
  "passport:kClientPassportBranch"
)

# ---------------------------------------------------------------------------
# branch_screen <router-file> <branch-const> → the widget class the branch
# builds, by slicing from that branch's navigatorKey line to the start of the
# next StatefulShellBranch and taking the first `<Name>Screen` mentioned.
# ---------------------------------------------------------------------------
branch_screen() {
  local file="$1" const="$2"
  awk -v c="$const" '
    index($0, "clientBranchNavigatorKeys[" c "]") { inblk = 1; next }
    inblk && /StatefulShellBranch\(/ { exit }
    inblk {
      if (match($0, /[A-Z][A-Za-z0-9_]*Screen/)) {
        print substr($0, RSTART, RLENGTH); exit
      }
    }
  ' "$file"
}

# ---------------------------------------------------------------------------
# check <router-file> <lib-root> → prints one diagnostic line per offender.
# ---------------------------------------------------------------------------
check() {
  local file="$1" libroot="$2" slug const screen decl
  for entry in "${branches[@]}"; do
    slug="${entry%%:*}"
    const="${entry##*:}"

    screen="$(branch_screen "$file" "$const")"
    if [ -z "$screen" ]; then
      echo "$slug: could not resolve a screen widget for $const in $file"
      continue
    fi

    # Placeholder-served branch: nothing to carry forward yet.
    case "$screen" in *PlaceholderScreen) continue ;; esac

    decl="$(grep -rl "class $screen\b" "$libroot" --include='*.dart' 2>/dev/null | head -1 || true)"
    if [ -z "$decl" ]; then
      echo "$slug: $screen is routed but its declaring file was not found"
      continue
    fi

    # Match the KEY CONSTRUCTION, not any mention: home_hub_screen.dart
    # discusses `client-branch-home` in a doc comment, so a bare substring
    # grep stays GREEN on the very bug this gate exists to catch (verified —
    # the first draft of this script did exactly that).
    grep -Eq "Key\\([[:space:]]*'client-branch-$slug'[[:space:]]*\\)" "$decl" \
      || echo "$slug: $screen ($decl) is missing Key('client-branch-$slug')"
  done
}

# ---------------------------------------------------------------------------
# Self-test mode.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/lib"

  # A router with all 5 branches: home + passport real, the rest placeholders.
  cat > "$tmp/router.dart" <<'EOF'
StatefulShellRoute.indexedStack(
  branches: [
    StatefulShellBranch(
      navigatorKey: clientBranchNavigatorKeys[kClientHomeBranch],
      routes: [GoRoute(builder: (c, s) => const HomeHubScreen())],
    ),
    StatefulShellBranch(
      navigatorKey: clientBranchNavigatorKeys[kClientFavoritesBranch],
      routes: [GoRoute(builder: (c, s) => const ClientFavoritesPlaceholderScreen())],
    ),
    StatefulShellBranch(
      navigatorKey: clientBranchNavigatorKeys[kClientSearchBranch],
      routes: [GoRoute(builder: (c, s) => const ClientSearchPlaceholderScreen())],
    ),
    StatefulShellBranch(
      navigatorKey: clientBranchNavigatorKeys[kClientBookingsBranch],
      routes: [GoRoute(builder: (c, s) => const ClientBookingsPlaceholderScreen())],
    ),
    StatefulShellBranch(
      navigatorKey: clientBranchNavigatorKeys[kClientPassportBranch],
      routes: [GoRoute(builder: (c, s) => const PassportScreen())],
    ),
  ],
)
EOF

  # The exact bug: the real home screen dropped the key.
  cat > "$tmp/lib/home_hub_screen.dart" <<'EOF'
class HomeHubScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) => const _HomeHubBody();
}
EOF
  # The compliant sibling that carried its key over.
  cat > "$tmp/lib/passport_screen.dart" <<'EOF'
class PassportScreen extends ConsumerStatefulWidget {}
class _PassportScreenState extends ConsumerState<PassportScreen> {
  @override
  Widget build(BuildContext context) =>
      Scaffold(key: const Key('client-branch-passport'));
}
EOF

  out="$(check "$tmp/router.dart" "$tmp/lib")"

  echo "$out" | grep -q "^home: HomeHubScreen" || {
    echo "SELF-TEST FAIL: the key-less real home screen was not flagged"; exit 1; }
  echo "$out" | grep -q "^passport:" && {
    echo "SELF-TEST FAIL: the compliant passport screen was flagged"; exit 1; }
  echo "$out" | grep -qE "^(favorites|search|bookings):" && {
    echo "SELF-TEST FAIL: a placeholder-served branch was flagged"; exit 1; }

  echo "SELF-TEST PASS: the superseding screen that dropped its key is flagged;"
  echo "                the compliant screen and placeholder-served branches are clean."
  exit 0
fi

# ---------------------------------------------------------------------------
# master_tripwire <lib-root> → fires when the master surface adopts the
# branch-key / placeholder convention this gate deliberately does not cover.
# See "WHY THE MASTER SURFACE IS NOT COVERED" in the header.
# ---------------------------------------------------------------------------
master_tripwire() {
  local libroot="$1"
  grep -rEl "master-branch-[a-z]" "$libroot" --include='*.dart' 2>/dev/null \
    | sed 's/^/  master-branch-* key literal in: /' || true
  grep -rEl "class Master[A-Za-z0-9_]*PlaceholderScreen" "$libroot" \
    --include='*.dart' 2>/dev/null \
    | sed 's/^/  master placeholder screen in: /' || true
}

tripped="$(master_tripwire lib)"
if [ -n "$tripped" ]; then
  echo "The master surface has adopted a branch-key / placeholder convention:"
  echo "$tripped"
  echo
  echo "This gate covers the CLIENT shell only, on the documented grounds that"
  echo "the master surface is not a StatefulShellRoute, has no placeholder"
  echo "screens, and has no branch-key convention (see this script's header)."
  echo "One of those is no longer true, so the same placeholder->real-screen"
  echo "key-drop hazard now applies there. EXTEND this gate to cover the master"
  echo "routes, then update the header's reasoning."
  exit 1
fi

offenders="$(check "$router" lib)"

if [ -n "$offenders" ]; then
  echo "CLIENT shell branch screen missing its client-branch-* Key:"
  echo "$offenders"
  echo
  echo "When a real screen supersedes a branch PLACEHOLDER it must carry the"
  echo "placeholder's stable Key forward — every shell E2E targets those keys to"
  echo "assert which branch is showing (text would couple them to UA copy)."
  echo "Phase 13.7 dropped client-branch-home in exactly this way and left two"
  echo "shell flows quietly red. Note the widget tier does NOT cover this: its"
  echo "branch-key assertions pump the PLACEHOLDER, not the replacement."
  echo
  echo "Add to the superseding screen's root widget:"
  echo "    key: const Key('client-branch-<slug>'),"
  exit 1
fi

exit 0
