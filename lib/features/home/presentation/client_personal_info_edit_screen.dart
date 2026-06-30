// CLIENT Особисті дані — the personal-info slice of the client profile: avatar
// editor + "Змінити фото" caption, then Ім'я (required) and Прізвище (required).
// A pinned "Зберегти" CTA sits at the bottom.
//
// 1:1 transcription of the master [PersonalInfoEditScreen] with ONE approved
// modification: the bio field is REMOVED (clients have no bio). Save merges
// firstName + lastName onto the cached profile via
// [ClientProfileRepository.updateMyProfile] (`PATCH /users/me`); the partial-
// update contract means the location + phone slices are never sent here, so they
// are preserved server-side.
//
// Save flow: validate → updateMyProfile(name slice) → invalidate
// clientEditProfileProvider + clientProfileProvider → saved SnackBar → home.
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
import 'package:beautica_mobile/shared/validators/name_validator.dart';

import 'package:beautica_mobile/features/master/presentation/widgets/section_scaffold.dart';

/// CLIENT personal-info edit page (firstName + lastName only — no bio).
class ClientPersonalInfoEditScreen extends ConsumerStatefulWidget {
  const ClientPersonalInfoEditScreen({super.key});

  @override
  ConsumerState<ClientPersonalInfoEditScreen> createState() =>
      _ClientPersonalInfoEditScreenState();
}

