import 'dart:async';

import 'package:darumen/config/env.dart';
import 'package:darumen/screens/consents_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/harness.dart';

/// «Данные и согласия» (`/profile/consents`, F16): согласия переключателями (обязательное заблокировано), журнал
/// доступа к моим данным, «Мои данные» — выгрузка копии в веб-кабинете (решение Q17) и запрос на удаление через лист
/// подтверждения.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object?> consents({bool stats = false, String? statsUpdated}) => {
        'items': [
          {
            'code': 'forecasts',
            'titleRu': 'Использование моих данных для прогноза сроков ожидания (обязательное)',
            'titleKk': 'Күту мерзімдерін болжау үшін деректерімді пайдалану (міндетті)',
            'required': true,
            'granted': true,
            'updatedAt': null,
          },
          {
            'code': 'anonymized_stats',
            'titleRu': 'Обезличенная статистика для улучшения сервиса',
            'titleKk': 'Қызметті жақсарту үшін иесіздендірілген статистика',
            'required': false,
            'granted': stats,
            'updatedAt': statsUpdated,
          },
          {
            'code': 'research_exports',
            'titleRu': 'Обезличенные выгрузки для научных исследований',
            'titleKk': 'Ғылыми зерттеулерге арналған иесіздендірілген деректер',
            'required': false,
            'granted': false,
            'updatedAt': null,
          },
        ],
      };

  const accessLog = {
    'items': [
      {'at': '2026-10-01T08:05:00+00:00', 'actor': 'doctor1', 'role': 'doctor', 'method': 'GET', 'path': '/api/v1/route/SYN-75-028B-1-01', 'status': 200},
      {'at': '2026-09-30T11:40:00+00:00', 'actor': 'doctor2', 'role': 'doctor', 'method': 'POST', 'path': '/api/v1/route/SYN-75-028B-1-01/redirect', 'status': 409},
    ],
  };

  Switch switchOf(WidgetTester tester, String code) =>
      tester.widget<Switch>(find.descendant(of: find.byKey(ValueKey('consent-$code')), matching: find.byType(Switch)));

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
    await tester.pump();
  }

  testWidgets('shows the three cards: consents with the required one locked, the access log and my data', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: {'GET /me/consents': consents(statsUpdated: '2026-09-30T10:15:00+00:00'), 'GET /me/access-log': accessLog});
    await pumpScreen(tester, session, const ConsentsScreen(), size: phoneTall);

    expect(find.text('Данные и согласия'), findsOneWidget);
    expect(find.text('Ерлан Жумабеков · согласий: 3 · доступ к данным виден в аудите'), findsOneWidget);
    expect(find.text('СОГЛАСИЯ'), findsOneWidget);
    expect(find.text('отзыв согласия попадает в аудит'), findsOneWidget);
    expect(find.text('Использование моих данных для прогноза сроков ожидания (обязательное)'), findsOneWidget);
    expect(find.text('обязательно для работы кабинета'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(switchOf(tester, 'forecasts').value, isTrue);
    expect(switchOf(tester, 'forecasts').onChanged, isNull, reason: 'обязательное согласие не отзывается');
    expect(switchOf(tester, 'anonymized_stats').onChanged, isNotNull);
    expect(find.text('обновлено 30.09.2026'), findsOneWidget);

    await scrollTo(tester, find.text('ЖУРНАЛ ДОСТУПА К МОИМ ДАННЫМ'));
    expect(find.textContaining('doctor1'), findsOneWidget);
    expect(find.textContaining('GET /route/SYN-75-028B-1-01'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);
    expect(find.text('409'), findsOneWidget);

    await scrollTo(tester, find.text('Запросить удаление учётной записи'));
    expect(find.text('МОИ ДАННЫЕ'), findsOneWidget);
    expect(find.text('Выгрузить копию (CSV)'), findsOneWidget);
    expect(find.textContaining('Удаление подтверждает администратор организации'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a switch sends PUT {granted}, is disabled while in flight and shows what the server stored', (tester) async {
    final gate = Completer<http.Response>();
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {
      'GET /me/consents': consents(),
      'GET /me/access-log': const {'items': <Object?>[]},
      'PUT /me/consents/anonymized_stats': (http.Request _) => gate.future,
    });
    await pumpScreen(tester, session, const ConsentsScreen(), size: phoneTall);

    await tester.tap(find.descendant(of: find.byKey(const ValueKey('consent-anonymized_stats')), matching: find.byType(Switch)));
    await tester.pump();
    expect(backend.lastBody('PUT', '/me/consents/anonymized_stats'), {'granted': true});
    expect(switchOf(tester, 'anonymized_stats').onChanged, isNull, reason: 'пока запрос в полёте, переключатели заблокированы');
    expect(switchOf(tester, 'research_exports').onChanged, isNull);

    gate.complete(json(consents(stats: true, statsUpdated: '2026-10-02T06:00:00+00:00')));
    await pumpFrames(tester);
    expect(switchOf(tester, 'anonymized_stats').value, isTrue);
    expect(switchOf(tester, 'anonymized_stats').onChanged, isNotNull);
    expect(find.text('обновлено 02.10.2026'), findsOneWidget);
    expect(backend.calls('PUT', '/me/consents/anonymized_stats'), hasLength(1));
  });

  testWidgets('a 422 keeps the old value and shows the server message', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: {
      'GET /me/consents': consents(),
      'GET /me/access-log': const {'items': <Object?>[]},
      'PUT /me/consents/research_exports': problem(422, 'Проверьте поля', errors: {
        'granted': ['обязательное поле'],
      }),
    });
    await pumpScreen(tester, session, const ConsentsScreen(), size: phoneTall);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('consent-research_exports')), matching: find.byType(Switch)));
    await pumpFrames(tester);
    expect(switchOf(tester, 'research_exports').value, isFalse);
    expect(find.text('Проверьте поля — обязательное поле'), findsOneWidget);
  });

  testWidgets('a network failure of the switch says the server is unavailable, no raw exception text', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: {
      'GET /me/consents': consents(),
      'GET /me/access-log': const {'items': <Object?>[]},
      'PUT /me/consents/research_exports': (http.Request _) => throw http.ClientException('Connection refused'),
    });
    await pumpScreen(tester, session, const ConsentsScreen(), size: phoneTall);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('consent-research_exports')), matching: find.byType(Switch)));
    await pumpFrames(tester);
    expect(find.text('Сервер недоступен. Повторите попытку позже.'), findsOneWidget);
    expect(find.textContaining('Connection refused'), findsNothing);
  });

  testWidgets('empty lists show the web empty texts', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: {
      'GET /me/consents': const {'items': <Object?>[]},
      'GET /me/access-log': const {'items': <Object?>[]},
    });
    await pumpScreen(tester, session, const ConsentsScreen(), size: phoneTall);
    expect(find.text('Согласий пока нет'), findsOneWidget);
    expect(find.text('К вашим данным ещё не обращались'), findsOneWidget);
  });

  testWidgets('a load error offers a retry per card; 403 is the no-access state', (tester) async {
    var consentsReply = problem(500, 'Ошибка');
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {
      'GET /me/consents': (http.Request _) => consentsReply,
      'GET /me/access-log': problem(403, 'Forbidden', detail: 'permission_required'),
    });
    await pumpScreen(tester, session, const ConsentsScreen(), size: phoneTall);
    expect(find.text('Не удалось загрузить данные'), findsOneWidget);
    expect(find.text('Нет доступа к разделу'), findsOneWidget);

    consentsReply = json(consents());
    await tester.tap(find.text('Повторить'));
    await pumpFrames(tester);
    expect(find.text('Использование моих данных для прогноза сроков ожидания (обязательное)'), findsOneWidget);
    expect(backend.calls('GET', '/me/consents'), hasLength(2));
  });

  testWidgets('deletion asks for confirmation first, then sends one request with a key and says it was sent', (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {
      'GET /me/consents': consents(),
      'GET /me/access-log': const {'items': <Object?>[]},
      'POST /me/deletion-request': json({'accepted': true}, 202),
    });
    await pumpScreen(tester, session, const ConsentsScreen(), size: phoneTall);

    await scrollTo(tester, find.text('Запросить удаление учётной записи'));
    await tester.tap(find.text('Запросить удаление учётной записи'));
    await pumpFrames(tester);
    expect(find.text('Удалить учётную запись?'), findsOneWidget);
    expect(find.textContaining('Запрос уйдёт администратору организации.'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await pumpFrames(tester);
    expect(backend.calls('POST', '/me/deletion-request'), isEmpty, reason: 'отмена ничего не отправляет');

    await tester.tap(find.text('Запросить удаление учётной записи'));
    await pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-deletion')));
    await pumpFrames(tester);
    final calls = backend.calls('POST', '/me/deletion-request');
    expect(calls, hasLength(1));
    expect(calls.single.headers['Idempotency-Key'], isNotEmpty);
    expect(find.text('Запрос на удаление отправлен администратору'), findsOneWidget);
    expect(find.text('Удалить учётную запись?'), findsNothing);
  });

  testWidgets('a failed deletion request shows the error text', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: {
      'GET /me/consents': consents(),
      'GET /me/access-log': const {'items': <Object?>[]},
      'POST /me/deletion-request': problem(503, 'Service Unavailable'),
    });
    await pumpScreen(tester, session, const ConsentsScreen(), size: phoneTall);
    await scrollTo(tester, find.text('Запросить удаление учётной записи'));
    await tester.tap(find.text('Запросить удаление учётной записи'));
    await pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-deletion')));
    await pumpFrames(tester);
    expect(find.text('Сервер недоступен. Повторите попытку позже.'), findsOneWidget);
    expect(find.text('Запрос на удаление отправлен администратору'), findsNothing);
  });

  testWidgets('the export opens the account page of the web cabinet in the browser (decision Q17)', (tester) async {
    final opened = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/url_launcher'), (call) async {
      opened.add((call.arguments as Map<Object?, Object?>)['url']! as String);
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/url_launcher'), null));
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {
      'GET /me/consents': consents(),
      'GET /me/access-log': const {'items': <Object?>[]},
    });
    await pumpScreen(tester, session, const ConsentsScreen(), size: phoneTall);
    await scrollTo(tester, find.text('Выгрузить копию (CSV)'));
    await tester.tap(find.text('Выгрузить копию (CSV)'));
    await pumpFrames(tester);
    expect(opened, ['${Env.webBase}/account/consents']);
    expect(backend.requests.where((r) => r.url.path.endsWith('/me/export')), isEmpty, reason: 'файл на телефоне не скачивается');
  });

  testWidgets('kazakh at text scale 1.3 on a 360 dp phone: texts in Kazakh, no overflow', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, locale: 'kk', api: {
      'GET /me/consents': consents(statsUpdated: '2026-09-30T10:15:00+00:00'),
      'GET /me/access-log': accessLog,
    });
    await pumpScreen(tester, session, const ConsentsScreen(), locale: 'kk', textScale: 1.3, size: phoneNarrow);
    expect(find.text('Деректер мен келісімдер'), findsOneWidget);
    expect(find.text('Күту мерзімдерін болжау үшін деректерімді пайдалану (міндетті)'), findsOneWidget);
    expect(find.text('кабинет жұмысы үшін міндетті'), findsOneWidget);
    expect(find.text('30.09.2026 жаңартылды'), findsOneWidget);
    await scrollTo(tester, find.text('Есептік жазбаны жоюды сұрау'));
    expect(find.text('Көшірмесін жүктеу (CSV)'), findsOneWidget);
    await tester.tap(find.text('Есептік жазбаны жоюды сұрау'));
    await pumpFrames(tester);
    expect(find.text('Есептік жазбаны жою керек пе?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
