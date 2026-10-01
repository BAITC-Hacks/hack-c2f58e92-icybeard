import 'dart:math' as math;

import '../../api/models.dart';
import '../../config/env.dart';
import '../../l10n/strings.dart';
import '../status_chip.dart';

// Чистые правила экрана скрайба — порт ScribeView.vue веба: памятка из назначений стенограммы, текст записи приёма,
// метка фразы, тон и доступность запроса согласия, заметка о модели распознавания, чип состояния, ссылка на памятку.
// Без состояния и без обращения к серверу: экран и ScribeFlow только вызывают их.

/// Предложение с назначением или контролем (LEAFLET_LINE веба, те же корни слов по-русски и по-казахски).
final _leafletLine = RegExp(
  r'(назнач|принима|таблет|\bмг\b|капл|контрол|явк|анализ|направ|повторн|диет|тағайында|қабылда|ішіңіз|жолдама|қайта)',
  caseSensitive: false,
  unicode: true,
);

/// Граница предложения: пробелы после «.», «!», «?» или «…».
final _sentenceEnd = RegExp(r'(?<=[.!?…])\s+', unicode: true);

/// Казахские буквы, которых нет в русском алфавите: по ним фраза помечается «KK».
final _kazakhLetters = RegExp('[әіңғүұқөһӘІҢҒҮҰҚӨҺ]', unicode: true);

/// Памятка пациенту: «Что делать после приёма:», пункт на каждое предложение с назначением (или «Назначения уточните у
/// врача.») и последним пунктом — правило «103». [visit] — словарь языка ПРИЁМА (`S.of(language)`), не интерфейса:
/// пациент читает памятку на том языке, на котором шёл приём. Врач потом правит текст.
String buildScribeLeaflet(List<TranscriptSegment> segments, S visit) {
  final lines = [
    for (final segment in segments)
      for (final sentence in segment.text.split(_sentenceEnd))
        if (sentence.trim().isNotEmpty && _leafletLine.hasMatch(sentence.trim())) sentence.trim(),
  ];
  return [
    visit.aiScribeLeafletIntro,
    for (final line in lines.isEmpty ? [visit.aiScribeLeafletNoPrescriptions] : lines) '- $line',
    '- ${visit.aiScribeLeafletSafety}',
  ].join('\n');
}

/// Весь текст приёма для поля «Запись приёма»: фразы стенограммы по одной на строку.
String scribeTranscriptText(List<TranscriptSegment> segments) => segments.map((s) => s.text).join('\n');

/// Язык фразы для метки: `kk`, если в ней есть казахские буквы, иначе `ru`.
String scribeSegmentLanguage(String text) => _kazakhLetters.hasMatch(text) ? 'kk' : 'ru';

/// Метка времени фразы «мм:сс–мм:сс» (у вставленного текста — условные отрезки сервиса).
String scribeStamp(double t0, double t1) => '${_clock(t0)}–${_clock(t1)}';

String _clock(double seconds) {
  final total = math.max(0, seconds.round());
  return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
}

/// Тон чипа состояния согласия (CONSENT_TONES веба): ждём ответа и начатая запись — warn, согласие и записанный
/// приём — ok, отказ — danger, остальное и незнакомое — нейтральный.
StatusTone scribeConsentTone(String status) => switch (status) {
      'pending' || 'recording' => StatusTone.warn,
      'granted' || 'completed' => StatusTone.ok,
      'declined' => StatusTone.danger,
      _ => StatusTone.neutral,
    };

/// Можно отправить новый запрос согласия: нет действующего — ждущего ответа, данного или израсходованного начатой
/// записью (её продолжают или отменяют). Правило веба (`canAsk`); у согласия нет списка `allowed` от сервера, а
/// лишний запрос сервер отклонит 409 «Запрос уже отправлен».
bool scribeCanAsk(String status) => !const {'pending', 'granted', 'recording'}.contains(status);

/// Заметка о модели распознавания речи под кнопками записи: скачивается (с процентом, не больше 99), загружается,
/// недоступна или заглушка; модель готова или состояние неизвестно — null.
String? scribeModelNote(S s, ScribeHealth? health) {
  switch (health?.transcriberState) {
    case 'loading':
      final done = health!.downloadedMb;
      final total = health.totalMb;
      if (done != null && total != null && total > 0 && done > 0) {
        return s.aiScribeModelDownloading(math.min(99, (done / total * 100).round()), done, total);
      }
      return s.aiScribeModelLoading;
    case 'error':
      return s.aiScribeModelError;
  }
  return health?.transcriber == 'fake' ? s.aiScribeModelFake : null;
}

/// Пока модель грузится или сломана, запись с микрофона не распознать: кнопка микрофона неактивна, вставка текста
/// остаётся.
bool scribeModelNotReady(ScribeHealth? health) => const {'loading', 'error'}.contains(health?.transcriberState);

/// Ключ чипа состояния в шапке (`doctor.scribe.state.*`) в порядке веба: утверждено → идёт запись → обработка →
/// стенограмма готова → готово к записи; до начала записи чипа нет (null).
String? scribeStateKey({required bool approved, required bool recording, required bool busy, required bool hasTranscript, required bool hasSession}) {
  if (approved) return 'approved';
  if (recording) return 'recording';
  if (busy) return 'processing';
  if (hasTranscript) return 'transcribed';
  return hasSession ? 'ready' : null;
}

/// Ссылка на памятку для пациента — веб-страница без входа (решение Q-17): `{Env.webBase}/leaflet/{token}`.
String scribeLeafletLink(String token) => '${Env.webBase}/leaflet/${Uri.encodeComponent(token)}';
