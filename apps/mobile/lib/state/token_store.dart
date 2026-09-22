import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Токены Keycloak в защищённом хранилище платформы (Keychain / EncryptedSharedPreferences), а не в SharedPreferences
/// открытым текстом. Роль и регион в хранилище не пишутся — они всегда выводятся из клеймов access-токена.
class StoredTokens {
  const StoredTokens({required this.access, this.refresh, this.expiresAt});

  final String access;
  final String? refresh;
  final DateTime? expiresAt;
}

class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: true));

  static const _access = 'kc.access';
  static const _refresh = 'kc.refresh';
  static const _expiresAt = 'kc.expiresAt';

  final FlutterSecureStorage _storage;

  Future<StoredTokens?> read() async {
    try {
      final access = await _storage.read(key: _access);
      if (access == null || access.isEmpty) {
        return null;
      }
      final expires = await _storage.read(key: _expiresAt);
      return StoredTokens(
        access: access,
        refresh: await _storage.read(key: _refresh),
        expiresAt: expires == null ? null : DateTime.tryParse(expires),
      );
    } catch (_) {
      return null; // хранилище недоступно (например, после переустановки эмулятора) — начинаем как гость
    }
  }

  Future<void> write(StoredTokens tokens) async {
    try {
      await _storage.write(key: _access, value: tokens.access);
      if (tokens.refresh != null) {
        await _storage.write(key: _refresh, value: tokens.refresh);
      } else {
        await _storage.delete(key: _refresh);
      }
      if (tokens.expiresAt != null) {
        await _storage.write(key: _expiresAt, value: tokens.expiresAt!.toUtc().toIso8601String());
      } else {
        await _storage.delete(key: _expiresAt);
      }
    } catch (_) {
      // без хранилища сессия живёт до перезапуска приложения
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _access);
      await _storage.delete(key: _refresh);
      await _storage.delete(key: _expiresAt);
    } catch (_) {
      // нечего очищать
    }
  }
}
