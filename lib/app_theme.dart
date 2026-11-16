import 'package:flutter/material.dart';

/// Имена палитр — стабильные строковые ключи, сохраняемые в настройках.
const appThemeNames = ['Бежевая', 'Коричневая', 'OLED', 'Светлая', 'Тёмная'];

const defaultAppThemeName = 'Светлая';

/// Единые метрики для всех строк ввода. Значения не зависят от конкретного
/// экрана, поэтому поиск, числовые параметры и обычные поля не расходятся по
/// толщине контура, кеглю и внутреннему воздуху.
const povarnyaInputBorderWidth = 1.0;
const povarnyaInputHorizontalPadding = 10.0;
const povarnyaInputVerticalPadding = 7.0;
const povarnyaInputFontSize = 16.0;
const povarnyaSearchBarHeight = 42.0;

bool isKnownAppThemeName(String value) => appThemeNames.contains(value);

/// Единственные шесть исходных цветовых ролей темы.
///
/// Поверхности, контуры и цвет текста не добавляют в тему скрытых оттенков:
/// они вычисляются из этих ролей и чёрного/белого.
@immutable
class PovarnyaPalette {
  const PovarnyaPalette({
    required this.brightness,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.success,
    required this.warning,
    required this.error,
  });

  final Brightness brightness;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color success;
  final Color warning;
  final Color error;

  List<Color> get sourceColors => [
    primary,
    secondary,
    tertiary,
    success,
    warning,
    error,
  ];

  static const black = Color(0xff000000);
  static const white = Color(0xffffffff);

  bool get isDark => brightness == Brightness.dark;

  /// Выбирает чёрный либо белый по большей контрастности с фоном.
  Color on(Color background) => contrastColorFor(background);

  Color _mix(Color background, Color tint, double opacity) =>
      Color.alphaBlend(tint.withValues(alpha: opacity), background);

  Color get surfaceBase => isDark ? black : white;
  Color get surface => _mix(surfaceBase, primary, isDark ? .11 : .035);
  Color get surfaceLow => _mix(surface, primary, isDark ? .05 : .025);
  Color get surfaceContainer => _mix(surface, primary, isDark ? .10 : .06);
  Color get surfaceHigh => _mix(surface, primary, isDark ? .16 : .10);
  Color get surfaceHighest => _mix(surface, primary, isDark ? .22 : .15);
  Color get outline => _mix(surface, on(surface), isDark ? .62 : .48);
  Color get outlineVariant => _mix(surface, on(surface), isDark ? .28 : .18);
  Color get inverseSurface => isDark ? white : black;

  Color container(Color accent) => _mix(surface, accent, isDark ? .30 : .16);

  ColorScheme get colorScheme {
    final primaryContainer = container(primary);
    final secondaryContainer = container(secondary);
    final tertiaryContainer = container(tertiary);
    final errorContainer = container(error);
    return ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: on(primary),
      primaryContainer: primaryContainer,
      onPrimaryContainer: on(primaryContainer),
      primaryFixed: primary,
      primaryFixedDim: primary,
      onPrimaryFixed: on(primary),
      onPrimaryFixedVariant: on(primary),
      secondary: secondary,
      onSecondary: on(secondary),
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: on(secondaryContainer),
      secondaryFixed: secondary,
      secondaryFixedDim: secondary,
      onSecondaryFixed: on(secondary),
      onSecondaryFixedVariant: on(secondary),
      tertiary: tertiary,
      onTertiary: on(tertiary),
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: on(tertiaryContainer),
      tertiaryFixed: tertiary,
      tertiaryFixedDim: tertiary,
      onTertiaryFixed: on(tertiary),
      onTertiaryFixedVariant: on(tertiary),
      error: error,
      onError: on(error),
      errorContainer: errorContainer,
      onErrorContainer: on(errorContainer),
      surface: surface,
      onSurface: on(surface),
      surfaceDim: surfaceLow,
      surfaceBright: surfaceHigh,
      surfaceContainerLowest: surfaceBase,
      surfaceContainerLow: surfaceLow,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHighest,
      onSurfaceVariant: on(surfaceHigh),
      outline: outline,
      outlineVariant: outlineVariant,
      shadow: black,
      scrim: black,
      inverseSurface: inverseSurface,
      onInverseSurface: on(inverseSurface),
      inversePrimary: primary,
      surfaceTint: primary,
    );
  }
}

/// Семантические цвета доступны элементам, которым недостаточно стандартного
/// `ColorScheme.error`: успеху, предупреждению и ошибке.
@immutable
class PovarnyaSemanticColors extends ThemeExtension<PovarnyaSemanticColors> {
  const PovarnyaSemanticColors({
    required this.success,
    required this.warning,
    required this.error,
  });

