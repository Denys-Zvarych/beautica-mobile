// Phase 4.3 — Master Edit Screen.
//
// `ConsumerStatefulWidget` edit form for INDEPENDENT_MASTER profile fields.
//
// Design source: `docs/signup-designs/MasterEditScreen/` — transcribed 1:1.
// VelvetTouch soft neumorphism (light-mode, warm taupe base #E6DDD0).
//
// Layout (top → bottom):
//   Top bar     — cancel icon + centred "Редагувати профіль" title.
//   Scrollable  — avatar edit ring → "Змінити фото" caption → hairline →
//                 sub-heading → 5 VelvetField rows (firstName, lastName,
//                 bio, phone [optional + privacy note], instagram [optional]).
//   Pinned foot — NeumorphicButton "Зберегти" (disabled when pristine,
//                 spinner when saving).
//
// Save flow: validates, calls [MasterRepository.updateMyProfile], invalidates
// [masterProfileProvider], shows SnackBar, pops.
//
// Server field errors: [ValidationFailure.fieldErrors] keyed by field name.
// Each validator checks the server error first, then the local rule.
// Typing in a field clears its server error immediately.
//
// Avatar edit: tapping the camera badge shows a "Незабаром…" SnackBar.
// Photo upload is deferred to Phase 9.4.
//
// Staggered entrance: a single 900 ms AnimationController drives 6 staggered
// fade+translate reveals. CurvedAnimation instances are pre-built in initState
// — zero allocations in build().

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:screen_protector/screen_protector.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/velvet_field.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_update.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/ua_phone_input_formatter.dart';

import 'master_profile_notifier.dart';

/// Edit form for the authenticated INDEPENDENT_MASTER's own profile.
///
/// Pre-populated from [masterProfileProvider]'s current cached value.
/// Handles pristine (Save disabled), dirty (Save enabled), saving (spinner +
/// form locked), server-field-errors (inline per field), and network/server
/// error (SnackBar) states.
class MasterEditScreen extends ConsumerStatefulWidget {
  const MasterEditScreen({super.key});

  @override
  ConsumerState<MasterEditScreen> createState() => _MasterEditScreenState();
}

