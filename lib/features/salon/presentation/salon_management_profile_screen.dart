// Phase 21.2 — Salon Profile (Owner + Admin, editable).
//
// Structurally a mirror of the shipped read-only `public_salon_profile_screen
// .dart`: full-bleed cover + overlapping hero identity card, a 4-tab switcher
// (Про салон / Персонал / Послуги / Відгуки). Owner/admin deltas layered on
// top, per the phase doc's locked 2026-07-06 decision — **admin sees the
// identical screen as owner**, with exactly one structural difference: admin
// has no salon-delete action (owner-only, `SalonController.java:104`).
//
// REUSE-FIRST — widgets reused verbatim from
// `features/salon/presentation/widgets/`:
//   [SalonCover], [CoverIconButton], [SalonLogo] — cover/hero chrome
//   [SalonTabBar]                                — the 4-tab switcher
//   [SalonMasterCard]                             — the «Персонал» grid cards
//   [SalonServicesAccordion]                      — «Послуги» tab (unchanged)
//   [SalonReviewsSection]                         — «Відгуки» tab (unchanged)
// `ContactTile` (shared/widgets) for the phone/Instagram rows. None of these
// were forked or copied.
//
// NOT reused from `public_salon_profile_screen.dart`: its `_SalonHeroCard`/
// `_CoverAndHero` are PRIVATE to that file and bundle client-only geometry
// (an `ExpandableNote`-driven variable-height overlap, Phase 224) this screen
// doesn't need — the design source's preview `_OwnerHeroCard` is a much
// simpler fixed-content card, so this file writes its own small
// `_ManagementHeroCard` from the already-shared [SalonLogo] + [NeumorphicCard]
// rather than pulling in geometry built for a feature (the location note)
// this screen never renders.
//
// EDIT MODE — the top-right `Icons.tune_rounded` cover control never toggles
// inline edit directly; it pushes [SalonSettingsScreen], whose «Редагувати
// профіль» row pops back here with a `true` result, which is what flips
// [_editMode] on (see [_openSettings]). In edit mode the «Про салон» tab body
// swaps to a form (name/description/phone/Instagram — see the phase's Phase
// 21.2 gap note on why phone starts blank) with a pinned Save/Cancel footer.
// Address (city/street/buildingNo) is NOT editable here — it isn't in this
// phase's Implementation Steps, and `UpdateSalonRequest.street`/`.buildingNo`
// are threaded through unmodified by the notifier regardless.
//
// Portfolio management (an owner "+" add-photo tile) is likewise NOT built
// here — no media-upload endpoint is wired for this phase's Implementation
// Steps, so the read-only description + contacts are all «Про салон» shows.
//
// «Персонал» — Phase 21.4 (Invite Staff, form only) is BUILT: the trailing
// "+" tile pushes [InviteStaffScreen] via `RouteNames.salonInviteStaff`.
// Phase 21.5 (Master Management Profile) is BUILT too: staff-card taps push
// `RouteNames.salonManageStaffMember` (see [_openStaffMember]). The roster
// itself now lists both masters and admins — `getSalonStaff` (GET
// `/salons/{salonId}/staff`), not a masters-only endpoint — a deliberate,
// user-approved behaviour change landed alongside 21.5.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/velvet_field.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/role_home.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/formatters/address_lines.dart';
import 'package:beautica_mobile/shared/utils/instagram_url.dart';
import 'package:beautica_mobile/shared/widgets/contact_tile.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';

import '../application/my_salons_notifier.dart';
import '../application/salon_management_profile_notifier.dart';
import '../application/salon_service_catalog_notifier.dart';
import '../domain/salon.dart';
import '../domain/salon_service_catalog.dart';
import '../domain/salon_staff_member.dart';
import 'widgets/salon_cover_widgets.dart';
import 'widgets/salon_master_card.dart';
import 'widgets/salon_reviews_section.dart';
import 'widgets/salon_services_accordion.dart';

// mobile-security LOW follow-up (2026-08-27) — client-side field caps for the
// «Про салон» edit form, mirroring `UpdateSalonRequest`'s backend Bean
// Validation `@Size` limits (`beautica-backend/.../salon/dto/
// UpdateSalonRequest.java`) so a value the backend WOULD reject with a 400
// surfaces an inline error instead. Shared between the validators in
// `_SalonManagementProfileScreenState` and the `maxLength` caps in
// [_AboutEditForm].
const int _salonNameMaxLength = 255;
const int _salonDescriptionMaxLength = 2000;
const int _salonPhoneMaxLength = 20;
const int _salonInstagramMaxLength = 500;

/// Owner/admin editable profile for the salon identified by [salonId].
class SalonManagementProfileScreen extends ConsumerStatefulWidget {
  const SalonManagementProfileScreen({
    super.key,
    required this.salonId,
    this.initialTab,
    this.embedded = false,
  });

