// Phase 21.10 — SalonContactsEditScreen («Контакти»).
//
// One of the three lightweight edit-form screens reached from the Phase 21.9
// settings hub (unbuilt — this screen has no in-app entry point yet, per this
// phase's own scope note). Edits ONLY phone + Instagram.
//
// REUSE-FIRST: no new save path. Calls the EXISTING
// [SalonManagementProfile.save] (Phase 21.2) — the same method the inline
// «Про салон» edit form on [SalonManagementProfileScreen] already uses —
// passing the CURRENT loaded name/description back in unchanged so that
// method's own per-field dirty-diff naturally omits them from the PATCH body.
//
// The salon phone is a PUBLIC contact (shown to clients), unlike a personal
// phone number — no privacy helper note, unlike `ContactsEditScreen`
// (`features/master/presentation/`). Phone mask reuses [UaPhoneInputFormatter]
// verbatim (the design source's locked "+380 __ ___ __ __" mask).
//
// Design source: `docs/signup-designs/SalonManagementDesign/lib/screens/
// salon_contacts_edit_screen.dart` — ported onto production's
// `SectionScaffold` + `VelvetField` + `UaPhoneInputFormatter`.

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
import 'package:beautica_mobile/shared/formatters/ua_phone_input_formatter.dart';

import '../../master/presentation/widgets/section_scaffold.dart';
import '../application/salon_management_profile_notifier.dart';
import '../domain/salon.dart';

// Mirrors UpdateSalonRequest.phone's backend @Pattern / @Size(max = 20).
const int _kPhoneMaxLength = 20;
final RegExp _kPhoneAllowedChars = RegExp(r'^[+\d\s\-()/]*$');
// Mirrors UpdateSalonRequest.instagramUrl's backend @Pattern — a bare/`@`
// handle, or a full instagram.com URL.
final RegExp _kInstagramHandle = RegExp(r'^@?[A-Za-z0-9._]{1,30}$');
final RegExp _kInstagramUrlPattern = RegExp(
  r'^https://(www\.)?instagram\.com/[A-Za-z0-9._]+/?$',
);
const int _kInstagramMaxLength = 500;

/// Dedicated «Контакти» edit screen for [salonId].
class SalonContactsEditScreen extends ConsumerStatefulWidget {
  const SalonContactsEditScreen({super.key, required this.salonId});

  /// Backend Salon-row UUID this screen edits.
  final String salonId;

  @override
  ConsumerState<SalonContactsEditScreen> createState() =>
      _SalonContactsEditScreenState();
}

class _SalonContactsEditScreenState
    extends ConsumerState<SalonContactsEditScreen> {
  bool _initialized = false;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _instagramCtrl;

  bool _saving = false;
  String? _errPhone;
  String? _errInstagram;

  void _initControllers(Salon salon) {
    if (_initialized) return;
    _initialized = true;
    // Phase 21.2 gap: `GET /salons/{salonId}` never returns `phone` — see
    // `Salon.phone`'s doc — so this field seeds empty even for a salon with a
    // real phone on file, exactly like the inline «Про салон» edit form.
    _phoneCtrl = TextEditingController(text: salon.phone ?? '');
    _instagramCtrl = TextEditingController(text: salon.instagramUrl ?? '');
  }

  @override
  void dispose() {
    if (_initialized) {
      _phoneCtrl.dispose();
      _instagramCtrl.dispose();
    }
    super.dispose();
  }

  String? _validatePhone(String v, AppLocalizations l10n) {
    if (v.trim().isEmpty) return l10n.errPhoneRequired;
    if (v.trim().length > _kPhoneMaxLength) return l10n.errPhoneTooLongEdit;
    if (!_kPhoneAllowedChars.hasMatch(v.trim())) {
      return l10n.errPhoneInvalidEdit;
    }
    return null;
  }

  String? _validateInstagram(String v, AppLocalizations l10n) {
    if (v.trim().isEmpty) return null; // optional
    if (!_kInstagramHandle.hasMatch(v.trim()) &&
        !_kInstagramUrlPattern.hasMatch(v.trim())) {
      return l10n.masterEditInstagramError;
    }
    return null;
  }

  void _onPhoneChanged(String v) {
    final next = _validatePhone(v, AppLocalizations.of(context));
    if (next != _errPhone) setState(() => _errPhone = next);
  }

  void _onInstagramChanged(String v) {
    final next = _validateInstagram(v, AppLocalizations.of(context));
    if (next != _errInstagram) setState(() => _errInstagram = next);
  }

  Future<void> _save(Salon current) async {
    final l10n = AppLocalizations.of(context);
    final String? phoneErr = _validatePhone(_phoneCtrl.text, l10n);
    final String? instagramErr = _validateInstagram(_instagramCtrl.text, l10n);
    if (phoneErr != null || instagramErr != null) {
      setState(() {
        _errPhone = phoneErr;
        _errInstagram = instagramErr;
      });
      showErrorSnack(context, l10n.editValidationSummary);
      return;
    }

    setState(() => _saving = true);
    final Failure? failure = await ref
        .read(salonManagementProfileProvider(widget.salonId).notifier)
        .save(
          // Unchanged — thread the CURRENT values back so save()'s own
          // dirty-diff omits them from the PATCH body (see file header doc).
          name: current.name,
          description: current.description ?? '',
          phone: _phoneCtrl.text,
          instagramUrl: _instagramCtrl.text,
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
      title: l10n.contactsTitle,
      backSemanticLabel: l10n.salonProfileBackLabel,
      onBack: _onBack,
      footer: NeumorphicButton(
        key: const Key('save_salon_contacts'),
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
              l10n.salonContactsEditSubheading,
              style: VelvetText.body(),
            ),
          ),
          VelvetField(
            fieldKey: const Key('salon_phone'),
            label: l10n.phoneLabel,
            controller: _phoneCtrl,
            enabled: !_saving,
            keyboardType: TextInputType.phone,
            inputFormatters: const <UaPhoneInputFormatter>[
              UaPhoneInputFormatter(),
            ],
            hint: '+380 __ ___ __ __',
            errorText: _errPhone,
            onChanged: _onPhoneChanged,
          ),
          const SizedBox(height: VelvetSpacing.lg),
          VelvetField(
            fieldKey: const Key('salon_instagram'),
            label: l10n.instagramLabel,
            controller: _instagramCtrl,
            enabled: !_saving,
            optional: true,
            prefixText: '@',
            hint: l10n.masterEditInstagramHint,
            maxLength: _kInstagramMaxLength,
            errorText: _errInstagram,
            onChanged: _onInstagramChanged,
          ),
        ],
      ),
    );
  }
}
