import 'package:flutter/foundation.dart';

import '../../api/client.dart';
import '../../api/models.dart';
import '../../l10n/strings.dart';
import 'scribe_text.dart';

/// Состояние экрана AI-скрайба одного пациента — порт ScribeView.vue веба. Держит согласие пациента (список запросов,
/// текущий — первый), состояние сервиса скрайба, сессию записи, фразы стенограммы, запись приёма и памятку, результат
/// утверждения; ходит в API и уведомляет экран. Таймеры опроса (согласие 5 с, сервис 12 с) живут в экране: он знает,
/// виден ли он.
///
/// Действия бросают ошибку запроса — экран показывает её через `showApiError`. Порядок по рецепту: там, где веб
/// перечитывает согласие после действия (запрос, отмена, начало, отмена записи), перечитывание идёт до того, как
/// ошибка дойдёт до экрана; 409 сессии (запись утверждена, отменена или истекла) перечитывает согласие и закрывает
/// сессию, если она уже не идёт; 404 сессии — запись потеряна, остаётся отмена. Пока действие идёт, его повтор ничего
/// не отправляет (двойное нажатие — одна запись в журнале). Ключ идемпотентности нужен только запросу согласия; сессия
/// и утверждение уходят без него (так требует сервер).
class ScribeFlow extends ChangeNotifier {
  ScribeFlow({required ApiClient api, required this.patientRef, String language = 'ru'})
      : _api = api,
        _language = language == 'kk' ? 'kk' : 'ru';

  final ApiClient _api;

  /// Реф пациента: экран скрайба всегда открыт для одного пациента (`/doctor/patients/:ref/scribe`).
  final String patientRef;
  bool _disposed = false;

  // ---------- согласие пациента ----------
  List<ScribeConsent> _consents = const [];
  bool _consentsLoaded = false;
  Object? _consentsError;
  bool _consentBusy = false;
  int _consentsRun = 0;

  /// Список запросов согласия прочитан хотя бы раз.
  bool get consentsLoaded => _consentsLoaded;

  /// Ошибка последнего чтения; известное до неё состояние остаётся на экране.
  Object? get consentsError => _consentsError;

  /// Текущий запрос согласия — самый свежий; null — запросов не было.
  ScribeConsent? get consent => _consents.firstOrNull;

  /// Состояние текущего запроса (`RouteCodes.scribeStatuses`) или `none`.
  String get consentState => consent?.status ?? 'none';

  /// Идёт запрос, отмена или отмена записи — кнопки согласия неактивны.
  bool get consentBusy => _consentBusy;

  /// Ждём ответа пациента и записи ещё нет — экран опрашивает согласие каждые 5 с, пока он виден.
  bool get waitsForPatient => consentState == RouteCodes.scribePending && _sessionId == null;

  // ---------- сервис скрайба ----------
  ScribeHealth? _health;
  bool _serviceDown = false;
  bool _healthRateLimited = false;

  /// Последний ответ `/scribe/health`; null — сервис не ответил или ещё не спрашивали.
  ScribeHealth? get health => _health;

  /// Сервис скрайба не отвечает (сеть или ошибка сервера) — «Сервис скрайба не запущен».
  bool get serviceDown => _serviceDown;

  /// Последняя проверка получила 429: «повторите позже», а не «сервис недоступен».
  bool get healthRateLimited => _healthRateLimited;

  /// Экран опрашивает сервис каждые 12 с, пока модель распознавания грузится или проверку отклонили по лимиту.
  bool get pollHealth => _healthRateLimited || _health?.transcriberState == 'loading';

  // ---------- сессия записи ----------
  String _language;
  String? _sessionId;
  bool _sessionLost = false;
  bool _starting = false;
  bool _resuming = false;
  List<TranscriptSegment> _segments = const [];
  String _recordText = '';
  bool _recordDirty = false;
  bool _transcriptChanged = false;
  String _leaflet = '';
  bool _leafletDirty = false;
  bool _processing = false;
  bool _correcting = false;
  int? _savingIndex;
  bool _approving = false;
  ApproveResult? _result;

