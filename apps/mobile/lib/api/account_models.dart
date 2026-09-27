import '../state/permissions.dart';

/// Модели аккаунта по docs/rbac.md («Я и мой аккаунт»): `GET /me`, `GET /me/security`. Разбор терпимый: поля,
/// которых нет в ответе, остаются пустыми — экран показывает то, что пришло, и ничего не додумывает.

/// `GET /api/v1/me` — кто вошёл и что ему можно.
class Me {
  const Me({
    required this.userId,
    required this.displayName,
    required this.roles,
    this.grants,
    this.email,
    this.emailVerified = false,
    this.moCode,
    this.moName,
    this.regionKato,
    this.iinMasked,
    this.otpConfigured,
  });

  final String userId;
  final String displayName;
  final String? email;
  final bool emailVerified;
  final List<String> roles;

  /// Разрешения из API; null — ответ без поля `permissions` (тогда сессия берёт фолбэк по ролям токена).
  final Grants? grants;
  final String? moCode;
  final String? moName;
  final String? regionKato;

  /// ИИН только маской, как его отдаёт API.
  final String? iinMasked;

  /// `onboarding.otpConfigured`; null — API не сообщил.
  final bool? otpConfigured;

  factory Me.fromJson(Map<String, dynamic> json) {
    final onboarding = json['onboarding'] as Map<String, dynamic>?;
    return Me(
      userId: json['userId'] as String? ?? json['actor'] as String? ?? '',
      displayName: json['displayName'] as String? ?? json['actor'] as String? ?? '',
      email: json['email'] as String?,
      emailVerified: json['emailVerified'] as bool? ?? false,
      roles: ((json['roles'] as List<dynamic>?) ?? const []).whereType<String>().toList(growable: false),
      grants: json['permissions'] is List<dynamic> ? Grants.fromJson(json['permissions'] as List<dynamic>) : null,
      moCode: json['moCode'] as String?,
      moName: json['moName'] as String?,
      regionKato: json['regionKato'] as String?,
      iinMasked: json['iinMasked'] as String?,
      otpConfigured: onboarding?['otpConfigured'] as bool?,
    );
  }
}

/// Активный сеанс Keycloak («Устройства»).
class DeviceSession {
  const DeviceSession({required this.id, required this.current, this.device, this.browser, this.ip, this.lastAccess});

  final String id;
  final String? device;
  final String? browser;
  final String? ip;
  final String? lastAccess;
  final bool current;

  factory DeviceSession.fromJson(Map<String, dynamic> json) => DeviceSession(
        id: json['id'] as String? ?? '',
        device: json['device'] as String?,
        browser: json['browser'] as String?,
        ip: json['ip'] as String?,
        lastAccess: json['lastAccess'] as String?,
        current: json['current'] as bool? ?? false,
      );
}

/// `GET /api/v1/me/security`: пароль, второй фактор и сеансы. SMS и резервные коды — после интеграции.
class SecurityInfo {
  const SecurityInfo({required this.otpConfigured, required this.smsAvailable, required this.sessions, this.passwordChangedAt});

  final String? passwordChangedAt;
  final bool otpConfigured;
  final bool smsAvailable;
  final List<DeviceSession> sessions;

  /// Сколько полных дней назад менялся пароль; null — дата неизвестна.
  int? passwordAgeDays(DateTime now) {
    final at = passwordChangedAt == null ? null : DateTime.tryParse(passwordChangedAt!);
    return at == null ? null : now.difference(at.toLocal()).inDays;
  }

  factory SecurityInfo.fromJson(Map<String, dynamic> json) => SecurityInfo(
        passwordChangedAt: json['passwordChangedAt'] as String?,
        otpConfigured: json['otpConfigured'] as bool? ?? false,
        smsAvailable: json['smsAvailable'] as bool? ?? false,
        sessions: ((json['sessions'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(DeviceSession.fromJson)
            .where((d) => d.id.isNotEmpty)
            .toList(growable: false),
      );
}
