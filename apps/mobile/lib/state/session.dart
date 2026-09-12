import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/client.dart';

/// Кто пользуется приложением и куда ходить за данными.
/// Два режима входа: демо-заголовки X-Actor/X-Role (по умолчанию) и Keycloak
/// (клиент darumen-mobile, password-grant с обновлением токена).
class Session extends ChangeNotifier {
  Session({String? baseUrl}) : _baseUrl = baseUrl ?? defaultBaseUrl();

  static const roles = ['citizen', 'doctor'];
  static const demoActors = {'citizen': 'citizen1', 'doctor': 'doctor1'};
  static const _kcClientId = 'darumen-mobile';

  String _baseUrl;
  String _role = 'citizen';
  String _region = '75';
  String _locale = 'ru';

  // Keycloak
  String _authMode = 'demo'; // demo | keycloak
  String _keycloakUrl = defaultKeycloakUrl();
  String? _kcToken;
  String? _kcRefresh;
  DateTime? _kcExpiresAt;
  String? _kcActor;

  String get baseUrl => _baseUrl;
  String get role => _role;
  String get region => _region;
  String get locale => _locale;
  bool get isDoctor => _role == 'doctor';
  String get authMode => _authMode;
  String get keycloakUrl => _keycloakUrl;
  bool get isKeycloak => _authMode == 'keycloak' && _kcToken != null;
  String? get actor => isKeycloak ? _kcActor : demoActors[_role];

  ApiClient get api => isKeycloak
      ? ApiClient(baseUrl: _baseUrl, locale: _locale, tokenProvider: _freshToken)
      : ApiClient(baseUrl: _baseUrl, actor: demoActors[_role], role: _role, region: _region, locale: _locale);

  static String defaultBaseUrl() {
    if (kIsWeb) return 'http://localhost:8000';
    try {
      return Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://localhost:8000';
    } catch (_) {
      return 'http://localhost:8000';
    }
  }

  static String defaultKeycloakUrl() {
    if (kIsWeb) return 'http://localhost:8080';
    try {
      return Platform.isAndroid ? 'http://10.0.2.2:8080' : 'http://localhost:8080';
    } catch (_) {
      return 'http://localhost:8080';
    }
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _baseUrl = prefs.getString('baseUrl') ?? _baseUrl;
      _role = prefs.getString('role') ?? _role;
      _region = prefs.getString('region') ?? _region;
      _locale = prefs.getString('locale') ?? _locale;
      _authMode = prefs.getString('authMode') ?? _authMode;
      _keycloakUrl = prefs.getString('keycloakUrl') ?? _keycloakUrl;
      _kcToken = prefs.getString('kcToken');
      _kcRefresh = prefs.getString('kcRefresh');
      final expires = prefs.getInt('kcExpiresAt');
      _kcExpiresAt = expires == null ? null : DateTime.fromMillisecondsSinceEpoch(expires);
      _kcActor = prefs.getString('kcActor');
      notifyListeners();
    } catch (_) {
      // без хранилища работаем с настройками по умолчанию
    }
  }

  Future<void> update({String? baseUrl, String? role, String? region, String? locale, String? keycloakUrl}) async {
    _baseUrl = baseUrl ?? _baseUrl;
    _role = role ?? _role;
    _region = region ?? _region;
    _locale = locale ?? _locale;
    _keycloakUrl = keycloakUrl ?? _keycloakUrl;
    notifyListeners();
    await _persist();
  }

  /// Вход паролем демо-пользователя реалма darumen (grant_type=password, клиент darumen-mobile).
  /// Роль и регион берутся из клеймов токена — как в вебе.
  Future<void> login(String username, String password) async {
    final data = await _tokenRequest({'grant_type': 'password', 'username': username, 'password': password});
    _applyTokens(data);
    _authMode = 'keycloak';
    notifyListeners();
    await _persist();
  }

  Future<void> logout() async {
    _authMode = 'demo';
    _kcToken = null;
    _kcRefresh = null;
    _kcExpiresAt = null;
    _kcActor = null;
    notifyListeners();
    await _persist();
  }

  /// Токен для запроса: обновляется за 30 секунд до истечения; при неудаче — выход в демо-режим.
  Future<String?> _freshToken() async {
    if (_kcToken == null) return null;
    final expiring = _kcExpiresAt == null || DateTime.now().isAfter(_kcExpiresAt!.subtract(const Duration(seconds: 30)));
    if (expiring && _kcRefresh != null) {
      try {
        _applyTokens(await _tokenRequest({'grant_type': 'refresh_token', 'refresh_token': _kcRefresh!}));
        await _persist();
      } catch (_) {
        await logout();
        return null;
      }
    }
    return _kcToken;
  }

  Future<Map<String, dynamic>> _tokenRequest(Map<String, String> body) async {
    final response = await http.post(
      Uri.parse('$_keycloakUrl/realms/darumen/protocol/openid-connect/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'client_id': _kcClientId, ...body},
    );
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, json['error'] as String? ?? 'HTTP ${response.statusCode}',
          detail: json['error_description'] as String?);
    }
    return json;
  }

  void _applyTokens(Map<String, dynamic> data) {
    _kcToken = data['access_token'] as String;
    _kcRefresh = data['refresh_token'] as String? ?? _kcRefresh;
    _kcExpiresAt = DateTime.now().add(Duration(seconds: (data['expires_in'] as num?)?.toInt() ?? 300));
    final claims = _jwtClaims(_kcToken!);
    _kcActor = claims['preferred_username'] as String? ?? _kcActor;
    final tokenRoles = ((claims['realm_access'] as Map<String, dynamic>?)?['roles'] as List<dynamic>? ?? []).cast<String>();
    // роль приложения: врач при роли doctor, иначе гражданин; admin считается врачом для демо
    _role = tokenRoles.contains('doctor') || tokenRoles.contains('admin') ? 'doctor' : 'citizen';
    _region = claims['region_kato'] as String? ?? _region;
  }

  static Map<String, dynamic> _jwtClaims(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return {};
    final payload = base64Url.normalize(parts[1]);
    return jsonDecode(utf8.decode(base64Url.decode(payload))) as Map<String, dynamic>;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('baseUrl', _baseUrl);
      await prefs.setString('role', _role);
      await prefs.setString('region', _region);
      await prefs.setString('locale', _locale);
      await prefs.setString('authMode', _authMode);
      await prefs.setString('keycloakUrl', _keycloakUrl);
      if (_kcToken != null) {
        await prefs.setString('kcToken', _kcToken!);
      } else {
        await prefs.remove('kcToken');
      }
      if (_kcRefresh != null) {
        await prefs.setString('kcRefresh', _kcRefresh!);
      } else {
        await prefs.remove('kcRefresh');
      }
      if (_kcExpiresAt != null) {
        await prefs.setInt('kcExpiresAt', _kcExpiresAt!.millisecondsSinceEpoch);
      } else {
        await prefs.remove('kcExpiresAt');
      }
      if (_kcActor != null) {
        await prefs.setString('kcActor', _kcActor!);
      } else {
        await prefs.remove('kcActor');
      }
    } catch (_) {
      // хранилище недоступно: настройки живут до перезапуска
    }
  }
}