  /// Язык приёма `ru` | `kk` (решение Q-9): распознавание и памятка — на нём; после начала записи не меняется.
  String get language => _language;
  String? get sessionId => _sessionId;
  bool get hasSession => _sessionId != null;

  /// Начатую запись сервис скрайба не знает (404): её можно только отменить.
  bool get sessionLost => _sessionLost;
  bool get starting => _starting;
  bool get resuming => _resuming;
  List<TranscriptSegment> get segments => _segments;

  /// Весь текст приёма; пока врач его не правил, следует за стенограммой.
  String get recordText => _recordText;

  /// Стенограмма изменилась после ручной правки записи — экран предлагает подставить её текст.
  bool get transcriptChanged => _transcriptChanged;
  String get leaflet => _leaflet;

  /// Врач правил памятку — она больше не пересобирается сама.
  bool get leafletDirty => _leafletDirty;

  /// Распознаётся аудио или разбирается вставленный текст.
  bool get processing => _processing;
  bool get correcting => _correcting;

  /// Номер фразы, правка которой сохраняется; null — ничего не сохраняется.
  int? get savingIndex => _savingIndex;
  bool get approving => _approving;
  ApproveResult? get result => _result;
  bool get approved => _result != null;

  /// «Начать запись»: согласие получено и сервис ответил (как у веба).
  bool get canStart => consentState == RouteCodes.scribeGranted && _health != null && !_starting;

  /// «Утвердить»: есть сессия, оба текста не пустые и ничего не обрабатывается.
  bool get canApprove => hasSession && !approved && _recordText.trim().isNotEmpty && _leaflet.trim().isNotEmpty && !sessionBusy;

  /// Работа с фразами и текстом сейчас недоступна (идёт обработка, правка или утверждение).
  bool get sessionBusy => _processing || _correcting || _approving || _savingIndex != null;

  // ---------- чтение ----------

  /// Перечитать запросы согласия. Никогда не бросает: ошибка — в [consentsError]. Ответ более раннего чтения,
  /// пришедший позже, отбрасывается.
  Future<void> loadConsents() async {
    final run = ++_consentsRun;
    try {
      final list = await _api.scribeConsents(patientRef);
      if (run != _consentsRun) return;
      _consents = list;
      _consentsLoaded = true;
      _consentsError = null;
    } on Exception catch (e) {
      if (run != _consentsRun) return;
      _consentsError = e;
    }
    _notify();
  }

  /// Проверить сервис скрайба. Никогда не бросает: 429 — [healthRateLimited] (прежнее состояние остаётся), остальные
  /// сбои — [serviceDown].
  Future<void> loadHealth() async {
    try {
      _health = await _api.scribeHealth();
      _serviceDown = false;
      _healthRateLimited = false;
    } on ApiException catch (e) {
      _healthRateLimited = e.isRateLimited;
      if (!e.isRateLimited) {
        _health = null;
        _serviceDown = true;
      }
    } on Exception {
      _health = null;
      _serviceDown = true;
      _healthRateLimited = false;
    }
    _notify();
  }

  // ---------- согласие: действия ----------

  /// Запросить согласие (или «Запросить снова»): один свежий ключ идемпотентности на нажатие. true — запрос
  /// отправлен; false — уже идёт действие или у пациента уже есть действующий запрос (409 «Запрос уже отправлен» не
  /// ошибка, как на вебе). Список перечитывается в любом случае.
  Future<bool> askConsent() async {
    if (_consentBusy || !scribeCanAsk(consentState)) return false;
    _setConsentBusy(true);
    try {
      await _api.requestScribeConsent(patientRef, idempotencyKey: newIdempotencyKey());
      return true;
    } on ApiException catch (e) {
      if (e.isConflict) return false;
      rethrow;
    } finally {
      await _afterConsentAction();
    }
  }

