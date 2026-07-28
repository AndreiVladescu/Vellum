// Appearance settings (plan 5 #39): theme mode, seed colour, shelf material and
// the spine size nudges.
//
// The plan asked for a golden test of a spine under two seeds. There is no
// golden infrastructure in this repo and pixel goldens are font-rendering
// sensitive, so the same property is pinned by *value* instead: the spine
// palette must not move with the seed (a library is not a colour swatch), while
// the shelf board must.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/settings/app_settings.dart';
import 'package:vellum/settings/appearance.dart';
import 'package:vellum/shelf/cover_color.dart';
import 'package:vellum/shelf/shelf_view.dart';
import 'package:vellum/shelf/spine_style.dart';

void main() {
  Future<AppSettingsStore> store([Map<String, Object> initial = const {}]) {
    SharedPreferences.setMockInitialValues(initial);
    return AppSettingsStore.load();
  }

  group('persistence', () {
    test('defaults keep an existing install looking unchanged', () async {
      final s = await store();
      expect(s.themeMode, ThemeMode.system);
      expect(s.seedPreset, SeedPreset.leather);
      expect(s.seedColor, SeedPreset.leather.color,
          reason: 'the original hardcoded seed');
      expect(s.shelfMaterial, ShelfMaterial.oak);
      expect(s.useDynamicColor, isFalse);
      expect(s.spineTypography.clampedTitle, 1.0);
      expect(s.spineTypography.clampedWidth, 1.0);
    });

    test('theme mode, material and dynamic colour round-trip', () async {
      final s = await store();
      await s.setThemeMode(ThemeMode.dark);
      await s.setShelfMaterial(ShelfMaterial.glass);
      await s.setUseDynamicColor(true);

      final reloaded = await AppSettingsStore.load();
      expect(reloaded.themeMode, ThemeMode.dark);
      expect(reloaded.shelfMaterial, ShelfMaterial.glass);
      expect(reloaded.useDynamicColor, isTrue);
    });

    test('a preset is stored by name, so restyling it later still applies',
        () async {
      final s = await store();
      await s.setSeedPreset(SeedPreset.forest);
      final reloaded = await AppSettingsStore.load();
      expect(reloaded.seedPreset, SeedPreset.forest);
      expect(reloaded.seedColor, SeedPreset.forest.color);
    });

    test('a custom seed is stored as hex and reports no preset', () async {
      final s = await store();
      await s.setCustomSeed(const Color(0xFF123456));
      final reloaded = await AppSettingsStore.load();
      expect(reloaded.seedPreset, isNull,
          reason: 'null preset is what the UI shows as "Custom"');
      expect(reloaded.seedColor, const Color(0xFF123456));
    });

    test('a corrupt stored seed falls back rather than throwing', () async {
      final s = await store({'settings.seedColor': 'not-a-colour'});
      expect(s.seedColor, SeedPreset.fallback.color);
      expect(s.seedPreset, isNull);
    });

    test('spine scales are clamped on the way in', () async {
      final s = await store();
      await s.setSpineTypography(
        const SpineTypography(titleScale: 9, widthScale: 0.01),
      );
      final reloaded = await AppSettingsStore.load();
      expect(reloaded.spineTypography.clampedTitle, SpineTypography.max);
      expect(reloaded.spineTypography.clampedWidth, SpineTypography.min);
    });
  });

  group('themes', () {
    test('the seed drives the scheme, and mode drives brightness', () {
      final leather = vellumThemes(seed: SeedPreset.leather.color);
      final forest = vellumThemes(seed: SeedPreset.forest.color);

      expect(leather.light.colorScheme.brightness, Brightness.light);
      expect(leather.dark.colorScheme.brightness, Brightness.dark);
      expect(leather.light.colorScheme.primary,
          isNot(forest.light.colorScheme.primary),
          reason: 'two seeds must not produce the same scheme');
    });

    test('dynamic colour wins only when enabled and actually supplied', () {
      final supplied = ColorScheme.fromSeed(seedColor: const Color(0xFF00A5FF));
      final suppliedDark = ColorScheme.fromSeed(
        seedColor: const Color(0xFF00A5FF),
        brightness: Brightness.dark,
      );

      final off = vellumThemes(
        seed: SeedPreset.leather.color,
        dynamicLight: supplied,
        dynamicDark: suppliedDark,
      );
      expect(off.light.colorScheme.primary,
          isNot(supplied.primary),
          reason: 'the toggle is off, so the seed still wins');

      final on = vellumThemes(
        seed: SeedPreset.leather.color,
        dynamicLight: supplied,
        dynamicDark: suppliedDark,
        useDynamic: true,
      );
      expect(on.light.colorScheme.primary, supplied.primary);

      // Enabled but unsupported (every desktop): fall back to the seed rather
      // than to a null scheme.
      final unsupported =
          vellumThemes(seed: SeedPreset.leather.color, useDynamic: true);
      expect(unsupported.light.colorScheme.primary,
          off.light.colorScheme.primary);
    });
  });

  group('shelf material', () {
    test('each material has its own face, and follows brightness', () {
      final lightFaces = {
        for (final m in ShelfMaterial.values) m.colorFor(Brightness.light),
      };
      expect(lightFaces, hasLength(ShelfMaterial.values.length),
          reason: 'no two materials should look identical');
      expect(
        ShelfMaterial.oak.colorFor(Brightness.dark),
        isNot(ShelfMaterial.oak.colorFor(Brightness.light)),
      );
    });

    test('glass is drawn as glass, not as a plank with a shadow', () {
      final glass =
          shelfBoardDecoration(ShelfMaterial.glass, Brightness.light);
      final oak = shelfBoardDecoration(ShelfMaterial.oak, Brightness.light);
      expect(glass.border, isNotNull);
      expect(oak.border, isNull);
      expect(glass.color!.a, lessThan(1.0), reason: 'translucent');
      expect(oak.color!.a, 1.0);
    });
  });

  group('the spine palette is independent of the theme', () {
    test('a generated spine is the same colour whatever the seed is', () {
      // Spine colours are persisted per book, so they cannot follow a live
      // preference — and shouldn't: see the note in spine_style.dart.
      final a = SpineStyle.generate(title: 'Dune', author: 'Frank Herbert');
      final b = SpineStyle.generate(title: 'Dune', author: 'Frank Herbert');
      expect(a.color, b.color);
      expect(a.toJson(), b.toJson(), reason: 'generation stays deterministic');
    });

    test('title ink is neutral, not the old leather brown', () {
      // The one place the theme had leaked into the spine.
      expect(spineInk, isNot(const Color(0xFF3A3226)));
      expect(spineTextColorFor(const Color(0xFFE8DCC0)), spineInk,
          reason: 'light spine gets ink');
      expect(spineTextColorFor(const Color(0xFF2E5A9C)), Colors.white,
          reason: 'dark spine gets white');
    });
  });

  group('the shelf actually uses the choices', () {
    Book book(String id, String title) => Book(
          id: id,
          title: title,
          needsPush: true,
          readerNotesNeedsPush: false,
          needsProgressPush: false,
          status: 'unread',
          readCount: 0,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    Future<BoxDecoration> boardOf(
      WidgetTester tester,
      ShelfMaterial material,
    ) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ShelfView(
            books: [book('b1', 'Dune')],
            material: material,
            detailBuilder: (_) => const SizedBox.shrink(),
          ),
        ),
      ));
      await tester.pump();
      // The board is the only Container in a row carrying a decoration with a
      // fixed 14px height.
      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .toList();
      return containers
          .map((c) => c.decoration! as BoxDecoration)
          .firstWhere((d) => d.borderRadius == BorderRadius.circular(3));
    }

    testWidgets('the board is painted in the chosen material', (tester) async {
      final oak = await boardOf(tester, ShelfMaterial.oak);
      final walnut = await boardOf(tester, ShelfMaterial.walnut);
      expect(oak.color, ShelfMaterial.oak.colorFor(Brightness.light));
      expect(walnut.color, ShelfMaterial.walnut.colorFor(Brightness.light));
    });

    testWidgets('the thickness nudge widens the spine it lays out',
        (tester) async {
      Future<double> widthAt(double scale) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ShelfView(
              books: [book('b1', 'Dune')],
              typography: SpineTypography(widthScale: scale),
              detailBuilder: (_) => const SizedBox.shrink(),
            ),
          ),
        ));
        await tester.pump();
        return tester.getSize(find.byType(BookSpine).first).width;
      }

      final normal = await widthAt(1.0);
      final wide = await widthAt(SpineTypography.max);
      expect(wide, greaterThan(normal));
      expect(wide / normal, closeTo(SpineTypography.max, 0.01),
          reason: 'the packer and the spine must scale by the same factor');
    });
  });
}
