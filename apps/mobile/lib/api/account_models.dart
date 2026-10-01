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

/// `GET /api/v1/me/security`: пароль, второй фактор и сеансы. SMS-шлюз не подключён, резервные коды — после интеграции.
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

/// Канал доставки уведомления (docs/rbac.md, `GET /me/notifications`).
enum NotificationChannel { inApp, email, sms, push }

/// Событие и его каналы; `locked` — событие `security`, его не отключают.
class NotificationEvent {
  const NotificationEvent({
    required this.code,
    required this.inApp,
    required this.email,
    required this.sms,
    required this.push,
    this.locked = false,
    this.titleRu,
    this.titleKk,
  });

  final String code;
  final String? titleRu;
  final String? titleKk;
  final bool inApp;
  final bool email;
  final bool sms;
  final bool push;
  final bool locked;

  bool channel(NotificationChannel c) => switch (c) {
        NotificationChannel.inApp => inApp,
        NotificationChannel.email => email,
        NotificationChannel.sms => sms,
        NotificationChannel.push => push,
      };

  /// Копия с одним изменённым каналом.
  NotificationEvent withChannel(NotificationChannel c, bool value) => NotificationEvent(
        code: code,
        titleRu: titleRu,
        titleKk: titleKk,
        locked: locked,
        inApp: c == NotificationChannel.inApp ? value : inApp,
        email: c == NotificationChannel.email ? value : email,
        sms: c == NotificationChannel.sms ? value : sms,
        push: c == NotificationChannel.push ? value : push,
      );

  factory NotificationEvent.fromJson(Map<String, dynamic> json) => NotificationEvent(
        code: json['code'] as String? ?? '',
        titleRu: json['titleRu'] as String?,
        titleKk: json['titleKk'] as String?,
        inApp: json['inApp'] as bool? ?? false,
        email: json['email'] as bool? ?? false,
        sms: json['sms'] as bool? ?? false,
        push: json['push'] as bool? ?? false,
        locked: json['locked'] as bool? ?? false,
      );

  /// Строка `PUT /me/notifications` — только код и каналы.
  Map<String, dynamic> toJson() => {'code': code, 'inApp': inApp, 'email': email, 'sms': sms, 'push': push};
}

/// `GET /me/notifications`: события × каналы, тихие часы и дайджест. Мобилка меняет только каналы целиком; всё
/// остальное уходит обратно без изменений, чтобы не затереть настройки, сделанные в вебе.
class NotificationSettings {
  const NotificationSettings({required this.events, this.quietFrom, this.quietTo, this.quietExceptRegulator = false, this.digest = 'off'});

  /// Код события «Изменения моего маршрута»: его канал inApp решает, что гражданин видит в колокольчике (пункты,
  /// которые ждут ответа, приходят всегда).
  static const routeUpdates = 'route_updates';

  /// Код события «Безопасность» — закреплено (`locked`), не отключается.
  static const security = 'security';

  final List<NotificationEvent> events;
  final String? quietFrom;
  final String? quietTo;
  final bool quietExceptRegulator;
  final String digest;

  /// Событие с кодом [code]; null — сервер такого не прислал.
  NotificationEvent? event(String code) => events.where((e) => e.code == code).firstOrNull;

  /// Копия, где у одного события [code] канал [c] включён или выключен; закреплённое или отсутствующее событие не
  /// меняется, тихие часы и дайджест уходят обратно как были.
  NotificationSettings withEventChannel(String code, NotificationChannel c, bool value) => NotificationSettings(
        events: List.unmodifiable([for (final e in events) e.code == code && !e.locked ? e.withChannel(c, value) : e]),
        quietFrom: quietFrom,
        quietTo: quietTo,
        quietExceptRegulator: quietExceptRegulator,
        digest: digest,
      );

  /// Канал включён хотя бы для одного события, которое пользователь может менять (у `security` почта включена
  /// всегда — она не в счёт); если таких событий нет — по всем.
  bool enabled(NotificationChannel c) {
    final editable = events.where((e) => !e.locked);
    return (editable.isEmpty ? events : editable).any((e) => e.channel(c));
  }

  /// Копия, где канал включён или выключен у всех изменяемых событий; закреплённые события не трогаются.
  NotificationSettings withChannel(NotificationChannel c, bool value) => NotificationSettings(
        events: List.unmodifiable([for (final e in events) e.locked ? e : e.withChannel(c, value)]),
        quietFrom: quietFrom,
        quietTo: quietTo,
        quietExceptRegulator: quietExceptRegulator,
        digest: digest,
      );

  factory NotificationSettings.fromJson(Map<String, dynamic> json) => NotificationSettings(
        events: List.unmodifiable(((json['events'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(NotificationEvent.fromJson)
            .where((e) => e.code.isNotEmpty)),
        quietFrom: json['quietFrom'] as String?,
        quietTo: json['quietTo'] as String?,
        quietExceptRegulator: json['quietExceptRegulator'] as bool? ?? false,
        digest: json['digest'] as String? ?? 'off',
      );

  Map<String, dynamic> toJson() => {
        'events': [for (final e in events) e.toJson()],
        'quietFrom': quietFrom,
        'quietTo': quietTo,
        'quietExceptRegulator': quietExceptRegulator,
        'digest': digest,
      };
}
