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
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/category_request_dialog.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/pricing_field.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/searchable_select_field.dart';
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

  /// Pre-fill rule for the service name when a service type is selected
  /// (Phase 16.3). Pure helper — given the current name text and the value this
  /// form last auto-filled, decide whether the chosen type's `nameUk` may
  /// overwrite the name.
  ///
  /// The name is overwritten ONLY when it is empty (after trim) OR still equals
  /// the value this form last auto-filled — i.e. the user has not hand-edited
  /// it. This keeps a user-edited name from being clobbered when the master
  /// changes the selected type. Lives on the public widget (not the private
  /// State) so the rule is unit-testable in isolation from the widget tree.
  @visibleForTesting
  static bool shouldPrefillName({
    required String currentName,
    required String? lastAutoFilledName,
  }) {
    if (currentName.trim().isEmpty) return true;
    return lastAutoFilledName != null && currentName == lastAutoFilledName;
  }

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

  /// True only while [onServiceTypeSelected] is programmatically writing the
  /// auto-filled name into [_nameCtrl] (Phase 16.3). The name controller's
  /// listener checks this so it does NOT treat the auto-fill as a manual edit
  /// (which would immediately reset [_lastAutoFilledName] and defeat the
  /// don't-clobber tracking).
  bool _applyingAutoFill = false;

  /// Bumped on every keystroke that can change a field's inline error text
  /// (live re-validation after the first submit, or a cleared server error).
  /// Only the per-field error sub-trees listen to this — `_CategoryDropdown`
  /// (which reads [approvedCategoriesProvider]) stays outside its scope, so
  /// typing in a price/name field never rebuilds the dropdown. Replaces the
  /// old form-wide `setState(() {})` (perf MEDIUM).
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

  /// Currently selected platform service-type id (Phase 16.3). Null = the
  /// master has not chosen a service type (the picker is optional). Submitted
  /// as [MasterServiceCreate.serviceTypeId]; a null value sends no type.
  ///
  /// The picker UI that drives this lives in Phase 16.4 — it calls
  /// [onServiceTypeSelected] / [clearServiceType]; this phase only wires the
  /// behavior.
  String? _selectedServiceTypeId;

  /// The exact name string this form last auto-filled from a selected service
  /// type's `nameUk` (Phase 16.3). Used to detect whether the user has since
  /// hand-edited the name: pre-fill is only allowed to overwrite the name when
  /// it is still empty OR still equals this value. Reset to null whenever the
  /// user edits the name themselves, so a manual edit is never clobbered.
  String? _lastAutoFilledName;

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
    _nameCtrl.addListener(_onNameChanged);
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
    // sub-trees recompute. Never calls setState, so `_CategoryDropdown` and the
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

  /// Drops a stale server-side error keyed by backend wire [field] from
  /// [_serverFieldErrors], if present. Must be called inside a [setState] (or a
  /// frame that otherwise rebuilds) — it only mutates the map. Used by the
  /// service-type handlers, which have no [TextEditingController] to hang an
  /// edit-clears-error listener on.
  void _clearServerError(String field) {
    if (!_serverFieldErrors.containsKey(field)) return;
    _serverFieldErrors = Map<String, String>.unmodifiable(
      Map<String, String>.from(_serverFieldErrors)..remove(field),
    );
  }

  /// Inline error for the service type, sourced solely from the backend
  /// cross-field validation (Phase 16.3 — e.g. the chosen type does not belong
  /// to the selected category). There is no client-side validator because the
  /// service type is optional; the error is purely the mapped-back
  /// `serviceTypeId` server message. Null when there is none.
  String? _serviceTypeError() => _serverFieldErrors['serviceTypeId'];

  /// Name-controller listener. Behaves exactly like `_onChanged('name')` for
  /// re-validation / dirty tracking, but additionally resets
  /// [_lastAutoFilledName] when the change is a genuine *user* edit (i.e. not
  /// the programmatic write performed by [onServiceTypeSelected]). Once the
  /// user hand-edits the name, the next service-type selection must not
  /// overwrite it.
  void _onNameChanged() {
    if (!_applyingAutoFill && _lastAutoFilledName != null) {
      _lastAutoFilledName = null;
    }
    _onChanged('name');
  }

  /// Called by the Phase 16.4 picker when the master selects a service type.
  ///
  /// Sets [_selectedServiceTypeId] to [option.id] and pre-fills the name field
  /// with [option.nameUk] — but only when [shouldPrefillName] allows it, so a
  /// name the user typed by hand is never overwritten. When the name is
  /// auto-filled, [_lastAutoFilledName] is updated so a *subsequent* selection
  /// is still allowed to replace this auto-filled value (but a manual edit in
  /// between resets it and locks the name).
  void onServiceTypeSelected(ServiceTypeOption option) {
    if (!mounted) return;
    final bool prefill = ServiceForm.shouldPrefillName(
      currentName: _nameCtrl.text,
      lastAutoFilledName: _lastAutoFilledName,
    );
    setState(() {
      _selectedServiceTypeId = option.id;
      _clearServerError('serviceTypeId');
      if (prefill) {
        // Guard the programmatic write so the name listener does not mistake
        // the auto-fill for a manual edit.
        _applyingAutoFill = true;
        _nameCtrl.text = option.nameUk;
        _applyingAutoFill = false;
        _lastAutoFilledName = option.nameUk;
      }
    });
    // Re-evaluate dirty state (name and/or type may have changed).
    _wasDirty = _isDirty;
    _dirtyNotifier.value = _wasDirty;
  }

  /// Called by the Phase 16.4 picker when the master clears the service-type
  /// selection. Nulls [_selectedServiceTypeId] so the create payload submits
  /// `serviceTypeId = null`. The name is intentionally left as-is (clearing a
  /// type never edits the name), though future auto-fills are again permitted
  /// when the name still matches the last auto-filled value.
  void clearServiceType() {
    if (!mounted) return;
    setState(() {
      _selectedServiceTypeId = null;
      _clearServerError('serviceTypeId');
    });
    _wasDirty = _isDirty;
    _dirtyNotifier.value = _wasDirty;
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
            // Optional service type (Phase 16.3); null when none selected.
            serviceTypeId: _selectedServiceTypeId,
          );
        case ServicePriceType.range:
          input = MasterServiceCreate(
            name: _nameCtrl.text.trim(),
            durationMinutes: int.parse(_durationCtrl.text.trim()),
            priceType: ServicePriceType.range,
            priceMin: parsePrice(_priceMinCtrl.text),
            priceMax: parsePrice(_priceMaxCtrl.text),
            category: _selectedCategory,
            // Optional service type (Phase 16.3); null when none selected.
            serviceTypeId: _selectedServiceTypeId,
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
      'serviceTypeId',
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
        // inline error — `_CategoryDropdown` stays out of the rebuild (perf MEDIUM).
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

        // 1b — Category searchable dropdown (required; reuses
        //      [SearchableSelectField]). Options sourced from the approved-
        //      category provider (Ukrainian labels); the selected wire slug is
        //      routed back via [onSelect]. Selecting a category clears any
        //      previously-selected service type below.
        _CategoryDropdown(
          selected: _selectedCategory,
          disabled: _submitting,
          label: l10n.serviceCategoryLabel,
          errorText: _categoryError(l10n),
          onSelect: (String? wire) {
            setState(() {
              _selectedCategory = wire;
            });
            // Category changed: a service-type selected under the previous
            // category is no longer compatible (the type belongs to one
            // category). Drop it through the existing 16.3 handler so there is
            // a single clear code path — the stale selection and any mapped-back
            // serviceTypeId error don't linger into the new category's picker
            // (16.4 basic clear-on-change; deeper edit-flow hardening is 16.5).
            // The name controller is intentionally untouched (16.3 don't-clobber
            // rule governs the name; only the type selection is cleared here).
            clearServiceType();
          },
        ),

        // 1c — Second-level service-type searchable dropdown (Phase 16.6). Shown
        //      only when a category is selected; reuses [SearchableSelectField]
        //      over `serviceTypesProvider(category)`. Selection drives the
        //      existing 16.3 handler (`onServiceTypeSelected`) so there is a
        //      single source of truth for `_selectedServiceTypeId`; clearing is
        //      handled on category change (above) via `clearServiceType()`.
        //      A slow/failed type lookup degrades to a retryable error inside
        //      the dropdown (field affordance + menu retry) — never an infinite
        //      spinner. The mapped-back `serviceTypeId` cross-field error (16.3)
        //      renders beneath via [_ServiceTypeError]; ONLY that inline error
        //      subtree rebuilds on a revalidate tick so a backend mismatch is
        //      never swallowed.
        if (_selectedCategory != null &&
            _selectedCategory!.isNotEmpty) ...<Widget>[
          const SizedBox(height: VelvetSpacing.lg),
          _ServiceTypeDropdown(
            categoryName: _selectedCategory!,
            selectedId: _selectedServiceTypeId,
            disabled: _submitting,
            label: l10n.serviceTypeLabel,
            onSelect: onServiceTypeSelected,
          ),
          ValueListenableBuilder<int>(
            valueListenable: _revalidateTick,
            builder: (BuildContext context, _, _) =>
                _ServiceTypeError(errorText: _serviceTypeError()),
          ),
        ],
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
// Service-type searchable dropdown (Phase 16.6)
//
// The second-level picker: reuses [SearchableSelectField] over
// `serviceTypesProvider(categoryName)` (the service types under the currently-
// selected platform category). Single-select, optional. The parent form is
// shown this only when a category is selected, so [categoryName] is non-empty.
//
// This widget owns NO selection state: it reflects [selectedId] from the form
// and routes the chosen [ServiceTypeOption] back through [onSelect], which
// drives the form's existing 16.3 handler. Single source of truth lives on the
// form (clearing on category change is handled there via `clearServiceType()`).
//
// Robust load states (the spinner fix): the provider's async value maps to a
// [SelectFieldState]; a slow/failed lookup shows the field's loading/error
// affordance and, when opened, an ESCAPABLE menu spinner or a Retry state that
// `ref.invalidate(serviceTypesProvider(categoryName))`. The empty case (a
// category with no types) resolves to data → the menu shows the calm empty
// hint. A hang/failure therefore never strands the user on an infinite spinner.
// ---------------------------------------------------------------------------

/// A labelled searchable single-select dropdown of service types.
///
/// Options are sourced from [serviceTypesProvider] for [categoryName] — each
/// option's [ServiceTypeOption.nameUk] is the searchable display label while
/// [ServiceTypeOption.id] is the value. The chosen [ServiceTypeOption] is passed
/// back to [onSelect] (so the form can pre-fill the name and persist the id).
/// [selectedId] is the currently-selected service-type id, or null.
///
/// [disabled] suppresses opening the menu while a submit is in-flight.
class _ServiceTypeDropdown extends ConsumerWidget {
  const _ServiceTypeDropdown({
    required this.categoryName,
    required this.selectedId,
    required this.label,
    required this.onSelect,
    this.disabled = false,
  });

  final String categoryName;
  final String? selectedId;
  final String label;
  final ValueChanged<ServiceTypeOption> onSelect;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final typesAsync = ref.watch(serviceTypesProvider(categoryName));

    final List<ServiceTypeOption> options =
        typesAsync.value ?? const <ServiceTypeOption>[];

    // Resolve the selected option's label for the closed field. The selection
    // lives on the form; if the option list hasn't loaded yet but a selection
    // is held (edit flow), fall back to a null label until it resolves.
    String? selectedLabel;
    for (final ServiceTypeOption o in options) {
      if (o.id == selectedId) {
        selectedLabel = o.nameUk;
        break;
      }
    }

    final SelectFieldState fieldState = typesAsync.when(
      data: (_) => SelectFieldState.idle,
      loading: () => SelectFieldState.loading,
      error: (_, _) => SelectFieldState.error,
    );

    // Empty category → an empty option list with idle state; the menu surfaces
    // the calm `serviceTypeEmpty` hint via [emptyLabel].
    return SearchableSelectField<ServiceTypeOption>(
      key: const Key('select-service-type-field-wrapper'),
      fieldKey: const Key('select-service-type-field'),
      label: label,
      menuTitle: l10n.serviceTypeMenuTitle,
      placeholder: l10n.serviceTypePlaceholder,
      searchHint: l10n.serviceSelectSearchHint,
      emptyLabel: l10n.serviceTypeEmpty,
      errorLabel: l10n.serviceTypeLoadError,
      retryLabel: l10n.serviceSelectRetry,
      loadingLabel: l10n.serviceTypeLoading,
      selectedLabel: selectedLabel,
      fieldState: fieldState,
      enabled: !disabled,
      options: <SelectOption<ServiceTypeOption>>[
        for (final ServiceTypeOption o in options)
          SelectOption<ServiceTypeOption>(
            value: o,
            label: o.nameUk,
            rowKey: Key('chip-service-type-${o.id}'),
          ),
      ],
      onSelected: onSelect,
      onMenuRetry: () => ref.invalidate(serviceTypesProvider(categoryName)),
    );
  }
}

