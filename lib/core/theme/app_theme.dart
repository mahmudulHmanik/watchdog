import 'package:material_ui/material_ui.dart';

import 'palettes.dart';

enum ShapeMode { box, rounded }

/// Extra palette tokens + shape flag for custom widgets.
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens(this.palette, this.box);
  final AppPalette palette;
  final bool box;

  Color get badge => palette.bar.withValues(alpha: 0.9);
  Color get okBg => palette.ok.withValues(alpha: 0.18);
  Color get hi => palette.highlight;
  Color get border => palette.border;
  Color get accent => palette.accent;

  /// Radius for cards/thumbs in this shape mode.
  BorderRadius radius([double r = 12]) =>
      box ? BorderRadius.zero : BorderRadius.circular(r);

  /// Selected look: Box = transparent + 2px accent border; Rounded = hi fill.
  BoxDecoration selected({double r = 12}) => BoxDecoration(
    color: box ? Colors.transparent : palette.highlight,
    border: Border.all(color: palette.accent, width: box ? 2 : 1),
    borderRadius: radius(r),
  );

  BoxDecoration plain({double r = 12, Color? color}) => BoxDecoration(
    color: color,
    border: Border.all(color: palette.border),
    borderRadius: radius(r),
  );

  @override
  AppTokens copyWith() => this;
  @override
  AppTokens lerp(AppTokens? other, double t) => other ?? this;
}

extension AppTokensX on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;
}

/// Bundled families (assets/fonts, variable). Old system names stay only as
/// fallbacks; scripts the fonts lack fall through to system fonts.
const _boxFallback = ['CaskaydiaMono Nerd Font', 'JetBrains Mono', 'monospace'];
const _roundedFallback = <String>[];

/// Builds the Material 3 theme for [p] in shape mode [s].
ThemeData buildTheme(AppPalette p, ShapeMode s) {
  final box = s == ShapeMode.box;
  final scheme = ColorScheme(
    brightness: p.dark ? Brightness.dark : Brightness.light,
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.accent,
    onSecondary: p.onAccent,
    tertiary: p.ok,
    onTertiary: p.onAccent,
    error: p.error,
    onError: p.onAccent,
    surface: p.bg,
    onSurface: p.text,
    onSurfaceVariant: p.muted,
    surfaceContainerLowest: p.bar,
    surfaceContainerLow: p.card,
    surfaceContainer: p.card,
    surfaceContainerHigh: p.highlight,
    surfaceContainerHighest: p.highlight,
    outline: p.border,
    outlineVariant: p.border,
  );

  final r = box ? BorderRadius.zero : BorderRadius.circular(12);
  final shape = RoundedRectangleBorder(borderRadius: r);
  final selectedBorder = BorderSide(color: p.accent, width: 2);
  final plainBorder = BorderSide(color: p.border);
  OutlinedBorder chipShape = box
      ? const RoundedRectangleBorder()
      : const StadiumBorder();

  return ThemeData(
    useMaterial3: true,
    extensions: [AppTokens(p, box)],
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    fontFamily: box ? 'JetBrainsMono' : 'Inter',
    fontFamilyFallback: box ? _boxFallback : _roundedFallback,
    appBarTheme: AppBarThemeData(
      backgroundColor: p.bar,
      foregroundColor: p.text,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: p.bar,
      indicatorColor: box ? Colors.transparent : p.highlight,
      indicatorShape: box
          ? RoundedRectangleBorder(side: selectedBorder)
          : const StadiumBorder(),
      iconTheme: WidgetStateProperty.resolveWith(
        (st) => IconThemeData(
          color: st.contains(WidgetState.selected) ? p.accent : p.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (st) => TextStyle(
          fontSize: 12,
          fontWeight: st.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: st.contains(WidgetState.selected) ? p.accent : p.muted,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: p.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: r, side: plainBorder),
    ),
    chipTheme: ChipThemeData(
      shape: chipShape,
      backgroundColor: p.card,
      selectedColor: box ? Colors.transparent : p.accent,
      checkmarkColor: box ? p.accent : p.onAccent,
      labelStyle: TextStyle(color: p.text),
      secondaryLabelStyle: TextStyle(color: box ? p.accent : p.onAccent),
      showCheckmark: false,
      side: WidgetStateBorderSide.resolveWith(
        (st) => st.contains(WidgetState.selected)
            ? BorderSide(color: p.accent, width: box ? 2 : 1)
            : plainBorder,
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: p.card,
      border: OutlineInputBorder(borderRadius: r, borderSide: plainBorder),
      enabledBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: plainBorder,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: p.accent, width: box ? 2 : 1),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: shape),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape,
        side: BorderSide(color: p.border),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: shape),
    ),
    listTileTheme: ListTileThemeData(
      shape: shape,
      selectedColor: p.accent,
      iconColor: p.muted,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      shape: RoundedRectangleBorder(borderRadius: r, side: plainBorder),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      constraints: const BoxConstraints(maxWidth: double.infinity),
      backgroundColor: p.card,
      showDragHandle: !box,
      shape: box
          ? Border(top: selectedBorder)
          : const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.highlight,
      contentTextStyle: TextStyle(color: p.text),
      shape: shape,
    ),
    dividerTheme: DividerThemeData(color: p.border, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
  );
}
