import 'route_codes.dart';

// Маршрут как машина состояний (§3.1–§3.2): progress, текущий перевод, последняя неудавшаяся попытка и журнал событий.
// Вынесено из route_models.dart, чтобы файлы оставались < 600 строк; models.dart реэкспортирует этот файл.

/// Состояние маршрута как машины состояний (§3.1) — что с ним сейчас происходит и что эта сторона может сделать.
class RouteProgress {
  const RouteProgress({
    required this.status,
    required this.originMoCode,
    required this.responsibleMoCode,
    required this.responsibleMoName,
    this.transfer,
    this.lastAttempt,
    this.prefersCurrent = false,
    this.closedReason,
    this.closedAt,
    this.overdue = false,
    this.allowed = const [],
    this.blockedMoCodes = const [],
    this.side = RouteCodes.sideNone,
  });

  /// waiting | kept | transfer_pending_consent | transfer_pending_confirmation | transferred | admitted |
  /// withdrawal_requested | closed ([RouteCodes.statuses]); неизвестная строка сохраняется как есть.
  final String status;

  /// Больница, закодированная в patientRef — откуда пациент встал в очередь.
  final String originMoCode;

  /// origin, пока перевод не подтверждён, иначе — принимающая больница (transfer.toMoCode); имя — фолбэк на код.
  final String responsibleMoCode;
  final String responsibleMoName;

  /// Текущий перевод; null — перевода нет или он не состоялся (отказ пациента, отзыв согласия, отмена, отказ больницы,
  /// снятие пациентом до подтверждения). Подтверждённый перевод остаётся здесь и в admitted, и в closed.
  final RouteTransfer? transfer;

  /// Последняя неудавшаяся попытка перевода — для подсказки «уже отказали» (null, если такой не было).
  final RouteTransferAttempt? lastAttempt;

  /// Гражданин попросил остаться в своей больнице; сбрасывается следующим request_redirect.
  final bool prefersCurrent;

  /// discharged | no_show | withdrawn | treated_elsewhere ([RouteCodes.closedReasons]) — только когда status == closed.
  final String? closedReason;

  /// Время закрытия (ISO-штамп), только когда status == closed.
  final String? closedAt;

  /// true — маршрут в статусе transferred и сегодня позже plannedAt + 3 дня (Asia/Almaty).
  final bool overdue;

  /// Что может сделать именно этот вызывающий прямо сейчас ([RouteCodes.actions], по алфавиту) — единственный
  /// источник для показа действий (§4.11): экран показывает кнопку только при `PatientRoute.can(action)`.
  final List<String> allowed;

  /// Больницы, которые нельзя предложить этому маршруту (отказали или их отклонил пациент).
  final List<String> blockedMoCodes;

  /// none | citizen | origin | receiving ([RouteCodes.sides]); none — пользователь другой больницы или без права
  /// referral.confirm.
  final String side;

  factory RouteProgress.fromJson(Map<String, dynamic> json) => RouteProgress(
        status: json['status'] as String? ?? RouteCodes.statusWaiting,
        originMoCode: json['originMoCode'] as String? ?? '',
        responsibleMoCode: json['responsibleMoCode'] as String? ?? '',
        responsibleMoName: json['responsibleMoName'] as String? ?? json['responsibleMoCode'] as String? ?? '',
        transfer: json['transfer'] == null ? null : RouteTransfer.fromJson(json['transfer'] as Map<String, dynamic>),
        lastAttempt: json['lastAttempt'] == null ? null : RouteTransferAttempt.fromJson(json['lastAttempt'] as Map<String, dynamic>),
        prefersCurrent: json['prefersCurrent'] as bool? ?? false,
        closedReason: json['closedReason'] as String?,
        closedAt: json['closedAt'] as String?,
        overdue: json['overdue'] as bool? ?? false,
        allowed: List.unmodifiable((json['allowed'] as List<dynamic>? ?? const []).cast<String>()),
        blockedMoCodes: List.unmodifiable((json['blockedMoCodes'] as List<dynamic>? ?? const []).cast<String>()),
        side: json['side'] as String? ?? RouteCodes.sideNone,
      );
}

/// Перевод, который сейчас определяет маршрут — предложен, ждёт согласия/подтверждения или уже подтверждён (§3.1).
class RouteTransfer {
  const RouteTransfer({
    required this.decisionId,
    required this.toMoCode,
    required this.toMoName,
    this.severe = false,
    this.reason,
    required this.proposedAt,
    this.consentAt,
    this.confirmedAt,
    this.plannedAt,
    this.admittedAt,
  });

