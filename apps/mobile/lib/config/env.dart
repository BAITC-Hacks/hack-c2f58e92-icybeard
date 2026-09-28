import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Адреса и флаги сборки — через `--dart-define`, а не через поля на экране настроек:
/// `flutter run --dart-define=API_BASE=http://10.0.2.2:8000 --dart-define=KEYCLOAK_URL=http://10.0.2.2:8080`.
/// Пустое значение — платформенный дефолт под локальный стек (`make up`): веб и iOS-симулятор ходят на localhost,
/// эмулятор Android — на 10.0.2.2. Стенд: `API_BASE=https://dc.jurek.kz KEYCLOAK_URL=https://dc.jurek.kz/auth`.
/// Веб-кабинет (`WEB_BASE`) открывается в браузере для ролей без мобильного кабинета, регистрации организации и
/// действий Keycloak (смена пароля, аутентификатор); без флага — корень хоста API (локальный стек: порт 8000 → 3000).
/// Доступность входа через eGov mobile — не флаг сборки, а `egov.available` из `GET /public/service-status`.
class Env {
  static const _apiBase = String.fromEnvironment('API_BASE');
  static const _keycloakUrl = String.fromEnvironment('KEYCLOAK_URL');
  static const _webBase = String.fromEnvironment('WEB_BASE');
  static const _defaultRegion = String.fromEnvironment('DEFAULT_REGION', defaultValue: '75');

  static const keycloakRealm = 'darumen';
  static const keycloakClientId = 'darumen-mobile';

  /// Клиент веб-кабинета: через него идут действия аккаунта в браузере (`kc_action`).
  static const keycloakWebClientId = 'darumen-web';

  static String get apiBase => _apiBase.isNotEmpty ? _apiBase : _localhost(8000);

  static String get keycloakUrl => _keycloakUrl.isNotEmpty ? _keycloakUrl : _localhost(8080);

  /// Корень веб-кабинета без завершающего `/`.
  static String get webBase => _webBase.isNotEmpty ? _trimSlash(_webBase) : webFromApi(apiBase);

  /// Веб живёт на том же хосте, что и API (стенд: nginx отдаёт и `/`, и `/api`); в локальном стеке API на 8000,
  /// веб — на 3000.
  static String webFromApi(String api) {
    final uri = Uri.parse(api);
    return (uri.hasPort && uri.port == 8000 ? uri.replace(port: 3000) : uri).origin;
  }

  /// Страница Keycloak с обязательным действием (`UPDATE_PASSWORD`, `CONFIGURE_TOTP`) для веб-клиента; после него
  /// Keycloak возвращает в веб-кабинет.
  static Uri keycloakAction(String action) => Uri.parse('$keycloakUrl/realms/$keycloakRealm/protocol/openid-connect/auth').replace(queryParameters: {
        'client_id': keycloakWebClientId,
        'response_type': 'code',
        'scope': 'openid',
        'redirect_uri': '$webBase/',
        'kc_action': action,
      });

  static String _trimSlash(String url) => url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  /// Регион по умолчанию для учётной записи без клейма region_kato: г. Алматы, как у демо-пользователей.
  static String get defaultRegion => _defaultRegion;

  static String _localhost(int port) {
    if (kIsWeb) {
      return 'http://localhost:$port';
    }
    // эмулятор Android видит хост-машину как 10.0.2.2; iOS-симулятор и десктоп — как localhost
    return Platform.isAndroid ? 'http://10.0.2.2:$port' : 'http://localhost:$port';
  }
}
