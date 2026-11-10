// First-time service-setup widgets.
//
// Ported 1:1 from the approved preview
// `docs/signup-designs/ServiceSetup/lib/widgets/service_setup_widgets.dart`
// (+ `pricing_field.dart`). The preview's standalone VelvetColors / VelvetText /
// VelvetShadows tokens are swapped for the production BrandColors / VelvetText /
// VelvetShadows + the shared NeumorphicInset; the layout, motion, and geometry
// are unchanged.
//
// VelvetTouch craft (within the locked palette): unselected chip = a recessed
// inset pill; selected chip = a raised camel→mocha gradient pillow with a leading
// icon + cream label + optional cream count badge. Each service-type row is a
// raised card that expands (AnimatedSize + cross-fade) to reveal the pricing
// control while its include toggle is ON, and dims to a single muted line while
// OFF.

import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_name_key.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/pricing_field.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Why a save-time validation flag fired on a row, so its card can show a
/// precise message (and the right inline field hints) instead of one generic
/// "missing duration and price" string. [none] means the row is valid / not
/// flagged.
enum RowFlagReason {
  /// Row is valid or has not been flagged.
  none,

  /// Included row whose duration is empty / not a positive integer.
  missingDuration,

  /// Included fixed-price row whose price is empty / unparseable.
  missingPrice,

  /// Included row missing BOTH a valid duration and a valid price.
  missingBoth,

  /// Included range-priced row whose price range is missing or invalid
  /// (max must exceed min). The precise range message is surfaced inline by
  /// [PricingField] beneath the price fields, so the flag stays terse.
  invalidRange,

  /// Included row whose duration exceeds the backend maximum (480 min / 8 h).
  /// Caught client-side before the network round-trip; the inline duration
  /// message mirrors the backend's own `items[i].durationMinutes` max error.
  durationTooLong,

  /// The refreshed catalogue (re-read after a 409 `DUPLICATE_SERVICE`) shows the
  /// master ALREADY offers this service type, so the row was switched off to
  /// unblock the next save.
  ///
  /// Unlike every other reason here this is not a validation fault and the row
  /// is EXCLUDED while it holds — so it renders in the off-state sub-label slot
  /// with the calm camel treatment, never the red error rim. It exists so the
  /// change is stated rather than silent: a row that simply went quiet under the
  /// master's hands reads as a bug, and a row left selectable would 409 again on
  /// the very next tap.
  ///
  /// Distinct from [ServiceRowState.alreadyAdded], which is the immutable
  /// at-load exclusion; this one is a mid-session transition and clears on the
  /// next save or toggle.
  alreadyInMenu,
}

/// SUPERSEDED (2026-08-27, user instruction: "continue adding SVGs to missed
/// places"): this file used to define
/// `IconData serviceCategoryIcon(String slug) => Icons.spa_rounded` — a single
/// uniform Material glyph rendered for every category chip / group header,
/// locked in by a regression test guarding against a MAKEUP-only divergence.
/// That uniform-icon decision is reversed. Chips and headers now render the
/// real per-category SVG resolved by
/// [categoryIconOrNullFor](../../../../core/icons/category_icons.dart) —
/// called by the owning screen (`service_setup_screen.dart`) with both the
/// category's wire slug and its Ukrainian display name, and passed down here
/// as [CategoryChip.iconAsset] / [CategoryGroupHeader.iconAsset]. See
/// `test/features/services/presentation/widgets/service_setup_widgets_test.dart`
/// for the updated contract test.

/// A multi-selectable category chip — the entry point that, when selected,
/// expands inline to reveal every service-type under the category.
///
/// Unselected = a recessed inset well; selected = a raised camel→mocha gradient
/// pillow with a leading icon + cream label, cross-faded by a 150 ms
/// [AnimatedContainer]. Once the master has included rows inside it the selected
/// chip carries a cream count badge so the chip telegraphs progress.
class CategoryChip extends StatelessWidget {
  const CategoryChip({
    super.key,
    required this.iconAsset,
    required this.label,
    required this.selected,
    required this.includedCount,
    required this.onTap,
  });

  /// Resolved SVG asset path for the category glyph (from
  /// [categoryIconOrNullFor](../../../../core/icons/category_icons.dart)), or
  /// `null` for an uncategorised entry. `null` renders no icon but the leading
  /// slot still reserves [_iconSize] so every chip's label stays aligned.
  final String? iconAsset;
  final String label;
  final bool selected;

  /// How many service-types under this category are currently toggled ON.
  final int includedCount;
  final VoidCallback onTap;

  /// Matches the 20dp icon size used app-wide for comparable category rows
  /// and headers (`service_category_cards.dart`, `service_category_list.dart`,
  /// `service_catalogue_accordion.dart`) — chosen over the previous 16dp
  /// Material glyph size because the category SVG set is thin-stroke and loses
  /// detail below ~20dp (see `project_category_icon_set_thin_locked` memory).
  /// Measured effect (`tester.getSize`, badge-less chip): unselected/selected
  /// height grows 32dp → 36dp, which now MATCHES the already-existing 36dp
  /// height of a selected chip carrying a count badge — so this removes a
  /// pre-existing 4dp inconsistency between badge / no-badge chips rather than
  /// introducing a new one.
  static const double _iconSize = 20;

  static const BorderRadius _pillRadius = BorderRadius.all(
    Radius.circular(VelvetRadii.pill),
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: selected
              ? const BoxDecoration(
                  borderRadius: _pillRadius,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      BrandColors.accentLatte,
                      BrandColors.accentDeep,
                    ],
                  ),
                  boxShadow: VelvetShadows.extrudedButtonAccent,
                )
              : null,
          child: selected ? _selectedContent() : _unselectedContent(),
        ),
      ),
    );
  }

  Widget _selectedContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md,
        vertical: VelvetSpacing.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: _iconSize,
            height: _iconSize,
            child: iconAsset == null
                ? null
                : AppIcon(
                    iconAsset!,
                    size: _iconSize,
                    color: BrandColors.white,
                  ),
          ),
          const SizedBox(width: VelvetSpacing.sm - 2),
          Text(
            label,
            style: VelvetText.pill().copyWith(color: BrandColors.white),
          ),
          if (includedCount > 0) ...<Widget>[
            const SizedBox(width: VelvetSpacing.sm - 2),
            _CountBadge(count: includedCount, onAccent: true),
          ],
        ],
      ),
    );
  }

  Widget _unselectedContent() {
    return NeumorphicInset(
      radius: VelvetRadii.pill,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.md,
          vertical: VelvetSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: _iconSize,
              height: _iconSize,
              child: iconAsset == null
                  ? null
                  : AppIcon(
                      iconAsset!,
                      size: _iconSize,
                      color: BrandColors.accent,
                    ),
            ),
            const SizedBox(width: VelvetSpacing.sm - 2),
            Text(label, style: VelvetText.pill()),
          ],
        ),
      ),
    );
  }
}

/// A small pill-shaped count badge. On the camel chip it is a cream disc with
/// mocha digits; on the base surface it is a soft camel disc with cream digits.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, this.onAccent = false});

  final int count;
  final bool onAccent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onAccent ? BrandColors.white : BrandColors.accent,
        borderRadius: BorderRadius.circular(VelvetRadii.pill),
      ),
      child: Text(
        '$count',
        style: VelvetText.svcCountPill.copyWith(
          color: onAccent ? BrandColors.accentDeep : BrandColors.white,
        ),
      ),
    );
  }
}

/// The header that introduces an expanded category's row list — its icon, the
/// Ukrainian name, and a live "n з m" count of included service-types.
class CategoryGroupHeader extends StatelessWidget {
  const CategoryGroupHeader({
    super.key,
    required this.iconAsset,
    required this.label,
    required this.includedCount,
    required this.total,
  });

  /// Resolved SVG asset path for the category glyph (from
  /// [categoryIconOrNullFor](../../../../core/icons/category_icons.dart)), or
  /// `null` for an uncategorised entry. `null` renders no icon but the leading
  /// slot still reserves [_iconSize] so every header's label stays aligned.
  final String? iconAsset;
  final String label;
  final int includedCount;
  final int total;

