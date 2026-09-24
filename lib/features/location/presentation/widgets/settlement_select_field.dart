// Phase 346 — SettlementSelectField: the ONE «Населений пункт» autocomplete
// that replaces the «Область» + «Місто» cascade on every address surface.
//
// REUSE-FIRST, twice over.
//
//   1. The SHEET is not new. This widget is a thin, settlement-shaped
//      configuration of `SearchableSelectField` (the service-form category /
//      service-type picker), which already owns the VelvetTouch bottom sheet,
//      the drag handle, the header + close X, the inset search input, the
//      debounce, the empty state, the error state with Retry, and the
//      pop-with-value contract. The three things it did NOT have — a
//      server-backed row source, a two-line row, an inline label suffix — were
//      added there as OPTIONAL parameters, so every pre-existing caller renders
//      byte-identically. Nothing was forked. See `SearchableSelectSource`.
//
//   2. This widget is used by all six surfaces (phase-346 D1): independent-
//      master registration step 3, master location edit, salon registration,
//      salon address edit, client location edit, and discovery filters. Six
//      hand-rolled copies of a debounced autocomplete is exactly the drift the
//      rule exists to stop, and this field WILL change again.
//
// WHAT IT EMITS (D3). `onSelected` fires with a `settlementId` and nothing
// else. No screen keeps the display name in its own state: the label lives
// here, seeded from [initialLabel] (what the screen already has denormalised on
// its profile/salon read — `UserProfileResponse.cityName`,
// `SalonResponse.city`) and replaced from the picked row. That is what makes
// re-opening a saved address show the settlement (D7) WITHOUT an id -> name
// lookup the backend does not offer: `GET /settlements` is query-shaped, and
// the retiring cascade's `/oblasts/{id}/cities` returns `settlement_type =
// 'CITY'` only, so a village id is unresolvable through it.
//
// BELOW THREE CHARACTERS the sheet shows «Введіть щонайменше 3 символи» and
// issues NO request — the same predicate the server enforces
// (`settlementQueryIsSearchable`), evaluated locally so a 1-2 character
// keystroke costs nothing. It deliberately does NOT hold the last servable
// query; see `SearchableSelectSource._remoteBody`'s doc for the divergence that
// avoids.
//
// BEFORE ANY TYPING the sheet shows the ~50 major settlements (D6) — never a
// blank sheet. That is the blank-query response, and it is the one family key
// pinned `keepAlive` on `settlementSearchProvider`.

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/domain/settlement.dart';
import 'package:beautica_mobile/features/location/state/location_providers.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/searchable_select_field.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long the field waits after the last keystroke before it applies the
/// query and issues a request.
///
/// Deliberately its own constant and deliberately LONGER than the two
/// in-memory searchable sheets (`SearchableSelectField` 180 ms,
/// `LocalityPickerSheet` 200 ms): those commit a `contains` over a list already
/// in memory, this commits a network round trip against a 25 698-row table on
/// an IP-throttled endpoint.
///
/// Phase-346 D5 asks for "discovery's existing constant rather than a second
/// one". The MINIMUM is genuinely shared — [kSearchMinQueryLength] is imported
/// from `discovery/domain/search_filters.dart` and is the same backend
/// constant (`NormalizedSearchQuery.MIN_QUERY_LENGTH`) on both surfaces. A
/// debounce constant to reuse does NOT exist: the 400 ms figure the
/// mobile-backlog attributes to live search is not present anywhere in `lib/`
/// (the filters screen states in-line that it never fetches, so it has no
/// debounce at all). 400 ms is adopted here as the value that entry records.
const Duration kSettlementSearchDebounce = Duration(milliseconds: 400);

/// How long the sheet stays quiet after a settlement-search 429 whose
/// `Retry-After` is absent, unparsable, or above the UX ceiling.
///
/// The backend bucket refills at 4 tokens/s (240 per 60 s), so ten seconds
/// restores a comfortable typing budget without stranding the user.
const Duration kSettlementThrottleFallback = Duration(seconds: 10);

/// The settlement sheet's cooldown for [error], or `null` when [error] is not
/// a rate limit. Reuses the app-wide [isThrottleFailure] family test.
Duration? settlementThrottleCooldown(Object error) {
  if (error is! Failure || !isThrottleFailure(error)) return null;
  final int? seconds = error is SettlementSearchRateLimitedFailure
      ? error.retryAfterSeconds
      : null;
  return (seconds != null && seconds > 0)
      ? Duration(seconds: seconds)
      : kSettlementThrottleFallback;
}