  /// Backend Salon-row UUID of the profile being managed.
  final String salonId;

  /// Phase 21.8 — seeds the initial «Про салон»/«Персонал»/«Послуги»/«Відгуки»
  /// sub-tab once, on first build. `null` (the default, every pre-Phase-21.8
  /// call site) keeps the original behaviour of always starting on tab 0
  /// («Про салон»). The Salon Shell's «Команда» tab passes `1` to land
  /// directly on `salonManageTabStaff`.
  final int? initialTab;

  /// Phase 21.8 — `true` when this screen is mounted as one `IndexedStack`
  /// child of [SalonShellScreen] rather than as its own routed, back-
  /// navigable page. Additive, defaults to `false` so every existing call
  /// site (`app_router.dart`'s `/salons/:salonId/manage`) renders IDENTICALLY
  /// to before this phase.
  ///
  /// When `true`:
  ///   * the cover's `salon-manage-back` [CoverIconButton] is hidden — the
  ///     shell's own bottom nav is the only navigation surface, and there is
  ///     nothing on the Navigator stack to pop back to (H1a);
  ///   * [_bounceIfNotOwned] is skipped entirely (H1b) — the shell mounts
  ///     this screen TWICE (Салон + Команда) in one `IndexedStack`, so both
  ///     instances' `ref.listen` would otherwise fire on the same
  ///     `mySalonsProvider` emission and race two `context.go` calls. The
  ///     shell's own route guard (`salonManageGuard`, reused verbatim for
  ///     `/salons/:salonId/shell`) already binds ownership before this
  ///     screen ever mounts, so the second, screen-level check this bounce
  ///     exists for is redundant in the embedded context.
  final bool embedded;

  @override
  ConsumerState<SalonManagementProfileScreen> createState() =>
      _SalonManagementProfileScreenState();
}

