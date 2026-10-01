// Колокольчики (§3.7, §3.8 контракта): лента гражданина по его маршруту и колокольчик персонала больницы. Push нет —
// оба опрашиваются. models.dart реэкспортирует этот файл, импорты экранов не меняются.

/// `GET /api/v1/route/me/notifications?regionKato=` — что другие сделали на маршруте гражданина, плюс напоминания.
/// Всегда 200; нет маршрута в регионе — `unread: 0`, пустой список.
class CitizenNotifications {
  const CitizenNotifications({this.unread = 0, this.items = const []});

  /// Сколько пунктов с read == false — число на значке вкладки.
  final int unread;

  /// Сначала needsAction, затем по времени, свежие первыми (порядок сервера, не пересортировывать).
  final List<CitizenNotification> items;

  factory CitizenNotifications.fromJson(Map<String, dynamic> json) => CitizenNotifications(
        unread: (json['unread'] as num?)?.toInt() ?? 0,
        items: List.unmodifiable((json['items'] as List<dynamic>? ?? const []).map((i) => CitizenNotification.fromJson(i as Map<String, dynamic>))),
      );
}

/// Пункт ленты гражданина. Отметка прочтения — `POST /route/me/notifications/{id}/read` (204, общая с вебом).
class CitizenNotification {
  const CitizenNotification({
    required this.id,
    required this.kind,
    required this.at,
    this.moName,
    this.plannedAt,
    this.reason,
    this.needsAction = false,
    this.read = false,
    this.count,
  });

  /// Для журнальных видов — id записи журнала (у redirect = `progress.transfer.decisionId`); для scribe_consent —
  /// requestId согласия (годится для `POST /route/me/scribe/{id}/answer`); для tests_expiring и scribe_leaflet —
  /// устойчивый хеш, не id сущности (токен памятки берётся из `GET /route/me/scribe`).
  final String id;

  /// Один из `RouteCodes.notificationKinds`: redirect | keep | cancel | confirm | reject | reschedule | admit |
  /// no_show | discharge | close (что сделали другие; свои действия гражданина сюда не попадают) | tests_expiring |
  /// scribe_consent | scribe_leaflet. Незнакомый вид — запасная подпись.
  final String kind;

  /// ISO-штамп события. У tests_expiring это время запроса («сейчас») — его не показывать.
  final String at;

  /// Больница события: цель перевода, принимающая больница или та, что просит записать приём; null — нет.
  final String? moName;

  /// `yyyy-MM-dd`: у confirm/reschedule — назначенная дата, у tests_expiring — дата, к которой истекут анализы.
  final String? plannedAt;

  /// Причина врача / больницы, комментарий врача к запросу записи; у discharge гражданину — null.
  final String? reason;

  /// true — нужен ответ гражданина: текущий redirect, ждущий согласия, или запрос записи приёма в статусе pending.
  /// Такие пункты приходят всегда, даже если гражданин выключил уведомления о маршруте.
  final bool needsAction;
  final bool read;

  /// Только у tests_expiring — сколько анализов истекают или истекли; иначе null.
  final int? count;

  factory CitizenNotification.fromJson(Map<String, dynamic> json) => CitizenNotification(
        id: json['id'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        at: json['at'] as String? ?? '',
        moName: json['moName'] as String?,
        plannedAt: json['plannedAt'] as String?,
        reason: json['reason'] as String?,
        needsAction: json['needsAction'] as bool? ?? false,
        read: json['read'] as bool? ?? false,
        count: (json['count'] as num?)?.toInt(),
      );
}

/// `GET /api/v1/journal/notifications/bell?moCode=` — колокольчик персонала своей больницы. Списки содержат только
/// непрочитанное; без больницы в области видимости — нули и пустые списки, не ошибка.
class NotificationBell {
  const NotificationBell({
    this.pendingIncomingCount = 0,
    this.unreadConfirmations = const [],
    this.unreadDischarges = const [],
    this.patientSignals = const [],
  });

  /// Переводы в мою больницу, ждущие моего подтверждения (transfer_pending_confirmation).
  final int pendingIncomingCount;

  /// Мои направления, которые принимающая больница подтвердила; прочитано — `markBellRead('referral-confirmed', decisionId)`.
  final List<SentReferralConfirmation> unreadConfirmations;

  /// Мои направления, по которым пациента выписали с эпикризом; прочитано — `markBellRead('referral-discharged', decisionId)`.
  final List<DischargeReady> unreadDischarges;

  /// Что сделали пациенты моей больницы за 30 дней (не больше 30, только непрочитанное); прочитано —
  /// `markBellRead('patient-signal', id)`. null/нет в ответе — пустой список.
  final List<PatientEvent> patientSignals;

