import 'package:darumen/l10n/strings.dart';
import 'package:darumen/screens/decisions_screen.dart';
import 'package:darumen/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/harness.dart';

/// Журнал решений врача (DecisionsScreen) через harness: запрос `actor=me&size=200`, служебные записи скрайба скрыты,
/// итог словами (не чипом), события маршрута — подписями журнала врача, пилюли предметов со счётчиками, лист
/// подробностей без номера записи, пустое состояние и ошибка, казахский при крупном шрифте.
const dostar = 'Товарищество с ограниченной ответственностью "Достар Мед"';
const transfer = 'd2a6afd6-c158-49ab-96ef-385974a9fe4a';
final ru = S.of('ru');

Map<String, Object?> decision(String id, String subject, String subjectId, {Map<String, Object?>? recommended, Map<String, Object?>? chosen, String? reason, String at = '2026-09-25T10:00:00+00:00'}) => {
      'decisionId': id,
      'actor': 'doctor1',
      'role': 'doctor',
      'subject': subject,
      'subjectId': subjectId,
      'recommended': recommended,
      'chosen': chosen,
      'reason': ?reason,
      'recordedAt': at,
    };

/// Настоящий ответ журнала (fixture decisions.json) плюс служебная запись скрайба и ответы принимающей больницы.
List<Object?> journal() => [
      ...(fixtureMap('decisions')['items'] as List<dynamic>),
      decision('scribe-1', 'scribe', 'SYN-75-028B-381-03', chosen: {'scribeConsent': 'requested'}),
      decision('confirm-1', 'route', 'SYN-75-028B-381-03', chosen: {'moCode': '22GN', 'confirms': transfer, 'plannedAt': '2026-10-03'}, reason: 'место есть'),
      decision('cancel-1', 'route', 'SYN-75-028B-381-04', chosen: {'cancels': transfer}, reason: 'пациент передумал'),
    ];

Map<String, Object?> api(Object? Function(http.Request) decisions) => {
      '/journal/decisions': (http.Request r) {
        final items = decisions(r);
        return items is http.Response ? items : {'items': items, 'page': 1, 'size': 200, 'total': (items as List).length};
      },
      '/refdata/regions': {
        'items': [
          {'regionKato': '75', 'name': 'г. Алматы'},
        ],
      },
      '/refdata/profiles': {
        'items': [
          {'profileCode': '381', 'name': 'Офтальмологические'},
        ],
      },
      '/refdata/organizations': {
        'items': [
          {'moCode': '22GN', 'name': dostar},
          {'moCode': '031N', 'name': 'Государственное учреждение "Региональный военный госпиталь"'},
        ],
      },
    };

Future<DemoBackend> pumpJournal(WidgetTester tester, Object? Function(http.Request) decisions, {String locale = 'ru', double textScale = 1, Size size = phoneTall}) async {
  final (session, backend) = await demoSession(DemoUser.doctor1, api: api(decisions));
  await pumpScreen(tester, session, const DecisionsScreen(), locale: locale, textScale: textScale, size: size);
  return backend;
}

Finder rich(String text) => find.textContaining(text, findRichText: true);

/// Пилюли — в горизонтальной прокрутке: сначала прокрутить к пилюле, потом нажать.
Future<void> tapPill(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await pumpFrames(tester);
}

