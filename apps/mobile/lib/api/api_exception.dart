import 'dart:convert';

/// Ошибка API: ответ с HTTP-кодом ≥ 400 в формате problem+json (RFC 9457), разобранный терпимо: тело не-JSON,
/// detail-список, поля не того типа не роняют разбор. Тексты [title] и [detail] написаны сервером для людей (только
/// по-русски) и показываются как есть; своих текстов для пользователя здесь нет — их подбирает слой экранов по
/// [status] и флагам ниже.
///
/// Порядок обработки на экране: 409 — перезагрузить объект, затем показать [title] — [detail]; 422 — [fieldError]
/// у поля; 403 — состояние «нет доступа»; 429 — «попробуйте позже»; «Сервер недоступен» — только сбой сети и 5xx.
///
/// Каких исключений ждать от `ApiClient`:
/// - [ApiException] — сервер ответил кодом ≥ 400 (тело любое: problem+json, HTML прокси, пустое);
/// - `http.ClientException` — сбой транспорта: нет сети, DNS, обрыв соединения (на устройстве это и
///   `SocketException`); ошибка TLS приходит как `HandshakeException`. Такие ошибки не заворачиваются в
///   [ApiException]: «Сервер недоступен» показывается для них и для [isServerError];
/// - `FormatException` — ответ 2xx, но тело не JSON (страница авторизации Wi-Fi и т. п.) — тоже «Сервер недоступен».
///
/// Все поля неизменяемы: [errors] и [permissions], разобранные из ответа, — неизменяемые коллекции.
class ApiException implements Exception {
  const ApiException(
    this.status,
    this.title, {
    this.detail,
    this.errors,
    this.stateCode,
    this.requestId,
    this.permissions,
    this.retryAfterSeconds,
  });

  /// Разбор ответа с кодом ≥ 400. [statusCode] — HTTP-код ответа, [bodyBytes] — тело как есть,
  /// [headers] — заголовки ответа (имена в любом регистре). Никогда не бросает: в худшем случае
  /// получается `ApiException(statusCode, 'HTTP statusCode')`.
  factory ApiException.fromResponse(int statusCode, List<int> bodyBytes, Map<String, String> headers) {
    final problem = _jsonObject(utf8.decode(bodyBytes, allowMalformed: true)) ?? const <String, dynamic>{};
    return ApiException(
      statusCode,
      _text(problem['title']) ?? 'HTTP $statusCode',
      detail: _detail(problem['detail']),
      errors: _errors(problem['errors']),
      // ключ status в теле 409 повторяется (RouteJournal, ScribeEndpoints): jsonDecode оставляет последнее
      // значение — строку состояния, а HTTP-код берётся только из ответа
      stateCode: _text(problem['status']),
      requestId: _text(problem['requestId']),
      permissions: _strings(problem['permissions']),
      retryAfterSeconds: _retryAfter(headers),
    );
  }

  /// HTTP-код ответа — только из статус-строки ответа, никогда из тела (в теле 409 под ключом status — строка).
  final int status;

  /// Заголовок проблемы от сервера; без него — `HTTP n`.
  final String title;

  /// Пояснение для человека или null. Список сообщений FastAPI (проксированный скрайб) даёт null; сырое тело
  /// ответа сервиса скрайба, вложенное строкой JSON («Запись не утверждена»), разворачивается до его detail.
  final String? detail;

  /// Ошибки полей 422: имя поля в camelCase → сообщения. null — ошибок полей нет.
  final Map<String, List<String>>? errors;

  /// Текущее состояние объекта из 409 маршрута и согласий на запись: статус маршрута (`transfer_pending_consent`,
  /// `closed`, …) или статус согласия (`pending`, `recording`, …). null — сервер его не прислал. Логику на нём не
  /// строить: после 409 объект перезагружается, строка — подсказка.
  final String? stateCode;

  /// id уже действующего запроса согласия из 409 «Запрос уже отправлен» (`POST /scribe-consents`).
  final String? requestId;

  /// Разрешения, которых не хватило, из 403 `permission_required`; null — расширения нет.
  final List<String>? permissions;

  /// Через сколько секунд повторить запрос — заголовок `Retry-After` ответа 429 (только число секунд).
  final int? retryAfterSeconds;

  /// 409: действие не подходит к текущему состоянию — перезагрузить объект, затем показать [title] — [detail].
  bool get isConflict => status == 409;

  /// 422: ошибка ввода — сообщение у поля через [fieldError], без поля — [title] и [detail].
  bool get isValidation => status == 422;

  /// 403: нет разрешения, другая организация или регион — состояние «нет доступа».
  bool get isForbidden => status == 403;

  /// 404: объекта нет (пациент, направление, запрос согласия, сессия записи).
  bool get isNotFound => status == 404;

  /// 429: слишком много запросов — повторить позже (см. [retryAfterSeconds]).
  bool get isRateLimited => status == 429;

  /// 5xx: сервер или его зависимость недоступны — как и сбой сети, «Сервер недоступен».
  bool get isServerError => status >= 500 && status <= 599;

  /// Первое сообщение для поля [name] (camelCase, как в API) или null, если для поля ошибок нет.
  String? fieldError(String name) => errors?[name]?.firstOrNull;

  @override
  String toString() => detail == null ? title : '$title: $detail';
}

Map<String, dynamic>? _jsonObject(String text) {
  if (text.trim().isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// Непустая строка или null.
String? _text(Object? value) => value is String && value.trim().isNotEmpty ? value : null;

/// detail — только строка. Строка, которая сама является JSON-объектом (сырой ответ сервиса скрайба в 409/422
/// «Запись не утверждена»), разворачивается до вложенного detail; если она не разбирается — остаётся как есть.
String? _detail(Object? value) {
  final text = _text(value);
  if (text == null || !text.trimLeft().startsWith('{')) {
    return text;
  }
  final inner = _jsonObject(text);
  return inner == null ? text : _text(inner['detail']);
}

/// errors — объект «поле → список»; значения не-списки отбрасываются, элементы приводятся к строкам, null-элементы
/// пропускаются. Пустой результат — null.
Map<String, List<String>>? _errors(Object? value) {
  if (value is! Map) {
    return null;
  }
  final fields = <String, List<String>>{
    for (final entry in value.entries)
      if (entry.value case final List<dynamic> messages) '${entry.key}': List.unmodifiable([for (final m in messages) if (m != null) '$m']),
  };
  return fields.isEmpty ? null : Map.unmodifiable(fields);
}

List<String>? _strings(Object? value) => value is List ? List.unmodifiable([for (final item in value) if (item != null) '$item']) : null;

/// `Retry-After` в секундах (сервер шлёт только их); HTTP-дата и отрицательные значения — null.
int? _retryAfter(Map<String, String> headers) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == 'retry-after') {
      final seconds = int.tryParse(entry.value.trim());
      return seconds != null && seconds >= 0 ? seconds : null;
    }
  }
  return null;
}
