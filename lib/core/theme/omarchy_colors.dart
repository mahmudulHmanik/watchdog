/// Omarchy `colors.toml` -> app palette. Pure Dart (no Flutter binding).
library;

import 'dart:math' show pow;

import 'package:material_ui/material_ui.dart';

import 'palettes.dart';

double _lin(double c) =>
    c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();

/// WCAG relative luminance.
double luminance(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

/// WCAG contrast ratio, 1..21.
double contrast(Color a, Color b) {
  final la = luminance(a), lb = luminance(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [a] moved [t] (0..1) of the way towards [b].
Color blend(Color a, Color b, double t) => Color.from(
  alpha: 1,
  red: a.r + (b.r - a.r) * t,
  green: a.g + (b.g - a.g) * t,
  blue: a.b + (b.b - a.b) * t,
);

Color? parseHex(String s) {
  var h = s.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

class OmarchyColors {
  const OmarchyColors(this.values, {this.dark = true});
  final Map<String, Color> values;
  final bool dark;

  Color? operator [](String k) => values[k];

  /// Tolerant: unknown keys, bad lines, comments and bad colours are ignored.
  factory OmarchyColors.parse(String text) {
    final out = <String, Color>{};
    var dark = true;
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('[')) {
        continue;
      }
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      var val = line.substring(eq + 1).trim();
      final hash = val.indexOf(RegExp(r'"\s+#'));
      if (hash > 0) val = val.substring(0, hash + 1);
      if (val.length >= 2 &&
          (val.startsWith('"') && val.endsWith('"') ||
              val.startsWith("'") && val.endsWith("'"))) {
        val = val.substring(1, val.length - 1);
      }
      if (key == 'mode') {
        dark = val.toLowerCase() != 'light';
        continue;
      }
      final c = parseHex(val);
      if (c != null) out[key] = c;
    }
    return OmarchyColors(out, dark: dark);
  }

  /// Null when background/foreground are missing.
  AppPalette? toPalette({String name = 'Omarchy', String id = 'omarchy'}) {
    final bg = this['background'], fg = this['foreground'];
    if (bg == null || fg == null) return null;
    final bar =
        this['darker_background'] ??
        blend(bg, dark ? const Color(0xFF000000) : fg, 0.25);
    var card = this['lighter_background'] ?? blend(bg, fg, 0.06);
    if (card == bg) card = blend(bg, fg, 0.06);
    var hi = this['selection'] ?? blend(bg, fg, 0.12);
    if (hi == card || hi == bg) hi = blend(card, fg, 0.10);
    final border = blend(bg, fg, 0.25);
    var muted = this['muted'];
    if (muted == null || contrast(muted, bg) < 4.5) {
      // ~35% towards bg; ease back towards fg until it reads (>= 4.5).
      var t = 0.35;
      muted = blend(fg, bg, t);
      while (contrast(muted!, bg) < 4.5 && t > 0) {
        t -= 0.05;
        muted = blend(fg, bg, t < 0 ? 0 : t);
      }
    }

    var accent = this['accent'] ?? this['blue'] ?? fg;
    if (contrast(accent, bg) < 3) {
      for (final k in const ['bright_blue', 'blue']) {
        final c = this[k];
        if (c != null && contrast(c, bg) > contrast(accent, bg)) {
          accent = c;
          if (contrast(accent, bg) >= 3) break;
        }
      }
    }
    // Last resort: ease the accent towards the foreground until it reads.
    for (var t = 0.1; contrast(accent, bg) < 3 && t <= 1; t += 0.1) {
      accent = blend(accent, fg, t);
    }
    final darkBar = this['darker_background'] ?? bg;
    var onAccent = contrast(darkBar, accent) >= contrast(fg, accent)
        ? darkBar
        : fg;
    if (contrast(onAccent, accent) < 4.5) {
      // Pure black/white always reaches >= 4.58 against any colour.
      const black = Color(0xFF000000), white = Color(0xFFFFFFFF);
      onAccent = contrast(black, accent) >= contrast(white, accent)
          ? black
          : white;
    }
    return AppPalette(
      id: id,
      name: name,
      dark: dark,
      bg: bg,
      bar: bar,
      card: card,
      highlight: hi,
      border: border,
      text: fg,
      muted: muted,
      accent: accent,
      onAccent: onAccent,
      ok: this['green'] ?? const Color(0xFF50A14F),
      error: this['red'] ?? const Color(0xFFE45649),
    );
  }
}