  /// See [CategoryChip._iconSize] — same 20dp app-wide category-icon size and
  /// the same thin-stroke-legibility rationale. Measured effect
  /// (`tester.getSize`): header height grows 23dp → ~28dp (was sized to a
  /// 14dp Material glyph; the SVG set does not ship a smaller variant).
  static const double _iconSize = 20;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final TextStyle style = VelvetText.svcGroupHeader;
    return Padding(
      padding: const EdgeInsets.only(
        left: VelvetSpacing.xs,
        top: VelvetSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _iconSize,
            height: _iconSize,
            child: iconAsset == null
                ? null
                : AppIcon(
                    iconAsset!,
                    size: _iconSize,
                    color: BrandColors.accentDeep,
                  ),
          ),
          const SizedBox(width: VelvetSpacing.xs + 2),
          Flexible(
            child: Text(
              label,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: VelvetSpacing.xs + 2),
          Text(l10n.serviceSetupGroupCount(includedCount, total), style: style),
        ],
      ),
    );
  }
}

/// Mutable per-row UI state for one service-type while the master configures the
/// one-pass menu. Holds everything the bottom save serialises into the per-row
/// bulk payload `{ serviceTypeId, durationMinutes, priceType, price |
/// priceMin/priceMax, name? }`. The service category is derived server-side
/// from the service-type; the name defaults to the type name and is only
/// overridable on a type that has more than one row (phase 471 copies).
///
/// A [ChangeNotifier] so the row's own card — and the derived footer count /
/// chip badges — can rebuild *locally* when `included` / `pricingMode` /
/// `flagged` change, instead of forcing a full-tree `setState` on the screen.
/// It also owns the four field controllers so the card is the single source of
/// truth for its own rebuild (range-error recomputation included).
class ServiceRowState extends ChangeNotifier {
  ServiceRowState({
    required this.serviceTypeId,
    required this.nameUk,
    this.alreadyAdded = false,
    this.ownedDurations = const <int>{},
    this.copyIndex = 0,
    String? name,
    List<MasterService> ownedServices = const <MasterService>[],
    Set<(int, String)>? ownedCopyKeys,
  }) : _owned = <OwnedServiceName>[
         for (final MasterService s in ownedServices) OwnedServiceName(s),
       ],
       ownedCopyKeys =
           ownedCopyKeys ??
           (ownedServices.isEmpty
               ? null
               : copyKeysOf(ownedServices, typeName: nameUk)) {
    // Parsed-value caches (see [durationMinutes] / [customName]) follow the
    // controllers' TEXT; registered before the seed so it is cached too.
    duration.addListener(_syncDuration);
    this.name.addListener(_syncName);
    if (name != null) this.name.text = name;
  }

  /// Text [_durationMinutes] was parsed from; a caret / selection-only
  /// notification leaves it equal and skips the re-parse.
  String _durationText = '';
  int? _durationMinutes;

  /// Text [_customName] was derived from.
  String _nameText = '';
  String? _customName;

  void _syncDuration() {
    final String text = duration.text;
    if (text == _durationText) return;
    _durationText = text;
    _durationMinutes = int.tryParse(text.trim());
  }

  void _syncName() {
    final String text = name.text;
    if (text == _nameText) return;
    _nameText = text;
    final String t = text.trim();
    _customName = t.isEmpty ? null : t;
    _effectiveNameKey = null; // re-derived on next read
  }

  /// [effectiveNameKey] cache, cleared by [_syncName]; [_typeNameKey] is the
  /// fixed [serviceNameKey] of [nameUk].
  String? _effectiveNameKey;
  String? _typeNameKey;

  /// The duration field parsed as whole minutes, or null when blank / not a
  /// number. Cached on text change — reads never re-parse.
  int? get durationMinutes => _durationMinutes;

  /// Phase 471 — an extra copy row of [source]'s type, already included: same
  /// type / name / ownership, an empty price and the nearest free quick-pick
  /// duration — free of [source]'s duration, of [ServiceRowState.ownedDurations]
  /// and of [takenDurations] (the type's other session rows). Blank when every
  /// ladder value is taken (the master types one).
  ///
  /// [copyIndex] must be unique among the type's rows (> 0): it keys the
  /// copy's widgets (see [keyId]).
  factory ServiceRowState.copyOf(
    ServiceRowState source, {
    Set<int> takenDurations = const <int>{},
    int copyIndex = 1,
  }) {
    assert(copyIndex > 0, 'a copy row needs copyIndex > 0');
    final copy = ServiceRowState(
      serviceTypeId: source.serviceTypeId,
      nameUk: source.nameUk,
      alreadyAdded: source.alreadyAdded,
      ownedDurations: source.ownedDurations,
      ownedCopyKeys: source.ownedCopyKeys,
      copyIndex: copyIndex,
    );
    final int? sourceDuration = source.durationMinutes;
    final Set<int> used = <int>{
      ...source.ownedDurations,
      ...takenDurations,
      ?sourceDuration,
    };
    final int? seed = nearestFreeQuickPick(used);
    if (seed != null) copy.duration.text = '$seed';
    // Set directly: the public setter's owned-duration re-seed is already
    // covered by `used`, and a fresh copy has no listeners yet.
    copy._included = true;
    return copy;
  }

  /// Quick-pick duration ladder (minutes) used to seed a free duration when an
  /// already-owned type is selected again (phase 468). Ascending.
  static const List<int> durationQuickPicks = <int>[
    30,
    45,
    60,
    90,
    120,
    150,
    180,
    240,
  ];

  /// The quick-pick value to seed for a copy of a type whose existing copies
  /// run [owned] minutes: the nearest free ladder value ABOVE the longest
  /// owned duration, else the nearest free one below it, else `null` (every
  /// ladder value is taken — the master types one).
  static int? nearestFreeQuickPick(Set<int> owned) {
    if (owned.isEmpty) return null;
    final int longest = owned.reduce((int a, int b) => a > b ? a : b);
    int? best;
    for (final int v in durationQuickPicks) {
      if (owned.contains(v)) continue;
      if (best == null) {
        best = v;
        continue;
      }
      final bool vAbove = v > longest;
      final bool bestAbove = best > longest;
      if (vAbove != bestAbove) {
        if (vAbove) best = v;
        continue;
      }
      if ((v - longest).abs() < (best - longest).abs()) best = v;
    }
    return best;
  }

  /// The platform service-type id submitted in the bulk payload.
  final String serviceTypeId;

  /// Ukrainian display name shown on the row card.
  final String nameUk;

  /// Phase 471 — position of this row among its type's rows: 0 for the first
  /// (primary) row, > 0 for an extra copy. Unique per type, stable for the
  /// row's life except when the primary is removed and this row is promoted to
  /// 0. Not a notifier field: the screen rebuilds when it changes.
  int copyIndex;

  /// True for an extra copy row added with «+ додати ще» (phase 471).
  bool get isExtraCopy => copyIndex > 0;

  /// Widget-key id of this row: the bare [serviceTypeId] for the primary row
  /// (so every pre-471 key is unchanged), `<id>_copy_<n>` for a copy.
  String get keyId =>
      copyIndex == 0 ? serviceTypeId : '${serviceTypeId}_copy_$copyIndex';

  /// Phase 471 — optional custom name of this copy. Only shown while the type
  /// has more than one row; blank = the type name.
  final TextEditingController name = TextEditingController();

  /// The trimmed custom name, or null when blank. Cached on text change.
  String? get customName => _customName;

  /// The name the backend 464 duplicate rule compares ([serviceNameKey]:
  /// compatibility-folded, space runs collapsed, trimmed, lower-cased),
  /// blank = the type name.
  /// Cached with [customName] (phase 472 audit) — the pair check reads it per
  /// row on every edit.
  String get effectiveNameKey => _effectiveNameKey ??= switch (customName) {
    final String n => serviceNameKey(n),
    null => _typeKey,
  };

  String get _typeKey => _typeNameKey ??= serviceNameKey(nameUk);

  /// True when this row would be saved under the type name — the name every
  /// existing copy in [ownedDurations] is compared with.
  bool get keepsTypeName => effectiveNameKey == _typeKey;

  bool _copyCollision = false;

  /// Phase 471 — set by the screen's pair check: this included row has the
  /// same duration AND effective name as an earlier row of the same type, so
  /// the save is blocked until one of them changes.
  bool get copyCollision => _copyCollision;
  set copyCollision(bool value) {
    if (_copyCollision == value) return;
    _copyCollision = value;
    notifyListeners();
  }