class _SalonManagementProfileScreenState
    extends ConsumerState<SalonManagementProfileScreen> {
  static const double _coverHeight = 232;
  static const double _heroProtrusion = 116;

  // Mirrors UpdateSalonRequest.phone's backend @Pattern.
  static final RegExp _phoneAllowedChars = RegExp(r'^[+\d\s\-()/]*$');
  // Mirrors UpdateSalonRequest.instagramUrl's backend @Pattern — a bare/`@`
  // handle, or a full instagram.com URL.
  static final RegExp _instagramHandle = RegExp(r'^@?[A-Za-z0-9._]{1,30}$');
  static final RegExp _instagramUrlPattern = RegExp(
    r'^https://(www\.)?instagram\.com/[A-Za-z0-9._]+/?$',
  );

  late int _tab;
  bool _editMode = false;
  bool _saving = false;

  bool _controllersReady = false;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _instagramCtrl;

  String? _errName;
  String? _errPhone;
  String? _errInstagram;

  @override
  void initState() {
    super.initState();
    // Seeds once from `widget.initialTab` — every pre-Phase-21.8 call site
    // leaves it `null`, so `_tab` starts at 0 exactly as before.
    _tab = widget.initialTab ?? 0;
  }

  @override
  void dispose() {
    if (_controllersReady) {
      _nameCtrl.dispose();
      _descCtrl.dispose();
      _phoneCtrl.dispose();
      _instagramCtrl.dispose();
    }
    super.dispose();
  }

  void _initControllers(Salon salon) {
    if (_controllersReady) return;
    _controllersReady = true;
    _nameCtrl = TextEditingController(text: salon.name);
    _descCtrl = TextEditingController(text: salon.description ?? '');
    _phoneCtrl = TextEditingController(text: salon.phone ?? '');
    _instagramCtrl = TextEditingController(text: salon.instagramUrl ?? '');
  }

  void _resetControllers(Salon salon) {
    _nameCtrl.text = salon.name;
    _descCtrl.text = salon.description ?? '';
    _phoneCtrl.text = salon.phone ?? '';
    _instagramCtrl.text = salon.instagramUrl ?? '';
  }

  void _clearErrors() {
    _errName = null;
    _errPhone = null;
    _errInstagram = null;
  }

  String? _validateName(String v) {
    final l10n = AppLocalizations.of(context);
    if (v.trim().isEmpty) return l10n.errNameRequired;
    if (v.trim().length > _salonNameMaxLength) {
      return l10n.salonManageNameTooLong;
    }
    return null;
  }

  String? _validatePhone(String v) {
    if (v.trim().isEmpty) return null; // optional
    final l10n = AppLocalizations.of(context);
    if (v.trim().length > _salonPhoneMaxLength) return l10n.errPhoneTooLongEdit;
    if (!_phoneAllowedChars.hasMatch(v.trim())) {
      return l10n.errPhoneInvalidEdit;
    }
    return null;
  }

  String? _validateInstagram(String v) {
    if (v.trim().isEmpty) return null; // optional
    final l10n = AppLocalizations.of(context);
    if (!_instagramHandle.hasMatch(v.trim()) &&
        !_instagramUrlPattern.hasMatch(v.trim())) {
      return l10n.masterEditInstagramError;
    }
    return null;
  }

  /// Re-validates all three fields, updates the inline error state, and
  /// returns whether the form is valid. Mirrors `ContactsEditScreen
  /// ._validateAndUpdateErrors` / `PersonalInfoEditScreen`'s identical
  /// validate-then-block Save convention.
  bool _validateAndUpdateErrors() {
    final String? nameErr = _validateName(_nameCtrl.text);
    final String? phoneErr = _validatePhone(_phoneCtrl.text);
    final String? instagramErr = _validateInstagram(_instagramCtrl.text);
    setState(() {
      _errName = nameErr;
      _errPhone = phoneErr;
      _errInstagram = instagramErr;
    });
    return nameErr == null && phoneErr == null && instagramErr == null;
  }

  void _onNameChanged(String v) {
    final next = _validateName(v);
    if (next != _errName) setState(() => _errName = next);
  }

  void _onPhoneChanged(String v) {
    final next = _validatePhone(v);
    if (next != _errPhone) setState(() => _errPhone = next);
  }

  void _onInstagramChanged(String v) {
    final next = _validateInstagram(v);
    if (next != _errInstagram) setState(() => _errInstagram = next);
  }

  Future<void> _openSettings() async {
    final bool? toggleEdit = await context.push<bool>(
      RouteNames.salonManageSettings(widget.salonId),
    );
    if (toggleEdit == true && mounted) {
      setState(() => _editMode = true);
    }
  }

  void _cancelEdit(Salon salon) {
    _resetControllers(salon);
    setState(() {
      _editMode = false;
      _clearErrors();
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (!_validateAndUpdateErrors()) {
      showErrorSnack(context, l10n.editValidationSummary);
      return;
    }
    setState(() => _saving = true);
    final Failure? failure = await ref
        .read(salonManagementProfileProvider(widget.salonId).notifier)
        .save(
          name: _nameCtrl.text,
          description: _descCtrl.text,
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
    setState(() {
      _editMode = false;
      _clearErrors();
    });
  }

  /// Opens the staff management profile for [member] (Phase 21.5) — works for
  /// both a master and an admin entry; the destination screen branches on
  /// [member.role] internally.
  void _openStaffMember(SalonStaffMember member) => context.push(
    RouteNames.salonManageStaffMember(widget.salonId, member.userId),
  );

  void _openInviteStaff() =>
      context.push(RouteNames.salonInviteStaff(widget.salonId));

  // mobile-security LOW follow-up (2026-08-28) — `salonManageGuard`'s
  // `SALON_OWNER` arm (`app_router.dart`) admits a cold deep link BEFORE
  // `mySalonsProvider` resolves (documented, synchronous-`redirect:`-only
  // design — see that guard's own comment). `GET /salons/{salonId}` (this
  // screen's own data source, `salonManagementProfileProvider`) is the SAME
  // publicly-readable endpoint `public_salon_profile_notifier.dart` uses, so
  // during that window a SALON_OWNER can see a fully-rendered shell of a
  // salon they do not own (not a privilege escalation — `PATCH`/`DELETE`
  // stay backend-gated — but a real exposure gap, same class as the
  // SALON_ADMIN one the guard already closed). Once `mySalonsProvider`
  // resolves, close the window here: bounce off this screen the instant the
  // owner's real salon list turns out not to contain [widget.salonId].
  // SALON_ADMIN is exempt — its ownership check (`User.salonId`) is already
  // synchronous in the guard, so there is no window to close, and gating on
  // role keeps this listener from ever touching `mySalonsProvider` for a
  // role that has no use for it (would otherwise reintroduce the same
  // unwanted-fetch shape the mobile-perf HIGH finding on that provider just
  // closed).
  void _bounceIfNotOwned(AuthSession? session) {
    // Phase 21.8 H1b / mobile-security MEDIUM follow-up (2026-08-28) —
    // embedded (i.e. mounted inside `SalonShellScreen`'s `IndexedStack`) is
    // NOT this screen's job to ownership-bounce. The Salon Shell mounts this
    // screen TWICE in one `IndexedStack` (Салон + Команда, same `salonId`) —
    // if each instance carried its own `ref.listen` below, both would fire
    // on the SAME `mySalonsProvider` emission and race two `context.go`
    // calls (and since `roleHomePath(salonOwner)` now points at the shell's
    // own resolver, that race can loop). `SalonShellScreen` itself now owns
    // exactly ONE such listener for the whole shell instead — see its own
    // `_bounceIfNotOwned` in `salon_shell_screen.dart` — so this early
    // return just keeps this screen from adding a second, redundant one when
    // embedded. NOTE: this is NOT because the route guard already bound
    // ownership — `salonManageGuard`'s `SALON_OWNER` arm has a documented
    // "admit while `mySalonsProvider` is unresolved" window, which is
    // exactly what the shell's own listener (not the guard) closes.
    if (widget.embedded) return;
    if (session is! Authenticated || session.user.role != UserRole.salonOwner) {
      return;
    }
    ref.listen<AsyncValue<List<Salon>>>(mySalonsProvider, (
      AsyncValue<List<Salon>>? previous,
      AsyncValue<List<Salon>> next,
    ) {
      // Concrete-subtype gate — `copyWithPrevious` keeps a stale `.value`
      // attached to a LATER `AsyncLoading`/`AsyncError` (e.g. mid-retry, or
      // right after a cross-account login on the same device), so only a
      // genuinely resolved `AsyncData` is ever trusted here — mirrors
      // `salonManageGuard`'s own gate in `app_router.dart` and
      // `SalonShellScreen`'s own `_bounceIfNotOwned`.
      if (next is! AsyncData<List<Salon>>) return;
      final List<Salon> salons = next.value;
      if (salons.any((Salon salon) => salon.id == widget.salonId)) return;
      if (context.mounted) context.go(roleHomePath(session.user.role));
    });
  }

  @override
  Widget build(BuildContext context) {
    _bounceIfNotOwned(ref.watch(authProvider).value);
    final AsyncValue<SalonManagementProfileData> async = ref.watch(
      salonManagementProfileProvider(widget.salonId),
    );
    final double topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: BrandColors.base,
      bottomNavigationBar: async.maybeWhen(
        data: (SalonManagementProfileData data) => _editMode
            ? _EditFooter(
                saving: _saving,
                onCancel: () => _cancelEdit(data.$1),
                onSave: _save,
              )
            : null,
        orElse: () => null,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: VelvetSpacing.xxl),
        child: async.when(
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 120),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (Object e, _) => Padding(
            padding: EdgeInsets.only(top: topInset + VelvetSpacing.xxl),
            child: ErrorState(
              failure: e is Failure ? e : UnknownFailure(cause: e),
              onRetry: () => ref.invalidate(
                salonManagementProfileProvider(widget.salonId),
              ),
            ),
          ),
          data: (SalonManagementProfileData data) {
            final (Salon salon, List<SalonStaffMember> staff) = data;
            _initControllers(salon);
            return _LoadedBody(
              salonId: widget.salonId,
              salon: salon,
              staff: staff,
              embedded: widget.embedded,
              topInset: topInset,
              coverHeight: _coverHeight,
              heroProtrusion: _heroProtrusion,
              tab: _tab,
              onTabSelected: (int i) => setState(() => _tab = i),
              editMode: _editMode,
              nameCtrl: _nameCtrl,
              descCtrl: _descCtrl,
              phoneCtrl: _phoneCtrl,
              instagramCtrl: _instagramCtrl,
              saving: _saving,
              errName: _errName,
              errPhone: _errPhone,
              errInstagram: _errInstagram,
              onNameChanged: _onNameChanged,
              onPhoneChanged: _onPhoneChanged,
              onInstagramChanged: _onInstagramChanged,
              onOpenSettings: _openSettings,
              onOpenStaffMember: _openStaffMember,
              onInviteStaff: _openInviteStaff,
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _LoadedBody — cover + hero + tab bar + tab body
// ---------------------------------------------------------------------------

class _LoadedBody extends StatelessWidget {
  const _LoadedBody({
    required this.salonId,
    required this.salon,
    required this.staff,
    required this.embedded,
    required this.topInset,
    required this.coverHeight,
    required this.heroProtrusion,
    required this.tab,
    required this.onTabSelected,
    required this.editMode,
    required this.nameCtrl,
    required this.descCtrl,
    required this.phoneCtrl,
    required this.instagramCtrl,
    required this.saving,
    required this.errName,
    required this.errPhone,
    required this.errInstagram,
    required this.onNameChanged,
    required this.onPhoneChanged,
    required this.onInstagramChanged,
    required this.onOpenSettings,
    required this.onOpenStaffMember,
    required this.onInviteStaff,
  });

  final String salonId;
  final Salon salon;
  final List<SalonStaffMember> staff;

  /// Phase 21.8 — see [SalonManagementProfileScreen.embedded]. Hides the
  /// `salon-manage-back` cover control (H1a).
  final bool embedded;
  final double topInset;
  final double coverHeight;
  final double heroProtrusion;
  final int tab;
  final ValueChanged<int> onTabSelected;

  final bool editMode;
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController instagramCtrl;
  final bool saving;

  /// mobile-security LOW follow-up (2026-08-27) — inline field-validation
  /// error state, driven by `_SalonManagementProfileScreenState`'s
  /// validators; `null` renders no error.
  final String? errName;
  final String? errPhone;
  final String? errInstagram;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onPhoneChanged;
  final ValueChanged<String> onInstagramChanged;

  final VoidCallback onOpenSettings;
  final ValueChanged<SalonStaffMember> onOpenStaffMember;
  final VoidCallback onInviteStaff;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final List<String> tabs = <String>[
      l10n.salonTabAbout,
      l10n.salonManageTabStaff,
      l10n.salonTabServices,
      l10n.salonTabReviews,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _CoverAndHero(
          coverHeight: coverHeight,
          heroProtrusion: heroProtrusion,
          topInset: topInset,
          salon: salon,
          embedded: embedded,
          onOpenSettings: onOpenSettings,
        ),
        const SizedBox(height: VelvetSpacing.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
          child: SalonTabBar(
            tabs: tabs,
            selected: tab,
            onSelect: onTabSelected,
          ),
        ),
        const SizedBox(height: VelvetSpacing.lg),
        KeyedSubtree(
          key: ValueKey<String>('salon-manage-tab-body-${_tabKeys[tab]}'),
          child: switch (tab) {
            0 => _AboutTab(
              salon: salon,
              editMode: editMode,
              nameCtrl: nameCtrl,
              descCtrl: descCtrl,
              phoneCtrl: phoneCtrl,
              instagramCtrl: instagramCtrl,
              saving: saving,
              errName: errName,
              errPhone: errPhone,
              errInstagram: errInstagram,
              onNameChanged: onNameChanged,
              onPhoneChanged: onPhoneChanged,
              onInstagramChanged: onInstagramChanged,
            ),
            1 => Padding(
              padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
              child: _StaffTab(
                salonId: salonId,
                staff: staff,
                onOpenMember: onOpenStaffMember,
                onInvite: onInviteStaff,
              ),
            ),
            2 => Padding(
              padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
              child: _ServicesTab(salonId: salonId),
            ),
            _ => Padding(
              padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
              child: SalonReviewsSection(salonId: salonId),
            ),
          },
        ),
      ],
    );
  }

  static const List<String> _tabKeys = <String>[
    'about',
    'staff',
    'services',
    'reviews',
  ];
}

// ---------------------------------------------------------------------------
// Cover + hero
// ---------------------------------------------------------------------------

class _CoverAndHero extends StatelessWidget {
  const _CoverAndHero({
    required this.coverHeight,
    required this.heroProtrusion,
    required this.topInset,
    required this.salon,
    required this.embedded,
    required this.onOpenSettings,
  });

  final double coverHeight;
  final double heroProtrusion;
  final double topInset;
  final Salon salon;

  /// Phase 21.8 H1a — when `true`, the back control is omitted: the shell has
  /// no Navigator entry to pop back to for this `IndexedStack` child.
  final bool embedded;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Stack(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(bottom: heroProtrusion),
          child: SalonCover(
            height: coverHeight,
            topInset: topInset,
            imageUrl: salon.coverImageUrl,
          ),
        ),
        if (!embedded)
          Positioned(
            top: topInset + VelvetSpacing.sm,
            left: VelvetSpacing.lg,
            child: CoverIconButton(
              key: const Key('salon-manage-back'),
              icon: Icons.arrow_back_ios_new_rounded,
              semanticLabel: l10n.salonProfileBackLabel,
              onTap: () => context.pop(),
            ),
          ),
        Positioned(
          top: topInset + VelvetSpacing.sm,
          right: VelvetSpacing.lg,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Static demo unread state; tap is a placeholder — the
              // notification centre is out of scope (all notifications stay
              // dark until release, see mobile-backlog).
              //
              // The glyph keeps its baked-in unread dot verbatim per the
              // approved design (docs/signup-designs/SalonManagementDesign/
              // lib/screens/salon_profile_screen.dart:407-425) — do not add
              // an overlay dot or swap the icon. But the accessible name
              // deliberately does NOT say "unread": onTap is a no-op, so a
              // screen-reader user would be told about unread notifications
              // with no way to act on or dismiss the claim. Keep the label
              // plain ("Сповіщення" / "Notifications") until a real
              // notification centre exists — do not restore the longer
              // "…, unread" label from the preview app.
              CoverIconButton(
                key: const Key('salon-manage-notifications'),
                svgIcon: BeauticaAssetIcons.notificationUnread,
                semanticLabel: l10n.salonManageNotificationsSemanticLabel,
                onTap: () {},
              ),
              const SizedBox(width: VelvetSpacing.sm),
              CoverIconButton(
                key: const Key('salon-manage-settings'),
                icon: Icons.tune_rounded,
                iconColor: BrandColors.accentDeep,
                semanticLabel: l10n.salonManageSettingsSemanticLabel,
                onTap: onOpenSettings,
              ),
            ],
          ),
        ),
        Positioned(
          left: VelvetSpacing.lg,
          right: VelvetSpacing.lg,
          bottom: 0,
          child: _ManagementHeroCard(salon: salon),
        ),
      ],
    );
  }
}

