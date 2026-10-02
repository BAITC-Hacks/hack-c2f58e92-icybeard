import 'dart:convert';

import 'package:darumen/api/almaty_time.dart';
import 'package:darumen/l10n/strings.dart';
import 'package:darumen/screens/referral_screen.dart';
import 'package:darumen/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/harness.dart';

/// Ассистент направления (ReferralScreen) через harness: прогноз и альтернативы по полной форме (тела запросов как у
/// веба), варианты выбора, четыре числа и факторы, запись выбора в журнал (subjectId `регион.организация.профиль.дата`,
/// ключ идемпотентности, двойное нажатие — одна запись), риск словами, 422 под полями, сервис моделей недоступен,
/// выбор организации, казахский при крупном шрифте на узком телефоне.
final ru = S.of('ru');
const clinic = 'ТОО "Глазная клиника"';

Map<String, Object?> prediction({double p50 = 40.4, double pRefusal = 0.12, bool inTraining = true}) => {
      'p50Days': p50,
      'p90Days': 90,
      'pWithin30Days': 0.35,
      'pRefusal': pRefusal,
      'queue': {'len': 133, 'ageP50': 21, 'throughputPerDay': 2.4},
      'explanation': {
        'summary': '',
        'factors': [
          {'name': 'queue_len', 'contribution': 9.0, 'text': 'Длина очереди: 133 (+9.0 дн.)'},
          {'name': 'same_mo', 'contribution': 6.2, 'text': 'Направляет эта же МО: False (+6.2 дн.)'},
        ],
      },
      'model': {'name': 'wait', 'version': '1', 'trainedThrough': '2025-03-31'},
      'refusalOrgInTraining': inTraining,
    };

Map<String, Object?> alternative(String code, String name, double p50, {double pRefusal = 0.1, bool neighbour = false, String region = '75'}) => {
      'mo': {'moCode': code, 'name': name, 'regionKato': region},
      'p50Days': p50,
      'p90Days': p50 * 2,
      'pRefusal': pRefusal,
      'distanceKm': 4.2,
      'isNeighborRegion': neighbour,
    };

Map<String, Object?> api([Map<String, Object?> more = const {}]) => {
      '/refdata/regions': {
        'items': [
          {'regionKato': '75', 'name': 'г. Алматы'},
          {'regionKato': '19', 'name': 'Алматинская область'},
        ],
      },
      '/refdata/profiles': {
        'items': [
          {'profileCode': '381', 'name': 'Офтальмологические'},
        ],
      },
      '/refdata/organizations': (http.Request r) => {
            'items': [
              {'moCode': '028B', 'name': clinic},
              {'moCode': '22GN', 'name': 'ТОО "Достар Мед"'},
              {'moCode': '031N', 'name': 'ГУ "Военный госпиталь"'},
              if (r.url.queryParameters['profileCode'] == null) {'moCode': '08IV', 'name': 'КГП "Онкоцентр"'},
            ],
          },
      'POST /queue/predict': prediction(),
      'POST /queue/alternatives': {
        'items': [
          alternative('031N', 'ГУ "Военный госпиталь"', 12, pRefusal: 0.25),
          alternative('028B', clinic, 40.4),
          alternative('22GN', 'ТОО "Достар Мед"', 50),
          alternative('19AB', 'ТОО "Областная клиника"', 30, neighbour: true, region: '19'),
        ],
      },
      'POST /journal/decisions': recorded('dec-1'),
      ...more,
    };

Future<DemoBackend> pumpAssistant(WidgetTester tester, {Map<String, Object?> more = const {}, String? moCode = '028B', String locale = 'ru', double textScale = 1, Size size = phoneTall}) async {
  final (session, backend) = await demoSession(DemoUser.doctor1, api: api(more));
  await pumpScreen(tester, session, ReferralScreen(moCode: moCode, profileCode: '381'), locale: locale, textScale: textScale, size: size);
  return backend;
}

Finder rich(String text) => find.textContaining(text, findRichText: true);

/// Прокрутить длинную форму (ленивый список) до [finder]: построенный — к нему, ещё не построенный — тянуть вниз,
/// пока он не окажется под пальцем.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  final list = find.byType(Scrollable).first;
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 300, scrollable: list);
  }
  await tester.ensureVisible(finder.first);
  await tester.pump();
  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder.hitTestable(), 300, scrollable: list);
  }
}

/// Вернуться к началу формы (у экрана нет «потяни, чтобы обновить» — рывок вниз только прокручивает).
Future<void> toTop(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, 5000));
  await pumpFrames(tester);
}

Future<void> tapText(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.tap(finder.first);
  await pumpFrames(tester);
}

ButtonStyleButton button(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first);