  /// True when the master ALREADY offers this service type (at least one
  /// copy). Drives the «Вже додано» label only.
  ///
  /// Phase 468: an owned type is selectable again — the backend accepts a copy
  /// whose duration OR name differs from every active copy. The add-services
  /// row has no name field (its name is the type name), so the client mirrors
  /// only the duration half of the rule via [ownedDurations]; the server 409
  /// stays the backstop for name collisions.
  ///
  /// Immutable for the row's lifetime — seeded from the master's existing
  /// catalogue when the category's types load.
  final bool alreadyAdded;

  /// Durations (minutes) of the master's existing copies of this type. Empty
  /// for a type the master does not offer. An included row whose duration is
  /// one of these is [durationTaken] and blocks the save.
  final Set<int> ownedDurations;

  /// Phase 472 — `(durationMinutes, serviceNameKey(name))` of every existing
  /// copy, the backend 464 rule's (duration, canonical name) half (the type
  /// is the row's). Null when unknown — [durationTaken] then falls back to
  /// "existing copies carry the type name" (the pre-472 assumption).
  final Set<(int, String)>? ownedCopyKeys;

  /// The [ownedCopyKeys] of [services]: a blank name counts as the service's
  /// own type name, else [typeName] (the row's catalogue name).
  static Set<(int, String)> copyKeysOf(
    List<MasterService> services, {
    required String typeName,
  }) => <(int, String)>{
    for (final MasterService s in services)
      (
        s.durationMinutes,
        serviceNameKey(
          s.name.trim().isNotEmpty
              ? s.name
              : ((s.serviceTypeNameUk ?? '').trim().isNotEmpty
                    ? s.serviceTypeNameUk ?? typeName
                    : typeName),
        ),
      ),
  };

  /// True while the row is included and its (duration, canonical name)
  /// matches an existing copy of the same type — an exact duplicate the
  /// backend would reject with 409 `DUPLICATE_SERVICE`. Phase 472 compares
  /// [effectiveNameKey] with each copy's canonical name ([ownedCopyKeys]), so
  /// a renamed existing copy no longer blocks a type-name row at its
  /// duration; without keys, only a row that keeps the type name is taken
  /// (phase 471).
  bool get durationTaken {
    if (!_included) return false;
    final int? d = _durationMinutes;
    if (d == null) return false;
    final Set<(int, String)>? keys = ownedCopyKeys;
    if (keys != null) return keys.contains((d, effectiveNameKey));
    return ownedDurations.contains(d) && keepsTypeName;
  }

  /// Field controllers, owned by the row so its card can recompute the
  /// cross-field range error from the min/max text without a screen rebuild.
  final TextEditingController duration = TextEditingController();
  final TextEditingController fixed = TextEditingController();
  final TextEditingController min = TextEditingController();
  final TextEditingController max = TextEditingController();

  bool _included = false;

  /// Include toggle — defaults OFF (opt-in model). Expanding a category just
  /// reveals its service-types; the master toggles ON only the ones they offer.
  /// Only included rows are submitted and require a duration + price; the
  /// untouched (off) rows are skipped by the save, so browsing a category never
  /// makes its rows required.
  bool get included => _included;
  set included(bool value) {
    if (_included == value) return;
    _included = value;
    // Phase 472: no duration seed on toggle. Phase 468 filled an owned type's
    // row with a free quick-pick here, which read as an autofilled duration on
    // every reopen; the master now types the copy's duration themselves
    // ([durationTaken] still blocks a value an existing copy already has).
    notifyListeners();
  }

  ServicePriceType _pricingMode = ServicePriceType.fixed;
  ServicePriceType get pricingMode => _pricingMode;
  set pricingMode(ServicePriceType value) {
    if (_pricingMode == value) return;
    _pricingMode = value;
    notifyListeners();
  }

  RowFlagReason _flagReason = RowFlagReason.none;

  /// The precise reason this row is flagged (or [RowFlagReason.none] when
  /// valid). Drives the card's flag message + the inline per-field hints.
  RowFlagReason get flagReason => _flagReason;
  set flagReason(RowFlagReason value) {
    if (_flagReason == value) return;
    _flagReason = value;
    notifyListeners();
  }

  /// True when the row is included but missing a required value, so its card
  /// shows the validation flag + tinted rim. Derived from [flagReason].
  bool get flagged => _flagReason != RowFlagReason.none;

  /// Clears any active validation flag (e.g. when the row is toggled or the
  /// pricing mode changes, giving the master a clean slate before re-saving).
  void clearFlag() => flagReason = RowFlagReason.none;

  String? _serverDurationError;

  /// A backend per-field validation message for this row's duration
  /// (`items[i].durationMinutes`), mapped back from a 400 response. Coalesced
  /// into the duration well's inline-error slot ahead of any client hint, so a
  /// server constraint surfaces on the exact row + field instead of a generic
  /// snackbar. Null when the row has no outstanding server duration error.
  String? get serverDurationError => _serverDurationError;
  set serverDurationError(String? value) {
    if (_serverDurationError == value) return;
    _serverDurationError = value;
    notifyListeners();
  }

  String? _serverPriceError;

  /// A backend per-field validation message for this row's price
  /// (`items[i].price` / `priceMin` / `priceMax`), mapped back from a 400
  /// response. Coalesced into the price field's inline-error slot. Null when
  /// there is no outstanding server price error.
  String? get serverPriceError => _serverPriceError;
  set serverPriceError(String? value) {
    if (_serverPriceError == value) return;
    _serverPriceError = value;
    notifyListeners();
  }

  String? _serverNameError;

  /// Phase 471 — a backend per-field validation message for this row's copy
  /// name (`items[i].name`), mapped back from a 400. Rendered in the name
  /// well's inline-error slot. Null when there is none.
  String? get serverNameError => _serverNameError;
  set serverNameError(String? value) {
    if (_serverNameError == value) return;
    _serverNameError = value;
    notifyListeners();
  }

  /// Clears the mapped-back server duration error (e.g. when the master edits
  /// the duration field, so the red state disappears as they fix the value).
  void clearServerDurationError() => serverDurationError = null;

  /// Clears the mapped-back server name error (the master edited the name).
  void clearServerNameError() => serverNameError = null;

  /// Clears the mapped-back server price error (e.g. when the master edits a
  /// price field).
  void clearServerPriceError() => serverPriceError = null;

  /// Clears BOTH server-error channels — used on include-toggle / mode-change
  /// and before a fresh save so a stale server error never lingers.
  void clearServerErrors() {
    serverDurationError = null;
    serverPriceError = null;
    serverNameError = null;
  }

  // -------------------------------------------------------------------------
  // Phase 472 — «+ додати ще» focus jump, custom name of a new service, and
  // inline rename of the master's existing services (decision D2)
  // -------------------------------------------------------------------------

  FocusNode? _durationFocus;

  /// Focus node of this row's duration well, created on first use, so the
  /// screen can move focus into a freshly added copy.
  FocusNode get durationFocus =>
      _durationFocus ??= FocusNode(debugLabel: 'setup_duration_$keyId');

  FocusNode? _nameFocus;

  /// Focus node of this row's custom-name well, created on first use, so the
  /// header pencil can move focus into the well it reveals.
  FocusNode get nameFocus =>
      _nameFocus ??= FocusNode(debugLabel: 'setup_name_$keyId');

  bool _nameFieldOpen = false;

  /// D2 — true once the header pencil revealed the custom-name well of a
  /// not-yet-owned service (the name is sent with the add).
  bool get nameFieldOpen => _nameFieldOpen;

  /// Reveals the custom-name well (the header pencil of a new service).
  void openNameField() {
    if (_nameFieldOpen) return;
    _nameFieldOpen = true;
    notifyListeners();
  }

  List<OwnedServiceName> _owned;

  /// D2 — the master's existing services of this type, each renameable in
  /// place (one pencil per service). Held by the type's primary row only;
  /// empty for a type the master does not offer and for extra copy rows.
  /// A read-only view over the live list (no copy per read).
  List<OwnedServiceName> get ownedServices =>
      UnmodifiableListView<OwnedServiceName>(_owned);

  /// The name [entry]'s service is saved under (blank = the type name).
  String savedNameOf(OwnedServiceName entry) {
    final String n = entry.service.name.trim();
    return n.isEmpty ? nameUk : n;
  }

