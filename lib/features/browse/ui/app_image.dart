import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/features/browse/image_store.dart';

/// The one network image widget (posters, backdrops, profile photos): serves
/// from the capped disk cache ([ImageStore]) and downloads on a miss. Shows
/// [fallback] while loading, offline, or when the image is broken; never
/// throws.
class AppImage extends ConsumerStatefulWidget {
  const AppImage(
    this.url, {
    super.key,
    required this.fallback,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  final String url;
  final Widget fallback;
  final double? width, height;
  final BoxFit fit;

  /// Decode width in physical pixels (keeps decoded bitmaps small).
  final int? cacheWidth;

  @override
  ConsumerState<AppImage> createState() => _AppImageState();
}

class _AppImageState extends ConsumerState<AppImage> {
  File? _file;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(AppImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _file = null;
      _resolve();
    }
  }

  void _resolve() {
    final store = ref.read(imageStoreProvider);
    final url = widget.url;
    _file = store.peek(url);
    if (_file != null) return;
    store.fetch(url).then((f) {
      if (!mounted || widget.url != url || f == null) return;
      setState(() => _file = f);
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = _file;
    if (f == null) return widget.fallback;
    return Image.file(
      f,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => widget.fallback,
    );
  }
}
