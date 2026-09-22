import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Ошибка API в формате problem+json (RFC 9457).
class ApiException implements Exception {
  ApiException(this.status, this.title, {this.detail, this.errors});
  final int status;
  final String title;
  final String? detail;
  final Map<String, List<String>>? errors;

  String? field(String name) => errors?[name]?.firstOrNull;

  @override
  String toString() => detail == null ? title : '$title: $detail';
}

/// Клиент REST API. Bearer-токен Keycloak на каждый запрос, если пользователь вошёл; без токена — только публичные
/// эндпоинты (ожидание, лекарства, справочники). Один экземпляр на сессию, закрывается вместе с ней.
class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client, this.tokenProvider, String Function()? locale})
      : _http = client ?? http.Client(),
        _locale = locale ?? (() => 'ru');

  final String baseUrl;
  final http.Client _http;
  final String Function() _locale;

  /// Свежий Bearer-токен на каждый запрос (Keycloak с обновлением); null — гость.
  final Future<String?> Function()? tokenProvider;

  String get locale => _locale();

  Map<String, String> _headers(String? bearer) => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Accept-Language': locale,
        if (bearer != null) 'Authorization': 'Bearer $bearer',
      };

  Future<String?> _bearer() async => await tokenProvider?.call();

  Uri _uri(String path, [Map<String, String?>? query]) {
    final clean = <String, String>{for (final e in (query ?? {}).entries) if (e.value != null && e.value!.isNotEmpty) e.key: e.value!};
    return Uri.parse('$baseUrl$path').replace(queryParameters: clean.isEmpty ? null : clean);
  }

  Future<dynamic> get(String path, [Map<String, String?>? query]) async =>
      _decode(await _http.get(_uri(path, query), headers: _headers(await _bearer())));

  Future<dynamic> post(String path, Object body, {Map<String, String>? headers}) async =>
      _decode(await _http.post(_uri(path), headers: {..._headers(await _bearer()), ...?headers}, body: jsonEncode(body)));

  Future<dynamic> delete(String path) async => _decode(await _http.delete(_uri(path), headers: _headers(await _bearer())));

  dynamic _decode(http.Response response) {
    final text = utf8.decode(response.bodyBytes);
    final body = text.isEmpty ? null : jsonDecode(text);
    if (response.statusCode >= 400) {
      final problem = body is Map<String, dynamic> ? body : <String, dynamic>{};
      final errors = (problem['errors'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, (v as List<dynamic>).cast<String>()));
      throw ApiException(response.statusCode, problem['title'] as String? ?? 'HTTP ${response.statusCode}', detail: problem['detail'] as String?, errors: errors);
    }
    return body;
  }

  // ---------- endpoints ----------
  Future<List<Region>> regions() async =>
      ((await get('/api/v1/refdata/regions'))['items'] as List<dynamic>).map((r) => Region.fromJson(r as Map<String, dynamic>)).toList();

  Future<List<BedProfile>> profiles() async => ((await get('/api/v1/refdata/profiles'))['items'] as List<dynamic>)
      .map((p) => p as Map<String, dynamic>)
      .where((p) => p['isDayHospital'] != true)
      .map(BedProfile.fromJson)
      .toList();

  Future<List<Organization>> organizations(String regionKato, String profileCode) async =>
      ((await get('/api/v1/refdata/organizations', {'regionKato': regionKato, 'profileCode': profileCode, 'limit': '100'}))['items'] as List<dynamic>)
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

  Future<WorklistResponse> worklistPage({String? flag}) async =>
      WorklistResponse.fromJson(await get('/api/v1/journal/worklist', {'flag': flag}) as Map<String, dynamic>);

  Future<List<WorklistItem>> worklist({String? flag}) async => (await worklistPage(flag: flag)).items;

  // ---------- маршрут пациента ----------
  Future<PatientRoute> myRoute({String? regionKato}) async =>
      PatientRoute.fromJson(await get('/api/v1/route/me', {'regionKato': regionKato}) as Map<String, dynamic>);

  Future<PatientRoute> patientRoute(String patientRef) async =>
      PatientRoute.fromJson(await get('/api/v1/route/${Uri.encodeComponent(patientRef)}') as Map<String, dynamic>);

  /// Перенаправление пациента врачом: один Idempotency-Key на нажатие, повтор возвращает ту же запись.
  Future<String> redirectRoute(String patientRef, {required String toMoCode, required String reason, required String idempotencyKey}) async =>
      ((await post('/api/v1/route/${Uri.encodeComponent(patientRef)}/redirect', {'toMoCode': toMoCode, 'reason': reason},
              headers: {'Idempotency-Key': idempotencyKey})) as Map<String, dynamic>)['decisionId'] as String;

  Future<RouteStandard> routeStandard() async => RouteStandard.fromJson(await get('/api/v1/refdata/route-standard') as Map<String, dynamic>);

  Future<String> recordDecision(Map<String, dynamic> decision, String idempotencyKey) async =>
      ((await post('/api/v1/journal/decisions', decision, headers: {'Idempotency-Key': idempotencyKey})) as Map<String, dynamic>)['decisionId'] as String;

  Future<List<Nosology>> nosologies() async =>
      ((await get('/api/v1/medicines/nosologies', {'limit': '30'}))['items'] as List<dynamic>).map((n) => Nosology.fromJson(n as Map<String, dynamic>)).toList();

  Future<List<Mnn>> mnn(String nosologyId) async =>
      ((await get('/api/v1/medicines/mnn', {'nosologyId': nosologyId, 'limit': '30'}))['items'] as List<dynamic>).map((m) => Mnn.fromJson(m as Map<String, dynamic>)).toList();

  Future<CheckResponse> checkMedicine({String? mnnId, String? nosologyId, String? regionKato}) async =>
      CheckResponse.fromJson(await post('/api/v1/medicines/check', {'mnnId': mnnId, 'nosologyId': nosologyId, 'regionKato': regionKato}) as Map<String, dynamic>);

  Future<List<VaccinationEstimate>> vaccination() async =>
      ((await get('/api/v1/refdata/vaccination'))['items'] as List<dynamic>).map((v) => VaccinationEstimate.fromJson(v as Map<String, dynamic>)).toList();

  Future<List<DecisionRecord>> myDecisions({int page = 1, int size = 50}) async =>
      ((await get('/api/v1/journal/decisions', {'actor': 'me', 'page': '$page', 'size': '$size'}))['items'] as List<dynamic>)
          .map((d) => DecisionRecord.fromJson(d as Map<String, dynamic>))
          .toList();

  Future<ScribeSession> createScribeSession(String language) async =>
      ScribeSession.fromJson(await post('/api/v1/scribe/sessions', {'consent': true, 'language': language}) as Map<String, dynamic>);

  Future<List<TranscriptSegment>> setTranscript(String sessionId, String text) async =>
      ((await post('/api/v1/scribe/sessions/$sessionId/transcript', {'text': text}))['transcript'] as List<dynamic>)
          .map((t) => TranscriptSegment.fromJson(t as Map<String, dynamic>))
          .toList();

  Future<ScribeDraft> makeDraft(String sessionId) async =>
      ScribeDraft.fromJson(await post('/api/v1/scribe/sessions/$sessionId/draft', {}) as Map<String, dynamic>);

  Future<ApproveResult> approveScribe(String sessionId, List<DraftSection> sections, String leaflet) async => ApproveResult.fromJson(await post(
    '/api/v1/scribe/sessions/$sessionId/approve',
    {'sections': [for (final s in sections) {'name': s.name, 'text': s.text}], 'patientLeaflet': leaflet},
  ) as Map<String, dynamic>);

  Future<void> discardScribe(String sessionId) async => await delete('/api/v1/scribe/sessions/$sessionId');

  void close() => _http.close();
}