  /// Opens [entry]'s rename well, pre-filled with its custom name (blank when
  /// it carries the type name — the type name is the placeholder).
  void beginRename(OwnedServiceName entry) {
    if (entry._controller != null || !_owned.contains(entry)) return;
    final String saved = savedNameOf(entry);
    entry._controller = TextEditingController(
      text: saved == nameUk ? '' : saved,
    );
    _listenRename(entry);
    notifyListeners();
  }

  /// (Re)binds [entry]'s rename-text listener to THIS row: a real text edit
  /// clears its error and notifies only when the error or the pending state
  /// flips, so plain typing stays inside the well.
  void _listenRename(OwnedServiceName entry) {
    final TextEditingController? c = entry._controller;
    if (c == null) return;
    final VoidCallback? old = entry._listener;
    if (old != null) c.removeListener(old);
    entry._lastText = c.text;
    entry._lastPending = pendingRenameOf(entry) != null;
    void listener() {
      if (c.text == entry._lastText) return; // caret / selection only
      entry._lastText = c.text;
      final bool pending = pendingRenameOf(entry) != null;
      if (entry._error == null && pending == entry._lastPending) return;
      entry._error = null;
      entry._lastPending = pending;
      notifyListeners();
    }

    entry._listener = listener;
    c.addListener(listener);
  }

  /// The name to send for [entry] — trimmed; a blank well sends the catalogue
  /// type name [nameUk] (backend `UpdateServiceDefinitionRequest.name` is
  /// `@Size(min = 1)`, so `''` would 400) — or null when its well is closed or
  /// matches the saved name. The match is by [serviceNameCanonical] (the form
  /// the backend stores), so a name the server normalised on save (space
  /// runs collapsed, full-width folded) is not pending again; a case-only
  /// change still is. Never returns an empty string.
  String? pendingRenameOf(OwnedServiceName entry) {
    final TextEditingController? c = entry._controller;
    if (c == null) return null;
    final String typed = c.text.trim();
    final String effective = typed.isEmpty ? nameUk : typed;
    return serviceNameCanonical(effective) ==
            serviceNameCanonical(savedNameOf(entry))
        ? null
        : effective;
  }

  /// Owned services of this row with an unsaved rename.
  int get pendingRenameCount {
    var n = 0;
    for (final OwnedServiceName e in _owned) {
      if (pendingRenameOf(e) != null) n++;
    }
    return n;
  }

  /// Records a saved rename, so a later save does not send it again.
  void commitRename(OwnedServiceName entry, MasterService updated) {
    entry._service = updated;
    entry._error = null;
    entry._lastPending = pendingRenameOf(entry) != null;
    notifyListeners();
  }

  /// Error on [entry]'s rename well (409 duplicate / 400 name), or null.
  void setRenameError(OwnedServiceName entry, String? value) {
    if (entry._error == value) return;
    entry._error = value;
    notifyListeners();
  }

  /// «Прибрати» on the primary row: the promoted row takes over [from]'s
  /// owned services, open rename wells and unsaved renames included, so a
  /// pending rename is never lost with the row that showed it.
  void adoptOwnedServices(ServiceRowState from) {
    if (identical(from, this) || from._owned.isEmpty) return;
    _owned = <OwnedServiceName>[..._owned, ...from._owned];
    from._owned = <OwnedServiceName>[];
    _owned.forEach(_listenRename);
    notifyListeners();
  }

  @override
  void dispose() {
    _durationFocus?.dispose();
    _nameFocus?.dispose();
    for (final OwnedServiceName e in _owned) {
      e._dispose();
    }
    name.dispose();
    duration.dispose();
    fixed.dispose();
    min.dispose();
    max.dispose();
    super.dispose();
  }
}

/// Phase 472 (D2) — one of the master's existing services shown on its
/// type's add-services row, renameable in place. Mutated only through its
/// [ServiceRowState] (which notifies); disposed with that row.
class OwnedServiceName {
  OwnedServiceName(this._service);

  MasterService _service;

  /// The service as last saved (updated after a successful rename).
  MasterService get service => _service;

  TextEditingController? _controller;

  /// The rename well's controller; null until its pencil is tapped.
  TextEditingController? get controller => _controller;

  /// True once the pencil turned this service's line into the rename well.
  bool get renaming => _controller != null;

  FocusNode? _focus;

  /// Focus node of the rename well, created on first use.
  FocusNode get focus =>
      _focus ??= FocusNode(debugLabel: 'setup_rename_${_service.id}');

  String? _error;

  /// Error shown on the rename well (409 duplicate / 400 name), or null.
  String? get error => _error;

  String _lastText = '';
  bool _lastPending = false;
  VoidCallback? _listener;

  void _dispose() {
    final VoidCallback? l = _listener;
    if (l != null) _controller?.removeListener(l);
    _controller?.dispose();
    _focus?.dispose();
  }
}

/// One configurable service-type row inside an expanded category.
///
/// A raised neumorphic card. The header row carries the service name, an
/// optional "потрібна ціна" validation flag, and the include toggle on the
/// trailing edge. While included the card expands ([AnimatedSize] + cross-fade)
/// to reveal the duration field and the fixed/range price control; while excluded
/// it collapses to a single muted header line and the card face dims, so an "off"
/// row reads as physically receded without leaving the menu.
/// Resolves the cross-field "max > min" range error for a row from its current
/// min/max text + pricing mode. Returns null when valid / not in range mode.
typedef RangeErrorResolver = String? Function(ServiceRowState row);

class ServiceTypeRowCard extends StatefulWidget {
  const ServiceTypeRowCard({
    super.key,
    required this.row,
    required this.resolveRangeError,
    this.onChanged,
    this.onFieldEdited,
    this.onAddCopy,
    this.onRemove,
    this.showNameField = false,
    this.offerCustomName = false,
    this.canRename,
    this.renameNote,
  });

  final ServiceRowState row;

  /// Computes the cross-field "max > min" message for this row from its current
  /// field text — re-run locally on min/max keystrokes (null when valid / N/A).
  final RangeErrorResolver resolveRangeError;

  /// Notifies the screen that this row's `included` / `pricingMode` changed, so
  /// any derived aggregate (footer count, chip badges) can re-derive. The row's
  /// own card already rebuilds itself via its [ServiceRowState] notifier.
  final VoidCallback? onChanged;

  /// Called once per REAL duration / name text change (never on caret or
  /// selection traffic) with whether [ServiceRowState.durationTaken] flipped.
  /// When set it REPLACES [onChanged] for field edits, so the owner runs its
  /// re-derivation (e.g. the copy pair check) exactly once per edit. Null =
  /// field edits report a taken-flip through [onChanged], as before.
  final ValueChanged<bool>? onFieldEdited;

  /// Phase 471 — when non-null (and the row is included) a «+ додати ще» text
  /// action under the row adds another copy of this type. Null = no action,
  /// the row renders exactly as before.
  final VoidCallback? onAddCopy;

  /// Phase 471 — when non-null a «Прибрати» text action removes this row.
  final VoidCallback? onRemove;

  /// Phase 471 — renders the optional name field («Назва (необов'язково)»)
  /// above the duration / price wells while the row is included.
  final bool showNameField;

  /// Phase 472 (D2) — while the row is included, a not-yet-owned type without
  /// a visible name well shows a pencil after its name that reveals the
  /// custom-name well ([ServiceRowState.openNameField]). False = no pencil,
  /// the row renders exactly as before.
  final bool offerCustomName;

  /// Phase 472 audit — whether an existing [MasterService] of this row may be
  /// renamed here; false hides its pencil (e.g. a salon definition the owner
  /// performs is identity-locked for an admin). Null = every one may, exactly
  /// as before.
  final bool Function(MasterService service)? canRename;

  /// Phase 472 audit — a caption under the owned services while a rename
  /// well is open (a salon target: the rename changes the shared definition
  /// for every master performing it). Null = no caption.
  final String? renameNote;

  @override
  State<ServiceTypeRowCard> createState() => _ServiceTypeRowCardState();
}

class _ServiceTypeRowCardState extends State<ServiceTypeRowCard> {
  @override
  void initState() {
    super.initState();
    _attach(widget.row);
  }