  final Color success;
  final Color warning;
  final Color error;

  @override
  PovarnyaSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? error,
  }) => PovarnyaSemanticColors(
    success: success ?? this.success,
    warning: warning ?? this.warning,
    error: error ?? this.error,
  );

  @override
  PovarnyaSemanticColors lerp(
    covariant PovarnyaSemanticColors? other,
    double t,
  ) {
    if (other == null) return this;
    return PovarnyaSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
    );
  }
}

const _palettes = <String, PovarnyaPalette>{
  'Бежевая': PovarnyaPalette(
    brightness: Brightness.light,
    primary: Color(0xffa64100),
    secondary: Color(0xff2f6b3d),
    tertiary: Color(0xff355c9b),
    success: Color(0xff177245),
    warning: Color(0xffa55f00),
    error: Color(0xffba1a1a),
  ),
  'Коричневая': PovarnyaPalette(
    brightness: Brightness.dark,
    primary: Color(0xffffb4a0),
    secondary: Color(0xff91d6b0),
    tertiary: Color(0xffaec6ff),
    success: Color(0xff9de2b2),
    warning: Color(0xffffd27a),
    error: Color(0xffffb4ab),
  ),
  'OLED': PovarnyaPalette(
    brightness: Brightness.dark,
    primary: Color(0xffffb1c1),
    secondary: Color(0xff7de3c3),
    tertiary: Color(0xffb9c4ff),
    success: Color(0xff8be9a8),
    warning: Color(0xffffd166),
    error: Color(0xffffb4ab),
  ),
  'Светлая': PovarnyaPalette(
    brightness: Brightness.light,
    primary: Color(0xff2764a8),
    secondary: Color(0xff16815f),
    tertiary: Color(0xff8b3d8f),
    success: Color(0xff247a45),
    warning: Color(0xffa66300),
    error: Color(0xffba1a1a),
  ),
  'Тёмная': PovarnyaPalette(
    brightness: Brightness.dark,
    primary: Color(0xffb5ccff),
    secondary: Color(0xff8de0b5),
    tertiary: Color(0xfff0b2e9),
    success: Color(0xff9ae7a8),
    warning: Color(0xffffd27a),
    error: Color(0xffffb4ab),
  ),
};

PovarnyaPalette appPalette(String themeName) =>
    _palettes[themeName] ?? _palettes[defaultAppThemeName]!;

ThemeData appTheme(String themeName) {
  final palette = appPalette(themeName);
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(
      width: povarnyaInputBorderWidth,
      color: palette.outline,
    ),
  );
  return ThemeData(
    // Файл шрифта лежит в assets и упаковывается Flutter в bundle, поэтому
    // одинаково выглядит на Linux, Android, Windows и без системной установки.
    fontFamily: 'Yeseva One',
    colorScheme: palette.colorScheme,
    scaffoldBackgroundColor: palette.surface,
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: povarnyaInputHorizontalPadding,
        vertical: povarnyaInputVerticalPadding,
      ),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(
          width: povarnyaInputBorderWidth,
          color: palette.primary,
        ),
      ),
      errorBorder: inputBorder.copyWith(
        borderSide: BorderSide(
          width: povarnyaInputBorderWidth,
          color: palette.error,
        ),
      ),
      focusedErrorBorder: inputBorder.copyWith(
        borderSide: BorderSide(
          width: povarnyaInputBorderWidth,
          color: palette.error,
        ),
      ),
    ),
    searchBarTheme: SearchBarThemeData(
      constraints: const BoxConstraints(minHeight: povarnyaSearchBarHeight),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: povarnyaInputHorizontalPadding),
      ),
      side: WidgetStatePropertyAll(
        BorderSide(width: povarnyaInputBorderWidth, color: palette.outline),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: povarnyaInputFontSize),
      ),
      hintStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: povarnyaInputFontSize),
      ),
    ),
    extensions: [
      PovarnyaSemanticColors(
        success: palette.success,
        warning: palette.warning,
        error: palette.error,
      ),
    ],
    useMaterial3: true,
  );
}

PovarnyaSemanticColors semanticColors(BuildContext context) =>
    Theme.of(context).extension<PovarnyaSemanticColors>()!;

/// Формула WCAG выбирает самый контрастный из чистого чёрного и белого.
Color contrastColorFor(Color background) {
  final luminance = background.computeLuminance();
  final blackContrast = (luminance + .05) / .05;
  final whiteContrast = 1.05 / (luminance + .05);
  return blackContrast >= whiteContrast
      ? PovarnyaPalette.black
      : PovarnyaPalette.white;
}
