import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/features/index/index_providers.dart';
import 'package:watchdog/features/index/index_service.dart';

import 'index_format.dart';
import 'index_sheet.dart';

/// Slim, non-blocking indexing bar: one status line plus a thin progress bar.
/// Shown while a run is going; show/hide is debounced so quick state changes
/// do not flicker. Tap opens the per-category sheet.
class IndexBanner extends ConsumerStatefulWidget {
  const IndexBanner({
    super.key,
    this.debounce = const Duration(milliseconds: 300),
  });
  final Duration debounce;

  @override
  ConsumerState<IndexBanner> createState() => _IndexBannerState();
}

class _IndexBannerState extends ConsumerState<IndexBanner> {
  late bool _shown;
  IndexState? _last;
  Timer? _timer;

  bool _running() => ref.read(indexStateProvider).value?.running ?? false;

  @override
  void initState() {
    super.initState();
    _shown = _running(); // no delay when mounted mid-run
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _sync(bool want) {
    if (want == _shown) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer(widget.debounce, () {
        _timer = null;
        if (mounted) setState(() => _shown = _running());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(indexStateProvider).value;
    if (s != null && s.running) _last = s;
    _sync(s?.running ?? false);
    final show = _shown ? _last : null;
    if (show == null) return const SizedBox.shrink();
    final t = context.tokens;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final label = indexLabel(show);
    return Semantics(
      container: true,
      label: label,
      child: InkWell(
        key: const Key('index-banner'),
        onTap: () => showIndexSheet(context),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.palette.bar,
            border: Border(bottom: BorderSide(color: t.border)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ),
                    Icon(Icons.expand_less, size: 16, color: muted),
                  ],
                ),
              ),
              LinearProgressIndicator(
                value: indexBarValue(show),
                minHeight: 2,
                backgroundColor: t.border,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
