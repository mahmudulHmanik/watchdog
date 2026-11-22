import 'package:material_ui/material_ui.dart';

/// Error overlay of the player. A [decoderFailure] offers the external player
/// ([onExternal]) and never shows an auto-skip countdown (the screen does not
/// start one either).
class PlayerErrorCard extends StatelessWidget {
  const PlayerErrorCard({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onClose,
    this.countdown,
    this.countdownLabel,
    this.hasNext = false,
    this.decoderFailure = false,
    this.onCancel,
    this.onSkip,
    this.onExternal,
  });

  final String message;
  final int? countdown;
  final String? countdownLabel;
  final bool hasNext;
  final bool decoderFailure;
  final VoidCallback onRetry;
  final VoidCallback onClose;
  final VoidCallback? onCancel;
  final VoidCallback? onSkip;
  final VoidCallback? onExternal;

  @override
  Widget build(BuildContext context) => Center(
    child: Card(
      margin: const EdgeInsets.all(24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
            if (countdown != null && !decoderFailure) ...[
              const SizedBox(height: 8),
              Text('$countdownLabel in ${countdown}s'),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
                if (decoderFailure && onExternal != null)
                  FilledButton.tonal(
                    key: const Key('error-external'),
                    onPressed: onExternal,
                    child: const Text('Open in external player'),
                  ),
                if (countdown != null && !decoderFailure)
                  TextButton(onPressed: onCancel, child: const Text('Cancel')),
                if (hasNext)
                  TextButton(onPressed: onSkip, child: const Text('Skip')),
                TextButton(onPressed: onClose, child: const Text('Close')),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