  @override
  void didUpdateWidget(ServiceTypeRowCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.row, widget.row)) {
      _detach(oldWidget.row);
      _attach(widget.row);
    }
  }

  @override
  void dispose() {
    _detach(widget.row);
    super.dispose();
  }

  /// Last-seen duration text, and the last-seen fixed/min/max price triple.
  ///
  /// A [TextEditingController] is a [ValueNotifier<TextEditingValue>],
  /// so it notifies on SELECTION and COMPOSING changes too — every caret move,
  /// every focus gain, every `selectAll`. Without these the listeners below ran
  /// `clearServer*Error()` + `setState` on cursor traffic alone, rebuilding the
  /// card for a value that never changed. Comparing the TEXT (the only thing
  /// either listener acts on) collapses that back to real edits.
  String _lastDurationText = '';
  String _lastPriceSignature = '';

  /// Last-seen [ServiceRowState.durationTaken], so a duration edit notifies
  /// the screen only when the CTA-gating state actually flips.
  bool _lastDurationTaken = false;

  /// Last-seen name text, so a caret move never clears the server name error.
  String _lastNameText = '';

  void _attach(ServiceRowState row) {
    _lastNameText = row.name.text;
    _lastDurationText = row.duration.text;
    _lastPriceSignature = _priceSignatureOf(row);
    _lastDurationTaken = row.durationTaken;
    row.addListener(_onRowChanged);
    // Editing the duration clears any mapped-back server duration error so the
    // red state disappears as the master fixes the value.
    row.duration.addListener(_onDurationChanged);
    // Editing any price field clears the server price error; min/max also
    // recompute the cross-field range error locally (no screen rebuild).
    row.fixed.addListener(_onPriceChanged);
    row.min.addListener(_onPriceChanged);
    row.max.addListener(_onPriceChanged);
    // Phase 471: a rename can flip [ServiceRowState.durationTaken].
    row.name.addListener(_onNameChanged);
    _lastPendingRenames = row.pendingRenameCount;
  }

  /// Last-seen [ServiceRowState.pendingRenameCount], so only a change reaches
  /// the screen (its footer counts pending renames).
  int _lastPendingRenames = 0;

  /// D2 — the header pencil: reveal the custom-name well, then focus it.
  void _startName() {
    final ServiceRowState row = widget.row;
    row.openNameField();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) row.nameFocus.requestFocus();
    });
  }

  /// D2 — an owned service's pencil: open its rename well, then focus it.
  void _startRename(OwnedServiceName entry) {
    widget.row.beginRename(entry);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) entry.focus.requestFocus();
    });
  }

  void _detach(ServiceRowState row) {
    row.removeListener(_onRowChanged);
    row.duration.removeListener(_onDurationChanged);
    row.fixed.removeListener(_onPriceChanged);
    row.min.removeListener(_onPriceChanged);
    row.max.removeListener(_onPriceChanged);
    row.name.removeListener(_onNameChanged);
  }

  void _onRowChanged() {
    if (mounted) setState(() {});
    // A rename well's pending state flipped (or a rename saved): let the
    // screen's footer re-derive — on a change only.
    final int pending = widget.row.pendingRenameCount;
    if (pending != _lastPendingRenames) {
      _lastPendingRenames = pending;
      widget.onChanged?.call();
    }
  }

  /// The three price controllers share one listener, so their combined text is
  /// compared as one signature. NUL is the separator because no keyboard or
  /// paste can produce it — a plain concatenation would let "1"+"23" and
  /// "12"+"3" collide and swallow a real edit.
  static String _priceSignatureOf(ServiceRowState row) =>
      '${row.fixed.text}\u0000${row.min.text}\u0000${row.max.text}';

  void _onDurationChanged() {
    final String text = widget.row.duration.text;
    if (text == _lastDurationText) return; // caret / selection only
    _lastDurationText = text;
    widget.row.clearServerDurationError();
    // A toggle-on duration re-seed: [_setIncluded] reports the toggle itself
    // through [onChanged], so reporting here too would run the pair check twice.
    if (_settingIncluded) {
      if (mounted) setState(() {});
      return;
    }
    // Phase 468: a duration edit can flip the row into / out of the
    // taken-duration state, which gates the footer CTA — tell the screen so
    // its aggregate re-derives. Only on a FLIP, so plain typing stays local.
    _reportFieldEdit();
    if (mounted) setState(() {});
  }

  void _onNameChanged() {
    final String text = widget.row.name.text;
    if (text == _lastNameText) return; // caret / selection only
    _lastNameText = text;
    widget.row.clearServerNameError();
    // Phase 471: a rename can flip [ServiceRowState.durationTaken].
    if (_reportFieldEdit() && mounted) setState(() {});
  }

  /// One report per real duration / name edit: through [onFieldEdited] when
  /// set (every edit, with the flip), else through [onChanged] on a flip only.
  /// Returns whether [ServiceRowState.durationTaken] flipped.
  bool _reportFieldEdit() {
    final bool taken = widget.row.durationTaken;
    final bool flipped = taken != _lastDurationTaken;
    _lastDurationTaken = taken;
    final ValueChanged<bool>? onFieldEdited = widget.onFieldEdited;
    if (onFieldEdited != null) {
      onFieldEdited(flipped);
    } else if (flipped) {
      widget.onChanged?.call();
    }
    return flipped;
  }

  void _onPriceChanged() {
    final String signature = _priceSignatureOf(widget.row);
    if (signature == _lastPriceSignature) return; // caret / selection only
    _lastPriceSignature = signature;
    widget.row.clearServerPriceError();
    if (mounted) setState(() {});
  }

  /// True while [_setIncluded] writes the row, whose setter may re-seed the
  /// duration (phase 468) — that edit is part of the toggle, not its own.
  bool _settingIncluded = false;

  void _setIncluded(bool v) {
    _settingIncluded = true;
    try {
      widget.row.included = v;
    } finally {
      _settingIncluded = false;
    }
    _lastDurationTaken = widget.row.durationTaken;
    // Toggling clears any stale flag — an excluded row is never required, and a
    // freshly-included one starts clean (its inline hints fire only on save).
    widget.row.clearFlag();
    widget.row.clearServerErrors();
    widget.onChanged?.call();
  }

  void _setMode(ServicePriceType m) {
    widget.row.pricingMode = m;
    widget.row.clearFlag();
    widget.row.clearServerErrors();
    widget.onChanged?.call();
  }

  /// The terse header flag message for the row's current [RowFlagReason]. The
  /// precise range message is surfaced inline by [PricingField], so the
  /// [RowFlagReason.invalidRange] header copy stays generic to avoid
  /// double-reporting it.
  ///
  /// [RowFlagReason.durationTooLong] is deliberately NOT surfaced here — its
  /// `serviceSetupDurationMax` copy is identical to the inline duration-field
  /// error, so the header is suppressed for it (see `showHeaderFlag` in
  /// [build]) and it falls through to the generic fallback below (never read).
  String _flagMessage(AppLocalizations l10n, RowFlagReason reason) {
    switch (reason) {
      case RowFlagReason.missingDuration:
        return l10n.serviceSetupRowMissingDuration;
      case RowFlagReason.missingPrice:
        return l10n.serviceSetupRowMissingPriceOnly;
      case RowFlagReason.invalidRange:
        return l10n.serviceSetupRowFixRange;
      case RowFlagReason.alreadyInMenu:
        // Never reached through the header slot — an alreadyInMenu row is
        // always EXCLUDED, and the header flag is gated on inclusion. Its copy
        // renders in the off-state sub-label instead. Kept as its own arm so
        // the exhaustive switch states the message rather than letting it fall
        // into the "missing price" default, which would be actively wrong if a
        // future change ever surfaced it here.
        return l10n.serviceSetupRowAlreadyInMenu;
      case RowFlagReason.durationTooLong:
      case RowFlagReason.missingBoth:
      case RowFlagReason.none:
        return l10n.serviceSetupRowMissingPrice;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ServiceRowState row = widget.row;
    // A service the master already offers. Phase 468: no longer inert — it
    // keeps its include switch and can be added again at a free duration;
    // `owned` only drives the «Вже додано» label and the calm camel hairline.
    final bool owned = row.alreadyAdded;
    final bool on = row.included;
    // Phase 472 (D2): the header pencil can reveal the name well too.
    final bool showName = widget.showNameField || row.nameFieldOpen;
    // Included copy whose duration matches an existing copy (exact duplicate).
    final bool durationTaken = row.durationTaken;
    final RowFlagReason reason = row.flagReason;
    // Backend per-field validation mapped back onto this row (null when none).
    // Only ever set on included rows (only included rows are submitted).
    final String? serverDurationError = on ? row.serverDurationError : null;
    final String? serverPriceError = on ? row.serverPriceError : null;
    final bool hasServerError =
        serverDurationError != null ||
        serverPriceError != null ||
        (on && row.serverNameError != null);
    // Only INCLUDED rows are ever validated, so an excluded row must never paint
    // a flag — gate the build-local flag on inclusion. This suppresses the flag
    // message, the error rim, and the inline field hints for an excluded row, and
    // lets the "виключено" off-state sub-label take over. A mapped-back server
    // error also tints the rim (its message rides the inline field slot).
    final bool clientFlagged = on && row.flagged;
    // Phase 471: a copy that duplicates another row of its type (pair check).
    final bool copyCollision = on && row.copyCollision;
    final bool flagged =
        clientFlagged || hasServerError || durationTaken || copyCollision;
    // "The refreshed catalogue says you already offer this, so it was switched
    // off." Not a validation fault and not the master's mistake, so it borrows
    // the already-added row's calm camel hairline rather than the red error rim
    // — but it DOES claim the off-state sub-label, because the alternative is a
    // row that silently went quiet under someone's hands.
    final bool ownedNow = !on && reason == RowFlagReason.alreadyInMenu;
    // The "too long" duration reason is field-only: its header copy would be an
    // exact duplicate of the inline duration-field error (both are
    // `serviceSetupDurationMax`), so it is excluded from the header flag line.
    // The other client reasons (missing duration / price / both, invalid range)
    // carry terse summary copy that differs from the field hints, so they keep
    // their header line.
    final bool showHeaderFlag =
        clientFlagged && reason != RowFlagReason.durationTooLong;
    final String? rangeError = widget.resolveRangeError(row);

    // Inline per-field hints derived from the save-time flag reason, so a
    // flagged row points the master at the exact empty field rather than
    // relying on the header line alone. The range case is left to
    // PricingField's own inline cross-field hint.
    final bool durationMissing =
        reason == RowFlagReason.missingDuration ||
        reason == RowFlagReason.missingBoth;
    final bool fixedPriceFlagged =
        reason == RowFlagReason.missingPrice ||
        reason == RowFlagReason.missingBoth;
    // Client-side duration hint: the "too long" (≤480) guard shows the max
    // message; an empty/invalid duration shows the "required" hint.
    final String? clientDurationError = reason == RowFlagReason.durationTooLong
        ? l10n.serviceSetupDurationMax
        : (durationMissing ? l10n.serviceSetupDurationRequired : null);
    // Server error wins over the client hint (it is the authoritative,
    // just-returned constraint), then falls back to the client-side hint.
    final String? durationError =
        serverDurationError ??
        (durationTaken
            // A row with a name field can fix the clash by renaming too.
            ? (showName
                  ? l10n.serviceSetupCopyCollision
                  : l10n.serviceSetupDurationTaken)
            : null) ??
        (copyCollision ? l10n.serviceSetupCopyCollision : null) ??
        clientDurationError;
    final String? clientFixedPriceError =
        fixedPriceFlagged && row.pricingMode == ServicePriceType.fixed
        ? l10n.serviceSetupPriceRequired
        : null;
    // A mapped-back server price error surfaces via a message-capable slot:
    // the fixed field in FIXED mode, the "min" field in RANGE mode (the "max"
    // field carries only a ring, so it has no text slot).
    final bool fixedMode = row.pricingMode == ServicePriceType.fixed;
    final String? fixedPriceError = fixedMode
        ? (serverPriceError ?? clientFixedPriceError)
        : clientFixedPriceError;
    final String? minPriceError = fixedMode ? null : serverPriceError;

    // Phase 471: the low «+ додати ще» / «Прибрати» footer owns the card's
    // bottom inset (see [_RowTextAction]); rows without it keep the pre-471
    // geometry exactly.
    final bool hasActions =
        (on && widget.onAddCopy != null) || widget.onRemove != null;

    return _BelowCardHitSlop(
      slop: hasActions ? _RowTextAction.belowCardSlop : 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: BrandColors.base,
          borderRadius: BorderRadius.circular(VelvetRadii.card),
          // Visual weight encodes availability, heaviest to lightest:
          //   included (extrudedCard) > selectable-but-off (extrudedSmall).
          // An already-added (owned) row is selectable since phase 468, so it
          // keeps the selectable lift; its hairline camel rule marks the fact.
          border: Border.all(
            color: flagged
                ? BrandColors.error
                : ((owned && !on) || ownedNow
                      ? BrandColors.accent.withValues(alpha: 0.35)
                      : Colors.transparent),
            width: flagged ? 1.4 : ((owned && !on) || ownedNow ? 1 : 0),
          ),
          boxShadow: on
              ? VelvetShadows.extrudedCard
              : VelvetShadows.extrudedSmall,
        ),
        padding: EdgeInsets.fromLTRB(
          VelvetSpacing.md + 2,
          VelvetSpacing.md,
          VelvetSpacing.md,
          hasActions ? 0 : VelvetSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Header: name + (flag / excluded sub-label) + include switch.
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _headerName(l10n, row, on, showName: showName),
                      // Header flag line only for CLIENT-side reasons — a pure
                      // server error carries its message on the inline field slot
                      // (below), so a generic header line here would misreport it.
                      // `durationTooLong` is also excluded (see showHeaderFlag) so
                      // its message shows on the duration FIELD only, never twice.
                      if (showHeaderFlag) ...<Widget>[
                        const SizedBox(height: 4),
                        Row(
                          children: <Widget>[
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 14,
                              color: BrandColors.error,
                            ),
                            const SizedBox(width: VelvetSpacing.xs + 1),
                            Flexible(
                              child: Text(
                                _flagMessage(l10n, reason),
                                style: VelvetText.feedback(BrandColors.error),
                              ),
                            ),
                          ],
                        ),
                      ] else if (owned || ownedNow) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          // One slot, two mutually exclusive facts, most
                          // specific first: an already-added row says "you
                          // already offer this" (on or off — it explains the
                          // seeded free duration); a row the catalogue refresh
                          // just claimed says "уже у вашому переліку" and is
                          // emphasised because it CHANGED under the master. A
                          // merely-off row (neither owned nor ownedNow) renders
                          // no sub-label at all.
                          owned
                              ? l10n.serviceSetupRowAlreadyAdded
                              : l10n.serviceSetupRowAlreadyInMenu,
                          style: ownedNow
                              ? VelvetText.svcCaptionNote.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: BrandColors.accentDeep,
                                )
                              : VelvetText.svcCaptionNote,
                        ),
                      ],
                      // D2: the master's existing services of this type, one
                      // pencil each (primary row only; empty otherwise).
                      if (row.ownedServices.isNotEmpty)
                        _ownedServices(l10n, row),
                    ],
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                _IncludeSwitch(
                  key: Key('setup_row_toggle_${row.keyId}'),
                  value: on,
                  onChanged: _setIncluded,
                  semanticLabel: row.nameUk,
                ),
              ],
            ),

            // Configured fields — present only while included.
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (Widget child, Animation<double> anim) {
                  // dim-decorative: fields row show/hide; 0/1
                  return FadeTransition(
                    opacity: anim,
                    child: SizeTransition(
                      sizeFactor: anim,
                      axisAlignment: -1,
                      child: child,
                    ),
                  );
                },
                child: on
                    ? KeyedSubtree(
                        key: const ValueKey<String>('row-fields'),
                        child: Padding(
                          padding: const EdgeInsets.only(top: VelvetSpacing.md),
                          // Compact one-line layout: the duration field is handed
                          // to PricingField as its leading slot, so duration and
                          // price share a single Row beneath the mode toggle.
                          child: _withNameField(
                            l10n,
                            row,
                            showName,
                            PricingField(
                              // Phase 472: keyed so revealing the name well
                              // above it keeps its state (and a focused
                              // price well's focus) instead of rebuilding.
                              key: const ValueKey<String>('row-pricing'),
                              mode: row.pricingMode,
                              onModeChanged: _setMode,
                              fixedController: row.fixed,
                              minController: row.min,
                              maxController: row.max,
                              rangeError: rangeError,
                              fixedError: fixedPriceError,
                              // RANGE-mode server price errors ride the "min" slot
                              // (the "max" well exposes only a ring, no text slot).
                              minError: minPriceError,
                              // compact=true: label-less wells, tight padding so
                              // duration + price always share one line at ~320 dp.
                              compact: true,
                              durationController: row.duration,
                              durationError: durationError,
                              // Phase 472: lets the screen focus a new copy.
                              durationFocusNode: row.durationFocus,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(
                        key: ValueKey<String>('row-collapsed'),
                      ),
              ),
            ),
            if (hasActions) _copyActions(l10n, row, on),
          ],
        ),
      ),
    );
  }

  /// Phase 471 — stacks the optional name well above [pricing] when
  /// [showName] is set ([ServiceTypeRowCard.showNameField] or the D2 header
  /// pencil). Phase 472: [pricing] always sits last in the same Column (with
  /// its own key), so the well appearing never rebuilds the pricing wells —
  /// a focused price field keeps its focus node. Without the well the Column
  /// is `min`-sized and start-aligned: the pre-471 geometry exactly.
  Widget _withNameField(
    AppLocalizations l10n,
    ServiceRowState row,
    bool showName,
    Widget pricing,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: showName
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: <Widget>[
        if (showName) ...<Widget>[
          _nameWell(
            key: Key('setup_row_name_${row.keyId}'),
            l10n: l10n,
            row: row,
            controller: row.name,
            errorText: row.included ? row.serverNameError : null,
            focusNode: row.nameFocus,
          ),
          const SizedBox(height: VelvetSpacing.md),
        ],
        pricing,
      ],
    );
  }

  /// The custom-name well shared by a copy's name (phase 471) and the inline
  /// rename of an owned service (phase 472): same label, type-name
  /// placeholder, length cap and character allow-list.
  Widget _nameWell({
    required Key key,
    required AppLocalizations l10n,
    required ServiceRowState row,
    required TextEditingController controller,
    String? errorText,
    FocusNode? focusNode,
    String? label,
  }) {
    return NeumorphicTextField(
      key: key,
      label: label ?? l10n.serviceSetupCopyNameHint,
      controller: controller,
      // Blank keeps the type name, so the type name IS the placeholder.
      hintText: row.nameUk,
      // Backend 464: BulkServiceItemRequest.name maxLength 100.
      maxLength: _nameMaxLength,
      // Mirrors the backend name allow-list (phase 464) so a character the
      // server would reject can never be typed or pasted in.
      inputFormatters: _nameInputFormatters,
      errorText: errorText,
      focusNode: focusNode,
      textInputAction: TextInputAction.done,
    );
  }

  /// The header's service name. Phase 472 (D2): while included, a
  /// not-yet-owned row without a visible name well adds a pencil that
  /// reveals it ([ServiceTypeRowCard.offerCustomName]); otherwise the exact
  /// pre-472 text.
  Widget _headerName(
    AppLocalizations l10n,
    ServiceRowState row,
    bool on, {
    required bool showName,
  }) {
    final Widget name = AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 200),
      style: VelvetText.subheading16.copyWith(
        color: on ? BrandColors.text : BrandColors.muted,
      ),
      child: Text(row.nameUk),
    );
    final bool offer =
        widget.offerCustomName && on && !row.alreadyAdded && !showName;
    if (!offer) return name;
    return Row(
      children: <Widget>[
        Flexible(child: name),
        _pencil(
          key: Key('btn-setup-row-name-${row.keyId}'),
          label: l10n.serviceSetupRenameAction,
          onTap: _startName,
        ),
      ],
    );
  }

  /// D2 — the master's existing services of this type under «Вже додано»:
  /// one compact caption line each (saved name, duration, pencil); the
  /// pencil turns its line into the shared name well, labelled with the
  /// service's duration so it is clear which copy is being renamed.
  Widget _ownedServices(AppLocalizations l10n, ServiceRowState row) {
    final TextStyle nameStyle = VelvetText.svcCaptionNote.copyWith(
      color: BrandColors.text,
    );
    final bool Function(MasterService service)? canRename = widget.canRename;
    final String? renameNote = widget.renameNote;
    final bool anyRenaming =
        renameNote != null && row.ownedServices.any((e) => e.renaming);
    return Padding(
      padding: const EdgeInsets.only(top: VelvetSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final OwnedServiceName e in row.ownedServices)
            if (e.controller case final TextEditingController c)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.xs),
                child: _nameWell(
                  key: Key('setup_row_rename_${e.service.id}'),
                  l10n: l10n,
                  row: row,
                  controller: c,
                  errorText: e.error,
                  focusNode: e.focus,
                  label: l10n.serviceSetupRenameLabel(
                    e.service.durationMinutes,
                  ),
                ),
              )
            else
              Row(
                key: Key('setup_row_owned_${e.service.id}'),
                children: <Widget>[
                  Flexible(
                    child: Text(
                      row.savedNameOf(e),
                      style: nameStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: VelvetSpacing.xs),
                  Text(
                    '${e.service.durationMinutes} '
                    '${l10n.serviceSetupDurationSuffix}',
                    style: VelvetText.svcCaptionNote,
                  ),
                  if (canRename == null || canRename(e.service))
                    _pencil(
                      key: Key('btn-setup-row-rename-${e.service.id}'),
                      label: l10n.serviceSetupRenameAction,
                      onTap: () => _startRename(e),
                    ),
                ],
              ),
          if (anyRenaming)
            Text(
              renameNote,
              key: Key('setup_row_rename_note_${row.keyId}'),
              style: VelvetText.svcCaptionNote,
            ),
        ],
      ),
    );
  }

  /// The small camel pencil after a name: a 48 dp wide box whose 16 dp glyph
  /// stays within the text line, so the line keeps its height. Its touch
  /// target and semantics rect are ≥48×48 dp all the same: [_PencilTarget]
  /// extends both vertically without taking layout height.
  Widget _pencil({
    required Key key,
    required String label,
    required VoidCallback onTap,
  }) {
    return _PencilTarget(
      label: label,
      onTap: onTap,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onTap,
        child: const SizedBox(
          width: _RowTextAction._minTouch,
          child: Padding(
            padding: EdgeInsets.only(left: VelvetSpacing.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              heightFactor: 1,
              child: Icon(
                Icons.edit_outlined,
                size: 16,
                color: BrandColors.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const int _nameMaxLength = 100;

  /// Backend 464 copy-name allow-list: letters (any script), digits, space and
  /// `- – — . , ' ’ ʼ ( ) + / & « » " № : % ! ?`.
  static final List<TextInputFormatter>
  _nameInputFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(
      RegExp(
        '[\\p{L}0-9 \u2013\u2014.,\'\u2019\u02BC()+/&\u00AB\u00BB"\u2116:%!?-]',
        unicode: true,
      ),
    ),
    // The backend subtracts the four Hangul fillers from its letter class:
    // they are `Lo` letters that render blank, so `\p{L}` above admits them.
    FilteringTextInputFormatter.deny(RegExp('[\u115F\u1160\u3164\uFFA0]')),
  ];

  /// Phase 471 — the «+ додати ще» / «Прибрати» text actions under the row.
  Widget _copyActions(AppLocalizations l10n, ServiceRowState row, bool on) {
    final VoidCallback? onAdd = on ? widget.onAddCopy : null;
    final VoidCallback? onRemove = widget.onRemove;
    return Row(
      children: <Widget>[
        if (onAdd != null)
          _RowTextAction(
            key: Key('btn-setup-row-add-copy-${row.keyId}'),
            label: l10n.serviceSetupAddCopy,
            style: _RowTextAction.accentStyle,
            onTap: onAdd,
          ),
        const Spacer(),
        if (onRemove != null)
          _RowTextAction(
            key: Key('btn-setup-row-remove-${row.keyId}'),
            label: l10n.serviceSetupRemoveCopy,
            style: _RowTextAction.mutedStyle,
            onTap: onRemove,
          ),
      ],
    );
  }
}

/// Phase 471 — a quiet caption-style text action in the row card's footer.
///
/// Kept VERY low: a single 11 sp caption line with a [_topGap] above it and
/// the card's own bottom inset ([_bottomGap], replacing the card's 16 dp
/// bottom padding) below it, so the footer adds only ~17 dp to the card.
/// The whole footer band is the hit box (≈33 dp), and [_BelowCardHitSlop]
/// extends it [belowCardSlop] dp into the empty gap under the card — a
/// ≥48 dp vertical touch target that adds no layout height. Styles are
/// hoisted (no per-build `copyWith`).
class _RowTextAction extends StatelessWidget {
  const _RowTextAction({
    super.key,
    required this.label,
    required this.style,
    required this.onTap,
  });

  final String label;
  final TextStyle style;
  final VoidCallback onTap;

  static final TextStyle accentStyle = VelvetText.svcCaptionNote.copyWith(
    fontWeight: FontWeight.w800,
    color: BrandColors.accentDeep,
  );
  static final TextStyle mutedStyle = VelvetText.svcCaptionNote.copyWith(
    fontWeight: FontWeight.w700,
    color: BrandColors.muted,
  );

  static const double _minTouch = 48;
  static const double _topGap = VelvetSpacing.xs + 2;
  static const double _bottomGap = VelvetSpacing.sm + VelvetSpacing.xs;

  /// Hit extension below the card — within the 16 dp gap the setup list
  /// leaves under every row card, so it never overlaps another control.
  static const double belowCardSlop = VelvetSpacing.md;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: _minTouch),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.xs,
              _topGap,
              VelvetSpacing.xs,
              _bottomGap,
            ),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(label, style: style),
            ),
          ),
        ),
      ),
    );
  }
}

