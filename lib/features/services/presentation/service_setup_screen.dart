// Service Setup screen (INDEPENDENT_MASTER) — the ONE "add services" surface.
//
// Serves BOTH cases, reached from the services list either way:
//   • SETUP   — the master has zero services and stands up their whole menu.
//   • APPEND  — the master already has a catalogue and is adding more (the
//               «Додати послугу» FAB). Unlocked by `beautica-backend` c5e420f,
//               which made the bulk endpoint additive; before that it 409'd
//               whenever the catalogue was non-empty, which is why a separate
//               single-create form used to exist. That form is deleted.
//
// The two differ only in framing + the already-owned exclusion; the mechanics
// are identical. [_ServiceSetupScreenState._appending] is the one switch.
//
// The flow lives on one scrollable screen:
//   1. a tappable helper strip — the entry point for requesting a missing
//      CATEGORY (see [_MissingCategoryPrompt]);
//   2. a Wrap of multi-selectable platform-category chips — selecting one
//      loads + expands it inline to reveal every service-type beneath it;
//   3. under each expanded category, a configurable row per service-type
//      (include toggle defaulting OFF, duration, and a fixed/range price),
//      closed by a per-category prompt for suggesting a missing SERVICE TYPE
//      (see [_MissingServiceTypePrompt] — it supplies the `categoryName` the
//      suggestion dialog requires, which is why it lives per-category rather
//      than alongside the category prompt at the top);
//   4. a pinned CTA that counts the services the save would create.
//
// APPEND-MODE EXCLUSION (the guaranteed-409 trap)
// -----------------------------------------------
// The bulk endpoint is all-or-nothing: ONE item naming a service the master
// already offers rolls back the WHOLE batch with 409 DUPLICATE_SERVICE. A
// screen written for an empty catalogue happily lists those types, so reusing
// it for APPEND without filtering would make some saves impossible. Rows for
// already-owned types are therefore seeded `alreadyAdded` + `ownedDurations`
// (see [ServiceRowState]). Phase 468 (backend 464/465): an owned type may be
// added again as a COPY whose duration or name differs, so the row stays
// selectable, starts with an empty duration (phase 472), and blocks the CTA
// while its duration matches an existing copy (the client mirrors the duration half of the rule;
// the server 409 backstops name collisions).
//
// On a successful bulk save the catalogue providers are invalidated and the
// screen POPS back to the list. Popping (not `go`) is load-bearing: the list's
// `_openAndRefresh` awaits the push Future to re-fire its category invalidation
// on return, and a `go` would replace the stack so that Future never completes.
// `go` survives only as the no-stack fallback (deep link / cold start).
//
// Ported 1:1 from the approved preview
// `docs/signup-designs/ServiceSetup/lib/screens/service_setup_screen.dart`;
// local state / Navigator replaced by Riverpod providers + go_router, and the
// hardcoded category seed replaced by the live `approvedCategoriesProvider` /
// `serviceTypesProvider` data.

import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/icons/category_icons.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/presentation/category_catalogue_freshness.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_name_key.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/category_request_dialog.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_setup_widgets.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_type_suggestion_dialog.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack_host.dart'
    show VelvetSnackHandle;
import 'package:beautica_mobile/shared/formatters/server_field_message.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/features/services/presentation/service_catalogue_invalidation.dart';

/// Service setup — the single "add services" screen, for a master with zero
/// services (SETUP) and for one adding to an existing catalogue (APPEND).
class ServiceSetupScreen extends ConsumerStatefulWidget {
  const ServiceSetupScreen({super.key, this.exitRoute});

  /// Phase 317 (D3) — the `go` fallback destination when there is nothing to
  /// pop (a genuine deep link / cold start straight onto this route).
  ///
  /// ADDITIVE and NULLABLE: `null` means [RouteNames.services], i.e. exactly
  /// what [_ServiceSetupScreenState._leave] did before phase 317, so no
  /// existing caller changes. The salon-target route supplies
  /// [RouteNames.salonManageStaffServices] instead — without it a cold start
  /// on `/salons/S/manage/staff/U/services/setup` lands the operator on their
  /// OWN services list, which is a different master's catalogue under the
  /// heading they just left. The phase doc's claim that this screen needs no
  /// change was wrong, and deep-link / cold-start is the live case for as long
  /// as phase 318's tile is unlanded (these routes are deep-link-only until
  /// then).
  ///
  /// The POP path is unchanged and is still the normal exit — see [_leave]'s
  /// own doc for why popping is a contract, not a preference.
  final String? exitRoute;

  @override
  ConsumerState<ServiceSetupScreen> createState() => _ServiceSetupScreenState();
}

/// Test-only probe onto the screen state's row-wrapper [GlobalKey] cache, so
/// a test can prove «Прибрати» releases the removed row's key.
@visibleForTesting
abstract interface class ServiceSetupRowKeysProbe {
  /// The row key ids currently holding a cached wrapper [GlobalKey].
  Iterable<String> get debugRowWrapperKeyIds;

  /// How many times the copy pair check has run since the screen mounted.
  int get debugPairCheckRuns;
}

/// Test-only handle onto the state's log-safe error summary, so a test can pin
/// that a server failure logs only its type + status code, never its message.
@visibleForTesting
String debugServiceSetupErrorSummary(Object e) =>
    _ServiceSetupScreenState._errorSummary(e);

/// A row card's callbacks, allocated once per row (not per build).
final class _RowCallbacks {
  const _RowCallbacks({
    required this.changed,
    required this.fieldEdited,
    required this.addCopy,
    required this.remove,
  });

  final VoidCallback changed;
  final ValueChanged<bool> fieldEdited;
  final VoidCallback addCopy;
  final VoidCallback remove;
}