/// The owner/admin identity card — logo + name + ★ rating · review count,
/// then a single combined address line. No inline edit affordances (editing
/// lives behind the settings hub → «Редагувати профіль»).
class _ManagementHeroCard extends StatelessWidget {
  const _ManagementHeroCard({required this.salon});

  final Salon salon;

  static const double _logoDiameter = 68;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String? monogram = salon.name.trim().isEmpty
        ? null
        : salon.name.trim()[0].toUpperCase();
    final String ratingLabel = salon.avgRating?.toStringAsFixed(1) ?? '—';
    final String? addressLine =
        buildCombinedAddressLine(salon.city, salon.street, salon.buildingNo) ??
        (salon.address?.trim().isNotEmpty ?? false ? salon.address : null);

    return NeumorphicCard(
      key: const Key('salon-manage-hero-card'),
      color: const Color(0xFFEDE4D5),
      padding: const EdgeInsets.all(VelvetSpacing.md + 2),
      // Logo centres against the FULL name+rating(+address) stack, not just
      // the name+rating row — a deliberate departure from
      // docs/signup-designs/SalonManagementDesign/lib/screens/
      // salon_profile_screen.dart:501-510, which keeps address in a second
      // band below an empty gutter (the logo then centres above the card's
      // true midpoint whenever an address is present). Requested by the
      // user 2026-08-29; the preview's two-band shape is intentionally NOT
      // restored.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SalonLogo(diameter: _logoDiameter, monogram: monogram),
          const SizedBox(width: VelvetSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  salon.name,
                  key: const Key('salon-manage-name'),
                  style: VelvetText.displayName20,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: BrandColors.accentDeep,
                    ),
                    const SizedBox(width: 4),
                    Text(ratingLabel, style: VelvetText.bodyStrong14),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '·  ${l10n.salonReviewCountLabel(salon.reviewCount)}',
                        style: VelvetText.feedbackMuted13,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (addressLine != null) ...<Widget>[
                  const SizedBox(height: 5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.location_on_outlined,
                          size: 15,
                          color: BrandColors.accentDeep,
                        ),
                      ),
                      const SizedBox(width: VelvetSpacing.xs + 1),
                      Expanded(
                        child: Text(
                          addressLine,
                          key: const Key('salon-manage-address'),
                          style: VelvetText.bookFeedbackSec13,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Про салон tab — read view / edit form
// ---------------------------------------------------------------------------

class _AboutTab extends StatelessWidget {
  const _AboutTab({
    required this.salon,
    required this.editMode,
    required this.nameCtrl,
    required this.descCtrl,
    required this.phoneCtrl,
    required this.instagramCtrl,
    required this.saving,
    required this.errName,
    required this.errPhone,
    required this.errInstagram,
    required this.onNameChanged,
    required this.onPhoneChanged,
    required this.onInstagramChanged,
  });

  final Salon salon;
  final bool editMode;
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController instagramCtrl;
  final bool saving;
  final String? errName;
  final String? errPhone;
  final String? errInstagram;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onPhoneChanged;
  final ValueChanged<String> onInstagramChanged;

  @override
  Widget build(BuildContext context) {
    if (editMode) {
      return _AboutEditForm(
        nameCtrl: nameCtrl,
        descCtrl: descCtrl,
        phoneCtrl: phoneCtrl,
        instagramCtrl: instagramCtrl,
        saving: saving,
        errName: errName,
        errPhone: errPhone,
        errInstagram: errInstagram,
        onNameChanged: onNameChanged,
        onPhoneChanged: onPhoneChanged,
        onInstagramChanged: onInstagramChanged,
      );
    }
    return _AboutReadView(salon: salon);
  }
}

class _AboutReadView extends StatelessWidget {
  const _AboutReadView({required this.salon});

  final Salon salon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String? description = (salon.description?.trim().isNotEmpty ?? false)
        ? salon.description!.trim()
        : null;
    final String? phone = (salon.phone?.trim().isNotEmpty ?? false)
        ? salon.phone!.trim()
        : null;
    final String? instagram = (salon.instagramUrl?.isNotEmpty ?? false)
        ? salon.instagramUrl
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            description ?? l10n.salonAboutEmpty,
            key: const Key('salon-manage-about-text'),
            style: description == null
                ? VelvetText.feedback(BrandColors.muted)
                : VelvetText.bodyStrong(),
          ),
          if (phone != null || instagram != null) ...<Widget>[
            const SizedBox(height: VelvetSpacing.xl),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
              child: Text(
                l10n.masterContactsLabel,
                style: VelvetText.sectionLabel(),
              ),
            ),
            if (phone != null)
              ContactTile(
                key: const Key('salon-manage-contact-phone'),
                icon: Icons.phone_outlined,
                value: phone,
                semanticLabel: l10n.phoneLabel,
                // Dialing out is not in this phase's Implementation Steps —
                // editing (not calling) is the affordance this tab offers.
                onTap: () {},
              ),
            if (phone != null && instagram != null)
              const SizedBox(height: VelvetSpacing.sm + 2),
            if (instagram != null)
              ContactTile(
                key: const Key('salon-manage-contact-instagram'),
                icon: Icons.alternate_email,
                label: l10n.masterInstagramLabel,
                value: instagram,
                semanticLabel: l10n.masterInstagramLabel,
                onTap: () => _openInstagram(context, instagram),
              ),
          ],
        ],
      ),
    );
  }

  static Future<void> _openInstagram(
    BuildContext context,
    String rawValue,
  ) async {
    final Uri? uri = canonicalInstagramUri(rawValue);
    if (uri == null) {
      _showInstagramError(context);
      return;
    }
    bool launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      launched = false;
    }
    if (!context.mounted) return;
    if (!launched) _showInstagramError(context);
  }

  static void _showInstagramError(BuildContext context) {
    showErrorSnack(
      context,
      AppLocalizations.of(context).masterInstagramOpenError,
    );
  }
}

