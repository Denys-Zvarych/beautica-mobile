// Phase 5.3 — Reusable service form widget.
// Phase 5.4 — Extended with [initial] MasterService support for the edit flow:
//   - Pre-populates fields from the loaded service.
//   - Dirty-state tracking: compares current field values vs the loaded baseline.
//   - Exposes a "Незбережені зміни" badge via [_DirtyMarker] (fades in whenever
//     any field diverges from the loaded values).
//   - [ServiceEditScreen] passes [initial] and a [MasterServiceUpdate]-producing
//     [onSubmit] callback; [ServiceCreateScreen] passes nothing (blank form).
// Phase 5.x — Category chip selector added between the name field and the
//   duration+pricing row. Supports both create (blank) and edit (pre-populated)
//   modes. Dirty-state tracking includes the selected category.
// Phase 5.6 — Flexible pricing: replaced the single price field with
//   [PricingField] — a two-mode segmented control (Фіксована / Діапазон).
//   - FIXED mode: one "Сума" amount field with "грн" suffix.
//   - RANGE mode: side-by-side "Від" / "До" fields with an inline range error hint.
//   - Edit form pre-fills the toggle + fields from [MasterService.priceType],
//     [priceMin], [priceMax].
//   - Dirty-state tracking includes priceType + all price field values.
//   - Price display in cards/lists uses [MasterService.priceDisplay] (server-
//     formatted) — no client-side string building.
//
// Description is intentionally absent from the UI (user decision: deferred).
// [MasterServiceCreate.description] is left null when the payload is built.

import 'dart:developer';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:flutter/foundation.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/category_slug.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/category_request_dialog.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/pricing_field.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/validators/name_validator.dart';
import 'package:beautica_mobile/shared/validators/numeric_validators.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A form for creating or editing a service.
///
/// Renders three [NeumorphicTextField]-equivalent fields (using the project's
/// existing [NeumorphicInset] + [TextField] composition identical to the
/// approved preview app) and a [NeumorphicButton] CTA. Validation is
/// submit-triggered: errors surface after the first submit attempt, then clear
/// live as the user corrects each field.
///
/// [initial] seeds all fields for the edit use-case (Phase 5.4). When null,
/// the form starts blank (create use-case). When set, a dirty-state marker
/// ("Незбережені зміни") fades in beneath the sub-heading the moment any
/// field diverges from the loaded values, giving the master a quiet signal.
///
/// [submitLabel] overrides the CTA label. Defaults to [l10n.masterSaveButton]
/// when null, so the create screen gets "Зберегти" and the edit screen gets
/// "Зберегти зміни" by passing the appropriate l10n key.
///
/// [onSubmit] is awaited; the form disables the submit button and shows a
/// spinner while it is in-flight. Any exception thrown by [onSubmit] propagates
/// to the caller — the screen is responsible for error presentation.
class ServiceForm extends StatefulWidget {
  const ServiceForm({
    super.key,
    this.initial,
    this.submitLabel,
    required this.onSubmit,
  });

  /// Pre-filled service values (edit mode). Null = blank form (create mode).
  ///
  /// When set, the dirty-state marker is shown whenever any field value
  /// diverges from the baseline established by this object.
  final MasterService? initial;

  /// Override for the CTA button label. When null, uses [l10n.masterSaveButton].
  final String? submitLabel;

  /// Called with the validated payload when the user taps Save.
  ///
  /// Must return a [Future] so the form can show a loading spinner. Throw a
  /// [Failure] or any exception to surface an error at the screen level.
  final Future<void> Function(MasterServiceCreate input) onSubmit;

  @override
  State<ServiceForm> createState() => _ServiceFormState();
}

class _ServiceFormState extends State<ServiceForm> {
  static const _tag = 'feature.services.form';

  // Label styles — cached to avoid per-frame TextStyle allocations.
  static final TextStyle _labelStyle = VelvetText.label();
  static final TextStyle _feedbackError = VelvetText.feedback(
    BrandColors.error,
  );
  static final TextStyle _subheadingStyle = VelvetText.body();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _durationCtrl;

  // Pricing controllers and mode state (Phase 5.6 flexible pricing).
  late final TextEditingController _priceFixedCtrl;
  late final TextEditingController _priceMinCtrl;
  late final TextEditingController _priceMaxCtrl;
  ServicePriceType _pricingMode = ServicePriceType.fixed;

  bool _submitted = false;
  bool _submitting = false;
  bool _wasDirty = false;

  /// Bumped on every keystroke that can change a field's inline error text
  /// (live re-validation after the first submit, or a cleared server error).
  /// Only the per-field error sub-trees listen to this — `_CategoryChips`
  /// (which reads [approvedCategoriesProvider] and rebuilds N chips) stays
  /// outside its scope, so typing in a price/name field never rebuilds the
  /// chip row. Replaces the old form-wide `setState(() {})` (perf MEDIUM).
  final ValueNotifier<int> _revalidateTick = ValueNotifier<int>(0);