/// The single «Населений пункт» autocomplete.
///
/// Renders a closed neumorphic field showing the currently-chosen settlement
/// (or [placeholder]) and, on tap, the shared searchable bottom sheet backed by
/// `GET /api/v1/settlements`.
class SettlementSelectField extends ConsumerStatefulWidget {
  const SettlementSelectField({
    super.key,
    this.fieldKey = const Key('settlement_select_field'),
    required this.onSelected,
    this.initialLabel,
    this.label,
    this.placeholder,
    this.labelSuffix,
    this.errorText,
    this.enabled = true,
    this.onCleared,
  });

  /// Stable key on the tappable closed field. Defaults to
  /// `settlement_select_field`; a screen that renders two of them (none does
  /// today) passes its own.
  final Key fieldKey;

  /// Fired with the chosen `settlementId` and the label this field composed
  /// for it.
  ///
  /// The ID is the value (phase-346 D3): it is what every screen stores and
  /// submits, and the label is never round-tripped to the server. The label is
  /// handed over for the ONE thing a screen cannot do without it — rendering
  /// the chosen settlement somewhere OUTSIDE this field. Discovery needs it for
  /// its applied-filter chip, which lives on a different screen entirely and
  /// reads `SearchFilterLabels`, a display-only store that predates this phase.
  /// The five address surfaces ignore the second argument: the field itself is
  /// the only place the name appears there, and it keeps its own.
  ///
  /// Never fired with `null` — a row tap always carries an id. Clearing is a
  /// separate, opt-in affordance ([onCleared]).
  final void Function(String settlementId, String label) onSelected;

  /// The label to show before the user picks anything — the settlement name
  /// already denormalised onto the screen's own profile/salon read.
  ///
  /// Purely a SEED. Once the user picks a row the picked label wins, and a
  /// later change to this value does not overwrite it.
  final String? initialLabel;

  /// Section label above the field. Defaults to «Населений пункт».
  final String? label;

  /// Hint inside the closed field before anything is chosen. Defaults to
  /// «Оберіть населений пункт».
  final String? placeholder;

  /// Optional inline widget to the right of [label] — the CLIENT
  /// «— необов'язково» tag and its "?" tip icon, which the cascade used to
  /// carry on its Область row.
  final Widget? labelSuffix;

  /// Inline validation error beneath the field.
  final String? errorText;

  /// Suppresses opening while a submit is in flight.
  final bool enabled;

  /// When non-null AND a settlement is showing, the field grows a «×» that
  /// clears it and invokes this.
  ///
  /// `null` on every REQUIRED surface (an address must name a place). Non-null
  /// on discovery, where an unset settlement is a legitimate nationwide search.
  final VoidCallback? onCleared;

  @override
  ConsumerState<SettlementSelectField> createState() =>
      _SettlementSelectFieldState();
}

class _SettlementSelectFieldState extends ConsumerState<SettlementSelectField> {
  /// The label shown on the CLOSED field.
  ///
  /// Seeded from `initialLabel` and thereafter owned here — see the file
  /// header for why the display name lives in the field rather than in each of
  /// the six screens.
  String? _label;

  // Single-entry memo for [_toOptions] (perf M2). The sheet's Consumer can
  // re-run `resolve` many times for ONE resolved list; keyed on the list's
  // IDENTITY (the provider hands back the same instance until it refetches)
  // plus the localised hromada/oblast/type words, a re-run is a pointer
  // compare instead of three `sanitizeDisplayText` passes on each of up to 50
  // rows.
  List<Settlement>? _memoSettlements;
  String? _memoHromadaWord;
  String? _memoOblastWord;
  String? _memoCityPrefix;
  String? _memoVillagePrefix;
  List<SelectOption<_SettlementChoice>> _memoOptions =
      const <SelectOption<_SettlementChoice>>[];

  List<SelectOption<_SettlementChoice>> _optionsFor(
    List<Settlement> settlements,
    String hromadaWord,
    String oblastWord,
    String cityPrefix,
    String villagePrefix,
  ) {
    if (!identical(settlements, _memoSettlements) ||
        hromadaWord != _memoHromadaWord ||
        oblastWord != _memoOblastWord ||
        cityPrefix != _memoCityPrefix ||
        villagePrefix != _memoVillagePrefix) {
      _memoSettlements = settlements;
      _memoHromadaWord = hromadaWord;
      _memoOblastWord = oblastWord;
      _memoCityPrefix = cityPrefix;
      _memoVillagePrefix = villagePrefix;
      _memoOptions = _toOptions(
        settlements,
        hromadaWord: hromadaWord,
        oblastWord: oblastWord,
        cityPrefix: cityPrefix,
        villagePrefix: villagePrefix,
      );
    }
    return _memoOptions;
  }

  @override
  void initState() {
    super.initState();
    // Sanitised with the SAME rule a picked row's label gets — the seed is a
    // server string too (security audit #1).
    _label = sanitizeSettlementLabel(widget.initialLabel);
  }

