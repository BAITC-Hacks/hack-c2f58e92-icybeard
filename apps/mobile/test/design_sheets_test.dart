import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/theme/tokens.dart';
import 'package:darumen/widgets/org_name.dart';
import 'package:darumen/widgets/picker_sheet.dart';
import 'package:darumen/widgets/pill_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {String locale = 'ru', double textScale = 1.0}) => MaterialApp(
      theme: AppTheme.light(),
      locale: Locale(locale),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale), size: const Size(360, 780)),
        child: Scaffold(body: Center(child: SizedBox(width: 360, child: child))),
      ),
    );

const regions = [PickerItem('75', 'г. Алматы'), PickerItem('71', 'г. Астана', detail: 'столица'), PickerItem('11', 'Акмолинская область')];

void main() {
  final c = ColorTokens.light;

  testWidgets('SheetHeader: title 19/800 and a 13.5 text-secondary subtitle', (tester) async {
    await tester.pumpWidget(host(const SheetHeader('Регион', subtitle: 'Откуда считать очереди')));
    final title = tester.widget<Text>(find.text('Регион'));
    expect(title.style?.fontSize, 19);
    expect(title.style?.fontWeight, FontWeight.w800);
    final subtitle = tester.widget<Text>(find.text('Откуда считать очереди'));
    expect(subtitle.style?.fontSize, 13.5);
    expect(subtitle.style?.color, c.muted);
  });

  testWidgets('showInfoSheet opens a bottom sheet with the header and the body', (tester) async {
    await tester.pumpWidget(host(Builder(
      builder: (context) => TextButton(onPressed: () => showInfoSheet(context, title: 'Как считается', body: const Text('по правилу')), child: const Text('open')),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.widget<Text>(find.text('Как считается')).style?.fontSize, 19);
    expect(find.text('по правилу'), findsOneWidget);
  });

  testWidgets('picker: the sheet title uses the sheet header; the selected option is surface-hover, ink 800 and a check', (tester) async {
    await tester.pumpWidget(host(Builder(
      builder: (context) => TextButton(onPressed: () => PickerSheet.show<String>(context, title: 'Регион', items: regions, selected: '71'), child: const Text('open')),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text('Регион')).style?.fontSize, 19);
    final selected = tester.widget<ListTile>(find.ancestor(of: find.text('г. Астана'), matching: find.byType(ListTile)));
    expect(selected.selected, isTrue);
    final theme = Theme.of(tester.element(find.text('г. Астана')));
    expect(theme.listTileTheme.selectedTileColor, c.surfaceHover);
    expect(theme.listTileTheme.selectedColor, c.ink, reason: 'текст выбранной опции остаётся --text');
    final title = tester.widget<Text>(find.text('г. Астана'));
    expect(title.style?.fontWeight, FontWeight.w800);
    expect(find.byIcon(Icons.check), findsOneWidget);
    final other = tester.widget<Text>(find.text('г. Алматы'));
    expect(other.style?.fontWeight, isNot(FontWeight.w800));
  });

  testWidgets('picker and info sheets open on the root navigator, above a nested one (the tab pill stays under them)', (tester) async {
    final nested = GlobalKey<NavigatorState>();
    await tester.pumpWidget(host(SizedBox(
      height: 600,
      child: Navigator(
        key: nested,
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (context) => Column(children: [
            TextButton(onPressed: () => PickerSheet.show<String>(context, title: 'Регион', items: regions), child: const Text('picker')),
            TextButton(onPressed: () => showInfoSheet(context, title: 'Как считается', body: const Text('по правилу')), child: const Text('info')),
          ]),
        ),
      ),
    )));
    final root = tester.state<NavigatorState>(find.byType(Navigator).first);
    expect(root, isNot(nested.currentState));

    await tester.tap(find.text('picker'));
    await tester.pumpAndSettle();
    expect(Navigator.of(tester.element(find.byType(PickerSheet<String>))), root);
    await tester.tap(find.text('г. Астана'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('info'));
    await tester.pumpAndSettle();
    expect(Navigator.of(tester.element(find.text('по правилу'))), root);
  });

  testWidgets('picker search: nothing found shows the empty line', (tester) async {
    await tester.pumpWidget(host(Builder(
      builder: (context) => TextButton(onPressed: () => PickerSheet.show<String>(context, title: 'Регион', items: regions), child: const Text('open')),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'нет такого');
    await tester.pumpAndSettle();
    expect(find.text('Ничего не найдено'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'столица');
    await tester.pumpAndSettle();
    expect(find.text('г. Астана'), findsOneWidget, reason: 'поиск и по второй строке');
  });

  testWidgets('org name sheet: short name as the sheet title, the label and the full legal name', (tester) async {
    const name = 'Товарищество с ограниченной ответственностью "Достар Мед"';
    await tester.pumpWidget(host(const OrgName(name)));
    await tester.tap(find.byType(OrgName));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text('Достар Мед').last).style?.fontSize, 19);
    expect(find.text('Полное юридическое название'), findsOneWidget);
    expect(find.text(name), findsOneWidget);
  });

  testWidgets('pill filter: the active pill is accent-soft, taps report the value', (tester) async {
    String? chosen;
    await tester.pumpWidget(host(PillFilter<String>(items: const [('today', 'Сегодня'), ('all', 'Все')], selected: 'today', onChanged: (v) => chosen = v)));
    final active = tester.widget<Material>(find.ancestor(of: find.text('Сегодня'), matching: find.byType(Material)).first);
    expect(active.color, c.accentSoft);
    await tester.tap(find.text('Все'));
    expect(chosen, 'all');
  });

  testWidgets('picker row and sheet in kazakh at 1.3x do not overflow', (tester) async {
    await tester.pumpWidget(host(
      Builder(
        builder: (context) => Column(children: [
          PickerRow(label: 'Төсек бейіні', value: 'Ересектерге арналған хирургиялық', detail: 'жылына 11 330 078 рецепт', onTap: () {}),
          TextButton(onPressed: () => PickerSheet.show<String>(context, title: 'Ересектерге арналған төсек бейіні', items: regions, selected: '75'), child: const Text('open')),
        ]),
      ),
      locale: 'kk',
      textScale: 1.3,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
