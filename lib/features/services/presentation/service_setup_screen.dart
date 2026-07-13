// First-Time Service Setup screen (INDEPENDENT_MASTER).
//
// The empty-state path: a master with ZERO services stands up their whole menu
// in one pass. Reached from the services-list empty state (replacing the
// single-create CTA when the catalogue is empty).
//
// The flow lives on one scrollable screen:
//   1. a helper note explaining a missing service-type can be requested later;
//   2. a Wrap of multi-selectable platform-category chips — selecting one
//      loads + expands it inline to reveal every service-type beneath it;
//   3. under each expanded category, a configurable row per service-type
//      (include toggle defaulting ON, duration, and a fixed/range price);
//   4. a pinned CTA that counts the services the save would create.
//
// On a successful bulk save the services list is invalidated and the screen
// navigates to it (now populated). A 409 (the master already has services)
// surfaces a message and routes to the list instead of allowing a retry.
//
// Ported 1:1 from the approved preview
// `docs/signup-designs/ServiceSetup/lib/screens/service_setup_screen.dart`;
// local state / Navigator replaced by Riverpod providers + go_router, and the
// hardcoded category seed replaced by the live `approvedCategoriesProvider` /
// `serviceTypesProvider` data.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/pricing_field.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_setup_widgets.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';

/// First-time service setup — the single empty-state screen for a master with
/// zero services.
class ServiceSetupScreen extends ConsumerStatefulWidget {
  const ServiceSetupScreen({super.key});

  @override
  ConsumerState<ServiceSetupScreen> createState() => _ServiceSetupScreenState();
}

class _ServiceSetupScreenState extends ConsumerState<ServiceSetupScreen> {
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