// ---------------------------------------------------------------------------
// Service-type inline error
//
// The mapped-back `serviceTypeId` cross-field error (Phase 16.3) — e.g. the
// chosen type does not belong to the selected category. Rendered as a separate
// leaf so the parent can wrap ONLY this subtree in the `_revalidateTick`
// listener: a revalidate tick reflows the error without rebuilding the pill
// `Wrap` above or re-watching `serviceTypesProvider` (perf HIGH).
// ---------------------------------------------------------------------------

class _ServiceTypeError extends StatelessWidget {
  const _ServiceTypeError({required this.errorText});

  /// The backend-mapped error message, or null when there is none. There is no
  /// client-side validator (the service type is optional).
  final String? errorText;

  // Error style — hoisted; matches the field/category feedback style.
  static final TextStyle _errorStyle = VelvetText.feedback(
    const Color(0xFFB0452F), // BrandColors.error
  );

  @override
  Widget build(BuildContext context) {
    final String? message = errorText;
    if (message == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(
        left: VelvetSpacing.xs,
        right: VelvetSpacing.xs,
        top: VelvetSpacing.sm,
      ),
      child: Semantics(
        liveRegion: true,
        child: Row(
          key: const Key('error-service-type'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(
              Icons.error_outline_rounded,
              size: 15,
              color: Color(0xFFB0452F), // BrandColors.error
            ),
            const SizedBox(width: VelvetSpacing.xs + 2),
            Expanded(child: Text(message, style: _errorStyle)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category searchable dropdown (Phase 16.6)
//
// Replaces the chip wrap with a [SearchableSelectField] over
// `approvedCategoriesProvider`. Options render the Ukrainian
// [ServiceCategoryOption.displayName]; the wire [ServiceCategoryOption.name]
// slug is routed back via [onSelect] (preserving the existing wire-name
// contract). The required-field error renders inline beneath the field.
//
// The "suggest a category" affordance moves into the menu footer
// ("Не знайшли? Запропонувати категорію") → [showCategoryRequestDialog].
//
// The deprecated/absent-category guard (`_withSelected` + humanize) is kept so
// a persisted selection whose slug is no longer in the approved list still
// shows a readable label in the closed field.
// ---------------------------------------------------------------------------

/// A labelled searchable single-select dropdown of approved categories.
///
/// Options are sourced from [approvedCategoriesProvider] — each option renders
/// the Ukrainian [ServiceCategoryOption.displayName] as its searchable label
/// while the [ServiceCategoryOption.name] wire slug is the value sent to
/// [onSelect].
///
/// [selected] is the currently-selected wire name, or null for none.
/// [onSelect] is called with the chosen wire name.
/// [disabled] suppresses opening the menu when a submit is in-flight.
class _CategoryDropdown extends ConsumerWidget {
  const _CategoryDropdown({
    required this.selected,
    required this.label,
    required this.onSelect,
    this.errorText,
    this.disabled = false,
  });

  final String? selected;
  final String label;
  final ValueChanged<String?> onSelect;

  /// Required-field error surfaced beneath the field after a submit attempt
  /// with no category selected. Null when there is no error.
  final String? errorText;
  final bool disabled;

  Future<void> _openSuggestDialog(
    BuildContext sheetContext,
    BuildContext rootContext,
  ) async {
    final l10n = AppLocalizations.of(rootContext);
    // Close the menu first so the dialog is the top surface, then open it on
    // the root context (the sheet context is torn down by the pop).
    Navigator.of(sheetContext).pop();
    final submitted = await showCategoryRequestDialog(rootContext);
    if (submitted == true && rootContext.mounted) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        SnackBar(
          content: Text(l10n.categoryRequestSuccess),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// The selected option's display label for the closed field. Resolves the
  /// Ukrainian displayName from [options]; when the persisted [selected] slug is
  /// absent from the approved list (deactivated/retired, or a transient empty
  /// list while the backend is slow), humanizes the slug instead of leaking the
  /// raw ALL-CAPS value.
  String? _selectedLabel(List<ServiceCategoryOption> options) {
    final String? sel = selected;
    if (sel == null || sel.isEmpty) return null;
    for (final ServiceCategoryOption o in options) {
      if (categorySlugMatches(sel, o.name)) return o.displayName;
    }
    return humanizeCategorySlug(sel);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final categoriesAsync = ref.watch(approvedCategoriesProvider);

    final List<ServiceCategoryOption> options =
        categoriesAsync.value ?? const <ServiceCategoryOption>[];

    final SelectFieldState fieldState = categoriesAsync.when(
      data: (_) => SelectFieldState.idle,
      loading: () => SelectFieldState.loading,
      error: (_, _) => SelectFieldState.error,
    );

    return SearchableSelectField<String>(
      key: const Key('select-category-field-wrapper'),
      fieldKey: const Key('select-category-field'),
      label: label,
      menuTitle: l10n.serviceCategoryMenuTitle,
      placeholder: l10n.serviceCategoryPlaceholder,
      searchHint: l10n.serviceSelectSearchHint,
      emptyLabel: l10n.serviceSelectSearchEmpty,
      errorLabel: l10n.serviceCategoryLoadError,
      retryLabel: l10n.serviceSelectRetry,
      selectedLabel: _selectedLabel(options),
      fieldState: fieldState,
      errorText: errorText,
      enabled: !disabled,
      options: <SelectOption<String>>[
        for (final ServiceCategoryOption o in options)
          SelectOption<String>(
            value: o.name,
            label: o.displayName,
            rowKey: Key('chip-category-${o.name}'),
          ),
      ],
      onSelected: onSelect,
      onMenuRetry: () => ref.invalidate(approvedCategoriesProvider),
      menuFooter: (BuildContext sheetContext) => SelectMenuActionRow(
        key: const Key('chip-category-suggest'),
        label: l10n.serviceCategorySuggest,
        onTap: disabled
            ? () {}
            : () => _openSuggestDialog(sheetContext, context),
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