/// Phase 471 — lets a tap up to [slop] dp BELOW the row card reach whatever
/// sits on the card's bottom edge (the [_RowTextAction] footer band). The
/// tap is clamped [_clampInset] dp inside the card — past the ≤1.4 dp border
/// inset, inside the footer's [_RowTextAction._bottomGap]. Layout and paint
/// are untouched; with `slop == 0` it is a pure pass-through, so rows without
/// copy actions behave exactly as before.
class _BelowCardHitSlop extends SingleChildRenderObjectWidget {
  const _BelowCardHitSlop({required this.slop, required super.child});

  final double slop;

  @override
  _RenderBelowCardHitSlop createRenderObject(BuildContext context) =>
      _RenderBelowCardHitSlop(slop);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderBelowCardHitSlop renderObject,
  ) {
    renderObject.slop = slop;
  }
}

class _RenderBelowCardHitSlop extends RenderProxyBox {
  _RenderBelowCardHitSlop(this.slop);

  double slop;

  static const double _clampInset = VelvetSpacing.xs;

  /// Phase 472 audit — the card's [_PencilTarget]s (they register on attach).
  final Set<_RenderPencilTarget> _pencils = <_RenderPencilTarget>{};

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final bool inSlop =
        slop > 0 &&
        position.dx >= 0 &&
        position.dx < size.width &&
        position.dy >= size.height &&
        position.dy < size.height + slop;
    final Offset at = inSlop
        ? Offset(position.dx, size.height - _clampInset)
        : position;
    return super.hitTest(result, position: _towardPencil(at) ?? at);
  }

  /// A tap inside a pencil's 48×48 touch rect but outside its laid-out box
  /// is redirected to the nearest such pencil's centre — unless it lands
  /// directly on another gesture target (a text field, an action), which
  /// keeps it. Null = hit-test [at] as is.
  Offset? _towardPencil(Offset at) {
    if (_pencils.isEmpty) return null;
    Offset? best;
    var bestDistance = double.infinity;
    for (final _RenderPencilTarget pencil in _pencils) {
      if (!pencil.attached || !pencil.hasSize) continue;
      final Matrix4 toCard = pencil.getTransformTo(this);
      if (!MatrixUtils.transformRect(toCard, pencil.touchRect).contains(at)) {
        continue;
      }
      final Rect box = MatrixUtils.transformRect(
        toCard,
        Offset.zero & pencil.size,
      );
      if (box.contains(at)) return null; // a direct hit needs no help
      final double distance = (box.center - at).distanceSquared;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = box.center;
      }
    }
    if (best == null) return null;
    final BoxHitTestResult probe = BoxHitTestResult();
    super.hitTest(probe, position: at);
    for (final HitTestEntry entry in probe.path) {
      if (entry.target is RenderPointerListener) return null;
    }
    return best;
  }
}