void main() {
  testWidgets('новое направление: прогноз по полной форме, варианты, четыре числа, факторы и запись выбора в журнал', (tester) async {
    final backend = await pumpAssistant(tester);
    expect(backend.lastBody('POST', '/queue/predict'), {
      'regionKato': '75',
      'moCode': '028B',
      'profileCode': '381',
      'icd10': '',
      'referralPurpose': 'Оперативное лечение',
      'territorialType': 'Город',
      'financeSource': 'Активы Фонда на ОСМС',
      'registrationDate': '',
      'referringMoCode': '',
    });
    expect(backend.lastBody('POST', '/queue/alternatives'), containsPair('includeNeighbors', false));
    expect(backend.lastBody('POST', '/queue/alternatives'), containsPair('limit', 5));

    expect(find.text('Ассистент направления'), findsOneWidget);
    expect(find.text('${ru.assistLead} · данные на 2025-03-31'), findsOneWidget);
    expect(rich('028B · выбрана врачом · в очереди 133 · риск отказа 12 %'), findsOneWidget);
    expect(rich('031N · на 28 дн. быстрее · риск отказа 25 %'), findsOneWidget);
    expect(rich('22GN · на 10 дн. дольше'), findsOneWidget);
    expect(rich('19AB · сосед: Алматинская область · на 10 дн. быстрее'), findsOneWidget);
    expect(find.text('Глазная клиника'), findsWidgets);

    await reveal(tester, find.text('ПРОГНОЗ ДЛЯ «ГЛАЗНАЯ КЛИНИКА»'));
    expect(find.text('ПРОГНОЗ ДЛЯ «ГЛАЗНАЯ КЛИНИКА»'), findsOneWidget, reason: 'заголовок раздела — kicker прописными, как на вебе');
    expect(find.text('≈ 40 дн.'), findsOneWidget, reason: 'половина ждёт');
    expect(find.text('35 %'), findsOneWidget);
    expect(tester.widget<Text>(find.text('12 %')).style?.color, isNot(ColorTokens.light.danger), reason: 'риск 12 % — не красный');
    expect(find.text('В очереди 133 направлений, медианный возраст 21 дн., 2.4 госпитализаций в день.'), findsOneWidget);
    await tapText(tester, find.text(ru.factorsTitle));
    expect(find.text(ru.assistReferringUnset), findsOneWidget);
    expect(find.text(ru.assistReferringUnsetHint), findsOneWidget);

    await toTop(tester);
    await tapText(tester, find.text('Военный госпиталь'));
    await reveal(tester, rich('вместо «Глазная клиника»'));
    expect(rich('вместо «Глазная клиника»'), findsOneWidget);
    await reveal(tester, find.widgetWithText(TextField, ru.assistReason));
    await tester.enterText(find.widgetWithText(TextField, ru.assistReason), '  ближе к дому  ');
    expect(find.text(ru.assistSaveNote), findsOneWidget);

    await tester.tap(find.text(ru.assistSaveChoice));
    await tester.tap(find.text(ru.assistSaveChoice), warnIfMissed: false);
    await pumpFrames(tester);
    final calls = backend.calls('POST', '/journal/decisions');
    expect(calls, hasLength(1), reason: 'двойное нажатие — одна запись');
    expect(jsonDecode(calls.single.body), {
      'subject': 'referral',
      'subjectId': '75.028B.381.${almatyTodayString()}',
      'recommended': {'moCode': '031N'},
      'chosen': {'moCode': '031N'},
      'reason': 'ближе к дому',
    });
    expect(calls.single.headers['Idempotency-Key'], isNotEmpty);
    expect(find.text('${ru.assistDecisionRecorded}\n${ru.assistToJournal}'), findsOneWidget);
    expect(button(tester, ru.assistRecorded).enabled, isFalse);
    expect(find.text(ru.decisionsTitle), findsOneWidget, reason: 'ссылка на журнал после записи');
    expect(tester.takeException(), isNull);
  });

  testWidgets('без причины выбор тоже записывается (Q-6); дата постановки попадает в subjectId', (tester) async {
    final backend = await pumpAssistant(tester);
    await tapText(tester, find.text(ru.assistMore));
    await tester.enterText(find.widgetWithText(TextField, ru.assistRegistrationDate), '2025-03-01');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFrames(tester);
    expect(backend.lastBody('POST', '/queue/predict')['registrationDate'], '2025-03-01');
    await tester.tap(find.text(ru.assistSaveChoice));
    await pumpFrames(tester);
    expect(backend.lastBody('POST', '/journal/decisions'), {
      'subject': 'referral',
      'subjectId': '75.028B.381.2025-03-01',
      'recommended': {'moCode': '031N'},
      'chosen': {'moCode': '028B'},
      'reason': '',
    });
  });

  testWidgets('больница вне обучения: риск словами и пояснение; направляющая организация — новый расчёт и подпись кита', (tester) async {
    final backend = await pumpAssistant(tester, more: {'POST /queue/predict': prediction(pRefusal: 0.29, inTraining: false)});
    expect(rich('риск отказа выше среднего'), findsOneWidget);
    await reveal(tester, find.text(ru.assistUnseenOrgHint));
    expect(find.text(ru.assistUnseenOrgHint), findsOneWidget);
    expect(find.text('выше среднего'), findsOneWidget, reason: 'в четырёх числах — тоже словами');
    expect(tester.widget<Text>(find.text('выше среднего')).style?.color, ColorTokens.light.danger, reason: 'риск выше 20 % — красный, как в вебе');

    await toTop(tester);
    await tapText(tester, find.text(ru.assistMore));
    await tapText(tester, find.text(ru.assistNotSpecified));
    await tapText(tester, find.text('Онкоцентр'));
    expect(backend.lastBody('POST', '/queue/predict')['referringMoCode'], '08IV');
    await tapText(tester, find.text(ru.factorsTitle));
    expect(find.text(ru.assistReferringUnset), findsNothing);
    expect(find.text(ru.factorSameMo(false)), findsOneWidget);
  });

  testWidgets('422 — сообщения под полями «Профиль койки» и «Дата постановки в очередь»; чисел нет', (tester) async {
    final backend = await pumpAssistant(tester);
    backend.routes['POST /queue/predict'] = problem(422, 'One or more validation errors occurred.', errors: {
      'registrationDate': ['ожидается дата yyyy-MM-dd'],
    });
    await tapText(tester, find.text(ru.assistMore));
    await tester.enterText(find.widgetWithText(TextField, ru.assistRegistrationDate), '01.03.2025');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFrames(tester);
    expect(find.text('ожидается дата yyyy-MM-dd'), findsWidgets, reason: 'под полем и в плашке');
    expect(find.text('≈ 40 дн.'), findsNothing);
    expect(find.text(ru.assistSaveChoice), findsNothing, reason: 'без прогноза записывать нечего');
  });

  testWidgets('сервис моделей недоступен (503): «Сервер недоступен», чисел нет, «Повторить» считает заново', (tester) async {
    final backend = await pumpAssistant(tester, more: {'POST /queue/predict': problem(503, 'Сервис моделей недоступен')});
    expect(find.text(ru.apiServerUnavailable), findsOneWidget);
    expect(find.text(ru.assistFillForm), findsOneWidget);
    expect(find.text('≈ 40 дн.'), findsNothing);
    backend.routes['POST /queue/predict'] = prediction();
    await tapText(tester, find.text(ru.retry));
    expect(find.text(ru.apiServerUnavailable), findsNothing);
    expect(rich('выбрана врачом'), findsOneWidget);
  });

  testWidgets('без организации: «Выберите организацию», прогноза нет; выбор считает прогноз; «Сменить организацию» возвращает выбор', (tester) async {
    final backend = await pumpAssistant(tester, moCode: null);
    expect(backend.calls('POST', '/queue/predict'), isEmpty);
    expect(find.text(ru.assistFillForm), findsOneWidget);
    await tapText(tester, find.text(ru.assistPickOrg));
    await tapText(tester, find.text('Глазная клиника'));
    expect(backend.lastBody('POST', '/queue/predict')['moCode'], '028B');
    expect(rich('выбрана врачом'), findsOneWidget);

    await tapText(tester, find.text(ru.assistChangeOrg));
    expect(find.text(ru.assistPickOrg), findsOneWidget);
    expect(rich('выбрана врачом'), findsNothing);
    expect(backend.calls('POST', '/queue/predict'), hasLength(1));
  });

  testWidgets('маршрут /doctor/referral?moCode&profileCode открывает ассистент с организацией и профилем из ссылки', (tester) async {
    final (session, backend) = await demoSession(DemoUser.doctor1, api: api());
    final router = await pumpRouterApp(tester, session, location: '/doctor/referral?moCode=028B&profileCode=381');
    expect(router.state.uri.path, '/doctor/referral');
    expect(find.byType(ReferralScreen), findsOneWidget);
    expect(backend.lastBody('POST', '/queue/predict'), allOf(containsPair('moCode', '028B'), containsPair('profileCode', '381')));
  });

  testWidgets('казахский при масштабе 1.3 на телефоне 360 dp: форма, варианты, прогноз и решение без переполнения', (tester) async {
    await pumpAssistant(tester, locale: 'kk', textScale: 1.3, size: phoneNarrow);
    final kk = S.of('kk');
    expect(find.text(kk.assistTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final text in [kk.assistWhere.toUpperCase(), kk.assistForecastFor('Глазная клиника').toUpperCase(), kk.assistDecision.toUpperCase(), kk.assistSaveNote]) {
      await reveal(tester, find.text(text));
      await pumpFrames(tester);
      expect(tester.takeException(), isNull, reason: text);
    }
  });
}