class _ServiceSetupScreenState extends ConsumerState<ServiceSetupScreen>
    implements ServiceSetupRowKeysProbe {
  static const _tag = 'feature.services.setup_screen';

  /// Matches a backend per-field validation key `items[<zero-based-index>].<field>`
  /// where the index is into the SUBMITTED items list (see [_submittedRows]).
  static final RegExp _itemFieldErrorPattern = RegExp(
    r'^items\[(\d+)\]\.(\w+)$',
  );

  /// Selected (expanded) category wire slugs.
  final Set<String> _expanded = <String>{};

  /// Loaded service-type rows per category slug. Absent until the category's
  /// types finish loading; an empty list once loaded-but-empty.
  final Map<String, List<ServiceRowState>> _rowsByCategory =
      <String, List<ServiceRowState>>{};

  /// Phase 471 — every row of each service type, in on-screen order (the
  /// primary row first, then its «+ додати ще» copies). The same objects as in
  /// [_rowsByCategory], where a type's rows sit adjacent.
  final Map<String, List<ServiceRowState>> _typeRows =
      <String, List<ServiceRowState>>{};

  /// Per-row card callbacks, created on the row's first build and dropped
  /// with the row (weakly held), so a rebuild allocates no closures.
  final Expando<_RowCallbacks> _rowCallbacks = Expando<_RowCallbacks>();

  _RowCallbacks _callbacksFor(ServiceRowState row) =>
      _rowCallbacks[row] ??= _RowCallbacks(
        changed: () => _onRowChanged(row.serviceTypeId),
        fieldEdited: (bool takenFlipped) =>
            _onPairFieldEdited(row.serviceTypeId, takenFlipped: takenFlipped),
        addCopy: () => _addCopy(row),
        remove: () => _removeRow(row),
      );

  /// Row-independent range-error resolver; the tear-off is cached so a
  /// rebuild passes the same object instead of allocating a closure per row.
  late final RangeErrorResolver _rangeResolver = _resolveRangeError;

  /// Null once unmounted: `context` is no longer valid for a lookup then.
  String? _resolveRangeError(ServiceRowState r) =>
      mounted ? _rangeErrorFor(r, AppLocalizations.of(context)) : null;

  /// Test probe only — incremented under [kDebugMode], so release builds
  /// tree-shake the bookkeeping away.
  int _pairCheckRuns = 0;

  @override
  int get debugPairCheckRuns => _pairCheckRuns;

  /// Categories whose service-type fetch is currently in flight.
  final Set<String> _loadingCategories = <String>{};

  /// Categories whose service-type fetch failed (retryable on re-tap).
  final Set<String> _erroredCategories = <String>{};

  /// One [GlobalKey] per service-type row wrapper, keyed by serviceTypeId.
  /// Reused across rebuilds so [Scrollable.ensureVisible] can resolve the live
  /// element for a flagged row when a blocked save needs to scroll to it.
  final Map<String, GlobalKey> _rowWrapperKeys = <String, GlobalKey>{};

  /// Lazily creates (or returns the existing) [GlobalKey] for a row wrapper.
  GlobalKey _rowWrapperKey(String id) =>
      _rowWrapperKeys.putIfAbsent(id, GlobalKey.new);

  @override
  Iterable<String> get debugRowWrapperKeyIds => _rowWrapperKeys.keys;

  /// Durations of the master's existing copies, keyed by service-type id,
  /// captured ONCE in [initState] (phase 468 — replaces the old id set; the
  /// key set is "types the master already offers").
  ///
  /// Source: [servicesListProvider] — the master's own «Мої послуги» catalogue.
  /// Chosen over [masterServiceCatalogProvider] deliberately: the latter is the
  /// «Мої записи» booking-filter universe, kept alive for a different screen and
  /// not guaranteed warm here, whereas the list provider is the one the entry
  /// point (services list) has already resolved — so in practice this read is a
  /// cache hit and the exclusion is correct on the very first frame.
  ///
  /// Read with `ref.read` in [initState], NOT watched, and deliberately so: it
  /// is a SNAPSHOT of what to exclude. Watching it would let a mid-flight
  /// invalidation (this screen's own successful save re-enters the list
  /// provider) re-seed rows underneath the master while they are typing.
  ///
  /// `MasterService.serviceTypeId` is nullable — a pre-Phase-16.3 row carries no
  /// type id and simply cannot be matched, so it contributes nothing here. That
  /// degrades to the old behaviour (the type stays selectable and the save may
  /// 409) rather than to over-blocking, which is the safer failure direction:
  /// the 409 is recoverable and explained, an over-eager exclusion would hide a
  /// service the master genuinely cannot add any other way.
  late final Map<String, Set<int>> _ownedDurationsByType;

  /// Phase 472 — the master's existing services per type: the (duration,
  /// canonical name) keys [ServiceRowState.durationTaken] compares with. Same
  /// initState snapshot as [_ownedDurationsByType].
  late final Map<String, List<MasterService>> _ownedByType;

  /// True when the master already had services on entry — the APPEND case.
  /// Drives the copy variants only; ownership itself keys off
  /// [_ownedDurationsByType].
  late final bool _appending;

  /// The [ServiceRowState]s backing the LAST assembled payload, in submitted
  /// order — so a 400's `items[<index>].<field>` path resolves back to its
  /// originating row. Only INCLUDED rows are submitted, so this list index is
  /// NOT the on-screen row index; it must be captured explicitly during
  /// [_assemble] rather than recomputed. Refilled on every [_assemble] call.
  final List<ServiceRowState> _submittedRows = <ServiceRowState>[];

  /// Aggregate listenable feeding the footer count + chip badges. Re-derived
  /// whenever a row's `included` toggles (rows mutate their own [ServiceRowState]
  /// notifier; this bumps so the derived widgets recompute without a full-tree
  /// `setState`).
  final _AggregateNotifier _aggregate = _AggregateNotifier();

  // Captured in initState so dispose() never touches `ref` — under Riverpod
  // 3.x using `ref` in dispose() throws. Hold the keepAlive manager instead.
  late final ScreenProtectionManager _screenProtection;

  /// The live handle on the 503 RETRY snack, when one is up.
  ///
  /// VelvetSnack lives on the app's ROOT `Overlay` (see `velvet_snack_host.dart`),
  /// so a snack posted here outlives this route exactly like the old
  /// `ScaffoldMessenger`-backed bar did. That is harmless for a plain
  /// confirmation snack, and NOT harmless for the retry snack specifically: its
  /// action is bound to `_save` on a State that a `pop` has since disposed. Its
  /// 8 s dwell (`VelvetSnackMotion.dwellWithAction`) is the only real timeout —
  /// unlike the old `SnackBar`, VelvetSnack does not disable its dwell timer
  /// just because an action is present — but the route can still be popped well
  /// before that timer fires, so [dispose] reclaims the handle explicitly.
  /// Only the retry snack is tracked: the plain success/info snacks never carry
  /// a callback into this State, so there is nothing on them dispose needs to
  /// reclaim.
  VelvetSnackHandle? _retrySnack;

  /// True while the NEXT [_save] is a retry issued from the 503 bar's action.
  ///
  /// A 503 from the backend's own advisory-lock ceiling rolled the batch back,
  /// so a retry is clean. A 503 synthesised by an EDGE PROXY after the backend
  /// already committed is byte-identical from here, and the retry then re-POSTs
  /// an accepted batch. Real idempotency needs a server-honoured request key
  /// that does not exist yet, and inventing a header the backend ignores would
  /// only look like protection — so the interim mitigation is to stop
  /// MISREPORTING the outcome: a 409 arriving on a retried save is reported as
  /// "this may already have saved, go check", never as a plain duplicate.
  bool _retryingAfterBusy = false;

  @override
  void initState() {
    super.initState();
    // SEC MEDIUM: ref-counted screenshot guard (single app-wide owner;
    // the manager is internally !kDebugMode-guarded).
    _screenProtection = ref.read(screenProtectionProvider)..acquire();

    // The approved-category list is a keepAlive root cache: a category an admin
    // approved since it was last read would be missing from the picker until
    // restart. Re-fetch on open, unless inside the 30 s entry floor or already
    // in flight. This screen watches the provider, so the
    // invalidate re-fetches at once (the previous value is retained while the
    // reload is in flight — Riverpod's seamless invalidate).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        refreshCategoryCataloguesIfOlderThan(ref, kCategoryEntryFloor);
      }
    });

    // Snapshot the existing catalogue once.
    //
    // `asData?.value`, NOT `.value` — this comment used to assert that `.value`
    // "is null while the provider is loading/errored", which is false:
    // `AsyncValue.value` hands back RETAINED previous data in AsyncLoading and
    // AsyncError. Since N2 `servicesListProvider` is a view over
    // `masterServiceCatalogProvider`, whose header documents that hazard — a
    // logout leaves it errored while still holding the PREVIOUS master's
    // catalogue — so `.value` could have seeded `_appending` and the exclusion
    // set from another account's services on a shared device. `asData?.value`
    // is null in every non-AsyncData state, giving the empty set: "exclude
    // nothing", which is exactly the SETUP behaviour and is the correct
    // degradation — see [_ownedDurationsByType] on why over-blocking would be
    // the worse failure.
    final List<MasterService> existing =
        ref.read(servicesListProvider).asData?.value ?? const <MasterService>[];
    _appending = existing.isNotEmpty;
    _ownedDurationsByType = _durationsByType(existing);
    _ownedByType = _servicesByType(existing);
  }

  /// `serviceTypeId → [service, …]` in catalogue order. Rows without a type
  /// id cannot be matched and are skipped.
  static Map<String, List<MasterService>> _servicesByType(
    List<MasterService> services,
  ) {
    final Map<String, List<MasterService>> out =
        <String, List<MasterService>>{};
    for (final MasterService s in services) {
      if (s.serviceTypeId case final String id when id.isNotEmpty) {
        (out[id] ??= <MasterService>[]).add(s);
      }
    }
    return out;
  }

  /// Groups [services] into `serviceTypeId → {durationMinutes}`. Every copy of
  /// a type contributes its own duration, so two copies never collapse into
  /// one entry. Rows without a type id cannot be matched and are skipped.
  static Map<String, Set<int>> _durationsByType(List<MasterService> services) {
    final Map<String, Set<int>> out = <String, Set<int>>{};
    for (final MasterService s in services) {
      if (s.serviceTypeId case final String id when id.isNotEmpty) {
        (out[id] ??= <int>{}).add(s.durationMinutes);
      }
    }
    return out;
  }

  /// Groups [services] into `serviceTypeId → {(durationMinutes, name key)}`,
  /// the name key canonicalised by [serviceNameKey] (blank = the type name) so
  /// it compares with [ServiceRowState.effectiveNameKey]. The type-name
  /// fallback is the service's own `serviceTypeNameUk`, else the loaded row's
  /// catalogue name — the same [ServiceRowState.nameUk] the row side falls
  /// back to. Rows without a type id cannot be matched and are skipped.
  Map<String, Set<(int, String)>> _copyKeysByType(
    List<MasterService> services,
  ) {
    final Map<String, Set<(int, String)>> out = <String, Set<(int, String)>>{};
    for (final MasterService s in services) {
      if (s.serviceTypeId case final String id when id.isNotEmpty) {
        String name = s.name;
        if (name.trim().isEmpty) name = s.serviceTypeNameUk ?? '';
        if (name.trim().isEmpty) {
          name = _typeRows[id]?.firstOrNull?.nameUk ?? '';
        }
        (out[id] ??= <(int, String)>{}).add((
          s.durationMinutes,
          serviceNameKey(name),
        ));
      }
    }
    return out;
  }

  /// True when an included row is an exact duplicate — of an existing copy
  /// ([ServiceRowState.durationTaken]) or of another row of its type in this
  /// session ([ServiceRowState.copyCollision], phase 471).
  static bool _isBlocked(ServiceRowState row) =>
      row.durationTaken || (row.included && row.copyCollision);

  /// The footer's single pass over every loaded row: the count the save would
  /// create and whether any included row blocks it (phase 471 folded the old
  /// separate duration-taken scan into this one).
  ({int total, bool blocked}) _footerScan() {
    var total = 0;
    var blocked = false;
    for (final rows in _rowsByCategory.values) {
      for (final row in rows) {
        if (!row.included) continue;
        total++;
        if (!blocked && _isBlocked(row)) blocked = true;
      }
    }
    return (total: total, blocked: blocked);
  }

  // -------------------------------------------------------------------------
  // Phase 471 — copy rows («+ додати ще» / «Прибрати») + pair check
  // -------------------------------------------------------------------------

  /// Re-runs the pair check for [typeId]: an included row collides when an
  /// EARLIER included row of the same type has the same duration and the same
  /// effective name (trimmed, lower-cased, blank = type name) — backend 464's
  /// rule. Only the later row of a pair is marked. Returns true when any
  /// row's state flipped.
  bool _recheckType(String typeId) {
    if (kDebugMode) _pairCheckRuns++;
    final rows = _typeRows[typeId];
    if (rows == null) return false;
    var changed = false;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      var collides = false;
      if (row.included) {
        final int? d = row.durationMinutes;
        if (d != null) {
          final String key = row.effectiveNameKey;
          for (var j = 0; j < i && !collides; j++) {
            final other = rows[j];
            collides =
                other.included &&
                other.durationMinutes == d &&
                other.effectiveNameKey == key;
          }
        }
      }
      if (row.copyCollision != collides) {
        row.copyCollision = collides;
        changed = true;
      }
    }
    return changed;
  }

  /// A row's include / mode / taken state changed: re-check its type, then
  /// let the footer + chip badges re-derive.
  void _onRowChanged(String typeId) {
    _recheckType(typeId);
    _notifyAggregate();
  }

  /// A real duration / name edit on a row (the card reports text changes
  /// only, never caret moves, and reports each edit once). Bumps the footer
  /// only when the pair check or the row's taken state flipped, so plain
  /// typing stays local.
  void _onPairFieldEdited(String typeId, {required bool takenFlipped}) {
    if (_recheckType(typeId) || takenFlipped) _notifyAggregate();
  }

  /// The category row list holding [row] (by identity), or null.
  List<ServiceRowState>? _categoryListOf(ServiceRowState row) {
    for (final rows in _rowsByCategory.values) {
      if (rows.any((r) => identical(r, row))) return rows;
    }
    return null;
  }

  /// «+ додати ще»: adds an included copy row of [source]'s type right after the
  /// type's last row, with an empty duration (phase 472 D4).
  void _addCopy(ServiceRowState source) {
    final String typeId = source.serviceTypeId;
    final group = _typeRows[typeId];
    final categoryRows = _categoryListOf(source);
    if (group == null || categoryRows == null) return;
    var nextIndex = 1;
    for (final r in group) {
      if (r.copyIndex >= nextIndex) nextIndex = r.copyIndex + 1;
    }
    // Phase 472 (D4): the copy starts with an empty duration.
    final copy = ServiceRowState.copyOf(source, copyIndex: nextIndex);
    final ServiceRowState previous = group.last;
    setState(() {
      final int at = categoryRows.indexWhere((r) => identical(r, previous));
      categoryRows.insert(at + 1, copy);
      group.add(copy);
    });
    _onRowChanged(typeId);
    _revealCopy(
      copy,
      previous,
      focusAtTap: FocusManager.instance.primaryFocus,
      token: ++_revealToken,
    );
  }

  /// Phase 472 audit — the live reveal loop's token. Each «+ додати ще» tap
  /// takes a fresh one (so only the latest reveal runs) and a user drag of
  /// the list bumps it (so the loop never fights the master's scroll).
  int _revealToken = 0;

  /// A reveal started with [token] may continue.
  bool _revealLive(int token) => mounted && token == _revealToken;

  /// A user drag on the setup list (depth 0 — never a text field's own
  /// scrollable) cancels a running reveal; programmatic scrolls carry no
  /// drag details.
  bool _onScrollStart(ScrollStartNotification n) {
    if (n.depth == 0 && n.dragDetails != null) _revealToken++;
    return false;
  }

  /// Phase 472 — after «+ додати ще»: focuses the new [copy]'s duration well
  /// and scrolls its card fully into view, both starting in the first frame
  /// after the tap. When the copy is not laid out yet (inserted past the
  /// list's cache extent) the [previous] row is scrolled to first, then the
  /// copy is retried once. Focus moves unless the master put it into another
  /// field meanwhile (see [_focusUnmovedSinceTap]).
  void _revealCopy(
    ServiceRowState copy,
    ServiceRowState previous, {
    required FocusNode? focusAtTap,
    required int token,
    bool retried = false,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_revealLive(token)) return;
      final BuildContext? target = _rowWrapperKeys[copy.keyId]?.currentContext;
      if (target == null) {
        final BuildContext? prev =
            _rowWrapperKeys[previous.keyId]?.currentContext;
        if (retried || prev == null) return;
        await Scrollable.ensureVisible(
          prev,
          duration: _revealDuration,
          curve: Curves.easeOutCubic,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
        if (_revealLive(token)) {
          _revealCopy(
            copy,
            previous,
            focusAtTap: focusAtTap,
            token: token,
            retried: true,
          );
        }
        return;
      }
      if (_focusUnmovedSinceTap(focusAtTap, previous)) {
        copy.durationFocus.requestFocus();
      }
      await _settleInView(target, token);
    });
  }

  /// True unless focus moved into another field after the «+ додати ще» tap:
  /// it is still on the node focused at the tap, that node was detached (a
  /// rebuild of the row above disposed it), nothing is focused, or it sits on
  /// the row above's duration well (where a rebuild can hand it).
  bool _focusUnmovedSinceTap(FocusNode? atTap, ServiceRowState previous) {
    final FocusNode? now = FocusManager.instance.primaryFocus;
    if (identical(now, atTap)) return true;
    if (atTap != null && atTap.context == null) return true;
    if (now == null || now is FocusScopeNode) return true;
    return identical(now, previous.durationFocus);
  }

  /// Keeps [target]'s card fully on screen while the layout above it settles
  /// (the row above grows as its name well animates in; the focused field's
  /// caret reveal may interrupt a pass). Short passes back to back, ending
  /// once two in a row leave the scroll offset where it was — or as soon as
  /// [token] goes stale (a user drag, or a newer «+ додати ще» tap).
  Future<void> _settleInView(BuildContext target, int token) async {
    var idle = 0;
    for (var pass = 0; pass < _revealMaxPasses && idle < 2; pass++) {
      if (!_revealLive(token) || !target.mounted) return;
      final ScrollPosition? position = Scrollable.maybeOf(target)?.position;
      final double? before = position?.pixels;
      await Scrollable.ensureVisible(
        target,
        duration: _revealDuration,
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      if (position == null || position.pixels == before) {
        idle++;
        await WidgetsBinding.instance.endOfFrame;
      } else {
        idle = 0;
      }
    }
  }

  static const Duration _revealDuration = Duration(milliseconds: 140);

  /// Upper bound on [_settleInView] passes — a layout that never settles
  /// cannot keep scrolling forever.
  static const int _revealMaxPasses = 6;

  /// «Прибрати»: removes [row]. Removing the primary row promotes the next
  /// one (it keeps its values); the row is disposed after the frame that
  /// unmounts its card.
  void _removeRow(ServiceRowState row) {
    final String typeId = row.serviceTypeId;
    final group = _typeRows[typeId];
    final categoryRows = _categoryListOf(row);
    if (group == null || categoryRows == null || group.length < 2) return;
    setState(() {
      group.removeWhere((r) => identical(r, row));
      categoryRows.removeWhere((r) => identical(r, row));
      // Release the removed row's wrapper key; a promoted row's old copy key
      // is released too — it rebuilds under the primary id.
      _rowWrapperKeys.remove(row.keyId);
      if (row.copyIndex == 0) {
        final ServiceRowState promoted = group.first;
        _rowWrapperKeys.remove(promoted.keyId);
        promoted.copyIndex = 0;
      }
    });
    _disposeAfterFrame(<ServiceRowState>[row]);
    _onRowChanged(typeId);
  }

  @override
  void dispose() {
    _screenProtection.release();
    // Kill the retry snack with the route. `_save` also refuses to run unmounted.
    //
    // `_retrySnack` targets a `_VelvetSnackScopeState` that lives on the
    // app's ROOT `Overlay`, with its own lifecycle independent of this
    // screen's route (see velvet_snack_host.dart's file-level doc on why a
    // VelvetSnack survives a route pop) — it deliberately outlives this
    // disposing `State` by design. Calling `dismiss()` on it here is not a
    // use-after-unmount: do not "fix" this into a `mounted`/context guard.
    //
    // What the tests actually pin: this `dismiss()` ALONE satisfies the
    // disposed-retry test and its control (QA mutation-probed the `mounted`
    // guard out and both stayed green — dismissing the snack removes the
    // button, so nothing is left to tap). The guard is therefore DEFENSIVE, not
    // covered: it catches a tap already dispatched when the pop lands, a race a
    // widget test cannot schedule deterministically. Keep it — "untested" here
    // means "untestable at this tier", not "redundant".
    unawaited(_retrySnack?.dismiss());
    _retrySnack = null;
    // Final wholesale cleanup — every row (across every loaded category, even
    // collapsed ones whose controllers we deliberately retained) is disposed
    // here.
    for (final rows in _rowsByCategory.values) {
      for (final row in rows) {
        row.dispose();
      }
    }
    _aggregate.dispose();
    super.dispose();
  }

  /// Bumps the aggregate listenable so the footer count + chip badges re-derive.
  void _notifyAggregate() => _aggregate.bump();

  // -------------------------------------------------------------------------
  // Category expand / collapse + lazy service-type load
  // -------------------------------------------------------------------------

  Future<void> _toggleCategory(String slug) async {
    if (_expanded.contains(slug)) {
      // Collapse is a pure visibility change: drop the slug from `_expanded`
      // ONLY. The category's rows + their controllers (entered duration / price)
      // are retained, keyed by service-type id, so re-expanding restores the
      // values and hits the "already loaded → no refetch" branch below.
      //
      // A deselected category must contribute nothing: drop each retained row
      // from the footer count AND the bulk-save payload by resetting `included`
      // (both derive from `r.included` across ALL loaded categories). Typed
      // duration / price text survives on the retained controllers, so
      // re-toggling restores values — only the include flag resets.
      //
      // Defense-in-depth: clear any stale save-time flag on the retained rows so a
      // re-expanded row never resurrects a flag predating a later field edit. The
      // rows may not be loaded yet, so guard for a null/absent list.
      setState(() {
        _expanded.remove(slug);
        for (final row in _rowsByCategory[slug] ?? const <ServiceRowState>[]) {
          row.included = false;
          row.clearFlag();
          row.clearServerErrors();
        }
      });
      _notifyAggregate();
      return;
    }

    setState(() => _expanded.add(slug));
    _notifyAggregate();
    // Already loaded earlier in this session — re-expand without refetch.
    if (_rowsByCategory.containsKey(slug)) return;
    await _loadCategory(slug);
  }

  Future<void> _loadCategory(String slug) async {
    // In-flight guard: ignore concurrent fetches (rapid expand/collapse/expand,
    // or a retry tap while a load is already running for this category).
    if (_loadingCategories.contains(slug)) return;
    setState(() {
      _loadingCategories.add(slug);
      _erroredCategories.remove(slug);
    });
    try {
      final List<ServiceTypeOption> types = await ref.read(
        serviceTypesProvider(slug).future,
      );
      if (!mounted) return;
      // A REFETCH (see [_suggestServiceType]) must not wipe what the master has
      // already typed, so surviving service-types keep their EXISTING
      // [ServiceRowState] — same object, so its controllers, include flag and
      // pricing mode all carry over, and the mounted card's `identical(row)`
      // check means it does not even re-attach its listeners. Only types that
      // vanished from the catalogue are dropped, and their controllers are
      // disposed AFTER the frame that unmounts their card, never during it.
      // Phase 471: carried per TYPE, so a type's «+ додати ще» copies survive a
      // refetch together with its primary row, in order.
      final Map<String, List<ServiceRowState>> carried =
          <String, List<ServiceRowState>>{};
      for (final row in _rowsByCategory[slug] ?? const <ServiceRowState>[]) {
        (carried[row.serviceTypeId] ??= <ServiceRowState>[]).add(row);
      }
      setState(() {
        final rows = <ServiceRowState>[];
        for (final t in types) {
          final List<ServiceRowState> typeRows =
              carried.remove(t.id) ??
              <ServiceRowState>[
                ServiceRowState(
                  serviceTypeId: t.id,
                  nameUk: t.nameUk,
                  // Seeded at row-construction time, immutable for the row's
                  // life. An owned type is selectable (phase 468) but blocks
                  // the save while its duration matches an existing copy.
                  alreadyAdded: _ownedDurationsByType.containsKey(t.id),
                  ownedDurations: _ownedDurationsByType[t.id] ?? const <int>{},
                  // Phase 472: the (duration, canonical name) keys
                  // [ServiceRowState.durationTaken] compares with.
                  ownedServices: _ownedByType[t.id] ?? const <MasterService>[],
                ),
              ];
          _typeRows[t.id] = typeRows;
          rows.addAll(typeRows);
        }
        _rowsByCategory[slug] = rows;
        _loadingCategories.remove(slug);
      });
      final List<ServiceRowState> orphans = <ServiceRowState>[
        for (final entry in carried.entries) ...entry.value,
      ];
      for (final id in carried.keys) {
        _typeRows.remove(id);
      }
      // Release the orphans' wrapper keys too — their cards unmount on this
      // frame and their type ids are gone from the catalogue.
      for (final row in orphans) {
        _rowWrapperKeys.remove(row.keyId);
      }
      _disposeAfterFrame(orphans);
    } on Object catch (e, st) {
      if (kDebugMode) {
        log(
          '_loadCategory($slug) failed: ${_errorSummary(e)}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      if (!mounted) return;
      setState(() {
        _loadingCategories.remove(slug);
        _erroredCategories.add(slug);
      });
    }
  }

  /// Disposes [orphans] once the frame that removed their cards from the tree
  /// has been laid out.
  ///
  /// Ordering is the whole point. Each [ServiceRowState] owns four
  /// [TextEditingController]s that its mounted [ServiceTypeRowCard] both reads
  /// and listens to; disposing while the card is still up trades a stale-list
  /// bug for a use-after-dispose. A post-frame callback is not tied to this
  /// element's lifetime, so the disposal still happens even if the screen itself
  /// is popped in the same frame — which matters, because these rows have
  /// already been removed from `_rowsByCategory` and so are no longer reachable
  /// by [dispose]'s wholesale sweep. Exactly one owner, either way.
  void _disposeAfterFrame(List<ServiceRowState> orphans) {
    if (orphans.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final row in orphans) {
        row.dispose();
      }
    });
  }

  // -------------------------------------------------------------------------
  // Counts
  // -------------------------------------------------------------------------

  int _includedCount(String slug) {
    final rows = _rowsByCategory[slug];
    if (rows == null) return 0;
    return rows.where((r) => r.included).length;
  }

  // -------------------------------------------------------------------------
  // Validation + assembly + save
  // -------------------------------------------------------------------------

  /// Parses a positive number from a price field. Accepts ',' or '.' as the
  /// decimal separator. Returns null when blank or unparseable.
  double? _parsePrice(String raw) {
    final trimmed = raw.trim().replaceAll(',', '.');
    if (trimmed.isEmpty) return null;
    final value = double.tryParse(trimmed);
    if (value == null || value <= 0) return null;
    return value;
  }

  /// Returns the cross-field range error for a row, or null when valid / N/A.
  String? _rangeErrorFor(ServiceRowState row, AppLocalizations l10n) {
    if (row.pricingMode != ServicePriceType.range) return null;
    final min = _parsePrice(row.min.text);
    final max = _parsePrice(row.max.text);
    if (min == null || max == null) return null;
    if (max <= min) return l10n.pricingRangeHint;
    return null;
  }

  /// Builds the bulk payload, returning null (and flagging the offending rows)
  /// when any included row is incomplete or invalid.
  List<MasterServiceBulkItem>? _assemble() {
    final items = <MasterServiceBulkItem>[];
    // Keyed by row identity: since phase 471 a type can have several rows.
    final reasons = Map<ServiceRowState, RowFlagReason>.identity();
    // Capture the row↔submitted-item ordering so a 400's items[i].field path
    // resolves back to the originating row. Rebuilt from scratch each call.
    _submittedRows.clear();

    for (final rows in _rowsByCategory.values) {
      for (final row in rows) {
        if (!row.included) continue;
        final id = row.serviceTypeId;
        // Phase 471: only a non-blank custom name is sent.
        final String? name = row.customName;
        final duration = row.durationMinutes;
        // Client-side mirror of the backend @Max(480) guard, so the common
        // over-8h case is caught before the network round-trip.
        final bool durationTooLong = duration != null && duration > 480;
        final durationOk = duration != null && duration >= 1 && duration <= 480;

        if (row.pricingMode == ServicePriceType.fixed) {
          final price = _parsePrice(row.fixed.text);
          final priceOk = price != null;
          if (!durationOk || !priceOk) {
            reasons[row] = durationTooLong
                ? RowFlagReason.durationTooLong
                : (!durationOk && !priceOk
                      ? RowFlagReason.missingBoth
                      : (!durationOk
                            ? RowFlagReason.missingDuration
                            : RowFlagReason.missingPrice));
            continue;
          }
          items.add(
            MasterServiceBulkItem(
              serviceTypeId: id,
              durationMinutes: duration,
              priceType: ServicePriceType.fixed,
              price: price,
              name: name,
            ),
          );
          _submittedRows.add(row);
        } else {
          final min = _parsePrice(row.min.text);
          final max = _parsePrice(row.max.text);
          final priceOk = min != null && max != null && max > min;
          if (!durationOk || !priceOk) {
            reasons[row] = durationTooLong
                ? RowFlagReason.durationTooLong
                : (!durationOk && !priceOk
                      ? RowFlagReason.missingBoth
                      : (!durationOk
                            ? RowFlagReason.missingDuration
                            : RowFlagReason.invalidRange));
            continue;
          }
          items.add(
            MasterServiceBulkItem(
              serviceTypeId: id,
              durationMinutes: duration,
              priceType: ServicePriceType.range,
              priceMin: min,
              priceMax: max,
              name: name,
            ),
          );
          _submittedRows.add(row);
        }
      }
    }

    // Flag each offending row on its own notifier — only those cards rebuild.
    for (final rows in _rowsByCategory.values) {
      for (final row in rows) {
        row.flagReason = reasons[row] ?? RowFlagReason.none;
      }
    }
    if (reasons.isNotEmpty) return null;
    return items;
  }

  /// Scrolls the topmost flagged-and-included row into view after a blocked
  /// save, so a master never stares at a silently-failed CTA with the offending
  /// row below the fold.
  ///
  /// "Topmost" is resolved by global vertical position across all currently
  /// laid-out rows — collapsed categories build no rows, so their flagged rows
  /// (if any) are simply skipped here; an included flagged row only exists under
  /// an expanded category, so the visible set always contains the candidates.
  ///
  /// [ids] overrides the collector for callers whose rows are deliberately NOT
  /// included — [_flagRowsNowOwned] switches its rows off as part of the fix, so
  /// the include-gated default would find nothing to scroll to.
  void _scrollToFirstFlagged({Set<String>? ids}) {
    // Collect the flagged-row ids (client flag OR mapped-back server error);
    // bail early when nothing is flagged.
    final flaggedIds =
        ids ??
        <String>{
          for (final rows in _rowsByCategory.values)
            for (final row in rows)
              if (row.included &&
                  (row.flagReason != RowFlagReason.none ||
                      row.serverDurationError != null ||
                      row.serverPriceError != null ||
                      row.serverNameError != null))
                row.keyId,
        };
    if (flaggedIds.isEmpty) return;

    // Resolve after the current frame so freshly-flagged cards (which expand to
    // show their inline hints) are laid out before we measure / scroll.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      BuildContext? topContext;
      double? topDy;
      for (final id in flaggedIds) {
        final context = _rowWrapperKeys[id]?.currentContext;
        // Null when the row isn't laid out (e.g. its category collapsed) — skip.
        if (context == null) continue;
        final renderObject = context.findRenderObject();
        if (renderObject is! RenderBox || !renderObject.hasSize) continue;
        final dy = renderObject.localToGlobal(Offset.zero).dy;
        if (topDy == null || dy < topDy) {
          topDy = dy;
          topContext = context;
        }
      }

      final target = topContext;
      if (target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
        alignment: 0.1,
      );
    });
  }

  /// Synchronous single-flight guard for [_save], set before the first
  /// `await` (same pattern as `day_hours_sheet.dart`'s): the footer's
  /// `saving` flag only bites after a rebuild, so same-frame taps each ran a
  /// save. It only DROPS a repeat; the CTA keeps its plain `onPressed`, so
  /// the first tap behaves exactly as before (no spinner during the 409
  /// `_flagRowsNowOwned` refetch).
  bool _saveInFlight = false;

  Future<void> _save() async {
    if (_saveInFlight) return;
    _saveInFlight = true;
    try {
      await _runSave();
    } finally {
      _saveInFlight = false;
    }
  }

  Future<void> _runSave() async {
    // The 503 retry bar posts on the ROOT messenger and therefore survives a
    // pop, action and all. Without this guard a tap after leaving runs the whole
    // method against a defunct element — `AppLocalizations.of(context)` on the
    // very next line throws on a deactivated element, and `ref.read` would
    // re-POST an abandoned selection even if it did not. [dispose] also closes
    // that bar; this guard covers the tap already in flight.
    if (!mounted) return;
    // Consume the retry marker for THIS attempt: it changes only how a 409 is
    // reported (see [_retryingAfterBusy]), and must not leak into the next,
    // freshly-initiated save.
    final bool afterBusyRetry = _retryingAfterBusy;
    _retryingAfterBusy = false;

    final l10n = AppLocalizations.of(context);
    // Defensive: the CTA is disabled while a row is an exact duplicate (taken
    // duration or phase-471 copy collision), but a same-frame tap could still
    // land here — never send a known duplicate.
    final Set<String> blockedIds = <String>{
      for (final rows in _rowsByCategory.values)
        for (final row in rows)
          if (_isBlocked(row)) row.keyId,
    };
    if (blockedIds.isNotEmpty) {
      _scrollToFirstFlagged(ids: blockedIds);
      return;
    }
    final items = _assemble();
    if (items == null || items.isEmpty) {
      // Blocked save: surface the first flagged row so the failure is visible.
      _scrollToFirstFlagged();
      return;
    }

    // Clear any server errors mapped from a PRIOR attempt so this response's
    // field errors are the sole authority (and stale rims vanish on retry).
    for (final row in _submittedRows) {
      row.clearServerErrors();
    }

    final created = await ref.read(serviceSetupProvider.notifier).submit(items);
    if (!mounted) return;

    if (created != null) {
      // Success — refresh the catalogue views and pop back to the list.
      invalidateMasterServiceCatalogues(ref);
      showSuccessSnack(context, l10n.serviceSetupSuccess);
      _leave();
      return;
    }

    // Failure — read the typed error from the notifier state.
    final error = ref.read(serviceSetupProvider).error;

    // 503: the per-master bulk lock was held past the backend's 3 s ceiling.
    // The batch is all-or-nothing, so NOTHING was written — the selection is
    // still valid and a retry is the correct next action. Keep the master on
    // the screen with their whole configuration intact and hand them an
    // explicit RETRY, rather than a dead-end error they can only dismiss.
    // The copy must never imply the services were saved (they were not).
    if (error is BulkSetupBusyFailure) {
      _showErrorSnack(
        error.userMessage(context),
        onRetry: () {
          // Mark the NEXT save as a retry so a 409 landing on it is reported as
          // "this may already have saved" rather than as a plain duplicate —
          // see [_retryingAfterBusy].
          _retryingAfterBusy = true;
          _save();
        },
      );
      return;
    }

    // 429: a per-master write bucket is exhausted (bulk 10/min, single writes
    // 60/min). Deliberately NO retry action — see [_showErrorSnack]. The
    // selection stays untouched and the CTA stays live, so the master re-fires
    // it when they choose to.
    if (error is ServiceRateLimitedFailure) {
      _showErrorSnack(error.userMessage(context));
      return;
    }

    // 409 DUPLICATE_SERVICE: one selected type is already in the master's menu,
    // and the whole batch was rolled back. In APPEND mode the owned types are
    // already un-includable, so reaching here means the catalogue changed under
    // us (another device, or a type added since this screen mounted).
    //
    // Keep the master here with their selection rather than forcing a
    // navigation away — their unsaved configuration would be lost.
    //
    // The invalidation refreshes the LIST screen behind us so it is correct on
    // return. It still does NOT re-seed `_ownedDurationsByType` / `alreadyAdded`:
    // those are an initState snapshot precisely so rows cannot mutate under a
    // master mid-edit. What DOES happen now is narrower and stated out loud —
    // [_flagRowsNowOwned] re-reads the catalogue and switches off only the rows
    // the refreshed list actually claims, marking each `alreadyInMenu`. Leaving
    // them selectable made a blind re-save 409 again with no explanation; making
    // them inert silently was the other bad option. Every other selection, and
    // every typed value, is untouched.
    //
    // On a save that was itself a 503 retry the batch's fate is genuinely
    // unknown (an edge-proxy 503 can follow a committed write), so the copy
    // switches to the one that claims neither outcome — see [_retryingAfterBusy].
    if (error is ServiceDuplicateFailure) {
      invalidateMasterServiceCatalogues(ref);
      _showErrorSnack(
        afterBusyRetry
            ? l10n.serviceSetupErrDuplicateAfterRetry
            : error.userMessage(context),
      );
      await _flagRowsNowOwned();
      return;
    }

    // Backend per-field validation (HTTP 400): surface each error inline on the
    // matching service row instead of the generic snackbar. Only fall through
    // to the snackbar when NO field key maps to a submitted row.
    if (error is ValidationFailure &&
        _applyServerFieldErrors(error.fieldErrors, l10n)) {
      _scrollToFirstFlagged();
      return;
    }

    final message = error is Failure
        ? error.userMessage(context)
        : l10n.errUnknown;
    _showErrorSnack(message);
  }

  /// Log-safe summary of a caught error: its type and, for a server failure,
  /// the status code — never the message, which can carry a request URL.
  static String _errorSummary(Object e) => switch (e) {
    ServerFailure(:final int? statusCode) => 'ServerFailure($statusCode)',
    _ => '${e.runtimeType}',
  };

  /// Re-reads the master's catalogue after a 409 and switches OFF every
  /// currently-included row the refreshed list now claims, flagging each
  /// [RowFlagReason.alreadyInMenu] so the change is stated rather than silent.
  ///
  /// Best-effort by design: the snackbar has already reported the clash, so a
  /// failed re-read costs a sharper follow-up message, never correctness. The
  /// row's immutable `alreadyAdded` seed is deliberately NOT touched — that
  /// would re-render the row inert mid-edit, which is exactly the mutation the
  /// initState snapshot exists to prevent.
  Future<void> _flagRowsNowOwned() async {
    final List<MasterService> refreshed;
    try {
      refreshed = await ref.read(servicesListProvider.future);
    } on Object catch (e, st) {
      if (kDebugMode) {
        log(
          '_flagRowsNowOwned: catalogue re-read failed: ${_errorSummary(e)}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      return;
    }
    if (!mounted) return;

    // Phase 468/471: a type may legitimately be owned more than once, so only
    // a row whose (type, duration, canonical name) triple the refreshed list
    // now claims is the duplicate — backend V233's rule. A copy at another
    // duration, or under another name, stays selected; a renamed row whose
    // name the 409 was about is caught too.
    final owned = _copyKeysByType(refreshed);
    if (owned.isEmpty) return;

    final flagged = <String>{};
    for (final rows in _rowsByCategory.values) {
      for (final row in rows) {
        if (!row.included) continue;
        final int? duration = row.durationMinutes;
        final Set<(int, String)>? ownedKeys = owned[row.serviceTypeId];
        if (ownedKeys == null ||
            duration == null ||
            !ownedKeys.contains((duration, row.effectiveNameKey))) {
          continue;
        }
        // Off FIRST: `included` is what makes a row submittable, so clearing it
        // is what actually unblocks the next save. The flag is the explanation
        // that keeps the change from reading as the app losing the selection.
        row.included = false;
        row.flagReason = RowFlagReason.alreadyInMenu;
        flagged.add(row.keyId);
      }
    }
    if (flagged.isEmpty) return;
    _notifyAggregate();
    // Pass the ids explicitly: the default collector only considers INCLUDED
    // rows, and these were just excluded.
    _scrollToFirstFlagged(ids: flagged);
  }

  // -------------------------------------------------------------------------
  // Missing category / service type — request affordances
  // -------------------------------------------------------------------------
  //
  // Two requests with DIFFERENT scopes, so each lives inside the scope it acts
  // on rather than behind one shared control with a fork:
  //   • a missing CATEGORY takes no argument → the strip above the chip Wrap;
  //   • a missing SERVICE TYPE needs a `categoryName` → the tail of each
  //     expanded category's row list, which supplies it unambiguously.
  // Both dialogs already exist and own their own submit/validation/error paths;
  // the screen only opens them and reports the outcome.

  /// Opens the suggest-a-category dialog. On success the approved-category list
  /// is invalidated so a category approved out-of-band shows up without a
  /// restart. (The request itself needs moderation, so the new category will not
  /// normally appear immediately — the refresh is for the already-approved case
  /// and costs nothing otherwise.)
  Future<void> _requestCategory() async {
    final l10n = AppLocalizations.of(context);
    final bool? sent = await showCategoryRequestDialog(context);
    if (!mounted || sent != true) return;
    ref.invalidate(approvedCategoriesProvider);
    showSuccessSnack(context, l10n.categoryRequestSuccess);
  }

  /// Opens the suggest-a-service-type dialog for [categorySlug].
  ///
  /// [categorySlug] is the System-B wire name the dialog forwards to the
  /// backend; [categoryLabel] is the Ukrainian display name shown in the
  /// prompt's own copy. They are distinct values — do not pass the label.
  Future<void> _suggestServiceType(String categorySlug) async {
    final l10n = AppLocalizations.of(context);
    final bool? sent = await showServiceTypeSuggestionDialog(
      context,
      categoryName: categorySlug,
    );
    if (!mounted || sent != true) return;
    showSuccessSnack(context, l10n.serviceTypeSuggestSuccess);
    // Drop this category's cached type list so an auto-approved suggestion can
    // appear immediately.
    ref.invalidate(serviceTypesProvider(categorySlug));
    // The invalidate ALONE is dead: `_toggleCategory` returns early on
    // `_rowsByCategory.containsKey(slug)`, so nothing in this session would ever
    // re-read the provider — not a collapse, not a re-expand — and a master who
    // was just told their suggestion was submitted could not see it without a
    // cold restart. Refetch here, where the promise was made. `_loadCategory`
    // carries surviving rows over by identity, so no typed duration or price is
    // lost to the refresh.
    await _loadCategory(categorySlug);
  }

  /// Leaves the screen, POPPING whenever there is a stack to pop.
  ///
  /// Popping is the contract the services list depends on: its `_openAndRefresh`
  /// awaits the `context.push` Future and re-invalidates the category /
  /// service-type caches when it completes. `context.go` would REPLACE the stack,
  /// so that Future would never complete, the invalidation would never fire, and
  /// the await would leak. `go` therefore survives only as the fallback for the
  /// no-stack entries (deep link, cold start on this route).
  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(widget.exitRoute ?? RouteNames.services);
    }
  }

  /// Parses a 400's `fieldErrors` map, attributing each `items[<index>].<field>`
  /// entry to the originating [ServiceRowState] (via [_submittedRows], captured
  /// in submitted order by [_assemble]) and stamping the matching per-row
  /// server-error channel. Returns true when AT LEAST ONE field mapped to a
  /// submitted row — the caller only suppresses the generic snackbar then.
  bool _applyServerFieldErrors(
    Map<String, String> fieldErrors,
    AppLocalizations l10n,
  ) {
    var mappedAny = false;
    for (final entry in fieldErrors.entries) {
      final match = _itemFieldErrorPattern.firstMatch(entry.key);
      if (match == null) continue;
      final index = int.tryParse(match.group(1)!);
      if (index == null || index < 0 || index >= _submittedRows.length) {
        continue;
      }
      final row = _submittedRows[index];
      final field = match.group(2);
      if (field == 'durationMinutes') {
        // The only backend duration constraint on this payload is @Max(480), so
        // any durationMinutes error is localized to the known max copy rather
        // than echoing the server's English string.
        row.serverDurationError = l10n.serviceSetupDurationMax;
        mappedAny = true;
      } else if (field == 'price' ||
          field == 'priceMin' ||
          field == 'priceMax') {
        // No localized copy for the price constraints (rare — the client
        // validates price shape), so the server's own message is shown — but
        // only when it is short enough to BE a field hint. Anything blank or
        // oversized falls back to localized copy: a server string is untrusted
        // input, and one rendered verbatim into a row label can push the card
        // apart or spill internal detail. The interceptor's own 200-char cap is
        // a transport guard, not a layout one.
        row.serverPriceError = serverFieldMessageOr(
          entry.value,
          l10n.serviceSetupPriceInvalid,
        );
        mappedAny = true;
      } else if (field == 'name') {
        // Phase 471: the only name constraints the client cannot already
        // enforce are the backend's character allow-list (the formatter
        // mirrors it; this is the backstop), so the copy is always localized.
        row.serverNameError = l10n.serviceSetupCopyNameInvalid;
        mappedAny = true;
      }
    }
    return mappedAny;
  }

  /// Shows a floating error VelvetSnack. When [onRetry] is supplied the snack
  /// also carries a retry action, which VelvetSnack automatically dwells
  /// longer for (`VelvetSnackMotion.dwellWithAction`, 6 s) — used for the
  /// transient 503, where the only useful next step is "try that again".
  ///
  /// A retry action is offered for the 503 ONLY. Notably not for the 429: the
  /// implicit promise of a «Повторити» button is "this will work now", and while
  /// the rate-limit bucket is closed that is false by construction — the tap
  /// spends the master's next allowance on a request that cannot succeed. That
  /// snack states the wait and lets the CTA (still enabled) carry the retry on
  /// the master's own schedule.
  ///
  /// VelvetSnack pre-empts whatever is currently showing on its own
  /// (single-slot host, see `velvet_snack_host.dart`) — unlike the old
  /// `ScaffoldMessenger` FIFO queue, no manual "clear before show" step is
  /// needed here.
  void _showErrorSnack(String message, {VoidCallback? onRetry}) {
    final l10n = AppLocalizations.of(context);
    final VelvetSnackHandle handle = showErrorSnack(
      context,
      message,
      actionLabel: onRetry == null ? null : l10n.serviceSetupRetry,
      onAction: onRetry,
    );
    // Only the retry snack is tracked: it is the only one whose action can
    // outlive the route (see [_retrySnack]'s doc comment).
    _retrySnack = onRetry == null ? null : handle;
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categoriesAsync = ref.watch(approvedCategoriesProvider);
    final saving = ref.watch(serviceSetupProvider).isLoading;

    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _TopBar(
              // APPEND reframes the screen from "set up your menu" to "add
              // services"; the SETUP copy is untouched for the empty case.
              title: _appending
                  ? l10n.serviceSetupTitleAppend
                  : l10n.serviceSetupTitle,
              closeLabel: l10n.serviceSetupClose,
              onClose: _leave,
            ),
            Expanded(
              child: categoriesAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: BrandColors.accentDeep,
                  ),
                ),
                error: (e, _) {
                  final failure = e is Failure ? e : UnknownFailure(cause: e);
                  return ErrorState(
                    key: const Key('service_setup_error_state'),
                    failure: failure,
                    onRetry: () => ref.invalidate(approvedCategoriesProvider),
                  );
                },
                data: (categories) => _content(l10n, categories),
              ),
            ),
            // Footer count derives from the aggregate notifier — only the
            // footer rebuilds when a row toggles, not the whole screen.
            ListenableBuilder(
              listenable: _aggregate,
              builder: (context, _) {
                final (:total, :blocked) = _footerScan();
                return _Footer(
                  total: total,
                  saving: saving,
                  appending: _appending,
                  onSave: total == 0 || blocked ? null : _save,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// The scrollable body, virtualized: the helper note + section label + chip
  /// Wrap ride in a [SliverToBoxAdapter], while the expanded category headers +
  /// service-type rows are emitted lazily through a [SliverList] so off-screen
  /// rows are never built or painted.
  Widget _content(
    AppLocalizations l10n,
    List<ServiceCategoryOption> categories,
  ) {
    final List<_SetupSlot> slots = _expandedSlots(l10n, categories);
    // Stable key → slot index, so inserting / removing a copy row re-attaches
    // every row below to its existing element instead of remounting it. Rows
    // resolve by their cached wrapper [GlobalKey] (only rows already built
    // have one — an unbuilt row has no element to find).
    final Map<Key, int> slotIndexByKey = <Key, int>{};
    for (var i = 0; i < slots.length; i++) {
      final Key? key = switch (slots[i]) {
        _FixedSlot(:final Widget child) => child.key,
        _RowSlot(:final ServiceRowState row) => _rowWrapperKeys[row.keyId],
      };
      if (key != null) slotIndexByKey[key] = i;
    }
    return NotificationListener<ScrollStartNotification>(
      onNotification: _onScrollStart,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.lg,
              VelvetSpacing.sm,
              VelvetSpacing.lg,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Sits directly above the chip Wrap — the CATEGORY-selection
                  // surface — because that is the scope it acts on.
                  _MissingCategoryPrompt(onTap: _requestCategory),
                  const SizedBox(height: VelvetSpacing.lg),
                  _categorySection(l10n, categories),
                  const SizedBox(height: VelvetSpacing.lg),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.lg,
              0,
              VelvetSpacing.lg,
              VelvetSpacing.xl,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => switch (slots[index]) {
                  _FixedSlot(:final Widget child) => child,
                  _RowSlot(:final ServiceRowState row) => _rowCard(row),
                },
                childCount: slots.length,
                findChildIndexCallback: (key) => slotIndexByKey[key],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categorySection(
    AppLocalizations l10n,
    List<ServiceCategoryOption> categories,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: VelvetSpacing.xs),
          child: Text(
            l10n.serviceSetupSectionCategories,
            style: VelvetText.label(),
          ),
        ),
        const SizedBox(height: VelvetSpacing.sm + 2),
        // The chip Wrap derives each chip's included-count badge from the
        // aggregate, so toggling a row repaints only the chips, not the screen.
        ListenableBuilder(
          listenable: _aggregate,
          builder: (context, _) => Wrap(
            spacing: VelvetSpacing.sm,
            runSpacing: VelvetSpacing.sm,
            children: <Widget>[
              for (final c in categories)
                CategoryChip(
                  key: ValueKey<String>('cat_${c.name}'),
                  iconAsset: categoryIconOrNullFor(
                    categoryKey: c.name,
                    categoryName: c.displayName,
                  ),
                  label: c.displayName,
                  selected: _expanded.contains(c.name),
                  includedCount: _expanded.contains(c.name)
                      ? _includedCount(c.name)
                      : 0,
                  onTap: () => _toggleCategory(c.name),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Flattens the expanded categories into the flat slot list fed to the
  /// [SliverList] builder — headers, hints, and one [_RowSlot] per service-type.
  ///
  /// Returns SLOTS, not widgets, and that distinction is the point. The
  /// [SliverList] only ever *indexes* whatever this returns, so an eager
  /// `List<Widget>` made element creation lazy while leaving widget ALLOCATION
  /// eager: every one of up to ~140 rows (21 categories × ≤12 types) built its
  /// `KeyedSubtree` → `RepaintBoundary` → `Padding` → `ServiceTypeRowCard`
  /// wrapper on every screen build, including the ~139 nobody can see. A
  /// [_RowSlot] is one small object holding a reference the screen already
  /// owns; the wrapper is built in the delegate, on demand. The few fixed items
  /// per expanded category (header, empty/all-added hint, suggest prompt,
  /// spacers) stay eager as [_FixedSlot]s — they are bounded by the category
  /// count, not the type count, and keeping them as widgets keeps their keys and
  /// ordering exactly where they were.
  List<_SetupSlot> _expandedSlots(
    AppLocalizations l10n,
    List<ServiceCategoryOption> categories,
  ) {
    final active = categories
        .where((c) => _expanded.contains(c.name))
        .toList(growable: false);
    if (active.isEmpty) {
      return <_SetupSlot>[
        _FixedSlot(_EmptyHint(text: l10n.serviceSetupEmptyHint)),
      ];
    }

    final out = <_SetupSlot>[];
    for (final c in active) {
      final slug = c.name;
      final iconAsset = categoryIconOrNullFor(
        categoryKey: slug,
        categoryName: c.displayName,
      );

      if (_loadingCategories.contains(slug)) {
        out.add(
          _FixedSlot(_CategoryLoading(key: ValueKey<String>('loading_$slug'))),
        );
        continue;
      }
      if (_erroredCategories.contains(slug)) {
        out.add(
          _FixedSlot(
            _CategoryRetry(
              key: ValueKey<String>('retry_$slug'),
              onRetry: () => _loadCategory(slug),
              label: l10n.serviceTypeLoadError,
              retryLabel: l10n.serviceCategoryRetry,
            ),
          ),
        );
        continue;
      }

      final rows = _rowsByCategory[slug] ?? const <ServiceRowState>[];
      // "n з m": since phase 468 an owned type is selectable again (as a copy),
      // so `m` counts every type in the category.
      final int selectable = rows.length;
      final bool allOwned =
          rows.isNotEmpty && rows.every((r) => r.alreadyAdded);
      // The header's live "n з m" count derives from the aggregate so it tracks
      // include toggles without forcing a full-tree rebuild.
      out.add(
        _FixedSlot(
          ListenableBuilder(
            key: ValueKey<String>('group_$slug'),
            listenable: _aggregate,
            builder: (context, _) => CategoryGroupHeader(
              iconAsset: iconAsset,
              label: c.displayName,
              includedCount: _includedCount(slug),
              total: selectable,
            ),
          ),
        ),
      );
      out.add(const _FixedSlot(SizedBox(height: VelvetSpacing.md)));

      if (rows.isEmpty) {
        out.add(
          _FixedSlot(
            Padding(
              padding: const EdgeInsets.only(bottom: VelvetSpacing.md),
              child: Text(l10n.serviceTypeEmpty, style: VelvetText.body()),
            ),
          ),
        );
      } else if (allOwned) {
        // Every type here is already in the master's menu. Say so explicitly —
        // each row below can still be added again at another duration.
        out.add(
          _FixedSlot(
            Padding(
              padding: const EdgeInsets.only(bottom: VelvetSpacing.md),
              child: Text(
                l10n.serviceSetupAllAlreadyAdded,
                style: VelvetText.body(),
              ),
            ),
          ),
        );
      }

      for (final row in rows) {
        out.add(_RowSlot(row));
      }
      // Closes the category: every type it DOES offer has now been listed, so
      // this is the moment "the one I want isn't here" is actionable. It also
      // supplies the category context the suggestion dialog needs.
      out.add(
        _FixedSlot(
          Padding(
            padding: const EdgeInsets.only(bottom: VelvetSpacing.sm),
            child: _MissingServiceTypePrompt(
              key: ValueKey<String>('suggest_type_$slug'),
              categoryLabel: c.displayName,
              onTap: () => _suggestServiceType(slug),
            ),
          ),
        ),
      );
      out.add(const _FixedSlot(SizedBox(height: VelvetSpacing.sm)));
    }
    return out;
  }

  /// Builds one service-type row's wrapper, on demand from the [SliverList]
  /// delegate rather than eagerly in [_expandedSlots].
  ///
  /// Byte-for-byte the tree that used to be built up-front — outer
  /// [KeyedSubtree] carrying the per-row [GlobalKey] so a blocked save can
  /// `Scrollable.ensureVisible` this flagged row, inner [RepaintBoundary]
  /// keeping its `rowwrap_$id` [ValueKey] for test finders and capping the
  /// per-row expand/collapse animation's repaint blast radius to this one card.
  ///
  /// Phase 471: keys use [ServiceRowState.keyId] (the bare type id for the
  /// primary row, so every pre-471 key is unchanged). «+ додати ще» is offered
  /// on every row (the card shows it only while included); «Прибрати» once the
  /// type has more than one row. Phase 472 (D3): the name well opens from the
  /// card's pencil (or while the row carries a custom name).
  Widget _rowCard(ServiceRowState row) {
    final id = row.keyId;
    final bool hasCopies = (_typeRows[row.serviceTypeId]?.length ?? 1) > 1;
    final _RowCallbacks callbacks = _callbacksFor(row);
    return KeyedSubtree(
      key: _rowWrapperKey(id),
      child: RepaintBoundary(
        key: ValueKey<String>('rowwrap_$id'),
        child: Padding(
          padding: const EdgeInsets.only(bottom: VelvetSpacing.md),
          child: ServiceTypeRowCard(
            key: Key('setup_row_$id'),
            row: row,
            resolveRangeError: _rangeResolver,
            onChanged: callbacks.changed,
            onFieldEdited: callbacks.fieldEdited,
            onAddCopy: callbacks.addCopy,
            onRemove: hasCopies ? callbacks.remove : null,
            // Phase 472 (D3/D4.3): every card — owned or not, primary or
            // copy — shows its name with a pencil that edits the title in
            // place; the title shows the custom name, so a sent name is
            // never hidden.
            offerCustomName: true,
          ),
        ),
      ),
    );
  }
}

/// One entry in the [SliverList]'s flat item list.
///
/// Exists so the list can be indexed WITHOUT every row's widget wrapper having
/// been allocated first — see [_ServiceSetupScreenState._expandedSlots].
sealed class _SetupSlot {
  const _SetupSlot();
}

/// A slot whose widget is cheap and bounded by the CATEGORY count (header,
/// spacer, hint, suggest prompt), so it is built eagerly and simply carried.
final class _FixedSlot extends _SetupSlot {
  const _FixedSlot(this.child);

  final Widget child;
}

/// A slot for one service-type row: holds only the [ServiceRowState] the screen
/// already owns, and defers the card wrapper to
/// [_ServiceSetupScreenState._rowCard]. This is the one that repeats up to ~140
/// times, and the only reason this type exists.
final class _RowSlot extends _SetupSlot {
  const _RowSlot(this.row);

  final ServiceRowState row;
}

/// Lightweight bump-notifier driving the footer count + chip badges. Exposing a
/// public [bump] avoids the lint against calling the protected
/// `notifyListeners` from outside a [ChangeNotifier] subclass.
class _AggregateNotifier extends ChangeNotifier {
  void bump() => notifyListeners();
}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

/// A close affordance + centred title, geometry shared with the sibling service
/// screens so the title never shifts on navigation.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.closeLabel,
    required this.onClose,
  });

  final String title;
  final String closeLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.md,
        VelvetSpacing.lg,
        VelvetSpacing.sm,
      ),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: NeumorphicIconButton(
                key: const Key('btn-setup-close'),
                icon: Icons.close_rounded,
                semanticLabel: closeLabel,
                onTap: onClose,
              ),
            ),
            Text(
              title,
              style: VelvetText.subheading(),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper note
// ---------------------------------------------------------------------------

/// The missing-CATEGORY affordance, pinned above the category chips.
///
/// Was a static note whose prose merely PROMISED that a missing entry could be
/// requested "later, from the Services page" — a dead end that pointed at
/// another screen. It is now the request itself.
///
/// Stays a recessed [NeumorphicInset] rather than becoming a raised button:
/// this is the quiet channel, subordinate to the CTA at the foot of the screen,
/// and a second extruded pillow up here would compete with the chips. The
/// trailing chevron plus the press-scale are what promote it from "note" to
/// "control" without raising its visual weight.
class _MissingCategoryPrompt extends StatefulWidget {
  const _MissingCategoryPrompt({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_MissingCategoryPrompt> createState() => _MissingCategoryPromptState();
}

class _MissingCategoryPromptState extends State<_MissingCategoryPrompt> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final TextStyle caption = VelvetText.svcCaptionNote;
    return Semantics(
      button: true,
      label: l10n.serviceSetupRequestCategoryAction,
      child: GestureDetector(
        key: const Key('btn-setup-request-category'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.99 : 1.0,
          duration: const Duration(milliseconds: 110),
          child: NeumorphicInset(
            radius: VelvetRadii.field,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: VelvetSpacing.md,
                vertical: VelvetSpacing.md - 2,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 18,
                      color: BrandColors.accentDeep,
                    ),
                  ),
                  const SizedBox(width: VelvetSpacing.sm + 2),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: caption,
                        children: <InlineSpan>[
                          TextSpan(
                            text: l10n.serviceSetupMissingCategoryLead,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const TextSpan(text: ' '),
                          // The action phrase is the accent-coloured part, so
                          // the tappable promise is legible at a glance.
                          TextSpan(
                            text: l10n.serviceSetupRequestCategoryAction,
                            style: caption.copyWith(
                              fontWeight: FontWeight.w800,
                              color: BrandColors.accentDeep,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: VelvetSpacing.sm),
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: BrandColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The missing-SERVICE-TYPE affordance, closing each expanded category's rows.
///
/// Placement is the whole design: it appears only under an expanded category,
/// AFTER every type that category does offer. That position both states the
/// case ("you have now seen all of them — not the one you wanted?") and supplies
/// the `categoryName` the suggestion dialog requires, with no picker and no
/// ambiguity about which category the suggestion attaches to.
///
/// Treatment is deliberately the third surface in the system: flat, hairline-
/// outlined, no shadow at all. A raised card would claim it is a service; a
/// recessed well would claim it is an input. An outline reads as a slot waiting
/// to be filled, which is exactly what a suggestion is.
class _MissingServiceTypePrompt extends StatefulWidget {
  const _MissingServiceTypePrompt({
    super.key,
    required this.categoryLabel,
    required this.onTap,
  });

  /// Ukrainian display name, shown in the copy. NOT the wire slug.
  final String categoryLabel;
  final VoidCallback onTap;

  @override
  State<_MissingServiceTypePrompt> createState() =>
      _MissingServiceTypePromptState();
}

class _MissingServiceTypePromptState extends State<_MissingServiceTypePrompt> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String label = l10n.serviceSetupMissingTypePrompt(
      widget.categoryLabel,
    );
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.99 : 1.0,
          duration: const Duration(milliseconds: 110),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.md,
              vertical: VelvetSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(VelvetRadii.card),
              border: Border.all(
                color: BrandColors.accent.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.add_circle_outline_rounded,
                  size: 18,
                  color: BrandColors.accent,
                ),
                const SizedBox(width: VelvetSpacing.sm + 2),
                Expanded(
                  child: Text(
                    label,
                    style: VelvetText.svcCaptionNote.copyWith(
                      fontWeight: FontWeight.w800,
                      color: BrandColors.accentDeep,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty hint + per-category loading / retry
// ---------------------------------------------------------------------------

/// Calm passive hint shown below the chip row when no category is selected yet.
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.xl),
      child: Center(
        child: Column(
          children: <Widget>[
            const Icon(
              Icons.touch_app_rounded,
              size: 34,
              color: BrandColors.faint,
            ),
            const SizedBox(height: VelvetSpacing.sm),
            Text(text, style: VelvetText.body(), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// A compact spinner shown while an expanded category's service-types load.
class _CategoryLoading extends StatelessWidget {
  const _CategoryLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: VelvetSpacing.lg),
      child: Center(
        child: SizedBox(
          height: 26,
          width: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: BrandColors.accent,
          ),
        ),
      ),
    );
  }
}

/// A retry affordance shown when an expanded category's service-type fetch
/// failed. Tapping re-issues the load for just that category.
class _CategoryRetry extends StatelessWidget {
  const _CategoryRetry({
    super.key,
    required this.onRetry,
    required this.label,
    required this.retryLabel,
  });

  final VoidCallback onRetry;
  final String label;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.md),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: BrandColors.error,
          ),
          const SizedBox(width: VelvetSpacing.sm),
          Expanded(
            child: Text(label, style: VelvetText.feedback(BrandColors.error)),
          ),
          const SizedBox(width: VelvetSpacing.sm),
          GestureDetector(
            onTap: onRetry,
            child: Text(retryLabel, style: VelvetText.link()),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Footer CTA
// ---------------------------------------------------------------------------

/// Pinned bottom action — the base tone with a soft upward veil so the list
/// tucks beneath it, then the primary CTA whose label counts the services the
/// save would create. Disabled (flattened) while nothing is included.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.total,
    required this.saving,
    required this.appending,
    required this.onSave,
  });

  final int total;

  final bool saving;

  /// APPEND mode — the CTA says "add N" rather than "create my menu of N".
  final bool appending;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String label = total == 0
        ? l10n.serviceSetupCtaEmpty
        : (appending
              ? l10n.serviceSetupCtaAdd(total)
              : l10n.serviceSetupCtaCreate(total));
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: BrandColors.base,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: BrandColors.base,
            offset: Offset(0, -12),
            blurRadius: 18,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          VelvetSpacing.lg,
          VelvetSpacing.sm,
          VelvetSpacing.lg,
          VelvetSpacing.md,
        ),
        child: NeumorphicButton(
          key: const Key('btn-setup-save'),
          label: label,
          loading: saving,
          icon: total == 0 ? null : Icons.check_circle_outline_rounded,
          onPressed: onSave,
        ),
      ),
    );
  }
}
