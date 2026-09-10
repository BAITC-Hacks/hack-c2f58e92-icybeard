import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/client.dart';

/// Кто пользуется приложением и куда ходить за данными. Роль и регион как в демо-реалме Keycloak.
class Session extends ChangeNotifier {
  Session({String? baseUrl}) : _baseUrl = baseUrl ?? defaultBaseUrl();

  static const roles = ['citizen', 'doctor'];
  static const demoActors = {'citizen': 'citizen1', 'doctor': 'doctor1'};

  String _baseUrl;
  String _role = 'citizen';
  String _region = '75';
  String _locale = 'ru';

  String get baseUrl => _baseUrl;
  String get role => _role;
  String get region => _region;
  String get locale => _locale;
  bool get isDoctor => _role == 'doctor';

  ApiClient get api => ApiClient(baseUrl: _baseUrl, actor: demoActors[_role], role: _role, region: _region, locale: _locale);

  static String defaultBaseUrl() {
    if (kIsWeb) return 'http://localhost:8000';
    try {
      return Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://localhost:8000';
    } catch (_) {
      return 'http://localhost:8000';
    }
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _baseUrl = prefs.getString('baseUrl') ?? _baseUrl;
      _role = prefs.getString('role') ?? _role;
      _region = prefs.getString('region') ?? _region;
      _locale = prefs.getString('locale') ?? _locale;
      notifyListeners();
    } catch (_) {
      // без хранилища работаем с настройками по умолчанию
    }
  }

  Future<void> update({String? baseUrl, String? role, String? region, String? locale}) async {
    _baseUrl = baseUrl ?? _baseUrl;
    _role = role ?? _role;
    _region = region ?? _region;
    _locale = locale ?? _locale;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('baseUrl', _baseUrl);
      await prefs.setString('role', _role);
      await prefs.setString('region', _region);
      await prefs.setString('locale', _locale);
    } catch (_) {
      // хранилище недоступно: настройки живут до перезапуска
    }
  }
}
