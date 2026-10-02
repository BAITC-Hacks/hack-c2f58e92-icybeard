// Модели AI-скрайба (§3.10 контракта): согласие пациента на запись, сессия записи, стенограмма, черновик, утверждение,
// публичная памятка и состояние сервиса. Вынесены из models.dart, чтобы файлы оставались компактными; models.dart реэкспортирует этот
// файл, импорты экранов не меняются. Словаря терминов клиники здесь нет: на телефоне он не редактируется (только веб).

/// Начатая запись приёма (`POST /api/v1/scribe/sessions` → 201). Привязана к согласию пациента: consentId — его
/// requestId из `GET /scribe-consents`, patientRef — чей это приём (§2.1).
class ScribeSession {
  const ScribeSession({required this.sessionId, required this.consentId, required this.patientRef});
  final String sessionId;
  final String consentId;
  final String patientRef;
  factory ScribeSession.fromJson(Map<String, dynamic> json) => ScribeSession(
        sessionId: json['sessionId'] as String? ?? '',
        consentId: json['consentId'] as String? ?? '',
        patientRef: json['patientRef'] as String? ?? '',
      );
}

/// Фраза стенограммы. `original`/`source` отсутствуют (не null), пока фразу не трогали вручную, ИИ или словарём
/// (§3.10.5) — `original` хранит текст распознавания, `source` — кто поправил: doctor | ai | dictionary.
class TranscriptSegment {
  const TranscriptSegment({required this.t0, required this.t1, required this.text, this.original, this.source});

  /// Начало и конец фразы в секундах записи; у вставленного текста — синтетические 4-секундные отрезки.
  final double t0;
  final double t1;
  final String text;

  /// Текст распознавания до правки; null — фразу не трогали.
  final String? original;

  /// doctor | ai | dictionary (`RouteCodes.segmentSources`); null — фразу не трогали.
  final String? source;
  factory TranscriptSegment.fromJson(Map<String, dynamic> json) => TranscriptSegment(
        t0: (json['t0'] as num?)?.toDouble() ?? 0,
        t1: (json['t1'] as num?)?.toDouble() ?? 0,
        text: json['text'] as String? ?? '',
        original: json['original'] as String?,
        source: json['source'] as String?,
      );
}

/// Таймкод фразы исходной стенограммы, вошедшей в раздел черновика; обратно на `/approve` не отправляется.
typedef DraftSpan = ({double t0, double t1});

/// Раздел записи приёма. На `/approve` уходят только name и text — spans обратно не отправляются.
class DraftSection {
  const DraftSection({required this.name, required this.text, this.spans = const []});
  final String name;
  final String text;
  final List<DraftSpan> spans;
  factory DraftSection.fromJson(Map<String, dynamic> json) => DraftSection(
        name: json['name'] as String? ?? '',
        text: json['text'] as String? ?? '',
        spans: List.unmodifiable(((json['spans'] as List<dynamic>?) ?? const [])
            .map((s) => s as Map<String, dynamic>)
            .map<DraftSpan>((s) => (t0: (s['t0'] as num?)?.toDouble() ?? 0, t1: (s['t1'] as num?)?.toDouble() ?? 0))),
      );
}

/// Черновик приёма от ИИ внутри `GET /scribe/sessions/{id}`, если его составляли. Сам телефон черновик не заказывает:
/// запись приёма — один раздел со стенограммой.
class ScribeDraft {
  const ScribeDraft({required this.sections, required this.leaflet, this.model});
  final List<DraftSection> sections;
  final String leaflet;

  /// Имя языковой модели, составившей черновик; null — не сообщено.
  final String? model;
  factory ScribeDraft.fromJson(Map<String, dynamic> json) => ScribeDraft(
        sections: List.unmodifiable((json['sections'] as List<dynamic>? ?? const []).map((s) => DraftSection.fromJson(s as Map<String, dynamic>))),
        leaflet: json['leaflet'] as String? ?? '',
        model: json['model'] as String?,
      );
}

