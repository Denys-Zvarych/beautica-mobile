// Phase 21.10 — SalonProfileEditScreen («Назва та опис»).
//
// One of the three lightweight edit-form screens reached from the Phase 21.9
// settings hub (unbuilt — this screen has no in-app entry point yet, per this
// phase's own scope note). Edits ONLY the salon's name + description.
//
// REUSE-FIRST: no new save path. Calls the EXISTING
// [SalonManagementProfile.save] (Phase 21.2) — the same method the inline
// «Про салон» edit form on [SalonManagementProfileScreen] already uses —
// passing the CURRENT loaded phone/instagramUrl back in unchanged so that
// method's own per-field dirty-diff naturally omits them from the PATCH body.
// This avoids a duplicate fetch-and-diff notifier for a slice `save()`
// already fully covers.
//
// Design source: `docs/signup-designs/SalonManagementDesign/lib/screens/
// salon_profile_edit_screen.dart` — ported onto production's `SectionScaffold`
// + `VelvetField` (the preview's own `_FormScaffold`/`NeumorphicTextField`/
// `MultilineField` are preview-only stand-ins, not ported). Name/description
// maxLengths use the BACKEND `UpdateSalonRequest` caps (255 / 2000 — see
// `tool/openapi/api-spec.json`) and the already-shipped
// `_AboutEditForm` constants in `salon_management_profile_screen.dart`, not
// the preview's own placeholder caps (120 / no live counter) or the phase
// doc's stale "100 / 500" figures.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/velvet_field.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/validators/salon_name_validator.dart';

import '../../master/presentation/widgets/section_scaffold.dart';
import '../application/salon_management_profile_notifier.dart';
import '../domain/salon.dart';

// Backend UpdateSalonRequest caps (tool/openapi/api-spec.json), matching the
// constants already shipped in `salon_management_profile_screen.dart`.
const int _kNameMaxLength = 255;
const int _kDescriptionMaxLength = 2000;

/// Dedicated «Назва та опис» edit screen for [salonId].
class SalonProfileEditScreen extends ConsumerStatefulWidget {
  const SalonProfileEditScreen({super.key, required this.salonId});

  /// Backend Salon-row UUID this screen edits.
  final String salonId;

  @override
  ConsumerState<SalonProfileEditScreen> createState() =>
      _SalonProfileEditScreenState();
}

class _SalonProfileEditScreenState
    extends ConsumerState<SalonProfileEditScreen> {
  bool _initialized = false;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;

  bool _saving = false;
  String? _errName;

  void _initControllers(Salon salon) {
    if (_initialized) return;
    _initialized = true;
    _nameCtrl = TextEditingController(text: salon.name);
    _descCtrl = TextEditingController(text: salon.description ?? '');
  }

  @override
  void dispose() {
    if (_initialized) {
      _nameCtrl.dispose();
      _descCtrl.dispose();
    }
    super.dispose();
  }

  void _onNameChanged(String v) {
    final l10n = AppLocalizations.of(context);
    final next = validateSalonName(v, l10n);
    if (next != _errName) setState(() => _errName = next);
  }

  Future<void> _save(Salon current) async {
    final l10n = AppLocalizations.of(context);
    final String? nameErr = validateSalonName(_nameCtrl.text, l10n);
    if (nameErr != null) {
      setState(() => _errName = nameErr);
      showErrorSnack(context, l10n.editValidationSummary);
      return;
    }

    setState(() => _saving = true);
    final Failure? failure = await ref
        .read(salonManagementProfileProvider(widget.salonId).notifier)
        .save(
          name: _nameCtrl.text,
          description: _descCtrl.text,
          // Unchanged — thread the CURRENT values back so save()'s own
          // dirty-diff omits them from the PATCH body (see file header doc).
          phone: current.phone ?? '',
          instagramUrl: current.instagramUrl ?? '',
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (failure != null) {
      showErrorSnack(context, failure.userMessage(context));
      return;
    }
    showSuccessSnack(context, l10n.savedSnackbar);
    context.pop();
  }

  void _onBack() {
    if (context.canPop()) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<SalonManagementProfileData> async = ref.watch(
      salonManagementProfileProvider(widget.salonId),
    );

    final SalonManagementProfileData? data = async.value;
    if (data == null) {
      return const Scaffold(
        backgroundColor: BrandColors.base,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final (Salon salon, _) = data;
    _initControllers(salon);

    return SectionScaffold(
      title: l10n.salonProfileEditTitle,
      backSemanticLabel: l10n.salonProfileBackLabel,
      onBack: _onBack,
      footer: NeumorphicButton(
        key: const Key('save_salon_profile'),
        label: l10n.masterSaveButton,
        icon: Icons.check_rounded,
        loading: _saving,
        onPressed: _saving ? null : () => _save(salon),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.lg),
            child: Text(
              l10n.salonProfileEditSubheading,
              style: VelvetText.body(),
            ),
          ),
          VelvetField(
            fieldKey: const Key('salon_name'),
            label: l10n.salonManageNameLabel,
            controller: _nameCtrl,
            enabled: !_saving,
            maxLength: _kNameMaxLength,
            errorText: _errName,
            onChanged: _onNameChanged,
          ),
          const SizedBox(height: VelvetSpacing.lg),
          VelvetField(
            fieldKey: const Key('salon_description'),
            label: l10n.salonManageDescriptionLabel,
            controller: _descCtrl,
            enabled: !_saving,
            maxLines: 4,
            maxLength: _kDescriptionMaxLength,
            showCounter: true,
            optional: true,
          ),
        ],
      ),
    );
  }
}
