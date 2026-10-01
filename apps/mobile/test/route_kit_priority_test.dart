import 'package:darumen/l10n/strings.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/theme/tokens.dart';
import 'package:darumen/theme/tones.dart';
import 'package:darumen/widgets/route/priority_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Приоритет рабочего списка по фиксированной шкале API 0…10 (PriorityBadge.vue): число в пилюле 32, полосы 7–10 /
/// 4–6 / 0–3 постоянные, доступная подпись «уровень · N из 10».
Widget host(Widget child, {String locale = 'ru', double textScale = 1.0}) => MaterialApp(
      theme: AppTheme.light(),
      locale: Locale(locale),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale), size: const Size(360, 800)),
        child: Scaffold(body: Center(child: SizedBox(width: 296, child: Row(children: [child, const Expanded(child: Text('SYN-75-224E-171-01'))])))),
      ),
    );

final tones = AppTones.from(ColorTokens.light);

Color? badgeColor(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(find.descendant(of: find.byType(PriorityBadge), matching: find.byType(DecoratedBox)).first);
  final decoration = box.decoration;
  return switch (decoration) {
    ShapeDecoration(:final color) => color,
    BoxDecoration(:final color) => color,
    _ => null,
  };
}

void main() {
  group('шкала приоритета', () {
    test('число округляется и зажимается в 0…10; нечисло — 0', () {
      expect(priorityScore(8.4), 8);
      expect(priorityScore(8.5), 9);
      expect(priorityScore(-3), 0);
      expect(priorityScore(12), 10);
      expect(priorityScore(652), 10, reason: 'старые фикстуры с «652» не ломают шкалу');
      expect(priorityScore(double.nan), 0);
      expect(priorityScore(double.infinity), 10);
    });

    test('полосы постоянные: 7–10 высокий, 4–6 средний, 0–3 низкий', () {
      expect([for (var n = 0; n <= 10; n++) priorityBandOf(n)], [
        PriorityBand.low,
        PriorityBand.low,
        PriorityBand.low,
        PriorityBand.low,
        PriorityBand.mid,
        PriorityBand.mid,
        PriorityBand.mid,
        PriorityBand.high,
        PriorityBand.high,
        PriorityBand.high,
        PriorityBand.high,
      ]);
    });
  });

  group('PriorityBadge', () {
    testWidgets('высокий приоритет: число, danger-пара, подсказка и доступная подпись «Высокий приоритет · 8 из 10»', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(const PriorityBadge(8)));
      expect(find.text('8'), findsOneWidget);
      expect(badgeColor(tester), tones.danger.bg);
      expect(tester.widget<Text>(find.text('8')).style?.color, tones.danger.fg);
      expect(find.bySemanticsLabel('Высокий приоритет · 8 из 10'), findsOneWidget);
      expect(find.byTooltip('Высокий приоритет · 8 из 10'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('средний и низкий — warn и ok; KK-подпись «Орташа басымдық · 10 ішінен 5»', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(const PriorityBadge(5), locale: 'kk'));
      expect(badgeColor(tester), tones.warn.bg);
      expect(find.bySemanticsLabel('Орташа басымдық · 10 ішінен 5'), findsOneWidget);
      await tester.pumpWidget(host(const PriorityBadge(2.6)));
      expect(find.text('3'), findsOneWidget);
      expect(badgeColor(tester), tones.ok.bg);
      expect(find.bySemanticsLabel('Низкий приоритет · 3 из 10'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('кружок не меньше 32×32 и не растягивается; выход за шкалу показывается как 10', (tester) async {
      await tester.pumpWidget(host(const PriorityBadge(652)));
      expect(find.text('10'), findsOneWidget);
      final size = tester.getSize(find.byType(PriorityBadge));
      expect(size.width, greaterThanOrEqualTo(AppSizes.priority));
      expect(size.height, greaterThanOrEqualTo(AppSizes.priority));
      expect(size.width, lessThan(80), reason: 'бейдж не растягивается на ширину строки');
    });

    for (final locale in ['ru', 'kk']) {
      testWidgets('при крупном шрифте 1.3 растёт, а не обрезается ($locale)', (tester) async {
        await tester.pumpWidget(host(const PriorityBadge(10), locale: locale, textScale: 1.3));
        expect(tester.takeException(), isNull);
        final badge = tester.getRect(find.byType(PriorityBadge));
        final digits = tester.getRect(find.text('10'));
        expect(badge.contains(digits.topLeft) && badge.contains(digits.bottomRight - const Offset(0.01, 0.01)), isTrue);
      });
    }
  });
}