  /// Id решения-redirect — ключ для `POST /route/me/consent` и для `/journal/referrals/{id}/…`.
  final String decisionId;
  final String toMoCode;

  /// Имя принимающей больницы; фолбэк — код.
  final String toMoName;

  /// Клиническая отметка врача; для гражданина всегда false.
  final bool severe;

  /// Причина врача, предложившего перевод.
  final String? reason;

  /// ISO-штампы: предложен, пациент согласился, больница подтвердила.
  final String proposedAt;
  final String? consentAt;
  final String? confirmedAt;

  /// `yyyy-MM-dd`; появляется при confirm, меняется при reschedule.
  final String? plannedAt;

  /// ISO-штамп госпитализации (admit).
  final String? admittedAt;

  factory RouteTransfer.fromJson(Map<String, dynamic> json) => RouteTransfer(
        decisionId: json['decisionId'] as String? ?? '',
        toMoCode: json['toMoCode'] as String? ?? '',
        toMoName: json['toMoName'] as String? ?? json['toMoCode'] as String? ?? '',
        severe: json['severe'] as bool? ?? false,
        reason: json['reason'] as String?,
        proposedAt: json['proposedAt'] as String? ?? '',
        consentAt: json['consentAt'] as String?,
        confirmedAt: json['confirmedAt'] as String?,
        plannedAt: json['plannedAt'] as String?,
        admittedAt: json['admittedAt'] as String?,
      );
}

/// Последняя неудавшаяся попытка перевода — подсказка «эта больница уже отказала» (§3.1).
class RouteTransferAttempt {
  const RouteTransferAttempt({required this.outcome, required this.toMoCode, required this.toMoName, required this.at, this.reason});

  /// declined | consent_withdrawn | cancelled | rejected | patient_withdrew ([RouteCodes.attemptOutcomes]). Любая другая
  /// строка (документация и веб упоминают no_show) разбирается как есть: экран берёт запасную подпись, логики на ней нет.
  final String outcome;
  final String toMoCode;

  /// Имя больницы; фолбэк — код.
  final String toMoName;

  /// ISO-штамп события, которым попытка закончилась.
  final String at;
  final String? reason;

  factory RouteTransferAttempt.fromJson(Map<String, dynamic> json) => RouteTransferAttempt(
        outcome: json['outcome'] as String? ?? '',
        toMoCode: json['toMoCode'] as String? ?? '',
        toMoName: json['toMoName'] as String? ?? json['toMoCode'] as String? ?? '',
        at: json['at'] as String? ?? '',
        reason: json['reason'] as String?,
      );
}

/// Одна строка полной истории маршрута (§3.2) — надмножество decisions[]/signals[], самые новые первыми.
class RouteJournalEntry {
  const RouteJournalEntry({
    required this.id,
    required this.at,
    required this.kind,
    required this.role,
    this.moCode,
    this.moName,
    this.reason,
    this.plannedAt,
    this.severe = false,
  });

  /// Id записи журнала; для kind == redirect равен progress.transfer.decisionId, пока этот перевод актуален.
  final String id;

  /// ISO-штамп записи.
  final String at;

  /// Один из [RouteCodes.journalKinds]: request | prefer_current | still_waiting | withdraw | treated_elsewhere | keep |
  /// redirect | consent_accepted | consent_declined | confirm | reject | reschedule | admit | no_show | discharge |
  /// cancel | close.
  final String kind;

  /// Роль автора записи: citizen | doctor | org_admin | …
  final String role;

  /// Целевая больница для request/redirect, своя — для keep, принимающая — для confirm…discharge, цель перевода — для
  /// consent_* и cancel; null для close, still_waiting, prefer_current, withdraw, treated_elsewhere.
  final String? moCode;
  final String? moName;

  /// Причина врача / комментарий гражданина; для discharge — эпикриз персоналу и null гражданину.
  final String? reason;

  /// Только для confirm и reschedule, `yyyy-MM-dd`.
  final String? plannedAt;

  /// Только для redirect; для гражданина всегда false.
  final bool severe;

  factory RouteJournalEntry.fromJson(Map<String, dynamic> json) => RouteJournalEntry(
        id: json['id'] as String? ?? '',
        at: json['at'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        role: json['role'] as String? ?? '',
        moCode: json['moCode'] as String?,
        moName: json['moName'] as String?,
        reason: json['reason'] as String?,
        plannedAt: json['plannedAt'] as String?,
        severe: json['severe'] as bool? ?? false,
      );
}