  /// «Отменить запрос» (ждёт ответа или согласие дано).
  Future<void> cancelConsent() async {
    final current = consent;
    if (_consentBusy || current == null) return;
    _setConsentBusy(true);
    try {
      await _api.cancelScribeConsent(current.requestId, patientRef);
    } finally {
      await _afterConsentAction();
    }
  }

  /// «Отменить запись»: аудио, стенограмма и черновик удаляются через журнал (`/scribe-consents/{id}/discard`),
  /// согласие израсходовано — для нового приёма нужен новый запрос.
  Future<void> discard() async {
    final current = consent;
    if (_consentBusy || current == null) return;
    _setConsentBusy(true);
    try {
      await _api.discardScribeRecording(current.requestId, patientRef);
      _resetSession();
    } finally {
      await _afterConsentAction();
    }
  }

  // ---------- сессия: начало, продолжение, новый приём ----------

  /// Язык приёма выбирается только до начала записи.
  void setLanguage(String language) {
    if (hasSession || (language != 'ru' && language != 'kk') || language == _language) return;
    _language = language;
    _notify();
  }

  /// «Начать запись» по согласию `granted`; согласие перечитывается и после успеха (оно стало `recording`), и после
  /// ошибки (409 «пациент ещё не ответил…», 403 «Согласие дано другой больнице», 503).
  Future<void> start() async {
    final current = consent;
    if (!canStart || current == null) return;
    _starting = true;
    _notify();
    try {
      final created = await _api.createScribeSession(consentId: current.requestId, language: _language);
      _resetSession();
      _sessionId = created.sessionId;
    } finally {
      _starting = false;
      await loadConsents();
    }
  }

  /// «Продолжить запись» начатой и не утверждённой сессии: язык и фразы восстанавливаются, запись приёма и памятка
  /// собираются заново. 404 — запись потеряна ([sessionLost]), остаётся только отмена.
  Future<void> resume() async {
    final id = consent?.sessionId;
    if (_resuming || id == null || id.isEmpty) return;
    _resuming = true;
    _notify();
    try {
      final state = await _api.scribeSession(id);
      _resetSession();
      _language = state.language == 'kk' ? 'kk' : 'ru';
      _sessionId = state.sessionId.isEmpty ? id : state.sessionId;
      _applySegments(state.transcript);
    } on ApiException catch (e) {
      if (!e.isNotFound) rethrow;
      _sessionLost = true;
    } finally {
      _resuming = false;
      _notify();
    }
  }

  /// «Новый приём»: экран возвращается к шагам; на новый приём нужно новое согласие.
  Future<void> newVisit() {
    _resetSession();
    _notify();
    return loadConsents();
  }

  // ---------- стенограмма ----------

  /// Аудио с микрофона → фразы (заменяют стенограмму целиком). 422 «речь не распознана» — сессия остаётся.
  Future<ScribeAudioUpload> uploadAudio(List<int> bytes, String filename) =>
      _sessionCall(() => _api.uploadScribeAudio(_sessionId!, bytes, filename), (upload) => _applySegments(upload.transcript), busy: _setProcessing);

  /// Вставленный или напечатанный текст → фразы (сервер режет текст на предложения).
  Future<void> useText(String text) =>
      _sessionCall<List<TranscriptSegment>>(() => _api.setTranscript(_sessionId!, text), _applySegments, busy: _setProcessing);

  /// Правка фразы [index]; текст, равный исходному («вернуть»), снимает пометку правки.
  Future<void> saveSegment(int index, String text) => _sessionCall<List<TranscriptSegment>>(
        () => _api.editScribeSegment(_sessionId!, index, text.trim()),
        _applySegments,
        busy: (on) => _savingIndex = on ? index : null,
      );