  /// A CHANGED [SettlementSelectField.initialLabel] is always adopted.
  ///
  /// It is not a stale seed racing the user's pick: on the five address
  /// surfaces it is written once, inside the screen's `_initialized`-guarded
  /// init, and never moves again — so this branch simply never fires there. The
  /// caller that DOES move it is discovery, where `SearchFilterLabels.cityName`
  /// is authoritative and is rewritten by
  /// `SearchFiltersController.applyProfileLocationSave` when the client saves a
  /// new home address from another screen while Search is still mounted in the
  /// shell. Ignoring it there would leave Search showing the previous
  /// settlement — the exact class of bug that method exists to fix.
  @override
  void didUpdateWidget(covariant SettlementSelectField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialLabel != oldWidget.initialLabel) {
      _label = sanitizeSettlementLabel(widget.initialLabel);
    }
  }

  void _onClear() {
    setState(() => _label = null);
    widget.onCleared?.call();
  }

  void _onSelected(_SettlementChoice choice) {
    setState(() => _label = choice.label);
    widget.onSelected(choice.id, choice.label);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String hromadaWord = l10n.settlementHromadaWord;
    final String oblastWord = l10n.settlementOblastAbbrev;
    final String cityPrefix = l10n.settlementCityPrefix;
    final String villagePrefix = l10n.settlementVillagePrefix;

    return SearchableSelectField<_SettlementChoice>(
      fieldKey: widget.fieldKey,
      label: widget.label ?? l10n.settlementLabel,
      labelSuffix: widget.labelSuffix,
      menuTitle: l10n.settlementLabel,
      placeholder: widget.placeholder ?? l10n.settlementPlaceholder,
      searchHint: l10n.settlementSearchHint,
      emptyLabel: l10n.localitySearchEmpty,
      errorLabel: l10n.errUnknown,
      retryLabel: l10n.localityRetry,
      selectedLabel: _label,
      // The FIELD never loads: every async state of the settlement list lives
      // inside the sheet, under the search input that produces it.
      fieldState: SelectFieldState.idle,
      options: const <SelectOption<_SettlementChoice>>[],
      errorText: widget.errorText,
      enabled: widget.enabled,
      onClear: widget.onCleared == null ? null : _onClear,
      // The disambiguating three-part label is the whole point of the row and
      // must WRAP rather than truncate (D4).
      optionMaxLines: 2,
      onSelected: _onSelected,
      onMenuRetry: () => ref.invalidate(settlementSearchProvider),
      source: SearchableSelectSource<_SettlementChoice>(
        debounce: kSettlementSearchDebounce,
        belowMinimumLabel: l10n.settlementQueryTooShort,
        isSearchable: settlementQueryIsSearchable,
        // The server's cap (perf L2 / security #2-#3): the input cannot grow
        // past it, and the committed key is bounded by the same function the
        // repository applies, so key == wire text.
        maxQueryLength: kSettlementQueryMaxLength,
        throttleCooldownOf: settlementThrottleCooldown,
        resolve: (WidgetRef ref, String query) => ref
            .watch(settlementSearchProvider(query))
            .whenData(
              (List<Settlement> settlements) => _optionsFor(
                settlements,
                hromadaWord,
                oblastWord,
                cityPrefix,
                villagePrefix,
              ),
            ),
        onRetry: (WidgetRef ref, String query) =>
            ref.invalidate(settlementSearchProvider(query)),
      ),
    );
  }

  static List<SelectOption<_SettlementChoice>> _toOptions(
    List<Settlement> settlements, {
    required String hromadaWord,
    required String oblastWord,
    required String cityPrefix,
    required String villagePrefix,
  }) {
    return List<SelectOption<_SettlementChoice>>.generate(settlements.length, (
      int i,
    ) {
      final Settlement settlement = settlements[i];
      final String label = composeSettlementLabel(
        settlement,
        hromadaWord: hromadaWord,
        oblastWord: oblastWord,
        cityPrefix: cityPrefix,
        villagePrefix: villagePrefix,
      );
      return SelectOption<_SettlementChoice>(
        value: _SettlementChoice(id: settlement.id, label: label),
        label: label,
        // Keyed by the settlement id, not the list index — the list re-sorts on
        // every keystroke and an index key would make a row's identity depend
        // on how far the user has typed.
        rowKey: Key('settlement_option_${settlement.id}'),
      );
    }, growable: false);
  }
}

/// What one row pops back: the id the screens consume plus the label this field
/// keeps for the closed state.
///
/// Private on purpose — `onSelected` hands the caller a bare id string (D3);
/// the label never leaves this file.
@immutable
class _SettlementChoice {
  const _SettlementChoice({required this.id, required this.label});

  final String id;
  final String label;
}
