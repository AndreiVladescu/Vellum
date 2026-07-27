import 'package:flutter/material.dart';

/// The look of the app, as choices rather than constants (plan 5 #39).
///
/// Vellum's whole point is visual, and until now the only thing the user could
/// change was the wallpaper: the theme was one hardcoded leather-brown seed and
/// the shelf boards were two hardcoded browns. Everything here is a value in
/// `AppSettingsStore`, so a preference can move the whole app rather than one
/// screen.

/// Curated theme seeds. A picker of arbitrary colours produces mostly bad
/// schemes, so the presets come first and "custom" is the escape hatch.
enum SeedPreset {
  leather('Leather', Color(0xFF7A5C3E)),
  ink('Ink', Color(0xFF3B4C8F)),
  forest('Forest', Color(0xFF3C6B4B)),
  slate('Slate', Color(0xFF56626D)),
  plum('Plum', Color(0xFF7A3E63)),
  ember('Ember', Color(0xFFA8482C));

  const SeedPreset(this.label, this.color);

  final String label;
  final Color color;

  /// The original hardcoded seed, so an existing install looks unchanged until
  /// someone deliberately picks otherwise.
  static const fallback = SeedPreset.leather;
}

/// What the shelf boards are made of. Extends the wallpaper mechanism: the
/// wallpaper is the wall behind the shelf, this is the shelf itself.
enum ShelfMaterial {
  oak('Oak', Color(0xFFB09B82), Color(0xFF4A4038)),
  walnut('Walnut', Color(0xFF8C6A4E), Color(0xFF3A2C22)),
  ebony('Ebony', Color(0xFF4A443F), Color(0xFF221F1D)),
  painted('Painted', Color(0xFFE8E2D8), Color(0xFF3E4247)),
  metal('Metal', Color(0xFFB8BEC4), Color(0xFF52585E)),
  glass('Glass', Color(0x66C9D6DE), Color(0x593C4A55));

  const ShelfMaterial(this.label, this._light, this._dark);

  final String label;
  final Color _light;
  final Color _dark;

  /// The board's face colour for the current brightness.
  Color colorFor(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  /// Glass is the one material that isn't a solid plank: it takes a hairline
  /// edge and a far softer shadow, because a sheet of glass with an oak
  /// drop-shadow under it reads as a mistake rather than as glass.
  bool get isTranslucent => this == ShelfMaterial.glass;

  static const fallback = ShelfMaterial.oak;
}

/// How a shelf board is painted, given its material and the current theme.
///
/// Lives here rather than in `shelf_view.dart` so the digital shelf and any
/// future surface that draws a board can't drift apart.
BoxDecoration shelfBoardDecoration(
  ShelfMaterial material,
  Brightness brightness,
) {
  final dark = brightness == Brightness.dark;
  final face = material.colorFor(brightness);
  if (material.isTranslucent) {
    return BoxDecoration(
      color: face,
      borderRadius: BorderRadius.circular(3),
      border: Border.all(
        color: Colors.white.withValues(alpha: dark ? 0.16 : 0.55),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.28 : 0.12),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }
  return BoxDecoration(
    color: face,
    borderRadius: BorderRadius.circular(3),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.5 : 0.25),
        blurRadius: 4,
        offset: const Offset(0, 3),
      ),
    ],
  );
}

/// Multipliers the user can nudge, for shelves that feel too cramped or too
/// sparse. Clamped rather than free: a spine at 3× stops being a spine.
class SpineTypography {
  const SpineTypography({this.titleScale = 1.0, this.widthScale = 1.0});

  /// Scales the title painted down the spine (base size 13).
  final double titleScale;

  /// Scales the spine's thickness, which is otherwise page-count-driven.
  final double widthScale;

  static const min = 0.8;
  static const max = 1.4;

  static const normal = SpineTypography();

  double get clampedTitle => titleScale.clamp(min, max);
  double get clampedWidth => widthScale.clamp(min, max);
}

/// The theme pair for a seed, or for a platform-supplied dynamic scheme.
///
/// [dynamicLight]/[dynamicDark] come from Material You on Android and are null
/// everywhere else; when present *and* enabled they win over [seed], because a
/// user who switched Material You on is asking for the system's colour rather
/// than ours.
({ThemeData light, ThemeData dark}) vellumThemes({
  required Color seed,
  ColorScheme? dynamicLight,
  ColorScheme? dynamicDark,
  bool useDynamic = false,
}) {
  final useIt = useDynamic && dynamicLight != null && dynamicDark != null;
  ThemeData build(Brightness brightness, ColorScheme? dynamicScheme) =>
      ThemeData(
        colorScheme: useIt
            ? dynamicScheme!
            : ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
        // Guarantee >=48dp tap targets on every platform (not just the mobile
        // default) so touch/accessibility targets are always reachable.
        materialTapTargetSize: MaterialTapTargetSize.padded,
      );
  return (
    light: build(Brightness.light, dynamicLight),
    dark: build(Brightness.dark, dynamicDark),
  );
}
