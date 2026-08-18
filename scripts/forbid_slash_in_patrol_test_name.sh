#!/usr/bin/env bash
# Forbid '/' inside a patrolTest(...) description.
#
# WHY THIS EXISTS
# ---------------
# AndroidTestOrchestrator writes a per-test output file whose NAME is derived
# from the test description, via Context.openFileOutput(). That API rejects any
# filename containing a path separator, so a single '/' anywhere in a patrol
# test's description kills the orchestrator PROCESS:
#
#   E/AndroidRuntime: FATAL EXCEPTION: AndroidTestOrchestrator
#   java.lang.IllegalArgumentException:
#     File ...[... navigates to the /home client shell ...].txt
#     contains a path separator
#       at android.app.ContextImpl.makeFilename(ContextImpl.java:3574)
#       at android.app.ContextImpl.openFileOutput(ContextImpl.java:752)
#       at androidx.test.orchestrator.AndroidTestOrchestrator.getOutputStream
#       at androidx.test.orchestrator.AndroidTestOrchestrator.executeNextTest
#
# The failure is nasty because of how it PRESENTS. Gradle reports only
# "Instrumentation run failed due to Process crashed", patrol's own summary
# shows ZERO failed assertions, and the tests that already ran are reported as
# passing. On 2026-07-22 that was mistaken for the (real, separate) emulator
# device-loss issue and cost a full round of diagnosis before the logcat
# artifact showed the actual exception.
#
# It is also silent locally: `flutter analyze`, `dart format` and the whole
# host-side `flutter test` suite are all completely green, because nothing in
# that path ever goes near the orchestrator. Only a real patrol run on a device
# surfaces it — which is why it needs a static gate.
#
# Naming a patrol test after a route is the obvious way to hit this ('/home',
# '/master/profile', '/bookings/:id'), and so is citing a file path in a skip
# reason. Say "the home client shell" instead, and put routes and paths in the
# COMMENT above the test, where they are just as readable and cost nothing.
#
# Scope: only the DESCRIPTION (the leading string literals of a patrolTest
# call). Slashes anywhere else in the file — comments, imports, the test body,
# URLs under test — are fine and are not flagged.
#
# Exit 0 when clean, 1 on the first offender. `--self-test` runs the fixture
# suite below instead of scanning the repo.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/.." && pwd)"

# Scan one or more Dart files; print offenders. Returns 1 if any were found.
scan() {
  local found=0
  local f
  for f in "$@"; do
    [ -f "$f" ] || continue
    # Collect the consecutive single-quoted string literals that directly
    # follow `patrolTest(` — that is the description, possibly split across
    # adjacent lines by Dart's implicit string concatenation.
    local out
    out="$(awk '
      /patrolTest\(/ { collecting = 1; desc = ""; startline = NR; next }
      collecting {
        line = $0
        sub(/^[ \t]+/, "", line)
        # A quoted literal continues the description.
        if (line ~ /^'"'"'/) {
          body = line
          sub(/^'"'"'/, "", body)
          sub(/'"'"'[ \t]*,?[ \t]*$/, "", body)
          desc = desc body
          next
        }
        # Anything else ends the description.
        if (index(desc, "/") > 0) {
          printf "%d\t%s\n", startline, substr(desc, 1, 130)
        }
        collecting = 0
      }
    ' "$f")"
    if [ -n "$out" ]; then
      while IFS=$'\t' read -r ln desc; do
        printf '  %s:%s\n      %s\n' "${f#$repo_root/}" "$ln" "$desc"
        found=1
      done <<< "$out"
    fi
  done
  return $found
}

self_test() {
  local tmp status rc=0
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  # 1. compliant — no slash in the description
  cat > "$tmp/ok.dart" <<'EOF'
void main() {
  patrolTest(
    'CLIENT login navigates to the home client shell',
    ($) async {
      // A slash here is fine: see /home and integration_test/foo.dart
      await $.pumpWidgetAndSettle(const App());
    },
  );
}
EOF

  # 2. violating — route in the description
  cat > "$tmp/route.dart" <<'EOF'
void main() {
  patrolTest(
    'CLIENT login navigates to the /home client shell',
    ($) async {},
  );
}
EOF

  # 3. violating — file path in a multi-line (implicitly concatenated) skip reason
  cat > "$tmp/multiline.dart" <<'EOF'
void main() {
  patrolTest(
    'CLIENT login lands on the client shell '
    '(SKIPPED: covered by integration_test/auth_login_flow_test.dart)',
    skip: true,
    ($) async {},
  );
}
EOF

  # 4. compliant — slashes only in comments and body, never the description
  cat > "$tmp/comments.dart" <<'EOF'
void main() {
  // Lands on /home via roleHomePath — see lib/routing/role_home.dart
  patrolTest(
    'CLIENT login lands on the client shell',
    ($) async {
      await $.platform.mobile.openUrl('https://example.com/reset-password');
    },
  );
}
EOF

  run_case() { # name expected(0=clean,1=flagged) file
    local name="$1" expect="$2" file="$3"
    set +e; scan "$file" >/dev/null 2>&1; status=$?; set -e
    if [ "$status" -eq "$expect" ]; then
      printf '  PASS  %s\n' "$name"
    else
      printf '  FAIL  %s (expected rc=%s, got rc=%s)\n' "$name" "$expect" "$status"
      rc=1
    fi
  }

  echo "forbid_slash_in_patrol_test_name --self-test"
  run_case "compliant description"                0 "$tmp/ok.dart"
  run_case "route in description"                 1 "$tmp/route.dart"
  run_case "file path in multi-line description"  1 "$tmp/multiline.dart"
  run_case "slashes only in comments/body"        0 "$tmp/comments.dart"
  return $rc
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  st_rc=$?
  if [ "$st_rc" -eq 0 ]; then
    echo "SELF-TEST OK: forbid_slash_in_patrol_test_name.sh"
  fi
  exit "$st_rc"
fi

mapfile -t files < <(find "$repo_root/integration_test" -type f -name '*.dart' 2>/dev/null || true)
if [ "${#files[@]}" -eq 0 ]; then
  echo "forbid_slash_in_patrol_test_name: no integration_test Dart files found — nothing to check."
  exit 0
fi

set +e
output="$(scan "${files[@]}")"
status=$?
set -e

if [ "$status" -ne 0 ]; then
  echo "ERROR: a patrolTest description contains '/'."
  echo
  echo "$output"
  echo
  echo "AndroidTestOrchestrator names a per-test output file after the description"
  echo "and Context.openFileOutput rejects path separators, so this crashes the"
  echo "orchestrator process — reported only as 'Instrumentation run failed due to"
  echo "Process crashed', with zero failed assertions. Nothing host-side catches it."
  echo
  echo "Fix: drop the slash from the description (say 'the home client shell', not"
  echo "'/home'), and put routes and file paths in the comment above the test."
  exit 1
fi

echo "forbid_slash_in_patrol_test_name: OK — no patrolTest description contains '/'."
