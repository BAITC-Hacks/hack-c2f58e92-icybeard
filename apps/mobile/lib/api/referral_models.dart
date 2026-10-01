// Входящие направления принимающей больницы (§3.6 контракта) — вынесены из models.dart, чтобы файлы оставались
// компактными; models.dart реэкспортирует этот файл, импорты экранов не меняются.

/// Строка «голого» массива `GET /api/v1/journal/referrals/incoming` — текущий перевод, нацеленный на мою больницу,
/// ожидающий или подтверждённый (отклонённый, отменённый или отозванный из списка исчезает). Сервер сортирует:
/// severe первыми, затем recordedAt по убыванию. `decisionId` — id решения-redirect, он же `{id}` в путях
/// `/journal/referrals/{id}/…`; `patientRef` уходит в теле каждого действия.
class IncomingReferral {
  const IncomingReferral({
    required this.decisionId,
    required this.patientRef,
    required this.fromMoCode,
    required this.fromMoName,
    required this.profileCode,
    this.reason,
    required this.recordedAt,
    this.severe = false,
    required this.patientConsent,
    this.confirmed = false,
    this.confirmedAt,
    this.discharged = false,
    this.dischargedAt,
    this.status,
    this.plannedAt,
    this.admitted = false,
    this.overdue = false,
    this.allowed = const [],
    this.closedReason,
  });

  final String decisionId;

  /// Реф пациента с больницей очереди (направившей), не моей.
  final String patientRef;

  /// Направившая больница; имя — фолбэк на код.
  final String fromMoCode;
  final String fromMoName;
  final String profileCode;

  /// Причина врача, предложившего перевод.
  final String? reason;

  /// ISO-штамп предложения перевода.
  final String recordedAt;

  /// Клиническая отметка врача, видна только здесь (принимающей стороне).
  final bool severe;

  /// pending | accepted — declined сюда больше не попадает, строка исчезает из списка (§3.6).
  final String patientConsent;

  /// Моя больница подтвердила приём (и когда — ISO-штамп).
  final bool confirmed;
  final String? confirmedAt;

  /// Выписан с эпикризом — только когда closedReason == discharged.
  final bool discharged;
  final String? dischargedAt;

  /// transfer_pending_consent | transfer_pending_confirmation | transferred | admitted | withdrawal_requested | closed
  /// (`RouteCodes.statuses`), как в `progress.status`; null — старый сервер.
  final String? status;

  /// Назначенная моей больницей дата госпитализации, `yyyy-MM-dd`.
  final String? plannedAt;
  final bool admitted;

  /// true — подтверждённый перевод, назначенная дата прошла больше чем на 3 дня.
  final bool overdue;

  /// Что может сделать принимающая сторона прямо сейчас (confirm, reject, reschedule, admit, no_show, discharge,
  /// close) — те же коды, что в `progress.allowed`; пусто, если у пользователя нет своей больницы. Действие close
  /// выполняется на маршруте пациента (`POST /route/{ref}/close`), а не здесь.
  final List<String> allowed;

  /// discharged | no_show | withdrawn | treated_elsewhere (`RouteCodes.closedReasons`), когда status == closed.
  final String? closedReason;

  /// true — [action] сейчас разрешено (см. `allowed`); тот же контракт, что `PatientRoute.can`.
  bool can(String action) => allowed.contains(action);

  factory IncomingReferral.fromJson(Map<String, dynamic> json) => IncomingReferral(
        decisionId: json['decisionId'] as String? ?? '',
        patientRef: json['patientRef'] as String? ?? '',
        fromMoCode: json['fromMoCode'] as String? ?? '',
        fromMoName: json['fromMoName'] as String? ?? json['fromMoCode'] as String? ?? '',
        profileCode: json['profileCode'] as String? ?? '',
        reason: json['reason'] as String?,
        recordedAt: json['recordedAt'] as String? ?? '',
        severe: json['severe'] as bool? ?? false,
        patientConsent: json['patientConsent'] as String? ?? '',
        confirmed: json['confirmed'] as bool? ?? false,
        confirmedAt: json['confirmedAt'] as String?,
        discharged: json['discharged'] as bool? ?? false,
        dischargedAt: json['dischargedAt'] as String?,
        status: json['status'] as String?,
        plannedAt: json['plannedAt'] as String?,
        admitted: json['admitted'] as bool? ?? false,
        overdue: json['overdue'] as bool? ?? false,
        allowed: List.unmodifiable((json['allowed'] as List<dynamic>? ?? const []).cast<String>()),
        closedReason: json['closedReason'] as String?,
      );
}
