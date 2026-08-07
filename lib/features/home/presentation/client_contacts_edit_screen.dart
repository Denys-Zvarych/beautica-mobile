// CLIENT Контакти — the contact slice of the client profile: Телефон (required,
// UaPhoneInputFormatter, privacy helper note). A pinned "Зберегти" CTA sits at
// the bottom.
//
// 1:1 transcription of the master [ContactsEditScreen] with ONE approved
// modification: the Instagram field is REMOVED entirely (clients have no
// Instagram). Save merges the phone slice onto the cached profile via
// [ClientProfileRepository.updateMyProfile] (`PATCH /users/me`); the partial-
// update contract means the name + location slices are never sent here, so they
// are preserved server-side, and `instagram` is NEVER sent by the repository.
//
// Save flow: validate → updateMyProfile(phone slice) → invalidate
// clientEditProfileProvider + clientProfileProvider → saved SnackBar → home.
//
// Phone onChanged only setState when the error actually changes (avoids a
// full-card rebuild per keystroke).
//
// Security: ScreenProtector active in release builds (PII-bearing screen).

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
import 'package:beautica_mobile/core/widgets/velvet_field.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/data/client_profile_repository.dart';
import 'package:beautica_mobile/features/home/domain/client_profile_update.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/formatters/ua_phone_input_formatter.dart';

import 'package:beautica_mobile/features/master/presentation/widgets/section_scaffold.dart';

/// CLIENT contacts edit page (phone only — no Instagram).
class ClientContactsEditScreen extends ConsumerStatefulWidget {
  const ClientContactsEditScreen({super.key});

  @override
  ConsumerState<ClientContactsEditScreen> createState() =>
      _ClientContactsEditScreenState();
}

