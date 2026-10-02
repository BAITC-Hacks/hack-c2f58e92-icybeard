import 'package:darumen/api/models.dart';
import 'package:darumen/l10n/strings.dart';
import 'package:darumen/widgets/scribe/scribe_text.dart';
import 'package:darumen/widgets/status_chip.dart';
import 'package:flutter_test/flutter_test.dart';

/// Чистые правила экрана скрайба — порт ScribeView.vue: памятка из назначений на языке приёма, склейка стенограммы,
/// метка фразы, тон и доступность запроса согласия, заметка о модели распознавания, чип состояния и ссылка на памятку.
TranscriptSegment seg(String text, {double t0 = 0, double t1 = 4, String? original, String? source}) =>
    TranscriptSegment(t0: t0, t1: t1, text: text, original: original, source: source);

void main() {
  final ru = S.of('ru');
  final kk = S.of('kk');

  group('памятка пациенту', () {
    test('берёт предложения с назначениями, начинает вводной строкой и заканчивается правилом «103»', () {
      final leaflet = buildScribeLeaflet([seg(ru.aiScribeSampleTranscript)], ru);
      expect(leaflet.split('\n'), [
        'Что делать после приёма:',
        '- Назначаю амлодипин 5 мг утром.',
        '- При ухудшении самочувствия обратитесь к врачу или вызовите скорую помощь (103).',
      ]);
    });

    test('без назначений — «Назначения уточните у врача.»; предложения разных фраз собираются по порядку', () {
      expect(buildScribeLeaflet([seg('Жалоб нет. Давление в норме.')], ru).split('\n')[1], '- Назначения уточните у врача.');
      final leaflet = buildScribeLeaflet([seg('Принимать по таблетке! Пить воду.'), seg('Контроль через неделю… Анализ крови сдать')], ru);
      expect(leaflet.split('\n'), [
        'Что делать после приёма:',
        '- Принимать по таблетке!',
        '- Контроль через неделю…',
        '- Анализ крови сдать',
        '- При ухудшении самочувствия обратитесь к врачу или вызовите скорую помощь (103).',
      ]);
    });

    test('на языке приёма, а не интерфейса: казахский приём — казахские строки и казахские назначения', () {
      final leaflet = buildScribeLeaflet([seg(kk.aiScribeSampleTranscript)], kk);
      expect(leaflet.split('\n').first, 'Қабылдаудан кейін не істеу керек:');
      expect(leaflet, contains('- Таңертең 5 мг амлодипин тағайындаймын.'));
      expect(leaflet.split('\n').last, '- Жағдайыңыз нашарласа, дәрігерге қаралыңыз немесе жедел жәрдем шақырыңыз (103).');
    });

    test('пустые фразы и пробелы не дают пустых пунктов; входной список не меняется', () {
      final input = List<TranscriptSegment>.unmodifiable([seg('   '), seg('Назначен покой.  ')]);
      expect(buildScribeLeaflet(input, ru).split('\n'), [ru.aiScribeLeafletIntro, '- Назначен покой.', '- ${ru.aiScribeLeafletSafety}']);
    });
  });

  test('текст записи приёма — фразы по строкам, как на вебе', () {
    expect(scribeTranscriptText([seg('Первая.'), seg('Вторая.')]), 'Первая.\nВторая.');
    expect(scribeTranscriptText(const []), '');
  });

  test('язык фразы угадывается по казахским буквам; метка «мм:сс–мм:сс»', () {
    expect(scribeSegmentLanguage('Давление 150 на 95.'), 'ru');
    expect(scribeSegmentLanguage('Қысым 150-95.'), 'kk');
    expect(scribeSegmentLanguage('ӘЛЕМ'), 'kk');
    expect(scribeStamp(0, 4.4), '00:00–00:04');
    expect(scribeStamp(59.6, 125), '01:00–02:05');
    expect(scribeStamp(-3, 0), '00:00–00:00');
  });

  test('тон чипа согласия — как CONSENT_TONES веба; незнакомое — нейтральный', () {
    expect(scribeConsentTone('none'), StatusTone.neutral);
    expect(scribeConsentTone('pending'), StatusTone.warn);
    expect(scribeConsentTone('granted'), StatusTone.ok);
    expect(scribeConsentTone('declined'), StatusTone.danger);
    expect(scribeConsentTone('recording'), StatusTone.warn);
    expect(scribeConsentTone('completed'), StatusTone.ok);
    for (final status in ['withdrawn', 'cancelled', 'expired', 'discarded', 'unknown']) {
      expect(scribeConsentTone(status), StatusTone.neutral);
    }
  });

  test('новый запрос согласия — только когда нет действующего (ждёт ответа, дано, начатая запись)', () {
    for (final status in ['pending', 'granted', 'recording']) {
      expect(scribeCanAsk(status), isFalse, reason: status);
    }
    for (final status in ['none', 'declined', 'withdrawn', 'cancelled', 'expired', 'discarded', 'completed']) {
      expect(scribeCanAsk(status), isTrue, reason: status);
    }
  });

  group('модель распознавания речи', () {
    ScribeHealth health({String? state, String transcriber = 'faster-whisper', int? done, int? total}) => ScribeHealth(
          status: 'ok',
          transcriber: transcriber,
          drafter: 'stub',
          transcriberState: state,
          downloadedMb: done,
          totalMb: total,
        );

    test('скачивание с процентом (не больше 99), загрузка без прогресса, ошибка, заглушка, готово — без заметки', () {
      expect(scribeModelNote(ru, health(state: 'loading', done: 150, total: 300)), ru.aiScribeModelDownloading(50, 150, 300));
      expect(scribeModelNote(ru, health(state: 'loading', done: 299, total: 300)), ru.aiScribeModelDownloading(99, 299, 300));
      expect(scribeModelNote(kk, health(state: 'loading', done: 0, total: 300)), kk.aiScribeModelLoading);
      expect(scribeModelNote(ru, health(state: 'loading')), ru.aiScribeModelLoading);
      expect(scribeModelNote(ru, health(state: 'error')), ru.aiScribeModelError);
      expect(scribeModelNote(ru, health(state: 'ready', transcriber: 'fake')), ru.aiScribeModelFake);
      expect(scribeModelNote(ru, health(state: 'ready')), isNull);
      expect(scribeModelNote(ru, null), isNull);
    });

    test('микрофон недоступен, пока модель грузится или сломана', () {
      expect(scribeModelNotReady(health(state: 'loading')), isTrue);
      expect(scribeModelNotReady(health(state: 'error')), isTrue);
      expect(scribeModelNotReady(health(state: 'ready')), isFalse);
      expect(scribeModelNotReady(health()), isFalse);
      expect(scribeModelNotReady(null), isFalse);
    });
  });

  test('чип состояния: утверждено → идёт запись → обработка → стенограмма готова → готово к записи; без сессии — нет', () {
    String? key({bool approved = false, bool recording = false, bool busy = false, bool transcript = false, bool session = true}) =>
        scribeStateKey(approved: approved, recording: recording, busy: busy, hasTranscript: transcript, hasSession: session);
    expect(key(approved: true, recording: true, busy: true, transcript: true), 'approved');
    expect(key(recording: true, busy: true), 'recording');
    expect(key(busy: true, transcript: true), 'processing');
    expect(key(transcript: true), 'transcribed');
    expect(key(), 'ready');
    expect(key(session: false), isNull);
  });
}