/// Phase 472 audit — gives the inline pencil a ≥48×48 dp touch target and
/// semantics rect without layout height: the rect grows vertically (and
/// horizontally if ever narrower) around the laid-out box; the enclosing
/// row card ([_RenderBelowCardHitSlop]) routes taps in it to the pencil.
/// Owns the pencil's button semantics (label + tap).
class _PencilTarget extends SingleChildRenderObjectWidget {
  const _PencilTarget({
    required this.label,
    required this.onTap,
    required super.child,
  });

  final String label;
  final VoidCallback onTap;

  @override
  _RenderPencilTarget createRenderObject(BuildContext context) =>
      _RenderPencilTarget(
        label: label,
        onTap: onTap,
        textDirection: Directionality.maybeOf(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPencilTarget renderObject,
  ) {
    renderObject
      ..label = label
      ..onTap = onTap
      ..textDirection = Directionality.maybeOf(context);
  }
}

class _RenderPencilTarget extends RenderProxyBox {
  _RenderPencilTarget({
    required String label,
    required VoidCallback onTap,
    TextDirection? textDirection,
  }) : _label = label,
       _onTap = onTap,
       _textDirection = textDirection;

  static const double minTouch = _RowTextAction._minTouch;

  String _label;
  set label(String value) {
    if (_label == value) return;
    _label = value;
    markNeedsSemanticsUpdate();
  }

