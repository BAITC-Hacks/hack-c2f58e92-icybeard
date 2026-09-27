import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../config/env.dart';
import 'permissions.dart';
import 'token_store.dart';

export 'permissions.dart' show Perm, ShellKind;

/// Кто пользуется приложением. Единственный вход — Keycloak (клиент darumen-mobile, password grant с обновлением
/// токена; при настроенном TOTP — с параметром `totp`); без входа открыт только экран входа (shell null). После входа
/// сессия читает `GET /api/v1/me` — роли и разрешения; пока `/me` недоступен (404, сеть), разрешения выводятся из
/// ролей токена по матрице docs/rbac.md (permissions.dart). Регион и ИИН — из клеймов токена, не хранятся отдельно.
/// «Запомнить на 30 дней» выключено — токены живут только в памяти до закрытия приложения. Один ApiClient на всю
/// сессию; слушатели уведомляются при смене shell/разрешений или языка, но не на тихом обновлении токена.
class Session extends ChangeNotifier {
  Session({TokenStore? tokens, http.Client? httpClient})
      : _tokens = tokens ?? TokenStore(),
        _http = httpClient ?? http.Client() {
    api = ApiClient(baseUrl: Env.apiBase, client: _http, tokenProvider: freshToken, locale: () => _locale);
  }

  static const _refreshAhead = Duration(seconds: 30);
  static const _meTimeout = Duration(seconds: 8);

  final TokenStore _tokens;
  final http.Client _http;
  late final ApiClient api;

  ShellKind? _shell;
  List<String> _tokenRoles = const [];
  Grants _grants = Grants.none;
  Me? _me;
  String? _username;
  String? _name;
  String? _email;
  String? _moClaim;
  String? _regionClaim;
  String? _iin;
  String _locale = 'ru';
  String _preferredRegion = Env.defaultRegion;
  String? _lastProfile;
  String? _lastNosology;
  String? _seenDecisionId;
  ShellKind? _lastShell;
  Set<String> _otpUsers = const {};
  bool _remember = true;
  String? _access;
  String? _refresh;
  DateTime? _expiresAt;

  /// Набор вкладок: врач (`worklist.view`), гражданин (`route.own`), веб-версия (остальные роли); null — не вошёл.
  ShellKind? get shell => _shell;
  bool get isAuthenticated => _shell != null;
  bool get isDoctor => _shell == ShellKind.doctor;
  bool get isCitizen => _shell == ShellKind.citizen;
  bool get isWebOnly => _shell == ShellKind.web;

  /// Разрешение из `/me` (или фолбэка по ролям). Проверка только для интерфейса — API перепроверяет каждое действие.
  bool can(String code) => _grants.can(code);
  bool canAny(Iterable<String> codes) => _grants.canAny(codes);
  Grants get grants => _grants;

  /// true — разрешения пришли из `/me`, false — фолбэк по ролям токена.
  bool get grantsFromApi => _me?.grants != null;
  List<String> get roles => _me == null || _me!.roles.isEmpty ? _tokenRoles : _me!.roles;
  String? get primaryRoleKey => primaryRole(roles);
  Me? get me => _me;

  String? get username => _username;
  String? get displayName => _me?.displayName.isNotEmpty == true ? _me!.displayName : _name;
  String? get email => _me?.email ?? _email;
  String? get organizationName => _me?.moName;
  String? get iin => _iin;
  String get locale => _locale;
  bool get rememberMe => _remember;

  /// Каким кабинетом пользовались на этом устройстве в прошлый раз — подпись «Кабинет врача» на входе.
  ShellKind? get lastShell => _lastShell;

  /// Для этого логина на устройстве уже вводили код из приложения-аутентификатора: вход сразу спросит код.
  bool needsOtp(String username) => _otpUsers.contains(username.trim().toLowerCase());