/// Ответ `POST /scribe/sessions/{id}/approve` (§2.2): `{leafletToken, audioDeleted, consentId}`. Ссылка для пациента —
/// `Env.leafletLink(leafletToken)`.
class ApproveResult {
  const ApproveResult({required this.leafletToken, this.audioDeleted = true, this.consentId});

  /// Токен памятки пациента — для ссылки/QR и для `GET /scribe/leaflets/{token}`.
  final String leafletToken;

  /// Аудио удалено после утверждения; по умолчанию true.
  final bool audioDeleted;

  /// Согласие, по которому шла запись (теперь в статусе completed).
  final String? consentId;

  factory ApproveResult.fromJson(Map<String, dynamic> json) => ApproveResult(
        leafletToken: json['leafletToken'] as String? ?? '',
        audioDeleted: json['audioDeleted'] as bool? ?? true,
        consentId: json['consentId'] as String?,
      );
}

/// Публичный текст памятки после приёма `GET /scribe/leaflets/{token}` (без проверки роли): `{text, language,
/// approvedAt}`. Организации, врача и срока действия в ответе нет; неизвестный или удалённый токен — 404.
class PublicLeaflet {
  const PublicLeaflet({required this.text, this.language = '', this.approvedAt = ''});

  /// Текст памятки: абзацы через пустую строку; строка с двоеточием или короткая заглавная — заголовок шага.
  final String text;

  /// Язык приёма: `ru` | `kk`; пусто — не прислан.
  final String language;

  /// ISO-штамп утверждения врачом; пусто — не прислан.
  final String approvedAt;

  factory PublicLeaflet.fromJson(Map<String, dynamic> json) => PublicLeaflet(
        text: json['text'] as String? ?? '',
        language: json['language'] as String? ?? '',
        approvedAt: json['approvedAt'] as String? ?? '',
      );
}

/// Ответ `POST /scribe/sessions/{id}/audio` (§3.10.5) — заменяет стенограмму целиком; `text` — удобная склейка
/// фраз, `transcript` — сами сегменты с таймингами для посегментной правки.
class ScribeAudioUpload {
  const ScribeAudioUpload({this.transcript = const [], this.text = '', this.transcriber});
  final List<TranscriptSegment> transcript;
  final String text;

  /// Имя модели распознавания речи; null — не сообщено.
  final String? transcriber;
  factory ScribeAudioUpload.fromJson(Map<String, dynamic> json) => ScribeAudioUpload(
        transcript: _segments(json['transcript']),
        text: json['text'] as String? ?? '',
        transcriber: json['transcriber'] as String?,
      );
}

/// Запрос согласия на запись приёма — элемент «голого» массива `GET /scribe-consents?patientRef=` (врач) и
/// `GET /route/me/scribe` (гражданин), свежие первыми: текущий запрос — первый элемент (§3.10.1/§3.10.2).
class ScribeConsent {
  const ScribeConsent({
    required this.requestId,
    required this.patientRef,
    this.moCode,
    this.moName,
    required this.requestedRole,
    required this.requestedAt,
    required this.day,
    this.comment,
    required this.status,
    this.answeredAt,
    this.sessionId,
    this.leafletToken,
    this.approvedAt,
  });
  /// Id запроса: `{id}` в `/scribe-consents/{id}/cancel|discard`, `/route/me/scribe/{id}/answer` и consentId сессии.
  final String requestId;
  final String patientRef;

  /// Больница, которая просит записать приём.
  final String? moCode;
  final String? moName;
  final String requestedRole;

  /// ISO-штамп запроса.
  final String requestedAt;

  /// `yyyy-MM-dd` — согласие действует только в этот день (Asia/Almaty).
  final String day;
  final String? comment;

  /// pending | granted | declined | withdrawn | cancelled | expired | recording | discarded | completed
  /// (`RouteCodes.scribeStatuses`); granted действует на одну запись и только сегодня.
  final String status;

  /// ISO-штамп ответа пациента.
  final String? answeredAt;

  /// Заполняется с началом записи (recording и дальше) — id для `GET /scribe/sessions/{id}`.
  final String? sessionId;

  /// Токен памятки, когда status == completed: ссылка `Env.leafletLink(leafletToken)`.
  final String? leafletToken;
  final String? approvedAt;