class _AboutEditForm extends StatelessWidget {
  const _AboutEditForm({
    required this.nameCtrl,
    required this.descCtrl,
    required this.phoneCtrl,
    required this.instagramCtrl,
    required this.saving,
    required this.errName,
    required this.errPhone,
    required this.errInstagram,
    required this.onNameChanged,
    required this.onPhoneChanged,
    required this.onInstagramChanged,
  });

  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController instagramCtrl;
  final bool saving;

  /// mobile-security LOW follow-up (2026-08-27) — inline field-validation
  /// error state; `null` renders no error.
  final String? errName;
  final String? errPhone;
  final String? errInstagram;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onPhoneChanged;
  final ValueChanged<String> onInstagramChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          VelvetField(
            fieldKey: const Key('field-salon-name'),
            label: l10n.salonManageNameLabel,
            controller: nameCtrl,
            enabled: !saving,
            maxLength: _salonNameMaxLength,
            errorText: errName,
            onChanged: onNameChanged,
          ),
          const SizedBox(height: VelvetSpacing.lg),
          VelvetField(
            fieldKey: const Key('field-salon-description'),
            label: l10n.salonManageDescriptionLabel,
            controller: descCtrl,
            enabled: !saving,
            maxLines: 4,
            maxLength: _salonDescriptionMaxLength,
            showCounter: true,
            optional: true,
          ),
          const SizedBox(height: VelvetSpacing.lg),
          VelvetField(
            fieldKey: const Key('field-salon-phone'),
            label: l10n.phoneLabel,
            controller: phoneCtrl,
            enabled: !saving,
            keyboardType: TextInputType.phone,
            maxLength: _salonPhoneMaxLength,
            optional: true,
            errorText: errPhone,
            onChanged: onPhoneChanged,
          ),
          const SizedBox(height: VelvetSpacing.lg),
          VelvetField(
            fieldKey: const Key('field-salon-instagram'),
            label: l10n.instagramLabel,
            controller: instagramCtrl,
            enabled: !saving,
            optional: true,
            prefixText: '@',
            maxLength: _salonInstagramMaxLength,
            errorText: errInstagram,
            onChanged: onInstagramChanged,
          ),
        ],
      ),
    );
  }
}

