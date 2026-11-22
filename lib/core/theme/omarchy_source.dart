/// Locating, loading and watching the active Omarchy theme.
library;

import 'dart:async';
import 'dart:io';

import 'palettes.dart';
import 'omarchy_colors.dart';

/// Active Omarchy theme: derived palette + display name.
class OmarchyState {
  const OmarchyState(this.palette, this.name);
  final AppPalette palette;
  final String? name;
}

/// Paths under `$XDG_STATE_HOME/omarchy/current` (default `~/.local/state`).
class OmarchyLocator {
  OmarchyLocator(this.root);
  final Directory root; // .../omarchy

  /// Null when HOME/XDG_STATE_HOME are unknown.
  static OmarchyLocator? fromEnv([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    final xdg = e['XDG_STATE_HOME'];
    final home = e['HOME'];
    final base = (xdg != null && xdg.isNotEmpty)
        ? xdg
        : (home == null ? null : '$home/.local/state');
    return base == null ? null : OmarchyLocator(Directory('$base/omarchy'));
  }

  Directory get current => Directory('${root.path}/current');
  Directory get themeDir => Directory('${current.path}/theme');
  File get colors => File('${themeDir.path}/colors.toml');
  File get nameFile => File('${current.path}/theme.name');

  bool get exists => colors.existsSync();

  /// Never throws: null when absent or unparsable.
  OmarchyState? load() {
    try {
      final p = OmarchyColors.parse(colors.readAsStringSync()).toPalette();
      if (p == null) return null;
      String? name;
      try {
        name = nameFile.readAsStringSync().trim();
        if (name.isEmpty) name = null;
      } catch (_) {}
      return OmarchyState(p, name);
    } catch (_) {
      return null;
    }
  }
}

/// Watches `current/` and `current/theme/` (the theme dir may be swapped via
/// symlink or rewritten), debounced; re-subscribes after every change and
/// retries with backoff on errors/missing dirs.
class OmarchyWatcher {
  OmarchyWatcher(
    this.locator,
    this.onChange, {
    this.debounce = const Duration(milliseconds: 300),
    this.maxBackoff = const Duration(seconds: 30),
  }) {
    _subscribe();
  }

  final OmarchyLocator locator;
  final void Function() onChange;
  final Duration debounce;
  final Duration maxBackoff;

  final _subs = <StreamSubscription<FileSystemEvent>>[];
  Timer? _debounce, _retry;
  var _backoff = const Duration(seconds: 1);
  var _disposed = false;

  void _cancelSubs() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  void _subscribe() {
    if (_disposed) return;
    _cancelSubs();
    var ok = false;
    for (final d in [locator.current, locator.themeDir]) {
      try {
        if (!d.existsSync()) continue;
        _subs.add(d.watch().listen((_) => _poke(), onError: (_) => _fail()));
        ok = true;
      } catch (_) {
        // try again via backoff
      }
    }
    if (ok) {
      _backoff = const Duration(seconds: 1);
    } else {
      _fail();
    }
  }

  void _fail() {
    if (_disposed) return;
    _cancelSubs();
    _retry?.cancel();
    _retry = Timer(_backoff, () {
      _subscribe();
      onChange(); // dir may have reappeared
    });
    final next = _backoff * 2;
    _backoff = next > maxBackoff ? maxBackoff : next;
  }

  void _poke() {
    _debounce?.cancel();
    _debounce = Timer(debounce, () {
      if (_disposed) return;
      _subscribe(); // re-resolve paths (symlink swap)
      onChange();
    });
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _retry?.cancel();
    _cancelSubs();
  }
}
