// Phase 1.5 — Generic error state widget.
//
// Used by every screen's `AsyncValue.error` branch. Renders a centered
// error icon, a localized message from the `Failure`, and an optional
// retry button. All spacing uses `AppSpacing` tokens — no magic numbers.
//
// The widget is stateless; retry logic lives in the calling notifier.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/app_spacing.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Displays a localized error message derived from [failure] and an optional
/// [onRetry] callback rendered as a [FilledButton].
///
/// Intended for use in the `error` branch of `AsyncValue.when`:
/// ```dart
/// error: (e, _) => ErrorState(
///   failure: e is Failure ? e : UnknownFailure(cause: e),
///   onRetry: () => ref.invalidate(someProvider),
/// )
/// ```
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.failure, this.onRetry});

  /// The domain failure describing what went wrong.
  final Failure failure;

  /// Optional callback invoked when the user taps "Retry".
  ///
  /// When `null`, the retry button is omitted entirely.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              failure.userMessage(context),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                key: const Key('error_state_retry_button'),
                onPressed: onRetry,
                child: Text(l10n.retryLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
