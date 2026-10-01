import 'package:flutter/material.dart';

import '../api/client.dart';
import '../l10n/strings.dart';

/// Единственное место, где ошибка запроса превращается в то, что видит пользователь (PLAN §1, принцип 3; веб —
/// `useRouteData.act`, `ErrorBox.vue`). Рецепт для экрана:
/// - успех (201 или 200 — «уже записано») → перезагрузить объект;
/// - 409 → сначала перезагрузить объект (его состояние изменилось на сервере), потом показать `title — detail`;
/// - 422 → сообщение у поля ([apiFieldError]); поле не на экране — текст в снекбаре;
/// - 403 → «нет доступа» с причиной; 429 → «повторите позже»;
/// - сбой сети и 5xx → «Сервер недоступен» — только в этих случаях.
/// [showApiError] делает это одним вызовом; [apiErrorText] — тот же текст без показа (для ErrorBox, состояний).

/// Что экрану делать с ошибкой.
enum ApiErrorKind {
  /// 409: действие не подходит к текущему состоянию — перезагрузить объект и показать текст сервера.
  conflict,

  /// 422: ошибка ввода — сообщение у поля.
  validation,

  /// 403: нет разрешения, другая организация или регион.
  forbidden,

  /// 404: объекта нет.
  notFound,

  /// 429: слишком много запросов.
  rateLimited,

  /// Сбой сети, тайм-аут, тело не JSON или 5xx — «Сервер недоступен».
  unavailable,

  /// Прочие коды (400, 401, …) — текст сервера как есть.
  other,
}

/// Вид ошибки. Всё, что не [ApiException] (`http.ClientException`, `SocketException`, `TimeoutException`,
/// `FormatException` тела 2xx), — сбой связи с сервером: [ApiErrorKind.unavailable].
ApiErrorKind apiErrorKind(Object? error) {
  if (error is! ApiException) {
    return ApiErrorKind.unavailable;
  }
  return switch (error.status) {
    409 => ApiErrorKind.conflict,
    422 => ApiErrorKind.validation,
    403 => ApiErrorKind.forbidden,
    404 => ApiErrorKind.notFound,
    429 => ApiErrorKind.rateLimited,
    _ when error.isServerError => ApiErrorKind.unavailable,
    _ => ApiErrorKind.other,
  };
}

/// Машинный код вместо фразы (`permission_required`, `no_organization`, `rate_limited`, `invalid_grant`).
final _machineCode = RegExp(r'^[a-z][a-z0-9_]*$');

/// Заголовок проблемы, если он написан для людей: не запасной `HTTP n` и не машинный код.
String? humanTitle(ApiException error) {
  final title = error.title.trim();
  return title.isEmpty || title.startsWith('HTTP ') || _machineCode.hasMatch(title) ? null : title;
}

/// Пояснение сервера, если оно написано для людей (не машинный код из docs/rbac.md).
String? humanDetail(ApiException error) {
  final detail = error.detail?.trim();
  return detail == null || detail.isEmpty || _machineCode.hasMatch(detail) ? null : detail;
}

/// Причина отказа 403 для текста под «Нет доступа к разделу»: коды `no_organization` / `other_organization` —
/// фразы веба, понятный заголовок сервера («Решает больница пациента») — с пояснением через тире. null — причины
/// нет (`permission_required`, пустой ответ, не 403): вызывающий подставляет общий текст.
String? forbiddenReason(S s, Object? error) {
  if (error is! ApiException) {
    return null;
  }
  return switch (error.detail) {
    'no_organization' => s.noAccessNoOrganization,
    'other_organization' => s.noAccessOtherOrganization,
    'permission_required' => null,
    _ => _joined([humanTitle(error), humanDetail(error)]),
  };
}

/// Текст ошибки для пользователя на языке [s] (чистая функция, без показа):
/// - 409, 422, 404 и прочие коды — `заголовок — пояснение — первое сообщение поля` от сервера (без повторов и
///   машинных кодов); если читать нечего — «Сервер ответил ошибкой. Код N.»;
/// - 403 — причина ([forbiddenReason]) или «Нет доступа к разделу»;
/// - 429 — «Слишком много запросов. Повторите через несколько минут.»;
/// - сбой сети и 5xx — «Сервер недоступен. Повторите попытку позже.» без текста исключения.
/// Тексты сервера показываются как есть (по-русски и в казахском интерфейсе — сервер их не переводит).
String apiErrorText(S s, Object error) {
  final kind = apiErrorKind(error);
  if (kind == ApiErrorKind.unavailable || error is! ApiException) {
    return s.apiServerUnavailable;
  }
  return switch (kind) {
    ApiErrorKind.rateLimited => s.apiRateLimited,
    ApiErrorKind.forbidden => forbiddenReason(s, error) ?? s.noAccessTitle,
    _ => _joined([humanTitle(error), humanDetail(error), error.errors?.values.expand((messages) => messages).firstOrNull]) ?? s.loadErrorCode(error.status),
  };
}

/// Сообщение 422 для поля [field] (имя в camelCase, как в API: `reason`, `plannedAt`, `toMoCode`) — показывается
/// под полем (`InputDecoration.errorText`). null — ошибка не 422 или для поля сообщения нет.
String? apiFieldError(Object? error, String field) => error is ApiException && error.isValidation ? error.fieldError(field) : null;

/// Показывает ошибку действия одним вызовом из `catch` экрана и возвращает её вид:
/// - 409 и задан [reload] — сначала ждёт перезагрузку объекта, затем показывает текст (ошибка самой перезагрузки
///   уходит в `FlutterError.reportError`, текст 409 всё равно показывается);
/// - 422 с сообщением для одного из [fields] (поля, которые экран показывает со своей ошибкой) — снекбара нет,
///   экран берёт текст через [apiFieldError];
/// - остальное — снекбар с [apiErrorText].
/// Контекст читается до ожидания, поэтому экран может закрыться во время перезагрузки. Без ScaffoldMessenger
/// ничего не показывается.
Future<ApiErrorKind> showApiError(BuildContext context, Object error, {Future<void> Function()? reload, Iterable<String> fields = const []}) async {
  final kind = apiErrorKind(error);
  final s = S.at(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (kind == ApiErrorKind.conflict && reload != null) {
    try {
      await reload();
    } on Object catch (reloadError, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: reloadError,
        stack: stack,
        library: 'api_error',
        context: ErrorDescription('while reloading after a 409 conflict'),
      ));
    }
  }
  if (kind == ApiErrorKind.validation && fields.any((field) => apiFieldError(error, field) != null)) {
    return kind;
  }
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(apiErrorText(s, error)), duration: const Duration(seconds: 6)));
  return kind;
}

/// Непустые части без повторов через « — »; null, если частей нет.
String? _joined(Iterable<String?> parts) {
  final unique = <String>[];
  for (final part in parts) {
    final text = part?.trim();
    if (text != null && text.isNotEmpty && !unique.contains(text)) {
      unique.add(text);
    }
  }
  return unique.isEmpty ? null : unique.join(' — ');
}
