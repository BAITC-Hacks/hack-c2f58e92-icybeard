import 'dart:async';
import 'dart:convert';

import 'package:darumen/config/env.dart';
import 'package:darumen/l10n/strings.dart';
import 'package:darumen/screens/scribe_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import 'support/harness.dart';

/// Экран AI-скрайба врача (ScribeScreen) через harness: три шага до записи, запрос согласия и опрос каждые 5 с,
/// начало и продолжение записи, вставка текста, правка фразы, исправление терминов, утверждение и итог; ошибки
/// 409/403/404/422/429; казахский при крупном шрифте на узком телефоне.
const ref = 'SYN-75-028B-381-03';
final ru = S.of('ru');

Map<String, Object?> consent(String id, String status, {String? sessionId}) => {
      'requestId': id,
      'patientRef': ref,
      'moCode': '028B',
      'requestedRole': 'doctor',
      'requestedAt': '2026-10-01T09:00:00+00:00',
      'day': '2026-10-01',
      'status': status,
      'answeredAt': status == 'pending' ? null : '2026-10-01T09:05:00+00:00',
      'sessionId': ?sessionId,
    };

Map<String, Object?> segment(String text, {double t0 = 0, String? original, String? source}) =>
    {'t0': t0, 't1': t0 + 4, 'text': text, 'original': ?original, 'source': ?source};

const health = {'status': 'ok', 'transcriber': 'faster-whisper', 'drafter': 'stub', 'transcriberState': 'ready'};

/// Сессия с пустой стенограммой — «Продолжить запись» открывает рабочую область.
Map<String, Object?> recordingApi([Map<String, Object?> more = const {}]) => {
      '/scribe-consents': [consent('r1', 'recording', sessionId: 's1')],
      '/scribe/sessions/s1': {'sessionId': 's1', 'language': 'ru', 'approved': false, 'transcript': <Object?>[]},
      ...more,
    };

Future<DemoBackend> pumpScribe(WidgetTester tester, Map<String, Object?> api, {String locale = 'ru', double textScale = 1, Size size = phoneTall}) async {
  final (session, backend) = await demoSession(DemoUser.doctor1, api: {'/scribe/health': health, ...api});
  await pumpScreen(tester, session, const ScribeScreen(patientRef: ref), locale: locale, textScale: textScale, size: size);
  return backend;
}

/// Кнопка с подписью [label] (FilledButton, OutlinedButton, TextButton и их варианты с иконкой).
ButtonStyleButton button(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first);

/// Тап по тексту: сначала прокрутить к нему (в длинном ленивом списке оценка его высоты бывает мала для
/// `ensureVisible` — тогда список тянется, пока текст не окажется под пальцем).
Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).first;
  await tester.ensureVisible(finder);
  await tester.pump();
  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder.hitTestable(), 300, scrollable: find.byType(Scrollable).first);
  }
  await tester.tap(finder);
  await pumpFrames(tester);
}

Future<void> resume(WidgetTester tester) => tapText(tester, ru.aiScribeResume);

/// Канал плагина записи: в тестах у него нет платформы, а его общий семафор ждёт ответа на `create` — без заглушки
/// любой вызов рекордера висит. Разрешения на микрофон нет (как отказ пользователя).
const recordChannel = MethodChannel('com.llfbandit.record/messages');

/// Что ушло в буфер обмена (`Clipboard.setData`) в текущем тесте.
String? clipboard;

Future<void> pasteSample(WidgetTester tester, S s) async {
  await tapText(tester, s.aiScribePasteText);
  await tapText(tester, s.aiScribePasteSample);
  await tapText(tester, s.aiScribeUseText);
}

