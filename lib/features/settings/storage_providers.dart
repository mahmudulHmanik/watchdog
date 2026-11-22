import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:watchdog/platform/platform_api.dart';

/// What the app stores on disk. Re-read by `ref.invalidate` (Library page
/// opens and after each clear action). Errors surface as AsyncError.
final storageUsageProvider = FutureProvider.autoDispose<StorageUsage>(
  (ref) => ref.watch(platformApiProvider).storageUsage(),
  // Show the failure at once (with a Retry button) instead of silent
  // exponential-backoff retries.
  retry: (_, _) => null,
);
