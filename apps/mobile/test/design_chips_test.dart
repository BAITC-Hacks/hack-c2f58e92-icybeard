import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/theme/tokens.dart';
import 'package:darumen/widgets/app_card.dart';
import 'package:darumen/widgets/origin_tag.dart';
import 'package:darumen/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {String locale = 'ru', double textScale = 1.0, double width = 360}) => MaterialApp(
      theme: AppTheme.light(),
      locale: Locale(locale),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale), size: Size(width, 800)),
        child: Scaffold(body: Center(child: SizedBox(width: width, child: child))),
      ),
    );

/// Фон и цвет текста чипа, найденного по подписи.
(Color?, Color?) chipColors(WidgetTester tester, String label) {
  final box = tester.widget<Container>(find.ancestor(of: find.text(label), matching: find.byType(Container)).first);
  final text = tester.widget<Text>(find.text(label));
  return ((box.decoration as BoxDecoration?)?.color, text.style?.color);
}

void main() {
  group('StatusChip', () {
    testWidgets('capitalises the first letter of the dictionary label in both languages', (tester) async {
      await tester.pumpWidget(host(const Column(children: [
        StatusChip('риск отказа', tone: StatusTone.danger),
        StatusChip('бас тарту қаупі', tone: StatusTone.danger),
        StatusChip('> 30 дней'),
      ])));
      expect(find.text('Риск отказа'), findsOneWidget);
      expect(find.text('Бас тарту қаупі'), findsOneWidget);
      expect(find.text('> 30 дней'), findsOneWidget);
      expect(find.text('риск отказа'), findsNothing);
    });

    testWidgets('eight tones take their pairs from AppTones: info = accent, ai and bench = the quiet pill', (tester) async {
      final c = ColorTokens.light;
      final expected = {
        StatusTone.neutral: (c.surfaceSunken, c.muted),
        StatusTone.ok: (c.okSoft, c.ok),
        StatusTone.warn: (c.warnSoft, c.warn),
        StatusTone.danger: (c.dangerSoft, c.danger),
        StatusTone.accent: (c.accentSoft, c.accentHover),
        StatusTone.info: (c.accentSoft, c.accentHover),
        StatusTone.ai: (c.neutralSoft, c.muted),
        StatusTone.bench: (c.neutralSoft, c.muted),
      };
      expect(expected.keys.toSet(), StatusTone.values.toSet(), reason: 'каждый тон проверен');
      await tester.pumpWidget(host(Column(children: [for (final tone in StatusTone.values) StatusChip('тон ${tone.name}', tone: tone)])));
      for (final entry in expected.entries) {
        expect(chipColors(tester, 'Тон ${entry.key.name}'), entry.value, reason: entry.key.name);
      }
    });

    testWidgets('the positional constructor keeps working with the default neutral tone and an icon', (tester) async {
      await tester.pumpWidget(host(const StatusChip('ожидает', icon: Icons.schedule)));
      expect(find.text('Ожидает'), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      expect(chipColors(tester, 'Ожидает'), (ColorTokens.light.surfaceSunken, ColorTokens.light.muted));
    });

    testWidgets('ToneChip shows the label as given (origin tags stay lowercase)', (tester) async {
      await tester.pumpWidget(host(const ToneChip(label: 'прогноз модели', fg: ColorTokens.white, bg: ColorTokens.shadow)));
      expect(find.text('прогноз модели'), findsOneWidget);
    });
  });

  group('OriginTag', () {
    testWidgets('russian labels follow the web and stay lowercase', (tester) async {
      await tester.pumpWidget(host(const Wrap(children: [OriginTag(Origin.ml), OriginTag(Origin.formula), OriginTag(Origin.ai)])));
      expect(find.text('прогноз модели'), findsOneWidget);
      expect(find.text('расчёт по правилу'), findsOneWidget);
      expect(find.text('черновик ИИ'), findsOneWidget);
      expect(find.text('ML-модель'), findsNothing);
    });

    testWidgets('kazakh labels follow the web', (tester) async {
      await tester.pumpWidget(host(const Wrap(children: [OriginTag(Origin.ml), OriginTag(Origin.formula), OriginTag(Origin.ai)]), locale: 'kk'));
      expect(find.text('модель болжамы'), findsOneWidget);
      expect(find.text('ереже бойынша есеп'), findsOneWidget);
      expect(find.text('ЖИ жобасы'), findsOneWidget);
    });

    testWidgets('tap opens a sheet with the label as a 19/800 sheet title and the web tooltip as the note', (tester) async {
      await tester.pumpWidget(host(const OriginTag(Origin.ml)));
      await tester.tap(find.text('прогноз модели'));
      await tester.pumpAndSettle();
      expect(find.text('Число предсказала компьютерная модель по истории очередей. Это оценка, а не обещание'), findsOneWidget);
      final title = tester.widget<Text>(find.text('прогноз модели').last);
      expect(title.style?.fontSize, 19);
      expect(title.style?.fontWeight, FontWeight.w800);
    });

    testWidgets('formula and ai notes, and a caller note that overrides the default', (tester) async {
      await tester.pumpWidget(host(const Column(children: [OriginTag(Origin.formula), OriginTag(Origin.ai, note: 'Своё пояснение')])));
      await tester.tap(find.text('расчёт по правилу'));
      await tester.pumpAndSettle();
      expect(find.text('Число посчитано по заранее известному правилу или формуле, без предсказаний'), findsOneWidget);
      Navigator.of(tester.element(find.text('расчёт по правилу').last)).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('черновик ИИ'));
      await tester.pumpAndSettle();
      expect(find.text('Своё пояснение'), findsOneWidget);
    });

    testWidgets('semantics read the label and the note as one button', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(const OriginTag(Origin.formula)));
      expect(
        find.bySemanticsLabel('расчёт по правилу. Число посчитано по заранее известному правилу или формуле, без предсказаний'),
        findsOneWidget,
      );
      handle.dispose();
    });

    test('tag rules: model-or-rule blocks always carry a tag, model-only blocks only when the model answered', () {
      expect(originModelOrRule(true), Origin.ml);
      expect(originModelOrRule(false), Origin.formula);
      expect(originModelOnly(true), Origin.ml);
      expect(originModelOnly(false), isNull);
    });

    testWidgets('the longer kazakh label fits next to a kicker at 1.3x on a 360 dp phone', (tester) async {
      await tester.pumpWidget(host(
        const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: CardLabel('емдеуге жатқызуға дейінгі күту мерзімі', trailing: OriginTag(Origin.formula)),
        ),
        locale: 'kk',
        textScale: 1.3,
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
