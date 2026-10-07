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
      surface: dark ? const Color(0xff1a1114) : const Color(0xfffffbfa),
      surfaceDim: dark ? const Color(0xff1a1114) : const Color(0xffeedddc),
      surfaceBright: dark ? const Color(0xff422c33) : const Color(0xfffffbfa),
      surfaceContainerLowest: dark ? const Color(0xff140d10) : Colors.white,
      surfaceContainerLow: dark
          ? const Color(0xff23161a)
          : const Color(0xfffff3f1),
      surfaceContainer: dark
          ? const Color(0xff2c1c21)
          : const Color(0xfffbe9e7),
      surfaceContainerHigh: dark
          ? const Color(0xff362329)
          : const Color(0xfff7e1df),
      surfaceContainerHighest: dark
          ? const Color(0xff422c33)
          : const Color(0xfff0d5d3),
      onSurface: dark ? const Color(0xfff8e9ec) : const Color(0xff2d1b20),
      onSurfaceVariant: dark
          ? const Color(0xffdabdc3)
          : const Color(0xff79545b),
      outline: dark ? const Color(0xff9e7f87) : const Color(0xffa67f84),
      outlineVariant: dark ? const Color(0xff52343d) : const Color(0xffedd7d8),
      surfaceTint: dark ? const Color(0xffff8998) : ruby,
    );
  }

  static List<Color> curves(Brightness brightness) =>
      brightness == Brightness.dark
      ? const [
          Color(0xffff8292),
          Color(0xffffb0a6),
          Color(0xffe66d99),
          Color(0xffbf869b),
        ]
      : const [
          Color(0xffc62e46),
          Color(0xffc55242),
          Color(0xff983860),
          Color(0xff631d37),
        ];

  static Map<String, String> editor(ColorScheme colors) {
    String hex(Color color) =>
        '#${color.toARGB32().toRadixString(16).substring(2)}';
    return {
      'bg': hex(colors.surfaceContainerLow),
      'fg': hex(colors.onSurface),
      'accent': hex(colors.primary),
      'onAccent': hex(colors.onPrimary),
      'key': hex(
        colors.brightness == Brightness.dark
            ? colors.surfaceContainerHigh
            : colors.surfaceContainerLowest,
      ),
      'line': hex(colors.outlineVariant),
    };
  }
}