class _MasterEditScreenState extends ConsumerState<MasterEditScreen>
    with SingleTickerProviderStateMixin {
  // -------------------------------------------------------------------------
  // Animation — pre-built in initState; zero allocations in build().
  // -------------------------------------------------------------------------
  late final AnimationController _controller;
  late final CurvedAnimation _anim0; // avatar section
  late final CurvedAnimation _anim1; // sub-heading
  late final CurvedAnimation _anim2; // firstName + lastName
  late final CurvedAnimation _anim3; // bio
  late final CurvedAnimation _anim4; // phone
  late final CurvedAnimation _anim5; // instagram + footer

  // -------------------------------------------------------------------------
  // Form state
  // -------------------------------------------------------------------------
  final _formKey = GlobalKey<FormState>();

  // Controllers are late because they are initialized once master data lands.
  // Before _initialized is true, the loading scaffold renders instead.
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _bio;
  late final TextEditingController _phone;
  late final TextEditingController _instagram;

  // True once controllers have been seeded from the provider's master data.
  bool _initialized = false;

  // Snapshot of original values for pristine detection.
  String _origFirstName = '';
  String _origLastName = '';
  String _origBio = '';
  String _origPhone = '';
  String _origInstagram = '';

  /// Server-side field errors from the last [ValidationFailure].
  Map<String, String> _fieldErrors = const <String, String>{};

  bool _saving = false;

  // Inline error texts mirrored from FormField state so VelvetField can display
  // them without being a FormField itself. Updated after every validate() call.
  String? _errFirstName;
  String? _errLastName;
  String? _errBio;
  String? _errPhone;

  static const int _bioMax = 2000;
  static const int _phoneMax = 20;

  // Pre-built cached styles — never call copyWith inside build().
  static final TextStyle _titleStyle = VelvetText.subheading();
  static final TextStyle _bodyStyle = VelvetText.body();
  static final TextStyle _changePhotoStyle = VelvetText.label().copyWith(
    color: BrandColors.accent,
    letterSpacing: 0.4,
  );

  // Fix 2 (PERF MEDIUM-1): static final Tween reused across all _reveal() calls
  // instead of allocating a new Tween<Offset> per call per build frame.
  static final Tween<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  );

  // Fix 5 (PERF LOW-1): static final RegExp so _validatePhone does not allocate
  // a new RegExp on every keystroke.
  static final RegExp _phoneAllowedChars = RegExp(r'^[+\d\s\-()]*$');

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    // Fix 4 (SEC MEDIUM): protect PII-bearing screen from screenshots/Recent Apps
    // thumbnails in release builds. Mirrors the pattern in master_profile_screen.
    if (!kDebugMode) ScreenProtector.preventScreenshotOn();

    // Controllers are NOT initialized here. They are seeded lazily from
    // the provider's first resolved data value in [_maybeInit] — called from
    // build() the first time [masterProfileProvider] has a non-null value.
    // This avoids a race condition where the provider completes its first
    // async build after initState runs (common in tests with Future.value stubs
    // and in production when the profile cache is cold).

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim0 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.00, 0.42, curve: Curves.easeOutCubic),
    );
    _anim1 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.06, 0.44, curve: Curves.easeOutCubic),
    );
    _anim2 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.10, 0.52, curve: Curves.easeOutCubic),
    );
    _anim3 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.22, 0.66, curve: Curves.easeOutCubic),
    );
    _anim4 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.30, 0.74, curve: Curves.easeOutCubic),
    );
    _anim5 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.38, 0.82, curve: Curves.easeOutCubic),
    );
  }

  /// Initializes text controllers from [master] on the FIRST call only.
  ///
  /// Called from [build] the first time [masterProfileProvider] resolves to
  /// a non-null [Master]. Subsequent calls are no-ops (guarded by [_initialized]).
  void _maybeInit(Master master) {
    if (_initialized) return;
    _initialized = true;

    _origFirstName = master.firstName;
    _origLastName = master.lastName;
    _origBio = master.bio ?? '';
    _origPhone = master.phoneNumber ?? '';
    _origInstagram = '';

    _firstName = TextEditingController(text: _origFirstName);
    _lastName = TextEditingController(text: _origLastName);
    _bio = TextEditingController(text: _origBio);
    _phone = TextEditingController(text: _origPhone);
    _instagram = TextEditingController(text: _origInstagram);

    // Start the entrance animation now that we have content to reveal.
    _controller.forward();
  }

  @override
  void dispose() {
    if (!kDebugMode) ScreenProtector.preventScreenshotOff();
    if (_initialized) {
      for (final c in <TextEditingController>[
        _firstName,
        _lastName,
        _bio,
        _phone,
        _instagram,
      ]) {
        c.dispose();
      }
    }
    _anim0.dispose();
    _anim1.dispose();
    _anim2.dispose();
    _anim3.dispose();
    _anim4.dispose();
    _anim5.dispose();
    _controller.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  bool get _isDirty =>
      _initialized &&
      (_firstName.text.trim() != _origFirstName ||
          _lastName.text.trim() != _origLastName ||
          _bio.text.trim() != _origBio ||
          _phone.text.trim() != _origPhone ||
          _instagram.text.trim() != _origInstagram);

  Widget _reveal(CurvedAnimation anim, Widget child) {
    // Fix 2: reuse the static _slideTween — only the lightweight
    // _AnimatedEvaluation wrapper is allocated per call.
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

  // -------------------------------------------------------------------------
  // Validators — used by Form.validate() AND by the inline error update path.
  // -------------------------------------------------------------------------

  String? _validateFirstName(String? v) {
    final serverErr = _fieldErrors['firstName'];
    if (serverErr != null) return serverErr;
    if (v == null || v.trim().isEmpty) {
      return AppLocalizations.of(context).errNameRequired;
    }
    if (v.trim().length > 100) {
      return AppLocalizations.of(context).errNameTooLong;
    }
    return null;
  }

  String? _validateLastName(String? v) {
    final serverErr = _fieldErrors['lastName'];
    if (serverErr != null) return serverErr;
    if (v == null || v.trim().isEmpty) {
      return AppLocalizations.of(context).errNameRequired;
    }
    if (v.trim().length > 100) {
      return AppLocalizations.of(context).errNameTooLong;
    }
    return null;
  }

  String? _validateBio(String? v) {
    final serverErr = _fieldErrors['bio'];
    if (serverErr != null) return serverErr;
    if (v != null && v.length > _bioMax) {
      return AppLocalizations.of(context).errBioTooLong;
    }
    return null;
  }

  String? _validatePhone(String? v) {
    final serverErr = _fieldErrors['contactPhone'];
    if (serverErr != null) return serverErr;
    if (v == null || v.trim().isEmpty) return null; // optional
    if (v.trim().length > _phoneMax) {
      return AppLocalizations.of(context).errPhoneTooLongEdit;
    }
    if (!_phoneAllowedChars.hasMatch(v.trim())) {
      return AppLocalizations.of(context).errPhoneInvalidEdit;
    }
    return null;
  }

  /// Runs the form validators and mirrors errors into the inline state so
  /// VelvetField can display them via its [errorText] parameter.
  bool _validateAndUpdateErrors() {
    final ok = _formKey.currentState!.validate();
    setState(() {
      _errFirstName = _validateFirstName(_firstName.text);
      _errLastName = _validateLastName(_lastName.text);
      _errBio = _validateBio(_bio.text);
      _errPhone = _validatePhone(_phone.text);
    });
    return ok;
  }

  // -------------------------------------------------------------------------
  // Save
  // -------------------------------------------------------------------------

  Future<void> _save() async {
    if (!_initialized) return;
    setState(() {
      _fieldErrors = const <String, String>{};
      _errFirstName = null;
      _errLastName = null;
      _errBio = null;
      _errPhone = null;
    });

    if (!_validateAndUpdateErrors()) return;

    setState(() => _saving = true);

    try {
      await ref
          .read(masterRepositoryProvider)
          .updateMyProfile(
            MasterUpdate(
              firstName: _firstName.text.trim(),
              lastName: _lastName.text.trim(),
              bio: _bio.text.trim(),
              contactPhone: _phone.text.trim(),
              instagram: _instagram.text.trim(),
            ),
          );

      ref.invalidate(masterProfileProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).savedSnackbar)),
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(RouteNames.masterProfile);
      }
    } on ValidationFailure catch (f) {
      if (kDebugMode) {
        log(
          'updateMyProfile validation failure: ${f.fieldErrors}',
          name: 'feature.master',
          level: 800,
        );
      }
      if (!mounted) return;
      setState(() {
        _fieldErrors = Map<String, String>.unmodifiable(f.fieldErrors);
        _saving = false;
      });
      // Re-mirror server errors into VelvetField errorText state.
      _validateAndUpdateErrors();
    } on Failure catch (f) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(f.userMessage(context))));
      setState(() => _saving = false);
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  // -------------------------------------------------------------------------
  // Avatar
  // -------------------------------------------------------------------------

  void _onAvatarTap() {
    if (kDebugMode) {
      log(
        'Avatar edit tapped — photo upload deferred to Phase 9.4',
        name: 'feature.master',
        level: 800,
      );
    }
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

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Seed controllers from provider data on first successful resolution.
    // ref.watch ensures this rebuilds when the provider settles from loading.
    final masterAsync = ref.watch(masterProfileProvider);
    masterAsync.whenData<void>(_maybeInit);

    // Show a minimal centered indicator while waiting for data.
    if (!_initialized) {
      return const Scaffold(
        backgroundColor: BrandColors.base,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Top bar.
            Padding(
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
                        key: const Key('btn-cancel-master'),
                        icon: Icons.close_rounded,
                        semanticLabel: l10n.masterCancelButton,
                        onTap: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go(RouteNames.masterProfile);
                          }
                        },
                      ),
                    ),
                    Text(
                      l10n.masterEditTitle,
                      style: _titleStyle,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            // Scrollable form body.
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    VelvetSpacing.lg,
                    VelvetSpacing.md,
                    VelvetSpacing.lg,
                    VelvetSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // 0 — Avatar edit section.
                      _reveal(
                        _anim0,
                        Column(
                          children: <Widget>[
                            Center(
                              child: NeumorphicAvatarEditor(
                                state: AvatarEditState.pristine,
                                initials: _buildInitials(),
                                onTap: _onAvatarTap,
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

                      // 1 — Sub-heading.
                      _reveal(
                        _anim1,
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 4,
                            bottom: VelvetSpacing.lg,
                          ),
                          child: Text(
                            l10n.updateDataSubheading,
                            style: _bodyStyle,
                          ),
                        ),
                      ),

                      // 2a — First name.
                      _reveal(
                        _anim2,
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
                                setState(
                                  () => _errFirstName = _validateFirstName(
                                    _firstName.text,
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: VelvetSpacing.lg),

                      // 2b — Last name.
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
                                setState(
                                  () => _errLastName = _validateLastName(
                                    _lastName.text,
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: VelvetSpacing.lg),

                      // 3 — Bio (multiline, max 2000, live counter).
                      _reveal(
                        _anim3,
                        FormField<String>(
                          key: const Key('field-bio'),
                          initialValue: _bio.text,
                          validator: (_) => _validateBio(_bio.text),
                          builder: (FormFieldState<String> field) {
                            return VelvetField(
                              label: l10n.bioLabel,
                              controller: _bio,
                              enabled: !_saving,
                              hint:
                                  'Розкажіть про свій досвід та спеціалізацію',
                              maxLines: 4,
                              maxLength: _bioMax,
                              showCounter: true,
                              errorText: _errBio,
                              onChanged: (v) {
                                _clearServerError('bio');
                                field.didChange(v);
                                setState(
                                  () => _errBio = _validateBio(_bio.text),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: VelvetSpacing.lg),

                      // 4 — Phone (optional, privacy helper, formatter).
                      _reveal(
                        _anim4,
                        FormField<String>(
                          key: const Key('field-phone'),
                          initialValue: _phone.text,
                          validator: (_) => _validatePhone(_phone.text),
                          builder: (FormFieldState<String> field) {
                            return VelvetField(
                              label: l10n.phoneLabel,
                              controller: _phone,
                              enabled: !_saving,
                              optional: true,
                              keyboardType: TextInputType.phone,
                              inputFormatters: const <UaPhoneInputFormatter>[
                                UaPhoneInputFormatter(),
                              ],
                              hint: '+380 __ ___ __ __',
                              errorText: _errPhone,
                              helperText: l10n.phonePrivacyNote,
                              onChanged: (v) {
                                _clearServerError('contactPhone');
                                field.didChange(v);
                                setState(
                                  () => _errPhone = _validatePhone(_phone.text),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: VelvetSpacing.lg),

                      // 5 — Instagram handle (optional, @ prefix).
                      _reveal(
                        _anim5,
                        FormField<String>(
                          key: const Key('field-instagram'),
                          initialValue: _instagram.text,
                          validator: (_) => _fieldErrors['instagram'],
                          builder: (FormFieldState<String> field) {
                            return VelvetField(
                              label: l10n.instagramLabel,
                              controller: _instagram,
                              enabled: !_saving,
                              optional: true,
                              prefixText: '@',
                              hint: 'username',
                              errorText: _fieldErrors['instagram'],
                              onChanged: (v) {
                                _clearServerError('instagram');
                                field.didChange(v);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Pinned Save CTA footer.
            _reveal(
              _anim5,
              DecoratedBox(
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
                    key: const Key('btn-save-master'),
                    label: l10n.masterSaveButton,
                    icon: Icons.check_rounded,
                    loading: _saving,
                    onPressed: (!_saving && _isDirty) ? _save : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
