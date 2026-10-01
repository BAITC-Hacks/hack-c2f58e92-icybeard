import 'package:darumen/widgets/citizen/route_next_card.dart';
import 'package:darumen/widgets/hero_number.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'citizen_route_test.dart' show pumpRoute, signalsPath, tapAction;
import 'citizen_support.dart';
import 'support/harness.dart';

/// «Мой путь» ниже карточки действия: «Где быстрее» (просьба с комментарием, заблокированные больницы, сосед по
/// региону, блок «Не хотите переводиться?»), «Прогноз», «Что дальше», «Анализы», запрос записи приёма, памятки,
/// журнал, прошлые направления, подвал.
Map<String, dynamic> neighbour(String code, String regionKato, double p50) =>
    {'mo': {'moCode': code, 'name': 'ГКП на ПХВ "Областная больница"', 'regionKato': regionKato}, 'p50Days': p50, 'p90Days': p50 * 3, 'pRefusal': 0.2, 'distanceKm': 80, 'isNeighborRegion': true};

void main() {
  group('«Где быстрее»', () {
    testWidgets('waiting: tiles without blocked hospitals; a request goes with the optional comment from the sheet', (tester) async {
      final backend = await pumpRoute(tester, routeMe(status: 'waiting', blocked: ['031N'], decisions: [], signals: []), api: {'POST $signalsPath': recorded()});
      expect(find.text('ГДЕ БЫСТРЕЕ'), findsOneWidget);
      expect(find.text('Больницы вашего региона с тем же профилем.'), findsOneWidget);
      expect(find.text('031N'), findsNothing, reason: 'больница в blockedMoCodes не предлагается');
      expect(find.text('22GN'), findsOneWidget);
      expect(find.text('на 2 дн. больше, чем в вашей больнице'), findsOneWidget);
      expect(find.text('Попросить рассмотреть'), findsNWidgets(2));
      await tapAction(tester, 'Попросить рассмотреть');
      expect(find.textContaining('Перевести в другую больницу может только врач.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'живу рядом');
      await tapAction(tester, 'Попросить рассмотреть', last: true);
      expect(backend.lastBody('POST', signalsPath), {'kind': 'request_redirect', 'toMoCode': '22GN', 'comment': 'живу рядом'});
      expect(find.text('Запрос отправлен врачу'), findsOneWidget);
    });

    testWidgets('422 from the server: its field message is shown, nothing else changes', (tester) async {
      await pumpRoute(tester, routeMe(status: 'waiting', decisions: [], signals: []), api: {
        'POST $signalsPath': problem(422, 'Ошибка проверки', errors: {
          'toMoCode': ['организация совпадает с текущей'],
        }),
      });
      await tapAction(tester, 'Попросить рассмотреть');
      await tapAction(tester, 'Попросить рассмотреть', last: true);
      expect(find.text('Ошибка проверки — организация совпадает с текущей'), findsOneWidget);
    });

    testWidgets('an open request: the chip on the tile and the row in «Что дальше»', (tester) async {
      await pumpRoute(tester, routeMe(status: 'waiting', decisions: [], signals: [signal('request_redirect', open: true, toMoCode: '22GN')]));
      expect(find.text('Запрос отправлен'), findsOneWidget);
      expect(find.text('Вы попросили рассмотреть: Достар Мед'), findsOneWidget);
      expect(find.text('Ждёт ответа врача'), findsOneWidget);
    });

    testWidgets('while a transfer is decided: no request buttons and «Сейчас просить о переводе нельзя…»', (tester) async {
      await pumpRoute(tester, routeMe());
      expect(find.text('Попросить рассмотреть'), findsNothing);
      expect(find.text('Сейчас просить о переводе нельзя: решение по маршруту уже принято.'), findsOneWidget);
      expect(find.text('Не хотите переводиться?'), findsNothing);
    });

    testWidgets('a hospital of a neighbour region is captioned with the region name from the regions list', (tester) async {
      final backend = await pumpRoute(tester, routeMe(status: 'waiting', decisions: [], signals: [], alternatives: [neighbour('19AB', '19', 1)]), api: {
        '/refdata/regions': {
          'items': [
            {'regionKato': '19', 'name': 'Алматинская область'},
            {'regionKato': '75', 'name': 'г. Алматы'},
          ],
        },
      });
      expect(find.text('19AB · сосед: Алматинская область'), findsOneWidget);
      expect(backend.calls('GET', '/refdata/regions'), hasLength(1));
    });

    testWidgets('no neighbour region — the regions list is not requested; no tiles — the empty text', (tester) async {
      final backend = await pumpRoute(tester, routeMe(status: 'waiting', decisions: [], signals: [], alternatives: []));
      expect(find.text('Других организаций с этим профилем в регионе нет.'), findsOneWidget);
      expect(backend.calls('GET', '/refdata/regions'), isEmpty);
    });

    testWidgets('«Не хотите переводиться?»: «Хочу остаться» sends prefer_current; the made choice is shown', (tester) async {
      final backend = await pumpRoute(tester, routeMe(status: 'waiting', decisions: [], signals: []), api: {'POST $signalsPath': recorded()});
      expect(find.text('Не хотите переводиться?'), findsOneWidget);
      await tapAction(tester, 'Хочу остаться в своей больнице');
      expect(backend.lastBody('POST', signalsPath), {'kind': 'prefer_current'});
      await tapAction(tester, 'Больше не нужно');
      expect(find.text('Снять вас с листа ожидания?'), findsOneWidget, reason: '«Больше не нужно» и здесь — через лист подтверждения');

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpRoute(tester, routeMe(status: 'kept', prefersCurrent: true, allowed: ['request_transfer', 'still_waiting', 'withdraw'], decisions: [], signals: []));
      expect(find.textContaining('Вы остаётесь в своей больнице.'), findsOneWidget);
      expect(find.text('Хочу остаться в своей больнице'), findsNothing);
    });
  });

  group('forecast, «Что дальше» and analyses', () {
    testWidgets('forecast: sentence first, ≈ p50, p90 and the 30-day share, the model tag, the MoH benchmark with its source', (tester) async {
      await pumpRoute(tester, routeMe(status: 'waiting', decisions: [], signals: []));
      expect(find.text('ПРОГНОЗ'), findsOneWidget);
      expect(find.text('Половина пациентов в этой очереди ждёт госпитализации не больше'), findsOneWidget);
      expect(find.descendant(of: find.byType(HeroNumber), matching: find.text('≈ 2')), findsOneWidget);
      expect(find.text('9 из 10 пациентов ждут не больше 21 дн.\n56 % пациентов попадают в больницу в течение 30 дней.'), findsOneWidget);
      expect(find.text('прогноз модели'), findsWidgets);
      expect(find.text('Ориентир Минздрава РК — ждать не больше 20 дн.'), findsOneWidget);
      await tapAction(tester, 'Источник');
      expect(find.textContaining('Источник: МЗ РК, расширенная коллегия'), findsOneWidget);
    });

    testWidgets('a rule-based forecast without the 30-day share: «расчёт по правилу», p90 line only', (tester) async {
      await pumpRoute(tester, routeMe(status: 'waiting', decisions: [], signals: [], forecast: {'fromModel': false, 'pWithin30Days': null}));
      expect(find.text('9 из 10 пациентов ждут не больше 21 дн.'), findsOneWidget);
      expect(find.textContaining('в течение 30 дней'), findsNothing);
      expect(find.text('расчёт по правилу'), findsWidgets);
    });

    testWidgets('«Что дальше»: the date row, expired tests with «Посмотреть» that opens «Анализы», the next stage norm', (tester) async {
      await pumpRoute(tester, routeMe(status: 'waiting', decisions: [], signals: []));
      expect(find.text('ЧТО ДАЛЬШЕ'), findsOneWidget);
      expect(find.text('Дата госпитализации'), findsOneWidget);
      expect(find.descendant(of: find.byType(RouteNextCard), matching: find.text('31.03.2025')), findsOneWidget);
      expect(find.text('Обновить анализы: 7 истекли'), findsOneWidget);
      expect(find.text('Действуют: 3'), findsOneWidget);
      expect(find.textContaining('Норма срока: Планируемая дата'), findsOneWidget);
      expect(find.text('Срок действия истёк'), findsNothing);
      await tapAction(tester, 'Посмотреть');
      expect(find.text('Срок действия истёк'), findsOneWidget, reason: '«Посмотреть» раскрывает «Анализы»');
    });

    testWidgets('a failed transfer while waiting: «Перевод не состоялся» in the citizen voice with the reason', (tester) async {
      await pumpRoute(tester, routeMe(status: 'kept', decisions: [], signals: [], lastAttempt: {
        'outcome': 'declined',
        'toMoCode': '031N',
        'toMoName': militaryHospital,
        'at': '2026-09-28T10:00:00+00:00',
        'reason': 'далеко',
      }));
      expect(find.text('Перевод не состоялся'), findsOneWidget);
      expect(find.text('Вы отказались от перевода — «далеко»'), findsOneWidget);
    });
  });

  group('scribe consent, leaflets, journal, history', () {
    testWidgets('a pending recording request comes first; «Разрешаю» answers it and the answer is confirmed', (tester) async {
      final backend = await pumpRoute(tester, routeMe(), api: {
        '/route/me/scribe': [scribeConsent('req-1', 'pending', comment: 'обсудим результаты')],
        'POST /route/me/scribe/req-1/answer': recorded(),
      });
      expect(find.text('Врач просит разрешение записать приём'), findsOneWidget);
      expect(find.textContaining('ГКБ №7: приём запишут'), findsOneWidget);
      expect(find.text('«обсудим результаты»'), findsOneWidget);
      final scribeTop = tester.getTopLeft(find.text('Врач просит разрешение записать приём')).dy;
      expect(scribeTop, lessThan(tester.getTopLeft(find.text('Врач предлагает перевод')).dy), reason: 'запрос записи — над карточкой состояния');
      await tapAction(tester, 'Разрешаю');
      expect(backend.lastBody('POST', '/route/me/scribe/req-1/answer'), {'granted': true});
      expect(find.text('Ответ отправлен врачу'), findsOneWidget);
    });

    testWidgets('a granted consent is a thin bar with «Отозвать»; a 409 shows the server explanation', (tester) async {
      final backend = await pumpRoute(tester, routeMe(), api: {
        '/route/me/scribe': [scribeConsent('req-2', 'granted')],
        'POST /route/me/scribe/req-2/answer': problem(409, 'Согласие', detail: 'запись уже начата — отозвать согласие нельзя'),
      });
      expect(find.text('Вы разрешили записать приём сегодня'), findsOneWidget);
      await tapAction(tester, 'Отозвать');
      expect(backend.lastBody('POST', '/route/me/scribe/req-2/answer'), {'granted': false});
      expect(find.text('Согласие — запись уже начата — отозвать согласие нельзя'), findsOneWidget);
    });

    testWidgets('«Памятки врача» opens the leaflet reader nested under «Мой путь»', (tester) async {
      final (session, _) = await demoSession(DemoUser.citizen1, api: {
        '/route/me': routeMe(status: 'waiting', decisions: [], signals: []),
        '/route/me/scribe': [scribeConsent('req-3', 'completed', token: 'tok-abc', approvedAt: '2026-09-30T07:00:00+00:00')],
        '/scribe/leaflets/tok-abc': {'text': 'Пейте воду.', 'language': 'ru', 'approvedAt': '2026-09-30T07:00:00+00:00'},
      });
      final router = await pumpRouterApp(tester, session, location: '/home/route', size: phoneTall);
      await tester.scrollUntilVisible(find.text('ПАМЯТКИ ВРАЧА'), 300);
      await tapAction(tester, 'Открыть');
      expect(router.state.uri.path, '/home/route/leaflet/tok-abc');
      expect(find.textContaining('Пейте воду.'), findsOneWidget);
    });

    testWidgets('journal and past referrals are collapsed with their counts; the footnote names the basis and the Standard', (tester) async {
      await pumpRoute(tester, routeMe(status: 'waiting', decisions: [], signals: []));
      await tester.scrollUntilVisible(find.text('Решения и запросы'), 300);
      expect(find.text('6'), findsOneWidget);
      await tapAction(tester, 'Решения и запросы');
      expect(find.text('Врач предложил перевод: Достар Мед'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Прошлые направления'), 300);
      expect(find.text('3'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('Стандарт стационарной помощи, приказ МЗ РК ҚР-ДСМ-27'), 300);
      expect(find.textContaining('Синтетический маршрут: пациент выдуман'), findsOneWidget);
      expect(find.textContaining('Синтетический маршрут на реальных очередях · данные на 31.03.2025'), findsOneWidget);
    });
  });

  testWidgets('kazakh at 1.3 on a 360 dp phone: tiles, stay block, scribe card and leaflets fit', (tester) async {
    await pumpRoute(
      tester,
      routeMe(status: 'waiting', decisions: [], signals: [], alternatives: [neighbour('19AB', '19', 1), ...(fixtureMap('route-me')['alternatives'] as List).cast<Map<String, dynamic>>()]),
      api: {
        '/route/me/scribe': [scribeConsent('req-4', 'pending'), scribeConsent('req-5', 'completed', token: 'tok-kk', approvedAt: '2026-09-30T07:00:00+00:00')],
        '/refdata/regions': {
          'items': [
            {'regionKato': '19', 'name': 'Алматы облысы'},
          ],
        },
      },
      locale: 'kk',
      textScale: 1.3,
      size: phoneNarrow,
    );
    expect(find.text('Дәрігер қабылдауды жазуға рұқсат сұрайды'), findsOneWidget);
    for (final text in ['ҚАЙДА ТЕЗІРЕК', 'Ауысқыңыз келмей ме?', 'ДӘРІГЕР ЖАДЫНАМАЛАРЫ', 'Шешімдер мен сұраулар']) {
      await tester.scrollUntilVisible(find.text(text), 300);
      expect(tester.takeException(), isNull, reason: text);
    }
    expect(find.text('19AB · көрші: Алматы облысы'), findsOneWidget);
  });
}
