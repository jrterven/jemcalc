import 'package:flutter/material.dart';

/// Shared brand colors for Flutter, the native editor and the web editor.
abstract final class JemPalette {
  static const ruby = Color(0xffb9263d);

  static ColorScheme scheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ColorScheme.fromSeed(
      seedColor: ruby,
      brightness: brightness,
    ).copyWith(
      primary: dark ? const Color(0xffff8998) : ruby,
      onPrimary: dark ? const Color(0xff510c1e) : Colors.white,
      primaryContainer: dark
          ? const Color(0xff792137)
          : const Color(0xffffdadf),
      onPrimaryContainer: dark
          ? const Color(0xffffdadf)
          : const Color(0xff4d071a),
      secondary: dark ? const Color(0xffedb1be) : const Color(0xff8c4a56),
      onSecondary: dark ? const Color(0xff481b29) : Colors.white,
      secondaryContainer: dark
          ? const Color(0xff643845)
          : const Color(0xfffadee2),
      onSecondaryContainer: dark
          ? const Color(0xffffdce4)
          : const Color(0xff38131c),
      tertiary: dark ? const Color(0xffffb1a4) : const Color(0xffa54132),
      onTertiary: dark ? const Color(0xff4b160e) : Colors.white,
      tertiaryContainer: dark
          ? const Color(0xff763226)
          : const Color(0xffffdad3),
      onTertiaryContainer: dark
          ? const Color(0xffffdad3)
          : const Color(0xff3f0b04),
      surface: dark ? const Color(0xff000000) : const Color(0xfffffbfa),
      surfaceDim: dark ? const Color(0xff000000) : const Color(0xffeedddc),
      surfaceBright: dark ? const Color(0xff303030) : const Color(0xfffffbfa),
      surfaceContainerLowest: dark ? const Color(0xff000000) : Colors.white,
      surfaceContainerLow: dark
          ? const Color(0xff101010)
          : const Color(0xfffff3f1),
      surfaceContainer: dark
          ? const Color(0xff181818)
          : const Color(0xfffbe9e7),
      surfaceContainerHigh: dark
          ? const Color(0xff242424)
          : const Color(0xfff7e1df),
      surfaceContainerHighest: dark
          ? const Color(0xff303030)
          : const Color(0xfff0d5d3),
      onSurface: dark ? const Color(0xfff2f2f2) : const Color(0xff2d1b20),
      onSurfaceVariant: dark
          ? const Color(0xffc6c6c6)
          : const Color(0xff79545b),
      outline: dark ? const Color(0xff8f8f8f) : const Color(0xffa67f84),
      outlineVariant: dark ? const Color(0xff3a3a3a) : const Color(0xffedd7d8),
      surfaceTint: dark ? Colors.transparent : ruby,
    );
  }

  // Distinct hues identify curves; the rest of the UI keeps the red accent.
  static List<Color> curves(Brightness brightness) =>
      brightness == Brightness.dark
      ? const [
          Color(0xffff8292),
          Color(0xff56b4e9),
          Color(0xff4dd5a2),
          Color(0xfff4d35e),
        ]
      : const [
          Color(0xffc62e46),
          Color(0xff0072b2),
          Color(0xff008060),
          Color(0xff9d6500),
        ];

  static Map<String, String> editor(ColorScheme colors) {
    String hex(Color color) =>
        '#${color.toARGB32().toRadixString(16).substring(2)}';
    return {
      'bg': hex(
        colors.brightness == Brightness.dark
            ? colors.surface
            : colors.surfaceContainerLow,
      ),
      'fg': hex(colors.onSurface),
      'accent': hex(colors.primary),
      'onAccent': hex(colors.onPrimary),
      'key': hex(
        colors.brightness == Brightness.dark
            ? colors.surfaceContainerHigh
            : colors.surfaceContainerLowest,
      ),
      'keyHover': colors.brightness == Brightness.dark ? '#303030' : '#fff0f2',
      'keyPressed': colors.brightness == Brightness.dark
          ? '#484848'
          : '#ffdce2',
      'line': hex(colors.outlineVariant),
      'result': hex(
        Color.alphaBlend(
          colors.primaryContainer.withValues(alpha: .45),
          colors.brightness == Brightness.dark
              ? colors.surface
              : colors.surfaceContainerLow,
        ),
      ),
    };
  }
}