class _EditFooter extends StatelessWidget {
  const _EditFooter({
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: BrandColors.base,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: BrandColors.shadowDarkCard,
            offset: Offset(0, -9),
            blurRadius: 24,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.sm,
            VelvetSpacing.lg,
            VelvetSpacing.md,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextButton(
                  key: const Key('btn-salon-cancel-edit'),
                  onPressed: saving ? null : onCancel,
                  child: Text(l10n.masterCancelButton),
                ),
              ),
              const SizedBox(width: VelvetSpacing.md),
              Expanded(
                flex: 2,
                child: NeumorphicButton(
                  key: const Key('btn-salon-save-edit'),
                  label: l10n.masterSaveButton,
                  icon: Icons.check_rounded,
                  loading: saving,
                  onPressed: saving ? null : onSave,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Персонал tab — staff management grid
// ---------------------------------------------------------------------------

class _StaffTab extends StatelessWidget {
  const _StaffTab({
    required this.salonId,
    required this.staff,
    required this.onOpenMember,
    required this.onInvite,
  });

  final String salonId;
  final List<SalonStaffMember> staff;
  final ValueChanged<SalonStaffMember> onOpenMember;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (staff.isEmpty)
          Padding(
            key: const Key('salon-manage-staff-empty'),
            padding: const EdgeInsets.only(bottom: VelvetSpacing.md),
            child: Text(
              l10n.salonManageStaffEmpty,
              style: VelvetText.feedback(BrandColors.muted),
            ),
          ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: VelvetSpacing.md,
            crossAxisSpacing: VelvetSpacing.md,
            mainAxisExtent: kSalonMasterCardHeight,
          ),
          itemCount: staff.length + 1,
          itemBuilder: (BuildContext context, int i) {
            if (i == staff.length) {
              return _AddStaffTile(onTap: onInvite);
            }
            final SalonStaffMember member = staff[i];
            final bool isAdmin = member.role == SalonStaffRole.admin;
            final String? ownTitle = member.professionalTitle?.trim();
            // Phase 21.5 — the roster now includes admins (previously
            // masters-only): an admin has no professional title, so it
            // always shows the admin role label; a master falls back to the
            // generic salon-master label when no own title is set.
            final String role = isAdmin
                ? l10n.salonStaffRoleAdmin
                : (ownTitle != null && ownTitle.isNotEmpty)
                ? ownTitle
                : l10n.masterRoleSalonMaster;
            return SalonMasterCard(
              key: Key('salon-manage-staff-card-${member.userId}'),
              name: member.firstName,
              role: role,
              // Admins carry no service rating — always the placeholder.
              ratingLabel: !isAdmin && member.reviewCount > 0
                  ? (member.avgRating?.toStringAsFixed(1) ?? '—')
                  : '—',
              avatarIndex: i,
              onTap: () => onOpenMember(member),
            );
          },
        ),
      ],
    );
  }
}