  /// Drives only the [_DirtyMarker] repaint when the dirty edge flips, instead
  /// of rebuilding the whole form to toggle one boolean (perf LOW).
  final ValueNotifier<bool> _dirtyNotifier = ValueNotifier<bool>(false);

  /// Server-side field errors from the last [ValidationFailure] returned by
  /// [widget.onSubmit]. Keyed by the BACKEND wire field name
  /// (`name`, `baseDurationMinutes`, `price`, `priceMin`, `priceMax`,
  /// `category`, `bufferMinutesAfter`). When a key is present its message
  /// wins over the client-side validator for that field, so the backend's
  /// specific reason is surfaced inline instead of a generic snackbar. Each
  /// entry is cleared the moment the user edits the matching field.
  Map<String, String> _serverFieldErrors = const <String, String>{};

  // Dirty-state baseline values (edit mode only). These are the string
  // representations of widget.initial fields — compared against current
  // field texts, the selected category, and pricing mode to determine if
  // the form is dirty.
  late final String _baselineName;
  late final String _baselineDuration;
  late final ServicePriceType _baselinePricingMode;
  late final String _baselinePriceFixed;
  late final String _baselinePriceMin;
  late final String _baselinePriceMax;
  late final String? _baselineCategory;

  /// Currently selected category wire name. Null = no category selected.
  String? _selectedCategory;

  /// True when the form is in edit mode ([widget.initial] is set) and at
  /// least one field (including category or pricing) differs from the loaded
  /// service values.
  bool get _isDirty {
    if (widget.initial == null) return false;
    return _nameCtrl.text != _baselineName ||
        _durationCtrl.text != _baselineDuration ||
        _pricingMode != _baselinePricingMode ||
        _priceFixedCtrl.text != _baselinePriceFixed ||
        _priceMinCtrl.text != _baselinePriceMin ||
        _priceMaxCtrl.text != _baselinePriceMax ||
        _selectedCategory != _baselineCategory;
  }

  @override
  void initState() {
    super.initState();

    final MasterService? initial = widget.initial;

    _baselineName = initial?.name ?? '';
    _baselineDuration = initial != null
        ? initial.durationMinutes.toString()
        : '';
    _baselineCategory = initial?.category;
    _baselinePricingMode = initial?.priceType ?? ServicePriceType.fixed;

    // Seed pricing baseline from the loaded service.
    // priceMin is the canonical floor for both modes; display as integer.
    _baselinePriceFixed =
        (initial?.priceType == ServicePriceType.fixed &&
            initial?.priceMin != null)
        ? initial!.priceMin.toInt().toString()
        : '';
    _baselinePriceMin =
        (initial?.priceType == ServicePriceType.range &&
            initial?.priceMin != null)
        ? initial!.priceMin.toInt().toString()
        : '';
    _baselinePriceMax =
        (initial?.priceType == ServicePriceType.range &&
            initial?.priceMax != null)
        ? initial!.priceMax!.toInt().toString()
        : '';

    _selectedCategory = initial?.category;
    _pricingMode = _baselinePricingMode;

    _nameCtrl = TextEditingController(text: _baselineName);
    _durationCtrl = TextEditingController(text: _baselineDuration);
    _priceFixedCtrl = TextEditingController(text: _baselinePriceFixed);
    _priceMinCtrl = TextEditingController(text: _baselinePriceMin);
    _priceMaxCtrl = TextEditingController(text: _baselinePriceMax);

    // After first submit, live-re-validate on every keystroke so errors clear
    // the instant the field becomes valid. In edit mode, also repaint the dirty
    // badge on each keystroke. Editing a field also clears any stale
    // server-side error keyed to that field's backend wire name.
    _nameCtrl.addListener(() => _onChanged('name'));
    _durationCtrl.addListener(() => _onChanged('baseDurationMinutes'));
    _priceFixedCtrl.addListener(() => _onChanged('price'));
    _priceMinCtrl.addListener(() => _onChanged('priceMin'));
    _priceMaxCtrl.addListener(() => _onChanged('priceMax'));
  }