void main() {
  testWidgets('мои решения: запрос actor=me&size=200, скрайб скрыт, итог словами, события маршрута — подписи журнала врача', (tester) async {
    final backend = await pumpJournal(tester, (_) => journal());
    final query = backend.calls('GET', '/journal/decisions').single.url.queryParameters;
    expect(query['actor'], 'me');
    expect(query['size'], '200');

    expect(find.text(ru.decisionsLead), findsOneWidget);
    expect(find.text('Все решения · 7'), findsOneWidget, reason: '8 записей минус служебная запись скрайба');
    expect(find.text('SYN-75-028B-381-03'), findsOneWidget, reason: 'подтверждение видно, запись скрайба того же пациента — нет');
    expect(find.text('Предложен перевод: Достар Мед'), findsOneWidget);
    expect(find.text('Достар Мед: приём подтверждён'), findsOneWidget);
    expect(find.text('Дата госпитализации: 03.10.2026'), findsOneWidget);
    expect(find.text('Перевод отменён'), findsOneWidget);
    expect(find.text('Оставлен в своей больнице'), findsOneWidget);
    expect(find.text('г. Алматы · Офтальмологические · 11'), findsOneWidget, reason: 'новое направление — регион · профиль · дата');
    expect(rich('выбрано иначе'), findsWidgets);
    expect(rich('как рекомендовано'), findsWidgets);
    expect(rich('без рекомендации'), findsWidgets);
    expect(find.byType(StatusChip), findsNothing, reason: 'итог — текстом, без чипа');
    expect(find.textContaining('34dc8035'), findsNothing, reason: 'номера записи нет');
    expect(find.textContaining('{'), findsNothing, reason: 'сырого JSON нет');
    expect(find.textContaining('«место есть»'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('пилюли предмета со счётчиками фильтруют список; лист подробностей без номера записи', (tester) async {
    await pumpJournal(tester, (_) => journal());
    await tapPill(tester, 'Новое направление · 1');
    expect(find.text('г. Алматы · Офтальмологические · 11'), findsOneWidget);
    expect(find.text('Предложен перевод: Достар Мед'), findsNothing);
    await tapPill(tester, 'Пациент в очереди · 6');
    expect(find.text('г. Алматы · Офтальмологические · 11'), findsNothing);

    await tester.tap(find.text('Достар Мед: приём подтверждён'));
    await pumpFrames(tester);
    expect(find.text('Пациент в очереди'), findsOneWidget, reason: 'заголовок листа — предмет с заглавной');
    expect(find.text(ru.subjectIdLabel), findsOneWidget);
    expect(find.text(ru.recommendedLabel), findsOneWidget);
    expect(find.text(ru.chosenLabel), findsOneWidget);
    expect(find.text(ru.decisionsOutcomeLabel), findsOneWidget);
    expect(find.text('без рекомендации'), findsOneWidget);
    expect(find.text('ПРИЧИНА'), findsOneWidget);
    expect(find.text('место есть'), findsOneWidget);
    expect(find.textContaining('confirm-1'), findsNothing);
    expect(find.textContaining('decisionId'), findsNothing);
  });

  testWidgets('пусто — «Решений пока нет» с пояснением веба (и когда есть только записи скрайба)', (tester) async {
    await pumpJournal(tester, (_) => [decision('s', 'scribe', 'SYN-75-028B-381-03', chosen: {'x': 1})]);
    expect(find.text(ru.decisionsEmpty), findsOneWidget);
    expect(find.text(ru.decisionsEmptyText), findsOneWidget);
  });

  testWidgets('ошибка загрузки — состояние ошибки с «Повторить»; повтор загружает журнал', (tester) async {
    var fail = true;
    await pumpJournal(tester, (_) => fail ? problem(503, 'Service Unavailable') : journal());
    expect(find.text(ru.loadErrorTitle), findsOneWidget);
    fail = false;
    await tester.tap(find.text(ru.retry));
    await pumpFrames(tester);
    expect(find.text('Все решения · 7'), findsOneWidget);
  });

  testWidgets('казахский при масштабе 1.3 на телефоне 360 dp: список и лист подробностей без переполнения', (tester) async {
    await pumpJournal(tester, (_) => journal(), locale: 'kk', textScale: 1.3, size: phoneNarrow);
    final kk = S.of('kk');
    expect(find.text('Барлық шешімдер · 7'), findsOneWidget);
    expect(find.text('Ауыстыру ұсынылды: Достар Мед'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Ауыстыру ұсынылды: Достар Мед'));
    await pumpFrames(tester);
    expect(find.text(kk.decisionsOutcomeLabel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