void main() {
  setUp(() {
    clipboard = null;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(recordChannel, (call) async => call.method == 'hasPermission' ? false : null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      return null;
    });
  });
  tearDown(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(recordChannel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('до записи', () {
    testWidgets('согласие получено: три шага; «Начать запись» шлёт consentId и выбранный язык; дальше — карточка записи', (tester) async {
      var list = [consent('r1', 'granted')];
      final backend = await pumpScribe(tester, {
        '/scribe-consents': (http.Request r) => list,
        'POST /scribe/sessions': (http.Request r) {
          list = [consent('r1', 'recording', sessionId: 's1')];
          return json({'sessionId': 's1', 'consentId': 'r1', 'patientRef': ref}, 201);
        },
      });
      expect(find.text('Пациент $ref · аудио удаляется при утверждении'), findsOneWidget);
      expect(find.text(ref), findsOneWidget, reason: 'шаг 1 — пациент без выбора');
      expect(find.text('Согласие получено'), findsOneWidget);
      expect(find.text('Согласие действует на один приём сегодня.'), findsOneWidget);
      expect(find.text('Отменить запрос'), findsOneWidget);
      expect(find.text('Запросить снова'), findsNothing);
      expect(find.text(ru.aiScribeWhat2), findsOneWidget);
      expect(find.textContaining('черновик'), findsNothing, reason: 'Q-11: текст описывает реальный порядок');
      expect(backend.calls('GET', '/scribe-consents').single.url.queryParameters['patientRef'], ref);

      await tapText(tester, 'Қазақша');
      await tapText(tester, 'Начать запись');
      final call = backend.calls('POST', '/scribe/sessions').single;
      expect(jsonDecode(call.body), {'consentId': 'r1', 'language': 'kk'});
      expect(call.headers.containsKey('Idempotency-Key'), isFalse);
      expect(find.text('Записать с микрофона'), findsOneWidget);
      expect(find.text('Готово к записи'), findsOneWidget);
      expect(find.text(ru.aiScribeNoTranscript), findsOneWidget);
      expect(find.text('Начать запись'), findsNothing);
      expect(find.text('Қазақша'), findsOneWidget, reason: 'язык заблокирован и показан чипом');
      expect(button(tester, ru.aiScribeApprove).enabled, isFalse, reason: 'утверждать нечего');
      expect(tester.takeException(), isNull);
    });

    testWidgets('нет запроса: «Запросить согласие» → тост, «ждём ответа» и опрос каждые 5 с, пока пациент не ответит', (tester) async {
      var list = <Map<String, Object?>>[];
      final backend = await pumpScribe(tester, {
        '/scribe-consents': (http.Request r) => list,
        'POST /scribe-consents': (http.Request r) {
          list = [consent('r2', 'pending')];
          return recorded('r2');
        },
      });
      expect(find.text('Не запрошено'), findsOneWidget);
      expect(find.text('Пациент получит уведомление и ответит в своём кабинете.'), findsOneWidget);
      expect(find.text(ru.aiScribeNeedConsent), findsOneWidget);
      expect(button(tester, 'Начать запись').enabled, isFalse);

      await tapText(tester, 'Запросить согласие');
      final call = backend.calls('POST', '/scribe-consents').single;
      expect(jsonDecode(call.body), {'patientRef': ref});
      expect(call.headers['Idempotency-Key'], isNotEmpty);
      expect(find.text('Запрос отправлен пациенту'), findsOneWidget);
      expect(find.text('Ждём ответа'), findsOneWidget);
      expect(find.text('Пациент получил уведомление. Статус обновится сам.'), findsOneWidget);

      final reads = backend.calls('GET', '/scribe-consents').length;
      list = [consent('r2', 'granted')];
      await tester.pump(const Duration(seconds: 5));
      await pumpFrames(tester);
      expect(backend.calls('GET', '/scribe-consents').length, reads + 1);
      expect(find.text('Согласие получено'), findsOneWidget);
      expect(button(tester, 'Начать запись').enabled, isTrue);
      await tester.pump(const Duration(seconds: 10));
      expect(backend.calls('GET', '/scribe-consents').length, reads + 1, reason: 'согласие получено — опрос остановлен');
    });

    testWidgets('отказ пациента: «Запросить снова»; 409 «Запрос уже отправлен» — без ошибки, просто перечитали', (tester) async {
      var list = [consent('r1', 'declined')];
      final backend = await pumpScribe(tester, {
        '/scribe-consents': (http.Request r) => list,
        'POST /scribe-consents': (http.Request r) {
          list = [consent('r3', 'pending')];
          return problem(409, 'Запрос уже отправлен', detail: 'у пациента уже есть действующий запрос согласия на сегодня');
        },
      });
      expect(find.text('Пациент отказался'), findsOneWidget);
      expect(find.text('Без согласия записывать приём нельзя.'), findsOneWidget);
      await tapText(tester, 'Запросить снова');
      expect(backend.calls('POST', '/scribe-consents'), hasLength(1));
      expect(find.textContaining('Запрос уже отправлен'), findsNothing);
      expect(find.text('Запрос отправлен пациенту'), findsNothing);
      expect(find.text('Ждём ответа'), findsOneWidget);
    });

    testWidgets('отмена запроса: POST …/cancel; 409 — сначала перечитали, потом текст сервера', (tester) async {
      var list = [consent('r1', 'pending')];
      final backend = await pumpScribe(tester, {
        '/scribe-consents': (http.Request r) => list,
        'POST /cancel': (http.Request r) {
          list = [consent('r1', 'recording', sessionId: 's1')];
          return problem(409, 'Действие недоступно', detail: 'запрос уже закрыт или запись начата — отменить нельзя');
        },
      });
      await tapText(tester, 'Отменить запрос');
      expect(jsonDecode(backend.calls('POST', '/scribe-consents/r1/cancel').single.body), {'patientRef': ref});
      expect(find.text('Действие недоступно — запрос уже закрыт или запись начата — отменить нельзя'), findsOneWidget);
      expect(find.text('Запись не утверждена'), findsOneWidget);
    });

    testWidgets('409 при начале: сначала перечитали согласие, потом текст сервера', (tester) async {
      var list = [consent('r1', 'granted')];
      await pumpScribe(tester, {
        '/scribe-consents': (http.Request r) => list,
        'POST /scribe/sessions': (http.Request r) {
          list = [consent('r1', 'withdrawn')];
          return problem(409, 'Действие недоступно', detail: 'пациент не дал согласия на запись');
        },
      });
      await tapText(tester, 'Начать запись');
      expect(find.text('Действие недоступно — пациент не дал согласия на запись'), findsOneWidget);
      expect(find.text('Пациент отозвал согласие'), findsOneWidget);
      expect(find.text('Записать с микрофона'), findsNothing);
    });

    testWidgets('сервис: 429 — «повторите позже», а не «не запущен»; сбой — «Сервис скрайба не запущен»', (tester) async {
      final backend = await pumpScribe(tester, {'/scribe-consents': [consent('r1', 'granted')], '/scribe/health': problem(429, 'Too Many Requests')});
      expect(find.text(ru.apiRateLimited), findsOneWidget);
      expect(find.text(ru.aiScribeServiceDown), findsNothing);
      expect(button(tester, 'Начать запись').enabled, isFalse);
      backend.routes['/scribe/health'] = problem(502, 'Bad Gateway');
      await tester.pump(const Duration(seconds: 12));
      await pumpFrames(tester);
      expect(find.text(ru.aiScribeServiceDown), findsOneWidget);
      expect(find.text(ru.apiRateLimited), findsNothing);
    });

    testWidgets('пациент другой больницы (403) — состояние «нет доступа» с причиной сервера', (tester) async {
      await pumpScribe(tester, {
        '/scribe-consents': problem(403, 'Пациент другой больницы', detail: 'запрашивать согласие и записывать приём может только больница пациента'),
      });
      expect(find.text(ru.noAccessTitle), findsOneWidget);
      expect(find.text('Пациент другой больницы — запрашивать согласие и записывать приём может только больница пациента'), findsOneWidget);
      expect(find.text('Начать запись'), findsNothing);
    });
  });

  group('начатая запись', () {
    testWidgets('«Продолжить запись»: фразы с метками и пометкой правки, исходный текст и «вернуть»', (tester) async {
      final backend = await pumpScribe(tester, recordingApi({
        '/scribe/sessions/s1': {
          'sessionId': 's1',
          'language': 'ru',
          'approved': false,
          'transcript': [segment('Давление 150 на 95.'), segment('Назначаю амлодипин 5 мг утром.', t0: 4, original: 'Назначаю амлодепин 5 мг утром.', source: 'ai')],
        },
        'POST /segments/1': {'transcript': [segment('Давление 150 на 95.'), segment('Назначаю амлодепин 5 мг утром.', t0: 4)]},
      }));
      expect(find.text('Запись не утверждена'), findsOneWidget);
      expect(find.text(ru.aiScribeResumeHint), findsOneWidget);
      await resume(tester);
      expect(backend.calls('GET', '/scribe/sessions/s1'), hasLength(1));
      expect(find.text('Давление 150 на 95.'), findsOneWidget);
      expect(find.text('00:00–00:04 · RU'), findsOneWidget);
      expect(find.text('Исправил ИИ'), findsOneWidget);
      expect(find.text('ИСХОДНЫЙ ТЕКСТ РАСПОЗНАВАНИЯ'), findsOneWidget);
      expect(find.text('Назначаю амлодепин 5 мг утром.'), findsOneWidget);
      expect(find.text('Стенограмма готова'), findsOneWidget);

      await tapText(tester, 'вернуть');
      expect(backend.lastBody('POST', '/scribe/sessions/s1/segments/1'), {'text': 'Назначаю амлодепин 5 мг утром.'});
      expect(find.text('ИСХОДНЫЙ ТЕКСТ РАСПОЗНАВАНИЯ'), findsNothing);
    });

    testWidgets('запись потеряна (404 при продолжении): подсказка и только «Отменить запись»', (tester) async {
      await pumpScribe(tester, recordingApi({'/scribe/sessions/s1': problem(404, 'Скрайб', detail: 'session not found')}));
      await resume(tester);
      expect(find.text(ru.aiScribeSessionLost), findsOneWidget);
      expect(find.text(ru.aiScribeResume), findsNothing);
      expect(find.text(ru.aiScribeDiscard), findsOneWidget);
    });

    testWidgets('отмена записи спрашивает подтверждение, говорит про аудио и новое согласие и шлёт discard', (tester) async {
      var list = [consent('r1', 'recording', sessionId: 's1')];
      final backend = await pumpScribe(tester, recordingApi({
        '/scribe-consents': (http.Request r) => list,
        'POST /discard': (http.Request r) {
          list = [consent('r1', 'discarded')];
          return recorded();
        },
      }));
      await tapText(tester, ru.aiScribeDiscard);
      expect(find.text(ru.aiScribeDiscardQuestion), findsOneWidget);
      expect(find.text(ru.aiScribeDiscardHint), findsOneWidget);
      await tapText(tester, ru.aiScribeDiscardKeep);
      expect(backend.calls('POST', '/discard'), isEmpty);

      await tapText(tester, ru.aiScribeDiscard);
      await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text(ru.aiScribeDiscard)));
      await pumpFrames(tester);
      final call = backend.calls('POST', '/scribe-consents/r1/discard').single;
      expect(jsonDecode(call.body), {'patientRef': ref});
      expect(call.headers.containsKey('Idempotency-Key'), isFalse);
      expect(find.text(ru.aiScribeDiscardDone), findsOneWidget);
      expect(find.text('Запись отменена'), findsOneWidget);
      expect(find.text('Запросить снова'), findsOneWidget);
    });
  });

  group('во время записи', () {
    final sample = ru.aiScribeSampleTranscript;
    final sampleSegments = [
      segment('Пациент жалуется на боль в груди при нагрузке.'),
      segment('Давление 150 на 95.', t0: 4),
      segment('Назначаю амлодипин 5 мг утром.', t0: 8),
    ];

    testWidgets('вставка примера → фразы, запись приёма и памятка; правка фразы в листе', (tester) async {
      final backend = await pumpScribe(tester, recordingApi({
        'POST /transcript': {'transcript': sampleSegments},
        'POST /segments/1': {'transcript': [sampleSegments[0], segment('Давление 140 на 90.', t0: 4, original: 'Давление 150 на 95.', source: 'doctor'), sampleSegments[2]]},
      }));
      await resume(tester);
      await tapText(tester, ru.aiScribePasteText);
      expect(button(tester, ru.aiScribeUseText).enabled, isFalse, reason: 'пустой текст не отправляется');
      await tapText(tester, ru.aiScribePasteSample);
      await tapText(tester, ru.aiScribeUseText);
      expect(backend.lastBody('POST', '/scribe/sessions/s1/transcript'), {'text': sample});
      expect(find.text('Назначаю амлодипин 5 мг утром.'), findsOneWidget);
      expect(find.text(ru.aiScribeEditHint), findsOneWidget);

      await tester.ensureVisible(find.text(ru.aiScribeRecordHint));
      final record = tester.widget<TextField>(find.byWidgetPredicate((w) => w is TextField && w.controller?.text == 'Пациент жалуется на боль в груди при нагрузке.\nДавление 150 на 95.\nНазначаю амлодипин 5 мг утром.'));
      expect(record.readOnly, isFalse);
      await tapText(tester, ru.scribeLeafletLabel);
      expect(find.byWidgetPredicate((w) => w is TextField && (w.controller?.text.contains('- Назначаю амлодипин 5 мг утром.') ?? false)), findsOneWidget);
      expect(find.text(ru.aiScribeLeafletHint), findsOneWidget);
      expect(button(tester, ru.aiScribeApprove).enabled, isTrue);

      await tapText(tester, 'Давление 150 на 95.');
      expect(find.text('00:04–00:08 · RU'), findsWidgets);
      await tester.enterText(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)), 'Давление 140 на 90.');
      await tapText(tester, ru.aiScribeSave);
      expect(backend.lastBody('POST', '/scribe/sessions/s1/segments/1'), {'text': 'Давление 140 на 90.'});
      expect(find.text('Исправил врач'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('исправление терминов: тост с числом фраз и второй строкой про недоступную модель (мягкий сбой)', (tester) async {
      final backend = await pumpScribe(tester, recordingApi({
        'POST /transcript': {'transcript': sampleSegments},
        'POST /correct': {
          'transcript': [sampleSegments[0], sampleSegments[1], segment('Назначаю амлодипин 5 мг утром.', t0: 8, original: 'Назначаю амлодепин 5 мг утром.', source: 'dictionary')],
          'changed': 1,
          'aiError': 'llm unavailable',
        },
      }));
      await resume(tester);
      await pasteSample(tester, ru);
      await tapText(tester, ru.aiScribeCorrectTerms);
      expect(backend.calls('POST', '/scribe/sessions/s1/correct'), hasLength(1));
      expect(find.text('${ru.aiScribeCorrected(1)}\n${ru.aiScribeAiUnavailable}'), findsOneWidget);
      expect(find.text('Исправлено по словарю'), findsOneWidget);

      backend.routes['POST /correct'] = {'transcript': sampleSegments, 'changed': 0};
      await tapText(tester, ru.aiScribeCorrectTerms);
      expect(find.text(ru.aiScribeNothingToCorrect), findsOneWidget);
    });

    testWidgets('микрофон без разрешения — подсказка; вставка текста остаётся', (tester) async {
      await pumpScribe(tester, recordingApi());
      await resume(tester);
      await tapText(tester, ru.aiScribeRecordMic);
      expect(find.text(ru.scribeMicDenied), findsOneWidget, reason: 'разрешения на микрофон нет');
      expect(button(tester, ru.aiScribePasteText).enabled, isTrue);
    });

    testWidgets('модель грузится: заметка с процентом, микрофон неактивен, сервис перечитывается каждые 12 с до готовности', (tester) async {
      final backend = await pumpScribe(tester, recordingApi({
        '/scribe/health': {...health, 'transcriberState': 'loading', 'transcriberProgress': {'downloadedMb': 150, 'totalMb': 300}},
      }));
      await resume(tester);
      expect(find.text(ru.aiScribeModelDownloading(50, 150, 300)), findsOneWidget);
      expect(button(tester, ru.aiScribeRecordMic).enabled, isFalse);
      expect(button(tester, ru.aiScribePasteText).enabled, isTrue);

      final reads = backend.calls('GET', '/scribe/health').length;
      backend.routes['/scribe/health'] = health;
      await tester.pump(const Duration(seconds: 12));
      await pumpFrames(tester);
      expect(backend.calls('GET', '/scribe/health').length, reads + 1);
      expect(find.text(ru.aiScribeModelDownloading(50, 150, 300)), findsNothing);
      expect(button(tester, ru.aiScribeRecordMic).enabled, isTrue);
      await tester.pump(const Duration(seconds: 24));
      expect(backend.calls('GET', '/scribe/health').length, reads + 1, reason: 'модель готова — опрос остановлен');
    });

    testWidgets('утверждение: один раздел «Запись приёма» и памятка; итог — ссылка на памятку, QR, копирование, новый приём', (tester) async {
      var list = [consent('r1', 'recording', sessionId: 's1')];
      final backend = await pumpScribe(tester, recordingApi({
        '/scribe-consents': (http.Request r) => list,
        'POST /transcript': {'transcript': sampleSegments},
        'POST /approve': (http.Request r) {
          list = [consent('r1', 'completed')];
          return json({'leafletToken': 'tok-1', 'audioDeleted': true, 'consentId': 'r1'});
        },
      }));
      await resume(tester);
      await pasteSample(tester, ru);
      await tester.tap(find.text(ru.aiScribeApprove));
      await pumpFrames(tester);
      final call = backend.calls('POST', '/scribe/sessions/s1/approve').single;
      final body = jsonDecode(call.body) as Map<String, dynamic>;
      expect(body['sections'], [
        {'name': 'Запись приёма', 'text': 'Пациент жалуется на боль в груди при нагрузке.\nДавление 150 на 95.\nНазначаю амлодипин 5 мг утром.'},
      ]);
      expect(body['patientLeaflet'], startsWith('Что делать после приёма:\n- Назначаю амлодипин 5 мг утром.'));
      expect(call.headers.containsKey('Idempotency-Key'), isFalse);

      expect(find.text(ru.aiScribeApprovedToast), findsOneWidget);
      expect(find.text(ru.aiScribeLeafletSent), findsOneWidget);
      expect(find.text('Аудио удалено'), findsOneWidget);
      expect(find.text('${Env.webBase}/leaflet/tok-1'), findsOneWidget);
      expect(tester.widget<QrImageView>(find.byType(QrImageView)).semanticsLabel, ru.aiScribeQrAlt);
      expect(find.text('Утверждено'), findsOneWidget);
      await tapText(tester, ru.aiScribeCopyLink);
      expect(clipboard, '${Env.webBase}/leaflet/tok-1');
      expect(find.text(ru.aiScribeLinkCopied), findsOneWidget);

      await tapText(tester, ru.aiScribeNewVisit);
      expect(find.text('Приём записан'), findsOneWidget);
      expect(find.text('Запросить снова'), findsOneWidget, reason: 'на новый приём — новое согласие');
    });

    testWidgets('409 при утверждении (запись истекла): шаги с настоящим состоянием и текст сервера', (tester) async {
      var list = [consent('r1', 'recording', sessionId: 's1')];
      await pumpScribe(tester, recordingApi({
        '/scribe-consents': (http.Request r) => list,
        'POST /transcript': {'transcript': sampleSegments},
        'POST /approve': (http.Request r) {
          list = [consent('r1', 'expired')];
          return problem(409, 'Действие недоступно', detail: 'запись отменена или истекла — для нового приёма нужно новое согласие');
        },
      }));
      await resume(tester);
      await pasteSample(tester, ru);
      await tester.tap(find.text(ru.aiScribeApprove));
      await pumpFrames(tester);
      expect(find.text('Действие недоступно — запись отменена или истекла — для нового приёма нужно новое согласие'), findsOneWidget);
      expect(find.text('Истекло'), findsOneWidget);
      expect(find.text(ru.aiScribeApprove), findsNothing);
    });

    testWidgets('422 при вставке — текст сервера, сессия остаётся', (tester) async {
      await pumpScribe(tester, recordingApi({
        'POST /transcript': problem(422, 'One or more validation errors occurred.', errors: {'text': ['текст 1…20 000 символов']}),
      }));
      await resume(tester);
      await pasteSample(tester, ru);
      expect(find.textContaining('текст 1…20 000 символов'), findsOneWidget);
      expect(find.text(ru.aiScribeRecordMic), findsOneWidget);
    });
  });

  group('опрос согласия идёт, только пока экран виден', () {
    testWidgets('экран под другим экраном и приложение в фоне — без запросов; возврат — перечитать сразу', (tester) async {
      final backend = await pumpScribe(tester, {'/scribe-consents': [consent('r1', 'pending')]});
      int reads() => backend.calls('GET', '/scribe-consents').length;
      final start = reads();

      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('другой экран')))));
      await pumpFrames(tester);
      await tester.pump(const Duration(seconds: 11));
      expect(reads(), start, reason: 'экран скрайба закрыт другим — опроса нет');
      navigator.pop();
      await pumpFrames(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(reads(), greaterThan(start), reason: 'экран снова виден — опрос идёт');

      final visible = reads();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 11));
      expect(reads(), visible, reason: 'в фоне — без запросов');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpFrames(tester);
      expect(reads(), visible + 1, reason: 'вернулись — перечитали сразу');
    });
  });

  testWidgets('маршрут /doctor/patients/:ref/scribe открывает скрайб этого пациента', (tester) async {
    final (session, backend) = await demoSession(DemoUser.doctor1, api: {'/scribe/health': health, '/scribe-consents': [consent('r1', 'granted')]});
    final router = await pumpRouterApp(tester, session, location: '/doctor/patients/${Uri.encodeComponent(ref)}/scribe');
    expect(router.state.uri.path, '/doctor/patients/$ref/scribe');
    expect(find.byType(ScribeScreen), findsOneWidget);
    expect(find.text('Пациент $ref · аудио удаляется при утверждении'), findsOneWidget);
    expect(backend.calls('GET', '/scribe-consents').last.url.queryParameters['patientRef'], ref);
  });

  testWidgets('казахский при масштабе 1.3 на телефоне 360 dp: шаги, рабочая область и итог без переполнения', (tester) async {
    final kk = S.of('kk');
    var list = [consent('r1', 'granted')];
    await pumpScribe(
      tester,
      {
        '/scribe-consents': (http.Request r) => list,
        'POST /scribe/sessions': (http.Request r) {
          list = [consent('r1', 'recording', sessionId: 's1')];
          return json({'sessionId': 's1', 'consentId': 'r1', 'patientRef': ref}, 201);
        },
        'POST /transcript': {
          'transcript': [segment('Қысым 150-95.'), segment('Таңертең 5 мг амлодипин тағайындаймын.', t0: 4, original: 'Таңертең 5 мг амлодепин тағайындаймын.', source: 'dictionary')],
        },
        'POST /approve': json({'leafletToken': 'tok-kk', 'audioDeleted': true}),
      },
      locale: 'kk',
      textScale: 1.3,
      size: phoneNarrow,
    );
    expect(find.text('Келісім алынды'), findsOneWidget);
    expect(find.text(kk.aiScribeWhat2), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tapText(tester, kk.aiScribeStart);
    expect(find.text(kk.aiScribeRecordMic), findsOneWidget);
    expect(tester.takeException(), isNull);
    await pasteSample(tester, kk);
    await tester.ensureVisible(find.text('Сөздік бойынша түзетілді'));
    await pumpFrames(tester);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text(kk.aiScribeApproveHint));
    await pumpFrames(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(kk.aiScribeApprove));
    await pumpFrames(tester);
    expect(find.text(kk.aiScribeLeafletSent), findsOneWidget);
    await tester.ensureVisible(find.text(kk.aiScribeOpenPatient));
    await pumpFrames(tester);
    expect(tester.takeException(), isNull);
  });
}
