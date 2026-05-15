#!/usr/bin/env bash
# Phase 1.2 spacing-scale gate.
#
# Beautica's design system locks padding/margin/inset values to the
# seven tokens exposed by `lib/core/theme/app_spacing.dart`
# (`AppSpacing.xxs` … `AppSpacing.xxl`). Every `EdgeInsets*` constructor
# under `lib/` MUST reference one of those constants — raw numeric
# literals are forbidden so designers and engineers share the same
# spacing vocabulary and so theme refactors don't drift.
#
# This script is the CI hard-gate (run from `.github/workflows/pr-validate.yml`)
# and can also be invoked locally before pushing. It fails the moment a
# numeric literal sneaks into ANY of:
#
#   EdgeInsets.all(N)
#   EdgeInsets.symmetric(...: N, ...)
#   EdgeInsets.fromLTRB(N, ...)
#   EdgeInsets.fromSTEB(N, ...)
#   EdgeInsets.only(...: N, ...)
#   EdgeInsetsDirectional.<any of the above>(N, ...)
#
# Lines that already route through `AppSpacing.` are filtered out before
# the offender check, so e.g. `EdgeInsets.all(AppSpacing.md)` passes.

set -euo pipefail

# Outer `!` inverts the exit code: this script exits 0 when the inner
# grep finds zero offenders, exit 1 the moment any literal numeric
# `EdgeInsets(...)` shows up under `lib/`.
! grep -rEn \
    "EdgeInsets(Directional)?\.(all|symmetric|fromLTRB|fromSTEB|only)\(\s*[0-9]" \
    lib/ \
  | grep -v "AppSpacing\."