class _ClientPersonalInfoEditScreenState
    extends ConsumerState<ClientPersonalInfoEditScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _firstName;
  late final TextEditingController _lastName;

  bool _initialized = false;

  String _origFirstName = '';
  String _origLastName = '';

  Map<String, String> _fieldErrors = const <String, String>{};
  bool _saving = false;

  String? _errFirstName;
  String? _errLastName;

  // PERF (P2): drives the Save button's enabled state in isolation so typing
  // does not setState the whole form (and its reveal animation wrappers). Only
  // the footer (ValueListenableBuilder) and the avatar initials follow input.
  final ValueNotifier<bool> _dirty = ValueNotifier<bool>(false);

  // Animation — pre-built in initState; zero allocations in build().
  late final AnimationController _controller;
  late final CurvedAnimation _anim0; // avatar
  late final CurvedAnimation _anim1; // firstName
  late final CurvedAnimation _anim2; // lastName
  late final CurvedAnimation _animFooter; // pinned Save

  static final Tween<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  );

  static final TextStyle _changePhotoStyle = VelvetText.label().copyWith(
    color: BrandColors.accent,
    letterSpacing: 0.4,
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
    _anim1 = _curve(0.06, 0.50);
    _anim2 = _curve(0.14, 0.58);
    _animFooter = _curve(0.60, 1.0);
  }

  CurvedAnimation _curve(double start, double end) => CurvedAnimation(
    parent: _controller,
    curve: Interval(start, end, curve: Curves.easeOutCubic),
  );

  void _maybeInit(User user) {
    if (_initialized) return;
    _initialized = true;

    _origFirstName = user.firstName ?? '';
    _origLastName = user.lastName ?? '';

    _firstName = TextEditingController(text: _origFirstName);
    _lastName = TextEditingController(text: _origLastName);

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
    _anim2.dispose();
    _animFooter.dispose();
    _controller.dispose();
    _dirty.dispose();
    super.dispose();
  }

  List<TextEditingController> get _editableControllers =>
      <TextEditingController>[_firstName, _lastName];

  // PERF (P2): recompute the dirty flag only — no setState, so the form subtree
  // and its animation wrappers are not rebuilt on every keystroke.
  void _onFormChanged() {
    _dirty.value = _isDirty;
  }

  bool get _isDirty =>
      _initialized &&
      (_firstName.text.trim() != _origFirstName ||
          _lastName.text.trim() != _origLastName);

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

  String? _validateFirstName(String? v) {
    final serverErr = _fieldErrors['firstName'];
    if (serverErr != null) return serverErr;
    final l10n = AppLocalizations.of(context);
    if (v == null || v.trim().isEmpty) {
      return l10n.errNameRequired;
    }
    if (v.trim().length > 100) {
      return l10n.errNameTooLong;
    }
    if (nameContainsDigit(v)) {
      return l10n.errFirstNameHasDigit;
    }
    return null;
  }

  String? _validateLastName(String? v) {
    final serverErr = _fieldErrors['lastName'];
    if (serverErr != null) return serverErr;
    final l10n = AppLocalizations.of(context);
    if (v == null || v.trim().isEmpty) {
      return l10n.errNameRequired;
    }
    if (v.trim().length > 100) {
      return l10n.errNameTooLong;
    }
    if (nameContainsDigit(v)) {
      return l10n.errLastNameHasDigit;
    }
    return null;
  }

  bool _validateAndUpdateErrors() {
    final ok = _formKey.currentState!.validate();
    setState(() {
      _errFirstName = _validateFirstName(_firstName.text);
      _errLastName = _validateLastName(_lastName.text);
    });
    return ok;
  }

  Future<void> _save() async {
    if (!_initialized) return;
    setState(() {
      _fieldErrors = const <String, String>{};
      _errFirstName = null;
      _errLastName = null;
    });

    if (!_validateAndUpdateErrors()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const Key('snackbar-validation-summary'),
            content: Text(AppLocalizations.of(context).editValidationSummary),
          ),
        );
      }
      return;
    }

    setState(() => _saving = true);

    try {
      // Only the name slice — phone + location are untouched and preserved
      // server-side (partial-update contract).
      await ref
          .read(clientProfileRepositoryProvider)
          .updateMyProfile(
            ClientProfileUpdate(
              firstName: _firstName.text.trim(),
              lastName: _lastName.text.trim(),
            ),
          );

      if (!mounted) return;
      // Re-fetch the session User so clientProfile (derived from authProvider)
      // re-derives the fresh name; then invalidate the edit-seed + profile
      // providers so they re-read from the now-current session.
      await ref.read(authProvider.notifier).refreshUser();
      if (!mounted) return;
      ref.invalidate(clientEditProfileProvider);
      ref.invalidate(clientProfileProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('snackbar-saved'),
          content: Text(AppLocalizations.of(context).savedSnackbar),
        ),
      );
      context.go(RouteNames.clientHome);
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _fieldErrors = Map<String, String>.unmodifiable(f.fieldErrors);
        _saving = false;
      });
      _validateAndUpdateErrors();
      if (f.fieldErrors.isEmpty) {
        final serverMessage = f.serverMessage?.trim();
        final text = (serverMessage != null && serverMessage.isNotEmpty)
            ? serverMessage
            : AppLocalizations.of(context).errValidation;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const Key('snackbar-validation-error'),
            content: Text(text),
          ),
        );
      }
    } on Failure catch (f) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(f.userMessage(context))));
      setState(() => _saving = false);
    } catch (e, st) {
      if (kDebugMode) {
        log(
          'client personal-info save unexpected error',
          name: 'feature.client.edit.personal',
          level: 1000,
          error: e,
          stackTrace: st,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).errUnknown)),
      );
      setState(() => _saving = false);
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  void _onAvatarTap() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).snackbarAvatarSoon)),
    );
  }

  String _buildInitials() {
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    if (first.isEmpty && last.isEmpty) return '?';
    final a = first.isNotEmpty ? first[0].toUpperCase() : '';
    final b = last.isNotEmpty ? last[0].toUpperCase() : '';
    final initials = '$a$b'.trim();
    return initials.isEmpty ? '?' : initials;
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
      title: l10n.personalInfoTitle,
      backKey: const Key('btn-back-personal'),
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
            key: const Key('btn-save-personal'),
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
              Column(
                children: <Widget>[
                  Center(
                    // PERF (P2): only the avatar initials follow the name
                    // keystrokes — listen to just the two name controllers
                    // rather than rebuilding the whole form.
                    child: ListenableBuilder(
                      listenable: Listenable.merge(<Listenable>[
                        _firstName,
                        _lastName,
                      ]),
                      builder: (context, _) => NeumorphicAvatarEditor(
                        state: AvatarEditState.pristine,
                        initials: _buildInitials(),
                        onTap: _onAvatarTap,
                      ),
                    ),
                  ),
                  const SizedBox(height: VelvetSpacing.sm),
                  Text(
                    l10n.changePhotoCaption,
                    style: _changePhotoStyle,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: VelvetSpacing.sm),
                  Divider(
                    thickness: 0.6,
                    color: BrandColors.accent.withValues(alpha: 0.25),
                  ),
                  const SizedBox(height: VelvetSpacing.md),
                ],
              ),
            ),
            _reveal(
              _anim1,
              FormField<String>(
                key: const Key('field-firstName'),
                initialValue: _firstName.text,
                validator: (_) => _validateFirstName(_firstName.text),
                builder: (FormFieldState<String> field) {
                  return VelvetField(
                    label: l10n.firstNameLabel,
                    controller: _firstName,
                    enabled: !_saving,
                    hint: l10n.registerFirstNamePlaceholder,
                    errorText: _errFirstName,
                    onChanged: (v) {
                      _clearServerError('firstName');
                      field.didChange(v);
                      final next = _validateFirstName(_firstName.text);
                      if (next != _errFirstName) {
                        setState(() => _errFirstName = next);
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: VelvetSpacing.lg),
            _reveal(
              _anim2,
              FormField<String>(
                key: const Key('field-lastName'),
                initialValue: _lastName.text,
                validator: (_) => _validateLastName(_lastName.text),
                builder: (FormFieldState<String> field) {
                  return VelvetField(
                    label: l10n.lastNameLabel,
                    controller: _lastName,
                    enabled: !_saving,
                    hint: l10n.registerLastNamePlaceholder,
                    errorText: _errLastName,
                    onChanged: (v) {
                      _clearServerError('lastName');
                      field.didChange(v);
                      final next = _validateLastName(_lastName.text);
                      if (next != _errLastName) {
                        setState(() => _errLastName = next);
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
