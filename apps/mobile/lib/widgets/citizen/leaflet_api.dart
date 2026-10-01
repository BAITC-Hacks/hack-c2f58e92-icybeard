import 'package:flutter/foundation.dart';

import '../../api/client.dart';
import '../../config/env.dart';

/// Публичный текст памятки после приёма — ответ `GET /api/v1/scribe/leaflets/{token}` (сервис скрайба через прокси
/// API, без проверки роли): `{text, language, approvedAt}`. Организации, врача и срока действия в ответе нет.
/// Неизвестный или удалённый токен — 404 (`ApiException`), такую ссылку экран показывает как истёкшую.
@immutable
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

/// Метода в `ApiClient` нет (WAVE0-API-CLIENT, «Not in the spec's work list») — расширение экрана памятки поверх
/// публичного `get`. Перенести в `lib/api` при следующей правке клиента.
extension LeafletApi on ApiClient {
  /// Текст памятки по токену из `GET /route/me/scribe` (`leafletToken` завершённой записи).
  Future<PublicLeaflet> publicLeaflet(String token) async =>
      PublicLeaflet.fromJson(await get('/api/v1/scribe/leaflets/${Uri.encodeComponent(token)}') as Map<String, dynamic>);
}

/// Публичная страница памятки в веб-кабинете — та же ссылка, что врач показывает QR-кодом (решение Q-17).
String leafletWebLink(String token) => '${Env.webBase}/leaflet/$token';