  VoidCallback _onTap;
  set onTap(VoidCallback value) {
    if (_onTap == value) return;
    _onTap = value;
    markNeedsSemanticsUpdate();
  }

  TextDirection? _textDirection;
  set textDirection(TextDirection? value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsSemanticsUpdate();
  }

  _RenderBelowCardHitSlop? _host;

  /// The ≥[minTouch]-square touch rect, centred on the laid-out box, in
  /// this box's coordinates.
  Rect get touchRect {
    final double dx = math.max(0, (minTouch - size.width) / 2);
    final double dy = math.max(0, (minTouch - size.height) / 2);
    return Rect.fromLTRB(-dx, -dy, size.width + dx, size.height + dy);
  }

  @override
  Rect get semanticBounds => touchRect;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..isButton = true
      ..label = _label
      ..textDirection = _textDirection
      ..onTap = _onTap;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    RenderObject? node = parent;
    while (node != null && node is! _RenderBelowCardHitSlop) {
      node = node.parent;
    }
    if (node is _RenderBelowCardHitSlop) {
      _host = node.._pencils.add(this);
    }
  }

  @override
  void detach() {
    _host?._pencils.remove(this);
    _host = null;
    super.detach();
  }
}

/// The per-row include toggle — a soft-UI switch. A recessed inset track holds a
/// raised pebble that slides on toggle; ON fills the track with the camel
/// gradient + a cream check, OFF is a plain inset well. Mirrors the tactile
/// language of the pricing-mode toggle so the two read as one family.
class _IncludeSwitch extends StatelessWidget {
  const _IncludeSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String semanticLabel;

  static const double _w = 54;
  static const double _h = 30;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: _w,
          height: _h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VelvetRadii.pill),
            gradient: value
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      BrandColors.accentLatte,
                      BrandColors.accentDeep,
                    ],
                  )
                : null,
            color: value ? null : BrandColors.base,
            boxShadow: value ? VelvetShadows.extrudedSmall : null,
          ),
          child: value
              ? _knob(alignment: Alignment.centerRight, showCheck: true)
              : NeumorphicInset(
                  radius: VelvetRadii.pill,
                  child: _knob(
                    alignment: Alignment.centerLeft,
                    showCheck: false,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _knob({required Alignment alignment, required bool showCheck}) {
    return Padding(
      padding: const EdgeInsets.all(VelvetSpacing.xs),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: alignment,
        child: Container(
          width: _h - 8,
          height: _h - 8,
          decoration: const BoxDecoration(
            color: BrandColors.white,
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: showCheck
              ? const Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: BrandColors.accentDeep,
                )
              : null,
        ),
      ),
    );
  }
}
