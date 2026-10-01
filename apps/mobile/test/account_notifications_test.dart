import 'dart:convert';

import 'package:darumen/screens/notification_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/harness.dart';

/// Настройки уведомлений (§9, решение Q12): к карточке каналов добавлен один переключатель «Изменения моего
/// маршрута» (событие `route_updates`, канал «в системе») — только у гражданина. Пишется через
/// `NotificationSettings.withEventChannel`: остальные события, каналы, тихие часы и сводка уходят обратно как были.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object?> stored({bool routeInApp = true}) => {
        'events': [
          {
            'code': 'security',
            'titleRu': 'Безопасность аккаунта: вход, смена пароля, новые сессии',
            'titleKk': 'Аккаунт қауіпсіздігі: кіру, құпиясөзді ауыстыру, жаңа сессиялар',
            'inApp': true,
            'email': true,
            'sms': false,
            'push': false,
            'locked': true,
          },
          {
            'code': 'route_updates',
            'titleRu': 'Изменения моего маршрута',
            'titleKk': 'Менің бағытымдағы өзгерістер',
            'inApp': routeInApp,
            'email': true,
            'sms': false,
            'push': true,
            'locked': false,
          },
          {'code': 'patient_signals', 'titleRu': 'Сигналы пациентов', 'titleKk': 'Пациенттердің сигналдары', 'inApp': true, 'email': false, 'sms': false, 'push': false, 'locked': false},
        ],
        'quietFrom': '22:00',
        'quietTo': '07:00',
        'quietExceptRegulator': true,
        'digest': 'weekly',
      };

  /// Ответ `PUT /me/notifications`, как у API: сохранённое тело с названиями и признаком `locked`.
  http.Response echo(http.Request request) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final titles = {for (final e in (stored()['events']! as List<Object?>).cast<Map<String, Object?>>()) e['code']: e};
    return json({
      ...body,
      'events': [
        for (final e in (body['events'] as List<dynamic>).cast<Map<String, dynamic>>())
          {...e, 'titleRu': titles[e['code']]!['titleRu'], 'titleKk': titles[e['code']]!['titleKk'], 'locked': e['code'] == 'security'},
      ],
    });
  }

  Switch routeSwitch(WidgetTester tester) =>
      tester.widget<Switch>(find.descendant(of: find.byKey(const ValueKey('event-route_updates')), matching: find.byType(Switch)));

  testWidgets('citizen: the route switch with the API title and the caption; turning it off keeps everything else', (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {'GET /me/notifications': stored(), 'PUT /me/notifications': echo});
    await pumpScreen(tester, session, const NotificationSettingsScreen(), size: phoneTall);

    expect(find.text('Изменения моего маршрута'), findsOneWidget);
    expect(find.text('Перевод, на который нужен ваш ответ, и просьба врача записать приём приходят всегда.'), findsOneWidget);
    expect(routeSwitch(tester).value, isTrue);
    expect(find.text('КАНАЛЫ ДОСТАВКИ'), findsOneWidget, reason: 'карточка каналов остаётся');

    await tester.tap(find.descendant(of: find.byKey(const ValueKey('event-route_updates')), matching: find.byType(Switch)));
    await pumpFrames(tester);

    final body = backend.lastBody('PUT', '/me/notifications');
    expect(body['events'], [
      {'code': 'security', 'inApp': true, 'email': true, 'sms': false, 'push': false},
      {'code': 'route_updates', 'inApp': false, 'email': true, 'sms': false, 'push': true},
      {'code': 'patient_signals', 'inApp': true, 'email': false, 'sms': false, 'push': false},
    ]);
    expect(body['quietFrom'], '22:00');
    expect(body['quietTo'], '07:00');
    expect(body['quietExceptRegulator'], isTrue);
    expect(body['digest'], 'weekly');
    expect(routeSwitch(tester).value, isFalse);
  });

  testWidgets('after saving the citizen bell is read again', (tester) async {
    final (session, backend) = await demoSession(DemoUser.citizen1, api: {'GET /me/notifications': stored(routeInApp: false), 'PUT /me/notifications': echo});
    await pumpScreen(tester, session, const NotificationSettingsScreen(), size: phoneTall);
    final before = backend.calls('GET', '/route/me/notifications').length;
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('event-route_updates')), matching: find.byType(Switch)));
    await pumpFrames(tester);
    expect(backend.lastBody('PUT', '/me/notifications')['events'][1]['inApp'], isTrue);
    expect(backend.calls('GET', '/route/me/notifications').length, greaterThan(before));
  });

  testWidgets('a rejected save rolls the switch back and shows the server text', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, api: {
      'GET /me/notifications': stored(),
      'PUT /me/notifications': problem(422, 'Проверьте поля', errors: {
        'events': ['неизвестные события: x'],
      }),
    });
    await pumpScreen(tester, session, const NotificationSettingsScreen(), size: phoneTall);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('event-route_updates')), matching: find.byType(Switch)));
    await pumpFrames(tester);
    expect(routeSwitch(tester).value, isTrue);
    expect(find.text('Проверьте поля — неизвестные события: x'), findsOneWidget);
  });

  testWidgets('a doctor has no route switch; a server without the event shows none either', (tester) async {
    final (doctor, _) = await demoSession(DemoUser.doctor1, api: {'GET /me/notifications': stored()});
    await pumpScreen(tester, doctor, const NotificationSettingsScreen(), size: phoneTall);
    expect(find.byKey(const ValueKey('event-route_updates')), findsNothing);
    expect(find.text('КАНАЛЫ ДОСТАВКИ'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // новый экран, а не прежнее состояние
    final (citizen, _) = await demoSession(DemoUser.citizen1, api: {
      'GET /me/notifications': {'events': <Object?>[], 'digest': 'off'},
    });
    await pumpScreen(tester, citizen, const NotificationSettingsScreen(), size: phoneTall);
    expect(find.byKey(const ValueKey('event-route_updates')), findsNothing);
  });

  testWidgets('kazakh at text scale 1.3 on a 360 dp phone: Kazakh title from the API, no overflow', (tester) async {
    final (session, _) = await demoSession(DemoUser.citizen1, locale: 'kk', api: {'GET /me/notifications': stored()});
    await pumpScreen(tester, session, const NotificationSettingsScreen(), locale: 'kk', textScale: 1.3, size: phoneNarrow);
    expect(find.text('Менің бағытымдағы өзгерістер'), findsOneWidget);
    expect(find.textContaining('әрқашан келеді'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
