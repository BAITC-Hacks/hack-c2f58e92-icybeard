import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Адреса и флаги сборки — через `--dart-define`, а не через поля на экране настроек:
/// `flutter run --dart-define=API_BASE=http://10.0.2.2:8000 --dart-define=KEYCLOAK_URL=http://10.0.2.2:8080`.
/// Пустое значение — платформенный дефолт под локальный стек (`make up`): веб и iOS-симулятор ходят на localhost,
/// эмулятор Android — на 10.0.2.2. Стенд: `API_BASE=https://dc.jurek.kz KEYCLOAK_URL=https://dc.jurek.kz/auth`.
class Env {
  static const _apiBase = String.fromEnvironment('API_BASE');
  static const _keycloakUrl = String.fromEnvironment('KEYCLOAK_URL');
  static const _defaultRegion = String.fromEnvironment('DEFAULT_REGION', defaultValue: '75');

  /// Включает реальный вход через eGov mobile (Smart Bridge / SIGEX); без флага кнопка ведёт на экран «Скоро».
  static const egovEnabled = bool.fromEnvironment('EGOV_ENABLED');

  static const keycloakRealm = 'darumen';
  static const keycloakClientId = 'darumen-mobile';

  static String get apiBase => _apiBase.isNotEmpty ? _apiBase : _localhost(8000);

  static String get keycloakUrl => _keycloakUrl.isNotEmpty ? _keycloakUrl : _localhost(8080);

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