  factory ScribeConsent.fromJson(Map<String, dynamic> json) => ScribeConsent(
        requestId: json['requestId'] as String? ?? '',
        patientRef: json['patientRef'] as String? ?? '',
        moCode: json['moCode'] as String?,
        moName: json['moName'] as String?,
        requestedRole: json['requestedRole'] as String? ?? '',
        requestedAt: json['requestedAt'] as String? ?? '',
        day: json['day'] as String? ?? '',
        comment: json['comment'] as String?,
        status: json['status'] as String? ?? '',
        answeredAt: json['answeredAt'] as String?,
        sessionId: json['sessionId'] as String?,
        leafletToken: json['leafletToken'] as String?,
        approvedAt: json['approvedAt'] as String?,
      );
}

/// Возобновлённая сессия записи (`GET /scribe/sessions/{id}`, §3.10.4) — хранится на диске сервиса скрайба и
/// переживает его перезапуск, пока явно не утверждена или не отменена.
class ScribeSessionState {
  const ScribeSessionState({required this.sessionId, required this.language, required this.approved, this.transcript = const [], this.draft});
  final String sessionId;

  /// ru | kk; по умолчанию ru.
  final String language;
  final bool approved;
  final List<TranscriptSegment> transcript;

  /// Черновик ИИ, если его составляли; null — нет.
  final ScribeDraft? draft;
  factory ScribeSessionState.fromJson(Map<String, dynamic> json) => ScribeSessionState(
        sessionId: json['sessionId'] as String? ?? '',
        language: json['language'] as String? ?? 'ru',
        approved: json['approved'] as bool? ?? false,
        transcript: _segments(json['transcript']),
        draft: json['draft'] == null ? null : ScribeDraft.fromJson(json['draft'] as Map<String, dynamic>),
      );
}

/// Ответ `POST /scribe/sessions/{id}/correct` (§3.10.5) — сначала правки по словарю, потом языковой моделью;
/// `aiError` заполнен и статус всё равно 200, когда модель недоступна — это не ошибка запроса.
class ScribeCorrection {
  const ScribeCorrection({this.transcript = const [], this.changed = 0, this.aiError});
  /// Вся стенограмма после правок.
  final List<TranscriptSegment> transcript;

  /// Сколько фраз исправлено.
  final int changed;

  /// Текст, почему языковая модель не отработала (исправлено только по словарю); null — отработала.
  final String? aiError;
  factory ScribeCorrection.fromJson(Map<String, dynamic> json) => ScribeCorrection(
        transcript: _segments(json['transcript']),
        changed: (json['changed'] as num?)?.toInt() ?? 0,
        aiError: json['aiError'] as String?,
      );
}

/// `GET /scribe/health` — состояние сервиса распознавания и составления черновика (§3.10.5); опрашивается, пока
/// модель загружается.
class ScribeHealth {
  const ScribeHealth({required this.status, required this.transcriber, required this.drafter, this.transcriberState, this.transcriberError, this.downloadedMb, this.totalMb});
  final String status;
  final String transcriber;
  final String drafter;

  /// idle | loading | ready | error.
  final String? transcriberState;
  final String? transcriberError;
  final int? downloadedMb;
  final int? totalMb;
  factory ScribeHealth.fromJson(Map<String, dynamic> json) {
    final progress = json['transcriberProgress'] as Map<String, dynamic>?;
    return ScribeHealth(
      status: json['status'] as String? ?? '',
      transcriber: json['transcriber'] as String? ?? '',
      drafter: json['drafter'] as String? ?? '',
      transcriberState: json['transcriberState'] as String?,
      transcriberError: json['transcriberError'] as String?,
      downloadedMb: (progress?['downloadedMb'] as num?)?.toInt(),
      totalMb: (progress?['totalMb'] as num?)?.toInt(),
    );
  }
}

/// Фразы стенограммы из `transcript` ответа; отсутствующий список — пустой, результат неизменяемый.
List<TranscriptSegment> _segments(Object? json) =>
    List.unmodifiable((json as List<dynamic>? ?? const []).map((t) => TranscriptSegment.fromJson(t as Map<String, dynamic>)));
