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

/// Клиент REST API. Вход через заголовки X-Actor/X-Role/X-Region (демо) или Bearer-токен Keycloak.
class ApiClient {
  ApiClient({required this.baseUrl, http.Client? http_, this.actor, this.role, this.region, this.locale = 'ru', this.token, this.tokenProvider})
      : _http = http_ ?? http.Client();

  final String baseUrl;
  final http.Client _http;
  final String? actor;
  final String? role;
  final String? region;
  final String locale;
  final String? token;

  /// Свежий Bearer-токен на каждый запрос (Keycloak с обновлением); null — режим заголовков.
  final Future<String?> Function()? tokenProvider;

  Map<String, String> _headers(String? bearer) => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Accept-Language': locale,
        if (bearer != null) 'Authorization': 'Bearer $bearer',
        if (bearer == null && actor != null) 'X-Actor': actor!,
        if (bearer == null && role != null) 'X-Role': role!,
        if (bearer == null && region != null) 'X-Region': region!,
      };

  Future<String?> _bearer() async => token ?? await tokenProvider?.call();

  Uri _uri(String path, [Map<String, String?>? query]) {
    final clean = <String, String>{for (final e in (query ?? {}).entries) if (e.value != null && e.value!.isNotEmpty) e.key: e.value!};
    return Uri.parse('$baseUrl$path').replace(queryParameters: clean.isEmpty ? null : clean);
  }

  Future<dynamic> get(String path, [Map<String, String?>? query]) async =>
      _decode(await _http.get(_uri(path, query), headers: _headers(await _bearer())));

  Future<dynamic> post(String path, Object body, {Map<String, String>? headers}) async =>
      _decode(await _http.post(_uri(path), headers: {..._headers(await _bearer()), ...?headers}, body: jsonEncode(body)));

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

  Future<List<WorklistItem>> worklist({String? flag}) async =>
      ((await get('/api/v1/journal/worklist', {'flag': flag}))['items'] as List<dynamic>).map((w) => WorklistItem.fromJson(w as Map<String, dynamic>)).toList();

  Future<String> recordDecision(Map<String, dynamic> decision, String idempotencyKey) async =>
      ((await post('/api/v1/journal/decisions', decision, headers: {'Idempotency-Key': idempotencyKey})) as Map<String, dynamic>)['decisionId'] as String;

  Future<List<Nosology>> nosologies() async =>
      ((await get('/api/v1/medicines/nosologies', {'limit': '30'}))['items'] as List<dynamic>).map((n) => Nosology.fromJson(n as Map<String, dynamic>)).toList();

  Future<List<Mnn>> mnn(String nosologyId) async =>
      ((await get('/api/v1/medicines/mnn', {'nosologyId': nosologyId, 'limit': '30'}))['items'] as List<dynamic>).map((m) => Mnn.fromJson(m as Map<String, dynamic>)).toList();

  Future<CheckResponse> checkMedicine({String? mnnId, String? nosologyId, String? regionKato}) async =>
      CheckResponse.fromJson(await post('/api/v1/medicines/check', {'mnnId': mnnId, 'nosologyId': nosologyId, 'regionKato': regionKato}) as Map<String, dynamic>);
}
