// Project-wide ERROR-state golden harness (mobile-qa M3).
//
// WHY THIS FILE EXISTS (the gap it closes)
// ----------------------------------------
// Before this harness ZERO error-state goldens existed anywhere in the suite —
// every screen golden covered only LOADING + LOADED + EMPTY. The error branch
// (`AsyncValue.when(error:)`) is the one production users hit on every flaky
// network, every 5xx, every expired session — and it shipped with no visual
// regression guard at all. A silent restyle of the shared error surface (icon,
// spacing, retry button) could regress on every screen at once and no golden
// would catch it. This file is that guard.
//
// THE CANONICAL SURFACE
// ---------------------
// Almost every feature error branch delegates to ONE shared widget:
// `ErrorState(failure:, onRetry:)` (lib/shared/widgets/error_state.dart). The
// per-feature private `_ErrorBody` / `_CardErrorState` / `_GridError` /
// `_ServiceTypeError` widgets are private (not constructible from a test) and
// are thin wrappers over the same icon + `failure.userMessage(context)` + retry
// idiom. So we golden the canonical `ErrorState` once per failure-variant —
// that is the byte-for-byte surface those private widgets render — PLUS the one
// PUBLIC feature-specific variant that diverges visually: `ResultsError`
// (search results: different icon, `BrandColors.muted`, NeumorphicButton retry).
//
// ONE PARAMETERIZED HARNESS, NOT N FILES
// --------------------------------------
// A single data-driven `_ErrorCase` list (screen-name → error-fixture widget)
// drives the whole matrix. Adding a new error surface = one row, not a new file.
// Each case is rendered through the shared `goldenPumpWidget` at a single
// representative width (360 dp) — error layouts are width-robust (centered,
// max-width-clamped Columns), so the {320,360,414} sweep used for full screens
// would just triple identical PNGs. Failure VARIANT coverage (network / server /
// validation / not-found) is the axis that matters here, and that is swept in
// full.
//
// SEED / REFRESH: run once with `--update-goldens` to seed the PNG masters under
// test/golden/goldens/, then commit them. Subsequent runs diff against them.
//
// FINDERS: this is a golden harness — assertions are pixel diffs, not widget
// finders, so the no-raw-Cyrillic-finder policy is satisfied vacuously (no
// `find.text`). The l10n strings rendered come from `failure.userMessage`.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/results_states.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Failure fixtures — one per Failure variant that drives a distinct l10n
// message. const so the whole case table is a compile-time constant.
// ---------------------------------------------------------------------------

const Failure _networkFailure = NetworkFailure();
const Failure _serverFailure = ServerFailure(statusCode: 503);
const Failure _notFoundFailure = NotFoundFailure();
const Failure _validationFailure = ValidationFailure(
  fieldErrors: <String, String>{},
);

// ---------------------------------------------------------------------------
// Case model — a named error surface + the widget that renders it.
// ---------------------------------------------------------------------------

@immutable
class _ErrorCase {
  const _ErrorCase({required this.name, required this.builder});

  /// Filename-safe scenario id (also the golden master file stem).
  final String name;

  /// Builds the error widget under test. `onRetry` is a no-op so the retry
  /// affordance renders (it is omitted entirely when the callback is null).
  final Widget Function() builder;
}

// Canonical shared-surface cases. `ErrorState` is what working-hours
// (`_ErrorBody`), master-profile, services and the home hub (`_CardErrorState`)
// all delegate to in their `error:` branch — goldening it once per failure
// variant covers every one of those screens' error surface.
List<_ErrorCase> _sharedErrorCases() => <_ErrorCase>[
  _ErrorCase(
    name: 'shared_error_state_network',
    builder: () => const ErrorState(failure: _networkFailure, onRetry: _noop),
  ),
  _ErrorCase(
    name: 'shared_error_state_server',
    builder: () => const ErrorState(failure: _serverFailure, onRetry: _noop),
  ),
  _ErrorCase(
    name: 'shared_error_state_not_found',
    builder: () => const ErrorState(failure: _notFoundFailure, onRetry: _noop),
  ),
  _ErrorCase(
    name: 'shared_error_state_validation',
    builder: () =>
        const ErrorState(failure: _validationFailure, onRetry: _noop),
  ),
  // Retry-less variant — some surfaces pass a null onRetry (the button must be
  // omitted). Guards against a regression that always renders the button.
  _ErrorCase(
    name: 'shared_error_state_no_retry',
    builder: () => const ErrorState(failure: _networkFailure),
  ),
];

// Public feature-specific error surface that diverges visually from the shared
// one: ResultsError (search/discovery results). cloud_off icon, muted color,
// NeumorphicButton retry — a distinct surface worth its own golden.
List<_ErrorCase> _resultsErrorCases() => <_ErrorCase>[
  _ErrorCase(
    name: 'results_error_network',
    builder: () => const ResultsError(error: _networkFailure, onRetry: _noop),
  ),
  _ErrorCase(
    name: 'results_error_server',
    builder: () => const ResultsError(error: _serverFailure, onRetry: _noop),
  ),
];

void _noop() {}

// ---------------------------------------------------------------------------
// Harness — ONE loop over every case at the representative golden width.
// ---------------------------------------------------------------------------

// Single representative width: error surfaces are centered + max-width-clamped,
// so layout is width-invariant; sweeping {320,360,414} would emit identical PNGs.
const double _kErrorGoldenWidth = 360;

void main() {
  final List<_ErrorCase> cases = <_ErrorCase>[
    ..._sharedErrorCases(),
    ..._resultsErrorCases(),
  ];

  for (final _ErrorCase c in cases) {
    goldenTest(
      'error-state ${c.name}',
      fileName: c.name,
      constraints: BoxConstraints.tight(
        const Size(_kErrorGoldenWidth, kGoldenHeight),
      ),
      textScaleFactor: 1.0,
      // settle:true — terminal error states have no perpetual animation, so
      // pumpAndSettle quiesces (the shared helper wraps in ProviderScope +
      // MaterialApp with UK l10n so `failure.userMessage(context)` resolves).
      pumpWidget: goldenPumpWidget(width: _kErrorGoldenWidth),
      builder: c.builder,
    );
  }
}