  /// «Исправить термины (ИИ)»: стенограмма меняется, только если исправлены фразы; `aiError` — мягкий сбой
  /// (исправлено только словарём), не ошибка запроса.
  Future<ScribeCorrection> correctTerms() => _sessionCall(
        () => _api.correctScribeTerms(_sessionId!),
        (correction) {
          if (correction.changed > 0) _applySegments(correction.transcript);
        },
        busy: (on) => _correcting = on,
      );

  // ---------- запись приёма и памятка ----------

  /// Врач правит запись приёма: дальше она не следует за стенограммой.
  void editRecord(String text) {
    if (text == _recordText) return;
    _recordText = text;
    _recordDirty = true;
    _notify();
  }

  /// Врач правит памятку: дальше она не пересобирается сама.
  void editLeaflet(String text) {
    if (text == _leaflet) return;
    _leaflet = text;
    _leafletDirty = true;
    _notify();
  }

  /// «Подставить текст стенограммы» после ручной правки.
  void replaceRecord() {
    _recordText = scribeTranscriptText(_segments);
    _recordDirty = false;
    _transcriptChanged = false;
    _notify();
  }

  /// «Собрать заново из стенограммы».
  void rebuildLeaflet() {
    _leaflet = buildScribeLeaflet(_segments, S.of(_language));
    _leafletDirty = false;
    _notify();
  }

  /// Утвердить: один раздел [sectionName] («Запись приёма» на языке интерфейса, как на вебе) с текстом записи и
  /// памятка. После успеха аудио удалено, памятка у пациента, согласие перечитывается (`completed`).
  Future<void> approve(String sectionName) async {
    if (!canApprove) return;
    await _sessionCall(
      () => _api.approveScribe(_sessionId!, [DraftSection(name: sectionName, text: _recordText.trim())], _leaflet.trim()),
      (result) => _result = result,
      busy: (on) => _approving = on,
    );
    await loadConsents();
  }

  // ---------- служебное ----------

  /// Вызов сессии: флаг занятости [busy] на время запроса, [apply] — после успеха; 409 — согласие перечитывается и
  /// сессия закрывается, если запись уже не идёт; 404 — запись потеряна. Повтор во время работы ничего не шлёт.
  Future<T> _sessionCall<T>(Future<T> Function() call, void Function(T value) apply, {required void Function(bool on) busy}) async {
    if (_sessionId == null || sessionBusy || approved) {
      throw StateError('scribe session is not ready for this action');
    }
    busy(true);
    _notify();
    try {
      final value = await call();
      apply(value);
      return value;
    } on ApiException catch (e) {
      if (e.isConflict) {
        await loadConsents();
        if (consentState != RouteCodes.scribeRecording) _resetSession();
      } else if (e.isNotFound) {
        _resetSession();
        _sessionLost = true;
        await loadConsents();
      }
      rethrow;
    } finally {
      busy(false);
      _notify();
    }
  }

  /// Новые фразы: запись приёма следует за ними, пока врач её не правил (иначе — пометка «стенограмма изменилась»);
  /// памятка пересобирается на языке приёма, пока врач её не правил. После утверждения ничего не меняется.
  void _applySegments(List<TranscriptSegment> list) {
    _segments = list;
    if (approved) return;
    final text = scribeTranscriptText(list);
    if (_recordDirty) {
      _transcriptChanged = _recordText != text;
    } else {
      _recordText = text;
    }
    if (!_leafletDirty) {
      _leaflet = list.isEmpty ? '' : buildScribeLeaflet(list, S.of(_language));
    }
  }

  void _resetSession() {
    _sessionLost = false;
    _sessionId = null;
    _segments = const [];
    _recordText = '';
    _recordDirty = false;
    _transcriptChanged = false;
    _leaflet = '';
    _leafletDirty = false;
    _result = null;
  }

  void _setProcessing(bool on) => _processing = on;

  void _setConsentBusy(bool on) {
    _consentBusy = on;
    _notify();
  }

  Future<void> _afterConsentAction() async {
    _consentBusy = false;
    await loadConsents();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
