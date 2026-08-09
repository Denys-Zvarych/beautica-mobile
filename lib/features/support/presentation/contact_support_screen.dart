// "Напишіть нам" — the logged-in support / contact screen. Reached from the
// "Допомога" row in the master settings hub. The user sends the team a free-text
// message (+ optional subject + 0..5 attachments); the backend forwards it to
// support via `POST /api/v1/support/contact` (multipart). Identity is taken from
// the JWT, never from the form.
//
// State: a single [SupportController] drives idle → sending → success | error.
// The screen swaps the form for the success card on success and surfaces a
// failure as a localized error VelvetSnack + an inline reset to the editable
// state.
//
// Layout is a plain Column (no entrance animation — the staggered reveal lives
// in settings_hub_screen.dart). Per-keystroke rebuilds are scoped: MessageArea
// repaints its own counter, and only the footer Send button rebuilds when the
// Send-enabled boolean flips (driven by the `_canSendNotifier` ValueNotifier).
//
// Security: the message field is user content → screenshot protection acquired
// via the app-wide ref-counted ScreenProtectionManager (captured in initState,
// released in dispose — `ref` is never touched in dispose under Riverpod 3.x).
// The message body / tokens are never logged.
//
// Design source: `docs/signup-designs/ContactSupport/lib/screens/
// contact_support_screen.dart` — ported 1:1, swapping the preview's mock picker
// + faked send for the real file_picker + SupportController, and VelvetColors →
// BrandColors, all copy → l10n, the imperative back for go_router.

import 'dart:developer';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/section_scaffold.dart';
import 'package:beautica_mobile/features/support/domain/support_attachment.dart';
import 'package:beautica_mobile/features/support/domain/support_limits.dart';
import 'package:beautica_mobile/features/support/presentation/support_controller.dart';
import 'package:beautica_mobile/features/support/presentation/widgets/attachment_tray.dart';
import 'package:beautica_mobile/features/support/presentation/widgets/message_area.dart';
import 'package:beautica_mobile/features/support/presentation/widgets/support_success_card.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_selectors.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The support-contact screen.
class ContactSupportScreen extends ConsumerStatefulWidget {
  const ContactSupportScreen({super.key});

  @override
  ConsumerState<ContactSupportScreen> createState() =>
      _ContactSupportScreenState();
}

class _ContactSupportScreenState extends ConsumerState<ContactSupportScreen> {
  final TextEditingController _subject = TextEditingController();
  final TextEditingController _message = TextEditingController();
  final List<SupportAttachment> _attachments = <SupportAttachment>[];

  // Drives ONLY the footer Send button. Flips when message validity / attachment
  // budget crosses a threshold — not on every keystroke. A ValueListenableBuilder
  // around the Send button is the sole listener, so typing rebuilds nothing but
  // MessageArea's own counter.
  final ValueNotifier<bool> _canSendNotifier = ValueNotifier<bool>(false);

  bool _submitAttempted = false;

  // Tracks whether the inline message error row is currently shown, so
  // `_onMessageChanged` only rebuilds the parent on the show↔hide transition.
  bool _errorVisible = false;

  // Captured in initState so dispose() never touches `ref` — under Riverpod 3.x
  // using `ref` in dispose() throws.
  late final ScreenProtectionManager _screenProtection;

  static const _tag = 'feature.support.screen';

  @override
  void initState() {
    super.initState();
    // The message field is user content (PII-adjacent) → acquire the app-wide
    // screenshot guard while this screen is mounted.
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
    _message.addListener(_onMessageChanged);
  }

