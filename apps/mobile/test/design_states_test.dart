import 'package:darumen/api/client.dart';
import 'package:darumen/state/load_state.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/theme/tokens.dart';
import 'package:darumen/widgets/empty_state.dart';
import 'package:darumen/widgets/error_box.dart';
import 'package:darumen/widgets/load_state_view.dart';
import 'package:darumen/widgets/state_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

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

/// Цвет круга с иконкой у состояния.
Color? circleColor(WidgetTester tester, IconData icon) {
  final box = tester.widget<Container>(find.ancestor(of: find.byIcon(icon), matching: find.byType(Container)).first);
  return (box.decoration as BoxDecoration?)?.color;
}

void main() {
  final c = ColorTokens.light;

  group('EmptyState', () {
    testWidgets('neutral circle is surface-muted, title 16.5/800, body 13.5 text-secondary', (tester) async {
      await tester.pumpWidget(host(const EmptyState(title: 'Пока нет пациентов', body: 'Появятся с направлениями')));
      expect(circleColor(tester, Icons.inbox_outlined), c.neutralSoft);
      expect(tester.widget<Text>(find.text('Пока нет пациентов')).style?.fontSize, 16.5);
      final body = tester.widget<Text>(find.text('Появятся с направлениями'));
      expect(body.style?.fontSize, 13.5);
      expect(body.style?.color, c.muted);
    });

    testWidgets('compact variant uses a 40 dp circle and a detail line under the body', (tester) async {
      await tester.pumpWidget(host(const EmptyState(title: 'Ошибка', body: 'Текст', detail: 'Пояснение сервера', compact: true)));
      expect(tester.getSize(find.ancestor(of: find.byIcon(Icons.inbox_outlined), matching: find.byType(Container)).first), const Size(40, 40));
      expect(tester.widget<Text>(find.text('Пояснение сервера')).style?.fontSize, 12);
    });
  });

  group('ErrorState wording follows the web StateError', () {
    testWidgets('network failure: «Сервер не отвечает — проверьте соединение.» in a warn circle with «Повторить»', (tester) async {
      var retried = false;
      await tester.pumpWidget(host(ErrorState(error: http.ClientException('socket'), onRetry: () => retried = true)));
      expect(find.text('Не удалось загрузить данные'), findsOneWidget);
      expect(find.text('Сервер не отвечает — проверьте соединение.'), findsOneWidget);
      expect(circleColor(tester, Icons.warning_amber_rounded), c.warnSoft);
      await tester.tap(find.text('Повторить'));
      expect(retried, isTrue);
    });

    testWidgets('server error: the code sentence and the server detail as a caption', (tester) async {
      await tester.pumpWidget(host(const ErrorState(error: ApiException(503, 'Сервис моделей недоступен', detail: 'повторите позже'))));
      expect(find.text('Сервер ответил ошибкой. Код 503.'), findsOneWidget);
      expect(find.text('повторите позже'), findsOneWidget);
    });

    testWidgets('404 without a readable title is «not connected»; a readable title becomes the caption', (tester) async {
      await tester.pumpWidget(host(const Column(children: [
        ErrorState(error: ApiException(404, 'HTTP 404')),
        ErrorState(error: ApiException(404, 'Нет очередей в регионе')),
      ])));
      expect(find.text('Раздел ещё не подключён на сервере (код 404).'), findsNWidgets(2));
      expect(find.text('Нет очередей в регионе'), findsOneWidget);
    });

    testWidgets('kazakh texts are the web ones', (tester) async {
      await tester.pumpWidget(host(ErrorState(error: http.ClientException('socket')), locale: 'kk'));
      expect(find.text('Деректерді жүктеу мүмкін болмады'), findsOneWidget);
      expect(find.text('Сервер жауап бермейді — байланысты тексеріңіз.'), findsOneWidget);
      expect(find.text('Қайталау'), findsNothing, reason: 'без onRetry кнопки нет');
    });

    testWidgets('403 renders the no-access state', (tester) async {
      await tester.pumpWidget(host(const ErrorState(error: ApiException(403, 'Нет доступа к разделу', detail: 'permission_required'))));
      expect(find.text('Нет доступа к разделу'), findsOneWidget);
      expect(find.text('Доступ выдаёт администратор организации.'), findsOneWidget);
    });
  });

  group('ForbiddenState', () {
    testWidgets('machine codes become the web sentences, a readable title and detail are shown as they are', (tester) async {
      await tester.pumpWidget(host(const Column(children: [
        ForbiddenState(error: ApiException(403, 'Нет организации', detail: 'no_organization')),
        ForbiddenState(error: ApiException(403, 'Данные другой организации', detail: 'other_organization')),
        ForbiddenState(error: ApiException(403, 'Решает больница пациента', detail: 'решение по маршруту принимает больница')),
        ForbiddenState(body: 'Своя причина'),
      ])));
      expect(find.text('Нет доступа к разделу'), findsNWidgets(4));
      expect(find.text('К учётной записи не привязана организация: раздел откроется, когда администратор её укажет.'), findsOneWidget);
      expect(find.text('Это данные другой организации — доступ открыт только к своей.'), findsOneWidget);
      expect(find.text('Решает больница пациента — решение по маршруту принимает больница'), findsOneWidget);
      expect(find.text('Своя причина'), findsOneWidget);
    });

    testWidgets('kazakh title', (tester) async {
      await tester.pumpWidget(host(const ForbiddenState(), locale: 'kk'));
      expect(find.text('Бөлімге қолжетімділік жоқ'), findsOneWidget);
    });
  });

  testWidgets('FilteredEmptyState: web wording and a reset action', (tester) async {
    var reset = false;
    await tester.pumpWidget(host(FilteredEmptyState(onReset: () => reset = true)));
    expect(find.text('Ничего не найдено'), findsOneWidget);
    expect(find.text('Попробуйте снять часть фильтров'), findsOneWidget);
    await tester.tap(find.text('Сбросить фильтры'));
    expect(reset, isTrue);
  });

  group('StaleDataBanner', () {
    testWidgets('banner on accent-subtle with a 28 dp clock circle, bold date and no refresh link', (tester) async {
      await tester.pumpWidget(host(const StaleDataBanner(asOf: '2025-03-31')));
      expect(find.text('Данные на 31.03.2025'), findsOneWidget);
      expect(find.text('Обновить'), findsNothing, reason: 'данные обновляет загрузка витрин, а не пользователь');
      expect(find.byType(TextButton), findsNothing);
      final banner = tester.widget<Container>(find.byKey(const ValueKey('stale-banner')));
      final decoration = banner.decoration! as BoxDecoration;
      expect(decoration.color, c.accentSubtle);
      expect(decoration.borderRadius, BorderRadius.circular(AppRadius.md));
      expect(decoration.boxShadow, isNull);
      expect(tester.getSize(find.ancestor(of: find.byIcon(Icons.schedule), matching: find.byType(Container)).first), const Size(28, 28));
    });

    testWidgets('the next upload is appended when known, in both languages', (tester) async {
      await tester.pumpWidget(host(const StaleDataBanner(asOf: '2025-03-31', next: '2025-04-30')));
      expect(find.text('Данные на 31.03.2025 · следующая загрузка — 30.04.2025'), findsOneWidget);
      await tester.pumpWidget(host(const StaleDataBanner(asOf: '2025-03-31', next: '2025-04-30'), locale: 'kk'));
      expect(find.text('31.03.2025 жағдай бойынша деректер · келесі жүктеу — 30.04.2025'), findsOneWidget);
    });

    test('isStale keeps its 7-day contract', () {
      expect(StaleDataBanner.isStale('2025-03-31', now: DateTime(2026, 9, 28)), isTrue);
      expect(StaleDataBanner.isStale('2026-09-27', now: DateTime(2026, 9, 28)), isFalse);
      expect(StaleDataBanner.isStale(null), isFalse);
    });
  });

  group('ErrorBox', () {
    testWidgets('shows the user text of the error recipe (409: title — detail) with «Повторить»', (tester) async {
      var retried = false;
      await tester.pumpWidget(host(ErrorBox(error: const ApiException(409, 'Ждём ответа пациента', detail: 'перевод без ответа'), onRetry: () => retried = true)));
      final text = tester.widget<Text>(find.text('Ждём ответа пациента — перевод без ответа'));
      expect(text.style?.fontSize, 14.5);
      expect(text.style?.color, c.danger);
      await tester.tap(find.text('Повторить'));
      expect(retried, isTrue);
    });

    testWidgets('network failure says the server is unavailable without the raw exception', (tester) async {
      await tester.pumpWidget(host(ErrorBox(error: http.ClientException('Connection refused'))));
      expect(find.text('Сервер недоступен. Повторите попытку позже.'), findsOneWidget);
      expect(find.textContaining('Connection refused'), findsNothing);
    });

    testWidgets('null error draws nothing, 403 draws the no-access state', (tester) async {
      await tester.pumpWidget(host(const Column(children: [ErrorBox(error: null), ErrorBox(error: ApiException(403, 'Forbidden'))])));
      expect(find.text('Нет доступа к разделу'), findsOneWidget);
    });
  });

  testWidgets('LoadStateView: skeleton, data, empty and failure', (tester) async {
    Widget view(LoadState<List<int>> state) => host(LoadStateView<List<int>>(
          state: state,
          skeleton: const Text('загрузка'),
          builder: (_, data) => Text('данные ${data.length}'),
          isEmpty: (data) => data.isEmpty,
          empty: const Text('пусто'),
        ));
    await tester.pumpWidget(view(const Loading()));
    expect(find.text('загрузка'), findsOneWidget);
    await tester.pumpWidget(view(const Loaded([1, 2])));
    expect(find.text('данные 2'), findsOneWidget);
    await tester.pumpWidget(view(const Loaded([])));
    expect(find.text('пусто'), findsOneWidget);
    await tester.pumpWidget(view(Failed(http.ClientException('x'))));
    expect(find.text('Не удалось загрузить данные'), findsOneWidget);
  });

  testWidgets('kazakh states at 1.3x on a 360 dp phone do not overflow', (tester) async {
    await tester.pumpWidget(host(
      Column(children: [
        ErrorState(error: http.ClientException('socket'), onRetry: () {}),
        const ForbiddenState(error: ApiException(403, 'Forbidden', detail: 'no_organization')),
        FilteredEmptyState(onReset: () {}),
        const StaleDataBanner(asOf: '2025-03-31', next: '2025-04-30'),
      ]),
      locale: 'kk',
      textScale: 1.3,
    ));
    expect(tester.takeException(), isNull);
  });
}
