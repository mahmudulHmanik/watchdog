import 'package:material_ui/material_ui.dart';

/// Omarchy palette tokens (CLAUDE.md "Themes").
class AppPalette {
  const AppPalette({
    required this.id,
    required this.name,
    required this.dark,
    required this.bg,
    required this.bar,
    required this.card,
    required this.highlight,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.ok,
    required this.error,
  });
  final String id;
  final String name;
  final bool dark;
  final Color bg,
      bar,
      card,
      highlight,
      border,
      text,
      muted,
      accent,
      onAccent,
      ok,
      error;
}

const tokyoNight = AppPalette(
  id: 'tokyo',
  name: 'Tokyo Night',
  dark: true,
  bg: Color(0xFF1A1B26),
  bar: Color(0xFF16161E),
  card: Color(0xFF24283B),
  highlight: Color(0xFF292E42),
  border: Color(0xFF414868),
  text: Color(0xFFC0CAF5),
  muted: Color(0xFF9AA5CE),
  accent: Color(0xFF7AA2F7),
  onAccent: Color(0xFF16161E),
  ok: Color(0xFF9ECE6A),
  error: Color(0xFFF7768E),
);

const everforest = AppPalette(
  id: 'everforest',
  name: 'Everforest',
  dark: true,
  bg: Color(0xFF2D353B),
  bar: Color(0xFF232A2E),
  card: Color(0xFF343F44),
  highlight: Color(0xFF3D484D),
  border: Color(0xFF56635F),
  text: Color(0xFFD3C6AA),
  muted: Color(0xFFA6B0A0),
  accent: Color(0xFFA7C080),
  onAccent: Color(0xFF232A2E),
  ok: Color(0xFFA7C080),
  error: Color(0xFFE67E80),
);

const catppuccinLatte = AppPalette(
  id: 'latte',
  name: 'Catppuccin Latte',
  dark: false,
  bg: Color(0xFFEFF1F5),
  bar: Color(0xFFE6E9EF),
  card: Color(0xFFE6E9EF),
  highlight: Color(0xFFDCE0E8),
  border: Color(0xFFBCC0CC),
  text: Color(0xFF4C4F69),
  muted: Color(0xFF5C5F77),
  accent: Color(0xFF1E66F5),
  onAccent: Color(0xFFEFF1F5),
  ok: Color(0xFF40A02B),
  error: Color(0xFFD20F39),
);

const allPalettes = [everforest, tokyoNight, catppuccinLatte];