  @override
  void dispose() {
    _message.removeListener(_onMessageChanged);
    _canSendNotifier.dispose();
    _screenProtection.release();
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  void _onMessageChanged() {
    // Per-keystroke work is intentionally minimal: MessageArea repaints its own
    // counter, and the only screen-level reaction is flipping the Send-enabled
    // notifier when validity crosses the 10/5000 threshold.
    _refreshCanSend();

    // After a failed submit, the inline error row (an `errorText` prop on
    // MessageArea) must clear once the user types past the minimum. That prop
    // is parent-owned, so rebuild — but ONLY on the transition (error shown →
    // hidden or back), never on every keystroke.
    if (_submitAttempted) {
      final bool errorVisible =
          _messageError(AppLocalizations.of(context)) != null;
      if (errorVisible != _errorVisible && mounted) {
        setState(() => _errorVisible = errorVisible);
      }
    }
  }

  /// Recompute Send-enabled and push it to [_canSendNotifier]. The notifier
  /// only notifies its [ValueListenableBuilder] when the boolean actually
  /// changes, so steady-state typing rebuilds nothing here.
  void _refreshCanSend() {
    final state = ref.read(supportControllerProvider);
    _canSendNotifier.value = _canSend(state is SupportSubmitSending);
  }

  int get _messageLength => _message.text.characters.length;

  int get _totalBytes =>
      _attachments.fold<int>(0, (int s, SupportAttachment a) => s + a.size);

  bool get _messageValid =>
      _messageLength >= SupportLimits.minMessage &&
      _messageLength <= SupportLimits.maxMessage;

  bool get _overBudget => _totalBytes > SupportLimits.maxTotalBytes;

  bool _canSend(bool sending) => _messageValid && !_overBudget && !sending;

  String? _messageError(AppLocalizations l10n) {
    if (!_submitAttempted) return null;
    if (_messageLength == 0) return l10n.contactSupportErrMessageEmpty;
    if (_messageLength < SupportLimits.minMessage) {
      return l10n.contactSupportErrMessageTooShort(SupportLimits.minMessage);
    }
    return null;
  }

  Future<void> _pickAttachment() async {
    final l10n = AppLocalizations.of(context);
    if (_attachments.length >= SupportLimits.maxFiles) return;

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: SupportLimits.extensionContentTypes.keys.toList(
          growable: false,
        ),
        withData: true,
        allowMultiple: false,
      );
    } catch (e, st) {
      if (kDebugMode) {
        log('attachment pick failed', name: _tag, level: 900, stackTrace: st);
      }
      if (!mounted) return;
      _showSnack(l10n.contactSupportErrPickFailed);
      return;
    }

    if (result == null || result.files.isEmpty) return; // user cancelled
    if (!mounted) return;

    final PlatformFile file = result.files.first;
    final Uint8List? bytes = file.bytes;
    if (bytes == null) {
      _showSnack(l10n.contactSupportErrPickFailed);
      return;
    }

    final String ext = (file.extension ?? '').toLowerCase();
    final String? contentType = SupportLimits.extensionContentTypes[ext];
    if (contentType == null ||
        !SupportLimits.allowedContentTypes.contains(contentType)) {
      _showSnack(l10n.contactSupportErrWrongType);
      return;
    }
    if (bytes.length > SupportLimits.maxFileBytes) {
      _showSnack(l10n.contactSupportErrFileTooBig);
      return;
    }
    if (_attachments.length >= SupportLimits.maxFiles) {
      _showSnack(l10n.contactSupportErrTooManyFiles(SupportLimits.maxFiles));
      return;
    }

    final SupportAttachmentKind kind = contentType == 'application/pdf'
        ? SupportAttachmentKind.pdf
        : SupportAttachmentKind.image;

