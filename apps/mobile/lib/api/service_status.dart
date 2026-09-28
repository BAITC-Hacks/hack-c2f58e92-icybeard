/// `GET /api/v1/public/service-status` — какие внешние сервисы стенда работают: почта (SMTP), push, SMS и вход через
/// eGov mobile (Smart Bridge). Эндпоинт анонимный. Разбор терпимый: неизвестная причина — общий текст, сервис,
/// которого нет в ответе или который пришёл не объектом, — недоступен; ответ не объектом — как сбой запроса
/// ([ServiceStatus.fallback]).
library;

/// Причина недоступности сервиса; [other] — код, которого клиент не знает, или причины нет.
enum ServiceReason {
  smtpNotConfigured('smtp_not_configured'),
  smtpUnreachable('smtp_unreachable'),
  notReady('not_ready'),
  endpointNotProvided('endpoint_not_provided'),
  other(null);

  const ServiceReason(this.code);

  /// Код причины в ответе API.
  final String? code;

  static ServiceReason parse(Object? value) => values.firstWhere((r) => r.code != null && r.code == value, orElse: () => other);
}

/// Состояние одного сервиса: работает, не работает (с причиной) или неизвестно (статус не удалось получить).
class ServiceAvailability {
  const ServiceAvailability.up()
      : available = true,
        reason = null;

  const ServiceAvailability.down([ServiceReason this.reason = ServiceReason.other]) : available = false;

  const ServiceAvailability.unknown()
      : available = null,
        reason = null;

  /// Сервис из ответа: `available: true` — работает, иначе не работает; не объект — не работает без причины.
  factory ServiceAvailability.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      return const ServiceAvailability.down();
    }
    return json['available'] == true ? const ServiceAvailability.up() : ServiceAvailability.down(ServiceReason.parse(json['reason']));
  }

  /// true — работает, false — нет, null — статус неизвестен.
  final bool? available;

  /// Причина для неработающего сервиса; null — работает или неизвестно.
  final ServiceReason? reason;

  bool get isUp => available == true;
  bool get isDown => available == false;
  bool get isUnknown => available == null;

  @override
  bool operator ==(Object other) => other is ServiceAvailability && other.available == available && other.reason == reason;

  @override
  int get hashCode => Object.hash(available, reason);

  @override
  String toString() => isUnknown ? 'unknown' : (isUp ? 'up' : 'down(${reason?.code ?? 'other'})');
}

/// Сводка по сервисам. Сравнение — только по состояниям сервисов: опрос с новым `checkedAt` и тем же состоянием
/// не перерисовывает экраны.
class ServiceStatus {
  const ServiceStatus({required this.email, required this.push, required this.sms, required this.egov, this.checkedAt});

  /// Ответ API; не объект — как сбой запроса.
  factory ServiceStatus.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      return fallback;
    }
    final checkedAt = json['checkedAt'];
    return ServiceStatus(
      checkedAt: checkedAt is String ? DateTime.tryParse(checkedAt) : null,
      email: ServiceAvailability.fromJson(json['email']),
      push: ServiceAvailability.fromJson(json['push']),
      sms: ServiceAvailability.fromJson(json['sms']),
      egov: ServiceAvailability.fromJson(json['egov']),
    );
  }

  /// Статус ещё не пришёл или запрос не удался: про почту ничего не утверждаем (баннера нет), push, SMS и eGov
  /// считаем недоступными — пока они не подключены, обещать их нельзя.
  static const fallback = ServiceStatus(
    email: ServiceAvailability.unknown(),
    push: ServiceAvailability.down(),
    sms: ServiceAvailability.down(),
    egov: ServiceAvailability.down(),
  );

  final DateTime? checkedAt;
  final ServiceAvailability email;
  final ServiceAvailability push;
  final ServiceAvailability sms;
  final ServiceAvailability egov;

  /// true — хотя бы один канал вне приложения (почта, SMS, push) доставляет уведомления.
  bool get anyExternalChannelUp => email.isUp || sms.isUp || push.isUp;

  @override
  bool operator ==(Object other) => other is ServiceStatus && other.email == email && other.push == push && other.sms == sms && other.egov == egov;

  @override
  int get hashCode => Object.hash(email, push, sms, egov);

  @override
  String toString() => 'ServiceStatus(email: $email, push: $push, sms: $sms, egov: $egov)';
}