/// The trailing "invite staff" tile, always the last cell in the «Персонал»
/// grid. Reuses [SalonMasterCard]'s exact shell dimensions
/// ([kSalonMasterCardHeight], `VelvetRadii.card`, `VelvetShadows.extrudedCard`)
/// so it sits flush with the real cards, but there is no existing production
/// "add tile" widget to reuse (the client-facing masters grid never has one) —
/// this is a small, genuinely new widget, private to this screen.
class _AddStaffTile extends StatefulWidget {
  const _AddStaffTile({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_AddStaffTile> createState() => _AddStaffTileState();
}

class _AddStaffTileState extends State<_AddStaffTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.salonManageAddStaffLabel,
      child: GestureDetector(
        key: const Key('salon-manage-add-staff'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: kSalonMasterCardHeight,
            decoration: BoxDecoration(
              color: BrandColors.base,
              borderRadius: BorderRadius.circular(VelvetRadii.card),
              boxShadow: _pressed ? null : VelvetShadows.extrudedCard,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.md - 2,
              vertical: VelvetSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Container(
                  height: 73,
                  width: 73,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: BrandColors.accent.withValues(alpha: 0.10),
                    border: Border.all(
                      color: BrandColors.accent.withValues(alpha: 0.55),
                      width: 1.4,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.add_rounded,
                      color: BrandColors.accentDeep,
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(height: VelvetSpacing.sm),
                Text(
                  l10n.salonManageAddStaffLabel,
                  style: VelvetText.subheading13Accent,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
// Послуги tab — reuses the same read the public profile uses
// ---------------------------------------------------------------------------

class _ServicesTab extends ConsumerWidget {
  const _ServicesTab({required this.salonId});

  final String salonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<List<SalonServiceCategoryEntry>> async = ref.watch(
      salonServiceCatalogProvider(salonId),
    );

    return async.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: VelvetSpacing.xl),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (Object e, _) => ErrorState(
        failure: e is Failure ? e : UnknownFailure(cause: e),
        onRetry: () => ref.invalidate(salonServiceCatalogProvider(salonId)),
      ),
      data: (List<SalonServiceCategoryEntry> categories) => categories.isEmpty
          ? Text(
              l10n.salonServicesEmpty,
              style: VelvetText.feedback(BrandColors.muted),
            )
          : SalonServicesAccordion(categories: categories),
    );
  }
}
