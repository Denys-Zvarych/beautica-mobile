#!/usr/bin/env bash
# All-guards local runner.
#
# THE GAP THIS FILLS
# -------------------
# scripts/forbid_*.sh (one file per gate) are each wired as their own step in
# `.github/workflows/pr-validate.yml`, all before the `Test` step, none with
# `continue-on-error`. That means the FIRST failing guard aborts the whole CI
# run and every subsequent guard — plus `flutter test` itself — never
# executes. There was no local equivalent: the only thing that ever ran all
# of them was opening a PR. Local verification fell back to sampling a few
# guards ad-hoc, and that is exactly how gates went red unnoticed — e.g.
# `forbid_stale_future_date_fixture` was breached and stayed breached for
# 13 days because nothing short of a PR would have caught it.
#
# This script is the local stand-in for those 19 (and counting) separate CI
# steps: it discovers and runs every scripts/forbid_*.sh, keeps going past
# failures instead of stopping at the first one (CI's behaviour is exactly
# what let later regressions hide behind an earlier one), and reports a full
# PASS/FAIL summary in one shot.
#
# PARALLEL EXECUTION
# -------------------
# Guards are independent — no shared state, no ordering dependency (CI
# already runs them as independent steps) — so they are dispatched
# concurrently, one process per guard, bounded by the machine's core count
# (`nproc`, falling back to 4 if `nproc` is unavailable or reports garbage).
# Each guard's combined stdout/stderr is captured to a private temp file
# while it runs; only once every guard has finished does this script print
# each guard's buffered output as one contiguous "== name ==" block, walked
# in the same deterministic (sorted) order discover_guards produces. That
# keeps concurrent execution from garbling interleaved output and keeps the
# summary/exit-code contract byte-for-byte compatible with the old
# sequential runner.
#
# Usage:
#   ./scripts/verify_guards.sh              run every discovered guard
#   ./scripts/verify_guards.sh --list       print discovered guards, don't run them
#   ./scripts/verify_guards.sh --self-test  run every guard's OWN --self-test
#
# THE SECOND GAP: --self-test
# ---------------------------
# The note that used to sit here said this runner "has nothing to self-test
# beyond discovery". That was wrong, and it hid the same class of silent gap
# the script was written to close.
#
# `.github/workflows/pr-validate.yml` used to list all 22 guard `--self-test`
# invocations BY HAND, one line each. Hand-maintained lists rot: a guard
# added without someone remembering to append its CI line is a guard whose
# self-test never runs anywhere — it looks covered (it has a --self-test!)
# while being verified by nothing. That is exactly the failure mode of the
# two bugs found on 2026-08-18: `no_raw_ui_strings` shipped as a
# `custom_lint` plugin that was never loaded, and `riverpod_lint` stopped
# being loaded when `custom_lint` was archived — both green, both enforcing
# nothing.
#
# So --self-test derives the list from the SAME discovery glob that normal
# mode uses. Adding a `scripts/forbid_*.sh` automatically enrols it; there is
# no second place to forget.
#
# A guard "passes" its self-test only if it BOTH exits 0 AND prints the
# sentinel line `SELF-TEST OK: <basename>`. Exit code alone is not enough —
# exit 0 from a check that silently did nothing is precisely the bug being
# guarded against, and a guard whose --self-test flag is unrecognised would
# typically fall through to normal mode and exit 0 looking healthy. The
# sentinel is the affirmative proof that the self-test path actually ran to
# completion. The count of sentinels must equal the count of discovered
# guards; any guard that produced none is named in the summary.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
self="$(basename "$0")"

# ---------------------------------------------------------------------------
# discover_guards
#   Emits one absolute path per line for every scripts/forbid_*.sh, sorted,
#   excluding this script itself (belt-and-suspenders: this file is not named
#   forbid_*, but guard against a future rename anyway).
# ---------------------------------------------------------------------------
discover_guards() {
  local g base
  while IFS= read -r g; do
    [ -z "$g" ] && continue
    base="$(basename "$g")"
    [ "$base" = "$self" ] && continue
    printf '%s\n' "$g"
  done < <(find "$here" -maxdepth 1 -type f -name 'forbid_*.sh' | sort)
}

mapfile -t guards < <(discover_guards)

if [ "${#guards[@]}" -eq 0 ]; then
  echo "No scripts/forbid_*.sh guards discovered in $here" >&2
  exit 1
fi