  @override
  void initState() {
    super.initState();
    // SEC MEDIUM: ref-counted screenshot guard (single app-wide owner;
    // the manager is internally !kDebugMode-guarded).
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
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
      setState(() {
        final rows = <ServiceRowState>[
          for (final t in types)
            ServiceRowState(serviceTypeId: t.id, nameUk: t.nameUk),
        ];
        _rowsByCategory[slug] = rows;
        _loadingCategories.remove(slug);
      });
    } on Object catch (e, st) {
      if (kDebugMode) {
        log(
          '_loadCategory($slug) failed: $e',
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

  // -------------------------------------------------------------------------
  // Counts
  // -------------------------------------------------------------------------

  int _includedCount(String slug) {
    final rows = _rowsByCategory[slug];
    if (rows == null) return 0;
    return rows.where((r) => r.included).length;
  }

  /// Total services the save would create — every included row across all loaded
  /// categories.
  int get _totalIncluded {
    var n = 0;
    for (final rows in _rowsByCategory.values) {
      n += rows.where((r) => r.included).length;
    }
    return n;
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
    final reasons = <String, RowFlagReason>{};
    // Capture the row↔submitted-item ordering so a 400's items[i].field path
    // resolves back to the originating row. Rebuilt from scratch each call.
    _submittedRows.clear();

    for (final rows in _rowsByCategory.values) {
      for (final row in rows) {
        if (!row.included) continue;
        final id = row.serviceTypeId;
        final duration = int.tryParse(row.duration.text.trim());
        // Client-side mirror of the backend @Max(480) guard, so the common
        // over-8h case is caught before the network round-trip.
        final bool durationTooLong = duration != null && duration > 480;
        final durationOk = duration != null && duration >= 1 && duration <= 480;

        if (row.pricingMode == ServicePriceType.fixed) {
          final price = _parsePrice(row.fixed.text);
          final priceOk = price != null;
          if (!durationOk || !priceOk) {
            reasons[id] = durationTooLong
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
            ),
          );
          _submittedRows.add(row);
        } else {
          final min = _parsePrice(row.min.text);
          final max = _parsePrice(row.max.text);
          final priceOk = min != null && max != null && max > min;
          if (!durationOk || !priceOk) {
            reasons[id] = durationTooLong
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
            ),
          );
          _submittedRows.add(row);
        }
      }
    }

    // Flag each offending row on its own notifier — only those cards rebuild.
    for (final rows in _rowsByCategory.values) {
      for (final row in rows) {
        row.flagReason = reasons[row.serviceTypeId] ?? RowFlagReason.none;
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
  void _scrollToFirstFlagged() {
    // Collect the flagged-row ids (client flag OR mapped-back server error);
    // bail early when nothing is flagged.
    final flaggedIds = <String>{
      for (final rows in _rowsByCategory.values)
        for (final row in rows)
          if (row.included &&
              (row.flagReason != RowFlagReason.none ||
                  row.serverDurationError != null ||
                  row.serverPriceError != null))
            row.serviceTypeId,
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

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
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
      // Success — refresh the list and land on it (now populated).
      ref.invalidate(servicesListProvider);
      _showSnack(l10n.serviceSetupSuccess);
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(RouteNames.services);
      }
      return;
    }

    // Failure — read the typed error from the notifier state.
    final error = ref.read(serviceSetupProvider).error;
    if (error is MasterAlreadyHasServicesFailure) {
      // The first-time guard tripped: the catalogue is no longer empty, so
      // refresh + route to the (now-populated) list rather than retry.
      ref.invalidate(servicesListProvider);
      _showSnack(error.userMessage(context));
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(RouteNames.services);
      }
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
    _showSnack(message);
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
        // validates price shape). Fall back to the raw server message.
        row.serverPriceError = entry.value;
        mappedAny = true;
      }
    }
    return mappedAny;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: BrandColors.accentDeep,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
              title: l10n.serviceSetupTitle,
              closeLabel: l10n.serviceSetupClose,
              onClose: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(RouteNames.services);
                }
              },
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
                final total = _totalIncluded;
                return _Footer(
                  total: total,
                  saving: saving,
                  onSave: total == 0 ? null : _save,
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
    final List<Widget> rowItems = _expandedItems(l10n, categories);
    return CustomScrollView(
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
                const _MissingServiceNote(),
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
              (context, index) => rowItems[index],
              childCount: rowItems.length,
            ),
          ),
        ),
      ],
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
                  icon: serviceCategoryIcon(c.name),
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

  /// Flattens the expanded categories into a single list of items fed to the
  /// [SliverList] builder (headers, hints, and one [RepaintBoundary]-wrapped
  /// [ServiceTypeRowCard] per service-type).
  List<Widget> _expandedItems(
    AppLocalizations l10n,
    List<ServiceCategoryOption> categories,
  ) {
    final active = categories
        .where((c) => _expanded.contains(c.name))
        .toList(growable: false);
    if (active.isEmpty) {
      return <Widget>[_EmptyHint(text: l10n.serviceSetupEmptyHint)];
    }

    final out = <Widget>[];
    for (final c in active) {
      final slug = c.name;
      final icon = serviceCategoryIcon(slug);

      if (_loadingCategories.contains(slug)) {
        out.add(_CategoryLoading(key: ValueKey<String>('loading_$slug')));
        continue;
      }
      if (_erroredCategories.contains(slug)) {
        out.add(
          _CategoryRetry(
            key: ValueKey<String>('retry_$slug'),
            onRetry: () => _loadCategory(slug),
            label: l10n.serviceTypeLoadError,
            retryLabel: l10n.serviceCategoryRetry,
          ),
        );
        continue;
      }

      final rows = _rowsByCategory[slug] ?? const <ServiceRowState>[];
      // The header's live "n з m" count derives from the aggregate so it tracks
      // include toggles without forcing a full-tree rebuild.
      out.add(
        ListenableBuilder(
          key: ValueKey<String>('group_$slug'),
          listenable: _aggregate,
          builder: (context, _) => CategoryGroupHeader(
            icon: icon,
            label: c.displayName,
            includedCount: _includedCount(slug),
            total: rows.length,
          ),
        ),
      );
      out.add(const SizedBox(height: VelvetSpacing.md));

      if (rows.isEmpty) {
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: VelvetSpacing.md),
            child: Text(l10n.serviceTypeEmpty, style: VelvetText.body()),
          ),
        );
      }

      for (final row in rows) {
        final id = row.serviceTypeId;
        out.add(
          // Outer KeyedSubtree carries the per-row GlobalKey so a blocked save
          // can `Scrollable.ensureVisible` this flagged row; the inner
          // RepaintBoundary keeps its `rowwrap_$id` ValueKey for test finders
          // and caps the per-row expand/collapse animation's repaint blast
          // radius to this one card.
          KeyedSubtree(
            key: _rowWrapperKey(id),
            child: RepaintBoundary(
              key: ValueKey<String>('rowwrap_$id'),
              child: Padding(
                padding: const EdgeInsets.only(bottom: VelvetSpacing.md),
                child: ServiceTypeRowCard(
                  key: Key('setup_row_$id'),
                  row: row,
                  resolveRangeError: (r) => _rangeErrorFor(r, l10n),
                  onChanged: _notifyAggregate,
                ),
              ),
            ),
          ),
        );
      }
      out.add(const SizedBox(height: VelvetSpacing.sm));
    }
    return out;
  }
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

/// A calm helper note pinned to the top — reassures the master that a service
/// missing from the catalogue isn't a dead end: it can be requested later from
/// the Services page. Soft recessed inset so it reads as guidance, not a CTA.
class _MissingServiceNote extends StatelessWidget {
  const _MissingServiceNote();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final TextStyle caption = VelvetText.svcCaptionNote;
    return NeumorphicInset(
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
                      text: l10n.serviceSetupMissingNoteLead,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    TextSpan(text: l10n.serviceSetupMissingNoteBody),
                    TextSpan(
                      text: l10n.serviceSetupMissingNoteServicesWord,
                      style: caption.copyWith(
                        fontWeight: FontWeight.w800,
                        color: BrandColors.accentDeep,
                      ),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ],
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
    required this.onSave,
  });

  final int total;
  final bool saving;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String label = total == 0
        ? l10n.serviceSetupCtaEmpty
        : l10n.serviceSetupCtaCreate(total);
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
