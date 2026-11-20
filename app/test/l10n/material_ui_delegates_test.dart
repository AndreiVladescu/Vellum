// The framework's own strings (tooltips, pickers, menus) in the app's language.
//
// Since Flutter 3.50 the widgets come from package:material_ui, which looks its
// localizations up by its own types. gen-l10n still emits the SDK's
// flutter_localizations delegates, which material_ui never reads, so Vellum
// passes appLocalizationsDelegates (lib/l10n/delegates.dart) instead. These
// pin that down for Romanian: the app's strings from app_ro.arb and
// material_ui's Romanian Material strings, side by side in one MaterialApp.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/l10n/delegates.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';

Widget _app({
  required List<LocalizationsDelegate<dynamic>> delegates,
  required Widget home,
  Locale locale = const Locale('ro'),
}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: delegates,
      supportedLocales: L10n.supportedLocales,
      home: home,
    );

void main() {
  testWidgets('Romanian: app strings and material_ui strings both resolve',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_app(
      delegates: appLocalizationsDelegates,
      home: Builder(builder: (context) {
        ctx = context;
        return const SizedBox.shrink();
      }),
    ));
    expect(L10n.of(ctx).localeName, 'ro');
    expect(L10n.of(ctx).addBook, lookupL10n(const Locale('ro')).addBook);
    final material = MaterialLocalizations.of(ctx);
    expect(material.backButtonTooltip, 'Înapoi');
    expect(material.cancelButtonLabel, 'Anulați');
    expect(material.datePickerHelpText, 'Selectați data');
    expect(Directionality.of(ctx), TextDirection.ltr);
  });

  testWidgets('a Romanian tooltip and date picker', (tester) async {
    await tester.pumpWidget(_app(
      delegates: appLocalizationsDelegates,
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(leading: const BackButton()),
          body: TextButton(
            onPressed: () => showDatePicker(
              context: context,
              initialDate: DateTime(2026, 11, 20),
              firstDate: DateTime(2000),
              lastDate: DateTime(2030),
            ),
            child: const Text('pick'),
          ),
        ),
      ),
    ));
    expect(find.byTooltip('Înapoi'), findsOneWidget);

    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    expect(find.text('Selectați data'), findsOneWidget);
    expect(find.text('Anulați'), findsOneWidget);
    // The calendar's header names the month in Romanian.
    expect(find.textContaining('noiembrie'), findsWidgets);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('English still gets English framework strings', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_app(
      locale: const Locale('en'),
      delegates: appLocalizationsDelegates,
      home: Builder(builder: (context) {
        ctx = context;
        return const SizedBox.shrink();
      }),
    ));
    expect(MaterialLocalizations.of(ctx).backButtonTooltip, 'Back');
    expect(MaterialLocalizations.of(ctx).cancelButtonLabel, 'Cancel');
  });

  testWidgets('gen-l10n\'s own delegates give material_ui nothing in Romanian',
      (tester) async {
    // Why delegates.dart exists. MaterialApp's built-in fallback is English
    // only, so with the legacy delegates a Romanian app has no
    // MaterialLocalizations at all, and the first tooltip or picker throws.
    // If this starts failing, gen-l10n has learnt to emit material_ui's
    // delegates and appLocalizationsDelegates can go.
    late BuildContext ctx;
    await tester.pumpWidget(_app(
      delegates: L10n.localizationsDelegates,
      home: Builder(builder: (context) {
        ctx = context;
        return const SizedBox.shrink();
      }),
    ));
    // In debug builds the framework says so as soon as the app is built.
    expect(
      tester.takeException().toString(),
      contains('is not supported by all of its localization delegates'),
    );
    expect(L10n.of(ctx).localeName, 'ro');
    expect(
      Localizations.of<MaterialLocalizations>(ctx, MaterialLocalizations),
      isNull,
    );
  });
}