if [ "${1:-}" = "--list" ]; then
  echo "Discovered ${#guards[@]} guard(s):"
  for g in "${guards[@]}"; do
    echo "  $(basename "$g")"
  done
  exit 0
fi

# selftest_mode: passed down to run_one so the same dispatch machinery
# (process group, bounded concurrency, buffered output) serves both modes.
selftest_mode=0
if [ "${1:-}" = "--self-test" ]; then
  selftest_mode=1
fi

# ---------------------------------------------------------------------------
# Run every guard concurrently (bounded by core count), unconditionally
# continuing past failures, then report a summary. Exit 1 if any guard
# failed, 0 only if all passed.
# ---------------------------------------------------------------------------

# Degree of parallelism: machine core count, sane fallback if nproc is
# missing or returns something non-numeric.
jobs_max="$(nproc 2>/dev/null || true)"
case "$jobs_max" in
  '' | *[!0-9]*) jobs_max=4 ;;
esac
[ "$jobs_max" -lt 1 ] && jobs_max=1

workdir="$(mktemp -d)"
group_pid=""

# cleanup: always removes the workdir (on a clean finish AND on interrupt).
# It also kills every guard process still running, via a SINGLE signal to a
# dedicated process group rather than per-PID bookkeeping.
#
# WHY NOT A PIDFILE (this script's previous approach, found NOT RESOLVED)
# --------------------------------------------------------------------------
# An earlier version recorded each guard's real PID to a pidfile right
# after backgrounding it, so this trap could `kill` those PIDs individually.
# That has a fundamental TOCTOU race: there is a window between forking the
# guard and the pidfile write completing, and with `jobs_max` guards forking
# concurrently, ANY guard interrupted inside that window is invisible to
# cleanup — confirmed on this machine: 5-7 orphaned forbid_*.sh processes,
# reparented to init, survived a SIGINT on 3/3 runs. Any record-the-PID-
# after-forking scheme has this race by construction, no matter how the
# bookkeeping step is arranged.
#
# WHY A PROCESS GROUP FIXES IT
# --------------------------------------------------------------------------
# Process-group membership is assigned by the kernel atomically AT FORK
# TIME — there is no later bookkeeping step for an interrupt to race
# against. The dispatch block below runs every guard inside one dedicated
# group (`$group_pid`; see the comment there for how that group is formed
# and why every guard, and every child a guard itself spawns, ends up in
# it). Signalling that single group with `kill -TERM -- "-$group_pid"`
# reaches all of them regardless of what stage of startup any individual
# guard is in — no pidfile, no per-PID `kill`/`pkill`, and no window where a
# just-forked guard is invisible to cleanup.
#
# On the normal (non-interrupted) path, `wait "$group_pid"` below has
# already reaped the whole group by the time this trap runs, so the group
# no longer exists and `kill` here fails with "no such process" — swallowed
# by `|| true`, a pure no-op that cannot make a clean run exit non-zero
# (this trap never calls `exit`; the script's already-decided exit code is
# unaffected either way).
cleanup() {
  if [ -n "$group_pid" ]; then
    kill -TERM -- "-$group_pid" 2>/dev/null || true
  fi
  rm -rf "$workdir"
}
trap cleanup EXIT

# run_one: execute a single guard, capturing its combined stdout/stderr to
# $out and its pass/fail (0/1) to $rc. This function itself always exits 0
# — the guard's real result lives in $rc, never in this function's own exit
# status — so a failing guard can never trip `set -e` when this runs as a
# background job (`wait -n` below propagates the exit status of whichever
# job it reaps). Runs `bash "$g"` synchronously (no inner backgrounding, no
# PID capture): with no pidfile to race against there is nothing left that
# needs the guard's own PID.
# In --self-test mode the guard is invoked as `bash "$g" --self-test` and the
# sentinel assertion is applied here, so a guard that exits 0 without ever
# reaching its self-test path is recorded as a FAILURE, not a pass. The
# distinction between "exited non-zero" and "exited 0 but printed no
# sentinel" is preserved in $rc (1 vs 2) so the summary can name the latter
# specifically — that is the silent-gap case worth calling out by name.
run_one() {
  local g="$1" out="$2" rc="$3" selftest="$4"
  local base
  base="$(basename "$g")"

  if [ "$selftest" = "1" ]; then
    if bash "$g" --self-test >"$out" 2>&1; then
      if grep -q "^SELF-TEST OK: $base\$" "$out"; then
        printf '0\n' >"$rc"
      else
        printf '2\n' >"$rc"
      fi
    else
      printf '1\n' >"$rc"
    fi
    return 0
  fi

  if bash "$g" >"$out" 2>&1; then
    printf '0\n' >"$rc"
  else
    printf '1\n' >"$rc"
  fi
}

