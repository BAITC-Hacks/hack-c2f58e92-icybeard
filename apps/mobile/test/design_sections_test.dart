import 'dart:async';

import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/theme/tokens.dart';
import 'package:darumen/widgets/collapsible_section.dart';
import 'package:darumen/widgets/inline_disclosure.dart';
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
        child: Scaffold(body: Center(child: SizedBox(width: width, child: SingleChildScrollView(child: child)))),
      ),
    );

void main() {
  final c = ColorTokens.light;

  group('CollapsibleSection', () {
    testWidgets('title reads as a row (14.5/700 ink), lead under it, head at least 52 tall', (tester) async {
      await tester.pumpWidget(host(const CollapsibleSection(title: 'Анализы', lead: 'Сроки действия по Стандарту', child: Text('тело'))));
      final title = tester.widget<Text>(find.text('Анализы'));
      expect(title.style?.fontSize, 14.5);
      expect(title.style?.fontWeight, FontWeight.w700);
      final lead = tester.widget<Text>(find.text('Сроки действия по Стандарту'));
      expect(lead.style?.fontSize, 13.5);
      expect(lead.style?.color, c.muted);
      expect(tester.getTopLeft(find.text('Сроки действия по Стандарту')).dy, greaterThan(tester.getTopLeft(find.text('Анализы')).dy));
      final head = find.ancestor(of: find.text('Анализы'), matching: find.byType(InkWell)).first;
      expect(tester.getSize(head).height, greaterThanOrEqualTo(52));
    });

    testWidgets('summary tone: danger and warn are red, ok is green, none stays text-secondary', (tester) async {
      await tester.pumpWidget(host(const Column(children: [
        CollapsibleSection(title: 'А', summary: 'истекли: 2', summaryTone: StatusTone.danger, child: SizedBox()),
        CollapsibleSection(title: 'Б', summary: 'сигнал', summaryTone: StatusTone.warn, child: SizedBox()),
        CollapsibleSection(title: 'В', summary: 'все действуют', summaryTone: StatusTone.ok, child: SizedBox()),
        CollapsibleSection(title: 'Г', summary: 'три', child: SizedBox()),
      ])));
      expect(tester.widget<Text>(find.text('истекли: 2')).style?.color, c.danger);
      expect(tester.widget<Text>(find.text('сигнал')).style?.color, c.danger, reason: 'как .summary.warn веба');
      expect(tester.widget<Text>(find.text('все действуют')).style?.color, c.ok);
      expect(tester.widget<Text>(find.text('три')).style?.color, c.muted);
    });

    testWidgets('an external controller opens and closes the section and taps write back to it', (tester) async {
      final open = ValueNotifier(false);
      addTearDown(open.dispose);
      final changes = <bool>[];
      await tester.pumpWidget(host(CollapsibleSection(title: 'Анализы', controller: open, onExpansionChanged: changes.add, child: const Text('тело'))));
      expect(find.text('тело'), findsNothing);
      open.value = true;
      await tester.pumpAndSettle();
      expect(find.text('тело'), findsOneWidget, reason: '«Посмотреть» в другой карточке раскрывает секцию');
      await tester.tap(find.text('Анализы'));
      await tester.pumpAndSettle();
      expect(open.value, isFalse);
      expect(find.text('тело'), findsNothing);
      expect(changes, [false], reason: 'колбэк — только на тап пользователя');
    });

    testWidgets('revealSection opens the section and scrolls it into view', (tester) async {
      final open = ValueNotifier(false);
      addTearDown(open.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ListView(children: [
            // ListView строит детей лениво: секция должна быть в пределах cacheExtent, чтобы к ней прокрутить
            const SizedBox(height: 700),
            CollapsibleSection(key: key, title: 'Анализы', controller: open, child: const Text('тело')),
          ]),
        ),
      ));
      expect(find.text('Анализы', skipOffstage: true), findsNothing);
      var done = false;
      unawaited(revealSection(key, open).then((_) => done = true));
      await tester.pumpAndSettle();
      expect(done, isTrue);
      expect(open.value, isTrue);
      expect(find.text('тело'), findsOneWidget);
      final head = tester.getRect(find.ancestor(of: find.text('Анализы'), matching: find.byType(InkWell)).first);
      expect(head.top, greaterThanOrEqualTo(0));
      expect(head.bottom, lessThanOrEqualTo(600), reason: 'шапка секции целиком в окне 800×600 теста');
    });

    testWidgets('initiallyExpanded and the old constructor keep working; semantics carry title, lead and summary', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(const CollapsibleSection(title: 'Анализы', lead: 'по Стандарту', summary: 'истекли: 2', initiallyExpanded: true, origin: Origin.formula, child: Text('тело'))));
      expect(find.text('тело'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Анализы. по Стандарту. истекли: 2')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('kazakh at 1.3x with lead, summary and origin tag does not overflow', (tester) async {
      await tester.pumpWidget(host(
        const CollapsibleSection(
          title: 'Талдаулар',
          lead: 'Жарамдылық мерзімдері — Стандарттың 5-қосымшасынан',
          summary: 'мерзімі өтті: 7 · жарамды: 3',
          summaryTone: StatusTone.danger,
          origin: Origin.formula,
          child: Text('мазмұны'),
        ),
        locale: 'kk',
        textScale: 1.3,
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('InlineDisclosure', () {
    testWidgets('link-styled toggle 13.5/700 opens the content in place and rotates the chevron', (tester) async {
      await tester.pumpWidget(host(const InlineDisclosure(title: 'Из чего сложился прогноз', child: Text('факторы'))));
      final toggle = tester.widget<Text>(find.text('Из чего сложился прогноз'));
      expect(toggle.style?.fontSize, 13.5);
      expect(toggle.style?.fontWeight, FontWeight.w700);
      expect(toggle.style?.color, c.link);
      expect(find.text('факторы'), findsNothing);
      expect(tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns, 0);
      await tester.tap(find.text('Из чего сложился прогноз'));
      await tester.pumpAndSettle();
      expect(find.text('факторы'), findsOneWidget);
      expect(tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns, 0.5);
      await tester.tap(find.text('Из чего сложился прогноз'));
      await tester.pumpAndSettle();
      expect(find.text('факторы'), findsNothing);
    });

    testWidgets('title style is 14.5/700, quiet style is 12 text-secondary', (tester) async {
      await tester.pumpWidget(host(const Column(children: [
        InlineDisclosure(title: 'Как считается', style: DisclosureStyle.title, child: Text('а')),
        InlineDisclosure(title: 'Источник', style: DisclosureStyle.quiet, child: Text('б')),
      ])));
      expect(tester.widget<Text>(find.text('Как считается')).style?.fontSize, 14.5);
      expect(tester.widget<Text>(find.text('Как считается')).style?.color, c.link);
      expect(tester.widget<Text>(find.text('Источник')).style?.fontSize, 12);
      expect(tester.widget<Text>(find.text('Источник')).style?.color, c.muted);
    });

    testWidgets('toggle is a 44 dp target with a border-soft hairline above it; divider can be turned off', (tester) async {
      await tester.pumpWidget(host(const Column(children: [
        InlineDisclosure(title: 'Источник', style: DisclosureStyle.quiet, child: Text('б')),
        InlineDisclosure(title: 'Без линии', divider: false, child: Text('в')),
      ])));
      final toggle = find.ancestor(of: find.text('Источник'), matching: find.byType(InkWell)).first;
      expect(tester.getSize(toggle).height, greaterThanOrEqualTo(44));
      final lines = tester.widgetList<Container>(find.byType(Container)).where((box) {
        final border = (box.decoration as BoxDecoration?)?.border;
        return border is Border && border.top.color == c.borderSoft;
      });
      expect(lines, hasLength(1));
    });

    testWidgets('semantics: a button with the expanded state; initiallyExpanded shows the content', (tester) async {
      final handle = tester.ensureSemantics();
      final changes = <bool>[];
      await tester.pumpWidget(host(InlineDisclosure(title: 'Источник', initiallyExpanded: true, onExpansionChanged: changes.add, child: const Text('ВОЗ'))));
      expect(find.text('ВОЗ'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('Источник')),
        matchesSemantics(label: 'Источник', isButton: true, hasTapAction: true, hasExpandedState: true, isExpanded: true, isFocusable: true, hasFocusAction: true),
      );
      await tester.tap(find.text('Источник'));
      await tester.pumpAndSettle();
      expect(changes, [false]);
      handle.dispose();
    });
  });
}
