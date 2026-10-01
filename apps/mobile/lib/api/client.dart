import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'models.dart';

export 'api_exception.dart';

/// Клиент REST API. Bearer-токен Keycloak на каждый запрос, если пользователь вошёл; без токена — только публичные
/// эндпоинты (ожидание, лекарства, справочники). Один экземпляр на сессию, закрывается вместе с ней.
///
/// Ошибки: ответ ≥ 400 — [ApiException] (рецепт обработки — в её описании); сбой сети — `http.ClientException`
/// как есть; 2xx с телом не-JSON — `FormatException`. Ответ 200 вместо 201 на запись — повтор с тем же
/// Idempotency-Key, сервер вернул уже записанное: это успех.
///
/// Idempotency-Key: каждый метод, который пишет запись в журнал маршрута или решений, принимает обязательный
/// `idempotencyKey` — вызывающий берёт один свежий [newIdempotencyKey] на нажатие и повторяет тот же ключ только при
/// автоматическом повторе того же запроса. Без ключа по контракту: [createScribeSession] и
/// [approveScribe] (повторно использованный ключ рассинхронизирует согласие со скрайбом), а также
/// [cancelScribeConsent] и [discardScribeRecording] (сервер сначала проверяет состояние, повтор — 409).
///
/// Методы гражданина (`/route/me/*`) принимают необязательный `regionKato`: передавайте везде одно и то же значение,
/// что и в [myRoute] — у учётных записей без региона в токене от него зависит, чей это маршрут.
class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client, this.tokenProvider, String Function()? locale})
      : _http = client ?? http.Client(),
        _locale = locale ?? (() => 'ru');

  final String baseUrl;
  final http.Client _http;
  final String Function() _locale;

  /// Свежий Bearer-токен на каждый запрос (Keycloak с обновлением); null — до входа (публичные эндпоинты).
  final Future<String?> Function()? tokenProvider;

  String get locale => _locale();

  Map<String, String> _headers(String? bearer) => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Accept-Language': locale,
        if (bearer != null) 'Authorization': 'Bearer $bearer',
      };

  Future<String?> _bearer() async => await tokenProvider?.call();

  /// Query без пустых значений: null и пустая строка не отправляются.
  Uri _uri(String path, [Map<String, String?>? query]) {
    final clean = <String, String>{for (final e in (query ?? {}).entries) if (e.value != null && e.value!.isNotEmpty) e.key: e.value!};
    return Uri.parse('$baseUrl$path').replace(queryParameters: clean.isEmpty ? null : clean);
  }

  Future<dynamic> get(String path, [Map<String, String?>? query]) async =>
      _decode(await _http.get(_uri(path, query), headers: _headers(await _bearer())));

  Future<dynamic> post(String path, Object body, {Map<String, String>? headers, Map<String, String?>? query}) async =>
      _decode(await _http.post(_uri(path, query), headers: {..._headers(await _bearer()), ...?headers}, body: jsonEncode(body)));

  Future<dynamic> put(String path, Object body) async =>
      _decode(await _http.put(_uri(path), headers: _headers(await _bearer()), body: jsonEncode(body)));

  Future<dynamic> delete(String path, [Map<String, String?>? query]) async =>
      _decode(await _http.delete(_uri(path, query), headers: _headers(await _bearer())));

  /// Публичный GET без токена: фоновый опрос не должен обновлять токен и выходить из сессии, если обновить нельзя.
  Future<dynamic> _getAnonymous(String path) async => _decode(await _http.get(_uri(path), headers: _headers(null)));

  /// Тело ответа: JSON (объект или массив), null для пустого тела (204); ≥ 400 — [ApiException].
  dynamic _decode(http.Response response) {
    if (response.statusCode >= 400) {
      throw ApiException.fromResponse(response.statusCode, response.bodyBytes, response.headers);
    }
    final text = utf8.decode(response.bodyBytes);
    return text.isEmpty ? null : jsonDecode(text);
  }

  /// Запись в журнал (201 или 200 на повтор ключа) → `decisionId` новой (или уже записанной) записи.
  Future<String> _record(String path, Map<String, Object?> body, {String? idempotencyKey, Map<String, String?>? query}) async {
    final created = await post(path, body, headers: {_idempotencyHeader: ?idempotencyKey}, query: query);
    return (created as Map<String, dynamic>)['decisionId'] as String;
  }

  /// Голый JSON-массив объектов → список моделей (неизменяемый).
  static List<T> _list<T>(dynamic body, T Function(Map<String, dynamic> json) fromJson) =>
      List.unmodifiable((body as List<dynamic>).map((item) => fromJson(item as Map<String, dynamic>)));

  // ---------- справочники, прогноз, лекарства ----------
  Future<List<Region>> regions() async =>
      ((await get('/api/v1/refdata/regions'))['items'] as List<dynamic>).map((r) => Region.fromJson(r as Map<String, dynamic>)).toList();

  Future<List<BedProfile>> profiles() async => ((await get('/api/v1/refdata/profiles'))['items'] as List<dynamic>)
      .map((p) => p as Map<String, dynamic>)
      .where((p) => p['isDayHospital'] != true)
      .map(BedProfile.fromJson)
      .toList();

  /// Организации региона по профилю койки; без профиля — весь справочник региона (имена для журнала решений).
  Future<List<Organization>> organizations(String regionKato, [String? profileCode]) async =>
      ((await get('/api/v1/refdata/organizations', {'regionKato': regionKato, 'profileCode': profileCode, 'limit': profileCode == null ? '500' : '100'}))['items']
              as List<dynamic>)
          .map((o) => Organization.fromJson(o as Map<String, dynamic>))
          .toList();

  Future<PredictResponse> predict(Map<String, dynamic> request) async =>
      PredictResponse.fromJson(await post('/api/v1/queue/predict', request) as Map<String, dynamic>);

  Future<List<Alternative>> alternatives(Map<String, dynamic> request) async =>
      ((await post('/api/v1/queue/alternatives', {...request, 'limit': 5}))['items'] as List<dynamic>)
          .map((a) => Alternative.fromJson(a as Map<String, dynamic>))
          .toList();

  Future<List<IndexItem>> index({String? profileCode}) async =>
      ((await get('/api/v1/index', {'profileCode': profileCode}))['items'] as List<dynamic>).map((i) => IndexItem.fromJson(i as Map<String, dynamic>)).toList();

  Future<RouteStandard> routeStandard() async => RouteStandard.fromJson(await get('/api/v1/refdata/route-standard') as Map<String, dynamic>);

  Future<List<Nosology>> nosologies() async =>
      ((await get('/api/v1/medicines/nosologies', {'limit': '30'}))['items'] as List<dynamic>).map((n) => Nosology.fromJson(n as Map<String, dynamic>)).toList();

  Future<List<Mnn>> mnn(String nosologyId) async =>
      ((await get('/api/v1/medicines/mnn', {'nosologyId': nosologyId, 'limit': '30'}))['items'] as List<dynamic>).map((m) => Mnn.fromJson(m as Map<String, dynamic>)).toList();

  Future<CheckResponse> checkMedicine({String? mnnId, String? nosologyId, String? regionKato}) async =>
      CheckResponse.fromJson(await post('/api/v1/medicines/check', {'mnnId': mnnId, 'nosologyId': nosologyId, 'regionKato': regionKato}) as Map<String, dynamic>);

  Future<List<VaccinationEstimate>> vaccination() async =>
      ((await get('/api/v1/refdata/vaccination'))['items'] as List<dynamic>).map((v) => VaccinationEstimate.fromJson(v as Map<String, dynamic>)).toList();

  // ---------- маршрут: гражданин (route.own) ----------
  Future<PatientRoute> myRoute({String? regionKato}) async =>
      PatientRoute.fromJson(await get('/api/v1/route/me', {'regionKato': regionKato}) as Map<String, dynamic>);

  /// Сигнал гражданина `POST /route/me/signals` → decisionId. [kind]: `request_redirect` (с [toMoCode]),
  /// `prefer_current`, `still_waiting`, `withdraw`, `treated_elsewhere` (`RouteCodes`); пустой [comment] не
  /// отправляется. Вне `progress.allowed` — 409, больница уже отказала — 409.
  Future<String> sendRouteSignal(String kind, {String? toMoCode, String? comment, required String idempotencyKey, String? regionKato}) =>
      _record('/api/v1/route/me/signals', {'kind': kind, 'toMoCode': ?toMoCode, if (comment != null && comment.isNotEmpty) 'comment': comment},
          idempotencyKey: idempotencyKey, query: {'regionKato': regionKato});

  /// Ответ гражданина на предложенный перевод `POST /route/me/consent` → decisionId. [decisionId] —
  /// `progress.transfer.decisionId`; [accepted] отправляется всегда (пропущенный сервер считает отказом);
  /// пустой [reason] не отправляется. В `transfer_pending_confirmation` отказ отзывает уже данное согласие.
  Future<String> answerTransfer({required String decisionId, required bool accepted, String? reason, required String idempotencyKey, String? regionKato}) =>
      _record('/api/v1/route/me/consent', {'decisionId': decisionId, 'accepted': accepted, if (reason != null && reason.isNotEmpty) 'reason': reason},
          idempotencyKey: idempotencyKey, query: {'regionKato': regionKato});

  /// Колокольчик гражданина `GET /route/me/notifications` — всегда 200; без маршрута — `unread: 0` и пустой список.
  /// Порядок сервера: сначала «нужен ваш ответ», затем новые.
  Future<CitizenNotifications> routeNotifications({String? regionKato}) async =>
      CitizenNotifications.fromJson(await get('/api/v1/route/me/notifications', {'regionKato': regionKato}) as Map<String, dynamic>);

  /// Отметить уведомление гражданина прочитанным `POST /route/me/notifications/{id}/read` → 204. Повтор и
  /// неизвестный id — тоже 204, ключ не нужен. Сервер отмечает прочтение по пользователю; [regionKato] передаётся
  /// ради единообразия вызовов `/route/me/*`.
  Future<void> markRouteNotificationRead(String id, {String? regionKato}) async =>
      await post('/api/v1/route/me/notifications/${Uri.encodeComponent(id)}/read', const <String, Object?>{}, query: {'regionKato': regionKato});

  /// Запросы записи приёма и памятки врача гражданина `GET /route/me/scribe` — голый массив, новые первыми; без
  /// маршрута — пустой. Памятки — элементы в статусе `completed` с `leafletToken`.
  Future<List<ScribeConsent>> myScribe({String? regionKato}) async =>
      _list(await get('/api/v1/route/me/scribe', {'regionKato': regionKato}), ScribeConsent.fromJson);

  /// Ответ гражданина на запрос записи приёма `POST /route/me/scribe/{requestId}/answer` → decisionId. [granted]
  /// отправляется всегда (пропущенный — отказ): pending + true → granted, pending + false → declined, granted + false → withdrawn
  /// (пока запись не начата); иначе 409.
  Future<String> answerScribe(String requestId, {required bool granted, required String idempotencyKey, String? regionKato}) =>
      _record('/api/v1/route/me/scribe/${Uri.encodeComponent(requestId)}/answer', {'granted': granted},
          idempotencyKey: idempotencyKey, query: {'regionKato': regionKato});

  // ---------- маршрут: врач (worklist.view — чтение, referral.confirm — действия) ----------
  Future<WorklistResponse> worklistPage({String? flag}) async =>
      WorklistResponse.fromJson(await get('/api/v1/journal/worklist', {'flag': flag}) as Map<String, dynamic>);

  Future<PatientRoute> patientRoute(String patientRef) async =>
      PatientRoute.fromJson(await get('/api/v1/route/${Uri.encodeComponent(patientRef)}') as Map<String, dynamic>);

  /// Предложить перевод `POST /route/{ref}/redirect` → decisionId: дальше нужны согласие пациента и подтверждение
  /// принимающей больницы. [reason] обязателен (иначе 422); `severe` уходит в теле только при true — флаг тяжести
  /// видит принимающая больница.
  Future<String> redirectRoute(String patientRef, {required String toMoCode, required String reason, required String idempotencyKey, bool severe = false}) =>
      _record('/api/v1/route/${Uri.encodeComponent(patientRef)}/redirect', {'toMoCode': toMoCode, 'reason': reason, if (severe) 'severe': true},
          idempotencyKey: idempotencyKey);

  /// Оставить пациента в своей больнице `POST /route/{ref}/keep` → decisionId; [reason] обязателен (иначе 422).
  Future<String> keepRoute(String patientRef, {required String reason, required String idempotencyKey}) =>
      _record('/api/v1/route/${Uri.encodeComponent(patientRef)}/keep', {'reason': reason}, idempotencyKey: idempotencyKey);

  /// Отменить ещё не подтверждённый перевод `POST /route/{ref}/cancel-transfer` → decisionId; [reason] обязателен.
  Future<String> cancelTransfer(String patientRef, {required String reason, required String idempotencyKey}) =>
      _record('/api/v1/route/${Uri.encodeComponent(patientRef)}/cancel-transfer', {'reason': reason}, idempotencyKey: idempotencyKey);

  /// Снять с листа ожидания по просьбе пациента `POST /route/{ref}/close` → decisionId; [reason] обязателен. Так же
  /// закрывает маршрут и принимающая больница после подтверждённого перевода.
  Future<String> closeRoute(String patientRef, {required String reason, required String idempotencyKey}) =>
      _record('/api/v1/route/${Uri.encodeComponent(patientRef)}/close', {'reason': reason}, idempotencyKey: idempotencyKey);

  // ---------- принимающая больница: входящие направления (referral.confirm, свой mo_code) ----------
  /// Входящие направления в больницу `GET /journal/referrals/incoming` (worklist.view) — голый массив, тяжёлые
  /// первыми. [includeConfirmed] по умолчанию true, как в вебе: подтверждённые тоже нужны, фильтрует экран;
  /// [severe] отправляется только если задан. Без своей больницы и без [moCode] — 422 «Нужна организация».
  Future<List<IncomingReferral>> incomingReferrals({String? moCode, bool? severe, bool includeConfirmed = true}) async => _list(
        await get('/api/v1/journal/referrals/incoming', {'moCode': moCode, 'severe': severe?.toString(), 'includeConfirmed': '$includeConfirmed'}),
        IncomingReferral.fromJson,
      );

  /// Подтвердить приём `POST /journal/referrals/{id}/confirm` → decisionId. [plannedAt] — `yyyy-MM-dd` в окне
  /// сегодня … +30 дней по Алматы (`almaty_time.dart`); пустой [comment] не отправляется.
  Future<String> confirmReferral(String decisionId, {required String patientRef, required String plannedAt, String? comment, required String idempotencyKey}) =>
      _record(_referralPath(decisionId, 'confirm'),
          {'patientRef': patientRef, 'plannedAt': plannedAt, if (comment != null && comment.isNotEmpty) 'comment': comment},
          idempotencyKey: idempotencyKey);

  /// Отказать в приёме `POST /journal/referrals/{id}/reject` → decisionId; [reason] обязателен. Больницу этому
  /// пациенту больше не предлагают.
  Future<String> rejectReferral(String decisionId, {required String patientRef, required String reason, required String idempotencyKey}) =>
      _record(_referralPath(decisionId, 'reject'), {'patientRef': patientRef, 'reason': reason}, idempotencyKey: idempotencyKey);

  /// Перенести дату `POST /journal/referrals/{id}/reschedule` → decisionId; [plannedAt] — как в [confirmReferral],
  /// [reason] обязателен.
  Future<String> rescheduleReferral(String decisionId, {required String patientRef, required String plannedAt, required String reason, required String idempotencyKey}) =>
      _record(_referralPath(decisionId, 'reschedule'), {'patientRef': patientRef, 'plannedAt': plannedAt, 'reason': reason}, idempotencyKey: idempotencyKey);

  /// Отметить госпитализацию `POST /journal/referrals/{id}/admit` → decisionId; пустой [reason] не отправляется.
  Future<String> admitReferral(String decisionId, {required String patientRef, String? reason, required String idempotencyKey}) =>
      _record(_referralPath(decisionId, 'admit'), {'patientRef': patientRef, if (reason != null && reason.isNotEmpty) 'reason': reason},
          idempotencyKey: idempotencyKey);

  /// Отметить неявку `POST /journal/referrals/{id}/no-show` → decisionId; закрывает маршрут. Пустой [reason] не
  /// отправляется.
  Future<String> noShowReferral(String decisionId, {required String patientRef, String? reason, required String idempotencyKey}) =>
      _record(_referralPath(decisionId, 'no-show'), {'patientRef': patientRef, if (reason != null && reason.isNotEmpty) 'reason': reason},
          idempotencyKey: idempotencyKey);

  /// Выписать `POST /journal/referrals/{id}/discharge` → decisionId; [summary] (эпикриз для направившего врача)
  /// обязателен. Закрывает маршрут.
  Future<String> dischargeReferral(String decisionId, {required String patientRef, required String summary, required String idempotencyKey}) =>
      _record(_referralPath(decisionId, 'discharge'), {'patientRef': patientRef, 'summary': summary}, idempotencyKey: idempotencyKey);

  String _referralPath(String decisionId, String action) => '/api/v1/journal/referrals/${Uri.encodeComponent(decisionId)}/$action';

  // ---------- колокольчик врача (worklist.view) ----------
  /// Колокольчик больницы `GET /journal/notifications/bell?moCode=`: ждут подтверждения, подтверждённые и выписанные
  /// переводы, действия пациентов. Без больницы в области видимости — нули и пустые списки, не ошибка.
  Future<NotificationBell> doctorBell({String? moCode}) async =>
      NotificationBell.fromJson(await get('/api/v1/journal/notifications/bell', {'moCode': moCode}) as Map<String, dynamic>);

  /// Отметить уведомление колокольчика прочитанным `POST /journal/notifications/bell/{kind}/{id}/read` → 204.
  /// [kind]: `RouteCodes.bellReferralConfirmed` | `bellReferralDischarged` | `bellPatientSignal`; другой — 400.
  Future<void> markBellRead(String kind, String id) async =>
      await post('/api/v1/journal/notifications/bell/${Uri.encodeComponent(kind)}/${Uri.encodeComponent(id)}/read', const <String, Object?>{});

  // ---------- журнал решений ----------
  /// Решение ассистента направления `POST /journal/decisions` → decisionId. Только `subject: referral`: события
  /// маршрута сервер принимает лишь через `/route/{ref}/…` и `/journal/referrals/{id}/…` (иначе 422).
  Future<String> recordDecision(Map<String, dynamic> decision, {required String idempotencyKey}) =>
      _record('/api/v1/journal/decisions', decision, idempotencyKey: idempotencyKey);

  Future<List<DecisionRecord>> myDecisions({int page = 1, int size = 50}) async =>
      ((await get('/api/v1/journal/decisions', {'actor': 'me', 'page': '$page', 'size': '$size'}))['items'] as List<dynamic>)
          .map((d) => DecisionRecord.fromJson(d as Map<String, dynamic>))
          .toList();

  // ---------- согласие на запись приёма: врач (scribe.use) ----------
  /// Запросы согласия пациента на запись `GET /scribe-consents?patientRef=` — голый массив, новые первыми; текущий —
  /// первый элемент.
  Future<List<ScribeConsent>> scribeConsents(String patientRef) async =>
      _list(await get('/api/v1/scribe-consents', {'patientRef': patientRef}), ScribeConsent.fromJson);

  /// Попросить у пациента согласие на запись `POST /scribe-consents` → decisionId, он же `requestId` нового
  /// запроса. Действующий запрос уже есть — 409 с [ApiException.requestId]. Пустой [comment] не отправляется.
  Future<String> requestScribeConsent(String patientRef, {String? comment, required String idempotencyKey}) =>
      _record('/api/v1/scribe-consents', {'patientRef': patientRef, if (comment != null && comment.isNotEmpty) 'comment': comment},
          idempotencyKey: idempotencyKey);

  /// Отменить запрос согласия (только `pending`/`granted`) `POST /scribe-consents/{id}/cancel` → decisionId.
  /// Без Idempotency-Key: сервер сначала проверяет состояние, повтор получает 409.
  Future<String> cancelScribeConsent(String requestId, String patientRef) =>
      _record('/api/v1/scribe-consents/${Uri.encodeComponent(requestId)}/cancel', {'patientRef': patientRef});

  /// Отменить начатую и не утверждённую запись (только `recording`) `POST /scribe-consents/{id}/discard` →
  /// decisionId: аудио и черновик удаляются, для нового приёма нужно новое согласие. Без Idempotency-Key.
  Future<String> discardScribeRecording(String requestId, String patientRef) =>
      _record('/api/v1/scribe-consents/${Uri.encodeComponent(requestId)}/discard', {'patientRef': patientRef});

  // ---------- запись приёма (scribe.use) ----------
  /// Начать запись по согласию пациента `POST /scribe/sessions` → 201. [consentId] — `requestId` согласия в статусе
  /// `granted` (действует один раз и только в день запроса), [language] — `ru` | `kk`. Без Idempotency-Key.
  Future<ScribeSession> createScribeSession({required String consentId, required String language}) async =>
      ScribeSession.fromJson(await post('/api/v1/scribe/sessions', {'consentId': consentId, 'language': language}) as Map<String, dynamic>);

  /// Состояние начатой записи `GET /scribe/sessions/{id}` — продолжить с того же места; `sessionId` берётся из
  /// согласия в статусе `recording`. 404 «Скрайб» — запись потеряна: отменить через [discardScribeRecording].
  Future<ScribeSessionState> scribeSession(String sessionId) async =>
      ScribeSessionState.fromJson(await get(_sessionPath(sessionId)) as Map<String, dynamic>);

  /// Аудио консультации → стенограмма `POST /scribe/sessions/{id}/audio`: multipart с полем `file`, как в вебе.
  /// Заменяет стенограмму целиком и сбрасывает черновик. Тишина — 422 с detail для человека.
  Future<ScribeAudioUpload> uploadScribeAudio(String sessionId, List<int> bytes, String filename) async {
    final headers = {..._headers(await _bearer())}..remove('Content-Type');
    final request = http.MultipartRequest('POST', _uri('${_sessionPath(sessionId)}/audio'))
      ..headers.addAll(headers)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    return ScribeAudioUpload.fromJson(_decode(await http.Response.fromStream(await _http.send(request))) as Map<String, dynamic>);
  }

  /// Вставленный текст → стенограмма `POST /scribe/sessions/{id}/transcript` (1…20 000 символов): сервер режет его
  /// на фразы с условными таймингами и снимает все пометки правок.
  Future<List<TranscriptSegment>> setTranscript(String sessionId, String text) async =>
      _transcript(await post('${_sessionPath(sessionId)}/transcript', {'text': text}));

  /// Правка одной фразы `POST /scribe/sessions/{id}/segments/{index}` (index с нуля, текст 1…4 000 символов) → вся
  /// стенограмма. Текст, равный исходному, отменяет правку.
  Future<List<TranscriptSegment>> editScribeSegment(String sessionId, int index, String text) async =>
      _transcript(await post('${_sessionPath(sessionId)}/segments/$index', {'text': text}));

  /// Исправление терминов словарём и ИИ `POST /scribe/sessions/{id}/correct`. Модель недоступна — всё равно 200,
  /// с `aiError`.
  Future<ScribeCorrection> correctScribeTerms(String sessionId) async =>
      ScribeCorrection.fromJson(await post('${_sessionPath(sessionId)}/correct', const <String, Object?>{}) as Map<String, dynamic>);

  /// Черновик по разделам от ИИ `POST /scribe/sessions/{id}/draft`. Веб этот шаг больше не использует.
  Future<ScribeDraft> makeDraft(String sessionId) async =>
      ScribeDraft.fromJson(await post('${_sessionPath(sessionId)}/draft', const <String, Object?>{}) as Map<String, dynamic>);

  /// Утвердить запись `POST /scribe/sessions/{id}/approve` → 200: аудио удаляется, памятка уходит пациенту;
  /// ссылка для него — `'${Env.webBase}/leaflet/$leafletToken'`. Без Idempotency-Key.
  Future<ApproveResult> approveScribe(String sessionId, List<DraftSection> sections, String leaflet) async => ApproveResult.fromJson(await post(
    '${_sessionPath(sessionId)}/approve',
    {'sections': [for (final s in sections) {'name': s.name, 'text': s.text}], 'patientLeaflet': leaflet},
  ) as Map<String, dynamic>);

  /// MOBILE-REFACTOR-SHIM: прежняя отмена записи для старого экрана скрайба, у которого нет id согласия. Журнал о
  /// ней не узнаёт — замена [discardScribeRecording]; удалить вместе со старым экраном.
  Future<void> discardScribe(String sessionId) async => await delete(_sessionPath(sessionId));

  /// Состояние сервиса записи и модели распознавания `GET /scribe/health`.
  Future<ScribeHealth> scribeHealth() async => ScribeHealth.fromJson(await get('/api/v1/scribe/health') as Map<String, dynamic>);

  String _sessionPath(String sessionId) => '/api/v1/scribe/sessions/${Uri.encodeComponent(sessionId)}';

  static List<TranscriptSegment> _transcript(dynamic body) =>
      _list((body as Map<String, dynamic>)['transcript'] ?? const <dynamic>[], TranscriptSegment.fromJson);

  // ---------- я и мой аккаунт (docs/rbac.md) ----------
  /// Кто вошёл: роли, разрешения `{code, scope}`, организация, ИИН маской.
  Future<Me> me() async => Me.fromJson(await get('/api/v1/me') as Map<String, dynamic>);

  Future<SecurityInfo> mySecurity() async => SecurityInfo.fromJson(await get('/api/v1/me/security') as Map<String, dynamic>);

  Future<void> endSession(String sessionId) async => await delete('/api/v1/me/sessions/${Uri.encodeComponent(sessionId)}');

  Future<void> endOtherSessions() async => await delete('/api/v1/me/sessions', {'keepCurrent': 'true'});

  Future<NotificationSettings> myNotifications() async =>
      NotificationSettings.fromJson(await get('/api/v1/me/notifications') as Map<String, dynamic>);

  /// Сохраняет настройки целиком (события, тихие часы, дайджест) и возвращает то, что записал API.
  Future<NotificationSettings> saveNotifications(NotificationSettings settings) async =>
      NotificationSettings.fromJson(await put('/api/v1/me/notifications', settings.toJson()) as Map<String, dynamic>);

  /// Какие внешние сервисы работают (почта, push, SMS, вход через eGov) — `GET /public/service-status`, без токена.
  /// Ошибка HTTP или сети — исключение: решение о фолбэке принимает `ServiceStatusNotifier`.
  Future<ServiceStatus> serviceStatus() async => ServiceStatus.fromJson(await _getAnonymous('/api/v1/public/service-status'));

  /// Ссылка на смену пароля уходит письмом; ответ 202 одинаковый для любой почты (без перебора адресов).
  Future<void> requestPasswordReset(String email) async => await post('/api/v1/public/password-reset', {'email': email});

  void close() => _http.close();
}

const _idempotencyHeader = 'Idempotency-Key';

/// Новый Idempotency-Key: 128 случайных бит (`Random.secure`), 32 шестнадцатеричных символа. Один ключ — одно
/// нажатие пользователя; тот же ключ — только для автоматического повтора того же запроса (сервер вернёт 200 и уже
/// записанную запись, не проверяя, что действие то же). Ключ меняется, если изменились выбор или причина.
String newIdempotencyKey() {
  final random = Random.secure();
  return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