  /// Число на значке колокольчика — как в вебе: ожидающие входящие плюс все три непрочитанных списка.
  int get totalUnread => pendingIncomingCount + unreadConfirmations.length + unreadDischarges.length + patientSignals.length;

  factory NotificationBell.fromJson(Map<String, dynamic> json) => NotificationBell(
        pendingIncomingCount: (json['pendingIncomingCount'] as num?)?.toInt() ?? 0,
        unreadConfirmations: List.unmodifiable(
            (json['unreadConfirmations'] as List<dynamic>? ?? const []).map((c) => SentReferralConfirmation.fromJson(c as Map<String, dynamic>))),
        unreadDischarges:
            List.unmodifiable((json['unreadDischarges'] as List<dynamic>? ?? const []).map((d) => DischargeReady.fromJson(d as Map<String, dynamic>))),
        patientSignals: List.unmodifiable((json['patientSignals'] as List<dynamic>? ?? const []).map((s) => PatientEvent.fromJson(s as Map<String, dynamic>))),
      );
}

/// Принимающая больница подтвердила перевод, отправленный моей больницей (kind прочтения — referral-confirmed).
class SentReferralConfirmation {
  const SentReferralConfirmation({
    required this.decisionId,
    required this.patientRef,
    required this.toMoCode,
    required this.toMoName,
    required this.confirmedAt,
    this.read = false,
  });

  /// Id решения-redirect — ключ для отметки прочтения.
  final String decisionId;
  final String patientRef;

  /// Принимающая больница; имя — фолбэк на код.
  final String toMoCode;
  final String toMoName;

  /// ISO-штамп подтверждения.
  final String confirmedAt;
  final bool read;

  factory SentReferralConfirmation.fromJson(Map<String, dynamic> json) => SentReferralConfirmation(
        decisionId: json['decisionId'] as String? ?? '',
        patientRef: json['patientRef'] as String? ?? '',
        toMoCode: json['toMoCode'] as String? ?? '',
        toMoName: json['toMoName'] as String? ?? json['toMoCode'] as String? ?? '',
        confirmedAt: json['confirmedAt'] as String? ?? '',
        read: json['read'] as bool? ?? false,
      );
}

/// Пациента, направленного моей больницей, выписали с эпикризом (kind прочтения — referral-discharged).
class DischargeReady {
  const DischargeReady({
    required this.decisionId,
    required this.patientRef,
    required this.fromMoCode,
    required this.fromMoName,
    required this.summary,
    required this.dischargedAt,
    this.read = false,
  });

  /// Id решения-redirect — ключ для отметки прочтения.
  final String decisionId;
  final String patientRef;

  /// Больница, которая выписала (принимающая); имя — фолбэк на код.
  final String fromMoCode;
  final String fromMoName;

  /// Текст эпикриза — показывается прямо в пункте колокольчика; '' — не пришёл.
  final String summary;

  /// ISO-штамп выписки.
  final String dischargedAt;
  final bool read;

  factory DischargeReady.fromJson(Map<String, dynamic> json) => DischargeReady(
        decisionId: json['decisionId'] as String? ?? '',
        patientRef: json['patientRef'] as String? ?? '',
        fromMoCode: json['fromMoCode'] as String? ?? '',
        fromMoName: json['fromMoName'] as String? ?? json['fromMoCode'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        dischargedAt: json['dischargedAt'] as String? ?? '',
        read: json['read'] as bool? ?? false,
      );
}

/// Действие пациента моей больницы (kind прочтения — patient-signal).
class PatientEvent {
  const PatientEvent({required this.id, required this.patientRef, required this.kind, this.moCode, this.moName, this.comment, required this.at});

  /// Id записи — ключ для отметки прочтения.
  final String id;
  final String patientRef;

  /// Один из `RouteCodes.patientEventKinds`: request | prefer_current | still_waiting | withdraw | treated_elsewhere |
  /// consent_accepted | consent_declined | scribe_granted | scribe_declined | scribe_withdrawn.
  final String kind;

  /// Больница, о которой просит пациент (у request) или цель перевода (у consent_*); null — нет.
  final String? moCode;
  final String? moName;

  /// Комментарий пациента; null — нет.
  final String? comment;

  /// ISO-штамп действия.
  final String at;

  factory PatientEvent.fromJson(Map<String, dynamic> json) => PatientEvent(
        id: json['id'] as String? ?? '',
        patientRef: json['patientRef'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        moCode: json['moCode'] as String?,
        moName: json['moName'] as String?,
        comment: json['comment'] as String?,
        at: json['at'] as String? ?? '',
      );
}