# ---------------------------------------------------------------------------
# Dispatch every guard inside a single dedicated process group.
#
# `set -m` (job control) is off by default in a non-interactive script, so
# ordinarily every `&` background job just inherits this shell's own
# process group — nothing to target in isolation. Turning `-m` on for
# exactly one job launch (the subshell below) makes bash assign that job a
# NEW process group whose pgid equals the subshell's own PID — assigned
# atomically when the job is created, not bookkept afterwards. `set +m`
# immediately inside the subshell then turns job control back OFF for
# everything *it* forks, so every `run_one … &` and every `bash "$g"` guard
# process — plus any children a guard spawns internally, e.g. its own
# `grep`/`find` — simply inherits the subshell's group instead of splitting
# off into a group of its own. Net effect: one process group holds the
# subshell and every guard (and grandchild) it ever forks, confirmed with
# `ps -eo pid,ppid,pgid,cmd` (see the accompanying commit message / phase
# doc for the captured snapshot). The top-level script's own process group
# is untouched by this — `-m` here only governs pgid assignment for jobs
# THIS shell launches, not the shell's own group — so `$group_pid` can be
# signalled from the EXIT trap without the trap's own process being caught
# in the blast radius mid-cleanup.
# ---------------------------------------------------------------------------
set -m
(
  set +m
  running=0
  i=0
  for g in "${guards[@]}"; do
    i=$((i + 1))
    run_one "$g" "$workdir/$i.out" "$workdir/$i.rc" "$selftest_mode" &
    running=$((running + 1))
    if [ "$running" -ge "$jobs_max" ]; then
      wait -n
      running=$((running - 1))
    fi
  done
  wait
) &
group_pid=$!
set +m
wait "$group_pid" || true

failed=()
passed=()
# no_sentinel: guards that exited 0 but never printed `SELF-TEST OK: <base>`.
# Tracked separately from ordinary failures because it is the interesting
# case: the guard reported success while proving nothing.
no_sentinel=()
i=0
for g in "${guards[@]}"; do
  i=$((i + 1))
  name="$(basename "$g")"
  echo "== $name =="
  cat "$workdir/$i.out"
  case "$(cat "$workdir/$i.rc")" in
    0)
      echo "PASS: $name"
      passed+=("$name")
      ;;
    2)
      echo "FAIL: $name — exited 0 but never printed 'SELF-TEST OK: $name'."
      echo "      Either it has no --self-test mode (so --self-test fell"
      echo "      through to normal mode and exited 0 looking healthy), or"
      echo "      its self-test path does not emit the sentinel. Both mean"
      echo "      this guard is verified by NOTHING."
      failed+=("$name")
      no_sentinel+=("$name")
      ;;
    *)
      echo "FAIL: $name"
      failed+=("$name")
      ;;
  esac
  echo
done

if [ "$selftest_mode" = "1" ]; then
  echo "============== verify_guards --self-test summary =============="
  echo "Discovered guards: ${#guards[@]}"
  echo "Sentinels seen:    ${#passed[@]}"
else
  echo "=================== verify_guards summary ==================="
  echo "Passed: ${#passed[@]}/${#guards[@]}"
fi

if [ "${#no_sentinel[@]}" -gt 0 ]; then
  echo
  echo "No 'SELF-TEST OK' sentinel from (missing or non-emitting --self-test):"
  for f in "${no_sentinel[@]}"; do
    echo "  - $f"
  done
fi

if [ "${#failed[@]}" -gt 0 ]; then
  echo
  echo "Failed:"
  for f in "${failed[@]}"; do
    echo "  - $f"
  done
  exit 1
fi

# Cardinality assertion: every discovered guard must have contributed a
# sentinel. Belt-and-suspenders over the per-guard checks above — if the two
# ever disagree, the bookkeeping itself is broken and that must not pass
# silently.
if [ "$selftest_mode" = "1" ] && [ "${#passed[@]}" -ne "${#guards[@]}" ]; then
  echo
  echo "FAIL: sentinel count ${#passed[@]} != discovered guard count ${#guards[@]}."
  exit 1
fi

if [ "$selftest_mode" = "1" ]; then
  echo "All ${#guards[@]} guards self-tested and emitted their sentinel."
else
  echo "All guards passed."
fi
exit 0
