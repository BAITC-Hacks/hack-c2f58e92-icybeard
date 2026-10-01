import 'package:darumen/config/env.dart';
import 'package:darumen/screens/leaflet_screen.dart';
import 'package:darumen/widgets/citizen/leaflet_api.dart';
import 'package:darumen/widgets/citizen/leaflet_document.dart';
import 'package:darumen/widgets/state_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// Читалка памятки после приёма `/home/route/leaflet/:token`: публичный текст `GET /api/v1/scribe/leaflets/{token}`
/// (в клиенте метода нет — расширение `LeafletApi`), разбор текста как в LeafletView.vue, просроченная ссылка,
/// копирование ссылки на публичную страницу веба.
const token = 'Xk2_aB9-qwertyF6A7B8C9';
const leafletText = 'Принимайте капли два раза в день и приходите на осмотр через неделю.\n\n'
    'Лекарства:\nКапли — по 1 капле утром и вечером.\nНе трите глаза.\n\n'
    'КОНТРОЛЬ\nОсмотр у офтальмолога через 7 дней.\n\n'
    'Если стало хуже — сразу обратитесь в поликлинику.';

Map<String, Object?> leafletJson({String language = 'ru'}) => {'text': leafletText, 'language': language, 'approvedAt': '2026-10-01T09:30:00+00:00'};