    setState(() {
      _attachments.add(
        SupportAttachment(
          name: file.name,
          bytes: bytes,
          contentType: contentType,
          kind: kind,
        ),
      );
    });
    _refreshCanSend(); // budget may now exceed → Send can flip off
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
    _refreshCanSend(); // budget may now drop under → Send can flip back on
  }

  void _showSnack(String message) {
    showErrorSnack(context, message);
  }

  Future<void> _send() async {
    setState(() {
      _submitAttempted = true;
      _errorVisible = _messageError(AppLocalizations.of(context)) != null;
    });
    final state = ref.read(supportControllerProvider);
    if (!_canSend(state is SupportSubmitSending)) return;

    await ref
        .read(supportControllerProvider.notifier)
        .submit(
          message: _message.text,
          subject: _subject.text,
          attachments: List<SupportAttachment>.unmodifiable(_attachments),
        );
  }

  void _onBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.masterMenu);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(supportControllerProvider);

    // Surface a submission failure as an error snack, then reset to editable.
    ref.listen<SupportSubmitState>(supportControllerProvider, (prev, next) {
      if (next is SupportSubmitError) {
        _showSnack(next.failure.userMessage(context));
        ref.read(supportControllerProvider.notifier).reset();
      }
    });

    if (state is SupportSubmitSuccess) {
      // Release the attachment byte buffers (up to 25 MB) now that the send
      // succeeded — the State stays mounted behind the success card until the
      // user pops, so without this the buffers linger for the screen's life.
      if (_attachments.isNotEmpty) {
        _attachments.clear();
      }
      final String? email = ref.read(currentUserProvider)?.email;
      return SectionScaffold(
        title: l10n.contactSupportTitle,
        backKey: const Key('support-back'),
        backSemanticLabel: l10n.contactSupportBack,
        onBack: _onBack,
        body: Padding(
          padding: const EdgeInsets.only(top: VelvetSpacing.xxl),
          child: SupportSuccessCard(email: email, onDone: _onBack),
        ),
      );
    }

    final bool sending = state is SupportSubmitSending;

    // Keep the Send-enabled notifier in sync with the controller state (the
    // `!sending` term). Typing-driven updates flow through `_onMessageChanged`.
    _canSendNotifier.value = _canSend(sending);

    return SectionScaffold(
      title: l10n.contactSupportTitle,
      backKey: const Key('support-back'),
      backSemanticLabel: l10n.contactSupportBack,
      onBack: _onBack,
      footer: ValueListenableBuilder<bool>(
        valueListenable: _canSendNotifier,
        builder: (BuildContext context, bool canSend, _) => NeumorphicButton(
          key: const Key('support-send'),
          label: l10n.contactSupportSend,
          icon: Icons.send_rounded,
          loading: sending,
          onPressed: canSend ? _send : null,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _Intro(),
          const SizedBox(height: VelvetSpacing.lg),
          NeumorphicTextField(
            key: const Key('support-subject'),
            label: l10n.contactSupportSubjectLabel,
            controller: _subject,
            hintText: l10n.contactSupportSubjectHint,
            maxLength: SupportLimits.maxSubject,
            textInputAction: TextInputAction.next,
            prefixIcon: const Icon(Icons.label_outline_rounded),
          ),
          const SizedBox(height: VelvetSpacing.lg),
          MessageArea(
            fieldKey: const Key('support-message'),
            label: l10n.contactSupportMessageLabel,
            controller: _message,
            minLength: SupportLimits.minMessage,
            maxLength: SupportLimits.maxMessage,
            hintText: l10n.contactSupportMessageHint,
            errorText: _messageError(l10n),
            helperText: l10n.contactSupportMessageHelper(
              SupportLimits.minMessage,
            ),
          ),
          const SizedBox(height: VelvetSpacing.lg),
          AttachmentTray(
            attachments: _attachments,
            onAdd: _pickAttachment,
            onRemove: _removeAttachment,
            maxFiles: SupportLimits.maxFiles,
            maxTotalBytes: SupportLimits.maxTotalBytes,
          ),
        ],
      ),
    );
  }
}

/// The screen's quiet opening: a short explanation + the promise that the reply
/// comes by email.
class _Intro extends StatelessWidget {
  const _Intro();

  static const BoxDecoration _badgeDecoration = BoxDecoration(
    color: BrandColors.base,
    shape: BoxShape.circle,
    boxShadow: VelvetShadows.extrudedSmall,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NeumorphicCard(
      padding: const EdgeInsets.all(VelvetSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 46,
            width: 46,
            decoration: _badgeDecoration,
            child: const Icon(
              Icons.help_outline_rounded,
              color: BrandColors.accent,
              size: 24,
            ),
          ),
          const SizedBox(width: VelvetSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.contactSupportIntroTitle,
                  style: VelvetText.subheading(),
                ),
                const SizedBox(height: VelvetSpacing.xs + 2),
                Text(l10n.contactSupportIntroBody, style: VelvetText.body()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