class _ClientContactsEditScreenState
    extends ConsumerState<ClientContactsEditScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _phone;

  bool _initialized = false;

  String _origPhone = '';

  Map<String, String> _fieldErrors = const <String, String>{};
  bool _saving = false;

  String? _errPhone;

  // PERF (P2): drives the Save button's enabled state in isolation so typing
  // does not setState the whole form (and its reveal animation wrappers).
  final ValueNotifier<bool> _dirty = ValueNotifier<bool>(false);

  static const int _phoneMax = 20;

  // Pre-built static RegExp — allocated once, never inside build or validate.
  static final RegExp _phoneAllowedChars = RegExp(r'^[+\d\s\-()]*$');

  // Animation — pre-built in initState; zero allocations in build().
  late final AnimationController _controller;
  late final CurvedAnimation _anim0; // subheading
  late final CurvedAnimation _anim1; // phone
  late final CurvedAnimation _animFooter; // pinned Save

  static final Tween<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  );

  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x rule).
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    _screenProtection = ref.read(screenProtectionProvider)..acquire();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim0 = _curve(0.00, 0.42);
    _anim1 = _curve(0.08, 0.52);
    _animFooter = _curve(0.60, 1.0);
  }

  CurvedAnimation _curve(double start, double end) => CurvedAnimation(
    parent: _controller,
    curve: Interval(start, end, curve: Curves.easeOutCubic),
  );

  void _maybeInit(User user) {
    if (_initialized) return;
    _initialized = true;

    _origPhone = user.phoneNumber ?? '';
    _phone = TextEditingController(text: _origPhone);

    for (final c in _editableControllers) {
      c.addListener(_onFormChanged);
    }

    _controller.forward();
  }

  @override
  void dispose() {
    _screenProtection.release();
    if (_initialized) {
      for (final c in _editableControllers) {
        c.removeListener(_onFormChanged);
        c.dispose();
      }
    }
    _anim0.dispose();
    _anim1.dispose();
    _animFooter.dispose();
    _controller.dispose();
    _dirty.dispose();
    super.dispose();
  }

  List<TextEditingController> get _editableControllers =>
      <TextEditingController>[_phone];

  // PERF (P2): recompute the dirty flag only — no setState, so the form subtree
  // and its animation wrappers are not rebuilt on every keystroke.
  void _onFormChanged() {
    _dirty.value = _isDirty;
  }

  bool get _isDirty => _initialized && (_phone.text.trim() != _origPhone);

  Widget _reveal(CurvedAnimation anim, Widget child) {
    final Animation<Offset> slide = _slideTween.animate(anim);
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(position: slide, child: child),
    );
  }

  void _clearServerError(String fieldName) {
    if (_fieldErrors.containsKey(fieldName)) {
      setState(() {
        _fieldErrors = Map<String, String>.unmodifiable(
          Map<String, String>.from(_fieldErrors)..remove(fieldName),
        );
      });
    }
  }

  String? _validatePhone(String? v) {
    final serverErr = _fieldErrors['phoneNumber'];
    if (serverErr != null) return serverErr;
    if (v == null || v.trim().isEmpty) {
      return AppLocalizations.of(context).errPhoneRequired;
    }
    if (v.trim().length > _phoneMax) {
      return AppLocalizations.of(context).errPhoneTooLongEdit;
    }
    if (!_phoneAllowedChars.hasMatch(v.trim())) {
      return AppLocalizations.of(context).errPhoneInvalidEdit;
    }
    return null;
  }

  bool _validateAndUpdateErrors() {
    final ok = _formKey.currentState!.validate();
    setState(() {
      _errPhone = _validatePhone(_phone.text);
    });
    return ok;
  }

  Future<void> _save() async {
    if (!_initialized) return;
    setState(() {
      _fieldErrors = const <String, String>{};
      _errPhone = null;
    });

    if (!_validateAndUpdateErrors()) {
      if (mounted) {
        showErrorSnack(
          context,
          AppLocalizations.of(context).editValidationSummary,
        );
      }
      return;
    }

    setState(() => _saving = true);

    try {
      // Only the phone slice — name + location are untouched and preserved
      // server-side. The repository never sends `instagram`.
      await ref
          .read(clientProfileRepositoryProvider)
          .updateMyProfile(
            ClientProfileUpdate(phoneNumber: _phone.text.trim()),
          );

      if (!mounted) return;
      // Re-fetch the session User so clientProfile (derived from authProvider)
      // re-derives the fresh phone; then invalidate the edit-seed + profile
      // providers so they re-read from the now-current session.
      await ref.read(authProvider.notifier).refreshUser();
      if (!mounted) return;
      ref.invalidate(clientEditProfileProvider);
      ref.invalidate(clientProfileProvider);
      showSuccessSnack(context, AppLocalizations.of(context).savedSnackbar);
      context.go(RouteNames.clientHome);
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _fieldErrors = Map<String, String>.unmodifiable(f.fieldErrors);
        _saving = false;
      });
      _validateAndUpdateErrors();
      if (f.fieldErrors.isEmpty) {
        // Localized only — the raw backend serverMessage can be
        // untranslated/technical and must not reach this VelvetSnack
        // (mobile-security, 2026-08). f.userMessage() already returns the
        // localized errValidation copy for ValidationFailure.
        showErrorSnack(context, f.userMessage(context));
      }
    } on Failure catch (f) {
      if (!mounted) return;
      showErrorSnack(context, f.userMessage(context));
      setState(() => _saving = false);
    } catch (e, st) {
      if (kDebugMode) {
        log(
          'client contacts save unexpected error',
          name: 'feature.client.edit.contacts',
          level: 1000,
          error: e,
          stackTrace: st,
        );
      }
      if (!mounted) return;
      showErrorSnack(context, AppLocalizations.of(context).errUnknown);
      setState(() => _saving = false);
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final profileAsync = ref.watch(clientEditProfileProvider);
    profileAsync.whenData<void>(_maybeInit);

    final cached = profileAsync.value;
    if (!_initialized || cached == null) {
      return const Scaffold(
        backgroundColor: BrandColors.base,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SectionScaffold(
      title: l10n.contactsTitle,
      backKey: const Key('btn-back-contacts'),
      backSemanticLabel: l10n.masterCancelButton,
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(RouteNames.clientMenu);
        }
      },
      footer: _reveal(
        _animFooter,
        ValueListenableBuilder<bool>(
          valueListenable: _dirty,
          builder: (context, dirty, _) => NeumorphicButton(
            key: const Key('btn-save-contacts'),
            label: l10n.masterSaveButton,
            icon: Icons.check_rounded,
            loading: _saving,
            onPressed: (!_saving && dirty) ? _save : null,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _reveal(
              _anim0,
              Padding(
                padding: const EdgeInsets.only(
                  left: 4,
                  bottom: VelvetSpacing.lg,
                ),
                child: Text(l10n.contactsSubheading, style: VelvetText.body()),
              ),
            ),
            _reveal(
              _anim1,
              FormField<String>(
                key: const Key('field-phone'),
                initialValue: _phone.text,
                validator: (_) => _validatePhone(_phone.text),
                builder: (FormFieldState<String> field) {
                  return VelvetField(
                    label: l10n.phoneLabel,
                    controller: _phone,
                    enabled: !_saving,
                    keyboardType: TextInputType.phone,
                    inputFormatters: const <UaPhoneInputFormatter>[
                      UaPhoneInputFormatter(),
                    ],
                    hint: '+380 __ ___ __ __',
                    errorText: _errPhone,
                    helperText: l10n.clientPhonePrivacyNote,
                    onChanged: (v) {
                      _clearServerError('phoneNumber');
                      field.didChange(v);
                      final next = _validatePhone(_phone.text);
                      if (next != _errPhone) {
                        setState(() => _errPhone = next);
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