  /// Re-renders on field change. [serverFieldName] is the backend wire name of
  /// the field that changed — any stale server error for it is dropped so the
  /// inline message disappears as soon as the user edits the offending field.
  void _onChanged([String? serverFieldName]) {
    if (!mounted) return;
    final bool clearedServerError =
        serverFieldName != null &&
        _serverFieldErrors.containsKey(serverFieldName);
    if (clearedServerError) {
      _serverFieldErrors = Map<String, String>.unmodifiable(
        Map<String, String>.from(_serverFieldErrors)..remove(serverFieldName),
      );
    }
    // Live re-validation: bump the error tick so ONLY the per-field error
    // sub-trees recompute. Never calls setState, so `_CategoryChips` and the
    // rest of the form do not rebuild on a keystroke.
    if (_submitted || clearedServerError) {
      _revalidateTick.value++;
    }
    // Dirty edge: repaint only the `_DirtyMarker` via its own notifier.
    final dirty = _isDirty;
    if (dirty != _wasDirty) {
      _wasDirty = dirty;
      _dirtyNotifier.value = dirty;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _durationCtrl.dispose();
    _priceFixedCtrl.dispose();
    _priceMinCtrl.dispose();
    _priceMaxCtrl.dispose();
    _revalidateTick.dispose();
    _dirtyNotifier.dispose();
    super.dispose();
  }

  // --- Validators -----------------------------------------------------------

  String? _nameError(AppLocalizations l10n) {
    final String? server = _serverFieldErrors['name'];
    if (server != null) return server;
    if (!_submitted) return null;
    return validateName(_nameCtrl.text, l10n);
  }

  String? _durationError(AppLocalizations l10n) {
    final String? server = _serverFieldErrors['baseDurationMinutes'];
    if (server != null) return server;
    if (!_submitted) return null;
    return validateDurationMinutes(_durationCtrl.text, l10n);
  }

  // --- Pricing validators (Phase 5.6; hardened 2026-06-03) -------------------
  // Bounds now come from the shared pure validators in
  // shared/validators/numeric_validators.dart so the form, the unit tests, and
  // the input formatters all agree on the same backend contract (decimals ≤ 2,
  // 0.01 ≤ price ≤ 99 999 999.99, RANGE max strictly > min).

  /// Inline error for the fixed-amount field (FIXED mode only).
  String? _fixedPriceError(AppLocalizations l10n) {
    final String? server = _serverFieldErrors['price'];
    if (server != null) return server;
    if (!_submitted || _pricingMode != ServicePriceType.fixed) return null;
    return validatePriceAmount(
      _priceFixedCtrl.text,
      l10n,
      requiredMessage: l10n.errRequired,
    );
  }

  /// Inline error for the "Від" (min) field (RANGE mode only).
  String? _rangeMinError(AppLocalizations l10n) {
    final String? server = _serverFieldErrors['priceMin'];
    if (server != null) return server;
    if (!_submitted || _pricingMode != ServicePriceType.range) return null;
    return validatePriceAmount(
      _priceMinCtrl.text,
      l10n,
      requiredMessage: l10n.errPriceMinRequired,
    );
  }

  /// Cross-field error: max must be present, valid, and strictly greater than min.
  String? _rangeMaxError(AppLocalizations l10n) {
    final String? server = _serverFieldErrors['priceMax'];
    if (server != null) return server;
    if (!_submitted || _pricingMode != ServicePriceType.range) return null;
    return validatePriceMax(
      _priceMaxCtrl.text,
      _priceMinCtrl.text,
      l10n,
      requiredMessage: l10n.errPriceMaxRequired,
    );
  }

  bool _pricingValid(AppLocalizations l10n) {
    switch (_pricingMode) {
      case ServicePriceType.fixed:
        return _fixedPriceError(l10n) == null &&
            _priceFixedCtrl.text.trim().isNotEmpty;
      case ServicePriceType.range:
        return _rangeMinError(l10n) == null &&
            _rangeMaxError(l10n) == null &&
            _priceMinCtrl.text.trim().isNotEmpty &&
            _priceMaxCtrl.text.trim().isNotEmpty;
    }
  }

  /// Category is required by the backend (`@NotBlank`); surface a required
  /// error after the first submit attempt when no chip is selected. A
  /// server-side `category` error wins over the client-side required check.
  String? _categoryError(AppLocalizations l10n) {
    final String? server = _serverFieldErrors['category'];
    if (server != null) return server;
    if (!_submitted) return null;
    return (_selectedCategory == null || _selectedCategory!.isEmpty)
        ? l10n.serviceCategoryRequired
        : null;
  }

  bool _isValid(AppLocalizations l10n) =>
      _nameError(l10n) == null &&
      _durationError(l10n) == null &&
      _pricingValid(l10n) &&
      _categoryError(l10n) == null &&
      _nameCtrl.text.trim().isNotEmpty &&
      _durationCtrl.text.trim().isNotEmpty;

  // --- Submit ---------------------------------------------------------------

  Future<void> _handleSubmit(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    // A fresh submit attempt clears any stale server-side field errors so the
    // form re-validates from scratch.
    setState(() {
      _submitted = true;
      _serverFieldErrors = const <String, String>{};
    });
    if (!_isValid(l10n)) {
      setState(() {});
      return;
    }
    setState(() => _submitting = true);
    try {
      // Prices parsed via the shared parser so the submitted value is computed
      // exactly as the validator checked it (comma → dot, ≤ 2 dp). _isValid
      // guarantees these are non-null at this point.
      final MasterServiceCreate input;
      switch (_pricingMode) {
        case ServicePriceType.fixed:
          input = MasterServiceCreate(
            name: _nameCtrl.text.trim(),
            durationMinutes: int.parse(_durationCtrl.text.trim()),
            priceType: ServicePriceType.fixed,
            price: parsePrice(_priceFixedCtrl.text),
            // Description intentionally omitted (user decision, Phase 5.3).
            category: _selectedCategory,
          );
        case ServicePriceType.range:
          input = MasterServiceCreate(
            name: _nameCtrl.text.trim(),
            durationMinutes: int.parse(_durationCtrl.text.trim()),
            priceType: ServicePriceType.range,
            priceMin: parsePrice(_priceMinCtrl.text),
            priceMax: parsePrice(_priceMaxCtrl.text),
            category: _selectedCategory,
          );
      }
      await widget.onSubmit(input);
    } on ValidationFailure catch (f) {
      // Backend per-field validation: surface each error inline on the matching
      // input instead of letting the screen show a single generic snackbar.
      // Only rethrow when NONE of the field keys map to a field we render — in
      // that case the screen falls back to its generic snackbar. The backend
      // wire field names are name / baseDurationMinutes / price / priceMin /
      // priceMax / category / bufferMinutesAfter.
      if (kDebugMode) {
        log(
          'ServiceForm.onSubmit validation failure: ${f.fieldErrors}',
          name: _tag,
          level: 900,
        );
      }
      final Map<String, String> mapped = _mapServerFieldErrors(f.fieldErrors);
      if (mapped.isEmpty) {
        // No recognised field — surface the backend's generic message (or a
        // localized fallback) as a snackbar so the submit never dies silently.
        if (context.mounted) {
          final String msg = (f.serverMessage?.trim().isNotEmpty ?? false)
              ? f.serverMessage!.trim()
              : f.userMessage(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
          );
        }
        return;
      }
      if (mounted) {
        setState(
          () => _serverFieldErrors = Map<String, String>.unmodifiable(mapped),
        );
      }
      // Swallow — the inline errors now communicate the problem; rethrowing
      // would also pop a redundant generic snackbar.
    } catch (e, st) {
      if (kDebugMode) {
        log(
          'ServiceForm.onSubmit threw: $e',
          name: _tag,
          level: 900,
          error: e,
          stackTrace: st,
        );
      }
      rethrow;
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  /// Filters [raw] (the backend `errors` field map) down to the keys this form
  /// renders inline. Unknown keys are dropped so the caller's generic snackbar
  /// fallback still fires when the backend flags a field we don't show.
  ///
  /// `baseDurationMinutes` is also accepted under its legacy `durationMinutes`
  /// alias for forward/backward compatibility with the backend contract.
  Map<String, String> _mapServerFieldErrors(Map<String, String> raw) {
    const Set<String> known = <String>{
      'name',
      'baseDurationMinutes',
      'price',
      'priceMin',
      'priceMax',
      'category',
      'bufferMinutesAfter',
    };
    final Map<String, String> out = <String, String>{};
    raw.forEach((String key, String message) {
      // Normalise the legacy duration alias onto the field we render.
      final String field = key == 'durationMinutes'
          ? 'baseDurationMinutes'
          : key;
      if (known.contains(field) && message.trim().isNotEmpty) {
        out[field] = message.trim();
      }
    });
    return out;
  }

  // --- Field builder --------------------------------------------------------

  /// Builds a labelled neumorphic inset field with optional suffix text and
  /// inline error rendering. Used for the name and duration fields only;
  /// pricing is handled by [PricingField].
  Widget _buildField({
    required Key fieldKey,
    required String label,
    required TextEditingController controller,
    required String? errorText,
    String? hintText,
    String? suffixText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool enabled = true,
  }) {
    return _VelvetFieldRow(
      fieldKey: fieldKey,
      label: label,
      controller: controller,
      errorText: errorText,
      hintText: hintText,
      suffixText: suffixText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      enabled: enabled,
      labelStyle: _labelStyle,
      feedbackErrorStyle: _feedbackError,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool isEditMode = widget.initial != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Intro sub-heading — mirrors the preview's quiet intent line.
        Padding(
          padding: const EdgeInsets.only(left: VelvetSpacing.xs),
          child: Text(
            isEditMode
                ? l10n.serviceEditSubheading
                : l10n.serviceFormSubheading,
            style: _subheadingStyle,
          ),
        ),

        // Dirty-state marker (edit mode only) — fades in beneath the intro
        // line when any field diverges from the loaded service values. Listens
        // to `_dirtyNotifier` so a keystroke that flips the dirty edge repaints
        // ONLY this marker, never the whole form (perf LOW).
        if (isEditMode)
          ValueListenableBuilder<bool>(
            valueListenable: _dirtyNotifier,
            builder: (BuildContext context, bool dirty, _) =>
                _DirtyMarker(visible: dirty, l10n: l10n),
          ),

        const SizedBox(height: VelvetSpacing.lg),

        // 1 — Service name (required, 1–255 chars). Wrapped in a
        // ValueListenableBuilder so a keystroke re-validates only this field's
        // inline error — `_CategoryChips` stays out of the rebuild (perf MEDIUM).
        ValueListenableBuilder<int>(
          valueListenable: _revalidateTick,
          builder: (BuildContext context, _, _) => _buildField(
            fieldKey: const Key('field-service-name'),
            label: l10n.serviceNameLabel,
            controller: _nameCtrl,
            errorText: _nameError(l10n),
            hintText: l10n.serviceNameHint,
            enabled: !_submitting,
          ),
        ),
        const SizedBox(height: VelvetSpacing.lg),

        // 1b — Category chip selector (optional; tapping a selected chip
        //      deselects it so the master can clear the category). Chips are
        //      sourced from the approved-category provider (Ukrainian labels).
        _CategoryChips(
          selected: _selectedCategory,
          disabled: _submitting,
          label: l10n.serviceCategoryLabel,
          errorText: _categoryError(l10n),
          onSelect: (String? wire) {
            setState(() {
              _selectedCategory = wire;
            });
            _wasDirty = _isDirty;
            _dirtyNotifier.value = _wasDirty;
          },
        ),
        const SizedBox(height: VelvetSpacing.lg),

        // 2 — Duration field (required, integer 1–480 min / 8 h — backend cap).
        //     Same per-field re-validation isolation as the name field.
        ValueListenableBuilder<int>(
          valueListenable: _revalidateTick,
          builder: (BuildContext context, _, _) => _buildField(
            fieldKey: const Key('field-service-duration'),
            label: l10n.serviceDurationLabel,
            controller: _durationCtrl,
            errorText: _durationError(l10n),
            hintText: '60',
            suffixText: 'хв',
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            enabled: !_submitting,
          ),
        ),
        const SizedBox(height: VelvetSpacing.lg),

        // 3 — Pricing: FIXED (single amount) or RANGE (min–max) via the
        //     two-mode segmented toggle + conditional field area. Wrapped in a
        //     ValueListenableBuilder so a price keystroke re-validates only the
        //     pricing sub-tree — the chip row stays out of scope (perf MEDIUM).
        ValueListenableBuilder<int>(
          valueListenable: _revalidateTick,
          builder: (BuildContext context, _, _) => PricingField(
            key: const Key('pricing-field'),
            mode: _pricingMode,
            enabled: !_submitting,
            onModeChanged: (ServicePriceType m) {
              setState(() {
                _pricingMode = m;
              });
              _wasDirty = _isDirty;
              _dirtyNotifier.value = _wasDirty;
            },
            fixedController: _priceFixedCtrl,
            minController: _priceMinCtrl,
            maxController: _priceMaxCtrl,
            fixedError: _fixedPriceError(l10n),
            minError: _rangeMinError(l10n),
            rangeError: _rangeMaxError(l10n),
          ),
        ),
        const SizedBox(height: VelvetSpacing.xl),

        // CTA — Save / Save changes button.
        NeumorphicButton(
          key: const Key('btn-submit-service'),
          label: widget.submitLabel ?? l10n.masterSaveButton,
          icon: Icons.check_rounded,
          loading: _submitting,
          onPressed: _submitting ? null : () => _handleSubmit(context, l10n),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Dirty-state marker
//
// A small camel inset pill that fades + slides in when the form diverges from
// its loaded values, and fades out when the user reverts every field. Mirrors
// the `_DirtyMarker` in the approved ServiceEditForm preview app exactly.
// ---------------------------------------------------------------------------

// Label styles extracted to `static final` to avoid per-frame allocations.
class _DirtyMarker extends StatelessWidget {
  const _DirtyMarker({required this.visible, required this.l10n});

  final bool visible;
  final AppLocalizations l10n;

  // Hoisted: never construct inside build().
  // feedbackAccentSm = Nunito 13/700, accentDeep, 12 sp — the closest
  // pre-cached variant to the approved preview's "caption accentDeep w800".
  // One cheap copyWith for the weight and tracking delta — far cheaper than
  // a full GoogleFonts.nunito() call on every frame.
  static final TextStyle _captionStyle = VelvetText.feedbackAccentSm.copyWith(
    fontWeight: FontWeight.w800,
    letterSpacing: 0.2,
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topLeft,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: visible ? 1.0 : 0.0,
        child: visible
            ? Padding(
                padding: const EdgeInsets.only(
                  left: VelvetSpacing.xs,
                  top: VelvetSpacing.sm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      height: 7,
                      width: 7,
                      decoration: const BoxDecoration(
                        color: BrandColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: VelvetSpacing.sm),
                    Text(l10n.serviceUnsavedChanges, style: _captionStyle),
                  ],
                ),
              )
            : const SizedBox(width: double.infinity, height: 0),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category chip selector
//
// A labelled section containing a horizontally-scrollable Wrap of neumorphic
// category pills. Unselected chips are inset (recessed well), selected chips
// are extruded with the camel/mocha CTA gradient and a leading check icon.
//
// Extracted to a StatelessWidget so that the callback-driven tap response
// is self-contained and the parent form's rebuild scope is tightly bounded.
// ---------------------------------------------------------------------------

/// A labelled row of neumorphic category chips for the service form.
///
/// Chips are sourced from [approvedCategoriesProvider] — each chip renders the
/// Ukrainian [ServiceCategoryOption.displayName] as its label while the
/// [ServiceCategoryOption.name] wire slug is the value sent to [onSelect].
///
/// [selected] is the currently-selected wire name, or null for none.
/// [onSelect] is called with the new wire name (or null when deselected).
/// [disabled] suppresses tap responses when a submit is in-flight.
///
/// The async provider's states are handled compactly so the rest of the form
/// stays usable (category is optional):
///   - loading → a single inset "skeleton" chip;
///   - error   → a compact error line + retry chip;
///   - data    → the chip row + a trailing "suggest a category" chip.
class _CategoryChips extends ConsumerWidget {
  const _CategoryChips({
    required this.selected,
    required this.label,
    required this.onSelect,
    this.errorText,
    this.disabled = false,
  });

  final String? selected;
  final String label;
  final ValueChanged<String?> onSelect;

  /// Required-field error surfaced beneath the chip row after a submit attempt
  /// with no category selected. Null when there is no error.
  final String? errorText;
  final bool disabled;

  // Section-label style — hoisted as a static final to avoid per-frame
  // TextStyle allocations. Matches the field-label convention already used by
  // _VelvetFieldRow (VelvetText.label(), then uppercased at render time).
  static final TextStyle _sectionLabelStyle = VelvetText.label();

  Future<void> _openSuggestDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final submitted = await showCategoryRequestDialog(context);
    if (submitted == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.categoryRequestSuccess),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final categoriesAsync = ref.watch(approvedCategoriesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Section label (uppercased at render time, same as field labels).
        Padding(
          padding: const EdgeInsets.only(
            left: VelvetSpacing.xs,
            bottom: VelvetSpacing.sm,
          ),
          child: Text(label.toUpperCase(), style: _sectionLabelStyle),
        ),
        categoriesAsync.when(
          loading: () => const _CategoryChipsLoading(),
          error: (_, _) => _CategoryChipsError(
            l10n: l10n,
            disabled: disabled,
            onRetry: () => ref.invalidate(approvedCategoriesProvider),
          ),
          data: (List<ServiceCategoryOption> options) {
            // Guard: if the loaded service's category was deprecated/removed
            // from the approved list, still render a chip for it so the
            // selection stays visible (and reversible).
            final List<ServiceCategoryOption> chips = _withSelected(options);
            // A Wrap inside a horizontal SingleChildScrollView gets unbounded
            // width and never wraps, so chips run off-screen on narrow devices.
            // Letting the Wrap wrap within the form's bounded width keeps every
            // chip (incl. the selected + "suggest" affordance) visible; the
            // outer form already provides vertical scrolling.
            return Wrap(
              spacing: VelvetSpacing.sm,
              runSpacing: VelvetSpacing.sm,
              children: <Widget>[
                for (final ServiceCategoryOption option in chips)
                  _CategoryChip(
                    key: Key('chip-category-${option.name}'),
                    wire: option.name,
                    label: option.displayName,
                    isSelected: _matches(selected, option.name),
                    disabled: disabled,
                    onTap: () => onSelect(
                      _matches(selected, option.name) ? null : option.name,
                    ),
                  ),
                // Trailing affordance — opens the suggest-a-category dialog.
                _SuggestCategoryChip(
                  key: const Key('chip-category-suggest'),
                  label: l10n.serviceCategorySuggest,
                  disabled: disabled,
                  onTap: () => _openSuggestDialog(context),
                ),
              ],
            );
          },
        ),
        // Required-field error row (shown after a submit with no selection).
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(
              left: VelvetSpacing.xs,
              right: VelvetSpacing.xs,
              top: VelvetSpacing.sm,
            ),
            child: Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 15,
                    color: Color(0xFFB0452F), // BrandColors.error
                  ),
                  const SizedBox(width: VelvetSpacing.xs + 2),
                  Expanded(child: Text(errorText!, style: _categoryErrorStyle)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // Error style — hoisted; matches the field-error feedback style.
  static final TextStyle _categoryErrorStyle = VelvetText.feedback(
    const Color(0xFFB0452F), // BrandColors.error
  );

  /// Returns [options] with the currently-[selected] category appended when it
  /// is absent from the approved list, so an existing service's category chip
  /// never disappears (keeps the toggle reversible).
  List<ServiceCategoryOption> _withSelected(
    List<ServiceCategoryOption> options,
  ) {
    final String? sel = selected;
    if (sel == null || sel.isEmpty) return options;
    final present = options.any((o) => _matches(sel, o.name));
    if (present) return options;
    return <ServiceCategoryOption>[
      ...options,
      // No Ukrainian displayName available client-side for a category absent
      // from the approved list (deactivated/retired, or a transient empty list
      // while the backend is slow). Humanize the wire slug for the visible
      // label instead of leaking the raw ALL-CAPS slug; the wire value [name]
      // is preserved unchanged for submission.
      ServiceCategoryOption(name: sel, displayName: humanizeCategorySlug(sel)),
    ];
  }

  /// Case/whitespace-insensitive equality for wire slugs — defends against
  /// drift between the persisted selection and the approved-list entries.
  static bool _matches(String? a, String b) => categorySlugMatches(a, b);
}

/// Compact loading state for the category chip row — a single inset skeleton
/// pill so the row keeps its height while the approved list loads.
class _CategoryChipsLoading extends StatelessWidget {
  const _CategoryChipsLoading();

  @override
  Widget build(BuildContext context) {
    return const Row(
      key: Key('category-chips-loading'),
      children: <Widget>[
        NeumorphicInset(
          radius: VelvetRadii.pill,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: VelvetSpacing.lg,
              vertical: VelvetSpacing.md,
            ),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: BrandColors.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact error state for the category chip row — an error line plus a retry
/// chip. The rest of the form stays usable because the category is optional.
class _CategoryChipsError extends StatelessWidget {
  const _CategoryChipsError({
    required this.l10n,
    required this.onRetry,
    this.disabled = false,
  });

  final AppLocalizations l10n;
  final VoidCallback onRetry;
  final bool disabled;

  static final TextStyle _errorStyle = VelvetText.feedback(
    const Color(0xFFB0452F), // BrandColors.error
  );
  static final TextStyle _retryStyle = VelvetText.pill();

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('category-chips-error'),
      children: <Widget>[
        const Icon(
          Icons.error_outline_rounded,
          size: 15,
          color: Color(0xFFB0452F), // BrandColors.error
        ),
        const SizedBox(width: VelvetSpacing.xs + 2),
        Expanded(
          child: Text(l10n.serviceCategoryLoadError, style: _errorStyle),
        ),
        const SizedBox(width: VelvetSpacing.sm),
        GestureDetector(
          key: const Key('btn-category-retry'),
          onTap: disabled ? null : onRetry,
          child: Semantics(
            button: true,
            label: l10n.serviceCategoryRetry,
            child: NeumorphicInset(
              radius: VelvetRadii.pill,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: VelvetSpacing.md,
                  vertical: VelvetSpacing.sm,
                ),
                child: Text(l10n.serviceCategoryRetry, style: _retryStyle),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A dashed-feel "suggest a category" chip rendered after the category list.
///
/// Reuses the unselected-chip neumorphic inset look with a leading "+" so it
/// reads as an additive affordance rather than a selectable category.
class _SuggestCategoryChip extends StatelessWidget {
  const _SuggestCategoryChip({
    super.key,
    required this.label,
    required this.onTap,
    this.disabled = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool disabled;

  static final TextStyle _labelStyle = VelvetText.pill();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Semantics(
        button: true,
        label: label,
        child: NeumorphicInset(
          radius: VelvetRadii.pill,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.md,
              vertical: VelvetSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.add_rounded,
                  size: 15,
                  color: BrandColors.accentDeep,
                ),
                const SizedBox(width: VelvetSpacing.xs),
                Text(label, style: _labelStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single neumorphic category chip.
///
/// **Unselected:** inset pill — [NeumorphicInset] with [VelvetText.pill()] in
/// [BrandColors.accentDeep] color.
/// **Selected:** extruded pill — camel/mocha gradient fill (identical to the
/// CTA gradient), white label, leading check icon, [VelvetShadows.extrudedButtonAccent].
///
/// [AnimatedContainer] provides the 150 ms cross-fade between states.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    super.key,
    required this.wire,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.disabled = false,
  });

  final String wire;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool disabled;

  // ---------------------------------------------------------------------------
  // Hoisted style constants — zero allocation per frame.
  // ---------------------------------------------------------------------------

  // Pill border radius (VelvetRadii.pill = 999) — a static const so the
  // BorderRadius is computed once at compile time.
  static const BorderRadius _pillRadius = BorderRadius.all(
    Radius.circular(VelvetRadii.pill),
  );

  // Selected chip: white label (BrandColors.white = #F5EDE0).
  static final TextStyle _selectedLabel = VelvetText.pill().copyWith(
    color: BrandColors.white,
  );

  // Unselected chip: default pill style (accentDeep, no copyWith needed).
  static final TextStyle _unselectedLabel = VelvetText.pill();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: isSelected
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
          child: isSelected
              ? _SelectedPillContent(label: label, labelStyle: _selectedLabel)
              : _UnselectedPillContent(
                  label: label,
                  labelStyle: _unselectedLabel,
                ),
        ),
      ),
    );
  }
}

/// Content inside a selected chip (gradient background + check + label).
class _SelectedPillContent extends StatelessWidget {
  const _SelectedPillContent({required this.label, required this.labelStyle});

  final String label;
  final TextStyle labelStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md,
        vertical: VelvetSpacing.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.check_rounded, size: 14, color: BrandColors.white),
          const SizedBox(width: VelvetSpacing.xs),
          Text(label, style: labelStyle),
        ],
      ),
    );
  }
}

/// Content inside an unselected chip (inset neumorphic well + label).
class _UnselectedPillContent extends StatelessWidget {
  const _UnselectedPillContent({required this.label, required this.labelStyle});

  final String label;
  final TextStyle labelStyle;

  @override
  Widget build(BuildContext context) {
    return NeumorphicInset(
      radius: VelvetRadii.pill,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.md,
          vertical: VelvetSpacing.sm,
        ),
        child: Text(label, style: labelStyle),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private field widget
//
// Extracted to avoid nesting a StatefulWidget (FocusNode listener) directly
// inside the _ServiceFormState build method, which would create a new instance
// on every build. By lifting it to a named private class, the element tree is
// stable and Flutter correctly reconciles focus state.
// ---------------------------------------------------------------------------

class _VelvetFieldRow extends StatefulWidget {
  const _VelvetFieldRow({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.errorText,
    required this.labelStyle,
    required this.feedbackErrorStyle,
    this.hintText,
    this.suffixText,
    this.keyboardType,
    this.inputFormatters,
    this.enabled = true,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final String? errorText;
  final String? hintText;
  final String? suffixText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;

  // Passed from parent to reuse the single cached static instances.
  final TextStyle labelStyle;
  final TextStyle feedbackErrorStyle;

  @override
  State<_VelvetFieldRow> createState() => _VelvetFieldRowState();
}

class _VelvetFieldRowState extends State<_VelvetFieldRow> {
  // Hoisted to avoid per-build TextStyle allocations.
  static final TextStyle _inputStyle = VelvetText.input();
  static final TextStyle _hintStyle = VelvetText.input().copyWith(
    color: const Color(0xFFAD9A82), // BrandColors.placeholder
  );
  static final TextStyle _suffixStyle = VelvetText.input().copyWith(
    color: const Color(0xFF9A8367), // BrandColors.muted
    fontWeight: FontWeight.w700,
  );

  late final FocusNode _focus;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode()
      ..addListener(() {
        if (_focus.hasFocus != _focused && mounted) {
          setState(() => _focused = _focus.hasFocus);
        }
      });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasError = widget.errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Label row.
        Padding(
          padding: const EdgeInsets.only(
            left: VelvetSpacing.xs,
            bottom: VelvetSpacing.sm,
          ),
          child: Text(widget.label.toUpperCase(), style: widget.labelStyle),
        ),

        // Inset well with focus ring.
        NeumorphicInset(
          key: widget.fieldKey,
          focused: _focused,
          hasError: hasError,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.md,
              vertical: VelvetSpacing.sm + 2,
            ),
            child: SizedBox(
              height: VelvetSizes.field - 2 * (VelvetSpacing.sm + 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focus,
                      enabled: widget.enabled,
                      keyboardType: widget.keyboardType ?? TextInputType.text,
                      inputFormatters: widget.inputFormatters,
                      style: _inputStyle,
                      cursorColor: const Color(
                        0xFFB89A7A,
                      ), // BrandColors.accent
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: widget.hintText,
                        hintStyle: _hintStyle,
                      ),
                    ),
                  ),
                  if (widget.suffixText != null) ...<Widget>[
                    const SizedBox(width: VelvetSpacing.sm),
                    Text(widget.suffixText!, style: _suffixStyle),
                  ],
                ],
              ),
            ),
          ),
        ),

        // Inline error row.
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(
              left: VelvetSpacing.xs,
              right: VelvetSpacing.xs,
              top: VelvetSpacing.sm - 2,
            ),
            child: Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 15,
                    color: Color(0xFFB0452F), // BrandColors.error
                  ),
                  const SizedBox(width: VelvetSpacing.xs + 2),
                  Expanded(
                    child: Text(
                      widget.errorText!,
                      style: widget.feedbackErrorStyle,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