void main() {
  group('leaflet text is split like the web reader', () {
    test('first paragraph without a heading is «Что дальше», the rest are numbered steps with titles', () {
      final doc = parseLeaflet(leafletText);
      expect(doc.intro, 'Принимайте капли два раза в день и приходите на осмотр через неделю.');
      expect(doc.steps.map((s) => s.title).toList(), ['Лекарства', 'КОНТРОЛЬ', '']);
      expect(doc.steps.first.body, 'Капли — по 1 капле утром и вечером.\nНе трите глаза.');
      expect(doc.steps.last.body, 'Если стало хуже — сразу обратитесь в поликлинику.');
    });

    test('a text that starts with a heading has no intro; blank and whitespace-only blocks are dropped', () {
      final doc = parseLeaflet('Режим:\nСпать 8 часов.\n \n\n\n');
      expect(doc.intro, isNull);
      expect(doc.steps, hasLength(1));
      expect(doc.steps.single.title, 'Режим');
      expect(parseLeaflet('').steps, isEmpty);
      expect(parseLeaflet('').intro, isNull);
    });

    test('a one-line block is never a heading, even in upper case', () {
      final doc = parseLeaflet('ВВОДНЫЙ АБЗАЦ\n\nОДНА СТРОКА');
      expect(doc.intro, 'ВВОДНЫЙ АБЗАЦ');
      expect(doc.steps.single.title, '');
      expect(doc.steps.single.body, 'ОДНА СТРОКА');
    });

    test('the public link is the web base, /leaflet/ and the token (Q-17)', () {
      expect(leafletWebLink(token), '${Env.webBase}/leaflet/$token');
    });
  });

  group('leaflet reader screen', () {
    testWidgets('loaded: number with language, approval line, intro, numbered steps, the AI note and the three footer notes', (tester) async {
      final (session, backend) = await demoSession(DemoUser.citizen1, api: {'/scribe/leaflets/$token': leafletJson()});
      await pumpScreen(tester, session, const LeafletScreen(token: token), size: phoneTall);
      expect(backend.calls('GET', '/api/v1/scribe/leaflets/$token'), hasLength(1));
      expect(find.text('Памятка после приёма'), findsOneWidget, reason: 'заголовок экрана, второго заголовка нет');
      expect(find.text('памятка F6A7B8C9 · RU'), findsOneWidget);
      expect(find.textContaining('утверждена 01.10.2026'), findsOneWidget);
      expect(find.textContaining('· утверждена врачом'), findsOneWidget);
      expect(find.textContaining('Принимайте капли два раза в день'), findsOneWidget);
      expect(find.text('Лекарства'), findsOneWidget);
      expect(find.text('КОНТРОЛЬ'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Данные синтетические, демонстрационные · Darumen Health'), 200);
      expect(find.text('О чём вы говорили с врачом'), findsOneWidget);
      expect(find.text('черновик ИИ'), findsOneWidget);
      expect(find.text('Памятка составлена по итогам приёма и утверждена врачом. Это не замена консультации.'), findsOneWidget);
      expect(find.text('Аудиозапись удалена после утверждения.'), findsOneWidget);
      expect(find.text('Персональные данные в памятке отсутствуют.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Скопировать ссылку» puts the public web link into the clipboard and says so', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final (session, _) = await demoSession(DemoUser.citizen1, api: {'/scribe/leaflets/$token': leafletJson()});
      await pumpScreen(tester, session, const LeafletScreen(token: token), size: phoneTall);
      expect(find.text('Открыть в браузере'), findsOneWidget);
      await tester.tap(find.text('Скопировать ссылку'));
      await tester.pump();
      expect(copied, ['${Env.webBase}/leaflet/$token']);
      expect(find.text('Ссылка скопирована'), findsOneWidget);
    });

    testWidgets('expired or unknown token (404, 410, 403): «Ссылка истекла», the number stays, no link actions', (tester) async {
      for (final status in [404, 410, 403]) {
        final (session, backend) = await demoSession(DemoUser.citizen1, api: {'/scribe/leaflets/$token': problem(status, 'Скрайб', detail: 'leaflet not found')});
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpScreen(tester, session, const LeafletScreen(token: token));
        expect(backend.calls('GET', '/api/v1/scribe/leaflets/$token'), hasLength(1));
        expect(find.text('Ссылка истекла'), findsOneWidget, reason: '$status');
        expect(find.text('Попросите врача выдать памятку заново.'), findsOneWidget);
        expect(find.text('памятка F6A7B8C9'), findsOneWidget);
        expect(find.text('Скопировать ссылку'), findsNothing);
        expect(find.textContaining('leaflet not found'), findsNothing, reason: 'текст сервера на английском не показывается');
      }
    });

    testWidgets('server error: the load error with «Повторить», which reloads', (tester) async {
      var calls = 0;
      final (session, _) = await demoSession(DemoUser.citizen1, api: {
        '/scribe/leaflets/$token': (_) => ++calls == 1 ? problem(502, 'Bad Gateway') : json(leafletJson()),
      });
      await pumpScreen(tester, session, const LeafletScreen(token: token), size: phoneTall);
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('Ссылка истекла'), findsNothing);
      await tester.tap(find.text('Повторить'));
      await pumpFrames(tester);
      expect(find.text('Лекарства'), findsOneWidget);
      expect(calls, 2);
    });

    testWidgets('kazakh at 1.3 on a 360 dp phone: loaded and expired readers do not overflow', (tester) async {
      final (session, _) = await demoSession(DemoUser.citizen1, api: {'/scribe/leaflets/$token': leafletJson(language: 'kk')}, locale: 'kk');
      await pumpScreen(tester, session, const LeafletScreen(token: token), locale: 'kk', textScale: 1.3, size: phoneNarrow);
      expect(find.text('Қабылдаудан кейінгі естелік'), findsOneWidget);
      expect(find.text('жадынама F6A7B8C9 · KK'), findsOneWidget);
      expect(find.text('Сілтемені көшіру'), findsOneWidget);
      expect(find.text('Браузерде ашу'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Аудиожазба бекітілгеннен кейін жойылды.'), 200);
      expect(find.text('ЖИ жобасы'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final (expired, _) = await demoSession(DemoUser.citizen1, api: {'/scribe/leaflets/$token': problem(404, 'Скрайб')}, locale: 'kk');
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpScreen(tester, expired, const LeafletScreen(token: token), locale: 'kk', textScale: 1.3, size: phoneNarrow);
      expect(find.text('Сілтеме мерзімі өтті'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