  /// Регион из клейма учётной записи, иначе выбранный в профиле, иначе г. Алматы.
  String get region => _regionClaim ?? _preferredRegion;
  bool get regionFromAccount => _regionClaim != null;
  String? get lastProfile => _lastProfile;
  String? get lastNosology => _lastNosology;

  /// Последнее решение врача, которое гражданин закрыл кнопкой «Понятно»: карточка «Ответ врача» не повторяется.
  String? get seenDecisionId => _seenDecisionId;

  /// Стартовый маршрут: врач — рабочий список, гражданин — главная, прочие роли — «Кабинет в веб-версии».
  String get home => switch (_shell) {
        ShellKind.doctor => '/doctor/patients',
        ShellKind.citizen => '/home',
        ShellKind.web => '/web',
        null => '/login',
      };

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _locale = prefs.getString('locale') ?? _locale;
      _preferredRegion = prefs.getString('region') ?? _preferredRegion;
      _lastProfile = prefs.getString('lastProfile');
      _lastNosology = prefs.getString('lastNosology');
      _seenDecisionId = prefs.getString('seenDecision');
      _lastShell = ShellKind.values.where((k) => k.name == prefs.getString('lastShell')).firstOrNull;
      _otpUsers = (prefs.getStringList('otpUsers') ?? const []).toSet();
    } catch (_) {
      // без хранилища — настройки по умолчанию
    }
    final stored = await _tokens.read();
    if (stored != null) {
      _access = stored.access;
      _refresh = stored.refresh;
      _expiresAt = stored.expiresAt;
      _remember = true;
      _applyClaims(stored.access);
      _recompute();
    }
    notifyListeners();
    if (stored != null) {
      await refreshMe();
    }
  }

  /// Вход паролем (демо-пользователи realm darumen, пароль `darumen`); [otp] — 6 цифр из приложения-аутентификатора.
  /// Keycloak отвечает одинаковым `invalid_grant` на неверный пароль, неверный и отсутствующий код — различить их
  /// нельзя, поэтому экран входа предлагает войти с кодом. [remember] = false — токены не пишутся в хранилище.
  Future<void> login(String username, String password, {String? otp, bool remember = true}) async {
    final data = await _tokenRequest({
      'grant_type': 'password',
      'username': username,
      'password': password,
      if (otp != null && otp.isNotEmpty) 'totp': otp,
    });
    _remember = remember;
    _me = null;
    _applyTokens(data);
    _recompute();
    await _persistTokens();
    if (otp != null && otp.isNotEmpty) {
      await _markOtpUser(username, true);
    }
    await refreshMe(notify: false);
    notifyListeners();
  }

  /// Перечитывает `/me`: разрешения API заменяют фолбэк по ролям; при 404, ошибке или таймауте остаётся фолбэк.
  Future<void> refreshMe({bool notify = true}) async {
    if (_access == null) {
      return;
    }
    final before = (_shell, _grants.codes.toSet());
    try {
      _me = await api.me().timeout(_meTimeout);
      final otp = _me!.otpConfigured;
      if (otp != null && _username != null) {
        await _markOtpUser(_username!, otp);
      }
    } catch (_) {
      _me = null; // /me ещё нет (бэкенд) или сеть — работаем по ролям токена
    }
    if (_access == null) {
      return; // пока ждали /me, обновление токена не удалось и сессия вышла
    }
    _recompute();
    if (_shell != null) {
      _lastShell = _shell;
      await _persist('lastShell', _shell!.name);
    }
    final after = (_shell, _grants.codes.toSet());
    if (notify && (before.$1 != after.$1 || !setEquals(before.$2, after.$2))) {
      notifyListeners();
    }
  }

  Future<void> logout() async {
    final refresh = _refresh;
    _access = null;
    _refresh = null;
    _expiresAt = null;
    _username = null;
    _name = null;
    _email = null;
    _moClaim = null;
    _regionClaim = null;
    _iin = null;
    _tokenRoles = const [];
    _me = null;
    _recompute();
    await _tokens.clear();
    notifyListeners();
    if (refresh != null) {
      unawaited(_endKeycloakSession(refresh));
    }
  }

  Future<void> setLocale(String locale) async {
    if (locale == _locale) {
      return;
    }
    _locale = locale;
    notifyListeners();
    await _persist('locale', locale);
  }

  /// Регион учётной записи без клейма region_kato; при клейме выбор не переопределяет учётную запись.
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

  Future<void> markDecisionSeen(String decisionId) async {
    _seenDecisionId = decisionId;
    notifyListeners();
    await _persist('seenDecision', decisionId);
  }

  /// Токен для запроса: обновляется за 30 секунд до истечения; если обновить нельзя — выход на экран входа.
  /// На тихом успешном обновлении слушатели не уведомляются (кроме смены shell, если роли поменялись).
  Future<String?> freshToken() async {
    if (_access == null) {
      return null;
    }
    final expiring = _expiresAt == null || DateTime.now().isAfter(_expiresAt!.subtract(_refreshAhead));
    if (expiring && _refresh != null) {
      try {
        final shellBefore = _shell;
        _applyTokens(await _tokenRequest({'grant_type': 'refresh_token', 'refresh_token': _refresh!}));
        _recompute();
        await _persistTokens();
        if (_shell != shellBefore) {
          notifyListeners();
        }
      } catch (_) {
        await logout();
        return null;
      }
    }
    return _access;
  }

  Uri get _openIdBase => Uri.parse('${Env.keycloakUrl}/realms/${Env.keycloakRealm}/protocol/openid-connect');

  Future<Map<String, dynamic>> _tokenRequest(Map<String, String> body) async {
    final response = await _http.post(
      Uri.parse('$_openIdBase/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'client_id': Env.keycloakClientId, ...body},
    );
    final text = utf8.decode(response.bodyBytes);
    final json = text.isEmpty ? const <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, json['error'] as String? ?? 'HTTP ${response.statusCode}', detail: json['error_description'] as String?);
    }
    return json;
  }

  /// Завершает сеанс Keycloak по refresh-токену; без сети сеанс истечёт сам — ошибки не показываются.
  Future<void> _endKeycloakSession(String refresh) async {
    try {
      await _http.post(
        Uri.parse('$_openIdBase/logout'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'client_id': Env.keycloakClientId, 'refresh_token': refresh},
      );
    } catch (_) {
      // сеанс истечёт по таймауту Keycloak
    }
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
    _name = claims['name'] as String?;
    _email = claims['email'] as String?;
    _tokenRoles = ((claims['realm_access'] as Map<String, dynamic>?)?['roles'] as List<dynamic>? ?? const []).whereType<String>().toList();
    _moClaim = claims['mo_code'] as String?;
    _regionClaim = claims['region_kato'] as String?;
    _iin = claims['iin'] as String?;
  }

  /// Разрешения: из `/me`, иначе по ролям токена; shell — из разрешений.
  void _recompute() {
    if (_access == null) {
      _grants = Grants.none;
      _shell = null;
      return;
    }
    _grants = _me?.grants ?? Grants.fromRoles(_tokenRoles, hasOrganization: _moClaim != null);
    _shell = _grants.shell;
  }

  Future<void> _persistTokens() async {
    if (_remember) {
      await _tokens.write(StoredTokens(access: _access!, refresh: _refresh, expiresAt: _expiresAt));
    } else {
      await _tokens.clear(); // «Запомнить» выключено: после закрытия приложения — снова вход
    }
  }

  Future<void> _markOtpUser(String username, bool on) async {
    final key = username.trim().toLowerCase();
    final next = {..._otpUsers};
    final changed = on ? next.add(key) : next.remove(key);
    if (!changed) {
      return;
    }
    _otpUsers = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('otpUsers', next.toList());
    } catch (_) {
      // подсказка живёт до перезапуска
    }
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

  Future<void> _persist(String key, String? value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, value);
      }
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
