import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/client.dart';
import '../config/env.dart';
import 'token_store.dart';

enum AuthRole { guest, citizen, doctor }

/// Кто пользуется приложением. Единственный вход — Keycloak (клиент darumen-mobile, password grant с обновлением
/// токена); без входа — гость с публичными экранами. Роль, регион и ИИН всегда выводятся из клеймов токена и не
/// хранятся отдельно. Один ApiClient на всю сессию; уведомляет слушателей только при смене роли или языка, чтобы
/// guard роутера не перезапускался на каждом тихом обновлении токена.
class Session extends ChangeNotifier {
  Session({TokenStore? tokens, http.Client? httpClient})
      : _tokens = tokens ?? TokenStore(),
        _http = httpClient ?? http.Client() {
    api = ApiClient(baseUrl: Env.apiBase, client: _http, tokenProvider: freshToken, locale: () => _locale);
  }

  static const _refreshAhead = Duration(seconds: 30);

  final TokenStore _tokens;
  final http.Client _http;
  late final ApiClient api;

  AuthRole _role = AuthRole.guest;
  String? _username;
  String? _regionClaim;
  String? _iin;
  String _locale = 'ru';
  String _preferredRegion = Env.defaultRegion;
  String? _lastProfile;
  String? _lastNosology;
  String? _access;
  String? _refresh;
  DateTime? _expiresAt;

  AuthRole get role => _role;
  bool get isAuthenticated => _role != AuthRole.guest;
  bool get isDoctor => _role == AuthRole.doctor;
  bool get isCitizen => _role == AuthRole.citizen;
  String? get username => _username;
  String? get iin => _iin;
  String get locale => _locale;

  /// Регион из клейма учётной записи, иначе выбранный гостем, иначе г. Алматы.
  String get region => _regionClaim ?? _preferredRegion;
  bool get regionFromAccount => _regionClaim != null;
  String? get lastProfile => _lastProfile;
  String? get lastNosology => _lastNosology;

  /// Стартовый маршрут по роли: врач — рабочий список, остальные — главная.
  String get home => _role == AuthRole.doctor ? '/doctor/patients' : '/home';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _locale = prefs.getString('locale') ?? _locale;
      _preferredRegion = prefs.getString('region') ?? _preferredRegion;
      _lastProfile = prefs.getString('lastProfile');
      _lastNosology = prefs.getString('lastNosology');
    } catch (_) {
      // без хранилища — настройки по умолчанию
    }
    final stored = await _tokens.read();
    if (stored != null) {
      _access = stored.access;
      _refresh = stored.refresh;
      _expiresAt = stored.expiresAt;
      _applyClaims(stored.access);
    }
    notifyListeners();
  }

  /// Вход паролем (демо-пользователи realm darumen: citizen1, doctor1). Роль, регион и ИИН — из клеймов токена.
  Future<void> login(String username, String password) async {
    _applyTokens(await _tokenRequest({'grant_type': 'password', 'username': username, 'password': password}));
    await _tokens.write(StoredTokens(access: _access!, refresh: _refresh, expiresAt: _expiresAt));
    notifyListeners();
  }

  Future<void> logout() async {
    _access = null;
    _refresh = null;
    _expiresAt = null;
    _username = null;
    _regionClaim = null;
    _iin = null;
    _role = AuthRole.guest;
    await _tokens.clear();
    notifyListeners();
  }

  Future<void> setLocale(String locale) async {
    if (locale == _locale) {
      return;
    }
    _locale = locale;
    notifyListeners();
    await _persist('locale', locale);
  }

  /// Регион гостя и учётной записи без клейма region_kato; при клейме выбор не переопределяет учётную запись.
  Future<void> setRegion(String regionKato) async {
    _preferredRegion = regionKato;
    await _persist('region', regionKato);
  }

  Future<void> rememberProfile(String profileCode) async {
    _lastProfile = profileCode;
    await _persist('lastProfile', profileCode);
  }

  Future<void> rememberNosology(String nosologyId) async {
    _lastNosology = nosologyId;
    await _persist('lastNosology', nosologyId);
  }

  /// Токен для запроса: обновляется за 30 секунд до истечения; если обновить нельзя — выход в гости.
  /// На тихом успешном обновлении слушатели не уведомляются.
  Future<String?> freshToken() async {
    if (_access == null) {
      return null;
    }
    final expiring = _expiresAt == null || DateTime.now().isAfter(_expiresAt!.subtract(_refreshAhead));
    if (expiring && _refresh != null) {
      try {
        _applyTokens(await _tokenRequest({'grant_type': 'refresh_token', 'refresh_token': _refresh!}));
        await _tokens.write(StoredTokens(access: _access!, refresh: _refresh, expiresAt: _expiresAt));
      } catch (_) {
        await logout();
        return null;
      }
    }
    return _access;
  }

  Future<Map<String, dynamic>> _tokenRequest(Map<String, String> body) async {
    final response = await _http.post(
      Uri.parse('${Env.keycloakUrl}/realms/${Env.keycloakRealm}/protocol/openid-connect/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'client_id': Env.keycloakClientId, ...body},
    );
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, json['error'] as String? ?? 'HTTP ${response.statusCode}', detail: json['error_description'] as String?);
    }
    return json;
  }

  void _applyTokens(Map<String, dynamic> data) {
    _access = data['access_token'] as String;
    _refresh = data['refresh_token'] as String? ?? _refresh;
    _expiresAt = DateTime.now().add(Duration(seconds: (data['expires_in'] as num?)?.toInt() ?? 300));
    _applyClaims(_access!);
  }

  void _applyClaims(String token) {
    final claims = jwtClaims(token);
    _username = claims['preferred_username'] as String? ?? _username;
    final roles = ((claims['realm_access'] as Map<String, dynamic>?)?['roles'] as List<dynamic>? ?? const []).cast<String>();
    // admin считается врачом: политика Doctor в API включает роль admin (AuthSetup.cs)
    _role = roles.contains('doctor') || roles.contains('admin') ? AuthRole.doctor : AuthRole.citizen;
    _regionClaim = claims['region_kato'] as String?;
    _iin = claims['iin'] as String?;
  }

  @visibleForTesting
  static Map<String, dynamic> jwtClaims(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      return {};
    }
    try {
      return jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _persist(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {
      // хранилище недоступно: настройка живёт до перезапуска
    }
  }

  @override
  void dispose() {
    api.close();
    super.dispose();
  }
}
