import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/theme/tokens.dart';
import 'package:darumen/widgets/app_card.dart';
import 'package:darumen/widgets/circle_button.dart';
import 'package:darumen/widgets/notice_card.dart';
import 'package:darumen/widgets/section.dart';
import 'package:darumen/widgets/skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget home, {String locale = 'ru', bool reduceMotion = false, double textScale = 1}) => MaterialApp(
      theme: AppTheme.light(),
      locale: Locale(locale),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion, textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    );

/// Сколько строк занял текст абзаца: число разных верхних краёв прямоугольников всего текста.
int lineCount(RenderParagraph paragraph) => paragraph
    .getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: paragraph.text.toPlainText().length))
    .map((box) => box.top.round())
    .toSet()
    .length;

Widget host(Widget child, {String locale = 'ru'}) => app(Scaffold(body: Center(child: SizedBox(width: 360, child: child))), locale: locale);

void main() {
  final c = ColorTokens.light;

  group('AppCard and rows', () {
    testWidgets('card is white radius 18 with the card shadow; a tap card is one button', (tester) async {
      var taps = 0;
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(AppCard(onTap: () => taps++, semanticsLabel: 'Открыть маршрут', child: const Text('карточка'))));
      final box = tester.widget<Container>(find.ancestor(of: find.text('карточка'), matching: find.byType(Container)).first);
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.color, c.card);
      expect(decoration.borderRadius, BorderRadius.circular(AppRadius.card));
      expect(decoration.boxShadow, c.cardShadow);
      await tester.tap(find.text('карточка'));
      expect(taps, 1);
      expect(find.bySemanticsLabel(RegExp('Открыть маршрут')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('card label: uppercase kicker 11.5/700 with the chip on the right', (tester) async {
      await tester.pumpWidget(host(const CardLabel('Срок ожидания', trailing: Text('чип'))));
      final kicker = tester.widget<Text>(find.text('СРОК ОЖИДАНИЯ'));
      expect(kicker.style?.fontSize, 11.5);
      expect(kicker.style?.fontWeight, FontWeight.w700);
      expect(tester.getTopLeft(find.text('чип')).dx, greaterThan(tester.getTopRight(find.text('СРОК ОЖИДАНИЯ')).dx));
    });

    testWidgets('list row: 14.5/600 title, 13.5 subtitle, dot, value and a chevron when tappable', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(Column(children: [
        ListRow(title: 'Уведомления', subtitle: 'только в приложении', dot: true, trailing: const RowValue('2'), onTap: () => taps++),
        const ListRow(title: 'Выйти', strong: true, last: true, chevron: false),
      ])));
      final title = tester.widget<Text>(find.text('Уведомления'));
      expect(title.style?.fontSize, 14.5);
      expect(title.style?.fontWeight, FontWeight.w600);
      expect(tester.widget<Text>(find.text('Выйти')).style?.fontWeight, FontWeight.w800);
      final subtitle = tester.widget<Text>(find.text('только в приложении'));
      expect(subtitle.style?.fontSize, 13.5);
      expect(subtitle.style?.color, c.muted);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(tester.getSize(find.ancestor(of: find.text('Уведомления'), matching: find.byType(Container)).first).height, greaterThanOrEqualTo(AppSizes.row));
      await tester.tap(find.text('Уведомления'));
      expect(taps, 1);
    });

    testWidgets('row value: 14.5 text-secondary by default, strong is ink 600', (tester) async {
      await tester.pumpWidget(host(const Column(children: [RowValue('47 дн.'), RowValue('≈ 9 дн.', strong: true)])));
      final plain = tester.widget<Text>(find.text('47 дн.'));
      expect(plain.style?.fontSize, 14.5);
      expect(plain.style?.color, c.muted);
      final strong = tester.widget<Text>(find.text('≈ 9 дн.'));
      expect(strong.style?.fontWeight, FontWeight.w600);
      expect(strong.style?.color, c.ink);
    });

    testWidgets('arrow link and field label', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(Column(children: [ArrowLink('Посмотреть', onTap: () => taps++), const ArrowLink('Без действия'), const FieldLabel('Причина')])));
      expect(tester.widget<Text>(find.text('Посмотреть')).style?.color, c.link);
      expect(find.text('→'), findsNWidgets(2));
      expect(tester.getSize(find.ancestor(of: find.text('Посмотреть'), matching: find.byType(InkWell))).height, greaterThanOrEqualTo(AppSizes.compact),
          reason: 'цель нажатия не меньше 44');
      await tester.tap(find.text('Посмотреть'));
      expect(taps, 1);
      expect(find.text('ПРИЧИНА'), findsOneWidget);
    });
  });

  testWidgets('notice card: attention tone, title and body, dismiss button with a tooltip', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(host(NoticeCard(title: 'Письмо сейчас не придёт', body: 'Почтовый сервер недоступен', onDismiss: () => dismissed = true, dismissLabel: 'Скрыть уведомление')));
    expect(tester.widget<Text>(find.text('Письмо сейчас не придёт')).style?.color, c.warn);
    expect(tester.widget<Text>(find.text('Почтовый сервер недоступен')).style?.fontSize, 13.5);
    await tester.tap(find.byTooltip('Скрыть уведомление'));
    expect(dismissed, isTrue);
  });

  group('skeletons', () {
    testWidgets('skeleton pulses on surface-muted; card skeleton has the card radius', (tester) async {
      await tester.pumpWidget(host(const Column(children: [Skeleton(width: 120), CardSkeleton(height: 80)])));
      await tester.pump(const Duration(milliseconds: 450));
      final boxes = tester.widgetList<Container>(find.byType(Container)).map((b) => b.decoration as BoxDecoration?).whereType<BoxDecoration>().toList();
      expect(boxes.every((d) => d.color == c.neutralSoft), isTrue);
      expect(boxes.any((d) => d.borderRadius == BorderRadius.circular(AppRadius.card)), isTrue);
    });

    testWidgets('reduced motion holds a steady opacity', (tester) async {
      await tester.pumpWidget(app(const Scaffold(body: Skeleton(width: 100)), reduceMotion: true));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.7);
    });
  });

  group('PageScaffold', () {
    testWidgets('title 24/800, actions, children with a 12 gap and a bottom action', (tester) async {
      await tester.pumpWidget(app(PageScaffold(
        title: 'Маршрут пациента',
        showBack: false,
        leading: const Icon(Icons.home),
        actions: const [Icon(Icons.search)],
        bottom: FilledButton(onPressed: () {}, child: const Text('Подтвердить')),
        children: const [Text('первый'), Text('второй')],
      )));
      expect(tester.widget<Text>(find.text('Маршрут пациента')).style?.fontSize, 24);
      expect(find.byIcon(Icons.home), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byType(BottomAction), findsOneWidget);
      final gap = tester.getTopLeft(find.text('второй')).dy - tester.getBottomLeft(find.text('первый')).dy;
      expect(gap, AppSpacing.md);
    });

    testWidgets('a one-word title next to the actions shrinks to fit instead of breaking inside the word (kk, 1.3×, 360 dp)', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Widget page(String title) => app(
            PageScaffold(
              title: title,
              showBack: false,
              leading: const SizedBox(width: 40, height: 40),
              actions: const [CircleIconButton(icon: Icons.tune, label: 'Сүзгі'), CircleIconButton(icon: Icons.notifications_none, label: 'Хабарламалар')],
              children: const [Text('тело')],
            ),
            locale: 'kk',
            textScale: 1.3,
          );
      await tester.pumpWidget(page('Пациенттер'));
      final word = tester.renderObject<RenderParagraph>(find.text('Пациенттер'));
      expect(lineCount(word), 1, reason: 'слово не рвётся посередине');
      expect(word.didExceedMaxLines, isFalse);
      expect(tester.widget<Text>(find.text('Пациенттер')).style!.fontSize, lessThan(24));

      // тестовый шрифт рисует каждую букву квадратом в кегль: два коротких слова помещаются только по одному в строке
      await tester.pumpWidget(page('Мой путь'));
      final words = tester.renderObject<RenderParagraph>(find.text('Мой путь'));
      expect(tester.widget<Text>(find.text('Мой путь')).style!.fontSize, 24, reason: 'каждое слово помещается — перенос между словами, кегль прежний');
      expect(lineCount(words), 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('back button appears when the navigator can pop and pops the page', (tester) async {
      await tester.pumpWidget(app(Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PageScaffold(title: 'Вторая', children: [Text('тело')]))),
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Назад'), findsOneWidget);
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      expect(find.text('Вторая'), findsNothing);
    });

    testWidgets('pull to refresh calls onRefresh; hero pages paint the hero gradient', (tester) async {
      var refreshed = 0;
      await tester.pumpWidget(app(PageScaffold(title: 'Главная', hero: true, onRefresh: () async => refreshed++, children: const [SizedBox(height: 100, child: Text('карточка'))])));
      final gradient = tester.widgetList<Container>(find.byType(Container)).map((b) => (b.decoration as BoxDecoration?)?.gradient).whereType<LinearGradient>().first;
      expect(gradient.colors, c.heroGradient);
      expect(gradient.stops, ColorTokens.heroGradientStops);
      await tester.fling(find.text('карточка'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(refreshed, 1);
    });
  });

  testWidgets('circle icon button: 40 dp on surface-muted with a tooltip and a tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(Center(child: CircleIconButton(icon: Icons.search, label: 'Поиск пациента', onTap: () => taps++))));
    expect(tester.getSize(find.byType(CircleIconButton)), const Size(AppSizes.iconButton, AppSizes.iconButton));
    final material = tester.widget<Material>(find.ancestor(of: find.byIcon(Icons.search), matching: find.byType(Material)).first);
    expect(material.color, c.neutralSoft);
    await tester.tap(find.byTooltip('Поиск пациента'));
    expect(taps, 1);
  });
}
